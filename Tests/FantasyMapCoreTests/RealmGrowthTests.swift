import Foundation
import Testing
@testable import FantasyMapCore

/// Realms step 3 (docs/plans/realms.md): verified crossings and connected frontier growth.
struct RealmGrowthTests {
	typealias Cells = LandGroupsTests.Cells

	let flat = GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: 0)

	struct Setup {
		var cells: Cells
		var groups: LandGroups
		var sites: [Point]
		var heights: [Height]
		var polygons: [[Point]]
		var areas: [Double]
	}

	func setup(_ picture: [String], reach: Double, heights: [Height]? = nil) throws -> Setup {
		let c = Cells(picture)
		let n = c.isLand.count
		return Setup(cells: c, groups: try c.groups(reach: reach),
			sites: (0..<n).map { Point(x: (Double($0 % c.columns) + 0.5) * c.s, y: (Double($0 / c.columns) + 0.5) * c.s) },
			heights: heights ?? c.isLand.map { $0 ? 30 : 5 }, polygons: (0..<n).map { c.isLand[$0] ? c.polygon($0) : [] }, areas: c.isLand.map { $0 ? c.s * c.s : 0 })
	}

	func seeds(_ s: Setup, at cells: [Int]) -> RealmSeeds {
		var perGroup = [Int](repeating: 0, count: s.groups.groups.count)
		let realms = cells.enumerated().map { i, cell in
			let g = Int(s.groups.groupOfCell[cell])
			perGroup[g] += 1
			return RealmSeeds.Realm(number: i + 1, group: g, cell: cell)
		}
		return RealmSeeds(mode: .chosen(cells.count), resolvedCount: cells.count, realmsPerGroup: perGroup, realms: realms)
	}

	func grow(_ s: Setup, seeds sd: RealmSeeds, policy: GrowthPolicy? = nil, factors: [Double]? = nil, realmSeed: String = "r") throws -> RealmOwnership {
		try RealmOwnership.compute(groups: s.groups, seeds: sd, neighbours: s.cells.neighbours, sites: s.sites, heights: s.heights, areas: s.areas, polygons: s.polygons, width: s.cells.width, height: s.cells.height, mapSeed: "map", realmSeed: realmSeed, policy: policy ?? flat, expansionFactors: factors)
	}

	func check(_ o: RealmOwnership, _ s: Setup, _ sd: RealmSeeds) -> [String] { RealmOwnership.problems(in: o, groups: s.groups, seeds: sd, neighbours: s.cells.neighbours) }

	func failure(_ s: Setup, seeds sd: RealmSeeds, policy: GrowthPolicy? = nil, mutate: ((inout Setup) -> Void)? = nil) -> RealmOwnership.Problem? {
		var s = s
		mutate?(&s)
		do { _ = try grow(s, seeds: sd, policy: policy); return nil } catch let p as RealmOwnership.Problem { return p } catch { return nil }
	}

	// MARK: connected frontier growth

	@Test func theChainCounterexampleGivesXToBAndKeepsAConnected() throws {
		// a chain A - B - X, seeds at A and B, edge lengths 1 and 3, expansion factors 10 for A and 1 for B. Unrestricted costs would give
		// X to A (0.4 against 3) through B's own cell, cutting A in two; connected frontier growth must give X to B
		var s = try setup(["###"], reach: 0)
		s.sites = [Point(x: 0, y: 5), Point(x: 1, y: 5), Point(x: 4, y: 5)]
		let sd = seeds(s, at: [0, 1])
		let o = try grow(s, seeds: sd, factors: [10, 1])
		#expect(o.owner == [1, 2, 2], "X goes to B")
		#expect(check(o, s, sd).isEmpty, "\(check(o, s, sd))")
		#expect(o.realms.map(\.cellCount) == [1, 2])
	}

	@Test func aRealmSpansIslandsOnlyThroughVerifiedCrossingsAndEveryLandCellIsOwned() throws {
		let s = try setup(["##.##.##"], reach: 10)
		#expect(s.groups.groups.count == 1 && s.groups.links.count == 2)
		let one = seeds(s, at: [0])
		let o = try grow(s, seeds: one)
		#expect(o.owner == [1, 1, 0, 1, 1, 0, 1, 1], "one realm owns all three islands through the crossings; water is not owned")
		#expect(check(o, s, one).isEmpty)
		// two realms, seeds on the two end islands: each is connected and every land cell is owned
		let two = seeds(s, at: [0, 7])
		let o2 = try grow(s, seeds: two)
		#expect(check(o2, s, two).isEmpty && o2.owner.filter { $0 > 0 }.count == 6 && o2.realms.allSatisfy { $0.cellCount >= 1 })
		#expect(o2.owner[0] == 1 && o2.owner[7] == 2 && o2.owner[1] == 1 && o2.owner[6] == 2)
	}

	@Test func eachGroupIsOneRealmWhenKEqualsCAndEveryCellIsItsOwnRealmWhenKIsTheLandCellCount() throws {
		let s = try setup(["##....##", "##....##"], reach: 0) // two groups of four cells
		let perGroup = seeds(s, at: [0, 6])
		let o = try grow(s, seeds: perGroup)
		#expect(o.realms.map(\.cellCount) == [4, 4] && check(o, s, perGroup).isEmpty)
		let all = Array((0..<s.cells.isLand.count).filter { s.cells.isLand[$0] })
		let each = seeds(s, at: all)
		let o2 = try grow(s, seeds: each)
		#expect(o2.realms.allSatisfy { $0.cellCount == 1 } && check(o2, s, each).isEmpty && o2.owner.filter { $0 > 0 }.count == 8)
	}

	@Test func aSeedOnATinyIslandOwnsItAndTheBiggerRealmReachesTheRest() throws {
		let s = try setup(["#.###", "..###"], reach: 10)
		let sd = seeds(s, at: [0, 4])
		let o = try grow(s, seeds: sd)
		#expect(check(o, s, sd).isEmpty && o.owner[0] == 1 && o.owner[4] == 2)
		#expect(o.realms[0].cellCount >= 1 && o.owner.filter { $0 > 0 }.count == 7)
	}

	// MARK: ties, costs and terrain

	@Test func ties_goToTheSmallerRealmNumber() throws {
		let s = try setup(["#.#.#"], reach: 10)
		let sd = seeds(s, at: [0, 4])
		let o = try grow(s, seeds: sd)
		#expect(o.owner == [1, 0, 1, 0, 2], "the middle island is equally far from both seeds: the smaller realm number takes it")
		#expect(check(o, s, sd).isEmpty)
	}

	@Test func theLandApproachesOfACrossingAreCharged() throws {
		// the same sea gap on both sides; the departure cell of realm 1 is a mountain, so its approach to the shore costs more and
		// realm 2 wins the island between them although ties would go to realm 1
		let mountain: [Height] = [80, 5, 30, 5, 30]
		let s = try setup(["#.#.#"], reach: 10, heights: mountain)
		let sd = seeds(s, at: [0, 4])
		let policy = GrowthPolicy(hillFactor: 1, mountainFactor: 5, crossingFactor: 1, unevenness: 0)
		let o = try grow(s, seeds: sd, policy: policy)
		#expect(o.owner[2] == 2, "the island goes to the realm whose approach is cheaper")
		#expect(check(o, s, sd).isEmpty)
		let level = try grow(try setup(["#.#.#"], reach: 10), seeds: sd, policy: policy)
		#expect(level.owner[2] == 1, "with level ground it is the tie, and the smaller realm number wins")
	}

	@Test func aMountainRidgeMovesTheBorderTowardTheSeedThatMustClimbIt() throws {
		let picture = ["###########"]
		let flatMap = try setup(picture, reach: 0)
		let sd = seeds(flatMap, at: [0, 10])
		let policy = GrowthPolicy(hillFactor: 1, mountainFactor: 10, crossingFactor: 1, unevenness: 0)
		let levelOwner = try grow(flatMap, seeds: sd, policy: policy).owner
		var ridge: [Height] = [Height](repeating: 30, count: 11)
		ridge[3] = 80
		ridge[4] = 80
		let ridged = try setup(picture, reach: 0, heights: ridge)
		let o = try grow(ridged, seeds: sd, policy: policy)
		#expect(o.owner.filter { $0 == 2 }.count > levelOwner.filter { $0 == 2 }.count, "realm 2 takes more cells: realm 1 must climb the ridge")
		#expect(check(o, ridged, sd).isEmpty)
	}

	@Test func hillsCostMoreToo() throws {
		let hills: [Height] = [30, 30, 50, 50, 30, 30, 30]
		let s = try setup(["#######"], reach: 0, heights: hills)
		let sd = seeds(s, at: [0, 6])
		let a = try grow(s, seeds: sd, policy: GrowthPolicy(hillFactor: 8, mountainFactor: 8, crossingFactor: 1, unevenness: 0))
		let b = try grow(try setup(["#######"], reach: 0), seeds: sd)
		#expect(a.owner.filter { $0 == 2 }.count > b.owner.filter { $0 == 2 }.count)
	}

	// MARK: determinism and size variation

	@Test func identicalInputsGiveIdenticalOwnershipAndSeedsChangeResultsOnNontrivialCases() throws {
		let picture = [String](repeating: String(repeating: "#", count: 12), count: 8)
		let s = try setup(picture, reach: 0)
		let sd = seeds(s, at: [3, 20, 50, 77, 90])
		let policy = GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: 8)
		let a = try grow(s, seeds: sd, policy: policy, realmSeed: "x")
		#expect(a == (try grow(s, seeds: sd, policy: policy, realmSeed: "x")))
		let others = try ["y", "z", "w", "v"].map { try grow(s, seeds: sd, policy: policy, realmSeed: $0).owner }
		#expect(others.contains { $0 != a.owner }, "another realm seed changes the sizes on this nontrivial case")
		#expect(check(a, s, sd).isEmpty)
	}

	@Test func unevennessSpreadsTheRealmSizesOnAverage_observational() throws {
		let picture = [String](repeating: String(repeating: "#", count: 16), count: 16)
		let s = try setup(picture, reach: 0)
		let sd = seeds(s, at: [17, 40, 100, 130, 200, 233])
		func spread(_ unevenness: Double) throws -> Double {
			var total = 0.0
			for t in 0..<30 {
				let o = try grow(s, seeds: sd, policy: GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: unevenness), realmSeed: "t\(t)")
				let sizes = o.realms.map { Double($0.cellCount) }
				let mean = sizes.reduce(0, +) / Double(sizes.count)
				total += (sizes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(sizes.count)).squareRoot()
			}
			return total / 30
		}
		let even = try spread(0), uneven = try spread(20)
		print("UNEVENNESS mean standard deviation of realm sizes over 30 realm seeds: unevenness 0 = \(even), unevenness 20 = \(uneven)")
		#expect(uneven > even, "the spread rises with unevenness on average (direction only; 0 means equal factors, not equal sizes)")
	}

	// MARK: crossing verification

	/// A hand-made link, bypassing the search, to test the verification.
	func withLink(_ picture: [String], _ link: LandGroups.Link, reach: Double = 100) throws -> (Setup, RealmSeeds) {
		var s = try setup(picture, reach: reach)
		s.groups.links = [link]
		return (s, seeds(s, at: [s.groups.groups[0].firstCell]))
	}

	@Test func aSegmentOverOtherLandIsRefusedAsUnusable() throws {
		// three islands in a row; the link jumps from the first to the last across the middle island
		let (s, sd) = try withLink(["#.#.#"], LandGroups.Link(landmassA: 0, landmassB: 2, cellA: 0, cellB: 4, distance: 30, pointA: Point(x: 10, y: 5), pointB: Point(x: 40, y: 5)))
		#expect(failure(s, seeds: sd) == .unusableCrossing(landmassA: 0, landmassB: 2))
	}

	@Test func aSegmentTouchingOtherLandAtAVertexIsAmbiguousAndRefused() throws {
		// landmass 0 is cell (0,0), landmass 1 the cell (0,2), landmass 2 the cell (2,2); the segment from (10,0) to (30,20) touches
		// cell (0,2) only at its corner (20,10)
		let (s, sd) = try withLink(["#.#.", "....", "..#."], LandGroups.Link(landmassA: 0, landmassB: 2, cellA: 0, cellB: 10, distance: 800.0.squareRoot(), pointA: Point(x: 10, y: 0), pointB: Point(x: 30, y: 20)))
		#expect(failure(s, seeds: sd) == .unusableCrossing(landmassA: 0, landmassB: 2))
	}

	@Test func aSegmentRunningAlongAnotherCellsEdgeIsRefused() throws {
		// landmass 0 is the cell (0,2), landmass 1 the cell (1,1), landmass 2 the cell (1,3); the segment from (20,10) to (30,10) lies
		// exactly along the bottom edge of cell (0,2)
		let (s, sd) = try withLink(["..#.", ".#.#"], LandGroups.Link(landmassA: 1, landmassB: 2, cellA: 5, cellB: 7, distance: 10, pointA: Point(x: 20, y: 10), pointB: Point(x: 30, y: 10)))
		#expect(failure(s, seeds: sd) == .unusableCrossing(landmassA: 1, landmassB: 2))
	}

	@Test func aSegmentThroughAnotherCellOfItsOwnLandmassIsRefusedAtEitherEnd() throws {
		// departure end: landmass 0 is cells 0 and 1, the link leaves cell 0 at its right edge (10, 5) and crosses cell 1 to reach cell 3
		let (s, sd) = try withLink(["##.#"], LandGroups.Link(landmassA: 0, landmassB: 1, cellA: 0, cellB: 3, distance: 20, pointA: Point(x: 10, y: 5), pointB: Point(x: 30, y: 5)))
		#expect(failure(s, seeds: sd) == .unusableCrossing(landmassA: 0, landmassB: 1), "the segment runs through land of its own landmass")
		// arrival end: landmass 1 is cells 2 and 3, the link reaches cell 3's far side (40, 5) by crossing cell 2... here cell 2 is the near cell
		let (t, td) = try withLink(["#.##"], LandGroups.Link(landmassA: 0, landmassB: 1, cellA: 0, cellB: 3, distance: 30, pointA: Point(x: 10, y: 5), pointB: Point(x: 40, y: 5)))
		#expect(failure(t, seeds: td) == .unusableCrossing(landmassA: 0, landmassB: 1), "the segment runs through land of the landmass it arrives at")
	}

	@Test func aCleanSegmentAndAZeroLengthCornerContactAreUsable() throws {
		let (s, sd) = try withLink(["#.#"], LandGroups.Link(landmassA: 0, landmassB: 1, cellA: 0, cellB: 2, distance: 10, pointA: Point(x: 10, y: 5), pointB: Point(x: 20, y: 5)))
		#expect(failure(s, seeds: sd) == nil, "a segment over water between the two cells is usable")
		let corner = try setup(["#.", ".#"], reach: 0.001)
		#expect(corner.groups.links.first?.distance == 0)
		let sd2 = seeds(corner, at: [0])
		let o = try grow(corner, seeds: sd2)
		#expect(o.owner == [1, 0, 0, 1], "a corner contact is a zero-length crossing and joins the two")
		#expect(check(o, corner, sd2).isEmpty)
	}

	// MARK: genuine witnesses, short crossings and malformed metadata

	@Test func aLinkMustBeAGenuineWitnessOfItsTwoCells() throws {
		let base = try setup(["#.#"], reach: 10)
		let sd = seeds(base, at: [0])
		let good = base.groups.links[0]
		#expect(good.pointA == Point(x: 10, y: 0) || good.pointA.x == 10, "the link from the search lies on cell 0's right edge")
		func with(_ change: (inout LandGroups.Link) -> Void) -> RealmOwnership.Problem? {
			var s = base
			change(&s.groups.links[0])
			do { _ = try grow(s, seeds: sd); return nil } catch let p as RealmOwnership.Problem { return p } catch { return nil }
		}
		#expect(with { _ in } == nil, "the genuine link is accepted")
		#expect(with { $0.pointA = Point(x: 5, y: 5) } == .invalidInputs, "an endpoint inside its own cell, not on its boundary, is invented")
		#expect(with { $0.pointA = Point(x: 500, y: 500) } == .invalidInputs, "an invented endpoint far from its cell")
		#expect(with { $0.pointB = Point(x: 15, y: 5) } == .invalidInputs, "an endpoint in the water between the cells")
		#expect(with { $0.pointB = Point(x: 25, y: 5) } == .invalidInputs, "an endpoint inside the second cell is not on its boundary")
		#expect(with { $0.distance += 1 } == .invalidInputs, "a stored distance that disagrees with the segment")
		#expect(with { $0.distance = 0 } == .invalidInputs)
		#expect(with { l in l.pointA = Point(x: 15, y: 5); l.pointB = Point(x: 15, y: 5); l.distance = 0 } == .invalidInputs, "a false zero-length link: a point neither cell contains")
		#expect(with { l in l.pointA = Point(x: 10, y: 5); l.pointB = Point(x: 10, y: 5); l.distance = 0 } == .invalidInputs, "a zero-length link at a point only the first cell has")
		// endpoints swapped between the cells
		#expect(with { l in swap(&l.pointA, &l.pointB) } == .invalidInputs, "points attached to the wrong cells")
	}

	@Test func aCrossingShorterThanAHundredTolerancesIsRefusedAsAmbiguous() throws {
		// two cells whose polygons are 1e-7 apart on a 30-unit map (the tolerance is 3e-8, so a crossing under 3e-6 is ambiguous)
		var s = try setup(["#.#"], reach: 10)
		s.polygons[2] = s.polygons[2].map { Point(x: $0.x - 9.9999999, y: $0.y) } // cell 2 now starts at 10.0000001
		let link = LandGroups.Link(landmassA: 0, landmassB: 1, cellA: 0, cellB: 2, distance: 1e-7, pointA: Point(x: 10, y: 5), pointB: Point(x: 10.0000001, y: 5))
		s.groups.links = [link]
		let sd = seeds(s, at: [0])
		#expect(failure(s, seeds: sd) == .unusableCrossing(landmassA: 0, landmassB: 1), "the allowance would cover the whole segment: refused, not accepted")
		// the same gap made a hundred times longer is an ordinary short crossing and is accepted
		var wider = s
		wider.polygons[2] = wider.polygons[2].map { Point(x: $0.x + 1e-4, y: $0.y) }
		wider.groups.links = [LandGroups.Link(landmassA: 0, landmassB: 1, cellA: 0, cellB: 2, distance: 1.001e-4, pointA: Point(x: 10, y: 5), pointB: Point(x: 10.0001001, y: 5))]
		#expect(failure(wider, seeds: sd) == nil)
	}

	@Test func aZeroLengthContactThatTouchesAThirdLandmassIsRefused() throws {
		// four cells meeting at the point (10, 10): the diagonal pair is the link, the other two cells are land of a third landmass
		let s = try setup(["#.", ".#"], reach: 0.001)
		var four = s
		four.polygons[1] = Cells(["#.", ".#"]).polygon(1) // cell 1 is water in the picture; make it land of a third landmass
		var groups = s.groups
		groups.landmassOfCell[1] = 2
		groups.groupOfCell[1] = 0
		groups.landmasses.append(LandGroups.Landmass(firstCell: 1, cellCount: 1, group: 0))
		groups.groups[0].cellCount += 1
		groups.groups[0].landmasses.append(2)
		four.groups = groups
		four.heights[1] = 30
		let sd = seeds(four, at: [0])
		#expect(failure(four, seeds: sd) == .unusableCrossing(landmassA: 0, landmassB: 1), "a corner point that a third landmass also touches is ambiguous")
	}

	@Test func malformedSeedMetadataIsRefusedAndNeverTraps() throws {
		let s = try setup(["#.#"], reach: 10)
		let sd = seeds(s, at: [0])
		var hugeGroup = sd
		hugeGroup.realms[0].group = Int.max
		#expect(failure(s, seeds: hugeGroup) == .invalidInputs, "a group index of Int.max must not trap in a conversion")
		var negativeGroup = sd
		negativeGroup.realms[0].group = Int.min
		#expect(failure(s, seeds: negativeGroup) == .invalidInputs)
		var hugeCell = sd
		hugeCell.realms[0].cell = Int.max
		#expect(failure(s, seeds: hugeCell) == .invalidInputs)
		var overflow = sd
		overflow.realmsPerGroup = [Int.max, 1]
		#expect(failure(s, seeds: overflow) == .invalidInputs, "per-group counts that would overflow a sum")
		var wrongCount = sd
		wrongCount.realmsPerGroup = [Int.max]
		#expect(failure(s, seeds: wrongCount) == .invalidInputs)
		var hugeNumber = sd
		hugeNumber.realms[0].number = Int.max
		#expect(failure(s, seeds: hugeNumber) == .invalidInputs)
	}

	@Test func theIndependentCheckerReportsMalformedInputsInsteadOfTrapping() throws {
		let s = try setup(["#.#"], reach: 10)
		let sd = seeds(s, at: [0])
		let o = try grow(s, seeds: sd)
		#expect(RealmOwnership.problems(in: o, groups: s.groups, seeds: sd, neighbours: s.cells.neighbours).isEmpty)
		var outside = sd
		outside.realms[0].cell = 99
		#expect(!RealmOwnership.problems(in: o, groups: s.groups, seeds: outside, neighbours: s.cells.neighbours).isEmpty, "a seed outside the map")
		var negative = sd
		negative.realms[0].cell = -1
		#expect(!RealmOwnership.problems(in: o, groups: s.groups, seeds: negative, neighbours: s.cells.neighbours).isEmpty)
		#expect(!RealmOwnership.problems(in: o, groups: s.groups, seeds: sd, neighbours: [[1]]).isEmpty, "neighbour lists shorter than the cells")
		var badLink = s.groups
		badLink.links[0].cellB = 99
		#expect(!RealmOwnership.problems(in: o, groups: badLink, seeds: sd, neighbours: s.cells.neighbours).isEmpty, "a link to a cell outside the map")
		var shortLandmass = s.groups
		shortLandmass.landmassOfCell.removeLast()
		#expect(!RealmOwnership.problems(in: o, groups: shortLandmass, seeds: sd, neighbours: s.cells.neighbours).isEmpty)
		var shortOwner = o
		shortOwner.owner.removeLast()
		#expect(!RealmOwnership.problems(in: shortOwner, groups: s.groups, seeds: sd, neighbours: s.cells.neighbours).isEmpty)
	}

	// MARK: failures, bounds and the public boundary

	@Test func landThatNoSeedCanReachIsAnamedFailure() throws {
		var s = try setup(["#.#"], reach: 10)
		let sd = seeds(s, at: [0])
		s.groups.links = [] // a hand-built input with the link missing
		do { _ = try grow(s, seeds: sd); Issue.record("land was left unowned without an error") } catch let p as RealmOwnership.Problem { #expect(p == .unreachableLand(cell: 2)) }
	}

	@Test func aNonFiniteDerivedCostIsRefusedBeforeItEntersTheHeap() throws {
		var s = try setup(["##"], reach: 0)
		s.sites = [Point(x: 0, y: 0), Point(x: 1e307, y: 0)]
		let sd = seeds(s, at: [0])
		#expect(throws: RealmOwnership.Problem.nonFiniteCost) { try grow(s, seeds: sd, policy: GrowthPolicy(hillFactor: 1, mountainFactor: 1000, crossingFactor: 1, unevenness: 0), factors: nil) }
		var heightsHigh = s
		heightsHigh.heights = [80, 80]
		#expect(throws: RealmOwnership.Problem.nonFiniteCost) { try grow(heightsHigh, seeds: sd, policy: GrowthPolicy(hillFactor: 1, mountainFactor: 1000, crossingFactor: 1, unevenness: 0)) }
	}

	@Test func eachWorkBoundIsRefusedWithAName() throws {
		let s = try setup(["#.#.#.#.#", ".........", "#.#.#.#.#"], reach: 20)
		let sd = seeds(s, at: [0])
		func with(_ change: (inout GrowthPolicy) -> Void) -> RealmOwnership.Problem? {
			var p = flat
			change(&p)
			do { _ = try grow(s, seeds: sd, policy: p); return nil } catch let e as RealmOwnership.Problem { return e } catch { return nil }
		}
		#expect(with { $0.heapPushes = 1 } == .workBudget("pushes"))
		#expect(with { $0.edgeExaminations = 1 } == .workBudget("edges"))
		#expect(with { $0.verificationTests = 0 } == .workBudget("verification"))
		#expect(with { $0.heapPops = 1 } == .workBudget("pops"))
		#expect(with { _ in } == nil)
	}

	@Test func invalidPolicyAndInconsistentInputsAreRefusedAtTheBoundary() throws {
		let s = try setup(["#.#"], reach: 10)
		let sd = seeds(s, at: [0])
		for bad in [GrowthPolicy(hillFactor: 0.5, mountainFactor: 1, crossingFactor: 1, unevenness: 0), GrowthPolicy(hillFactor: 1, mountainFactor: .nan, crossingFactor: 1, unevenness: 0),
			GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 5_000, unevenness: 0), GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: -1),
			GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: 1_000), { var p = GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: 0); p.heapPops = -1; return p }()] {
			#expect(failure(s, seeds: sd, policy: bad) == .invalidPolicy)
		}
		var wrongSeeds = sd
		wrongSeeds.realms[0].cell = 1 // a water cell
		#expect(failure(s, seeds: wrongSeeds) == .invalidInputs)
		var duplicate = seeds(s, at: [0, 2])
		duplicate.realms[1].cell = 0
		#expect(failure(s, seeds: duplicate) == .invalidInputs)
		var count = sd
		count.resolvedCount = 3
		#expect(failure(s, seeds: count) == .invalidInputs)
		#expect(failure(s, seeds: sd, mutate: { $0.groups.links[0].cellA = 99 }) == .invalidInputs, "a link to a cell that does not exist")
		#expect(failure(s, seeds: sd, mutate: { $0.groups.links[0].landmassB = 0 }) == .invalidInputs, "a link inside one landmass")
		#expect(failure(s, seeds: sd, mutate: { $0.groups.links[0].pointA = Point(x: .nan, y: 0) }) == .invalidInputs)
		#expect(failure(s, seeds: sd, mutate: { $0.groups.landmassOfCell.removeLast() }) == .invalidInputs)
		#expect(failure(s, seeds: sd, mutate: { $0.sites[0] = Point(x: .infinity, y: 0) }) == .invalidInputs)
	}

	// MARK: generated maps

	@Test func onEveryTemplateGrowthIsCompleteConnectedAndUsesOnlyUsableCrossings() throws {
		var grown = 0
		var worstShare = 0.0
		for template in HeightmapTemplate.all {
			for n in 1...3 {
				let m = try LandMap.generate(seed: "kaz-\(n)", width: 400, height: 300, cellsDesired: 1500, template: template)
				for reach in [10.0, 25, 60] {
					let groups = try LandGroups.find(in: m, reach: reach)
					let policy = RealmPolicy(typicalRealmArea: 8000, maximumRealms: 300)
					for count in [RealmCount.automatic, .chosen(min(groups.minimumRealms + 2, 300))] {
						let seeds: RealmSeeds
						do { seeds = try RealmSeeds.place(in: m, groups: groups, count: count, realmSeed: "r", policy: policy) } catch RealmSeeds.Problem.aboveLandCells { continue }
						let growth = GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3)
						let o = try RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: "r", policy: growth)
						#expect(RealmOwnership.problems(in: o, groups: groups, seeds: seeds, neighbours: m.voronoi.cells.c).isEmpty, "\(template.key) kaz-\(n) reach \(reach)")
						#expect(o.realms.allSatisfy { $0.cellCount >= 1 } && o.realms.reduce(0, { $0 + $1.cellCount }) == m.heights.filter { Heights.isLand($0) }.count)
						#expect(o == (try RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: "r", policy: growth)), "deterministic")
						worstShare = max(worstShare, Double(o.realms.map(\.cellCount).max()!) / Double(o.owner.filter { $0 > 0 }.count))
						grown += 1
					}
				}
			}
		}
		print("GROWTH \(grown) generated cases completed; the largest realm's share of the land was at most \(worstShare)")
		#expect(grown > 100)
	}

	@Test func theGroupsSeedsAndLinksMustBelongToTheMapAtThePublicBoundary() throws {
		let m = try LandMap.generate(seed: "kaz-1", width: 400, height: 300, cellsDesired: 800, template: try #require(HeightmapTemplate.named("archipelago")))
		let groups = try LandGroups.find(in: m, reach: 25)
		let seeds = try RealmSeeds.place(in: m, groups: groups, count: .automatic, realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 8000, maximumRealms: 100))
		let growth = GrowthPolicy(hillFactor: 2, mountainFactor: 4, crossingFactor: 2, unevenness: 1)
		func result(_ g: LandGroups, _ s: RealmSeeds, _ p: GrowthPolicy? = nil) -> RealmOwnership.Problem? {
			do { _ = try RealmOwnership.grow(in: m, groups: g, seeds: s, realmSeed: "r", policy: p ?? growth); return nil } catch let e as RealmOwnership.Problem { return e } catch { return nil }
		}
		#expect(result(groups, seeds) == nil)
		var shorter = groups
		shorter.landmassOfCell.removeLast()
		#expect(result(shorter, seeds) == .invalidInputs, "shorter arrays must not trap")
		let other = try LandMap.generate(seed: "kaz-2", width: 400, height: 300, cellsDesired: 800, template: try #require(HeightmapTemplate.named("archipelago")))
		#expect(result(try LandGroups.find(in: other, reach: 25), seeds) == .invalidInputs, "groups that describe other land")
		var badSeed = seeds
		badSeed.realms[0].cell = groups.landmassOfCell.firstIndex { $0 < 0 }!
		#expect(result(groups, badSeed) == .invalidInputs, "a seed on water")
		var badLink = groups
		if !badLink.links.isEmpty { badLink.links[0].cellB = badLink.links[0].cellA }
		#expect(result(badLink, seeds) == .invalidInputs, "a link inside one landmass")
		#expect(result(shorter, seeds, GrowthPolicy(hillFactor: 0, mountainFactor: 1, crossingFactor: 1, unevenness: 0)) == .invalidPolicy, "the policy is checked first")
	}

	@Test func timingAtTenAndAHundredThousandCells() throws {
		for cells in [10_000, 100_000] {
			let m = try LandMap.generate(seed: "kaz-1", width: 1280, height: 800, cellsDesired: cells, template: try #require(HeightmapTemplate.named("archipelago")))
			let groups = try LandGroups.find(in: m, reach: 20)
			let seeds = try RealmSeeds.place(in: m, groups: groups, count: .chosen(max(groups.minimumRealms, 30)), realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 20_000, maximumRealms: 1000))
			let start = Date()
			let o = try RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: "r", policy: GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3))
			print("GROWTH \(cells) cells, \(seeds.realms.count) realms, \(groups.links.count) links: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
			#expect(RealmOwnership.problems(in: o, groups: groups, seeds: seeds, neighbours: m.voronoi.cells.c).isEmpty)
		}
	}
}
