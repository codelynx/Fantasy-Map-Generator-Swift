import Foundation
import Testing
@testable import FantasyMapCore

/// Realms step 1 (docs/plans/realms.md): landmasses, reach, groups and the links, on hand-made cells where the gaps are exact and
/// on generated maps against a brute-force search.
struct LandGroupsTests {
	/// A grid of square cells of side `s`, four-neighbour connected, from rows of "#" (land) and "." (water). Cell (row, column) is
	/// number row * columns + column.
	struct Cells {
		var rows: Int, columns: Int, s: Double
		var isLand: [Bool]
		init(_ picture: [String], side s: Double = 10) {
			rows = picture.count
			columns = picture[0].count
			self.s = s
			isLand = picture.flatMap { $0.map { $0 == "#" } }
		}
		var width: Double { Double(columns) * s }
		var height: Double { Double(rows) * s }
		var neighbours: [[Int]] {
			(0..<(rows * columns)).map { c in
				let r = c / columns, k = c % columns
				var list: [Int] = []
				if r > 0 { list.append(c - columns) }
				if k < columns - 1 { list.append(c + 1) }
				if r < rows - 1 { list.append(c + columns) }
				if k > 0 { list.append(c - 1) }
				return list
			}
		}
		func polygon(_ c: Int) -> [Point] {
			let x = Double(c % columns) * s, y = Double(c / columns) * s
			return [Point(x: x, y: y), Point(x: x + s, y: y), Point(x: x + s, y: y + s), Point(x: x, y: y + s)]
		}
		func groups(reach: Double, budgets: LandGroups.Budgets = .init()) throws -> LandGroups {
			try LandGroups.compute(isLand: isLand, neighbours: neighbours, width: width, height: height, bucketFloor: 0.25 * s, reach: reach, budgets: budgets, polygon: polygon)
		}
		/// The reference: compare every pair of land cells of different landmasses directly, under the stated policy.
		func brute(reach: Double) -> [Int32] {
			let n = isLand.count, nb = neighbours
			var landmass = [Int](repeating: -1, count: n)
			var count = 0
			for start in 0..<n where isLand[start] && landmass[start] < 0 {
				var stack = [start]
				landmass[start] = count
				while let c = stack.popLast() { for o in nb[c] where isLand[o] && landmass[o] < 0 { landmass[o] = count; stack.append(o) } }
				count += 1
			}
			var parent = Array(0..<count)
			func find(_ x: Int) -> Int { parent[x] == x ? x : find(parent[x]) }
			if reach > 0 {
				for a in 0..<n where isLand[a] { for b in (a + 1)..<n where isLand[b] && landmass[a] != landmass[b] {
					if LandGroups.polygonDistance(polygon(a), polygon(b)) <= reach { parent[max(find(landmass[a]), find(landmass[b]))] = min(find(landmass[a]), find(landmass[b])) }
				} }
			}
			// number the groups by smallest cell
			var number: [Int: Int32] = [:]
			var out = [Int32](repeating: -1, count: n)
			for c in 0..<n where isLand[c] {
				let root = find(landmass[c])
				if number[root] == nil { number[root] = Int32(number.count) }
				out[c] = number[root]!
			}
			return out
		}
	}

	// MARK: the geometry

	func boundaryDistance(_ p: Point, _ polygon: [Point]) -> Double {
		polygon.indices.map { LandGroups.pointSegmentDistance(p, polygon[$0], polygon[($0 + 1) % polygon.count]) }.min()!
	}

	@Test func closestPairsOnKnownShapes() {
		let a = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)]
		func shifted(_ dx: Double, _ dy: Double) -> [Point] { a.map { Point(x: $0.x + dx, y: $0.y + dy) } }
		let diagonal = LandGroups.closestPair(a, shifted(13, 14))
		#expect(diagonal.distance == 5 && diagonal.a == Point(x: 10, y: 10) && diagonal.b == Point(x: 13, y: 14), "corner to corner: a 3-4-5 triangle")
		let sideways = LandGroups.closestPair(a, shifted(15, 3))
		#expect(sideways.distance == 5 && sideways.a.x == 10 && sideways.b.x == 15, "facing sides: the gap is 5 wherever the pair falls")
		#expect(sideways.a.y == sideways.b.y, "a perpendicular segment between parallel sides")
		let corner = LandGroups.closestPair(a, shifted(10, 10))
		#expect(corner.distance == 0 && corner.a == corner.b && corner.a == Point(x: 10, y: 10), "a corner contact is a zero-length segment at the shared point")
		// the order of the arguments mirrors the points, and the choice is deterministic
		let forward = LandGroups.closestPair(a, shifted(13, 14)), back = LandGroups.closestPair(shifted(13, 14), a)
		#expect(forward.distance == back.distance && forward.a == back.b && forward.b == back.a)
		#expect(LandGroups.closestPair(a, shifted(15, 3)) == LandGroups.closestPair(a, shifted(15, 3)))
	}

	@Test func polygonDistanceOnKnownShapes() {
		let a = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)]
		func shifted(_ dx: Double, _ dy: Double) -> [Point] { a.map { Point(x: $0.x + dx, y: $0.y + dy) } }
		#expect(LandGroups.polygonDistance(a, shifted(13, 0)) == 3, "side by side")
		#expect(LandGroups.polygonDistance(a, shifted(13, 14)) == 5, "diagonal gap 3 and 4")
		#expect(LandGroups.polygonDistance(a, shifted(10, 0)) == 0, "sharing an edge")
		#expect(LandGroups.polygonDistance(a, shifted(10, 10)) == 0, "sharing only a corner")
		#expect(LandGroups.polygonDistance(a, a) == 0)
		#expect(LandGroups.pointSegmentDistance(Point(x: 5, y: 3), Point(x: 0, y: 0), Point(x: 10, y: 0)) == 3)
		#expect(LandGroups.pointSegmentDistance(Point(x: 13, y: 4), Point(x: 0, y: 0), Point(x: 10, y: 0)) == 5, "beyond the end")
		#expect(LandGroups.pointSegmentDistance(Point(x: 1, y: 1), Point(x: 2, y: 2), Point(x: 2, y: 2)) == (2.0).squareRoot(), "a zero-length segment is a point")
	}

	@Test func theSharedRectangleClip() {
		let r = { (p: [Point]) in RectangleClip.clip(p, width: 100, height: 50) }
		let inside = [Point(x: 10, y: 10), Point(x: 20, y: 10), Point(x: 20, y: 20), Point(x: 10, y: 20)]
		#expect(r(inside) == inside, "a polygon inside is unchanged")
		let across = [Point(x: -10, y: 10), Point(x: 10, y: 10), Point(x: 10, y: 20), Point(x: -10, y: 20)]
		#expect(r(across).map(\.x).min() == 0 && r(across).map(\.x).max() == 10, "cut at the left edge")
		#expect(r([Point(x: 200, y: 10), Point(x: 210, y: 10), Point(x: 210, y: 20)]).isEmpty, "a polygon outside is empty")
		let corner = [Point(x: -5, y: -5), Point(x: 5, y: -5), Point(x: 5, y: 5), Point(x: -5, y: 5)]
		let cut = r(corner)
		#expect(cut.count == 4 && cut.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x <= 5 && $0.y <= 5 }, "a corner cut")
		#expect(r([]).isEmpty)
	}

	// MARK: landmasses and groups on hand-made cells

	@Test func reachZeroLeavesEveryLandmassItsOwnGroupAndAPositiveReachJoinsByGap() throws {
		let c = Cells(["#..#"]) // two landmasses, a gap of two cells = 20
		let zero = try c.groups(reach: 0)
		#expect(zero.landmasses.count == 2 && zero.groups.count == 2 && zero.minimumRealms == 2 && zero.links.isEmpty)
		#expect(try c.groups(reach: 19.999).groups.count == 2, "just below the gap")
		let exact = try c.groups(reach: 20)
		#expect(exact.groups.count == 1 && exact.minimumRealms == 1, "exactly at the gap: inclusive")
		// the two squares are 20 apart along their whole facing sides; the first closest pair in the fixed order is kept: vertex (10, 0) of
		// the first square against the second square's edge, closest at (30, 0)
		#expect(exact.links == [LandGroups.Link(landmassA: 0, landmassB: 1, cellA: 0, cellB: 3, distance: 20, pointA: Point(x: 10, y: 0), pointB: Point(x: 30, y: 0))])
		#expect(try c.groups(reach: 1e300).groups.count == 1, "a huge reach")
		#expect(try c.groups(reach: 1e-300).groups.count == 2, "a tiny positive reach does not join a gap")
	}

	@Test func aChainOfNearbyIslandsIsOneGroupWhoseEndsAreFarApart() throws {
		let c = Cells(["#.#.#.#"]) // gaps of one cell = 10, the ends are 60 apart
		let chain = try c.groups(reach: 10)
		#expect(chain.groups.count == 1 && chain.landmasses.count == 4 && chain.links.count == 3)
		#expect(chain.links.allSatisfy { $0.distance == 10 })
		#expect(try c.groups(reach: 9.99).groups.count == 4)
		#expect(chain.groupOfCell == [0, -1, 0, -1, 0, -1, 0])
	}

	@Test func cornerContactIsNotOneLandmassButAPositiveReachJoinsIt() throws {
		let c = Cells(["#.", ".#"]) // two squares touching only at a corner
		let zero = try c.groups(reach: 0)
		#expect(zero.landmasses.count == 2 && zero.groups.count == 2, "not one landmass, and reach 0 disables sea connections")
		let positive = try c.groups(reach: 0.001)
		#expect(positive.landmasses.count == 2 && positive.groups.count == 1, "a positive reach joins them (distance 0)")
		#expect(positive.links.first?.distance == 0)
	}

	@Test func theFrameJoinsNothingAndAnIslandInALakeIsItsOwnLandmass() throws {
		// two landmasses both touching the frame, a gap of 30 between them
		let frame = Cells(["#...#", "#...#"])
		#expect(try frame.groups(reach: 20).groups.count == 2)
		#expect(try frame.groups(reach: 30).groups.count == 1)
		let lake = Cells(["#####", "#...#", "#.#.#", "#...#", "#####"])
		let zero = try lake.groups(reach: 0)
		#expect(zero.landmasses.count == 2, "the ring of land and the island in the lake")
		#expect(zero.landmasses[0].cellCount == 16 && zero.landmasses[1].cellCount == 1)
		#expect(try lake.groups(reach: 9.99).groups.count == 2)
		#expect(try lake.groups(reach: 10).groups.count == 1)
	}

	@Test func noLandAndAllLand() throws {
		let water = try Cells(["....", "...."]).groups(reach: 50)
		#expect(water.landmasses.isEmpty && water.groups.isEmpty && water.minimumRealms == 0 && water.links.isEmpty)
		#expect(water.landmassOfCell.allSatisfy { $0 == -1 } && water.groupOfCell.allSatisfy { $0 == -1 })
		let land = try Cells(["###", "###"]).groups(reach: 50)
		#expect(land.landmasses.count == 1 && land.groups.count == 1 && land.minimumRealms == 1 && land.links.isEmpty)
		#expect(land.groups[0].cellCount == 6 && land.groupOfCell == [0, 0, 0, 0, 0, 0])
	}

	@Test func numberingIsBySmallestCellAndLinksAreTheClosestPairsAsASpanningForest() throws {
		// landmass 0 is cell 0; landmass 1 is cells 3 and 4 (wait: cell 3 is column 3); the closest pair between 0 and 1 is cells 0 and 3
		let c = Cells(["#..##", "....."])
		let g = try c.groups(reach: 100)
		#expect(g.landmasses.map(\.firstCell) == [0, 3] && g.landmassOfCell == [0, -1, -1, 1, 1, -1, -1, -1, -1, -1])
		#expect(g.links.count == 1 && g.links[0].cellA == 0 && g.links[0].cellB == 3 && g.links[0].distance == 20)
		// a triangle of three landmasses: the forest takes the two shortest links
		let t = Cells(["#.#", "...", "#.."])
		let tg = try t.groups(reach: 1000)
		#expect(tg.links.count == 2 && tg.groups.count == 1)
		#expect(tg.links.map(\.distance).sorted() == [10, 10], "cells 0-2 are 10 apart, and cells 0-6 are 10 apart; 2-6 is the diagonal")
	}

	@Test func aCoastCellWithADegeneratePolygonIsLeftOutAndItsLandmassCannotBeLinked() throws {
		let c = Cells(["#..#"])
		let g = try LandGroups.compute(isLand: c.isLand, neighbours: c.neighbours, width: c.width, height: c.height, bucketFloor: 2.5, reach: 100, polygon: { $0 == 3 ? [] : c.polygon($0) })
		#expect(g.landmasses.count == 2 && g.groups.count == 2 && g.links.isEmpty, "a landmass with no usable polygon stays its own group")
	}

	@Test func theReachMustBeFiniteAndNotNegative() {
		let c = Cells(["#.#"])
		for bad in [Double.nan, .infinity, -.infinity, -1, -1e-300] {
			#expect(throws: LandGroups.Problem.invalidReach) { try c.groups(reach: bad) }
		}
		#expect(throws: LandGroups.Problem.invalidGeometry) { try LandGroups.compute(isLand: [true], neighbours: [[]], width: 0, height: 1, bucketFloor: 1, reach: 1, polygon: { _ in [] }) }
		#expect(throws: LandGroups.Problem.invalidGeometry) { try LandGroups.compute(isLand: [true], neighbours: [[]], width: 1, height: 1, bucketFloor: 0, reach: 1, polygon: { _ in [] }) }
	}

	@Test func eachWorkBoundRefusesInsteadOfApproximating() {
		let c = Cells(["#.#.#.#.#", ".........", "#.#.#.#.#", ".........", "#.#.#.#.#"])
		var tight = LandGroups.Budgets()
		tight.insertions = 3
		#expect(throws: LandGroups.Problem.workBudget("insertions")) { try c.groups(reach: 20, budgets: tight) }
		tight = .init()
		tight.candidates = 3
		#expect(throws: LandGroups.Problem.workBudget("candidates")) { try c.groups(reach: 20, budgets: tight) }
		tight = .init()
		tight.distances = 2
		#expect(throws: LandGroups.Problem.workBudget("distances")) { try c.groups(reach: 20, budgets: tight) }
		// and the same input is fine with the default budgets
		#expect((try? c.groups(reach: 20)) != nil)
	}

	@Test func aPairOfManyVertexPolygonsIsRefusedByThePrimitiveBudgetBeforeItsDistanceIsComputed() throws {
		// two landmasses of one cell each (both next to a water cell); each cell's polygon has 600 vertices (a circle), so one candidate pair costs
		// 2 x 600 x 600 = 720,000 point-to-segment evaluations although it is a single "distance computation"
		func circle(_ cx: Double, _ cy: Double) -> [Point] { (0..<600).map { i in Point(x: cx + 4 * cos(Double(i) * .pi / 300), y: cy + 4 * sin(Double(i) * .pi / 300)) } }
		let polygons = [circle(10, 10), circle(30, 10)]
		func groups(_ budgets: LandGroups.Budgets) throws -> LandGroups {
			try LandGroups.compute(isLand: [true, true, false], neighbours: [[2], [2], [0, 1]], width: 40, height: 20, bucketFloor: 2.5, reach: 30, budgets: budgets, polygon: { $0 < 2 ? polygons[$0] : [] })
		}
		#expect(try groups(.init()).groups.count == 1, "fine with the default budgets: the circles are 12 apart")
		var tight = LandGroups.Budgets()
		tight.primitives = 719_999
		#expect(throws: LandGroups.Problem.workBudget("primitives")) { try groups(tight) }
		tight.primitives = 720_000
		#expect(try groups(tight).groups.count == 1, "exactly 2 x a x b is enough")
		// a polygon-distance cost that would overflow is refused, not wrapped
		var huge = LandGroups.Budgets()
		huge.primitives = Int.max
		#expect(try groups(huge).groups.count == 1)
	}

	@Test func negativeBudgetsAreRefusedEvenWhenNoSearchIsNeeded() {
		var negative = LandGroups.Budgets()
		negative.insertions = -1
		for budgets in [negative, { var b = LandGroups.Budgets(); b.candidates = -1; return b }(), { var b = LandGroups.Budgets(); b.distances = -1; return b }(), { var b = LandGroups.Budgets(); b.primitives = -1; return b }()] {
			// all water: no landmass at all, and reach 0: no search; still refused
			#expect(throws: LandGroups.Problem.invalidBudget) { try Cells(["...."]).groups(reach: 0, budgets: budgets) }
			#expect(throws: LandGroups.Problem.invalidBudget) { try Cells(["#.#"]).groups(reach: 0, budgets: budgets) }
			#expect(throws: LandGroups.Problem.invalidBudget) { try Cells(["#.#"]).groups(reach: 20, budgets: budgets) }
		}
		var zero = LandGroups.Budgets()
		zero.insertions = 0
		zero.candidates = 0
		zero.distances = 0
		zero.primitives = 0
		#expect((try? Cells(["#.#"]).groups(reach: 0, budgets: zero)) != nil, "zero is a valid policy: it refuses any search, and reach 0 needs none")
		#expect(throws: LandGroups.Problem.workBudget("insertions")) { try Cells(["#.#"]).groups(reach: 20, budgets: zero) }
	}

	@Test func eachCandidatePairCostsExactlyOneDistanceComputation() throws {
		// the distance work is bounded by the number of distinct pairs of coast cells of different landmasses whose boxes are within
		// the reach: with a budget of exactly that many the search finishes, with one fewer it refuses (so a pair met again in another
		// bucket is not computed twice)
		let c = Cells(["#.#.#.#", ".......", "#.#.#.#", ".......", "#.#.#.#"])
		let reach = 20.0
		let land = (0..<c.isLand.count).filter { c.isLand[$0] }
		var pairs = 0
		for (i, a) in land.enumerated() { for b in land[(i + 1)...] {
			let pa = c.polygon(a), pb = c.polygon(b)
			let gapX = max(pa.map(\.x).min()! - pb.map(\.x).max()!, pb.map(\.x).min()! - pa.map(\.x).max()!)
			let gapY = max(pa.map(\.y).min()! - pb.map(\.y).max()!, pb.map(\.y).min()! - pa.map(\.y).max()!)
			if gapX <= reach && gapY <= reach { pairs += 1 } // every land cell here is its own landmass and a coast cell
		} }
		#expect(pairs > 20)
		var exact = LandGroups.Budgets()
		exact.distances = pairs
		#expect((try? c.groups(reach: reach, budgets: exact)) != nil, "a budget of exactly \(pairs) distance computations is enough")
		exact.distances = pairs - 1
		#expect(throws: LandGroups.Problem.workBudget("distances")) { try c.groups(reach: reach, budgets: exact) }
	}

	// MARK: against brute force

	@Test func theSearchAgreesWithComparingEveryPairOnRandomGrids() throws {
		var seed: UInt64 = 12345
		func random() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
		var cases = 0
		for _ in 0..<40 {
			let rows = 6 + Int(random() * 6), columns = 6 + Int(random() * 6)
			let density = 0.2 + random() * 0.35
			let picture = (0..<rows).map { _ in String((0..<columns).map { _ in random() < density ? "#" : "." }) }
			let c = Cells(picture)
			var previous = Int.max
			for reach in [0.0, 1e-9, 0.5, 5, 10, 14.2, 20, 25, 30, 45, 1000] {
				let g = try c.groups(reach: reach)
				#expect(g.groupOfCell == c.brute(reach: reach), "picture \(picture), reach \(reach)")
				#expect(g.groups.count <= previous, "a larger reach never increases C")
				previous = g.groups.count
				// the links: a spanning forest of each group, each within the reach, and the closest pair of its two landmasses
				#expect(g.links.count == g.landmasses.count - g.groups.count)
				for l in g.links {
					#expect(l.distance <= reach && l.distance == LandGroups.polygonDistance(c.polygon(l.cellA), c.polygon(l.cellB)))
					// the stored points are on the two polygons' boundaries and are exactly `distance` apart: a real segment
					#expect(boundaryDistance(l.pointA, c.polygon(l.cellA)) <= 1e-9 && boundaryDistance(l.pointB, c.polygon(l.cellB)) <= 1e-9)
					#expect(((l.pointA.x - l.pointB.x) * (l.pointA.x - l.pointB.x) + (l.pointA.y - l.pointB.y) * (l.pointA.y - l.pointB.y)).squareRoot() == l.distance)
				}
				cases += 1
			}
		}
		#expect(cases == 440)
	}

	// MARK: generated maps

	func map(_ key: String, seed: String = "kaz-1", cells: Int = 800) throws -> LandMap {
		try LandMap.generate(seed: seed, width: 400, height: 300, cellsDesired: cells, template: try #require(HeightmapTemplate.named(key)))
	}

	@Test func onGeneratedMapsTheSearchAgreesWithBruteForceAndIsDeterministic() throws {
		for key in ["archipelago", "shattered", "continents", "highIsland", "atoll"] {
			let m = try map(key)
			let v = m.voronoi
			let n = m.heights.count
			let polygon = { (c: Int) in RectangleClip.clip(v.cells.v[c].map { v.vertices.p[$0] }, width: m.width, height: m.height) }
			var previous = Int.max
			for reach in [0.0, 3, 10, 30, 80, 200] {
				let g = try LandGroups.find(in: m, reach: reach)
				#expect(g == (try LandGroups.find(in: m, reach: reach)), "deterministic")
				// brute force over all land cells of different landmasses
				var parent = Array(0..<g.landmasses.count)
				func find(_ x: Int) -> Int { parent[x] == x ? x : find(parent[x]) }
				if reach > 0 {
					let land = (0..<n).filter { g.landmassOfCell[$0] >= 0 }
					for (i, a) in land.enumerated() { for b in land[(i + 1)...] where g.landmassOfCell[a] != g.landmassOfCell[b] {
						let la = find(Int(g.landmassOfCell[a])), lb = find(Int(g.landmassOfCell[b]))
						if la != lb, LandGroups.polygonDistance(polygon(a), polygon(b)) <= reach { parent[max(la, lb)] = min(la, lb) }
					} }
				}
				var roots = Set<Int>()
				for i in g.landmasses.indices { roots.insert(find(i)) }
				#expect(roots.count == g.groups.count, "\(key) reach \(reach): \(roots.count) by brute force, \(g.groups.count) found")
				for i in g.landmasses.indices { for j in g.landmasses.indices where find(i) == find(j) { #expect(g.landmasses[i].group == g.landmasses[j].group) } }
				#expect(g.groups.count <= previous)
				previous = g.groups.count
				// every link's points lie on the boundaries of its two cells' polygons and are exactly `distance` apart
				for l in g.links {
					#expect(boundaryDistance(l.pointA, polygon(l.cellA)) <= 1e-9 && boundaryDistance(l.pointB, polygon(l.cellB)) <= 1e-9, "\(key) reach \(reach)")
					#expect(((l.pointA.x - l.pointB.x) * (l.pointA.x - l.pointB.x) + (l.pointA.y - l.pointB.y) * (l.pointA.y - l.pointB.y)).squareRoot() == l.distance)
				}
				#expect(g.landmasses.map(\.firstCell) == g.landmasses.map(\.firstCell).sorted() && g.groups.map(\.firstCell) == g.groups.map(\.firstCell).sorted(), "numbered by smallest cell")
				#expect(g.groups.map(\.cellCount).reduce(0, +) == m.heights.filter { Heights.isLand($0) }.count)
			}
		}
	}

	@Test func timingAtTenAndAHundredThousandCells() throws {
		for cells in [10_000, 100_000] {
			let m = try LandMap.generate(seed: "kaz-1", width: 1280, height: 800, cellsDesired: cells, template: try #require(HeightmapTemplate.named("archipelago")))
			for reach in [0.0, 5.0, 20.0, 60.0] {
				let start = Date()
				let g = try LandGroups.find(in: m, reach: reach)
				print("GROUPS \(cells) cells, reach \(reach): \(g.landmasses.count) landmasses, \(g.groups.count) groups, \(g.links.count) links, \(Int(Date().timeIntervalSince(start) * 1000)) ms")
				#expect(g.groups.count >= 1)
			}
		}
	}
}
