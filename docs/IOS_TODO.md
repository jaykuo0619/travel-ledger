# iPhone 版待辦:Android 在 000d963 之後的改動

> 給 Jay 和他的 Claude。`ios` 分支是從 `000d963` 長出來的,之後 Android 和電腦行程桌又改了一些東西。這份清單列出 **iPhone 版要跟著改的**,每一項都標了規格在 `docs/IOS_PORT.md` 哪一節、Android 的程式和測試在哪裡,照著做兩邊行為就會一樣。
>
> **檔案格式(.zip)完全沒有變**,iPhone 1.0.0 和現在的 Android 可以照常互傳;以下都是畫面與行為的改動。
>
> 最後更新:2026-10-12(Android v0.10.6、電腦行程桌 v1.4)

## 怎麼把這些改動拿到 ios 分支

在 Jay 的 repo:

```
git remote add upstream https://github.com/nmymdf/travel-ledger.git   # 第一次才需要
git fetch upstream claude/confident-volta-6rsegv
git checkout ios
git merge upstream/claude/confident-volta-6rsegv
```

已經試過:合併**不會衝突**(ios 分支只動 `ios/` 與 `compat/from-ios/`)。合併後 `docs/IOS_PORT.md`、`compat/fixtures/` 就是最新的。

---

## A. 送審前建議先修(iPhone 版自己的問題)

- [ ] **非西曆的日期錯誤(重要)**:iPhone 設定成中華民國曆、日本曆、佛曆時,`LedgerCore/Dates.swift` 的 `CivilDate.today`、`date()`、`localDateTime` 用 `Calendar.current` 取年月日,會得到 115 年之類的年份,新旅程日期、記帳日期、「今天」都會錯,還會寫進分享檔。三個地方都改成固定 `Calendar(identifier: .gregorian)`(時區用目前的)。台灣使用者真的會選民國曆。
- [ ] `compat/from-ios/` 再補一個**真機匯出**的檔:一張相機照片、一張手寫便條、一張畫過的收據,讓 Android 端驗證真實照片(目前的檔只有 64×48 測試圖)。
- [ ] (小事)manifest `appVersion` 建議寫成 `ios-1.0.0`,之後比較好分辨檔案是哪一邊做的;沒有程式會讀這個欄位,不影響相容。
- [ ] `ios/PRIVACY.md` 的問題回報網址目前指向 Jay 的 fork,確認 App Store 上要放哪個長期不變的網址。

## B. 要跟著 Android 改的行為

| 版本 | 項目 | 規格(IOS_PORT.md) | Android 參考 |
|---|---|---|---|
| v0.10.1 / v0.10.3 | 匯入後刪除原檔:**備份檔不刪**、設定開關預設開 | 11.A「匯入成功後刪除原檔」 | `ui/ShareBackup.kt` `shouldDeleteSource`、`DeleteSourceTest` |
| v0.10.3 | **基礎分類/付款方式不能刪、可以改名**;自己新增的可刪,刪前顯示影響筆數;刪分類時**支出和行程**都改到「其他」(用 builtIn 找,不靠名稱) | 11.I「分類/付款方式管理」 | `data/Entities.kt` `builtIn`、`data/Daos.kt` `deleteCategory`、`LedgerFlowTest.onlyAddedCategoriesAndPaymentMethodsCanBeDeleted` |
| v0.10.3 | **移除成員時清掉他在支出上的付款人**(payerId → null) | 12 節 | `data/Daos.kt` `deleteMember`、`LedgerFlowTest.removingAMemberClearsTheirPayments` |
| v0.10.3 | 「拍照」把**原始高畫質**存進相簿(App 內仍存 1200 的版本);**從相簿選的照片不再存回相簿**;行程截圖檢視時「存到相簿」要真的存 | 11.G「另存相簿」 | `ui/ViewModels.kt` `PhotoItem.original/fromAlbum`、`LedgerFlowTest.onlyNewCameraMemoriesAreCopiedToTheGallery` |
| v0.10.4 | **記一筆改成真的計算機**:5 排 × 4 欄(C ⌫ ÷ × / 7 8 9 − / 4 5 6 + / 1 2 3 = / 00 0 . 儲存),先乘除後加減,上方小字算式、大字即時結果,不按 = 也能存,結果 ≤ 0 不能存,除以 0「無法計算」 | 11.F「計算機」 | `ui/Keypad.kt` `applyKey`/`evaluate`/`fmtExpression`、`ui/LogicTest`(18 個案例可直接轉成 XCTest) |
| v0.10.5 | 新增/編輯行程**沒名稱按 ✓**:✓ 一律可按(看起來是灰的),按了不存,名稱欄紅框、紅字「請輸入名稱才能儲存」、聚焦並開鍵盤 | 11.H「編輯行程」 | `ui/PlanScreens.kt` `PlanEditScreen`、`AppFlowTest.addAPlanToUnscheduled` |
| v0.10.6 | **電腦行程檔到了沒有這趟旅程的手機**:問「這趟旅程是誰記帳?」,選「別人記帳」+ 名字 → 唯讀副本 | 11.A「傳錯檔案的兩種補救」第 1 點 | `TripArchive.importPlans(organizer)`、`PlansImportDialog`、`PlansImportDialogTest` |
| v0.10.6 | **記帳人收到自己旅程的 kind=trip 檔**:列出對方有、自己沒有的行程與支出讓記帳人勾選加入(不再只拒絕);沒有新項目時提示改用「傳給記帳人」 | 11.A「傳錯檔案的兩種補救」第 2 點 | `TripArchive.readNewItems`/`importNewItems`、`backup/SharingMixupsTest` |

## C. 只有 Android 或電腦行程桌、iPhone 不用做

- v0.10.2 看圖模糊(Android 圖片快取的 bug;iPhone 不同寫法,自己確認全螢幕看到的是原圖即可)。
- 電腦行程桌 v1.1~v1.4(復原/重做、當日筆記大編輯區、多分頁同步、「傳到手機」提醒)。

## D. 還沒決定、先不要改

- 帳本卡和統計頁的「日均」定義不同(兩邊目前一樣),等使用者決定。

## E. 做完之後

1. 跑 `LedgerCore` 的測試和 `compat/fixtures` 的相容測試。
2. 用改好的 iPhone 版匯出 trip、backup、additions 檔放進 `compat/from-ios/`,push 到 `ios` 分支。
3. 告訴 Android 那邊跑 `./gradlew :app:testDebugUnitTest --tests '*CompatFixturesTest'` 確認。
4. 在這份清單把做完的項目打勾 `[x]`,一起 push。
