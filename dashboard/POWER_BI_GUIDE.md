# Power BI build guide: Service Ops dashboard

This rebuilds the [web dashboard](../docs/index.html) in Power BI Desktop (free, Windows).
Budget 2–3 hours. Everything you need is in this repo:

| File | What it's for |
|---|---|
| `data/bi/ServiceOps_Dashboard_Data.xlsx` | The data: 7 sheets exported from the SQL views, plus a README sheet with field definitions |
| `dashboard/measures.dax` | Every DAX measure, ready to paste |
| `dashboard/powerbi_theme.json` | Colors and fonts that match the web dashboard |

Screenshot each page when you're done and save them to `docs/img/` so the README can show them.

---

## 1. Load the data

1. **Home → Get data → Excel workbook** → pick `ServiceOps_Dashboard_Data.xlsx`.
2. Tick `WorkOrders`, `WorkOrderParts`, `Appointments`, `PartsInventory`, `Technicians`, `Customers`. Skip `README` and `MonthlyKPIs` (the measures rebuild those numbers).
3. Click **Transform Data** and check the types Power Query guessed:
   - `WorkOrders`: `opened_at`, `promised_at`, `completed_at` → Date/Time; `opened_date` → Date; money and hours columns → Decimal Number; `is_on_time`, `had_stockout`, `had_special_order`, `had_comeback` → Whole Number.
   - `Appointments`: `scheduled_start`, `booked_at` → Date/Time; `scheduled_date` → Date.
4. **Close & Apply**.

## 2. Build the model

1. **View → Themes → Browse for themes** → `powerbi_theme.json`.
2. **Modeling → New table** → paste the `Date` table from `measures.dax`. Then **Table tools → Mark as date table** → `Date[Date]`. Sort `Month` by `Month Num` and `Weekday` by `Weekday Num`.
3. **Home → Enter data** → create an empty table named `_Measures`. Paste every measure from `measures.dax` into it (**New measure** for each).
4. Set measure formats: `%` measures → Percentage, 1 decimal; money → Currency, 0 decimals.
5. **Model view**, draw these relationships (all *many-to-one, single direction*):

| From (many) | To (one) |
|---|---|
| `WorkOrders[opened_date]` | `Date[Date]` |
| `Appointments[scheduled_date]` | `Date[Date]` |
| `WorkOrders[mechanic_id]` | `Technicians[mechanic_id]` |
| `WorkOrders[customer_id]` | `Customers[customer_id]` |
| `WorkOrderParts[work_order_id]` | `WorkOrders[work_order_id]` |

`PartsInventory` stays unrelated on purpose. It's a snapshot as of 2025-12-31, so date filters shouldn't touch it.

This is a star schema: `WorkOrders` and `Appointments` are fact tables; `Date`, `Technicians` and `Customers` are dimensions. Say that in the interview.

## 3. Pages

Canvas: **View → Page view → 16:9**, background `#EEF0EF`, visuals on white cards (`#FCFCFB`, rounded corners 8, no shadow).
Put the same three slicers across the top of every page and **sync** them (**View → Sync slicers**):
`Date[Year]` (dropdown), `Technicians[mechanic_name]`, `WorkOrders[primary_category]`.

### Page 1: Overview
| Visual | Fields |
|---|---|
| 7 × **Card (new)** | Net Sales · Gross Margin % · Car Count · Avg Repair Order · On-Time % · Avg CSAT · No-Show Rate %. Add *Net Sales YoY %* etc. as the reference label |
| **Clustered column** "Net sales by month" | X: `Date[Month Start]` · Y: Net Sales · Tooltips: Gross Profit, Gross Margin %, Car Count |
| **Line** "On-time completion by month" | X: `Date[Month Start]` · Y: On-Time % · Analytics pane → Constant line at 0.9 labeled "Target 90%" |
| **Bar** "Net sales by service category" | Y: `primary_category` · X: Net Sales · sort descending |
| **Bar** "Top 10 vehicle makes" | Y: `make` · X: Net Sales · Filters pane → Top N = 10 by Net Sales · Tooltip: Avg Repair Order |
| **Text box** "What the data says" | 3–4 findings from `report/` in your own words |

### Page 2: Shop floor
| Visual | Fields |
|---|---|
| **Table** "Bay board" | Filter `status` ≠ Completed · columns: work_order_id, status, make, model, primary_service, mechanic_name, opened_at, promised_at · conditional formatting on `status` (Waiting on Parts = amber) |
| **Bar** "What makes a job late" | Y: a calculated column `Parts Status` (below) · X: On-Time % · add a second bar visual for `skill_level` |
| **Matrix heatmap** "Check-in wait by slot" | Rows: `Appointments[scheduled_weekday]` · Columns: `slot_time` · Values: Avg Check-in Wait (min) · Conditional formatting → Background color, gradient `#E4EEFB` → `#104281` |
| **Column** "No-show rate by lead time" | X: `lead_bucket` · Y: No-Show Rate % |

```DAX
Parts Status =                       // calculated column on WorkOrders
SWITCH ( TRUE (),
    WorkOrders[had_stockout] = 1, "Stocked part ran out",
    WorkOrders[had_special_order] = 1, "Special-order part",
    "All parts on shelf" )
```

### Page 3: Technicians
| Visual | Fields |
|---|---|
| **Table** "Scorecard" | `mechanic_name`, `skill_level`, Car Count, Efficiency % (conditional formatting → Data bars), On-Time %, Comeback Rate %, Avg CSAT, Net Sales, Comeback Flag |
| **Line** "Efficiency by month and skill level" | X: `Date[Month Start]` · Y: Efficiency % · Legend: `skill_level` · constant line at 1.0 "Book time" |
| **Bar** "Comeback rate by technician" | Y: `mechanic_name` · X: Comeback Rate % · constant line = Shop Comeback Rate % |

### Page 4: Parts & inventory
| Visual | Fields |
|---|---|
| 4 × **Card** | Stockout Jobs · Avg Parts Wait (days) · Parts Margin % · Inventory Value |
| **Column** "Jobs hit by a stockout" | X: `Date[Month Start]` · Y: Stockout Jobs |
| **Bar** "Parts that ran out most" | Y: `WorkOrderParts[part_name]` · X: Times Out of Stock · Top N = 8 |
| **Clustered bar** "Reorder point: current vs recommended" | Y: `PartsInventory[part_name]` · X: `reorder_point`, `suggested_reorder_point` · filter `times_out_of_stock_2025` > 0 |
| **Table** "Reorder watchlist" | PartsInventory where on_hand + on_order ≤ suggested_reorder_point |

### Page 5: Customers
| Visual | Fields |
|---|---|
| 4 × **Card** | Customers Served · Repeat Rate % · Sales per Customer · Avg CSAT |
| **Bar** "Sales per customer by channel" | Y: `Customers[acquisition_channel]` · X: Sales per Customer · Tooltip: Repeat Rate % |
| **Bar** "What drives a bad review" | Y: `Parts Status` or `is_on_time` · X: Avg CSAT |
| **Filled map** (optional) | Location: `Customers[zip_code]` (Data category = Postal code) · Color: Net Sales |

## 4. Finish and share

- Rename pages, add a title text box on each page, align everything with **Format → Align**.
- Add a **page navigator** (Insert → Buttons → Navigator → Page navigator) under the title.
- **Save as** `dashboard/ServiceOps.pbix` and commit it.
- Power BI's *Publish to web* needs a work or school account. If you don't have one, export each page (**File → Export → PDF**) and add the PDF and screenshots to the repo. That's what recruiters will look at anyway.

## 5. Interview talking points

- **Why a Date table?** Time intelligence (`SAMEPERIODLASTYEAR`, `TOTALYTD`) needs a continuous, marked date table.
- **Why is `PartsInventory` unrelated?** It's a point-in-time snapshot; a date slicer shouldn't filter current stock.
- **Why `DIVIDE` instead of `/`?** It returns blank instead of an error when the denominator is zero.
- **Why do the numbers match the SQL?** Every measure mirrors a definition in `sql/03_views.sql`, so SQL, Power BI and the web dashboard give the same answer.
