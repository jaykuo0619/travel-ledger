import Foundation

// Home screen and trip screen rules (docs/IOS_PORT.md §11.C, ui/HomeScreen.kt, ui/Nav.kt, ui/TripDetail.kt).

/// The trip to open when the app starts: today within [start − 30, end]; my own before shared ones,
/// then the earliest start. Archived trips never open.
public func tripToOpenAtLaunch(_ trips: [Trip], today: Int64) -> Int64? {
    trips.filter { !$0.archived && today >= $0.startDate - 30 && today <= $0.endDate }
        .sorted { a, b in
            if a.readOnly != b.readOnly { return !a.readOnly }
            if a.startDate != b.startDate { return a.startDate < b.startDate }
            return (a.id ?? 0) < (b.id ?? 0)
        }
        .first?.id
}

public enum TripTab: String, CaseIterable, Sendable {
    case today = "今天", plan = "行程", ledger = "帳本", stats = "統計"

    /// Before the trip: plans; during: today; after: stats.
    public static func `default`(start: Int64, end: Int64, today: Int64) -> TripTab {
        if today < start { return .plan }
        if today <= end { return .today }
        return .stats
    }
}

public enum TripFilter: String, CaseIterable, Sendable {
    case active = "進行中", ended = "已結束", all = "全部"

    /// "進行中" when something is on or coming up (or there are no trips at all), otherwise "全部".
    public static func initial(_ trips: [TripSummary], today: Int64) -> TripFilter {
        trips.isEmpty || trips.contains { $0.endDate >= today } ? .active : .all
    }

    /// Active trips nearest first; the others newest first (the list comes in start-date descending order).
    public func apply(_ trips: [TripSummary], today: Int64) -> [TripSummary] {
        switch self {
        case .active: return trips.filter { $0.endDate >= today }.sorted { $0.startDate < $1.startDate }
        case .ended: return trips.filter { $0.endDate < today }
        case .all: return trips
        }
    }
}

/// The most recently ended trip of my own that finished after the last backup and after the reminder
/// was last put off, or nil when there is nothing new to back up.
public func backupReminder(_ trips: [TripSummary], today: Int64, lastBackupDay: Int64, dismissedDay: Int64) -> TripSummary? {
    trips.filter { $0.sharedBy == nil && $0.endDate < today && $0.endDate >= lastBackupDay && $0.endDate > dismissedDay }
        .max { $0.endDate < $1.endDate }
}

/// Budget colour band: ≤ 80 % normal, > 80 % warning, > 100 % danger.
public enum BudgetLevel: Sendable { case normal, warning, danger
    public init(_ fraction: Double) { self = fraction > 1 ? .danger : fraction > 0.8 ? .warning : .normal }
}

// MARK: - Java compatibility

/// Java's String.hashCode(): UTF-16 units, ×31, 32-bit overflow. Colours picked from it match Android's.
public func javaHashCode(_ s: String) -> Int32 {
    var h: Int32 = 0
    for u in s.utf16 { h = h &* 31 &+ Int32(u) }
    return h
}

/// Kotlin's Int.mod: never negative for a positive divisor.
public func floorMod(_ a: Int, _ n: Int) -> Int {
    let r = a % n
    return r < 0 ? r + n : r
}

// MARK: - Category look (ui/CategoryStyle.kt)

/// An icon key (see the app's icon table) and a palette index.
public struct CategoryStyle: Equatable, Sendable {
    public let icon: String
    public let color: Int

    public init(icon: String, color: Int) { self.icon = icon; self.color = color }

    public static let paletteHex: [UInt32] = [
        0x3B82F6, 0xEC4899, 0x8B5CF6, 0xF97316, 0x14B8A6, 0xEAB308, 0x22C55E, 0xEF4444, 0x06B6D4, 0x64748B,
    ]

    /// Keys offered when creating a category; stored in the database as is.
    public static let iconKeys = [
        "bus", "train", "flight", "taxi", "hotel", "food", "ramen", "cafe", "bar", "shopping",
        "grocery", "gift", "camera", "ticket", "spa", "beach", "medical", "phone", "luggage", "more",
    ]

    public static func guess(_ name: String) -> CategoryStyle {
        func has(_ words: [String]) -> Bool { words.contains { name.contains($0) } }
        if has(["交通", "車", "巴士", "地鐵"]) { return .init(icon: "bus", color: 0) }
        if has(["住", "宿", "飯店", "旅館"]) { return .init(icon: "hotel", color: 1) }
        if has(["購", "買", "伴手"]) { return .init(icon: "shopping", color: 2) }
        if has(["機票", "飛"]) { return .init(icon: "flight", color: 8) }
        if has(["飲料", "咖啡", "茶"]) { return .init(icon: "cafe", color: 5) }
        if has(["吃", "食", "餐", "飯"]) { return .init(icon: "food", color: 3) }
        if has(["景點", "觀光", "拍"]) { return .init(icon: "camera", color: 4) }
        if has(["門票", "票"]) { return .init(icon: "ticket", color: 6) }
        if has(["酒"]) { return .init(icon: "bar", color: 7) }
        if has(["其他", "雜"]) { return .init(icon: "more", color: 9) }
        return .init(icon: "more", color: floorMod(Int(javaHashCode(name)), paletteHex.count))
    }

    /// A category's stored icon/colour, falling back to the guess from its name; nil name = 未分類.
    public static func resolve(name: String?, icon: String?, color: Int?) -> CategoryStyle {
        guard let name else { return .init(icon: "more", color: paletteHex.count - 1) }
        let g = guess(name)
        let key = icon.flatMap { !$0.isEmpty && iconKeys.contains($0) ? $0 : nil } ?? g.icon
        let idx = color.flatMap { $0 >= 0 && $0 < paletteHex.count ? $0 : nil } ?? g.color
        return .init(icon: key, color: idx)
    }

    /// Member avatar colour (palette without the last grey).
    public static func avatarColor(_ name: String) -> Int { floorMod(Int(javaHashCode(name)), paletteHex.count - 1) }
}

/// Payment method icon: "cash", "card", "mobile" or "wallet".
public func paymentIconKey(_ name: String?) -> String {
    guard let name else { return "wallet" }
    if name.contains("現金") { return "cash" }
    if name.contains("卡") { return "card" }
    if ["行動", "Pay", "pay", "支付"].contains(where: { name.contains($0) }) { return "mobile" }
    return "wallet"
}

// MARK: - Navigation apps

public enum NavApp: String, CaseIterable, Sendable {
    case google, naver, kakao
    public var label: String {
        switch self {
        case .google: return "Google 地圖"
        case .naver: return "Naver Map"
        case .kakao: return "KakaoMap"
        }
    }
}
