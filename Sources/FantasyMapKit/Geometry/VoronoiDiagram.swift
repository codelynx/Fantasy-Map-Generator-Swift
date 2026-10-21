// Ported from the original's src/generators/voronoi.ts (Azgaar's Fantasy Map Generator, MIT; see ACKNOWLEDGEMENTS.md),
// read at commit 8936c9c: the `Voronoi` class and `calculateVoronoi`. The Voronoi cells are derived from a Delaunay
// triangulation; the order of every list below is the triangulation's order, and later stages depend on it.

import Foundation

/// Why the Voronoi diagram could not be made.
public enum VoronoiDiagramError: Error, Equatable, Sendable {
	/// More points than `VoronoiDiagram.maximumInputPoints` (cell points plus boundary points together).
	case tooManyPoints
	/// The triangulation refused the points (a non-finite or oversized coordinate, or an unsupported degenerate input).
	case triangulation(DelaunayError)
	/// A Voronoi vertex (a triangle's circumcenter) is not a finite number, because a triangle is nearly collinear. The
	/// original would return NaN or infinity as a vertex; this port reports it instead.
	case nonFiniteGeometry
	/// The points did not triangulate (fewer than three, all collinear, or all duplicates).
	case degenerate
}

/// The Voronoi cells and vertices of the grid points, clipped by the boundary points.
public struct VoronoiDiagram: Equatable, Sendable {
	/// The cells, one per cell point. The original's `cells`.
	public struct Cells: Equatable, Sendable {
		/// For each cell, the Voronoi vertices (triangle indices) around it, in the original's order.
		public var v: [[Int]]
		/// For each cell, its neighbouring cells, in the original's order (boundary points are not cells and are left out).
		public var c: [[Int]]
		/// For each cell, 1 if it touches the map edge (a neighbour was a boundary point or the hull), else 0.
		public var b: [Int]
		/// The cell indices, 0 ..< number of cell points.
		public var i: [Int]
	}

	/// The Voronoi vertices, one per triangle. The original's `vertices`.
	public struct Vertices: Equatable, Sendable {
		/// The vertex coordinates (each triangle's circumcenter).
		public var p: [Point]
		/// For each vertex, the three adjacent vertices; -1 where the triangle's edge is on the convex hull.
		public var v: [[Int]]
		/// For each vertex, the three cells (points, boundary points included) that meet there.
		public var c: [[Int]]
	}

	public var cells: Cells
	public var vertices: Vertices
	/// The cell points and boundary points the diagram was built from (shared with the caller's arrays, not copied), so a
	/// later stage can check that a diagram belongs to the grid it is given.
	public let cellPoints: [Point]
	public let boundaryPoints: [Point]

	/// A provisional safety ceiling on the **combined** cell points and boundary points given to the triangulation, which
	/// also bounds its working arrays (about twenty arrays of this length). Not a performance claim.
	public static let maximumInputPoints = Delaunay.maximumPoints

	/// Builds the diagram from the cell points and the boundary pseudo-points, as the original's `calculateVoronoi` does:
	/// the boundary points are appended after the cell points, the whole set is triangulated, and only the cell points get cells.
	public static func calculate(points: [Point], boundary: [Point]) throws -> VoronoiDiagram {
		guard points.count + boundary.count <= maximumInputPoints else { throw VoronoiDiagramError.tooManyPoints }
		let allPoints = points + boundary
		let delaunay: Delaunay
		do { delaunay = try Delaunay(points: allPoints) } catch let error as DelaunayError { throw VoronoiDiagramError.triangulation(error) }
		guard !delaunay.triangles.isEmpty else { throw VoronoiDiagramError.degenerate }
		return try VoronoiDiagram(delaunay: delaunay, points: allPoints, pointsCount: points.count, cellPoints: points, boundaryPoints: boundary)
	}

	private init(delaunay: Delaunay, points: [Point], pointsCount: Int, cellPoints: [Point], boundaryPoints: [Point]) throws {
		self.cellPoints = cellPoints
		self.boundaryPoints = boundaryPoints
		let triangles = delaunay.triangles
		let halfedges = delaunay.halfedges
		let triangleCount = triangles.count / 3

		// where the original's arrays are sparse (a cell no triangle reached), these stay empty
		var cellV = [[Int]](repeating: [], count: pointsCount)
		var cellC = [[Int]](repeating: [], count: pointsCount)
		var cellB = [Int](repeating: 0, count: pointsCount)
		var cellSet = [Bool](repeating: false, count: pointsCount)
		var vertexP = [Point](repeating: Point(x: 0, y: 0), count: triangleCount)
		var vertexV = [[Int]](repeating: [], count: triangleCount)
		var vertexC = [[Int]](repeating: [], count: triangleCount)
		var vertexSet = [Bool](repeating: false, count: triangleCount)

		// `Math.floor(e / 3)`: for the twin of a hull half-edge (-1) this is -1, where integer division would give 0
		func triangleOfEdge(_ e: Int) -> Int { Int((Double(e) / 3).rounded(.down)) }
		func nextHalfedge(_ e: Int) -> Int { e % 3 == 2 ? e - 2 : e + 1 }
		func edgesOfTriangle(_ t: Int) -> [Int] { [3 * t, 3 * t + 1, 3 * t + 2] }
		func pointsOfTriangle(_ t: Int) -> [Int] { edgesOfTriangle(t).map { triangles[$0] } }
		func trianglesAdjacentToTriangle(_ t: Int) -> [Int] {
			edgesOfTriangle(t).map { triangleOfEdge(halfedges[$0]) }
		}
		func edgesAroundPoint(_ start: Int) -> [Int] {
			var result: [Int] = []
			var incoming = start
			repeat {
				result.append(incoming)
				let outgoing = nextHalfedge(incoming)
				incoming = halfedges[outgoing]
			} while incoming != -1 && incoming != start && result.count < 20
			return result
		}
		func circumcenter(_ a: Point, _ b: Point, _ c: Point) -> Point {
			let ad = a.x * a.x + a.y * a.y
			let bd = b.x * b.x + b.y * b.y
			let cd = c.x * c.x + c.y * c.y
			let D = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
			return Point(
				x: (1 / D) * (ad * (b.y - c.y) + bd * (c.y - a.y) + cd * (a.y - b.y)),
				y: (1 / D) * (ad * (c.x - b.x) + bd * (a.x - c.x) + cd * (b.x - a.x))
			)
		}

		for e in 0..<triangles.count {
			let p = triangles[nextHalfedge(e)]
			if p < pointsCount && !cellSet[p] {
				let edges = edgesAroundPoint(e)
				cellV[p] = edges.map(triangleOfEdge) // cell: adjacent vertex
				cellC[p] = edges.map { triangles[$0] }.filter { $0 < pointsCount } // cell: adjacent valid cells
				cellB[p] = edges.count > cellC[p].count ? 1 : 0 // cell: is border
				cellSet[p] = true
			}

			let t = triangleOfEdge(e)
			if !vertexSet[t] {
				let corners = pointsOfTriangle(t).map { points[$0] }
				let center = circumcenter(corners[0], corners[1], corners[2])
				guard center.x.isFinite, center.y.isFinite else { throw VoronoiDiagramError.nonFiniteGeometry }
				vertexP[t] = center // vertex: coordinates
				vertexV[t] = trianglesAdjacentToTriangle(t) // vertex: adjacent vertices
				vertexC[t] = pointsOfTriangle(t) // vertex: adjacent cells
				vertexSet[t] = true
			}
		}

		cells = Cells(v: cellV, c: cellC, b: cellB, i: Array(0..<pointsCount))
		vertices = Vertices(p: vertexP, v: vertexV, c: vertexC)
	}
}
