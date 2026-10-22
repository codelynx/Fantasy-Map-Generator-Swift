import Foundation

/// How the number of realms is asked for.
public enum RealmCount: Equatable, Sendable {
	/// The package works the count out from the map, the reach and the policy.
	case automatic
	/// The author's own count.
	case chosen(Int)
}

/// The explicit policy inputs of realm seeding. There are **no hidden placeholder constants**: a caller supplies them. The typical
/// realm area is a product choice and the maximum count is a resource policy; their defaults are not settled.
public struct RealmPolicy: Equatable, Sendable {
	/// The land area, in map units², a realm is typically given; the automatic count is the land area divided by it. Finite and above 0.
	public var typicalRealmArea: Double
	/// The most realms accepted, 1 or more: a resource cap, not a geographic limit.
	public var maximumRealms: Int
	/// How many candidate cells are sampled (without replacement) when placing each seed after the first, 1 or more. An advanced
	/// input with a provisional default: it changes both the work and the seeds, so **determinism includes the policy**, and it
	/// belongs in the generation recipe whenever reproducible regeneration is supported.
	public var sampleSize: Int
	/// The most candidate-to-seed distance evaluations seed placement may do, 0 or more; refused beyond, never approximated.
	public var workBudget: Int

	public init(typicalRealmArea: Double, maximumRealms: Int, sampleSize: Int = 24, workBudget: Int = 50_000_000) {
		self.typicalRealmArea = typicalRealmArea
		self.maximumRealms = maximumRealms
		self.sampleSize = sampleSize
		self.workBudget = workBudget
	}

	var isValid: Bool { typicalRealmArea.isFinite && typicalRealmArea > 0 && maximumRealms >= 1 && sampleSize >= 1 && workBudget >= 0 }
}

/// The resolved realm count and the seed cell of every realm (realms step 2, docs/plans/realms.md): no growth yet.
///
/// The automatic count is a deterministic function of the groups' areas: **each group gets max(1, round(its area ÷ the typical
/// realm area)) realms, at most its cell count,** and the sum is the count (capped at the maximum, then shared by area). It is at
/// least C by construction.
///
/// Realm numbers 1 to K run in group order, then in the order the group's seeds were placed; they identify the seeds growth
/// expands and are not renumbered afterwards. **Deterministic for identical inputs**; nothing is promised across a changed count,
/// reach or geography.
public struct RealmSeeds: Equatable, Sendable {
	public struct Realm: Equatable, Sendable {
		/// 1 to K.
		public var number: Int
		public var group: Int
		/// The seed cell: a land cell of that group.
		public var cell: Int
	}

	public var mode: RealmCount
	public var resolvedCount: Int
	/// How many realms each group holds, in group order.
	public var realmsPerGroup: [Int]
	public var realms: [Realm]

	public enum Problem: Error, Equatable, Sendable {
		case noLand
		case invalidPolicy
		/// A chosen count below 1.
		case countBelowOne
		/// A chosen count below the minimum the reach allows (C): incompatible with the reach.
		case belowMinimum(minimum: Int)
		/// A chosen count above the number of land cells.
		case aboveLandCells(landCells: Int)
		/// A chosen count above the maximum.
		case aboveMaximum(maximum: Int)
		/// C itself exceeds the maximum, so no count satisfies both: refused in both modes, never reduced or widened.
		case minimumAboveMaximum(minimum: Int, maximum: Int)
		/// The groups are not consistent with each other or with the map (wrong lengths, indices out of range, land/water
		/// membership, counts). They must come from `LandGroups.find` for this map.
		case invalidGroups
		/// The seeding work would exceed the policy's budget.
		case workBudget
		/// A pool ran out before the accepted count was placed: an implementation failure, never fewer seeds.
		case poolExhausted
	}

	/// The count and seeds for a map whose groups step 1 found. **`groups` must come from `LandGroups.find` for this same map;** it
	/// is publicly mutable, so it is checked structurally here, before any work (the geometric search is not repeated). The policy
	/// is validated first, then the groups. Weights and the automatic count use the summed areas of the land cells' raw polygons
	/// clipped to the map rectangle.
	public static func place(in map: LandMap, groups: LandGroups, count: RealmCount, realmSeed: String, policy: RealmPolicy) throws -> RealmSeeds {
		guard policy.isValid else { throw Problem.invalidPolicy }
		let v = map.voronoi
		let n = map.heights.count
		guard validate(groups, cellCount: n) else { throw Problem.invalidGroups }
		for cell in 0..<n where (groups.landmassOfCell[cell] >= 0) != Heights.isLand(map.heights[cell]) { throw Problem.invalidGroups }
		var areas = [Double](repeating: 0, count: n)
		for cell in 0..<n where groups.landmassOfCell[cell] >= 0 {
			let polygon = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: map.width, height: map.height)
			areas[cell] = polygon.count >= 3 ? abs(polygonArea(polygon)) : 0
		}
		return try compute(groups: groups, areas: areas, sites: map.grid.points, mapSeed: map.seed, count: count, realmSeed: realmSeed, policy: policy)
	}

	static func polygonArea(_ p: [Point]) -> Double {
		var sum = 0.0
		for (a, b) in zip(p, p.dropFirst() + [p[0]]) { sum += a.x * b.y - b.x * a.y }
		return sum / 2
	}

	/// Whether the groups are structurally consistent for `cellCount` cells: the per-cell arrays have that length; every landmass
	/// and group index is in range; land and water agree between the two arrays; each landmass belongs to the group its cells
	/// say; and the stored cell counts equal the counts of the cells.
	static func validate(_ groups: LandGroups, cellCount: Int) -> Bool {
		guard groups.landmassOfCell.count == cellCount, groups.groupOfCell.count == cellCount else { return false }
		var landmassCells = [Int](repeating: 0, count: groups.landmasses.count)
		var groupCells = [Int](repeating: 0, count: groups.groups.count)
		for cell in 0..<cellCount {
			let l = Int(groups.landmassOfCell[cell]), g = Int(groups.groupOfCell[cell])
			if l == -1 || g == -1 { guard l == -1 && g == -1 else { return false }; continue }
			guard l >= 0, l < landmassCells.count, g >= 0, g < groupCells.count, groups.landmasses[l].group == g else { return false }
			landmassCells[l] += 1
			groupCells[g] += 1
		}
		for (l, landmass) in groups.landmasses.enumerated() where landmass.cellCount != landmassCells[l] || landmass.group < 0 || landmass.group >= groupCells.count { return false }
		for (g, group) in groups.groups.enumerated() {
			guard group.cellCount == groupCells[g], group.landmasses.allSatisfy({ $0 >= 0 && $0 < landmassCells.count && groups.landmasses[$0].group == g }) else { return false }
			guard group.landmasses.reduce(0, { $0 + groups.landmasses[$1].cellCount }) == group.cellCount else { return false }
		}
		return true
	}

	/// The same over explicit data: `areas` and `sites` are indexed by cell.
	static func compute(groups: LandGroups, areas: [Double], sites: [Point], mapSeed: String, count: RealmCount, realmSeed: String, policy: RealmPolicy) throws -> RealmSeeds {
		guard policy.isValid else { throw Problem.invalidPolicy }
		guard areas.count == groups.groupOfCell.count, sites.count == groups.groupOfCell.count, validate(groups, cellCount: groups.groupOfCell.count) else { throw Problem.invalidGroups }
		guard !groups.groups.isEmpty else { throw Problem.noLand }
		let minimum = groups.groups.count
		let landCells = groups.groups.reduce(0) { $0 + $1.cellCount }
		guard minimum <= policy.maximumRealms else { throw Problem.minimumAboveMaximum(minimum: minimum, maximum: policy.maximumRealms) }
		let upper = min(landCells, policy.maximumRealms)

		// the area of each group's land (clipped cell polygons); weights fall back to cell counts if every area is zero
		var areaOfGroup = [Double](repeating: 0, count: minimum)
		var cellsOf = [[Int]](repeating: [], count: minimum)
		for cell in groups.groupOfCell.indices where groups.groupOfCell[cell] >= 0 {
			let g = Int(groups.groupOfCell[cell])
			areaOfGroup[g] += areas[cell]
			cellsOf[g].append(cell)
		}
		var weights = areaOfGroup
		if !(weights.reduce(0, +) > 0) { weights = groups.groups.map { Double($0.cellCount) } }
		var automaticExtra: [Int]?

		let resolved: Int
		switch count {
		case .chosen(let k):
			guard k >= 1 else { throw Problem.countBelowOne }
			guard k >= minimum else { throw Problem.belowMinimum(minimum: minimum) }
			guard k <= landCells else { throw Problem.aboveLandCells(landCells: landCells) }
			guard k <= policy.maximumRealms else { throw Problem.aboveMaximum(maximum: policy.maximumRealms) }
			resolved = k
		case .automatic:
			// **Each group gets the realms its own area asks for:** max(1, round(group area ÷ typical realm area)), never more than its
			// cells. The sum is the count, so a large landmass gets several realms and a speck keeps one (the earlier rule, the total
			// area over the typical area, let groups of specks use up the count meant for large land). If the sum exceeds the cap, the
			// count is the cap and the realms are shared among the groups by area (the allocation below).
			let perGroup = (0..<minimum).map { g -> Int in
				let wanted = (areaOfGroup[g] / policy.typicalRealmArea).rounded()
				let asked = wanted.isFinite ? Int(max(min(wanted, Double(Int.max / 4)), 0)) : Int.max / 4
				return min(groups.groups[g].cellCount, max(1, asked))
			}
			let sum = perGroup.reduce(0, +)
			if sum <= policy.maximumRealms {
				resolved = sum
				automaticExtra = perGroup.map { $0 - 1 }
			} else {
				resolved = upper
			}
		}

		let extra = automaticExtra ?? allocate(extra: resolved - minimum, weights: weights, capacities: groups.groups.map { $0.cellCount - 1 })

		// the work is known exactly before any seed is placed: placing the k-th seed of a group (k seeds already placed, a pool of
		// N - k cells) evaluates min(sample size, N - k) candidates against k seeds. Every product and sum is overflow-checked.
		var work = 0
		for g in 0..<minimum {
			let pool = cellsOf[g].count
			for placed in 1..<max(extra[g] + 1, 1) {
				let (evaluations, o1) = min(policy.sampleSize, pool - placed).multipliedReportingOverflow(by: placed)
				let (total, o2) = work.addingReportingOverflow(evaluations)
				guard !o1, !o2, total <= policy.workBudget else { throw Problem.workBudget }
				work = total
			}
		}

		var alea = Alea(seed: "\(mapSeed)_realms_\(realmSeed)")
		var realms: [Realm] = []
		for g in 0..<minimum {
			var pool = cellsOf[g]
			var placed: [Int] = []
			for _ in 0..<(extra[g] + 1) {
				guard !pool.isEmpty else { throw Problem.poolExhausted }
				let chosenAt: Int
				if placed.isEmpty {
					chosenAt = Int(alea.next() * Double(pool.count))
				} else {
					// a sample without replacement (a partial shuffle of the pool), then the candidate farthest from the seeds so far
					let s = min(pool.count, policy.sampleSize)
					var bestAt = 0, bestDistance = -1.0
					for i in 0..<s {
						let j = i + Int(alea.next() * Double(pool.count - i))
						pool.swapAt(i, j)
						let site = sites[pool[i]]
						var nearest = Double.infinity
						for seed in placed {
							let dx = site.x - sites[seed].x, dy = site.y - sites[seed].y
							nearest = min(nearest, dx * dx + dy * dy)
						}
						if nearest > bestDistance || (nearest == bestDistance && pool[i] < pool[bestAt]) { bestDistance = nearest; bestAt = i }
					}
					chosenAt = bestAt
				}
				let cell = pool[chosenAt]
				pool.swapAt(chosenAt, pool.count - 1)
				pool.removeLast()
				placed.append(cell)
				realms.append(Realm(number: realms.count + 1, group: g, cell: cell))
			}
		}
		return RealmSeeds(mode: count, resolvedCount: resolved, realmsPerGroup: extra.map { $0 + 1 }, realms: realms)
	}

	/// Capacity-constrained largest remainder: shares `extra` realms among groups in proportion to `weights`, no group above its
	/// `capacity`; a group whose floored quota exceeds its capacity is saturated and removed, the quotas are recomputed over the
	/// rest, and what is still owed after the floors goes one at a time by largest fractional part, ties to the smaller group
	/// number, never past a capacity. `extra` must not exceed the total capacity. Double arithmetic; no randomness.
	static func allocate(extra: Int, weights: [Double], capacities: [Int]) -> [Int] {
		var given = [Int](repeating: 0, count: weights.count)
		var open = Array(weights.indices)
		var remaining = extra
		while remaining > 0, !open.isEmpty {
			let total = open.reduce(0.0) { $0 + weights[$1] }
			let quotas = open.map { total > 0 ? Double(remaining) * weights[$0] / total : Double(remaining) / Double(open.count) }
			let saturated = open.indices.filter { Int(quotas[$0].rounded(.down)) > capacities[open[$0]] }
			if !saturated.isEmpty {
				for i in saturated { given[open[i]] = capacities[open[i]]; remaining -= capacities[open[i]] }
				let gone = Set(saturated)
				open = open.indices.filter { !gone.contains($0) }.map { open[$0] }
				continue
			}
			for (i, g) in open.enumerated() { given[g] = Int(quotas[i].rounded(.down)); remaining -= given[g] }
			let order = open.indices.sorted {
				let fa = quotas[$0] - quotas[$0].rounded(.down), fb = quotas[$1] - quotas[$1].rounded(.down)
				return fa != fb ? fa > fb : open[$0] < open[$1]
			}
			var progress = true
			while remaining > 0, progress {
				progress = false
				for i in order where remaining > 0 && given[open[i]] < capacities[open[i]] { given[open[i]] += 1; remaining -= 1; progress = true }
			}
			break
		}
		return given
	}
}
