// The small pieces of the original's utilities that the height steps rely on (src/utils/probabilityUtils.ts and
// numberUtils.ts, read at commit 8936c9c): `rand`, `P`, `getNumberInRange`, and the JavaScript text-to-number conversions
// they use. Ported with the original's arithmetic and the original's order of random draws.

import Foundation

extension Alea {
	/// The original's `rand(min, max)`: `Math.floor(Math.random() * (max - min + 1)) + min`. One draw.
	mutating func rand(_ min: Double, _ max: Double) -> Double {
		(next() * (max - min + 1)).rounded(.down) + min
	}

	/// The original's `P(probability)`: true if at least 1, false if at most 0, without drawing; otherwise one draw.
	mutating func p(_ probability: Double) -> Bool {
		if probability >= 1 { return true }
		if probability <= 0 { return false }
		return next() < probability
	}
}

/// JavaScript's string-to-number conversions, for the cases the height steps use.
enum JSParsing {
	/// `+string`: a JavaScript Number from text. Empty or blank text is 0; a decimal literal is its value; `Infinity`;
	/// anything else (including hexadecimal literals, which the original's templates never use) is NaN.
	static func number(_ text: String) -> Double {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty { return 0 }
		switch trimmed {
		case "Infinity", "+Infinity": return .infinity
		case "-Infinity": return -.infinity
		default: break
		}
		guard trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return .nan }
		return Double(trimmed) ?? .nan
	}

	/// `parseFloat(text)`: the longest leading decimal literal, or NaN.
	static func parseFloat(_ text: String) -> Double {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let match = trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?"#, options: .regularExpression) else {
			if trimmed.hasPrefix("Infinity") || trimmed.hasPrefix("+Infinity") { return .infinity }
			if trimmed.hasPrefix("-Infinity") { return -.infinity }
			return .nan
		}
		return Double(trimmed[match]) ?? .nan
	}

	/// `parseInt(text, 10)`: the longest leading integer, or NaN.
	static func parseInt(_ text: String) -> Double {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let match = trimmed.range(of: #"^[+-]?\d+"#, options: .regularExpression) else { return .nan }
		return Double(trimmed[match]) ?? .nan
	}

	/// The original's `getNumberInRange(r)`: a whole number with a fractional part taken as a chance of one more, or a
	/// number drawn from `min-max`. Returns 0 for text it cannot parse (the original logs and returns 0).
	static func numberInRange(_ text: String, random: inout Alea) -> Double {
		let value = number(text)
		if !value.isNaN {
			let whole = Double(JSNumber.toInt32(value)) // `~~r`
			return whole + (random.p(value - whole) ? 1 : 0)
		}
		var r = text
		let sign: Double = r.first == "-" ? -1 : 1
		if let first = r.first, number(String(first)).isNaN { r = String(r.dropFirst()) } // `Number.isNaN(+r[0])`
		guard r.contains("-") else { return 0 }
		let range = r.components(separatedBy: "-")
		let count = random.rand(parseFloat(range[0]) * sign, parseFloat(range[1]))
		if count.isNaN || count < 0 { return 0 }
		return count
	}
}
