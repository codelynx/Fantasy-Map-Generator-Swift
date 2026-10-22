import Foundation
import Testing
@testable import FantasyMapCore

/// Realms step 2 (docs/plans/realms.md): count validation, the allocation of realms over the groups and the seed cells.
struct RealmSeedsTests {
	typealias Cells = LandGroupsTests.Cells

	let policy = RealmPolicy(typicalRealmArea: 300, maximumRealms: 50)

	/// Groups, the cells' areas and sites for a picture, at an explicit reach.
	func setup(_ picture: [String], reach: Double = 0) throws -> (LandGroups, [Double], [Point]) {
		let c = Cells(picture)
		let groups = try c.groups(reach: reach)
		let areas = (0..<c.isLand.count).map { c.isLand[$0] ? c.s * c.s : 0 }
		let sites = (0..<c.isLand.count).map { cell in Point(x: (Double(cell % c.columns) + 0.5) * c.s, y: (Double(cell / c.columns) + 0.5) * c.s) }
		return (groups, areas, sites)
	}

	func seeds(_ picture: [String], reach: Double = 0, count: RealmCount, realmSeed: String = "r", policy: RealmPolicy? = nil) throws -> RealmSeeds {
		let (g, a, s) = try setup(picture, reach: reach)
		return try RealmSeeds.compute(groups: g, areas: a, sites: s, mapSeed: "map", count: count, realmSeed: realmSeed, policy: policy ?? self.policy)
	}

	func refused(_ picture: [String], reach: Double = 0, count: RealmCount, policy: RealmPolicy? = nil) -> RealmSeeds.Problem? {
		do { _ = try seeds(picture, reach: reach, count: count, policy: policy); return nil } catch let p as RealmSeeds.Problem { return p } catch { return nil }
	}

	// MARK: validating a count

	@Test func theSupportedIntervalAndEveryRefusalAtItsEdges() {
		let three = ["#.#.#"] // three landmasses, reach 0: C = 3, land cells 3
		#expect(refused(["...."], count: .automatic) == .noLand && refused(["...."], count: .chosen(1)) == .noLand)
		#expect(refused(three, count: .chosen(0)) == .countBelowOne && refused(three, count: .chosen(-4)) == .countBelowOne)
		#expect(refused(three, count: .chosen(2)) == .belowMinimum(minimum: 3), "below C: incompatible with the reach, and C is reported")
		#expect(refused(three, count: .chosen(3)) == nil, "K = C")
		#expect(refused(three, count: .chosen(4)) == .aboveLandCells(landCells: 3), "above the land-cell count")
		let big = ["###", "###"]
		#expect(refused(big, count: .chosen(6)) == nil, "K = the land-cell count")
		#expect(refused(big, count: .chosen(7)) == .aboveLandCells(landCells: 6))
		let capped = RealmPolicy(typicalRealmArea: 300, maximumRealms: 4)
		#expect(refused(big, count: .chosen(5), policy: capped) == .aboveMaximum(maximum: 4), "above the maximum, though within the land cells")
		#expect(refused(big, count: .chosen(4), policy: capped) == nil)
		// reach joins the islands: C falls, and a count that was below C becomes supported
		#expect(refused(three, reach: 10, count: .chosen(1)) == nil)
	}

	@Test func whenCItselfExceedsTheMaximumBothModesRefuseWithANamedErrorAndNothingIsWidenedOrReduced() {
		let many = ["#.#.#.#.#"] // C = 5 at reach 0
		let tiny = RealmPolicy(typicalRealmArea: 300, maximumRealms: 3)
		let expected = RealmSeeds.Problem.minimumAboveMaximum(minimum: 5, maximum: 3)
		#expect(refused(many, count: .automatic, policy: tiny) == expected)
		#expect(refused(many, count: .chosen(5), policy: tiny) == expected)
		#expect(refused(many, count: .chosen(3), policy: tiny) == expected, "not reduced to fit")
		// a reach that joins the islands (the author's choice) makes it supported
		#expect(refused(many, reach: 10, count: .automatic, policy: tiny) == nil)
	}

	@Test func theAutomaticCountIsTheLandAreaOverTheTypicalAreaWithinTheSupportedInterval() throws {
		let picture = ["#####", "#####", "#####"] // 15 cells of area 100: 1500; one group
		func count(_ typical: Double, maximum: Int = 50) throws -> Int {
			try seeds(picture, count: .automatic, policy: RealmPolicy(typicalRealmArea: typical, maximumRealms: maximum)).resolvedCount
		}
		let at300 = try count(300), at299 = try count(299)
		#expect(at300 == 5 && at299 == 5, "1500 / 300 = 5, 1500 / 299 rounds to 5")
		#expect(try count(1e9) == 1, "never below C")
		#expect(try count(1) == 15, "never above the land-cell count")
		#expect(try count(100, maximum: 7) == 7, "never above the maximum")
		let islands = try seeds(["#.#.#.#"], count: .automatic, policy: RealmPolicy(typicalRealmArea: 1e9, maximumRealms: 50))
		#expect(islands.resolvedCount == 4, "never below C (four islands at reach 0)")
	}

	@Test func eachGroupAsksForTheRealmsItsOwnAreaNeedsAndSpecksKeepOne() throws {
		// one landmass of 11 cells (area 1,100) and three one-cell specks (area 100 each), reach 0: C = 4. Typical area 300: the big group
		// asks for round(1100 / 300) = 4 realms and each speck for max(1, round(100 / 300)) = 1, so K = 7 and the extra three go to the
		// big landmass. (The earlier rule, total area over typical area, gave round(1400 / 300) = 5: the specks used up the count.)
		let picture = ["###########.#.#.#"]
		let r = try seeds(picture, count: .automatic, policy: RealmPolicy(typicalRealmArea: 300, maximumRealms: 50))
		#expect(r.resolvedCount == 7 && r.realmsPerGroup == [4, 1, 1, 1], "per group: \(r.realmsPerGroup)")
		#expect(r.mode == .automatic && r.realms.count == 7)
		// two equal landmasses, each below one and a half typical areas: one realm each (the total area would have said three)
		let two = try seeds(["####....####"], count: .automatic, policy: RealmPolicy(typicalRealmArea: 300, maximumRealms: 50))
		#expect(two.realmsPerGroup == [1, 1] && two.resolvedCount == 2)
		// a very large typical area: one realm per group, never below C
		#expect(try seeds(picture, count: .automatic, policy: RealmPolicy(typicalRealmArea: 1e9, maximumRealms: 50)).realmsPerGroup == [1, 1, 1, 1])
	}

	@Test func aGroupNeverAsksForMoreRealmsThanItHasCellsAndTheCapSharesTheRealmsByArea() throws {
		// a 2-cell landmass whose cells are huge asks for far more than 2: it gets 2; the 1-cell speck gets 1
		let c = Cells(["##.#"])
		let groups = try c.groups(reach: 0)
		let sites = (0..<4).map { Point(x: (Double($0) + 0.5) * 10, y: 5) }
		let big = try RealmSeeds.compute(groups: groups, areas: [100_000, 100_000, 0, 100], sites: sites, mapSeed: "m", count: .automatic, realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 300, maximumRealms: 5_000))
		#expect(big.realmsPerGroup == [2, 1] && big.resolvedCount == 3, "capped at the group's cells: \(big.realmsPerGroup)")
		// when the groups ask for more than the maximum, the count is the maximum and the realms are shared by area, each group keeping one
		let wide = Cells([String(repeating: "#", count: 10) + "." + String(repeating: "#", count: 10)])
		let wg = try wide.groups(reach: 0)
		let ws = (0..<21).map { Point(x: (Double($0) + 0.5) * 10, y: 5) }
		let capped = try RealmSeeds.compute(groups: wg, areas: (0..<21).map { $0 == 10 ? 0 : 1_000 }, sites: ws, mapSeed: "m", count: .automatic, realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 300, maximumRealms: 6))
		#expect(capped.resolvedCount == 6 && capped.realmsPerGroup.reduce(0, +) == 6 && capped.realmsPerGroup.allSatisfy { $0 >= 1 }, "capped: \(capped.realmsPerGroup)")
		// and the automatic count never falls below C or goes above the supported interval
		#expect(capped.resolvedCount >= wg.minimumRealms)
	}

	@Test func theCountIsFixedBeforeAnyRealmIsAdded() throws {
		let r = try seeds(["######", "######"], count: .chosen(5))
		#expect(r.resolvedCount == 5 && r.realms.count == 5 && r.realmsPerGroup == [5] && r.mode == .chosen(5))
	}

	@Test func policyInputsMustBeValid() {
		for bad in [RealmPolicy(typicalRealmArea: 0, maximumRealms: 5), RealmPolicy(typicalRealmArea: -1, maximumRealms: 5), RealmPolicy(typicalRealmArea: .nan, maximumRealms: 5),
			RealmPolicy(typicalRealmArea: .infinity, maximumRealms: 5), RealmPolicy(typicalRealmArea: 1, maximumRealms: 0), RealmPolicy(typicalRealmArea: 1, maximumRealms: 5, sampleSize: 0),
			RealmPolicy(typicalRealmArea: 1, maximumRealms: 5, workBudget: -1)] {
			#expect(refused(["###"], count: .automatic, policy: bad) == .invalidPolicy)
			#expect(refused(["..."], count: .automatic, policy: bad) == .invalidPolicy, "checked before anything else, even with no land")
		}
	}

	// MARK: the allocation

	@Test func allocationSumsToTheCountAndRespectsEveryCapacity() {
		var seed: UInt64 = 99
		func random() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
		for _ in 0..<300 {
			let groups = 1 + Int(random() * 7)
			let capacities = (0..<groups).map { _ in Int(random() * 12) }
			let weights = (0..<groups).map { _ in random() * 100 + 0.5 }
			let extra = Int(random() * Double(capacities.reduce(0, +) + 1))
			let given = RealmSeeds.allocate(extra: extra, weights: weights, capacities: capacities)
			#expect(given.reduce(0, +) == extra, "weights \(weights), capacities \(capacities), extra \(extra): \(given)")
			#expect(zip(given, capacities).allSatisfy { $0 <= $1 })
			#expect(given == RealmSeeds.allocate(extra: extra, weights: weights, capacities: capacities), "deterministic")
		}
	}

	@Test func saturatedGroupsAreRemovedAndTheSurplusIsReapportioned() {
		// weights 1000, 1, 1 with capacities 2, 50, 50 and 10 to give: the heavy group saturates at 2, the other 8 are split 4 and 4
		#expect(RealmSeeds.allocate(extra: 10, weights: [1000, 1, 1], capacities: [2, 50, 50]) == [2, 4, 4])
		// two rounds: after the first group saturates, the second's recomputed quota also exceeds its capacity
		#expect(RealmSeeds.allocate(extra: 12, weights: [1000, 100, 1], capacities: [1, 3, 50]) == [1, 3, 8])
		#expect(RealmSeeds.allocate(extra: 0, weights: [3, 1], capacities: [5, 5]) == [0, 0])
		#expect(RealmSeeds.allocate(extra: 10, weights: [3, 1], capacities: [5, 5]) == [5, 5], "every capacity used")
	}

	@Test func remaindersGoToTheLargestFractionAndTiesToTheSmallerGroup() {
		#expect(RealmSeeds.allocate(extra: 1, weights: [1, 1, 1], capacities: [5, 5, 5]) == [1, 0, 0], "a three-way tie: the smaller group number")
		#expect(RealmSeeds.allocate(extra: 2, weights: [1, 1, 1], capacities: [5, 5, 5]) == [1, 1, 0])
		// quotas 3 x (5, 3, 2) / 10 = 1.5, 0.9, 0.6: floors 1, 0, 0, then the largest fractions 0.9 and 0.6 take the two left
		#expect(RealmSeeds.allocate(extra: 3, weights: [5, 3, 2], capacities: [9, 9, 9]) == [1, 1, 1])
		#expect(RealmSeeds.allocate(extra: 1, weights: [5, 3, 2], capacities: [9, 9, 9]) == [1, 0, 0], "0.5 is the largest fraction")
		// a remainder cannot go past a capacity: the next largest fraction takes it
		#expect(RealmSeeds.allocate(extra: 1, weights: [1, 1], capacities: [0, 5]) == [0, 1])
		// all weights zero: shared equally
		#expect(RealmSeeds.allocate(extra: 4, weights: [0, 0], capacities: [9, 9]) == [2, 2])
	}

	@Test func groupsGetWeightFromClippedLandAreaNotFromCellCounts() throws {
		// two groups of the same cell count (two cells each): group 0's cells are small (area 10), group 1's large (area 1000)
		let c = Cells(["##.##"])
		let groups = try c.groups(reach: 0)
		let areas: [Double] = [10, 10, 0, 1000, 1000]
		let sites = (0..<5).map { Point(x: (Double($0) + 0.5) * 10, y: 5) }
		let r = try RealmSeeds.compute(groups: groups, areas: areas, sites: sites, mapSeed: "m", count: .chosen(4), realmSeed: "s", policy: policy)
		#expect(r.realmsPerGroup == [1, 3] || r.realmsPerGroup == [2, 2], "the heavier group takes the extra realms first: \(r.realmsPerGroup)")
		let heavy = try RealmSeeds.compute(groups: groups, areas: [1, 1, 0, 1_000_000, 1_000_000], sites: sites, mapSeed: "m", count: .chosen(3), realmSeed: "s", policy: policy)
		#expect(heavy.realmsPerGroup == [1, 2], "one realm for the light group, the extra to the heavy one")
	}

	// MARK: the seeds

	@Test func seedsAreDistinctLandCellsInTheRightGroupWithTheAllocatedCounts() throws {
		let picture = ["##########", "##########", "..........", "####......", "####......"]
		let (g, _, _) = try setup(picture)
		let r = try seeds(picture, count: .chosen(7))
		#expect(r.realms.count == 7 && r.realms.map(\.number) == Array(1...7) && r.realmsPerGroup.reduce(0, +) == 7)
		#expect(Set(r.realms.map(\.cell)).count == 7, "distinct")
		for realm in r.realms { #expect(Int(g.groupOfCell[realm.cell]) == realm.group, "a seed lies in its own group") }
		for g in r.realmsPerGroup.indices { #expect(r.realms.filter { $0.group == g }.count == r.realmsPerGroup[g]) }
		#expect(r.realms.map(\.group) == r.realms.map(\.group).sorted(), "numbers run in group order")
	}

	@Test func theCountEqualToTheLandCellsUsesEveryLandCellExactlyOnce() throws {
		let picture = ["####", "####", "..##"]
		let (g, _, _) = try setup(picture)
		let landCells = g.groupOfCell.indices.filter { g.groupOfCell[$0] >= 0 }
		for realmSeed in ["a", "b", "c"] {
			let r = try seeds(picture, count: .chosen(landCells.count), realmSeed: realmSeed)
			#expect(r.realms.map(\.cell).sorted() == landCells, "the pool is sampled without replacement and never exhausts early")
		}
	}

	@Test func aSampleOfOneStillNeverRepeatsACellBecauseTheChosenCellLeavesThePool() throws {
		// with a sample of one the candidate is simply a random cell of the pool: if chosen cells stayed in the pool the same cell
		// would come up again; with the pool shrinking, every land cell is used exactly once at K = the land-cell count
		let picture = ["####", "####", "####"]
		let (g, _, _) = try setup(picture)
		let landCells = g.groupOfCell.indices.filter { g.groupOfCell[$0] >= 0 }
		for realmSeed in ["a", "b", "c", "d", "e"] {
			let r = try seeds(picture, count: .chosen(landCells.count), realmSeed: realmSeed, policy: RealmPolicy(typicalRealmArea: 300, maximumRealms: 50, sampleSize: 1))
			#expect(r.realms.map(\.cell).sorted() == landCells, "realm seed \(realmSeed)")
		}
	}

	@Test func equallyFarCandidatesTieToTheSmallerCellIndex() throws {
		// three cells in a row, two realms: when the first seed is the middle cell, cells 0 and 2 are exactly as far; the smaller wins
		var middleFirst = 0
		for realmSeed in (0..<40).map({ "tie\($0)" }) {
			let r = try seeds(["###"], count: .chosen(2), realmSeed: realmSeed)
			if r.realms[0].cell == 1 {
				middleFirst += 1
				#expect(r.realms[1].cell == 0, "a tie between cells 0 and 2 goes to cell 0")
			}
		}
		#expect(middleFirst > 3, "the tie was met on \(middleFirst) of 40 seeds")
	}

	@Test func identicalInputsGiveIdenticalSeedsAndSeedsChangeResultsOnNontrivialCases() throws {
		let picture = ["############", "############", "############", "############"]
		let a = try seeds(picture, count: .chosen(6), realmSeed: "alpha")
		#expect(a == (try seeds(picture, count: .chosen(6), realmSeed: "alpha")))
		let others = try ["beta", "gamma", "delta", "epsilon"].map { try seeds(picture, count: .chosen(6), realmSeed: $0) }
		#expect(others.contains { $0.realms.map(\.cell) != a.realms.map(\.cell) }, "another realm seed changes the seeds on this nontrivial case")
		// a one-cell group with one realm cannot vary, and no test claims it does
		let single = ["#.."]
		#expect(try seeds(single, count: .chosen(1), realmSeed: "x").realms.map(\.cell) == (try seeds(single, count: .chosen(1), realmSeed: "y").realms.map(\.cell)))
		// the map's seed matters too
		let (g, areas, sites) = try setup(picture)
		let m1 = try RealmSeeds.compute(groups: g, areas: areas, sites: sites, mapSeed: "one", count: .chosen(6), realmSeed: "r", policy: policy)
		let others2 = try ["two", "three", "four", "five"].map { try RealmSeeds.compute(groups: g, areas: areas, sites: sites, mapSeed: $0, count: .chosen(6), realmSeed: "r", policy: policy) }
		#expect(others2.contains { $0.realms.map(\.cell) != m1.realms.map(\.cell) })
	}

	@Test func seedsAreSpreadFartherThanPlainRandomChoiceOnAverage() throws {
		// evidence, not a promise: on an open 16 x 16 land the least distance between six seeds is larger, on average over many seeds,
		// than for six cells drawn at random without replacement
		let picture = [String](repeating: String(repeating: "#", count: 16), count: 16)
		let (g, areas, sites) = try setup(picture)
		func leastDistance(_ cells: [Int]) -> Double {
			var least = Double.infinity
			for (i, a) in cells.enumerated() { for b in cells[(i + 1)...] { least = min(least, ((sites[a].x - sites[b].x) * (sites[a].x - sites[b].x) + (sites[a].y - sites[b].y) * (sites[a].y - sites[b].y)).squareRoot()) } }
			return least
		}
		var placed = 0.0, random = 0.0
		let trials = 60
		for t in 0..<trials {
			let r = try RealmSeeds.compute(groups: g, areas: areas, sites: sites, mapSeed: "m", count: .chosen(6), realmSeed: "t\(t)", policy: policy)
			placed += leastDistance(r.realms.map(\.cell))
			var alea = Alea(seed: "baseline\(t)")
			var pool = Array(0..<256)
			var chosen: [Int] = []
			for _ in 0..<6 { let i = Int(alea.next() * Double(pool.count)); chosen.append(pool.remove(at: i)) }
			random += leastDistance(chosen)
		}
		print("SPREAD least distance between six seeds, mean of \(trials): best-candidate \(placed / Double(trials)), random \(random / Double(trials))")
		#expect(placed > random)
	}

	@Test func theWorkPreflightIsTheExactCountOfCandidateEvaluationsIncludingAShrinkingPool() throws {
		// a group of 10 cells with 10 realms and a sample of 24: placing the k-th seed evaluates min(24, 10 - k) candidates against k seeds,
		// 9 + 16 + 21 + 24 + 25 + 24 + 21 + 16 + 9 = 165 (the plain s x m(m-1)/2 would be 24 x 45 = 1,080)
		let picture = ["##########"]
		var p = policy
		p.workBudget = 165
		#expect(refused(picture, count: .chosen(10), policy: p) == nil, "exactly the counted work is enough")
		p.workBudget = 164
		#expect(refused(picture, count: .chosen(10), policy: p) == .workBudget)
	}

	@Test func theWorkBoundIsRefusedBeforeAnySeedIsPlaced() throws {
		let picture = [String](repeating: String(repeating: "#", count: 10), count: 10)
		var tight = policy
		tight.workBudget = 10
		// 50 realms in one group, sample 24: 50 x 49 / 2 x 24 = 29,400 evaluations
		#expect(refused(picture, count: .chosen(50), policy: tight) == .workBudget)
		var exact = policy
		exact.workBudget = 29_400
		#expect(refused(picture, count: .chosen(50), policy: exact) == nil, "exactly the counted work is enough")
		exact.workBudget = 29_399
		#expect(refused(picture, count: .chosen(50), policy: exact) == .workBudget)
		var one = policy
		one.workBudget = 0
		#expect(refused(picture, count: .chosen(1), policy: one) == nil, "one realm needs no distance evaluations")
	}

	// MARK: the public entry point

	func generated() throws -> (LandMap, LandGroups) {
		let m = try LandMap.generate(seed: "kaz-1", width: 400, height: 300, cellsDesired: 800, template: try #require(HeightmapTemplate.named("archipelago")))
		return (m, try LandGroups.find(in: m, reach: 20))
	}

	@Test func theGroupsMustBelongToTheMapAndAreCheckedBeforeAnyWork() throws {
		let (m, good) = try generated()
		func place(_ groups: LandGroups, policy p: RealmPolicy? = nil) -> RealmSeeds.Problem? {
			do { _ = try RealmSeeds.place(in: m, groups: groups, count: .automatic, realmSeed: "r", policy: p ?? RealmPolicy(typicalRealmArea: 4000, maximumRealms: 200)); return nil } catch let e as RealmSeeds.Problem { return e } catch { return nil }
		}
		#expect(place(good) == nil, "the real groups are accepted")
		var shorter = good
		shorter.landmassOfCell.removeLast()
		#expect(place(shorter) == .invalidGroups, "a shorter per-cell array must not trap")
		var shorterGroup = good
		shorterGroup.groupOfCell.removeLast()
		#expect(place(shorterGroup) == .invalidGroups)
		var badLandmass = good
		let landCell = good.landmassOfCell.firstIndex { $0 >= 0 }!
		badLandmass.landmassOfCell[landCell] = Int32(good.landmasses.count + 5)
		#expect(place(badLandmass) == .invalidGroups, "an out-of-range landmass index")
		var badGroup = good
		badGroup.groupOfCell[landCell] = Int32(good.groups.count + 2)
		#expect(place(badGroup) == .invalidGroups, "an out-of-range group index")
		var negative = good
		negative.groupOfCell[landCell] = -7
		#expect(place(negative) == .invalidGroups)
		var membership = good
		membership.landmassOfCell[landCell] = -1
		membership.groupOfCell[landCell] = -1
		#expect(place(membership) == .invalidGroups, "a land cell marked as water")
		var water = good
		let waterCell = good.landmassOfCell.firstIndex { $0 < 0 }!
		water.landmassOfCell[waterCell] = 0
		water.groupOfCell[waterCell] = 0
		#expect(place(water) == .invalidGroups, "a water cell marked as land")
		var counts = good
		counts.groups[0].cellCount += 1
		#expect(place(counts) == .invalidGroups, "an inconsistent stored group count")
		var landmassCounts = good
		landmassCounts.landmasses[0].cellCount -= 1
		#expect(place(landmassCounts) == .invalidGroups, "an inconsistent stored landmass count")
		var wrongGroup = good
		wrongGroup.landmasses[0].group = good.groups.count
		#expect(place(wrongGroup) == .invalidGroups)
		// groups from another map (a different number of cells)
		let other = try LandMap.generate(seed: "kaz-1", width: 400, height: 300, cellsDesired: 1200, template: try #require(HeightmapTemplate.named("archipelago")))
		#expect(place(try LandGroups.find(in: other, reach: 20)) == .invalidGroups, "groups of another map")
		// groups of another map with the SAME number of cells: structurally consistent, but land and water do not match this map
		let sameSize = try LandMap.generate(seed: "kaz-2", width: 400, height: 300, cellsDesired: 800, template: try #require(HeightmapTemplate.named("archipelago")))
		#expect(sameSize.heights.count == m.heights.count)
		#expect(place(try LandGroups.find(in: sameSize, reach: 20)) == .invalidGroups, "consistent groups that describe different land")
		// empty groups
		#expect(place(LandGroups(landmassOfCell: [], groupOfCell: [], landmasses: [], groups: [], links: [])) == .invalidGroups)
		// the documented order: the policy is validated first, even with groups that are also wrong
		#expect(place(shorter, policy: RealmPolicy(typicalRealmArea: 0, maximumRealms: 5)) == .invalidPolicy)
		#expect(place(good, policy: RealmPolicy(typicalRealmArea: .nan, maximumRealms: 5)) == .invalidPolicy, "invalid policy is refused at the public entry point too")
		#expect(place(good, policy: RealmPolicy(typicalRealmArea: 1, maximumRealms: 0)) == .invalidPolicy)
	}

	// MARK: on generated maps

	@Test func onGeneratedMapsTheSeedsAreLandCellsOfTheirGroups() throws {
		for key in ["archipelago", "continents", "shattered"] {
			let m = try LandMap.generate(seed: "kaz-1", width: 400, height: 300, cellsDesired: 800, template: try #require(HeightmapTemplate.named(key)))
			let groups = try LandGroups.find(in: m, reach: 20)
			let big = RealmPolicy(typicalRealmArea: 4000, maximumRealms: 200)
			let auto = try RealmSeeds.place(in: m, groups: groups, count: .automatic, realmSeed: "r", policy: big)
			#expect(auto.resolvedCount >= groups.minimumRealms && auto.realms.count == auto.resolvedCount, "\(key)")
			for realm in auto.realms {
				#expect(Heights.isLand(m.heights[realm.cell]) && Int(groups.groupOfCell[realm.cell]) == realm.group)
			}
			#expect(Set(auto.realms.map(\.cell)).count == auto.realms.count)
			#expect(auto == (try RealmSeeds.place(in: m, groups: groups, count: .automatic, realmSeed: "r", policy: big)))
			let chosen = try RealmSeeds.place(in: m, groups: groups, count: .chosen(groups.minimumRealms + 3), realmSeed: "r", policy: big)
			#expect(chosen.resolvedCount == groups.minimumRealms + 3 && chosen.mode == .chosen(groups.minimumRealms + 3))
		}
	}

	@Test func timingAtTenAndAHundredThousandCells() throws {
		for cells in [10_000, 100_000] {
			let m = try LandMap.generate(seed: "kaz-1", width: 1280, height: 800, cellsDesired: cells, template: try #require(HeightmapTemplate.named("archipelago")))
			let groups = try LandGroups.find(in: m, reach: 20)
			for count in [groups.minimumRealms, groups.minimumRealms + 20, 200] {
				let start = Date()
				let r = try RealmSeeds.place(in: m, groups: groups, count: .chosen(count), realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 20_000, maximumRealms: 1000))
				print("SEEDS \(cells) cells, C \(groups.minimumRealms), K \(count): \(r.realms.count) seeds, \(Int(Date().timeIntervalSince(start) * 1000)) ms")
				#expect(r.realms.count == count)
			}
		}
	}
}
