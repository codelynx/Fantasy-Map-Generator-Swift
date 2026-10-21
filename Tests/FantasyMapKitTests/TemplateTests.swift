import CryptoKit
import Foundation
import Testing
@testable import FantasyMapKit

/// Step 4, stage 4: the template table and the whole-map runner, against the original's own `HeightmapGenerator.generate`.
struct TemplateTests {
	struct Fixture: Decodable {
		struct Template: Decodable { var key: String; var id: Int; var name: String; var template: String; var probability: Int }
		struct Result: Decodable {
			var key: String
			var heightsSha256: String
			var cells: Int
			var landCells: Int
			var randomState: [Double]
			var heights: [Int]?
		}
		struct Run: Decodable {
			var seed: String
			var width: Double
			var height: Double
			var cellsDesired: Int
			var results: [Result]
		}
		var templates: [Template]
		var runs: [Run]
	}

	func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("templates-original")) }

	@Test func theTemplateTableIsTheOriginalsOwnInOrderWithItsStepsAndProbabilities() throws {
		let original = try fixture().templates
		#expect(original.count == 14 && HeightmapTemplate.all.count == 14)
		for (mine, theirs) in zip(HeightmapTemplate.all, original) {
			#expect(mine.key == theirs.key && mine.id == theirs.id && mine.name == theirs.name && mine.probability == theirs.probability, "\(theirs.key)")
			// the original's text, split into lines and trimmed, is the port's step list
			#expect(mine.steps == theirs.template.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }, "\(theirs.key): steps")
		}
		#expect(HeightmapTemplate.all.map(\.id) == Array(0..<14))
		#expect(HeightmapTemplate.named("highIsland")?.name == "High Island" && HeightmapTemplate.named("nope") == nil)
	}

	@Test func everyTemplateMakesTheOriginalsMapOnEveryFixtureGridIncludingTheRandomState() throws {
		let runs = try fixture().runs
		#expect(runs.count == 4)
		for run in runs {
			let grid = try GridPoints.generate(seed: run.seed, width: run.width, height: run.height, cellsDesired: run.cellsDesired)
			let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
			for expected in run.results {
				let label = "\(expected.key), seed \(Array(run.seed.utf16)), \(run.cellsDesired) cells"
				let template = try #require(HeightmapTemplate.named(expected.key))
				var generator = try HeightmapGenerator(grid: grid, voronoi: voronoi)
				var random = Alea(seed: run.seed)
				for step in template.steps { try generator.apply(step: step, random: &random) }
				let heights = generator.heights
				#expect(heights.count == expected.cells, "\(label): cells")
				let digest = SHA256.hash(data: Data(heights)).map { String(format: "%02x", $0) }.joined()
				#expect(digest == expected.heightsSha256, "\(label): every height (SHA-256 of the bytes)")
				#expect(heights.filter { Heights.isLand($0) }.count == expected.landCells, "\(label): land cells")
				#expect(random.state == expected.randomState, "\(label): random state")
				if let full = expected.heights { #expect(heights == full.map { Height($0) }, "\(label): heights cell for cell") }
				// the same through the public whole-map entry point
				#expect(try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: run.seed) == heights, "\(label): generate")
			}
		}
	}

	@Test func theFixtureCoversAllFourteenTemplatesOnFourGrids() throws {
		for run in try fixture().runs { #expect(Set(run.results.map(\.key)) == Set(HeightmapTemplate.all.map(\.key))) }
	}

	@Test func scriptsAreOneStepPerLineWithBlankLinesAndCommentsSkipped() throws {
		let text = """
		# a small island
		Hill 1 90-100 44-56 40-60

		\tAdd 7 all 0 0   
		   # trailing comment line
		Multiply 0.8 land 0 0
		"""
		#expect(try HeightmapGenerator.steps(fromScript: text) == ["Hill 1 90-100 44-56 40-60", "Add 7 all 0 0", "Multiply 0.8 land 0 0"])
		#expect(try HeightmapGenerator.steps(fromScript: "") == [])
		#expect(throws: HeightmapError.malformedScript(line: 2, text: "Hill 1")) { try HeightmapGenerator.steps(fromScript: "Add 1 all 0 0\nHill 1") }
		#expect(throws: HeightmapError.malformedScript(line: 1, text: "Hill\t1 90-100 44-56 40-60")) { try HeightmapGenerator.steps(fromScript: "Hill\t1 90-100 44-56 40-60") } // a tab is not a separator
		#expect(throws: HeightmapError.malformedScript(line: 1, text: "Hill  1 90-100 44-56 40-60")) { try HeightmapGenerator.steps(fromScript: "Hill  1 90-100 44-56 40-60") }
	}

	@Test func aTabInsideALineIsRefusedEvenWhenAttachedToAnArgument() throws {
		// "land<tab>" would not be "land", silently changing the operation
		#expect(throws: HeightmapError.malformedScript(line: 1, text: "Add 7 land\t 0 0")) { try HeightmapGenerator.steps(fromScript: "Add 7 land\t 0 0") }
		#expect(throws: HeightmapError.malformedScript(line: 2, text: "Add 7 all\t0 0")) { try HeightmapGenerator.steps(fromScript: "Hill 1 90-100 44-56 40-60\nAdd 7 all\t0 0") }
		// leading and trailing tabs are trimmed, as before
		#expect(try HeightmapGenerator.steps(fromScript: "\tAdd 7 land 0 0\t") == ["Add 7 land 0 0"])
		// the same rule for a single step handed to apply
		let grid = try GridPoints.generate(seed: "k", width: 100, height: 60, cellsDesired: 24)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		var generator = try HeightmapGenerator(grid: grid, voronoi: voronoi)
		var random = Alea(seed: "k")
		#expect(throws: HeightmapError.malformedStep("Add 7 land\t 0 0")) { try generator.apply(step: "Add 7 land\t 0 0", random: &random) }
		#expect(throws: HeightmapError.malformedStep("Add 7 land 0 0\r")) { try generator.apply(step: "Add 7 land 0 0\r", random: &random) }
	}

	@Test func anyWhitespaceOrInvisibleCharacterOtherThanASpaceIsRefusedAndOnlyASCIISpacesAndTabsAreTrimmed() throws {
		let grid = try GridPoints.generate(seed: "k", width: 100, height: 60, cellsDesired: 24)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		var generator = try HeightmapGenerator(grid: grid, voronoi: voronoi)
		var random = Alea(seed: "k")
		let refused = [
			"Add 7 land\u{00A0} 0 0",      // a no-break space attached to `land`
			"Add 7 land\u{200B} 0 0",      // a zero-width space
			"Add 7 land\u{2028} 0 0",      // a line separator
			"Add\u{3000}7 land 0 0",       // an ideographic space used as a separator
			"Add 7 land\r\n 0 0",          // a CRLF directly inside a step (one Swift Character)
			"Add 7 land 0 0\r\n",          // a trailing CRLF: `apply` takes one line; use steps(fromScript:) for file text
			"Add 7 land\u{0085} 0 0",      // next line
			"Add 7 land\u{0007} 0 0"       // a control character
		]
		for step in refused {
			#expect(throws: HeightmapError.malformedStep(step)) { try generator.apply(step: step, random: &random) }
			#expect(HeightmapGenerator.stepElements(step) == nil, "\(step.unicodeScalars.map(\.value))")
		}
		// only ASCII spaces and tabs are trimmed: a leading no-break space is refused, a leading tab is not
		#expect(HeightmapGenerator.stepElements("\u{00A0}Add 7 land 0 0") == nil)
		#expect(HeightmapGenerator.stepElements("\t Add 7 land 0 0 \t") == ["Add", "7", "land", "0", "0"])
		// the same through scripts, and a line of only an unsupported space is refused rather than skipped as blank
		#expect(throws: HeightmapError.malformedScript(line: 1, text: "Add 7 land\u{00A0} 0 0")) { try HeightmapGenerator.steps(fromScript: "Add 7 land\u{00A0} 0 0") }
		#expect(throws: HeightmapError.malformedScript(line: 2, text: "\u{00A0}")) { try HeightmapGenerator.steps(fromScript: "Add 1 all 0 0\n\u{00A0}") }
	}

	@Test func scriptsSavedWithWindowsLineEndingsReadTheSame() throws {
		let unix = "# island\nHill 1 90-100 44-56 40-60\n\nAdd 7 all 0 0\n"
		let windows = "# island\r\nHill 1 90-100 44-56 40-60\r\n\r\nAdd 7 all 0 0\r\n"
		let oldMac = "# island\rHill 1 90-100 44-56 40-60\r\rAdd 7 all 0 0\r"
		let expected = ["Hill 1 90-100 44-56 40-60", "Add 7 all 0 0"]
		#expect(try HeightmapGenerator.steps(fromScript: unix) == expected)
		#expect(try HeightmapGenerator.steps(fromScript: windows) == expected)
		#expect(try HeightmapGenerator.steps(fromScript: oldMac) == expected)
		// a blank Windows line is blank, and line numbers in errors count lines once
		#expect(throws: HeightmapError.malformedScript(line: 4, text: "Hill 1")) { try HeightmapGenerator.steps(fromScript: "# a\r\nAdd 1 all 0 0\r\n\r\nHill 1\r\n") }
	}

	@Test func aScriptRunsLikeTheMatchingTemplateAndAFailingStepStopsTheRun() throws {
		let grid = try GridPoints.generate(seed: "k", width: 400, height: 300, cellsDesired: 2000)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		let template = try #require(HeightmapTemplate.named("volcano"))
		let script = template.steps.joined(separator: "\n")
		let fromScript = try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, steps: HeightmapGenerator.steps(fromScript: script), seed: "k")
		#expect(fromScript == (try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: "k")))
		#expect(throws: HeightmapError.unsupportedTool("Dance")) { try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, steps: ["Hill 1 90-100 44-56 40-60", "Dance 1 2 3 4"], seed: "k") }
		#expect(try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: "k") != (try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: "another")))
		// a failed generation publishes nothing, and the same inputs still work afterwards (generate keeps all its state local)
		let again = try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: "k")
		#expect(again == fromScript)
	}
}
