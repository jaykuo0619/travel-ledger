import XCTest
@testable import LedgerCore

/// The cases of app/src/test/.../logic/ReceiptParserTest.kt.
final class ReceiptParserTests: XCTestCase {
    /// Builds lines top to bottom; "label | amount" becomes two boxes on the same row, as the recognizer returns them.
    private func receipt(_ rows: String...) -> [OcrLine] {
        var out: [OcrLine] = []
        for (i, row) in rows.enumerated() {
            let h = i == 0 ? 60 : 30
            let top = i == 0 ? 0 : 80 + (i - 1) * 40
            let parts = row.components(separatedBy: " | ")
            out.append(OcrLine(parts[0], 20, top, 300, top + h))
            if parts.count > 1 { out.append(OcrLine(parts[1], 500, top + 2, 700, top + h - 2)) }
        }
        // Recognizer block order is not reliable: odd positions first, then the rest backwards.
        return out.enumerated().filter { $0.offset % 2 == 1 }.map(\.element) + out.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).reversed()
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Int64 { CivilDate(year: y, month: m, day: d).epochDay }

    func testJapaneseRamen() {
        let g = ReceiptParser.parse(receipt(
            "一蘭 新宿中央東口店", "領収書", "2024年6月12日 13:05",
            "ラーメン | ¥980", "替玉 | ¥210", "半熟卵 | ¥140",
            "小計 | ¥1,330", "(内消費税 | ¥120)", "合計 | ¥1,330", "お預り | ¥2,000", "お釣り | ¥670"))
        XCTAssertTrue(g.isReceipt)
        XCTAssertEqual("一蘭 新宿中央東口店", g.store)
        XCTAssertEqual(1330, g.total)
        XCTAssertEqual("JPY", g.currency)
        XCTAssertEqual(day(2024, 6, 12), g.date)
        XCTAssertEqual(13 * 60 + 5, g.minuteOfDay)
    }

    func testJapaneseReiwaAndFullWidth() {
        let g = ReceiptParser.parse(receipt("ファミリーマート", "令和6年6月11日(火) 21:47", "おにぎり | ￥１５０", "お茶 | ￥１６０", "合計 | ￥３１０", "現計 | ￥３１０"))
        XCTAssertEqual(310, g.total)
        XCTAssertEqual(day(2024, 6, 11), g.date)
        XCTAssertEqual("ファミリーマート", g.store)
    }

    func testTotalOnSameLine() {
        let g = ReceiptParser.parse(receipt("唐吉訶德", "商品A ¥2,980", "商品B ¥3,000", "合計 ¥5,980", "お預り ¥10,000", "お釣 ¥4,020"))
        XCTAssertEqual(5980, g.total)
    }

    func testTaiwanInvoice() {
        let g = ReceiptParser.parse(receipt("全家便利商店", "電子發票證明聯", "113-06-12 08:15:22", "拿鐵 | 65", "三明治 | 45", "總計 | 110", "現金 | 200", "找零 | 90"))
        XCTAssertEqual(110, g.total)
        XCTAssertEqual("TWD", g.currency)
        XCTAssertEqual(day(2024, 6, 12), g.date)
        XCTAssertEqual(8 * 60 + 15, g.minuteOfDay)
    }

    func testKoreanReceipt() {
        let g = ReceiptParser.parse(receipt("스타벅스 명동점", "영수증", "2023-09-16 10:20", "아메리카노 | 4,500", "라떼 | 5,000", "합계 | 9,500", "받은금액 | 10,000", "거스름돈 | 500"))
        XCTAssertEqual(9500, g.total)
        XCTAssertEqual("KRW", g.currency)
    }

    func testEnglishReceipt() {
        let g = ReceiptParser.parse(receipt("BLUE BOTTLE COFFEE", "06/12/2024", "Latte | 6.50", "Muffin | 4.25", "Subtotal | 10.75", "Tax | 0.86", "TOTAL | 11.61", "CASH | 20.00", "CHANGE | 8.39"))
        XCTAssertEqual(11.61, g.total ?? 0, accuracy: 0.001)
        XCTAssertEqual("BLUE BOTTLE COFFEE", g.store)
    }

    func testPhoneAndTimeAreNotAmounts() {
        XCTAssertEqual([], ReceiptParser.amountsIn("TEL 03-1234-5678"))
        XCTAssertEqual([], ReceiptParser.amountsIn("2024/06/12 13:05"))
        XCTAssertEqual([1330], ReceiptParser.amountsIn("合計 ¥1,330"))
        XCTAssertEqual([980], ReceiptParser.amountsIn("ラーメン x2 ¥980"))
    }

    func testFoodPhotoIsNotReceipt() {
        XCTAssertFalse(ReceiptParser.parse(receipt("一蘭", "ICHIRAN")).isReceipt)
        XCTAssertTrue(ReceiptParser.parse(receipt("一蘭", "ICHIRAN"), force: true).isReceipt) // 拍收據
    }

    func testHandwritten() {
        var r = parseHandwritten("拉麵 1200")
        XCTAssertEqual("拉麵", r.title); XCTAssertEqual(1200, r.amount)
        r = parseHandwritten("350 咖啡")
        XCTAssertEqual("咖啡", r.title); XCTAssertEqual(350, r.amount)
        r = parseHandwritten("晚餐\n1,280 元")
        XCTAssertEqual("晚餐", r.title); XCTAssertEqual(1280, r.amount)
        r = parseHandwritten("taxi 12.5")
        XCTAssertEqual("taxi", r.title); XCTAssertEqual(12.5, r.amount)
        r = parseHandwritten("伴手禮")
        XCTAssertEqual("伴手禮", r.title); XCTAssertNil(r.amount)
    }

    func testMarkedAmounts() {
        // Rows are 40 px apart from y = 80; amounts sit in their own boxes at x 500…700.
        let lines = receipt("一蘭", "ラーメン | ¥980", "替玉 | ¥210", "半熟卵 | ¥140", "合計 | ¥1,330", "お預り | ¥2,000")
        // A circle around the 替玉 amount only.
        var m = markedAmounts(lines, marks: [MarkBox(left: 480, top: 118, right: 720, bottom: 152)])
        XCTAssertEqual([210], m.marked)
        XCTAssertEqual([980, 140], m.rest) // the total and the cash line are not items
        // A line through the names of the first two items.
        m = markedAmounts(lines, marks: [MarkBox(left: 30, top: 90, right: 200, bottom: 100), MarkBox(left: 30, top: 130, right: 200, bottom: 140)])
        XCTAssertEqual([980, 210], m.marked)
        XCTAssertEqual(1190, m.markedTotal)
        XCTAssertEqual([140], m.rest)
        XCTAssertEqual([], markedAmounts(lines, marks: []).marked)
    }
}
