// Ported from the original's src/generators/features-generator.ts (Azgaar's Fantasy Map Generator, MIT; see
// ACKNOWLEDGEMENTS.md), read at commit 8936c9c: `markup` and `markupGrid`, the part that numbers the bodies of sea and land
// and marks each cell's distance from the coast. Step 6 of docs/plans/land-layer.md. The lakes that change heights and
// coasts are step 7; naming, subtypes, areas and shorelines belong to later layers and are not ported here.

import Foundation

/// What kind of body a feature is.
public enum FeatureKind: String, Codable, Sendable {
	/// Land: a connected set of cells at or above sea level.
	case island
	/// Water that touches the edge of the map.
	case ocean
	/// Water that does not touch the edge of the map.
	case lake
}

/// A connected body of land or water.
public struct Feature: Equatable, Sendable {
	/// The feature's number, from 1 (the numbers in `LandFeatures.featureIds`).
	public var id: Int
	public var land: Bool
	/// Whether the feature touches the map's edge.
	public var border: Bool
	public var kind: FeatureKind

	public init(id: Int, land: Bool, border: Bool, kind: FeatureKind) {
		self.id = id
		self.land = land
		self.border = border
		self.kind = kind
	}
}

/// Why the features could not be marked.
public enum LandFeaturesError: Error, Equatable, Sendable {
	/// The heights do not match the diagram's cells, there are no cells, or a neighbour index is not a cell.
	case inconsistentInput
	/// More than 65,535 features: the original numbers them in a 16-bit array and would wrap, so this is refused.
	case tooManyFeatures
}

/// The grid's features and each cell's distance from the coast, as the original's `markupGrid` makes them.
public struct LandFeatures: Equatable, Sendable {
	/// The feature each cell belongs to (the original's `grid.cells.f`): a number from 1.
	public var featureIds: [UInt16]
	/// Each cell's distance from the coast (the original's `grid.cells.t`), **a graph distance** (steps between neighbouring
	/// cells), not a distance in map units: 1 for a land cell next to water, -1 for a water cell next to land, -2 ... -9
	/// for water farther out, 0 for land inland and for water beyond 9 steps (and for any cell the flood did not reach).
	/// This is what `markupGrid` computes: it does not measure distance inland.
	public var distanceField: [Int8]
	/// The features, in order: `features[0]` is feature 1.
	public var features: [Feature]

	/// The feature with this number (from 1), or nil.
	public func feature(_ id: Int) -> Feature? { id >= 1 && id <= features.count ? features[id - 1] : nil }

	private static let unmarked: Int8 = 0
	private static let landCoast: Int8 = 1
	private static let waterCoast: Int8 = -1
	private static let deepWater: Int8 = -2

	/// Numbers the grid's connected bodies of sea and land and marks the coast and the water distance from it, as the
	/// original's `markupGrid` does. Land is a height of at least 20 (`Heights.seaLevel`). The original resets its random
	/// generator at the start of this step to get the same result on a height edit, but draws nothing; none is needed here.
	///
	/// The flood fill takes cells **last-in-first-out**, as the original's `queue.pop()` does; the order does not change which
	/// cells belong to a feature, but it is kept so the work mirrors the original's.
	public static func markup(heights: [Height], voronoi: VoronoiDiagram) throws -> LandFeatures {
		try markup(heights: heights, voronoi: voronoi, maximumFeatures: Int(UInt16.max))
	}

	/// As above, with the feature limit made explicit so the boundary can be tested with a small number: feature numbers
	/// 1 through `maximumFeatures` are allowed (the original's 16-bit array holds up to 65,535, and zero means "not yet
	/// reached"), and the check comes before feature `maximumFeatures + 1` is assigned.
	static func markup(heights: [Height], voronoi: VoronoiDiagram, maximumFeatures: Int) throws -> LandFeatures {
		let neighbours = voronoi.cells.c
		let border = voronoi.cells.b
		let count = neighbours.count
		guard count > 0, heights.count == count, border.count == count,
			neighbours.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0 < count } }) else { throw LandFeaturesError.inconsistentInput }

		var distance = [Int8](repeating: unmarked, count: count)
		var featureIds = [UInt16](repeating: 0, count: count)
		var features: [Feature] = []

		var first = 0
		var cursor = 0 // every cell before this one is marked, so the search for the next unmarked cell never rescans them
		var featureId = 1
		while first != -1 {
			guard featureId <= maximumFeatures else { throw LandFeaturesError.tooManyFeatures }
			featureIds[first] = UInt16(featureId)

			let land = Heights.isLand(heights[first])
			var touchesEdge = false
			var queue = [first]
			while let cell = queue.popLast() {
				if !touchesEdge && border[cell] != 0 { touchesEdge = true }
				for neighbour in neighbours[cell] {
					let neighbourIsLand = Heights.isLand(heights[neighbour])
					if land == neighbourIsLand && featureIds[neighbour] == 0 {
						featureIds[neighbour] = UInt16(featureId)
						queue.append(neighbour)
					} else if land && !neighbourIsLand {
						distance[cell] = landCoast
						distance[neighbour] = waterCoast
					}
				}
			}

			let kind: FeatureKind = land ? .island : (touchesEdge ? .ocean : .lake)
			features.append(Feature(id: featureId, land: land, border: touchesEdge, kind: kind))

			// the first cell no feature has reached: marks only ever increase, so a cursor that moves forward finds the same
			// cell the original's `indexOf` from zero finds, without rescanning (the numbering is unchanged)
			while cursor < count && featureIds[cursor] != 0 { cursor += 1 }
			first = cursor < count ? cursor : -1
			featureId += 1
		}

		// deep water: grow outward from the water coast one step at a time, to -9
		var step = Int(deepWater)
		var marked = Int.max
		while marked > 0 && step != -10 {
			marked = 0
			let previous = Int8(step + 1) // `distance - increment`, increment being -1
			for cell in 0..<count where distance[cell] == previous {
				for neighbour in neighbours[cell] where distance[neighbour] == unmarked {
					distance[neighbour] = Int8(step)
					marked += 1
				}
			}
			step -= 1
		}

		return LandFeatures(featureIds: featureIds, distanceField: distance, features: features)
	}
}
