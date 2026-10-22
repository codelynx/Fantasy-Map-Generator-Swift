import Foundation
import Testing
@testable import FantasyMapCore

/// Step 1 of docs/plans/land-layer.md: Alea against the values the original's `alea` 1.0.1 gives.
struct AleaTests {
	struct Fixture: Decodable {
		struct Entry: Decodable {
			var seed: String
			var utf16Units: [Int]
			var values: [Double]
		}
		struct Versions: Decodable { var alea: String }
		struct Checkpoint: Decodable { var index: Int; var value: Double }
		struct LongRun: Decodable {
			var seed: String
			var calls: Int
			var checkpoints: [Checkpoint]
			var finalState: [Double]
		}
		var versions: Versions
		var alea: [Entry]
		var longRun: LongRun
	}

	@Test func theValuesMatchTheOriginalForEverySeedInTheFixture() throws {
		let fixture = try JSONDecoder().decode(Fixture.self, from: Fixtures.data("alea"))
		#expect(fixture.versions.alea == "1.0.1")
		#expect(fixture.alea.count == 9)
		for entry in fixture.alea {
			var alea = Alea(seed: entry.seed)
			let values = entry.values.map { _ in alea.next() }
			#expect(values == entry.values, "seed \(entry.seed.debugDescription)")
		}
	}

	@Test func theFixtureSeedsAreTheUTF16SequencesTheyClaim() throws {
		// Swift String equality treats canonically equivalent spellings as equal, so compare the actual code units
		let entries = try JSONDecoder().decode(Fixture.self, from: Fixtures.data("alea")).alea
		for entry in entries { #expect(Array(entry.seed.utf16).map(Int.init) == entry.utf16Units, "seed \(entry.utf16Units)") }
		let units = entries.map(\.utf16Units)
		#expect(units.contains([]))                // empty
		#expect(units.contains([97, 98, 99]))      // ASCII
		#expect(units.contains([26085, 26412, 35486])) // non-ASCII
		#expect(units.contains([55357, 56830, 120]))   // a surrogate pair
		#expect(units.contains([0x00E9]))          // precomposed e-acute
		#expect(units.contains([0x0065, 0x0301]))  // decomposed e + combining acute
		#expect(Set(units.map { $0.map(String.init).joined(separator: ",") }).count == units.count, "no seed appears twice")
	}

	@Test func composedAndDecomposedAccentsGiveTheOriginalsDifferentValues() throws {
		let entries = try JSONDecoder().decode(Fixture.self, from: Fixtures.data("alea")).alea
		let composed = try #require(entries.first { $0.utf16Units == [0x00E9] })
		let decomposed = try #require(entries.first { $0.utf16Units == [0x0065, 0x0301] })
		#expect(composed.values != decomposed.values)
		var a = Alea(seed: String(utf16CodeUnits: [0x00E9], count: 1))
		var b = Alea(seed: String(utf16CodeUnits: [0x0065, 0x0301], count: 2))
		#expect((0..<20).map { _ in a.next() } == composed.values)
		#expect((0..<20).map { _ in b.next() } == decomposed.values)
	}

	@Test func aLongRunMatchesTheOriginalAtCheckpointsAndInItsFinalState() throws {
		let run = try JSONDecoder().decode(Fixture.self, from: Fixtures.data("alea")).longRun
		var alea = Alea(seed: run.seed)
		var seen: [Int: Double] = [:]
		let wanted = Set(run.checkpoints.map(\.index))
		for i in 0..<run.calls {
			let value = alea.next()
			if wanted.contains(i) { seen[i] = value }
		}
		for checkpoint in run.checkpoints { #expect(seen[checkpoint.index] == checkpoint.value, "call \(checkpoint.index)") }
		#expect(alea.state == run.finalState)
	}

	@Test func theSameSeedGivesTheSameValuesAndTheStateIsLocal() {
		var first = Alea(seed: "kaz-1")
		var second = Alea(seed: "kaz-1")
		var other = Alea(seed: "kaz-2")
		let a = (0..<50).map { _ in first.next() }
		_ = (0..<7).map { _ in other.next() } // using another generator does not disturb this one
		let b = (0..<50).map { _ in second.next() }
		#expect(a == b)
		#expect(a.allSatisfy { $0 >= 0 && $0 < 1 })
	}
}
