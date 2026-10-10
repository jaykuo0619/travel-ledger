import Foundation

// Text formats from the Android app (ui/Format.kt, ui/Pickers.kt), word for word.

private let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

/// "週四"
public func weekdayLabel(_ epochDay: Int64) -> String { "週" + weekdayChars[epochDay.civil.weekday] }

/// "2024/06/12"
public func fmtDate(_ epochDay: Int64) -> String {
    let d = epochDay.civil
    return String(format: "%d/%02d/%02d", d.year, d.month, d.day)
}

/// "10/22(四)"
public func fmtShortDate(_ epochDay: Int64) -> String {
    let d = epochDay.civil
    return "\(d.month)/\(d.day)(\(weekdayChars[d.weekday]))"
}

/// "10/22"
public func fmtMonthDay(_ epochDay: Int64) -> String {
    let d = epochDay.civil
    return "\(d.month)/\(d.day)"
}

/// "10月22日 週四"
public func fmtDayHeader(_ epochDay: Int64) -> String {
    let d = epochDay.civil
    return "\(d.month)月\(d.day)日 \(weekdayLabel(epochDay))"
}

/// "10/22 – 10/27" in [thisYear]; otherwise "2023/12/20 – 12/26", or the year on both ends when they differ.
public func fmtRange(_ start: Int64, _ end: Int64, thisYear: Int = CivilDate.today().year) -> String {
    let a = start.civil, b = end.civil
    if a.year == b.year && a.year == thisYear { return "\(a.month)/\(a.day) – \(b.month)/\(b.day)" }
    if a.year == b.year { return "\(a.year)/\(a.month)/\(a.day) – \(b.month)/\(b.day)" }
    return "\(a.year)/\(a.month)/\(a.day) – \(b.year)/\(b.month)/\(b.day)"
}

/// "14:32"
public func fmtTime(_ minuteOfDay: Int) -> String { String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60) }

/// "10/22 週四 14:32"
public func fmtShortDateTime(_ epochDay: Int64, _ minuteOfDay: Int?) -> String {
    let d = epochDay.civil
    return "\(d.month)/\(d.day) \(weekdayLabel(epochDay))" + (minuteOfDay.map { " " + fmtTime($0) } ?? "")
}

/// "10/22 14:05" from epoch millis, local time (files' exportedAt / sharedAt).
public func fmtStamp(_ millis: Int64, calendar: Calendar = .current) -> String {
    let c = localDateTime(millis: millis, calendar: calendar)
    return String(format: "%d/%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
}

private func symbol(_ currency: String) -> String { currency == homeCurrency ? "NT$" : currency }

/// Java's Math.round: half up toward positive infinity.
public func javaRound(_ v: Double) -> Int64 {
    guard v.isFinite else { return 0 }
    let r = (v + 0.5).rounded(.down)
    // Java clamps to Long.MIN_VALUE / MAX_VALUE; Int64(r) would trap out of range.
    if r >= 9.2e18 { return .max }
    if r <= -9.2e18 { return .min }
    return Int64(r)
}

private func grouped(_ n: Int64) -> String {
    let digits = String(n.magnitude)
    var out = ""
    for (i, ch) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return (n < 0 ? "-" : "") + out
}

/// Home-currency money rounded to whole dollars: "NT$ 28,450".
public func fmtMoney(_ v: Double, currency: String = homeCurrency) -> String { symbol(currency) + " " + grouped(javaRound(v)) }

/// Grouped number with up to 2 decimals: "1,320" / "12.5" (half-even like Java's NumberFormat).
public func fmtPlain(_ v: Double) -> String {
    guard v.isFinite else { return "0" }
    let cents = (Decimal(v) * 100)
    var rounded = Decimal()
    var c = cents
    NSDecimalRound(&rounded, &c, 0, .bankers)
    let total = NSDecimalNumber(decimal: rounded).int64Value
    let whole = total / 100
    let frac = abs(total % 100)
    var text = grouped(whole)
    if total < 0 && whole == 0 { text = "-0" }
    if frac != 0 {
        text += "." + (frac % 10 == 0 ? String(frac / 10) : String(format: "%02d", frac))
    }
    return text
}

/// "JPY 1,234.5" / "NT$ 1,200"
public func fmtAmount(_ v: Double, _ currency: String) -> String { "\(symbol(currency)) \(fmtPlain(v))" }

/// Plain decimal without trailing zeros: 1200.0 → "1200", 0.2150 → "0.215".
public func fmtNumber(_ v: Double) -> String {
    var s = String(format: "%.6f", v)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    return s == "-0" ? "0" : s
}

/// Rate with 4 decimals: "0.0240".
public func fmtRate(_ v: Double) -> String { String(format: "%.4f", v) }

public let commonCurrencies = ["TWD", "JPY", "USD", "KRW", "EUR", "HKD", "CNY", "THB", "SGD", "MYR", "GBP", "AUD", "VND"]

public let currencyNames: [String: String] = [
    "TWD": "新台幣", "JPY": "日圓", "USD": "美元", "KRW": "韓元", "EUR": "歐元",
    "HKD": "港幣", "CNY": "人民幣", "THB": "泰銖", "SGD": "新加坡幣", "MYR": "馬幣",
    "GBP": "英鎊", "AUD": "澳幣", "VND": "越南盾",
]

/// "JPY 日圓"
public func currencyLabel(_ code: String) -> String { currencyNames[code].map { "\(code) \($0)" } ?? code }

/// "明天出發" / "還有 12 天出發" / "旅行中 · 第 3 天" / "已結束"
public func tripStatus(start: Int64, end: Int64, today: Int64) -> String {
    if today < start { return start - today == 1 ? "明天出發" : "還有 \(start - today) 天出發" }
    if today <= end { return "旅行中 · 第 \(today - start + 1) 天" }
    return "已結束"
}

/// File names: runs of \ / : * ? " < > | and spaces become "_", at most 40 characters, "旅程" when empty.
public func safeFileName(_ name: String) -> String {
    var out = ""
    var lastWasBad = false
    for ch in name {
        let bad = "\\/:*?\"<>|".contains(ch) || ch.isWhitespace
        if bad {
            if !lastWasBad { out.append("_") }
        } else {
            out.append(ch)
        }
        lastWasBad = bad
    }
    let cut = String(out.prefix(40))
    return cut.isEmpty ? "旅程" : cut
}
