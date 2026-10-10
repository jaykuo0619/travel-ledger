import Foundation
import XCTest
@testable import LedgerCore

/// The repository root (…/travel-ledger), found from this file's location.
let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

func fixture(_ name: String) -> URL { repoRoot.appendingPathComponent("compat/fixtures/\(name)") }

/// A fresh phone: empty database in memory and an empty photo folder.
final class Phone {
    let db: LedgerDatabase
    let files: FileStore
    let archive: TripArchive
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("phone-\(UUID().uuidString)")
        db = try LedgerDatabase()
        files = FileStore(root: dir.appendingPathComponent("files"))
        archive = TripArchive(database: db, files: files)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    func tmp(_ name: String) -> URL { dir.appendingPathComponent(name) }

    func trip(_ uuid: String) throws -> Trip { try XCTUnwrap(try db.read { try Q.tripByUuid($0, uuid) }) }
    func plans(_ tripId: Int64) throws -> [PlanItem] { try db.read { try Q.plans($0, tripId) } }
    func expenses(_ tripId: Int64) throws -> [Expense] { try db.read { try Q.expenses($0, tripId) } }
    func category(_ id: Int64?) throws -> String? { try db.read { db in try Q.categories(db).first { $0.id == id }?.name } }
    func payment(_ id: Int64?) throws -> String? { try db.read { db in try Q.paymentMethods(db).first { $0.id == id }?.name } }
    func members(_ tripId: Int64) throws -> [Member] { try db.read { try Q.members($0, tripId) } }
    func dayNote(_ tripId: Int64, _ day: Int64) throws -> String? { try db.read { try Q.dayNote($0, tripId: tripId, day: day)?.text } }
    func planPhotos(_ planId: Int64) throws -> [PlanPhoto] { try db.read { try Q.planPhotos($0, planId: planId) } }
    func photos(_ expenseId: Int64) throws -> [Photo] { try db.read { try Q.photos($0, expenseId: expenseId) } }

    @discardableResult
    func importOK(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws -> (kind: String, ids: [Int64], updated: Int) {
        let r = archive.importFile(url)
        guard case let .imported(kind, ids, updated) = r else { XCTFail("\(r)", file: file, line: line); throw XCTSkip() }
        return (kind, ids, updated)
    }
}
