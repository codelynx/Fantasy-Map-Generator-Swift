import CryptoKit
import Foundation
import Testing
@testable import FantasyMapKit

/// Water chain, stage 4: the packed graph, compared EXACTLY with fixtures captured from the original's own `Pack.generate`
/// (Fixtures/original/pack-original.json), which runs after the original's own grid, heightmap, lake steps.
struct PackedMapTests {
	struct Hashes: Decodable { var p, g, h, area, v, c, b, vp, vv, vc: String }
	struct Whole: Decodable { var p: [[Double]], g: [Int], h: [Int], area: [Int], v: [[Int]], c: [[Int]], b: [Int], vp: [[Double]], vv: [[Int]], vc: [[Int]] }
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, gridCells: Int, cells: Int, vertices: Int, maxArea: Int?
		var sha: Hashes, whole: Whole?
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("pack-original")).runs }

	func map(_ r: Run) throws -> LandMap {
		try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
	}

	// the hashes the capture script makes: Float64 points, Int32 rows (length, then items), Int32 lists; all little-endian
	func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
	func points(_ values: [Point]) -> String {
		var data = Data()
		for p in values { for v in [p.x, p.y] { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } } }
		return hash(data)
	}
	func ints(_ values: [Int]) -> String {
		var data = Data()
		for v in values { withUnsafeBytes(of: Int32(v).littleEndian) { data.append(contentsOf: $0) } }
		return hash(data)
	}
	func rows(_ values: [[Int]]) -> String { ints(values.flatMap { [$0.count] + $0 }) }

	func hashes(_ m: PackedMap) -> Hashes {
		Hashes(p: points(m.points), g: ints(m.gridCell), h: ints(m.heights.map(Int.init)), area: ints(m.areas.map(Int.init)),
			v: rows(m.voronoi.cells.v), c: rows(m.voronoi.cells.c), b: ints(m.voronoi.cells.b), vp: points(m.voronoi.vertices.p), vv: rows(m.voronoi.vertices.v), vc: rows(m.voronoi.vertices.c))
	}

	@Test func theWholePackedGraphMatchesTheOriginal() throws {
		let all = try runs()
		var wrong: [String] = [], wholeWrong = 0, whole = 0
		for r in all {
			let m = try map(r)
			let packed = try PackedMap.generate(for: m)
			let h = hashes(packed), e = r.sha
			let same = packed.points.count == r.cells && packed.voronoi.vertices.p.count == r.vertices && m.heights.count == r.gridCells
				&& h.p == e.p && h.g == e.g && h.h == e.h && h.area == e.area && h.v == e.v && h.c == e.c && h.b == e.b && h.vp == e.vp && h.vv == e.vv && h.vc == e.vc
			if !same { wrong.append("\(r.seed)/\(r.key)/\(r.cellsDesired)") }
			if let w = r.whole {
				whole += 1
				let ok = packed.points == w.p.map { Point(x: $0[0], y: $0[1]) } && packed.gridCell == w.g && packed.heights.map(Int.init) == w.h && packed.areas.map(Int.init) == w.area
					&& packed.voronoi.cells.v == w.v && packed.voronoi.cells.c == w.c && packed.voronoi.cells.b == w.b
					&& packed.voronoi.vertices.p == w.vp.map { Point(x: $0[0], y: $0[1]) } && packed.voronoi.vertices.v == w.vv && packed.voronoi.vertices.c == w.vc
				if !ok { wholeWrong += 1 }
			}
		}
		#expect(all.count == 98 && whole == 28)
		#expect(wrong.isEmpty, "differ from the original: \(wrong.prefix(5))")
		#expect(wholeWrong == 0, "\(wholeWrong) of the \(whole) whole graphs differ")
	}

	@Test func theCapturedRunsCoverTheBranchesOfTheOriginal() throws {
		let all = try runs()
		#expect(all.contains { $0.cells == 0 }, "a map with no packed cell at all (all deep ocean) is present")
		#expect(all.contains { $0.cells > $0.gridCells }, "coastal splitting makes more packed cells than grid cells")
		#expect(all.contains { $0.cells < $0.gridCells / 2 }, "deep ocean dropping makes far fewer")
		#expect(Set(all.map(\.cellsDesired)).count >= 5)
	}

	// MARK: structure of a packed graph, derived from the map independently of the code under test

	func small() throws -> (LandMap, PackedMap) {
		let m = try LandMap.generate(seed: "kaz-1", width: 640, height: 400, cellsDesired: 600, template: try #require(HeightmapTemplate.named("archipelago")))
		return (m, try PackedMap.generate(for: m))
	}

	@Test func packedCellsKeepTheGridsOrderHeightsAndPoints() throws {
		let (m, p) = try small()
		let n = p.points.count
		#expect(p.gridCell.count == n && p.heights.count == n && p.areas.count == n && p.voronoi.cells.v.count == n)
		#expect(p.gridCell == p.gridCell.sorted(), "packed cells follow the grid's cell order")
		for (cell, g) in p.gridCell.enumerated() { #expect(p.heights[cell] == m.heights[g], "the packed height is the grid cell's") }
		// a grid cell's first packed cell is at its own point; the others are rounded midpoints with a neighbour
		var seen = Set<Int>()
		for (cell, g) in p.gridCell.enumerated() {
			if seen.insert(g).inserted { #expect(p.points[cell] == m.grid.points[g]) } else {
				let q = p.points[cell]
				#expect(m.voronoi.cells.c[g].contains { e in JSNumber.rn((m.grid.points[g].x + m.grid.points[e].x) / 2, 1) == q.x && JSNumber.rn((m.grid.points[g].y + m.grid.points[e].y) / 2, 1) == q.y })
			}
		}
	}

	@Test func deepOceanIsDroppedAndLakeCellsAreThinned() throws {
		let (m, p) = try small()
		let d = m.features.distanceField
		let kept = Set(p.gridCell)
		for i in 0..<m.heights.count {
			let t = d[i]
			if m.heights[i] < Heights.seaLevel && t != -1 && t != -2 { #expect(!kept.contains(i), "deep water \(i) is dropped") }
			if t == -2 && (i % 4 == 0 || m.features.feature(Int(m.features.featureIds[i]))?.kind == .lake) { #expect(!kept.contains(i), "inland lake cell \(i) is dropped") }
			if m.heights[i] >= Heights.seaLevel { #expect(kept.contains(i), "land cell \(i) is kept") }
		}
		#expect(kept.count < m.heights.count)
	}

	@Test func onlyCoastalCellsAwayFromTheBorderAreSplit() throws {
		let (m, p) = try small()
		var count = [Int: Int]()
		for g in p.gridCell { count[g, default: 0] += 1 }
		var split = 0
		for (g, k) in count where k > 1 {
			split += 1
			#expect(abs(Int(m.features.distanceField[g])) == 1 && m.voronoi.cells.b[g] == 0, "cell \(g) is split but is not a coast cell away from the border")
		}
		#expect(split > 0)
	}

	// MARK: the area, the budget

	@Test func areaIsTheShoelaceAreaCappedAndStoredAsAnUnsignedSixteenBit() {
		func square(_ side: Double) -> [Point] { [Point(x: 0, y: 0), Point(x: side, y: 0), Point(x: side, y: side), Point(x: 0, y: side)] }
		// d3's sum is a[1] * b[0] - a[0] * b[1]: this counter-clockwise (in y-up terms) square gives a negative sum, taken absolute
		#expect(PackedMap.polygonArea(square(2)) == -4 && PackedMap.storedArea(square(2)) == 4)
		#expect(PackedMap.polygonArea(square(2).reversed()) == 4)
		#expect(PackedMap.polygonArea([]) == 0 && PackedMap.storedArea([]) == 0)
		#expect(PackedMap.polygonArea([Point(x: 1, y: 1)]) == 0, "a single point")
		#expect(PackedMap.polygonArea([Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 0, y: 3)]) == -6)
		#expect(PackedMap.storedArea(square(255)) == 65025, "below the cap")
		#expect(PackedMap.storedArea(square(256)) == 65535, "at 65536 the cap holds the value at 65535 and does not wrap to 0")
		#expect(PackedMap.storedArea(square(1000)) == 65535)
		#expect(PackedMap.storedArea(square(0.9)) == 0, "a fractional area truncates toward zero")
		#expect(PackedMap.storedArea([Point(x: 0, y: 0), Point(x: 3.5, y: 0), Point(x: 3.5, y: 3.5), Point(x: 0, y: 3.5)]) == 12, "12.25 stores as 12")
		#expect(PackedMap.storedArea(square(.nan)) == 0, "not a number stores as 0, as a typed array does")
	}

	// MARK: the coast-splitting rule on hand data

	/// Two coast cells (distance 1, away from the border, neighbours of each other) `gap` apart at a spacing of 10, both land.
	func split(gap: Double, type: Int8 = 1, border: [Int] = [0, 0]) throws -> (points: [Point], gridCell: [Int], heights: [Height]) {
		try PackedMap.selectPoints(points: [Point(x: 0, y: 0), Point(x: gap, y: 0)], spacing: 10, heights: [30, 40], distance: [type, type], neighbours: [[1], [0]], border: border, limit: 100, isLake: { _ in false })
	}

	@Test func aCoastNeighbourExactlyOneSpacingAwayIsSplitAndACloserOneIsNot() throws {
		// the rule skips a pair whose squared distance is below the squared spacing, so exactly one spacing away is admitted
		#expect(try split(gap: 10).points == [Point(x: 0, y: 0), Point(x: 5, y: 0), Point(x: 10, y: 0)], "exactly one spacing: the midpoint is added")
		#expect(try split(gap: 10).gridCell == [0, 0, 1], "the midpoint belongs to the lower-numbered cell")
		#expect(try split(gap: 10).heights == [30, 30, 40], "and has its height")
		#expect(try split(gap: 9.99).points.count == 2, "just under one spacing: too close")
		#expect(try split(gap: 10.01).points.count == 3)
	}

	@Test func theMidpointIsRoundedToOneDecimal() throws {
		#expect(try split(gap: 10.3).points[1] == Point(x: 5.2, y: 0), "5.15 rounds half up to 5.2")
		#expect(try split(gap: 10.34).points[1].x == 5.2, "5.17")
	}

	@Test func borderCellsAndUnlikeNeighboursAreNotSplit() throws {
		#expect(try split(gap: 20, border: [1, 0]).points.count == 2, "a near-border cell adds no point")
		#expect(try split(gap: 20, border: [0, 1]).points.count == 3, "only the cell that would add it is asked: the lower-numbered one")
		let unlike = try PackedMap.selectPoints(points: [Point(x: 0, y: 0), Point(x: 20, y: 0)], spacing: 10, heights: [30, 10], distance: [1, -1], neighbours: [[1], [0]], border: [0, 0], limit: 100, isLake: { _ in false })
		#expect(unlike.points.count == 2, "a land coast and a water coast cell are not paired")
		#expect(try split(gap: 20, type: 5).points.count == 2, "a cell inland of the coast adds none")
	}

	@Test func theUnsignedSixteenBitStoreTruncatesAndWraps() {
		#expect([0, 1.9, 65535, 65536, 65537.5, -1, -1.5, .nan, .infinity].map { JSNumber.toUInt16($0) } == [0, 1, 65535, 0, 1, 65535, 65535, 0, 0])
	}

	@Test func thePointBudgetIsEnforcedWhileThePointsAreAdded() throws {
		let (m, p) = try small()
		let total = p.points.count + m.grid.boundary.count
		#expect(try PackedMap.generate(for: m, maximumPoints: total) == p, "a ceiling of exactly the number of points is allowed")
		#expect(throws: PackedMap.Problem.tooManyPoints) { try PackedMap.generate(for: m, maximumPoints: total - 1) }
		#expect(throws: PackedMap.Problem.tooManyPoints) { try PackedMap.generate(for: m, maximumPoints: m.grid.boundary.count) }
	}

	@Test func theBudgetHoldsForTheLargestSupportedGrid() throws {
		// the packed graph has at most one point per grid cell plus one per coastal neighbour pair, a planar graph's edges: under 4 x cells
		// (and a coast cell has at most a handful), so even the biggest density step stays far under the ceiling
		let m = try LandMap.generate(seed: "budget", width: 1280, height: 800, cellsDesired: 100_000, template: try #require(HeightmapTemplate.named("archipelago")))
		let p = try PackedMap.generate(for: m)
		#expect(p.points.count + m.grid.boundary.count <= VoronoiDiagram.maximumInputPoints)
		#expect(p.points.count < 4 * m.heights.count)
	}
}
