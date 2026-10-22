// The JavaScript number conversions the original's code relies on. The port keeps them apart from the algorithm's own
// range limiting (see Heights.swift), because they are different things: `ToUint32` and `ToInt32` truncate toward
// zero and wrap, and storing a number in a `Uint8Array` truncates toward zero and wraps modulo 256. They are specified
// by ECMAScript (ToUint32, ToInt32 and ToUint8 in the abstract operations).

import Foundation

/// JavaScript's number-to-integer conversions, computed on Doubles as the original does.
enum JSNumber {
	private static let twoTo32 = 4294967296.0
	private static let twoTo31 = 2147483648.0

	/// `x >>> 0`: truncate toward zero, then wrap into 0 ..< 2^32. Not finite gives 0.
	static func toUInt32(_ x: Double) -> Double {
		guard x.isFinite else { return 0 }
		var r = x.rounded(.towardZero).truncatingRemainder(dividingBy: twoTo32)
		if r < 0 { r += twoTo32 }
		return r
	}

	/// `x | 0`: truncate toward zero, then wrap into -2^31 ..< 2^31. Not finite gives 0.
	static func toInt32(_ x: Double) -> Int32 {
		let u = toUInt32(x)
		return Int32(truncatingIfNeeded: Int64(u >= twoTo31 ? u - twoTo32 : u))
	}

	/// The value a `Uint8Array` holds after storing `x`: truncate toward zero, then wrap modulo 256. Not finite gives 0.
	static func toUInt8(_ x: Double) -> UInt8 {
		guard x.isFinite else { return 0 }
		var r = x.rounded(.towardZero).truncatingRemainder(dividingBy: 256)
		if r < 0 { r += 256 }
		return UInt8(r)
	}

	/// The value a `Uint16Array` holds after storing `x`: truncate toward zero, then wrap modulo 65536. Not finite gives 0.
	static func toUInt16(_ x: Double) -> UInt16 {
		guard x.isFinite else { return 0 }
		var r = x.rounded(.towardZero).truncatingRemainder(dividingBy: 65536)
		if r < 0 { r += 65536 }
		return UInt16(r)
	}

	/// The value an `Int8Array` holds after storing `x`: truncate toward zero, then wrap modulo 256 into -128 ... 127. Not finite gives 0.
	static func toInt8(_ x: Double) -> Int8 {
		guard x.isFinite else { return 0 }
		var r = x.rounded(.towardZero).truncatingRemainder(dividingBy: 256)
		if r < 0 { r += 256 }
		return Int8(truncatingIfNeeded: Int(r))
	}

	/// `Math.hypot(a, b)` as V8 computes it: the larger magnitude scales both, and the squares are added with Kahan's compensation, so the result
	/// is **not** always the same as `sqrt(a * a + b * b)` (they differ for about a third of random inputs). Infinity wins over not a number.
	static func hypot(_ a: Double, _ b: Double) -> Double {
		let values = [abs(a), abs(b)]
		if values.contains(where: { $0.isInfinite }) { return .infinity }
		if values.contains(where: { $0.isNaN }) { return .nan }
		let largest = max(values[0], values[1])
		if largest == 0 { return 0 }
		var sum = 0.0, compensation = 0.0
		for value in values {
			let n = value / largest
			let summand = n * n - compensation
			let preliminary = sum + summand
			compensation = (preliminary - sum) - summand
			sum = preliminary
		}
		return sum.squareRoot() * largest
	}

	/// `Math.round(x)`: the nearest whole number, with halves rounded toward positive infinity (so -2.5 gives -2, not
	/// -3 as Swift's default rounding would). Not finite is returned as is.
	static func round(_ x: Double) -> Double {
		guard x.isFinite else { return x }
		let floor = x.rounded(.down)
		return x - floor >= 0.5 ? floor + 1 : floor
	}

	/// The original's `rn(v, d)` (numberUtils.ts): round `v` to `d` decimal places, using JavaScript's rounding.
	static func rn(_ v: Double, _ d: Int = 0) -> Double {
		let m = pow(10, Double(d))
		return round(v * m) / m
	}
}
