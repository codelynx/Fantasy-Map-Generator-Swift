// Height conventions of the original (src/utils/heightUtils.ts, numberUtils.ts): a cell's height is a whole number
// from 0 to 100, and 20 is sea level; land is height >= 20.

import Foundation

/// A cell's height: 0 to 100 as the algorithms limit it. Stored as a byte, like the original's `Uint8Array`.
public typealias Height = UInt8

public enum Heights {
	/// Heights below this are water; this and above is land.
	public static let seaLevel: Height = 20
	/// The highest height the algorithms produce.
	public static let maximum: Height = 100

	/// The algorithm's own clamp to 0 ... 100 (the original's `lim`). Not the same as the storage conversion.
	public static func limit(_ value: Double) -> Double {
		min(max(value, 0), 100)
	}

	/// What a byte array holds after the original stores `value` into it: truncation toward zero, wrapping modulo 256.
	/// Apply this exactly where the original assigns into a typed array, and nowhere else.
	public static func stored(_ value: Double) -> Height {
		JSNumber.toUInt8(value)
	}

	public static func isLand(_ height: Height) -> Bool { height >= seaLevel }
	public static func isWater(_ height: Height) -> Bool { height < seaLevel }
}
