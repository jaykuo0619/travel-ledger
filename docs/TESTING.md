# 測試

在專案根目錄執行(需要 Android SDK,見 `docs/android-env-setup.sh`):

```
./gradlew :app:testDebugUnitTest          # 全部測試
./gradlew :app:recordPaparazziDebug       # 重新產生畫面截圖(app/src/test/snapshots/images)
node desktop/build.mjs                    # 產生桌面網頁 desktop/dist/卡溜趴行程桌.html
node --test desktop/test/parser.test.mjs  # 桌面拆分規則
PLAYWRIGHT_DIR=/opt/node-tools/node_modules node desktop/test/e2e.mjs   # 桌面實際操作(需先跑一次 DesktopExchangeTest)
```

| 測試 | 內容 |
|---|---|
| `data/LedgerFlowTest` | 真實 Room 資料庫 + 真實 ViewModel:一趟東京旅程的完整記帳、匯率、預設值、名稱提示、照片、刪除分類/付款方式/旅程、行程規劃與從行程記帳 |
| `data/MigrationTest` | 舊版資料庫(v1)放入資料後升級到最新版,逐版驗證結構並確認資料保留;v6 每個舊旅程都拿到不同的 uuid |
| `ui/AppFlowTest` | 啟動整個 App 用點擊操作:建旅程、記帳(計算機)、帳本與統計、新增行程並從行程記帳、修改與刪除支出、同伴打開分享檔→確認→唯讀旅程與支出明細 |
| `backup/TripArchiveTest` | 兩支手機:分享旅程→同伴匯入唯讀副本(帳目、行程連結、付款人、自訂分類都正確)、再分享會更新同一趟、自己的旅程被拒、照片可選並在更新時清掉舊檔、備份還原到新手機且重複還原不重複、非卡溜趴檔案被拒 |
| `backup/AdditionsTest` | 同伴在分享的旅程補充支出與行程→傳給記帳人→審核勾選加入(誰補充、行程連結、收據照片)→重複打開不重複→記帳人再分享後同伴手機自動整理;分享不含補充、備份含;補充只能給記帳人;還原前「手機較新」判斷 |
| `ui/NoVerticalTextTest` | 所有畫面與對話框在 360dp 寬、系統字 1.5 倍 + 特大字下,不允許文字擠成直排、數字/短字被斷行,或文字被切到 |
| `ui/LinkTapTest` | 在編輯與明細畫面實際點擊網址、電話:確認開啟網頁/撥號,點其他文字進入編輯 |
| `ui/KeypadResizeTest` | 拖曳計算機上方橫槓:按鍵變大/變小、有上下限、記住高度 |
| `ui/MapLauncherTest` | 導航:Google 路線/Naver/Kakao 用名稱搜尋/每次詢問,以及沒安裝時的備案 |
| `backup/DesktopExchangeTest` | 手機檔給桌面(產生 e2e 用的檔案)、桌面行程檔併入手機(更新/新增/刪除/當日筆記/截圖,帳目不動)、新建旅程、別人的旅程拒絕、真的由桌面網頁寫出的檔案能併入 |
| `backup/CompatFixturesTest` | `compat/fixtures` 的範例檔仍能匯入(`WRITE_COMPAT_FIXTURES=1` 時重新產生);`compat/from-ios` 裡 iPhone 版寫的檔逐一匯入 |
| `logic/ParserParityTest` + `desktop/test/parser.test.mjs` | 手機與桌面跑同一份 `desktop/test/parser-cases.json`,拆分與分類結果一致 |
| `desktop/test/e2e.mjs` | 用 Chromium 實際操作桌面網頁:建旅程、輸入、貼上多行、拖曳換天、截圖、當日筆記、當日筆記大編輯區(打字即存、Esc 關閉保留、清空後按提示復原)、同一頁開兩個分頁時互相同步不覆蓋、復原/重做(拖曳、整段打字算一步、欄位內的 Ctrl+Z、刪除後按提示復原含截圖、刪除整趟旅程後復原)、重新整理後資料還在、傳到手機的檔案內容;再打開手機檔案修改後傳回(產生 `roundtrip.zip`) |
| `ui/DeleteSourceTest` | 匯入後刪除原檔:允許刪除的來源會刪掉,像 LINE 不允許的來源保留且不出錯 |
| `data/LedgerFlowTest`(v0.10.3)| 基礎分類/付款方式不能刪、改名後仍受保護;自己新增的刪除後支出與行程改到「其他」(即使已改名);移除成員清掉付款人;只有相機拍的回憶照片存進相簿(相簿選的與收據不存) |
| `ui/LogicTest`(計算機) | 先乘除後加減、同級由左到右、四捨五入兩位、除以 0、運算符號替換、每個數字各自的小數點與位數限制、「=」收成數字、顯示格式;`LedgerFlowTest` 算式存成結果、≤ 0 不能存 |
| `backup/SharingMixupsTest` | 電腦行程檔到同伴手機選「別人記帳」→ 唯讀副本 → 補充傳給記帳人;選自己 → 自己的旅程;記帳人收到自己旅程的檔 → 列出對方新增的項目並加入(原本內容不變、不重複);同伴再分享唯讀副本時沒有新項目 |
| `ui/PlansImportDialogTest` | 電腦行程檔對話框:問誰記帳、選別人時名字必填、手機已有旅程時不問 |
| `ui/ImageSharpnessTest` | 同一張圖先以縮圖載入,再以全螢幕載入時拿到的是原尺寸(不是縮圖);長截圖以短邊決定縮小倍數 |
| `logic/LinksTest` | 網址與電話偵測(不把日期、金額當電話) |
| `ui/PasteDialogTest` | 貼上多筆對話框 |
| `logic/*Test`、`ui/LogicTest` | 收據解析、貼上/地圖分享解析、計算機、換算 |
| `snap/ScreenSnapshots` | 各畫面淺色/深色/特大字截圖 |

測試以 Robolectric 在電腦上模擬 Android,不需要模擬器。Robolectric 需要的 Android 執行檔由 Gradle 下載後以離線模式使用(見 `app/build.gradle.kts`)。

**無法在電腦上測的**:相機拍照、ML Kit 對真實收據的辨識、Google 地圖分享、存到相簿、LINE 傳檔與「用其他應用程式開啟」、系統存檔畫面,需在手機上確認。
