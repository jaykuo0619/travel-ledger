// Builds the single-file desktop planner: desktop/dist/卡溜趴行程桌.html (no network needed to use it).
// Usage: node desktop/build.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const dir = path.dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(path.join(dir, "src", f), "utf8");
export const VERSION = "1.4";
const html = read("index.html")
  .replace("/*STYLE*/", () => read("style.css"))
  .replace("/*PARSER*/", () => read("parser.js"))
  .replace("/*ZIP*/", () => read("zip.js"))
  .replace("/*APP*/", () => read("app.js"))
  .replace("/*VERSION*/", VERSION);
mkdirSync(path.join(dir, "dist"), { recursive: true });
writeFileSync(path.join(dir, "dist", "卡溜趴行程桌.html"), html);
console.log("wrote desktop/dist/卡溜趴行程桌.html", Math.round(html.length / 1024) + " KB");
