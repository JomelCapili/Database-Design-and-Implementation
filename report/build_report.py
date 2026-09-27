#!/usr/bin/env python3
"""
build_report.py - assemble the database report

Fills report/report_template.html with live row counts and a data dictionary
read from MySQL's information_schema, writes report/report.html, then prints
report/Database_Report_v2.pdf with headless Chromium (Playwright, via print_pdf.js).

Usage
  pip install pymysql
  npm install -g playwright   (or any Playwright install with Chromium)
  python3 report/build_report.py
"""

import html
import os
import subprocess
from pathlib import Path

import pymysql

HERE = Path(__file__).resolve().parent
DB = "service_management"

ENTITIES = [
    ("Customers", [
        ("customer", "A retail driver or fleet account, with how they found the shop"),
        ("vehicle", "A car owned by a customer, identified by a validated VIN"),
        ("appointment", "A booking for one vehicle at one time, and whether they showed up"),
        ("customer_feedback", "A 1–5 star survey response for one completed job"),
    ]),
    ("Operations", [
        ("work_order", "One visit / repair order: timing, promise, status, responsible technician"),
        ("work_order_service", "A labor line: one service on one job, hours billed vs. clocked"),
        ("service_type", "The menu of labor operations with flat-rate book hours"),
        ("mechanic", "A technician: skill level, wage, employment dates"),
    ]),
    ("Inventory", [
        ("work_order_part", "A part installed on a job, its price at the time, and whether it was in stock"),
        ("part", "The parts catalog with reorder point and reorder quantity"),
        ("part_order", "Parts entering stock: opening balance, replenishment, or special order for a job"),
        ("supplier", "A parts vendor and its quoted lead time"),
    ]),
    ("Finance", [
        ("invoice", "The bill for one customer-pay job; totals are derived in a view"),
        ("payment", "Money received against an invoice (split payments allowed)"),
    ]),
]

DESCRIPTIONS = {
    "customer.company_name": "Fleet accounts only (CHECK ties it to the channel)",
    "customer.acquisition_channel": "How the customer found the shop",
    "customer.customer_since": "First contact (booking or visit)",
    "vehicle.vin": "17 chars, no I/O/Q; check digit verified by DQ test 3",
    "appointment.booked_at": "When the booking was made",
    "appointment.status": "Scheduled, Arrived, No-Show, Cancelled",
    "work_order.appointment_id": "NULL for walk-ins",
    "work_order.mechanic_id": "The single responsible technician",
    "work_order.parent_work_order_id": "Set on warranty reworks: the original job",
    "work_order.promised_at": "Completion time promised at drop-off",
    "work_order.status": "Open, In Progress, Waiting on Parts, Completed",
    "work_order_service.hours_billed": "Flat-rate hours charged (0 on warranty rework)",
    "work_order_service.hours_actual": "Hours the technician clocked",
    "work_order_service.labor_rate": "Shop rate at the time ($140 in 2024, $150 in 2025)",
    "work_order_part.unit_cost": "Cost at the time of use",
    "work_order_part.unit_price": "Price charged (0 on warranty rework)",
    "work_order_part.was_in_stock": "FALSE = special-ordered for this job",
    "part.reorder_point": "Reorder when on hand + on order falls to this",
    "part.reorder_qty": "0 = special-order only, never stocked",
    "part_order.work_order_id": "Set only for special orders",
    "part_order.received_date": "NULL = still in transit",
    "invoice.tax_rate": "Applied to parts only (Nevada does not tax repair labor)",
    "invoice.discount_reason": "Required whenever a discount is given",
    "payment.payment_method": "Card, cash, mobile wallet, or ACH / check (fleet)",
    "customer_feedback.rating": "1–5 stars",
    "mechanic.hourly_wage": "Current wage; used for labor cost",
    "service_type.book_hours": "Standard flat-rate labor time",
    "supplier.quoted_lead_days": "Lead time the supplier promises",
}


def connect():
    return pymysql.connect(host=os.environ.get("MYSQL_HOST", "localhost"), user=os.environ.get("MYSQL_USER", "root"),
                           password=os.environ.get("MYSQL_PASSWORD", ""), database=DB, charset="utf8mb4")


def main():
    conn = connect()
    cur = conn.cursor()

    rows = []
    for area, tables in ENTITIES:
        rows.append(f'<tr><td colspan="3" style="font-weight:600;color:#1c5cab;padding-top:6pt">{area}</td></tr>')
        for t, desc in tables:
            cur.execute(f"SELECT COUNT(*) FROM `{t}`")
            n = cur.fetchone()[0]
            rows.append(f'<tr><td><code>{t}</code></td><td>{html.escape(desc)}</td><td class="n">{n:,}</td></tr>')
    cur.execute("""SELECT SUM(TABLE_ROWS) FROM information_schema.TABLES WHERE TABLE_SCHEMA=%s AND TABLE_TYPE='BASE TABLE'""", (DB,))

    cur.execute("""SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
                   FROM information_schema.KEY_COLUMN_USAGE
                   WHERE TABLE_SCHEMA=%s AND REFERENCED_TABLE_NAME IS NOT NULL""", (DB,))
    fks = {(r[0], r[1]): f"{r[2]}.{r[3]}" for r in cur.fetchall()}
    cur.execute("""SELECT tc.TABLE_NAME, kcu.COLUMN_NAME, tc.CONSTRAINT_TYPE
                   FROM information_schema.TABLE_CONSTRAINTS tc
                   JOIN information_schema.KEY_COLUMN_USAGE kcu
                     ON kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME AND kcu.TABLE_NAME = tc.TABLE_NAME
                    AND kcu.TABLE_SCHEMA = tc.TABLE_SCHEMA
                   WHERE tc.TABLE_SCHEMA=%s AND tc.CONSTRAINT_TYPE IN ('PRIMARY KEY','UNIQUE')""", (DB,))
    keys = {}
    for t, c, typ in cur.fetchall():
        keys.setdefault((t, c), set()).add("PK" if typ == "PRIMARY KEY" else "UQ")
    cur.execute("""SELECT TABLE_NAME, CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS
                   WHERE TABLE_SCHEMA=%s AND CONSTRAINT_TYPE='CHECK' ORDER BY CONSTRAINT_NAME""", (DB,))
    checks = {}
    for t, name in cur.fetchall():
        checks.setdefault(t, []).append(name)
    cur.execute("""SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, EXTRA
                   FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=%s ORDER BY TABLE_NAME, ORDINAL_POSITION""", (DB,))
    cols = {}
    for t, c, typ, nullable, extra in cur.fetchall():
        cols.setdefault(t, []).append((c, typ, nullable, extra))

    order = [t for _, tables in ENTITIES for t, _ in tables]
    parts = []
    for t in order:
        parts.append(f"<h4>{t}</h4><table><tr><th style='width:27%'>Column</th><th style='width:17%'>Type</th>"
                     f"<th style='width:8%'>Null</th><th style='width:22%'>Key</th><th>Notes</th></tr>")
        for c, typ, nullable, extra in cols[t]:
            k = sorted(keys.get((t, c), set()))
            if (t, c) in fks:
                k.append("FK → " + fks[(t, c)])
            if "auto_increment" in extra:
                k.append("auto")
            parts.append(f"<tr><td>{c}</td><td>{html.escape(typ.upper())}</td><td>{'yes' if nullable == 'YES' else ''}</td>"
                         f"<td>{html.escape(', '.join(k))}</td><td>{html.escape(DESCRIPTIONS.get(f'{t}.{c}', ''))}</td></tr>")
        parts.append("</table>")
        if checks.get(t):
            parts.append(f"<p class='small' style='margin-top:-6pt'>CHECK constraints: {', '.join('<code>' + n + '</code>' for n in checks[t])}</p>")
    conn.close()

    page = (HERE / "report_template.html").read_text(encoding="utf-8")
    page = page.replace("<!--ROW_COUNTS-->", "\n".join(rows)).replace("<!--DATA_DICTIONARY-->", "\n".join(parts))
    out_html = HERE / "report.html"
    out_html.write_text(page, encoding="utf-8")
    print(f"  wrote {out_html}")
    subprocess.run(["node", str(HERE / "print_pdf.js"), str(out_html), str(HERE / "Database_Report_v2.pdf")], check=True)


if __name__ == "__main__":
    main()
