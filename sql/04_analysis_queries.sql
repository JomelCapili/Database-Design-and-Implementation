/* =============================================================================
   04_analysis_queries.sql - business questions answered with SQL
   -----------------------------------------------------------------------------
   The 2021 report identified two root problems at the shop:
     (1) jobs and appointments run late, frustrating customers, and
     (2) nobody tracks which parts get used, so the shop runs out of them.
   Each query below answers a specific question a shop owner would ask.
   Techniques used: CTEs, window functions (LAG, RANK, NTILE, SUM/AVG OVER),
   recursive CTEs, conditional aggregation (pivots), self-joins, CASE bucketing.

   Data window: 2024-01-01 to 2025-12-31 (snapshot 2025-12-31 12:00).

   Where the 2021 queries went (see docs/FIX_LOG.md for why each changed):
     2021 Q1, Q7        -> Q12 (parts actually tied to jobs now)
     2021 Q2, Q3, Q12   -> Q14 (unit cost x quantity, margin, by year)
     2021 Q4, Q10       -> Q12, Q15 (units used, not row counts)
     2021 Q5            -> Q8  (open work-order board)
     2021 Q6, Q9, Q13   -> Q5, Q9 (turnaround, on-time, by driver)
     2021 Q8            -> Q1, Q2 (true gross profit incl. technician labor)
     2021 Q11           -> Q4  (no more fan-out double counting)
     2021 Q14           -> Q21
     2021 Q15           -> Q7  (appointments + no-shows)
   ============================================================================= */
USE service_management;


/* =============================================================================
   A. REVENUE & PROFITABILITY
   ============================================================================= */

-- Q1. How are sales and profit trending month to month, and vs. the same month last year?
WITH monthly AS (
    SELECT opened_month,
           SUM(net_sales)    AS net_sales,
           SUM(gross_profit) AS gross_profit
    FROM v_work_order_summary
    GROUP BY opened_month
)
SELECT
    DATE_FORMAT(opened_month, '%Y-%m')                                             AS month,
    ROUND(net_sales, 0)                                                            AS net_sales,
    ROUND(gross_profit / net_sales * 100, 1)                                       AS gross_margin_pct,
    ROUND((net_sales / LAG(net_sales) OVER (ORDER BY opened_month) - 1) * 100, 1)  AS mom_change_pct,
    ROUND((net_sales / LAG(net_sales, 12) OVER (ORDER BY opened_month) - 1) * 100, 1) AS yoy_change_pct,
    ROUND(SUM(net_sales) OVER (PARTITION BY YEAR(opened_month) ORDER BY opened_month), 0) AS ytd_net_sales
FROM monthly
ORDER BY opened_month;


-- Q2. Year-over-year scorecard: did 2025 beat 2024?
WITH yearly AS (
    SELECT opened_year,
           COUNT(*)                                             AS work_orders,
           SUM(job_type = 'Customer Pay')                       AS paid_jobs,
           SUM(net_sales)                                       AS net_sales,
           SUM(gross_profit)                                    AS gross_profit,
           SUM(parts_revenue)                                   AS parts_revenue,
           SUM(parts_cost)                                      AS parts_cost,
           AVG(is_on_time)                                      AS on_time,
           AVG(csat_rating)                                     AS csat
    FROM v_work_order_summary
    GROUP BY opened_year
),
kpis AS (
    SELECT 'Car count (work orders)' AS kpi, 1 AS sort_order,
           MAX(CASE WHEN opened_year = 2024 THEN work_orders END) AS y2024,
           MAX(CASE WHEN opened_year = 2025 THEN work_orders END) AS y2025 FROM yearly
    UNION ALL
    SELECT 'Net sales ($)', 2,
           MAX(CASE WHEN opened_year = 2024 THEN net_sales END),
           MAX(CASE WHEN opened_year = 2025 THEN net_sales END) FROM yearly
    UNION ALL
    SELECT 'Average repair order ($)', 3,
           MAX(CASE WHEN opened_year = 2024 THEN net_sales / paid_jobs END),
           MAX(CASE WHEN opened_year = 2025 THEN net_sales / paid_jobs END) FROM yearly
    UNION ALL
    SELECT 'Gross margin (%)', 4,
           MAX(CASE WHEN opened_year = 2024 THEN gross_profit / net_sales * 100 END),
           MAX(CASE WHEN opened_year = 2025 THEN gross_profit / net_sales * 100 END) FROM yearly
    UNION ALL
    SELECT 'Parts margin (%)', 5,
           MAX(CASE WHEN opened_year = 2024 THEN (parts_revenue - parts_cost) / parts_revenue * 100 END),
           MAX(CASE WHEN opened_year = 2025 THEN (parts_revenue - parts_cost) / parts_revenue * 100 END) FROM yearly
    UNION ALL
    SELECT 'On-time completion (%)', 6,
           MAX(CASE WHEN opened_year = 2024 THEN on_time * 100 END),
           MAX(CASE WHEN opened_year = 2025 THEN on_time * 100 END) FROM yearly
    UNION ALL
    SELECT 'Average CSAT (1-5)', 7,
           MAX(CASE WHEN opened_year = 2024 THEN csat END),
           MAX(CASE WHEN opened_year = 2025 THEN csat END) FROM yearly
)
SELECT kpi,
       ROUND(y2024, 2)                   AS fy2024,
       ROUND(y2025, 2)                   AS fy2025,
       ROUND((y2025 / y2024 - 1) * 100, 1) AS change_pct
FROM kpis
ORDER BY sort_order;


-- Q3. Which service categories drive revenue and profit? (share of total + rank)
SELECT
    primary_category,
    COUNT(*)                                                            AS jobs,
    ROUND(SUM(net_sales), 0)                                            AS net_sales,
    ROUND(SUM(net_sales) / SUM(SUM(net_sales)) OVER () * 100, 1)        AS pct_of_sales,
    ROUND(AVG(net_sales), 0)                                            AS avg_ticket,
    ROUND(SUM(gross_profit) / SUM(net_sales) * 100, 1)                  AS gross_margin_pct,
    RANK() OVER (ORDER BY SUM(gross_profit) DESC)                       AS profit_rank
FROM v_work_order_summary
WHERE job_type = 'Customer Pay'
GROUP BY primary_category
ORDER BY net_sales DESC;


-- Q4. Which vehicle makes bring in the most revenue, and which spend the most per visit?
--     (Replaces 2021 Q11, which joined customer -> vehicle -> bill and double-counted
--      every bill for customers with more than one vehicle.)
SELECT
    make,
    CASE WHEN make IN ('BMW','Mercedes-Benz','Audi','Volkswagen') THEN 'European'
         WHEN make IN ('Lexus') THEN 'Luxury Asian'
         WHEN make IN ('Ford','Chevrolet','GMC','Ram','Dodge','Jeep','Chrysler','Buick') THEN 'Domestic'
         ELSE 'Asian' END                                               AS origin,
    COUNT(*)                                                            AS paid_jobs,
    ROUND(SUM(net_sales), 0)                                            AS net_sales,
    ROUND(AVG(net_sales), 0)                                            AS avg_ticket,
    ROUND(AVG(net_sales) / AVG(AVG(net_sales)) OVER () * 100 - 100, 0)  AS ticket_vs_avg_pct
FROM v_work_order_summary
WHERE job_type = 'Customer Pay'
GROUP BY make
ORDER BY net_sales DESC;


/* =============================================================================
   B. OPERATIONS - WHY ARE JOBS LATE?  (2021 business problem #1)
   ============================================================================= */

-- Q5. Driver analysis: which factors separate late jobs from on-time jobs?
SELECT 'Parts' AS driver,
       CASE WHEN had_stockout = 1 THEN 'Stocked part was out'
            WHEN had_special_order = 1 THEN 'Special-order part (never stocked)'
            ELSE 'All parts on shelf' END                         AS segment,
       COUNT(*) AS jobs, ROUND(AVG(is_on_time) * 100, 1) AS on_time_pct,
       ROUND(AVG(turnaround_hours), 1) AS avg_turnaround_hrs
FROM v_work_order_summary WHERE status = 'Completed' GROUP BY segment
UNION ALL
SELECT 'Technician level', skill_level, COUNT(*), ROUND(AVG(is_on_time) * 100, 1), ROUND(AVG(turnaround_hours), 1)
FROM v_work_order_summary WHERE status = 'Completed' GROUP BY skill_level
UNION ALL
SELECT 'Booking', booking_type, COUNT(*), ROUND(AVG(is_on_time) * 100, 1), ROUND(AVG(turnaround_hours), 1)
FROM v_work_order_summary WHERE status = 'Completed' GROUP BY booking_type
UNION ALL
SELECT 'Season', CASE WHEN MONTH(opened_at) BETWEEN 6 AND 8 THEN 'Summer (Jun-Aug)' ELSE 'Rest of year' END,
       COUNT(*), ROUND(AVG(is_on_time) * 100, 1), ROUND(AVG(turnaround_hours), 1)
FROM v_work_order_summary WHERE status = 'Completed'
GROUP BY CASE WHEN MONTH(opened_at) BETWEEN 6 AND 8 THEN 'Summer (Jun-Aug)' ELSE 'Rest of year' END
ORDER BY driver, on_time_pct;


-- Q6. Are popular appointment slots overbooked? (check-in wait by slot)
SELECT
    slot_time,
    COUNT(*)                                                    AS arrived_appointments,
    ROUND(AVG(bookings_in_slot), 2)                             AS avg_bookings_per_slot,
    ROUND(AVG(checkin_wait_min), 1)                             AS avg_checkin_wait_min,
    ROUND(AVG(checkin_wait_min > 15) * 100, 1)                  AS pct_wait_over_15_min,
    ROUND(AVG(bookings_in_slot >= 3) * 100, 1)                  AS pct_in_overbooked_slot
FROM v_appointment_summary
WHERE status = 'Arrived'
GROUP BY slot_time
ORDER BY slot_time;


-- Q7. Who no-shows? No-show rate by how far ahead the appointment was booked and weekday
SELECT
    lead_bucket,
    SUM(status IN ('Arrived','No-Show','Cancelled'))                                   AS appointments,
    ROUND(SUM(status = 'No-Show')   / SUM(status IN ('Arrived','No-Show','Cancelled')) * 100, 1) AS no_show_pct,
    ROUND(SUM(status = 'Cancelled') / SUM(status IN ('Arrived','No-Show','Cancelled')) * 100, 1) AS cancel_pct,
    ROUND(SUM(status = 'No-Show' AND weekday_num = 2)
          / NULLIF(SUM(status IN ('Arrived','No-Show','Cancelled') AND weekday_num = 2), 0) * 100, 1) AS monday_no_show_pct
FROM v_appointment_summary
GROUP BY lead_bucket
ORDER BY MIN(lead_days);


-- Q8. Shop-floor board: every open work order right now, oldest first
--     (Replaces 2021 Q5, which found "incomplete" work by a misspelled status.)
SELECT
    ws.work_order_id,
    ws.status,
    ws.mechanic_name,
    CONCAT(ws.model_year, ' ', ws.make, ' ', ws.model)                        AS vehicle,
    ws.primary_service,
    ws.opened_at,
    ws.promised_at,
    ROUND(TIMESTAMPDIFF(MINUTE, ws.opened_at, '2025-12-31 12:00:00') / 60, 1) AS age_hours,
    CASE WHEN ws.promised_at < '2025-12-31 12:00:00' THEN 'PAST PROMISE' ELSE 'On track' END AS promise_status,
    (SELECT GROUP_CONCAT(p.sku ORDER BY p.sku)
       FROM part_order po JOIN part p ON p.part_id = po.part_id
      WHERE po.work_order_id = ws.work_order_id AND po.received_date IS NULL)  AS parts_in_transit
FROM v_work_order_summary ws
WHERE ws.status <> 'Completed'
ORDER BY ws.opened_at;


/* =============================================================================
   C. TECHNICIANS
   ============================================================================= */

-- Q9. Technician scorecard, ranked, with each metric compared to the shop average
SELECT
    mechanic_name,
    skill_level,
    work_orders,
    efficiency_pct,
    RANK() OVER (ORDER BY efficiency_pct DESC)                               AS efficiency_rank,
    on_time_pct,
    ROUND(on_time_pct - AVG(on_time_pct) OVER (), 1)                         AS on_time_vs_avg,
    comeback_rate_pct,
    ROUND(comeback_rate_pct / AVG(comeback_rate_pct) OVER (), 2)             AS comeback_vs_avg_x,
    avg_csat,
    CASE WHEN comeback_rate_pct > 2 * AVG(comeback_rate_pct) OVER () THEN 'Quality review'
         WHEN efficiency_pct < 85 THEN 'Coaching / mentoring'
         ELSE 'On track' END                                                 AS action
FROM v_mechanic_scorecard
ORDER BY efficiency_rank;


-- Q10. Is the apprentice program working? Efficiency by quarter with quarter-over-quarter change
WITH q AS (
    SELECT mechanic_name,
           CONCAT(YEAR(opened_at), '-Q', QUARTER(opened_at))                AS quarter,
           SUM(hours_billed) / SUM(hours_actual) * 100                      AS efficiency_pct,
           COUNT(*)                                                         AS jobs
    FROM v_work_order_summary
    WHERE skill_level = 'Apprentice' AND job_type = 'Customer Pay'
    GROUP BY mechanic_name, CONCAT(YEAR(opened_at), '-Q', QUARTER(opened_at))
)
SELECT mechanic_name, quarter, jobs,
       ROUND(efficiency_pct, 1)                                                          AS efficiency_pct,
       ROUND(efficiency_pct - LAG(efficiency_pct) OVER (PARTITION BY mechanic_name ORDER BY quarter), 1) AS qoq_change_pts
FROM q
ORDER BY mechanic_name, quarter;


-- Q11. What do comebacks cost? Warranty rework cost traced back to the original technician
SELECT
    orig.mechanic_name                                          AS original_technician,
    COUNT(*)                                                    AS comebacks,
    ROUND(SUM(rw.hours_actual), 1)                              AS rework_hours,
    ROUND(SUM(rw.labor_cost + rw.parts_cost), 2)                AS rework_cost,
    ROUND(SUM(rw.labor_cost + rw.parts_cost) / COUNT(*), 2)     AS cost_per_comeback,
    ROUND(AVG(orig_fb.rating), 2)                               AS avg_rating_on_original_job
FROM v_work_order_summary rw
JOIN v_work_order_summary orig ON orig.work_order_id = rw.parent_work_order_id     -- self-join
LEFT JOIN customer_feedback orig_fb ON orig_fb.work_order_id = orig.work_order_id
WHERE rw.job_type = 'Warranty Rework'
GROUP BY orig.mechanic_name
ORDER BY rework_cost DESC;


/* =============================================================================
   D. INVENTORY - WHY DO WE RUN OUT OF PARTS?  (2021 business problem #2)
   ============================================================================= */

-- Q12. Which stocked parts ran out, what did it cost us in time, and what should the reorder point be?
WITH impact AS (
    SELECT wop.part_id,
           COUNT(*)                          AS jobs_delayed,
           AVG(ws.is_on_time) * 100          AS on_time_pct,
           AVG(ws.parts_wait_days)           AS avg_wait_days
    FROM work_order_part wop
    JOIN v_work_order_summary ws ON ws.work_order_id = wop.work_order_id
    WHERE wop.was_in_stock = 0 AND ws.opened_year = 2025
    GROUP BY wop.part_id
)
SELECT
    inv.sku,
    inv.part_name,
    inv.supplier_name,
    inv.times_out_of_stock_2025,
    ROUND(i.on_time_pct, 1)                         AS on_time_pct_when_out,
    ROUND(i.avg_wait_days, 1)                       AS avg_days_waiting,
    inv.reorder_point                               AS current_reorder_point,
    inv.suggested_reorder_point,
    inv.suggested_reorder_point - inv.reorder_point AS raise_by,
    inv.on_hand,
    inv.on_order
FROM v_part_inventory inv
JOIN impact i ON i.part_id = inv.part_id
WHERE inv.is_special_order_only = 0
ORDER BY inv.times_out_of_stock_2025 DESC
LIMIT 10;


-- Q13. Supplier scorecard: do vendors deliver when they say they will?
SELECT
    s.supplier_name,
    s.quoted_lead_days,
    COUNT(*)                                                             AS orders_received,
    ROUND(AVG(DATEDIFF(po.received_date, po.ordered_date)), 1)           AS avg_actual_lead_days,
    ROUND(AVG(po.received_date > po.expected_date) * 100, 1)             AS pct_delivered_late,
    MAX(DATEDIFF(po.received_date, po.expected_date))                    AS worst_days_late,
    ROUND(SUM(po.quantity * po.unit_cost), 0)                            AS spend
FROM part_order po
JOIN part p     ON p.part_id = po.part_id
JOIN supplier s ON s.supplier_id = p.supplier_id
WHERE po.order_type <> 'Opening Balance' AND po.received_date IS NOT NULL
GROUP BY s.supplier_id, s.supplier_name, s.quoted_lead_days
ORDER BY pct_delivered_late DESC;


-- Q14. Parts margin by category, 2024 vs 2025 - are supplier price increases squeezing us?
WITH cat AS (
    SELECT p.part_category,
           YEAR(w.opened_at)                          AS yr,
           SUM(wop.quantity)                          AS units,
           SUM(wop.quantity * wop.unit_price)         AS revenue,
           SUM(wop.quantity * wop.unit_cost)          AS cost
    FROM work_order_part wop
    JOIN part p       ON p.part_id = wop.part_id
    JOIN work_order w ON w.work_order_id = wop.work_order_id
    WHERE wop.unit_price > 0                                   -- exclude no-charge warranty parts
    GROUP BY p.part_category, YEAR(w.opened_at)
)
SELECT
    part_category,
    SUM(CASE WHEN yr = 2025 THEN units END)                                         AS units_2025,
    ROUND(SUM(CASE WHEN yr = 2025 THEN revenue END), 0)                             AS revenue_2025,
    ROUND(SUM(CASE WHEN yr = 2024 THEN (revenue - cost) / revenue END) * 100, 1)    AS margin_2024_pct,
    ROUND(SUM(CASE WHEN yr = 2025 THEN (revenue - cost) / revenue END) * 100, 1)    AS margin_2025_pct,
    ROUND((SUM(CASE WHEN yr = 2025 THEN (revenue - cost) / revenue END)
         - SUM(CASE WHEN yr = 2024 THEN (revenue - cost) / revenue END)) * 100, 1)  AS change_pts
FROM cat
GROUP BY part_category
ORDER BY revenue_2025 DESC;


-- Q15. Seasonality: how much busier is each category in summer? (monthly index, 100 = average month)
WITH m AS (
    SELECT primary_category, MONTH(opened_at) AS mon, COUNT(*) AS jobs
    FROM v_work_order_summary
    WHERE job_type = 'Customer Pay'
    GROUP BY primary_category, MONTH(opened_at)
),
idx AS (
    SELECT primary_category, mon,
           jobs / AVG(jobs) OVER (PARTITION BY primary_category) * 100 AS season_index
    FROM m
)
SELECT primary_category,
       ROUND(MAX(CASE WHEN mon = 1  THEN season_index END)) AS jan,
       ROUND(MAX(CASE WHEN mon = 2  THEN season_index END)) AS feb,
       ROUND(MAX(CASE WHEN mon = 3  THEN season_index END)) AS mar,
       ROUND(MAX(CASE WHEN mon = 4  THEN season_index END)) AS apr,
       ROUND(MAX(CASE WHEN mon = 5  THEN season_index END)) AS may,
       ROUND(MAX(CASE WHEN mon = 6  THEN season_index END)) AS jun,
       ROUND(MAX(CASE WHEN mon = 7  THEN season_index END)) AS jul,
       ROUND(MAX(CASE WHEN mon = 8  THEN season_index END)) AS aug,
       ROUND(MAX(CASE WHEN mon = 9  THEN season_index END)) AS sep,
       ROUND(MAX(CASE WHEN mon = 10 THEN season_index END)) AS oct,
       ROUND(MAX(CASE WHEN mon = 11 THEN season_index END)) AS nov,
       ROUND(MAX(CASE WHEN mon = 12 THEN season_index END)) AS `dec`,
       ROUND(MAX(season_index) / MIN(season_index), 1)      AS peak_to_trough
FROM idx
GROUP BY primary_category
ORDER BY peak_to_trough DESC;


/* =============================================================================
   E. CUSTOMERS
   ============================================================================= */

-- Q16. Does a late job cost us the customer?
--      Of customers acquired 2024-01 to 2025-06 (so everyone has 6 months to come back),
--      what share returned within 180 days - split by how their FIRST visit went?
WITH ranked AS (
    SELECT ws.customer_id, ws.opened_at, ws.is_on_time, ws.had_stockout, ws.had_comeback,
           ROW_NUMBER() OVER (PARTITION BY ws.customer_id ORDER BY ws.opened_at)   AS visit_no,
           LEAD(ws.opened_at) OVER (PARTITION BY ws.customer_id ORDER BY ws.opened_at) AS next_visit_at
    FROM v_work_order_summary ws
    JOIN customer c ON c.customer_id = ws.customer_id
    WHERE ws.job_type = 'Customer Pay'
      AND c.customer_since >= '2024-01-01' AND c.company_name IS NULL
),
first_visits AS (
    SELECT *,
           (next_visit_at IS NOT NULL AND next_visit_at <= opened_at + INTERVAL 180 DAY) AS returned_180d
    FROM ranked
    WHERE visit_no = 1 AND opened_at < '2025-07-01'
)
SELECT 'All new customers' AS first_visit_experience, COUNT(*) AS customers,
       ROUND(AVG(returned_180d) * 100, 1) AS returned_within_180d_pct
FROM first_visits
UNION ALL
SELECT CASE WHEN is_on_time = 1 THEN 'Finished on time' ELSE 'Finished late' END,
       COUNT(*), ROUND(AVG(returned_180d) * 100, 1)
FROM first_visits GROUP BY is_on_time
UNION ALL
SELECT 'Job needed a comeback', COUNT(*), ROUND(AVG(returned_180d) * 100, 1)
FROM first_visits WHERE had_comeback = 1;


-- Q17. Cohort retention: of customers first seen in each quarter, what % came back in later quarters?
WITH visits AS (
    SELECT ws.customer_id,
           YEAR(ws.opened_at) * 4 + QUARTER(ws.opened_at) - 1                      AS q_index
    FROM v_work_order_summary ws
    JOIN customer c ON c.customer_id = ws.customer_id
    WHERE ws.job_type = 'Customer Pay' AND c.customer_since >= '2024-01-01'
),
cohort AS (
    SELECT customer_id, MIN(q_index) AS cohort_q FROM visits GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT v.customer_id, c.cohort_q, v.q_index - c.cohort_q AS q_offset
    FROM visits v JOIN cohort c ON c.customer_id = v.customer_id
)
SELECT
    CONCAT(FLOOR(cohort_q / 4), '-Q', MOD(cohort_q, 4) + 1)                      AS cohort,
    COUNT(DISTINCT CASE WHEN q_offset = 0 THEN customer_id END)                  AS customers,
    -- NULL = that quarter hasn't happened yet for this cohort (last full quarter is 2025-Q4)
    CASE WHEN cohort_q + 1 <= 2025 * 4 + 3 THEN ROUND(COUNT(DISTINCT CASE WHEN q_offset = 1 THEN customer_id END)
        / COUNT(DISTINCT CASE WHEN q_offset = 0 THEN customer_id END) * 100, 1) END AS q1_later_pct,
    CASE WHEN cohort_q + 2 <= 2025 * 4 + 3 THEN ROUND(COUNT(DISTINCT CASE WHEN q_offset = 2 THEN customer_id END)
        / COUNT(DISTINCT CASE WHEN q_offset = 0 THEN customer_id END) * 100, 1) END AS q2_later_pct,
    CASE WHEN cohort_q + 3 <= 2025 * 4 + 3 THEN ROUND(COUNT(DISTINCT CASE WHEN q_offset = 3 THEN customer_id END)
        / COUNT(DISTINCT CASE WHEN q_offset = 0 THEN customer_id END) * 100, 1) END AS q3_later_pct,
    CASE WHEN cohort_q + 4 <= 2025 * 4 + 3 THEN ROUND(COUNT(DISTINCT CASE WHEN q_offset = 4 THEN customer_id END)
        / COUNT(DISTINCT CASE WHEN q_offset = 0 THEN customer_id END) * 100, 1) END AS q4_later_pct
FROM activity
GROUP BY cohort_q
ORDER BY cohort_q;


-- Q18. Which marketing channels bring the most valuable customers?
SELECT
    acquisition_channel,
    COUNT(*)                                                    AS customers_acquired,
    ROUND(AVG(visits > 1) * 100, 1)                             AS repeat_rate_pct,
    ROUND(AVG(visits), 2)                                       AS avg_visits,
    ROUND(AVG(lifetime_net_sales), 0)                           AS avg_sales_per_customer,
    ROUND(SUM(lifetime_net_sales), 0)                           AS total_sales,
    ROUND(AVG(avg_csat), 2)                                     AS avg_csat
FROM v_customer_summary
WHERE acquired_in_period = 1 AND visits > 0
GROUP BY acquisition_channel
ORDER BY avg_sales_per_customer DESC;


-- Q19. RFM segmentation: who are our best customers, and who is slipping away?
WITH rfm AS (
    SELECT customer_id, customer_name, acquisition_channel, visits, lifetime_net_sales, days_since_last_visit,
           NTILE(5) OVER (ORDER BY days_since_last_visit DESC) AS r_score,   -- 5 = most recent
           NTILE(5) OVER (ORDER BY visits)                     AS f_score,
           NTILE(5) OVER (ORDER BY lifetime_net_sales)         AS m_score
    FROM v_customer_summary
    WHERE visits > 0
),
segmented AS (
    SELECT *,
           CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
                WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
                WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
                WHEN r_score <= 2 AND m_score >= 4                  THEN 'At risk (high value)'
                WHEN r_score <= 2                                   THEN 'Lapsed'
                ELSE 'Needs attention' END                          AS segment
    FROM rfm
)
SELECT segment,
       COUNT(*)                                                     AS customers,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1)             AS pct_customers,
       ROUND(SUM(lifetime_net_sales) / SUM(SUM(lifetime_net_sales)) OVER () * 100, 1) AS pct_sales,
       ROUND(AVG(lifetime_net_sales), 0)                            AS avg_sales,
       ROUND(AVG(days_since_last_visit), 0)                         AS avg_days_since_visit
FROM segmented
GROUP BY segment
ORDER BY pct_sales DESC;


-- Q20. What drives a bad review? CSAT by experience
SELECT 'Overall' AS experience, COUNT(*) AS reviews, ROUND(AVG(csat_rating), 2) AS avg_rating,
       ROUND(AVG(csat_rating <= 2) * 100, 1) AS pct_1_2_star
FROM v_work_order_summary WHERE csat_rating IS NOT NULL
UNION ALL
SELECT CASE WHEN is_on_time = 1 THEN 'Finished on time' ELSE 'Finished late' END,
       COUNT(*), ROUND(AVG(csat_rating), 2), ROUND(AVG(csat_rating <= 2) * 100, 1)
FROM v_work_order_summary WHERE csat_rating IS NOT NULL GROUP BY is_on_time
UNION ALL
SELECT 'Waited on a special-order part', COUNT(*), ROUND(AVG(csat_rating), 2), ROUND(AVG(csat_rating <= 2) * 100, 1)
FROM v_work_order_summary WHERE csat_rating IS NOT NULL AND had_special_order = 1
UNION ALL
SELECT 'Job later needed a comeback', COUNT(*), ROUND(AVG(csat_rating), 2), ROUND(AVG(csat_rating <= 2) * 100, 1)
FROM v_work_order_summary WHERE csat_rating IS NOT NULL AND had_comeback = 1
UNION ALL
SELECT 'Waited 15+ min at check-in', COUNT(*), ROUND(AVG(csat_rating), 2), ROUND(AVG(csat_rating <= 2) * 100, 1)
FROM v_work_order_summary WHERE csat_rating IS NOT NULL AND checkin_wait_min >= 15;


/* =============================================================================
   F. FINANCE
   ============================================================================= */

-- Q21. How are customers paying, and how is it shifting? (share of payments per half-year)
--      (Replaces 2021 Q14.)
WITH p AS (
    SELECT CONCAT(YEAR(paid_at), '-H', IF(MONTH(paid_at) <= 6, 1, 2)) AS period, payment_method, amount
    FROM payment
)
SELECT payment_method,
       ROUND(SUM(CASE WHEN period = '2024-H1' THEN 1 ELSE 0 END) / (SELECT COUNT(*) FROM p WHERE period = '2024-H1') * 100, 1) AS `2024_H1_pct`,
       ROUND(SUM(CASE WHEN period = '2024-H2' THEN 1 ELSE 0 END) / (SELECT COUNT(*) FROM p WHERE period = '2024-H2') * 100, 1) AS `2024_H2_pct`,
       ROUND(SUM(CASE WHEN period = '2025-H1' THEN 1 ELSE 0 END) / (SELECT COUNT(*) FROM p WHERE period = '2025-H1') * 100, 1) AS `2025_H1_pct`,
       ROUND(SUM(CASE WHEN period = '2025-H2' THEN 1 ELSE 0 END) / (SELECT COUNT(*) FROM p WHERE period = '2025-H2') * 100, 1) AS `2025_H2_pct`,
       ROUND(SUM(amount), 0)                                                                                               AS total_collected
FROM p
GROUP BY payment_method
ORDER BY total_collected DESC;


-- Q22. Accounts receivable aging as of the snapshot (who owes us, and for how long?)
SELECT
    CASE WHEN DATEDIFF('2025-12-31', it.invoice_date) <= 30 THEN '0-30 days'
         WHEN DATEDIFF('2025-12-31', it.invoice_date) <= 60 THEN '31-60 days'
         ELSE '61+ days' END                                     AS age_bucket,
    COUNT(*)                                                     AS open_invoices,
    COUNT(DISTINCT c.customer_id)                                AS accounts,
    ROUND(SUM(it.balance_due), 2)                                AS balance_due,
    ROUND(SUM(it.balance_due) / SUM(SUM(it.balance_due)) OVER () * 100, 1) AS pct_of_ar
FROM v_invoice_totals it
JOIN work_order w ON w.work_order_id = it.work_order_id
JOIN vehicle v    ON v.vehicle_id = w.vehicle_id
JOIN customer c   ON c.customer_id = v.customer_id
WHERE it.balance_due > 0
GROUP BY age_bucket
ORDER BY MIN(DATEDIFF('2025-12-31', it.invoice_date));
