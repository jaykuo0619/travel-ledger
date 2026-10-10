import Foundation

/// Reference exchange rates fetched from the network, only ever used to prefill a rate the user can change.
/// Stored as "units of the currency per 1 TWD", the way the source publishes them.
public struct ReferenceRates: Codable, Equatable, Sendable {
    public var perHome: [String: Double]
    /// When they were fetched (epoch millis).
    public var fetchedAt: Int64

    public init(perHome: [String: Double], fetchedAt: Int64) {
        self.perHome = perHome
        self.fetchedAt = fetchedAt
    }

    /// Reads the answer of https://open.er-api.com/v6/latest/TWD ({"result":"success","rates":{"JPY":4.6,…}}).
    public static func parse(_ data: Data, now: Int64 = nowMillis()) -> ReferenceRates? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["result"] as? String == "success",
              let rates = root["rates"] as? [String: Any] else { return nil }
        var out: [String: Double] = [:]
        for (code, value) in rates {
            if let n = value as? NSNumber, n.doubleValue > 0, n.doubleValue.isFinite { out[code.uppercased()] = n.doubleValue }
        }
        return out.isEmpty ? nil : ReferenceRates(perHome: out, fetchedAt: now)
    }

    /// 1 unit of [currency] in TWD, as text for a rate field: four significant digits ("0.02345", "0.2134", "32.15").
    public func suggestion(_ currency: String) -> String? {
        guard currency != homeCurrency, let per = perHome[currency.uppercased()], per > 0 else { return nil }
        let rate = 1 / per
        guard rate.isFinite, rate > 0 else { return nil }
        let magnitude = Int(floor(log10(rate)))
        let decimals = max(0, min(8, 3 - magnitude))
        let scale = pow(10.0, Double(decimals))
        return fmtNumber((rate * scale).rounded() / scale)
    }

    /// Older than a day: worth fetching again.
    public func isStale(now: Int64 = nowMillis()) -> Bool { now - fetchedAt > 24 * 60 * 60 * 1000 }
}
