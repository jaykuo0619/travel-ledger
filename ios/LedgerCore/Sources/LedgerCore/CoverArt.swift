import Foundation

/// Illustrated cover scenes (logic/CoverArt.kt). Raw values are what the database and files store.
public enum CoverTheme: String, CaseIterable, Sendable {
    case autumn = "AUTUMN", sakura = "SAKURA", snow = "SNOW", beach = "BEACH", food = "FOOD", city = "CITY", generic = "GENERIC"

    public var label: String {
        switch self {
        case .autumn: return "秋楓"
        case .sakura: return "櫻花"
        case .snow: return "雪景"
        case .beach: return "海島"
        case .food: return "美食"
        case .city: return "城市"
        case .generic: return "旅行"
        }
    }

    public static func of(_ name: String?) -> CoverTheme? { name.flatMap(CoverTheme.init(rawValue:)) }
}

/// Landmark silhouettes drawn into the scene.
public enum Landmark: Sendable {
    case seoulTower, tokyoTower, fuji, osakaCastle, pagoda, torii, taipei101, bangkokTemple, marinaBay, eiffel, bigBen, citySkyline
}

public struct CoverSpec: Equatable, Sendable {
    public let theme: CoverTheme
    public let landmarks: [Landmark]
    public init(theme: CoverTheme, landmarks: [Landmark]) { self.theme = theme; self.landmarks = landmarks }
}

/// Picks a cover illustration from the trip name (theme + place) and, failing that, the travel month.
public enum CoverArt {
    private static let themeWords: [(CoverTheme, [String])] = [
        (.autumn, ["楓", "紅葉", "秋"]),
        (.sakura, ["櫻", "桜", "花見", "賞花", "春"]),
        (.snow, ["雪", "滑雪", "冬", "雪祭", "極光"]),
        (.beach, ["海島", "跳島", "海灘", "沙灘", "潛水", "浮潛", "夏日", "度假村", "島"]),
        (.food, ["美食", "吃", "拉麵", "壽司", "燒肉", "夜市", "小吃", "購物", "逛街"]),
    ]

    // First match wins; more specific places go first.
    private static let places: [([String], [Landmark])] = [
        (["北海道", "札幌", "小樽", "函館", "富良野"], [.torii]),
        (["沖繩", "峇里", "巴里", "普吉", "關島", "夏威夷", "長灘", "墾丁", "澎湖", "馬爾地夫", "宿霧", "濟州", "石垣", "宮古"], []),
        (["東京", "淺草", "新宿", "澀谷", "銀座", "橫濱"], [.fuji, .tokyoTower]),
        (["富士", "河口湖", "箱根"], [.fuji]),
        (["大阪", "關西", "環球影城", "神戶"], [.osakaCastle]),
        (["京都", "奈良", "嵐山"], [.pagoda]),
        (["首爾", "韓國", "南韓", "釜山", "仁川"], [.seoulTower]),
        (["台北", "台灣", "臺北", "臺灣"], [.taipei101]),
        (["曼谷", "泰國", "清邁"], [.bangkokTemple]),
        (["新加坡"], [.marinaBay]),
        (["巴黎", "法國"], [.eiffel]),
        (["倫敦", "英國"], [.bigBen]),
        (["香港", "上海", "紐約", "杜拜", "雪梨"], [.citySkyline]),
        (["日本", "九州", "福岡", "名古屋", "金澤", "廣島", "東北", "仙台"], [.torii]),
    ]
    private static let coldPlaces = ["北海道", "札幌", "小樽", "函館", "富良野", "東北", "仙台", "首爾", "韓國", "南韓", "巴黎", "法國", "倫敦", "英國", "歐洲", "瑞士", "冰島", "芬蘭"]
    private static var beachPlaces: [String] { places[1].0 }

    /// [chosen] is a theme picked by hand; it wins over everything the name suggests.
    public static func pick(name: String, start: CivilDate?, chosen: CoverTheme? = nil) -> CoverSpec {
        let landmarks = places.first { words, _ in words.contains { name.contains($0) } }?.1 ?? []
        let keyword = themeWords.first { _, words in words.contains { name.contains($0) } }?.0
        let month = start?.month
        let theme: CoverTheme
        if let chosen { theme = chosen }
        else if let keyword { theme = keyword }
        else if beachPlaces.contains(where: { name.contains($0) }) { theme = .beach }
        else if let m = month, (3...4).contains(m), !landmarks.isEmpty { theme = .sakura }
        else if let m = month, (10...11).contains(m), !landmarks.isEmpty { theme = .autumn }
        else if let m = month, [12, 1, 2].contains(m), coldPlaces.contains(where: { name.contains($0) }) { theme = .snow }
        else if !landmarks.isEmpty { theme = .city }
        else { theme = .generic }
        return CoverSpec(theme: theme, landmarks: theme == .beach ? [] : landmarks)
    }

    public static func pick(name: String, startDay: Int64?, theme: String?) -> CoverSpec {
        pick(name: name, start: startDay.map(CivilDate.init(epochDay:)), chosen: CoverTheme.of(theme))
    }
}

// MARK: - SVG path data

public struct SVGPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func == (a: SVGPoint, b: SVGPoint) -> Bool { abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
}

/// Absolute drawing commands, so the app can turn them into a SwiftUI Path.
public enum SVGCommand: Equatable, Sendable {
    case move(SVGPoint)
    case line(SVGPoint)
    case quad(SVGPoint, SVGPoint)
    case cubic(SVGPoint, SVGPoint, SVGPoint)
    case close
}

/// Parses the path strings the Android covers are drawn with (M L H V C S Q T Z, upper and lower case).
public enum SVGPath {
    public static func parse(_ d: String) -> [SVGCommand] {
        var tokens: [Character] = Array(d)
        var i = 0
        var out: [SVGCommand] = []
        var current = SVGPoint(0, 0), start = SVGPoint(0, 0)
        var lastCubic: SVGPoint?, lastQuad: SVGPoint?
        var command: Character = "M"

        func skipSeparators() {
            while i < tokens.count, tokens[i] == " " || tokens[i] == "," || tokens[i] == "\n" || tokens[i] == "\t" { i += 1 }
        }
        func number() -> Double? {
            skipSeparators()
            var s = ""
            var seenDot = false, seenExp = false
            if i < tokens.count, tokens[i] == "-" || tokens[i] == "+" { s.append(tokens[i]); i += 1 }
            while i < tokens.count {
                let c = tokens[i]
                if c.isNumber { s.append(c); i += 1 }
                else if c == ".", !seenDot, !seenExp { seenDot = true; s.append(c); i += 1 }
                else if (c == "e" || c == "E"), !seenExp, !s.isEmpty { seenExp = true; s.append(c); i += 1
                    if i < tokens.count, tokens[i] == "-" || tokens[i] == "+" { s.append(tokens[i]); i += 1 }
                } else { break }
            }
            return Double(s)
        }
        func point(_ relative: Bool) -> SVGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? SVGPoint(current.x + x, current.y + y) : SVGPoint(x, y)
        }

        tokens = tokens.map { $0 }
        while true {
            skipSeparators()
            guard i < tokens.count else { break }
            if tokens[i].isLetter, tokens[i] != "e", tokens[i] != "E" {
                command = tokens[i]
                i += 1
            } else if command == "M" { command = "L" } else if command == "m" { command = "l" }
            let rel = command.isLowercase
            switch command.uppercased() {
            case "M":
                guard let p = point(rel) else { return out }
                out.append(.move(p)); current = p; start = p
                lastCubic = nil; lastQuad = nil
            case "L":
                guard let p = point(rel) else { return out }
                out.append(.line(p)); current = p
                lastCubic = nil; lastQuad = nil
            case "H":
                guard let x = number() else { return out }
                let p = SVGPoint(rel ? current.x + x : x, current.y)
                out.append(.line(p)); current = p
                lastCubic = nil; lastQuad = nil
            case "V":
                guard let y = number() else { return out }
                let p = SVGPoint(current.x, rel ? current.y + y : y)
                out.append(.line(p)); current = p
                lastCubic = nil; lastQuad = nil
            case "C":
                guard let c1 = point(rel), let c2 = point(rel), let p = point(rel) else { return out }
                out.append(.cubic(c1, c2, p)); current = p; lastCubic = c2; lastQuad = nil
            case "S":
                let c1 = lastCubic.map { SVGPoint(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                guard let c2 = point(rel), let p = point(rel) else { return out }
                out.append(.cubic(c1, c2, p)); current = p; lastCubic = c2; lastQuad = nil
            case "Q":
                guard let c = point(rel), let p = point(rel) else { return out }
                out.append(.quad(c, p)); current = p; lastQuad = c; lastCubic = nil
            case "T":
                let c = lastQuad.map { SVGPoint(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current
                guard let p = point(rel) else { return out }
                out.append(.quad(c, p)); current = p; lastQuad = c; lastCubic = nil
            case "Z":
                out.append(.close); current = start
                lastCubic = nil; lastQuad = nil
                command = rel ? "m" : "M" // numbers after z start a new subpath
                skipSeparators()
                if i < tokens.count, !(tokens[i].isLetter) { continue } else { continue }
            default:
                return out
            }
        }
        return out
    }
}
