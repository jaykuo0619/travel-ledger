import XCTest
@testable import LedgerCore

/// desktop/test/parser-cases.json: the cases Android and the desktop planner also run.
final class PlanParserTests: XCTestCase {
    func testSharedCases() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("desktop/test/parser-cases.json"))
        let cases = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 10)
        for c in cases {
            let fn = c["fn"] as? String ?? "", input = c["input"] as? String ?? ""
            let expect = c["expect"]
            switch fn {
            case "splitNote":
                let want = (expect as? [[String: Any]] ?? []).map(place)
                XCTAssertEqual(want, PlanParser.splitNote(input), input)
            case "parseShare":
                var want = place(expect as? [String: Any] ?? [:])
                want.minuteOfDay = nil
                XCTAssertEqual(want, PlanParser.parseShare(input), input)
            case "findTime":
                XCTAssertEqual((expect as? NSNumber)?.intValue, PlanParser.findTime(input), input)
            case "guessCategory":
                XCTAssertEqual(expect as? String, PlanParser.guessCategory(input), input)
            default:
                XCTFail("unknown case \(fn)")
            }
        }
    }

    private func place(_ o: [String: Any]) -> ParsedPlace {
        ParsedPlace(title: o["title"] as? String ?? "", location: o["location"] as? String ?? "",
                    categoryHint: o["category"] as? String, minuteOfDay: (o["minuteOfDay"] as? NSNumber)?.intValue)
    }

    func testParseLines() {
        let got = PlanParser.parseLines("1. 一蘭拉麵 本店\n- 淺草寺\n\nhttps://maps.app.goo.gl/x")
        XCTAssertEqual(["一蘭拉麵 本店", "淺草寺", "地圖地點"], got.map(\.title))
        XCTAssertEqual(["吃", "景點", nil], got.map(\.categoryHint))
        XCTAssertEqual("https://maps.app.goo.gl/x", got[2].location)
    }

    func testSplitAndUndo() throws {
        let phone = try Phone()
        let tripId = try phone.db.write { try Q.createTrip($0, Trip(name: "首爾", startDate: 20748, endDate: 20753), members: [], rates: []) }
        let original = try phone.db.write { db -> PlanItem in
            try Q.putDayNote(db, DayNote(tripId: tripId, day: 20749, text: "早點出門"))
            let id = try Q.savePlan(db, PlanItem(tripId: tripId, title: "第二天", date: 20749, note: "09:00 景福宮\n中午 土俗村蔘雞湯"),
                                    pictures: [PlanPhoto(planItemId: 0, path: "photos/plans/a.jpg")]).id
            _ = try Q.saveExpense(db, Expense(tripId: tripId, date: 20749, amount: 1, currency: "TWD", rate: 1, homeAmount: 1, planItemId: id), photos: [])
            return try XCTUnwrap(try Q.plan(db, id))
        }
        let parsed = PlanParser.splitNote(original.note)
        XCTAssertEqual(2, parsed.count)
        let items = parsed.map { PlanItem(tripId: tripId, title: $0.title, date: original.date, minuteOfDay: $0.minuteOfDay, location: $0.location) }
        let undo = try phone.db.write { try Q.splitPlan($0, original: original, items: items, shared: false) }
        var plans = try phone.plans(tripId)
        XCTAssertEqual(["景福宮", "土俗村蔘雞湯"], plans.map(\.title))
        XCTAssertEqual(1, try phone.planPhotos(try XCTUnwrap(plans[0].id)).count) // the picture moved to the first one
        XCTAssertEqual("早點出門\n\n【第二天】\n09:00 景福宮\n中午 土俗村蔘雞湯", try phone.dayNote(tripId, 20749))
        XCTAssertNil(try phone.expenses(tripId)[0].planItemId)

        try phone.db.write { try Q.undoSplit($0, undo) }
        plans = try phone.plans(tripId)
        XCTAssertEqual(["第二天"], plans.map(\.title))
        XCTAssertEqual(original.id, plans[0].id)
        XCTAssertEqual(1, try phone.planPhotos(try XCTUnwrap(original.id)).count)
        XCTAssertEqual("早點出門", try phone.dayNote(tripId, 20749))
        XCTAssertEqual(original.id, try phone.expenses(tripId)[0].planItemId)
    }
}
