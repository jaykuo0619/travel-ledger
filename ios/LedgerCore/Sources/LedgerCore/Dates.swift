import Foundation

/// A calendar date as stored in the files: days since 1970-01-01, with no time zone.
public struct CivilDate: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    /// Howard Hinnant's days_from_civil.
    public var epochDay: Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = Int64(month)
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + Int64(day) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public init(epochDay: Int64) {
        let z = epochDay + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: Int(yoe + era * 400 + (m <= 2 ? 1 : 0)), month: Int(m), day: Int(d))
    }

    /// 0 = Sunday … 6 = Saturday.
    public var weekday: Int {
        let r = (epochDay + 4) % 7
        return Int(r < 0 ? r + 7 : r)
    }

    /// The Gregorian calendar in the current time zone. Dates in the data are Gregorian whatever calendar the
    /// phone is set to: with the ROC, Japanese or Buddhist calendar, Calendar.current would say year 115, 8 or 2569.
    public static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    public static func today(_ now: Date = Date(), calendar: Calendar = CivilDate.gregorian) -> CivilDate {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return CivilDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Midnight of this date in [calendar]'s time zone, for date pickers.
    public func date(calendar: Calendar = CivilDate.gregorian) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}

public extension Int64 {
    var civil: CivilDate { CivilDate(epochDay: self) }
}

public func todayEpochDay(_ now: Date = Date()) -> Int64 { CivilDate.today(now).epochDay }

/// Epoch millis to local month/day/hour/minute.
public func localDateTime(millis: Int64, calendar: Calendar = CivilDate.gregorian) -> DateComponents {
    calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: Double(millis) / 1000))
}
