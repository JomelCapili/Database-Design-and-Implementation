# Fix log: auditing my 2021 SQL

In 2026 I re-ran my 2021 term-project script for IS 475, Database Design and Implementation
(`legacy/service_management_2021.sql`), on a clean
**MySQL 8.0 server on Linux** and reviewed every table and query. This log records what I found,
how I proved it, and how version 2 fixes it.

**Summary:** the script throws **18 errors** on a standard Linux MySQL install, and several
queries that *do* run return wrong answers without any error. The root cause of most logic
bugs is a design decision: mechanics were linked to customers instead of to jobs, and parts
were linked to mechanics instead of to jobs.

---

## A. Errors (the script stops or a statement fails)

| # | Problem | Evidence | v2 fix |
|---|---|---|---|
| A1 | Table created as `Vehicle` but used as `VEHICLE` and `vehicle`. MySQL on Linux/macOS treats table names as case-sensitive, so the insert, the `vehicle_receives` table, 8 queries and 2 DML statements all fail (13 errors from one typo). It only worked in 2021 because Windows MySQL ignores case. | `ERROR 1146: Table 'service_management.VEHICLE' doesn't exist` | All identifiers lowercase `snake_case`; script tested on Linux MySQL 8.0.46 |
| A2 | `DELETE FROM customer WHERE customer_id = 'C-06'` | `ERROR 1451` foreign key from `appointment` | Customers with history are never deleted; `06_maintenance_examples.sql` #10 shows the guarded pattern |
| A3 | `DELETE FROM mechanic WHERE mechanic_id = 'M-043'` | `ERROR 1451` from `mechanic_performs` | Record `termination_date` instead (#7) |
| A4 | `DELETE FROM service WHERE service_date = ...` | `ERROR 1054: Unknown column 'service_date'` | n/a (column never existed) |
| A5 | `DELETE FROM bill WHERE total_bill = '40.41'` | `ERROR 1451` from `service_cost` | Delete by primary key, leaf tables only (#9) |
| A6 | `DELETE FROM part WHERE purchase_price = "P-0021"` compares a **price** to an **ID** | `ERROR 1292: Truncated incorrect DECIMAL value` | Delete by `part_id` with `NOT EXISTS` guards (#11) |

## B. Silent logic bugs (runs fine, wrong answer)

| # | Problem | Evidence | v2 fix |
|---|---|---|---|
| B1 | `WHERE year > 2000 AND make = 'Honda' OR make = 'Toyota'`: `AND` binds tighter than `OR` | Returns **5** rows including a 1995 and a 1998 Toyota; the correct answer is **3** | Parentheses / `IN (...)`; `model_year` is a number |
| B2 | Query 4 ("most used part category") counts **rows**, not **units** | Ranks *chassis* #1 (10 rows, 18 units); *engine* actually used the most (24 units) and *electrical* used 21 units from only 3 rows | Q12/Q15 sum `quantity` |
| B3 | Queries 1, 8, 12 sum `purchase_price` and ignore quantity. The schema never says whether the price is per unit or per line | If per unit, fuel-system cost is **$11,806**, not the reported $4,447, and engine cost is 3.4× what was reported | `unit_cost` × `quantity` stored explicitly on each job line |
| B4 | Query 8 "profit" = bill − one part's price | Ignores quantity, other parts and labor; 3 parts with NULL price make profit NULL | `gross_profit` = net sales − parts cost − technician labor cost |
| B5 | Revenue-by-make (Q11) joins `customer → vehicle → bill` on `customer_id` | Added one vehicle + one bill for C-01 (2 bills, **$413.72** total): the query credited **$413.72 to each car**, i.e. $827.44 | Revenue flows `invoice → work_order → vehicle`, one path, no fan-out |
| B6 | `mechanic.Customer_ID` ties each mechanic to one customer forever (50 mechanics for 50 customers). Queries 5, 7, 8, 13 reach the customer through it | Works only because every table has exactly one row per customer | Mechanic is an employee; the job (`work_order.mechanic_id`) says who did the work |
| B7 | `mechanic_uses` links parts to **mechanics**, not to **jobs** | "Which parts went into which repair?" (the report's own inventory problem) can't be answered | `work_order_part` links every part to the job it was installed on |
| B8 | Query 15 and an unnamed query use `LEFT JOIN` then filter the right table in `WHERE` | Silently becomes an `INNER JOIN` | Filters on outer-joined tables go in `ON`, or use `INNER JOIN` deliberately |
| B9 | Query 10's comment says "parts used most" but the query counts vehicle makes | Comment/code mismatch | Every query is headed by the business question it answers |
| B10 | 19 of 50 "incomplete" services are already fully paid; 3 services start on a different date than their appointment | No link between appointment, service and bill | `appointment → work_order → invoice → payment` chain; data-quality checks 5, 10, 13, 16 |

## C. Design and data-quality problems

| # | Problem | v2 fix |
|---|---|---|
| C1 | Status default misspelled `'incomeplete'`; any value accepted | `CHECK (status IN (...))` on every status column |
| C2 | `Part_Quantity VARCHAR`, `Year CHAR(5)`, `Appt_Time VARCHAR` ('12:21 PM') | `SMALLINT`, `SMALLINT`, `DATETIME` |
| C3 | Junction tables have no primary key, so duplicates are allowed | Composite primary keys |
| C4 | `Customer_Name VARCHAR(20)` (single field, truncation risk) | `first_name`, `last_name VARCHAR(50)` |
| C5 | `'C-42 '` stored with a trailing space | Integer surrogate keys; `CHECK` constraints on codes (ZIP, VIN) |
| C6 | Report's table structure shows `service.mechanic_id`, `service.vin`, `part.mechanic_id`; the SQL doesn't have them | Schema, ERD and data dictionary generated from the same design |
| C7 | 3 parts with NULL purchase price | `NOT NULL` + `CHECK (unit_price >= unit_cost)` |
| C8 | `UPDATE mechanic ... WHERE phone_number = ...` targets a non-key | Every UPDATE/DELETE targets the primary key |
| C9 | `UPDATE bill SET total_bill = total_bill * .80` overwrites the original amount | Discount stored separately with a reason; totals derived in `v_invoice_totals` |
| C10 | `DELETE FROM appointment WHERE appt_time = '4:42 PM'` | Would delete **2** unrelated appointments (A-11 and A-22). v2 cancels by key and keeps history |
| C11 | `UPDATE vehicle SET year = '2007'` on a car that is already 2007 | No-op removed |
| C12 | Query 3 duplicates query 2 | Removed |
| C13 | Only 50 rows per table, all 1:1 | ~70,000 rows with realistic many-to-many patterns, so the queries are tested against real fan-out |

## D. 2021 instructor feedback

When the project was graded in December 2021, my professor flagged ten design issues. Seven of them
overlap with problems the 2026 audit found on its own (B6, B7, C3, C6), and v2 fixes all ten.

| # | 2021 feedback | v2 fix |
|---|---|---|
| D1 | MECHANIC doesn't need `customer_ID`; mechanics and customers aren't related | Removed. The job records who did the work (`work_order.mechanic_id`). See B6 |
| D2 | The CUSTOMER–VEHICLE arrow in the logical schema is reversed | `vehicle.customer_id` references `customer`: the foreign key sits on the "many" side. ERD redrawn in crow's-foot notation |
| D3 | The CUSTOMER–APPOINTMENT arrow is reversed | `appointment.vehicle_id` references `vehicle`, which references `customer`, so the shop knows which car is booked |
| D4 | "Receives" is one-to-many, so it shouldn't be a standalone table | `vehicle_receives` removed; a foreign key (`work_order.vehicle_id`) replaces it |
| D5–D8 | No primary key on `vehicle_receives`, `service_cost`, `mechanic_uses`, `mechanic_performs` | Every table has a primary key; junction tables use composite keys, e.g. `PRIMARY KEY (work_order_id, part_id)`. See C3 |
| D9 | PART doesn't need `mechanic_id` (data dictionary inconsistent with the logical schema) | Parts link to jobs through `work_order_part`, which also stores quantity and cost. See B7 |
| D10 | SERVICE doesn't need `mechanic_id` and `VIN` (data dictionary inconsistent with the logical schema) | Resolved in favor of foreign keys, consistent with D4: each job has one vehicle and one responsible technician, so `work_order` holds both keys and the junction tables are gone. Schema, ERD and data dictionary now come from one design. See C6 |

---

## How to reproduce

```bash
# Linux / macOS, MySQL 8
mysql -u root -p --force -vvv < legacy/service_management_2021.sql 2>&1 | grep ERROR
```
