import Foundation
import Testing
@testable import FantasyMapKit

/// The water map: the whole chain in one call, and saving and loading its exact state (see docs/plans/water-8-saving.md).
struct WaterMapTests {
	func land(_ seed: String, _ template: String, cells: Int = 600) throws -> LandMap {
		try LandMap.generate(seed: seed, width: 800, height: 500, cellsDesired: cells, template: try #require(HeightmapTemplate.named(template)))
	}

	/// A small map with lakes with inlets and several rivers.
	func small() throws -> WaterMap {
		let runs = try RiverGeneratorTests().runs()
		let run = try #require(runs.first { $0.whole != nil && $0.erosion && $0.rain == 100 && $0.steps == 250 && $0.riverCount >= 5 && $0.lakes.contains { ($0.inlets ?? []).count > 1 } })
		var settings = WaterSettings()
		settings.precipitation = run.rain
		settings.lakeElevationLimit = run.limit
		let map = try LandMap.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired, template: try #require(HeightmapTemplate.named(run.key)))
		return try WaterMap.generate(land: map, settings: settings)
	}

	func decodeEdit(_ water: WaterMap, _ edit: (inout SavedWaterMap) -> Void) throws -> SavedWaterMap {
		var saved = water.saved
		edit(&saved)
		return saved
	}

	func refused(_ saved: SavedWaterMap, _ error: SavedWaterMapError, line: Int = #line) {
		#expect(throws: error, sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1)) { try WaterMap(saved: saved) }
	}

	@Test func theWholeChainInOneCallEqualsTheOriginalsEndStateOnTheCapturedRuns() throws {
		var checked = 0
		for run in try RiverGeneratorTests().runs() where run.cells < 2500 && checked < 40 {
			var settings = WaterSettings()
			settings.precipitation = run.rain
			settings.lakeElevationLimit = run.limit
			settings.allowErosion = run.erosion
			settings.resolveDepressionsSteps = run.steps
			let map = try LandMap.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired, template: try #require(HeightmapTemplate.named(run.key)))
			let water = try WaterMap.generate(land: map, settings: settings)
			#expect(Fixtures.hashUInt16s(water.flux) == run.sha.fl && Fixtures.hashUInt16s(water.riverIds) == run.sha.r && Fixtures.hashUInt16s(water.confluence) == run.sha.conf
				&& Fixtures.hashBytes(Data(water.packed.heights)) == run.sha.h, "\(run.seed)/\(run.key)")
			checked += 1
		}
		#expect(checked == 40)
	}

	@Test func manyMapsRoundTripExactlyAndSaveToTheSameBytes() throws {
		var withRivers = 0, withInlets = 0
		for (i, template) in HeightmapTemplate.all.map(\.key).enumerated() {
			for seed in ["a\(i)", "kaz-\(i)"] {
				let water = try WaterMap.generate(land: try land(seed, template, cells: i % 2 == 0 ? 600 : 1200))
				let data = try water.encoded()
				let loaded = try WaterMap(decoding: data)
				#expect(loaded == water, "\(seed)/\(template)")
				#expect(loaded.packed.voronoi == water.packed.voronoi && loaded.land.voronoi == water.land.voronoi, "the rebuilt cells")
				#expect(try loaded.encoded() == data, "the same bytes on a second save")
				withRivers += water.rivers.isEmpty ? 0 : 1
				withInlets += water.features.features.contains { !($0.inlets ?? []).isEmpty } ? 1 : 0
			}
		}
		#expect(withRivers > 5 && withInlets > 0, "the round trips carried rivers and lakes with inlets (\(withRivers), \(withInlets))")
	}

	@Test func aLoadedMapEqualsOneGeneratedAgainFromTheSameInputs() throws {
		let water = try small()
		let again = try WaterMap.generate(land: try WaterMap(decoding: try water.encoded()).land, settings: water.settings)
		#expect(again == water)
	}

	@Test func generationIsDeterministicAndSettingsAreValidated() throws {
		let a = try WaterMap.generate(land: try land("x", "continents")), b = try WaterMap.generate(land: try land("x", "continents"))
		let bytesA = try a.encoded(), bytesB = try b.encoded()
		#expect(a == b && bytesA == bytesB)
		let c = try land("x", "continents")
		for edit in [{ (s: inout WaterSettings) in s.heightExponent = 9 }, { $0.equator = .nan }, { $0.winds = [1] }, { $0.precipitation = -1 }, { $0.lakeElevationLimit = 101 }, { $0.resolveDepressionsSteps = 0 }, { $0.geography.mapSize = 101 }] as [(inout WaterSettings) -> Void] {
			var s = WaterSettings()
			edit(&s)
			#expect(throws: SavedWaterMapError.invalidSettings) { try WaterMap.generate(land: c, settings: s) }
		}
	}

	@Test func oneHeightExponentServesTheTemperatureAndTheLakes() throws {
		var s = WaterSettings()
		s.heightExponent = 1.7
		#expect(s.temperature.heightExponent == 1.7 && s.rivers.heightExponent == 1.7)
		let a = try WaterMap.generate(land: try land("x", "continents"), settings: s)
		#expect(try WaterMap(decoding: try a.encoded()).settings.heightExponent == 1.7)
	}

	@Test func loadingRecomputesNothing() throws {
		let water = try small()
		// a river's discharge, a lake's evaporation and a packed height are kept as saved, not worked out again
		var saved = water.saved
		saved.rivers[0].discharge += 1
		let lake = try #require(saved.features.firstIndex { $0.kind == .lake })
		saved.features[lake].evaporation += 1
		let loaded = try WaterMap(saved: saved)
		#expect(loaded.rivers[0].discharge == water.rivers[0].discharge + 1)
		#expect(loaded.features.features[lake].evaporation == water.features.features[lake].evaporation + 1)
	}

	@Test func aFileOfAnotherVersionIsRefused() throws {
		let water = try small()
		refused(try decodeEdit(water) { $0.formatVersion = 2 }, .unsupportedFormatVersion(2))
		refused(try decodeEdit(water) { $0.algorithmRevision = 2 }, .unsupportedAlgorithmRevision(2))
		#expect(throws: Error.self) { try WaterMap(decoding: Data("{}".utf8)) }
		#expect(throws: Error.self) { try WaterMap(decoding: Data("not json".utf8)) }
	}

	@Test func settingsAndGeographyAreChecked() throws {
		let water = try small()
		refused(try decodeEdit(water) { $0.settings.winds = [] }, .invalidSettings)
		refused(try decodeEdit(water) { $0.settings.equator = 500 }, .invalidSettings)
		refused(try decodeEdit(water) { $0.geography.coordinates.latN += 1 }, .invalidGeography)
		refused(try decodeEdit(water) { $0.geography.mapSize = .nan }, .invalidGeography)
		refused(try decodeEdit(water) { $0.temperature.removeLast() }, .climateCountsDiffer)
		refused(try decodeEdit(water) { $0.precipitation.append(0) }, .climateCountsDiffer)
	}

	@Test func theLandMapInsideIsValidatedToo() throws {
		let water = try small()
		#expect(throws: SavedLandMapError.self) { try WaterMap(saved: try decodeEdit(water) { $0.land.heights.removeLast() }) }
	}

	@Test func thePackedArraysAndCellsAreChecked() throws {
		let water = try small()
		for edit in [{ (s: inout SavedWaterMap) in s.packedGridCell.removeLast() }, { $0.packedHeights.removeLast() }, { $0.packedAreas.removeLast() }, { $0.featureIds.removeLast() }, { $0.distanceField.removeLast() },
			{ $0.haven.removeLast() }, { $0.harbor.removeLast() }, { $0.flux.removeLast() }, { $0.riverIds.removeLast() }, { $0.confluence.removeLast() }] as [(inout SavedWaterMap) -> Void] {
			refused(try decodeEdit(water, edit), .packedCountsDiffer)
		}
		refused(try decodeEdit(water) { $0.packedPoints = []; $0.packedGridCell = []; $0.packedHeights = []; $0.packedAreas = []; $0.featureIds = []; $0.distanceField = []; $0.haven = []; $0.harbor = []; $0.flux = []; $0.riverIds = []; $0.confluence = [] }, .packedCountsDiffer)
		refused(try decodeEdit(water) { $0.packedPoints[3].x = -1 }, .invalidPackedCell(index: 3))
		refused(try decodeEdit(water) { $0.packedPoints[3].y = .infinity }, .invalidPackedCell(index: 3))
		refused(try decodeEdit(water) { $0.packedPoints[3].y = -1 }, .invalidPackedCell(index: 3))
		refused(try decodeEdit(water) { $0.packedPoints[3].y = $0.land.height + 1 }, .invalidPackedCell(index: 3))
		refused(try decodeEdit(water) { $0.packedPoints[3].x = $0.land.width + 1 }, .invalidPackedCell(index: 3))
		refused(try decodeEdit(water) { $0.packedGridCell[4] = $0.temperature.count }, .invalidPackedCell(index: 4))
		refused(try decodeEdit(water) { $0.packedGridCell[4] = -1 }, .invalidPackedCell(index: 4))
		refused(try decodeEdit(water) { $0.packedHeights[5] = 101 }, .invalidPackedCell(index: 5))
		refused(try decodeEdit(water) { $0.packedAreas[6] &+= 1 }, .packedCellsDoNotMatch(index: 6))
		// a point moved a little keeps the counts but changes the cells, so the areas no longer agree
		let moved = try decodeEdit(water) { $0.packedPoints[7].x += 0.5 }
		#expect(throws: SavedWaterMapError.self) { try WaterMap(saved: moved) }
		refused(try decodeEdit(water) { $0.distanceField[8] = -11 }, .invalidPackedCell(index: 8))
		refused(try decodeEdit(water) { $0.harbor[9] = 200 }, .invalidPackedCell(index: 9))
		let riverCell = try #require(water.riverIds.firstIndex { $0 != 0 })
		refused(try decodeEdit(water) { $0.riverIds[riverCell] = 65535 }, .invalidPackedCell(index: riverCell))
	}

	@Test func theFeaturesAreChecked() throws {
		let water = try small()
		let lake = try #require(water.features.features.firstIndex { $0.kind == .lake })
		let id = water.features.features[lake].id
		refused(try decodeEdit(water) { $0.features.removeAll() }, .invalidFeature(id: 0))
		refused(try decodeEdit(water) { $0.features[0].id = 5 }, .invalidFeature(id: 0))
		refused(try decodeEdit(water) { $0.features[lake].land = true }, .invalidFeature(id: 0))
		refused(try decodeEdit(water) { $0.features[lake].cells += 1 }, .invalidFeature(id: id))
		refused(try decodeEdit(water) { $0.features[lake].firstCell = $0.flux.count }, .structureInvalid) // a lake's first cell must be its own
		refused(try decodeEdit(water) { $0.features[lake].vertices = [-1] }, .invalidFeature(id: id))
		let ocean0 = try #require(water.features.features.first { $0.kind == .ocean })
		refused(try decodeEdit(water) { $0.features[ocean0.id - 1].firstCell = -1 }, .invalidFeature(id: ocean0.id))
		refused(try decodeEdit(water) { $0.features[ocean0.id - 1].firstCell = $0.flux.count }, .invalidFeature(id: ocean0.id))
		// a first cell in range that belongs to another feature (an ocean, an island and a lake)
		for f in water.features.features {
			let other = try #require(water.features.featureIds.firstIndex { Int($0) != f.id })
			refused(try decodeEdit(water) { $0.features[f.id - 1].firstCell = other }, f.kind == .lake ? .structureInvalid : .invalidFeature(id: f.id))
		}
		refused(try decodeEdit(water) { $0.features[ocean0.id - 1].shoreline = [-1] }, .invalidFeature(id: ocean0.id))
		refused(try decodeEdit(water) { $0.features[ocean0.id - 1].shoreline = [$0.flux.count] }, .invalidFeature(id: ocean0.id))
		refused(try decodeEdit(water) { $0.features[lake].flux = .nan }, .invalidFeature(id: id))
		refused(try decodeEdit(water) { $0.features[lake].temp = .infinity }, .invalidFeature(id: id))
		refused(try decodeEdit(water) { $0.features[lake].inlets = [60000] }, .invalidFeature(id: id))
		refused(try decodeEdit(water) { $0.features[lake].outlet = 60000 }, .invalidFeature(id: id))
		let ocean = try #require(water.features.features.first { $0.kind == .ocean })
		refused(try decodeEdit(water) { $0.features[ocean.id - 1].outlet = $0.rivers[0].id }, .invalidFeature(id: ocean.id))
		refused(try decodeEdit(water) { $0.features[lake].shoreline = [] }, .structureInvalid)
		let landCell = try #require(water.packed.heights.lastIndex { $0 >= Heights.seaLevel })
		refused(try decodeEdit(water) { $0.haven[landCell] = landCell }, .structureInvalid)
		refused(try decodeEdit(water) { $0.haven[landCell] = -1 }, .structureInvalid)
		let water0 = try #require(water.packed.heights.firstIndex { $0 < Heights.seaLevel })
		refused(try decodeEdit(water) { $0.featureIds[water0] = UInt16($0.features.first { $0.land }!.id) }, .structureInvalid)
		refused(try decodeEdit(water) { $0.featureIds[0] = 0 }, .structureInvalid)
	}

	@Test func theRiversAreChecked() throws {
		let water = try small()
		let first = water.rivers[0].id
		refused(try decodeEdit(water) { $0.rivers[1].id = $0.rivers[0].id }, .invalidRiver(id: 0))
		refused(try decodeEdit(water) { $0.rivers[0].id = 0 }, .invalidRiver(id: 0))
		refused(try decodeEdit(water) { $0.rivers[0].id = 70000 }, .invalidRiver(id: 0))
		refused(try decodeEdit(water) { $0.rivers[0].discharge = .nan }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].length = -1 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].cells = [1, 2] }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].cells = [5, 6]; $0.rivers[0].source = 5; $0.rivers[0].mouth = 5 }, .invalidRiver(id: first)) // consistent, but too short
		refused(try decodeEdit(water) { $0.rivers[0].cells[1] = $0.flux.count }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].cells[1] = -2 }, .invalidRiver(id: first))
		// a record that agrees with itself but whose source and mouth are not cells
		refused(try decodeEdit(water) { $0.rivers[0].cells = [-1, -1, -1]; $0.rivers[0].source = -1; $0.rivers[0].mouth = -1 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].cells = [-1, 6, 7]; $0.rivers[0].source = -1; $0.rivers[0].mouth = 6 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { let m = $0.flux.count; $0.rivers[0].cells = [m, m, m]; $0.rivers[0].source = m; $0.rivers[0].mouth = m }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].cells = [5, 6, 7]; $0.rivers[0].source = 5; $0.rivers[0].mouth = -1; $0.rivers[0].cells[1] = -1 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].source += 1 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].mouth += 1 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].parent = -1 }, .invalidRiver(id: first))
		refused(try decodeEdit(water) { $0.rivers[0].parent = 70000 }, .invalidRiver(id: first))
		// the original's own rivers can name themselves, or a short river that was dropped, as parent: those load
		_ = try WaterMap(saved: try decodeEdit(water) { $0.rivers[0].parent = $0.rivers[0].id })
		_ = try WaterMap(saved: try decodeEdit(water) { $0.rivers[0].parent = 60000 })
	}

	@Test func theLoadedFileNeverHoldsTheTemporaryLakeFields() throws {
		let water = try small()
		#expect(water.features.features.allSatisfy { $0.closed == nil && $0.outCell == nil && $0.river == nil && $0.enteringFlux == nil })
		let text = String(decoding: try water.encoded(), as: UTF8.self)
		for key in ["\"closed\"", "\"outCell\"", "\"enteringFlux\""] { #expect(!text.contains(key)) }
	}

	@Test func aCompressedFileIsSmallerLoadsToTheSameMapAndIsRepeatable() throws {
		let water = try small()
		let plain = try water.encoded(), packed = try water.compressedEncoded()
		#expect(packed.count < plain.count / 2, "\(packed.count) of \(plain.count)")
		#expect(SavedFileCompression.isCompressed(packed) && !SavedFileCompression.isCompressed(plain))
		let loaded = try WaterMap(decoding: packed)
		#expect(loaded == water)
		#expect(try loaded.encoded() == plain, "saving what was loaded from a compressed file gives the plain file's bytes")
		#expect(try water.compressedEncoded() == packed, "the same bytes twice (in the tested environment)")
		#expect(try WaterMap(decoding: plain) == water)
	}

	@Test func aCompressedFileThatIsDamagedOrWouldExpandTooFarIsRefused() throws {
		let water = try small()
		let packed = try water.compressedEncoded()
		#expect(throws: SavedWaterMapError.invalidCompression) { try WaterMap(decoding: Data(packed.prefix(packed.count / 2))) } // cut short
		#expect(throws: SavedWaterMapError.invalidCompression) { try WaterMap(decoding: Data("bvx2 garbage that is no stream".utf8)) }
		#expect(throws: SavedWaterMapError.invalidCompression) { try WaterMap(decoding: Data("bvx".utf8)) }
		#expect(throws: SavedWaterMapError.invalidCompression) { try SavedFileCompression.decompress(Data()) }
		#expect(SavedFileCompression.isCompressed(Data("bvx".utf8)) && !SavedFileCompression.isCompressed(Data("bv".utf8)) && !SavedFileCompression.isCompressed(Data("bvz".utf8)) && !SavedFileCompression.isCompressed(Data("{".utf8)))
		// damage in the middle of a stream: refused one way or another, never loaded
		var damaged = packed
		for i in stride(from: packed.count / 3, to: packed.count / 3 + 400, by: 7) { damaged[i] ^= 0xFF }
		#expect(throws: Error.self) { try WaterMap(decoding: damaged) }
		// a small file that describes far more than the limit allows: refused before it is all produced
		let zeros = try (Data(count: 8_000_000) as NSData).compressed(using: .lzfse) as Data
		#expect(zeros.count < 100_000)
		#expect(throws: SavedWaterMapError.decompressedTooLarge) { try WaterMap(decoding: zeros, decompressedLimit: 1_000_000) }
		// the limit is exact: a stream that expands to exactly the limit is not refused for size (it is not a water map)
		let json = try water.encoded()
		_ = try WaterMap(decoding: try SavedFileCompression.compress(json), decompressedLimit: json.count)
		#expect(throws: SavedWaterMapError.decompressedTooLarge) { try WaterMap(decoding: try SavedFileCompression.compress(json), decompressedLimit: json.count - 1) }
	}

	@Test func theSizesOfSavedFiles() throws {
		let water = try small()
		print("a saved water map of \(water.packed.points.count) packed cells (\(water.land.grid.points.count) grid cells, \(water.rivers.count) rivers): \(try water.encoded().count) bytes")
	}
}
