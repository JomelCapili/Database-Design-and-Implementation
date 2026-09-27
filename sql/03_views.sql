/* =============================================================================
   03_views.sql - reporting layer
   -----------------------------------------------------------------------------
   These views turn the normalized tables into analysis-ready "facts" so that
   the dashboard (Power BI / Tableau / HTML) and ad-hoc queries all use ONE
   definition of every metric.

     v_invoice_totals       one row per invoice: labor, parts, discount, tax, total, paid, balance
     v_work_order_summary   one row per work order: the main fact table (revenue, cost, timing, CSAT)
     v_appointment_summary  one row per appointment: lead time, slot, outcome, check-in wait
     v_part_inventory       one row per part: on hand, on order, usage, stockouts, suggested reorder point
     v_mechanic_scorecard   one row per technician: productivity, quality, speed
     v_monthly_kpis         one row per month: the executive KPI set
     v_customer_summary     one row per customer: visits, lifetime value, recency, satisfaction

   Metric definitions (used everywhere)
     Net sales      = labor + parts - discount           (excludes sales tax)
     Gross profit   = net sales - parts cost - technician labor cost (hours_actual x wage)
     On-time        = completed_at <= promised_at
     Efficiency     = hours billed / hours actually clocked   (>100% = faster than book time)
     Comeback rate  = customer-pay jobs that needed a warranty rework / customer-pay jobs
     ARO            = average repair order = net sales / invoiced work orders
   ============================================================================= */
USE service_management;

-- -----------------------------------------------------------------------------
-- v_invoice_totals
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_invoice_totals AS
WITH labor AS (
    SELECT work_order_id, SUM(hours_billed * labor_rate) AS labor_amount
    FROM work_order_service
    GROUP BY work_order_id
),
parts AS (
    SELECT work_order_id, SUM(quantity * unit_price) AS parts_amount
    FROM work_order_part
    GROUP BY work_order_id
),
paid AS (
    SELECT invoice_id, SUM(amount) AS amount_paid, MAX(paid_at) AS last_paid_at
    FROM payment
    GROUP BY invoice_id
)
SELECT
    i.invoice_id,
    i.work_order_id,
    i.invoice_date,
    CAST(COALESCE(l.labor_amount, 0) AS DECIMAL(10,2))                       AS labor_amount,
    CAST(COALESCE(p.parts_amount, 0) AS DECIMAL(10,2))                       AS parts_amount,
    i.discount_amount,
    i.discount_reason,
    ROUND(COALESCE(p.parts_amount, 0) * i.tax_rate, 2)                       AS tax_amount,
    CAST(COALESCE(l.labor_amount, 0) + COALESCE(p.parts_amount, 0)
         - i.discount_amount AS DECIMAL(10,2))                               AS net_sales,
    CAST(COALESCE(l.labor_amount, 0) + COALESCE(p.parts_amount, 0) - i.discount_amount
         + ROUND(COALESCE(p.parts_amount, 0) * i.tax_rate, 2) AS DECIMAL(10,2)) AS invoice_total,
    CAST(COALESCE(pd.amount_paid, 0) AS DECIMAL(10,2))                       AS amount_paid,
    CAST(COALESCE(l.labor_amount, 0) + COALESCE(p.parts_amount, 0) - i.discount_amount
         + ROUND(COALESCE(p.parts_amount, 0) * i.tax_rate, 2)
         - COALESCE(pd.amount_paid, 0) AS DECIMAL(10,2))                     AS balance_due,
    pd.last_paid_at
FROM invoice i
LEFT JOIN labor l  ON l.work_order_id = i.work_order_id
LEFT JOIN parts p  ON p.work_order_id = i.work_order_id
LEFT JOIN paid  pd ON pd.invoice_id   = i.invoice_id;

-- -----------------------------------------------------------------------------
-- v_work_order_summary  (main fact table)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_work_order_summary AS
WITH labor AS (
    SELECT wos.work_order_id,
           COUNT(*)                                    AS service_count,
           SUM(wos.hours_billed)                       AS hours_billed,
           SUM(wos.hours_actual)                       AS hours_actual,
           SUM(wos.hours_billed * wos.labor_rate)      AS labor_revenue
    FROM work_order_service wos
    GROUP BY wos.work_order_id
),
primary_service AS (          -- the biggest job on the ticket defines its category
    SELECT work_order_id, service_name, service_category
    FROM (
        SELECT wos.work_order_id, st.service_name, st.service_category,
               ROW_NUMBER() OVER (PARTITION BY wos.work_order_id
                                  ORDER BY st.book_hours DESC, st.service_type_id) AS rn
        FROM work_order_service wos
        JOIN service_type st ON st.service_type_id = wos.service_type_id
    ) ranked
    WHERE rn = 1
),
parts AS (
    SELECT wop.work_order_id,
           SUM(wop.quantity * wop.unit_price)                               AS parts_revenue,
           SUM(wop.quantity * wop.unit_cost)                                AS parts_cost,
           MAX(wop.was_in_stock = 0)                                        AS had_special_order,
           MAX(wop.was_in_stock = 0 AND p.reorder_qty > 0)                  AS had_stockout
    FROM work_order_part wop
    JOIN part p ON p.part_id = wop.part_id
    GROUP BY wop.work_order_id
),
parts_wait AS (
    SELECT work_order_id, MAX(DATEDIFF(COALESCE(received_date, '2025-12-31'), ordered_date)) AS parts_wait_days
    FROM part_order
    WHERE order_type = 'Special Order'
    GROUP BY work_order_id
),
reworked AS (
    SELECT DISTINCT parent_work_order_id AS work_order_id
    FROM work_order
    WHERE parent_work_order_id IS NOT NULL
)
SELECT
    w.work_order_id,
    w.opened_at,
    DATE(w.opened_at)                                                   AS opened_date,
    CAST(DATE_FORMAT(w.opened_at, '%Y-%m-01') AS DATE)                  AS opened_month,
    YEAR(w.opened_at)                                                   AS opened_year,
    DAYNAME(w.opened_at)                                                AS opened_weekday,
    w.promised_at,
    w.completed_at,
    w.status,
    CASE WHEN w.parent_work_order_id IS NULL THEN 'Customer Pay' ELSE 'Warranty Rework' END AS job_type,
    w.parent_work_order_id,
    (rw.work_order_id IS NOT NULL)                                      AS had_comeback,
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)                              AS customer_name,
    c.acquisition_channel,
    (c.company_name IS NOT NULL)                                        AS is_fleet,
    c.zip_code,
    v.vehicle_id,
    v.make,
    v.model,
    v.model_year,
    YEAR(w.opened_at) - v.model_year                                    AS vehicle_age,
    w.odometer_miles,
    m.mechanic_id,
    CONCAT(m.first_name, ' ', m.last_name)                              AS mechanic_name,
    m.skill_level,
    CASE WHEN w.appointment_id IS NULL THEN 'Walk-in' ELSE 'Appointment' END AS booking_type,
    CASE WHEN w.appointment_id IS NULL THEN NULL
         ELSE TIMESTAMPDIFF(MINUTE, a.scheduled_start, w.opened_at) END AS checkin_wait_min,
    ps.service_name                                                     AS primary_service,
    ps.service_category                                                 AS primary_category,
    l.service_count,
    l.hours_billed,
    l.hours_actual,
    CAST(l.labor_revenue AS DECIMAL(10,2))                              AS labor_revenue,
    CAST(COALESCE(pt.parts_revenue, 0) AS DECIMAL(10,2))                AS parts_revenue,
    CAST(COALESCE(pt.parts_cost, 0) AS DECIMAL(10,2))                   AS parts_cost,
    CAST(l.hours_actual * m.hourly_wage AS DECIMAL(10,2))               AS labor_cost,
    COALESCE(i.discount_amount, 0)                                      AS discount_amount,
    CAST(l.labor_revenue + COALESCE(pt.parts_revenue, 0)
         - COALESCE(i.discount_amount, 0) AS DECIMAL(10,2))             AS net_sales,
    CAST(l.labor_revenue + COALESCE(pt.parts_revenue, 0) - COALESCE(i.discount_amount, 0)
         - COALESCE(pt.parts_cost, 0) - l.hours_actual * m.hourly_wage AS DECIMAL(10,2)) AS gross_profit,
    ROUND(TIMESTAMPDIFF(MINUTE, w.opened_at, w.completed_at) / 60, 2)  AS turnaround_hours,
    CASE WHEN w.completed_at IS NULL THEN NULL
         ELSE (w.completed_at <= w.promised_at) END                     AS is_on_time,
    CASE WHEN w.completed_at > w.promised_at
         THEN ROUND(TIMESTAMPDIFF(MINUTE, w.promised_at, w.completed_at) / 60, 2)
         ELSE 0 END                                                     AS hours_late,
    COALESCE(pt.had_special_order, 0)                                   AS had_special_order,
    COALESCE(pt.had_stockout, 0)                                        AS had_stockout,
    pw.parts_wait_days,
    i.invoice_id,
    f.rating                                                            AS csat_rating
FROM work_order w
JOIN vehicle   v  ON v.vehicle_id  = w.vehicle_id
JOIN customer  c  ON c.customer_id = v.customer_id
JOIN mechanic  m  ON m.mechanic_id = w.mechanic_id
JOIN labor     l  ON l.work_order_id = w.work_order_id
JOIN primary_service ps ON ps.work_order_id = w.work_order_id
LEFT JOIN parts      pt ON pt.work_order_id = w.work_order_id
LEFT JOIN parts_wait pw ON pw.work_order_id = w.work_order_id
LEFT JOIN reworked   rw ON rw.work_order_id = w.work_order_id
LEFT JOIN appointment a ON a.appointment_id = w.appointment_id
LEFT JOIN invoice     i ON i.work_order_id  = w.work_order_id
LEFT JOIN customer_feedback f ON f.work_order_id = w.work_order_id;

-- -----------------------------------------------------------------------------
-- v_appointment_summary
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_appointment_summary AS
SELECT
    a.appointment_id,
    a.booked_at,
    a.scheduled_start,
    DATE(a.scheduled_start)                                        AS scheduled_date,
    CAST(DATE_FORMAT(a.scheduled_start, '%Y-%m-01') AS DATE)       AS scheduled_month,
    DAYNAME(a.scheduled_start)                                     AS scheduled_weekday,
    DAYOFWEEK(a.scheduled_start)                                   AS weekday_num,
    TIME_FORMAT(a.scheduled_start, '%H:%i')                        AS slot_time,
    DATEDIFF(a.scheduled_start, a.booked_at)                       AS lead_days,
    CASE WHEN DATEDIFF(a.scheduled_start, a.booked_at) <= 2  THEN '0-2 days'
         WHEN DATEDIFF(a.scheduled_start, a.booked_at) <= 7  THEN '3-7 days'
         WHEN DATEDIFF(a.scheduled_start, a.booked_at) <= 14 THEN '8-14 days'
         ELSE '15+ days' END                                       AS lead_bucket,
    a.status,
    c.customer_id,
    c.acquisition_channel,
    (c.company_name IS NOT NULL)                                   AS is_fleet,
    w.work_order_id,
    TIMESTAMPDIFF(MINUTE, a.scheduled_start, w.opened_at)          AS checkin_wait_min,
    COUNT(*) OVER (PARTITION BY a.scheduled_start)                 AS bookings_in_slot
FROM appointment a
JOIN vehicle  v ON v.vehicle_id  = a.vehicle_id
JOIN customer c ON c.customer_id = v.customer_id
LEFT JOIN work_order w ON w.appointment_id = a.appointment_id;

-- -----------------------------------------------------------------------------
-- v_part_inventory  (as of the snapshot, 2025-12-31)
--   on_hand = everything received into stock - everything taken off the shelf.
--   Special orders are excluded from both sides (they arrive for one job and
--   go straight onto that car).
--   suggested_reorder_point = demand during lead time + safety stock
--        = avg daily use x avg actual lead time + 1.65 x sigma(daily use) x sqrt(lead time)
--   (1.65 = 95% service level). Uses 2025 business days.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_part_inventory AS
WITH RECURSIVE calendar AS (
    SELECT DATE('2025-01-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM calendar WHERE d < '2025-12-31'
),
business_days AS (
    SELECT d FROM calendar WHERE DAYOFWEEK(d) <> 1          -- open Mon-Sat
),
daily_use AS (
    SELECT wop.part_id, DATE(w.opened_at) AS d, SUM(wop.quantity) AS qty
    FROM work_order_part wop
    JOIN work_order w ON w.work_order_id = wop.work_order_id
    WHERE w.opened_at >= '2025-01-01'
    GROUP BY wop.part_id, DATE(w.opened_at)
),
demand AS (
    SELECT p.part_id,
           AVG(COALESCE(du.qty, 0))         AS avg_daily_use,
           STDDEV_SAMP(COALESCE(du.qty, 0)) AS sd_daily_use,
           SUM(COALESCE(du.qty, 0))         AS units_used_2025
    FROM part p
    CROSS JOIN business_days bd
    LEFT JOIN daily_use du ON du.part_id = p.part_id AND du.d = bd.d
    GROUP BY p.part_id
),
received AS (
    SELECT part_id, SUM(quantity) AS qty_in
    FROM part_order
    WHERE order_type <> 'Special Order' AND received_date IS NOT NULL
    GROUP BY part_id
),
in_transit AS (
    SELECT part_id, SUM(quantity) AS qty_on_order
    FROM part_order
    WHERE received_date IS NULL
    GROUP BY part_id
),
used AS (
    SELECT part_id, SUM(quantity) AS qty_out
    FROM work_order_part
    WHERE was_in_stock = 1
    GROUP BY part_id
),
lead_time AS (
    SELECT part_id, AVG(DATEDIFF(received_date, ordered_date)) AS avg_lead_days
    FROM part_order
    WHERE order_type <> 'Opening Balance' AND received_date IS NOT NULL
    GROUP BY part_id
),
stockouts AS (
    SELECT wop.part_id,
           COUNT(*)                                              AS special_order_lines,
           SUM(w.opened_at >= '2025-01-01')                      AS special_order_lines_2025
    FROM work_order_part wop
    JOIN work_order w ON w.work_order_id = wop.work_order_id
    WHERE wop.was_in_stock = 0
    GROUP BY wop.part_id
)
SELECT
    p.part_id,
    p.sku,
    p.part_name,
    p.part_category,
    s.supplier_name,
    s.quoted_lead_days,
    ROUND(COALESCE(lt.avg_lead_days, s.quoted_lead_days), 1)                   AS avg_actual_lead_days,
    p.unit_cost,
    p.unit_price,
    (p.reorder_qty = 0)                                                        AS is_special_order_only,
    CAST(COALESCE(r.qty_in, 0) - COALESCE(u.qty_out, 0) AS SIGNED)             AS on_hand,
    COALESCE(t.qty_on_order, 0)                                                AS on_order,
    CAST((COALESCE(r.qty_in, 0) - COALESCE(u.qty_out, 0)) * p.unit_cost AS DECIMAL(10,2)) AS inventory_value,
    p.reorder_point,
    p.reorder_qty,
    d.units_used_2025,
    ROUND(d.avg_daily_use, 3)                                                  AS avg_daily_use,
    COALESCE(so.special_order_lines, 0)                                        AS times_out_of_stock,
    COALESCE(so.special_order_lines_2025, 0)                                   AS times_out_of_stock_2025,
    CASE WHEN p.reorder_qty = 0 THEN NULL
         ELSE CEILING(d.avg_daily_use * COALESCE(lt.avg_lead_days, s.quoted_lead_days)
                      + 1.65 * d.sd_daily_use * SQRT(COALESCE(lt.avg_lead_days, s.quoted_lead_days)))
    END                                                                        AS suggested_reorder_point,
    CASE WHEN d.avg_daily_use > 0
         THEN ROUND((COALESCE(r.qty_in, 0) - COALESCE(u.qty_out, 0)) / d.avg_daily_use, 1)
    END                                                                        AS days_of_supply
FROM part p
JOIN supplier s   ON s.supplier_id = p.supplier_id
JOIN demand   d   ON d.part_id = p.part_id
LEFT JOIN received   r  ON r.part_id  = p.part_id
LEFT JOIN in_transit t  ON t.part_id  = p.part_id
LEFT JOIN used       u  ON u.part_id  = p.part_id
LEFT JOIN lead_time  lt ON lt.part_id = p.part_id
LEFT JOIN stockouts  so ON so.part_id = p.part_id;

-- -----------------------------------------------------------------------------
-- v_mechanic_scorecard
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_mechanic_scorecard AS
SELECT
    m.mechanic_id,
    CONCAT(m.first_name, ' ', m.last_name)                                AS mechanic_name,
    m.skill_level,
    m.hire_date,
    m.termination_date,
    COUNT(*)                                                              AS work_orders,
    SUM(ws.job_type = 'Customer Pay')                                     AS customer_pay_jobs,
    ROUND(SUM(ws.hours_billed), 1)                                        AS hours_billed,
    ROUND(SUM(ws.hours_actual), 1)                                        AS hours_actual,
    ROUND(SUM(ws.hours_billed) / SUM(ws.hours_actual) * 100, 1)           AS efficiency_pct,
    ROUND(SUM(ws.net_sales), 2)                                           AS net_sales,
    ROUND(SUM(ws.gross_profit), 2)                                        AS gross_profit,
    ROUND(AVG(ws.is_on_time) * 100, 1)                                    AS on_time_pct,
    ROUND(AVG(ws.turnaround_hours), 1)                                    AS avg_turnaround_hours,
    ROUND(SUM(ws.had_comeback) / SUM(ws.job_type = 'Customer Pay') * 100, 2) AS comeback_rate_pct,
    ROUND(AVG(ws.csat_rating), 2)                                         AS avg_csat,
    COUNT(ws.csat_rating)                                                 AS csat_responses
FROM mechanic m
JOIN v_work_order_summary ws ON ws.mechanic_id = m.mechanic_id
GROUP BY m.mechanic_id, m.first_name, m.last_name, m.skill_level, m.hire_date, m.termination_date;

-- -----------------------------------------------------------------------------
-- v_monthly_kpis
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_kpis AS
WITH wo AS (
    SELECT opened_month                                            AS month,
           COUNT(*)                                                AS work_orders,
           SUM(job_type = 'Customer Pay')                          AS customer_pay_jobs,
           SUM(net_sales)                                          AS net_sales,
           SUM(gross_profit)                                       AS gross_profit,
           SUM(parts_revenue)                                      AS parts_revenue,
           SUM(parts_cost)                                         AS parts_cost,
           AVG(is_on_time)                                         AS on_time_rate,
           AVG(turnaround_hours)                                   AS avg_turnaround_hours,
           AVG(had_stockout)                                       AS stockout_rate,
           AVG(csat_rating)                                        AS avg_csat,
           COUNT(DISTINCT customer_id)                             AS unique_customers
    FROM v_work_order_summary
    GROUP BY opened_month
),
appt AS (
    SELECT scheduled_month                                         AS month,
           SUM(status = 'No-Show') / SUM(status IN ('Arrived','No-Show','Cancelled')) AS no_show_rate
    FROM v_appointment_summary
    GROUP BY scheduled_month
),
new_cust AS (
    SELECT CAST(DATE_FORMAT(customer_since, '%Y-%m-01') AS DATE)   AS month,
           COUNT(*)                                                AS new_customers
    FROM customer
    WHERE customer_since >= '2024-01-01'
    GROUP BY 1
)
SELECT
    wo.month,
    wo.work_orders,
    wo.unique_customers,
    COALESCE(nc.new_customers, 0)                                  AS new_customers,
    ROUND(wo.net_sales, 2)                                         AS net_sales,
    ROUND(wo.gross_profit, 2)                                      AS gross_profit,
    ROUND(wo.gross_profit / wo.net_sales * 100, 1)                 AS gross_margin_pct,
    ROUND((wo.parts_revenue - wo.parts_cost) / wo.parts_revenue * 100, 1) AS parts_margin_pct,
    ROUND(wo.net_sales / wo.customer_pay_jobs, 2)                  AS avg_repair_order,
    ROUND(wo.on_time_rate * 100, 1)                                AS on_time_pct,
    ROUND(wo.avg_turnaround_hours, 1)                              AS avg_turnaround_hours,
    ROUND(wo.stockout_rate * 100, 1)                               AS stockout_rate_pct,
    ROUND(wo.avg_csat, 2)                                          AS avg_csat,
    ROUND(ap.no_show_rate * 100, 1)                                AS no_show_pct
FROM wo
LEFT JOIN appt     ap ON ap.month = wo.month
LEFT JOIN new_cust nc ON nc.month = wo.month;

-- -----------------------------------------------------------------------------
-- v_customer_summary
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_summary AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)                           AS customer_name,
    c.company_name,
    c.acquisition_channel,
    c.zip_code,
    c.customer_since,
    (c.customer_since >= '2024-01-01')                               AS acquired_in_period,
    COUNT(DISTINCT v.vehicle_id)                                     AS vehicles,
    COUNT(ws.work_order_id)                                          AS visits,
    MIN(ws.opened_date)                                              AS first_visit,
    MAX(ws.opened_date)                                              AS last_visit,
    DATEDIFF('2025-12-31', MAX(ws.opened_date))                      AS days_since_last_visit,
    ROUND(COALESCE(SUM(ws.net_sales), 0), 2)                         AS lifetime_net_sales,
    ROUND(AVG(ws.csat_rating), 2)                                    AS avg_csat,
    ROUND(AVG(ws.is_on_time) * 100, 1)                               AS on_time_pct
FROM customer c
JOIN vehicle v ON v.customer_id = c.customer_id
LEFT JOIN v_work_order_summary ws ON ws.vehicle_id = v.vehicle_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.company_name, c.acquisition_channel,
         c.zip_code, c.customer_since;
