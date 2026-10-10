import Foundation

/// A web address or phone number found in free text, and the uri that opens it. Offsets are UTF-16, like NSString.
public struct FoundLink: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let text: String
    public let uri: String
    public var isPhone: Bool { uri.hasPrefix("tel:") }
}

/// Finds links in notes, addresses and booking details so they can be tapped (logic/Links.kt).
public enum Links {
    // Stops at whitespace, brackets and Chinese/Japanese/Korean text, which often follows a link without a space.
    // (Java's \\b sees a boundary after a CJK character; ICU's does not, hence the ASCII look-behind.)
    private static let url = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])(?:https?://|www\.)[^\s()<>"⺀-鿿가-힯＀-￯]+"#, options: [.caseInsensitive])

    // Starts with + or 0 (local and international numbers), 8–15 digits with optional spaces or dashes.
    // Dates (2026-10-22), times and prices don't start that way.
    private static let phone = try! NSRegularExpression(pattern: #"(?<![\w/.])(?:\+\d{1,3}[\s-]?|0)\d(?:[\s-]?\d){6,13}(?![\w/])"#)

    private static let trailing = Set(".,:;!?)]}'\"")

    public static func find(_ text: String) -> [FoundLink] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [FoundLink] = []
        for m in url.matches(in: text, range: whole) {
            var raw = ns.substring(with: m.range)
            while let last = raw.last, trailing.contains(last) { raw.removeLast() }
            let uri = raw.lowercased().hasPrefix("www.") ? "https://" + raw : raw
            found.append(FoundLink(start: m.range.location, end: m.range.location + (raw as NSString).length, text: raw, uri: uri))
        }
        for m in phone.matches(in: text, range: whole) {
            let first = m.range.location, last = m.range.location + m.range.length - 1
            if found.contains(where: { first < $0.end && last >= $0.start }) { continue } // part of a URL
            let value = ns.substring(with: m.range)
            let digits = value.filter { ("0" ... "9").contains($0) || $0 == "+" }
            if digits.filter({ $0 != "+" }).count < 8 { continue }
            found.append(FoundLink(start: first, end: last + 1, text: value, uri: "tel:" + digits))
        }
        return found.sorted { $0.start < $1.start }
    }

    /// What the button for a link says (ui/LinkText.kt).
    public static func label(_ link: FoundLink) -> String {
        if link.isPhone { return "撥打 \(link.text)" }
        guard var host = URLComponents(string: link.uri)?.host else { return "開啟連結" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("maps.") || host.hasPrefix("goo.gl") || host == "maps.app.goo.gl" { return "開啟地圖" }
        return "開啟 \(host)"
    }
}

/// Where the 導航 button goes (ui/MapLauncher.kt). The first address that some installed app opens is used.
public enum MapLinks {
    /// What to search for: the address if one was written, otherwise the place name (a link is opened as is).
    public static func query(title: String, location: String) -> String {
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !location.hasPrefix("http") ? location : title
    }

    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The address for [app]; nil for Apple Maps (the fallback every iPhone has).
    public static func url(_ app: NavApp?, title: String, location: String, bundleId: String) -> String {
        let q = query(title: title, location: location)
        let link = location.hasPrefix("http") ? location : nil
        switch app {
        case .google?: return link ?? "comgooglemaps://?daddr=" + enc(q)
        case .naver?: return "nmap://search?query=\(enc(q))&appname=\(bundleId)"
        case .kakao?: return "kakaomap://search?q=\(enc(q))"
        case nil:
            let both = [title, location].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
            return link ?? "http://maps.apple.com/?q=" + enc(both)
        }
    }

    /// Google Maps in the browser, when the Google Maps app isn't installed.
    public static func googleWeb(title: String, location: String) -> String {
        location.hasPrefix("http") ? location : "https://www.google.com/maps/dir/?api=1&destination=" + enc(query(title: title, location: location))
    }
}
