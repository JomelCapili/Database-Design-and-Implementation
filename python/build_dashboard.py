#!/usr/bin/env python3
"""
build_dashboard.py - package the database into the interactive HTML dashboard

Queries the reporting views, compresses them into a compact columnar JSON blob,
and injects it into dashboard/dashboard.html, producing:

  docs/index.html   a single self-contained page (GitHub Pages serves /docs)

Usage
  pip install pymysql
  python3 python/build_dashboard.py            # MYSQL_HOST / MYSQL_USER / MYSQL_PASSWORD env vars
"""

import datetime as dt
import decimal
import json
import os
import sys
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "dashboard" / "dashboard.html"
OUT = ROOT / "docs" / "index.html"
EPOCH = dt.date(2024, 1, 1)
SNAPSHOT = "2025-12-31 12:00:00"


def connect():
    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST", "localhost"),
        user=os.environ.get("MYSQL_USER", "root"),
        password=os.environ.get("MYSQL_PASSWORD", ""),
        database="service_management",
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
    )


def num(v, places=2):
    if v is None:
        return None
    if isinstance(v, (decimal.Decimal, float)):
        f = round(float(v), places)
        return int(f) if f == int(f) else f
    return v


def day(v):
    d = v.date() if isinstance(v, dt.datetime) else v
    return (d - EPOCH).days


class Index:
    """Dictionary-encode a text column: value -> small integer."""
    def __init__(self, values=None):
        self.items, self.pos = [], {}
        for v in values or []:
            self(v)

    def __call__(self, v):
        if v not in self.pos:
            self.pos[v] = len(self.items)
            self.items.append(v)
        return self.pos[v]


def main():
    conn = connect()
    cur = conn.cursor()

    cur.execute("SELECT mechanic_id, mechanic_name, skill_level FROM v_mechanic_scorecard ORDER BY mechanic_id")
    mechs = cur.fetchall()
    mech_idx = {m["mechanic_id"]: i for i, m in enumerate(mechs)}

    cats = Index()
    channels = Index(["Walk-in", "Google Search", "Referral", "Yelp", "Social Media", "Fleet Account"])
    statuses = Index(["Completed", "In Progress", "Waiting on Parts", "Open"])

    # ---- work orders (columnar) --------------------------------------------
    cur.execute("""
        SELECT ws.*, (ws.opened_at = fv.first_at AND c.customer_since >= '2024-01-01') AS is_new_customer
        FROM v_work_order_summary ws
        JOIN customer c ON c.customer_id = ws.customer_id
        JOIN (SELECT customer_id, MIN(opened_at) AS first_at FROM work_order w
                JOIN vehicle v ON v.vehicle_id = w.vehicle_id GROUP BY customer_id) fv
          ON fv.customer_id = ws.customer_id
        ORDER BY ws.work_order_id""")
    rows = cur.fetchall()
    makes = Index()
    wo = {k: [] for k in ["id", "d", "st", "rw", "m", "c", "mk", "ch", "cu", "nw", "ap", "ns", "gp", "pr", "pc",
                          "hb", "ha", "ta", "ot", "so", "sp", "pw", "cb", "cs"]}
    wo_row = {}
    for i, r in enumerate(rows):
        wo_row[r["work_order_id"]] = i
        wo["id"].append(r["work_order_id"])
        wo["d"].append(day(r["opened_at"]))
        wo["st"].append(statuses(r["status"]))
        wo["rw"].append(1 if r["job_type"] == "Warranty Rework" else 0)
        wo["m"].append(mech_idx[r["mechanic_id"]])
        wo["c"].append(cats(r["primary_category"]))
        wo["mk"].append(makes(r["make"]))
        wo["ch"].append(channels(r["acquisition_channel"]))
        wo["cu"].append(r["customer_id"])
        wo["nw"].append(int(r["is_new_customer"] or 0))
        wo["ap"].append(1 if r["booking_type"] == "Appointment" else 0)
        wo["ns"].append(num(r["net_sales"]))
        wo["gp"].append(num(r["gross_profit"]))
        wo["pr"].append(num(r["parts_revenue"]))
        wo["pc"].append(num(r["parts_cost"]))
        wo["hb"].append(num(r["hours_billed"]))
        wo["ha"].append(num(r["hours_actual"]))
        wo["ta"].append(num(r["turnaround_hours"], 1))
        wo["ot"].append(None if r["is_on_time"] is None else int(r["is_on_time"]))
        wo["so"].append(int(r["had_stockout"]))
        wo["sp"].append(int(r["had_special_order"]))
        wo["pw"].append(r["parts_wait_days"])
        wo["cb"].append(int(r["had_comeback"]))
        wo["cs"].append(r["csat_rating"] or 0)

    # ---- part lines -------------------------------------------------------------
    cur.execute("SELECT part_id, sku, part_name, part_category FROM part ORDER BY part_id")
    parts = cur.fetchall()
    part_idx = {p["part_id"]: i for i, p in enumerate(parts)}
    cur.execute("SELECT work_order_id, part_id, quantity, was_in_stock FROM work_order_part ORDER BY work_order_id")
    pl = {"w": [], "p": [], "q": [], "s": []}
    for r in cur.fetchall():
        pl["w"].append(wo_row[r["work_order_id"]])
        pl["p"].append(part_idx[r["part_id"]])
        pl["q"].append(r["quantity"])
        pl["s"].append(int(r["was_in_stock"]))

    # ---- appointments -----------------------------------------------------------
    slots = Index()
    appt_status = Index(["Arrived", "No-Show", "Cancelled", "Scheduled"])
    cur.execute("SELECT * FROM v_appointment_summary ORDER BY scheduled_start")
    ap = {"d": [], "sl": [], "wd": [], "ld": [], "s": [], "w": [], "b": []}
    appt_rows = cur.fetchall()
    for s in sorted({r["slot_time"] for r in appt_rows}):
        slots(s)
    for r in appt_rows:
        ap["d"].append(day(r["scheduled_start"]))
        ap["sl"].append(slots(r["slot_time"]))
        ap["wd"].append(r["scheduled_start"].weekday())
        ap["ld"].append(r["lead_days"])
        ap["s"].append(appt_status(r["status"]))
        ap["w"].append(r["checkin_wait_min"])
        ap["b"].append(r["bookings_in_slot"])

    # ---- snapshot tables --------------------------------------------------------
    cur.execute("SELECT * FROM v_part_inventory ORDER BY part_id")
    inventory = [{
        "sku": r["sku"], "name": r["part_name"], "cat": r["part_category"], "supplier": r["supplier_name"],
        "onHand": r["on_hand"], "onOrder": int(r["on_order"]), "rop": r["reorder_point"],
        "sugRop": None if r["suggested_reorder_point"] is None else int(r["suggested_reorder_point"]), "value": num(r["inventory_value"]),
        "dos": num(r["days_of_supply"], 1), "lead": num(r["avg_actual_lead_days"], 1),
        "quoted": r["quoted_lead_days"], "specialOnly": int(r["is_special_order_only"]),
        "out2025": int(r["times_out_of_stock_2025"]),
    } for r in cur.fetchall()]

    cur.execute("""
        SELECT s.supplier_name, s.quoted_lead_days, COUNT(*) AS n,
               AVG(DATEDIFF(po.received_date, po.ordered_date)) AS actual,
               AVG(po.received_date > po.expected_date) * 100 AS late_pct
        FROM part_order po JOIN part p ON p.part_id = po.part_id JOIN supplier s ON s.supplier_id = p.supplier_id
        WHERE po.order_type <> 'Opening Balance' AND po.received_date IS NOT NULL
        GROUP BY s.supplier_id, s.supplier_name, s.quoted_lead_days ORDER BY s.supplier_id""")
    suppliers = [{"name": r["supplier_name"], "quoted": r["quoted_lead_days"], "orders": r["n"],
                  "actual": num(r["actual"], 1), "latePct": num(r["late_pct"], 1)} for r in cur.fetchall()]

    cur.execute(f"""
        SELECT ws.work_order_id, ws.status, ws.mechanic_name,
               CONCAT(ws.model_year, ' ', ws.make, ' ', ws.model) AS vehicle, ws.primary_service,
               ws.opened_at, ws.promised_at,
               (SELECT GROUP_CONCAT(p.sku ORDER BY p.sku) FROM part_order po JOIN part p ON p.part_id = po.part_id
                 WHERE po.work_order_id = ws.work_order_id AND po.received_date IS NULL) AS parts_in_transit
        FROM v_work_order_summary ws WHERE ws.status <> 'Completed' ORDER BY ws.opened_at""")
    wip = [{"id": r["work_order_id"], "status": r["status"], "tech": r["mechanic_name"], "vehicle": r["vehicle"],
            "service": r["primary_service"], "opened": r["opened_at"].strftime("%Y-%m-%dT%H:%M"),
            "promised": r["promised_at"].strftime("%Y-%m-%dT%H:%M"), "parts": r["parts_in_transit"]}
           for r in cur.fetchall()]

    # cohort retention + first-visit return rates (full history; not filterable)
    sql = (ROOT / "sql" / "04_analysis_queries.sql").read_text()

    def run_query(tag):
        start = sql.index(tag)
        body = sql[start:]
        body = body[body.index("\n") + 1:]
        end = body.index(";")
        cur.execute(body[:end])
        return cur.fetchall()

    cohort = [{"cohort": r["cohort"], "n": r["customers"],
               "q": [num(r[k], 1) for k in ("q1_later_pct", "q2_later_pct", "q3_later_pct", "q4_later_pct")]}
              for r in run_query("-- Q17.")]
    retention = [{"label": r["first_visit_experience"], "n": r["customers"], "pct": num(r["returned_within_180d_pct"], 1)}
                 for r in run_query("-- Q16.")]
    rework_cost = run_query("-- Q11.")

    # ---- headline findings (computed, never typed in) ---------------------------
    q5 = {(r["driver"], r["segment"]): r for r in run_query("-- Q5.")}
    ret = {r["label"]: r["pct"] for r in retention}
    tech = {r["mechanic_name"]: r for r in run_query("-- Q9.")}
    q7 = {r["lead_bucket"]: r for r in run_query("-- Q7.")}
    rotor = next(p for p in inventory if p["sku"] == "BR-ROT-F")
    summit = next(s for s in suppliers if s["name"].startswith("Summit"))
    others = [t for n, t in tech.items() if n != "Tyler Brooks"]
    others_cb = sum(float(t["comeback_rate_pct"]) for t in others) / len(others)
    tyler_cost = next(float(r["rework_cost"]) for r in rework_cost if r["original_technician"] == "Tyler Brooks")
    findings = [
        {"tab": "parts", "stat": f'{float(q5[("Parts", "Stocked part was out")]["on_time_pct"]):.0f}%',
         "title": "on-time when a stocked part ran out",
         "body": f'vs {float(q5[("Parts", "All parts on shelf")]["on_time_pct"]):.0f}% when parts were on the shelf. '
                 f'Front brake rotors ran out {rotor["out2025"]} times in 2025 with a reorder point of {rotor["rop"]}; '
                 f'demand supports {rotor["sugRop"]}.'},
        {"tab": "customers", "stat": f'{ret["Finished late"]:.0f}%',
         "title": "of new customers came back after a late first visit",
         "body": f'vs {ret["Finished on time"]:.0f}% when the first job was finished on time (6-month return rate).'},
        {"tab": "techs", "stat": f'{float(tech["Tyler Brooks"]["comeback_rate_pct"]):.1f}%',
         "title": "comeback rate for one technician",
         "body": f'about {float(tech["Tyler Brooks"]["comeback_rate_pct"]) / others_cb:.1f}x the rest of the team '
                 f'({others_cb:.1f}%), costing ${tyler_cost:,.0f} in unbilled rework.'},
        {"tab": "floor", "stat": f'{float(q7["15+ days"]["no_show_pct"]):.0f}%',
         "title": "no-show rate when booked 15+ days ahead",
         "body": f'vs {float(q7["0-2 days"]["no_show_pct"]):.1f}% for bookings made 0-2 days out. '
                 f'{summit["name"]} quotes {summit["quoted"]} days but averages {summit["actual"]}.'},
    ]

    data = {
        "meta": {"epoch": EPOCH.isoformat(), "snapshot": SNAPSHOT,
                 "mechs": [{"name": m["mechanic_name"], "level": m["skill_level"]} for m in mechs],
                 "cats": cats.items, "makes": makes.items, "channels": channels.items, "statuses": statuses.items,
                 "slots": slots.items, "apptStatus": appt_status.items,
                 "parts": [{"sku": p["sku"], "name": p["part_name"], "cat": p["part_category"]} for p in parts]},
        "wo": wo, "pl": pl, "ap": ap, "inventory": inventory, "suppliers": suppliers, "wip": wip,
        "cohort": cohort, "retention": retention, "findings": findings,
    }
    conn.close()

    blob = json.dumps(data, separators=(",", ":"), default=str).replace("</", "<\\/")
    page = TEMPLATE.read_text(encoding="utf-8").replace("__DASHBOARD_DATA__", blob)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    head = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '<style>html{color-scheme:light}body{margin:0;font:14px/1.45 system-ui,sans-serif}'
            'img{max-width:100%}[hidden]{display:none!important}</style>\n')
    # the template is a page fragment (title/style/markup/script); wrap it into a full document
    title_end = page.index("</style>") + len("</style>")
    full = head + page[:title_end] + "\n</head>\n<body>\n" + page[title_end:] + "\n</body>\n</html>\n"
    OUT.write_text(full, encoding="utf-8")
    if len(sys.argv) > 1:                      # optional: also write the bare fragment somewhere
        Path(sys.argv[1]).write_text(page, encoding="utf-8")
    print(f"  wrote {OUT} ({len(full) / 1024:,.0f} KB)")


if __name__ == "__main__":
    main()
