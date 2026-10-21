import Foundation
import Testing
@testable import FantasyMapKit

/// Step 2 of docs/plans/land-layer.md: the grid points against the original's own `Grid.generate`.
struct GridPointsTests {
	struct Fixture: Decodable {
		struct Grid: Decodable {
			var seed: String
			var width: Double
			var height: Double
			var cellsDesired: Int
			var spacing: Double
			var cellsX: Int
			var cellsY: Int
			var points: [Point]
			var boundary: [Point]
		}
		var grids: [Grid]
	}

	func load(_ name: String) throws -> [Fixture.Grid] {
		try JSONDecoder().decode(Fixture.self, from: Fixtures.data(name)).grids
	}

	@Test func theOriginalsOwnGeneratorGivesTheSamePointsForEveryFixtureGrid() throws {
		let grids = try load("grid-original")
		#expect(grids.count == 8)
		for grid in grids {
			let made = try GridPoints.generate(seed: grid.seed, width: grid.width, height: grid.height, cellsDesired: grid.cellsDesired)
			let label = "seed \(Array(grid.seed.utf16)) \(Int(grid.width))x\(Int(grid.height)) \(grid.cellsDesired) cells"
			#expect(made.spacing == grid.spacing, "\(label): spacing")
			#expect(made.cellsX == grid.cellsX && made.cellsY == grid.cellsY, "\(label): cells across and down")
			#expect(made.boundary == grid.boundary, "\(label): boundary points")
			#expect(made.points.count == grid.points.count, "\(label): point count")
			#expect(made.points == grid.points, "\(label): points")
		}
	}

	@Test func theFixtureIncludesTheOriginalsDefaultMapAndTheTwoAccentSpellings() throws {
		let grids = try load("grid-original")
		#expect(grids.contains { $0.width == 1280 && $0.height == 800 && $0.cellsDesired == 10000 })
		let accents = grids.filter { $0.seed.utf16.count <= 2 && !$0.seed.isEmpty && $0.cellsDesired == 1000 }
		#expect(Set(accents.map { Array($0.seed.utf16) }) == [[0x00E9], [0x0065, 0x0301]])
		#expect(accents.count == 2 && accents[0].points != accents[1].points)
	}

	@Test func theEarlierTranscriptionFixtureAgreesWithTheOriginalsOwnRun() throws {
		let own = try load("grid-original").prefix(3)
		let transcribed = try load("grid")
		#expect(transcribed.count == 3)
		for (a, b) in zip(own, transcribed) {
			#expect(a.points == b.points && a.boundary == b.boundary && a.spacing == b.spacing, "seed \(Array(a.seed.utf16))")
		}
	}

	@Test func pointsStayInsideTheMapAndTheSameSeedGivesTheSamePoints() throws {
		let a = try GridPoints.generate(seed: "kaz-1", width: 640, height: 400, cellsDesired: 2000)
		let b = try GridPoints.generate(seed: "kaz-1", width: 640, height: 400, cellsDesired: 2000)
		let c = try GridPoints.generate(seed: "kaz-2", width: 640, height: 400, cellsDesired: 2000)
		#expect(a == b)
		#expect(a.points != c.points)
		#expect(a.points.allSatisfy { $0.x >= 0 && $0.x <= 640 && $0.y >= 0 && $0.y <= 400 })
		#expect(abs(a.points.count - 2000) < 200) // close to the cells asked for, not equal
	}

	@Test func tinyAndOddSizesStillMakePoints() throws {
		let tiny = try GridPoints.generate(seed: "x", width: 10, height: 10, cellsDesired: 1)
		#expect(tiny.points.count >= 1)
		let narrow = try GridPoints.generate(seed: "x", width: 3, height: 500, cellsDesired: 50)
		#expect(narrow.points.count > 0) // not vacuous: allSatisfy on an empty array would pass
		#expect(narrow.points.allSatisfy { $0.x <= 3 && $0.y <= 500 })
	}

	@Test func unsafeInputsThrowPromptlyInsteadOfHangingOrTrapping() {
		// spacing that rounds to zero (a normal-looking tiny map with a huge cell count)
		#expect(throws: GridPointsError.unusableSpacing) { try GridPoints.generate(seed: "x", width: 0.001, height: 0.001, cellsDesired: 1_000_000) }
		// finite dimensions whose area overflows to infinity
		#expect(throws: GridPointsError.unusableSpacing) { try GridPoints.generate(seed: "x", width: 1e200, height: 1e200, cellsDesired: 10) }
		// an area that underflows
		#expect(throws: GridPointsError.unusableSpacing) { try GridPoints.generate(seed: "x", width: 1e-200, height: 1e-200, cellsDesired: 10) }
		// counts that would be allocated: far above the budget, and one just above it
		// Int.max cells on a normal map: the spacing rounds to zero, which is caught first
		#expect(throws: GridPointsError.unusableSpacing) { try GridPoints.generate(seed: "x", width: 1280, height: 800, cellsDesired: Int.max) }
		// a huge map with a usable spacing: about 100 million points
		#expect(throws: GridPointsError.tooManyPoints) { try GridPoints.generate(seed: "x", width: 1e6, height: 1e6, cellsDesired: 100_000_000) }
		#expect(throws: GridPointsError.tooManyPoints) { try GridPoints.generate(seed: "x", width: 1280, height: 800, cellsDesired: 500_000) }
	}

	@Test func theAdmissionEstimateIsConservativeOnPurpose() throws {
		// 1000 x 1000 with 198,500 cells asked: the loops would make 198,916 points, under the 200,000 ceiling, but the
		// estimate (size / spacing + 1 in each direction, about 200,192) is over it, so the map is refused
		let spacing = GridPoints.spacing(cellsDesired: 198_500, width: 1000, height: 1000)
		#expect(GridPoints.exactCellPointCount(width: 1000, height: 1000, spacing: spacing) == 198_916)
		#expect(198_916 <= GridPoints.maximumPoints)
		#expect(throws: GridPointsError.tooManyPoints) { try GridPoints.generate(seed: "x", width: 1000, height: 1000, cellsDesired: 198_500) }
		// a request comfortably under the estimate is accepted
		#expect(try GridPoints.generate(seed: "x", width: 1000, height: 1000, cellsDesired: 150_000).points.count <= GridPoints.maximumPoints)
	}

	@Test func theExactCountMatchesThePointsActuallyMade() throws {
		for (w, h, n) in [(1280.0, 800.0, 10_000), (100, 60, 24), (90, 1000, 300)] {
			let made = try GridPoints.generate(seed: "k", width: w, height: h, cellsDesired: n)
			#expect(made.points.count == GridPoints.exactCellPointCount(width: w, height: h, spacing: made.spacing))
		}
	}

	@Test func theBudgetAllowsTheOriginalsLargestDensityStep() throws {
		let made = try GridPoints.generate(seed: "kaz-1", width: 1280, height: 800, cellsDesired: 100_000)
		#expect(made.points.count > 90_000 && made.points.count <= GridPoints.maximumPoints)
		#expect(made.boundary.count <= GridPoints.maximumPoints)
	}

	@Test func aMapWithNoRoomForACellPointIsRefusedHere() {
		// a very thin map: the spacing is much larger than the map's height, so no row of points fits
		#expect(throws: GridPointsError.noCellPoints) { try GridPoints.generate(seed: "x", width: 1000, height: 1, cellsDesired: 1) }
	}

	@Test func badInputIsRefused() {
		#expect(throws: GridPointsError.invalidSize) { try GridPoints.generate(seed: "x", width: 0, height: 10, cellsDesired: 10) }
		#expect(throws: GridPointsError.invalidSize) { try GridPoints.generate(seed: "x", width: 10, height: .nan, cellsDesired: 10) }
		#expect(throws: GridPointsError.invalidSize) { try GridPoints.generate(seed: "x", width: -1, height: 10, cellsDesired: 10) }
		#expect(throws: GridPointsError.invalidCellCount) { try GridPoints.generate(seed: "x", width: 10, height: 10, cellsDesired: 0) }
	}

	@Test func javaScriptRoundingRoundsHalvesTowardPositiveInfinity() {
		#expect(JSNumber.round(2.5) == 3)
		#expect(JSNumber.round(-2.5) == -2) // Swift's default would give -3
		#expect(JSNumber.round(-0.5) == 0)
		#expect(JSNumber.round(0.49999999999999994) == 0) // floor(x + 0.5) would give 1
		#expect(JSNumber.round(1.4999999999999998) == 1)
		#expect(JSNumber.rn(15.8149, 2) == 15.81)
		#expect(JSNumber.rn(-15.81) == -16)
		#expect(JSNumber.rn(3.345, 2) == 3.35) // 3.345 * 100 is 334.5 in a Double, so the half rounds up, as in JavaScript (checked in Node)
	}
}
