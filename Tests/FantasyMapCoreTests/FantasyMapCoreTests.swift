import Testing
@testable import FantasyMapCore

struct FantasyMapCoreTests {
	@Test func theFormatVersionIsOneAsTheFirstSupportedPersistedFormat() {
		#expect(FantasyMapCore.formatVersion == 1)
	}
}
