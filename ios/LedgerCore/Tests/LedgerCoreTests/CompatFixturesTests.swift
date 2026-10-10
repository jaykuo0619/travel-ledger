import Foundation
import XCTest
@testable import LedgerCore

/// Compat test 1 (docs/IOS_PORT.md §7): files the Android app and the desktop planner wrote (compat/fixtures)
/// import here field by field, with the values listed in compat/README.md.
final class CompatFixturesTests: XCTestCase {

    // MARK: trip.zip

    func testSummaryOfSharedTrip() throws {
        let s = try TripArchive.readSummary(fixture("trip.zip"))
        XCTAssertEqual(s.kind, "trip")
        XCTAssertEqual(s.sharedBy, "小明")
        XCTAssertEqual(s.exportedAt, 1_790_000_100_000)
        XCTAssertEqual(s.photoCount, 2)
        XCTAssertEqual(s.trips, [TripArchive.TripInfo(uuid: "trip-seoul", name: "首爾賞楓", startDate: 20748, endDate: 20753, expenseCount: 2, totalHome: 1488)])
    }

    func testSharedTripImportsAsReadOnlyCopy() throws {
        let phone = try Phone()
        let r = try phone.importOK(fixture("trip.zip"))
        XCTAssertEqual(r.kind, "trip")
        XCTAssertEqual(r.updated, 0)

        let t = try phone.trip("trip-seoul")
        XCTAssertEqual(r.ids, [t.id!])
        XCTAssertEqual(t.name, "首爾賞楓")
        XCTAssertEqual(t.startDate, 20748)
        XCTAssertEqual(t.endDate, 20753)
        XCTAssertEqual(t.homeCurrency, "TWD")
        XCTAssertEqual(t.budget, 40000)
        XCTAssertTrue(t.splitEnabled)
        XCTAssertEqual(t.navApp, "naver")
        XCTAssertEqual(t.sharedBy, "小明")
        XCTAssertEqual(t.sharedAt, 1_790_000_100_000)
        XCTAssertEqual(t.createdAt, 1_790_000_000_000)
        XCTAssertTrue(t.readOnly)
        XCTAssertNil(t.coverPath)

        let tripId = t.id!
        XCTAssertEqual(try phone.members(tripId).map(\.name), ["我", "小美"])
        let rates = try phone.db.read { try Q.rates($0, tripId) }
        XCTAssertEqual(rates.map(\.currency), ["KRW"])
        XCTAssertEqual(rates.first?.rate, 0.024)
        XCTAssertEqual(rates.first?.source, "manual")

        // Plans
        let plans = try phone.plans(tripId)
        XCTAssertEqual(plans.map(\.uuid), ["plan-palace", "plan-market", "plan-oy"])
        let palace = plans[0]
        XCTAssertEqual(palace.title, "景福宮 韓服體驗")
        XCTAssertEqual(try phone.category(palace.categoryId), "景點")
        XCTAssertEqual(palace.date, 20749)
        XCTAssertEqual(palace.minuteOfDay, 540)
        XCTAssertEqual(palace.status, PlanStatus.todo)
        XCTAssertEqual(palace.reservation, Reservation.booked)
        XCTAssertEqual(palace.reservationNote, "10:00 兩位 #A123")
        XCTAssertEqual(palace.location, "https://maps.app.goo.gl/palace")
        XCTAssertEqual(palace.note, "韓服要先預約 https://hanbok.example.com 電話 02-1234-5678")
        XCTAssertFalse(palace.pending)
        let pictures = try phone.planPhotos(palace.id!)
        XCTAssertEqual(pictures.count, 1)
        XCTAssertEqual(pictures[0].width, 64)
        XCTAssertEqual(pictures[0].height, 48)
        XCTAssertTrue(pictures[0].path.hasPrefix("photos/plans/"))
        let jpeg = try Data(contentsOf: phone.files.url(pictures[0].path))
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8], "a real JPEG")

        let market = plans[1]
        XCTAssertEqual(market.title, "廣藏市場")
        XCTAssertEqual(try phone.category(market.categoryId), "吃")
        XCTAssertEqual(market.date, 20750)
        XCTAssertNil(market.minuteOfDay)

        let oy = plans[2]
        XCTAssertEqual(oy.title, "Olive Young")
        XCTAssertEqual(try phone.category(oy.categoryId), "購物")
        XCTAssertNil(oy.date, "待排")

        // Day notes, including the 待排 note at Int64.min
        XCTAssertEqual(try phone.dayNote(tripId, 20749), "早點出門")
        XCTAssertEqual(try phone.dayNote(tripId, unscheduledDay), "有空再去")
        XCTAssertEqual(try phone.db.read { try Q.dayNotes($0, tripId) }.count, 2)

        // Expenses
        let expenses = try phone.expenses(tripId)
        XCTAssertEqual(expenses.map(\.uuid), ["exp-metro", "exp-pancake"])
        let members = try phone.members(tripId)
        let metro = expenses[0]
        XCTAssertEqual(metro.title, "機場捷運")
        XCTAssertEqual(metro.date, 20748)
        XCTAssertEqual(metro.minuteOfDay, 930)
        XCTAssertEqual(metro.amount, 1200)
        XCTAssertEqual(metro.currency, "TWD")
        XCTAssertEqual(metro.rate, 1)
        XCTAssertEqual(metro.homeAmount, 1200)
        XCTAssertEqual(try phone.category(metro.categoryId), "交通")
        XCTAssertEqual(try phone.payment(metro.paymentMethodId), "信用卡")
        XCTAssertEqual(metro.payerId, members[0].id)
        XCTAssertNil(metro.planItemId)
        XCTAssertTrue(try phone.photos(metro.id!).isEmpty)

        let pancake = expenses[1]
        XCTAssertEqual(pancake.title, "綠豆煎餅")
        XCTAssertEqual(pancake.date, 20750)
        XCTAssertNil(pancake.minuteOfDay)
        XCTAssertEqual(pancake.amount, 12000)
        XCTAssertEqual(pancake.currency, "KRW")
        XCTAssertEqual(pancake.rate, 0.024)
        XCTAssertEqual(pancake.homeAmount, 288)
        XCTAssertEqual(try phone.category(pancake.categoryId), "吃")
        XCTAssertEqual(try phone.payment(pancake.paymentMethodId), "現金")
        XCTAssertEqual(pancake.payerId, members[1].id)
        XCTAssertEqual(pancake.note, "很好吃")
        XCTAssertEqual(pancake.planItemId, market.id)
        XCTAssertFalse(pancake.pending)
        let receipt = try phone.photos(pancake.id!)
        XCTAssertEqual(receipt.map(\.type), [PhotoType.receipt])
        XCTAssertTrue(receipt[0].path.hasPrefix("photos/receipts/"))
        XCTAssertTrue(phone.files.exists(receipt[0].path))

        // The home card: "小明 分享", 2 people, KRW, total NT$ 1,488.
        let card = try XCTUnwrap(try phone.db.read { try Q.tripSummaries($0) }.first)
        XCTAssertEqual(card.sharedBy, "小明")
        XCTAssertEqual(card.memberCount, 2)
        XCTAssertEqual(card.currencies, ["KRW"])
        XCTAssertEqual(card.totalHome, 1488)
    }

    func testSharedTripAgainUpdatesTheCopyAndKeepsMyAdditions() throws {
        let phone = try Phone()
        let id = try phone.importOK(fixture("trip.zip")).ids[0]
        let market = try phone.plans(id).first { $0.uuid == "plan-market" }!
        try phone.db.write { db in
            var p = PlanItem(tripId: id, title: "我想去", pending: true)
            try p.insert(db)
            var e = Expense(tripId: id, date: 20750, amount: 100, currency: "TWD", rate: 1, homeAmount: 100, planItemId: market.id, pending: true)
            try e.insert(db)
        }
        let again = try phone.importOK(fixture("trip.zip"))
        XCTAssertEqual(again.ids, [id])
        XCTAssertEqual(again.updated, 1)
        let plans = try phone.plans(id)
        XCTAssertEqual(plans.filter { !$0.pending }.count, 3)
        XCTAssertEqual(plans.filter(\.pending).map(\.title), ["我想去"])
        let mine = try phone.expenses(id).first(where: \.pending)!
        XCTAssertEqual(mine.planItemId, plans.first { $0.uuid == "plan-market" }!.id, "re-linked by uuid to the new row")
        XCTAssertEqual(try phone.expenses(id).count, 3)
        // Old official pictures were replaced, not piled up.
        let all = try FileManager.default.contentsOfDirectory(atPath: phone.files.url("photos/plans").path)
        XCTAssertEqual(all.count, 1)
    }

    func testOwnTripComingBackIsRefused() throws {
        let phone = try Phone()
        try phone.importOK(fixture("backup.zip"))
        XCTAssertEqual(phone.archive.importFile(fixture("trip.zip")), .failed("「首爾賞楓」是你自己記的旅程,不需要匯入"))
    }

    // MARK: backup.zip

    func testBackupRestoresOwnAndSharedTrips() throws {
        let phone = try Phone()
        let s = try TripArchive.readSummary(fixture("backup.zip"))
        XCTAssertEqual(s.kind, "backup")
        XCTAssertNil(s.sharedBy)
        XCTAssertEqual(s.trips.map(\.uuid), ["trip-seoul", "trip-okinawa"])

        let r = try phone.importOK(fixture("backup.zip"))
        XCTAssertEqual(r.kind, "backup")
        XCTAssertEqual(r.ids.count, 2)
        XCTAssertEqual(r.updated, 0)

        let seoul = try phone.trip("trip-seoul")
        XCTAssertNil(seoul.sharedBy)
        XCTAssertFalse(seoul.readOnly)
        XCTAssertEqual(seoul.budget, 40000)
        XCTAssertEqual(try phone.plans(seoul.id!).count, 3)
        XCTAssertEqual(try phone.expenses(seoul.id!).count, 2)
        XCTAssertEqual(try phone.dayNote(seoul.id!, unscheduledDay), "有空再去")
        XCTAssertEqual(try phone.expenses(seoul.id!)[1].payerId, try phone.members(seoul.id!)[1].id)

        let okinawa = try phone.trip("trip-okinawa")
        XCTAssertEqual(okinawa.name, "沖繩")
        XCTAssertEqual(okinawa.startDate, 20800)
        XCTAssertEqual(okinawa.endDate, 20803)
        XCTAssertEqual(okinawa.sharedBy, "阿姨")
        XCTAssertTrue(okinawa.readOnly)
        let plans = try phone.plans(okinawa.id!)
        XCTAssertEqual(plans.map(\.uuid), ["plan-aquarium", "plan-kouri"])
        XCTAssertEqual(plans[0].title, "美麗海水族館")
        XCTAssertEqual(plans[0].date, 20801)
        XCTAssertFalse(plans[0].pending)
        XCTAssertEqual(plans[1].title, "古宇利島")
        XCTAssertNil(plans[1].date)
        XCTAssertTrue(plans[1].pending, "my unsent addition survives a backup")
    }

    func testRestoringABackupAgainReplacesTripsAndWarnsWhenThePhoneIsNewer() throws {
        let phone = try Phone()
        try phone.importOK(fixture("backup.zip"))
        let s = try TripArchive.readSummary(fixture("backup.zip"))
        XCTAssertEqual(try phone.archive.newerOnPhone(s), [])
        let seoul = try phone.trip("trip-seoul").id!
        try phone.db.write { db in
            var e = Expense(tripId: seoul, date: 20751, amount: 50, currency: "TWD", rate: 1, homeAmount: 50, createdAt: s.exportedAt + 1)
            try e.insert(db)
        }
        XCTAssertEqual(try phone.archive.newerOnPhone(s), ["首爾賞楓"])
        let r = try phone.importOK(fixture("backup.zip"))
        XCTAssertEqual(r.updated, 2)
        XCTAssertEqual(r.ids, [seoul, try phone.trip("trip-okinawa").id!])
        XCTAssertEqual(try phone.expenses(seoul).count, 2)
        XCTAssertEqual(try phone.db.read { try Q.trips($0) }.count, 2)
    }

    // MARK: additions.zip

    func testAdditionsReviewList() throws {
        let a = try TripArchive.readAdditions(fixture("additions.zip"))
        XCTAssertEqual(a.tripUuid, "trip-seoul")
        XCTAssertEqual(a.tripName, "首爾賞楓")
        XCTAssertEqual(a.from, "小美")
        XCTAssertEqual(a.items, [
            .init(uuid: "plan-add-dumpling", isExpense: false, title: "明洞餃子", detail: "行程 · 10/25 · 吃"),
            .init(uuid: "exp-add-gimbap", isExpense: true, title: "麻藥飯捲", detail: "10/24 · KRW 5,000 · 吃"),
        ])
    }

    func testAdditionsGoIntoMyTripOnce() throws {
        let phone = try Phone()
        try phone.importOK(fixture("backup.zip"))
        let seoul = try phone.trip("trip-seoul").id!
        let all: Set<String> = ["plan-add-dumpling", "exp-add-gimbap"]
        XCTAssertEqual(phone.archive.importAdditions(fixture("additions.zip"), accepted: all), .imported(kind: "additions", tripIds: [seoul], updated: 2))

        let dumpling = try XCTUnwrap(try phone.plans(seoul).first { $0.uuid == "plan-add-dumpling" })
        XCTAssertEqual(dumpling.title, "明洞餃子")
        XCTAssertEqual(try phone.category(dumpling.categoryId), "吃")
        XCTAssertEqual(dumpling.date, 20751)
        XCTAssertEqual(dumpling.minuteOfDay, 720)
        XCTAssertEqual(dumpling.addedBy, "小美")
        XCTAssertFalse(dumpling.pending)

        let gimbap = try XCTUnwrap(try phone.expenses(seoul).first { $0.uuid == "exp-add-gimbap" })
        XCTAssertEqual(gimbap.title, "麻藥飯捲")
        XCTAssertEqual(gimbap.date, 20750)
        XCTAssertEqual(gimbap.amount, 5000)
        XCTAssertEqual(gimbap.currency, "KRW")
        XCTAssertEqual(gimbap.homeAmount, 120)
        XCTAssertEqual(try phone.category(gimbap.categoryId), "吃")
        XCTAssertEqual(gimbap.planItemId, try phone.plans(seoul).first { $0.uuid == "plan-market" }!.id)
        XCTAssertEqual(gimbap.addedBy, "小美")
        XCTAssertNil(gimbap.payerId)
        XCTAssertFalse(gimbap.pending)
        XCTAssertEqual(try phone.members(seoul).count, 2, "members untouched")

        XCTAssertEqual(phone.archive.importAdditions(fixture("additions.zip"), accepted: all), .imported(kind: "additions", tripIds: [seoul], updated: 0))
    }

    func testAdditionsOnAReadOnlyCopyAreRefused() throws {
        let phone = try Phone()
        try phone.importOK(fixture("trip.zip"))
        XCTAssertEqual(phone.archive.importAdditions(fixture("additions.zip"), accepted: ["plan-add-dumpling"]),
                       .failed("這是給記帳人(小明)的補充,請轉傳給他"))
    }

    func testAdditionsWithoutTheTrip() throws {
        let phone = try Phone()
        XCTAssertEqual(phone.archive.importAdditions(fixture("additions.zip"), accepted: ["plan-add-dumpling"]),
                       .failed("手機上沒有「首爾賞楓」這趟旅程"))
    }

    func testWrongKindsAreSentToTheirOwnScreens() throws {
        let phone = try Phone()
        XCTAssertEqual(phone.archive.importFile(fixture("additions.zip")), .failed("這是同伴的補充檔,請用審核畫面加入"))
        XCTAssertEqual(phone.archive.importFile(fixture("plans.zip")), .failed("這是電腦行程檔,請用併入行程畫面"))
        XCTAssertThrowsError(try TripArchive.readAdditions(fixture("trip.zip"))) { e in
            XCTAssertEqual(e as? TripArchive.BadArchive, .init("這不是補充檔"))
        }
        XCTAssertEqual(phone.archive.importPlans(fixture("trip.zip")), .failed("這不是電腦行程檔"))
    }

    // MARK: plans.zip

    func testDesktopPlansMergeIntoMyTrip() throws {
        let phone = try Phone()
        try phone.importOK(fixture("backup.zip"))
        let seoul = try phone.trip("trip-seoul").id!
        let before = try phone.expenses(seoul)

        let preview = try phone.archive.previewPlans(fixture("plans.zip"))
        XCTAssertEqual(preview.tripName, "首爾賞楓")
        XCTAssertFalse(preview.newTrip)
        XCTAssertNil(preview.refused)
        XCTAssertEqual(preview.deleted, 1)
        XCTAssertEqual(preview.added, 2)

        guard case .imported(kind: "plans", tripIds: [seoul], updated: _) = phone.archive.importPlans(fixture("plans.zip")) else {
            return XCTFail("not merged")
        }
        let plans = try phone.plans(seoul)
        XCTAssertNil(plans.first { $0.uuid == "plan-oy" }, "deleted on the desktop")
        XCTAssertEqual(plans.first { $0.uuid == "plan-market" }?.date, 20751)

        let bus = try XCTUnwrap(plans.first { $0.title == "搭乘 01A 循環公車到南大門市場站" })
        XCTAssertEqual(try phone.category(bus.categoryId), "交通")
        XCTAssertEqual(bus.minuteOfDay, 700)
        XCTAssertEqual(bus.date, 20751)
        let dumpling = try XCTUnwrap(plans.first { $0.title == "明洞餃子" })
        XCTAssertEqual(try phone.category(dumpling.categoryId), "吃")
        XCTAssertEqual(dumpling.date, 20751)

        let palace = try XCTUnwrap(plans.first { $0.uuid == "plan-palace" })
        XCTAssertEqual(palace.reservation, Reservation.none)
        XCTAssertEqual(palace.location, "")
        XCTAssertEqual(palace.note, "韓服要先預約 https://hanbok.example.com")
        let pictures = try phone.planPhotos(palace.id!)
        XCTAssertEqual(pictures.count, 2)
        // The first picture is 7 bytes, not an image: it is kept as a file and shown as a broken picture.
        XCTAssertTrue(pictures.allSatisfy { phone.files.exists($0.path) })

        XCTAssertEqual(try phone.dayNote(seoul, 20750), "先換錢再出門")
        XCTAssertEqual(try phone.dayNote(seoul, unscheduledDay), "有空再去")
        XCTAssertEqual(try phone.expenses(seoul), before, "expenses never change")
    }

    func testDesktopPlansOnAReadOnlyCopyAreRefused() throws {
        let phone = try Phone()
        try phone.importOK(fixture("trip.zip"))
        let preview = try phone.archive.previewPlans(fixture("plans.zip"))
        XCTAssertEqual(preview.refused, "「首爾賞楓」是小明記帳的旅程,請把這個檔案傳給小明")
        XCTAssertEqual(phone.archive.importPlans(fixture("plans.zip")), .failed("「首爾賞楓」是小明記帳的旅程,請把這個檔案傳給小明"))
    }

    func testDesktopPlansMakeANewTripWhenMissing() throws {
        let phone = try Phone()
        let preview = try phone.archive.previewPlans(fixture("plans.zip"))
        XCTAssertTrue(preview.newTrip)
        guard case .imported(_, let ids, _) = phone.archive.importPlans(fixture("plans.zip")) else { return XCTFail() }
        let t = try XCTUnwrap(try phone.db.read { try Q.trip($0, ids[0]) })
        XCTAssertEqual(t.uuid, "trip-seoul")
        XCTAssertNil(t.sharedBy)
        XCTAssertEqual(t.homeCurrency, "TWD")
        XCTAssertTrue(try phone.members(ids[0]).isEmpty)
    }

    // MARK: Broken files

    func testNotOurFile() throws {
        let phone = try Phone()
        let junk = phone.tmp("junk.zip")
        try FileManager.default.createDirectory(at: phone.dir, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: junk)
        XCTAssertThrowsError(try TripArchive.readSummary(junk)) { e in
            XCTAssertEqual(e as? TripArchive.BadArchive, .init("這不是卡溜趴的檔案"))
        }
        XCTAssertEqual(phone.archive.importFile(junk), .failed("這不是卡溜趴的檔案"))
    }
}
