# 卡溜趴行程桌

在電腦上排行程的網頁(單一 HTML,離線可用,資料存在瀏覽器)。只有行程,沒有記帳。

- 原始碼:`src/`(parser.js 與手機 `PlanParser.kt` 同一套規則;zip.js 讀寫卡溜趴檔案;app.js 畫面)
- 產生:`node desktop/build.mjs` → `desktop/dist/卡溜趴行程桌.html`
- 測試:`node --test desktop/test/parser.test.mjs`、`PLAYWRIGHT_DIR=… node desktop/test/e2e.mjs`

復原/重做:`checkpoint()` 在每次變更前存所有旅程的快照(`structuredClone`,最多 100 步),`undo`/`redo` 換回並整份寫回 IndexedDB。新增會改資料的功能時,記得先呼叫 `checkpoint()`。

檔案格式與手機相同(manifest.json + data.json + files/)。桌面寫出 `kind: "plans"`,手機以「併入」合併到同一趟旅程。
