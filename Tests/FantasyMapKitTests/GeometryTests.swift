import CryptoKit
import Foundation
import Testing
@testable import FantasyMapKit

/// Step 3 of docs/plans/land-layer.md: orient2d, Delaunator and the Voronoi cells, against the original's own output.
struct GeometryTests {
	// MARK: orient2d

	struct OrientFixture: Decodable {
		struct Case: Decodable {
			var ax, ay, bx, by, cx, cy, value: Double
			var branch: Int?
		}
		var cases: [Case]
		var branchCases: [Case]
		var permutations: [Case]
		var collinear: [Case]
		var convention: Case
	}

	func orient(_ c: OrientFixture.Case) -> (value: Double, branch: Int) {
		RobustPredicates.orient2dTraced(c.ax, c.ay, c.bx, c.by, c.cx, c.cy)
	}

	@Test func orient2dMatchesRobustPredicatesForEveryCase() throws {
		let fixture = try JSONDecoder().decode(OrientFixture.self, from: Fixtures.data("orient2d"))
		#expect(fixture.cases.count == 167)
		for c in fixture.cases + fixture.branchCases + fixture.permutations + fixture.collinear {
			let got = orient(c).value
			#expect(got == c.value, "case \(c)") // exact, and a zero compares equal to a zero
		}
	}

	@Test func everyReturnPointOfOrient2dIsReachedAndMatchesTheOriginal() throws {
		let fixture = try JSONDecoder().decode(OrientFixture.self, from: Fixtures.data("orient2d"))
		// found by running an instrumented copy of the library's source; here the port must reach the same branch
		var reached = Set<Int>()
		for c in fixture.branchCases + fixture.permutations + fixture.collinear {
			let expected = try #require(c.branch)
			let got = orient(c)
			#expect(got.branch == expected, "branch for \(c)")
			reached.insert(got.branch)
		}
		#expect(reached == [0, 1, 2, 3, 4], "branches reached: \(reached.sorted())")
		#expect(fixture.branchCases.filter { $0.branch == 4 }.count >= 6) // the full exact sum, the deepest path
	}

	@Test func orient2dKeepsTheOriginalsSignConventionAndFlipsOnOddPermutations() throws {
		let fixture = try JSONDecoder().decode(OrientFixture.self, from: Fixtures.data("orient2d"))
		// pinned: the original gives -1 for (0,0), (1,0), (0,1); a globally reversed port would give +1
		#expect(fixture.convention.value == -1)
		#expect(RobustPredicates.orient2d(0, 0, 1, 0, 0, 1) == -1)
		#expect(RobustPredicates.orient2d(0, 0, 0, 1, 1, 0) == 1) // an odd permutation flips the sign
		#expect(RobustPredicates.orient2d(0, 0, 1, 1, 2, 2) == 0) // exactly collinear
		// the exactly collinear fixtures give zero in every order
		for c in fixture.collinear { #expect(orient(c).value == 0, "collinear \(c)") }
	}

	// MARK: Delaunator

	struct GridFixture: Decodable {
		struct Grid: Decodable {
			var seed: String
			var points: [Point]
			var boundary: [Point]
			var triangles: [Int]
			var halfedges: [Int]
			var hull: [Int]
		}
		var grids: [Grid]
	}

	@Test func delaunayMatchesDelaunatorsTrianglesHalfedgesAndHullInOrder() throws {
		let grids = try JSONDecoder().decode(GridFixture.self, from: Fixtures.data("grid")).grids
		#expect(grids.count == 3)
		for grid in grids {
			let delaunay = try Delaunay(points: grid.points + grid.boundary)
			#expect(delaunay.triangles == grid.triangles, "triangles, seed \(Array(grid.seed.utf16))")
			#expect(delaunay.halfedges == grid.halfedges, "half-edges, seed \(Array(grid.seed.utf16))")
			#expect(delaunay.hull == grid.hull, "hull, seed \(Array(grid.seed.utf16))")
		}
	}

	@Test func theTriangulationIsStructurallySound() throws {
		var points: [Point] = []
		for i in 0..<200 {
			let x: Double = Double((i * 37) % 101) + Double(i % 7) * 0.13
			let y: Double = Double((i * 53) % 97) + Double(i % 5) * 0.11
			points.append(Point(x: x, y: y))
		}
		let d = try Delaunay(points: points)
		#expect(d.triangles.count % 3 == 0 && !d.triangles.isEmpty)
		#expect(d.triangles.count == d.halfedges.count)
		for (e, twin) in d.halfedges.enumerated() where twin != -1 { #expect(d.halfedges[twin] == e) } // twins are mutual
		#expect(d.hull.count >= 3)
		#expect(d.triangles.allSatisfy { $0 >= 0 && $0 < points.count })
	}

	@Test func degenerateInputsFollowTheOriginal() throws {
		let empty = try Delaunay(points: [])
		#expect(empty.triangles.isEmpty && empty.hull.isEmpty)
		let one = try Delaunay(points: [Point(x: 1, y: 2)])
		#expect(one.triangles.isEmpty && one.hull == [0])
		let two = try Delaunay(points: [Point(x: 1, y: 2), Point(x: 3, y: 4)])
		#expect(two.triangles.isEmpty && two.hull == [0, 1])
		// collinear points: the ordered line is the hull and there are no triangles
		let line = try Delaunay(points: [Point(x: 4, y: 4), Point(x: 0, y: 0), Point(x: 2, y: 2), Point(x: 1, y: 1)])
		#expect(line.triangles.isEmpty)
		#expect(line.hull == [1, 3, 2, 0])
		// duplicates are skipped, not failed on
		let dup = try Delaunay(points: [Point(x: 0, y: 0), Point(x: 0, y: 0), Point(x: 5, y: 0), Point(x: 0, y: 5), Point(x: 5, y: 5)])
		#expect(!dup.triangles.isEmpty)
	}

	@Test func theInputBoundaryRefusesWhatCouldTurnIntoAnUnsafeIndexOrAllocation() throws {
		#expect(throws: DelaunayError.nonFiniteCoordinate) { try Delaunay(points: [Point(x: .nan, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 0)]) }
		#expect(throws: DelaunayError.nonFiniteCoordinate) { try Delaunay(coords: [0, 0, .infinity, 1, 2, 0]) }
		#expect(throws: DelaunayError.coordinateTooLarge) { try Delaunay(coords: [0, 0, 1.0000001e9, 1, 2, 0]) }
		#expect(throws: DelaunayError.oddCoordinateCount) { try Delaunay(coords: [0, 0, 1, 1, 2]) }
		let huge = [Double](repeating: 0, count: (Delaunay.maximumPoints + 1) * 2)
		#expect(throws: DelaunayError.tooManyPoints) { try Delaunay(coords: huge) }
		// the largest magnitude accepted is within the supported range
		let big = try Delaunay(coords: [-1e9, -1e9, 1e9, -1e9, 0, 1e9, 1e8, 0])
		#expect(!big.triangles.isEmpty)
	}

	/// Scaling every coordinate by a power of two is exact in floating point (no overflow or underflow here), so a
	/// large-scale configuration must give the same triangulation as the ordinary-scale one, with no normalisation.
	@Test func aLargeScaleConfigurationGivesTheSameTriangulationAsTheOrdinaryScaleOne() throws {
		let grids = try JSONDecoder().decode(GridFixture.self, from: Fixtures.data("grid")).grids
		let scale = 4_194_304.0 // 2^22, so the largest coordinates (about 120) stay under the 1e9 limit
		for grid in grids {
			let all = grid.points + grid.boundary
			let big = all.map { Point(x: $0.x * scale, y: $0.y * scale) }
			#expect(big.allSatisfy { abs($0.x) <= Delaunay.maximumCoordinate && abs($0.y) <= Delaunay.maximumCoordinate })
			let ordinary = try Delaunay(points: all)
			let scaled = try Delaunay(points: big)
			#expect(scaled.triangles == ordinary.triangles && scaled.halfedges == ordinary.halfedges && scaled.hull == ordinary.hull, "seed \(Array(grid.seed.utf16))")
			let a = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
			let b = try VoronoiDiagram.calculate(points: grid.points.map { Point(x: $0.x * scale, y: $0.y * scale) }, boundary: grid.boundary.map { Point(x: $0.x * scale, y: $0.y * scale) })
			#expect(a.cells == b.cells && a.vertices.v == b.vertices.v && a.vertices.c == b.vertices.c, "cells, seed \(Array(grid.seed.utf16))")
			#expect(b.vertices.p == a.vertices.p.map { Point(x: $0.x * scale, y: $0.y * scale) }, "vertex points scale exactly")
		}
	}

	/// Found by search (see docs/steps/03): five nearly collinear points near 1.9e8, for which the triangulation has a
	/// triangle whose circumcenter, by the original's formula, is not finite. The original would return it as a vertex.
	@Test func nearlyCollinearInputWithANonFiniteCircumcenterIsReportedNotReturned() throws {
		let points = [
			Point(x: 193826680.5209982, y: 191970647.38926587), Point(x: 193804524.22186318, y: 192033338.24453223),
			Point(x: 194039010.37560847, y: 191369863.83317745), Point(x: 193980116.50459787, y: 191536502.9962029),
			Point(x: 194025018.04746446, y: 191409454.8773844)
		]
		let delaunay = try Delaunay(points: points) // the triangulation itself is fine, and in range
		#expect(delaunay.triangles == [3, 4, 2, 2, 0, 3, 3, 0, 4, 1, 0, 2]) // as the original gives it
		#expect(throws: VoronoiDiagramError.nonFiniteGeometry) { try VoronoiDiagram.calculate(points: points, boundary: []) }
	}

	@Test func aNonFiniteHashKeyIsReportedNotTrapped() {
		// a point exactly at the seed circumcenter gives 0 / 0; no finite input is known to reach this inside a
		// triangulation, so the function that decides it is tested directly
		#expect(Delaunay.hashKey(2, 2, cx: 2, cy: 2, hashSize: 5) == nil)
		#expect(Delaunay.hashKey(.infinity, 0, cx: 0, cy: 0, hashSize: 5) == nil)
		#expect(Delaunay.hashKey(3, 1, cx: 2, cy: 2, hashSize: 5) != nil)
		#expect(Delaunay.hashKey(1, 1, cx: 2, cy: 2, hashSize: 0) == nil)
		#expect(DelaunayError.unsupportedDegenerateInput != .tooManyPoints)
	}

	// MARK: Voronoi cells

	struct VoronoiFixture: Decodable {
		struct Grid: Decodable {
			var seed: String
			var width: Double
			var height: Double
			var cellsDesired: Int
			var points: [Point]
			var boundary: [Point]
			var cellStructureSha256: String
			var vertexCount: Int
			var vertexPointsSha256: String
			var vertexPointsFirst20: [Point]
			var cellNeighbours: [[Int]]?
			var cellVertices: [[Int]]?
			var cellBorder: [Int]?
			var vertexPoints: [Point]?
		}
		var grids: [Grid]
	}

	/// `JSON.stringify` of nested integer arrays, as the capture script hashes them.
	static func json(_ x: [[Int]]) -> String { "[" + x.map { "[" + $0.map(String.init).joined(separator: ",") + "]" }.joined(separator: ",") + "]" }
	static func json(_ x: [Int]) -> String { "[" + x.map(String.init).joined(separator: ",") + "]" }

	@Test func voronoiCellsMatchTheOriginalsOwnForEveryFixtureGrid() throws {
		let grids = try JSONDecoder().decode(VoronoiFixture.self, from: Fixtures.data("grid-original")).grids
		#expect(grids.count == 8)
		var fullCompared = 0
		for grid in grids {
			let label = "seed \(Array(grid.seed.utf16)) \(Int(grid.width))x\(Int(grid.height)) \(grid.cellsDesired)"
			let made = try GridPoints.generate(seed: grid.seed, width: grid.width, height: grid.height, cellsDesired: grid.cellsDesired)
			#expect(made.points == grid.points && made.boundary == grid.boundary, "\(label): the points feeding the cells")
			let diagram = try VoronoiDiagram.calculate(points: made.points, boundary: made.boundary)

			// the integer structure of every cell and vertex, by hash, for all eight grids
			let text = "[" + [Self.json(diagram.cells.c), Self.json(diagram.cells.v), Self.json(diagram.cells.b), Self.json(diagram.vertices.v), Self.json(diagram.vertices.c)].joined(separator: ",") + "]"
			let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
			#expect(hash == grid.cellStructureSha256, "\(label): cell structure hash")
			#expect(diagram.vertices.p.count == grid.vertexCount, "\(label): vertex count")
			#expect(Array(diagram.vertices.p.prefix(20)) == grid.vertexPointsFirst20, "\(label): first vertex points")

			// every vertex coordinate: SHA-256 over little-endian IEEE-754 bytes of x then y, in order (as the capture script hashes them)
			var bytes = Data()
			for p in diagram.vertices.p {
				#expect(p.x.isFinite && p.y.isFinite, "\(label): a vertex coordinate is not finite")
				withUnsafeBytes(of: p.x.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
				withUnsafeBytes(of: p.y.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
			}
			let coordinateHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
			#expect(coordinateHash == grid.vertexPointsSha256, "\(label): every vertex coordinate")

			// and field by field, in the original's order, where the fixture holds the full cells
			if let neighbours = grid.cellNeighbours, let vertices = grid.cellVertices, let border = grid.cellBorder, let vertexPoints = grid.vertexPoints {
				fullCompared += 1
				#expect(diagram.cells.c == neighbours, "\(label): ordered neighbours")
				#expect(diagram.cells.v == vertices, "\(label): cell vertices")
				#expect(diagram.cells.b == border, "\(label): border flags")
				#expect(diagram.vertices.p == vertexPoints, "\(label): all vertex points")
			}
		}
		#expect(fullCompared == 5) // the three tiny grids and the two odd aspect ratios
	}

	@Test func cellsAreConsistentWithTheirVertices() throws {
		let made = try GridPoints.generate(seed: "kaz-1", width: 200, height: 120, cellsDesired: 150)
		let d = try VoronoiDiagram.calculate(points: made.points, boundary: made.boundary)
		#expect(d.cells.i == Array(0..<made.points.count))
		for i in d.cells.i {
			#expect(d.cells.c[i].allSatisfy { $0 < made.points.count && $0 != i })
			for n in d.cells.c[i] { #expect(d.cells.c[n].contains(i), "neighbours are mutual") }
			#expect(d.cells.v[i].count >= 3)
		}
		// a hull half-edge's twin is -1, and the original's floor division makes that vertex -1, not 0
		#expect(d.vertices.v.contains { $0.contains(-1) })
	}

	@Test func theCombinedInputIsBudgetedAndDegenerateInputIsRefused() {
		let tooMany = [Point](repeating: Point(x: 0, y: 0), count: VoronoiDiagram.maximumInputPoints + 1)
		#expect(throws: VoronoiDiagramError.tooManyPoints) { try VoronoiDiagram.calculate(points: tooMany, boundary: []) }
		#expect(throws: VoronoiDiagramError.degenerate) { try VoronoiDiagram.calculate(points: [Point(x: 0, y: 0), Point(x: 1, y: 1)], boundary: [Point(x: 2, y: 2)]) }
		#expect(throws: VoronoiDiagramError.degenerate) { try VoronoiDiagram.calculate(points: [], boundary: []) }
		#expect(throws: VoronoiDiagramError.triangulation(.nonFiniteCoordinate)) { try VoronoiDiagram.calculate(points: [Point(x: .nan, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 0)], boundary: []) }
	}
}
