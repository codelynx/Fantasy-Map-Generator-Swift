import Foundation
import Testing
@testable import FantasyMapKit

/// Saving and loading the realms (docs/plans/realms-saving.md): the realm layer in the land map's own file.
struct RealmLayerTests {
	func map(_ seed: String = "kaz-1", template: String = "continents", cells: Int = 1500) throws -> LandMap {
		try LandMap.generate(seed: seed, width: 800, height: 500, cellsDesired: cells, template: try #require(HeightmapTemplate.named(template)))
	}

	/// A realm layer made by the generators for the map, with the recipe that made it and colours for each realm.
	func layer(_ m: LandMap, realmSeed: String = "realms-1", reach: Double = 25, chosen: Int? = nil, unevenness: Double = 3, withColors: Bool = true) throws -> RealmLayer {
		let groups = try LandGroups.find(in: m, reach: reach)
		let policy = RealmPolicy(typicalRealmArea: 40_000, maximumRealms: 500)
		let seeds = try RealmSeeds.place(in: m, groups: groups, count: chosen.map { .chosen($0) } ?? .automatic, realmSeed: realmSeed, policy: policy)
		let growth = GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: unevenness)
		let ownership = try RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: realmSeed, policy: growth)
		let recipe = RealmRecipe(realmSeed: realmSeed, reach: reach, chosenCount: chosen, resolvedCount: seeds.resolvedCount, typicalRealmArea: 40_000, maximumRealms: 500, hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: unevenness)
		let colors = (1...ownership.realms.count).map { RealmColor(red: Double($0 % 7) / 7, green: Double($0 % 5) / 5, blue: Double($0 % 3) / 3) }
		return RealmLayer(ownership: ownership, recipe: recipe, colors: withColors ? colors : nil)
	}

	func withRealms() throws -> (LandMap, RealmLayer) {
		let m = try map()
		let l = try layer(m)
		return (try m.adding(l), l)
	}

	func refused(_ saved: SavedLandMap, _ expected: Error? = nil, line: Int = #line) {
		var failed = false
		do { _ = try LandMap(saved: saved) } catch { failed = true; if let expected { #expect("\(error)" == "\(expected)", "\(error)", sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1)) } }
		#expect(failed, "refused", sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1))
	}

	// MARK: round trips

	@Test func aMapWithRealmsRoundTripsExactlyAndTheOldFormatIsUnchanged() throws {
		let (m, l) = try withRealms()
		#expect(m.realms == l && l.ownership.realms.count >= 4)
		let data = try m.encoded()
		let loaded = try LandMap(decoding: data)
		#expect(loaded == m && loaded.realms == l && loaded.voronoi == m.voronoi)
		#expect(try loaded.encoded() == data, "saving what was loaded gives the same bytes")
		#expect(m.saved.formatVersion == 2 && m.saved.realms != nil)
		// a map without realms is written exactly as before: version 1, no realms key
		let plain = try map()
		let plainData = try plain.encoded()
		#expect(plain.realms == nil && plain.saved.formatVersion == 1 && !String(decoding: plainData, as: UTF8.self).contains("\"realms\""))
		#expect(try LandMap(decoding: plainData).realms == nil, "an old file loads as a map with no realms: a distinct valid state")
		let plainLoaded = try LandMap(decoding: plainData)
		let plainResaved = try plainLoaded.encoded()
		#expect(plainLoaded == plain && plainResaved == plainData)
		#expect(m.removingRealms() == plain && m.removingRealms().realms == nil)
	}

	@Test func manyMapsWithRealmsRoundTripAndEqualRealmsGrownAgainFromTheRecipe() throws {
		var checked = 0
		for (i, template) in HeightmapTemplate.all.map(\.key).enumerated() {
			for (chosen, unevenness) in [(Int?.none, 3.0), (5, 0.0), (7, 12.0)] {
				let m = try map("rl\(i)", template: template, cells: 1200)
				guard (try? LandGroups.find(in: m, reach: 25))?.minimumRealms ?? Int.max <= (chosen ?? 1) else { continue }
				let l = try layer(m, chosen: chosen, unevenness: unevenness)
				let withLayer = try m.adding(l)
				let data = try withLayer.encoded()
				let loaded = try LandMap(decoding: data)
				let resaved = try loaded.encoded()
				#expect(loaded == withLayer && resaved == data, "\(template) \(chosen as Any) \(unevenness)")
				// the loaded ownership is what the recipe grows again (the saved state is the exact one, and the recipe says how it was made)
				let again = try layer(m, realmSeed: l.recipe.realmSeed, reach: l.recipe.reach, chosen: l.recipe.chosenCount, unevenness: l.recipe.unevenness)
				#expect(loaded.realms?.ownership.owner == again.ownership.owner && loaded.realms?.ownership.realms == again.ownership.realms)
				checked += 1
			}
		}
		#expect(checked >= 14)
	}

	@Test func twoMapsDifferWhenTheirRealmsDiffer() throws {
		let (m, l) = try withRealms()
		#expect(m != m.removingRealms())
		var other = l
		other.colors = other.colors?.reversed()
		#expect(try m != m.removingRealms().adding(other))
		other = l
		other.recipe.realmSeed = "another"
		#expect(try m != m.removingRealms().adding(other), "the recipe is part of the saved state")
		#expect(try m == m.removingRealms().adding(l))
	}

	@Test func validatingManyRealmsDoesLinearWorkNotOneScanPerRealm() throws {
		// many realms on a small map: the ownership's check once scanned every cell for each realm (realms x cells); now the work is counted and bounded by the cells,
		// their neighbours and the links, whatever the number of realms. A count, not a clock.
		let m = try map("many", template: "continents", cells: 3000)
		let l = try layer(m, chosen: 250)
		let k = l.ownership.realms.count
		#expect(k >= 200)
		_ = try m.adding(l) // the whole validation passes
		let groups = try LandGroups.find(in: m, reach: l.recipe.reach)
		var perGroup = [Int](repeating: 0, count: groups.groups.count)
		for r in l.ownership.realms { perGroup[r.group] += 1 }
		let seeds = RealmSeeds(mode: .chosen(250), resolvedCount: k, realmsPerGroup: perGroup, realms: l.ownership.realms.map { RealmSeeds.Realm(number: $0.number, group: $0.group, cell: $0.seedCell) })
		var work = 0
		let found = RealmOwnership.problems(in: l.ownership, groups: groups, seeds: seeds, neighbours: m.voronoi.cells.c, work: &work)
		#expect(found.isEmpty)
		let n = m.heights.count, land = m.heights.filter { Heights.isLand($0) }.count
		let neighbourEntries = m.voronoi.cells.c.reduce(0) { $0 + $1.count }
		#expect(work >= land, "every land cell is visited by its own realm's search")
		#expect(work <= 2 * n + 3 * groups.links.count + neighbourEntries, "work \(work) for \(k) realms on \(n) cells (one scan per realm would be \(k * n))")
		#expect(work < k * n / 4, "far below the one scan per realm it replaces")
	}

	@Test func theOwnershipCheckReportsInvalidOwnersWithoutTrapping() throws {
		let m = try map()
		let l = try layer(m)
		let groups = try LandGroups.find(in: m, reach: l.recipe.reach)
		var perGroup = [Int](repeating: 0, count: groups.groups.count)
		for r in l.ownership.realms { perGroup[r.group] += 1 }
		let seeds = RealmSeeds(mode: .automatic, resolvedCount: l.ownership.realms.count, realmsPerGroup: perGroup, realms: l.ownership.realms.map { RealmSeeds.Realm(number: $0.number, group: $0.group, cell: $0.seedCell) })
		for bad in [Int32(l.ownership.realms.count + 1), -1, Int32.max] {
			var o = l.ownership
			let seedCells = Set(l.ownership.realms.map(\.seedCell))
			let victim = try #require(m.heights.indices.first { Heights.isLand(m.heights[$0]) && !seedCells.contains($0) })
			o.owner[victim] = bad
			let found = RealmOwnership.problems(in: o, groups: groups, seeds: seeds, neighbours: m.voronoi.cells.c)
			#expect(found.contains { $0.contains("invalid owner") }, "owner \(bad): \(found.prefix(3))")
		}
		#expect(RealmOwnership.problems(in: l.ownership, groups: groups, seeds: seeds, neighbours: m.voronoi.cells.c).isEmpty)
	}

	@Test func theLinksUsedForConnectivityAreVerifiedAsCrossingsWithABudget() throws {
		// a map of several islands with links between them
		var found: (LandMap, RealmLayer)?
		for template in ["archipelago", "shattered", "highIsland", "mediterranean"] {
			for seed in ["a", "b", "c", "d", "e", "f"] where found == nil {
				let candidate = try map(seed, template: template, cells: 1500)
				guard let groups = try? LandGroups.find(in: candidate, reach: 60), !groups.links.isEmpty, let made = try? layer(candidate, reach: 60), let attached = try? candidate.adding(made) else { continue }
				found = (attached, made)
			}
		}
		let (m, l) = try #require(found, "a map whose islands are joined by crossings")
		#expect(m.realms == l)
		// the verification itself, with no budget at all: the first link cannot be tested within it
		let groups = try LandGroups.find(in: m, reach: 60)
		let v = m.voronoi
		var polygons = [[Point]](repeating: [], count: m.heights.count)
		for cell in 0..<m.heights.count where Heights.isLand(m.heights[cell]) { polygons[cell] = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: m.width, height: m.height) }
		try RealmOwnership.verifyCrossings(groups: groups, polygons: polygons, width: m.width, height: m.height, budget: 200_000_000)
		#expect(throws: RealmOwnership.Problem.self) { try RealmOwnership.verifyCrossings(groups: groups, polygons: polygons, width: m.width, height: m.height, budget: 0) }
		// a link that is not a genuine witness (its point moved off its cell) is refused
		var tampered = groups
		tampered.links[0].pointA = Point(x: tampered.links[0].pointA.x + 50, y: tampered.links[0].pointA.y + 50)
		#expect(throws: RealmOwnership.Problem.self) { try RealmOwnership.verifyCrossings(groups: tampered, polygons: polygons, width: m.width, height: m.height, budget: 200_000_000) }
		// the layer's own validation refuses when the crossings cannot be verified within the budget
		#expect(throws: RealmLayerError.self) { try l.validate(for: m.removingRealms(), crossingBudget: 0) }
		try l.validate(for: m.removingRealms())
	}

	@Test func theColoursAreSavedWithTheRealmsAndKeptApartFromTheOwnerData() throws {
		let m = try map()
		let withColours = try m.adding(try layer(m)), without = try m.adding(try layer(m, withColors: false))
		let a = try LandMap(decoding: try withColours.encoded()), b = try LandMap(decoding: try without.encoded())
		#expect(a.realms?.colors?.count == a.realms?.ownership.realms.count && a.realms?.colors == withColours.realms?.colors)
		#expect(b.realms?.colors == nil && b.realms?.ownership == a.realms?.ownership, "the owner data is the same with or without colours")
		#expect(try b.encoded() == (try without.encoded()))
	}

	@Test func aWaterMapCarriesTheRealmsOfItsLandMap() throws {
		let (m, l) = try withRealms()
		let water = try WaterMap.generate(land: m)
		#expect(water.land.realms == l)
		let loaded = try WaterMap(decoding: try water.encoded())
		#expect(loaded == water && loaded.land.realms == l)
		#expect(try WaterMap(decoding: try water.compressedEncoded()).land.realms == l)
	}

	// MARK: refusals

	@Test func theVersionSaysWhetherThereIsARealmLayer() throws {
		let (m, _) = try withRealms()
		var saved = m.saved
		saved.formatVersion = 1
		refused(saved, SavedLandMapError.realmLayerDoesNotMatchVersion)
		var noRealms = try map().saved
		noRealms.formatVersion = 2
		refused(noRealms, SavedLandMapError.realmLayerDoesNotMatchVersion)
		var unknown = m.saved
		unknown.formatVersion = 3
		refused(unknown)
		var injected = try map().saved
		injected.realms = m.saved.realms
		refused(injected, SavedLandMapError.realmLayerDoesNotMatchVersion)
	}

	@Test func theOwnerArrayAndTheRealmRecordsAreChecked() throws {
		let (m, _) = try withRealms()
		let good = m.saved
		func edit(_ change: (inout SavedRealmLayer) -> Void) -> SavedLandMap { var s = good; change(&s.realms!); return s }
		let landCell = try #require(m.heights.indices.first { Heights.isLand(m.heights[$0]) })
		let waterCell = try #require(m.heights.indices.first { !Heights.isLand(m.heights[$0]) })
		refused(edit { $0.owner.removeLast() }, RealmLayerError.ownershipDoesNotMatchMap)
		refused(edit { $0.owner[landCell] = 0 }, RealmLayerError.ownershipDoesNotMatchMap)
		refused(edit { $0.owner[landCell] = Int32($0.realms.count + 1) }, RealmLayerError.ownershipDoesNotMatchMap)
		refused(edit { $0.owner[landCell] = -1 }, RealmLayerError.ownershipDoesNotMatchMap)
		refused(edit { $0.owner[waterCell] = 1 }, RealmLayerError.ownershipDoesNotMatchMap)
		refused(edit { $0.realms[0].number = 9 }, RealmLayerError.ownershipDoesNotMatchMap)
		refused(edit { $0.realms[1].cellCount += 1 }, RealmLayerError.invalidRealmRecord(number: 2))
		refused(edit { $0.realms[1].cellCount = 0 }, RealmLayerError.invalidRealmRecord(number: 2))
		refused(edit { $0.realms[1].area += 1 }, RealmLayerError.invalidRealmRecord(number: 2))
		refused(edit { $0.realms[1].area = .nan }, RealmLayerError.invalidRealmRecord(number: 2))
		refused(edit { $0.realms[1].seedCell = -1 }, RealmLayerError.invalidRealmRecord(number: 2))
		refused(edit { $0.realms[1].seedCell = m.heights.count }, RealmLayerError.invalidRealmRecord(number: 2))
		// a seed cell that is land but belongs to another realm
		let other = try #require(m.heights.indices.first { Heights.isLand(m.heights[$0]) && good.realms!.owner[$0] == 1 })
		refused(edit { $0.realms[1].seedCell = other }, RealmLayerError.invalidRealmRecord(number: 2))
		refused(edit { $0.realms[1].group += 1 }, RealmLayerError.invalidRealmRecord(number: 2))
	}

	@Test func aSeedCellOutsideTheMapIsRefusedEvenWhenTheFirstOrLastCellIsTheRealms() throws {
		// find a map whose first or last cell is land owned by some realm, so that an index that is clamped into the map would pass the ownership test
		var found: (LandMap, RealmLayer, Int, Int)?
		search: for template in HeightmapTemplate.all.map(\.key) {
			for seed in ["e1", "e2", "e3", "e4", "e5", "e6"] {
				let m = try map(seed, template: template, cells: 600)
				guard let l = try? layer(m), let attached = try? m.adding(l) else { continue }
				let n = m.heights.count
				if l.ownership.owner[0] > 0 { found = (attached, l, Int(l.ownership.owner[0]), -1); break search }
				if l.ownership.owner[n - 1] > 0 { found = (attached, l, Int(l.ownership.owner[n - 1]), n); break search }
			}
		}
		let (attached, _, number, outside) = try #require(found, "a map with land at its first or last cell")
		var saved = attached.saved
		saved.realms!.realms[number - 1].seedCell = outside
		refused(saved, RealmLayerError.invalidRealmRecord(number: number))
	}

	/// The records recomputed for an owner array, as the layer's own validation computes them.
	func recounted(_ saved: SavedLandMap, _ owner: [Int32], _ m: LandMap) -> SavedLandMap {
		var s = saved
		s.realms!.owner = owner
		let v = m.voronoi
		for i in s.realms!.realms.indices { s.realms!.realms[i].cellCount = 0; s.realms!.realms[i].area = 0 }
		for cell in 0..<m.heights.count where owner[cell] > 0 {
			let polygon = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: m.width, height: m.height)
			s.realms!.realms[Int(owner[cell]) - 1].cellCount += 1
			s.realms!.realms[Int(owner[cell]) - 1].area += polygon.count >= 3 ? abs(RealmSeeds.polygonArea(polygon)) : 0
		}
		return s
	}

	@Test func aRealmThatIsNotConnectedIsRefusedEvenWithConsistentRecords() throws {
		let (m, _) = try withRealms()
		let good = m.saved
		let owner = good.realms!.owner
		let n = m.heights.count
		// a cell of realm 1, not its seed, with every neighbour in realm 1, given to realm 2: realm 2 then owns an island of one cell, with records that agree
		let seed1 = good.realms!.realms[0].seedCell
		let inner = try #require((0..<n).first { cell in owner[cell] == 1 && cell != seed1 && m.voronoi.cells.c[cell].allSatisfy { $0 < n && owner[$0] == 1 } })
		var changed = owner
		changed[inner] = 2
		let s = recounted(good, changed, m)
		do { _ = try LandMap(saved: s); Issue.record("a disconnected realm was accepted") } catch let e as RealmLayerError {
			if case .ownershipIsNotValid(let reason) = e { #expect(reason.contains("connected") || reason.contains("realm"), "\(reason)") } else { Issue.record("\(e)") }
		}
		// the same change leaves the records consistent (so connectivity, not the records, is what refuses it)
		#expect(s.realms!.realms[1].cellCount == good.realms!.realms[1].cellCount + 1)
	}

	@Test func theRecipeIsRangeCheckedAndAgreesWithTheRealms() throws {
		let (m, _) = try withRealms()
		let good = m.saved
		func edit(_ change: (inout RealmRecipe) -> Void) -> SavedLandMap { var s = good; change(&s.realms!.recipe); return s }
		let invalid = RealmLayerError.invalidRecipe
		refused(edit { $0.reach = -1 }, invalid)
		refused(edit { $0.reach = .nan }, invalid)
		refused(edit { $0.reach = .infinity }, invalid)
		refused(edit { $0.resolvedCount += 1 }, invalid)
		refused(edit { $0.chosenCount = $0.resolvedCount + 1 }, invalid)
		refused(edit { $0.typicalRealmArea = 0 }, invalid)
		refused(edit { $0.typicalRealmArea = .infinity }, invalid)
		refused(edit { $0.maximumRealms = 0 }, invalid)
		refused(edit { $0.maximumRealms = $0.resolvedCount - 1 }, invalid) // more realms than the cap the recipe says
		_ = try LandMap(saved: edit { $0.maximumRealms = $0.resolvedCount }) // exactly at the cap is fine
		refused(edit { $0.sampleSize = 0 }, invalid)
		refused(edit { $0.hillFactor = 0.5 }, invalid)
		refused(edit { $0.mountainFactor = 5_000 }, invalid)
		refused(edit { $0.crossingFactor = .nan }, invalid)
		refused(edit { $0.unevenness = -1 }, invalid)
		refused(edit { $0.unevenness = 1_000 }, invalid)
		// a different reach groups the land differently: on a map of several islands, realms made at reach 0 do not fit the groups of a reach of 5,000
		var found: (LandMap, RealmLayer)?
		for template in ["archipelago", "shattered", "atoll", "highIsland"] {
			for seed in ["a", "b", "c", "d"] where found == nil {
				let candidate = try map(seed, template: template, cells: 1500)
				guard let groups = try? LandGroups.find(in: candidate, reach: 0), groups.groups.count >= 2, let made = try? layer(candidate, reach: 0), let attached = try? candidate.adding(made) else { continue }
				found = (attached, made)
			}
		}
		let (islands, _) = try #require(found, "a map of several island groups")
		var wide = islands.saved
		wide.realms!.recipe.reach = 5_000
		refused(wide)
	}

	@Test func theColoursMustBeOneForEachRealmAndColours() throws {
		let (m, _) = try withRealms()
		let good = m.saved
		func edit(_ change: (inout [RealmColor]) -> Void) -> SavedLandMap { var s = good; change(&s.realms!.colors!); return s }
		refused(edit { $0.removeLast() }, RealmLayerError.invalidColors)
		refused(edit { $0.append(RealmColor(red: 0, green: 0, blue: 0)) }, RealmLayerError.invalidColors)
		refused(edit { $0[0].red = .nan }, RealmLayerError.invalidColors)
		refused(edit { $0[0].green = 1.5 }, RealmLayerError.invalidColors)
		refused(edit { $0[0].blue = -0.1 }, RealmLayerError.invalidColors)
		refused(edit { $0[0].blue = .infinity }, RealmLayerError.invalidColors)
		var none = good
		none.realms!.colors = nil
		_ = try LandMap(saved: none) // no saved colours is a valid state
	}

	@Test func attachingALayerThatDoesNotFitChangesNothing() throws {
		let m = try map()
		var l = try layer(m)
		let before = m
		l.ownership.owner[l.ownership.owner.firstIndex { $0 > 0 }!] = 0
		#expect(throws: RealmLayerError.ownershipDoesNotMatchMap) { try m.adding(l) }
		#expect(m == before && m.realms == nil)
		// a layer made for another map is refused
		let other = try map("other", template: "highIsland")
		#expect(throws: Error.self) { try other.adding(try layer(m)) }
	}

	@Test func garbageAndCorruptJSONFailToDecode() throws {
		#expect(throws: Error.self) { try LandMap(decoding: Data("{\"formatVersion\":2}".utf8)) }
		let (m, _) = try withRealms()
		var text = String(decoding: try m.encoded(), as: UTF8.self)
		text = text.replacingOccurrences(of: "\"owner\":", with: "\"ownerX\":")
		#expect(throws: Error.self) { try LandMap(decoding: Data(text.utf8)) }
	}

	// MARK: the fixed files

	@Test(.enabled(if: ProcessInfo.processInfo.environment["MAP_WRITE_REALMS_REVISION2"] != nil))
	func writeTheFixture() throws {
		let out = URL(filePath: try #require(ProcessInfo.processInfo.environment["MAP_WRITE_REALMS_REVISION2"]))
		let m = try map("kaz-1", template: "continents", cells: 1500)
		try (try m.adding(try layer(m))).encoded().write(to: out.appending(path: "realms-continents-1500.json"))
	}

	@Test func theFixedVersionTwoFileStillLoadsToTheSameRealms() throws {
		let url = try #require(Bundle.module.url(forResource: "Fixtures/realmsrevision2/realms-continents-1500", withExtension: "json"))
		let data = try Data(contentsOf: url)
		let loaded = try LandMap(decoding: data)
		#expect(try loaded.encoded() == data, "re-saving gives the same bytes")
		#expect(loaded.saved.formatVersion == 2 && loaded.realms != nil)
		// it is the map and the realms the generators make today for the same inputs (a changed algorithm shows here, and the old file is still read as saved)
		let m = try map("kaz-1", template: "continents", cells: 1500)
		let fresh = try m.adding(try layer(m))
		#expect(loaded == fresh, "the saved realms equal the realms made today: a difference means the algorithm changed under the same revision")
		#expect(loaded.realms?.ownership.realms.count == fresh.realms?.ownership.realms.count)
	}
}
