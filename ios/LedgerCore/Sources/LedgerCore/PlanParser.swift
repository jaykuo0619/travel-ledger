import Foundation
import GRDB

/// A place parsed from pasted text or a map app's share.
public struct ParsedPlace: Equatable, Sendable {
    public var title: String
    public var location: String
    public var categoryHint: String?
    public var minuteOfDay: Int?

    public init(title: String, location: String, categoryHint: String?, minuteOfDay: Int? = nil) {
        self.title = title; self.location = location; self.categoryHint = categoryHint; self.minuteOfDay = minuteOfDay
    }
}

/// Turns pasted research notes and shared map links into itinerary items (logic/PlanParser.kt; the patterns and
/// word lists are in PlanParserData.swift).
public enum PlanParser {
    private static func re(_ p: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: options) }
    private static let urlRegex = re(PlanParserData.url)
    private static let bracketTag = re(PlanParserData.bracketTag)
    private static let prefixTag = re(PlanParserData.prefixTag)
    private static let travelVerbs = re(PlanParserData.travelVerbs)
    private static let lineBullet = re(PlanParserData.lineBullet)
    private static let headerLine = re(PlanParserData.headerLine, [.caseInsensitive])
    private static let clock = re(PlanParserData.clock)
    private static let hourWord = re(PlanParserData.hourWord)
    private static let separators = re(PlanParserData.separators)
    private static let stepBullet = re(PlanParserData.stepBullet)
    private static let spaces = re(#"\s+"#)
    private static let digit = re(#"\d"#)
    private static let meals: Set<String> = ["早餐", "午餐", "晚餐", "下午茶", "宵夜"]

    private static func whole(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    private static func first(_ r: NSRegularExpression, _ s: String) -> NSTextCheckingResult? { r.firstMatch(in: s, range: whole(s)) }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (s as NSString).substring(with: r)
    }

    private static func replace(_ r: NSRegularExpression, _ s: String, with t: String) -> String {
        r.stringByReplacingMatches(in: s, range: whole(s), withTemplate: NSRegularExpression.escapedTemplate(for: t))
    }

    private static func removing(_ m: NSTextCheckingResult, from s: String) -> String {
        (s as NSString).replacingCharacters(in: m.range, with: "")
    }

    private static func trim(_ s: String, _ chars: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: chars)) }
    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func lines(_ s: String) -> [String] {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }

    /// The category the text names itself (tag, prefix or emoji), and the text without that marker.
    public static func explicitCategory(_ text: String) -> (category: String, rest: String)? {
        if let m = first(bracketTag, text), let c = PlanParserData.tagNames[trimmed(group(m, 1, text))] { return (c, trimmed(removing(m, from: text))) }
        if let m = first(prefixTag, text), let c = PlanParserData.tagNames[group(m, 1, text)] { return (c, trimmed(removing(m, from: text))) }
        if let e = PlanParserData.emojiTags.first(where: { $0.1.contains { text.contains($0) } }) { return (e.0, text) }
        return nil
    }

    public static func guessCategory(_ text: String) -> String? {
        if let c = explicitCategory(text)?.category { return c }
        if first(travelVerbs, trimmed(text)) != nil { return "交通" }
        return PlanParserData.hints.first { $0.1.contains { text.contains($0) } }?.0
    }

    /// One place per non-empty line; bullets and numbering are stripped, URLs become the location.
    public static func parseLines(_ text: String) -> [ParsedPlace] {
        lines(text).compactMap { raw in
            let url = first(urlRegex, raw).map { group($0, 0, raw) } ?? ""
            let title = trim(trimmed(replace(lineBullet, replace(urlRegex, raw, with: " "), with: "")), PlanParserData.lineTrim)
            if title.isEmpty, url.isEmpty { return nil }
            return ParsedPlace(title: title.isEmpty ? "地圖地點" : title, location: url, categoryHint: guessCategory(title))
        }
    }

    /// The time written in [text] (09:30, 3點半, 下午3點, 晚上…), in minutes after midnight.
    public static func findTime(_ text: String) -> Int? {
        let afternoon = text.contains("下午") || text.contains("晚上") || text.contains("傍晚")
        if let m = first(clock, text) {
            let h = Int(group(m, 1, text)) ?? 0
            return (afternoon && h < 12 ? h + 12 : h) * 60 + (Int(group(m, 2, text)) ?? 0)
        }
        if let m = first(hourWord, text) {
            let h = Int(group(m, 1, text)) ?? 0
            let part = group(m, 2, text)
            let min = part == "半" ? 30 : part.isEmpty ? 0 : Int(part.filter { ("0" ... "9").contains($0) }) ?? 0
            return (afternoon && h < 12 ? h + 12 : h) * 60 + min
        }
        return PlanParserData.periods.first { text.contains($0.0) }?.1
    }

    /// A day's notes split into separate plan items: one per line (and per "→" step), with the time and a guessed
    /// category. "Day 3" / "第三天" headings are skipped; a line that is only a link becomes the previous item's
    /// location. Nothing else is dropped, so whatever the guess misses is still there to fix in the preview.
    public static func splitNote(_ text: String) -> [ParsedPlace] {
        var out: [ParsedPlace] = []
        for raw in lines(text) {
            if trimmed(raw).isEmpty { continue }
            if let h = first(headerLine, raw), h.range.length == (raw as NSString).length { continue }
            let lineUrl = first(urlRegex, raw).map { group($0, 0, raw) }
            let rest = trimmed(replace(urlRegex, raw, with: " "))
            if rest.isEmpty, let lineUrl {
                if let last = out.last, last.location.isEmpty { out[out.count - 1].location = lineUrl } else {
                    out.append(ParsedPlace(title: "地圖地點", location: lineUrl, categoryHint: nil))
                }
                continue
            }
            let lineTime = findTime(rest)
            let steps = split(rest).filter { !trimmed($0).isEmpty }
            for (i, step) in steps.enumerated() {
                let time = findTime(step) ?? (i == 0 ? lineTime : nil)
                var t = replace(hourWord, replace(clock, step, with: " "), with: " ")
                t = replace(stepBullet, t, with: "")
                for (word, _) in PlanParserData.periods where !meals.contains(word) { t = t.replacingOccurrences(of: word, with: " ") }
                let title = trim(trimmed(replace(spaces, t, with: " ")), PlanParserData.stepTrim)
                let tagged = explicitCategory(title)
                let clean = trim(trimmed(tagged?.rest ?? title), PlanParserData.stepTrim)
                if clean.isEmpty { continue }
                out.append(ParsedPlace(title: clean, location: i == 0 ? lineUrl ?? "" : "",
                                       categoryHint: tagged?.category ?? guessCategory(clean) ?? guessCategory(step), minuteOfDay: time))
            }
        }
        return out
    }

    private static func split(_ s: String) -> [String] {
        let ns = s as NSString
        var parts: [String] = []
        var at = 0
        for m in separators.matches(in: s, range: whole(s)) {
            parts.append(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
            at = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: at))
        return parts
    }

    /// Google Maps shares look like "一蘭 新宿中央東口店\nhttps://maps.app.goo.gl/…" (sometimes with an address
    /// after a comma, sometimes only the link). The first non-link line is the name.
    public static func parseShare(_ text: String, subject: String? = nil) -> ParsedPlace {
        let url = first(urlRegex, text).map { group($0, 0, text) } ?? ""
        let firstLine = lines(replace(urlRegex, text, with: "\n")).map(trimmed).first { !$0.isEmpty }
        let subjectLine = subject.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
        var name = firstLine ?? subjectLine ?? ""
        // "Ichiran Shinjuku, 3-34-11 Shinjuku, Tokyo" → keep the name before the address.
        if let cut = name.firstIndex(where: { $0 == "," || $0 == "\u{FF0C}" }), cut > name.startIndex, first(digit, String(name[cut...])) != nil {
            name = trimmed(String(name[..<cut]))
        }
        let location = !url.isEmpty ? url : name.isEmpty ? trimmed(text) : ""
        return ParsedPlace(title: name.isEmpty ? "地圖地點" : name, location: location, categoryHint: guessCategory(name))
    }
}

/// What 復原 needs after a note was split into plan items.
public struct SplitUndo: Equatable, Sendable {
    public let original: PlanItem
    public let created: [Int64]
    public let movedPictures: Bool
    public let linkedExpenses: [Int64]
    public let noteBefore: DayNote?
    public let shared: Bool
}

public extension Q {
    /// Turns one plan item's note into [items] (ui/ViewModels.kt splitPlan). On my own trip the original goes:
    /// its note moves to that day's note as 「【title】\nnote」, its pictures to the first new item, and expenses
    /// recorded for it lose the link. On someone else's trip (or for my pending item) the original stays and the
    /// new items are pending.
    static func splitPlan(_ db: Database, original: PlanItem, items: [PlanItem], shared: Bool) throws -> SplitUndo {
        let id = original.id ?? 0
        let day = original.date ?? unscheduledDay
        let before = try dayNote(db, tripId: original.tripId, day: day)
        let linked = try Int64.fetchAll(db, sql: "SELECT id FROM expense WHERE planItemId = ?", arguments: [id])
        var created: [Int64] = []
        for var item in items {
            item.id = nil
            item.pending = item.pending || shared
            try item.insert(db)
            created.append(item.id ?? 0)
        }
        // Pictures go with the first new item so no screenshot is lost.
        let moved = try !shared && !created.isEmpty && !planPhotos(db, planId: id).isEmpty
        if moved, let first = created.first {
            try db.execute(sql: "UPDATE plan_photo SET planItemId = ? WHERE planItemId = ?", arguments: [first, id])
        }
        if !shared {
            let block = "【\(original.title)】\n\(original.note.trimmingCharacters(in: .whitespacesAndNewlines))"
            try setDayNote(db, tripId: original.tripId, day: day, text: [before?.text, block].compactMap { $0 }.joined(separator: "\n\n"))
            try deletePlan(db, id)
        }
        return SplitUndo(original: original, created: created, movedPictures: moved, linkedExpenses: linked, noteBefore: before, shared: shared)
    }

    /// Puts everything back as it was before [splitPlan].
    static func undoSplit(_ db: Database, _ undo: SplitUndo) throws {
        var o = undo.original
        // Bring the original back first, so its pictures can move home before the new items go.
        if !undo.shared {
            try o.insert(db)
            if undo.movedPictures, let first = undo.created.first {
                try db.execute(sql: "UPDATE plan_photo SET planItemId = ? WHERE planItemId = ?", arguments: [o.id, first])
            }
            for e in undo.linkedExpenses { try db.execute(sql: "UPDATE expense SET planItemId = ? WHERE id = ?", arguments: [o.id, e]) }
            let day = o.date ?? unscheduledDay
            if let before = undo.noteBefore { try putDayNote(db, before) } else {
                try db.execute(sql: "DELETE FROM day_note WHERE tripId = ? AND day = ?", arguments: [o.tripId, day])
            }
        }
        for id in undo.created { try db.execute(sql: "DELETE FROM plan_item WHERE id = ?", arguments: [id]) }
    }
}
