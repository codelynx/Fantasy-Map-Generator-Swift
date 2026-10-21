// Ported from the npm package `delaunator` 5.1.0 (index.js) by Vladimir Agafonkin / Mapbox: ISC licence; the notice is
// in ACKNOWLEDGEMENTS.md. The steps, their order and the arithmetic follow the original, because the triangle and
// half-edge ordering it produces decides the cells (and their neighbour order) generated afterwards.
//
// Two JavaScript behaviours are handled on purpose and noted where they occur: reads past the end of a typed array give
// `undefined` in JavaScript, and `Math.floor` of a non-finite number does not trap.

import Foundation

/// Why a set of points was refused.
public enum DelaunayError: Error, Equatable, Sendable {
	/// A coordinate is NaN or infinite.
	case nonFiniteCoordinate
	/// A coordinate is larger than `Delaunay.maximumCoordinate` in magnitude.
	case coordinateTooLarge
	/// The seed triangle's circumcenter is not finite (the first three points it chose are nearly collinear). The
	/// original would carry NaN or infinity into the triangulation; this port reports it instead.
	case nonFiniteGeometry
	/// The flat coordinate list has an odd number of values.
	case oddCoordinateCount
	/// More points than `Delaunay.maximumPoints`.
	case tooManyPoints
	/// The hull lookup could not be completed: a point's hash key is not a finite number, which the original does not
	/// handle either (see the note on `Delaunay.hashKey`). No input is known that reaches this with finite coordinates.
	case unsupportedDegenerateInput
}

/// A Delaunay triangulation of a set of points, with Delaunator's exact triangle, half-edge and hull ordering.
public struct Delaunay: Equatable, Sendable {
	/// The points' coordinates, `[x0, y0, x1, y1, ...]`.
	public let coords: [Double]
	/// Triangle vertex indices, three per triangle, all counter-clockwise (in the original's sense).
	public private(set) var triangles: [Int]
	/// For each half-edge, the index of its twin in the adjacent triangle, or -1 on the convex hull.
	public private(set) var halfedges: [Int]
	/// Indices of the points on the convex hull. For collinear input this is the ordered line and `triangles` is empty.
	public private(set) var hull: [Int]

	/// A provisional safety ceiling on the number of points, which also bounds about twenty working arrays of that length.
	/// Not a performance claim; peak memory at this size has not been measured.
	public static let maximumPoints = 400_000
	/// The largest coordinate magnitude accepted: a map up to a billion units across. This is a **supported range with
	/// ample headroom, not a guarantee that every derived number is finite**: the in-circle test forms fourth-degree
	/// products (about 1e36 at this limit, far below the largest Double), but the circumcenter formulas divide by a
	/// determinant that is tiny for nearly collinear points, so derived coordinates can still overflow. Those cases are
	/// detected and reported (`nonFiniteGeometry`, and `VoronoiDiagramError.nonFiniteGeometry`), never returned. Ordinary
	/// inputs are not rescaled, so parity with the original is unchanged.
	public static let maximumCoordinate = 1e9

	/// The original keeps this stack at 512 entries; past that the original silently stops pushing (extremely degenerate input).
	/// This is an upstream limitation preserved on purpose, not a guarantee about extreme degeneracy.
	private static let edgeStackSize = 512
	private static let epsilon = Double.ulpOfOne // 2^-52, the original's EPSILON

	/// Triangulates the points. Duplicate points are skipped, as in the original. Throws for non-finite or oversized
	/// coordinates, too many points, or (not known to occur) a hull lookup that cannot be completed.
	public init(points: [Point]) throws {
		guard points.count <= Self.maximumPoints else { throw DelaunayError.tooManyPoints }
		var coords = [Double](repeating: 0, count: points.count * 2)
		for (i, p) in points.enumerated() {
			coords[2 * i] = p.x
			coords[2 * i + 1] = p.y
		}
		try self.init(coords: coords)
	}

	/// Triangulates `[x0, y0, x1, y1, ...]`. An odd number of values is refused.
	public init(coords: [Double]) throws {
		guard coords.count % 2 == 0 else { throw DelaunayError.oddCoordinateCount }
		guard coords.count / 2 <= Self.maximumPoints else { throw DelaunayError.tooManyPoints }
		for value in coords {
			guard value.isFinite else { throw DelaunayError.nonFiniteCoordinate }
			guard abs(value) <= Self.maximumCoordinate else { throw DelaunayError.coordinateTooLarge }
		}
		self.coords = coords
		var state = State(coords: coords)
		try state.update()
		self.triangles = state.triangles
		self.halfedges = state.halfedges
		self.hull = state.hull
	}

	/// The original's mutable working state (its private fields), kept apart so the public value stays immutable.
	private struct State {
		let coords: [Double]
		let n: Int
		var triangles: [Int]
		var halfedges: [Int]
		var hull: [Int] = []
		var trianglesLen = 0
		var hashSize: Int
		var hullPrev: [Int]
		var hullNext: [Int]
		var hullTri: [Int]
		var hullHash: [Int]
		var ids: [Int]
		var dists: [Double]
		var cx = 0.0
		var cy = 0.0
		var hullStart = 0
		var edgeStack = [Int](repeating: 0, count: Delaunay.edgeStackSize)

		init(coords: [Double]) {
			self.coords = coords
			n = coords.count >> 1
			let maxTriangles = max(2 * n - 5, 0)
			triangles = [Int](repeating: 0, count: maxTriangles * 3)
			halfedges = [Int](repeating: 0, count: maxTriangles * 3)
			hashSize = Int(Double(n).squareRoot().rounded(.up))
			hullPrev = [Int](repeating: 0, count: n)
			hullNext = [Int](repeating: 0, count: n)
			hullTri = [Int](repeating: 0, count: n)
			hullHash = [Int](repeating: 0, count: hashSize)
			ids = [Int](repeating: 0, count: n)
			dists = [Double](repeating: 0, count: n)
		}

		mutating func update() throws {
			// no points: the original's typed arrays are empty and nothing is read
			if n == 0 {
				triangles = []
				halfedges = []
				hull = []
				return
			}

			// populate an array of point indices; calculate input data bbox
			var minX = Double.infinity
			var minY = Double.infinity
			var maxX = -Double.infinity
			var maxY = -Double.infinity

			for i in 0..<n {
				let x = coords[2 * i]
				let y = coords[2 * i + 1]
				if x < minX { minX = x }
				if y < minY { minY = y }
				if x > maxX { maxX = x }
				if y > maxY { maxY = y }
				ids[i] = i
			}
			let cx = (minX + maxX) / 2
			let cy = (minY + maxY) / 2

			var i0 = 0, i1 = 0, i2 = 0

			// pick a seed point close to the center
			var minDist = Double.infinity
			for i in 0..<n {
				let d = Self.dist(cx, cy, coords[2 * i], coords[2 * i + 1])
				if d < minDist {
					i0 = i
					minDist = d
				}
			}
			let i0x = coords[2 * i0]
			let i0y = coords[2 * i0 + 1]

			// find the point closest to the seed
			minDist = Double.infinity
			for i in 0..<n {
				if i == i0 { continue }
				let d = Self.dist(i0x, i0y, coords[2 * i], coords[2 * i + 1])
				if d < minDist && d > 0 {
					i1 = i
					minDist = d
				}
			}
			var i1x = coords[2 * i1]
			var i1y = coords[2 * i1 + 1]

			var minRadius = Double.infinity

			// find the third point which forms the smallest circumcircle with the first two
			for i in 0..<n {
				if i == i0 || i == i1 { continue }
				let r = Self.circumradius(i0x, i0y, i1x, i1y, coords[2 * i], coords[2 * i + 1])
				if r < minRadius {
					i2 = i
					minRadius = r
				}
			}
			var i2x = coords[2 * i2]
			var i2y = coords[2 * i2 + 1]

			if minRadius == Double.infinity {
				// order collinear points by dx (or dy if all x are identical) and return the list as a hull
				for i in 0..<n {
					let dx = coords[2 * i] - coords[0]
					dists[i] = dx != 0 && !dx.isNaN ? dx : (coords[2 * i + 1] - coords[1]) // JavaScript's `a || b`
				}
				Self.quicksort(&ids, dists, 0, n - 1)
				var hullIds: [Int] = []
				var d0 = -Double.infinity
				for i in 0..<n {
					let id = ids[i]
					let d = dists[id]
					if d > d0 {
						hullIds.append(id)
						d0 = d
					}
				}
				hull = hullIds
				triangles = []
				halfedges = []
				return
			}

			// swap the order of the seed points for counter-clockwise orientation
			if RobustPredicates.orient2d(i0x, i0y, i1x, i1y, i2x, i2y) < 0 {
				let i = i1
				let x = i1x
				let y = i1y
				i1 = i2
				i1x = i2x
				i1y = i2y
				i2 = i
				i2x = x
				i2y = y
			}

			let center = Self.circumcenter(i0x, i0y, i1x, i1y, i2x, i2y)
			guard center.x.isFinite, center.y.isFinite else { throw DelaunayError.nonFiniteGeometry }
			self.cx = center.x
			self.cy = center.y

			for i in 0..<n {
				dists[i] = Self.dist(coords[2 * i], coords[2 * i + 1], center.x, center.y)
			}

			// sort the points by distance from the seed triangle circumcenter
			Self.quicksort(&ids, dists, 0, n - 1)

			// set up the seed triangle as the starting hull
			hullStart = i0
			var hullSize = 3

			hullNext[i0] = i1; hullPrev[i2] = i1
			hullNext[i1] = i2; hullPrev[i0] = i2
			hullNext[i2] = i0; hullPrev[i1] = i0

			hullTri[i0] = 0
			hullTri[i1] = 1
			hullTri[i2] = 2

			for k in 0..<hashSize { hullHash[k] = -1 }
			setHash(try hashKey(i0x, i0y), i0)
			setHash(try hashKey(i1x, i1y), i1)
			setHash(try hashKey(i2x, i2y), i2)

			trianglesLen = 0
			_ = addTriangle(i0, i1, i2, -1, -1, -1)

			var xp = 0.0
			var yp = 0.0
			for k in 0..<ids.count {
				let i = ids[k]
				let x = coords[2 * i]
				let y = coords[2 * i + 1]

				// skip near-duplicate points
				if k > 0 && abs(x - xp) <= Delaunay.epsilon && abs(y - yp) <= Delaunay.epsilon { continue }
				xp = x
				yp = y

				// skip seed triangle points
				if i == i0 || i == i1 || i == i2 { continue }

				// find a visible edge on the convex hull using edge hash
				var start = 0
				let key = try hashKey(x, y)
				for j in 0..<hashSize {
					start = hullHash[(key + j) % hashSize]
					if start != -1 && start != hullNext[start] { break }
				}
				// every probe empty: the original's `hullPrev[-1]` would read undefined; nothing sensible follows
				guard start != -1 else { throw DelaunayError.unsupportedDegenerateInput }

				start = hullPrev[start]
				var e = start
				var q = hullNext[e]
				while RobustPredicates.orient2d(x, y, coords[2 * e], coords[2 * e + 1], coords[2 * q], coords[2 * q + 1]) >= 0 {
					e = q
					if e == start {
						e = -1
						break
					}
					q = hullNext[e]
				}
				if e == -1 { continue } // likely a near-duplicate point; skip it

				// add the first triangle from the point
				var t = addTriangle(e, i, hullNext[e], -1, -1, hullTri[e])

				// recursively flip triangles from the point until they satisfy the Delaunay condition
				hullTri[i] = legalize(t + 2)
				hullTri[e] = t // keep track of boundary triangles on the hull
				hullSize += 1

				// walk forward through the hull, adding more triangles and flipping recursively
				var nn = hullNext[e]
				q = hullNext[nn]
				while RobustPredicates.orient2d(x, y, coords[2 * nn], coords[2 * nn + 1], coords[2 * q], coords[2 * q + 1]) < 0 {
					t = addTriangle(nn, i, q, hullTri[i], -1, hullTri[nn])
					hullTri[i] = legalize(t + 2)
					hullNext[nn] = nn // mark as removed
					hullSize -= 1
					nn = q
					q = hullNext[nn]
				}

				// walk backward from the other side, adding more triangles and flipping
				if e == start {
					q = hullPrev[e]
					while RobustPredicates.orient2d(x, y, coords[2 * q], coords[2 * q + 1], coords[2 * e], coords[2 * e + 1]) < 0 {
						t = addTriangle(q, i, e, -1, hullTri[e], hullTri[q])
						_ = legalize(t + 2)
						hullTri[q] = t
						hullNext[e] = e // mark as removed
						hullSize -= 1
						e = q
						q = hullPrev[e]
					}
				}

				// update the hull indices
				hullPrev[i] = e
				hullStart = e
				hullNext[e] = i
				hullPrev[nn] = i
				hullNext[i] = nn

				// save the two new edges in the hash table
				setHash(try hashKey(x, y), i)
				setHash(try hashKey(coords[2 * e], coords[2 * e + 1]), e)
			}

			hull = []
			hull.reserveCapacity(hullSize)
			var e = hullStart
			for _ in 0..<hullSize {
				hull.append(e)
				e = hullNext[e]
			}

			// trim the triangle mesh arrays
			triangles = Array(triangles[0..<trianglesLen])
			halfedges = Array(halfedges[0..<trianglesLen])
		}

		/// The original's `_hashKey`: `floor(pseudoAngle(x - cx, y - cy) * hashSize) % hashSize`.
		///
		/// If the angle is not a finite number (a point exactly at the seed triangle's circumcenter makes it 0 / 0), the
		/// original indexes a typed array with NaN: writes do nothing, reads give `undefined`, and later steps then
		/// propagate `undefined` through the triangulation in ways a sentinel cannot reproduce. This port reports it as
		/// `unsupportedDegenerateInput` instead. A search of 3,000,000 random small integer point sets found no input that
		/// reaches it with finite coordinates (such a point would have been chosen as the seed's third point), so the path
		/// is defended and is not known to be reachable.
		func hashKey(_ x: Double, _ y: Double) throws -> Int {
			guard let key = Delaunay.hashKey(x, y, cx: cx, cy: cy, hashSize: hashSize) else { throw DelaunayError.unsupportedDegenerateInput }
			return key
		}

		mutating func setHash(_ key: Int, _ i: Int) {
			hullHash[key] = i
		}

		mutating func legalize(_ aIn: Int) -> Int {
			var a = aIn
			var i = 0
			var ar = 0

			// recursion eliminated with a fixed-size stack
			while true {
				let b = halfedges[a]

				let a0 = a - a % 3
				ar = a0 + (a + 2) % 3

				if b == -1 { // convex hull edge
					if i == 0 { break }
					i -= 1
					a = edgeStack[i]
					continue
				}

				let b0 = b - b % 3
				let al = a0 + (a + 1) % 3
				let bl = b0 + (b + 2) % 3

				let p0 = triangles[ar]
				let pr = triangles[a]
				let pl = triangles[al]
				let p1 = triangles[bl]

				let illegal = Self.inCircle(
					coords[2 * p0], coords[2 * p0 + 1],
					coords[2 * pr], coords[2 * pr + 1],
					coords[2 * pl], coords[2 * pl + 1],
					coords[2 * p1], coords[2 * p1 + 1])

				if illegal {
					triangles[a] = p1
					triangles[b] = p0

					let hbl = halfedges[bl]

					// edge swapped on the other side of the hull (rare); fix the half-edge reference
					if hbl == -1 {
						var e = hullStart
						repeat {
							if hullTri[e] == bl {
								hullTri[e] = a
								break
							}
							e = hullPrev[e]
						} while e != hullStart
					}
					link(a, hbl)
					link(b, halfedges[ar])
					link(ar, bl)

					let br = b0 + (b + 1) % 3

					// the original does not worry about hitting the cap: it can only happen on extremely degenerate input
					if i < Delaunay.edgeStackSize {
						edgeStack[i] = br
						i += 1
					}
				} else {
					if i == 0 { break }
					i -= 1
					a = edgeStack[i]
				}
			}

			return ar
		}

		mutating func link(_ a: Int, _ b: Int) {
			halfedges[a] = b
			if b != -1 { halfedges[b] = a }
		}

		mutating func addTriangle(_ i0: Int, _ i1: Int, _ i2: Int, _ a: Int, _ b: Int, _ c: Int) -> Int {
			let t = trianglesLen

			triangles[t] = i0
			triangles[t + 1] = i1
			triangles[t + 2] = i2

			link(t, a)
			link(t + 1, b)
			link(t + 2, c)

			trianglesLen += 3
			return t
		}

		// MARK: the original's free functions

		/// Monotonically increases with real angle, but needs no trigonometry.
		static func pseudoAngle(_ dx: Double, _ dy: Double) -> Double {
			let p = dx / (abs(dx) + abs(dy))
			return (dy > 0 ? 3 - p : 1 + p) / 4 // [0..1]
		}

		/// Squared distance between two points.
		static func dist(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
			let dx = ax - bx
			let dy = ay - by
			return dx * dx + dy * dy
		}

		/// Whether point P is inside the circle formed by A, B, C (Delaunator's own floating-point test, not a robust one).
		static func inCircle(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ px: Double, _ py: Double) -> Bool {
			let dx = ax - px
			let dy = ay - py
			let ex = bx - px
			let ey = by - py
			let fx = cx - px
			let fy = cy - py

			let ap = dx * dx + dy * dy
			let bp = ex * ex + ey * ey
			let cp = fx * fx + fy * fy

			return dx * (ey * cp - bp * fy) -
				dy * (ex * cp - bp * fx) +
				ap * (ex * fy - ey * fx) < 0
		}

		/// Squared radius of the circle formed by A, B, C.
		static func circumradius(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double) -> Double {
			let dx = bx - ax
			let dy = by - ay
			let ex = cx - ax
			let ey = cy - ay

			let bl = dx * dx + dy * dy
			let cl = ex * ex + ey * ey
			let d = 0.5 / (dx * ey - dy * ex)

			let x = (ey * bl - dy * cl) * d
			let y = (dx * cl - ex * bl) * d

			return x * x + y * y
		}

		/// Coordinates of the circumcenter of A, B, C.
		static func circumcenter(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double) -> (x: Double, y: Double) {
			let dx = bx - ax
			let dy = by - ay
			let ex = cx - ax
			let ey = cy - ay

			let bl = dx * dx + dy * dy
			let cl = ex * ex + ey * ey
			let d = 0.5 / (dx * ey - dy * ex)

			let x = ax + (ey * bl - dy * cl) * d
			let y = ay + (dx * cl - ex * bl) * d

			return (x, y)
		}

		/// The original's quicksort of point indices by distance. The order of ties and every swap follow the original,
		/// because the order of the sorted points decides the triangulation.
		static func quicksort(_ ids: inout [Int], _ dists: [Double], _ left: Int, _ right: Int) {
			if right - left <= 20 {
				var i = left + 1
				while i <= right {
					let temp = ids[i]
					let tempDist = dists[temp]
					var j = i - 1
					while j >= left && dists[ids[j]] > tempDist {
						ids[j + 1] = ids[j]
						j -= 1
					}
					ids[j + 1] = temp
					i += 1
				}
			} else {
				let median = (left + right) >> 1
				var i = left + 1
				var j = right
				swap(&ids, median, i)
				if dists[ids[left]] > dists[ids[right]] { swap(&ids, left, right) }
				if dists[ids[i]] > dists[ids[right]] { swap(&ids, i, right) }
				if dists[ids[left]] > dists[ids[i]] { swap(&ids, left, i) }

				let temp = ids[i]
				let tempDist = dists[temp]
				while true {
					repeat { i += 1 } while dists[ids[i]] < tempDist
					repeat { j -= 1 } while dists[ids[j]] > tempDist
					if j < i { break }
					swap(&ids, i, j)
				}
				ids[left + 1] = ids[j]
				ids[j] = temp

				if right - i + 1 >= j - left {
					quicksort(&ids, dists, i, right)
					quicksort(&ids, dists, left, j - 1)
				} else {
					quicksort(&ids, dists, left, j - 1)
					quicksort(&ids, dists, i, right)
				}
			}
		}

		private static func swap(_ arr: inout [Int], _ i: Int, _ j: Int) {
			let tmp = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp
		}
	}

	/// The hash key for a point, or nil if it is not a finite number. Separate so the unreachable-in-practice case can be tested.
	static func hashKey(_ x: Double, _ y: Double, cx: Double, cy: Double, hashSize: Int) -> Int? {
		let dx = x - cx
		let dy = y - cy
		let p = dx / (abs(dx) + abs(dy))
		let angle = (dy > 0 ? 3 - p : 1 + p) / 4
		let value = (angle * Double(hashSize)).rounded(.down)
		guard value.isFinite, hashSize > 0 else { return nil }
		return Int(value) % hashSize
	}
}
