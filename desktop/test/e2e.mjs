// Drives the built desktop planner in Chromium the way a person would, and checks the files it writes.
// Needs: node desktop/build.mjs, and the phone fixture from DesktopExchangeTest.phoneFileForTheDesktop
// (./gradlew :app:testDebugUnitTest --tests '*DesktopExchangeTest').
// Writes app/src/test/resources/desktop/roundtrip.zip, which DesktopExchangeTest.realDesktopFileMerges imports.
// Usage: PLAYWRIGHT_DIR=/opt/node-tools/node_modules node desktop/test/e2e.mjs [screenshot-dir]
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { deflateSync } from "node:zlib";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_DIR ? path.join(process.env.PLAYWRIGHT_DIR, "playwright") : "playwright");
const Zip = require("../src/zip.js");
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const page_ = pathToFileURL(path.join(root, "desktop/dist/卡溜趴行程桌.html")).href;
const shots = process.argv[2];
const phoneFile = path.join(root, "app/build/desktop-fixtures/phone-trip.zip");
const roundtrip = path.join(root, "app/src/test/resources/desktop/roundtrip.zip");

// A small real PNG (solid colour) to use as a "screenshot".
function png(w, h, rgb) {
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => {
    const out = Buffer.alloc(12 + data.length);
    out.writeUInt32BE(data.length, 0);
    out.write(type, 4, "ascii");
    data.copy(out, 8);
    out.writeUInt32BE(crc(out.subarray(4, 8 + data.length)), 8 + data.length);
    return out;
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) raw.set(rgb, y * (w * 3 + 1) + 1 + x * 3);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

async function readDownload(download) {
  const buf = readFileSync(await download.path());
  const files = await Zip.read(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length));
  return { buf, files, manifest: JSON.parse(Zip.text(files.get("manifest.json"))), data: JSON.parse(Zip.text(files.get("data.json"))) };
}

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const context = await browser.newContext({ acceptDownloads: true, viewport: { width: 1500, height: 950 }, locale: "zh-TW" });
const page = await context.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("dialog", (d) => d.accept());
await page.goto(page_);
await page.waitForFunction(() => window.__ready === true);
const col = (label) => page.locator(".col").filter({ has: page.locator(".col-head", { hasText: label }) });
const shot = async (name) => { if (shots) await page.screenshot({ path: path.join(shots, name + ".png") }); };

// ── 1. A new trip planned from scratch ──
await shot("01-empty");
await page.getByRole("button", { name: "＋ 新增旅程" }).click();
await page.locator("#tr-name").fill("大阪親子遊");
await page.locator("#tr-start").fill("2026-12-20");
await page.locator("#tr-end").fill("2026-12-23");
await page.getByRole("button", { name: "建立" }).click();
await page.locator(".col").nth(4).waitFor();
assert.equal(await page.locator(".col").count(), 5, "待排 + 4 days");

// One line typed into Day 1.
await col("Day 1").locator("textarea[data-add]").fill("09:00 環球影城");
await col("Day 1").locator("textarea[data-add]").press("Enter");
await col("Day 1").locator(".card", { hasText: "環球影城" }).waitFor();
assert.equal(await col("Day 1").locator(".card .time").first().textContent(), "09:00");

// Several lines pasted into Day 2 → preview → create.
await col("Day 2").locator("textarea[data-add]").fill("中午 一蘭拉麵 道頓堀店\n下午3點 大阪城\n記得帶護照");
await col("Day 2").locator("textarea[data-add]").press("Enter");
await page.locator("#sp-ok").waitFor();
await shot("02-split-preview");
assert.equal(await page.locator("#sp-count").textContent(), "3");
await page.locator('[data-i="2"]').uncheck(); // not a place
await page.locator("#sp-ok").click();
await col("Day 2").locator(".card", { hasText: "大阪城" }).waitFor();
assert.equal(await col("Day 2").locator(".card").count(), 2);

// Drag 大阪城 to 待排.
await col("Day 2").locator(".card", { hasText: "大阪城" }).dragTo(col("待排"));
await col("待排").locator(".card", { hasText: "大阪城" }).waitFor();

// Open 環球影城, add a note and a screenshot.
await col("Day 1").locator(".card", { hasText: "環球影城" }).click();
await page.locator("#ed-note").fill("官網 https://www.usj.co.jp 快速通關要先買");
await page.locator("#ed-note").blur();
await page.locator("#ed-pics").setInputFiles({ name: "ticket.png", mimeType: "image/png", buffer: png(40, 30, [230, 80, 60]) });
await page.locator("#drawer .pic img").first().waitFor();
await page.locator("#drawer a", { hasText: "usj.co.jp" }).waitFor();
await shot("03-editor");
await page.locator("#ed-close").click();

// Day note on Day 3: opens in the big drawer, saved as you type.
await col("Day 3").locator("[data-note]").click();
await page.locator("#nd-text").fill("搭 JR 到京都 https://www.jr-odekake.net");
await page.locator("#nd-links a", { hasText: "jr-odekake.net" }).waitFor();
await col("Day 3").locator(".daynote", { hasText: "搭 JR 到京都" }).waitFor(); // the board follows while typing
await shot("04a-day-note");
await page.locator("#nd-done").click();
await page.locator("#drawer").waitFor({ state: "detached" });
// Edit it again (✎ 修改; tapping the link itself opens the link): the drawer opens with the text; Esc closes and keeps it.
await col("Day 3").locator("[data-note] .edit").click();
assert.equal(await page.locator("#nd-text").inputValue(), "搭 JR 到京都 https://www.jr-odekake.net");
await page.locator("#nd-text").fill("搭 JR 到京都");
await page.keyboard.press("Escape");
await page.locator("#drawer").waitFor({ state: "detached" });
await col("Day 3").locator(".daynote", { hasText: /^當日筆記✎ 修改搭 JR 到京都$/ }).waitFor();
// Clearing it deletes the note; the toast brings it back.
await col("Day 3").locator("[data-note]").click();
await page.locator("#nd-text").fill("");
await page.locator("#nd-close").click();
await col("Day 3").locator(".daynote.empty").waitFor();
await page.locator(".toast-action", { hasText: "復原" }).click();
await col("Day 3").locator(".daynote", { hasText: "搭 JR 到京都" }).waitFor();
await shot("04-board");

// ── Undo / redo: every change is one step, Ctrl+Z / Ctrl+Y outside fields, or the buttons. ──
const usjCard = (label) => col(label).locator(".card", { hasText: "環球影城" });
const press = async (keys) => { await page.locator(".brand").click(); await page.keyboard.press(keys); };
await usjCard("Day 1").dragTo(col("Day 3"));
await usjCard("Day 3").waitFor();
await press("Control+z");
await usjCard("Day 1").waitFor();
await press("Control+y");
await usjCard("Day 3").waitFor();
await page.getByRole("button", { name: "↶ 復原" }).click();
await usjCard("Day 1").waitFor();
assert.equal(await page.getByRole("button", { name: "↷ 重做" }).isEnabled(), true);
// Typing a name is one step, however many keys.
await usjCard("Day 1").click();
await page.locator("#ed-title").click();
await page.keyboard.press("End");
await page.locator("#ed-title").pressSequentially(" 快速通關");
await page.locator("#ed-close").click();
await col("Day 1").locator(".card", { hasText: "環球影城 快速通關" }).waitFor();
await press("Control+z");
await col("Day 1").locator(".card .title", { hasText: /^環球影城$/ }).waitFor();
// Ctrl+Z inside a field stays the browser's own typing undo.
await usjCard("Day 1").click();
await page.locator("#ed-title").click();
await page.keyboard.press("End");
await page.keyboard.type("X");
await page.keyboard.press("Control+z");
assert.equal(await page.locator("#ed-title").inputValue(), "環球影城");
await page.locator("#ed-close").click();
// Delete asks nothing; the toast brings it back, pictures included.
await usjCard("Day 1").click();
await page.locator("#ed-delete").click();
await usjCard("Day 1").waitFor({ state: "detached" });
await shot("04b-undo-toast");
await page.locator(".toast-action", { hasText: "復原" }).click();
await usjCard("Day 1").click();
assert.equal(await page.locator("#drawer .pic img").count(), 1);
await page.locator("#ed-close").click();
// Deleting the whole trip can be undone too, and the undo is saved.
await page.getByRole("button", { name: "旅程設定" }).click();
await page.locator("#tr-delete").click();
await page.locator(".empty-state").waitFor();
await press("Control+z");
await usjCard("Day 1").waitFor();

// Survives a reload (kept in this browser).
await page.waitForTimeout(400);
await page.reload();
await page.waitForFunction(() => window.__ready === true);
await col("待排").locator(".card", { hasText: "大阪城" }).waitFor();
await col("Day 1").locator(".card", { hasText: "環球影城" }).waitFor();

// 傳到手機 → a plans file.
let [download] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "傳到手機" }).click()]);
let out = await readDownload(download);
assert.equal(out.manifest.kind, "plans");
assert.equal(out.data.trip.name, "大阪親子遊");
assert.deepEqual(out.data.plans.map((p) => p.title).sort(), ["一蘭拉麵 道頓堀店", "大阪城", "環球影城"]);
const usj = out.data.plans.find((p) => p.title === "環球影城");
assert.equal(usj.photos.length, 1);
assert.ok(out.files.has(usj.photos[0].file), "picture inside the file");
assert.equal(out.data.plans.find((p) => p.title === "一蘭拉麵 道頓堀店").category, "吃");
assert.equal(out.data.plans.find((p) => p.title === "大阪城").date, null);
await page.getByRole("button", { name: "知道了" }).click();

// ── 2. Open the phone's file, change it, send it back ──
if (!existsSync(phoneFile)) {
  console.log("skip phone round trip: run DesktopExchangeTest first");
} else {
  await page.locator("#file-input").setInputFiles(phoneFile);
  await page.getByRole("button", { name: "打開" }).click();
  await col("Day 2").locator(".card", { hasText: "景福宮" }).waitFor();
  await col("待排").locator(".daynote", { hasText: "有空再去" }).waitFor();
  await shot("05-phone-trip");
  // Move 廣藏市場 (Day 3) to Day 4.
  await col("Day 4").scrollIntoViewIfNeeded();
  await col("Day 3").locator(".card", { hasText: "廣藏市場" }).dragTo(col("Day 4"));
  await col("Day 4").locator(".card", { hasText: "廣藏市場" }).waitFor();
  // Delete Olive Young.
  await col("待排").locator(".card", { hasText: "Olive Young" }).click();
  await page.locator("#ed-delete").click();
  await page.locator(".card", { hasText: "Olive Young" }).waitFor({ state: "detached" });
  // Paste two lines into Day 4.
  await col("Day 4").locator("textarea[data-add]").fill("11:40 【交通】搭乘 01A 循環公車到南大門市場站\n明洞餃子");
  await col("Day 4").locator("textarea[data-add]").press("Enter");
  await page.locator("#sp-ok").click();
  await col("Day 4").locator(".card", { hasText: "明洞餃子" }).waitFor();
  // A second screenshot on 景福宮 (it already has one from the phone).
  await col("Day 2").locator(".card", { hasText: "景福宮" }).click();
  assert.equal(await page.locator("#drawer .pic img").count(), 1);
  await page.locator("#ed-pics").setInputFiles({ name: "map.png", mimeType: "image/png", buffer: png(30, 30, [40, 120, 220]) });
  await page.waitForFunction(() => document.querySelectorAll("#drawer .pic img").length === 2);
  await page.locator("#ed-close").click();
  // Day note on Day 3.
  await col("Day 3").locator("[data-note]").click();
  await page.locator("#nd-text").fill("先換錢再出門");
  await page.locator("#nd-done").click();
  await col("Day 3").locator(".daynote", { hasText: "先換錢再出門" }).waitFor();
  await shot("06-phone-trip-edited");

  [download] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "傳到手機" }).click()]);
  out = await readDownload(download);
  assert.equal(out.data.trip.uuid, "trip-seoul");
  assert.ok(out.data.deleted.includes("plan-oy"));
  assert.ok(Zip.text(out.files.get("data.json")).includes("-9223372036854775808"), "待排 note keeps the phone's exact day key");
  mkdirSync(path.dirname(roundtrip), { recursive: true });
  writeFileSync(roundtrip, out.buf);
  console.log("wrote", path.relative(root, roundtrip));
}

assert.deepEqual(errors, [], "no script errors");
await browser.close();
console.log("desktop e2e ok");
