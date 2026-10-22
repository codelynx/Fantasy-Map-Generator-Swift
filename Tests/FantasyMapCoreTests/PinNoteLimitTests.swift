import Testing
@testable import FantasyMapCore

/// `PinLimits.limiting(note:)`: what an editor keeps of what is typed, so that it can be saved.
struct PinNoteLimitTests {
	let family = "👨‍👩‍👧‍👦" // one character, 25 UTF-8 bytes

	@Test func aMemoThatFitsIsReturnedAsItIs() {
		for note in ["", "a short note", String(repeating: "n", count: 2_000), String(repeating: "日", count: 2_000), String(repeating: "😀", count: 2_000), String(repeating: family, count: 640)] {
			#expect(PinLimits.limiting(note: note) == note, "\(note.count) characters")
		}
	}

	@Test func aMemoOverTheCharacterLimitIsCutToIt() {
		let cut = PinLimits.limiting(note: String(repeating: "n", count: 2_001))
		#expect(cut == String(repeating: "n", count: PinLimits.maximumNoteLength))
		#expect(PinLimits.limiting(note: String(repeating: "日", count: 5_000)).count == PinLimits.maximumNoteLength)
	}

	@Test func aMemoOverTheByteLimitIsCutToWholeCharactersThatFit() {
		let cut = PinLimits.limiting(note: String(repeating: family, count: 700)) // 700 characters, 17,500 bytes
		#expect(cut == String(repeating: family, count: 640))
		#expect(cut.utf8.count == PinLimits.maximumNoteBytes && cut.count <= PinLimits.maximumNoteLength)
		// one more byte than fits drops a whole character, never half of one
		let tight = String(repeating: family, count: 639) + String(repeating: "x", count: 25)
		#expect(PinLimits.limiting(note: tight) == String(repeating: family, count: 639) + String(repeating: "x", count: 25))
		let over = String(repeating: family, count: 640) + "x"
		let kept = PinLimits.limiting(note: over)
		#expect(kept == String(repeating: family, count: 640) && kept.utf8.count <= PinLimits.maximumNoteBytes)
	}

	@Test func whatItKeepsIsAlwaysWithinBothLimitsAndLimitingTwiceChangesNothing() {
		let mixed = String(repeating: "a日😀" + family, count: 700)
		let once = PinLimits.limiting(note: mixed)
		#expect(once.count <= PinLimits.maximumNoteLength && once.utf8.count <= PinLimits.maximumNoteBytes)
		#expect(PinLimits.limiting(note: once) == once)
		#expect(mixed.hasPrefix(once))
	}
}
