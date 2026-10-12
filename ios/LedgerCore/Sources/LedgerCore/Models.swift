import Foundation
import GRDB

// Tables and columns follow the Android app (data/Entities.kt) one to one.
// Dates are epoch days (local date, no time zone); times are minutes after midnight;
// createdAt / updatedAt / sharedAt are epoch milliseconds. Photo paths are relative to FileStore.root.

public let homeCurrency = "TWD"

/// The 待排 list has no date; its day note is stored under this day.
public let unscheduledDay = Int64.min

public func nowMillis() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

/// Lower-case hex, no dashes; uuids from files are kept exactly as they come.
public func newUUID() -> String { UUID().uuidString.lowercased() }

public struct Trip: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "trip"
    public var id: Int64?
    public var name: String
    public var startDate: Int64
    public var endDate: Int64
    public var homeCurrency: String = LedgerCore.homeCurrency
    public var budget: Double?
    public var splitEnabled = false
    public var createdAt: Int64 = nowMillis()
    public var archived = false
    /// Cover photo (relative path), or nil for an illustration.
    public var coverPath: String?
    /// Illustration chosen by hand (CoverTheme raw value), or nil to pick it from the name.
    public var coverTheme: String?
    /// Stable identity across phones.
    public var uuid: String = newUUID()
    /// Who shared this trip with us; non-nil means a read-only copy.
    public var sharedBy: String?
    public var sharedAt: Int64?
    /// "google", "naver", "kakao", or nil to ask each time.
    public var navApp: String?

    public var readOnly: Bool { sharedBy != nil }

    public init(
        id: Int64? = nil, name: String, startDate: Int64, endDate: Int64, homeCurrency: String = LedgerCore.homeCurrency,
        budget: Double? = nil, splitEnabled: Bool = false, createdAt: Int64 = nowMillis(), archived: Bool = false,
        coverPath: String? = nil, coverTheme: String? = nil, uuid: String = newUUID(), sharedBy: String? = nil,
        sharedAt: Int64? = nil, navApp: String? = nil
    ) {
        self.id = id; self.name = name; self.startDate = startDate; self.endDate = endDate
        self.homeCurrency = homeCurrency; self.budget = budget; self.splitEnabled = splitEnabled
        self.createdAt = createdAt; self.archived = archived; self.coverPath = coverPath; self.coverTheme = coverTheme
        self.uuid = uuid; self.sharedBy = sharedBy; self.sharedAt = sharedAt; self.navApp = navApp
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct TripCurrencyRate: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trip_currency_rate"
    public var tripId: Int64
    public var currency: String
    /// 1 unit of [currency] in TWD.
    public var rate: Double
    public var updatedAt: Int64 = nowMillis()
    public var source = "manual"

    public init(tripId: Int64, currency: String, rate: Double, updatedAt: Int64 = nowMillis(), source: String = "manual") {
        self.tripId = tripId; self.currency = currency; self.rate = rate; self.updatedAt = updatedAt; self.source = source
    }
}

public struct Member: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "member"
    public var id: Int64?
    public var tripId: Int64
    public var name: String

    public init(id: Int64? = nil, tripId: Int64, name: String) { self.id = id; self.tripId = tripId; self.name = name }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Category: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "category"
    public var id: Int64?
    public var name: String
    public var sortOrder = 0
    /// Icon key (see CategoryStyle); empty means "guess from the name".
    public var icon = ""
    /// Palette index; -1 means "guess from the name".
    public var color = -1
    /// The original name of a built-in category (吃, 交通, … 其他): those can be renamed but not deleted.
    /// Nil for categories the user added or an import brought. Not written to files.
    public var builtIn: String?

    public init(id: Int64? = nil, name: String, sortOrder: Int = 0, icon: String = "", color: Int = -1, builtIn: String? = nil) {
        self.id = id; self.name = name; self.sortOrder = sortOrder; self.icon = icon; self.color = color; self.builtIn = builtIn
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct PaymentMethod: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "payment_method"
    public var id: Int64?
    public var name: String
    public var sortOrder = 0
    /// The original name of a built-in payment method (現金, 信用卡, 行動支付); nil for added ones.
    public var builtIn: String?

    public init(id: Int64? = nil, name: String, sortOrder: Int = 0, builtIn: String? = nil) {
        self.id = id; self.name = name; self.sortOrder = sortOrder; self.builtIn = builtIn
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Expense: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "expense"
    public var id: Int64?
    public var tripId: Int64
    public var date: Int64
    public var amount: Double
    public var currency: String
    public var rate: Double
    public var homeAmount: Double
    public var categoryId: Int64?
    public var paymentMethodId: Int64?
    public var payerId: Int64?
    public var note = ""
    public var createdAt: Int64 = nowMillis()
    public var title = ""
    public var minuteOfDay: Int?
    public var ocrText = ""
    public var planItemId: Int64?
    public var uuid: String = newUUID()
    public var addedBy: String?
    /// My own addition on a shared trip, waiting to be sent to the organizer.
    public var pending = false

    public init(
        id: Int64? = nil, tripId: Int64, date: Int64, amount: Double, currency: String, rate: Double, homeAmount: Double,
        categoryId: Int64? = nil, paymentMethodId: Int64? = nil, payerId: Int64? = nil, note: String = "",
        createdAt: Int64 = nowMillis(), title: String = "", minuteOfDay: Int? = nil, ocrText: String = "",
        planItemId: Int64? = nil, uuid: String = newUUID(), addedBy: String? = nil, pending: Bool = false
    ) {
        self.id = id; self.tripId = tripId; self.date = date; self.amount = amount; self.currency = currency
        self.rate = rate; self.homeAmount = homeAmount; self.categoryId = categoryId; self.paymentMethodId = paymentMethodId
        self.payerId = payerId; self.note = note; self.createdAt = createdAt; self.title = title
        self.minuteOfDay = minuteOfDay; self.ocrText = ocrText; self.planItemId = planItemId; self.uuid = uuid
        self.addedBy = addedBy; self.pending = pending
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum PhotoType {
    public static let receipt = "RECEIPT"
    public static let memory = "MEMORY"
}

public struct Photo: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "photo"
    public var id: Int64?
    public var expenseId: Int64
    public var type: String
    public var path: String
    public var width = 0
    public var height = 0
    public var createdAt: Int64 = nowMillis()
    public var savedToGallery = false

    public init(id: Int64? = nil, expenseId: Int64, type: String, path: String, width: Int = 0, height: Int = 0,
                createdAt: Int64 = nowMillis(), savedToGallery: Bool = false) {
        self.id = id; self.expenseId = expenseId; self.type = type; self.path = path; self.width = width
        self.height = height; self.createdAt = createdAt; self.savedToGallery = savedToGallery
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum PlanStatus {
    public static let todo = "TODO"
    public static let done = "DONE"
    public static let skipped = "SKIPPED"
}

public enum Reservation {
    public static let none = "NONE"
    public static let needed = "NEEDED"
    public static let booked = "BOOKED"
}

public struct PlanItem: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "plan_item"
    public var id: Int64?
    public var tripId: Int64
    public var title: String
    public var categoryId: Int64?
    /// nil = 待排
    public var date: Int64?
    public var minuteOfDay: Int?
    public var status = PlanStatus.todo
    public var reservation = Reservation.none
    public var reservationNote = ""
    /// Address or a map link.
    public var location = ""
    /// No longer shown; kept so files keep it.
    public var estCost: Double?
    public var note = ""
    public var createdAt: Int64 = nowMillis()
    public var uuid: String = newUUID()
    public var addedBy: String?
    public var pending = false

    public init(
        id: Int64? = nil, tripId: Int64, title: String, categoryId: Int64? = nil, date: Int64? = nil, minuteOfDay: Int? = nil,
        status: String = PlanStatus.todo, reservation: String = Reservation.none, reservationNote: String = "",
        location: String = "", estCost: Double? = nil, note: String = "", createdAt: Int64 = nowMillis(),
        uuid: String = newUUID(), addedBy: String? = nil, pending: Bool = false
    ) {
        self.id = id; self.tripId = tripId; self.title = title; self.categoryId = categoryId; self.date = date
        self.minuteOfDay = minuteOfDay; self.status = status; self.reservation = reservation
        self.reservationNote = reservationNote; self.location = location; self.estCost = estCost; self.note = note
        self.createdAt = createdAt; self.uuid = uuid; self.addedBy = addedBy; self.pending = pending
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct DayNote: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "day_note"
    public var tripId: Int64
    /// Epoch day, or `unscheduledDay` for the 待排 list.
    public var day: Int64
    public var text: String
    public var updatedAt: Int64 = nowMillis()

    public init(tripId: Int64, day: Int64, text: String, updatedAt: Int64 = nowMillis()) {
        self.tripId = tripId; self.day = day; self.text = text; self.updatedAt = updatedAt
    }
}

public struct PlanPhoto: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "plan_photo"
    public var id: Int64?
    public var planItemId: Int64
    public var path: String
    public var width = 0
    public var height = 0
    public var createdAt: Int64 = nowMillis()

    public init(id: Int64? = nil, planItemId: Int64, path: String, width: Int = 0, height: Int = 0, createdAt: Int64 = nowMillis()) {
        self.id = id; self.planItemId = planItemId; self.path = path; self.width = width; self.height = height; self.createdAt = createdAt
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Rows for lists

/// One trip card on the home screen.
public struct TripSummary: Equatable, Identifiable, Sendable, FetchableRecord {
    public var id: Int64
    public var name: String
    public var startDate: Int64
    public var endDate: Int64
    public var budget: Double?
    public var coverPath: String?
    public var coverTheme: String?
    /// Includes my pending additions.
    public var totalHome: Double
    public var memberCount: Int
    /// Foreign currencies used (from expenses and rates), without TWD.
    public var currencies: [String]
    public var sharedBy: String?

    public init(row: Row) throws {
        id = row["id"]; name = row["name"]; startDate = row["startDate"]; endDate = row["endDate"]; budget = row["budget"]
        coverPath = row["coverPath"]; coverTheme = row["coverTheme"]; totalHome = row["totalHome"]
        memberCount = row["memberCount"]; sharedBy = row["sharedBy"]
        let list: String? = row["currencies"]
        currencies = list?.split(separator: ",").map(String.init).filter { !$0.isEmpty } ?? []
    }

    public init(id: Int64, name: String, startDate: Int64, endDate: Int64, budget: Double? = nil, coverPath: String? = nil,
                coverTheme: String? = nil, totalHome: Double = 0, memberCount: Int = 0, currencies: [String] = [], sharedBy: String? = nil) {
        self.id = id; self.name = name; self.startDate = startDate; self.endDate = endDate; self.budget = budget
        self.coverPath = coverPath; self.coverTheme = coverTheme; self.totalHome = totalHome; self.memberCount = memberCount
        self.currencies = currencies; self.sharedBy = sharedBy
    }
}

/// An expense with what its list row shows.
public struct ExpenseRow: Equatable, Identifiable, Sendable, FetchableRecord {
    public var id: Int64
    public var date: Int64
    public var minuteOfDay: Int?
    public var title: String
    public var amount: Double
    public var currency: String
    public var rate: Double
    public var homeAmount: Double
    public var categoryId: Int64?
    public var categoryName: String?
    public var categoryIcon: String?
    public var categoryColor: Int?
    public var paymentMethodName: String?
    public var note: String
    public var thumbPath: String?
    public var planItemId: Int64?
    public var addedBy: String?
    public var pending: Bool

    public init(row: Row) throws {
        id = row["id"]; date = row["date"]; minuteOfDay = row["minuteOfDay"]; title = row["title"]; amount = row["amount"]
        currency = row["currency"]; rate = row["rate"]; homeAmount = row["homeAmount"]; categoryId = row["categoryId"]
        categoryName = row["categoryName"]; categoryIcon = row["categoryIcon"]; categoryColor = row["categoryColor"]
        paymentMethodName = row["paymentMethodName"]; note = row["note"]; thumbPath = row["thumbPath"]
        planItemId = row["planItemId"]; addedBy = row["addedBy"]; pending = row["pending"]
    }
}

/// A plan item with its category look and what has been spent on it.
public struct PlanRow: Equatable, Identifiable, Sendable, FetchableRecord {
    public var id: Int64
    public var title: String
    public var categoryId: Int64?
    public var categoryName: String?
    public var categoryIcon: String?
    public var categoryColor: Int?
    public var date: Int64?
    public var minuteOfDay: Int?
    public var status: String
    public var reservation: String
    public var reservationNote: String
    public var location: String
    public var estCost: Double?
    public var spent: Double
    public var addedBy: String?
    public var pending: Bool
    public var photoCount: Int

    public init(row: Row) throws {
        id = row["id"]; title = row["title"]; categoryId = row["categoryId"]; categoryName = row["categoryName"]
        categoryIcon = row["categoryIcon"]; categoryColor = row["categoryColor"]; date = row["date"]
        minuteOfDay = row["minuteOfDay"]; status = row["status"]; reservation = row["reservation"]
        reservationNote = row["reservationNote"]; location = row["location"]; estCost = row["estCost"]
        spent = row["spent"]; addedBy = row["addedBy"]; pending = row["pending"]; photoCount = row["photoCount"]
    }
}
