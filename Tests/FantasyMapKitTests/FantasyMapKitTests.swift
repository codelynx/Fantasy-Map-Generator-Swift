import Testing
@testable import FantasyMapKit

struct FantasyMapKitTests {
	@Test func theFormatVersionIsOneAsTheFirstSupportedPersistedFormat() {
		#expect(FantasyMapKit.formatVersion == 1)
	}
}
