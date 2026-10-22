import Foundation
import Testing
@testable import FantasyMapCore

/// The saved schema: it round-trips, and validation refuses what a build cannot accept.
struct SavedLandMapTests {
	func sample() -> SavedLandMap {
		SavedLandMap(
			seed: "日本語", width: 100, height: 60, cellsDesired: 24,
			points: [Point(x: 3.34, y: 14.36), Point(x: 24.78, y: 7.63)],
			boundaryPoints: [Point(x: 1, y: -16), Point(x: 1, y: 76)],
			heights: [19, 100],
			featureIds: [1, 2],
			coastDistance: [-1, 1],
			features: [
				SavedFeature(Feature(id: 1, land: false, border: true, kind: .ocean)),
				SavedFeature(Feature(id: 2, land: true, border: true, kind: .island))
			],
			recipe: GenerationRecipe(template: "continents", steps: ["Hill 1 80-85 60-80 40-60"], settings: ["cells": "10000"])
		)
	}

	@Test func theFormatStartsAtOneAndTheAlgorithmRevisionToo() {
		#expect(FantasyMapCore.formatVersion == 1 && FantasyMapCore.algorithmRevision == 1)
		// version 2 is the format of a map with a realm layer (docs/plans/realms-saving.md) and version 3 of a map with pins (docs/plans/pins-saving.md); a map with neither is still written in version 1
		#expect(FantasyMapCore.formatVersionWithRealms == 2 && FantasyMapCore.formatVersionWithPins == 3 && SavedLandMap.supportedFormatVersions == [1, 2, 3] && SavedLandMap.supportedAlgorithmRevisions == [1])
	}

	@Test func aSavedMapRoundTripsExactly() throws {
		let map = sample()
		let data = try JSONEncoder().encode(map)
		#expect(try JSONDecoder().decode(SavedLandMap.self, from: data) == map)
	}

	@Test func theSchemaCarriesTheExactState() throws {
		let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample())) as? [String: Any])
		#expect(json["formatVersion"] as? Int == FantasyMapCore.formatVersion)
		#expect(json["algorithmRevision"] as? Int == FantasyMapCore.algorithmRevision)
		#expect((json["points"] as? [[Double]])?.first == [3.34, 14.36]) // a point is a two-number array
		#expect((json["boundaryPoints"] as? [[Double]])?.count == 2)
		#expect((json["heights"] as? [Int]) == [19, 100])
		#expect((json["featureIds"] as? [Int]) == [1, 2])
		#expect((json["coastDistance"] as? [Int]) == [-1, 1])
		let records = try #require(json["features"] as? [[String: Any]])
		#expect(records.map { $0["kind"] as? String } == ["ocean", "island"])
		#expect((json["recipe"] as? [String: Any])?["template"] as? String == "continents")
	}

	@Test func aMapWithoutARecipeIsCompleteAndLoads() throws {
		var map = sample()
		map.recipe = nil
		let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(map)) as? [String: Any])
		#expect(json["recipe"] == nil)
		#expect(try JSONDecoder().decode(SavedLandMap.self, from: JSONEncoder().encode(map)) == map)
	}

	@Test func validationRefusesWhatABuildCannotAccept() {
		func refused(_ change: (inout SavedLandMap) -> Void) -> SavedLandMapError? {
			var map = sample()
			change(&map)
			do { try map.validate(); return nil } catch { return error as? SavedLandMapError }
		}
		#expect(refused { _ in } == nil)
		#expect(refused { $0.formatVersion = 0 } == .unsupportedFormatVersion(0))
		#expect(refused { $0.formatVersion = 99 } == .unsupportedFormatVersion(99))
		#expect(refused { $0.algorithmRevision = 99 } == .unsupportedAlgorithmRevision(99))
		#expect(refused { $0.width = 0 } == .invalidSize)
		#expect(refused { $0.height = .nan } == .invalidSize)
		#expect(refused { $0.width = -5 } == .invalidSize)
		#expect(refused { $0.cellsDesired = 0 } == .invalidCellCount)
		#expect(refused { $0.heights = [19] } == .pointAndHeightCountsDiffer(points: 2, heights: 1))
		#expect(refused { $0.heights = [19, 101] } == .heightOutOfRange(index: 1))
		#expect(refused { $0.points[0].x = .infinity } == .pointOutsideFiniteRange)
		#expect(refused { $0.boundaryPoints[1].y = .nan } == .pointOutsideFiniteRange)
		#expect(refused { $0.points[1].x = 101 } == .pointOutsideMap(index: 1))
		#expect(refused { $0.points[0].y = -0.5 } == .pointOutsideMap(index: 0))
		#expect(refused { $0.featureIds = [1] } == .featureIdCountDiffers(ids: 1, cells: 2))
		#expect(refused { $0.coastDistance = [1, 1, 1] } == .coastDistanceCountDiffers(distances: 3, cells: 2))
		#expect(refused { $0.features = [] } == .invalidFeatureTable)
		#expect(refused { $0.features[1].id = 5 } == .invalidFeatureTable) // ids must be 1, 2, 3 ...
		#expect(refused { $0.features[0].land = true } == .invalidFeatureTable) // an ocean is not land
		#expect(refused { $0.features[1].kind = .lake } == .invalidFeatureTable) // an island is land
		#expect(refused { $0.featureIds = [1, 3] } == .featureIdOutOfRange(index: 1))
		#expect(refused { $0.featureIds = [0, 2] } == .featureIdOutOfRange(index: 0))
		#expect(refused { $0.featureIds = [2, 2] } == .featureDisagreesWithHeight(index: 0)) // a water cell in a land feature
		#expect(refused { $0.heights = [19, 10] } == .featureDisagreesWithHeight(index: 1)) // a land feature on a water cell
		#expect(refused { $0.coastDistance = [-10, 1] } == .invalidCoastDistance(index: 0))
		#expect(refused { $0.coastDistance = [-1, 2] } == .invalidCoastDistance(index: 1))
		// the sign is deliberately not tied to land or water: the original can leave 1 on a water cell beside a lake
		#expect(refused { $0.coastDistance = [1, 1] } == nil)
		#expect(refused { $0.points = [Point](repeating: Point(x: 1, y: 1), count: GridPoints.maximumPoints + 1) } == .tooManyCells)
	}

	@Test func decodingRefusesAnInvalidMapAndAMalformedPoint() throws {
		let decoder = JSONDecoder()
		func data(_ edit: (inout [String: Any]) -> Void) throws -> Data {
			var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample())) as? [String: Any])
			edit(&json)
			return try JSONSerialization.data(withJSONObject: json)
		}
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: data { $0["heights"] = [19] }) }
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: data { $0["points"] = [[3.34, 14.36, 9.0], [24.78, 7.63]] }) } // a trailing coordinate
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: data { $0["points"] = [[3.34], [24.78, 7.63]] }) } // a missing coordinate
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: data { $0["featureIds"] = [1, 9] }) }
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: data { $0["coastDistance"] = [-1, 300] }) } // not an Int8
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: data { $0.removeValue(forKey: "features") }) } // a missing field
		#expect(throws: DecodingError.self) { try decoder.decode(SavedLandMap.self, from: Data("{".utf8)) } // not JSON
	}
}
