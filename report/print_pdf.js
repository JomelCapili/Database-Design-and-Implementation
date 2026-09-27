// print_pdf.js - render report.html to PDF with headless Chromium (Playwright)
// Usage: node report/print_pdf.js report/report.html report/Database_Report_v2.pdf
let playwright;
try { playwright = require("playwright"); } catch (e) {
  playwright = require(require("child_process").execSync("npm root -g").toString().trim() + "/playwright");
}
const path = require("path");

(async () => {
  const [src, out] = process.argv.slice(2);
  const browser = await playwright.chromium.launch();
  // IGNORE_HTTPS_ERRORS=1 only for sandboxed build machines behind an intercepting proxy
  const page = await browser.newPage({ ignoreHTTPSErrors: !!process.env.IGNORE_HTTPS_ERRORS });
  await page.goto("file://" + path.resolve(src), { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  await page.pdf({
    path: out,
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: "<div></div>",
    footerTemplate: `<div style="font: 7px 'Helvetica', sans-serif; color:#8a9096; width:100%; padding:0 0.75in; display:flex; justify-content:space-between;">
      <span>Service Management Database · v2 · Jomel Capili</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>`,
  });
  await browser.close();
  console.log("  wrote " + out);
})();
