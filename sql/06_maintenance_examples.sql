/* =============================================================================
   06_maintenance_examples.sql - safe UPDATE / DELETE patterns
   -----------------------------------------------------------------------------
   The 2021 script ended with 7 UPDATEs and 7 DELETEs. Six of the seven
   DELETEs failed when run (foreign keys, a column that didn't exist, a type
   mismatch, a misnamed table) and several statements targeted rows by
   non-unique values. This
   file shows how each of those tasks should be done.

   Rules followed here
     * Always target rows by PRIMARY KEY, never by a phone number, time or price.
     * Wrap multi-step changes in a transaction so they succeed or fail together.
     * Don't delete history (customers, mechanics, invoices) - change its state.
     * Guard deletes with NOT EXISTS so they can't orphan or fail on child rows.

   Every block ends in ROLLBACK, so this script is safe to run repeatedly
   and leaves the data exactly as loaded. Change ROLLBACK to COMMIT to apply.
   ============================================================================= */
USE service_management;


-- -----------------------------------------------------------------------------
-- 1. Update a customer's phone number            (2021: fine, but no transaction)
-- -----------------------------------------------------------------------------
START TRANSACTION;
UPDATE customer
   SET phone = '(702) 555-0199'
 WHERE customer_id = 17;                                  -- by primary key
SELECT customer_id, first_name, last_name, phone FROM customer WHERE customer_id = 17;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 2. Rename a mechanic         (2021: WHERE phone_number = '...' - not unique!)
-- -----------------------------------------------------------------------------
START TRANSACTION;
UPDATE mechanic
   SET first_name = 'AJ', last_name = 'Hunter'
 WHERE mechanic_id = 5;                                   -- the key, not a phone number
SELECT mechanic_id, first_name, last_name FROM mechanic WHERE mechanic_id = 5;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 3. Close out a job and invoice it in one atomic step
--    (2021: UPDATE service SET service_status = 'Complete' ... with a
--     misspelled default of 'incomeplete' and nothing stopping bad values)
-- -----------------------------------------------------------------------------
START TRANSACTION;
SET @wo := (SELECT MIN(work_order_id) FROM work_order WHERE status = 'In Progress');

UPDATE work_order
   SET status = 'Completed', completed_at = '2025-12-31 11:45:00'
 WHERE work_order_id = @wo;                               -- ck_work_order_status_date keeps status and date in sync

INSERT INTO invoice (work_order_id, invoice_date, discount_amount, discount_reason, tax_rate)
VALUES (@wo, '2025-12-31', 0.00, NULL, 0.08375);

SELECT * FROM v_invoice_totals WHERE work_order_id = @wo;  -- total is derived, never typed in
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 4. Give a customer 20% off     (2021: UPDATE bill SET total_bill = total_bill * .80
--    - overwrote the original amount, so the discount was invisible afterwards)
-- -----------------------------------------------------------------------------
START TRANSACTION;
SET @inv := 11;
SELECT invoice_id, net_sales, invoice_total FROM v_invoice_totals WHERE invoice_id = @inv;
UPDATE invoice i
  JOIN v_invoice_totals t ON t.invoice_id = i.invoice_id
   SET i.discount_amount = ROUND((t.labor_amount + t.parts_amount) * 0.20, 2),
       i.discount_reason = 'Manager goodwill (20%)'
 WHERE i.invoice_id = @inv;
SELECT invoice_id, net_sales, discount_amount, discount_reason, invoice_total
  FROM v_invoice_totals WHERE invoice_id = @inv;           -- audit trail: amount AND reason recorded
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 5. Reschedule an appointment                (2021: fine, but no validation)
-- -----------------------------------------------------------------------------
START TRANSACTION;
SET @appt := (SELECT MIN(appointment_id) FROM appointment WHERE status = 'Scheduled');
UPDATE appointment
   SET scheduled_start = '2026-01-06 09:30:00'
 WHERE appointment_id = @appt
   AND status = 'Scheduled'                               -- can't move a visit that already happened
   AND '2026-01-06 09:30:00' > NOW() - INTERVAL 100 YEAR; -- placeholder for "not in the past" in a live system
SELECT appointment_id, scheduled_start, status FROM appointment WHERE appointment_id = @appt;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 6. Update a part's catalog price             (2021: price stored as a quoted string)
--    Historical invoices don't change, because each job line kept the price
--    that was charged at the time.
-- -----------------------------------------------------------------------------
START TRANSACTION;
UPDATE part SET unit_price = 104.99 WHERE part_id = 16;
SELECT (SELECT unit_price FROM part WHERE part_id = 16)                  AS new_catalog_price,
       (SELECT MAX(unit_price) FROM work_order_part WHERE part_id = 16)  AS highest_price_ever_charged;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 7. A mechanic leaves the company   (2021: DELETE FROM mechanic ... failed on FK)
--    Never delete an employee with work history - record the termination.
-- -----------------------------------------------------------------------------
START TRANSACTION;
UPDATE mechanic SET termination_date = '2025-12-31' WHERE mechanic_id = 7;
SELECT mechanic_id, first_name, last_name, hire_date, termination_date FROM mechanic WHERE mechanic_id = 7;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 8. Cancel an appointment   (2021: DELETE FROM appointment WHERE appt_time = '4:42 PM'
--    - silently deleted every appointment at that time on ANY day)
-- -----------------------------------------------------------------------------
START TRANSACTION;
UPDATE appointment
   SET status = 'Cancelled'
 WHERE appointment_id = @appt AND status = 'Scheduled';   -- keeps the no-show / cancel history
SELECT appointment_id, status FROM appointment WHERE appointment_id = @appt;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 9. Reverse a payment entered in error     (2021: DELETE FROM bill WHERE total_bill = '40.41'
--    - matched on an amount, and failed on the service_cost foreign key)
-- -----------------------------------------------------------------------------
START TRANSACTION;
SET @pay := (SELECT MAX(payment_id) FROM payment);
DELETE FROM payment WHERE payment_id = @pay;              -- payment is a leaf table: safe by key
SELECT invoice_id, invoice_total, amount_paid, balance_due
  FROM v_invoice_totals
 WHERE invoice_id = (SELECT invoice_id FROM payment WHERE payment_id = @pay - 1);
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 10. Remove a customer who never did business with us
--     (2021: DELETE FROM customer WHERE customer_id = 'C-06' - failed on FK)
--     Only customers with no appointments and no work orders qualify; their
--     vehicles go first, then the customer, inside one transaction.
-- -----------------------------------------------------------------------------
START TRANSACTION;
SET @cust := (
    SELECT MIN(c.customer_id) FROM customer c
     WHERE NOT EXISTS (SELECT 1 FROM vehicle v JOIN appointment a ON a.vehicle_id = v.vehicle_id
                        WHERE v.customer_id = c.customer_id)
       AND NOT EXISTS (SELECT 1 FROM vehicle v JOIN work_order w ON w.vehicle_id = v.vehicle_id
                        WHERE v.customer_id = c.customer_id));
DELETE FROM vehicle  WHERE customer_id = @cust;
DELETE FROM customer WHERE customer_id = @cust;
SELECT @cust AS deleted_customer_id,
       (SELECT COUNT(*) FROM customer WHERE customer_id = @cust) AS rows_remaining;
ROLLBACK;


-- -----------------------------------------------------------------------------
-- 11. Delete a part from the catalog   (2021: WHERE purchase_price = "P-0021"
--     - compared a price to an ID, so it deleted nothing)
--     The NOT EXISTS guards mean a part that was ever used or ordered is kept.
-- -----------------------------------------------------------------------------
START TRANSACTION;
INSERT INTO part VALUES (99, 'TEST-SKU', 'Entered by mistake', 'Engine', 1, 1.00, 2.00, 0, 0);
DELETE FROM part
 WHERE part_id = 99
   AND NOT EXISTS (SELECT 1 FROM work_order_part WHERE part_id = 99)
   AND NOT EXISTS (SELECT 1 FROM part_order      WHERE part_id = 99);
SELECT COUNT(*) AS test_part_remaining FROM part WHERE part_id = 99;
ROLLBACK;
