// Ported from the original's src/generators/grid-generator.ts (Azgaar's Fantasy Map Generator, MIT; see
// ACKNOWLEDGEMENTS.md), read at commit 8936c9c: `findDeepDepressionLakes`, `addDeepDepressionLakes` and
// `openNearSeaLakes`. Step 7 of docs/plans/land-layer.md. In the original's pipeline they run right after the features are
// marked (`markupGrid`, then `addDeepDepressionLakes`, then `openNearSeaLakes`), and nothing in between reads the features.
//
// Neither routine draws a random number, so there is no random generator here. Climate-dependent lake behaviour (the
// original's `lakes.ts`, which needs temperature and rain) belongs to a later layer and is not ported.

import Foundation

/// Why the lake routines could not run.
public enum LandLakesError: Error, Equatable, Sendable {
	/// The heights, the features and the diagram do not match, or a neighbour index is not a cell.
	case inconsistentInput
	/// The elevation limit is not a finite, non-negative number (the original's setting is a non-negative number).
	case invalidElevationLimit
	/// A new lake would need a feature number above 65,535 (the original's 16-bit array would wrap; this refuses).
	case tooManyFeatures
}

/// The lake routines that run on the grid, before climate: deep depressions become lakes, and lakes beside the sea open into it.
public enum LandLakes {
	/// The elevation limit at which the original switches depression lakes off (`elevationLimit === 80`).
	public static let depressionLakesOffLimit = 80.0

	/// The template option value for which the original skips `openNearSeaLakes`. **As written in the original** the
	/// comparison is with the string "Atoll", while the template's key (what its options actually store) is "atoll", so
	/// the early return does not happen for the Atoll template in the original; it only happens for an option equal to
	/// exactly "Atoll". That looks like a latent bug in the original, and it is kept as written for parity: pass the
	/// option's value as the original would hold it.
	public static let atollTemplateOption = "Atoll"

	/// The height lakes are given (one below sea level).
	static let lakeHeight: Height = 19
	/// The highest land that near-sea water can break through (`LIMIT` in the original).
	static let breachLimit: Height = 22

	/// The cell groups of land depressions that cannot pour to water within the elevation limit: the lakes to be (the
	/// original's `findDeepDepressionLakes`). A working copy of the heights is used, so a lake found earlier is water that a
	/// later check can reach. The flood is last-in-first-out, as in the original.
	static func findDeepDepressionLakes(heights: [Height], voronoi: VoronoiDiagram, elevationLimit: Double) -> [[Int]] {
		if elevationLimit == depressionLakesOffLimit { return [] }
		let neighbours = voronoi.cells.c
		let border = voronoi.cells.b
		var h = heights // the working copy
		var lakes: [[Int]] = []

		for i in 0..<neighbours.count {
			if border[i] != 0 || h[i] < Heights.seaLevel { continue }
			// skip a cell that has a lower neighbour (`h > d3.min(...)`); with no neighbours the original's comparison is false
			if let lowest = neighbours[i].map({ h[$0] }).min(), h[i] > lowest { continue }

			var deep = true
			let threshold = Double(h[i]) + elevationLimit
			var queue = [i]
			var checked = Set<Int>([i])

			// can the cell pour to water within the limit? flood the cells below the threshold looking for water
			while deep, let q = queue.popLast() {
				for n in neighbours[q] {
					if checked.contains(n) { continue }
					if Double(h[n]) >= threshold { continue }
					if h[n] < Heights.seaLevel { deep = false; break }
					checked.insert(n)
					queue.append(n)
				}
			}

			if !deep { continue }
			let lakeCells = [i] + neighbours[i].filter { h[$0] == h[i] }
			for cell in lakeCells { h[cell] = lakeHeight }
			lakes.append(lakeCells)
		}
		return lakes
	}

	/// Turns the depressions that cannot pour to water into lakes (the original's `addDeepDepressionLakes`): the lake cells
	/// get height 19, water coast -1 and a new feature number; their neighbours outside the lake become coast land (1); and a
	/// new lake feature (not touching the edge) is added.
	///
	/// **Failure:** this function changes the caller's `heights` and `features` in place, so if it throws part-way (a later lake
	/// needing a feature number above 65,535) the earlier lakes have already been applied. `apply(...)` works on copies and
	/// publishes only a successful result.
	public static func addDeepDepressionLakes(heights: inout [Height], features: inout LandFeatures, voronoi: VoronoiDiagram, elevationLimit: Double) throws {
		try validate(heights: heights, features: features, voronoi: voronoi, elevationLimit: elevationLimit)
		let neighbours = voronoi.cells.c
		for lakeCells in findDeepDepressionLakes(heights: heights, voronoi: voronoi, elevationLimit: elevationLimit) {
			let featureId = features.features.count + 1
			guard featureId <= Int(UInt16.max) else { throw LandLakesError.tooManyFeatures }
			let members = Set(lakeCells)
			for i in lakeCells {
				heights[i] = lakeHeight
				features.distanceField[i] = -1
				features.featureIds[i] = UInt16(featureId)
				for n in neighbours[i] where !members.contains(n) {
					features.distanceField[n] = 1 // the lake shore is a coastline now
				}
			}
			features.features.append(Feature(id: featureId, land: false, border: false, kind: .lake))
		}
	}

	/// Opens lakes beside the sea into it (the original's `openNearSeaLakes`): near-sea lakes get a lot of water inflow, so
	/// where a low (22 or less) coast-land cell separates a lake from an ocean, that cell becomes water (height 19, water
	/// coast, the ocean's feature number), its land neighbours become coast, every cell of the lake takes the ocean's number,
	/// and **the former lake's feature record is kept, with its kind changed to ocean** (it keeps `land` false and `border`
	/// false, so it is not the same as a re-marked ocean). The kept record then has **no cells**: its numbers were merged
	/// into the ocean's, so it is historical pipeline state and not a second current ocean body. **Feature records need not
	/// all be referenced by cells.** No "opened lake" property is exposed; add explicit provenance when a caller needs it.
	///
	/// - Parameters:
	///   - templateOption: the template option's value **as the original holds it, which is the template's key** (for a
	///     `HeightmapTemplate`, pass `template.key`, not its display name); the original does nothing if it is exactly
	///     `atollTemplateOption`.
	public static func openNearSeaLakes(heights: inout [Height], features: inout LandFeatures, voronoi: VoronoiDiagram, templateOption: String) throws {
		try validate(heights: heights, features: features, voronoi: voronoi, elevationLimit: 0)
		if templateOption == atollTemplateOption { return } // no need for atolls (see the note on `atollTemplateOption`)
		guard features.features.contains(where: { $0.kind == .lake }) else { return }
		let neighbours = voronoi.cells.c

		func removeLake(threshold: Int, lake: Int, ocean: Int) {
			heights[threshold] = lakeHeight
			features.distanceField[threshold] = -1
			features.featureIds[threshold] = UInt16(ocean)
			for c in neighbours[threshold] where Heights.isLand(heights[c]) { features.distanceField[c] = 1 } // mark as coastline
			for i in 0..<features.featureIds.count where Int(features.featureIds[i]) == lake { features.featureIds[i] = UInt16(ocean) }
			features.features[lake - 1].kind = .ocean // the former lake: record kept, type changed
		}

		for i in 0..<neighbours.count {
			let lake = Int(features.featureIds[i])
			guard let feature = features.feature(lake), feature.kind == .lake else { continue }

			neighbourSearch: for c in neighbours[i] {
				if features.distanceField[c] != 1 || heights[c] > breachLimit { continue } // water cannot break this
				for n in neighbours[c] {
					let ocean = Int(features.featureIds[n])
					guard let candidate = features.feature(ocean), candidate.kind == .ocean else { continue } // not an ocean
					removeLake(threshold: c, lake: lake, ocean: ocean)
					break neighbourSearch
				}
			}
		}
	}

	/// Runs both routines in the original's order: deep depressions first, then near-sea lakes.
	public static func apply(heights: [Height], features: LandFeatures, voronoi: VoronoiDiagram, elevationLimit: Double, templateOption: String) throws -> (heights: [Height], features: LandFeatures) {
		var heights = heights
		var features = features
		try addDeepDepressionLakes(heights: &heights, features: &features, voronoi: voronoi, elevationLimit: elevationLimit)
		try openNearSeaLakes(heights: &heights, features: &features, voronoi: voronoi, templateOption: templateOption)
		return (heights, features)
	}

	private static func validate(heights: [Height], features: LandFeatures, voronoi: VoronoiDiagram, elevationLimit: Double) throws {
		let count = voronoi.cells.c.count
		guard elevationLimit.isFinite, elevationLimit >= 0 else { throw LandLakesError.invalidElevationLimit }
		guard count > 0, heights.count == count, features.featureIds.count == count, features.distanceField.count == count,
			voronoi.cells.b.count == count,
			voronoi.cells.c.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0 < count } }),
			features.featureIds.allSatisfy({ $0 >= 1 && Int($0) <= features.features.count }),
			features.features.enumerated().allSatisfy({ $0.element.id == $0.offset + 1 }) else { throw LandLakesError.inconsistentInput }
	}
}
