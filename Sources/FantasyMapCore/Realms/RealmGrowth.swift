import Foundation

/// The explicit policy of realm growth (realms step 3, docs/plans/realms.md). There are **no hidden constants** for the factors:
/// a caller supplies them. The height thresholds (44 for hills, 67 for mountains) are the original's own and are fixed.
public struct GrowthPolicy: Equatable, Sendable {
	/// The cost multiplier per unit distance on a hill (height 44 or more, below 67): 1 or more, at most `maximumFactor`.
	public var hillFactor: Double
	/// The same for a mountain (height 67 or more).
	public var mountainFactor: Double
	/// The multiplier on the sea length of a crossing: 1 or more, at most `maximumFactor`.
	public var crossingFactor: Double
	/// The "how uneven" setting: realm i grows at 1 + unevenness × r_i, r_i drawn once per realm from the seeded stream. 0 gives
	/// every realm the same expansion factor (not equal-sized realms). 0 to `maximumUnevenness`.
	public var unevenness: Double
	/// Resource budgets, each 0 or more: heap proposals pushed, heap pops, edge examinations, and the tests of crossing verification.
	public var heapPushes = 50_000_000
	public var heapPops = 50_000_000
	public var edgeExaminations = 200_000_000
	public var verificationTests = 200_000_000

	public static let maximumFactor = 1_000.0
	public static let maximumUnevenness = 100.0

	public init(hillFactor: Double, mountainFactor: Double, crossingFactor: Double, unevenness: Double) {
		self.hillFactor = hillFactor
		self.mountainFactor = mountainFactor
		self.crossingFactor = crossingFactor
		self.unevenness = unevenness
	}

	var isValid: Bool {
		func factor(_ x: Double) -> Bool { x.isFinite && x >= 1 && x <= Self.maximumFactor }
		return factor(hillFactor) && factor(mountainFactor) && factor(crossingFactor)
			&& unevenness.isFinite && unevenness >= 0 && unevenness <= Self.maximumUnevenness
			&& heapPushes >= 0 && heapPops >= 0 && edgeExaminations >= 0 && verificationTests >= 0
	}
}

/// The owner of every land cell, from connected frontier growth over verified crossings.
///
/// **Connected frontier growth, not shortest-path ownership.** Every seed is reserved for its realm before growth; proposals are
/// queued only from cells the realm has already claimed; each unclaimed cell is finalized once (the first proposal popped wins,
/// a finalized owner is never overwritten, stale proposals are discarded); a realm spreads only through its own claimed cells,
/// over land adjacency and over verified crossings. This builds connected territories and can cover a connected seeded graph
/// completely. It is **not** a guarantee of the globally lowest unrestricted source-specific shortest-path cost: with realm-
/// specific expansion factors a faster realm can have the cheapest path to a cell through another realm's land, which this does not allow.
public struct RealmOwnership: Equatable, Sendable {
	public struct Realm: Equatable, Sendable {
		public var number: Int
		public var group: Int
		public var seedCell: Int
		public var cellCount: Int
		/// The summed area of the realm's cells' raw polygons clipped to the map rectangle (map units²).
		public var area: Double
	}

	/// For every cell the realm number 1 … K, or 0 for water.
	public var owner: [Int32]
	public var realms: [Realm]
	public var policy: GrowthPolicy

	public enum Problem: Error, Equatable, Sendable {
		case invalidPolicy
		/// The groups, links or seeds are not consistent with the map or with each other.
		case invalidInputs
		/// A link's segment could not be verified as a clean over-water crossing (it passes over land, touches other land
		/// ambiguously, or the geometry is not finite): named, never silently dropped.
		case unusableCrossing(landmassA: Int, landmassB: Int)
		/// A derived cost was not finite.
		case nonFiniteCost
		/// Land could not be reached from any seed (a group without a seed, or links missing from a hand-built input).
		case unreachableLand(cell: Int)
		/// A work bound was exceeded: `pushes`, `pops`, `edges` or `verification`.
		case workBudget(String)
	}

	// MARK: public entry point

	/// Grows the realms of a map. **`groups`, `seeds` and the links in `groups` must come from steps 1 and 2 for this map**; they
	/// are validated here (policy first, then the groups, links and seeds) before any work.
	public static func grow(in map: LandMap, groups: LandGroups, seeds: RealmSeeds, realmSeed: String, policy: GrowthPolicy) throws -> RealmOwnership {
		guard policy.isValid else { throw Problem.invalidPolicy }
		let v = map.voronoi
		let n = map.heights.count
		guard RealmSeeds.validate(groups, cellCount: n) else { throw Problem.invalidInputs }
		for cell in 0..<n where (groups.landmassOfCell[cell] >= 0) != Heights.isLand(map.heights[cell]) { throw Problem.invalidInputs }
		var areas = [Double](repeating: 0, count: n)
		var polygons = [[Point]](repeating: [], count: n)
		for cell in 0..<n where groups.landmassOfCell[cell] >= 0 {
			let polygon = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: map.width, height: map.height)
			polygons[cell] = polygon
			areas[cell] = polygon.count >= 3 ? abs(RealmSeeds.polygonArea(polygon)) : 0
		}
		return try compute(groups: groups, seeds: seeds, neighbours: v.cells.c, sites: map.grid.points, heights: map.heights, areas: areas, polygons: polygons, width: map.width, height: map.height, mapSeed: map.seed, realmSeed: realmSeed, policy: policy)
	}

	/// **The verification of the links as over-water crossings:** each link must be a genuine witness (each point on the boundary of its declared cell, the stored
	/// distance agreeing with the segment) and its segment a clean crossing (not over land, not touching other land ambiguously, finite), within `budget` tests;
	/// anything else throws. Growth runs it before any growth, and the realm layer's validation runs it before a saved realm's connectivity is trusted over a link.
	static func verifyCrossings(groups: LandGroups, polygons: [[Point]], width: Double, height: Double, budget: Int) throws {
		var verification = 0
		let tolerance = 1e-9 * max(width, height)
		let bounds: [(minX: Double, minY: Double, maxX: Double, maxY: Double)] = polygons.map { p in
			p.isEmpty ? (0, 0, -1, -1) : (p.map(\.x).min()!, p.map(\.y).min()!, p.map(\.x).max()!, p.map(\.y).max()!)
		}
		for link in groups.links {
			guard try crossingIsClean(link, groups: groups, polygons: polygons, bounds: bounds, tolerance: tolerance, tests: &verification, budget: budget) else {
				throw Problem.unusableCrossing(landmassA: link.landmassA, landmassB: link.landmassB)
			}
		}
	}

	// MARK: the work, over explicit data

	/// A crossing as growth uses it: from cell `from` to cell `to`, with its total cost before division by an expansion factor.
	struct Crossing { var to: Int; var cost: Double }

	static func compute(groups: LandGroups, seeds: RealmSeeds, neighbours: [[Int]], sites: [Point], heights: [Height], areas: [Double], polygons: [[Point]], width: Double, height: Double, mapSeed: String, realmSeed: String, policy: GrowthPolicy, expansionFactors: [Double]? = nil) throws -> RealmOwnership {
		guard policy.isValid else { throw Problem.invalidPolicy }
		let n = groups.groupOfCell.count
		guard validateInputs(groups: groups, seeds: seeds, neighbours: neighbours, sites: sites, heights: heights, areas: areas, polygons: polygons, width: width, height: height) else { throw Problem.invalidInputs }
		let k = seeds.realms.count

		func terrain(_ cell: Int) -> Double { heights[cell] >= 67 ? policy.mountainFactor : heights[cell] >= 44 ? policy.hillFactor : 1 }
		func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }

		// the links as crossings, verified before any growth
		var crossings = [Int: [Crossing]]()
		try verifyCrossings(groups: groups, polygons: polygons, width: width, height: height, budget: policy.verificationTests)
		for link in groups.links {
			// the land approaches are charged at the terrain of the cell they lie in, the sea portion at the crossing factor
			let sea = policy.crossingFactor * distance(link.pointA, link.pointB)
			let approachA = distance(sites[link.cellA], link.pointA) * terrain(link.cellA)
			let approachB = distance(sites[link.cellB], link.pointB) * terrain(link.cellB)
			let cost = approachA + sea + approachB
			guard cost.isFinite else { throw Problem.nonFiniteCost }
			crossings[link.cellA, default: []].append(Crossing(to: link.cellB, cost: cost))
			crossings[link.cellB, default: []].append(Crossing(to: link.cellA, cost: cost))
		}

		// the expansion factors: 1 + unevenness x r_i, one draw per realm in realm-number order
		var alea = Alea(seed: "\(mapSeed)_growth_\(realmSeed)")
		var factors = (0..<k).map { _ in 1 + policy.unevenness * alea.next() }
		if let forced = expansionFactors, forced.count == k { factors = forced } // a hook for tests: exact factors for a counterexample

		// the work that can be known first: each directed edge proposes at most once, from the cell that claims it
		var directedEdges = 0
		for cell in 0..<n where groups.landmassOfCell[cell] >= 0 {
			directedEdges += neighbours[cell].filter { $0 >= 0 && $0 < n && groups.landmassOfCell[$0] >= 0 }.count + (crossings[cell]?.count ?? 0)
		}
		guard directedEdges <= policy.heapPushes else { throw Problem.workBudget("pushes") }
		guard directedEdges <= policy.edgeExaminations else { throw Problem.workBudget("edges") }

		var owner = [Int32](repeating: 0, count: n)
		var accumulated = [Double](repeating: 0, count: n)
		var heap = Heap()
		var pushes = 0, pops = 0, edges = 0

		func relax(_ cell: Int, realm: Int) throws {
			let factor = factors[realm - 1]
			for other in neighbours[cell] where other >= 0 && other < n && groups.landmassOfCell[other] >= 0 {
				edges += 1
				guard edges <= policy.edgeExaminations else { throw Problem.workBudget("edges") }
				guard owner[other] == 0 else { continue }
				let cost = accumulated[cell] + distance(sites[cell], sites[other]) * terrain(other) / factor
				guard cost.isFinite else { throw Problem.nonFiniteCost }
				pushes += 1
				guard pushes <= policy.heapPushes else { throw Problem.workBudget("pushes") }
				heap.push(Proposal(cost: cost, realm: Int32(realm), cell: Int32(other)))
			}
			for crossing in crossings[cell] ?? [] {
				edges += 1
				guard edges <= policy.edgeExaminations else { throw Problem.workBudget("edges") }
				guard owner[crossing.to] == 0 else { continue }
				let cost = accumulated[cell] + crossing.cost / factor
				guard cost.isFinite else { throw Problem.nonFiniteCost }
				pushes += 1
				guard pushes <= policy.heapPushes else { throw Problem.workBudget("pushes") }
				heap.push(Proposal(cost: cost, realm: Int32(realm), cell: Int32(crossing.to)))
			}
		}

		// every seed is reserved for its realm before growth begins
		for realm in seeds.realms { owner[realm.cell] = Int32(realm.number) }
		for realm in seeds.realms { try relax(realm.cell, realm: realm.number) }
		while let proposal = heap.pop() {
			pops += 1
			guard pops <= policy.heapPops else { throw Problem.workBudget("pops") }
			let cell = Int(proposal.cell)
			guard owner[cell] == 0 else { continue } // stale: a finalized owner is never overwritten
			owner[cell] = proposal.realm
			accumulated[cell] = proposal.cost
			try relax(cell, realm: Int(proposal.realm))
		}
		for cell in 0..<n where groups.landmassOfCell[cell] >= 0 && owner[cell] == 0 { throw Problem.unreachableLand(cell: cell) }

		var summaries = seeds.realms.map { Realm(number: $0.number, group: $0.group, seedCell: $0.cell, cellCount: 0, area: 0) }
		for cell in 0..<n where owner[cell] > 0 {
			summaries[Int(owner[cell]) - 1].cellCount += 1
			summaries[Int(owner[cell]) - 1].area += areas[cell]
		}
		return RealmOwnership(owner: owner, realms: summaries, policy: policy)
	}

	/// Structural checks of everything supplied, before any work. Every range is checked **before** any conversion or sum, so malformed
	/// metadata is refused and never traps. A link is accepted only if it is a genuine witness: each point lies on the boundary of its
	/// declared cell, the stored distance agrees with the segment's length, and a zero-length link is a point both cells really share.
	/// The numerical policy: a tolerance of 1e-9 of the map's larger side.
	static func validateInputs(groups: LandGroups, seeds: RealmSeeds, neighbours: [[Int]], sites: [Point], heights: [Height], areas: [Double], polygons: [[Point]], width: Double, height: Double) -> Bool {
		let n = groups.groupOfCell.count
		guard RealmSeeds.validate(groups, cellCount: n), neighbours.count >= n, sites.count == n, sites.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), heights.count == n, areas.count == n, polygons.count == n else { return false }
		guard width.isFinite, height.isFinite, width > 0, height > 0 else { return false }
		guard seeds.resolvedCount == seeds.realms.count, !seeds.realms.isEmpty, seeds.realmsPerGroup.count == groups.groups.count else { return false }
		var used = Set<Int>()
		var perGroup = [Int](repeating: 0, count: groups.groups.count)
		for (i, realm) in seeds.realms.enumerated() {
			// ranges first: nothing is converted or indexed before it is known to be in range
			guard realm.number == i + 1, realm.group >= 0, realm.group < perGroup.count, realm.cell >= 0, realm.cell < n else { return false }
			guard Int(groups.groupOfCell[realm.cell]) == realm.group, used.insert(realm.cell).inserted else { return false }
			perGroup[realm.group] += 1
		}
		guard perGroup == seeds.realmsPerGroup else { return false } // counts compared with the actual membership, with no unchecked sum
		let tolerance = 1e-9 * max(width, height)
		for link in groups.links {
			guard link.cellA >= 0, link.cellA < n, link.cellB >= 0, link.cellB < n,
				link.landmassA >= 0, link.landmassA < groups.landmasses.count, link.landmassB >= 0, link.landmassB < groups.landmasses.count, link.landmassA != link.landmassB,
				Int(groups.landmassOfCell[link.cellA]) == link.landmassA, Int(groups.landmassOfCell[link.cellB]) == link.landmassB,
				link.distance.isFinite, link.distance >= 0, [link.pointA.x, link.pointA.y, link.pointB.x, link.pointB.y].allSatisfy({ $0.isFinite }) else { return false }
			guard linkIsGenuine(link, polygons: polygons, tolerance: tolerance) else { return false }
		}
		return true
	}

	/// The distance from a point to a polygon's boundary (infinite for fewer than three points).
	static func boundaryDistance(_ p: Point, _ polygon: [Point]) -> Double {
		guard polygon.count >= 3 else { return .infinity }
		var best = Double.infinity
		for i in polygon.indices { best = min(best, LandGroups.closestOnSegment(p, polygon[i], polygon[(i + 1) % polygon.count]).distance) }
		return best
	}

	/// Whether a link is a genuine witness of its two cells: `pointA` is on the boundary of `cellA`'s polygon and `pointB` on
	/// `cellB`'s; the stored `distance` agrees with the segment's length; and a zero-length link is accepted only when the one point
	/// is on both cells' boundaries. Within the stated tolerance.
	static func linkIsGenuine(_ link: LandGroups.Link, polygons: [[Point]], tolerance: Double) -> Bool {
		let length = ((link.pointA.x - link.pointB.x) * (link.pointA.x - link.pointB.x) + (link.pointA.y - link.pointB.y) * (link.pointA.y - link.pointB.y)).squareRoot()
		guard length.isFinite, abs(length - link.distance) <= tolerance else { return false }
		guard boundaryDistance(link.pointA, polygons[link.cellA]) <= tolerance, boundaryDistance(link.pointB, polygons[link.cellB]) <= tolerance else { return false }
		// a zero-length link needs nothing more: its one point is on the boundary of both cells (the two checks above, since the points
		// are equal) and its stored distance is zero (the agreement check), so it is a point both cells really share
		return true
	}

	/// Whether a link's segment is a clean over-water crossing. It may touch the land of **its own two landmasses, the endpoint cells
	/// included,** only at its end points (within a tolerance of 1e-9 of the map's larger side, so a point on an edge shared with a
	/// neighbouring cell is not mistaken for overlap), and it must not touch any other land cell at all: passing through, touching
	/// at a vertex and running along an edge are all refused, as are polygons that are not usable.
	///
	/// **A short crossing is not given the benefit of the doubt:** the allowance is a fraction `tolerance / length` of the segment, so
	/// if the segment is shorter than 100 tolerances the allowance could cover a meaningful part of it, and a non-zero crossing that
	/// short is refused as ambiguous. A zero-length crossing (a corner contact) must not touch any land of a third landmass.
	/// Ordinary Double arithmetic: a near miss and a near touch fall on whichever side the arithmetic puts them.
	static func crossingIsClean(_ link: LandGroups.Link, groups: LandGroups, polygons: [[Point]], bounds: [(minX: Double, minY: Double, maxX: Double, maxY: Double)], tolerance: Double, tests: inout Int, budget: Int) throws -> Bool {
		let a = link.pointA, b = link.pointB
		let length = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
		guard length.isFinite else { return false }
		let zero = length == 0
		guard zero || length > 100 * tolerance else { return false }
		let touchLimit = zero ? 0 : tolerance / length
		let minX = min(a.x, b.x) - tolerance, maxX = max(a.x, b.x) + tolerance, minY = min(a.y, b.y) - tolerance, maxY = max(a.y, b.y) + tolerance
		for cell in 0..<polygons.count where groups.landmassOfCell[cell] >= 0 {
			tests += 1
			guard tests <= budget else { throw Problem.workBudget("verification") }
			let box = bounds[cell]
			guard box.minX <= maxX, box.maxX >= minX, box.minY <= maxY, box.maxY >= minY else { continue } // boxes apart: no contact
			let polygon = polygons[cell]
			guard polygon.count >= 3 else { continue }
			let landmass = Int(groups.landmassOfCell[cell])
			if zero {
				// the shared point may lie in the cells of the two landmasses it joins, and in no other land
				if landmass != link.landmassA && landmass != link.landmassB && (boundaryDistance(a, polygon) <= tolerance || pointInside(a, polygon)) { return false }
				continue
			}
			guard let (lo, hi) = interval(of: a, b, inside: polygon) else { continue }
			if landmass == link.landmassA && hi <= touchLimit { continue } // touches its own land only at the departure end
			if landmass == link.landmassB && lo >= 1 - touchLimit { continue } // and the arrival end
			return false
		}
		return true
	}

	/// Whether a point is inside or on a convex polygon.
	static func pointInside(_ p: Point, _ polygon: [Point]) -> Bool {
		guard let (lo, hi) = interval(of: p, p, inside: polygon) else { return false }
		return lo <= hi
	}

	/// The parameter interval of the closed segment a to b inside a convex polygon (boundary included), or nil if they do not meet.
	static func interval(of a: Point, _ b: Point, inside polygon: [Point]) -> (Double, Double)? {
		var area = 0.0
		for (p, q) in zip(polygon, polygon.dropFirst() + [polygon[0]]) { area += p.x * q.y - q.x * p.y }
		guard area != 0 else { return nil }
		let sign: Double = area > 0 ? 1 : -1
		var lo = 0.0, hi = 1.0
		for i in polygon.indices {
			let p = polygon[i], q = polygon[(i + 1) % polygon.count]
			let f0 = sign * ((q.x - p.x) * (a.y - p.y) - (q.y - p.y) * (a.x - p.x))
			let f1 = sign * ((q.x - p.x) * (b.y - p.y) - (q.y - p.y) * (b.x - p.x))
			if f0 >= 0 && f1 >= 0 { continue }
			if f0 < 0 && f1 < 0 { return nil }
			let t = f0 / (f0 - f1)
			if f0 < 0 { lo = max(lo, t) } else { hi = min(hi, t) }
			if lo > hi { return nil }
		}
		return (lo, hi)
	}

	// MARK: the independent check

	/// An independent check of an ownership, used by the tests and available to callers: returns what is wrong, empty if nothing.
	/// Every land cell is owned and no water cell is; every realm owns at least its seed; each realm is connected by a separate
	/// breadth-first search over land adjacency and the links, a link joining a realm's pieces only if both end cells are its own.
	/// **The work is linear in the cells, their neighbours and the links** whatever the number of realms: the owners are counted once, and each realm's search
	/// visits only the cells that realm owns.
	public static func problems(in ownership: RealmOwnership, groups: LandGroups, seeds: RealmSeeds, neighbours: [[Int]]) -> [String] {
		var work = 0
		return problems(in: ownership, groups: groups, seeds: seeds, neighbours: neighbours, work: &work)
	}

	/// The same, counting the work: one for each cell scanned, each cell a search takes from its queue, and each neighbour or link it examines.
	static func problems(in ownership: RealmOwnership, groups: LandGroups, seeds: RealmSeeds, neighbours: [[Int]], work: inout Int) -> [String] {
		var found: [String] = []
		let n = groups.groupOfCell.count
		// structural guards first: malformed inputs are reported, never trapped on
		guard ownership.owner.count == n else { return ["the owner array has the wrong length"] }
		guard groups.landmassOfCell.count == n else { return ["the landmass array has the wrong length"] }
		guard neighbours.count >= n else { return ["the neighbour lists are shorter than the cells"] }
		for (i, realm) in seeds.realms.enumerated() where realm.cell < 0 || realm.cell >= n { found.append("seed \(i + 1) is outside the map") }
		for link in groups.links where link.cellA < 0 || link.cellA >= n || link.cellB < 0 || link.cellB >= n { found.append("a link refers to a cell outside the map") }
		guard found.isEmpty else { return found }
		// the owners, counted once
		var counts = [Int](repeating: 0, count: seeds.realms.count + 1)
		for cell in 0..<n {
			work += 1
			let land = groups.landmassOfCell[cell] >= 0
			let owner = ownership.owner[cell]
			if land && owner <= 0 { found.append("land cell \(cell) has no owner") }
			if !land && owner != 0 { found.append("water cell \(cell) has an owner") }
			if owner > Int32(seeds.realms.count) || owner < 0 { found.append("cell \(cell) has the invalid owner \(owner)") } else { counts[Int(owner)] += 1 }
		}
		var linked = [Int: [Int]]()
		for link in groups.links { work += 1; linked[link.cellA, default: []].append(link.cellB); linked[link.cellB, default: []].append(link.cellA) }
		for realm in seeds.realms {
			guard ownership.owner[realm.cell] == Int32(realm.number) else { found.append("realm \(realm.number) does not own its seed"); continue }
			var seen = Set([realm.cell])
			var queue = [realm.cell]
			var head = 0
			while head < queue.count {
				let cell = queue[head]; head += 1
				work += 1
				for other in neighbours[cell] where other >= 0 && other < n {
					work += 1
					if ownership.owner[other] == Int32(realm.number) && seen.insert(other).inserted { queue.append(other) }
				}
				for other in linked[cell] ?? [] {
					work += 1
					if ownership.owner[other] == Int32(realm.number) && seen.insert(other).inserted { queue.append(other) }
				}
			}
			let owned = realm.number >= 1 && realm.number < counts.count ? counts[realm.number] : 0
			if seen.count != owned { found.append("realm \(realm.number) is not connected: \(seen.count) of its \(owned) cells are reachable from its seed") }
		}
		return found
	}

	// MARK: the heap

	struct Proposal { var cost: Double; var realm: Int32; var cell: Int32 }

	/// A binary heap keyed by (cost, realm number, cell index): a total order, so the result does not depend on insertion order.
	struct Heap {
		private var items: [Proposal] = []
		private func less(_ a: Proposal, _ b: Proposal) -> Bool {
			if a.cost != b.cost { return a.cost < b.cost }
			if a.realm != b.realm { return a.realm < b.realm }
			return a.cell < b.cell
		}
		mutating func push(_ p: Proposal) {
			items.append(p)
			var i = items.count - 1
			while i > 0 {
				let parent = (i - 1) / 2
				if less(items[i], items[parent]) { items.swapAt(i, parent); i = parent } else { break }
			}
		}
		mutating func pop() -> Proposal? {
			guard let top = items.first else { return nil }
			let last = items.removeLast()
			if !items.isEmpty {
				items[0] = last
				var i = 0
				while true {
					let l = 2 * i + 1, r = l + 1
					var smallest = i
					if l < items.count && less(items[l], items[smallest]) { smallest = l }
					if r < items.count && less(items[r], items[smallest]) { smallest = r }
					if smallest == i { break }
					items.swapAt(i, smallest)
					i = smallest
				}
			}
			return top
		}
	}
}
