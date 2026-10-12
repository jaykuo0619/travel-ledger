import Foundation
import GRDB

public let maxAmountIntDigits = 9
public let maxAmountDecimals = 2
public let maxExpensePhotos = 3

/// Calculator operators as shown on the keys.
public let keypadOperators = "+−×÷"

private func isOp(_ c: Character) -> Bool { keypadOperators.contains(c) }

/// The number being typed: everything after the last operator.
private func lastNumber(_ expr: String) -> String {
    guard let i = expr.lastIndex(where: isOp) else { return expr }
    return String(expr[expr.index(after: i)...])
}

/// Pure reducer for the calculator: digits, "00", ".", operators (+ − × ÷), "=", "⌫" and "C" (clear) — ui/Keypad.kt
/// applyKey. The text is the expression as typed, e.g. "1200+350×2"; a plain number is just a number.
public func applyKey(_ current: String, _ key: String) -> String {
    switch key {
    case "C": return ""
    case "⌫": return String(current.dropLast())
    case "=": return evaluate(current).map(fmtNumber) ?? current
    default:
        if key.count == 1, let op = key.first, isOp(op) {
            guard let last = current.last else { return current } // nothing to work on yet
            // Changed my mind about the operator, or it follows a bare ".".
            if isOp(last) || last == "." { return String(current.dropLast()) + key }
            return current + key
        }
        let number = lastNumber(current)
        return String(current.dropLast(number.count)) + typeDigit(number, key)
    }
}

/// Digits, "00" and "." within one number (at most 9 digits before the point and 2 after).
private func typeDigit(_ current: String, _ key: String) -> String {
    switch key {
    case ".":
        if current.contains(".") { return current }
        return current.isEmpty ? "0." : current + "."
    case "00":
        return current.isEmpty || current == "0" ? current : typeDigit(typeDigit(current, "0"), "0")
    default:
        if let dot = current.firstIndex(of: ".") {
            if current.distance(from: dot, to: current.endIndex) - 1 >= maxAmountDecimals { return current }
        } else if current.count >= maxAmountIntDigits {
            return current
        }
        return current == "0" ? key : current + key
    }
}

/// Whether [expr] has an operation in it (rather than being a single number).
public func isExpression(_ expr: String) -> Bool { expr.contains(where: isOp) }

/// The value of [expr], × and ÷ before + and −, rounded to 2 decimals; a trailing operator is ignored.
/// Nil when there is nothing to compute or it divides by zero.
public func evaluate(_ expr: String) -> Double? {
    var text = expr
    while let last = text.last, isOp(last) || last == "." { text.removeLast() }
    if text.isEmpty { return nil }
    var numbers: [Decimal] = []
    var ops: [Character] = []
    var piece = ""
    for c in text {
        if isOp(c) {
            guard let n = Decimal(string: piece, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            numbers.append(n)
            ops.append(c)
            piece = ""
        } else {
            piece.append(c)
        }
    }
    guard let tail = Decimal(string: piece, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
    numbers.append(tail)
    func rounded(_ v: Decimal, _ scale: Int) -> Decimal {
        var input = v, out = Decimal()
        NSDecimalRound(&out, &input, scale, .plain) // half away from zero, like HALF_UP
        return out
    }
    // × and ÷ first, left to right.
    var terms = [numbers[0]]
    var addOps: [Character] = []
    for (i, op) in ops.enumerated() {
        let n = numbers[i + 1]
        switch op {
        case "×": terms[terms.count - 1] *= n
        case "÷":
            if n.isZero { return nil }
            terms[terms.count - 1] = rounded(terms[terms.count - 1] / n, 10)
        default:
            addOps.append(op)
            terms.append(n)
        }
    }
    var total = terms[0]
    for (i, op) in addOps.enumerated() { total = op == "+" ? total + terms[i + 1] : total - terms[i + 1] }
    return Double(truncating: rounded(total, maxAmountDecimals) as NSDecimalNumber)
}

/// The expression for display, numbers grouped: "1,200 + 350 × 2".
public func fmtExpression(_ expr: String) -> String {
    var out = "", piece = ""
    for c in expr {
        if isOp(c) {
            out += fmtTyped(piece) + " \(c) "
            piece = ""
        } else {
            piece.append(c)
        }
    }
    out += fmtTyped(piece)
    return out.trimmingCharacters(in: .whitespaces)
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

    /// The category deleted items fall back to: the one that started as 「其他」, whatever it is called now.
    static func otherCategory(_ db: Database) throws -> Category? {
        try Category.fetchOne(db, sql: "SELECT * FROM category WHERE builtIn = '其他' LIMIT 1")
    }

    /// How many expenses and plan items use a category (shown before deleting it).
    static func categoryUse(_ db: Database, _ id: Int64) throws -> (expenses: Int, plans: Int) {
        (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expense WHERE categoryId = ?", arguments: [id]) ?? 0,
         try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plan_item WHERE categoryId = ?", arguments: [id]) ?? 0)
    }

    static func paymentMethodUse(_ db: Database, _ id: Int64) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expense WHERE paymentMethodId = ?", arguments: [id]) ?? 0
    }

    /// Deletes a category the user added; its expenses and plan items move to 「其他」. The built-in ones stay
    /// (they can be renamed): returns false and does nothing for those.
    @discardableResult
    static func deleteCategory(_ db: Database, _ id: Int64) throws -> Bool {
        guard let c = try Category.fetchOne(db, key: id), c.builtIn == nil else { return false }
        let to = try otherCategory(db)?.id
        try db.execute(sql: "UPDATE expense SET categoryId = ? WHERE categoryId = ?", arguments: [to, id])
        try db.execute(sql: "UPDATE plan_item SET categoryId = ? WHERE categoryId = ?", arguments: [to, id])
        try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [id])
        return true
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

    /// Deletes a payment method the user added; expenses that used it become 未指定. Built-in ones stay.
    @discardableResult
    static func deletePaymentMethod(_ db: Database, _ id: Int64) throws -> Bool {
        guard let m = try PaymentMethod.fetchOne(db, key: id), m.builtIn == nil else { return false }
        try db.execute(sql: "UPDATE expense SET paymentMethodId = NULL WHERE paymentMethodId = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM payment_method WHERE id = ?", arguments: [id])
        return true
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

/// Why a quick expense (Siri / Shortcuts) could not be recorded.
public enum QuickExpenseError: Error, Equatable {
    case noTrip
    case badAmount
    /// No rate is known for this currency yet.
    case noRate(String)
}

public extension Q {
    /// Records an expense without the editor (Siri, Shortcuts): into the trip that is on or about to start, with
    /// the same defaults 記一筆 would start from. [currency] nil = the default one; [reference] fills in a rate
    /// the trip doesn't have yet. Returns the saved expense and its trip.
    static func quickExpense(
        _ db: Database, amount: Double, title: String?, currency: String?, reference: ReferenceRates?, today: Int64 = todayEpochDay(),
        minuteOfDay: Int? = nil
    ) throws -> (expense: Expense, trip: Trip) {
        guard amount.isFinite, amount > 0 else { throw QuickExpenseError.badAmount }
        guard let tripId = tripToOpenAtLaunch(try trips(db), today: today), let trip = try Q.trip(db, tripId) else { throw QuickExpenseError.noTrip }
        let d = try expenseDefaults(db, tripId: tripId, planId: nil)
        var code = d.currency
        var text = d.rate
        if let c = currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), c.count == 3, c != code {
            code = c
            let rates = Dictionary(try Q.rates(db, tripId).map { ($0.currency, $0.rate) }, uniquingKeysWith: { a, _ in a })
            text = Q.rateText(c, tripRates: rates, last: try latestExpense(db, tripId))
        }
        if text.isEmpty { text = reference?.suggestion(code) ?? "" }
        guard let rate = Double(text), rate > 0 else { throw QuickExpenseError.noRate(code) }
        let e = Expense(tripId: tripId, date: today, amount: amount, currency: code, rate: rate, homeAmount: toHomeAmount(amount, rate),
                        categoryId: d.categoryId, paymentMethodId: d.paymentId,
                        title: (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines), minuteOfDay: minuteOfDay)
        let id = try saveExpense(db, e, photos: []).id
        return (try Q.expense(db, id) ?? e, trip)
    }
}
