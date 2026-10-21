// Ported from the npm package `alea` 1.0.1 (alea.js), which wraps Johannes Baagøe's Alea 0.9 generator and its Mash
// string hash. alea is MIT licensed, © 2010 Johannes Baagøe; the notice is in ACKNOWLEDGEMENTS.md.
//
// The arithmetic follows the original's JavaScript number semantics (all values are Doubles, `>>> 0` and `| 0` are
// reproduced by `toUInt32` and `toInt32`), because the port aims to give the same numbers for the same seed.

import Foundation

/// A seeded random number generator that reproduces the original's `Alea(seed)`.
///
/// Its state is local to the value, with no global generator, so separate generations can run concurrently.
public struct Alea: Sendable {
	private var s0: Double
	private var s1: Double
	private var s2: Double
	private var c: Double

	/// Seeds the generator from a string, as the original's `Alea(seed)` does. The string is hashed by its UTF-16
	/// code units, as JavaScript's `charCodeAt` reads it, so non-ASCII seeds match the original.
	public init(seed: String) {
		var mash = Mash()
		var s0 = mash.hash(" ")
		var s1 = mash.hash(" ")
		var s2 = mash.hash(" ")
		s0 -= mash.hash(seed)
		if s0 < 0 { s0 += 1 }
		s1 -= mash.hash(seed)
		if s1 < 0 { s1 += 1 }
		s2 -= mash.hash(seed)
		if s2 < 0 { s2 += 1 }
		self.s0 = s0
		self.s1 = s1
		self.s2 = s2
		self.c = 1
	}

	/// The next value in [0, 1), the original's `Math.random()` once it was replaced by `Alea(seed)`.
	public mutating func next() -> Double {
		let t = 2091639 * s0 + c * 2.3283064365386963e-10 // 2^-32
		s0 = s1
		s1 = s2
		c = Double(JSNumber.toInt32(t))
		s2 = t - c
		return s2
	}

	/// The generator's four state numbers, as the original's `exportState()` returns them.
	public var state: [Double] { [s0, s1, s2, c] }

	/// Alea's string hash, 0.9.
	private struct Mash {
		private var n: Double = 0xefc8249d

		mutating func hash(_ data: String) -> Double {
			for unit in data.utf16 {
				n += Double(unit)
				var h = 0.02519603282416938 * n
				n = JSNumber.toUInt32(h)
				h -= n
				h *= n
				n = JSNumber.toUInt32(h)
				h -= n
				n += h * 0x100000000 // 2^32
			}
			return JSNumber.toUInt32(n) * 2.3283064365386963e-10 // 2^-32
		}
	}
}
