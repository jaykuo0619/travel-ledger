import XCTest
@testable import LedgerCore

/// The two "wrong file" recoveries (backup/SharingMixupsTest.kt, PlansImportDialogTest.kt).
final class SharingMixupsTests: XCTestCase {
    /// A desktop plans file reaches a phone that doesn't have the trip: it is mine, or someone else's.
    func testPlansFileOnAPhoneWithoutTheTrip() throws {
        let mine = try Phone()
        guard case .imported = mine.archive.importPlans(fixture("plans.zip")) else { return XCTFail() }
        XCTAssertFalse(try mine.trip("trip-seoul").readOnly)

        let companion = try Phone()
        guard case .imported = companion.archive.importPlans(fixture("plans.zip"), organizer: "  小明 ") else { return XCTFail() }
        let trip = try companion.trip("trip-seoul")
        XCTAssertTrue(trip.readOnly)
        XCTAssertEqual("小明", trip.sharedBy)
        XCTAssertNotNil(trip.sharedAt)
        XCTAssertFalse(try companion.plans(try XCTUnwrap(trip.id)).contains { $0.pending }) // the organizer's plans, not my additions

        // A blank name means it is mine after all.
        let blank = try Phone()
        _ = blank.archive.importPlans(fixture("plans.zip"), organizer: "   ")
        XCTAssertFalse(try blank.trip("trip-seoul").readOnly)
    }

    /// The organizer gets a kind=trip file of their own trip back from a companion who added things to their copy.
    func testOrganizerReceivesTheirOwnTripBack() throws {
        let organizer = try Phone()
        try organizer.importOK(fixture("backup.zip"))
        let tripId = try XCTUnwrap(try organizer.trip("trip-seoul").id)

        // Not a trip file, or not my trip: the ordinary import goes on.
        XCTAssertNil(try organizer.archive.readNewItems(fixture("backup.zip")))
        XCTAssertNil(try Phone().archive.readNewItems(fixture("trip.zip")))
        // The same content: nothing new.
        XCTAssertEqual([], try XCTUnwrap(try organizer.archive.readNewItems(fixture("trip.zip"))).items)

        // The companion's phone holds its own (not read-only) copy with two more items, and shares it back.
        let companion = try Phone()
        try companion.importOK(fixture("backup.zip"))
        let theirs = try XCTUnwrap(try companion.trip("trip-seoul").id)
        let market = try XCTUnwrap(try companion.plans(theirs).first { $0.uuid == "plan-market" })
        try companion.db.write { db in
            _ = try Q.savePlan(db, PlanItem(tripId: theirs, title: "南山塔", date: 20751, uuid: "plan-tower"), pictures: [])
            _ = try Q.saveExpense(db, Expense(tripId: theirs, date: 20750, amount: 5000, currency: "KRW", rate: 0.024, homeAmount: 120,
                                             payerId: try Q.members(db, theirs).last?.id, title: "麻藥飯捲", planItemId: market.id, uuid: "exp-gimbap"), photos: [])
        }
        let file = companion.tmp("back.zip")
        try companion.archive.export(to: file, kind: TripArchive.kindTrip, tripIds: [theirs], includePhotos: false, sharedBy: "小美")

        let found = try XCTUnwrap(try organizer.archive.readNewItems(file))
        XCTAssertEqual("小美", found.from)
        XCTAssertEqual(["plan-tower", "exp-gimbap"], found.items.map(\.uuid)) // plans first
        XCTAssertEqual("首爾賞楓", found.tripName)

        let before = try organizer.expenses(tripId).count
        guard case let .imported(_, ids, updated) = organizer.archive.importNewItems(file, accepted: ["plan-tower", "exp-gimbap"]) else { return XCTFail() }
        XCTAssertEqual([tripId], ids)
        XCTAssertEqual(2, updated)
        let added = try XCTUnwrap(try organizer.expenses(tripId).first { $0.uuid == "exp-gimbap" })
        XCTAssertEqual(before + 1, try organizer.expenses(tripId).count)
        XCTAssertEqual("小美", added.addedBy)
        XCTAssertNil(added.payerId) // the payer index is dropped
        XCTAssertFalse(added.pending)
        XCTAssertEqual(try organizer.plans(tripId).first { $0.uuid == "plan-market" }?.id, added.planItemId) // linked by uuid
        XCTAssertFalse(try organizer.trip("trip-seoul").readOnly) // still mine

        // Opening it again: nothing new, nothing doubled.
        XCTAssertEqual([], try XCTUnwrap(try organizer.archive.readNewItems(file)).items)
        guard case let .imported(_, _, again) = organizer.archive.importNewItems(file, accepted: ["plan-tower", "exp-gimbap"]) else { return XCTFail() }
        XCTAssertEqual(0, again)
    }

    /// Only what was ticked is added.
    func testOnlyAcceptedItemsAreAdded() throws {
        let organizer = try Phone()
        try organizer.importOK(fixture("backup.zip"))
        let companion = try Phone()
        try companion.importOK(fixture("backup.zip"))
        let theirs = try XCTUnwrap(try companion.trip("trip-seoul").id)
        try companion.db.write { db in
            _ = try Q.savePlan(db, PlanItem(tripId: theirs, title: "A", uuid: "plan-a"), pictures: [])
            _ = try Q.savePlan(db, PlanItem(tripId: theirs, title: "B", uuid: "plan-b"), pictures: [])
        }
        let file = companion.tmp("back.zip")
        try companion.archive.export(to: file, kind: TripArchive.kindTrip, tripIds: [theirs], includePhotos: false, sharedBy: "小美")
        _ = organizer.archive.importNewItems(file, accepted: ["plan-b"])
        let uuids = try organizer.plans(try XCTUnwrap(try organizer.trip("trip-seoul").id)).map(\.uuid)
        XCTAssertTrue(uuids.contains("plan-b"))
        XCTAssertFalse(uuids.contains("plan-a"))
    }
}
