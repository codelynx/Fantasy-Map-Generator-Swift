// Ported from Azgaar's Fantasy Map Generator, `src/generators/pack-generator.ts` (`generate`; the original at commit 8936c9c, 2026-10-19).
// The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md. `polygonArea` is a port
// of d3-polygon 3.0.1 (ISC, © Mike Bostock; the notice is in ACKNOWLEDGEMENTS.md).
//
// The packed graph: a second Voronoi diagram built from the grid points that matter for the map. Deep-ocean points are dropped, the points
// of lakes that are not on a coast are thinned, and the cells along a coast are split in two so that the packed graph has a higher
// resolution where the land meets the water. Each packed cell remembers the grid cell it came from.

import Foundation

public struct PackedMap: Equatable, Sendable {
	public enum Problem: Error, Equatable, Sendable {
		/// The packed points and the boundary points together would pass `VoronoiDiagram.maximumInputPoints` (a safety ceiling; the
		/// original has none). Checked as each point is added, so nothing large is built first.
		case tooManyPoints
		/// The map's arrays disagree (the number of cells, a feature number that has no feature), so the packed graph cannot be made.
		case invalidInputs
	}

	/// The packed cells' points, in the original's order: for each kept grid cell in grid order, its own point, then the midpoints with
	/// its coastal neighbours with a higher number. The original's `pack.cells.p`.
	public let points: [Point]
	/// For each packed cell, the grid cell it came from (the original's `g`, a `Uint32Array`). Several packed cells can share one.
	public let gridCell: [Int]
	/// For each packed cell, the height of its grid cell at packing time. **The packed heights are a copy: later stages change them
	/// (rivers cut valleys) and never the grid's.**
	public let heights: [Height]
	/// For each packed cell, the area of its polygon, as the original's `Uint16Array` (the absolute area capped at 65535, then
	/// truncated toward zero).
	public let areas: [UInt16]
	/// The cells and vertices of the packed diagram, clipped by the grid's boundary points.
	public let voronoi: VoronoiDiagram

	/// The packed graph of a map (the original's `Pack.generate`). It reads the grid's final heights, its coast distance field, feature
	/// numbers and features, its cell neighbours and border flags, and the grid's points, spacing and boundary points, after the lake
	/// steps: it does not depend on the climate.
	public static func generate(for map: LandMap) throws -> PackedMap {
		try generate(for: map, maximumPoints: VoronoiDiagram.maximumInputPoints)
	}

	/// The same with a ceiling on the packed points and the boundary points together (the tests lower it).
	static func generate(for map: LandMap, maximumPoints: Int) throws -> PackedMap {
		let grid = map.grid
		let n = grid.points.count
		let heights = map.heights, distance = map.features.distanceField, featureIds = map.features.featureIds
		let cells = map.voronoi.cells
		guard heights.count == n, distance.count == n, featureIds.count == n, cells.c.count == n, cells.b.count == n else { throw Problem.invalidInputs }
		let limit = min(maximumPoints, VoronoiDiagram.maximumInputPoints) - grid.boundary.count
		let selected = try selectPoints(
			points: grid.points, spacing: grid.spacing, heights: heights, distance: distance, neighbours: cells.c, border: cells.b, limit: limit,
			isLake: { i in
				guard let feature = map.features.feature(Int(featureIds[i])) else { throw Problem.invalidInputs }
				return feature.kind == .lake
			})
		let (points, gridCell, packedHeights) = (selected.points, selected.gridCell, selected.heights)

		let voronoi = try VoronoiDiagram.calculate(points: points, boundary: grid.boundary)
		let areas = (0..<points.count).map { cell in storedArea(voronoi.cells.v[cell].map { voronoi.vertices.p[$0] }) }
		return PackedMap(points: points, gridCell: gridCell, heights: packedHeights, areas: areas, voronoi: voronoi)
	}

	/// Which grid cells get a packed point, and the extra points along coasts, in the original's order. Over explicit values so that the
	/// rules can be pinned by small hand cases; `isLake` tells whether a cell's feature is a lake (asked only for cells at distance -2).
	static func selectPoints(points grid: [Point], spacing: Double, heights: [Height], distance: [Int8], neighbours: [[Int]], border: [Int], limit: Int, isLake: (Int) throws -> Bool) throws -> (points: [Point], gridCell: [Int], heights: [Height]) {
		let spacing2 = pow(spacing, 2)
		var points: [Point] = [], gridCell: [Int] = [], packedHeights: [Height] = []
		func add(_ cell: Int, _ x: Double, _ y: Double, _ height: Height) throws {
			guard points.count < limit else { throw Problem.tooManyPoints }
			points.append(Point(x: x, y: y))
			gridCell.append(cell)
			packedHeights.append(height)
		}

		for i in 0..<grid.count {
			let height = heights[i]
			let type = Int(distance[i])
			if height < Heights.seaLevel && type != -1 && type != -2 { continue } // exclude all deep ocean points
			if type == -2 {
				if try i % 4 == 0 || isLake(i) { continue } // exclude non-coastal lake points
			}

			let x = grid[i].x, y = grid[i].y
			try add(i, x, y, height)

			// add additional points for cells along coast
			if type == 1 || type == -1 {
				if border[i] != 0 { continue } // not for near-border cells
				for e in neighbours[i] {
					if i > e { continue }
					if Int(distance[e]) != type { continue }
					let dist2 = pow(y - grid[e].y, 2) + pow(x - grid[e].x, 2)
					if dist2 < spacing2 { continue } // too close to each other
					try add(i, JSNumber.rn((x + grid[e].x) / 2, 1), JSNumber.rn((y + grid[e].y) / 2, 1), height)
				}
			}
		}
		return (points, gridCell, packedHeights)
	}

	/// `Math.min(Math.abs(polygonArea(polygon)), 65535)` stored in a `Uint16Array`: the cap, then the store's truncation.
	static func storedArea(_ polygon: [Point]) -> UInt16 {
		let area = abs(polygonArea(polygon))
		return JSNumber.toUInt16(area.isNaN ? area : min(area, 65535))
	}

	/// d3-polygon 3.0.1's `polygonArea`: the signed area by the shoelace sum, added in the library's order (an empty polygon is 0).
	static func polygonArea(_ polygon: [Point]) -> Double {
		guard var b = polygon.last else { return 0 }
		var area = 0.0
		for point in polygon {
			let a = b
			b = point
			area += a.y * b.x - a.x * b.y
		}
		return area / 2
	}
}
