// Ported from the npm package `robust-predicates` 3.0.3 (esm/orient2d.js and the helpers in esm/util.js it uses), by
// Vladimir Agafonkin: Unlicense (public domain); the notice is in ACKNOWLEDGEMENTS.md. Only `orient2d` and the
// expansion helpers it needs are ported (about 320 lines in the original); the library's other predicates are not used
// by Delaunator and are not ported.
//
// This is Jonathan Shewchuk's adaptive-precision orientation test. The arithmetic must stay exactly as written: each
// expression is evaluated in the same order as the original's JavaScript, and nothing here may be reassociated or fused.

import Foundation

/// The adaptive-precision geometric tests Delaunator relies on.
public enum RobustPredicates {
	private static let epsilon = 1.1102230246251565e-16
	private static let splitter = 134217729.0
	private static let resulterrbound = (3 + 8 * epsilon) * epsilon
	private static let ccwerrboundA = (3 + 16 * epsilon) * epsilon
	private static let ccwerrboundB = (2 + 12 * epsilon) * epsilon
	private static let ccwerrboundC = (9 + 64 * epsilon) * epsilon * epsilon

	/// Which side of the line through `a` and `b` the point `c` lies on: positive when `a`, `b`, `c` turn
	/// counter-clockwise in the original's convention (the sign Delaunator reads), negative clockwise, zero collinear,
	/// computed exactly enough that the sign is right even for nearly collinear points.
	public static func orient2d(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double) -> Double {
		orient2dTraced(ax, ay, bx, by, cx, cy).value
	}

	/// `orient2d` and which of its return points produced the value, so tests can show the exact-arithmetic branches are
	/// reached: 0 the fast filter; 1 after the first exact estimate; 2 the error tails are all zero; 3 after the first
	/// correction; 4 the full exact sum.
	static func orient2dTraced(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double) -> (value: Double, branch: Int) {
		let detleft = (ay - cy) * (bx - cx)
		let detright = (ax - cx) * (by - cy)
		let det = detleft - detright

		let detsum = abs(detleft + detright)
		if abs(det) >= ccwerrboundA * detsum { return (det, 0) }

		let adapted = orient2dAdapt(ax, ay, bx, by, cx, cy, detsum)
		return (-adapted.value, adapted.branch)
	}

	/// The expansion helper's reads past the end of an array are `undefined` in JavaScript and never used; here they give 0.
	@inline(__always) private static func at(_ a: [Double], _ i: Int) -> Double { i < a.count ? a[i] : 0 }

	/// `estimate` from the original's util.js.
	private static func estimate(_ elen: Int, _ e: [Double]) -> Double {
		var Q = e[0]
		var i = 1
		while i < elen { Q += e[i]; i += 1 }
		return Q
	}

	/// `sum` (fast_expansion_sum_zeroelim) from the original's util.js.
	private static func sum(_ elen: Int, _ e: [Double], _ flen: Int, _ f: [Double], _ h: inout [Double]) -> Int {
		var Q: Double
		var Qnew: Double
		var hh: Double
		var bvirt: Double
		var enow = e[0]
		var fnow = f[0]
		var eindex = 0
		var findex = 0
		if (fnow > enow) == (fnow > -enow) {
			Q = enow
			eindex += 1
			enow = at(e, eindex)
		} else {
			Q = fnow
			findex += 1
			fnow = at(f, findex)
		}
		var hindex = 0
		if eindex < elen && findex < flen {
			if (fnow > enow) == (fnow > -enow) {
				Qnew = enow + Q
				hh = Q - (Qnew - enow)
				eindex += 1
				enow = at(e, eindex)
			} else {
				Qnew = fnow + Q
				hh = Q - (Qnew - fnow)
				findex += 1
				fnow = at(f, findex)
			}
			Q = Qnew
			if hh != 0 {
				h[hindex] = hh
				hindex += 1
			}
			while eindex < elen && findex < flen {
				if (fnow > enow) == (fnow > -enow) {
					Qnew = Q + enow
					bvirt = Qnew - Q
					hh = Q - (Qnew - bvirt) + (enow - bvirt)
					eindex += 1
					enow = at(e, eindex)
				} else {
					Qnew = Q + fnow
					bvirt = Qnew - Q
					hh = Q - (Qnew - bvirt) + (fnow - bvirt)
					findex += 1
					fnow = at(f, findex)
				}
				Q = Qnew
				if hh != 0 {
					h[hindex] = hh
					hindex += 1
				}
			}
		}
		while eindex < elen {
			Qnew = Q + enow
			bvirt = Qnew - Q
			hh = Q - (Qnew - bvirt) + (enow - bvirt)
			eindex += 1
			enow = at(e, eindex)
			Q = Qnew
			if hh != 0 {
				h[hindex] = hh
				hindex += 1
			}
		}
		while findex < flen {
			Qnew = Q + fnow
			bvirt = Qnew - Q
			hh = Q - (Qnew - bvirt) + (fnow - bvirt)
			findex += 1
			fnow = at(f, findex)
			Q = Qnew
			if hh != 0 {
				h[hindex] = hh
				hindex += 1
			}
		}
		if Q != 0 || hindex == 0 {
			h[hindex] = Q
			hindex += 1
		}
		return hindex
	}

	/// `orient2dadapt` from the original's orient2d.js.
	private static func orient2dAdapt(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ detsum: Double) -> (value: Double, branch: Int) {
		var B = [Double](repeating: 0, count: 4)
		var C1 = [Double](repeating: 0, count: 8)
		var C2 = [Double](repeating: 0, count: 12)
		var D = [Double](repeating: 0, count: 16)
		var u = [Double](repeating: 0, count: 4)

		var acxtail: Double, acytail: Double, bcxtail: Double, bcytail: Double
		var bvirt: Double, c: Double, ahi: Double, alo: Double, bhi: Double, blo: Double
		var _i: Double, _j: Double, _0: Double, s1: Double, s0: Double, t1: Double, t0: Double, u3: Double

		let acx = ax - cx
		let bcx = bx - cx
		let acy = ay - cy
		let bcy = by - cy

		s1 = acx * bcy
		c = splitter * acx
		ahi = c - (c - acx)
		alo = acx - ahi
		c = splitter * bcy
		bhi = c - (c - bcy)
		blo = bcy - bhi
		s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
		t1 = acy * bcx
		c = splitter * acy
		ahi = c - (c - acy)
		alo = acy - ahi
		c = splitter * bcx
		bhi = c - (c - bcx)
		blo = bcx - bhi
		t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
		_i = s0 - t0
		bvirt = s0 - _i
		B[0] = s0 - (_i + bvirt) + (bvirt - t0)
		_j = s1 + _i
		bvirt = _j - s1
		_0 = s1 - (_j - bvirt) + (_i - bvirt)
		_i = _0 - t1
		bvirt = _0 - _i
		B[1] = _0 - (_i + bvirt) + (bvirt - t1)
		u3 = _j + _i
		bvirt = u3 - _j
		B[2] = _j - (u3 - bvirt) + (_i - bvirt)
		B[3] = u3

		var det = estimate(4, B)
		var errbound = ccwerrboundB * detsum
		if det >= errbound || -det >= errbound {
			return (det, 1)
		}

		bvirt = ax - acx
		acxtail = ax - (acx + bvirt) + (bvirt - cx)
		bvirt = bx - bcx
		bcxtail = bx - (bcx + bvirt) + (bvirt - cx)
		bvirt = ay - acy
		acytail = ay - (acy + bvirt) + (bvirt - cy)
		bvirt = by - bcy
		bcytail = by - (bcy + bvirt) + (bvirt - cy)

		if acxtail == 0 && acytail == 0 && bcxtail == 0 && bcytail == 0 {
			return (det, 2)
		}

		errbound = ccwerrboundC * detsum + resulterrbound * abs(det)
		det += (acx * bcytail + bcy * acxtail) - (acy * bcxtail + bcx * acytail)
		if det >= errbound || -det >= errbound { return (det, 3) }

		s1 = acxtail * bcy
		c = splitter * acxtail
		ahi = c - (c - acxtail)
		alo = acxtail - ahi
		c = splitter * bcy
		bhi = c - (c - bcy)
		blo = bcy - bhi
		s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
		t1 = acytail * bcx
		c = splitter * acytail
		ahi = c - (c - acytail)
		alo = acytail - ahi
		c = splitter * bcx
		bhi = c - (c - bcx)
		blo = bcx - bhi
		t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
		_i = s0 - t0
		bvirt = s0 - _i
		u[0] = s0 - (_i + bvirt) + (bvirt - t0)
		_j = s1 + _i
		bvirt = _j - s1
		_0 = s1 - (_j - bvirt) + (_i - bvirt)
		_i = _0 - t1
		bvirt = _0 - _i
		u[1] = _0 - (_i + bvirt) + (bvirt - t1)
		u3 = _j + _i
		bvirt = u3 - _j
		u[2] = _j - (u3 - bvirt) + (_i - bvirt)
		u[3] = u3
		let C1len = sum(4, B, 4, u, &C1)

		s1 = acx * bcytail
		c = splitter * acx
		ahi = c - (c - acx)
		alo = acx - ahi
		c = splitter * bcytail
		bhi = c - (c - bcytail)
		blo = bcytail - bhi
		s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
		t1 = acy * bcxtail
		c = splitter * acy
		ahi = c - (c - acy)
		alo = acy - ahi
		c = splitter * bcxtail
		bhi = c - (c - bcxtail)
		blo = bcxtail - bhi
		t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
		_i = s0 - t0
		bvirt = s0 - _i
		u[0] = s0 - (_i + bvirt) + (bvirt - t0)
		_j = s1 + _i
		bvirt = _j - s1
		_0 = s1 - (_j - bvirt) + (_i - bvirt)
		_i = _0 - t1
		bvirt = _0 - _i
		u[1] = _0 - (_i + bvirt) + (bvirt - t1)
		u3 = _j + _i
		bvirt = u3 - _j
		u[2] = _j - (u3 - bvirt) + (_i - bvirt)
		u[3] = u3
		let C2len = sum(C1len, C1, 4, u, &C2)

		s1 = acxtail * bcytail
		c = splitter * acxtail
		ahi = c - (c - acxtail)
		alo = acxtail - ahi
		c = splitter * bcytail
		bhi = c - (c - bcytail)
		blo = bcytail - bhi
		s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
		t1 = acytail * bcxtail
		c = splitter * acytail
		ahi = c - (c - acytail)
		alo = acytail - ahi
		c = splitter * bcxtail
		bhi = c - (c - bcxtail)
		blo = bcxtail - bhi
		t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
		_i = s0 - t0
		bvirt = s0 - _i
		u[0] = s0 - (_i + bvirt) + (bvirt - t0)
		_j = s1 + _i
		bvirt = _j - s1
		_0 = s1 - (_j - bvirt) + (_i - bvirt)
		_i = _0 - t1
		bvirt = _0 - _i
		u[1] = _0 - (_i + bvirt) + (bvirt - t1)
		u3 = _j + _i
		bvirt = u3 - _j
		u[2] = _j - (u3 - bvirt) + (_i - bvirt)
		u[3] = u3
		let Dlen = sum(C2len, C2, 4, u, &D)

		return (D[Dlen - 1], 4)
	}
}
