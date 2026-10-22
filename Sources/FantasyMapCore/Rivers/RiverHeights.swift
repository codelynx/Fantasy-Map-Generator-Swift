// Ported from Azgaar's Fantasy Map Generator, `src/generators/river-generator.ts` (`alterHeights`, `resolveDepressions`; the original at
// commit 8936c9c, 2026-10-19). The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in
// ACKNOWLEDGEMENTS.md.
//
// The river generator's working heights: a fractional copy of the packed heights with a small gradient toward the coast, and the depression
// filling, which attempts to resolve depressions within the iteration limit, for a correct water flux. **It can stop with depressions left,
// including on bad progress: a caller must not infer that the drainage is complete from this helper's success.**

import Foundation

/// What `resolveDepressions` left (the original returns nothing; these are this package's report).
public struct DepressionOutcome: Equatable, Sendable {
	/// How many depressions the last completed iteration found and raised (0 if it settled: nothing was left to raise in it).
	public var lastIterationDepressions: Int
	/// Whether the run ended by the "bad progress" branch.
	public var badProgress: Bool
	/// How many iterations completed.
	public var iterations: Int
}

public enum RiverHeights {
	/// `alterHeights`: for every land cell with a positive coast distance, its height plus `distance / 100` plus the mean distance of its
	/// neighbours over 10,000, as a list of exact doubles; every other cell keeps its height. `distance` is `PackedFeatures.distanceField`.
	/// A land cell without neighbours has no mean (not a number in the original), and is refused.
	public static func alterHeights(packedHeights: [Height], distance: [Int8], neighbours: [[Int]]) throws -> [Double] {
		let n = packedHeights.count
		guard distance.count == n, neighbours.count == n, neighbours.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0 < n } }) else { throw RiverError.invalidInputs }
		var result = [Double](repeating: 0, count: n)
		for i in 0..<n {
			let h = Double(packedHeights[i])
			if packedHeights[i] < Heights.seaLevel || distance[i] < 1 { result[i] = h; continue }
			guard !neighbours[i].isEmpty else { throw RiverError.invalidInputs }
			let mean = Double(neighbours[i].reduce(0) { $0 + Int(distance[$1]) }) / Double(neighbours[i].count)
			result[i] = h + Double(distance[i]) / 100 + mean / 10000
		}
		return result
	}

	/// `resolveDepressions(h)`: **attempts to resolve depressions within the iteration limit**; it raises, in place, the working heights of the land cells that have no lower neighbour (by 0.1 above their
	/// lowest neighbour, a lake counting as its own height) and the lakes' heights (by 0.2 above their lowest shore cell), for at most
	/// `steps` iterations (a whole number from 1 to 1,000; the original's option is 250). Iterations past 0.75 of the steps close the lakes
	/// that are still not resolved (their shore cells go back to the **packed** heights and the lake is set one below its lowest shore cell);
	/// iterations past 0.85 stop checking the lakes. **If the progress turns bad** (more than five counts and a positive sum of their
	/// changes) the original reassigns its parameter, which changes only a local variable: **the heights keep their raises, as here**, and
	/// the loop ends.
	///
	/// The features are changed (each lake's `height` and `closed`). **A refused call changes nothing.** Land cells exclude the cells on the
	/// map border. A lake without a shore, a land cell without neighbours, a feature number outside the table, heights that are not finite or
	/// not one per cell, and steps outside 1 … 1,000 are refused (the original would produce not-a-number heights or fail).
	/// - Parameters:
	///   - packedHeights: the packed map's own byte heights (`pack.cells.h`).
	///   - neighbours: the packed diagram's cell neighbour lists; `border` its near-border flags.
	@discardableResult
	public static func resolveDepressions(heights h: inout [Double], features: inout PackedFeatures, packedHeights: [Height], neighbours: [[Int]], border: [Int], steps: Int, work: inout RiverWork) throws -> DepressionOutcome {
		let n = h.count
		guard steps >= 1, steps <= 1000 else { throw RiverError.invalidSettings }
		guard n == packedHeights.count, n == features.featureIds.count, n == neighbours.count, n == border.count, h.allSatisfy(\.isFinite),
			neighbours.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0 < n } }),
			features.featureIds.allSatisfy({ $0 >= 1 && Int($0) <= features.features.count }) else { throw RiverError.invalidInputs }
		for lake in features.features where lake.kind == .lake {
			guard !lake.shoreline.isEmpty else { throw RiverError.lakeWithoutShore }
			guard lake.shoreline.allSatisfy({ $0 >= 0 && $0 < n }) else { throw RiverError.invalidInputs }
		}

		// worked on as copies: a refused call changes nothing
		var h2 = h, f = features, w = work
		let maxIterations = Double(steps)
		let checkLakeMaxIteration = maxIterations * 0.85
		let elevateLakeMaxIteration = maxIterations * 0.75

		/// height of lake or specific cell: the feature's height unless it is 0 or not a number (JavaScript's `||`)
		func height(_ i: Int) -> Double {
			let featureHeight = f.features[Int(f.featureIds[i]) - 1].height
			return featureHeight == 0 || featureHeight.isNaN ? h2[i] : featureHeight
		}

		let lakes = f.features.indices.filter { f.features[$0].kind == .lake }
		let bits = Int.bitWidth - n.leadingZeroBitCount
		try w.charge(n, .resolveDepressions)
		let (sortCharge, overflow) = n.multipliedReportingOverflow(by: bits)
		guard !overflow else { throw RiverError.workBudgetExceeded(.resolveDepressions) }
		try w.charge(sortCharge, .resolveDepressions)
		// the land cells away from the border, lowest first; equal heights keep the cell order (the sort is stable)
		let land = (0..<n).filter { h2[$0] >= Double(Heights.seaLevel) && border[$0] == 0 }.sorted { (h2[$0], $0) < (h2[$1], $1) }
		for i in land where neighbours[i].isEmpty { throw RiverError.invalidInputs }

		var progress: [Int] = []
		var depressions = Int.max // the original starts at Infinity
		var previous: Int? // the last completed iteration's count
		var iteration = 0
		var badProgress = false
		while depressions != 0 && iteration < steps {
			if progress.count > 5 && progress.reduce(0, +) > 0 {
				// bad progress: the original resets a local copy of the heights, which the caller never sees
				badProgress = true
				break
			}

			depressions = 0

			if Double(iteration) < checkLakeMaxIteration {
				for index in lakes {
					try w.charge(1, .resolveDepressions)
					if f.features[index].closed == true { continue }
					try w.charge(f.features[index].shoreline.count, .resolveDepressions)
					let minHeight = f.features[index].shoreline.map { h2[$0] }.min()!
					if minHeight >= 100 || f.features[index].height > minHeight { continue }

					if Double(iteration) > elevateLakeMaxIteration {
						// the shore goes back to the packed heights, and is scanned again for the new lake height: both passes are charged first
						try w.charge(f.features[index].shoreline.count, .resolveDepressions)
						try w.charge(f.features[index].shoreline.count, .resolveDepressions)
						for i in f.features[index].shoreline { h2[i] = Double(packedHeights[i]) }
						f.features[index].height = f.features[index].shoreline.map { h2[$0] }.min()! - 1
						f.features[index].closed = true
						continue
					}

					depressions += 1
					f.features[index].height = minHeight + 0.2
				}
			}

			for i in land {
				try w.charge(1 + neighbours[i].count, .resolveDepressions)
				let minHeight = neighbours[i].map(height).min()!
				if minHeight >= 100 || h2[i] > minHeight { continue }

				depressions += 1
				h2[i] = minHeight + 0.1
			}

			if let previous { progress.append(depressions - previous) }
			previous = depressions
			iteration += 1
		}

		h = h2
		features = f
		work = w
		return DepressionOutcome(lastIterationDepressions: previous ?? 0, badProgress: badProgress, iterations: iteration)
	}
}
