import Foundation
import XCTest
@testable import LedgerCore

final class FormatTests: XCTestCase {
    func testEpochDays() {
        XCTAssertEqual(CivilDate(year: 1970, month: 1, day: 1).epochDay, 0)
        XCTAssertEqual(CivilDate(year: 2026, month: 10, day: 22).epochDay, 20748)
        XCTAssertEqual(CivilDate(epochDay: 20753), CivilDate(year: 2026, month: 10, day: 27))
        XCTAssertEqual(CivilDate(epochDay: -1), CivilDate(year: 1969, month: 12, day: 31))
        XCTAssertEqual(CivilDate(year: 2024, month: 2, day: 29).epochDay + 1, CivilDate(year: 2024, month: 3, day: 1).epochDay)
        XCTAssertEqual(CivilDate(epochDay: 20748).weekday, 4, "2026/10/22 is a Thursday")
    }

    func testDates() {
        XCTAssertEqual(fmtShortDate(20748), "10/22(四)")
        XCTAssertEqual(fmtShortDate(20753), "10/27(二)")
        XCTAssertEqual(fmtDayHeader(20748), "10月22日 週四")
        XCTAssertEqual(fmtShortDateTime(20748, 14 * 60 + 32), "10/22 週四 14:32")
        XCTAssertEqual(fmtShortDateTime(20748, nil), "10/22 週四")
        XCTAssertEqual(fmtDate(20748), "2026/10/22")
        XCTAssertEqual(fmtTime(540), "09:00")
    }

    func testRanges() {
        XCTAssertEqual(fmtRange(20748, 20753, thisYear: 2026), "10/22 – 10/27")
        let dec20 = CivilDate(year: 2023, month: 12, day: 20).epochDay
        XCTAssertEqual(fmtRange(dec20, dec20 + 6, thisYear: 2026), "2023/12/20 – 12/26")
        XCTAssertEqual(fmtRange(dec20 + 10, dec20 + 14, thisYear: 2026), "2023/12/30 – 2024/1/3")
    }

    func testMoney() {
        XCTAssertEqual(fmtMoney(28450), "NT$ 28,450")
        XCTAssertEqual(fmtMoney(1487.5), "NT$ 1,488")
        XCTAssertEqual(fmtMoney(0), "NT$ 0")
        XCTAssertEqual(fmtMoney(1234567.4), "NT$ 1,234,567")
        XCTAssertEqual(fmtAmount(12000, "KRW"), "KRW 12,000")
        XCTAssertEqual(fmtAmount(1234.5, "JPY"), "JPY 1,234.5")
        XCTAssertEqual(fmtAmount(1200, "TWD"), "NT$ 1,200")
        XCTAssertEqual(fmtPlain(0.125), "0.12", "half-even like Java's NumberFormat")
        XCTAssertEqual(fmtPlain(12.05), "12.05")
        XCTAssertEqual(fmtNumber(1200), "1200")
        XCTAssertEqual(fmtNumber(0.2150), "0.215")
        XCTAssertEqual(fmtNumber(0.024), "0.024")
        XCTAssertEqual(fmtRate(0.024), "0.0240")
    }

    func testHomeAmountMatchesJavaBigDecimal() {
        XCTAssertEqual(toHomeAmount(12000, 0.024), 288)
        XCTAssertEqual(toHomeAmount(5000, 0.024), 120)
        XCTAssertEqual(toHomeAmount(1200, 1), 1200)
        // 1.005 is 1.00499999999999989… as a double, so BigDecimal rounds it down.
        XCTAssertEqual(toHomeAmount(1.005, 1), 1.0)
        // 0.125 is exact: half up.
        XCTAssertEqual(toHomeAmount(0.125, 1), 0.13)
        XCTAssertEqual(toHomeAmount(1234, 0.2135), 263.46)
        XCTAssertEqual(toHomeAmount(999, 0.21), 209.79)
        XCTAssertEqual(toHomeAmount(0, 0.21), 0)
        XCTAssertEqual(toHomeAmount(123456789, 4.5), 555555550.5)
    }

    func testTripStatus() {
        XCTAssertEqual(tripStatus(start: 10, end: 14, today: 9), "明天出發")
        XCTAssertEqual(tripStatus(start: 10, end: 14, today: 0), "還有 10 天出發")
        XCTAssertEqual(tripStatus(start: 10, end: 14, today: 12), "旅行中 · 第 3 天")
        XCTAssertEqual(tripStatus(start: 10, end: 14, today: 15), "已結束")
    }

    func testSafeFileName() {
        XCTAssertEqual(safeFileName("首爾 賞楓/2026"), "首爾_賞楓_2026")
        XCTAssertEqual(safeFileName("a  :: b"), "a_b")
        XCTAssertEqual(safeFileName(""), "旅程")
        XCTAssertEqual(safeFileName(String(repeating: "長", count: 50)).count, 40)
    }

    func testJavaHashCode() {
        XCTAssertEqual(javaHashCode("吃"), 21507)
        XCTAssertEqual(javaHashCode("hello"), 99162322)
        XCTAssertEqual(javaHashCode("小美的旅程很長很長很長很長"), {
            var h: Int32 = 0
            for u in "小美的旅程很長很長很長很長".utf16 { h = h &* 31 &+ Int32(u) }
            return h
        }())
        XCTAssertEqual(floorMod(-7, 3), 2)
    }
}

final class JSONTests: XCTestCase {
    func testKeepsExactLongs() throws {
        let o = try XCTUnwrap(try JSON.parse(#"{"day":-9223372036854775808,"a":1200,"b":1200.5,"c":null,"s":"xé😀\/"}"#).objectValue)
        XCTAssertEqual(o.int64("day"), Int64.min)
        XCTAssertEqual(o.double("a"), 1200)
        XCTAssertEqual(o.int64("b"), 1200)
        XCTAssertNil(o.string("c"))
        XCTAssertNil(o.int64("missing"))
        XCTAssertEqual(o.string("s"), "xé😀/")
        XCTAssertEqual(JSON.object(o).text(), #"{"day":-9223372036854775808,"a":1200,"b":1200.5,"c":null,"s":"xé😀/"}"#)
    }

    func testDoublesWriteLikeOrgJson() {
        XCTAssertEqual(JSON.double(40000).text(), "40000")
        XCTAssertEqual(JSON.double(0.024).text(), "0.024")
        XCTAssertEqual(JSON.double(1487.5).text(), "1487.5")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try JSON.parse("{"))
        XCTAssertThrowsError(try JSON.parse("[1,]"))
        XCTAssertThrowsError(try JSON.parse("nul"))
    }
}

final class TripListTests: XCTestCase {
    private func t(_ id: Int64, _ start: Int64, _ end: Int64, sharedBy: String? = nil, archived: Bool = false) -> Trip {
        Trip(id: id, name: "t\(id)", startDate: start, endDate: end, archived: archived, sharedBy: sharedBy)
    }

    func testAutoOpenPicksTheCurrentTrip() {
        let today: Int64 = 1000
        XCTAssertNil(tripToOpenAtLaunch([t(1, 1100, 1105), t(2, 900, 990)], today: today), "more than 30 days ahead, or over")
        XCTAssertEqual(tripToOpenAtLaunch([t(1, 1030, 1035)], today: today), 1, "starts within 30 days")
        XCTAssertEqual(tripToOpenAtLaunch([t(1, 1020, 1025), t(2, 995, 1001, sharedBy: "阿姨")], today: today), 1, "my own first")
        XCTAssertEqual(tripToOpenAtLaunch([t(1, 1020, 1025), t(2, 1005, 1008)], today: today), 2, "earliest start")
        XCTAssertNil(tripToOpenAtLaunch([t(1, 995, 1001, archived: true)], today: today))
    }

    func testDefaultTab() {
        XCTAssertEqual(TripTab.default(start: 10, end: 14, today: 9), .plan)
        XCTAssertEqual(TripTab.default(start: 10, end: 14, today: 10), .today)
        XCTAssertEqual(TripTab.default(start: 10, end: 14, today: 15), .stats)
    }

    func testFilters() {
        let today: Int64 = 1000
        let trips = [
            TripSummary(id: 1, name: "a", startDate: 1200, endDate: 1205),
            TripSummary(id: 2, name: "b", startDate: 1100, endDate: 1105),
            TripSummary(id: 3, name: "c", startDate: 900, endDate: 905),
        ]
        XCTAssertEqual(TripFilter.initial(trips, today: today), .active)
        XCTAssertEqual(TripFilter.active.apply(trips, today: today).map(\.id), [2, 1], "nearest first")
        XCTAssertEqual(TripFilter.ended.apply(trips, today: today).map(\.id), [3])
        XCTAssertEqual(TripFilter.all.apply(trips, today: today).map(\.id), [1, 2, 3])
        XCTAssertEqual(TripFilter.initial([trips[2]], today: today), .all)
        XCTAssertEqual(TripFilter.initial([], today: today), .active)
    }

    func testBackupReminder() {
        let today: Int64 = 1000
        let trips = [
            TripSummary(id: 1, name: "a", startDate: 980, endDate: 990),
            TripSummary(id: 2, name: "b", startDate: 960, endDate: 970),
            TripSummary(id: 3, name: "c", startDate: 985, endDate: 995, sharedBy: "阿姨"),
        ]
        XCTAssertEqual(backupReminder(trips, today: today, lastBackupDay: -1, dismissedDay: -1)?.id, 1)
        XCTAssertNil(backupReminder(trips, today: today, lastBackupDay: 991, dismissedDay: -1))
        XCTAssertNil(backupReminder(trips, today: today, lastBackupDay: -1, dismissedDay: 990))
    }

    func testCoverArt() {
        XCTAssertEqual(CoverArt.pick(name: "首爾賞楓", start: nil).theme, .autumn)
        XCTAssertEqual(CoverArt.pick(name: "首爾賞楓", start: nil).landmarks, [.seoulTower])
        XCTAssertEqual(CoverArt.pick(name: "沖繩", start: nil), CoverSpec(theme: .beach, landmarks: []))
        XCTAssertEqual(CoverArt.pick(name: "東京", start: CivilDate(year: 2026, month: 4, day: 1)).theme, .sakura)
        XCTAssertEqual(CoverArt.pick(name: "札幌", start: CivilDate(year: 2026, month: 1, day: 1)).theme, .snow)
        XCTAssertEqual(CoverArt.pick(name: "隨便走走", start: nil).theme, .generic)
        XCTAssertEqual(CoverArt.pick(name: "東京", start: nil, chosen: .food).theme, .food)
    }

    func testCategoryGuess() {
        XCTAssertEqual(CategoryStyle.guess("交通").icon, "bus")
        XCTAssertEqual(CategoryStyle.guess("吃").color, 3)
        XCTAssertEqual(CategoryStyle.resolve(name: "吃", icon: "", color: -1), CategoryStyle(icon: "food", color: 3))
        XCTAssertEqual(CategoryStyle.resolve(name: "吃", icon: "ramen", color: 7), CategoryStyle(icon: "ramen", color: 7))
        XCTAssertEqual(CategoryStyle.resolve(name: nil, icon: nil, color: nil), CategoryStyle(icon: "more", color: 9))
        XCTAssertEqual(CategoryStyle.guess("Hello").color, floorMod(Int(javaHashCode("Hello")), 10))
    }

    func testSvgPath() {
        let cmds = SVGPath.parse("M0,-14 L3,-6 H5 V2 Z m1 1 q15,-6 30,0 t30,0")
        XCTAssertEqual(cmds.first, .move(SVGPoint(0, -14)))
        XCTAssertEqual(cmds[1], .line(SVGPoint(3, -6)))
        XCTAssertEqual(cmds[2], .line(SVGPoint(5, -6)))
        XCTAssertEqual(cmds[3], .line(SVGPoint(5, 2)))
        XCTAssertEqual(cmds[4], .close)
        XCTAssertEqual(cmds[5], .move(SVGPoint(1, -13)), "relative to the start of the closed path")
        XCTAssertEqual(cmds[6], .quad(SVGPoint(16, -19), SVGPoint(31, -13)))
        XCTAssertEqual(cmds[7], .quad(SVGPoint(46, -7), SVGPoint(61, -13)), "t reflects the last control point")
        // Compact numbers: "c0-.83-.67-1.5-1.5-1.5"
        let c = SVGPath.parse("M10 0c0-.83-.67-1.5-1.5-1.5")
        XCTAssertEqual(c[1], .cubic(SVGPoint(10, -0.83), SVGPoint(9.33, -1.5), SVGPoint(8.5, -1.5)))
    }
}
