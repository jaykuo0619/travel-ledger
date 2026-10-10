import Foundation
import GRDB

public let maxAmountIntDigits = 9
public let maxAmountDecimals = 2
public let maxExpensePhotos = 3

/// Pure reducer for the amount keypad: digits, "00", ".", "⌫" and "C" (clear) — ui/Keypad.kt applyKey.
public func applyKey(_ current: String, _ key: String) -> String {
    switch key {
    case "C": return ""
    case "⌫": return String(current.dropLast())
    case ".":
        if current.contains(".") { return current }
        return current.isEmpty ? "0." : current + "."
    case "00":
        return current.isEmpty || current == "0" ? current : applyKey(applyKey(current, "0"), "0")
    default:
        if let dot = current.firstIndex(of: ".") {
            if current.distance(from: dot, to: current.endIndex) - 1 >= maxAmountDecimals { return current }
        } else if current.count >= maxAmountIntDigits {
            return current
        }
        return current == "0" ? key : current + key
    }
}

/// The amount as typed, with thousands separators in the whole part ("1234.5" → "1,234.5", "0." stays "0.").
public func fmtTyped(_ typed: String) -> String {
    guard !typed.isEmpty else { return "" }
    let parts = typed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = String(parts[0])
    var out = ""
    for (i, ch) in whole.enumerated() {
        if i > 0, (whole.count - i) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return parts.count > 1 ? out + "." + parts[1] : out
}

/// A title used before and the category it was last filed under.
public struct TitleSuggestion: Equatable, Sendable {
    public let title: String
    public let categoryId: Int64?
}

/// Up to 8 remembered titles containing what was typed (case-insensitive), never the text itself.
public func matchSuggestions(_ all: [TitleSuggestion], typed: String) -> [TitleSuggestion] {
    let q = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return Array(all.filter { s in
        let t = s.title.lowercased()
        return t != q && (q.isEmpty || t.contains(q))
    }.prefix(8))
}

/// What a new expense starts with (ExpenseEditViewModel).
public struct ExpenseDefaults: Equatable, Sendable {
    public var title = ""
    public var currency = homeCurrency
    /// As text for the rate field; "" = not known yet (「請設定匯率」).
    public var rate = "1"
    public var categoryId: Int64?
    public var paymentId: Int64?
    public var currencies: [String] = [homeCurrency]
}

public extension Q {
    static func latestExpense(_ db: Database, _ tripId: Int64) throws -> Expense? {
        try Expense.fetchOne(db, sql: "SELECT * FROM expense WHERE tripId = ? ORDER BY createdAt DESC LIMIT 1", arguments: [tripId])
    }

    /// Titles used in any trip, most recent first (SQLite returns the other columns from the MAX(createdAt) row).
    static func titleSuggestions(_ db: Database) throws -> [TitleSuggestion] {
        try Row.fetchAll(db, sql: """
            SELECT title, categoryId, MAX(createdAt) AS lastUsed FROM expense
            WHERE title != '' GROUP BY title ORDER BY lastUsed DESC LIMIT 300
            """).map { TitleSuggestion(title: $0["title"], categoryId: $0["categoryId"]) }
    }

    /// The rate to prefill for [currency]: 1 for TWD, the trip's rate, the last expense's if it used the same
    /// currency, otherwise unknown.
    static func rateText(_ currency: String, tripRates: [String: Double], last: Expense?) -> String {
        if currency == homeCurrency { return "1" }
        if let r = tripRates[currency] { return fmtNumber(r) }
        if let last, last.currency == currency { return fmtNumber(last.rate) }
        return ""
    }

    static func expenseDefaults(_ db: Database, tripId: Int64, planId: Int64?) throws -> ExpenseDefaults {
        let rates = Dictionary(try Q.rates(db, tripId).map { ($0.currency, $0.rate) }, uniquingKeysWith: { a, _ in a })
        let last = try latestExpense(db, tripId)
        let plan = try planId.flatMap { try Q.plan(db, $0) }
        var d = ExpenseDefaults()
        d.title = plan?.title ?? ""
        d.currency = last?.currency ?? rates.keys.sorted().first ?? homeCurrency
        d.rate = rateText(d.currency, tripRates: rates, last: last)
        d.categoryId = try plan?.categoryId ?? last?.categoryId ?? categories(db).first?.id
        d.paymentId = try last?.paymentMethodId ?? paymentMethods(db).first?.id
        var seen = Set<String>()
        d.currencies = ([homeCurrency] + rates.keys.sorted() + [d.currency]).filter { seen.insert($0).inserted }
        return d
    }

    /// Saves an expense with its photos as edited ([photos] is the whole set; saved ones carry their id).
    /// A new expense recorded for a plan item ticks it off, and the first use of a foreign currency becomes
    /// the trip's rate — neither on someone else's trip. Returns the id and the files of removed photos.
    static func saveExpense(_ db: Database, _ expense: Expense, photos: [Photo]) throws -> (id: Int64, removed: [String]) {
        var e = expense
        let isNew = e.id == nil
        let shared = try Q.trip(db, e.tripId)?.readOnly == true
        if isNew {
            e.pending = shared
            try e.insert(db)
            if let plan = e.planItemId, !shared { try setPlanStatus(db, plan, PlanStatus.done) }
        } else {
            try e.update(db)
        }
        let id = e.id ?? 0
        let kept = Set(photos.compactMap(\.id))
        let gone = try Q.photos(db, expenseId: id).filter { !kept.contains($0.id ?? -1) }
        for g in gone { try db.execute(sql: "DELETE FROM photo WHERE id = ?", arguments: [g.id]) }
        for var p in photos {
            p.expenseId = id
            if p.id == nil { try p.insert(db) } else { try p.update(db) }
        }
        if e.currency != homeCurrency, !shared, try !Q.rates(db, e.tripId).contains(where: { $0.currency == e.currency }) {
            try upsertRate(db, TripCurrencyRate(tripId: e.tripId, currency: e.currency, rate: e.rate))
        }
        return (id, gone.map(\.path))
    }

    /// Deletes an expense and its photo rows; returns the photo files to delete from disk.
    static func deleteExpense(_ db: Database, _ id: Int64) throws -> [String] {
        let paths = try Q.photos(db, expenseId: id).map(\.path)
        try db.execute(sql: "DELETE FROM photo WHERE expenseId = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM expense WHERE id = ?", arguments: [id])
        return paths
    }

    // Categories and payment methods (ui/ManageScreens.kt, LookupViewModel)

    static func addCategory(_ db: Database, name: String, icon: String, color: Int) throws {
        let order = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM category") ?? -1) + 1
        var c = Category(name: name, sortOrder: order, icon: icon, color: color)
        try c.insert(db)
    }

    static func updateCategory(_ db: Database, _ category: Category) throws { try category.update(db) }

    /// Expenses using the deleted category fall back to 「其他」 (or no category if that is the one deleted).
    /// Plan items too — on Android they were left pointing at nothing (IOS_PORT.md §12).
    static func deleteCategory(_ db: Database, _ id: Int64) throws {
        let other = try Int64.fetchOne(db, sql: "SELECT id FROM category WHERE name = '其他' LIMIT 1")
        let to: Int64? = other == id ? nil : other
        try db.execute(sql: "UPDATE expense SET categoryId = ? WHERE categoryId = ?", arguments: [to, id])
        try db.execute(sql: "UPDATE plan_item SET categoryId = ? WHERE categoryId = ?", arguments: [to, id])
        try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [id])
    }

    static func moveCategory(_ db: Database, from: Int, to: Int) throws {
        var list = try categories(db)
        guard list.indices.contains(from), list.indices.contains(to) else { return }
        list.insert(list.remove(at: from), at: to)
        for (i, var c) in list.enumerated() where c.sortOrder != i {
            c.sortOrder = i
            try c.update(db)
        }
    }

    static func addPaymentMethod(_ db: Database, name: String) throws {
        let order = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM payment_method") ?? -1) + 1
        var m = PaymentMethod(name: name, sortOrder: order)
        try m.insert(db)
    }

    static func updatePaymentMethod(_ db: Database, _ method: PaymentMethod) throws { try method.update(db) }

    /// Expenses that used it become 未指定.
    static func deletePaymentMethod(_ db: Database, _ id: Int64) throws {
        try db.execute(sql: "UPDATE expense SET paymentMethodId = NULL WHERE paymentMethodId = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM payment_method WHERE id = ?", arguments: [id])
    }

    static func movePaymentMethod(_ db: Database, from: Int, to: Int) throws {
        var list = try paymentMethods(db)
        guard list.indices.contains(from), list.indices.contains(to) else { return }
        list.insert(list.remove(at: from), at: to)
        for (i, var m) in list.enumerated() where m.sortOrder != i {
            m.sortOrder = i
            try m.update(db)
        }
    }
}
