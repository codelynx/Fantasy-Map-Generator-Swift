import Foundation
import Testing
@testable import FantasyMapCore

/// Water chain, stage 7c: the whole `Rivers.generate`, compared EXACTLY with fixtures captured from the original's own `Rivers.generate` on its own
/// packed graph (Fixtures/original/rivers-original.json). The drainage, flow and river definition are closures inside the original's `generate`,
/// so only its END STATE is compared (the flux, river and confluence arrays, the heights, every river record and the lakes' fields).
struct RiverGeneratorTests {
	struct Sha: Decodable { var fl, r, conf, h: String }
	struct LakeFields: Decodable {
		var i: Int
		var height: Double, flux: Double, temp: Double, evaporation: Double
		var inlets: [Int]?
		var outlet: Int?
		var leftover: [String]
	}
	struct RiverRecord: Decodable {
		var i: Int, source: Int, mouth: Int, parent: Int
		var discharge: Double, length: Double, width: Double, widthFactor: Double, sourceWidth: Double
		var cells: [Int]
	}
	struct Whole: Decodable {
		var fl: [Int], r: [Int], conf: [Int], h: [Int]
		var rivers: [RiverRecord]
	}
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, rain: Double, steps: Int, limit: Double, erosion: Bool, cells: Int, nextRandom: Double
		var sha: Sha
		var maxFlux: Int, riverCount: Int
		var riversSha: String, riverCellsSha: String
		var lakes: [LakeFields]
		var whole: Whole?
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("rivers-original")).runs }

	// the capture's hashes: Uint16 as little-endian 16 bits, bytes, Int32 lists, and the river records (4 Int32 and 5 Float64 each)
	func hash(_ data: Data) -> String { Fixtures.hashBytes(data) }
	func u16(_ values: [UInt16]) -> String { Fixtures.hashUInt16s(values) }
	func rivers(_ list: [River]) -> String {
		var data = Data()
		for r in list {
			for v in [r.id, r.source, r.mouth, r.parent] { withUnsafeBytes(of: Int32(v).littleEndian) { data.append(contentsOf: $0) } }
			for v in [r.discharge, r.length, r.width, r.widthFactor, r.sourceWidth] { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
		}
		return hash(data)
	}

	struct Chain {
		var map: LandMap, packed: PackedMap, features: PackedFeatures, precipitation: [UInt8], temperature: [Int8]
	}

	/// The chain of the capture for a run: our map, geography, temperature, precipitation (at the run's rain level), packed graph and features.
	func chain(_ r: Run) throws -> Chain {
		let m = try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
		let g = try Geography.generate(for: m)
		let temp = try Temperature.compute(for: m, geography: g)
		var rain = PrecipitationSettings()
		rain.precipitation = r.rain
		let prec = try Precipitation.compute(for: m, geography: g, temperature: temp, settings: rain)
		let packed = try PackedMap.generate(for: m)
		let features = try PackedFeatures.markup(for: packed, width: m.width, height: m.height)
		return Chain(map: m, packed: packed, features: features, precipitation: prec, temperature: temp)
	}

	func generate(_ c: Chain, _ r: Run) throws -> RiverSystem {
		var settings = RiverSettings()
		settings.allowErosion = r.erosion
		settings.lakeElevationLimit = r.limit
		var policy = RiverResourcePolicy()
		policy.resolveDepressionsSteps = r.steps
		return try Rivers.generate(packed: c.packed, features: c.features, precipitation: c.precipitation, temperature: c.temperature, cellsDesired: r.cellsDesired, width: c.map.width, height: c.map.height, settings: settings, policy: policy)
	}

	@Test func theWholeGeneratorMatchesTheOriginalsEndState() throws {
		let all = try runs()
		var cache: [String: Chain] = [:]
		var wrong: [String] = [], wholeWrong = 0, whole = 0, lakesWrong = 0, rivers = 0, erosionRuns = 0
		var maxByPart: [RiverPart: Double] = [:], maxTotal = 0.0, maxEntries = 0.0, maxPoints = 0, maxBytes = 0
		for r in all {
			let key = "\(r.seed)|\(r.cellsDesired)|\(r.key)|\(r.rain)"
			var c: Chain
			if let hit = cache[key] { c = hit } else { c = try chain(r); cache[key] = c }
			let s = try generate(c, r)
			rivers += s.rivers.count
			let cellCount = Double(c.packed.points.count)
			for (part, charged) in s.report.work.chargedByPart { maxByPart[part] = max(maxByPart[part] ?? 0, Double(charged) / cellCount) }
			maxTotal = max(maxTotal, Double(s.report.work.charged) / cellCount)
			maxEntries = max(maxEntries, Double(s.report.riverEntries) / cellCount)
			maxPoints = max(maxPoints, s.report.geometry.points)
			maxBytes = max(maxBytes, s.report.geometry.peakBytes)
			var fresh = Alea(seed: r.seed)
			#expect(r.nextRandom == fresh.next(), "no river code draws: the stream stands where a fresh one does")
			if r.erosion { erosionRuns += 1 }
			let same = u16(s.flux) == r.sha.fl && u16(s.riverIds) == r.sha.r && u16(s.confluence) == r.sha.conf && Fixtures.hashBytes(Data(s.heights)) == r.sha.h
				&& s.rivers.count == r.riverCount && self.rivers(s.rivers) == r.riversSha && Fixtures.hashInt32s(s.rivers.flatMap { [$0.cells.count] + $0.cells }) == r.riverCellsSha
				&& (s.flux.map(Int.init).max() ?? 0) == r.maxFlux
			if !same { wrong.append("\(r.seed)/\(r.key)/\(r.cellsDesired)/rain \(r.rain)/steps \(r.steps)/erosion \(r.erosion)") }
			let lakeFeatures = s.features.features.filter { $0.kind == .lake }
			let lakesSame = lakeFeatures.count == r.lakes.count && zip(lakeFeatures, r.lakes).allSatisfy { a, b in
				a.id == b.i && a.height == b.height && a.flux == b.flux && a.temp == b.temp && a.evaporation == b.evaporation && a.inlets == b.inlets && a.outlet == b.outlet
					&& a.river == nil && a.enteringFlux == nil && a.outCell == nil && a.closed == nil && b.leftover.isEmpty
			}
			if !lakesSame { lakesWrong += 1 }
			if let w = r.whole {
				whole += 1
				let ok = s.flux.map(Int.init) == w.fl && s.riverIds.map(Int.init) == w.r && s.confluence.map(Int.init) == w.conf && s.heights.map(Int.init) == w.h
					&& s.rivers.count == w.rivers.count && zip(s.rivers, w.rivers).allSatisfy { a, b in
						a.id == b.i && a.source == b.source && a.mouth == b.mouth && a.parent == b.parent && a.discharge == b.discharge && a.length == b.length && a.width == b.width
							&& a.widthFactor == b.widthFactor && a.sourceWidth == b.sourceWidth && a.cells == b.cells
					}
				if !ok { wholeWrong += 1 }
			}
		}
		print("observed on the 336 fixture runs: charges per packed cell, most in one run: total \(maxTotal), by part \(maxByPart.mapValues { $0 }); river entries per cell \(maxEntries); geometry points \(maxPoints); estimated peak bytes \(maxBytes)")
		#expect(all.count == 336 && rivers > 20000 && erosionRuns == 252 && whole == 100)
		#expect(wrong.isEmpty, "\(wrong.count) runs differ from the original: \(wrong.prefix(5))")
		#expect(lakesWrong == 0, "\(lakesWrong) runs leave other lake fields than the original")
		#expect(wholeWrong == 0, "\(wholeWrong) of the \(whole) whole end states differ")
	}

	@Test func theCapturedRunsCoverTheBranchesOfTheOriginal() throws {
		let all = try runs()
		#expect(all.contains { $0.erosion } && all.contains { !$0.erosion })
		#expect(all.flatMap(\.lakes).contains { $0.inlets != nil } && all.flatMap(\.lakes).contains { $0.outlet != nil }, "lakes with inlets and outlets")
		let wholes = all.compactMap(\.whole)
		#expect(wholes.contains { $0.conf.contains { $0 > 0 } }, "confluences")
		#expect(wholes.contains { $0.rivers.contains { $0.parent != 0 } }, "tributaries")
		#expect(wholes.contains { $0.rivers.contains { $0.cells.contains(-1) } }, "rivers leaving by the border")
		#expect(all.contains { $0.steps == 40 } && all.contains { $0.limit == 5 } && all.contains { $0.rain == 300 })
	}

	// MARK: refusals, budgets and the structure

	func small() throws -> (Run, Chain) {
		let run = try #require(try runs().first { $0.whole != nil && $0.erosion && $0.rain == 100 && $0.steps == 250 && $0.riverCount >= 5 && $0.lakes.count >= 2 })
		return (run, try chain(run))
	}

	func generate(_ c: Chain, features: PackedFeatures? = nil, packed: PackedMap? = nil, precipitation: [UInt8]? = nil, temperature: [Int8]? = nil, cellsDesired: Int = 600, settings: RiverSettings = RiverSettings(), policy: RiverResourcePolicy = RiverResourcePolicy(), riverIdLimit: Int = 65535, entryLimit: Int? = nil) throws -> RiverSystem {
		try Rivers.generate(packed: packed ?? c.packed, features: features ?? c.features, precipitation: precipitation ?? c.precipitation, temperature: temperature ?? c.temperature, cellsDesired: cellsDesired, width: c.map.width, height: c.map.height, settings: settings, policy: policy, riverIdLimit: riverIdLimit, entryLimit: entryLimit)
	}

	@Test func generationIsDeterministicAndLeavesItsInputsAlone() throws {
		let (run, c) = try small()
		let before = (c.features, c.packed.heights)
		let a = try generate(c, cellsDesired: run.cellsDesired), b = try generate(c, cellsDesired: run.cellsDesired)
		#expect(a == b)
		#expect(c.features == before.0 && c.packed.heights == before.1, "the inputs are values and are not changed")
		#expect(a.report.work.charged > 0 && a.report.work.chargedByPart.keys.contains(.drainWater) && a.report.work.chargedByPart.keys.contains(.resolveDepressions) && a.report.work.chargedByPart.keys.contains(.detectCloseLakes))
		#expect(a.report.riverEntries > a.rivers.reduce(0) { $0 + $1.cells.count } || a.report.riverEntries == a.rivers.reduce(0) { $0 + $1.cells.count }, "the entries include the short rivers that were dropped")
	}

	@Test func theRiverNumberLimitIsCheckedBeforeANumberThatWouldWrapIsAssigned() throws {
		let (run, c) = try small()
		// the smallest limit that passes: the highest river number the run assigns (the short rivers take numbers too and are dropped)
		var low = 1, high = 65535
		while low < high {
			let mid = (low + high) / 2
			if (try? generate(c, cellsDesired: run.cellsDesired, riverIdLimit: mid)) != nil { high = mid } else { low = mid + 1 }
		}
		let assigned = try generate(c, cellsDesired: run.cellsDesired).report.riverNumbersAssigned
		#expect(low == assigned && assigned > 3, "the smallest limit that passes is the number of river numbers handed out (\(assigned))")
		_ = try generate(c, cellsDesired: run.cellsDesired, riverIdLimit: low)
		#expect(throws: RiverError.tooManyRivers) { try generate(c, cellsDesired: run.cellsDesired, riverIdLimit: low - 1) }
	}

	@Test func theSixteenBitAndEightBitStoresTruncateAndWrapLikeTypedArrays() {
		#expect(Rivers.addToUInt16(5, 1.9) == 6, "5 + 1.9 = 6.9 is stored as 6")
		#expect(Rivers.addToUInt16(5, 0.9) == 5, "a fraction under one is lost")
		#expect(Rivers.addToUInt16(65530, 10) == 4, "65,540 wraps to 4, it does not stop at 65,535")
		#expect(Rivers.addToUInt16(65535, 1) == 0)
		#expect(Rivers.addToUInt8(250, 10) == 4, "260 wraps to 4")
		#expect(Rivers.addToUInt8(255, 1) == 0 && Rivers.addToUInt8(100, 0.99) == 100)
	}

	@Test func anUnrepresentableEntryCapIsRefusedNotReplaced() throws {
		let (run, c) = try small()
		var policy = RiverResourcePolicy()
		policy.maximumRiverEntriesPerCell = Int.max
		#expect(throws: RiverError.invalidSettings) { try generate(c, cellsDesired: run.cellsDesired, policy: policy) }
	}

	@Test func aLakeKeepsEveryInletInTheOrderTheRiversReachedIt() throws {
		let (run, c) = try small()
		let lakes = try generate(c, cellsDesired: run.cellsDesired).features.features.filter { $0.kind == .lake }
		let expected = run.lakes
		#expect(lakes.map { $0.inlets ?? [] } == expected.map { $0.inlets ?? [] })
		#expect(lakes.contains { ($0.inlets ?? []).count > 1 })
	}

	@Test func theEntryLimitIsExactlyMetAndNotPassed() throws {
		let (run, c) = try small()
		let entries = try generate(c, cellsDesired: run.cellsDesired).report.riverEntries
		_ = try generate(c, cellsDesired: run.cellsDesired, entryLimit: entries)
		#expect(throws: RiverError.riverEntriesBudgetExceeded) { try generate(c, cellsDesired: run.cellsDesired, entryLimit: entries - 1) }
	}

	@Test func theWorkAndEntryBudgetsRefuseBeforeTheyAreExceeded() throws {
		let (run, c) = try small()
		var tightWork = RiverResourcePolicy()
		tightWork.workPerCell = 1
		#expect(throws: RiverError.self) { try generate(c, cellsDesired: run.cellsDesired, policy: tightWork) }
		// the entries: exactly the entries made pass, one fewer is refused (the limit is a multiple of the cells: search for the smallest that passes)
		let entries = try generate(c, cellsDesired: run.cellsDesired).report.riverEntries
		var policy = RiverResourcePolicy()
		policy.maximumRiverEntriesPerCell = 0
		#expect(throws: RiverError.riverEntriesBudgetExceeded) { try generate(c, cellsDesired: run.cellsDesired, policy: policy) }
		let perCell = (entries + c.packed.points.count - 1) / c.packed.points.count
		policy.maximumRiverEntriesPerCell = perCell
		_ = try generate(c, cellsDesired: run.cellsDesired, policy: policy)
		policy.maximumRiverEntriesPerCell = max(0, entries / c.packed.points.count - 1)
		if entries / c.packed.points.count >= 1 { #expect(throws: RiverError.riverEntriesBudgetExceeded) { try generate(c, cellsDesired: run.cellsDesired, policy: policy) } }
		// the geometry budget: a river's points limit that is too small for the smallest river
		var geometry = RiverResourcePolicy()
		geometry.maximumRiverPoints = 2
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try generate(c, cellsDesired: run.cellsDesired, policy: geometry) }
		var bytes = RiverResourcePolicy()
		bytes.maximumGeometryBytes = 100
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try generate(c, cellsDesired: run.cellsDesired, policy: bytes) }
	}

	@Test func settingsAndInputsAreValidated() throws {
		let (run, c) = try small()
		for limit in [-1.0, 101, .nan] { var s = RiverSettings(); s.lakeElevationLimit = limit; #expect(throws: RiverError.invalidSettings) { try generate(c, cellsDesired: run.cellsDesired, settings: s) } }
		for exponent in [0.0, 5.5, .nan] { var s = RiverSettings(); s.heightExponent = exponent; #expect(throws: RiverError.invalidSettings) { try generate(c, cellsDesired: run.cellsDesired, settings: s) } }
		var steps = RiverResourcePolicy()
		steps.resolveDepressionsSteps = 0
		#expect(throws: RiverError.invalidSettings) { try generate(c, cellsDesired: run.cellsDesired, policy: steps) }
		#expect(throws: RiverError.invalidInputs) { try generate(c, cellsDesired: 0) }
		#expect(throws: RiverError.invalidInputs) { try Rivers.generate(packed: c.packed, features: c.features, precipitation: c.precipitation, temperature: c.temperature, cellsDesired: 600, width: 0, height: 400) }
		#expect(throws: RiverError.invalidInputs) { try generate(c, precipitation: Array(c.precipitation.dropLast()), cellsDesired: run.cellsDesired) }
		var shortFeatures = c.features
		shortFeatures.featureIds.removeLast()
		#expect(throws: RiverError.invalidInputs) { try generate(c, features: shortFeatures, cellsDesired: run.cellsDesired) }
		var badId = c.features
		badId.featureIds[0] = 60000
		#expect(throws: RiverError.invalidInputs) { try generate(c, features: badId, cellsDesired: run.cellsDesired) }
	}

	@Test func theStructuralValidationRefusesAnInconsistentFeatureTable() throws {
		let (run, c) = try small()
		// a water cell given to a land feature
		let water = try #require(c.packed.heights.firstIndex { $0 < Heights.seaLevel })
		let land = try #require(c.features.features.first { $0.land })
		var wrongKind = c.features
		wrongKind.featureIds[water] = UInt16(land.id)
		#expect(throws: RiverError.invalidInputs) { try generate(c, features: wrongKind, cellsDesired: run.cellsDesired) }
		// a haven that is a land cell
		let landCell = try #require(c.packed.heights.lastIndex { $0 >= Heights.seaLevel }) // not cell 0: a haven of 0 means none
		var badHaven = c.features
		badHaven.haven[landCell] = landCell
		#expect(throws: RiverError.invalidInputs) { try generate(c, features: badHaven, cellsDesired: run.cellsDesired) }
		// a haven that is negative, or a water cell that is not a neighbour of its cell (0 stays "none")
		var negativeHaven = c.features
		negativeHaven.haven[landCell] = -1
		#expect(throws: RiverError.invalidInputs) { try generate(c, features: negativeHaven, cellsDesired: run.cellsDesired) }
		let neighbours = c.packed.voronoi.cells.c
		let farWater = try #require(c.packed.heights.indices.first { c.packed.heights[$0] < Heights.seaLevel && !neighbours[landCell].contains($0) && $0 != landCell })
		var farHaven = c.features
		farHaven.haven[landCell] = farWater
		#expect(throws: RiverError.invalidInputs) { try generate(c, features: farHaven, cellsDesired: run.cellsDesired) }
		var noHaven = c.features
		noHaven.haven[landCell] = 0
		_ = try generate(c, features: noHaven, cellsDesired: run.cellsDesired)
		// a lake whose first cell is not its own, or without a shore
		let lakeIndex = try #require(c.features.features.firstIndex { $0.kind == .lake })
		var wrongFirst = c.features
		wrongFirst.features[lakeIndex].firstCell = landCell
		#expect(throws: RiverError.lakeWithoutShore) { try generate(c, features: wrongFirst, cellsDesired: run.cellsDesired) }
		var noShore = c.features
		noShore.features[lakeIndex].shoreline = []
		#expect(throws: RiverError.lakeWithoutShore) { try generate(c, features: noShore, cellsDesired: run.cellsDesired) }
		var waterShore = c.features
		waterShore.features[lakeIndex].shoreline = [water]
		#expect(throws: RiverError.lakeWithoutShore) { try generate(c, features: waterShore, cellsDesired: run.cellsDesired) }
		// a cell without neighbours, or with more than 20
		var voronoi = c.packed.voronoi
		voronoi.cells.c[5] = []
		let isolated = PackedMap(points: c.packed.points, gridCell: c.packed.gridCell, heights: c.packed.heights, areas: c.packed.areas, voronoi: voronoi)
		#expect(throws: RiverError.invalidInputs) { try generate(c, packed: isolated, cellsDesired: run.cellsDesired) }
		voronoi.cells.c[5] = Array(0..<21)
		let crowded = PackedMap(points: c.packed.points, gridCell: c.packed.gridCell, heights: c.packed.heights, areas: c.packed.areas, voronoi: voronoi)
		#expect(throws: RiverError.invalidInputs) { try generate(c, packed: crowded, cellsDesired: run.cellsDesired) }
		// a packed cell whose grid cell is outside the grid arrays
		var badGrid = c.packed.gridCell
		badGrid[0] = c.precipitation.count
		let outside = PackedMap(points: c.packed.points, gridCell: badGrid, heights: c.packed.heights, areas: c.packed.areas, voronoi: c.packed.voronoi)
		#expect(throws: RiverError.invalidInputs) { try generate(c, packed: outside, cellsDesired: run.cellsDesired) }
	}

	@Test func aNonFiniteLakeClimateIsRefusedBeforeTheDrainageNamingTheLakeAndTheField() throws {
		let (run, c) = try small()
		// which lakes does detectCloseLakes close, in this map (the working heights as the generator makes them)?
		var f = c.features
		var h = try RiverHeights.alterHeights(packedHeights: c.packed.heights, distance: f.distanceField, neighbours: c.packed.voronoi.cells.c)
		try f.detectCloseLakes(heights: h, neighbours: c.packed.voronoi.cells.c, elevationLimit: 20)
		var work = try RiverWork(cells: c.packed.points.count, policy: RiverResourcePolicy())
		try RiverHeights.resolveDepressions(heights: &h, features: &f, packedHeights: c.packed.heights, neighbours: c.packed.voronoi.cells.c, border: c.packed.voronoi.cells.b, steps: 250, work: &work)
		let lakes = f.features.filter { $0.kind == .lake }
		// poison each lake in turn: every shore cell and the first cell at 80 degrees, so the mean or the first cell's temperature is 80 and the
		// evaporation's denominator is 0; the refusal names that lake and the field (the closed lakes too)
		var refused = 0, closedRefused = 0
		for lake in lakes {
			var temperature = c.temperature
			for cell in lake.shoreline + [lake.firstCell] { temperature[c.packed.gridCell[cell]] = 80 }
			do { _ = try generate(c, temperature: temperature, cellsDesired: run.cellsDesired) } catch RiverError.nonFiniteLakeClimate(let id, let field) {
				if id == lake.id && field == .evaporation { refused += 1; if lake.closed == true { closedRefused += 1 } }
			}
		}
		#expect(refused == lakes.count, "every poisoned lake is named (\(refused) of \(lakes.count))")
		#expect(closedRefused > 0, "closed lakes are checked too (\(closedRefused))")
	}
}
