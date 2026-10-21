import CryptoKit
import Foundation
import Testing
@testable import FantasyMapKit

/// Step 6 of docs/plans/land-layer.md: features and the coast-distance field, against the original's own `markupGrid`.
struct LandFeaturesTests {
	struct Fixture: Decodable {
		struct FeatureRow: Decodable { var i: Int; var land: Bool; var border: Bool; var type: String }
		struct Result: Decodable {
			var key: String
			var cells: Int
			var heightsSha256: String
			var distanceSha256: String
			var featureIdsSha256: String
			var featureCount: Int
			var features: [FeatureRow]
			var distanceValues: [Int]
			var heights: [Int]?
			var distance: [Int]?
			var featureIds: [Int]?
		}
		struct Run: Decodable { var seed: String; var width: Double; var height: Double; var cellsDesired: Int; var results: [Result] }
		var runs: [Run]
	}

	func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("features-original")) }

	func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

	@Test func featuresAndTheDistanceFieldMatchTheOriginalsOwnForEveryTemplateOnEveryFixtureGrid() throws {
		let runs = try fixture().runs
		#expect(runs.count == 5)
		var checked = 0
		var kinds = Set<String>()
		var values = Set<Int>()
		for run in runs {
			let grid = try GridPoints.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired)
			let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
			for expected in run.results {
				let label = "\(expected.key), seed \(Array(run.seed.utf16)), \(run.cellsDesired) cells"
				let template = try #require(HeightmapTemplate.named(expected.key))
				let heights = try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: run.seed)
				#expect(sha(Data(heights)) == expected.heightsSha256, "\(label): the heights the features are marked on")
				let result = try LandFeatures.markup(heights: heights, voronoi: voronoi)
				// the distance field as Int8 bytes, and the feature ids as little-endian UInt16
				#expect(sha(Data(result.distanceField.map { UInt8(bitPattern: $0) })) == expected.distanceSha256, "\(label): distance field")
				var idBytes = Data()
				for id in result.featureIds { idBytes.append(UInt8(id & 0xff)); idBytes.append(UInt8(id >> 8)) }
				#expect(sha(idBytes) == expected.featureIdsSha256, "\(label): feature ids")
				#expect(result.features.count == expected.featureCount, "\(label): feature count")
				for (mine, theirs) in zip(result.features, expected.features) {
					#expect(mine.id == theirs.i && mine.land == theirs.land && mine.border == theirs.border && mine.kind.rawValue == theirs.type, "\(label): feature \(theirs.i)")
					kinds.insert(theirs.type)
				}
				#expect(Set(result.distanceField.map(Int.init)) == Set(expected.distanceValues), "\(label): which distance values occur")
				values.formUnion(expected.distanceValues)
				if let t = expected.distance, let f = expected.featureIds {
					#expect(result.distanceField.map(Int.init) == t, "\(label): distance field cell for cell")
					#expect(result.featureIds.map(Int.init) == f, "\(label): feature ids cell for cell")
				}
				checked += 1
			}
		}
		#expect(checked == 70) // fourteen templates on five grids
		#expect(kinds == ["island", "ocean", "lake"], "the fixtures include all three kinds of feature")
		#expect(values.isSuperset(of: [-9, -2, -1, 0, 1]), "and the coast, shallow and deep water")
	}

	// MARK: small hand-made cases

	/// A 100 x 60 grid of 24 cells to put chosen heights on.
	func tinyGrid() throws -> (GridPoints, VoronoiDiagram) {
		let grid = try GridPoints.generate(seed: "k", width: 100, height: 60, cellsDesired: 24)
		return (grid, try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary))
	}

	@Test func allLandIsOneIslandTouchingTheEdgeWithNoCoast() throws {
		let (grid, voronoi) = try tinyGrid()
		let result = try LandFeatures.markup(heights: [Height](repeating: 50, count: grid.points.count), voronoi: voronoi)
		#expect(result.features == [Feature(id: 1, land: true, border: true, kind: .island)])
		#expect(result.featureIds.allSatisfy { $0 == 1 })
		#expect(result.distanceField.allSatisfy { $0 == 0 }) // no water: no coast and nothing inland is measured
	}

	@Test func allWaterIsOneOceanAndTheFieldIsAllZero() throws {
		let (grid, voronoi) = try tinyGrid()
		let result = try LandFeatures.markup(heights: [Height](repeating: 5, count: grid.points.count), voronoi: voronoi)
		#expect(result.features == [Feature(id: 1, land: false, border: true, kind: .ocean)])
		#expect(result.distanceField.allSatisfy { $0 == 0 }) // no land: no water coast, so no distance to grow from
	}

	@Test func waterInsideLandThatDoesNotReachTheEdgeIsALake() throws {
		let grid = try GridPoints.generate(seed: "k", width: 400, height: 300, cellsDesired: 600)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		// land everywhere except one interior cell
		let interior = try #require(voronoi.cells.b.indices.first { voronoi.cells.b[$0] == 0 })
		var heights = [Height](repeating: 60, count: grid.points.count)
		heights[interior] = 10
		let result = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		let kinds = result.features.map(\.kind)
		#expect(kinds.contains(.lake) && kinds.contains(.island) && !kinds.contains(.ocean))
		#expect(result.distanceField[interior] == -1) // water next to land
		for n in voronoi.cells.c[interior] { #expect(result.distanceField[n] == 1) } // land next to water
		#expect(result.feature(Int(result.featureIds[interior]))?.kind == .lake)
		#expect(result.feature(0) == nil && result.feature(result.features.count + 1) == nil)
	}

	@Test func waterDistanceGrowsOutwardFromTheCoastToMinusNine() throws {
		let grid = try GridPoints.generate(seed: "k", width: 600, height: 100, cellsDesired: 600)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		// land on the left of the map, sea elsewhere: distance grows with the steps away from the shore
		var heights = [Height](repeating: 5, count: grid.points.count)
		for (i, p) in grid.points.enumerated() where p.x < 60 { heights[i] = 50 }
		let result = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		let waterValues = Set(result.distanceField.filter { $0 < 0 }.map(Int.init))
		#expect(waterValues.contains(-1) && waterValues.contains(-2) && waterValues.min()! >= -9)
		#expect(result.distanceField.max()! == 1)
		// water never reaches -10: the growth stops at -9, so far water stays at 0 when it is farther than 9 steps
		#expect(!waterValues.contains(-10))
	}

	@Test func theFeatureLimitIsCheckedBeforeTheNextNumberIsAssigned() throws {
		let grid = try GridPoints.generate(seed: "k", width: 600, height: 100, cellsDesired: 600)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		// land in vertical stripes 40 units wide, sea between: several features
		var heights = [Height](repeating: 5, count: grid.points.count)
		for (i, p) in grid.points.enumerated() where Int(p.x / 40) % 2 == 0 { heights[i] = 50 }
		let all = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		let n = all.features.count
		#expect(n >= 5)
		#expect(all.features.map(\.id) == Array(1...n)) // numbered in order from 1
		// exactly the limit succeeds with the same result; one below throws
		#expect(try LandFeatures.markup(heights: heights, voronoi: voronoi, maximumFeatures: n) == all)
		#expect(throws: LandFeaturesError.tooManyFeatures) { try LandFeatures.markup(heights: heights, voronoi: voronoi, maximumFeatures: n - 1) }
		#expect(throws: LandFeaturesError.tooManyFeatures) { try LandFeatures.markup(heights: heights, voronoi: voronoi, maximumFeatures: 0) }
		// and the public limit is the 16-bit array's: 65,535
		#expect(Int(UInt16.max) == 65_535 && all.featureIds.allSatisfy { Int($0) >= 1 && Int($0) <= n })
	}

	@Test func theForwardSearchNumbersFeaturesExactlyAsASearchFromZeroWould() throws {
		// a fragmented pattern: land cells scattered by a hash, so features appear in many places and orders
		let grid = try GridPoints.generate(seed: "frag", width: 400, height: 300, cellsDesired: 3000)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		var heights = [Height](repeating: 5, count: grid.points.count)
		for i in heights.indices where (i &* 2654435761) % 7 < 3 { heights[i] = 50 }
		let result = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		#expect(result.features.count > 20)
		// a feature's lowest-index cell: numbers must increase with it, as a search from zero would assign them
		var firstCell: [Int: Int] = [:]
		for (i, id) in result.featureIds.enumerated() where firstCell[Int(id)] == nil { firstCell[Int(id)] = i }
		let ordered = (1...result.features.count).map { firstCell[$0]! }
		#expect(ordered == ordered.sorted())
	}

	@Test func inconsistentInputIsRefused() throws {
		let (grid, voronoi) = try tinyGrid()
		#expect(throws: LandFeaturesError.inconsistentInput) { try LandFeatures.markup(heights: [Height](repeating: 50, count: grid.points.count - 1), voronoi: voronoi) }
		#expect(throws: LandFeaturesError.inconsistentInput) { try LandFeatures.markup(heights: [], voronoi: voronoi) }
	}
}
