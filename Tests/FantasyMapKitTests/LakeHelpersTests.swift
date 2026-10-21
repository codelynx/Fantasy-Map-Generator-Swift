import Foundation
import Testing
@testable import FantasyMapKit

/// Water chain, stage 6: the lake helpers (`detectCloseLakes`, `defineClimateData`, `cleanupLakeData`), compared EXACTLY with fixtures
/// captured from the original's own `Lakes` on its own packed graph (Fixtures/original/lake-helpers-original.json).
struct LakeHelpersTests {
	struct Box: Decodable { var latT: Double, latN: Double, latS: Double }
	struct LakeClimate: Decodable {
		var i: Int, flux: Double, temp: Double, evaporation: Double
		var outCell: Int?
		var closed: Bool?
	}
	struct Climate: Decodable { var exponent: Double, lakes: [LakeClimate], outCellsSha: String, outCellsCount: Int }
	struct Variant: Decodable { var heights: String, limit: Double, closed: [Bool?], climate: [Climate]? }
	struct Before: Decodable {
		var inlets: [Int]?
		var outlet: Int?
		var height: Double
	}
	struct After: Decodable {
		var inlets: [Int]?
		var outlet: Int?
		var height: Double
		var has: [Bool]
	}
	struct Cleanup: Decodable { var rivers: [Int], before: [Before], after: [After] }
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, coordinates: Box, lakes: Int
		var variants: [Variant], cleanup: Cleanup?
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("lake-helpers-original")).runs }

	@Test func theHelpersMatchTheOriginalThroughTheWholeChain() throws {
		let all = try runs()
		var wrongClosed = 0, wrongClimate = 0, wrongCleanup = 0, lakes = 0, openCount = 0, closedCount = 0
		for r in all where r.lakes > 0 {
			let m = try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
			let g = try Geography.generate(for: m)
			let temp = try Temperature.compute(for: m, geography: g)
			let prec = try Precipitation.compute(for: m, geography: g, temperature: temp)
			let packed = try PackedMap.generate(for: m)
			var f = try PackedFeatures.markup(for: packed, width: m.width, height: m.height)
			let lakeIndices = f.features.indices.filter { f.features[$0].kind == .lake }
			#expect(lakeIndices.count == r.lakes)
			lakes += lakeIndices.count
			let base = packed.heights.map(Double.init)
			let raised = base.map { $0 >= 20 ? min(100, $0 + 15) : $0 }
			// the river generator's fractional working copies, made as the capture makes them
			let fracA = base.enumerated().map { i, v in v + Double(i % 7) * 0.15 }
			let fracB = base.enumerated().map { i, v in v >= 21 ? max(20.05, v - Double(i % 5) * 0.2) : v }
			for v in r.variants {
				let h = ["same": base, "raised": raised, "fracA": fracA, "fracB": fracB][v.heights]!
				try f.detectCloseLakes(heights: h, neighbours: packed.voronoi.cells.c, elevationLimit: v.limit)
				let closed = lakeIndices.map { f.features[$0].closed }
				if closed != v.closed { wrongClosed += 1 }
				openCount += closed.filter { $0 == false }.count
				closedCount += closed.filter { $0 == true }.count
				for c in v.climate ?? [] {
					let out = try f.defineClimateData(heights: h, gridCell: packed.gridCell, precipitation: prec, temperature: temp, heightExponent: c.exponent)
					let mine = lakeIndices.map { f.features[$0] }
					let same = zip(mine, c.lakes).allSatisfy { a, b in a.id == b.i && a.flux == b.flux && a.temp == b.temp && a.evaporation == b.evaporation && a.outCell == b.outCell && a.closed == b.closed }
					if !(same && Fixtures.hashUInt16s(out) == c.outCellsSha && out.filter { $0 != 0 }.count == c.outCellsCount) { wrongClimate += 1 }
				}
			}
			// cleanup on the same synthetic fields as the capture
			for (n, index) in lakeIndices.enumerated() {
				f.features[index].river = 7; f.features[index].enteringFlux = 9; f.features[index].outCell = 5; f.features[index].closed = n % 2 == 0
				f.features[index].inlets = Array([1, 2, 3, 0].prefix(n % 5))
				f.features[index].outlet = [0, 1, 2, 3, 5][n % 5]
				f.features[index].height += 0.12345
			}
			let cleanup = try #require(r.cleanup)
			#expect(zip(lakeIndices, cleanup.before).allSatisfy { f.features[$0].height == $1.height && f.features[$0].inlets ?? [] == $1.inlets ?? [] && f.features[$0].outlet == $1.outlet })
			f.cleanupLakeData(riverIds: Set(cleanup.rivers))
			for (index, after) in zip(lakeIndices, cleanup.after) {
				let x = f.features[index]
				let has = [x.river != nil, x.enteringFlux != nil, x.outCell != nil, x.closed != nil]
				if x.inlets != after.inlets || x.outlet != after.outlet || x.height != after.height || has != after.has { wrongCleanup += 1 }
			}
		}
		#expect(lakes == 237)
		#expect(openCount > 100 && closedCount > 100, "both outcomes of the deep-depression search are exercised")
		#expect(wrongClosed == 0, "\(wrongClosed) passes decide the closed lakes differently from the original")
		#expect(wrongClimate == 0, "\(wrongClimate) climate passes differ from the original")
		#expect(wrongCleanup == 0, "\(wrongCleanup) cleaned lakes differ from the original")
	}

	// MARK: hand-computed cases on a path of cells

	func lake(id: Int, height: Double, shoreline: [Int], cells: Int = 1, firstCell: Int = 0) -> PackedFeature {
		PackedFeature(id: id, kind: .lake, land: false, border: false, cells: cells, firstCell: firstCell, vertices: [], area: 0, shoreline: shoreline, height: height)
	}
	func ocean(id: Int) -> PackedFeature { PackedFeature(id: id, kind: .ocean, land: false, border: true, cells: 1, firstCell: 0, vertices: [], area: 0, shoreline: [], height: 0) }
	func line(_ n: Int) -> [[Int]] { (0..<n).map { i in [i - 1, i + 1].filter { $0 >= 0 && $0 < n } } }

	/// Feature numbers: 1 for cell 0's ocean; 2 for the lake at cell `lakeCell`; 3 for a second lake at `otherCell` if any (else an island); the rest land (4).
	func features(_ n: Int, lakeCell: Int, lake: PackedFeature, other: (Int, PackedFeature)? = nil) -> PackedFeatures {
		var ids = [UInt16](repeating: 4, count: n)
		ids[0] = 1; ids[lakeCell] = 2
		var list = [ocean(id: 1), lake, PackedFeature(id: 3, kind: .island, land: true, border: false, cells: 1, firstCell: 0, vertices: [], area: 0, shoreline: [], height: 0),
			PackedFeature(id: 4, kind: .island, land: true, border: false, cells: 1, firstCell: 0, vertices: [], area: 0, shoreline: [], height: 0)]
		if let (cell, feature) = other { ids[cell] = 3; list[2] = feature }
		return PackedFeatures(distanceField: [Int8](repeating: 0, count: n), featureIds: ids, haven: [Int](repeating: 0, count: n), harbor: [UInt8](repeating: 0, count: n), features: list)
	}

	@Test func aLakeBehindAWallIsClosedAndOneNextToTheOceanIsOpen() throws {
		// cells: 0 ocean (10), 1 land (90), 2 land (25), 3 lake (15), 4 land (25), 5 land (90): from the lowest shore cell 2 the flood meets only
		// the lake itself and land under 24.9 + 20: closed
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]))
		try f.detectCloseLakes(heights: [10, 90, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == true)
		// lower the wall at cell 1 to 40 (under 44.9) and the flood reaches the ocean: open
		try f.detectCloseLakes(heights: [10, 40, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == false)
		// at limit 10 the same wall is over 34.9 and holds again
		try f.detectCloseLakes(heights: [10, 40, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 10)
		#expect(f.features[1].closed == true)
		// exactly at the limit (a wall of 44.9 is not under it, a wall of 44 is): the wall of 45 holds, 44 lets the flood through
		try f.detectCloseLakes(heights: [10, 45, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == true)
		try f.detectCloseLakes(heights: [10, 44, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == false)
	}

	@Test func aCellExactlyAtTheLimitHeightIsNotCrossed() throws {
		// lake height 24.5 and limit 0.5 give exactly 25: a wall of 25 is not under it, a wall of 24 is
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.5, shoreline: [2, 4]))
		try f.detectCloseLakes(heights: [10, 25, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 0.5)
		#expect(f.features[1].closed == true)
		try f.detectCloseLakes(heights: [10, 24, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 0.5)
		#expect(f.features[1].closed == false)
	}

	@Test func fractionalWorkingHeightsAreKeptExactly() throws {
		// the flood threshold: lake height 24.5 and limit 0.5 give 25: a wall of 24.99 is under it (open) and 25 is not (closed); a byte copy
		// of 24.99 would be 24 and say the same as 24, which is why the heights are not truncated
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.5, shoreline: [2, 4]))
		try f.detectCloseLakes(heights: [10, 24.99, 25.2, 15, 25.2, 90], neighbours: line(6), elevationLimit: 0.5)
		#expect(f.features[1].closed == false)
		try f.detectCloseLakes(heights: [10, 25, 25.2, 15, 25.2, 90], neighbours: line(6), elevationLimit: 0.5)
		#expect(f.features[1].closed == true)
		// the water test: a cell of 19.95 is water (a lake or the ocean next to it), 20 is land: here cell 1 as the ocean opens the lake only under 20
		try f.detectCloseLakes(heights: [10, 19.95, 25.2, 15, 25.2, 90], neighbours: line(6), elevationLimit: 0.5)
		#expect(f.features[1].closed == false, "feature 4 is land in the lists, so 19.95 here is only under the threshold, and the flood passes through")
		// the lowest shore cell: 25.3 against 25.2 (both 25 as bytes, which would pick the first): the lower one, cell 4
		var g = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]))
		_ = try g.defineClimateData(heights: [10, 90, 25.3, 15, 25.2, 90], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2)
		#expect(g.features[1].outCell == 4)
		var tie = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]))
		_ = try tie.defineClimateData(heights: [10, 90, 25.2, 15, 25.2, 90], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2)
		#expect(tie.features[1].outCell == 2, "equal fractional heights: the first")
		// the byte form converts exactly
		var b = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]))
		try b.detectCloseLakes(byteHeights: [10, 90, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20)
		#expect(b.features[1].closed == true)
	}

	@Test func malformedIndicesAndHeightsAreRefusedBeforeAnythingChanges() throws {
		let h: [Double] = [10, 90, 25, 15, 25, 90], zeros = [UInt8](repeating: 0, count: 6), temps = [Int8](repeating: 0, count: 6)
		let good = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]))
		// a shore cell outside the cells, in either direction
		for shoreline in [[2, 6], [-1, 4]] {
			var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: shoreline))
			let before = f
			#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.detectCloseLakes(heights: h, neighbours: line(6), elevationLimit: 20) }
			#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { _ = try f.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: zeros, temperature: temps, heightExponent: 2) }
			#expect(f == before)
		}
		// a neighbour outside the cells
		var f = good
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.detectCloseLakes(heights: h, neighbours: [[1], [0, 2], [1, 3], [2, 4], [3, 9], [4]], elevationLimit: 20) }
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.detectCloseLakes(heights: h, neighbours: [[1], [0, 2], [1, 3], [2, -4], [3, 5], [4]], elevationLimit: 20) }
		// a first cell outside the cells matters only where it is used: a lake of fewer than 6 cells
		var small = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4], cells: 5, firstCell: 6))
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { _ = try small.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: zeros, temperature: temps, heightExponent: 2) }
		var big = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4], cells: 6, firstCell: 99))
		_ = try big.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: zeros, temperature: temps, heightExponent: 2)
		#expect(big.features[1].outCell == 2, "its first cell is not used")
		// a water cell whose feature number is not in the table (the original would fail on the missing feature); 0 is the placeholder and is fine
		var badId = good
		badId.featureIds[0] = 9
		let beforeBadId = badId
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try badId.detectCloseLakes(heights: h, neighbours: line(6), elevationLimit: 20) }
		#expect(badId == beforeBadId)
		var landBad = good
		landBad.featureIds[1] = 9 // a land cell's number is never read by the search
		try landBad.detectCloseLakes(heights: h, neighbours: line(6), elevationLimit: 20)
		try landBad.detectCloseLakes(heights: [10, 20, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20) // exactly sea level is land
		var placeholder = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4], cells: 1))
		placeholder.featureIds[0] = 0
		try placeholder.detectCloseLakes(heights: [10, 40, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20)
		#expect(placeholder.features[1].closed == true, "feature 0 is the placeholder: it is not an ocean and not lower, so the flood does not open the lake")
		// heights that are not finite
		for bad in [Double.nan, .infinity, -.infinity] {
			var heights = h
			heights[0] = bad
			var g = good
			let before = g
			#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try g.detectCloseLakes(heights: heights, neighbours: line(6), elevationLimit: 20) }
			#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { _ = try g.defineClimateData(heights: heights, gridCell: Array(0..<6), precipitation: zeros, temperature: temps, heightExponent: 2) }
			#expect(g == before)
		}
		// a refused call changes nothing even when it is refused after earlier lakes: the second lake has no shore where the search needs one
		var two = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]), other: (5, lake(id: 3, height: 24.9, shoreline: [])))
		let before = two
		#expect(throws: PackedFeatures.LakeProblem.lakeWithoutShore) { try two.detectCloseLakes(heights: h, neighbours: line(6), elevationLimit: 20) }
		#expect(two == before, "the first lake's decision was not kept")
		// a closed lake without a shore is fine in the climate step (the original's documented behaviour), an open one is not
		var closed = features(6, lakeCell: 3, lake: { var l = lake(id: 2, height: 24.9, shoreline: []); l.closed = true; return l }())
		_ = try closed.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: zeros, temperature: temps, heightExponent: 2)
		#expect(closed.features[1].outCell == nil)
		var open = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: []))
		#expect(throws: PackedFeatures.LakeProblem.lakeWithoutShore) { _ = try open.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: zeros, temperature: temps, heightExponent: 2) }
	}

	@Test func nonFiniteClimateResultsArePreservedByTheParityLayer() throws {
		// a temperature of exactly 80 makes the evaporation's denominator 0: the original's result is infinity (and rn keeps it); not clamped here.
		// The integrated generator (stage 7) is to refuse a non-finite lake climate; this layer keeps the original's numbers
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 30, shoreline: [2, 4], cells: 2, firstCell: 2))
		_ = try f.defineClimateData(heights: [10, 90, 25, 15, 25, 90], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [0, 0, 80, 0, 0, 0], heightExponent: 2)
		#expect(f.features[1].temp == 80 && f.features[1].evaporation == .infinity)
		// a lake of 6 cells or more with no shore has no mean temperature, so its temperature and evaporation are not numbers (closed: no outlet needed)
		var empty = features(6, lakeCell: 3, lake: { var l = lake(id: 2, height: 30, shoreline: [], cells: 6); l.closed = true; return l }())
		_ = try empty.defineClimateData(heights: [10, 90, 25, 15, 25, 90], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2)
		#expect(empty.features[1].temp.isNaN && empty.features[1].evaporation.isNaN)
	}

	@Test func aLakeNextToALowerLakeIsOpenAndNextToAHigherOrEqualOneIsNot() throws {
		// cell 5 is a second lake at the end of the path; the flood from cell 4 reaches it
		let walls: [Double] = [10, 90, 25, 15, 25, 15]
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]), other: (5, lake(id: 3, height: 20.9, shoreline: [4])))
		try f.detectCloseLakes(heights: walls, neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == false, "the other lake is lower (20.9 under 24.9): the water can go there")
		f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]), other: (5, lake(id: 3, height: 24.9, shoreline: [4])))
		try f.detectCloseLakes(heights: walls, neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == true, "an equal lake is not lower")
		f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [2, 4]), other: (5, lake(id: 3, height: 30, shoreline: [4])))
		try f.detectCloseLakes(heights: walls, neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == true, "a higher lake is not lower")
	}

	@Test func aLakeHighEnoughIsOpenWithoutASearchAndTheLimitsAreChecked() throws {
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 80, shoreline: [2, 4]))
		try f.detectCloseLakes(heights: [10, 100, 25, 15, 25, 100], neighbours: line(6), elevationLimit: 20)
		#expect(f.features[1].closed == false, "80 + 20 passes 99")
		try f.detectCloseLakes(heights: [10, 100, 25, 15, 25, 100], neighbours: line(6), elevationLimit: 19)
		#expect(f.features[1].closed == true, "80 + 19 is 99, not over it, so it is searched, and walls of 100 are not under 99")
		try f.detectCloseLakes(heights: [10, 98, 25, 15, 25, 100], neighbours: line(6), elevationLimit: 19)
		#expect(f.features[1].closed == false, "a wall of 98 is under 99")
		for limit in [-1.0, 101, .nan, .infinity] { #expect(throws: PackedFeatures.LakeProblem.invalidSettings) { try f.detectCloseLakes(heights: [10, 90, 25, 15, 25, 90], neighbours: line(6), elevationLimit: limit) } }
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.detectCloseLakes(heights: [10, 90], neighbours: line(6), elevationLimit: 20) }
		var noShore = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: []))
		#expect(throws: PackedFeatures.LakeProblem.lakeWithoutShore) { try noShore.detectCloseLakes(heights: [10, 90, 25, 15, 25, 90], neighbours: line(6), elevationLimit: 20) }
	}

	@Test func theLowestShoreCellIsTheFirstOfEquals() throws {
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 24.9, shoreline: [4, 2, 5]), other: nil)
		let out = try f.defineClimateData(heights: [10, 90, 25, 15, 25, 25], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 1, count: 6), temperature: [Int8](repeating: 20, count: 6), heightExponent: 2)
		#expect(f.features[1].outCell == 4 && out[4] == 2, "cells 4, 2 and 5 are all 25: the first listed, 4")
		#expect(out.filter { $0 != 0 }.count == 1)
	}

	@Test func theClimateOfALakeFromItsShore() throws {
		// a 10-cell lake of height 30 with shore cells 1 and 3; grid cells are the packed cells; rain 5 and 7, temperatures 20 and 21
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 30, shoreline: [1, 3], cells: 10, firstCell: 2))
		_ = try f.defineClimateData(heights: [10, 40, 25, 15, 25, 25], gridCell: Array(0..<6), precipitation: [0, 5, 0, 7, 0, 0], temperature: [0, 20, 0, 21, 0, 0], heightExponent: 2)
		let l = f.features[1]
		#expect(l.flux == 12, "5 + 7")
		#expect(l.temp == 20.5, "10 cells (6 or more): the mean of 20 and 21, to one decimal")
		// the formula by hand: (30 - 18)^2 = 144 m; (700 x (20.5 + 0.006 x 144)) / 50 + 75 = 372.896 + ... computed in plain arithmetic below
		let metres = 144.0
		let expected = ((700 * (20.5 + 0.006 * metres)) / 50 + 75) / (80 - 20.5) * 10
		#expect(l.evaporation == expected.rounded(), "\(expected)")
		#expect(l.evaporation == 63, "6.287 a cell, 62.87 for ten cells, rounded")
		// a lake of fewer than 6 cells takes the temperature under its first cell, whatever the shore
		var small = features(6, lakeCell: 3, lake: lake(id: 2, height: 30, shoreline: [1, 3], cells: 5, firstCell: 2))
		_ = try small.defineClimateData(heights: [10, 40, 25, 15, 25, 25], gridCell: Array(0..<6), precipitation: [0, 5, 0, 7, 0, 0], temperature: [0, 20, -3, 21, 0, 0], heightExponent: 2)
		#expect(small.features[1].temp == -3)
		// a closed lake gets no outlet
		var closed = features(6, lakeCell: 3, lake: { var l = lake(id: 2, height: 30, shoreline: [1, 3]); l.closed = true; return l }())
		let out = try closed.defineClimateData(heights: [10, 40, 25, 15, 25, 25], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2)
		#expect(closed.features[1].outCell == nil && out.allSatisfy { $0 == 0 })
		// the heights asked for are the caller's, not the map's: the outlet follows them
		var alt = features(6, lakeCell: 3, lake: lake(id: 2, height: 30, shoreline: [2, 4]))
		_ = try alt.defineClimateData(heights: [10, 40, 25, 15, 25, 25], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2)
		#expect(alt.features[1].outCell == 2)
		_ = try alt.defineClimateData(heights: [10, 40, 99, 15, 25, 25], gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2)
		#expect(alt.features[1].outCell == 4)
	}

	@Test func climateInputsAreValidated() throws {
		var f = features(6, lakeCell: 3, lake: lake(id: 2, height: 30, shoreline: [1, 3]))
		let h: [Double] = [10, 40, 25, 15, 25, 25]
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: [0, 0], temperature: [0, 0], heightExponent: 2) }
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: [0, 0, 0, 0, 0, 0], temperature: [0, 0, 0], heightExponent: 2) }
		#expect(throws: PackedFeatures.LakeProblem.invalidInputs) { try f.defineClimateData(heights: Array(h.dropLast()), gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: 2) }
		for e in [0.0, 5.1, .nan] { #expect(throws: PackedFeatures.LakeProblem.invalidSettings) { try f.defineClimateData(heights: h, gridCell: Array(0..<6), precipitation: [UInt8](repeating: 0, count: 6), temperature: [Int8](repeating: 0, count: 6), heightExponent: e) } }
	}

	@Test func cleanupKeepsOnlyRiversThatExist() {
		var l = lake(id: 2, height: 22.0234567, shoreline: [1])
		l.river = 3; l.enteringFlux = 4; l.outCell = 5; l.closed = true; l.inlets = [4, 1, 9, 3]; l.outlet = 3
		var f = PackedFeatures(distanceField: [], featureIds: [], haven: [], harbor: [], features: [ocean(id: 1), l])
		f.features[0].height = 5.55555
		f.cleanupLakeData(riverIds: [1, 3])
		#expect(f.features[1].inlets == [1, 3] && f.features[1].outlet == 3 && f.features[1].height == 22.023)
		#expect(f.features[1].river == nil && f.features[1].enteringFlux == nil && f.features[1].outCell == nil && f.features[1].closed == nil)
		#expect(f.features[0].height == 5.55555, "only lakes are cleaned")
		f.cleanupLakeData(riverIds: [])
		#expect(f.features[1].inlets == nil && f.features[1].outlet == nil)
		var zero = f
		zero.features[1].outlet = 0
		zero.cleanupLakeData(riverIds: [0])
		#expect(zero.features[1].outlet == nil, "an outlet number of 0 is dropped even if a river 0 exists")
	}
}
