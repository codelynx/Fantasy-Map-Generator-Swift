// Ported from Azgaar's Fantasy Map Generator: `src/generators/features-generator.ts` (`markupPack`, `markup`), `src/utils/pathUtils.ts`
// (`connectVertices`) and `src/generators/lakes.ts` (`defineShoreline`, `getHeight`); the original at commit 8936c9c, 2026-10-19. The
// original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// The packed graph's features (oceans, lakes, islands), found by flood fill over the packed cells, with a ring of Voronoi vertices around
// each island and lake, the distance of every cell from the coast, and for every land cell on a coast the water cell opposite it.

import Foundation

/// An ocean, lake or island of the packed graph. The original's `Feature` after `markupPack` (the climate and river fields are added by
/// later stages).
public struct PackedFeature: Equatable, Sendable {
	/// The feature's number from 1, the numbers in `PackedFeatures.featureIds`.
	public var id: Int
	public var kind: FeatureKind
	public var land: Bool
	/// True if it touches the map border.
	public var border: Bool
	/// The number of cells.
	public var cells: Int
	/// The cell its ring starts from: the first cell found on the feature's border (not always its lowest-numbered cell).
	public var firstCell: Int
	/// The ring of Voronoi vertices around it (empty for an ocean). **A lake's ring is turned to run the other way when its clipped area is
	/// positive.**
	public var vertices: [Int]
	/// An ocean's area is the sum of its cells' areas (its ring is open at the border); the others' is the absolute rounded area of the
	/// ring clipped to the map.
	public var area: Double
	/// A lake's shoreline: the land cells around its ring, each once, in order of first appearance (empty for the others).
	public var shoreline: [Int]
	/// A lake's height: its lowest shore cell less 0.1, rounded to two decimals (20 for a lake without a shore); 0 for the others.
	public var height: Double

	// The fields later stages give a lake (the original's `Feature` carries them all). A lake has none of them after `markupPack`.
	/// The rain on the shore (the sum of the grid precipitation of the shore cells), the temperature (the lake's own or the shore's mean) and the
	/// yearly evaporation: set by `defineClimateData`.
	public var flux = 0.0, temp = 0.0, evaporation = 0.0
	/// True for a lake in a deep depression (no outlet), false for one that can overflow: set by `detectCloseLakes`.
	public var closed: Bool?
	/// The lake's outlet: its lowest shore cell (not for closed lakes): set by `defineClimateData`.
	public var outCell: Int?
	/// River fields (set while the rivers are made, and cleaned by `cleanupLakeData`).
	public var river: Int?, enteringFlux: Double?
	public var inlets: [Int]?, outlet: Int?
}

/// The result of the original's `Features.markupPack`: its `pack.cells.t`, `f`, `haven` and `harbor`, and `pack.features` (without the
/// original's placeholder at 0: `features[id - 1]` is the feature with that number).
public struct PackedFeatures: Equatable, Sendable {
	public enum Problem: Error, Equatable, Sendable {
		/// The feature numbers would pass 65535, the largest the original's `Uint16Array` holds (a safety refusal; the original would wrap).
		case tooManyFeatures
		/// A feature has no cell on its border or on the map border (the original throws).
		case noBorderCell
		/// A feature's border cell has no vertex next to a different feature (the original throws).
		case noStartingVertex
		/// The packed map's arrays disagree.
		case invalidInputs
	}

	/// The distance of every packed cell from the coast: 1 land coast, 2 and up inland (3 and up from the second ring), -1 water coast,
	/// -2 and down out to sea to -10. The original's `Int8Array`.
	public var distanceField: [Int8]
	/// The number of the feature each packed cell belongs to (the original's `Uint16Array`).
	public var featureIds: [UInt16]
	/// For every land cell on a coast, the closest water cell next to it (the original's `Uint32Array`; 0 where there is none).
	public var haven: [Int]
	/// For every land cell on a coast, the number of water cells next to it (the original's `Uint8Array`).
	public var harbor: [UInt8]
	public var features: [PackedFeature]

	public func feature(_ id: Int) -> PackedFeature? { id >= 1 && id <= features.count ? features[id - 1] : nil }

	private static let landCoast: Int8 = 1, landlocked: Int8 = 2, unmarked: Int8 = 0, waterCoast: Int8 = -1, deepWater: Int8 = -2, deeperLand: Int8 = 3

	/// The original's `markupPack` for a packed map, on a map of the given size (the rings are clipped to it). **A packed map with no cell
	/// is supported:** the original returns without marking anything, and this returns no features and empty arrays.
	public static func markup(for packed: PackedMap, width: Double, height: Double) throws -> PackedFeatures {
		let n = packed.points.count
		let cells = packed.voronoi.cells, vertices = packed.voronoi.vertices
		guard packed.heights.count == n, packed.areas.count == n, packed.gridCell.count == n, cells.c.count == n, cells.b.count == n, cells.v.count == n, width.isFinite, height.isFinite else { throw Problem.invalidInputs }
		if n == 0 { return PackedFeatures(distanceField: [], featureIds: [], haven: [], harbor: [], features: []) }

		let neighbors = cells.c, borderCells = cells.b
		func isLand(_ cell: Int) -> Bool { cell >= 0 && cell < n && packed.heights[cell] >= Heights.seaLevel }
		func isWater(_ cell: Int) -> Bool { cell >= 0 && cell < n && packed.heights[cell] < Heights.seaLevel }

		var distanceField = [Int8](repeating: unmarked, count: n)
		var featureIds = [UInt16](repeating: 0, count: n)
		var haven = [Int](repeating: 0, count: n)
		var harbor = [UInt8](repeating: 0, count: n)
		var features: [PackedFeature] = []

		/// A feature number as the original reads it: outside the array (a boundary point) it is `undefined`, different from every number.
		func featureId(of cell: Int) -> Int? { cell >= 0 && cell < n ? Int(featureIds[cell]) : nil }

		func defineHaven(_ cellId: Int) {
			let waterCells = neighbors[cellId].filter(isWater)
			let distances = waterCells.map { distanceSquared(packed.points[cellId], packed.points[$0]) }
			if let least = distances.min(), let closest = distances.firstIndex(of: least) { haven[cellId] = waterCells[closest] }
			harbor[cellId] = UInt8(truncatingIfNeeded: waterCells.count)
		}

		func addFeature(firstCell: Int, land: Bool, border: Bool, id: Int, totalCells: Int, cellsArea: Double) throws -> PackedFeature {
			let kind: FeatureKind = land ? .island : border ? .ocean : .lake
			var startCell = firstCell
			var ring: [Int] = []
			if kind != .ocean {
				let type = featureId(of: firstCell)
				let isOnBorder = { (cell: Int) -> Bool in borderCells[cell] != 0 || neighbors[cell].contains { featureId(of: $0) != type } }
				if !isOnBorder(firstCell) {
					guard let found = (0..<n).first(where: { featureId(of: $0) == type && isOnBorder($0) }) else { throw Problem.noBorderCell }
					startCell = found
				}
				guard let startingVertex = cells.v[startCell].first(where: { v in vertices.c[v].contains { featureId(of: $0) != type } }) else { throw Problem.noStartingVertex }
				ring = VertexRing.connect(vertices: vertices, startingVertex: startingVertex, ofSameType: { featureId(of: $0) == type }, closeRing: false)
			}
			let points = LineClip.clipPoly(ring.map { vertices.p[$0] }, width: width, height: height)
			let area = PackedMap.polygonArea(points) // feature perimeter area
			let absArea = kind == .ocean ? cellsArea : abs(JSNumber.rn(area)) // an ocean ring is open at the border: its polygon area collapses

			var feature = PackedFeature(id: id, kind: kind, land: land, border: border, cells: totalCells, firstCell: startCell, vertices: ring, area: absArea, shoreline: [], height: 0)
			if kind == .lake {
				if area > 0 { feature.vertices.reverse() }
				feature.shoreline = shoreline(of: feature, vertices: vertices, isLand: isLand)
				feature.height = lakeHeight(of: feature, heights: packed.heights)
			}
			return feature
		}

		var next = 0
		var id = 1
		while next != -1 {
			guard id <= Int(UInt16.max) else { throw Problem.tooManyFeatures }
			let firstCell = next
			featureIds[firstCell] = UInt16(id)

			let land = isLand(firstCell)
			var border = borderCells[firstCell] != 0 // true if feature touches map border
			var totalCells = 1 // count cells in a feature
			var cellsArea = Double(packed.areas[firstCell])

			var queue = [firstCell]
			while let cellId = queue.popLast() {
				if borderCells[cellId] != 0 { border = true }

				for neighborId in neighbors[cellId] {
					let isNeibLand = isLand(neighborId)

					if land && !isNeibLand {
						distanceField[cellId] = landCoast
						distanceField[neighborId] = waterCoast
						if haven[cellId] == 0 { defineHaven(cellId) }
					} else if land && isNeibLand {
						if distanceField[neighborId] == unmarked && distanceField[cellId] == landCoast { distanceField[neighborId] = landlocked }
						else if distanceField[cellId] == unmarked && distanceField[neighborId] == landCoast { distanceField[cellId] = landlocked }
					}

					if featureIds[neighborId] == 0 && land == isNeibLand {
						queue.append(neighborId)
						featureIds[neighborId] = UInt16(id)
						totalCells += 1
						cellsArea += Double(packed.areas[neighborId])
					}
				}
			}

			features.append(try addFeature(firstCell: firstCell, land: land, border: border, id: id, totalCells: totalCells, cellsArea: cellsArea))
			next = featureIds.firstIndex(of: 0) ?? -1 // find unmarked cell
			id += 1
		}

		markup(&distanceField, neighbors: neighbors, start: Int(deeperLand), increment: 1, limit: 127) // markup pack land
		markup(&distanceField, neighbors: neighbors, start: Int(deepWater), increment: -1, limit: -10) // markup pack water
		return PackedFeatures(distanceField: distanceField, featureIds: featureIds, haven: haven, harbor: harbor, features: features)
	}

	/// The original's `markup`: the distance to the coast, ring by ring, from `start` in steps of `increment` until nothing is marked or the
	/// limit is reached.
	private static func markup(_ distanceField: inout [Int8], neighbors: [[Int]], start: Int, increment: Int, limit: Int) {
		var distance = start, marked = Int.max
		while marked > 0 && distance != limit {
			marked = 0
			let previous = distance - increment
			for cellId in 0..<neighbors.count where Int(distanceField[cellId]) == previous {
				for neighborId in neighbors[cellId] where distanceField[neighborId] == unmarked {
					distanceField[neighborId] = Int8(distance)
					marked += 1
				}
			}
			distance += increment
		}
	}

	/// `(x1 - x2) ** 2 + (y1 - y2) ** 2`.
	static func distanceSquared(_ a: Point, _ b: Point) -> Double { pow(a.x - b.x, 2) + pow(a.y - b.y, 2) }

	/// `Lakes.defineShoreline`: the land cells around the lake's ring, each once, in order of first appearance. A boundary point is not a
	/// land cell.
	static func shoreline(of feature: PackedFeature, vertices: VoronoiDiagram.Vertices, isLand: (Int) -> Bool) -> [Int] {
		var seen = Set<Int>(), result: [Int] = []
		for vertex in feature.vertices { for cell in vertices.c[vertex] where isLand(cell) && seen.insert(cell).inserted { result.append(cell) } }
		return result
	}

	/// `Lakes.getHeight`: `rn(min(shore heights) || 20 - 0.1, 2)`: the lowest shore cell (20 if there is none, or if it is 0) less 0.1.
	static func lakeHeight(of feature: PackedFeature, heights: [Height]) -> Double {
		let lowest = feature.shoreline.map { Double(heights[$0]) }.min() ?? 0
		return JSNumber.rn((lowest == 0 ? 20 : lowest) - 0.1, 2)
	}
}

/// The original's `connectVertices` (`utils/pathUtils.ts`).
enum VertexRing {
	/// Follows the border of a set of cells around the Voronoi vertices, from a starting vertex, until it comes back to it. **The original's
	/// stops are kept:** if the next vertex is outside the list (a hull edge has none), is the current one, or the walk has gone on for as
	/// many steps as there are vertices, it stops and returns the ring so far (the original logs an error only when its debug flag is on).
	static func connect(vertices: VoronoiDiagram.Vertices, startingVertex: Int, ofSameType: (Int) -> Bool, closeRing: Bool) -> [Int] {
		let maxIterations = vertices.c.count
		var chain: [Int] = []
		var next = startingVertex
		var i = 0
		while i == 0 || next != startingVertex {
			let previous = chain.last
			let current = next
			chain.append(current)
			guard current >= 0, current < vertices.c.count, vertices.c[current].count == 3, vertices.v[current].count == 3 else { break }

			let same = vertices.c[current].map(ofSameType)
			let (c1, c2, c3) = (same[0], same[1], same[2])
			let (v1, v2, v3) = (vertices.v[current][0], vertices.v[current][1], vertices.v[current][2])

			if v1 != previous && c1 != c2 { next = v1 }
			else if v2 != previous && c2 != c3 { next = v2 }
			else if v3 != previous && c1 != c3 { next = v3 }

			// a hull half-edge has no opposite triangle, so `vertices.v` holds -1 for it
			if next < 0 || next >= vertices.c.count { break }
			if next == current { break }
			if i == maxIterations { break }
			i += 1
		}
		if closeRing { chain.append(startingVertex) }
		return chain
	}
}
