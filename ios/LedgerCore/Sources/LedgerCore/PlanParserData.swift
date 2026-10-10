import Foundation

// Generated from app/src/main/java/com/archiekuo/travelledger/logic/PlanParser.kt by copying its patterns and
// word lists character for character (they mix full-width and ASCII punctuation). Change them there first.
enum PlanParserData {
    static let url = #"https?://\S+"#
    static let bracketTag = #"[【\[(（〔]\s*([^】\])）〕]{1,4})\s*[】\])）〕]\s*[:：]?"#
    static let prefixTag = #"^\s*(交通|移動|住宿|購物|景點|美食|餐廳|早餐|午餐|晚餐)\s*[:：]"#
    static let travelVerbs = #"^(?:搭乘|搭|坐|轉乘|轉搭|步行|走路|前往|移動|開車|騎)|(?:搭乘|轉乘|步行約|走路約|車程|下車|上車|直達)"#
    static let lineBullet = #"^\s*(?:[-*•・●○◎▶►]|\d{1,3}[.、)):]|[(\(]\d{1,3}[)\)])\s*"#
    static let headerLine = #"^\s*(?:day\s*\d+|d\d+|第\s*[一二三四五六七八九十\d]+\s*天)\s*[:：]?\s*$"#
    static let clock = #"(?<!\d)([01]?\d|2[0-3])\s*[:：]\s*([0-5]\d)(?!\d)"#
    static let hourWord = #"(?<!\d)([01]?\d|2[0-3])\s*點\s*(半|\d{1,2}\s*分)?"#
    static let separators = #"\s*(?:→|➡|->|⇒|>)\s*"#
    static let stepBullet = #"^\s*(?:[-*•・●○◎▶►✓✔☐□]|\d{1,3}[.、)):]|[(\(]\d{1,3}[)\)])\s*"#
    static let lineTrim = "-—:: "
    static let stepTrim = "-—:：,，、～~。 "
    /// Keyword → category name. First match wins, so lodging ("飯店") goes before food ("飯").
    static let hints: [(String, [String])] = [
        ("住宿", ["飯店", "酒店", "旅館", "民宿", "ホテル", "Hotel", "hotel", "Inn", "check-in", "入住", "退房", "住宿"]),
        ("交通", ["機場", "空港", "車站", "駅", "新幹線", "JR", "巴士", "バス", "租車", "Airport", "Station", "地鐵", "捷運", "KTX", "高鐵", "計程車", "轉乘", "接駁", "AREX"]),
        ("吃", ["早餐", "午餐", "晚餐", "宵夜", "下午茶", "拉麵", "ラーメン", "壽司", "寿司", "燒肉", "焼肉", "烤肉", "炸雞", "蔘雞湯", "部隊鍋", "冷麵", "火鍋", "牛舌", "餃子", "小吃", "餐", "食堂", "居酒屋", "咖哩", "カレー", "麵", "うどん", "そば", "丼", "飯", "料理", "甜點", "スイーツ", "パン", "麵包", "Cafe", "cafe", "咖啡", "茶", "Restaurant", "restaurant"]),
        ("購物", ["百貨", "商場", "Outlet", "outlet", "唐吉訶德", "ドン・キホーテ", "藥妝", "超市", "市場", "商店街", "Mall", "購物", "免稅", "伴手禮", "Olive Young"]),
        ("景點", ["寺", "神社", "宮", "城", "塔", "公園", "博物館", "美術館", "展望", "水族館", "動物園", "樂園", "ランド", "山", "海", "湖", "島", "橋", "老街", "夜市", "壁畫村", "韓屋", "韓服", "Temple", "Park", "Museum", "Tower", "Shrine", "Palace"]),
    ]
    static let tagNames: [String: String] = [
        "交通": "交通",
        "移動": "交通",
        "吃": "吃",
        "餐": "吃",
        "美食": "吃",
        "餐廳": "吃",
        "早餐": "吃",
        "午餐": "吃",
        "晚餐": "吃",
        "住宿": "住宿",
        "住": "住宿",
        "飯店": "住宿",
        "購物": "購物",
        "買": "購物",
        "逛街": "購物",
        "景點": "景點",
        "玩": "景點",
        "參觀": "景點",
    ]
    static let emojiTags: [(String, [String])] = [
        ("交通", ["🚇", "🚌", "🚕", "🚆", "🚄", "✈", "🚶", "🚗", "🚉"]),
        ("吃", ["🍜", "🍣", "🍖", "🍗", "🍲", "🍚", "☕", "🍰", "🍺", "🍴", "🍽"]),
        ("住宿", ["🏨", "🛏"]),
        ("購物", ["🛍", "🛒"]),
        ("景點", ["📷", "📸", "🏯", "⛩", "🏞"]),
    ]
    /// Period words and the time they stand for when no clock time is written.
    static let periods: [(String, Int)] = [("早上", 9 * 60), ("上午", 9 * 60), ("早餐", 8 * 60), ("中午", 12 * 60), ("午餐", 12 * 60), ("下午茶", 15 * 60), ("下午", 14 * 60), ("傍晚", 17 * 60), ("晚餐", 18 * 60), ("晚上", 18 * 60), ("宵夜", 21 * 60)]
}
