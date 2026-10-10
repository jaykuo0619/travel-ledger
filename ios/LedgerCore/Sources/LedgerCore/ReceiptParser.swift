import Foundation

/// One recognized text line with its bounding box in image pixels (top-left origin).
public struct OcrLine: Equatable, Sendable {
    public let text: String
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int
    public var centerY: Int { (top + bottom) / 2 }
    public var height: Int { bottom - top }

    public init(_ text: String, _ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
        self.text = text; self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

/// What we could read from a photo. Every field is optional; the user confirms before applying.
public struct ReceiptGuess: Equatable, Sendable {
    public var isReceipt: Bool
    public var store: String?
    public var total: Double?
    public var currency: String?
    /// Epoch day.
    public var date: Int64?
    public var minuteOfDay: Int?
    public var hasData: Bool { store != nil || total != nil || date != nil }

    public init(isReceipt: Bool, store: String? = nil, total: Double? = nil, currency: String? = nil, date: Int64? = nil, minuteOfDay: Int? = nil) {
        self.isReceipt = isReceipt; self.store = store; self.total = total; self.currency = currency; self.date = date; self.minuteOfDay = minuteOfDay
    }
}

/// Heuristic receipt reader for Japanese, Taiwanese, Korean and English receipts (logic/ReceiptParser.kt).
/// Works on OCR lines with positions so a "合計" label can be paired with the amount printed on the same row.
public enum ReceiptParser {
    // Strongest first. A label containing an excluded word is skipped.
    private static let totalLabels = [
        "総合計", "税込合計", "合計金額", "お会計", "ご請求額", "お支払", "合計", "総額", "現計",
        "總計", "總金額", "應付", "應收", "合計金額", "總額",
        "합계", "총액", "결제금액", "받을금액", "판매금액",
        "GRAND TOTAL", "TOTAL", "AMOUNT DUE", "BALANCE DUE",
        "小計", "SUBTOTAL",
    ]
    private static let excludedLabels = [
        "預り", "預かり", "お釣", "釣銭", "おつり", "対象", "消費税", "税額", "内税", "外税", "ポイント", "点数", "點數",
        "找零", "找錢", "實收", "收現", "稅額", "數量",
        "거스름", "받은금액", "부가세", "과세",
        "CHANGE", "CASH", "TENDER", "TAX", "QTY", "ITEMS",
    ]
    private static let receiptWords = [
        "領収", "レシート", "お買上", "税込", "合計", "統一發票", "電子發票", "發票", "收據", "交易明細",
        "영수증", "합계", "RECEIPT", "INVOICE", "TOTAL",
    ]
    private static let storeStopWords = [
        "領収", "レシート", "receipt", "RECEIPT", "TEL", "Tel", "電話", "〒", "發票", "统一", "統一", "영수증",
        "登録番号", "No.", "NO.", "日付", "時間", "年", "月", "www", "http", "@",
    ]

    private static func re(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    private static let amountRegex = re(#"(?:[¥￥$₩]|NT\$|円)?\s*(\d{1,3}(?:[,\x{FF0C}]\d{3})+(?:\.\d{1,2})?|\d{1,7}(?:\.\d{1,2})?)\s*(?:円|元|원|-)?"#)
    private static let dateLike = re(#"\d{2,4}[/\-.年]\d{1,2}[/\-.月]\d{1,2}"#)
    private static let notMoney = [re(#"\d{1,2}:\d{2}(:\d{2})?"#), re(#"\d{2,4}-\d{2,4}-\d{3,4}"#), re(#"\d+\s*%"#), re(#"[x×*]\s*\d+|\d+\s*(個|点|點|件|개|pcs)"#)]

    private static func groups(_ regex: NSRegularExpression, _ s: String) -> [[String]] {
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0 ..< m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    private static func has(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    public static func normalize(_ s: String) -> String {
        String(s.map { c -> Character in
            switch c {
            case "\u{FF10}" ... "\u{FF19}": // full-width digits
                return Character(UnicodeScalar(UInt32(48) + c.unicodeScalars.first!.value - 0xFF10)!)
            case "\u{FF0C}": return ","
            case "\u{FF0E}": return "."
            case "\u{FF1A}": return ":"
            case "\u{FF0F}": return "/"
            case "\u{FFE5}": return "\u{A5}" // full-width yen
            case "\\": return "\u{A5}" // OCR often reads the yen sign as a backslash
            default: return c
            }
        })
    }

    /// Numbers in a line that look like money (not dates, times, phone numbers).
    public static func amountsIn(_ raw: String) -> [Double] {
        let line = normalize(raw)
        if has(dateLike, line) { return [] }
        var cleaned = line
        for r in notMoney {
            cleaned = r.stringByReplacingMatches(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length), withTemplate: " ")
        }
        return groups(amountRegex, cleaned).compactMap { Double($0[1].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "\u{FF0C}", with: "")) }
            .filter { $0 > 0 }
    }

    private static func squash(_ s: String) -> String { s.uppercased().replacingOccurrences(of: " ", with: "") }

    private static func labelRank(_ text: String) -> Int? {
        let upper = squash(normalize(text))
        if excludedLabels.contains(where: { upper.contains(squash($0)) }) { return nil }
        return totalLabels.firstIndex { upper.contains(squash($0)) }
    }

    /// Amount on the same visual row as [label]: in the label line itself, else the nearest line at that height.
    private static func amountForLabel(_ label: OcrLine, _ lines: [OcrLine]) -> Double? {
        if let a = amountsIn(label.text).last { return a }
        let tolerance = Double(max(label.height, 12)) * 0.7
        return lines
            .filter { $0 != label && $0.left >= label.left && Double(abs($0.centerY - label.centerY)) <= tolerance }
            .filter { l in labelRank(l.text) == nil && !excludedLabels.contains { normalize(l.text).uppercased().contains($0.uppercased()) } }
            .sorted { abs($0.centerY - label.centerY) < abs($1.centerY - label.centerY) }
            .compactMap { amountsIn($0.text).last }
            .first
    }

    public static func findTotal(_ lines: [OcrLine]) -> Double? {
        let labeled = lines.compactMap { l in labelRank(l.text).map { (l, $0) } }
            .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.top > b.0.top }
        for (label, _) in labeled {
            if let a = amountForLabel(label, lines) { return a }
        }
        // No label: the largest money-looking number, ignoring lines about cash tendered or change.
        return lines.filter { l in !excludedLabels.contains { normalize(l.text).uppercased().contains($0.uppercased()) } }
            .flatMap { amountsIn($0.text) }
            .filter { $0 < 10_000_000 }
            .max()
    }

    private static let hangul = re("[가-힣]")
    private static let kana = re("[ぁ-んァ-ヶ]")

    public static func findCurrency(_ all: String) -> String? {
        let t = normalize(all)
        if t.contains("₩") || t.contains("원") || has(hangul, t) { return "KRW" }
        if t.contains("NT$") || t.contains("統一發票") || t.contains("電子發票") || t.contains("新台幣") { return "TWD" }
        if t.contains("¥") || t.contains("円") || has(kana, t) { return "JPY" }
        if t.contains("฿") || t.contains("บาท") { return "THB" }
        if t.contains("HK$") { return "HKD" }
        if t.contains("S$") { return "SGD" }
        if t.contains("RM"), t.contains("SST") { return "MYR" }
        return nil
    }

    private static let reiwa = re(#"令和\s*(\d{1,2}|元)\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#)
    private static let western = re(#"(20\d{2})\s*[/\-.年]\s*(\d{1,2})\s*[/\-.月]\s*(\d{1,2})"#)
    private static let roc = re(#"(?<!\d)(1[01]\d)\s*[/\-.年]\s*(\d{1,2})\s*[/\-.月]\s*(\d{1,2})"#)
    private static let time = re(#"(?<!\d)([01]?\d|2[0-3])\s*[:時]\s*([0-5]\d)"#)

    /// The receipt's date as an epoch day.
    public static func findDate(_ all: String) -> Int64? {
        let t = normalize(all)
        func ok(_ y: Int, _ m: Int, _ d: Int) -> Int64? {
            guard (2000 ... 2100).contains(y), (1 ... 12).contains(m), d >= 1 else { return nil }
            let day = CivilDate(year: y, month: m, day: d).epochDay
            let back = day.civil
            return back.year == y && back.month == m && back.day == d ? day : nil // 2/30 and the like
        }
        if let m = groups(reiwa, t).first {
            let n = m[1] == "元" ? 1 : Int(m[1]) ?? 0
            if let d = ok(2018 + n, Int(m[2]) ?? 0, Int(m[3]) ?? 0) { return d }
        }
        if let m = groups(western, t).first, let d = ok(Int(m[1]) ?? 0, Int(m[2]) ?? 0, Int(m[3]) ?? 0) { return d }
        // Taiwan ROC year, e.g. 113/06/12 or 民國113年6月12日
        if let m = groups(roc, t).first, let d = ok((Int(m[1]) ?? 0) + 1911, Int(m[2]) ?? 0, Int(m[3]) ?? 0) { return d }
        return nil
    }

    public static func findTime(_ all: String) -> Int? {
        guard let m = groups(time, normalize(all)).first else { return nil }
        return (Int(m[1]) ?? 0) * 60 + (Int(m[2]) ?? 0)
    }

    /// The store name is usually the tallest text near the top of the receipt.
    public static func findStore(_ lines: [OcrLine]) -> String? {
        guard let top = lines.map(\.top).min(), let bottom = lines.map(\.bottom).max() else { return nil }
        let limit = Double(top) + Double(bottom - top) * 0.3
        let trim = CharacterSet(charactersIn: "*-= 【】")
        var candidates: [(line: OcrLine, text: String)] = []
        for line in lines where Double(line.top) <= limit {
            let t = normalize(line.text).trimmingCharacters(in: .whitespacesAndNewlines)
            let letters = t.filter(\.isLetter).count
            let stop = storeStopWords.contains { t.contains($0) }
            if letters >= 2, letters * 2 >= t.count, !stop, labelRank(t) == nil { candidates.append((line, t)) }
        }
        candidates.sort { a, b in a.line.height != b.line.height ? a.line.height > b.line.height : a.line.top < b.line.top }
        return candidates.map { $0.text.trimmingCharacters(in: trim) }.first { !$0.isEmpty }
    }

    public static func isReceipt(_ lines: [OcrLine]) -> Bool {
        if lines.count < 4 { return false }
        let all = normalize(lines.map(\.text).joined(separator: "\n")).uppercased()
        let keyword = receiptWords.contains { all.contains($0.uppercased()) }
        let priceLines = lines.filter { !amountsIn($0.text).isEmpty }.count
        return (keyword && priceLines >= 2) || priceLines >= 4
    }

    /// [force]: the photo was taken with 「拍收據」, so read it as a receipt even if the layout is hard to read.
    public static func parse(_ lines: [OcrLine], force: Bool = false) -> ReceiptGuess {
        if !isReceipt(lines), !force { return ReceiptGuess(isReceipt: false) }
        let all = lines.map(\.text).joined(separator: "\n")
        return ReceiptGuess(isReceipt: true, store: findStore(lines), total: findTotal(lines), currency: findCurrency(all),
                            date: findDate(all), minuteOfDay: findTime(all))
    }
}
