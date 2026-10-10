import Foundation
@_exported import GRDB

/// The app's SQLite database (same tables as Android's Room database) and the queries the screens use.
public final class LedgerDatabase: @unchecked Sendable {
    public let queue: DatabaseQueue

    /// [path] nil = in memory (tests).
    public init(path: String? = nil) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        queue = try path.map { try DatabaseQueue(path: $0, configuration: config) } ?? DatabaseQueue(configuration: config)
        try Self.migrator.migrate(queue)
    }

    public static let defaultCategories = ["吃", "交通", "購物", "住宿", "景點", "其他"]
    public static let defaultPayments = ["現金", "信用卡", "行動支付"]

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE trip (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL, startDate INTEGER NOT NULL, endDate INTEGER NOT NULL,
                    homeCurrency TEXT NOT NULL DEFAULT 'TWD', budget REAL, splitEnabled INTEGER NOT NULL DEFAULT 0,
                    createdAt INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
                    coverPath TEXT, coverTheme TEXT, uuid TEXT NOT NULL DEFAULT '',
                    sharedBy TEXT, sharedAt INTEGER, navApp TEXT);
                CREATE INDEX trip_uuid ON trip(uuid);
                CREATE TABLE trip_currency_rate (
                    tripId INTEGER NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
                    currency TEXT NOT NULL, rate REAL NOT NULL, updatedAt INTEGER NOT NULL, source TEXT NOT NULL,
                    PRIMARY KEY (tripId, currency));
                CREATE TABLE member (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    tripId INTEGER NOT NULL REFERENCES trip(id) ON DELETE CASCADE, name TEXT NOT NULL);
                CREATE INDEX member_tripId ON member(tripId);
                CREATE TABLE category (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sortOrder INTEGER NOT NULL,
                    icon TEXT NOT NULL DEFAULT '', color INTEGER NOT NULL DEFAULT -1);
                CREATE TABLE payment_method (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sortOrder INTEGER NOT NULL);
                CREATE TABLE expense (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    tripId INTEGER NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
                    date INTEGER NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, rate REAL NOT NULL,
                    homeAmount REAL NOT NULL, categoryId INTEGER, paymentMethodId INTEGER, payerId INTEGER,
                    note TEXT NOT NULL DEFAULT '', createdAt INTEGER NOT NULL, title TEXT NOT NULL DEFAULT '',
                    minuteOfDay INTEGER, ocrText TEXT NOT NULL DEFAULT '', planItemId INTEGER,
                    uuid TEXT NOT NULL DEFAULT '', addedBy TEXT, pending INTEGER NOT NULL DEFAULT 0);
                CREATE INDEX expense_tripId ON expense(tripId);
                CREATE TABLE photo (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    expenseId INTEGER NOT NULL REFERENCES expense(id) ON DELETE CASCADE,
                    type TEXT NOT NULL, path TEXT NOT NULL, width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0,
                    createdAt INTEGER NOT NULL, savedToGallery INTEGER NOT NULL DEFAULT 0);
                CREATE INDEX photo_expenseId ON photo(expenseId);
                CREATE TABLE plan_item (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    tripId INTEGER NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
                    title TEXT NOT NULL, categoryId INTEGER, date INTEGER, minuteOfDay INTEGER,
                    status TEXT NOT NULL, reservation TEXT NOT NULL, reservationNote TEXT NOT NULL DEFAULT '',
                    location TEXT NOT NULL DEFAULT '', estCost REAL, note TEXT NOT NULL DEFAULT '', createdAt INTEGER NOT NULL,
                    uuid TEXT NOT NULL DEFAULT '', addedBy TEXT, pending INTEGER NOT NULL DEFAULT 0);
                CREATE INDEX plan_item_tripId ON plan_item(tripId);
                CREATE TABLE day_note (
                    tripId INTEGER NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
                    day INTEGER NOT NULL, text TEXT NOT NULL, updatedAt INTEGER NOT NULL,
                    PRIMARY KEY (tripId, day));
                CREATE TABLE plan_photo (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    planItemId INTEGER NOT NULL REFERENCES plan_item(id) ON DELETE CASCADE,
                    path TEXT NOT NULL, width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL);
                CREATE INDEX plan_photo_planItemId ON plan_photo(planItemId);
                """)
            for (i, n) in defaultCategories.enumerated() {
                var c = Category(name: n, sortOrder: i)
                try c.insert(db)
            }
            for (i, n) in defaultPayments.enumerated() {
                var p = PaymentMethod(name: n, sortOrder: i)
                try p.insert(db)
            }
        }
        return m
    }

    public func read<T>(_ block: (Database) throws -> T) throws -> T { try queue.read(block) }
    public func write<T>(_ block: (Database) throws -> T) throws -> T { try queue.write(block) }
}

// MARK: - Queries (Database-level, so they compose inside one transaction)

public enum Q {
    // Trips

    public static func tripSummaries(_ db: Database) throws -> [TripSummary] {
        try TripSummary.fetchAll(db, sql: """
            SELECT t.id, t.name, t.startDate, t.endDate, t.budget, t.coverPath, t.coverTheme, t.sharedBy,
                   COALESCE((SELECT SUM(homeAmount) FROM expense WHERE tripId = t.id), 0) AS totalHome,
                   (SELECT COUNT(*) FROM member WHERE tripId = t.id) AS memberCount,
                   (SELECT GROUP_CONCAT(currency) FROM
                       (SELECT DISTINCT currency FROM expense WHERE tripId = t.id AND currency != 'TWD'
                        UNION SELECT currency FROM trip_currency_rate WHERE tripId = t.id)) AS currencies
            FROM trip t WHERE t.archived = 0 ORDER BY t.startDate DESC
            """)
    }

    public static func trips(_ db: Database) throws -> [Trip] {
        try Trip.fetchAll(db, sql: "SELECT * FROM trip WHERE archived = 0 ORDER BY startDate DESC")
    }

    public static func trip(_ db: Database, _ id: Int64) throws -> Trip? { try Trip.fetchOne(db, key: id) }

    public static func tripByUuid(_ db: Database, _ uuid: String) throws -> Trip? {
        try Trip.fetchOne(db, sql: "SELECT * FROM trip WHERE uuid = ? LIMIT 1", arguments: [uuid])
    }

    /// Every trip, archived or not, for a full backup.
    public static func allTripIds(_ db: Database) throws -> [Int64] {
        try Int64.fetchAll(db, sql: "SELECT id FROM trip ORDER BY startDate")
    }

    public static func members(_ db: Database, _ tripId: Int64) throws -> [Member] {
        try Member.fetchAll(db, sql: "SELECT * FROM member WHERE tripId = ? ORDER BY id", arguments: [tripId])
    }

    public static func rates(_ db: Database, _ tripId: Int64) throws -> [TripCurrencyRate] {
        try TripCurrencyRate.fetchAll(db, sql: "SELECT * FROM trip_currency_rate WHERE tripId = ? ORDER BY currency", arguments: [tripId])
    }

    public static func upsertRate(_ db: Database, _ r: TripCurrencyRate) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO trip_currency_rate (tripId, currency, rate, updatedAt, source) VALUES (?, ?, ?, ?, ?)",
            arguments: [r.tripId, r.currency, r.rate, r.updatedAt, r.source])
    }

    /// Creates a trip with its members and default rates; returns its id.
    @discardableResult
    public static func createTrip(_ db: Database, _ trip: Trip, members: [String], rates: [TripCurrencyRate]) throws -> Int64 {
        var t = trip
        t.id = nil
        try t.insert(db)
        let id = t.id!
        for n in members { var m = Member(tripId: id, name: n); try m.insert(db) }
        for r in rates { var r = r; r.tripId = id; try upsertRate(db, r) }
        return id
    }

    /// Keeps members whose name stays so expense references stay valid; a renamed member is removed and added.
    public static func updateTrip(_ db: Database, _ trip: Trip, members: [String], rates: [TripCurrencyRate]) throws {
        guard let id = trip.id else { return }
        try trip.update(db)
        let existing = try Self.members(db, id)
        for m in existing where !members.contains(m.name) { try db.execute(sql: "DELETE FROM member WHERE id = ?", arguments: [m.id]) }
        let kept = Set(existing.map(\.name))
        for n in members where !kept.contains(n) { var m = Member(tripId: id, name: n); try m.insert(db) }
        try db.execute(sql: "DELETE FROM trip_currency_rate WHERE tripId = ?", arguments: [id])
        for r in rates { var r = r; r.tripId = id; try upsertRate(db, r) }
    }

    /// Deletes a trip and returns the picture files it used (cover, photos, plan pictures) for the caller to remove.
    @discardableResult
    public static func deleteTrip(_ db: Database, _ id: Int64) throws -> [String] {
        var files = try photoPaths(db, tripId: id, officialOnly: false) + planPhotoPaths(db, tripId: id, officialOnly: false)
        if let cover = try String?.fetchOne(db, sql: "SELECT coverPath FROM trip WHERE id = ?", arguments: [id]) ?? nil { files.append(cover) }
        try db.execute(sql: "DELETE FROM trip WHERE id = ?", arguments: [id])
        return files
    }

    /// Empties a trip completely, for restoring a backup over it.
    public static func clearAll(_ db: Database, _ tripId: Int64) throws {
        for table in ["day_note", "expense", "plan_item", "member", "trip_currency_rate"] {
            try db.execute(sql: "DELETE FROM \(table) WHERE tripId = ?", arguments: [tripId])
        }
    }

    /// Empties a shared copy so an update can refill it; my pending additions stay.
    public static func clearContents(_ db: Database, _ tripId: Int64) throws {
        try db.execute(sql: "DELETE FROM day_note WHERE tripId = ?", arguments: [tripId])
        try db.execute(sql: "DELETE FROM expense WHERE tripId = ? AND pending = 0", arguments: [tripId])
        try db.execute(sql: "DELETE FROM plan_item WHERE tripId = ? AND pending = 0", arguments: [tripId])
        try db.execute(sql: "DELETE FROM member WHERE tripId = ?", arguments: [tripId])
        try db.execute(sql: "DELETE FROM trip_currency_rate WHERE tripId = ?", arguments: [tripId])
    }

    // Lookups

    public static func categories(_ db: Database) throws -> [Category] {
        try Category.fetchAll(db, sql: "SELECT * FROM category ORDER BY sortOrder, id")
    }

    public static func paymentMethods(_ db: Database) throws -> [PaymentMethod] {
        try PaymentMethod.fetchAll(db, sql: "SELECT * FROM payment_method ORDER BY sortOrder, id")
    }

    // Expenses

    public static func expenseRows(_ db: Database, _ tripId: Int64) throws -> [ExpenseRow] {
        try ExpenseRow.fetchAll(db, sql: """
            SELECT e.id, e.date, e.minuteOfDay, e.title, e.amount, e.currency, e.rate, e.homeAmount,
                   e.categoryId, c.name AS categoryName, c.icon AS categoryIcon, c.color AS categoryColor,
                   p.name AS paymentMethodName, e.note,
                   (SELECT path FROM photo WHERE expenseId = e.id ORDER BY id LIMIT 1) AS thumbPath, e.planItemId,
                   e.addedBy, e.pending
            FROM expense e
            LEFT JOIN category c ON c.id = e.categoryId
            LEFT JOIN payment_method p ON p.id = e.paymentMethodId
            WHERE e.tripId = ?
            ORDER BY e.date DESC, COALESCE(e.minuteOfDay, -1) DESC, e.id DESC
            """, arguments: [tripId])
    }

    public static func expenses(_ db: Database, _ tripId: Int64) throws -> [Expense] {
        try Expense.fetchAll(db, sql: "SELECT * FROM expense WHERE tripId = ? ORDER BY id", arguments: [tripId])
    }

    public static func expense(_ db: Database, _ id: Int64) throws -> Expense? { try Expense.fetchOne(db, key: id) }

    public static func photos(_ db: Database, expenseId: Int64) throws -> [Photo] {
        try Photo.fetchAll(db, sql: "SELECT * FROM photo WHERE expenseId = ? ORDER BY id", arguments: [expenseId])
    }

    public static func photoPaths(_ db: Database, tripId: Int64, officialOnly: Bool) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT path FROM photo WHERE expenseId IN (SELECT id FROM expense WHERE tripId = ?\(officialOnly ? " AND pending = 0" : ""))
            """, arguments: [tripId])
    }

    // Plans

    /// Undated last, then date, untimed last, time, id.
    public static func planRows(_ db: Database, _ tripId: Int64) throws -> [PlanRow] {
        try PlanRow.fetchAll(db, sql: """
            SELECT pl.id, pl.title, pl.categoryId, c.name AS categoryName, c.icon AS categoryIcon, c.color AS categoryColor,
                   pl.date, pl.minuteOfDay, pl.status, pl.reservation, pl.reservationNote, pl.location, pl.estCost,
                   COALESCE((SELECT SUM(homeAmount) FROM expense WHERE planItemId = pl.id), 0) AS spent,
                   pl.addedBy, pl.pending, (SELECT COUNT(*) FROM plan_photo WHERE planItemId = pl.id) AS photoCount
            FROM plan_item pl LEFT JOIN category c ON c.id = pl.categoryId
            WHERE pl.tripId = ?
            ORDER BY pl.date IS NULL, pl.date, pl.minuteOfDay IS NULL, pl.minuteOfDay, pl.id
            """, arguments: [tripId])
    }

    public static func plans(_ db: Database, _ tripId: Int64) throws -> [PlanItem] {
        try PlanItem.fetchAll(db, sql: "SELECT * FROM plan_item WHERE tripId = ? ORDER BY id", arguments: [tripId])
    }

    public static func plan(_ db: Database, _ id: Int64) throws -> PlanItem? { try PlanItem.fetchOne(db, key: id) }

    public static func planByUuid(_ db: Database, tripId: Int64, uuid: String) throws -> PlanItem? {
        try PlanItem.fetchOne(db, sql: "SELECT * FROM plan_item WHERE tripId = ? AND uuid = ? LIMIT 1", arguments: [tripId, uuid])
    }

    /// Deletes a plan item; expenses recorded for it stay but lose the link.
    public static func deletePlan(_ db: Database, _ id: Int64) throws {
        try db.execute(sql: "UPDATE expense SET planItemId = NULL WHERE planItemId = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM plan_item WHERE id = ?", arguments: [id])
    }

    /// Saves a plan item with its pictures as edited: [pictures] is the whole set, saved ones carry their id.
    /// Returns the item's id and the files of pictures that were removed (to delete from disk).
    public static func savePlan(_ db: Database, _ plan: PlanItem, pictures: [PlanPhoto]) throws -> (id: Int64, removed: [String]) {
        var p = plan
        if p.id == nil { try p.insert(db) } else { try p.update(db) }
        let id = p.id ?? 0
        let kept = Set(pictures.compactMap(\.id))
        let gone = try planPhotos(db, planId: id).filter { !kept.contains($0.id ?? -1) }
        for g in gone { try db.execute(sql: "DELETE FROM plan_photo WHERE id = ?", arguments: [g.id]) }
        for var n in pictures where n.id == nil {
            n.planItemId = id
            try n.insert(db)
        }
        return (id, gone.map(\.path))
    }

    /// Deletes a plan item and its pictures; returns the picture files to delete from disk.
    public static func deletePlanWithPhotos(_ db: Database, _ id: Int64) throws -> [String] {
        let paths = try planPhotos(db, planId: id).map(\.path)
        try db.execute(sql: "DELETE FROM plan_photo WHERE planItemId = ?", arguments: [id])
        try deletePlan(db, id)
        return paths
    }

    public static func setPlanStatus(_ db: Database, _ id: Int64, _ status: String) throws {
        try db.execute(sql: "UPDATE plan_item SET status = ? WHERE id = ?", arguments: [status, id])
    }

    public static func planPhotos(_ db: Database, planId: Int64) throws -> [PlanPhoto] {
        try PlanPhoto.fetchAll(db, sql: "SELECT * FROM plan_photo WHERE planItemId = ? ORDER BY id", arguments: [planId])
    }

    public static func planPhotoPaths(_ db: Database, tripId: Int64, officialOnly: Bool) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT path FROM plan_photo WHERE planItemId IN (SELECT id FROM plan_item WHERE tripId = ?\(officialOnly ? " AND pending = 0" : ""))
            """, arguments: [tripId])
    }

    public static func pendingCount(_ db: Database, _ tripId: Int64) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT (SELECT COUNT(*) FROM expense WHERE tripId = ?1 AND pending = 1) + (SELECT COUNT(*) FROM plan_item WHERE tripId = ?1 AND pending = 1)
            """, arguments: [tripId]) ?? 0
    }

    // Day notes

    public static func dayNotes(_ db: Database, _ tripId: Int64) throws -> [DayNote] {
        try DayNote.fetchAll(db, sql: "SELECT * FROM day_note WHERE tripId = ? ORDER BY day", arguments: [tripId])
    }

    public static func dayNote(_ db: Database, tripId: Int64, day: Int64) throws -> DayNote? {
        try DayNote.fetchOne(db, sql: "SELECT * FROM day_note WHERE tripId = ? AND day = ?", arguments: [tripId, day])
    }

    /// Writes the text exactly as given (imports keep notes untouched).
    public static func putDayNote(_ db: Database, _ note: DayNote) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO day_note (tripId, day, text, updatedAt) VALUES (?, ?, ?, ?)",
                       arguments: [note.tripId, note.day, note.text, note.updatedAt])
    }

    /// Saves the trimmed note, or removes it when blank (the editor and desktop plans use this).
    public static func setDayNote(_ db: Database, tripId: Int64, day: Int64, text: String) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            try db.execute(sql: "DELETE FROM day_note WHERE tripId = ? AND day = ?", arguments: [tripId, day])
        } else {
            try putDayNote(db, DayNote(tripId: tripId, day: day, text: t))
        }
    }
}
