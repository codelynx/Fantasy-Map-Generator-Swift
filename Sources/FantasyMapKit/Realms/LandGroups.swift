import Foundation

/// Which land is connected to which, for the realms layer (step 1 of docs/plans/realms.md): a pure function of a map and a
/// **reach**, before any realm is grown.
///
/// - A **landmass** is a maximal set of land cells (height 20 or more) connected through shared cell edges (the cell neighbour
///   lists). Water, lakes included, is not land. Two landmasses that touch only at a corner are not one landmass, and the map
///   frame joins nothing.
/// - **Reach** is an explicit, finite number of map units, 0 or more. **Reach 0 disables sea connections:** every landmass is
///   its own group. For a positive reach, two landmasses are joined by a **proximity link** when the distance between their raw
///   cell polygons, clipped to the map rectangle, is at most the reach (inclusive). The distance is computed with Double
///   arithmetic. **Because of that, a positive reach also joins landmasses that touch only at a corner (their distance is
///   zero), while reach 0 does not.** Such a corner contact cannot occur in a generic Voronoi diagram (every vertex joins
///   exactly three cells, which are pairwise neighbours); it is defined for degenerate diagrams and tested on hand-made cells.
/// - **Groups** are the transitive closure of the proximity links, numbered by the smallest cell index they contain (the
///   landmasses likewise), and **`minimumRealms` is the number of groups:** complete ownership by connected realms needs at
///   least that many. A map with no land has none.
/// - **`links`** are the links the grouping relies on: a **minimum spanning forest of the landmasses by distance** (Kruskal's
///   order, ties broken by the smallest cell indices), each with the pair of land cells whose polygons are closest. That the
///   groups are connected does not show that a direct link is a usable sea crossing (intervening land can replace it by a chain
///   of shorter links), so a later step that grows realms uses these end points and distances and not group membership alone.
///
/// **`links` are a compact connectivity witness, not a complete catalogue of crossings,** and their cell numbers and distance do
/// not themselves specify a verified over-water segment; growth must not treat them as the only crossings allowed.
///
/// The geometry is the raw cell polygons clipped to the rectangle, **not** the drawing layer's ray-extended border polygons; the
/// coast drawn on screen can differ from it. A clipped polygon with fewer than three points or no area is left out of the
/// distance work, though its cell stays in its landmass: a landmass with no usable polygon cannot be linked and stays its own
/// group.
public struct LandGroups: Equatable, Sendable {
	public struct Landmass: Equatable, Sendable {
		public var firstCell: Int
		public var cellCount: Int
		public var group: Int
	}

	public struct Group: Equatable, Sendable {
		public var firstCell: Int
		public var cellCount: Int
		/// The landmasses in this group, in increasing number.
		public var landmasses: [Int]
	}

	public struct Link: Equatable, Sendable {
		public var landmassA: Int
		public var landmassB: Int
		/// The closest pair of land cells, one in each landmass (`cellA` in the lower-numbered landmass).
		public var cellA: Int
		public var cellB: Int
		public var distance: Double
		/// The closest boundary points: `pointA` on the polygon of `cellA` and `pointB` on the polygon of `cellB`, so the link is a
		/// real segment and its length is `distance`. When several pairs of points are equally close, the first found in a fixed
		/// order (the vertices of A against the edges of B, then the vertices of B against the edges of A) is kept, so the choice is
		/// deterministic. **The segment is not verified to lie over water here;** that is the job of the step that uses it.
		public var pointA: Point
		public var pointB: Point
	}

	/// For every cell the number of its landmass, or -1 for water.
	public var landmassOfCell: [Int32]
	/// For every cell the number of its group, or -1 for water.
	public var groupOfCell: [Int32]
	public var landmasses: [Landmass]
	public var groups: [Group]
	public var links: [Link]

	/// The least number of realms that can own all the land with each realm connected: the number of groups.
	public var minimumRealms: Int { groups.count }

	public enum Problem: Error, Equatable, Sendable {
		case invalidReach
		case invalidGeometry
		/// A budget is negative. Checked before anything else, so an invalid resource policy never "works" merely because no search was needed.
		case invalidBudget
		/// A work bound was exceeded (`insertions`, `candidates`, `distances` or `primitives`): refused, never approximated.
		case workBudget(String)
	}

	/// The bounds on the work of the search, each checked before the expensive loops run.
	public struct Budgets: Equatable, Sendable {
		public var insertions = 5_000_000
		public var candidates = 50_000_000
		public var distances = 10_000_000
		/// The primitive point-to-segment evaluations inside the polygon distances: one pair of polygons with a and b vertices costs 2 × a × b.
		/// Counted **before** a pair's distance is computed, so one candidate pair with very many vertices cannot do uncounted work.
		public var primitives = 400_000_000
		public init() {}
		var isValid: Bool { insertions >= 0 && candidates >= 0 && distances >= 0 && primitives >= 0 }
	}

	/// The groups of a map for an explicit reach, in map units. Throws `invalidReach` for a reach that is not finite or is
	/// negative, and `workBudget` when the search would exceed its bounds (a very large reach on a dense map can).
	public static func find(in map: LandMap, reach: Double, budgets: Budgets = Budgets()) throws -> LandGroups {
		let n = map.heights.count
		let v = map.voronoi
		let isLand = map.heights.map { Heights.isLand($0) }
		return try compute(
			isLand: isLand, neighbours: v.cells.c, width: map.width, height: map.height, bucketFloor: 0.25 * map.grid.spacing, reach: reach, budgets: budgets,
			polygon: { cell in
				guard cell < n else { return [] }
				return RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: map.width, height: map.height)
			}
		)
	}

	/// The search over explicit cells: `polygon` gives a cell's (already clipped) polygon, asked only for coast cells.
	static func compute(isLand: [Bool], neighbours: [[Int]], width: Double, height: Double, bucketFloor: Double, reach: Double, budgets: Budgets = Budgets(), polygon: (Int) -> [Point]) throws -> LandGroups {
		guard budgets.isValid else { throw Problem.invalidBudget }
		guard reach.isFinite, reach >= 0 else { throw Problem.invalidReach }
		guard width.isFinite, height.isFinite, width > 0, height > 0, bucketFloor.isFinite, bucketFloor > 0 else { throw Problem.invalidGeometry }
		let n = isLand.count

		// landmasses, numbered by their smallest cell
		var landmassOf = [Int32](repeating: -1, count: n)
		var landmasses: [Landmass] = []
		var stack: [Int] = []
		for start in 0..<n where isLand[start] && landmassOf[start] < 0 {
			let id = Int32(landmasses.count)
			var count = 0
			landmassOf[start] = id
			stack.append(start)
			while let cell = stack.popLast() {
				count += 1
				for other in neighbours[cell] where other >= 0 && other < n && isLand[other] && landmassOf[other] < 0 {
					landmassOf[other] = id
					stack.append(other)
				}
			}
			landmasses.append(Landmass(firstCell: start, cellCount: count, group: 0))
		}

		var best: [Int64: Link] = [:]
		if reach > 0 && landmasses.count > 1 {
			try search(isLand: isLand, neighbours: neighbours, landmassOf: landmassOf, width: width, height: height, bucketFloor: bucketFloor, reach: reach, budgets: budgets, polygon: polygon, best: &best)
		}

		// Kruskal over the best link of each landmass pair
		let edges = best.values.sorted {
			if $0.distance != $1.distance { return $0.distance < $1.distance }
			if $0.cellA != $1.cellA { return $0.cellA < $1.cellA }
			return $0.cellB < $1.cellB
		}
		var parent = Array(0..<landmasses.count)
		func find(_ x: Int) -> Int {
			var r = x
			while parent[r] != r { r = parent[r] }
			var c = x
			while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
			return r
		}
		var links: [Link] = []
		for edge in edges {
			let a = find(edge.landmassA), b = find(edge.landmassB)
			if a != b { parent[max(a, b)] = min(a, b); links.append(edge) }
		}

		// groups, numbered by the smallest cell: landmasses are already in that order
		var groupOfRoot: [Int: Int] = [:]
		var groups: [Group] = []
		for (i, landmass) in landmasses.enumerated() {
			let root = find(i)
			if let g = groupOfRoot[root] {
				groups[g].cellCount += landmass.cellCount
				groups[g].landmasses.append(i)
				landmasses[i].group = g
			} else {
				groupOfRoot[root] = groups.count
				landmasses[i].group = groups.count
				groups.append(Group(firstCell: landmass.firstCell, cellCount: landmass.cellCount, landmasses: [i]))
			}
		}
		let groupOfCell = landmassOf.map { $0 < 0 ? Int32(-1) : Int32(landmasses[Int($0)].group) }
		return LandGroups(landmassOfCell: landmassOf, groupOfCell: groupOfCell, landmasses: landmasses, groups: groups, links: links)
	}

	/// Candidate discovery that cannot miss a pair, as a mathematical argument for this construction under ordinary floating-point
	/// arithmetic and the stated geometry assumptions (the brute-force comparisons in the tests are the evidence for the
	/// implementation): the bounding boxes of the coast cells' polygons, each grown by half the reach, are put in a hash whose
	/// buckets are at least as large as the reach (and never smaller than a floor), and two polygons are candidates when their
	/// grown boxes overlap, which they must if their distance is at most the reach.
	private static func search(isLand: [Bool], neighbours: [[Int]], landmassOf: [Int32], width: Double, height: Double, bucketFloor: Double, reach: Double, budgets: Budgets, polygon: (Int) -> [Point], best: inout [Int64: Link]) throws {
		let n = isLand.count
		struct Box { var cell: Int; var landmass: Int32; var polygon: [Point]; var minX: Double; var minY: Double; var maxX: Double; var maxY: Double; var ix: Int; var iy: Int }
		let size = max(reach, bucketFloor)
		let grow = reach / 2
		func bucket(_ v: Double) -> Int { Int(max(min((v / size).rounded(.down), 1e12), -1e12)) }
		var boxes: [Box] = []
		var insertions = 0
		struct Bucket: Hashable { var x: Int; var y: Int }
		var grid: [Bucket: [Int32]] = [:]
		for cell in 0..<n where isLand[cell] && neighbours[cell].contains(where: { $0 >= 0 && $0 < n && !isLand[$0] }) {
			let p = polygon(cell)
			guard p.count >= 3, p.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
			var area = 0.0
			for (a, b) in zip(p, p.dropFirst() + [p[0]]) { area += a.x * b.y - b.x * a.y }
			guard area != 0 else { continue }
			let xs = p.map(\.x), ys = p.map(\.y)
			let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
			let x0 = bucket(minX - grow), x1 = bucket(maxX + grow), y0 = bucket(minY - grow), y1 = bucket(maxY + grow)
			let (w, o1) = (x1 - x0 + 1).multipliedReportingOverflow(by: y1 - y0 + 1)
			guard !o1 else { throw Problem.workBudget("insertions") }
			insertions += w
			guard insertions <= budgets.insertions else { throw Problem.workBudget("insertions") }
			let id = Int32(boxes.count)
			boxes.append(Box(cell: cell, landmass: landmassOf[cell], polygon: p, minX: minX, minY: minY, maxX: maxX, maxY: maxY, ix: x0, iy: y0))
			for x in x0...x1 { for y in y0...y1 { grid[Bucket(x: x, y: y), default: []].append(id) } }
		}
		var candidates = 0, distances = 0, primitives = 0
		for (at, bucketBoxes) in grid {
			guard bucketBoxes.count > 1 else { continue }
			for i in 0..<bucketBoxes.count {
				for j in (i + 1)..<bucketBoxes.count {
					candidates += 1
					guard candidates <= budgets.candidates else { throw Problem.workBudget("candidates") }
					let a = boxes[Int(bucketBoxes[i])], b = boxes[Int(bucketBoxes[j])]
					guard a.landmass != b.landmass else { continue }
					// each pair is tested once, in the first bucket both grown boxes occupy
					guard max(a.ix, b.ix) == at.x, max(a.iy, b.iy) == at.y else { continue }
					guard a.minX - grow <= b.maxX + grow, b.minX - grow <= a.maxX + grow, a.minY - grow <= b.maxY + grow, b.minY - grow <= a.maxY + grow else { continue }
					distances += 1
					guard distances <= budgets.distances else { throw Problem.workBudget("distances") }
					// the primitive evaluations this pair will perform, counted before any of them: 2 x a x b, overflow-checked
					let (each, o1) = a.polygon.count.multipliedReportingOverflow(by: b.polygon.count)
					let (cost, o2) = each.multipliedReportingOverflow(by: 2)
					let (total, o3) = primitives.addingReportingOverflow(cost)
					guard !o1, !o2, !o3, total <= budgets.primitives else { throw Problem.workBudget("primitives") }
					primitives = total
					let (low, high) = a.landmass < b.landmass ? (a, b) : (b, a)
					let witness = closestPair(low.polygon, high.polygon)
					guard witness.distance <= reach else { continue }
					let d = witness.distance
					let link = Link(landmassA: Int(low.landmass), landmassB: Int(high.landmass), cellA: low.cell, cellB: high.cell, distance: d, pointA: witness.a, pointB: witness.b)
					let k = Int64(low.landmass) << 32 | Int64(high.landmass)
					if let old = best[k], (old.distance, old.cellA, old.cellB) <= (link.distance, link.cellA, link.cellB) { continue }
					best[k] = link
				}
			}
		}
	}

	/// The distance between two polygons that do not overlap: the least distance from a vertex of one to an edge of the other,
	/// in both directions, computed with Double arithmetic. Polygons that share a vertex are at distance 0.
	static func polygonDistance(_ a: [Point], _ b: [Point]) -> Double { closestPair(a, b).distance }

	/// The same distance with the pair of points that gives it: `a` on the first polygon's boundary and `b` on the second's. The
	/// first minimal pair in the stated order is kept (strictly smaller wins), so the choice is deterministic.
	static func closestPair(_ a: [Point], _ b: [Point]) -> (distance: Double, a: Point, b: Point) {
		var best = (distance: Double.infinity, a: Point(x: 0, y: 0), b: Point(x: 0, y: 0))
		// edges are taken by index, so no edge array is built inside the loops
		for p in a { for i in b.indices {
			let (d, q) = closestOnSegment(p, b[i], b[(i + 1) % b.count])
			if d < best.distance { best = (d, p, q) }
		} }
		for p in b { for i in a.indices {
			let (d, q) = closestOnSegment(p, a[i], a[(i + 1) % a.count])
			if d < best.distance { best = (d, q, p) }
		} }
		return best
	}

	static func pointSegmentDistance(_ p: Point, _ a: Point, _ b: Point) -> Double { closestOnSegment(p, a, b).distance }

	/// The point of the segment a to b closest to `p`, and its distance.
	static func closestOnSegment(_ p: Point, _ a: Point, _ b: Point) -> (distance: Double, point: Point) {
		let dx = b.x - a.x, dy = b.y - a.y
		let length2 = dx * dx + dy * dy
		let t = length2 == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length2, 0), 1)
		let q = Point(x: a.x + t * dx, y: a.y + t * dy)
		let ex = p.x - q.x, ey = p.y - q.y
		return ((ex * ex + ey * ey).squareRoot(), q)
	}
}
