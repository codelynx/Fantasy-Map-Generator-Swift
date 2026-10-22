import Foundation
import Testing
@testable import FantasyMapCore

/// Step 4 of docs/plans/land-layer.md, first stage: the step runner, Hill, Add and Multiply, compared with the original's
/// own HeightmapGenerator after every step.
struct HeightmapTests {
	struct Fixture: Decodable {
		struct Run: Decodable {
			var seed: String
			var width: Double
			var height: Double
			var cellsDesired: Int
			var blobPower: Double
			var linePower: Double
			var steps: [String]
			var afterEach: [[Int]]
			var randomStateAfterEach: [[Double]]
		}
		var runs: [Run]
	}

	func runs() throws -> [Fixture.Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("heights-original")).runs }

	func generator(for run: Fixture.Run) throws -> HeightmapGenerator {
		let grid = try GridPoints.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		return try HeightmapGenerator(grid: grid, voronoi: voronoi)
	}

	@Test func everyStepMatchesTheOriginalsHeightsAfterThatStep() throws {
		let runs = try runs()
		#expect(runs.count == 20)
		for run in runs {
			var generator = try generator(for: run)
			var random = Alea(seed: run.seed) // the reset the original performs before it runs a template
			for (index, step) in run.steps.enumerated() {
				try generator.apply(step: step, random: &random)
				let expected = run.afterEach[index].map { Height($0) }
				// the random state too: equal heights could hide different random consumption until a later step
				#expect(random.state == run.randomStateAfterEach[index], "seed \(Array(run.seed.utf16)) \(run.cellsDesired) cells, after step \(index + 1): random state")
				let label = "seed \(Array(run.seed.utf16)) \(run.cellsDesired) cells, after step \(index + 1) (\(step))"
				#expect(generator.heights.count == expected.count, "\(label): length")
				if generator.heights != expected {
					let first = zip(generator.heights, expected).enumerated().first { $0.element.0 != $0.element.1 }
					let differing = zip(generator.heights, expected).filter { $0 != $1 }.count
					Issue.record("\(label): \(differing) cells differ; first at cell \(first?.offset ?? -1): \(first?.element.0 ?? 0) vs the original's \(first?.element.1 ?? 0)")
					break // later steps build on this one; the first difference is the one to look at
				}
			}
		}
	}

	@Test func theBlobAndLinePowersFollowTheOriginalsTables() throws {
		for run in try runs() {
			#expect(HeightmapGenerator.blobPower(for: run.cellsDesired) == run.blobPower, "blob power for \(run.cellsDesired)")
			#expect(HeightmapGenerator.linePower(for: run.cellsDesired) == run.linePower, "line power for \(run.cellsDesired)")
		}
		#expect(HeightmapGenerator.blobPower(for: 24) == 0.98 && HeightmapGenerator.linePower(for: 24) == 0.81) // the fallback
		#expect(HeightmapGenerator.blobPower(for: 100_000) == 0.9973 && HeightmapGenerator.linePower(for: 100_000) == 0.93)
	}

	@Test func theFixtureCoversTheTableEntriesAndTheFallback() throws {
		let counts = Set(try runs().map(\.cellsDesired))
		#expect(counts.isSuperset(of: [1000, 2000, 10000, 24, 300])) // 24 and 300 are not in the tables
	}

	@Test func heightsStayWholeNumbersWithinTheLimitsAfterTheseSteps() throws {
		for run in try runs() {
			var generator = try generator(for: run)
			var random = Alea(seed: run.seed)
			for step in run.steps { try generator.apply(step: step, random: &random) }
			// general invariants only: the length and the limits. That something was raised, or that both land and sea exist,
			// is specific to these fixtures (a zero-count Hill, or Multiply by zero, can legitimately leave everything at 0)
			#expect(generator.heights.count == run.afterEach[0].count)
			#expect(generator.heights.allSatisfy { $0 <= Heights.maximum })
		}
	}

	@Test func theSameSeedAndStepsGiveTheSameHeights() throws {
		let run = try #require(try runs().first)
		var a = try generator(for: run), b = try generator(for: run)
		var ra = Alea(seed: run.seed), rb = Alea(seed: run.seed)
		for step in run.steps { try a.apply(step: step, random: &ra); try b.apply(step: step, random: &rb) }
		#expect(a.heights == b.heights)
	}

	@Test func badStepsAreReportedNotTrapped() throws {
		let run = try #require(try runs().first)
		var generator = try generator(for: run)
		var random = Alea(seed: run.seed)
		#expect(throws: HeightmapError.malformedStep("Hill 1")) { try generator.apply(step: "Hill 1", random: &random) }
		#expect(throws: HeightmapError.unsupportedTool("Dance")) { try generator.apply(step: "Dance 1 2 3 4", random: &random) }
	}

	// MARK: the original's number parsing

	@Test func numberInRangeFollowsTheOriginal() {
		var a = Alea(seed: "n")
		#expect(JSParsing.numberInRange("1", random: &a) == 1) // a whole number: no draw
		#expect(a.state == Alea(seed: "n").state)
		var b = Alea(seed: "n")
		let ranged = JSParsing.numberInRange("5-6", random: &b)
		#expect(ranged == 5 || ranged == 6)
		var c = Alea(seed: "n")
		#expect(JSParsing.numberInRange("not a number", random: &c) == 0)
		var d = Alea(seed: "n")
		let fractional = JSParsing.numberInRange("2.5", random: &d) // 2 plus a one-in-two chance of 3
		#expect(fractional == 2 || fractional == 3)
		var e = Alea(seed: "n")
		#expect(JSParsing.numberInRange("0", random: &e) == 0)
	}

	@Test func theJavaScriptConversionsBehaveLikeTheOriginals() {
		#expect(JSParsing.number("") == 0 && JSParsing.number("  ") == 0)
		#expect(JSParsing.number("-5") == -5 && JSParsing.number("0.8") == 0.8)
		#expect(JSParsing.number("all").isNaN && JSParsing.number("90-100").isNaN)
		#expect(JSParsing.parseInt("44") == 44 && JSParsing.parseInt("40abc") == 40 && JSParsing.parseInt("").isNaN)
		#expect(JSParsing.parseFloat("90") == 90 && JSParsing.parseFloat("2.5x") == 2.5 && JSParsing.parseFloat("x").isNaN)
	}

	// MARK: small independent cases, and the execution boundary

	func blank(width: Double = 100, height: Double = 60, cells: Int = 24, seed: String = "k") throws -> HeightmapGenerator {
		let grid = try GridPoints.generate(seed: seed, width: width, height: height, cellsDesired: cells)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		return try HeightmapGenerator(grid: grid, voronoi: voronoi)
	}

	@Test func addOnABlankMapAndTheLandOnlyBehaviourAroundSeaLevel() throws {
		var g = try blank()
		var random = Alea(seed: "k")
		let before = random.state
		try g.apply(step: "Add 7 all 0 0", random: &random)
		#expect(g.heights.allSatisfy { $0 == 7 })
		try g.apply(step: "Add 30 all 0 0", random: &random)
		#expect(g.heights.allSatisfy { $0 == 37 })
		// `land` adds at least up to sea level: land stays at or above 20; water is untouched
		var mixed = try blank()
		mixed.setHeightsForTesting([0, 10, 19, 20, 21, 50, 100] + [Height](repeating: 0, count: 17))
		try mixed.apply(step: "Add 5 land 0 0", random: &random)
		#expect(Array(mixed.heights.prefix(7)) == [0, 10, 19, 25, 26, 55, 100]) // 20 + 5, 21 + 5, 50 + 5, 100 clamped
		try mixed.apply(step: "Add -5 land 0 0", random: &random)
		#expect(Array(mixed.heights.prefix(7)) == [0, 10, 19, 20, 21, 50, 95]) // a land cell never drops below 20
		#expect(random.state == before) // Add and Multiply never draw
	}

	@Test func multiplyByZeroAndOneAndOnLandOnly() throws {
		var g = try blank()
		var random = Alea(seed: "k")
		let before = random.state
		g.setHeightsForTesting([0, 10, 20, 40, 100] + [Height](repeating: 60, count: 19))
		try g.apply(step: "Multiply 1 all 0 0", random: &random)
		#expect(Array(g.heights.prefix(5)) == [0, 10, 20, 40, 100]) // by one: nothing changes
		try g.apply(step: "Multiply 0 land 0 0", random: &random)
		#expect(Array(g.heights.prefix(5)) == [0, 10, 20, 20, 20]) // land scaled about sea level: (h - 20) * 0 + 20
		try g.apply(step: "Multiply 0 all 0 0", random: &random)
		#expect(g.heights.allSatisfy { $0 == 0 })
		try g.apply(step: "Multiply 0.5 all 0 0", random: &random)
		#expect(g.heights.allSatisfy { $0 == 0 })
		#expect(random.state == before)
		// the original's NaN: not a number scales to NaN, which a byte array stores as 0
		var h = try blank()
		h.setHeightsForTesting([Height](repeating: 33, count: 24))
		try h.apply(step: "Multiply x all 0 0", random: &random)
		#expect(h.heights.allSatisfy { $0 == 0 })
	}

	@Test func aZeroCountHillLeavesEverythingAtZeroAndTheBoundaryIsEnforced() throws {
		var g = try blank()
		var random = Alea(seed: "k")
		try g.apply(step: "Hill 0 90-100 44-56 40-60", random: &random)
		#expect(g.heights.allSatisfy { $0 == 0 })
		// an infinite or impractical count is refused before any work
		#expect(throws: HeightmapError.operationCountTooLarge) { try g.apply(step: "Hill 1-Infinity 90-100 44-56 40-60", random: &random) }
		#expect(throws: HeightmapError.operationCountTooLarge) { try g.apply(step: "Hill 1000000 90-100 44-56 40-60", random: &random) }
		// the original reads the count "Infinity" as `~~Infinity` (0) plus P(Infinity), which is true: one hill, not infinitely many
		try g.apply(step: "Hill Infinity 90-100 44-56 40-60", random: &random)
		#expect(g.heights.contains { $0 > 0 })
		// repeated spaces would leave empty arguments: rejected here (the original would read them as undefined)
		#expect(throws: HeightmapError.malformedStep("Hill  1 90-100 44-56 40-60")) { try g.apply(step: "Hill  1 90-100 44-56 40-60", random: &random) }
		// a range far beyond the map is not an error: the original's own `Math.min` clamps it to the last column (a hill at the edge)
		var edge = try blank()
		try edge.apply(step: "Hill 1 90-100 1000-2000 40-60", random: &random)
		#expect(edge.heights.contains { $0 > 0 })
	}

	@Test func findCellRefusesNonFiniteAndNegativeCoordinates() throws {
		let g = try blank()
		#expect(throws: HeightmapError.cellOutOfRange) { try g.findCell(x: .nan, y: 5) }
		#expect(throws: HeightmapError.cellOutOfRange) { try g.findCell(x: -1, y: 5) }
		#expect(throws: HeightmapError.cellOutOfRange) { try g.findCell(x: 5, y: -0.5) }
		#expect(throws: HeightmapError.cellOutOfRange) { try g.findCell(x: 1e300, y: -1e300) }
		// +infinity and anything beyond the far edge are clamped to the last row and column by the original's own `Math.min`
		#expect(try g.findCell(x: 5, y: .infinity) == g.grid.cellsX * (g.grid.cellsY - 1) + Int((5 / g.grid.spacing).rounded(.down)))
		#expect(try g.findCell(x: 0, y: 0) == 0)
		let last = try g.findCell(x: 1e9, y: 1e9) // beyond the far edge: the original clamps to the last row and column
		#expect(last == g.grid.cellsX * g.grid.cellsY - 1)
	}

	@Test func theInitialiserRejectsInconsistentInputAndADiagramFromAnotherGrid() throws {
		let grid = try GridPoints.generate(seed: "k", width: 100, height: 60, cellsDesired: 24)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		var zero = grid; zero.width = 0
		#expect(throws: HeightmapError.invalidGrid) { try HeightmapGenerator(grid: zero, voronoi: voronoi) }
		var nan = grid; nan.height = .nan
		#expect(throws: HeightmapError.invalidGrid) { try HeightmapGenerator(grid: nan, voronoi: voronoi) }
		var noCells = grid; noCells.cellsDesired = 0
		#expect(throws: HeightmapError.invalidGrid) { try HeightmapGenerator(grid: noCells, voronoi: voronoi) }
		// a size that is not the one the grid was made for
		var wrongSize = grid; wrongSize.width = 5000
		#expect(throws: HeightmapError.invalidGrid) { try HeightmapGenerator(grid: wrongSize, voronoi: voronoi) }
		// a size with the same cell counts but a different point count (cells across and down alone do not establish it)
		var sameCountsDifferentSize = grid; sameCountsDifferentSize.width = grid.width + grid.spacing * 0.3
		#expect(throws: HeightmapError.invalidGrid) { try HeightmapGenerator(grid: sameCountsDifferentSize, voronoi: voronoi) }
		// a diagram built from another grid's points (same number of cells, different points)
		let other = try GridPoints.generate(seed: "another", width: 100, height: 60, cellsDesired: 24)
		let otherDiagram = try VoronoiDiagram.calculate(points: other.points, boundary: other.boundary)
		#expect(other.points.count == grid.points.count && other.points != grid.points)
		#expect(throws: HeightmapError.invalidGrid) { try HeightmapGenerator(grid: grid, voronoi: otherDiagram) }
		// a diagram with a different number of cells
		let fewer = try VoronoiDiagram.calculate(points: Array(grid.points.dropLast()), boundary: grid.boundary)
		#expect(throws: HeightmapError.heightsDoNotMatchCells) { try HeightmapGenerator(grid: grid, voronoi: fewer) }
		// the size and the cell count come from the grid, so a valid pair needs no separate copies
		_ = try HeightmapGenerator(grid: grid, voronoi: voronoi)
	}

	@Test func theFixtureCoversEveryPortedToolAndBothOutcomesOfAChanceInvert() throws {
		let runs = try runs()
		let tools = Set(runs.flatMap(\.steps).map { String($0.split(separator: " ")[0]) })
		#expect(tools == ["Hill", "Pit", "Range", "Trough", "Strait", "Add", "Multiply", "Smooth", "Mask", "Invert"])
		// a fractional Invert changes the map or leaves it, depending on its draw: the fixture holds both
		var outcomes = Set<Bool>()
		for run in runs {
			for (i, step) in run.steps.enumerated() where i > 0 && step.hasPrefix("Invert 0.") {
				outcomes.insert(run.afterEach[i] != run.afterEach[i - 1])
			}
		}
		#expect(outcomes == [true, false])
	}

	@Test func smoothOnAFlatMapChangesNothingAndASpikeSpreadsToItsNeighbours() throws {
		var g = try blank()
		var random = Alea(seed: "k")
		let before = random.state
		g.setHeightsForTesting([Height](repeating: 40, count: 24))
		try g.apply(step: "Smooth 2 0 0 0", random: &random)
		#expect(g.heights.allSatisfy { $0 == 40 })
		var spike = [Height](repeating: 0, count: 24)
		spike[10] = 100
		g.setHeightsForTesting(spike)
		try g.apply(step: "Smooth 1 0 0 0", random: &random) // fr 1: the plain mean of the cell and its neighbours
		#expect(g.heights[10] < 100 && g.heights[10] > 0)
		let neighbours = g.neighbours[10]
		#expect(neighbours.allSatisfy { g.heights[$0] > 0 || g.neighbours[$0].isEmpty })
		#expect(random.state == before) // Smooth never draws
	}

	@Test func maskPullsTheEdgesDownAndANegativePowerPullsTheCentreDown() throws {
		var g = try blank()
		var random = Alea(seed: "k")
		let before = random.state
		g.setHeightsForTesting([Height](repeating: 80, count: 24))
		try g.apply(step: "Mask 1 0 0 0", random: &random) // power 1: fully masked
		let points = g.grid.points
		let centre = points.indices.min { abs(points[$0].x - 50) + abs(points[$0].y - 30) < abs(points[$1].x - 50) + abs(points[$1].y - 30) }!
		let corner = points.indices.min { points[$0].x + points[$0].y < points[$1].x + points[$1].y }!
		#expect(g.heights[centre] > g.heights[corner])
		g.setHeightsForTesting([Height](repeating: 80, count: 24))
		try g.apply(step: "Mask -1 0 0 0", random: &random) // inverted: the edge keeps its height, the centre drops
		#expect(g.heights[corner] > g.heights[centre])
		g.setHeightsForTesting([Height](repeating: 80, count: 24))
		try g.apply(step: "Mask 0 0 0 0", random: &random) // 0 is treated as 1
		var one = try blank()
		one.setHeightsForTesting([Height](repeating: 80, count: 24))
		try one.apply(step: "Mask 1 0 0 0", random: &random)
		#expect(g.heights == one.heights)
		#expect(random.state == before) // Mask never draws
	}

	@Test func invertMirrorsTheMapAndDrawsOnlyForAChanceBetweenZeroAndOne() throws {
		var g = try blank()
		var random = Alea(seed: "k")
		let start = (0..<24).map { Height($0 * 4) }
		g.setHeightsForTesting(start)
		let before = random.state
		try g.apply(step: "Invert 1 both 0 0", random: &random)
		#expect(random.state == before) // a count of 1 is certain: no draw
		let (cx, cy) = (g.grid.cellsX, g.grid.cellsY)
		#expect(cx * cy == 24)
		for i in 0..<24 {
			let mirrored = (cx - i % cx - 1) + (cy - i / cx - 1) * cx
			#expect(g.heights[i] == start[mirrored])
		}
		try g.apply(step: "Invert 1 both 0 0", random: &random)
		#expect(g.heights == start) // twice is the identity
		try g.apply(step: "Invert 0 x 0 0", random: &random)
		#expect(g.heights == start && random.state == before) // a count of 0 never inverts and never draws
		var drawn = Alea(seed: "k")
		_ = drawn.next()
		try g.apply(step: "Invert 0.5 x 0 0", random: &random)
		#expect(random.state == drawn.state) // a fractional count draws once
	}

	@Test func pitLowersHeightsAroundItsStartAndNeverGoesBelowZero() throws {
		var g = try blank(width: 400, height: 300, cells: 600)
		var random = Alea(seed: "k")
		g.setHeightsForTesting([Height](repeating: 60, count: g.heights.count))
		try g.apply(step: "Pit 2 40-50 20-80 20-80", random: &random)
		#expect(g.heights.contains { $0 < 60 })
		#expect(g.heights.allSatisfy { $0 <= 60 }) // a pit only lowers
		var flat = try blank()
		flat.setHeightsForTesting([Height](repeating: 5, count: 24)) // below 20: the start search gives up after 50 tries and still digs
		try flat.apply(step: "Pit 1 90-100 20-80 20-80", random: &random)
		#expect(flat.heights.allSatisfy { $0 <= 5 })
	}

	/// Flat-map cases only: on uneven terrain the prominence pass blends a neighbour toward `(2 * current + neighbour) / 3`,
	/// which can raise or lower it, so these show those particular results and not that a range always raises or a trough
	/// always lowers.
	@Test func onAFlatMapARangeRaisesATroughLowersAndAStraitLowers() throws {
		var random = Alea(seed: "k")
		var g = try blank(width: 400, height: 300, cells: 2000)
		g.setHeightsForTesting([Height](repeating: 50, count: g.heights.count))
		try g.apply(step: "Range 1 40-50 20-80 20-80", random: &random)
		#expect(g.heights.allSatisfy { $0 >= 50 } && g.heights.contains { $0 > 50 }) // on a flat map a range adds
		g.setHeightsForTesting([Height](repeating: 50, count: g.heights.count))
		try g.apply(step: "Trough 2 20-30 20-80 20-80", random: &random)
		#expect(g.heights.allSatisfy { $0 <= 50 } && g.heights.contains { $0 < 50 }) // on a flat map a trough takes away
		g.setHeightsForTesting([Height](repeating: 50, count: g.heights.count))
		try g.apply(step: "Strait 2 vertical 0 0", random: &random)
		#expect(g.heights.allSatisfy { $0 <= 50 } && g.heights.contains { $0 < 50 }) // a strait lowers
		g.setHeightsForTesting([Height](repeating: 50, count: g.heights.count))
		try g.apply(step: "Strait 2 horizontal 0 0", random: &random)
		#expect(g.heights.contains { $0 < 50 })
	}

	@Test func straitWithAWholeWidthDrawsNoChanceAndAWidthOfZeroStopsWithoutDrawing() throws {
		var g = try blank(width: 400, height: 300, cells: 2000)
		var a = Alea(seed: "k")
		let before = a.state
		try g.apply(step: "Strait 1 vertical 0 0", random: &a)
		#expect(a.state != before) // the start, the end and the path draw
		// width 0 (under 1): P(0) is false without drawing, the loop `i < 0` never runs, and the map is untouched; the
		// two start and end draws and the path's draws still happen first, as in the original
		var tiny = try blank(width: 400, height: 300, cells: 2000)
		var c = Alea(seed: "k")
		try tiny.apply(step: "Strait 0 vertical 0 0", random: &c)
		#expect(tiny.heights.allSatisfy { $0 == 0 })
	}

	@Test func theStraitStepBudgetIsCheckedBeforeEachStepAndTheLastAllowedStepSucceeds() throws {
		// the path length on this grid, found by raising a small budget until the strait succeeds
		// the grid and diagram are built once and the generator is copied for each attempt
		var baseline = try blank(width: 400, height: 300, cells: 2000)
		baseline.setHeightsForTesting([Height](repeating: 50, count: baseline.heights.count))
		func run(budget: Int?) throws -> (heights: [Height], state: [Double]) {
			var g = baseline
			var random = Alea(seed: "k")
			try g.addStrait(width: "2", direction: "vertical", random: &random, stepBudget: budget)
			return (g.heights, random.state)
		}
		let reference = try run(budget: nil)
		var needed = 1
		while true {
			do { _ = try run(budget: needed); break } catch HeightmapError.pathDidNotConverge { needed += 1 }
			if needed > 100_000 { Issue.record("no budget succeeded"); return }
		}
		#expect(needed > 1)
		let exact = try run(budget: needed) // reaches the end on exactly its last allowed step: succeeds, same result
		#expect(exact.heights == reference.heights && exact.state == reference.state)
		#expect(throws: HeightmapError.pathDidNotConverge) { try run(budget: needed - 1) } // one step short: refused
		// failure changes no height, though the random stream has advanced
		var g = baseline
		var random = Alea(seed: "k")
		let before = random.state
		#expect(throws: HeightmapError.pathDidNotConverge) { try g.addStrait(width: "2", direction: "vertical", random: &random, stepBudget: needed - 1) }
		#expect(g.heights.allSatisfy { $0 == 50 })
		#expect(random.state != before)
		#expect(g.straitStepBudget == g.heights.count * 10)
	}

	@Test func theFixtureHasEveryToolWithEffect() throws {
		var changed = Set<String>()
		for run in try runs() {
			var previous = [Int](repeating: 0, count: run.afterEach[0].count)
			for (i, step) in run.steps.enumerated() {
				if run.afterEach[i] != previous { changed.insert(String(step.split(separator: " ")[0])) }
				previous = run.afterEach[i]
			}
		}
		#expect(changed == ["Hill", "Pit", "Range", "Trough", "Strait", "Add", "Multiply", "Smooth", "Mask", "Invert"])
	}

	@Test func theNumberParsingIsTheTemplateSubsetNotAllOfJavaScript() {
		// decimal numbers and min-max ranges are supported; hexadecimal and other JavaScript literals read as NaN
		#expect(JSParsing.number("0x10").isNaN)
		#expect(JSParsing.number("1e3") == 1000)
		#expect(JSParsing.number("90-100").isNaN)
	}
}

extension HeightmapGenerator {
	/// Test support: starts from chosen heights instead of the blank map.
	mutating func setHeightsForTesting(_ values: [Height]) { precondition(values.count == heights.count); setHeights(values) }
}
