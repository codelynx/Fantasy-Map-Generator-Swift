import Foundation
import Testing
@testable import FantasyMapKit

/// Water chain, stage 7a: `alterHeights` and `resolveDepressions`, compared EXACTLY with fixtures captured from the original's own
/// `Rivers` on its own packed graph (Fixtures/original/depressions-original.json).
struct RiverHeightsTests {
	struct LakeState: Decodable {
		var height: Double
		var closed: Bool?
	}
	struct Case: Decodable {
		var variant: String, steps: Int, bad: Bool, hSha: String
		var closedBefore: [Bool?]
		var lakes: [LakeState]
		var hWhole: [Double]?
	}
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, cells: Int, lakes: Int, alterSha: String
		var alterWhole: [Double]?
		var cases: [Case]
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("depressions-original")).runs }

	// the working-height variants of the capture, made the same way
	static func variant(_ name: String, _ h: [Double]) -> [Double] {
		switch name {
		case "pits": return h.enumerated().map { i, v in v >= 20 && i % 3 == 0 ? max(20, v - 12) : v }
		case "ridges": return h.enumerated().map { i, v in v >= 20 && i % 5 == 0 ? min(100, v + 30) : v }
		case "noise": return h.enumerated().map { i, v in v >= 20 ? min(100, max(20, v + Double((i * 7919) % 21) - 10)) : v }
		default: return h
		}
	}

	@Test func alterHeightsAndResolveDepressionsMatchTheOriginal() throws {
		let all = try runs()
		var wrongAlter = 0, wrongCases = 0, wholeWrong = 0, whole = 0, bad = 0, forced = 0, cases = 0, maxRatio = 0.0
		for r in all {
			let m = try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
			let packed = try PackedMap.generate(for: m)
			let features = try PackedFeatures.markup(for: packed, width: m.width, height: m.height)
			let cells = packed.voronoi.cells
			let base = try RiverHeights.alterHeights(packedHeights: packed.heights, distance: features.distanceField, neighbours: cells.c)
			if r.cells != base.count || Fixtures.hashDoubles(base) != r.alterSha || (r.alterWhole.map { $0 != base } ?? false) { wrongAlter += 1 }
			for c in r.cases {
				cases += 1
				var f = features
				var h = Self.variant(c.variant, base)
				try f.detectCloseLakes(heights: h, neighbours: cells.c, elevationLimit: 20)
				let lakeIndices = f.features.indices.filter { f.features[$0].kind == .lake }
				let closedBefore = lakeIndices.map { f.features[$0].closed }
				var work = try RiverWork(cells: packed.points.count, policy: RiverResourcePolicy())
				let outcome = try RiverHeights.resolveDepressions(heights: &h, features: &f, packedHeights: packed.heights, neighbours: cells.c, border: cells.b, steps: c.steps, work: &work)
				maxRatio = max(maxRatio, Double(work.charged) / Double(max(1, packed.points.count)))
				let lakes = lakeIndices.map { LakeState(height: f.features[$0].height, closed: f.features[$0].closed) }
				let sameLakes = zip(lakes, c.lakes).allSatisfy { $0.height == $1.height && $0.closed == $1.closed } && lakes.count == c.lakes.count
				if !(Fixtures.hashDoubles(h) == c.hSha && sameLakes && closedBefore == c.closedBefore && outcome.badProgress == c.bad) { wrongCases += 1 }
				if let w = c.hWhole { whole += 1; if h != w { wholeWrong += 1 } }
				if c.bad { bad += 1 }
				if zip(lakes, c.closedBefore).contains(where: { $0.closed == true && $1 != true }) { forced += 1 }
			}
		}
		#expect(all.count == 84 && cases == 1008 && whole > 60)
		#expect(bad >= 5, "cases that really reach the bad-progress branch are present (\(bad))")
		#expect(forced > 100, "cases where a lake is closed by force are present (\(forced))")
		#expect(wrongAlter == 0, "\(wrongAlter) of \(all.count) maps differ in alterHeights")
		#expect(wrongCases == 0, "\(wrongCases) of \(cases) resolveDepressions cases differ from the original")
		#expect(wholeWrong == 0, "\(wholeWrong) of the \(whole) whole arrays differ")
		print("observed maximum work per packed cell on the fixtures: \(maxRatio); all of it charged to resolveDepressions")
	}

	// MARK: hand-computed cases

	func island(heights: [Double], border: [Int], packed: [Height]? = nil, lake: PackedFeature? = nil) -> (PackedFeatures, [[Int]], [Int], [Height]) {
		let n = heights.count
		var list = [PackedFeature(id: 1, kind: .island, land: true, border: false, cells: n, firstCell: 0, vertices: [], area: 0, shoreline: [], height: 0)]
		var ids = [UInt16](repeating: 1, count: n)
		if let lake { list.append(lake); ids[Int(lake.firstCell)] = 2 }
		let f = PackedFeatures(distanceField: [Int8](repeating: 0, count: n), featureIds: ids, haven: [Int](repeating: 0, count: n), harbor: [UInt8](repeating: 0, count: n), features: list)
		return (f, (0..<n).map { i in [i - 1, i + 1].filter { $0 >= 0 && $0 < n } }, border, packed ?? heights.map { Height($0) })
	}

	func resolve(_ h: [Double], border: [Int], steps: Int, lake: PackedFeature? = nil, budget: RiverResourcePolicy = RiverResourcePolicy()) throws -> ([Double], PackedFeatures, DepressionOutcome) {
		var heights = h
		var (f, c, b, p) = island(heights: h, border: border, lake: lake)
		var work = try RiverWork(cells: h.count, policy: budget)
		let outcome = try RiverHeights.resolveDepressions(heights: &heights, features: &f, packedHeights: p, neighbours: c, border: b, steps: steps, work: &work)
		return (heights, f, outcome)
	}

	@Test func alterHeightsAddsTheCoastGradient() throws {
		// cell 0 is water (kept), cell 1 is land with distance 1 and neighbours of distances -1 and 2 (mean 0.5), cell 2 distance 2 with the
		// neighbour 1, cell 3 is land with distance 0 (kept), cell 4 land with distance -1 (kept)
		let h = try RiverHeights.alterHeights(packedHeights: [10, 30, 30, 30, 30], distance: [-1, 1, 2, 0, -1], neighbours: [[1], [0, 2], [1, 3], [2, 4], [3]])
		#expect(h[0] == 10 && h[3] == 30 && h[4] == 30)
		#expect(h[1] == 30 + 1.0 / 100 + 0.5 / 10000, "30.01005")
		#expect(h[2] == 30 + 2.0 / 100 + (Double(1 + 0) / 2) / 10000, "30.02 and the mean of distances 1 and 0: 0.5")
		#expect(throws: RiverError.invalidInputs) { try RiverHeights.alterHeights(packedHeights: [30], distance: [1], neighbours: [[]]) }
		#expect(throws: RiverError.invalidInputs) { try RiverHeights.alterHeights(packedHeights: [30, 30], distance: [1], neighbours: [[1], [0]]) }
		#expect(throws: RiverError.invalidInputs) { try RiverHeights.alterHeights(packedHeights: [30, 30], distance: [1, 1], neighbours: [[2], [0]]) }
	}

	@Test func aPitIsRaisedAboveItsLowestNeighbourEachIterationInSortedOrder() throws {
		// five land cells, border at both ends: [40, 25, 30, 25, 40]. One iteration: cell 1 (25) goes to 30 + 0.1 (neighbours 40 and 30),
		// cell 3 likewise, then cell 2 (30) sees 30.1 on both sides and goes to 30.1 + 0.1 (the cells are visited lowest first, equal heights in cell order)
		let (h, _, outcome) = try resolve([40, 25, 30, 25, 40], border: [1, 0, 0, 0, 1], steps: 1)
		#expect(h == [40, 30 + 0.1, (30 + 0.1) + 0.1, 30 + 0.1, 40])
		#expect(outcome == DepressionOutcome(lastIterationDepressions: 3, badProgress: false, iterations: 1))
		// a cell at its neighbours' height is a depression too (not strictly lower), one above them is not
		let (flat, _, o2) = try resolve([40, 30, 30, 40], border: [1, 0, 0, 1], steps: 1)
		#expect(flat == [40, 30 + 0.1, (30 + 0.1) + 0.1, 40] && o2.lastIterationDepressions == 2, "cell 1 sees 30 at cell 2 and goes up; cell 2 then sees 30.1")
		// the lowest cell goes first whatever its place: [40, 35, 30, 40] raises cell 2 (30) to 35.1, and then cell 1 (35) to 35.1 + 0.1
		let (ordered, _, o3) = try resolve([40, 35, 30, 40], border: [1, 0, 0, 1], steps: 1)
		#expect(ordered == [40, (35 + 0.1) + 0.1, 35 + 0.1, 40] && o3.lastIterationDepressions == 2)
	}

	@Test func aLakeIsRaisedAboveItsLowestShoreCellAndFlagsAreKept() throws {
		// a lake whose height (24.9) is not above its lowest shore cell (25) is raised to 25 + 0.2 and counted; the lake is cell 2 of an island
		// of heights [40, 25, 15, 25, 40]; its shore is cells 1 and 3
		let lake = PackedFeature(id: 2, kind: .lake, land: false, border: false, cells: 1, firstCell: 2, vertices: [], area: 0, shoreline: [1, 3], height: 24.9)
		let (_, f, outcome) = try resolve([40, 25, 15, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, lake: lake)
		#expect(f.features[1].height == 25 + 0.2)
		#expect(outcome.lastIterationDepressions >= 1)
		// a lake already above its lowest shore cell is left alone, and a closed lake is not examined
		let high = PackedFeature(id: 2, kind: .lake, land: false, border: false, cells: 1, firstCell: 2, vertices: [], area: 0, shoreline: [1, 3], height: 26)
		let (_, f2, _) = try resolve([40, 25, 15, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, lake: high)
		#expect(f2.features[1].height == 26)
		var closed = lake
		closed.closed = true
		let (_, f3, _) = try resolve([40, 25, 15, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, lake: closed)
		#expect(f3.features[1].height == 24.9)
	}

	@Test func aLakeWhoseShoreIsAtOneHundredIsLeftAlone() throws {
		// the shore at exactly 100 (the top of the scale): the lake is skipped, not raised (the test is "at least 100")
		let lake = PackedFeature(id: 2, kind: .lake, land: false, border: false, cells: 1, firstCell: 2, vertices: [], area: 0, shoreline: [1, 3], height: 24.9)
		let (_, f, outcome) = try resolve([100, 100, 15, 100, 100], border: [1, 0, 0, 0, 1], steps: 1, lake: lake)
		#expect(f.features[1].height == 24.9 && outcome.lastIterationDepressions == 0)
	}

	@Test func theWorkChargesOfALakeAreCountedByHand() throws {
		// [40, 25, 15, 25, 40] with the lake at cell 2 (shore 1 and 3), one iteration: the filter 5 and the sort 5 x 3 bits are 20; the lake is
		// charged 1 and its 2 shore cells (3); the two land cells away from the border are charged 1 + 2 neighbours each (6): 29. A closed lake is
		// charged 1 only: 27
		func charged(closed: Bool?) throws -> Int {
			var lake = PackedFeature(id: 2, kind: .lake, land: false, border: false, cells: 1, firstCell: 2, vertices: [], area: 0, shoreline: [1, 3], height: 24.9)
			lake.closed = closed
			var h: [Double] = [40, 25, 15, 25, 40]
			var (f, c, b, p) = island(heights: h, border: [1, 0, 0, 0, 1], lake: lake)
			var work = try RiverWork(cells: 5, policy: RiverResourcePolicy())
			try RiverHeights.resolveDepressions(heights: &h, features: &f, packedHeights: p, neighbours: c, border: b, steps: 1, work: &work)
			return work.charged
		}
		#expect(try charged(closed: nil) == 29)
		#expect(try charged(closed: true) == 27)
	}

	@Test func refusalsChangeNothing() throws {
		let lake = PackedFeature(id: 2, kind: .lake, land: false, border: false, cells: 1, firstCell: 2, vertices: [], area: 0, shoreline: [1, 3], height: 24.9)
		for steps in [0, -1, 1001] { #expect(throws: RiverError.invalidSettings) { try resolve([40, 25, 30, 25, 40], border: [1, 0, 0, 0, 1], steps: steps) } }
		var outside = lake
		outside.shoreline = [1, 9]
		#expect(throws: RiverError.invalidInputs) { try resolve([40, 25, 15, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, lake: outside) }
		outside.shoreline = [-1, 3]
		#expect(throws: RiverError.invalidInputs) { try resolve([40, 25, 15, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, lake: outside) }
		// a lake without a shore, a non-finite height, a land cell without neighbours, a feature number outside the table
		var noShore = lake
		noShore.shoreline = []
		#expect(throws: RiverError.lakeWithoutShore) { try resolve([40, 25, 15, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, lake: noShore) }
		var heights: [Double] = [40, 25, 30, 25, 40], (f, c, b, p) = island(heights: [40, 25, 30, 25, 40], border: [1, 0, 0, 0, 1])
		var work = try RiverWork(cells: 5, policy: RiverResourcePolicy())
		let before = (heights, f, work)
		heights[2] = .nan
		#expect(throws: RiverError.invalidInputs) { try RiverHeights.resolveDepressions(heights: &heights, features: &f, packedHeights: p, neighbours: c, border: b, steps: 1, work: &work) }
		heights = before.0
		c[2] = []
		#expect(throws: RiverError.invalidInputs) { try RiverHeights.resolveDepressions(heights: &heights, features: &f, packedHeights: p, neighbours: c, border: b, steps: 1, work: &work) }
		c = (0..<5).map { i in [i - 1, i + 1].filter { $0 >= 0 && $0 < 5 } }
		f.featureIds[1] = 9
		#expect(throws: RiverError.invalidInputs) { try RiverHeights.resolveDepressions(heights: &heights, features: &f, packedHeights: p, neighbours: c, border: b, steps: 1, work: &work) }
		#expect(heights == before.0 && work == before.2, "a refused call leaves the inputs as they were")
	}

	@Test func theWorkBudgetIsChargedBeforeFilteringAndOverflowIsRefused() throws {
		var tight = RiverResourcePolicy()
		tight.workPerCell = 1
		#expect(throws: RiverError.workBudgetExceeded(.resolveDepressions)) { try resolve([40, 25, 30, 25, 40], border: [1, 0, 0, 0, 1], steps: 1, budget: tight) }
		var work = try RiverWork(cells: 10, policy: RiverResourcePolicy())
		#expect(work.limit == 100_000)
		try work.charge(100_000, .drainWater)
		#expect(throws: RiverError.workBudgetExceeded(.drainWater)) { try work.charge(1, .drainWater) }
		// the sum of charges is overflow-checked: a limit of Int.max can be reached exactly and not passed
		var huge = RiverResourcePolicy()
		huge.workPerCell = Int.max
		var atMax = try RiverWork(cells: 1, policy: huge)
		#expect(atMax.limit == Int.max)
		try atMax.charge(Int.max, .detectCloseLakes)
		#expect(throws: RiverError.workBudgetExceeded(.detectCloseLakes)) { try atMax.charge(1, .detectCloseLakes) }
		#expect(throws: RiverError.invalidInputs) { try atMax.charge(-1, .detectCloseLakes) }
		// a budget whose product does not fit an Int is refused at construction, not saturated
		#expect(throws: RiverError.invalidSettings) { try RiverWork(cells: 4, policy: huge) }
		// a land-only graph of 5 cells charges: the filter 5, the sort 5 x 3 bits = 15, then per iteration 3 land cells x (1 + 2 neighbours) = 9
		var counted = try RiverWork(cells: 5, policy: RiverResourcePolicy())
		var h: [Double] = [40, 25, 30, 25, 40]
		var (f, c, b, p) = island(heights: h, border: [1, 0, 0, 0, 1])
		try RiverHeights.resolveDepressions(heights: &h, features: &f, packedHeights: p, neighbours: c, border: b, steps: 1, work: &counted)
		#expect(counted.charged == 5 + 15 + 9)
	}

	@Test func publicConstructionOfTheWorkCounterIsGuarded() throws {
		let policy = RiverResourcePolicy()
		#expect(throws: RiverError.invalidSettings) { try RiverWork(cells: -1, policy: policy) }
		var negative = policy
		negative.workPerCell = -5
		#expect(throws: RiverError.invalidSettings) { try RiverWork(cells: -3, policy: negative) }
		#expect(throws: RiverError.invalidSettings) { try RiverWork(cells: 3, policy: negative) }
		var zeroSteps = policy
		zeroSteps.resolveDepressionsSteps = 0
		#expect(throws: RiverError.invalidSettings) { try RiverWork(cells: 3, policy: zeroSteps) }
		var tooManySteps = policy
		tooManySteps.resolveDepressionsSteps = 1001
		#expect(throws: RiverError.invalidSettings) { try RiverWork(cells: 3, policy: tooManySteps) }
		let zero = try RiverWork(cells: 0, policy: policy)
		#expect(zero.limit == 0 && zero.charged == 0, "zero cells have a zero budget")
		var empty = zero
		#expect(throws: RiverError.workBudgetExceeded(.resolveDepressions)) { try empty.charge(1, .resolveDepressions) }
		try empty.charge(0, .resolveDepressions)
	}

	@Test func aForcedClosureChargesItsTwoShorePassesAndResetsTheShore() throws {
		// [40, 25, 15, 25, 40] with the lake at cell 2 (shore 1 and 3) and 20 steps: the forced closure acts on iterations past 0.75 x 20 = 15
		// and under 0.85 x 20 = 17, so on iteration 16 only. Iterations 0 to 15 each raise the lake and both shore cells (the lake to the lowest
		// shore + 0.2, each shore cell to the lake + 0.1), so the lake persists. Charges: the filter and sort 20; sixteen iterations of 9 (the
		// lake 1 + 2 shore cells, two land cells 3 each) 144; and in iteration 16 the lake 1 + 2 for its minimum + 2 for restoring the shore + 2
		// for the rescan, then 6 for the land cells: 13. In all 177. The shore goes back to the packed 25, the lake becomes 24 and closed, and
		// that iteration finds nothing to raise (the lake is now below the shore), so the loop ends after 17 iterations
		let lake = PackedFeature(id: 2, kind: .lake, land: false, border: false, cells: 1, firstCell: 2, vertices: [], area: 0, shoreline: [1, 3], height: 24.9)
		var h: [Double] = [40, 25, 15, 25, 40]
		var (f, c, b, p) = island(heights: h, border: [1, 0, 0, 0, 1], lake: lake)
		var work = try RiverWork(cells: 5, policy: RiverResourcePolicy())
		let outcome = try RiverHeights.resolveDepressions(heights: &h, features: &f, packedHeights: p, neighbours: c, border: b, steps: 20, work: &work)
		#expect(work.charged == 177 && work.chargedByPart == [.resolveDepressions: 177])
		#expect(f.features[1].closed == true && f.features[1].height == 24)
		#expect(h == [40, 25, 15, 25, 40])
		#expect(outcome == DepressionOutcome(lastIterationDepressions: 0, badProgress: false, iterations: 17))
	}

	@Test func theResourcePolicyIsValidated() throws {
		var p = RiverResourcePolicy()
		try p.validate()
		p.resolveDepressionsSteps = 0
		#expect(throws: RiverError.invalidSettings) { try p.validate() }
		p.resolveDepressionsSteps = 1001
		#expect(throws: RiverError.invalidSettings) { try p.validate() }
		p.resolveDepressionsSteps = 1000
		try p.validate()
		p.workPerCell = 0
		#expect(throws: RiverError.invalidSettings) { try p.validate() }
	}
}
