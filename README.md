# Service Management Database

**A MySQL database, SQL analysis and operations dashboard for an independent auto repair shop.**
Rebuilt in 2026 from my 2021 term project for IS 475, Database Design and Implementation, at UNLV.

**[Live dashboard](https://jomelcapili.github.io/Database-Design-and-Implementation/)** ·
**[Full report (PDF)](report/Database_Report_v2.pdf)** ·
**[Original 2021 files](legacy/)** ·
**[What I fixed from 2021](docs/FIX_LOG.md)**

![Service Ops Board dashboard](docs/img/dashboard_overview.png)

| 14 tables | ~70,000 rows | 22 business questions in SQL | 20 data-quality checks | 5-page dashboard |
|---|---|---|---|---|

> **Data note:** the data is simulated, not from a real shop. Every person, company, phone number and VIN is made up.

---

## The story

In 2021, for my database design class at UNLV, I designed a database for an auto repair shop with two
problems: **jobs and appointments running late**, and **no record of which parts were used**, so the shop
kept running out of them. The class required at least 7 tables and 50 rows per table, and I typed all
550 rows by hand. I built and ran it in MySQL Workbench on Windows, and it worked.

In 2026 I went back to it with fresh eyes and found problems that hadn't shown up in class:

- **Some queries ran without errors but gave the wrong answer.** One returned 1995 and 1998 Toyotas when
  I asked for cars newer than 2000. Another could count the same bill twice. With only 50 tidy rows per
  table, nothing looked wrong.
- **The design couldn't answer the shop's main question.** Parts were linked to mechanics instead of to
  jobs, so there was no way to see which parts went into which repair. My professor had flagged several
  of these design issues in the 2021 feedback.
- **It wouldn't run on a Linux server.** I'd named one table `Vehicle` and later typed it as `VEHICLE`. Windows
  doesn't care about capitalization, but a Linux server (what most companies use) does, and 12 statements fail.

So I rebuilt it:

1. **Redesigned the database** around the job (work order), so every job links to its car, mechanic, services and parts
2. **Replaced the hand-typed rows** with two years of simulated shop activity (~70,000 rows), so the design gets tested at real scale
3. **Answered 22 business questions** in SQL, with each metric defined once in a view so every report agrees
4. **Added 20 automated checks** that test the data for mistakes. They caught a real bug in my simulated data.
5. **Built a dashboard and a report** that turn the results into recommendations

Every problem I found, with evidence, is in the [fix log](docs/FIX_LOG.md).

## 2021 vs. 2026

The original proposal, slides, report and SQL are in [`legacy/`](legacy/), so you can compare them directly.

| | 2021 class project | 2026 rebuild |
|---|---|---|
| Tables | 11 | 14 |
| Data | 550 rows, typed by hand | ~70,000 rows, simulated |
| Rules the database enforces | 12 foreign keys; 4 tables with no primary key | 16 foreign keys, a primary key on every table, 30 validation rules (CHECK constraints) |
| Queries | 15 | 22, plus 7 views that define each metric once |
| Testing | none | 20 automated data-quality checks |
| Runs on | Windows (MySQL Workbench) | Windows and Linux |
| Deliverables | 20-page report | 22-page report and an interactive dashboard |

<table>
<tr><th>2021: my hand-drawn logical schema</th><th>2026: entity relationship diagram</th></tr>
<tr>
<td width="50%"><a href="legacy/img/logical_schema_2021.jpg"><img src="legacy/img/logical_schema_2021.jpg" alt="2021 hand-drawn logical schema"></a></td>
<td width="50%"><a href="docs/img/erd.png"><img src="docs/img/erd.png" alt="2026 entity relationship diagram"></a></td>
</tr>
</table>

## What the data shows

| Finding | Evidence | Recommendation |
|---|---|---|
| **Running out of parts is the biggest fixable cause of late jobs** | Jobs where a stocked part ran out finished on time **11%** of the time, vs. **80%** when parts were on the shelf. Front brake rotors ran out 53 times in 2025. | Raise the reorder point on 11 parts, about **$3,600** of extra stock |
| **A late first visit loses customers** | New customers came back within 6 months **31%** of the time after a late first visit, vs. **48%** after an on-time one | Build supplier delivery times into promised times; text customers when a job will be late |
| **One technician's work came back far more often** | 7.7% of that technician's jobs needed warranty rework, 2.6× the rest of the team, costing $5,046 | Add rework rate to technician reviews |
| **Appointments booked far ahead get missed** | 19.7% no-shows when booked 15+ days out, vs. 3.0% when booked 0–2 days out | Send reminder texts for bookings made 8+ days ahead |
| **Growth came from bigger tickets, not more cars** | 2025 sales +9.9%, average ticket +7.6%, number of cars +1.4% | Push referrals: referred customers come back 57% of the time vs. 38% from social media |

## Example: the query behind the top finding

```sql
-- Are jobs late more often when a part runs out?
SELECT CASE WHEN had_stockout = 1      THEN 'A stocked part ran out'
            WHEN had_special_order = 1 THEN 'Special-order part'
            ELSE 'All parts on the shelf' END      AS parts_situation,
       COUNT(*)                                    AS jobs,
       ROUND(AVG(is_on_time) * 100)                AS on_time_pct
FROM v_work_order_summary          -- a view: one row per completed job, with its metrics
WHERE status = 'Completed'
GROUP BY parts_situation
ORDER BY on_time_pct;
```

| parts_situation | jobs | on_time_pct |
|---|---|---|
| A stocked part ran out | 228 | 11 |
| Special-order part | 146 | 22 |
| All parts on the shelf | 7,557 | 80 |

The other 21 questions are in [`sql/04_analysis_queries.sql`](sql/04_analysis_queries.sql). They use
joins, subqueries, CTEs and window functions, and each one starts with the business question it answers.

## How the database is designed

![Entity relationship diagram](docs/img/erd.png)

- **Everything centers on the job.** A work order links the car, the mechanic, the services, the parts and the invoice, so any question about a repair can be answered from one place.
- **Totals are calculated, not typed in.** Invoice totals, stock on hand and profit are worked out from the line items, so they can never disagree with them.
- **The database blocks bad data.** A rating has to be 1 to 5, a VIN has to be 17 valid characters, and a job can't be marked complete without a finish time.

## What's in this repository

| Folder | What's in it |
|---|---|
| [`sql/`](sql/) | The database: tables, data, views, the 22 analysis queries and the data-quality checks |
| [`report/`](report/) | The full written report ([PDF](report/Database_Report_v2.pdf)) |
| [`docs/`](docs/) | The live dashboard page and the [fix log](docs/FIX_LOG.md) |
| [`data/`](data/) | Every table as a CSV file, plus an Excel workbook ready for Tableau or Power BI |
| [`dashboard/`](dashboard/) | Step-by-step guides for building the dashboard in Tableau or Power BI |
| [`python/`](python/) | The scripts that create the simulated data and build the dashboard page |
| [`legacy/`](legacy/) | The original 2021 project |

## Try it yourself

You need MySQL 8 and MySQL Workbench (free from mysql.com).

1. In Workbench, open each file with **File → Open SQL Script** and run it with the lightning-bolt button, in this order:
   `sql/01_schema.sql`, then `sql/02_seed_data.sql` (takes a few seconds), then `sql/03_views.sql`.
2. Open `sql/04_analysis_queries.sql` and run any question.
3. Run `sql/05_data_quality_checks.sql`. All 20 checks should say **PASS**.

---

**Jomel Capili** · B.S. Business Administration, Information Systems, University of Nevada, Las Vegas ·
[LinkedIn](https://www.linkedin.com/in/jomelcapili)
