import CryptoKit
import Foundation
import Testing
@testable import FantasyMapCore

/// Step 7 of docs/plans/land-layer.md: the deep-depression and near-sea lakes, against the original's own routines.
struct LandLakesTests {
	struct Row: Decodable, Equatable { var i: Int; var land: Bool; var border: Bool; var type: String }
	struct Snapshot: Decodable {
		var heightsSha256: String
		var distanceSha256: String
		var featureIdsSha256: String
		var features: [Row]
		var land: Int
	}
	struct Result: Decodable {
		var key: String
		var limit: Double
		var templateOption: String
		var before: Snapshot
		var lakesFound: [[Int]]
		var afterDepressions: Snapshot
		var afterOpening: Snapshot
		var heights: [Int]?
		var distance: [Int]?
		var featureIds: [Int]?
	}
	struct Run: Decodable { var seed: String; var width: Double; var height: Double; var cellsDesired: Int; var results: [Result] }
	struct Single: Decodable {
		var seed: String; var width: Double; var height: Double; var cellsDesired: Int
		var key: String; var limit: Double; var templateOption: String
		var before: Snapshot; var lakesFound: [[Int]]; var afterDepressions: Snapshot; var afterOpening: Snapshot
		var heights: [Int]?; var distance: [Int]?; var featureIds: [Int]?
	}
	struct Fixture: Decodable { var runs: [Run]; var atoll: [Single]; var fulls: [Single] }

	func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("lakes-original")) }

	func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

	func digests(heights: [Height], features: LandFeatures) -> (heights: String, distance: String, ids: String) {
		var ids = Data()
		for id in features.featureIds { ids.append(UInt8(id & 0xff)); ids.append(UInt8(id >> 8)) }
		return (sha(Data(heights)), sha(Data(features.distanceField.map { UInt8(bitPattern: $0) })), sha(ids))
	}

	func rows(_ features: LandFeatures) -> [Row] {
		features.features.map { Row(i: $0.id, land: $0.land, border: $0.border, type: $0.kind.rawValue) }
	}

	/// Runs the original's sequence on a template map and compares every stage with the fixture.
	func compare(_ expected: Result, seed: String, grid: GridPoints, voronoi: VoronoiDiagram, label: String) throws -> (lakes: Int, opened: Int) {
		let template = try #require(HeightmapTemplate.named(expected.key))
		var heights = try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: seed)
		var features = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		func check(_ snapshot: Snapshot, _ stage: String) {
			let d = digests(heights: heights, features: features)
			#expect(d.heights == snapshot.heightsSha256, "\(label) \(stage): heights")
			#expect(d.distance == snapshot.distanceSha256, "\(label) \(stage): coast distance")
			#expect(d.ids == snapshot.featureIdsSha256, "\(label) \(stage): feature ids")
			#expect(rows(features) == snapshot.features, "\(label) \(stage): feature records")
			#expect(heights.filter { Heights.isLand($0) }.count == snapshot.land, "\(label) \(stage): land cells")
		}
		check(expected.before, "before")
		#expect(LandLakes.findDeepDepressionLakes(heights: heights, voronoi: voronoi, elevationLimit: expected.limit) == expected.lakesFound, "\(label): lakes found")
		try LandLakes.addDeepDepressionLakes(heights: &heights, features: &features, voronoi: voronoi, elevationLimit: expected.limit)
		check(expected.afterDepressions, "after depression lakes")
		let beforeOpening = rows(features)
		try LandLakes.openNearSeaLakes(heights: &heights, features: &features, voronoi: voronoi, templateOption: expected.templateOption)
		check(expected.afterOpening, "after near-sea lakes")
		if let h = expected.heights, let t = expected.distance, let f = expected.featureIds {
			#expect(heights.map(Int.init) == h, "\(label): heights cell for cell")
			#expect(features.distanceField.map(Int.init) == t, "\(label): coast distance cell for cell")
			#expect(features.featureIds.map(Int.init) == f, "\(label): feature ids cell for cell")
		}
		return (expected.lakesFound.count, rows(features) != beforeOpening ? 1 : 0)
	}

	@Test func everyStageMatchesTheOriginalsOwnRoutinesOnEveryTemplateGridAndElevationLimit() throws {
		let runs = try fixture().runs
		#expect(runs.count == 6)
		var maps = 0, withDepressionLakes = 0, withOpening = 0
		var openedWithBorderFalse = 0
		for run in runs {
			let grid = try GridPoints.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired)
			let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
			for expected in run.results {
				let label = "\(expected.key), seed \(Array(run.seed.utf16)), \(run.cellsDesired) cells, limit \(expected.limit)"
				let r = try compare(expected, seed: run.seed, grid: grid, voronoi: voronoi, label: label)
				maps += 1
				if r.lakes > 0 { withDepressionLakes += 1 }
				if r.opened > 0 { withOpening += 1 }
				if expected.afterOpening.features.contains(where: { $0.type == "ocean" && !$0.border }) { openedWithBorderFalse += 1 }
			}
		}
		#expect(maps == 420)
		#expect(withDepressionLakes > 100 && withOpening > 100, "the fixtures exercise both routines: \(withDepressionLakes) maps with depression lakes, \(withOpening) with a lake opened")
		#expect(openedWithBorderFalse > 0, "an opened lake keeps its record: an ocean whose border is false occurs")
	}

	@Test func theAtollOptionEarlyReturnHappensOnlyForTheExactStringAsInTheOriginal() throws {
		let cases = try fixture().atoll
		#expect(cases.count == 12)
		for c in cases {
			let grid = try GridPoints.generate(seed: c.seed, width: c.width, height: c.height, cellsDesired: c.cellsDesired)
			let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
			#expect(c.templateOption == "Atoll")
			let expected = Result(key: c.key, limit: c.limit, templateOption: c.templateOption, before: c.before, lakesFound: c.lakesFound, afterDepressions: c.afterDepressions, afterOpening: c.afterOpening, heights: c.heights, distance: c.distance, featureIds: c.featureIds)
			_ = try compare(expected, seed: c.seed, grid: grid, voronoi: voronoi, label: "Atoll option, \(c.key), seed \(Array(c.seed.utf16))")
			// the early return leaves the near-sea step doing nothing
			#expect(c.afterOpening.heightsSha256 == c.afterDepressions.heightsSha256 && c.afterOpening.features == c.afterDepressions.features)
		}
		// the template KEY "atoll" is not the string "Atoll": as written in the original, it does not skip the step (the fixtures
		// above with option = key ran the step on the atoll template too), so the exception is dead code for a real selection
		#expect(LandLakes.atollTemplateOption == "Atoll" && HeightmapTemplate.named("atoll")?.name == "Atoll")
		#expect(HeightmapTemplate.named("atoll")?.key != LandLakes.atollTemplateOption)
	}

	@Test func theFixtureHasCellForCellMapsAndEveryLimitIncludingTheSentinel() throws {
		let f = try fixture()
		#expect(f.fulls.count == 2 && f.fulls.allSatisfy { $0.heights != nil })
		for c in f.fulls {
			let grid = try GridPoints.generate(seed: c.seed, width: c.width, height: c.height, cellsDesired: c.cellsDesired)
			let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
			let expected = Result(key: c.key, limit: c.limit, templateOption: c.templateOption, before: c.before, lakesFound: c.lakesFound, afterDepressions: c.afterDepressions, afterOpening: c.afterOpening, heights: c.heights, distance: c.distance, featureIds: c.featureIds)
			_ = try compare(expected, seed: c.seed, grid: grid, voronoi: voronoi, label: "full \(c.key) \(c.seed)")
		}
		let limits = Set(f.runs.flatMap { $0.results.map(\.limit) })
		#expect(limits == [0, 5, 20, 35, 80])
		// the sentinel: at 80 the original finds no depression lakes at all
		for run in f.runs { for r in run.results where r.limit == 80 { #expect(r.lakesFound.isEmpty) } }
	}

	// MARK: hand-made cases

	func island(seed: String = "k") throws -> (GridPoints, VoronoiDiagram) {
		let grid = try GridPoints.generate(seed: seed, width: 400, height: 300, cellsDesired: 600)
		return (grid, try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary))
	}

	@Test func aDeepDepressionBecomesALakeAndItsShoreBecomesCoast() throws {
		let (grid, voronoi) = try island()
		// flat land at 60 with one interior cell dug to 25 (a land cell lower than every neighbour, deep: the surroundings are 60)
		let pit = try #require(voronoi.cells.b.indices.first { voronoi.cells.b[$0] == 0 })
		var heights = [Height](repeating: 60, count: grid.points.count)
		heights[pit] = 25
		var features = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		try LandLakes.addDeepDepressionLakes(heights: &heights, features: &features, voronoi: voronoi, elevationLimit: 20)
		#expect(heights[pit] == 19)
		#expect(features.distanceField[pit] == -1)
		#expect(features.feature(Int(features.featureIds[pit]))?.kind == .lake)
		#expect(features.features.last == Feature(id: features.features.count, land: false, border: false, kind: .lake))
		for n in voronoi.cells.c[pit] { #expect(features.distanceField[n] == 1) }
		// the same map with the limit at 80 gets no lake
		var h2 = [Height](repeating: 60, count: grid.points.count)
		h2[pit] = 25
		var f2 = try LandFeatures.markup(heights: h2, voronoi: voronoi)
		let countBefore = f2.features.count
		try LandLakes.addDeepDepressionLakes(heights: &h2, features: &f2, voronoi: voronoi, elevationLimit: 80)
		#expect(f2.features.count == countBefore && h2[pit] == 25)
	}

	@Test func aLakeBesideTheSeaOpensIntoItAndKeepsItsRecordWithKindOcean() throws {
		let (grid, voronoi) = try island()
		// built from the graph: a low coast cell C touching a one-cell lake L and an ocean cell O (O and L are not neighbours),
		// with the ocean a water path from O to the map's edge that stays clear of L and its neighbours
		let n = voronoi.cells.c
		var chosen: (c: Int, lake: Int, ocean: Int, path: [Int])?
		search: for c in n.indices where voronoi.cells.b[c] == 0 && n[c].count >= 5 && n[c].allSatisfy({ voronoi.cells.b[$0] == 0 }) {
			for lake in n[c] {
				for ocean in n[c] where ocean != lake && !n[lake].contains(ocean) {
					let blocked = Set(n[lake] + [lake, c])
					guard !blocked.contains(ocean) else { continue }
					// breadth-first from the ocean cell to any border cell, avoiding blocked cells
					var previous: [Int: Int] = [ocean: -1]
					var queue = [ocean]
					var head = 0
					var edge: Int?
					while head < queue.count, edge == nil {
						let q = queue[head]; head += 1
						if voronoi.cells.b[q] != 0 { edge = q; break }
						for m in n[q] where !blocked.contains(m) && previous[m] == nil { previous[m] = q; queue.append(m) }
					}
					if let edge {
						var path: [Int] = [], at = edge
						while at != -1 { path.append(at); at = previous[at]! }
						chosen = (c, lake, ocean, path)
						break search
					}
				}
			}
		}
		let plan = try #require(chosen)
		var heights = [Height](repeating: 60, count: grid.points.count)
		for cell in plan.path { heights[cell] = 5 } // the ocean
		heights[plan.lake] = 8 // the lake
		heights[plan.c] = 21 // the low coast between them
		var features = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		let lakeIds = features.features.filter { $0.kind == .lake }.map(\.id)
		try #require(!lakeIds.isEmpty)
		let opened = lakeIds[0]
		let recordBefore = features.features[opened - 1]
		try LandLakes.openNearSeaLakes(heights: &heights, features: &features, voronoi: voronoi, templateOption: "continents")
		let record = features.features[opened - 1]
		// a low coast cell touches both the lake and the ocean, so the lake opens: the record keeps `land` and `border`, only
		// the kind changed, and the lake's cells took the ocean's number
		#expect(record.kind == .ocean)
		#expect(record.land == recordBefore.land && record.border == recordBefore.border && record.id == opened)
		#expect(record.border == false) // an "ocean" that does not touch the edge: not what a re-marking would give
		#expect(features.featureIds.contains { Int($0) == opened } == false)
		#expect(try LandLakes.apply(heights: heights, features: features, voronoi: voronoi, elevationLimit: 20, templateOption: "Atoll").heights.count == heights.count)
	}

	@Test func inconsistentOrUnsafeInputIsRefused() throws {
		let (grid, voronoi) = try island()
		var heights = [Height](repeating: 60, count: grid.points.count)
		var features = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		for bad in [-1.0, .nan, .infinity] {
			#expect(throws: LandLakesError.invalidElevationLimit) { try LandLakes.addDeepDepressionLakes(heights: &heights, features: &features, voronoi: voronoi, elevationLimit: bad) }
		}
		var short = Array(heights.dropLast())
		#expect(throws: LandLakesError.inconsistentInput) { try LandLakes.addDeepDepressionLakes(heights: &short, features: &features, voronoi: voronoi, elevationLimit: 20) }
		var wrong = features
		wrong.featureIds[0] = 99 // not a feature of the table
		#expect(throws: LandLakesError.inconsistentInput) { try LandLakes.openNearSeaLakes(heights: &heights, features: &wrong, voronoi: voronoi, templateOption: "x") }
	}
}
