import Foundation

/// A JSON value that keeps numbers as their original text, so a 64-bit day such as
/// -9223372036854775808 (the 待排 note) never passes through Double, and keeps object keys in order.
/// The accessors behave like Android's org.json `opt…` calls, which wrote and read these files first.
public enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSON])
    case object(JSONObject)

    // MARK: building

    public static func int(_ v: Int64) -> JSON { .number(String(v)) }
    public static func int(_ v: Int) -> JSON { .number(String(v)) }

    /// Whole numbers are written without a fraction ("1200"), as org.json does; others in the shortest exact form.
    public static func double(_ v: Double) -> JSON {
        guard v.isFinite else { return .null }
        if v == v.rounded(), abs(v) < 1e15 { return .number(String(Int64(v))) }
        return .number("\(v)")
    }

    public var objectValue: JSONObject? { if case .object(let o) = self { return o } else { return nil } }
    public var arrayValue: [JSON]? { if case .array(let a) = self { return a } else { return nil } }
    public var isNull: Bool { if case .null = self { return true } else { return false } }

    /// Text of a string, number or boolean (org.json `optString` turns these into text too).
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// An exact 64-bit integer; a number with a fraction is cut toward zero like Java's `longValue()`.
    public var int64Value: Int64? {
        let text: String
        switch self {
        case .number(let n): text = n
        case .string(let s): text = s.trimmingCharacters(in: .whitespaces)
        default: return nil
        }
        if let v = Int64(text) { return v }
        guard let d = Double(text), d.isFinite else { return nil }
        if d >= 9.2233720368547758e18 { return Int64.max }
        if d <= -9.2233720368547758e18 { return Int64.min }
        return Int64(d)
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let n): return Double(n)
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s):
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
            return nil
        default: return nil
        }
    }
}

/// A JSON object with its keys in the order they were written.
public struct JSONObject: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var values: [String: JSON] = [:]

    public init() {}

    public init(_ pairs: [(String, JSON?)]) {
        for (k, v) in pairs { if let v { self[k] = v } }
    }

    public subscript(key: String) -> JSON? {
        get { values[key] }
        set {
            if let newValue {
                if values[key] == nil { keys.append(key) }
                values[key] = newValue
            } else if values.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Present and not null (org.json `isNull` is the opposite).
    public func has(_ key: String) -> Bool { values[key].map { !$0.isNull } ?? false }

    // MARK: org.json-style reads: missing and null both count as absent.

    public func string(_ key: String) -> String? { has(key) ? values[key]?.stringValue : nil }
    public func optString(_ key: String, _ fallback: String = "") -> String { string(key) ?? fallback }
    public func int64(_ key: String) -> Int64? { has(key) ? values[key]?.int64Value : nil }
    public func optInt64(_ key: String, _ fallback: Int64 = 0) -> Int64 { int64(key) ?? fallback }
    public func int(_ key: String) -> Int? { int64(key).map { Int(truncatingIfNeeded: $0) } }
    public func optInt(_ key: String, _ fallback: Int = 0) -> Int { int(key) ?? fallback }
    public func double(_ key: String) -> Double? { has(key) ? values[key]?.doubleValue : nil }
    public func optDouble(_ key: String, _ fallback: Double = 0) -> Double { double(key) ?? fallback }
    public func bool(_ key: String) -> Bool? { has(key) ? values[key]?.boolValue : nil }
    public func optBool(_ key: String, _ fallback: Bool = false) -> Bool { bool(key) ?? fallback }
    public func array(_ key: String) -> [JSON]? { values[key]?.arrayValue }
    public func object(_ key: String) -> JSONObject? { values[key]?.objectValue }
    /// The objects in an array (anything else in it is skipped).
    public func objects(_ key: String) -> [JSONObject]? { array(key)?.compactMap(\.objectValue) }

    // MARK: required reads, for fields every file has

    public func reqString(_ key: String) throws -> String {
        guard let v = string(key) else { throw JSONError.missing(key) }
        return v
    }
    public func reqInt64(_ key: String) throws -> Int64 {
        guard let v = int64(key) else { throw JSONError.missing(key) }
        return v
    }
    public func reqDouble(_ key: String) throws -> Double {
        guard let v = double(key) else { throw JSONError.missing(key) }
        return v
    }
    public func reqArray(_ key: String) throws -> [JSON] {
        guard let v = array(key) else { throw JSONError.missing(key) }
        return v
    }
    public func reqObjects(_ key: String) throws -> [JSONObject] {
        guard let v = array(key) else { throw JSONError.missing(key) }
        return try v.map { guard let o = $0.objectValue else { throw JSONError.missing(key) }; return o }
    }
    public func reqObject(_ key: String) throws -> JSONObject {
        guard let v = object(key) else { throw JSONError.missing(key) }
        return v
    }
}

public enum JSONError: Error, Equatable {
    case syntax(Int)
    case missing(String)
}

// MARK: - Parsing

extension JSON {
    public static func parse(_ data: Data) throws -> JSON {
        var p = Parser(bytes: [UInt8](data))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.i == p.bytes.count else { throw JSONError.syntax(p.i) }
        return v
    }

    public static func parse(_ text: String) throws -> JSON { try parse(Data(text.utf8)) }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func skipSpace() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        mutating func value() throws -> JSON {
            guard i < bytes.count else { throw JSONError.syntax(i) }
            switch bytes[i] {
            case UInt8(ascii: "{"): return .object(try object())
            case UInt8(ascii: "["): return .array(try array())
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { throw JSONError.syntax(i) }
            i += w.count
        }

        mutating func object() throws -> JSONObject {
            var o = JSONObject()
            i += 1
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return o }
            while true {
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw JSONError.syntax(i) }
                let key = try string()
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw JSONError.syntax(i) }
                i += 1
                skipSpace()
                o[key] = try value()
                skipSpace()
                guard i < bytes.count else { throw JSONError.syntax(i) }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return o }
                throw JSONError.syntax(i)
            }
        }

        mutating func array() throws -> [JSON] {
            var a: [JSON] = []
            i += 1
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return a }
            while true {
                skipSpace()
                a.append(try value())
                skipSpace()
                guard i < bytes.count else { throw JSONError.syntax(i) }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return a }
                throw JSONError.syntax(i)
            }
        }

        mutating func number() throws -> String {
            let start = i
            while i < bytes.count {
                let c = bytes[i]
                let ok = (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
                    || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
                    || c == UInt8(ascii: "e") || c == UInt8(ascii: "E")
                guard ok else { break }
                i += 1
            }
            guard i > start, let text = String(bytes: bytes[start..<i], encoding: .utf8), Double(text) != nil else {
                throw JSONError.syntax(start)
            }
            return text
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= bytes.count, let s = String(bytes: bytes[i..<i + 4], encoding: .ascii), let v = UInt32(s, radix: 16) else {
                throw JSONError.syntax(i)
            }
            i += 4
            return v
        }

        mutating func string() throws -> String {
            i += 1
            var out = [UInt8]()
            while true {
                guard i < bytes.count else { throw JSONError.syntax(i) }
                let c = bytes[i]
                i += 1
                if c == UInt8(ascii: "\"") { break }
                if c != UInt8(ascii: "\\") { out.append(c); continue }
                guard i < bytes.count else { throw JSONError.syntax(i) }
                let e = bytes[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                        i += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            out.append(contentsOf: Array(String(UnicodeScalar(0xFFFD)!).utf8))
                            code = low
                        }
                    }
                    let scalar = UnicodeScalar(code) ?? UnicodeScalar(0xFFFD)!
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: throw JSONError.syntax(i - 1)
                }
            }
            return String(decoding: out, as: UTF8.self)
        }
    }
}

// MARK: - Writing

extension JSON {
    /// Compact text; with [indent] > 0 each member goes on its own line (like org.json `toString(1)`).
    public func text(indent: Int = 0) -> String {
        var out = ""
        write(into: &out, indent: indent, level: 0)
        return out
    }

    public func data(indent: Int = 0) -> Data { Data(text(indent: indent).utf8) }

    private func write(into out: inout String, indent: Int, level: Int) {
        func newline(_ l: Int) {
            guard indent > 0 else { return }
            out += "\n" + String(repeating: " ", count: indent * l)
        }
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): JSON.quote(s, into: &out)
        case .array(let a):
            out += "["
            for (k, v) in a.enumerated() {
                if k > 0 { out += "," }
                newline(level + 1)
                v.write(into: &out, indent: indent, level: level + 1)
            }
            if !a.isEmpty { newline(level) }
            out += "]"
        case .object(let o):
            out += "{"
            for (k, key) in o.keys.enumerated() {
                if k > 0 { out += "," }
                newline(level + 1)
                JSON.quote(key, into: &out)
                out += indent > 0 ? ": " : ":"
                o[key]!.write(into: &out, indent: indent, level: level + 1)
            }
            if !o.keys.isEmpty { newline(level) }
            out += "}"
        }
    }

    private static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 || u.value == 0x2028 || u.value == 0x2029 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}
