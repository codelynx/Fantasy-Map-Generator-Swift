import Foundation
import Testing
@testable import FantasyMapKit

/// Step 1: the JavaScript conversions and the algorithm's own clamp, kept apart and tested separately.
struct HeightStorageTests {
	@Test func storingTruncatesTowardZero() {
		#expect(Heights.stored(7.9) == 7)
		#expect(Heights.stored(0.99) == 0)
		#expect(Heights.stored(100) == 100)
		#expect(Heights.stored(-0.5) == 0) // truncates to -0, which is 0
	}

	@Test func storingWrapsModulo256WhereAClampWouldNot() {
		#expect(Heights.stored(256) == 0)
		#expect(Heights.stored(257.9) == 1)
		#expect(Heights.stored(300) == 44)
		#expect(Heights.stored(-1) == 255)
		#expect(Heights.stored(-1.9) == 255)
		#expect(Heights.stored(-256) == 0)
		#expect(Heights.stored(1e10) == UInt8(truncatingIfNeeded: Int64(1e10)))
	}

	@Test func storingNonFiniteValuesGivesZero() {
		#expect(Heights.stored(.nan) == 0)
		#expect(Heights.stored(.infinity) == 0)
		#expect(Heights.stored(-.infinity) == 0)
	}

	@Test func theAlgorithmsClampIsNotTheStorageConversion() {
		#expect(Heights.limit(130) == 100)
		#expect(Heights.limit(-5) == 0)
		#expect(Heights.limit(42.5) == 42.5) // still fractional until stored
		#expect(Heights.stored(Heights.limit(130)) == 100)
		#expect(Heights.stored(130) == 130) // a byte holds 130; only `limit` brings it to 100
	}

	@Test func uInt32AndInt32FollowJavaScript() {
		#expect(JSNumber.toUInt32(-1) == 4294967295)
		#expect(JSNumber.toUInt32(4294967296) == 0)
		#expect(JSNumber.toUInt32(4294967297.9) == 1)
		#expect(JSNumber.toUInt32(.nan) == 0)
		#expect(JSNumber.toInt32(2147483648) == Int32.min)
		#expect(JSNumber.toInt32(-1.9) == -1)
		#expect(JSNumber.toInt32(4294967295) == -1)
		#expect(JSNumber.toInt32(2091640.7) == 2091640)
	}

	@Test func seaLevelSeparatesWaterFromLand() {
		#expect(Heights.isWater(19) && !Heights.isLand(19))
		#expect(Heights.isLand(20) && !Heights.isWater(20))
	}
}
