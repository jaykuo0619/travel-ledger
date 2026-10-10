import Foundation

/// The amount in TWD, rounded to 2 decimals half-up, exactly like Android's
/// `BigDecimal(amount).multiply(BigDecimal(rate)).setScale(2, HALF_UP)`: the doubles are taken at their exact
/// binary value (1.005 is really 1.00499…), so the result matches the other phone to the cent.
public func toHomeAmount(_ amount: Double, _ rate: Double) -> Double {
    guard amount.isFinite, rate.isFinite else { return 0 }
    if amount == 0 || rate == 0 { return 0 }
    guard let a = exactParts(amount), let b = exactParts(rate) else { return (amount * rate * 100).rounded() / 100 }
    let negative = (amount < 0) != (rate < 0)
    // |amount × rate| × 100 = m × 100 × 2^e
    let (mh, ml) = a.mantissa.multipliedFullWidth(by: b.mantissa)
    let (ph, pl) = ml.multipliedFullWidth(by: 100)
    let n = U128(hi: mh &* 100 &+ ph, lo: pl)
    let e = a.exponent + b.exponent
    let cents: U128
    if e >= 0 {
        // Already a whole number of units: no rounding needed.
        if e >= 14 { return amount * rate }
        cents = n.shiftedLeft(e)
    } else {
        let k = -e
        if k >= 128 { return 0 }
        let q = n.shiftedRight(k)
        let r = n.subtracting(q.shiftedLeft(k))
        let half = U128.one.shiftedLeft(k - 1)
        cents = r.isAtLeast(half) ? q.adding(1) : q
    }
    guard cents.hi == 0 else { return (amount * rate * 100).rounded() / 100 }
    let whole = cents.lo / 100, frac = cents.lo % 100
    let text = "\(negative ? "-" : "")\(whole).\(frac < 10 ? "0" : "")\(frac)"
    return Double(text) ?? 0
}

/// |v| = mantissa × 2^exponent, exactly.
private func exactParts(_ v: Double) -> (mantissa: UInt64, exponent: Int)? {
    let x = abs(v)
    guard x.isNormal else { return nil }
    return (UInt64(1) << 52 | x.significandBitPattern, Int(x.exponent) - 52)
}

private struct U128 {
    var hi: UInt64
    var lo: UInt64
    static let one = U128(hi: 0, lo: 1)

    func shiftedLeft(_ k: Int) -> U128 {
        if k == 0 { return self }
        if k >= 128 { return U128(hi: 0, lo: 0) }
        if k >= 64 { return U128(hi: lo << (k - 64), lo: 0) }
        return U128(hi: hi << k | lo >> (64 - k), lo: lo << k)
    }

    func shiftedRight(_ k: Int) -> U128 {
        if k == 0 { return self }
        if k >= 128 { return U128(hi: 0, lo: 0) }
        if k >= 64 { return U128(hi: 0, lo: hi >> (k - 64)) }
        return U128(hi: hi >> k, lo: lo >> k | hi << (64 - k))
    }

    func subtracting(_ o: U128) -> U128 {
        let (l, borrow) = lo.subtractingReportingOverflow(o.lo)
        return U128(hi: hi &- o.hi &- (borrow ? 1 : 0), lo: l)
    }

    func adding(_ v: UInt64) -> U128 {
        let (l, carry) = lo.addingReportingOverflow(v)
        return U128(hi: hi &+ (carry ? 1 : 0), lo: l)
    }

    func isAtLeast(_ o: U128) -> Bool { hi != o.hi ? hi > o.hi : lo >= o.lo }
}
