// Renders docs/manual/manual.html to docs/manual/卡溜趴使用說明書.pdf with headless Chromium.
// Usage: node docs/manual/build.mjs
// Needs Playwright (installed in the project, or set PLAYWRIGHT_DIR to a node_modules that has it)
// and network access for Google Fonts.
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_DIR ? path.join(process.env.PLAYWRIGHT_DIR, "playwright") : "playwright");

const dir = path.dirname(fileURLToPath(import.meta.url));
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
  proxy: proxy ? { server: proxy } : undefined,
});
const page = await browser.newPage();
await page.goto(pathToFileURL(path.join(dir, "manual.html")).href, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
await page.pdf({
  path: path.join(dir, "卡溜趴使用說明書.pdf"),
  format: "A4",
  printBackground: true,
  preferCSSPageSize: true,
  displayHeaderFooter: true,
  headerTemplate: "<span></span>",
  footerTemplate:
    '<div style="width:100%;font-size:8px;color:#8e91a2;padding:0 17mm;display:flex;justify-content:space-between;font-family:sans-serif">' +
    '<span>卡溜趴 使用說明書 v0.10.4</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>',
});
await browser.close();
console.log("wrote 卡溜趴使用說明書.pdf");
