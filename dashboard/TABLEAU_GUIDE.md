# Tableau build guide: Service Ops dashboard

This rebuilds the [web dashboard](../docs/index.html) in **Tableau Public** (free, Windows or Mac).
Tableau Public is the best choice for a portfolio: you get a public link you can put on your resume and LinkedIn.
Budget 2–3 hours.

Data: `data/bi/ServiceOps_Dashboard_Data.xlsx` (7 sheets exported from the SQL views; the README sheet defines every field).

---

## 1. Connect

1. **Connect → Microsoft Excel** → `ServiceOps_Dashboard_Data.xlsx`.
2. Drag **WorkOrders** onto the canvas. Then drag **Technicians**, **Customers** and **WorkOrderParts** next to it. Tableau creates *relationships* (the noodles). Set them to:
   - WorkOrders `mechanic_id` = Technicians `mechanic_id`
   - WorkOrders `customer_id` = Customers `customer_id`
   - WorkOrders `work_order_id` = WorkOrderParts `work_order_id`
3. **Appointments** and **PartsInventory** answer different questions. Add each as its own data source (**Data → New Data Source**, same file) instead of relating them.
4. Check field types: `Opened Date`, `Scheduled Date` → Date; `Zip Code` → String, then **Geographic Role → ZIP Code/Postcode**.

## 2. Calculated fields (WorkOrders source)

```
// Gross Margin %
SUM([Gross Profit]) / SUM([Net Sales])

// Customer Pay Jobs
SUM(IF [Job Type] = "Customer Pay" THEN 1 ELSE 0 END)

// Avg Repair Order
SUM([Net Sales]) / [Customer Pay Jobs]

// On-Time %            (blank for open jobs, so AVG skips them)
AVG([Is On Time])

// Stockout Rate %
AVG([Had Stockout])

// Efficiency %
SUM([Hours Billed]) / SUM([Hours Actual])

// Comeback Rate %
SUM(IF [Job Type] = "Customer Pay" THEN [Had Comeback] ELSE 0 END) / [Customer Pay Jobs]

// Parts Status
IF [Had Stockout] = 1 THEN "Stocked part ran out"
ELSEIF [Had Special Order] = 1 THEN "Special-order part"
ELSE "All parts on shelf" END

// Season
IF MONTH([Opened Date]) >= 6 AND MONTH([Opened Date]) <= 8 THEN "Summer (Jun-Aug)" ELSE "Rest of year" END

// Net Sales YoY %     (table calculation: compute using Year of Opened Date)
(ZN(SUM([Net Sales])) - LOOKUP(ZN(SUM([Net Sales])), -1)) / ABS(LOOKUP(ZN(SUM([Net Sales])), -1))
```

Appointments source:
```
// No-Show Rate %
SUM(IF [Status] = "No-Show" THEN 1 ELSE 0 END) / SUM(IF [Status] <> "Scheduled" THEN 1 ELSE 0 END)
```

PartsInventory source:
```
// Reorder Gap
[Suggested Reorder Point] - [Reorder Point]

// Needs Reorder
[Is Special Order Only] = 0 AND [On Hand] + [On Order] <= [Suggested Reorder Point]
```

## 3. Colors

Paste this into `Documents/My Tableau Repository/Preferences.tps`, restart Tableau, and pick **Service Ops** in any color legend:

```xml
<?xml version='1.0'?>
<workbook>
  <preferences>
    <color-palette name="Service Ops" type="regular">
      <color>#2A78D6</color><color>#EB6834</color><color>#1BAF7A</color><color>#EDA100</color>
      <color>#E87BA4</color><color>#008300</color><color>#4A3AA7</color><color>#E34948</color>
    </color-palette>
    <color-palette name="Service Ops Blues" type="ordered-sequential">
      <color>#E4EEFB</color><color>#B7D3F6</color><color>#86B6EF</color><color>#5598E7</color>
      <color>#2A78D6</color><color>#1C5CAB</color><color>#104281</color>
    </color-palette>
  </preferences>
</workbook>
```

Style rules that keep it looking professional: one color per chart unless color *means* something, light gray gridlines, no borders, bars thinner than their gaps, and titles that state the finding ("Stockouts wreck on-time rates"), not the chart type.

## 4. Sheets

| Sheet | Build |
|---|---|
| **KPI – Net Sales** (repeat for each KPI) | Text mark: `SUM(Net Sales)`; add `Net Sales YoY %` below it |
| **Sales by Month** | Columns: `MONTH(Opened Date)` (continuous) · Rows: `SUM(Net Sales)` · Bar |
| **On-Time Trend** | Columns: `MONTH(Opened Date)` · Rows: `On-Time %` · Line · Analytics → Reference Line constant 0.9 "Target 90%" |
| **Category Mix** | Rows: `Primary Category` · Columns: `SUM(Net Sales)` · sort descending · label with Percent of Total quick table calc |
| **Late Drivers** | Rows: `Parts Status` · Columns: `On-Time %` · Bar · reference line at 0.9 |
| **Check-in Heatmap** (Appointments) | Columns: `Slot Time` · Rows: `Scheduled Weekday` · Color: `AVG(Checkin Wait Min)` with *Service Ops Blues* · Square mark |
| **No-Shows by Lead Time** (Appointments) | Columns: `Lead Bucket` · Rows: `No-Show Rate %` |
| **Tech Scorecard** | Rows: `Mechanic Name` · Measure Names/Values: Efficiency %, On-Time %, Comeback Rate %, AVG(Csat Rating) · Text table |
| **Comebacks** | Rows: `Mechanic Name` · Columns: `Comeback Rate %` · Average reference line |
| **Reorder Points** (PartsInventory) | Rows: `Part Name` · Columns: Measure Values (`Reorder Point`, `Suggested Reorder Point`) · Circle marks joined with a Line (dual axis, synchronized) = dumbbell · Filter `Times Out Of Stock 2025` > 0 |
| **Customer Map** | Double-click `Zip Code` · Color: `SUM(Net Sales)` · Detail: `COUNTD(Customer Id)`. Tableau geocodes ZIPs for free, which Power BI can't do as easily |

## 5. Dashboards

Make **five dashboards** (Overview, Shop Floor, Technicians, Parts & Inventory, Customers) at a fixed **1200 × 900** size:
- A title bar on each with the same filters: `YEAR(Opened Date)`, `Mechanic Name`, `Primary Category`. Right-click each filter → **Apply to Worksheets → All Using This Data Source**.
- KPI sheets across the top, two charts per row below.
- Add navigation buttons (Objects → **Navigation**) between the five dashboards, or combine them into one **Story**.
- On the Overview, add a text box with 3–4 findings and the recommendation for each.

## 6. Publish

1. **File → Save to Tableau Public** (create a free account).
2. On the viz page, click the settings gear and allow **Show Viz on Profile**. Add a description that says the data is synthetic and links to this GitHub repo.
3. Copy the link and put it in the README, on your resume, and in LinkedIn's *Featured* section.
