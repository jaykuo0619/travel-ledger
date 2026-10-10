import XCTest
@testable import LedgerCore

/// Recording expenses: the keypad, defaults, saving, and category / payment method management.
final class ExpenseTests: XCTestCase {
    func testKeypad() {
        XCTAssertEqual("0.", applyKey("", "."))
        XCTAssertEqual("", applyKey("", "00"))
        XCTAssertEqual("0", applyKey("0", "00"))
        XCTAssertEqual("5", applyKey("0", "5"))
        XCTAssertEqual("1200", applyKey("12", "00"))
        XCTAssertEqual("1.5", applyKey("1.", "5"))
        XCTAssertEqual("1.55", applyKey("1.55", "5")) // two decimals at most
        XCTAssertEqual("1.5", applyKey("1.5", "."))
        XCTAssertEqual("123456789", applyKey("123456789", "1")) // nine digits at most
        XCTAssertEqual("12", applyKey("123", "⌫"))
        XCTAssertEqual("", applyKey("123", "C"))
        XCTAssertEqual("1,234,567.5", fmtTyped("1234567.5"))
        XCTAssertEqual("0.", fmtTyped("0."))
    }

    func testSuggestions() {
        let all = [TitleSuggestion(title: "Ramen", categoryId: 1), TitleSuggestion(title: "拉麵", categoryId: 1), TitleSuggestion(title: "ram", categoryId: nil)]
        XCTAssertEqual(["Ramen"], matchSuggestions(all, typed: "RAM").map(\.title)) // not the text itself
        XCTAssertEqual(3, matchSuggestions(all, typed: "").count)
    }

    func testDefaultsAndSave() throws {
        let phone = try Phone()
        let tripId = try phone.db.write { db in
            try Q.createTrip(db, Trip(name: "首爾", startDate: 20748, endDate: 20753), members: ["我"],
                             rates: [TripCurrencyRate(tripId: 0, currency: "KRW", rate: 0.024)])
        }
        var d = try phone.db.read { try Q.expenseDefaults($0, tripId: tripId, planId: nil) }
        XCTAssertEqual("KRW", d.currency) // no expense yet: the trip's first currency
        XCTAssertEqual("0.024", d.rate)
        XCTAssertEqual(["TWD", "KRW"], d.currencies)
        XCTAssertEqual("吃", try phone.category(d.categoryId))
        XCTAssertEqual("現金", try phone.payment(d.paymentId))

        let planId = try phone.db.write { try Q.savePlan($0, PlanItem(tripId: tripId, title: "廣藏市場"), pictures: []).id }
        let e = Expense(tripId: tripId, date: 20750, amount: 100, currency: "JPY", rate: 0.21, homeAmount: toHomeAmount(100, 0.21),
                        title: "綠豆煎餅", planItemId: planId)
        let saved = try phone.db.write { try Q.saveExpense($0, e, photos: [Photo(expenseId: 0, type: PhotoType.receipt, path: "photos/receipts/a.jpg")]) }
        XCTAssertEqual(PlanStatus.done, try phone.plans(tripId)[0].status) // recording for a plan ticks it
        XCTAssertEqual(0.21, try phone.db.read { try Q.rates($0, tripId) }.first { $0.currency == "JPY" }?.rate) // remembered
        XCTAssertEqual(1, try phone.photos(saved.id).count)
        XCTAssertFalse(try phone.expenses(tripId)[0].pending)

        d = try phone.db.read { try Q.expenseDefaults($0, tripId: tripId, planId: nil) }
        XCTAssertEqual("JPY", d.currency) // the last expense's
        XCTAssertEqual(["綠豆煎餅"], try phone.db.read { try Q.titleSuggestions($0) }.map(\.title))

        // Editing: the photo is removed, its file is reported for deletion.
        let again = try phone.db.write { try Q.saveExpense($0, try XCTUnwrap(try Q.expense($0, saved.id)), photos: []) }
        XCTAssertEqual(["photos/receipts/a.jpg"], again.removed)
        XCTAssertEqual([], try phone.db.write { try Q.deleteExpense($0, saved.id) })
        XCTAssertEqual(0, try phone.expenses(tripId).count)
    }

    func testSharedTripExpenseIsPending() throws {
        let phone = try Phone()
        let tripId = try phone.importOK(fixture("trip.zip")).ids[0]
        let e = Expense(tripId: tripId, date: 20750, amount: 5, currency: "USD", rate: 32, homeAmount: 160)
        _ = try phone.db.write { try Q.saveExpense($0, e, photos: []) }
        XCTAssertTrue(try XCTUnwrap(try phone.expenses(tripId).last).pending)
        XCTAssertNil(try phone.db.read { try Q.rates($0, tripId) }.first { $0.currency == "USD" }) // their trip's rates stay
    }

    func testCategoriesAndPaymentMethods() throws {
        let phone = try Phone()
        let tripId = try phone.db.write { try Q.createTrip($0, Trip(name: "t", startDate: 1, endDate: 2), members: [], rates: []) }
        try phone.db.write { try Q.addCategory($0, name: "按摩", icon: "more", color: 3) }
        var cats = try phone.db.read { try Q.categories($0) }
        XCTAssertEqual("按摩", cats.last?.name)
        let massage = try XCTUnwrap(cats.last?.id)
        _ = try phone.db.write { try Q.saveExpense($0, Expense(tripId: tripId, date: 1, amount: 1, currency: "TWD", rate: 1, homeAmount: 1, categoryId: massage), photos: []) }
        try phone.db.write { try Q.moveCategory($0, from: cats.count - 1, to: 0) }
        cats = try phone.db.read { try Q.categories($0) }
        XCTAssertEqual("按摩", cats.first?.name)
        try phone.db.write { try Q.deleteCategory($0, massage) }
        XCTAssertEqual("其他", try phone.category(try phone.expenses(tripId)[0].categoryId))

        try phone.db.write { try Q.addPaymentMethod($0, name: "悠遊卡") }
        let card = try XCTUnwrap(try phone.db.read { try Q.paymentMethods($0) }.last?.id)
        try phone.db.write { try $0.execute(sql: "UPDATE expense SET paymentMethodId = ?", arguments: [card]) }
        try phone.db.write { try Q.deletePaymentMethod($0, card) }
        XCTAssertNil(try phone.expenses(tripId)[0].paymentMethodId)
    }

    func testReferenceRates() throws {
        let json = #"{"result":"success","base_code":"TWD","rates":{"TWD":1,"JPY":4.6860,"KRW":42.65,"USD":0.03110,"XXX":0}}"#
        let r = try XCTUnwrap(ReferenceRates.parse(Data(json.utf8), now: 1000))
        XCTAssertEqual("0.2134", r.suggestion("JPY"))
        XCTAssertEqual("0.02345", r.suggestion("KRW"))
        XCTAssertEqual("32.15", r.suggestion("USD"))
        XCTAssertNil(r.suggestion("TWD")) // the home currency is always 1
        XCTAssertNil(r.suggestion("XXX"))
        XCTAssertNil(r.suggestion("ABC"))
        XCTAssertFalse(r.isStale(now: 1000 + 3_600_000))
        XCTAssertTrue(r.isStale(now: 1000 + 90_000_000))
        XCTAssertNil(ReferenceRates.parse(Data(#"{"result":"error"}"#.utf8)))
    }

    func testQuickExpense() throws {
        let phone = try Phone()
        XCTAssertThrowsError(try phone.db.write { try Q.quickExpense($0, amount: 10, title: nil, currency: nil, reference: nil, today: 20750) }) {
            XCTAssertEqual(QuickExpenseError.noTrip, $0 as? QuickExpenseError)
        }
        let tripId = try phone.db.write { db in
            try Q.createTrip(db, Trip(name: "首爾", startDate: 20748, endDate: 20753), members: [],
                             rates: [TripCurrencyRate(tripId: 0, currency: "KRW", rate: 0.024)])
        }
        let r = try phone.db.write { try Q.quickExpense($0, amount: 3000, title: " 晚餐 ", currency: nil, reference: nil, today: 20750, minuteOfDay: 1140) }
        XCTAssertEqual("首爾", r.trip.name)
        XCTAssertEqual("KRW", r.expense.currency)
        XCTAssertEqual(72, r.expense.homeAmount)
        XCTAssertEqual("晚餐", r.expense.title)
        XCTAssertEqual(1, try phone.expenses(tripId).count)
        // A currency the trip has no rate for: the reference rate, or an error when there is none.
        XCTAssertThrowsError(try phone.db.write { try Q.quickExpense($0, amount: 5, title: nil, currency: "usd", reference: nil, today: 20750) }) {
            XCTAssertEqual(QuickExpenseError.noRate("USD"), $0 as? QuickExpenseError)
        }
        let ref = ReferenceRates(perHome: ["USD": 0.0311], fetchedAt: 0)
        let usd = try phone.db.write { try Q.quickExpense($0, amount: 5, title: nil, currency: "usd", reference: ref, today: 20750) }
        XCTAssertEqual(32.15, usd.expense.rate)
        XCTAssertThrowsError(try phone.db.write { try Q.quickExpense($0, amount: 0, title: nil, currency: nil, reference: nil, today: 20750) })
    }
}
