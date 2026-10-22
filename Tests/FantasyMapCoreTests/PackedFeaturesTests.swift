import Foundation
import Testing
@testable import FantasyMapCore

/// Water chain, stage 5: the packed graph's features (`markupPack`), compared EXACTLY with fixtures captured from the original's own
/// `Features.markupPack` (Fixtures/original/markup-pack-original.json), and the original's `clipPoly` (clip-original.json).
struct PackedFeaturesTests {
	struct Sha: Decodable { var t, f, haven, harbor: String }
	struct FeatureRecord: Decodable {
		var i: Int, type: String, land: Bool, border: Bool, cells: Int, firstCell: Int, area: Double, height: Double
		var vertices: Int, shoreline: Int, verticesSha: String, shorelineSha: String, verticesWhole: [Int]?, shorelineWhole: [Int]?
	}
	struct Whole: Decodable { var t: [Int], f: [Int], haven: [Int], harbor: [Int] }
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, cells: Int, empty: Bool
		var sha: Sha?, features: [FeatureRecord]?, maxHarbor: Int?, whole: Whole?
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("markup-pack-original")).runs }

	func packed(_ r: Run) throws -> (LandMap, PackedMap) {
		let m = try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
		return (m, try PackedMap.generate(for: m))
	}

	@Test func theFeaturesMatchTheOriginal() throws {
		let all = try runs()
		var wrong: [String] = [], wholeWrong = 0, whole = 0, features = 0
		for r in all {
			let (m, p) = try packed(r)
			let f = try PackedFeatures.markup(for: p, width: m.width, height: m.height)
			if r.empty {
				if !(p.points.isEmpty && f.features.isEmpty && f.distanceField.isEmpty && f.featureIds.isEmpty && f.haven.isEmpty && f.harbor.isEmpty) { wrong.append("empty \(r.seed)/\(r.key)") }
				continue
			}
			let sha = try #require(r.sha), records = try #require(r.features)
			var ok = f.distanceField.count == r.cells && Fixtures.hashInt32s(f.distanceField.map(Int.init)) == sha.t && Fixtures.hashInt32s(f.featureIds.map(Int.init)) == sha.f
				&& Fixtures.hashInt32s(f.haven) == sha.haven && Fixtures.hashInt32s(f.harbor.map(Int.init)) == sha.harbor && f.harbor.map(Int.init).max() == r.maxHarbor && f.features.count == records.count
			for (mine, theirs) in zip(f.features, records) {
				features += 1
				ok = ok && mine.id == theirs.i && mine.kind.rawValue == theirs.type && mine.land == theirs.land && mine.border == theirs.border && mine.cells == theirs.cells
					&& mine.firstCell == theirs.firstCell && mine.area == theirs.area && mine.height == theirs.height && mine.vertices.count == theirs.vertices && mine.shoreline.count == theirs.shoreline
					&& Fixtures.hashInt32s(mine.vertices) == theirs.verticesSha && Fixtures.hashInt32s(mine.shoreline) == theirs.shorelineSha
				if let v = theirs.verticesWhole, let s = theirs.shorelineWhole { ok = ok && mine.vertices == v && mine.shoreline == s }
			}
			if !ok { wrong.append("\(r.seed)/\(r.key)/\(r.cellsDesired)") }
			if let w = r.whole {
				whole += 1
				if f.distanceField.map(Int.init) != w.t || f.featureIds.map(Int.init) != w.f || f.haven != w.haven || f.harbor.map(Int.init) != w.harbor { wholeWrong += 1 }
			}
		}
		#expect(all.count == 98 && whole > 15 && features > 900)
		#expect(wrong.isEmpty, "differ from the original: \(wrong.prefix(5))")
		#expect(wholeWrong == 0, "\(wholeWrong) of the \(whole) whole arrays differ")
	}

	@Test func theCapturedRunsCoverTheBranchesOfTheOriginal() throws {
		let all = try runs()
		let features = all.flatMap { $0.features ?? [] }
		#expect(all.contains { $0.empty }, "a map with no packed cell: the original marks nothing")
		#expect(features.contains { $0.type == "ocean" } && features.contains { $0.type == "island" } && features.contains { $0.type == "lake" })
		#expect(features.contains { $0.type == "lake" && $0.shoreline > 0 })
		#expect(all.contains { ($0.maxHarbor ?? 0) >= 3 }, "cells with several water neighbours")
		#expect(features.contains { $0.type == "island" && $0.border } && features.contains { $0.type == "island" && !$0.border })
	}

	// MARK: the original's clipPoly (lineclip 2.0.0's clipPolygon)

	struct Case: Decodable { var width: Double, height: Double, points: [[Double]], clipped: [[Double]] }

	@Test func clippingMatchesTheOriginalExactly() throws {
		struct File: Decodable { var cases: [Case] }
		let cases = try JSONDecoder().decode(File.self, from: Fixtures.data("clip-original")).cases
		var wrong = 0
		for c in cases {
			let mine = LineClip.clipPoly(c.points.map { Point(x: $0[0], y: $0[1]) }, width: c.width, height: c.height)
			if mine != c.clipped.map({ Point(x: $0[0], y: $0[1]) }) { wrong += 1 }
		}
		#expect(cases.count == 702)
		#expect(wrong == 0, "\(wrong) of \(cases.count) clipped polygons differ from the original")
	}

	@Test func clippingHandCases() {
		func pts(_ values: [(Double, Double)]) -> [Point] { values.map { Point(x: $0.0, y: $0.1) } }
		// a polygon inside is unchanged, fewer than two points are returned as they are, nothing outside leaves nothing
		let inside = pts([(10, 10), (90, 10), (50, 50)])
		#expect(LineClip.clipPoly(inside, width: 100, height: 60) == inside)
		#expect(LineClip.clipPoly([], width: 100, height: 60).isEmpty)
		#expect(LineClip.clipPoly(pts([(-5, -5)]), width: 100, height: 60) == pts([(-5, -5)]), "one point is returned even outside")
		#expect(LineClip.clipPoly(pts([(-5, -5), (-1, -5), (-1, -1)]), width: 100, height: 60).isEmpty)
		// a triangle half outside on the right: the crossings are found in the order of the ring: [100, 10] then [100, 30]
		#expect(LineClip.clipPoly(pts([(50, 10), (150, 10), (50, 50)]), width: 100, height: 60) == pts([(50, 10), (100, 10), (100, 30), (50, 50)]))
		// lineclip's inside test is inclusive on the edges: a point exactly on the border stays inside
		let onEdge = pts([(0, 0), (100, 0), (100, 60), (0, 60)])
		#expect(LineClip.clipPoly(onEdge, width: 100, height: 60) == onEdge)
	}

	// MARK: the ring walk (connectVertices) on hand-made vertices

	/// Four vertices in a cycle 0, 1, 2, 3, each touching one cell inside (100) and two outside (200).
	func cycle(_ v: [[Int]]) -> VoronoiDiagram.Vertices {
		VoronoiDiagram.Vertices(p: v.map { _ in Point(x: 0, y: 0) }, v: v, c: v.map { _ in [100, 200, 200] })
	}
	let inside: (Int) -> Bool = { $0 == 100 }

	@Test func theRingWalkFollowsTheBorderAndCloses() {
		let vertices = cycle([[1, 3, 3], [0, 2, 2], [1, 3, 3], [2, 0, 0]])
		#expect(VertexRing.connect(vertices: vertices, startingVertex: 0, ofSameType: inside, closeRing: false) == [0, 1, 2, 3])
		#expect(VertexRing.connect(vertices: vertices, startingVertex: 0, ofSameType: inside, closeRing: true) == [0, 1, 2, 3, 0])
	}

	@Test func theRingWalkStopsWhereTheOriginalStops() {
		// the next vertex is -1 (a hull edge): it stops and returns the ring so far
		#expect(VertexRing.connect(vertices: cycle([[-1, -1, -1], [0, 0, 0]]), startingVertex: 0, ofSameType: inside, closeRing: false) == [0])
		// the next vertex is outside the list
		#expect(VertexRing.connect(vertices: cycle([[5, 5, 5], [0, 0, 0]]), startingVertex: 0, ofSameType: inside, closeRing: false) == [0])
		// the next vertex is the current one: at the start, and further along the walk (vertex 1 leads only to itself)
		#expect(VertexRing.connect(vertices: cycle([[0, 0, 0], [0, 0, 0]]), startingVertex: 0, ofSameType: inside, closeRing: false) == [0])
		#expect(VertexRing.connect(vertices: cycle([[1, 1, 1], [1, 1, 1], [0, 0, 0]]), startingVertex: 0, ofSameType: inside, closeRing: false) == [0, 1])
		// a walk that never returns to its start stops after as many steps as there are vertices: 4 vertices, 5 entries
		let loop = cycle([[1, 1, 1], [2, 0, 0], [3, 1, 1], [1, 2, 2]])
		#expect(VertexRing.connect(vertices: loop, startingVertex: 0, ofSameType: inside, closeRing: false) == [0, 1, 2, 3, 1])
	}

	// MARK: markup on hand-made neighbours (the Voronoi geometry is a zigzag of six points; its neighbours are then replaced by a path)

	/// Six cells on a path 0-1-2-3-4-5 with the given heights and border flags; the rings are not asserted (their vertices come from the zigzag).
	func path(heights: [Height], border: [Int], neighbours: [[Int]]? = nil, areas: [UInt16] = [1, 2, 3, 4, 5, 6]) throws -> (PackedMap, PackedFeatures) {
		let points = (0..<6).map { Point(x: Double($0) * 10, y: $0 % 2 == 0 ? 0 : 5) }
		let boundary = [Point(x: -100, y: -100), Point(x: 200, y: -100), Point(x: 200, y: 100), Point(x: -100, y: 100)]
		var voronoi = try VoronoiDiagram.calculate(points: points, boundary: boundary)
		voronoi.cells.c = neighbours ?? (0..<6).map { i in [i - 1, i + 1].filter { $0 >= 0 && $0 < 6 } }
		voronoi.cells.b = border
		let packed = PackedMap(points: points, gridCell: Array(0..<6), heights: heights, areas: areas, voronoi: voronoi)
		return (packed, try PackedFeatures.markup(for: packed, width: 100, height: 60))
	}

	@Test func anOceanAnIslandAndALakeGetTheirDistancesAndHavens() throws {
		// water 0 (on the border), land 1-3, water 4-5 (not on the border): an ocean, an island and a lake
		let (_, f) = try path(heights: [10, 30, 30, 30, 10, 10], border: [1, 0, 0, 0, 0, 0])
		#expect(f.featureIds == [1, 2, 2, 2, 3, 3])
		#expect(f.features.map(\.kind) == [.ocean, .island, .lake])
		#expect(f.features.map(\.cells) == [1, 3, 2])
		#expect(f.features.map(\.border) == [true, false, false])
		#expect(f.features[0].area == 1, "an ocean's area is the sum of its cells' areas")
		#expect(f.distanceField == [-1, 1, 2, 1, -1, -2], "land coast 1, landlocked 2, water coast -1, the next water ring -2")
		#expect(f.harbor == [0, 1, 0, 1, 0, 0])
		#expect(f.haven[3] == 4)
		#expect(f.haven[1] == 0, "the water cell opposite cell 1 is cell 0, which the original cannot tell from no haven")
		#expect(f.features[2].firstCell == 4 && f.features[1].firstCell == 1, "a feature's first cell is on its border")
	}

	@Test func theHavenIsTheClosestWaterNeighbourAndTheFirstOfEquals() throws {
		// cell 1 sits at (10, 5) between water cells 0 and 2 at (0, 0) and (20, 0): both at squared distance 125, so the first listed wins
		let h: [Height] = [10, 30, 10, 10, 10, 10]
		let (_, a) = try path(heights: h, border: [1, 0, 0, 0, 0, 1], neighbours: [[1], [2, 0], [1, 3], [2, 4], [3, 5], [4]])
		#expect(a.haven[1] == 2 && a.harbor[1] == 2)
		let (_, b) = try path(heights: h, border: [1, 0, 0, 0, 0, 1], neighbours: [[1], [0, 2], [1, 3], [2, 4], [3, 5], [4]])
		#expect(b.haven[1] == 0 && b.harbor[1] == 2)
		// a closer neighbour wins over a listed-first farther one: cell 3 at (30, 5) is next to water 2 (20, 0) and 4 (40, 0)... made unequal by listing cell 5 (50, 5) first
		let (_, c) = try path(heights: [10, 10, 10, 30, 10, 10], border: [1, 0, 0, 0, 0, 1], neighbours: [[1], [0, 2], [1, 3], [5, 2, 4], [3, 5], [4, 3]])
		#expect(c.haven[3] == 2 || c.haven[3] == 4, "squared distances: cell 2 is 125 away, cell 4 is 125, cell 5 is 400")
		#expect(c.haven[3] == 2 && c.harbor[3] == 3, "the first of the two equally close cells in the list order [5, 2, 4]")
	}

	@Test func theWaterDistanceStopsAtMinusNine() throws {
		// a long water path from a coast: -1 at the coast, then -2 ... -9; farther cells stay 0 (the original's limit is -10)
		let n = 14
		let points = (0..<n).map { Point(x: Double($0) * 10, y: $0 % 2 == 0 ? 0 : 5) }
		var voronoi = try VoronoiDiagram.calculate(points: points, boundary: [Point(x: -100, y: -100), Point(x: 300, y: -100), Point(x: 300, y: 100), Point(x: -100, y: 100)])
		voronoi.cells.c = (0..<n).map { i in [i - 1, i + 1].filter { $0 >= 0 && $0 < n } }
		voronoi.cells.b = [Int](repeating: 0, count: n)
		let packed = PackedMap(points: points, gridCell: Array(0..<n), heights: [30] + [Height](repeating: 10, count: n - 1), areas: [UInt16](repeating: 1, count: n), voronoi: voronoi)
		let f = try PackedFeatures.markup(for: packed, width: 100, height: 60)
		#expect(f.distanceField.map(Int.init) == [1, -1, -2, -3, -4, -5, -6, -7, -8, -9, 0, 0, 0, 0])
	}

	@Test func landDistanceCountsRingsFromTheCoast() throws {
		// land 1-6 between water 0 and water 7. The flood marks "landlocked" (2) only from a cell already known as a coast cell when its
		// neighbour is looked at, in the stack order of the flood: cell 1 is a coast cell when cell 2 is reached, so cell 2 is 2; cell 6 is
		// not yet known as a coast when cell 5 is reached (its water neighbour is looked at after cell 5), so cell 5 stays unmarked and
		// the later ring pass numbers it 5, from the 2 at cell 2. That order dependence is the original's, kept
		let n = 8
		let points = (0..<n).map { Point(x: Double($0) * 10, y: $0 % 2 == 0 ? 0 : 5) }
		var voronoi = try VoronoiDiagram.calculate(points: points, boundary: [Point(x: -100, y: -100), Point(x: 300, y: -100), Point(x: 300, y: 100), Point(x: -100, y: 100)])
		voronoi.cells.c = (0..<n).map { i in [i - 1, i + 1].filter { $0 >= 0 && $0 < n } }
		voronoi.cells.b = [1] + [Int](repeating: 0, count: n - 1)
		let packed = PackedMap(points: points, gridCell: Array(0..<n), heights: [10, 30, 30, 30, 30, 30, 30, 10], areas: [UInt16](repeating: 1, count: n), voronoi: voronoi)
		let f = try PackedFeatures.markup(for: packed, width: 100, height: 60)
		#expect(f.distanceField.map(Int.init) == [-1, 1, 2, 3, 4, 5, 1, -1])
	}

	@Test func aLakesShorelineAndHeight() {
		// the shoreline lists each land cell once, in order of first appearance around the ring; boundary points (cell ids past the cells) are not land
		let vertices = VoronoiDiagram.Vertices(p: [], v: [], c: [[0, 1, 9], [1, 2, 3], [0, 3, 9]])
		let lake = PackedFeature(id: 1, kind: .lake, land: false, border: false, cells: 1, firstCell: 0, vertices: [0, 1, 2], area: 0, shoreline: [], height: 0)
		let heights: [Height] = [30, 25, 15, 40]
		let shore = PackedFeatures.shoreline(of: lake, vertices: vertices, isLand: { $0 >= 0 && $0 < heights.count && heights[$0] >= Heights.seaLevel })
		#expect(shore == [0, 1, 3], "cell 2 is water, cell 9 is a boundary point, and no cell repeats")
		var withShore = lake
		withShore.shoreline = shore
		#expect(PackedFeatures.lakeHeight(of: withShore, heights: heights) == 24.9, "the lowest shore cell is 25 less 0.1")
		withShore.shoreline = [0, 3]
		#expect(PackedFeatures.lakeHeight(of: withShore, heights: heights) == 29.9, "30 less 0.1")
		#expect(PackedFeatures.lakeHeight(of: lake, heights: heights) == 19.9, "a lake without a shore is 20 less 0.1")
		withShore.shoreline = [1]
		#expect(PackedFeatures.lakeHeight(of: withShore, heights: heights) == 24.9)
	}

	@Test func aPackedMapWithNoCellMarksNothing() throws {
		let points: [Point] = []
		let boundary = [Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 60), Point(x: 0, y: 60)]
		let packed = PackedMap(points: points, gridCell: [], heights: [], areas: [], voronoi: try VoronoiDiagram.calculate(points: points, boundary: boundary))
		let f = try PackedFeatures.markup(for: packed, width: 100, height: 60)
		#expect(f.features.isEmpty && f.distanceField.isEmpty && f.featureIds.isEmpty && f.haven.isEmpty && f.harbor.isEmpty)
	}
}
