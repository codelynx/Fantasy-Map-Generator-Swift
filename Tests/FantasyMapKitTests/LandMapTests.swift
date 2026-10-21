import CryptoKit
import Foundation
import Testing
@testable import FantasyMapKit

/// Step 8 of docs/plans/land-layer.md: `LandMap` generates as the original's pipeline does, and saves and loads the exact state.
struct LandMapTests {
	// the lake fixture holds the original's state after every stage for 420 maps
	typealias Fixture = LandLakesTests.Fixture

	func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("lakes-original")) }

	func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

	func digests(_ map: LandMap) -> (heights: String, distance: String, ids: String) {
		var ids = Data()
		for id in map.features.featureIds { ids.append(UInt8(id & 0xff)); ids.append(UInt8(id >> 8)) }
		return (sha(Data(map.heights)), sha(Data(map.features.distanceField.map { UInt8(bitPattern: $0) })), sha(ids))
	}

	@Test func generateGivesTheOriginalsStateAfterTheLakesAndEveryMapRoundTripsExactly() throws {
		let runs = try fixture().runs.dropFirst() // the smaller grids; the default 10,000-cell map is tested below
		var maps = 0, retainedRecords = 0, nonCanonical = 0
		for run in runs {
			for expected in run.results {
				let label = "\(expected.key), seed \(Array(run.seed.utf16)), \(run.cellsDesired) cells, limit \(expected.limit)"
				let template = try #require(HeightmapTemplate.named(expected.key))
				let map = try LandMap.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired, template: template, elevationLimit: expected.limit)

				// the whole pipeline in one call equals the original's state after the lakes
				let d = digests(map)
				#expect(d.heights == expected.afterOpening.heightsSha256 && d.distance == expected.afterOpening.distanceSha256 && d.ids == expected.afterOpening.featureIdsSha256, "\(label): the original's state")
				#expect(map.features.features.map { LandLakesTests.Row(i: $0.id, land: $0.land, border: $0.border, type: $0.kind.rawValue) } == expected.afterOpening.features, "\(label): feature records")

				// saving and loading gives the identical map, with the cells rebuilt identically
				let data = try map.encoded()
				let loaded = try LandMap(decoding: data)
				#expect(loaded == map, "\(label): round trip")
				#expect(loaded.voronoi == map.voronoi, "\(label): the rebuilt cells")
				#expect(try loaded.encoded() == data, "\(label): saving what was loaded gives the same bytes")

				// the exact state, not a canonical one: where the features differ from a fresh marking, loading keeps the saved ones
				let fresh = try LandFeatures.markup(heights: loaded.heights, voronoi: loaded.voronoi)
				if fresh != loaded.features { nonCanonical += 1 }
				if loaded.features.features.contains(where: { $0.kind == .ocean && !$0.border }) { retainedRecords += 1 }
				maps += 1
			}
		}
		#expect(maps == 350)
		#expect(nonCanonical > 50, "many maps carry state a re-marking would not give: \(nonCanonical)")
		#expect(retainedRecords > 20, "and opened lakes' retained records are saved and loaded: \(retainedRecords)")
	}

	@Test func theDefaultMapRoundTripsAndItsSizeIsKnown() throws {
		let template = try #require(HeightmapTemplate.named("highIsland"))
		let map = try LandMap.generate(seed: "kaz-1", template: template) // 1280 x 800, 10,000 cells, limit 20
		#expect(map.grid.points.count == 9954)
		let data = try map.encoded()
		let loaded = try LandMap(decoding: data)
		#expect(loaded == map && loaded.voronoi == map.voronoi)
		// a measurement for the documentation, not a promise: the exact-state JSON for the default map
		#expect(data.count > 100_000 && data.count < 2_000_000, "the default map's file is \(data.count) bytes")
		let expected = try fixture().runs.first { $0.seed == "kaz-1" && $0.cellsDesired == 10000 }?.results.first { $0.key == "highIsland" && $0.limit == 20 }
		let d = digests(map)
		#expect(d.heights == expected?.afterOpening.heightsSha256 && d.ids == expected?.afterOpening.featureIdsSha256)
	}

	@Test func loadingNeverRunsTheLakesAgain() throws {
		// find a template and size where a lower elevation limit makes more lakes than the sentinel 80, which makes none
		let grid = (seed: "mid", width: 640.0, height: 400.0, cells: 1000)
		var found: (template: HeightmapTemplate, withLakes: LandMap, withoutLakes: LandMap)?
		for template in HeightmapTemplate.all {
			let with = try LandMap.generate(seed: grid.seed, width: grid.width, height: grid.height, cellsDesired: grid.cells, template: template, elevationLimit: 20)
			let without = try LandMap.generate(seed: grid.seed, width: grid.width, height: grid.height, cellsDesired: grid.cells, template: template, elevationLimit: 80)
			if with.features.features.count > without.features.features.count { found = (template, with, without); break }
		}
		let pair = try #require(found)
		// loading the no-lakes save keeps it without lakes: a re-run at the default limit would have added some
		let loadedWithout = try LandMap(decoding: pair.withoutLakes.encoded())
		#expect(loadedWithout.features.features.count == pair.withoutLakes.features.features.count)
		#expect(loadedWithout.features.features.count < pair.withLakes.features.features.count)
		#expect(loadedWithout.heights == pair.withoutLakes.heights && loadedWithout.heights != pair.withLakes.heights)
		// the recipe records how it was made, and is never used to regenerate
		#expect(loadedWithout.recipe.settings["elevationLimit"] == "80.0" && loadedWithout.recipe.template == pair.template.key)
	}

	@Test func theSameInputsGiveTheSameBytesAndADifferentSeedDoesNot() throws {
		let template = try #require(HeightmapTemplate.named("archipelago"))
		let a = try LandMap.generate(seed: "kaz-1", width: 400, height: 300, cellsDesired: 800, template: template)
		let b = try LandMap.generate(seed: "kaz-1", width: 400, height: 300, cellsDesired: 800, template: template)
		let c = try LandMap.generate(seed: "kaz-2", width: 400, height: 300, cellsDesired: 800, template: template)
		let (bytesA, bytesB, bytesC) = (try a.encoded(), try b.encoded(), try c.encoded())
		#expect(a == b && bytesA == bytesB)
		#expect(a != c && bytesA != bytesC)
	}

	@Test func loadingRefusesAFileWhoseGridDoesNotMatchItsSizeOrWhoseContentIsInconsistent() throws {
		let template = try #require(HeightmapTemplate.named("continents"))
		let map = try LandMap.generate(seed: "k", width: 400, height: 300, cellsDesired: 600, template: template)
		let good = try map.encoded()
		func edited(_ edit: (inout [String: Any]) -> Void) throws -> Data {
			var json = try #require(JSONSerialization.jsonObject(with: good) as? [String: Any])
			edit(&json)
			return try JSONSerialization.data(withJSONObject: json)
		}
		// the boundary points are derived from the size and cell count, so a file that disagrees is refused
		#expect(throws: SavedLandMapError.gridDoesNotMatchSize) {
			try LandMap(decoding: edited { var b = $0["boundaryPoints"] as! [[Double]]; b[0][0] += 1; $0["boundaryPoints"] = b })
		}
		#expect(throws: SavedLandMapError.gridDoesNotMatchSize) { try LandMap(decoding: edited { $0["cellsDesired"] = 2000 }) }
		#expect(throws: SavedLandMapError.gridDoesNotMatchSize) { try LandMap(decoding: edited { $0["width"] = 410.0 }) }
		// content the validation catches: decoding refuses before a map is built
		#expect(throws: DecodingError.self) { try LandMap(decoding: edited { var h = $0["heights"] as! [Int]; h.removeLast(); $0["heights"] = h }) }
		#expect(throws: DecodingError.self) { try LandMap(decoding: edited { var f = $0["featureIds"] as! [Int]; f[0] = 9999; $0["featureIds"] = f }) }
		#expect(throws: DecodingError.self) { try LandMap(decoding: edited { $0["formatVersion"] = 2 }) }
		#expect(throws: DecodingError.self) { try LandMap(decoding: Data("not json".utf8)) }
		// a file the build wrote loads
		_ = try LandMap(decoding: good)
	}

	@Test func aSizeAndCellCountThatImplyExcessiveWorkAreRefusedBeforeAnythingIsEnumerated() throws {
		// a tiny record (one cell, one feature) whose size and cell count would make a counting loop run ~10^12 times
		func record(width: Double, height: Double, cellsDesired: Int) -> SavedLandMap {
			SavedLandMap(
				seed: "x", width: width, height: height, cellsDesired: cellsDesired,
				points: [Point(x: 0, y: 0)], boundaryPoints: [], heights: [50], featureIds: [1], coastDistance: [0],
				features: [SavedFeature(Feature(id: 1, land: true, border: true, kind: .island))]
			)
		}
		let cases: [(Double, Double, Int)] = [
			(1e12, 1, 1_000_000_000_000),          // spacing 1, a trillion columns
			(1e9, 1e9, 1_000_000_000_000),         // spacing 1e-3: far too many points
			(1e300, 1e300, 10),                    // the area overflows
			(1e-300, 1e-300, 10),                  // the area underflows
			(1, 1, Int.max),                       // a spacing that rounds to zero
			(1e12, 1, 1)                           // a very thin strip: no room for a cell point
		]
		for (w, h, n) in cases {
			// a deterministic assertion: the shared preflight rejects these inputs, and it runs before either counting loop or the
			// boundary construction, so the rejection precedes any enumeration (no wall-clock assertion: it could fail on a busy
			// machine and cannot interrupt a call that hangs)
			#expect(throws: SavedLandMapError.gridDoesNotMatchSize, "\(w) x \(h), \(n) cells") { try LandMap(saved: record(width: w, height: h, cellsDesired: n)) }
			#expect(throws: (any Error).self, "preflight itself refuses \(w) x \(h), \(n) cells") { try GridPoints.preflight(width: w, height: h, cellsDesired: n) }
		}
		// the shared preflight is the one generation uses
		#expect(throws: GridPointsError.tooManyPoints) { try GridPoints.preflight(width: 1e12, height: 1, cellsDesired: 1_000_000_000_000) }
		#expect(try GridPoints.preflight(width: 1280, height: 800, cellsDesired: 10_000) == 10.12)
	}

	@Test func aMapWithoutARecipeLoadsWithAnEmptyOne() throws {
		let template = try #require(HeightmapTemplate.named("continents"))
		var saved = try LandMap.generate(seed: "k", width: 400, height: 300, cellsDesired: 600, template: template).saved
		saved.recipe = nil
		let loaded = try LandMap(saved: saved)
		#expect(loaded.recipe == GenerationRecipe())
		#expect(loaded.heights == saved.heights)
		// saved again, the field is present: byte-identical re-saving holds for files `encoded()` produced, not for this one
		let resaved = try JSONSerialization.jsonObject(with: loaded.encoded()) as? [String: Any]
		#expect(resaved?["recipe"] != nil)
	}
}
