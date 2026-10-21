// Ported from fdlibm 5.3 (`e_atan2.c`, `s_atan.c`, `s_sin.c`, `s_cos.c`, `k_sin.c`, `k_cos.c`, `e_rem_pio2.c`), © 1993 Sun Microsystems, Inc.
// ("Permission to use, copy, modify, and distribute this software is freely granted, provided that this notice is preserved"; the notice is in
// ACKNOWLEDGEMENTS.md), in the form V8 uses for `Math.sin`, `Math.cos` and `Math.atan2` (`src/base/ieee754.cc`).
//
// Why this exists: the original's river geometry calls `Math.sin`, `Math.cos` and `Math.atan2`, which V8 computes with its own fdlibm-derived
// code. With the system math library the river points differed from the captured ones in their last digits (observed: 26 of 600 meandered
// paths), so the geometry is compared exactly only with these. Constants are written as their exact bit patterns.
//
// **Source.** Written from fdlibm 5.3 as it is generally known and as V8's `ieee754.cc` derives from it; **no copy of a V8 source revision was
// available to read, so this is not a transcription of a named V8 revision.** It was checked only against outputs: the expressions below match
// the results of the captured build (recorded in `provenance.json`: Node, V8, architecture, platform) on every sampled argument.
//
// **Fused multiply-adds.** The plain formulas did not reproduce the captured results (about 2 per cent of arguments differed), and writing
// the products that feed an addition or subtraction as `fma` did. That is how these expressions are written, where the samples require it.
// **This matches the captured build and the samples; it is not a claim about any other build or compiler.**

import Foundation

enum FdLibm {
	private static func d(_ bits: UInt64) -> Double { Double(bitPattern: bits) }
	private static func high(_ x: Double) -> Int32 { Int32(truncatingIfNeeded: x.bitPattern >> 32) }
	private static func low(_ x: Double) -> UInt32 { UInt32(truncatingIfNeeded: x.bitPattern) }
	private static func withHigh(_ x: Double, _ hi: Int32) -> Double { Double(bitPattern: (UInt64(UInt32(bitPattern: hi)) << 32) | (x.bitPattern & 0xFFFF_FFFF)) }

	// MARK: kernels

	private static let S1 = d(0xBFC5555555555549), S2 = d(0x3F8111111110F8A6), S3 = d(0xBF2A01A019C161D5)
	private static let S4 = d(0x3EC71DE357B1FE7D), S5 = d(0xBE5AE5E68A2B9CEB), S6 = d(0x3DE5D93A5ACFD57C)
	private static let C1 = d(0x3FA555555555554C), C2 = d(0xBF56C16C16C15177), C3 = d(0x3EFA01A019CB1590)
	private static let C4 = d(0xBE927E4F809C52AD), C5 = d(0x3E21EE9EBDB4B1C4), C6 = d(0xBDA8FAE9BE8838D4)

	private static func kernelSin(_ x: Double, _ y: Double, _ iy: Int) -> Double {
		let ix = high(x) & 0x7fffffff
		if ix < 0x3e400000 { if Int(x) == 0 { return x } } // |x| < 2**-27
		let z = x * x
		let v = z * x
		let r = fma(z, fma(z, fma(z, fma(z, S6, S5), S4), S3), S2)
		if iy == 0 { return fma(v, fma(z, r, S1), x) }
		let w = fma(0.5, y, -(v * r)) // half * y - v * r
		let u = fma(z, w, -y) // z * w - y
		return x - fma(-v, S1, u) // x - (u - v * S1)
	}

	private static func kernelCos(_ x: Double, _ y: Double) -> Double {
		let ix = high(x) & 0x7fffffff
		if ix < 0x3e400000 { if Int(x) == 0 { return 1 } } // |x| < 2**-27
		let z = x * x
		let r = z * fma(z, fma(z, fma(z, fma(z, fma(z, C6, C5), C4), C3), C2), C1)
		let q = fma(z, r, -(x * y)) // z * r - x * y
		if ix < 0x3FD33333 { return 1 - fma(0.5, z, -q) } // |x| < 0.3
		let qx: Double
		if ix > 0x3fe90000 { qx = 0.28125 } // x > 0.78125
		else { qx = withHigh(0, ix - 0x00200000) } // x/4
		let hz = fma(0.5, z, -qx)
		let a = 1 - qx
		return a - (hz - q)
	}

	// MARK: argument reduction (the medium sizes: |x| up to 2^19 * pi/2, which covers every angle the geometry uses)

	private static let npio2hw: [Int32] = [
		0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C,
		0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x404147AC,
		0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB
	]
	private static let invpio2 = d(0x3FE45F306DC9C883)
	private static let pio2_1 = d(0x3FF921FB54400000), pio2_1t = d(0x3DD0B4611A626331)
	private static let pio2_2 = d(0x3DD0B4611A600000), pio2_2t = d(0x3BA3198A2E037073)
	private static let pio2_3 = d(0x3BA3198A2E000000), pio2_3t = d(0x397B839A252049C1)

	/// `__ieee754_rem_pio2(x, y)` for finite `x` below 2^19 * pi/2 in size: returns `n` and `y0`, `y1` with `x = n * pi/2 + y0 + y1`.
	/// (Beyond that the original's own routine needs the large-argument reduction, which is not ported: **never reached by the geometry**,
	/// whose arguments are angles from `atan2`; the caller falls back to the system function there.)
	private static func remPio2(_ x: Double) -> (n: Int, y0: Double, y1: Double)? {
		let hx = high(x)
		let ix = hx & 0x7fffffff
		if ix <= 0x3fe921fb { return (0, x, 0) } // |x| ~<= pi/4, no need for reduction
		if ix < 0x4002d97c { // |x| < 3pi/4, special case with n = +-1
			if hx > 0 {
				var z = x - pio2_1
				let y0: Double, y1: Double
				if ix != 0x3ff921fb { // 33+53 bit pi is good enough
					y0 = z - pio2_1t
					y1 = (z - y0) - pio2_1t
				} else { // near pi/2, use 33+33+53 bit pi
					z -= pio2_2
					y0 = z - pio2_2t
					y1 = (z - y0) - pio2_2t
				}
				return (1, y0, y1)
			} else {
				var z = x + pio2_1
				let y0: Double, y1: Double
				if ix != 0x3ff921fb {
					y0 = z + pio2_1t
					y1 = (z - y0) + pio2_1t
				} else {
					z += pio2_2
					y0 = z + pio2_2t
					y1 = (z - y0) + pio2_2t
				}
				return (-1, y0, y1)
			}
		}
		if ix <= 0x413921fb { // |x| ~<= 2^19 * (pi/2), medium size
			var t = abs(x)
			let n = Int32(fma(t, invpio2, 0.5))
			let fn = Double(n)
			var r = fma(-fn, pio2_1, t)
			var w = fn * pio2_1t // 1st round good to 85 bit
			var y0: Double
			if n < 32 && ix != npio2hw[Int(n) - 1] {
				y0 = r - w // quick check no cancellation
			} else {
				let j = ix >> 20
				y0 = r - w
				var i = j - ((high(y0) >> 20) & 0x7ff)
				if i > 16 { // 2nd iteration needed, good to 118
					t = r
					w = fn * pio2_2
					r = t - w
					w = fma(fn, pio2_2t, -((t - r) - w))
					y0 = r - w
					i = j - ((high(y0) >> 20) & 0x7ff)
					if i > 49 { // 3rd iteration need, 151 bits acc
						t = r // will cover all possible cases
						w = fn * pio2_3
						r = t - w
						w = fma(fn, pio2_3t, -((t - r) - w))
						y0 = r - w
					}
				}
			}
			let y1 = (r - y0) - w
			return hx < 0 ? (-Int(n), -y0, -y1) : (Int(n), y0, y1)
		}
		return nil
	}

	// MARK: sin, cos

	static func sin(_ x: Double) -> Double {
		let ix = high(x) & 0x7fffffff
		if ix <= 0x3fe921fb { return kernelSin(x, 0, 0) }
		if ix >= 0x7ff00000 { return x - x }
		guard let (n, y0, y1) = remPio2(x) else { return Foundation.sin(x) }
		switch n & 3 {
		case 0: return kernelSin(y0, y1, 1)
		case 1: return kernelCos(y0, y1)
		case 2: return -kernelSin(y0, y1, 1)
		default: return -kernelCos(y0, y1)
		}
	}

	static func cos(_ x: Double) -> Double {
		let ix = high(x) & 0x7fffffff
		if ix <= 0x3fe921fb { return kernelCos(x, 0) }
		if ix >= 0x7ff00000 { return x - x }
		guard let (n, y0, y1) = remPio2(x) else { return Foundation.cos(x) }
		switch n & 3 {
		case 0: return kernelCos(y0, y1)
		case 1: return -kernelSin(y0, y1, 1)
		case 2: return -kernelCos(y0, y1)
		default: return kernelSin(y0, y1, 1)
		}
	}

	// MARK: atan, atan2

	private static let atanhi = [d(0x3FDDAC670561BB4F), d(0x3FE921FB54442D18), d(0x3FEF730BD281F69B), d(0x3FF921FB54442D18)]
	private static let atanlo = [d(0x3C7A2B7F222F65E2), d(0x3C81A62633145C07), d(0x3C7007887AF0CBBD), d(0x3C91A62633145C07)]
	private static let aT = [
		d(0x3FD555555555550D), d(0xBFC999999998EBC4), d(0x3FC24924920083FF), d(0xBFBC71C6FE231671), d(0x3FB745CDC54C206E), d(0xBFB3B0F2AF749A6D),
		d(0x3FB10D66A0D03D51), d(0xBFADDE2D52DEFD9A), d(0x3FA97B4B24760DEB), d(0xBFA2B4442C6A6C2F), d(0x3F90AD3AE322DA11)
	]

	static func atan(_ input: Double) -> Double {
		var x = input
		let hx = high(x)
		let ix = hx & 0x7fffffff
		let id: Int
		if ix >= 0x44100000 { // |x| >= 2^66
			if ix > 0x7ff00000 || (ix == 0x7ff00000 && low(x) != 0) { return x + x } // NaN
			return hx > 0 ? atanhi[3] + atanlo[3] : -atanhi[3] - atanlo[3]
		}
		if ix < 0x3fdc0000 { // |x| < 0.4375
			if ix < 0x3e200000 { if 1e300 + x > 1 { return x } } // |x| < 2^-29
			id = -1
		} else {
			x = abs(x)
			if ix < 0x3ff30000 { // |x| < 1.1875
				if ix < 0x3fe60000 { // 7/16 <= |x| < 11/16
					id = 0
					x = fma(2.0, x, -1) / (2.0 + x)
				} else { // 11/16 <= |x| < 19/16
					id = 1
					x = (x - 1) / (x + 1)
				}
			} else {
				if ix < 0x40038000 { // |x| < 2.4375
					id = 2
					x = (x - 1.5) / fma(1.5, x, 1)
				} else { // 2.4375 <= |x| < 2^66
					id = 3
					x = -1.0 / x
				}
			}
		}
		// end of argument reduction
		let z = x * x
		let w = z * z
		// break sum from i=0 to 10 aT[i]z**(i+1) into odd and even poly
		let s1 = z * fma(w, fma(w, fma(w, fma(w, fma(w, aT[10], aT[8]), aT[6]), aT[4]), aT[2]), aT[0])
		let s2 = w * fma(w, fma(w, fma(w, fma(w, aT[9], aT[7]), aT[5]), aT[3]), aT[1])
		if id < 0 { return fma(-x, s1 + s2, x) }
		let result = atanhi[id] - (fma(x, s1 + s2, -atanlo[id]) - x)
		return hx < 0 ? -result : result
	}

	private static let tiny = 1.0e-300
	private static let piO4 = d(0x3FE921FB54442D18), piO2 = d(0x3FF921FB54442D18), pi = d(0x400921FB54442D18), piLo = d(0x3CA1A62633145C07)

	static func atan2(_ y: Double, _ x: Double) -> Double {
		let hx = high(x), lx = low(x)
		let ix = hx & 0x7fffffff
		let hy = high(y), ly = low(y)
		let iy = hy & 0x7fffffff
		// x or y is NaN
		if x.isNaN || y.isNaN { return x + y }
		if hx == 0x3ff00000 && lx == 0 { return atan(y) } // x = 1.0
		let m = Int(((hy >> 31) & 1) | ((hx >> 30) & 2)) // 2 * sign(x) + sign(y)

		// when y = 0
		if iy == 0 && ly == 0 {
			switch m {
			case 0, 1: return y // atan(+-0, +anything) = +-0
			case 2: return pi + tiny // atan(+0, -anything) = pi
			default: return -pi - tiny // atan(-0, -anything) = -pi
			}
		}
		// when x = 0
		if ix == 0 && lx == 0 { return hy < 0 ? -piO2 - tiny : piO2 + tiny }

		// when x is INF
		if ix == 0x7ff00000 {
			if iy == 0x7ff00000 {
				switch m {
				case 0: return piO4 + tiny // atan(+INF, +INF)
				case 1: return -piO4 - tiny // atan(-INF, +INF)
				case 2: return 3.0 * piO4 + tiny // atan(+INF, -INF)
				default: return -3.0 * piO4 - tiny // atan(-INF, -INF)
				}
			} else {
				switch m {
				case 0: return 0 // atan(+..., +INF)
				case 1: return -0.0 // atan(-..., +INF)
				case 2: return pi + tiny // atan(+..., -INF)
				default: return -pi - tiny // atan(-..., -INF)
				}
			}
		}
		// when y is INF
		if iy == 0x7ff00000 { return hy < 0 ? -piO2 - tiny : piO2 + tiny }

		// compute y/x
		let k = (iy - ix) >> 20
		var z: Double
		if k > 60 { z = piO2 + 0.5 * piLo } // |y/x| > 2**60
		else if hx < 0 && k < -60 { z = 0.0 } // |y|/x < -2**60
		else { z = atan(abs(y / x)) } // safe to do y/x
		switch m {
		case 0: return z // atan(+, +)
		case 1: return -z // atan(-, +): the sign bit flipped
		case 2: return pi - (z - piLo) // atan(+, -)
		default: return (z - piLo) - pi // atan(-, -)
		}
	}
}
