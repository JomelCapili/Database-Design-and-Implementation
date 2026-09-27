// capture_images.js - screenshot dashboard charts for the report (report/img) and README (docs/img)
// Usage: node report/capture_images.js   (after python3 python/build_dashboard.py)
let pw; try { pw = require('playwright'); } catch (e) { pw = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright'); }
const { chromium } = pw;
const path = require('path');
const shots = {
  overview: { "Net sales by month": "sales_by_month", "Net sales by service category": "sales_by_category", "On-time completion by month": "on_time_by_month", "Top 10 vehicle makes by net sales": "top_makes" },
  floor: { "What makes a job late": "late_drivers", "Wait at check-in by appointment slot": "checkin_heatmap", "No-show rate by how far ahead it was booked": "no_show_lead", "Bay board: open repair orders": "bay_board", "Turnaround time": "turnaround" },
  techs: { "Technician scorecard": "tech_scorecard", "Efficiency by month and skill level": "efficiency_levels", "Comeback rate by technician": "comebacks" },
  parts: { "Jobs hit by a stockout, by month": "stockouts_by_month", "Stocked parts that ran out most": "parts_out", "Reorder points: current vs recommended": "reorder_points", "Supplier lead time: quoted vs actual": "supplier_lead" },
  customers: { "Sales per customer by acquisition channel": "channels", "Did a late first visit cost us the customer?": "late_churn", "What drives a bad review": "csat_drivers", "Cohort retention": "cohort" },
};
(async () => {
  const root = path.resolve(__dirname, '..');
  const file = path.join(root, 'docs/index.html'), outDir = path.join(root, 'report/img'), readmeDir = path.join(root, 'docs/img');
  const b = await chromium.launch();
  const ctx = await b.newContext({ ignoreHTTPSErrors: !!process.env.IGNORE_HTTPS_ERRORS, viewport: { width: 1240, height: 1000 }, deviceScaleFactor: 2, colorScheme: 'light' });
  const p = await ctx.newPage();
  await p.goto('file://' + file + '#overview');
  await p.waitForTimeout(1500);
  // README hero shots (default view: 2025 vs 2024)
  for (const t of ['overview', 'parts', 'floor']) {
    await p.click(`#t-${t}`); await p.waitForTimeout(400);
    await p.screenshot({ path: path.join(readmeDir, `dashboard_${t}.png`), fullPage: true });
  }
  await p.click('#t-overview'); await p.waitForTimeout(400);
  await p.screenshot({ path: path.join(outDir, 'dashboard_top.png'), clip: { x: 0, y: 0, width: 1240, height: 660 } });
  await p.addStyleTag({ content: '.tv{visibility:hidden}' });
  await p.selectOption('#f-period', 'all'); await p.waitForTimeout(400);
  for (const [tab, cards] of Object.entries(shots)) {
    await p.click(`#t-${tab}`); await p.waitForTimeout(400);
    for (const [title, name] of Object.entries(cards)) {
      const card = p.locator('section.card', { has: p.locator('h2', { hasText: title }) }).first();
      await card.screenshot({ path: path.join(outDir, name + '.png') });
    }
  }
  await b.close();
  console.log('done');
})();
