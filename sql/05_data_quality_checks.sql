/* =============================================================================
   05_data_quality_checks.sql - automated data-quality test suite
   -----------------------------------------------------------------------------
   Constraints in 01_schema.sql already block most bad data at the door
   (foreign keys, CHECKs, UNIQUEs). These checks cover the business rules that
   span multiple rows or tables, which a single-row constraint cannot see.

   Every check returns the number of violating rows. Expected result: 0 / PASS.
   Run after loading data, and after any bulk change.
   ============================================================================= */
USE service_management;

WITH RECURSIVE
positions AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM positions WHERE n < 17),

-- VIN check digit (ISO 3779): transliterate each character, weight it, sum, mod 11
vin_calc AS (
    SELECT v.vehicle_id, v.vin,
           MOD(SUM(
               CASE WHEN SUBSTRING(v.vin, p.n, 1) REGEXP '[0-9]'
                    THEN CAST(SUBSTRING(v.vin, p.n, 1) AS UNSIGNED)
                    ELSE CAST(SUBSTRING('A1B2C3D4E5F6G7H8J1K2L3M4N5P7R9S2T3U4V5W6X7Y8Z9',
                                        LOCATE(SUBSTRING(v.vin, p.n, 1),
                                               'A1B2C3D4E5F6G7H8J1K2L3M4N5P7R9S2T3U4V5W6X7Y8Z9') + 1, 1) AS UNSIGNED)
               END * CAST(ELT(p.n, 8,7,6,5,4,3,2,10,0,9,8,7,6,5,4,3,2) AS UNSIGNED)
           ), 11) AS check_value
    FROM vehicle v
    CROSS JOIN positions p
    GROUP BY v.vehicle_id, v.vin
),

-- Stock ledger: +received into stock, -pulled off the shelf, in date order
stock_events AS (
    SELECT part_id, received_date AS event_date, 0 AS seq, quantity AS qty
    FROM part_order
    WHERE order_type <> 'Special Order' AND received_date IS NOT NULL
    UNION ALL
    SELECT wop.part_id, DATE(w.opened_at), 1, -wop.quantity
    FROM work_order_part wop
    JOIN work_order w ON w.work_order_id = wop.work_order_id
    WHERE wop.was_in_stock = 1
),
stock_running AS (
    SELECT part_id, event_date,
           SUM(qty) OVER (PARTITION BY part_id ORDER BY event_date, seq
                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance
    FROM stock_events
),

checks AS (
    -- 1 ---------------------------------------------------------------------
    SELECT 1 AS id, 'Every customer owns at least one vehicle' AS check_name,
           (SELECT COUNT(*) FROM customer c
             WHERE NOT EXISTS (SELECT 1 FROM vehicle v WHERE v.customer_id = c.customer_id)) AS violations
    UNION ALL
    -- 2 ---------------------------------------------------------------------
    SELECT 2, 'No duplicate customers (same name + phone)',
           (SELECT COALESCE(SUM(n - 1), 0) FROM (
                SELECT COUNT(*) AS n FROM customer WHERE phone IS NOT NULL
                GROUP BY first_name, last_name, phone HAVING COUNT(*) > 1) d)
    UNION ALL
    -- 3 ---------------------------------------------------------------------
    SELECT 3, 'VIN check digit (position 9) is valid',
           (SELECT COUNT(*) FROM vin_calc
             WHERE SUBSTRING(vin, 9, 1) <> IF(check_value = 10, 'X', CAST(check_value AS CHAR)))
    UNION ALL
    -- 4 ---------------------------------------------------------------------
    SELECT 4, 'Work order vehicle matches its appointment vehicle',
           (SELECT COUNT(*) FROM work_order w
              JOIN appointment a ON a.appointment_id = w.appointment_id
             WHERE a.vehicle_id <> w.vehicle_id)
    UNION ALL
    -- 5 ---------------------------------------------------------------------
    SELECT 5, 'Arrived appointments have a work order; no-shows/cancels/scheduled do not',
           (SELECT COUNT(*) FROM appointment a
              LEFT JOIN work_order w ON w.appointment_id = a.appointment_id
             WHERE (a.status = 'Arrived') <> (w.work_order_id IS NOT NULL))
    UNION ALL
    -- 6 ---------------------------------------------------------------------
    SELECT 6, 'Scheduled appointments are at/after the snapshot; others are before it',
           (SELECT COUNT(*) FROM appointment
             WHERE (status = 'Scheduled') <> (scheduled_start >= '2025-12-31 12:00:00'))
    UNION ALL
    -- 7 ---------------------------------------------------------------------
    SELECT 7, 'Customer existed before their first booking or visit',
           (SELECT COUNT(*) FROM customer c
              JOIN vehicle v ON v.customer_id = c.customer_id
              JOIN appointment a ON a.vehicle_id = v.vehicle_id
             WHERE a.booked_at < c.customer_since)
    UNION ALL
    -- 8 ---------------------------------------------------------------------
    SELECT 8, 'Work orders only assigned to mechanics employed that day',
           (SELECT COUNT(*) FROM work_order w
              JOIN mechanic m ON m.mechanic_id = w.mechanic_id
             WHERE DATE(w.opened_at) < m.hire_date
                OR (m.termination_date IS NOT NULL AND DATE(w.opened_at) > m.termination_date))
    UNION ALL
    -- 9 ---------------------------------------------------------------------
    SELECT 9, 'Odometer never goes backwards for a vehicle',
           (SELECT COUNT(*) FROM (
                SELECT odometer_miles,
                       LAG(odometer_miles) OVER (PARTITION BY vehicle_id ORDER BY opened_at) AS prev_odometer
                FROM work_order) o
             WHERE o.odometer_miles < o.prev_odometer)
    UNION ALL
    -- 10 --------------------------------------------------------------------
    SELECT 10, 'Every completed customer-pay job has exactly one invoice',
           (SELECT COUNT(*) FROM work_order w
              LEFT JOIN invoice i ON i.work_order_id = w.work_order_id
             WHERE w.status = 'Completed' AND w.parent_work_order_id IS NULL AND i.invoice_id IS NULL)
    UNION ALL
    -- 11 --------------------------------------------------------------------
    SELECT 11, 'Warranty reworks are never invoiced and never billed',
           (SELECT COUNT(*) FROM work_order w
             WHERE w.parent_work_order_id IS NOT NULL
               AND (EXISTS (SELECT 1 FROM invoice i WHERE i.work_order_id = w.work_order_id)
                 OR EXISTS (SELECT 1 FROM work_order_service s WHERE s.work_order_id = w.work_order_id AND s.hours_billed > 0)
                 OR EXISTS (SELECT 1 FROM work_order_part p WHERE p.work_order_id = w.work_order_id AND p.unit_price > 0)))
    UNION ALL
    -- 12 --------------------------------------------------------------------
    SELECT 12, 'A rework follows its original job on the same vehicle',
           (SELECT COUNT(*) FROM work_order r
              JOIN work_order o ON o.work_order_id = r.parent_work_order_id
             WHERE r.vehicle_id <> o.vehicle_id OR r.opened_at <= o.completed_at)
    UNION ALL
    -- 13 --------------------------------------------------------------------
    SELECT 13, 'Invoice dated the day the job was completed',
           (SELECT COUNT(*) FROM invoice i JOIN work_order w ON w.work_order_id = i.work_order_id
             WHERE i.invoice_date <> DATE(w.completed_at))
    UNION ALL
    -- 14 --------------------------------------------------------------------
    SELECT 14, 'No invoice is overpaid',
           (SELECT COUNT(*) FROM v_invoice_totals WHERE amount_paid > invoice_total)
    UNION ALL
    -- 15 --------------------------------------------------------------------
    SELECT 15, 'Retail invoices are paid in full (except cars finished today, not yet picked up)',
           (SELECT COUNT(*) FROM v_invoice_totals it
              JOIN work_order w ON w.work_order_id = it.work_order_id
              JOIN vehicle v    ON v.vehicle_id = w.vehicle_id
              JOIN customer c   ON c.customer_id = v.customer_id
             WHERE c.company_name IS NULL AND it.balance_due <> 0 AND it.invoice_date < '2025-12-31')
    UNION ALL
    -- 16 --------------------------------------------------------------------
    SELECT 16, 'Payments happen after the job is completed',
           (SELECT COUNT(*) FROM payment p
              JOIN invoice i    ON i.invoice_id = p.invoice_id
              JOIN work_order w ON w.work_order_id = i.work_order_id
             WHERE p.paid_at < w.completed_at)
    UNION ALL
    -- 17 --------------------------------------------------------------------
    SELECT 17, 'Feedback submitted after the job was completed',
           (SELECT COUNT(*) FROM customer_feedback f
              JOIN work_order w ON w.work_order_id = f.work_order_id
             WHERE w.completed_at IS NULL OR f.submitted_at < w.completed_at)
    UNION ALL
    -- 18 --------------------------------------------------------------------
    SELECT 18, 'Out-of-stock part lines have a matching special order (and vice versa)',
           (SELECT COUNT(*) FROM work_order_part wop
             WHERE (wop.was_in_stock = 0) <> EXISTS (
                   SELECT 1 FROM part_order po
                    WHERE po.work_order_id = wop.work_order_id AND po.part_id = wop.part_id
                      AND po.order_type = 'Special Order'))
    UNION ALL
    -- 19 --------------------------------------------------------------------
    SELECT 19, '"Waiting on Parts" jobs really have a part in transit',
           (SELECT COUNT(*) FROM work_order w
             WHERE w.status = 'Waiting on Parts'
               AND NOT EXISTS (SELECT 1 FROM part_order po
                                WHERE po.work_order_id = w.work_order_id AND po.received_date IS NULL))
    UNION ALL
    -- 20 --------------------------------------------------------------------
    SELECT 20, 'Stock on hand never goes negative (running ledger)',
           (SELECT COUNT(*) FROM stock_running WHERE balance < 0)
)
SELECT id,
       check_name,
       violations,
       IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY id;
