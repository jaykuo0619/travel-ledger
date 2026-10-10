import Foundation
import XCTest
import ZIPFoundation
@testable import LedgerCore

/// Compat tests 2 and 3 (docs/IOS_PORT.md §7): files this app writes carry the same data as Android's, and a
/// trip read and written again is unchanged. With WRITE_FROM_IOS=1 the files go to compat/from-ios for the
/// Android side to import (CompatFixturesTest.filesFromTheIphone).
final class ExportTests: XCTestCase {

    /// The two real JPEGs inside Android's trip.zip (menu screenshot and receipt).
    private func androidJpegs() throws -> (menu: Data, receipt: Data) {
        let zip = try Archive(url: fixture("trip.zip"), accessMode: .read)
        func read(_ name: String) throws -> Data {
            var d = Data()
            _ = try zip.extract(XCTUnwrap(zip[name])) { d.append($0) }
            return d
        }
        return (try read("files/plans/0-menu.jpg"), try read("files/receipts/1-receipt.jpg"))
    }

    /// The organizer's trip, built exactly like Android's CompatFixturesTest.seoul().
    @discardableResult
    private func seoul(_ phone: Phone) throws -> Int64 {
        let jpegs = try androidJpegs()
        let menu = try phone.files.write(jpegs.menu, folder: "photos/plans")
        let receipt = try phone.files.write(jpegs.receipt, folder: "photos/receipts")
        return try phone.db.write { db in
            let cats = try Q.categories(db)
            func cat(_ n: String) -> Int64? { cats.first { $0.name == n }?.id }
            let pays = try Q.paymentMethods(db)
            let trip = try Q.createTrip(
                db,
                Trip(name: "首爾賞楓", startDate: 20748, endDate: 20753, budget: 40000, splitEnabled: true,
                     createdAt: 1_790_000_000_000, uuid: "trip-seoul", navApp: "naver"),
                members: ["我", "小美"],
                rates: [TripCurrencyRate(tripId: 0, currency: "KRW", rate: 0.024, updatedAt: 1_790_000_000_000, source: "manual")]
            )
            var palace = PlanItem(tripId: trip, title: "景福宮 韓服體驗", categoryId: cat("景點"), date: 20749, minuteOfDay: 9 * 60,
                                  reservation: Reservation.booked, reservationNote: "10:00 兩位 #A123",
                                  location: "https://maps.app.goo.gl/palace",
                                  note: "韓服要先預約 https://hanbok.example.com 電話 02-1234-5678", createdAt: 1_790_000_000_001, uuid: "plan-palace")
            try palace.insert(db)
            var market = PlanItem(tripId: trip, title: "廣藏市場", categoryId: cat("吃"), date: 20750, createdAt: 1_790_000_000_002, uuid: "plan-market")
            try market.insert(db)
            var oy = PlanItem(tripId: trip, title: "Olive Young", categoryId: cat("購物"), createdAt: 1_790_000_000_003, uuid: "plan-oy")
            try oy.insert(db)
            var pic = PlanPhoto(planItemId: palace.id!, path: menu, width: 64, height: 48, createdAt: 1_790_000_000_004)
            try pic.insert(db)
            try Q.setDayNote(db, tripId: trip, day: 20749, text: "早點出門")
            try Q.setDayNote(db, tripId: trip, day: unscheduledDay, text: "有空再去")
            // Day notes carry the time they were written; use the fixture's so the files compare equal.
            try db.execute(sql: "UPDATE day_note SET updatedAt = 1791628768459 WHERE day = 20749")
            try db.execute(sql: "UPDATE day_note SET updatedAt = 1791628768462 WHERE day = ?", arguments: [unscheduledDay])
            let members = try Q.members(db, trip)
            var metro = Expense(tripId: trip, date: 20748, amount: 1200, currency: "TWD", rate: 1, homeAmount: 1200,
                                categoryId: cat("交通"), paymentMethodId: pays.first { $0.name == "信用卡" }!.id, payerId: members[0].id,
                                createdAt: 1_790_000_000_005, title: "機場捷運", minuteOfDay: 15 * 60 + 30, uuid: "exp-metro")
            try metro.insert(db)
            var pancake = Expense(tripId: trip, date: 20750, amount: 12000, currency: "KRW", rate: 0.024, homeAmount: 288,
                                  categoryId: cat("吃"), paymentMethodId: pays.first { $0.name == "現金" }!.id, payerId: members[1].id,
                                  note: "很好吃", createdAt: 1_790_000_000_006, title: "綠豆煎餅", planItemId: market.id, uuid: "exp-pancake")
            try pancake.insert(db)
            var photo = Photo(expenseId: pancake.id!, type: PhotoType.receipt, path: receipt, width: 64, height: 48, createdAt: 1_790_000_000_007)
            try photo.insert(db)
            return trip
        }
    }

    private func readZipJSON(_ url: URL, _ name: String) throws -> JSONObject {
        let zip = try Archive(url: url, accessMode: .read)
        var d = Data()
        _ = try zip.extract(XCTUnwrap(zip[name])) { d.append($0) }
        return try XCTUnwrap(try JSON.parse(d).objectValue)
    }

    private func entryNames(_ url: URL) throws -> [String] {
        try Archive(url: url, accessMode: .read).map(\.path).sorted()
    }

    /// For comparing two files: numbers by value, photo files by folder and sequence number only.
    private func normalized(_ v: JSON, key: String? = nil) -> JSON {
        switch v {
        case .number(let n): return .number(Decimal(string: n).map { "\($0)" } ?? n)
        case .string(let s) where key == "file" || key == "cover":
            // files/plans/0-menu.jpg and files/plans/0-<uuid>.jpg are the same picture
            return .string(s.components(separatedBy: "-").first ?? s)
        case .array(let a): return .array(a.map { normalized($0) })
        case .object(let o):
            var out = JSONObject()
            for k in o.keys.sorted() { out[k] = normalized(o[k]!, key: k) }
            return .object(out)
        default: return v
        }
    }

    private var fromIOS: URL? {
        ProcessInfo.processInfo.environment["WRITE_FROM_IOS"] == "1" ? repoRoot.appendingPathComponent("compat/from-ios") : nil
    }

    private func keep(_ url: URL, as name: String) throws {
        guard let dir = fromIOS else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
    }

    // MARK: kind = trip

    func testSharedTripFileMatchesAndroids() throws {
        let organizer = try Phone()
        let trip = try seoul(organizer)
        let out = organizer.tmp("卡溜趴-首爾賞楓.zip")
        try FileManager.default.createDirectory(at: organizer.dir, withIntermediateDirectories: true)
        let n = try organizer.archive.export(to: out, kind: TripArchive.kindTrip, tripIds: [trip], includePhotos: true,
                                             sharedBy: "小明", appVersion: "0.10.0", now: 1_790_000_100_000)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(try entryNames(out).filter { $0.hasPrefix("files/") }.map { $0.components(separatedBy: "-").first! },
                       ["files/plans/0", "files/receipts/1"])

        let mine = try readZipJSON(out, "data.json"), android = try readZipJSON(fixture("trip.zip"), "data.json")
        XCTAssertEqual(normalized(.object(mine)), normalized(.object(android)))
        let myManifest = try readZipJSON(out, "manifest.json"), androidManifest = try readZipJSON(fixture("trip.zip"), "manifest.json")
        XCTAssertEqual(normalized(.object(myManifest)), normalized(.object(androidManifest)))
        // The 待排 note's day is written as the exact 64-bit integer.
        XCTAssertTrue(String(decoding: try JSON.object(mine).data(), as: UTF8.self).contains("\"day\":-9223372036854775808"))

        // A companion phone opens it like Android's file.
        let companion = try Phone()
        let copy = try companion.importOK(out)
        XCTAssertEqual(copy.kind, "trip")
        XCTAssertEqual(try companion.trip("trip-seoul").sharedBy, "小明")
        try keep(out, as: "ios-trip.zip")
    }

    // MARK: kind = additions

    func testAdditionsFileForTheOrganizer() throws {
        // The companion opens the organizer's share, adds a plan and an expense, and sends them back.
        let organizer = try Phone()
        let share = organizer.tmp("share.zip")
        try FileManager.default.createDirectory(at: organizer.dir, withIntermediateDirectories: true)
        try organizer.archive.export(to: share, kind: TripArchive.kindTrip, tripIds: [try seoul(organizer)], includePhotos: true,
                                     sharedBy: "小明", now: 1_790_000_100_000)
        let companion = try Phone()
        let copy = try companion.importOK(share).ids[0]
        try companion.db.write { db in
            let cats = try Q.categories(db)
            let market = try XCTUnwrap(try Q.planByUuid(db, tripId: copy, uuid: "plan-market"))
            var p = PlanItem(tripId: copy, title: "明洞餃子", categoryId: cats.first { $0.name == "吃" }?.id, date: 20751, minuteOfDay: 12 * 60,
                             createdAt: 1_790_000_200_000, uuid: "plan-add-dumpling", pending: true)
            try p.insert(db)
            var e = Expense(tripId: copy, date: 20750, amount: 5000, currency: "KRW", rate: 0.024, homeAmount: 120,
                            categoryId: cats.first { $0.name == "吃" }?.id, createdAt: 1_790_000_200_001, title: "麻藥飯捲",
                            planItemId: market.id, uuid: "exp-add-gimbap", pending: true)
            try e.insert(db)
        }
        XCTAssertEqual(try companion.archive.pendingCount(copy), 2)
        let out = companion.tmp("卡溜趴補充-首爾賞楓-小美.zip")
        XCTAssertEqual(try companion.archive.exportAdditions(to: out, tripId: copy, from: "小美", includePhotos: false,
                                                             appVersion: "0.10.0", now: 1_790_000_300_000), 2)

        let mine = try readZipJSON(out, "data.json"), android = try readZipJSON(fixture("additions.zip"), "data.json")
        XCTAssertEqual(normalized(.object(mine)), normalized(.object(android)))
        let myManifest = try readZipJSON(out, "manifest.json"), androidManifest = try readZipJSON(fixture("additions.zip"), "manifest.json")
        XCTAssertEqual(normalized(.object(myManifest)), normalized(.object(androidManifest)))

        // The organizer (restored from Android's backup) takes both in.
        let back = try Phone()
        try back.importOK(fixture("backup.zip"))
        let items = Set(try TripArchive.readAdditions(out).items.map(\.uuid))
        XCTAssertEqual(back.archive.importAdditions(out, accepted: items),
                       .imported(kind: "additions", tripIds: [try back.trip("trip-seoul").id!], updated: 2))
        try keep(out, as: "ios-additions.zip")
    }

    // MARK: kind = backup

    func testBackupFileMatchesAndroids() throws {
        let organizer = try Phone()
        let trip = try seoul(organizer)
        let okinawa = try organizer.db.write { db -> Int64 in
            var t = Trip(name: "沖繩", startDate: 20800, endDate: 20803, uuid: "trip-okinawa", sharedBy: "阿姨", sharedAt: 1_790_000_000_000)
            t.createdAt = 1_791_628_768_578 // as in the fixture
            try t.insert(db)
            var a = PlanItem(tripId: t.id!, title: "美麗海水族館", date: 20801, createdAt: 1_790_000_400_000, uuid: "plan-aquarium")
            try a.insert(db)
            var k = PlanItem(tripId: t.id!, title: "古宇利島", createdAt: 1_790_000_400_001, uuid: "plan-kouri", pending: true)
            try k.insert(db)
            return t.id!
        }
        let out = organizer.tmp("卡溜趴備份-2026-10-10.zip")
        try FileManager.default.createDirectory(at: organizer.dir, withIntermediateDirectories: true)
        XCTAssertEqual(try organizer.archive.export(to: out, kind: TripArchive.kindBackup, tripIds: [trip, okinawa], includePhotos: true,
                                                    appVersion: "0.10.0", now: 1_790_000_500_000), 2)

        let mine = try readZipJSON(out, "data.json"), android = try readZipJSON(fixture("backup.zip"), "data.json")
        XCTAssertEqual(normalized(.object(mine)), normalized(.object(android)))
        let myManifest = try readZipJSON(out, "manifest.json"), androidManifest = try readZipJSON(fixture("backup.zip"), "manifest.json")
        XCTAssertEqual(normalized(.object(myManifest)), normalized(.object(androidManifest)))

        let fresh = try Phone()
        let r = try fresh.importOK(out)
        XCTAssertEqual(r.ids.count, 2)
        XCTAssertTrue(try fresh.plans(try fresh.trip("trip-okinawa").id!).first { $0.uuid == "plan-kouri" }!.pending)
        XCTAssertEqual(try fresh.trip("trip-okinawa").sharedBy, "阿姨")
        try keep(out, as: "ios-backup.zip")
    }

    // MARK: Round trip

    /// Compat test 3: import Android's trip.zip, write it again, import that on another phone: nothing changes.
    func testRoundTripKeepsEverything() throws {
        let first = try Phone()
        let id = try first.importOK(fixture("trip.zip")).ids[0]
        let out = first.tmp("again.zip")
        try first.archive.export(to: out, kind: TripArchive.kindTrip, tripIds: [id], includePhotos: true, sharedBy: "我", now: 1_800_000_000_000)

        // The copy keeps the original sender and time.
        let manifestTrip = try readZipJSON(out, "data.json").objects("trips")![0]
        XCTAssertEqual(manifestTrip.string("sharedBy"), "小明")
        XCTAssertEqual(manifestTrip.int64("sharedAt"), 1_790_000_100_000)

        let mine = try readZipJSON(out, "data.json"), android = try readZipJSON(fixture("trip.zip"), "data.json")
        XCTAssertEqual(normalized(.object(mine)), normalized(.object(android)))

        let second = try Phone()
        let id2 = try second.importOK(out).ids[0]
        func snapshot(_ p: Phone, _ id: Int64) throws -> String {
            let t = try XCTUnwrap(try p.db.read { try Q.trip($0, id) })
            let plans = try p.plans(id).map { "\($0.uuid)|\($0.title)|\(try p.category($0.categoryId) ?? "")|\(String(describing: $0.date))|\(String(describing: $0.minuteOfDay))|\($0.status)|\($0.reservation)|\($0.reservationNote)|\($0.location)|\($0.note)|\($0.createdAt)|\(try p.planPhotos($0.id!).count)" }
            let ex = try p.expenses(id).map { "\($0.uuid)|\($0.title)|\($0.amount)|\($0.currency)|\($0.rate)|\($0.homeAmount)|\(try p.category($0.categoryId) ?? "")|\(try p.payment($0.paymentMethodId) ?? "")|\($0.note)|\($0.createdAt)|\(try p.photos($0.id!).map(\.type))" }
            let notes = try p.db.read { try Q.dayNotes($0, id) }.sorted { $0.day < $1.day }.map { "\($0.day)=\($0.text)" }
            return ["\(t.name)|\(t.startDate)|\(t.endDate)|\(String(describing: t.budget))|\(t.splitEnabled)|\(String(describing: t.navApp))|\(String(describing: t.sharedBy))|\(String(describing: t.sharedAt))",
                    try p.members(id).map(\.name).joined(separator: ","), plans.joined(separator: "\n"), ex.joined(separator: "\n"), notes.joined(separator: "\n")]
                .joined(separator: "\n--\n")
        }
        XCTAssertEqual(try snapshot(first, id), try snapshot(second, id2))
    }
}
