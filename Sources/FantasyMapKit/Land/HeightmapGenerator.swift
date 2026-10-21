// Ported from the original's src/generators/heightmap-generator.ts (Azgaar's Fantasy Map Generator, MIT; see
// ACKNOWLEDGEMENTS.md), read at commit 8936c9c. Step 4 of docs/plans/land-layer.md is built in stages: so far the
// step runner and every tool the original's templates use: `Hill`, `Pit`, `Range`, `Trough`, `Strait`, `Add`, `Multiply`,
// `Smooth`, `Mask` and `Invert`; and the runner that makes a whole map from a template or a script of steps.
//
// Heights are whole numbers in a byte array in the original: every store into it truncates toward zero and wraps modulo
// 256 (`Heights.stored`), and that conversion is applied here exactly where the original assigns into a typed array.

import Foundation

/// Why a height step could not be run.
public enum HeightmapError: Error, Equatable, Sendable {
	/// The step line has fewer than five space-separated parts (tool and four arguments), as every template step has.
	case malformedStep(String)
	/// The word is not one of the tools the original's templates use.
	case unsupportedTool(String)
	/// A line of a step script is not a step (reported with its line number, counting from 1).
	case malformedScript(line: Int, text: String)
	/// A strait path did not reach its end within its step budget (the original's `Strait` has no visited-cell check and
	/// could in principle wander forever). The heights are left unchanged, but the random stream has advanced.
	case pathDidNotConverge
	/// The heights array does not match the cells.
	case heightsDoNotMatchCells
	/// A cell index found from map coordinates is not a valid cell. The rule, as the original has it: a finite,
	/// non-negative coordinate beyond the far edge uses the last row or column (the original's own `Math.min`); a negative
	/// or non-finite coordinate is rejected with this error, never moved to another cell.
	case cellOutOfRange
	/// The grid and the Voronoi diagram are not usable together: a non-finite or non-positive size or cell count, a grid whose
	/// cells across and down or whose point count do not follow from its size and spacing, a diagram that was not built
	/// from this grid's points, or a neighbour index that is not a cell.
	case invalidGrid
	/// A step asks for more operations than `HeightmapGenerator.maximumOperations`, or for a count that is not finite.
	case operationCountTooLarge
}

/// Builds the heights of the land one step at a time, as the original's `HeightmapModule` does.
public struct HeightmapGenerator: Sendable {
	/// The heights so far, one byte per cell point (0 to 100 as the steps limit them).
	public private(set) var heights: [Height]

	/// Replaces the heights (for tests that start from a chosen map).
	mutating func setHeights(_ values: [Height]) { heights = values }

	let width: Double
	let height: Double
	let cellsDesired: Int
	let grid: GridPoints
	let neighbours: [[Int]]
	let blobPower: Double
	let linePower: Double

	/// A provisional bound on the **number** of operations one step may ask for (for example the number of hills): far above
	/// any template (the largest asks for 15). It bounds a count, not execution time: ten thousand hills over a large grid
	/// can still be expensive. A grid-size-aware work budget and cancellation are follow-up requirements before an app
	/// exposes unrestricted editable step lists.
	public static let maximumOperations = 10_000

	/// The original's `getBlobPower`: tuned for exactly its density steps, 0.98 for any other cell count.
	static func blobPower(for cellsDesired: Int) -> Double {
		let table: [Int: Double] = [
			1000: 0.93, 2000: 0.95, 5000: 0.97, 10000: 0.98, 20000: 0.99, 30000: 0.991, 40000: 0.993, 50000: 0.994,
			60000: 0.995, 70000: 0.9955, 80000: 0.996, 90000: 0.9964, 100000: 0.9973
		]
		return table[cellsDesired] ?? 0.98
	}

	/// The original's `getLinePower`: tuned for exactly its density steps, 0.81 for any other cell count.
	static func linePower(for cellsDesired: Int) -> Double {
		let table: [Int: Double] = [
			1000: 0.75, 2000: 0.77, 5000: 0.79, 10000: 0.81, 20000: 0.82, 30000: 0.83, 40000: 0.84, 50000: 0.86,
			60000: 0.87, 70000: 0.88, 80000: 0.91, 90000: 0.92, 100000: 0.93
		]
		return table[cellsDesired] ?? 0.81
	}

	/// Starts from a blank heightmap on a grid, as `setGraph` does after `Grid.generate` has made one (all heights 0). The
	/// size and the cell count asked for (which picks the blob and line powers) come from the grid, so they cannot
	/// contradict it. Throws `invalidGrid` if the grid is inconsistent or the diagram was not built from it.
	public init(grid: GridPoints, voronoi: VoronoiDiagram) throws {
		let width = grid.width, height = grid.height, cellsDesired = grid.cellsDesired
		guard voronoi.cells.c.count == grid.points.count else { throw HeightmapError.heightsDoNotMatchCells }
		guard width.isFinite, height.isFinite, width > 0, height > 0, cellsDesired > 0,
			grid.spacing.isFinite, grid.spacing > 0, grid.cellsX > 0, grid.cellsY > 0,
			grid.cellsX == GridPoints.cellsCount(spacing: grid.spacing, size: width),
			grid.cellsY == GridPoints.cellsCount(spacing: grid.spacing, size: height),
			grid.points.count == GridPoints.exactCellPointCount(width: width, height: height, spacing: grid.spacing),
			voronoi.cellPoints == grid.points, voronoi.boundaryPoints == grid.boundary,
			voronoi.cells.c.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0 < grid.points.count } })
		else { throw HeightmapError.invalidGrid }
		self.grid = grid
		self.neighbours = voronoi.cells.c
		self.width = width
		self.height = height
		self.cellsDesired = cellsDesired
		self.heights = [Height](repeating: 0, count: grid.points.count)
		self.blobPower = Self.blobPower(for: cellsDesired)
		self.linePower = Self.linePower(for: cellsDesired)
	}

	/// Runs one step line (`Hill 1 90-100 44-56 40-60`), as the original's `addStep` does for the tools ported so far.
	/// `random` is the generator the original replaces `Math.random` with, seeded from the map's seed; it is advanced.
	public mutating func apply(step line: String, random: inout Alea) throws {
		// The original splits on single spaces, so repeated spaces give it empty strings as arguments. This public runner
		// rejects them: a step is the tool and at least four non-empty arguments separated by single spaces. How tabs, blank
		// lines and comments are handled is decided when the multi-line template runner is ported.
		guard let elements = Self.stepElements(line) else { throw HeightmapError.malformedStep(line) }
		let (tool, a2, a3, a4, a5) = (elements[0], elements[1], elements[2], elements[3], elements[4])
		switch tool {
		case "Hill": try addHill(count: a2, height: a3, rangeX: a4, rangeY: a5, random: &random)
		case "Pit": try addPit(count: a2, height: a3, rangeX: a4, rangeY: a5, random: &random)
		case "Range": try addRange(count: a2, height: a3, rangeX: a4, rangeY: a5, random: &random)
		case "Trough": try addTrough(count: a2, height: a3, rangeX: a4, rangeY: a5, random: &random)
		case "Strait": try addStrait(width: a2, direction: a3, random: &random)
		case "Mask": mask(power: JSParsing.number(a2))
		case "Invert": invert(count: JSParsing.number(a2), axes: a3, random: &random)
		case "Smooth": smooth(fr: JSParsing.number(a2))
		case "Add": modify(range: a3, add: JSParsing.number(a2), mult: 1)
		case "Multiply": modify(range: a3, add: 0, mult: JSParsing.number(a2))
		default: throw HeightmapError.unsupportedTool(tool)
		}
	}

	/// Trims **only ASCII spaces and tabs** from both ends. (Foundation's `.whitespaces` trims more, such as a no-break space,
	/// which would silently change what a line means.)
	static func trimmingSpacesAndTabs(_ line: String) -> String {
		var scalars = Substring(line).unicodeScalars
		while let first = scalars.first, first == " " || first == "\t" { scalars.removeFirst() }
		while let last = scalars.last, last == " " || last == "\t" { scalars.removeLast() }
		return String(scalars)
	}

	/// The parts of a step line, or nil if it is not a step. After the leading and trailing ASCII spaces and tabs are
	/// trimmed, **any whitespace or control or invisible-format character other than an ASCII space is refused**, checked
	/// on Unicode scalars (so a CRLF, which Swift reads as one `Character`, is caught): a tab, a carriage return, a
	/// no-break space or a zero-width space attached to an argument would turn `land` into something else and silently
	/// change the operation. The line needs the tool and four non-empty arguments separated by single ASCII spaces.
	static func stepElements(_ line: String) -> [String]? {
		let trimmed = trimmingSpacesAndTabs(line)
		let unsupported = trimmed.unicodeScalars.contains { scalar in
			scalar != " " && (scalar.properties.isWhitespace || scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format)
		}
		guard !unsupported else { return nil }
		let elements = trimmed.components(separatedBy: " ")
		guard elements.count >= 5, elements.prefix(5).allSatisfy({ !$0.isEmpty }) else { return nil }
		return elements
	}

	/// The original's `getPointInRange`: a coordinate drawn between two percentages of `length`.
	func pointInRange(_ range: String, length: Double, random: inout Alea) -> Double {
		let parts = range.components(separatedBy: "-")
		let low = JSParsing.parseInt(parts[0]) / 100
		let min = (low == 0 || low.isNaN) ? 0 : low // `|| 0`
		let highText = parts.count > 1 ? parts[1] : ""
		let highRaw = JSParsing.parseInt(highText) / 100
		let max = (highRaw == 0 || highRaw.isNaN) ? min : highRaw // `|| min`
		return random.rand(min * length, max * length)
	}

	/// The original's `Grid.findCell(x, y)`: the cell of the regular square grid the points sit on. The row and column are
	/// checked before they become integers, so a non-finite or negative coordinate (or an unrepresentable one) is refused
	/// and never trapped or moved to another cell.
	func findCell(x: Double, y: Double) throws -> Int {
		let row = Swift.min(y / grid.spacing, Double(grid.cellsY - 1)).rounded(.down)
		let column = Swift.min(x / grid.spacing, Double(grid.cellsX - 1)).rounded(.down)
		guard row.isFinite, column.isFinite, row >= 0, column >= 0, row < Double(grid.cellsY), column < Double(grid.cellsX) else { throw HeightmapError.cellOutOfRange }
		return Int(row) * grid.cellsX + Int(column)
	}

	/// The original's `addHill`: `count` hills, each a rise that spreads outward from a start cell, shrinking as it goes.
	mutating func addHill(count: String, height heightText: String, rangeX: String, rangeY: String, random: inout Alea) throws {
		let desiredHillCount = JSParsing.numberInRange(count, random: &random)
		guard desiredHillCount.isFinite, desiredHillCount <= Double(Self.maximumOperations) else { throw HeightmapError.operationCountTooLarge }
		var i = 0.0
		while i < desiredHillCount {
			try addOneHill(height: heightText, rangeX: rangeX, rangeY: rangeY, random: &random)
			i += 1
		}
	}

	private mutating func addOneHill(height heightText: String, rangeX: String, rangeY: String, random: inout Alea) throws {
		var change = [Height](repeating: 0, count: heights.count)
		var limit = 0
		var start: Int
		let h = Heights.limit(JSParsing.numberInRange(heightText, random: &random))

		repeat {
			let x = pointInRange(rangeX, length: width, random: &random)
			let y = pointInRange(rangeY, length: height, random: &random)
			start = try findCell(x: x, y: y)
			guard start < heights.count else { throw HeightmapError.cellOutOfRange }
			limit += 1
		} while Double(heights[start]) + h > 90 && limit < 50

		change[start] = Heights.stored(h)
		var queue = [start]
		var head = 0
		while head < queue.count {
			let q = queue[head]
			head += 1
			for c in neighbours[q] {
				if change[c] != 0 { continue }
				change[c] = Heights.stored(pow(Double(change[q]), blobPower) * (random.next() * 0.2 + 0.9))
				if change[c] > 1 { queue.append(c) }
			}
		}

		for i in heights.indices {
			heights[i] = Heights.stored(Heights.limit(Double(heights[i]) + Double(change[i])))
		}
	}

	/// The original's `modify(range, add, mult, power)` without `power` (no ported step uses it): add to and scale the
	/// heights in a range (`land`, `all`, or `min-max`), keeping land at or above sea level.
	mutating func modify(range: String, add: Double, mult: Double) {
		let min: Double = range == "land" ? 20 : range == "all" ? 0 : JSParsing.number(range.components(separatedBy: "-")[0])
		let max: Double = (range == "land" || range == "all") ? 100 : JSParsing.number(range.components(separatedBy: "-").count > 1 ? range.components(separatedBy: "-")[1] : "")
		let isLand = min == 20

		for i in heights.indices {
			var h = Double(heights[i])
			if h < min || h > max { continue }
			if add != 0 && !add.isNaN { h = isLand ? Swift.max(h + add, 20) : h + add } // `if (add)`: zero and NaN are falsy
			if mult != 1 { h = isLand ? (h - 20) * mult + 20 : h * mult }
			heights[i] = Heights.stored(Heights.limit(h))
		}
	}

	/// The original's `addPit`: `count` pits, each a dip that spreads outward from a start cell over the neighbours,
	/// shrinking as it goes and ending early when it is under 1.
	mutating func addPit(count: String, height heightText: String, rangeX: String, rangeY: String, random: inout Alea) throws {
		let desiredPitCount = JSParsing.numberInRange(count, random: &random)
		guard desiredPitCount.isFinite, desiredPitCount <= Double(Self.maximumOperations) else { throw HeightmapError.operationCountTooLarge }
		var i = 0.0
		while i < desiredPitCount {
			try addOnePit(height: heightText, rangeX: rangeX, rangeY: rangeY, random: &random)
			i += 1
		}
	}

	private mutating func addOnePit(height heightText: String, rangeX: String, rangeY: String, random: inout Alea) throws {
		var used = [Bool](repeating: false, count: heights.count)
		var limit = 0
		var start: Int
		var h = Heights.limit(JSParsing.numberInRange(heightText, random: &random))

		repeat {
			let x = pointInRange(rangeX, length: width, random: &random)
			let y = pointInRange(rangeY, length: height, random: &random)
			start = try findCell(x: x, y: y)
			guard start < heights.count else { throw HeightmapError.cellOutOfRange }
			limit += 1
		} while heights[start] < 20 && limit < 50

		var queue = [start]
		var head = 0
		while head < queue.count {
			let q = queue[head]
			head += 1
			h = pow(h, blobPower) * (random.next() * 0.2 + 0.9) // `h` stays a number here; only the heights are stored as bytes
			if h < 1 { return }

			for c in neighbours[q] {
				if used[c] { continue }
				heights[c] = Heights.stored(Heights.limit(Double(heights[c]) - h * (random.next() * 0.2 + 0.9)))
				used[c] = true
				queue.append(c)
			}
		}
	}

	/// The original's `smooth` as the template operation `Smooth <fr>`: the original's method also takes an `add`, which its
	/// `addStep` never supplies (always 0), so it is left out here and added when a supported caller needs it. Each height becomes a blend of itself and the mean of itself and its
	/// neighbours. Every new height is computed from the old ones (the original maps into a new array). With `fr` 1 the mean
	/// is stored without the clamp, as in the original.
	mutating func smooth(fr: Double) {
		let old = heights
		for i in old.indices {
			let h = Double(old[i])
			var sum = h // d3.mean sums in order: the cell first, then its neighbours
			var count = 1.0
			for c in neighbours[i] {
				sum += Double(old[c])
				count += 1
			}
			let mean = sum / count
			if fr == 1 {
				heights[i] = Heights.stored(mean + 0)
			} else {
				heights[i] = Heights.stored(Heights.limit((h * (fr - 1) + mean + 0) / fr))
			}
		}
	}

	/// The original's `mask(power)`: pulls the heights toward the map's edges (a positive power, an island) or its centre
	/// (negative), blending the masked value with the original by `|power|`; a power of 0 or NaN is treated as 1.
	mutating func mask(power: Double) {
		let fr = (power != 0 && !power.isNaN) ? abs(power) : 1 // `power ? Math.abs(power) : 1`
		for i in heights.indices {
			let point = grid.points[i]
			let nx = (2 * point.x) / width - 1 // [-1, 1], 0 is the centre
			let ny = (2 * point.y) / height - 1
			var distance = (1 - nx * nx) * (1 - ny * ny) // 1 is the centre, 0 is the edge (the port squares by multiplication; every tested `Mask` step matches the original)
			if power < 0 { distance = 1 - distance } // inverted: 0 is the centre, 1 is the edge
			let h = Double(heights[i])
			let masked = h * distance
			heights[i] = Heights.stored(Heights.limit((h * (fr - 1) + masked) / fr))
		}
	}

	/// The original's `invert(count, axes)`: with probability `count` (one draw unless `count` is at least 1 or at most 0),
	/// mirror the map across x, y or both. A cell whose mirrored index is not a cell reads as 0, as `undefined` stores in a
	/// byte array. That fallback is kept as an explicit compatibility behaviour: it can only arise from an invalid grid, which
	/// the initialiser rejects, and changing `invert` alone to throw would add another divergence from the original.
	mutating func invert(count: Double, axes: String, random: inout Alea) {
		guard random.p(count) else { return } // `if (!P(count) ...) return`: NaN is not at most 0 or at least 1, so it draws
		let invertX = axes != "y"
		let invertY = axes != "x"
		let cellsX = grid.cellsX, cellsY = grid.cellsY
		var inverted = [Height](repeating: 0, count: heights.count)
		for i in heights.indices {
			let x = i % cellsX
			let y = i / cellsX
			let nx = invertX ? cellsX - x - 1 : x
			let ny = invertY ? cellsY - y - 1 : y
			let invertedIndex = nx + ny * cellsX
			inverted[i] = invertedIndex >= 0 && invertedIndex < heights.count ? heights[invertedIndex] : 0
		}
		heights = inverted
	}

	// MARK: Range, Trough and Strait

	/// The original's `addRange` as the template operation `Range <count> <height> <rangeX> <rangeY>` (its other parameters,
	/// a fixed start and end cell and the randomness, are never supplied by `addStep` and are left at their defaults).
	mutating func addRange(count: String, height heightText: String, rangeX: String, rangeY: String, random: inout Alea) throws {
		let desiredCount = JSParsing.numberInRange(count, random: &random)
		guard desiredCount.isFinite, desiredCount <= Double(Self.maximumOperations) else { throw HeightmapError.operationCountTooLarge }
		var i = 0.0
		while i < desiredCount {
			try addOneRidge(raising: true, height: heightText, rangeX: rangeX, rangeY: rangeY, randomness: 0.15, random: &random)
			i += 1
		}
	}

	/// The original's `addTrough`: a mirror of `Range` that lowers the land along a line (its start is retried while it is
	/// under 20, its end may be farther, and its path is more random).
	mutating func addTrough(count: String, height heightText: String, rangeX: String, rangeY: String, random: inout Alea) throws {
		let desiredCount = JSParsing.numberInRange(count, random: &random)
		guard desiredCount.isFinite, desiredCount <= Double(Self.maximumOperations) else { throw HeightmapError.operationCountTooLarge }
		var i = 0.0
		while i < desiredCount {
			try addOneRidge(raising: false, height: heightText, rangeX: rangeX, rangeY: rangeY, randomness: 0.2, random: &random)
			i += 1
		}
	}

	/// One ridge (`Range`, raising) or trough (`Trough`, lowering). The two are the same procedure in the original apart from
	/// the places marked below, and they are kept in one function so the draw order cannot drift between them.
	private mutating func addOneRidge(raising: Bool, height heightText: String, rangeX: String, rangeY: String, randomness: Double, random: inout Alea) throws {
		var used = [Bool](repeating: false, count: heights.count)
		var h = Heights.limit(JSParsing.numberInRange(heightText, random: &random))

		// `if (rangeX && rangeY)`: non-empty text is truthy (a step line never has empty arguments)
		var limit = 0
		var startX = 0.0, startY = 0.0
		var startCell: Int
		if raising {
			// Range: one start point
			startX = pointInRange(rangeX, length: width, random: &random)
			startY = pointInRange(rangeY, length: height, random: &random)
			startCell = try findCell(x: startX, y: startY)
		} else {
			// Trough: the start is drawn again while its cell is under 20, at most 50 times
			repeat {
				startX = pointInRange(rangeX, length: width, random: &random)
				startY = pointInRange(rangeY, length: height, random: &random)
				startCell = try findCell(x: startX, y: startY)
				guard startCell < heights.count else { throw HeightmapError.cellOutOfRange }
				limit += 1
			} while heights[startCell] < 20 && limit < 50
		}

		limit = 0
		var endX = 0.0, endY = 0.0
		var dist = 0.0
		let farthest = raising ? width / 3 : width / 2 // Range: a third of the width; Trough: half
		repeat {
			endX = random.next() * width * 0.8 + width * 0.1
			endY = random.next() * height * 0.7 + height * 0.15
			dist = abs(endY - startY) + abs(endX - startX)
			limit += 1
		} while (dist < width / 8 || dist > farthest) && limit < 50
		let endCell = try findCell(x: endX, y: endY)
		guard startCell < heights.count, endCell < heights.count else { throw HeightmapError.cellOutOfRange }

		// the main ridge: step to the unused neighbour nearest the end, halving a distance now and then
		var path = [startCell]
		var cur = startCell
		used[cur] = true
		let threshold = 1 - randomness
		let end = grid.points[endCell]
		while cur != endCell {
			var best = Double.infinity
			var next = cur
			for e in neighbours[cur] {
				if used[e] { continue }
				let p = grid.points[e]
				var diff = (end.x - p.x) * (end.x - p.x) + (end.y - p.y) * (end.y - p.y)
				if random.next() > threshold { diff = diff / 2 }
				if diff < best {
					best = diff
					next = e
				}
			}
			if best == Double.infinity { break }
			cur = next
			path.append(cur)
			used[cur] = true
		}

		// add (or take away) height along the ridge and on rings of cells around it
		var queue = path
		var rounds = 0
		while !queue.isEmpty {
			let frontier = queue
			queue = []
			rounds += 1
			for cell in frontier {
				let change = h * (random.next() * 0.3 + 0.85)
				heights[cell] = Heights.stored(Heights.limit(Double(heights[cell]) + (raising ? change : -change)))
			}
			h = pow(h, linePower) - 1
			if h < 2 { break }
			for f in frontier {
				for neighbour in neighbours[f] where !used[neighbour] {
					queue.append(neighbour)
					used[neighbour] = true
				}
			}
		}

		// prominences: from every sixth cell of the ridge, step downhill `rounds` times, blending heights
		for (d, start) in path.enumerated() where d % 6 == 0 {
			var current = start
			for _ in 0..<rounds {
				guard let downhill = leastIndex(of: neighbours[current]) else { continue }
				heights[downhill] = Heights.stored((Double(heights[current]) * 2 + Double(heights[downhill])) / 3)
				current = downhill
			}
		}
	}

	/// d3's `leastIndex` over the neighbours by height: the first cell of the lowest height, or nil if there are none.
	private func leastIndex(of cells: [Int]) -> Int? {
		guard var best = cells.first else { return nil }
		for c in cells.dropFirst() where heights[c] < heights[best] { best = c }
		return best
	}

	/// The step budget of a strait path: ten times the number of cells. A provisional safety policy, not a demonstrated
	/// convergence bound: the original's walk has no visited-cell check, so it is not known to end.
	var straitStepBudget: Int { heights.count * 10 }

	/// The original's `addStrait(width, direction)`: a channel of water across the map, from one side to the other, widened
	/// by lowering the cells around the path.
	///
	/// The width is processed in two stages, as in the original: `getNumberInRange` reads it (drawing if it is a range or a
	/// fraction), and it is capped at a third of the cells across; then, if it is **under 1**, a draw with that probability
	/// **skips the strait altogether** (a chance to skip, not a chance to apply). A strait that is not skipped runs even if
	/// its width is under 1 (one ring).
	///
	/// - Parameters:
	///   - stepBudget: the most steps the path may take; the default is `straitStepBudget`. The path is checked before each
	///     step while the end is not reached, so a path that reaches the end on exactly its last allowed step succeeds.
	///     Exhausting it throws `pathDidNotConverge` before any height is changed.
	mutating func addStrait(width widthText: String, direction: String, random: inout Alea, stepBudget: Int? = nil) throws {
		let desiredWidth = Swift.min(JSParsing.numberInRange(widthText, random: &random), Double(grid.cellsX) / 3)
		if desiredWidth < 1 && random.p(desiredWidth) { return }
		var used = [Bool](repeating: false, count: heights.count)
		let vertical = direction == "vertical"
		let startX = vertical ? (random.next() * width * 0.4 + width * 0.3).rounded(.down) : 5
		let startY = vertical ? 5 : (random.next() * height * 0.4 + height * 0.3).rounded(.down)
		let endX = vertical ? (width - startX - width * 0.1 + random.next() * width * 0.2).rounded(.down) : width - 5
		let endY = vertical ? height - 5 : (height - startY - height * 0.1 + random.next() * height * 0.2).rounded(.down)

		let start = try findCell(x: startX, y: startY)
		let end = try findCell(x: endX, y: endY)
		guard start < heights.count, end < heights.count else { throw HeightmapError.cellOutOfRange }

		// the path to the far side. The original has no visited-cell check here, so it could in principle wander forever; a
		// step budget stops that and reports it (a path that reaches the end within the budget is unaffected)
		var path: [Int] = []
		var cur = start
		let target = grid.points[end]
		let budget = stepBudget ?? straitStepBudget
		while cur != end {
			if path.count >= budget { throw HeightmapError.pathDidNotConverge }
			var best = Double.infinity
			var next = cur
			for e in neighbours[cur] {
				let p = grid.points[e]
				var diff = (target.x - p.x) * (target.x - p.x) + (target.y - p.y) * (target.y - p.y)
				if random.next() > 0.8 { diff = diff / 2 }
				if diff < best {
					best = diff
					next = e
				}
			}
			cur = next
			path.append(cur)
		}

		var range = path
		var query: [Int] = []
		let step = 0.1 / desiredWidth
		var i = 0.0
		while i < desiredWidth {
			let remainingWidth = desiredWidth - i
			let exponent = 0.9 - step * remainingWidth
			for r in range {
				for e in neighbours[r] {
					if used[e] { continue }
					used[e] = true
					query.append(e)
					heights[e] = Heights.stored(pow(Double(heights[e]), exponent)) // `heights[e] **= exp`, stored as a byte
					if heights[e] > 100 { heights[e] = 5 }
				}
			}
			range = query
			i += 1
		}
	}

	// MARK: Whole maps: templates and scripts

	/// The steps of a script in text form: one step per line. Lines end with `\n`, `\r\n` or a lone `\r` (so a script saved
	/// on Windows reads the same). Each line is trimmed of ASCII spaces and tabs only; **blank lines and lines starting
	/// with `#` are skipped** (documented extensions for hand-written scripts: the original's templates have neither, and its
	/// own runner would reject a blank line). Anything else must be a step (see `apply(step:random:)`), otherwise
	/// `malformedScript` names the line. Any whitespace, control or invisible character other than an ASCII space inside a
	/// line, even one attached to an argument, is refused; a line of only such characters is refused, not skipped.
	public static func steps(fromScript text: String) throws -> [String] {
		let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
		var steps: [String] = []
		for (index, raw) in normalised.components(separatedBy: "\n").enumerated() {
			let line = trimmingSpacesAndTabs(raw)
			if line.isEmpty || line.hasPrefix("#") { continue }
			guard stepElements(line) != nil else { throw HeightmapError.malformedScript(line: index + 1, text: raw) }
			steps.append(line)
		}
		return steps
	}

	/// Makes the heights of a whole map from a template, as the original's `HeightmapGenerator.generate` does: the random
	/// generator is seeded from `seed`, then the template's steps run in order on a blank map. **Stops at the first step that
	/// fails.** This function owns its generator and its random generator locally and returns only the completed heights, so
	/// on failure no partial map and no advanced random stream escapes, and the grid and diagram it was given are unchanged
	/// (unlike the low-level `apply`, which mutates its caller's generator and stream).
	public static func generate(grid: GridPoints, voronoi: VoronoiDiagram, template: HeightmapTemplate, seed: String) throws -> [Height] {
		try generate(grid: grid, voronoi: voronoi, steps: template.steps, seed: seed)
	}

	/// Makes the heights of a whole map from a script of steps (see `steps(fromScript:)`), seeded as above.
	public static func generate(grid: GridPoints, voronoi: VoronoiDiagram, steps: [String], seed: String) throws -> [Height] {
		var generator = try HeightmapGenerator(grid: grid, voronoi: voronoi)
		var random = Alea(seed: seed) // the reset the original performs before it runs a template
		for step in steps { try generator.apply(step: step, random: &random) }
		return generator.heights
	}
}
