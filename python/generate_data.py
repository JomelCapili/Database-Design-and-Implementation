#!/usr/bin/env python3
"""
generate_data.py - synthetic data generator for the Service Management DB (v2)

Simulates two years (2024-01-01 -> 2025-12-31) of day-by-day operations for an
independent auto repair shop in Las Vegas, NV:

  * customers arrive (new + returning) and book appointments or walk in
  * appointments can no-show or cancel; popular slots get overbooked
  * each visit becomes a work order with labor lines and parts lines
  * parts come out of a simulated inventory with reorder points, supplier
    lead times and special orders when the shelf is empty
  * technicians have different speeds (efficiency) and comeback (rework) rates
  * completed jobs are invoiced, paid, and sometimes reviewed (1-5 stars)
  * whether a customer comes back depends on how their last visit went

Everything uses a fixed random seed, so the output is fully reproducible.
Only the Python standard library is used.

Outputs
  sql/02_seed_data.sql    INSERT statements for MySQL 8 (run after 01_schema.sql)
  data/raw/<table>.csv    one CSV per table (for Excel / Power BI / Tableau)

Usage
  python3 python/generate_data.py
"""

import csv
import math
import random
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

SEED = 2021                      # the year the original project was written
rng = random.Random(SEED)

ROOT = Path(__file__).resolve().parents[1]
SQL_OUT = ROOT / "sql" / "02_seed_data.sql"
CSV_DIR = ROOT / "data" / "raw"

START = date(2024, 1, 1)
END = date(2025, 12, 31)
SNAPSHOT = datetime(2025, 12, 31, 12, 0)      # "as of" moment: noon on the last day
BOOKING_HORIZON = END + timedelta(days=21)     # future appointments already booked

TAX_RATE = Decimal("0.08375")                  # Clark County, NV sales tax (parts only)
LABOR_RATE = {2024: Decimal("140.00"), 2025: Decimal("150.00")}
CENT = Decimal("0.01")

HOLIDAYS = {
    date(2024, 1, 1), date(2024, 5, 27), date(2024, 7, 4), date(2024, 9, 2),
    date(2024, 11, 28), date(2024, 12, 25), date(2025, 1, 1), date(2025, 5, 26),
    date(2025, 7, 4), date(2025, 9, 1), date(2025, 11, 27), date(2025, 12, 25),
    date(2026, 1, 1),
}

# Monthly demand seasonality (Las Vegas: summer heat drives A/C, battery, cooling work)
VOLUME_SEASON = [0.92, 0.93, 1.00, 1.00, 1.04, 1.12, 1.15, 1.12, 1.02, 0.98, 0.93, 0.86]
CATEGORY_SEASON = {
    "Climate Control": [0.30, 0.30, 0.60, 1.00, 1.80, 2.80, 3.20, 3.00, 1.80, 0.80, 0.40, 0.30],
    "Cooling":         [0.60, 0.60, 0.80, 1.00, 1.30, 1.70, 1.90, 1.80, 1.30, 0.90, 0.70, 0.60],
}
BATTERY_SEASON = [0.80, 0.70, 0.80, 0.90, 1.30, 1.90, 2.30, 2.20, 1.60, 1.00, 0.90, 1.00]


def money(x) -> Decimal:
    return Decimal(str(x)).quantize(CENT, rounding=ROUND_HALF_UP)


def hrs(x) -> Decimal:
    """Round hours to the nearest 0.05 (3-minute increments, like a time clock)."""
    return (Decimal(str(round(x * 20) / 20))).quantize(CENT)


# =============================================================================
# Business calendar helpers
# =============================================================================
def open_hours(d: date):
    """(open, close) datetimes for a day, or None when the shop is closed."""
    if d in HOLIDAYS or d.weekday() == 6:
        return None
    if d.weekday() == 5:
        return datetime.combine(d, time(8, 0)), datetime.combine(d, time(14, 0))
    return datetime.combine(d, time(7, 30)), datetime.combine(d, time(17, 30))


def next_open_day(d: date) -> date:
    d += timedelta(days=1)
    while open_hours(d) is None:
        d += timedelta(days=1)
    return d


def roll_to_open_day(d: date) -> date:
    while open_hours(d) is None:
        d += timedelta(days=1)
    return d


def add_business_hours(start: datetime, hours: float) -> datetime:
    """Advance a timestamp by N working hours, skipping nights, Sundays and holidays."""
    remaining = hours * 60.0
    cur = start
    while True:
        oh = open_hours(cur.date())
        if oh is None or cur >= oh[1]:
            cur = open_hours(next_open_day(cur.date()))[0]
            continue
        if cur < oh[0]:
            cur = oh[0]
        available = (oh[1] - cur).total_seconds() / 60.0
        if remaining <= available:
            return cur + timedelta(minutes=remaining)
        remaining -= available
        cur = open_hours(next_open_day(cur.date()))[0]


def pick(weighted):
    """weighted: list of (item, weight) -> item"""
    total = sum(w for _, w in weighted)
    r = rng.random() * total
    for item, w in weighted:
        r -= w
        if r <= 0:
            return item
    return weighted[-1][0]


def poisson(lam: float) -> int:
    l, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= l:
            return k
        k += 1


def year_frac(d: date) -> float:
    """0.0 on 2024-01-01 -> 1.0 on 2025-12-31 (for gradual trends)."""
    return min(1.0, max(0.0, (d - START).days / (END - START).days))


# =============================================================================
# Reference data
# =============================================================================
SUPPLIERS = [
    # id, name, phone, quoted lead days, avg extra days actually taken
    (1, "Desert Auto Parts Supply",     "(702) 555-0142", 1, 0.2),
    (2, "Silver State Distributors",    "(702) 555-0187", 2, 0.3),
    (3, "Mojave Drivetrain Co.",        "(725) 555-0119", 5, 1.0),
    (4, "Summit Electrical Components", "(702) 555-0163", 3, 1.7),
    (5, "Red Rock Climate & Cooling",   "(702) 555-0128", 5, 1.2),
    (6, "Valley Fluids & Filters",      "(725) 555-0171", 1, 0.1),
]
SUPPLIER_BY_ID = {s[0]: s for s in SUPPLIERS}
# 2025 supplier cost increases (shelf prices only rose ~4%, squeezing parts margin)
COST_INCREASE_2025 = {1: 1.05, 2: 1.06, 3: 1.05, 4: 1.09, 5: 1.07, 6: 1.04}
PRICE_INCREASE_2025 = 1.04

# part_id, sku, name, category, supplier_id, unit_cost_2024, unit_price_2024, reorder_point, reorder_qty
PARTS = [
    (1,  "FL-0W20-QT",  "Full Synthetic Motor Oil 0W-20 (1 qt)", "Fluids", 6, 5.10, 9.99, 60, 200),
    (2,  "FL-5W30-QT",  "Full Synthetic Motor Oil 5W-30 (1 qt)", "Fluids", 6, 5.10, 9.99, 60, 200),
    (3,  "FL-ATF-QT",   "ATF Multi-Vehicle (1 qt)", "Fluids", 6, 6.20, 12.99, 24, 60),
    (4,  "FL-COOL-GAL", "Extended Life Coolant 50/50 (1 gal)", "Fluids", 6, 11.50, 24.99, 12, 36),
    (5,  "FL-DOT4",     "DOT 4 Brake Fluid (32 oz)", "Fluids", 6, 9.40, 19.99, 8, 24),
    (6,  "FL-R134A",    "R-134a Refrigerant (12 oz)", "Fluids", 6, 14.00, 34.99, 12, 36),
    (7,  "FL-R1234YF",  "R-1234yf Refrigerant (8 oz)", "Fluids", 6, 38.00, 89.99, 8, 24),
    (8,  "FL-FUELCLN",  "Fuel Injection Cleaning Kit", "Fluids", 6, 18.00, 44.99, 6, 18),
    (9,  "FI-OIL-STD",  "Oil Filter - Spin-On", "Filters", 6, 4.20, 11.99, 40, 120),
    (10, "FI-OIL-CART", "Oil Filter - Cartridge (European)", "Filters", 6, 9.50, 22.99, 10, 30),
    (11, "FI-AIR",      "Engine Air Filter", "Filters", 2, 9.80, 27.99, 12, 36),
    (12, "FI-CABIN",    "Cabin Air Filter", "Filters", 2, 8.60, 29.99, 12, 36),
    (13, "FI-FUEL",     "In-Line Fuel Filter", "Filters", 2, 14.00, 36.99, 3, 8),
    (14, "BR-PAD-F",    "Ceramic Brake Pads - Front (set)", "Brakes", 2, 32.00, 79.99, 4, 12),
    (15, "BR-PAD-R",    "Ceramic Brake Pads - Rear (set)", "Brakes", 2, 28.00, 69.99, 6, 18),
    (16, "BR-ROT-F",    "Brake Rotor - Front (each)", "Brakes", 2, 41.00, 94.99, 2, 8),     # under-stocked
    (17, "BR-HW-KIT",   "Brake Hardware Kit", "Brakes", 2, 7.50, 19.99, 8, 24),
    (18, "EL-BAT-24F",  "AGM Battery - Group 24F", "Electrical System", 4, 145.00, 249.99, 2, 5),  # under-stocked
    (19, "EL-BAT-H6",   "AGM Battery - Group H6/48", "Electrical System", 4, 160.00, 269.99, 2, 5),  # under-stocked
    (20, "EL-ALT",      "Alternator (Remanufactured)", "Electrical System", 4, 165.00, 329.99, 1, 2),
    (21, "EL-STARTER",  "Starter Motor (Remanufactured)", "Electrical System", 4, 120.00, 259.99, 1, 3),
    (22, "EL-COIL",     "Ignition Coil", "Electrical System", 4, 38.00, 89.99, 6, 16),
    (23, "EL-PLUG-IR",  "Iridium Spark Plug (each)", "Electrical System", 4, 8.50, 19.99, 24, 64),
    (24, "EL-O2",       "Oxygen Sensor", "Electrical System", 4, 45.00, 119.99, 3, 8),
    (25, "AC-COMP",     "A/C Compressor Assembly", "Climate Control", 5, 310.00, 649.99, 1, 2),  # under-stocked
    (26, "AC-DRIER",    "A/C Receiver Drier / Accumulator", "Climate Control", 5, 32.00, 79.99, 3, 6),
    (27, "AC-DYE",      "UV Leak Detection Dye", "Climate Control", 5, 6.00, 17.99, 6, 24),
    (28, "AC-COND",     "A/C Condenser", "Climate Control", 5, 145.00, 319.99, 1, 2),
    (29, "CL-WPUMP",    "Water Pump", "Cooling System", 5, 85.00, 199.99, 2, 4),
    (30, "CL-RAD",      "Radiator", "Cooling System", 5, 160.00, 349.99, 1, 3),
    (31, "CL-TSTAT",    "Thermostat & Gasket", "Cooling System", 5, 22.00, 54.99, 3, 8),
    (32, "CL-HOSE",     "Radiator Hose Kit", "Cooling System", 5, 28.00, 64.99, 3, 6),
    (33, "EN-TBELT",    "Timing Belt Kit", "Engine", 1, 210.00, 449.99, 1, 2),
    (34, "EN-VCG",      "Valve Cover Gasket Set", "Engine", 1, 26.00, 64.99, 3, 6),
    (35, "EN-SERP",     "Serpentine Belt", "Engine", 1, 24.00, 54.99, 4, 10),
    (36, "EN-MOUNT",    "Engine Mount", "Engine", 1, 55.00, 129.99, 2, 4),
    (37, "CH-STRUT",    "Strut Assembly - Front (each)", "Chassis", 1, 95.00, 219.99, 2, 6),
    (38, "CH-CARM",     "Control Arm w/ Ball Joint", "Chassis", 1, 68.00, 159.99, 2, 4),
    (39, "CH-TIEROD",   "Outer Tie Rod End", "Chassis", 1, 22.00, 54.99, 3, 8),
    (40, "CH-SWAYLNK",  "Sway Bar Link", "Chassis", 1, 18.00, 44.99, 4, 10),
    (41, "EX-CAT",      "Catalytic Converter (Direct-Fit)", "Exhaust System", 1, 380.00, 799.99, 0, 0),
    (42, "EX-MUFF",     "Muffler", "Exhaust System", 1, 85.00, 189.99, 1, 2),
    (43, "EX-GASKET",   "Exhaust Gasket Kit", "Exhaust System", 1, 12.00, 29.99, 4, 10),
    (44, "FS-PUMP",     "Fuel Pump Module", "Fuel System", 1, 180.00, 389.99, 1, 2),
    (45, "FS-INJ",      "Fuel Injector (each)", "Fuel System", 1, 55.00, 129.99, 4, 8),
    (46, "TR-FILTER",   "Transmission Filter & Gasket Kit", "Transmission", 3, 24.00, 59.99, 3, 8),
    (47, "TR-CLUTCH",   "Clutch Kit", "Transmission", 3, 240.00, 499.99, 0, 0),
    (48, "TR-REBUILD",  "Transmission Rebuild Kit", "Transmission", 3, 420.00, 899.99, 0, 0),
    (49, "TR-SOLENOID", "Shift Solenoid", "Transmission", 3, 65.00, 149.99, 1, 2),
]
PART_BY_ID = {p[0]: p for p in PARTS}
PART_ID_BY_SKU = {p[1]: p[0] for p in PARTS}


def part_cost_price(part_id: int, on: date):
    p = PART_BY_ID[part_id]
    cost, price = p[5], p[6]
    if on.year >= 2025:
        cost *= COST_INCREASE_2025[p[4]]
        price *= PRICE_INCREASE_2025
    return money(cost), money(price)


# --- parts rules that depend on the vehicle ----------------------------------
def oil_parts(v):
    qts = 6 if v["body"] in ("Truck", "SUV") else 5
    if v["region"] == "European":
        qts += 1
    oil = "FL-5W30-QT" if (v["body"] == "Truck" or v["region"] == "Domestic") else "FL-0W20-QT"
    filt = "FI-OIL-CART" if v["region"] == "European" else "FI-OIL-STD"
    return [(oil, qts), (filt, 1)]


def refrigerant(v, cans=2):
    return [("FL-R1234YF" if v["year"] >= 2015 else "FL-R134A", cans)]


def battery(v):
    return [("EL-BAT-H6" if v["body"] in ("Truck", "SUV") or v["region"] == "European" else "EL-BAT-24F", 1)]


def plugs(v):
    return [("EL-PLUG-IR", 8 if v["body"] == "Truck" else (6 if v["body"] in ("SUV", "Van") else 4))]


# service_type_id, name, category, book_hours, base weight as the primary job, parts rule
# parts rule: list of (sku, qty, probability) or a function(vehicle) -> list of (sku, qty)
SERVICES = [
    (1,  "Synthetic Oil Change",            "Maintenance",           0.40, 26.0, oil_parts),
    (2,  "Tire Rotation & Balance",         "Maintenance",           0.60, 5.0,  []),
    (3,  "Multi-Point Inspection",          "Diagnostics",           0.50, 3.0,  []),
    (4,  "Air & Cabin Filter Replacement",  "Maintenance",           0.30, 3.0,  [("FI-AIR", 1, 1.0), ("FI-CABIN", 1, 0.8)]),
    (5,  "Coolant Flush",                   "Cooling",               1.00, 2.5,  [("FL-COOL-GAL", 2, 1.0)]),
    (6,  "Transmission Fluid Service",      "Transmission",          1.20, 2.0,  [("FL-ATF-QT", 6, 1.0), ("TR-FILTER", 1, 0.6)]),
    (7,  "Front Brake Pads & Rotors",       "Brakes",                1.80, 7.0,  [("BR-PAD-F", 1, 1.0), ("BR-ROT-F", 2, 1.0), ("BR-HW-KIT", 1, 0.7)]),
    (8,  "Rear Brake Pads",                 "Brakes",                1.20, 4.0,  [("BR-PAD-R", 1, 1.0), ("BR-HW-KIT", 1, 0.5)]),
    (9,  "Brake Fluid Flush",               "Brakes",                0.80, 2.0,  [("FL-DOT4", 1, 1.0)]),
    (10, "Check Engine Light Diagnosis",    "Diagnostics",           1.00, 6.0,  []),
    (11, "Electrical System Diagnosis",     "Diagnostics",           1.50, 2.0,  []),
    (12, "Battery Replacement",             "Electrical",            0.40, 5.0,  battery),
    (13, "Alternator Replacement",          "Electrical",            2.00, 1.5,  [("EL-ALT", 1, 1.0), ("EN-SERP", 1, 0.4)]),
    (14, "Starter Replacement",             "Electrical",            1.80, 1.2,  [("EL-STARTER", 1, 1.0)]),
    (15, "A/C Recharge & Leak Test",        "Climate Control",       1.00, 4.0,  lambda v: refrigerant(v) + [("AC-DYE", 1)]),
    (16, "A/C Compressor Replacement",      "Climate Control",       3.50, 0.8,  lambda v: [("AC-COMP", 1), ("AC-DRIER", 1)] + refrigerant(v)),
    (17, "A/C Condenser Replacement",       "Climate Control",       2.50, 0.4,  lambda v: [("AC-COND", 1), ("AC-DRIER", 1)] + refrigerant(v)),
    (18, "Water Pump Replacement",          "Cooling",               3.00, 1.0,  [("CL-WPUMP", 1, 1.0), ("FL-COOL-GAL", 2, 1.0)]),
    (19, "Radiator Replacement",            "Cooling",               2.50, 0.8,  [("CL-RAD", 1, 1.0), ("CL-HOSE", 1, 0.5), ("FL-COOL-GAL", 2, 1.0)]),
    (20, "Thermostat Replacement",          "Cooling",               1.20, 1.0,  [("CL-TSTAT", 1, 1.0), ("FL-COOL-GAL", 1, 1.0)]),
    (21, "Spark Plug Replacement",          "Engine",                1.20, 2.5,  plugs),
    (22, "Ignition Coil Replacement",       "Engine",                0.80, 1.5,  [("EL-COIL", 1, 1.0)]),
    (23, "Timing Belt Replacement",         "Engine",                4.50, 0.8,  [("EN-TBELT", 1, 1.0)]),
    (24, "Valve Cover Gasket Replacement",  "Engine",                2.20, 1.2,  [("EN-VCG", 1, 1.0)]),
    (25, "Serpentine Belt Replacement",     "Engine",                0.60, 1.2,  [("EN-SERP", 1, 1.0)]),
    (26, "Oxygen Sensor Replacement",       "Exhaust",               0.80, 1.2,  [("EL-O2", 1, 1.0)]),
    (27, "Wheel Alignment",                 "Suspension & Steering", 1.00, 3.0,  []),
    (28, "Front Strut Replacement",         "Suspension & Steering", 3.00, 1.2,  [("CH-STRUT", 2, 1.0)]),
    (29, "Control Arm Replacement",         "Suspension & Steering", 2.00, 1.0,  [("CH-CARM", 1, 1.0), ("CH-TIEROD", 1, 0.3)]),
    (30, "Catalytic Converter Replacement", "Exhaust",               2.00, 0.6,  [("EX-CAT", 1, 1.0), ("EX-GASKET", 1, 1.0)]),
    (31, "Muffler Replacement",             "Exhaust",               1.20, 0.6,  [("EX-MUFF", 1, 1.0), ("EX-GASKET", 1, 1.0)]),
    (32, "Fuel Injection Service",          "Fuel System",           1.00, 1.5,  [("FL-FUELCLN", 1, 1.0)]),
    (33, "Fuel Pump Replacement",           "Fuel System",           3.00, 0.6,  [("FS-PUMP", 1, 1.0), ("FI-FUEL", 1, 0.4)]),
    (34, "Clutch Replacement",              "Transmission",          6.00, 0.4,  [("TR-CLUTCH", 1, 1.0)]),
    (35, "Transmission Rebuild",            "Transmission",          10.0, 0.25, [("TR-REBUILD", 1, 1.0), ("FL-ATF-QT", 10, 1.0), ("TR-SOLENOID", 1, 0.5)]),
    (36, "Engine Mount Replacement",        "Engine",                2.00, 0.6,  [("EN-MOUNT", 1, 1.0)]),
    (37, "Sway Bar Link Replacement",       "Suspension & Steering", 0.80, 0.8,  [("CH-SWAYLNK", 2, 1.0)]),
    (38, "Fuel Injector Replacement",       "Fuel System",           2.50, 0.5,  [("FS-INJ", 1, 1.0)]),
]
SERVICE_BY_ID = {s[0]: s for s in SERVICES}
MAINTENANCE_IDS = {1, 2, 3, 4, 5, 6, 9, 27, 32}
ADDON_IDS = [2, 4, 3, 9, 27, 32]
DIAG_FOLLOWUPS = {10: [22, 26, 21, 30, 20, 32, 24], 11: [12, 13, 14]}

MECHANICS = [
    # id, first, last, phone, skill, wage, hire, termination, efficiency(start, end), rework rate
    (1, "Marcus", "Reyes",    "(702) 555-0110", "Master Technician", 44.00, date(2014, 3, 10), None,             (1.17, 1.17), 0.012),
    (2, "Dana",   "Whitfield", "(702) 555-0111", "Master Technician", 42.00, date(2016, 7, 18), None,             (1.12, 1.12), 0.015),
    (3, "Luis",   "Navarro",  "(725) 555-0112", "Technician",        33.00, date(2019, 2, 4),  None,             (1.03, 1.03), 0.022),
    (4, "Priya",  "Shah",     "(702) 555-0113", "Technician",        32.00, date(2020, 9, 14), None,             (1.06, 1.06), 0.018),
    (5, "Tyler",  "Brooks",   "(702) 555-0114", "Technician",        30.00, date(2021, 5, 3),  date(2025, 5, 16), (0.95, 0.95), 0.070),
    (6, "Kevin",  "Tran",     "(725) 555-0115", "Apprentice",        22.00, date(2023, 8, 21), None,             (0.74, 0.94), 0.040),
    (7, "Jordan", "Kim",      "(702) 555-0116", "Apprentice",        20.00, date(2025, 6, 2),  None,             (0.70, 0.83), 0.035),
]
MECH_BY_ID = {m[0]: m for m in MECHANICS}

MAKES = {
    # make: (weight, WMI prefixes, region, [(model, body, weight)])
    "Toyota":        (15, ["4T1", "5TD", "JTD", "5TF", "2T1"], "Asian",    [("Camry", "Car", 5), ("Corolla", "Car", 4), ("RAV4", "SUV", 4), ("Tacoma", "Truck", 3), ("Highlander", "SUV", 2), ("Tundra", "Truck", 2), ("Prius", "Car", 1), ("Sienna", "Van", 1)]),
    "Honda":         (11, ["1HG", "2HG", "5J6", "5FN"], "Asian",           [("Civic", "Car", 5), ("Accord", "Car", 5), ("CR-V", "SUV", 4), ("Pilot", "SUV", 2), ("Odyssey", "Van", 1.5)]),
    "Ford":          (12, ["1FA", "1FM", "1FT", "3FA"], "Domestic",        [("F-150", "Truck", 6), ("Escape", "SUV", 3), ("Explorer", "SUV", 3), ("Fusion", "Car", 2), ("Focus", "Car", 2), ("Mustang", "Car", 1.5), ("Expedition", "SUV", 1)]),
    "Chevrolet":     (11, ["1G1", "1GN", "1GC", "2GN"], "Domestic",        [("Silverado 1500", "Truck", 5), ("Equinox", "SUV", 3), ("Malibu", "Car", 3), ("Tahoe", "SUV", 2), ("Impala", "Car", 1.5), ("Traverse", "SUV", 1.5), ("Cruze", "Car", 1.5)]),
    "Nissan":        (9,  ["1N4", "5N1", "1N6", "3N1"], "Asian",           [("Altima", "Car", 5), ("Sentra", "Car", 3), ("Rogue", "SUV", 4), ("Frontier", "Truck", 1.5), ("Maxima", "Car", 1), ("Pathfinder", "SUV", 1.5)]),
    "Hyundai":       (6,  ["KMH", "5NP", "5NM"], "Asian",                  [("Elantra", "Car", 4), ("Sonata", "Car", 3), ("Tucson", "SUV", 3), ("Santa Fe", "SUV", 2)]),
    "Kia":           (5,  ["KNA", "5XY", "KND"], "Asian",                  [("Optima", "Car", 3), ("Forte", "Car", 3), ("Sorento", "SUV", 3), ("Soul", "Car", 2), ("Sportage", "SUV", 2)]),
    "Jeep":          (5,  ["1C4", "1J4"], "Domestic",                      [("Wrangler", "SUV", 3), ("Grand Cherokee", "SUV", 4), ("Cherokee", "SUV", 2), ("Compass", "SUV", 1)]),
    "Ram":           (4,  ["1C6", "3C6"], "Domestic",                      [("1500", "Truck", 5), ("2500", "Truck", 1.5)]),
    "Dodge":         (4,  ["2C3", "1C3", "2C4"], "Domestic",               [("Charger", "Car", 3), ("Durango", "SUV", 2), ("Grand Caravan", "Van", 2), ("Challenger", "Car", 1.5)]),
    "GMC":           (3,  ["1GT", "1GK"], "Domestic",                      [("Sierra 1500", "Truck", 4), ("Yukon", "SUV", 2), ("Acadia", "SUV", 2), ("Terrain", "SUV", 1.5)]),
    "Subaru":        (2.5, ["4S3", "4S4", "JF1"], "Asian",                 [("Outback", "SUV", 3), ("Forester", "SUV", 3), ("Impreza", "Car", 1.5), ("Crosstrek", "SUV", 1.5)]),
    "Mazda":         (3,  ["JM1", "JM3", "3MZ"], "Asian",                  [("Mazda3", "Car", 3), ("CX-5", "SUV", 4), ("Mazda6", "Car", 1.5), ("CX-9", "SUV", 1)]),
    "Lexus":         (3,  ["JTH", "2T2", "JTJ"], "Luxury Asian",           [("RX 350", "SUV", 4), ("ES 350", "Car", 3), ("IS 250", "Car", 1.5), ("GX 460", "SUV", 1)]),
    "BMW":           (3,  ["WBA", "5UX", "WBS"], "European",               [("3 Series", "Car", 4), ("X3", "SUV", 3), ("X5", "SUV", 3), ("5 Series", "Car", 2)]),
    "Mercedes-Benz": (3,  ["WDD", "WDC", "55S", "4JG"], "European",        [("C-Class", "Car", 4), ("E-Class", "Car", 2.5), ("GLC", "SUV", 2.5), ("GLE", "SUV", 2)]),
    "Volkswagen":    (2.5, ["3VW", "1VW", "WVW", "WVG"], "European",       [("Jetta", "Car", 4), ("Passat", "Car", 2), ("Tiguan", "SUV", 2.5), ("Atlas", "SUV", 1)]),
    "Audi":          (1.8, ["WAU", "WA1"], "European",                     [("A4", "Car", 3), ("Q5", "SUV", 3), ("A6", "Car", 1.5), ("Q7", "SUV", 1)]),
    "Chrysler":      (1.5, ["2C3", "1C3"], "Domestic",                     [("300", "Car", 3), ("Pacifica", "Van", 2)]),
    "Buick":         (1.2, ["1G4", "KL4", "5GA"], "Domestic",              [("Enclave", "SUV", 2), ("Encore", "SUV", 2), ("LaCrosse", "Car", 1)]),
}
HOURS_FACTOR = {"European": 1.25, "Luxury Asian": 1.10, "Domestic": 1.00, "Asian": 1.00}

FIRST_NAMES = """James Mary Robert Patricia John Jennifer Michael Linda David Elizabeth William Barbara
Richard Susan Joseph Jessica Thomas Sarah Christopher Karen Daniel Lisa Matthew Nancy Anthony Betty Mark
Sandra Donald Ashley Steven Kimberly Andrew Emily Paul Donna Joshua Michelle Kenneth Carol Kevin Amanda
Brian Melissa George Deborah Timothy Stephanie Ronald Rebecca Jason Sharon Edward Laura Jeffrey Cynthia
Ryan Dorothy Jacob Amy Gary Kathleen Nicholas Angela Eric Shirley Jonathan Brenda Stephen Emma Larry Anna
Justin Pamela Scott Nicole Brandon Samantha Benjamin Katherine Samuel Christine Gregory Debra Alexander
Rachel Patrick Carolyn Frank Janet Raymond Maria Jack Olivia Dennis Heather Jerry Helen Tyler Catherine
Aaron Diane Jose Julie Adam Victoria Nathan Joyce Henry Lauren Zachary Kelly Douglas Christina Peter Ruth
Kyle Joan Noah Virginia Ethan Judith Jeremy Evelyn Christian Hannah Walter Andrea Keith Megan Austin Cheryl
Roger Jacqueline Terry Madison Sean Teresa Gerald Abigail Carl Sophia Dylan Martha Harold Sara Jordan Gloria
Jesse Janice Bryan Kathryn Lawrence Ann Arthur Isabella Gabriel Judy Bruce Charlotte Logan Julia Billy Grace
Joe Amber Alan Alice Juan Jean Elijah Denise Willie Frances Albert Danielle Wayne Marilyn Randy Natalie Mason
Beverly Vincent Diana Liam Brittany Roy Theresa Bobby Kayla Caleb Alexis Bradley Doris Russell Lori Lucas
Tiffany Carlos Miguel Luis Sofia Ana Diego Camila Mateo Valeria Andres Lucia Jorge Elena Ricardo Gabriela
Wei Mei Hiroshi Yuki Minh Linh Arjun Priya Rahul Anjali Kwame Amara Tariq Leila Omar Fatima Mohammed Aisha
Malik Imani Darnell Keisha Andre Tamika Marcus Jasmine Manuel Rosa""".split()

LAST_NAMES = """Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez
Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin Lee Perez Thompson White Harris Sanchez Clark
Ramirez Lewis Robinson Walker Young Allen King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson
Baker Hall Rivera Campbell Mitchell Carter Roberts Gomez Phillips Evans Turner Diaz Parker Cruz Edwards
Collins Reyes Stewart Morris Morales Murphy Cook Rogers Gutierrez Ortiz Morgan Cooper Peterson Bailey Reed
Kelly Howard Ramos Kim Cox Ward Richardson Watson Brooks Chavez Wood James Bennett Gray Mendoza Ruiz Hughes
Price Alvarez Castillo Sanders Patel Myers Long Ross Foster Jimenez Powell Jenkins Perry Russell Sullivan
Bell Coleman Butler Henderson Barnes Gonzales Fisher Vasquez Simmons Romero Jordan Patterson Alexander
Hamilton Graham Reynolds Griffin Wallace Moreno West Cole Hayes Bryant Herrera Gibson Ellis Tran Medina
Aguilar Stevens Murray Ford Castro Marshall Owens Harrison Fernandez McDonald Woods Washington Kennedy Wells
Vargas Henry Chen Freeman Webb Tucker Guzman Burns Crawford Olson Simpson Porter Hunter Gordon Mendez Silva
Shaw Snyder Mason Dixon Munoz Hunt Hicks Holmes Palmer Wagner Black Robertson Boyd Rose Stone Salazar Fox
Warren Mills Meyer Rice Schmidt Garza Daniels Ferguson Nichols Stephens Soto Weaver Ryan Gardner Payne Grant
Dunn Kelley Spencer Hawkins Arnold Pierce Vazquez Hansen Peters Santos Hart Bradley Knight Elliott Cunningham
Duncan Armstrong Hudson Carroll Lane Riley Andrews Alvarado Ray Delgado Berry Perkins Hoffman Johnston
Matthews Pena Richards Contreras Willis Carpenter Lawrence Sandoval Guerrero George Chapman Rios Estrada
Ortega Watkins Greene Nunez Wheeler Valdez Harper Burke Larson Santiago Maldonado Morrison Franklin Carlson
Austin Dominguez Carr Lawson Jacobs Obrien Lynch Singh Vega Bishop Montgomery Oliver Jensen Harvey Williamson
Gilbert Dean Sims Espinoza Howell Li Wong Reid Hanson Le McCoy Garrett Burton Fuller Wang Weber Welch Rojas
Lucas Marquez Fields Park Yang Little Banks Padilla Day Walsh Bowman Schultz Luna Fowler Mejia Davidson
Acosta Brewer May Holland Juarez Newman Pearson Curtis Cortez Douglas Schneider Joseph Barrett Navarro Figueroa
Keller Avila Wade Molina Stanley Hopkins Campos Barnett Bates Chambers Caldwell Beck Lambert Miranda Byrd
Craig Ayala Lowe Frazier Powers Neal Leonard Gregory Carrillo Sutton Fleming Rhodes Shelton Schwartz Norris
Jennings Watts Duran Walters Cohen McDaniel Moran Parks Steele Vaughn Becker Holt Deleon Barker Terry Hale
Leon Hail Benson Haynes Horton Miles Lyons Pham Graves Bush Thornton Wolfe Warner Cabrera McKinney Mann
Zimmerman Dawson Lara Fletcher Page McCarthy Love Robles Cervantes Solis Erickson Reeves Chang Klein Salinas
Fuentes Baldwin Daniel Simon Velasquez Hardy Higgins Aguirre Lin Cummings Chandler Sharp Barber Bowen Ochoa
Dennis Robbins Liu Ramsey Francis Griffith Paul Blair Oconnor Cardenas Pacheco Cross Calderon Quinn Moss
Swanson Chan Rivas Khan Rodgers Serrano Fitzgerald Rosales Stevenson Christensen Manning Gill Curry McLaughlin
Harmon McGee Gross Doyle Garner Newton Burgess Reese Walton Blake Trujillo Adkins Brady Goodman Roman Webster
Goodwin Fischer Huang Potter Delacruz Montoya Todd Wu Hines Mullins Castaneda Malone Cannon Tate Mack Sherman
Hubbard Hodges Zhang Guerra Wolf Valencia Saunders Franco Rowe Gallagher Farmer Hammond Hampton Townsend
Ingram Wise Gallegos Clarke Barton Schroeder Maxwell Waters Logan Camacho Strickland Norman Person Colon
Parsons Frank Harrington Glover Osborne Buchanan Casey Floyd Patton Ibarra Ball Tyler Suarez Bowers Orozco
Salas Cobb Gibbs Andrade Bauer Conner Moody Escobar McGuire Lloyd Mueller Hartman French Kramer McBride""".split()

FLEET_TRADES = ["Plumbing", "Landscaping", "HVAC Services", "Electric", "Courier Services",
                "Pool Service", "Property Management", "Construction", "Pest Control", "Mobile Detailing"]

ZIP_WEIGHTS = [  # shop sits in the southwest valley, so nearby ZIPs dominate
    ("89118", 10), ("89113", 10), ("89139", 9), ("89148", 9), ("89147", 8), ("89117", 6), ("89103", 6),
    ("89102", 4), ("89146", 5), ("89123", 6), ("89183", 4), ("89141", 5), ("89178", 6), ("89179", 3),
    ("89052", 3), ("89074", 3), ("89014", 2), ("89012", 2), ("89119", 3), ("89120", 2), ("89121", 2),
    ("89109", 2), ("89107", 2), ("89108", 2), ("89128", 2), ("89129", 2), ("89130", 1.5), ("89131", 1.5),
    ("89134", 1.5), ("89135", 2.5), ("89138", 1.5), ("89144", 2), ("89145", 2), ("89149", 1.5),
    ("89166", 1), ("89031", 1), ("89032", 1), ("89081", 0.8), ("89084", 0.8), ("89086", 0.5),
    ("89015", 1), ("89011", 0.8), ("89002", 0.8), ("89101", 1), ("89104", 1.2), ("89106", 1),
    ("89110", 1), ("89115", 0.8), ("89122", 1), ("89142", 0.8), ("89156", 0.6),
]

CHANNELS = [("Walk-in", 18), ("Google Search", 32), ("Referral", 20), ("Yelp", 12),
            ("Social Media", 10), ("Fleet Account", 8)]
RETURN_BASE = {"Referral": 0.76, "Fleet Account": 0.93, "Walk-in": 0.58,
               "Google Search": 0.64, "Yelp": 0.57, "Social Media": 0.55}

SLOTS_WEEKDAY = [((7, 30), 11), ((8, 0), 16), ((8, 30), 9), ((9, 0), 9), ((9, 30), 7), ((10, 0), 7),
                 ((10, 30), 6), ((11, 0), 6), ((11, 30), 4), ((12, 0), 3), ((12, 30), 3), ((13, 0), 4),
                 ((13, 30), 4), ((14, 0), 4), ((14, 30), 3), ((15, 0), 3), ((15, 30), 2)]
SLOTS_SATURDAY = [((8, 0), 14), ((8, 30), 8), ((9, 0), 8), ((9, 30), 6), ((10, 0), 6),
                  ((10, 30), 5), ((11, 0), 4), ((11, 30), 3), ((12, 0), 2)]

COMMENTS = {
    5: ["Great service and a fair price.", "Fast, friendly, and explained everything.",
        "Car was ready early - will be back.", "Honest shop. Didn't try to upsell me.",
        "Best shop I've used in Vegas."],
    4: ["Good work, a little pricey.", "Solid service overall.", "Friendly staff, quick turnaround.",
        "Happy with the repair."],
    3: ["Took longer than promised.", "Okay experience, updates could be better.",
        "Repair was fine but the wait was long."],
    2: ["Car was not ready when promised.", "Took way too long and nobody called me.",
        "Had to follow up several times for an update."],
    1: ["Very slow and no communication.", "Will not be coming back.",
        "Promised same day, took most of the week."],
}
PARTS_COMMENTS = ["Waited days for a part to come in.", "They had to order the part - took forever.",
                  "Parts delay turned a one-day job into a week."]
REWORK_COMMENTS = ["Had to bring it back - it wasn't fixed right the first time.",
                   "Same problem came back a week later."]


# =============================================================================
# VIN generation (valid ISO 3779 check digit and model-year code)
# =============================================================================
VIN_CHARS = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"
VIN_TRANSLIT = {**{str(i): i for i in range(10)},
                **dict(zip("ABCDEFGH", range(1, 9))), **dict(zip("JKLMN", range(1, 6))),
                "P": 7, "R": 9, **dict(zip("STUVWXYZ", range(2, 10)))}
VIN_WEIGHTS = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
YEAR_CODES = "ABCDEFGHJKLMNPRSTVWXY123456789"   # 2010..2039 cycle


def year_code(y: int) -> str:
    return YEAR_CODES[(y - 2010) % 30]


used_vins = set()


def make_vin(wmi: str, year: int) -> str:
    while True:
        vds = "".join(rng.choice(VIN_CHARS) for _ in range(5))
        plant = rng.choice("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        serial = "".join(rng.choice("0123456789") for _ in range(6))
        body = wmi + vds + "0" + year_code(year) + plant + serial
        total = sum(VIN_TRANSLIT[c] * w for c, w in zip(body, VIN_WEIGHTS))
        check = total % 11
        vin = body[:8] + ("X" if check == 10 else str(check)) + body[9:]
        if vin not in used_vins:
            used_vins.add(vin)
            return vin


# =============================================================================
# Entities
# =============================================================================
customers = []          # dicts
vehicles = []           # dicts
appointments = []       # dicts
work_orders = []        # dicts
wo_services = []        # dicts
wo_parts = []           # dicts
part_orders = []        # dicts
invoices = []
payments = []
feedback = []

used_emails = set()


def new_phone():
    return f"({rng.choice(['702', '702', '702', '725'])}) 555-{rng.randint(0, 9999):04d}"


def new_customer(since: date, channel: str = None):
    channel = channel or pick(CHANNELS)
    first, last = rng.choice(FIRST_NAMES), rng.choice(LAST_NAMES)
    company = f"{last} {rng.choice(FLEET_TRADES)} LLC" if channel == "Fleet Account" else None
    email = None
    if company or rng.random() < 0.86:
        base = f"{first}.{last}".lower().replace("'", "")
        domain = "example.com" if company is None else "example.net"
        email = f"{base}@{domain}"
        n = 2
        while email in used_emails:
            email = f"{base}{n}@{domain}"
            n += 1
        used_emails.add(email)
    c = {
        "key": len(customers), "first_name": first, "last_name": last, "company_name": company,
        "phone": new_phone() if (company or rng.random() < 0.97) else None, "email": email,
        "zip_code": pick(ZIP_WEIGHTS), "acquisition_channel": channel, "customer_since": since,
        "vehicles": [], "visits": 0,
        "last_event": since if since < START else None,   # a new booking can't predate this
    }
    customers.append(c)
    n_veh = rng.randint(3, 8) if company else pick([(1, 78), (2, 18), (3, 4)])
    for _ in range(n_veh):
        new_vehicle(c, since, fleet=bool(company))
    return c


def new_vehicle(c, as_of: date, fleet=False):
    if fleet:
        make = pick([("Ford", 5), ("Chevrolet", 4), ("Ram", 3), ("Toyota", 3), ("GMC", 2), ("Nissan", 1)])
    else:
        make = pick([(m, v[0]) for m, v in MAKES.items()])
    weight, wmis, region, models = MAKES[make]
    if fleet:
        trucks = [(m, b, w) for m, b, w in models if b in ("Truck", "Van", "SUV")] or models
        model, body, _ = pick([((m, b, w), w) for m, b, w in trucks])
    else:
        model, body, _ = pick([((m, b, w), w) for m, b, w in models])
    age = min(20, max(0, int(rng.gammavariate(3.0, 3.0 if not fleet else 1.6))))
    year = min(as_of.year + (1 if as_of.month >= 9 else 0), as_of.year - age)
    year = max(2005, year)
    odo = int(max(0, (as_of.year - year) * rng.uniform(9000, 14500) + rng.uniform(0, 6000)))
    if fleet:
        odo = int(odo * 1.8)
    v = {"key": len(vehicles), "customer": c, "vin": make_vin(rng.choice(wmis), year), "make": make,
         "model": model, "body": body, "region": region, "year": year, "odo": odo,
         "odo_date": as_of, "fleet": fleet}
    vehicles.append(v)
    c["vehicles"].append(v)
    return v


def odometer_on(v, d: date) -> int:
    days = (d - v["odo_date"]).days
    per_day = rng.uniform(40, 75) if v["fleet"] else rng.uniform(22, 45)
    v["odo"] = int(v["odo"] + max(0, days) * per_day + rng.uniform(5, 40))
    v["odo_date"] = d
    return v["odo"]


# =============================================================================
# Service selection
# =============================================================================
def primary_weights(d: date, v):
    m = d.month - 1
    age = d.year - v["year"]
    out = []
    for sid, name, cat, hours, w, _ in SERVICES:
        w *= CATEGORY_SEASON.get(cat, [1.0] * 12)[m]
        if sid == 12:
            w *= BATTERY_SEASON[m]
        if sid not in MAINTENANCE_IDS and age >= 10:
            w *= 1.3
        if v["fleet"] and sid in (1, 7, 8, 2):
            w *= 1.8
        if sid in (15, 16, 17) and v["year"] < 2008:
            w *= 1.2
        out.append((sid, w))
    return out


def choose_services(d: date, v):
    primary = pick(primary_weights(d, v))
    chosen = [primary]
    if primary in DIAG_FOLLOWUPS and rng.random() < 0.62:
        chosen.append(rng.choice(DIAG_FOLLOWUPS[primary]))
    if rng.random() < 0.34:
        pool = [s for s in ADDON_IDS + ([1] if primary != 1 else []) if s not in chosen]
        chosen.append(rng.choice(pool))
        if rng.random() < 0.22:
            pool = [s for s in pool if s not in chosen]
            chosen.append(rng.choice(pool))
    if primary in (28, 29, 37) and 27 not in chosen and rng.random() < 0.75:
        chosen.append(27)       # suspension work -> alignment
    return chosen


def parts_for_service(sid: int, v):
    rule = SERVICE_BY_ID[sid][5]
    if callable(rule):
        return [(PART_ID_BY_SKU[s], q) for s, q in rule(v)]
    out = []
    for sku, qty, prob in rule:
        if rng.random() < prob:
            if sku in ("EL-COIL", "FS-INJ"):
                qty = pick([(1, 60), (2, 25), (4, 15)])
            out.append((PART_ID_BY_SKU[sku], qty))
    return out


# =============================================================================
# Mechanics
# =============================================================================
vacation = defaultdict(set)
for mid, *_ in MECHANICS:
    for yr in (2024, 2025):
        for _ in range(rng.randint(9, 13)):
            d = date(yr, 1, 1) + timedelta(days=rng.randint(0, 364))
            vacation[mid].add(d)
            vacation[mid].add(d + timedelta(days=1))


def active_mechanics(d: date):
    out = []
    for mid, _, _, _, _, _, hire, term, *_ in MECHANICS:
        if hire <= d and (term is None or d <= term) and d not in vacation[mid]:
            out.append(mid)
    return out


def efficiency(mid: int, d: date) -> float:
    m = MECH_BY_ID[mid]
    lo, hi = m[8]
    if lo == hi:
        return lo
    start = max(START, m[6])
    frac = min(1.0, max(0.0, (d - start).days / max(1, (END - start).days)))
    return lo + (hi - lo) * frac


def assign_mechanic(d, complexity, load_today, prefer=None):
    active = active_mechanics(d)
    if prefer in active and rng.random() < 0.7:
        return prefer
    weights = []
    for mid in active:
        skill = MECH_BY_ID[mid][4]
        if complexity >= 3:
            w = {"Master Technician": 4, "Technician": 1.5, "Apprentice": 0.15}[skill]
        elif complexity >= 1.5:
            w = {"Master Technician": 1.5, "Technician": 2.5, "Apprentice": 0.7}[skill]
        else:
            w = {"Master Technician": 0.5, "Technician": 1.5, "Apprentice": 3}[skill]
        weights.append((mid, w / (1 + load_today[mid] / 5.0)))
    return pick(weights)


# =============================================================================
# Inventory
# =============================================================================
on_hand = {}
on_order = defaultdict(int)
arrivals = defaultdict(list)          # date -> [part_order dict]


def actual_lead_days(supplier_id: int) -> int:
    quoted, extra = SUPPLIER_BY_ID[supplier_id][3], SUPPLIER_BY_ID[supplier_id][4]
    return max(1, quoted + int(round(max(0.0, rng.gauss(extra, 0.9)))))


def delivery_date(ordered: date, lead: int) -> date:
    return roll_to_open_day(ordered + timedelta(days=lead))


def place_order(part_id, qty, ordered: date, order_type, wo=None):
    sup = PART_BY_ID[part_id][4]
    cost, _ = part_cost_price(part_id, ordered)
    received = delivery_date(ordered, actual_lead_days(sup))
    po = {"part_id": part_id, "wo": wo, "order_type": order_type, "ordered_date": ordered,
          "expected_date": ordered + timedelta(days=SUPPLIER_BY_ID[sup][3]),
          "received_date": received, "quantity": qty, "unit_cost": cost}
    part_orders.append(po)
    if order_type == "Replenishment":
        on_order[part_id] += qty
        arrivals[received].append(po)
    return po


for p in PARTS:
    qty = p[7] + p[8]
    on_hand[p[0]] = qty
    if qty:
        cost, _ = part_cost_price(p[0], START)
        part_orders.append({"part_id": p[0], "wo": None, "order_type": "Opening Balance",
                            "ordered_date": START, "expected_date": START, "received_date": START,
                            "quantity": qty, "unit_cost": cost})


def receive_deliveries(d: date):
    for po in arrivals.pop(d, []):
        on_hand[po["part_id"]] += po["quantity"]
        on_order[po["part_id"]] -= po["quantity"]


def pull_part(part_id, qty, d: date, wo):
    """Take parts off the shelf; special-order them if the shelf can't cover it."""
    if on_hand[part_id] >= qty:
        on_hand[part_id] -= qty
        p = PART_BY_ID[part_id]
        if p[8] > 0 and on_hand[part_id] + on_order[part_id] <= p[7]:
            place_order(part_id, p[8], d, "Replenishment")
        return True, None
    po = place_order(part_id, qty, d, "Special Order", wo)
    return False, po


# =============================================================================
# Simulation
# =============================================================================
return_queue = defaultdict(list)      # date -> [(customer, vehicle, parent_wo)]
mech_free = {}                        # mechanic_id -> next time they can start a job


def queue_visit(d: date, c, v=None, parent=None):
    if d > BOOKING_HORIZON:
        return
    return_queue[roll_to_open_day(d)].append((c, v, parent))


# Existing customer base migrated into the system on go-live (history before 2024 not loaded)
for _ in range(950):
    since = date(2018, 1, 1) + timedelta(days=rng.randint(0, (date(2023, 12, 15) - date(2018, 1, 1)).days))
    c = new_customer(since)
    if rng.random() < 0.80:
        queue_visit(START + timedelta(days=int(rng.triangular(0, 170, 0))), c)


def lead_days_for(c, rework=False):
    if rework:
        return rng.randint(0, 3)
    if c["company_name"]:
        return rng.randint(1, 7)
    bucket = pick([((0, 2), 42), ((3, 7), 30), ((8, 14), 17), ((15, 30), 11)])
    return rng.randint(*bucket)


def no_show_prob(lead: int, d: date, c) -> float:
    p = 0.035 if lead <= 2 else 0.07 if lead <= 7 else 0.125 if lead <= 14 else 0.19
    if d.weekday() == 0:
        p *= 1.3
    if c["company_name"]:
        p *= 0.4
    return p


def book_appointment(c, v, visit_day: date, lead: int):
    slots = SLOTS_SATURDAY if visit_day.weekday() == 5 else SLOTS_WEEKDAY
    hh, mm = pick(slots)
    start = datetime.combine(visit_day, time(hh, mm))
    book_day = visit_day - timedelta(days=lead)
    if lead == 0:
        latest = max(0, int((start - datetime.combine(visit_day, time(6, 0))).total_seconds() / 60) - 20)
        booked = datetime.combine(visit_day, time(6, 0)) + timedelta(minutes=rng.randint(0, latest))
    else:
        booked = datetime.combine(book_day, time(7, 0)) + timedelta(minutes=rng.randint(0, 14 * 60))
    appt = {"vehicle": v, "booked_at": booked.replace(second=0), "scheduled_start": start, "status": None}
    appointments.append(appt)
    return appt


def satisfaction(wo) -> float:
    s = 4.55 + rng.gauss(0, 0.55)
    if wo["late_hours"] > 0:
        s -= 1.15
        if wo["late_hours"] > 20:
            s -= 0.5
    if wo["stockout"]:
        s -= 0.45
    if wo["will_rework"]:
        s -= 1.4
    if wo["start_delay"] > 45:
        s -= 0.35
    if MECH_BY_ID[wo["mechanic_id"]][4] == "Master Technician":
        s += 0.15
    return s


day = START
while day <= BOOKING_HORIZON:
    oh = open_hours(day)
    if day <= END:
        receive_deliveries(day)
    if oh is None:
        # anything queued for a closed day moves to the next open day
        if return_queue.get(day):
            return_queue[next_open_day(day)].extend(return_queue.pop(day))
        day += timedelta(days=1)
        continue

    m = day.month - 1
    visitors = return_queue.pop(day, [])
    # Marketing brings in enough new customers to hit the day's demand target
    # (the target grows ~10%/yr); returning customers fill the rest.
    target = (12.4 + 1.5 * year_frac(day)) * VOLUME_SEASON[m] * (0.5 if day.weekday() == 5 else 1.0)
    if day.weekday() == 0:
        target *= 1.10
    floor = 2.2 if day.weekday() != 5 else 1.0
    for _ in range(poisson(max(floor, target - 0.88 * len(visitors)))):
        visitors.append((None, None, None))

    todays = []   # (customer, vehicle, appointment or None, parent)
    for c, v, parent in visitors:
        if c is None:
            since = day
            c = new_customer(since)
        if v is None:
            v = rng.choice(c["vehicles"])
        wants_appt = 0.9 if c["company_name"] else (0.62 if c["visits"] == 0 else 0.74)
        if parent is not None:
            wants_appt = 0.6
        if rng.random() < wants_appt:
            lead = lead_days_for(c, rework=parent is not None)
            if c["last_event"] is not None:
                lead = max(0, min(lead, (day - c["last_event"]).days))
            appt = book_appointment(c, v, day, lead)
            if c["visits"] == 0 and c["customer_since"] > appt["booked_at"].date():
                c["customer_since"] = appt["booked_at"].date()
            if appt["booked_at"] > SNAPSHOT:           # booking itself is in the future: drop it
                appointments.pop()
                continue
            if day > END:
                appt["status"] = "Scheduled"
                continue
            r = rng.random()
            if parent is None and r < no_show_prob(lead, day, c):
                appt["status"] = "No-Show"
            elif parent is None and r < no_show_prob(lead, day, c) + 0.05:
                appt["status"] = "Cancelled"
            else:
                appt["status"] = "Arrived"
            c["last_event"] = day
            if appt["status"] != "Arrived":
                if rng.random() < 0.45:
                    queue_visit(day + timedelta(days=rng.randint(3, 21)), c, v, None)
                continue
            todays.append((c, v, appt, parent))
        elif day <= END:
            todays.append((c, v, None, parent))

    if day > END:
        day += timedelta(days=1)
        continue

    # --- start times: overbooked slots push the start of the job back --------
    by_slot = defaultdict(list)
    for item in todays:
        if item[2] is not None:
            by_slot[item[2]["scheduled_start"]].append(item)
    starts = {}
    for slot, items in by_slot.items():
        items.sort(key=lambda it: it[2]["booked_at"])
        for i, it in enumerate(items):
            # two service writers: the 3rd+ customer in the same slot waits at the counter
            delay = max(0, i - 1) * rng.uniform(14, 24) + rng.uniform(0, 10)
            starts[id(it)] = (slot + timedelta(minutes=delay), delay)
    for it in todays:
        if it[2] is None:
            close_h = 13.0 if day.weekday() == 5 else 15.5
            arrive = rng.triangular(7.5 if day.weekday() != 5 else 8.0, close_h, 8.75)
            opened = datetime.combine(day, time(0, 0)) + timedelta(hours=arrive, minutes=rng.uniform(5, 35))
            starts[id(it)] = (opened, 0.0)

    todays.sort(key=lambda it: starts[id(it)][0])
    if day == SNAPSHOT.date():
        # the data stops at the snapshot: later arrivals haven't happened yet
        for it in todays:
            if starts[id(it)][0] > SNAPSHOT and it[2] is not None:
                it[2]["status"] = "Scheduled"
        todays = [it for it in todays if starts[id(it)][0] <= SNAPSHOT]

    # --- pass 1: build work orders, assign techs, pull parts ------------------
    load_today = defaultdict(float)
    day_wos = []
    for item in todays:
        c, v, appt, parent = item
        opened, delay = starts[id(item)]
        opened = opened.replace(second=0, microsecond=0)
        wo = {"vehicle": v, "customer": c, "appointment": appt, "parent": parent,
              "opened_at": opened, "start_delay": delay, "stockout": False, "special_orders": [],
              "will_rework": False, "lines": [], "parts": {}}
        if parent is None:
            sids = choose_services(day, v)
        else:
            sids = [parent["primary_sid"]]
        wo["primary_sid"] = max(sids, key=lambda s: SERVICE_BY_ID[s][3])
        complexity = max(SERVICE_BY_ID[s][3] for s in sids)
        prefer = parent["mechanic_id"] if parent is not None else None
        mid = assign_mechanic(day, complexity, load_today, prefer)
        wo["mechanic_id"] = mid
        eff = efficiency(mid, day)
        rate = LABOR_RATE[day.year]
        factor = HOURS_FACTOR[v["region"]]
        for sid in sids:
            book = SERVICE_BY_ID[sid][3] * factor
            billed = hrs(book) if parent is None else Decimal("0.00")
            base = book if parent is None else book * rng.uniform(0.3, 0.7)
            actual = max(Decimal("0.10"), hrs(base / eff * rng.lognormvariate(0, 0.16)))
            wo["lines"].append({"sid": sid, "billed": billed, "actual": actual, "rate": rate})
            load_today[mid] += float(billed if parent is None else actual)
        # parts
        wanted = defaultdict(int)
        if parent is None:
            for sid in sids:
                for pid, q in parts_for_service(sid, v):
                    wanted[pid] += q
        else:
            for pid, q in parts_for_service(wo["primary_sid"], v):
                if PART_BY_ID[pid][3] not in ("Fluids", "Filters") and rng.random() < 0.5:
                    wanted[pid] += q
        for pid, q in wanted.items():
            in_stock, po = pull_part(pid, q, day, wo)
            cost, price = part_cost_price(pid, day)
            wo["parts"][pid] = {"qty": q, "cost": cost, "price": price if parent is None else Decimal("0.00"),
                                "in_stock": in_stock}
            if not in_stock:
                wo["stockout"] = True
                wo["special_orders"].append(po)
        day_wos.append(wo)

    # --- pass 2: timing. Each technician works one job at a time, so a busy
    #     morning creates a real queue (the "appointments delayed" problem). ----
    for mid in active_mechanics(day):
        mech_free[mid] = max(mech_free.get(mid, oh[0]), oh[0])
    for wo in day_wos:
        billed = float(sum(l["billed"] for l in wo["lines"])) or float(sum(l["actual"] for l in wo["lines"]))
        actual = float(sum(l["actual"] for l in wo["lines"]))
        repair = wo["primary_sid"] not in MAINTENANCE_IDS
        mid = wo["mechanic_id"]
        backlog_h = max(0.0, (mech_free[mid] - wo["opened_at"]).total_seconds() / 3600)
        # big estimates often sit on "authorization hold" while the customer decides;
        # the promise clock only starts once they approve
        estimate = billed * float(LABOR_RATE[day.year]) + sum(float(p["price"]) * p["qty"] for p in wo["parts"].values())
        hold_h = rng.uniform(2, 20) if (repair and wo["parent"] is None and estimate > 600 and rng.random() < 0.35) else 0.0
        released = add_business_hours(wo["opened_at"], hold_h) if hold_h else wo["opened_at"]
        # the service writer quotes: labor time + a buffer + part of the visible backlog
        promise = add_business_hours(released,
                                     billed * 1.25 + (2.0 if repair else 0.75) + 0.6 * min(backlog_h, 6))
        # about a third of the time the writer already knows a part is out and
        # builds the supplier's quoted date into the promise
        if wo["special_orders"] and rng.random() < 0.35:
            eta = max(po["expected_date"] for po in wo["special_orders"])
            eta_dt = datetime.combine(roll_to_open_day(eta), time(10, 0))
            promise = max(promise, add_business_hours(eta_dt, max(0.5, billed * 0.6) + 1.5))
        close = open_hours(promise.date())[1]
        if promise > close - timedelta(minutes=45):
            promise = close
        wo["promised_at"] = promise.replace(second=0, microsecond=0)
        if hold_h:
            bench_end = add_business_hours(released, actual)   # slotted in once approved
        else:
            start = max(wo["opened_at"], mech_free[mid])
            bench_end = add_business_hours(start, actual)
            mech_free[mid] = bench_end
        wait_h = 0.0
        if repair and rng.random() < 0.45:
            wait_h += rng.uniform(0.5, 4.0)             # waiting on customer approval of the estimate
        done = add_business_hours(bench_end, wait_h + rng.uniform(0.05, 0.4))   # road test / QC / paperwork
        for po in wo["special_orders"]:
            arrive = datetime.combine(po["received_date"], time(10, 0)) + timedelta(minutes=rng.randint(0, 150))
            done = max(done, add_business_hours(arrive, max(0.5, actual * 0.6)))
        wo["done_at"] = done.replace(second=0, microsecond=0)
        if wo["done_at"] <= wo["opened_at"]:
            wo["done_at"] = wo["opened_at"] + timedelta(minutes=15)
        wo["late_hours"] = max(0.0, (wo["done_at"] - wo["promised_at"]).total_seconds() / 3600)
        wo["odometer"] = odometer_on(wo["vehicle"], day)
        c = wo["customer"]
        c["visits"] += 1
        c["last_event"] = max(c["last_event"] or day, wo["done_at"].date())
        # comeback?
        if wo["parent"] is None and wo["primary_sid"] not in MAINTENANCE_IDS:
            p_rw = MECH_BY_ID[wo["mechanic_id"]][9] * (1.5 if SERVICE_BY_ID[wo["primary_sid"]][3] >= 3 else 1.0)
            if rng.random() < p_rw * 2.2:
                wo["will_rework"] = True
        wo["satisfaction"] = satisfaction(wo) if wo["parent"] is None else 2.5
        if wo["will_rework"]:
            queue_visit(wo["done_at"].date() + timedelta(days=rng.randint(2, 20)), c, wo["vehicle"], wo)
        # will they come back for their next routine visit?
        p_ret = RETURN_BASE[c["acquisition_channel"]]
        if wo["late_hours"] > 0:
            p_ret -= 0.18
        if wo["satisfaction"] < 2.5:
            p_ret -= 0.25
        if wo["parent"] is not None:
            p_ret -= 0.12
        if wo["parent"] is None and rng.random() < p_ret:
            mean_gap = 42 if c["company_name"] else 118
            gap = rng.gammavariate(2.2, mean_gap / 2.2)
            queue_visit(wo["done_at"].date() + timedelta(days=int(max(14 if not c["company_name"] else 7, gap))), c)
        work_orders.append(wo)

    day += timedelta(days=1)


# =============================================================================
# Post-processing: statuses as of SNAPSHOT, invoices, payments, feedback
# =============================================================================
work_orders.sort(key=lambda w: w["opened_at"])
for i, wo in enumerate(work_orders, start=1):
    wo["id"] = i

for wo in work_orders:
    if wo["done_at"] <= SNAPSHOT:
        wo["status"], wo["completed_at"] = "Completed", wo["done_at"]
    else:
        wo["completed_at"] = None
        waiting = [po for po in wo["special_orders"] if po["received_date"] > SNAPSHOT.date()]
        if waiting:
            wo["status"] = "Waiting on Parts"
        elif wo["opened_at"] > SNAPSHOT - timedelta(minutes=45):
            wo["status"] = "Open"
        else:
            wo["status"] = "In Progress"

for po in part_orders:
    if po["received_date"] is not None and po["received_date"] > SNAPSHOT.date():
        po["received_date"] = None          # still in transit on the snapshot date


def pay_mix(d: date):
    f = year_frac(d)
    return [("Visa", 30), ("Mastercard", 19), ("American Express", 8), ("Discover", 4),
            ("Debit Card", 18), ("Cash", 13 - 6 * f), ("Mobile Wallet", 7 + 11 * f)]


completed = sorted([w for w in work_orders if w["status"] == "Completed"], key=lambda w: w["completed_at"])
for wo in completed:
    if wo["parent"] is not None:
        continue                                        # warranty rework: no charge, no invoice
    c = wo["customer"]
    labor = sum(l["billed"] * l["rate"] for l in wo["lines"])
    parts = sum(p["price"] * p["qty"] for p in wo["parts"].values())
    first_visit = c["visits_invoiced"] if "visits_invoiced" in c else 0
    discount, reason = Decimal("0.00"), None
    if c["company_name"]:
        discount, reason = money(labor * Decimal("0.10")), "Fleet pricing (10% labor)"
    elif first_visit == 0 and c["customer_since"] >= START and c["acquisition_channel"] in ("Google Search", "Yelp", "Social Media") and rng.random() < 0.55:
        discount, reason = money(labor * Decimal("0.10")), "New customer (10% labor)"
    elif labor >= 100 and rng.random() < 0.035:
        discount, reason = Decimal("25.00"), "Loyalty reward"
    if discount == 0:
        reason = None
    c["visits_invoiced"] = first_visit + 1
    tax = (parts * TAX_RATE).quantize(CENT, rounding=ROUND_HALF_UP)
    total = labor + parts - discount + tax
    inv = {"wo": wo, "invoice_date": wo["completed_at"].date(), "discount": discount, "reason": reason,
           "total": total}
    invoices.append(inv)
    # payments
    if c["company_name"]:
        paid = wo["completed_at"] + timedelta(days=rng.randint(8, 45), hours=rng.uniform(-3, 3))
        if paid <= SNAPSHOT:
            payments.append({"inv": inv, "paid_at": paid, "method": "ACH / Check", "amount": total})
    else:
        paid = wo["completed_at"] + timedelta(minutes=rng.uniform(10, 150))
        close = open_hours(paid.date())
        if close is None or paid > close[1]:
            nd = next_open_day(paid.date())
            paid = open_hours(nd)[0] + timedelta(minutes=rng.uniform(15, 240))
        if paid > SNAPSHOT:
            continue
        method = pick(pay_mix(paid.date()))
        if rng.random() < 0.02 and total > 60:
            first_amt = money(float(total) * rng.uniform(0.2, 0.6))
            payments.append({"inv": inv, "paid_at": paid, "method": "Cash", "amount": first_amt})
            payments.append({"inv": inv, "paid_at": paid + timedelta(minutes=1),
                             "method": pick([("Visa", 3), ("Mastercard", 2), ("Debit Card", 2)]),
                             "amount": total - first_amt})
        else:
            payments.append({"inv": inv, "paid_at": paid, "method": method, "amount": total})
    # survey
    if rng.random() < 0.38:
        submitted = wo["completed_at"] + timedelta(hours=rng.uniform(4, 96))
        if submitted <= SNAPSHOT:
            rating = int(min(5, max(1, round(wo["satisfaction"]))))
            comment = None
            if rng.random() < 0.45:
                if wo["will_rework"] and rating <= 3:
                    comment = rng.choice(REWORK_COMMENTS)
                elif wo["stockout"] and rating <= 3:
                    comment = rng.choice(PARTS_COMMENTS)
                else:
                    comment = rng.choice(COMMENTS[rating])
            feedback.append({"wo": wo, "submitted_at": submitted, "rating": rating, "comment": comment})

# =============================================================================
# Assign surrogate keys in natural (chronological) order
# =============================================================================
active_vehicles = {id(a["vehicle"]) for a in appointments} | {id(w["vehicle"]) for w in work_orders}
drop = {id(c) for c in customers
        if c["customer_since"] >= START and not any(id(v) in active_vehicles for v in c["vehicles"])}
customers = [c for c in customers if id(c) not in drop]
vehicles = [v for v in vehicles if id(v["customer"]) not in drop]
customers.sort(key=lambda c: (c["customer_since"], c["key"]))
for i, c in enumerate(customers, start=1):
    c["id"] = i
vehicles.sort(key=lambda v: (v["customer"]["id"], v["key"]))
for i, v in enumerate(vehicles, start=1):
    v["id"] = i
appointments.sort(key=lambda a: (a["booked_at"], a["scheduled_start"]))
for i, a in enumerate(appointments, start=1):
    a["id"] = i
part_orders.sort(key=lambda p: (p["ordered_date"], p["order_type"] != "Opening Balance", p["part_id"]))
for i, p in enumerate(part_orders, start=1):
    p["id"] = i
invoices.sort(key=lambda x: (x["invoice_date"], x["wo"]["completed_at"]))
for i, x in enumerate(invoices, start=1):
    x["id"] = i
payments.sort(key=lambda x: x["paid_at"])
for i, x in enumerate(payments, start=1):
    x["id"] = i
feedback.sort(key=lambda x: x["submitted_at"])
for i, x in enumerate(feedback, start=1):
    x["id"] = i


def ts(x):
    return x.strftime("%Y-%m-%d %H:%M:%S") if x is not None else None


def ds(x):
    return x.isoformat() if x is not None else None


TABLES = [
    ("customer", ["customer_id", "first_name", "last_name", "company_name", "phone", "email", "zip_code",
                  "acquisition_channel", "customer_since"],
     [[c["id"], c["first_name"], c["last_name"], c["company_name"], c["phone"], c["email"], c["zip_code"],
       c["acquisition_channel"], ds(c["customer_since"])] for c in customers]),
    ("vehicle", ["vehicle_id", "customer_id", "vin", "make", "model", "model_year"],
     [[v["id"], v["customer"]["id"], v["vin"], v["make"], v["model"], v["year"]] for v in vehicles]),
    ("mechanic", ["mechanic_id", "first_name", "last_name", "phone", "skill_level", "hourly_wage", "hire_date",
                  "termination_date"],
     [[m[0], m[1], m[2], m[3], m[4], money(m[5]), ds(m[6]), ds(m[7])] for m in MECHANICS]),
    ("service_type", ["service_type_id", "service_name", "service_category", "book_hours"],
     [[s[0], s[1], s[2], money(s[3])] for s in SERVICES]),
    ("supplier", ["supplier_id", "supplier_name", "phone", "quoted_lead_days"],
     [[s[0], s[1], s[2], s[3]] for s in SUPPLIERS]),
    ("part", ["part_id", "sku", "part_name", "part_category", "supplier_id", "unit_cost", "unit_price",
              "reorder_point", "reorder_qty"],
     [[p[0], p[1], p[2], p[3], p[4], *part_cost_price(p[0], END), p[7], p[8]] for p in PARTS]),
    ("appointment", ["appointment_id", "vehicle_id", "booked_at", "scheduled_start", "status"],
     [[a["id"], a["vehicle"]["id"], ts(a["booked_at"]), ts(a["scheduled_start"]), a["status"]]
      for a in appointments]),
    ("work_order", ["work_order_id", "vehicle_id", "appointment_id", "mechanic_id", "parent_work_order_id",
                    "opened_at", "promised_at", "completed_at", "status", "odometer_miles"],
     [[w["id"], w["vehicle"]["id"], w["appointment"]["id"] if w["appointment"] else None, w["mechanic_id"],
       w["parent"]["id"] if w["parent"] else None, ts(w["opened_at"]), ts(w["promised_at"]),
       ts(w["completed_at"]), w["status"], w["odometer"]] for w in work_orders]),
    ("work_order_service", ["work_order_id", "service_type_id", "hours_billed", "hours_actual", "labor_rate"],
     [[w["id"], l["sid"], l["billed"], l["actual"], l["rate"]] for w in work_orders for l in w["lines"]]),
    ("work_order_part", ["work_order_id", "part_id", "quantity", "unit_cost", "unit_price", "was_in_stock"],
     [[w["id"], pid, p["qty"], p["cost"], p["price"], 1 if p["in_stock"] else 0]
      for w in work_orders for pid, p in sorted(w["parts"].items())]),
    ("part_order", ["part_order_id", "part_id", "work_order_id", "order_type", "ordered_date", "expected_date",
                    "received_date", "quantity", "unit_cost"],
     [[p["id"], p["part_id"], p["wo"]["id"] if p["wo"] else None, p["order_type"], ds(p["ordered_date"]),
       ds(p["expected_date"]), ds(p["received_date"]), p["quantity"], p["unit_cost"]] for p in part_orders]),
    ("invoice", ["invoice_id", "work_order_id", "invoice_date", "discount_amount", "discount_reason", "tax_rate"],
     [[x["id"], x["wo"]["id"], ds(x["invoice_date"]), x["discount"], x["reason"], TAX_RATE] for x in invoices]),
    ("payment", ["payment_id", "invoice_id", "paid_at", "payment_method", "amount"],
     [[x["id"], x["inv"]["id"], ts(x["paid_at"].replace(second=0, microsecond=0)), x["method"], x["amount"]]
      for x in payments]),
    ("customer_feedback", ["feedback_id", "work_order_id", "submitted_at", "rating", "comment"],
     [[x["id"], x["wo"]["id"], ts(x["submitted_at"].replace(second=0, microsecond=0)), x["rating"], x["comment"]]
      for x in feedback]),
]


def sql_literal(v):
    if v is None:
        return "NULL"
    if isinstance(v, (int, Decimal)):
        return str(v)
    return "'" + str(v).replace("\\", "\\\\").replace("'", "''") + "'"


def write_outputs():
    CSV_DIR.mkdir(parents=True, exist_ok=True)
    with open(SQL_OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("/* =============================================================================\n")
        f.write("   02_seed_data.sql - GENERATED by python/generate_data.py (seed %d). Do not edit.\n" % SEED)
        f.write("   Synthetic data: 2024-01-01 to 2025-12-31, snapshot %s.\n" % SNAPSHOT.isoformat(" "))
        f.write("   All people, companies, phone numbers (555) and emails (example.com) are fictional.\n")
        f.write("   ============================================================================= */\n")
        f.write("USE service_management;\nSET autocommit = 0;\n\n")
        for name, cols, rows in TABLES:
            f.write(f"-- {name}: {len(rows):,} rows\n")
            for i in range(0, len(rows), 500):
                chunk = rows[i:i + 500]
                f.write(f"INSERT INTO {name} ({', '.join(cols)}) VALUES\n")
                f.write(",\n".join("(" + ", ".join(sql_literal(v) for v in r) + ")" for r in chunk))
                f.write(";\n")
            f.write("\n")
        f.write("COMMIT;\nSET autocommit = 1;\n")
    for name, cols, rows in TABLES:
        with open(CSV_DIR / f"{name}.csv", "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(cols)
            w.writerows([["" if v is None else v for v in r] for r in rows])
    total = 0
    for name, cols, rows in TABLES:
        print(f"  {name:<20} {len(rows):>7,}")
        total += len(rows)
    print(f"  {'TOTAL':<20} {total:>7,}")


if __name__ == "__main__":
    write_outputs()
