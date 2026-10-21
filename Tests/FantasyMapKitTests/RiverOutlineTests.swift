import Foundation
import Testing
@testable import FantasyMapKit

/// The river's outline polygon (`getRiverPath` of the original and d3's Catmull-Rom curve), compared number for number with paths the ORIGINAL made from the
/// same meandered points (`Fixtures/original/river-paths-original.json`, captured by `tools/capture-original-river-paths.mjs`).
struct RiverOutlineTests {
	struct Captured: Decodable {
		var seed: String, key: String
		var river: Int
		var cells: [Int]
		var widthFactor: Double, sourceWidth: Double
		var points: [[Double]]
		var path: String
	}
	struct Fixture: Decodable { var rivers: [Captured] }

	func captured() throws -> [Captured] { try JSONDecoder().decode(Fixture.self, from: try fixture("river-paths-original")).rivers }

	func fixture(_ name: String) throws -> Data { try Fixtures.data(name) }

	/// The numbers of an SVG path string, as the original's `round` reads them: each run of digits, dots, `e` and minus signs.
	func numbers(_ path: String) -> [Double] {
		var result: [Double] = [], current = ""
		let allowed = Set("0123456789.-e")
		for ch in path {
			if allowed.contains(ch) {
				// a minus sign starts a new number unless it follows an exponent
				if ch == "-", !current.isEmpty, current.last != "e" { result.append(Double(current)!); current = "" }
				current.append(ch)
			} else if !current.isEmpty { result.append(Double(current)!); current = "" }
		}
		if !current.isEmpty { result.append(Double(current)!) }
		return result
	}

	func riverPoints(_ c: Captured) -> [RiverGeometry.RiverPoint] { c.points.map { RiverGeometry.RiverPoint(x: $0[0], y: $0[1], flux: $0[2]) } }

	@Test func theOutlineEqualsTheOriginalsPathNumberForNumber() throws {
		var checked = 0, numbersCompared = 0, withBorderExit = 0
		for c in try captured() {
			let path = try #require(RiverOutline.path(points: riverPoints(c), widthFactor: c.widthFactor, sourceWidth: c.sourceWidth), "\(c.seed)/\(c.key)/\(c.river)")
			// the original's string is rounded twice: d3-shape's path keeps 3 decimals, then the original's `round` keeps 1; the port keeps full precision
			let ours = path.numbers.map { JSNumber.rn(JSNumber.rn($0, 3), 1) }
			let theirs = numbers(c.path)
			// the path string starts with "M", then curves "C"; the number counts and every number agree
			#expect(ours.count == theirs.count, "\(c.seed)/\(c.key)/\(c.river): \(ours.count) numbers against \(theirs.count)")
			let wrong = zip(ours, theirs).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
			#expect(wrong.isEmpty, "\(c.seed)/\(c.key)/\(c.river): numbers \(wrong.prefix(5)) differ")
			checked += 1
			numbersCompared += theirs.count
			if c.cells.contains(-1) { withBorderExit += 1 }
		}
		#expect(checked > 100 && withBorderExit > 0, "\(checked) rivers, \(withBorderExit) leaving by the border, \(numbersCompared) numbers")
	}

	@Test func theNumbersDifferFromTheOriginalsRoundedPathByLessThanTheTwoRoundingsAllow() throws {
		// the original's numbers are rounded to 3 decimals and then to 1: a value can move by up to 0.05 and then by up to 0.0005 more
		var largest = 0.0, compared = 0
		for c in try captured() {
			let path = try #require(RiverOutline.path(points: riverPoints(c), widthFactor: c.widthFactor, sourceWidth: c.sourceWidth))
			for (ours, theirs) in zip(path.numbers, numbers(c.path)) { largest = max(largest, abs(ours - theirs)); compared += 1 }
		}
		print("largest difference between the port's full-precision numbers and the original's rounded path numbers: \(largest) over \(compared) numbers")
		#expect(compared > 10_000 && largest <= 0.0505 + 1e-9, "largest \(largest)")
	}

	@Test func theFlattenedSizeIsCheckedBeforeAnyPointIsMade() throws {
		let points = (0..<6).map { RiverGeometry.RiverPoint(x: Double($0) * 10, y: Double($0 % 2) * 4, flux: 1) }
		let path = try #require(RiverOutline.path(points: points, widthFactor: 1, sourceWidth: 1))
		let curves = path.curves.count
		#expect(RiverOutline.flattenedCount(path, samplesPerCurve: 6) == 1 + curves * 6)
		#expect(RiverOutline.flattenedCount(path, samplesPerCurve: 0) == 1 + curves, "at least one piece to a curve")
		// a sampling that would overflow, or pass the limit, is refused without making the points (a huge sampling would otherwise trap or exhaust memory)
		#expect(RiverOutline.flattenedCount(path, samplesPerCurve: Int.max) == nil)
		#expect(RiverOutline.polygon(path, samplesPerCurve: Int.max) == nil)
		#expect(RiverOutline.polygon(path, samplesPerCurve: Int.max / 2, maximumPoints: Int.max) == nil)
		#expect(RiverOutline.polygon(path, samplesPerCurve: 1_000_000_000) == nil, "far past the default limit")
		// the limit is exact
		let exact = 1 + curves * 6
		#expect(RiverOutline.polygon(path, samplesPerCurve: 6, maximumPoints: exact)?.count == exact)
		#expect(RiverOutline.polygon(path, samplesPerCurve: 6, maximumPoints: exact - 1) == nil)
		// a path with a number that is not finite gives no polygon
		var broken = path
		broken.curves[0].control1.x = .nan
		#expect(RiverOutline.polygon(broken) == nil)
		var infinite = path
		infinite.start.y = .infinity
		#expect(RiverOutline.polygon(infinite) == nil)
		// (finite numbers cannot flatten to a non-finite point: each point is a convex combination of them, so the check on the flattened coordinates is a guard that no input reaches)
	}

	@Test func fewerThanThreePointsAndNonFiniteInputsGiveNoOutline() {
		let p = { (x: Double) in RiverGeometry.RiverPoint(x: x, y: 0, flux: 1) }
		#expect(RiverOutline.path(points: [], widthFactor: 1, sourceWidth: 1) == nil)
		#expect(RiverOutline.path(points: [p(0), p(1)], widthFactor: 1, sourceWidth: 1) == nil)
		#expect(RiverOutline.path(points: [p(0), p(1), p(2)], widthFactor: 1, sourceWidth: 1) != nil)
		#expect(RiverOutline.path(points: [p(0), p(1), RiverGeometry.RiverPoint(x: .nan, y: 0, flux: 1)], widthFactor: 1, sourceWidth: 1) == nil)
		#expect(RiverOutline.path(points: [p(0), p(1), RiverGeometry.RiverPoint(x: 2, y: 0, flux: .infinity)], widthFactor: 1, sourceWidth: 1) == nil)
		#expect(RiverOutline.path(points: [p(0), p(1), p(2)], widthFactor: .nan, sourceWidth: 1) == nil)
		#expect(RiverOutline.path(points: [p(0), p(1), p(2)], widthFactor: 1, sourceWidth: .infinity) == nil)
	}

	@Test func aStraightRiverIsAStripOfTheRightWidth() throws {
		// three points on a line, no flux: the offset at index 0 is the source width, so the strip starts that wide on each side
		let points = (0..<5).map { RiverGeometry.RiverPoint(x: Double($0) * 10, y: 50, flux: 0) }
		let path = try #require(RiverOutline.path(points: points, widthFactor: 1, sourceWidth: 2))
		let polygon = try #require(RiverOutline.polygon(path, samplesPerCurve: 4))
		let ys = polygon.map(\.y)
		#expect(abs(ys.min()! - (50 - RiverGeometry.offset(flux: 0, pointIndex: 4, widthFactor: 1, startingWidth: 2))) < 0.5)
		#expect(ys.max()! > 50 + 1.9 && ys.min()! < 50 - 1.9, "wider than the source width on both banks")
		#expect(polygon.map(\.x).min()! >= -0.001 && polygon.map(\.x).max()! <= 40.001, "the curve stays within the centre line's reach")
		#expect(polygon.count == 1 + path.curves.count * 4)
	}

	@Test func theWidthGrowsFromTheSourceToTheMouth() throws {
		let c = try #require(try captured().max { $0.points.count < $1.points.count })
		let path = try #require(RiverOutline.path(points: riverPoints(c), widthFactor: c.widthFactor, sourceWidth: c.sourceWidth))
		let a = RiverGeometry.offset(flux: 0, pointIndex: 1, widthFactor: c.widthFactor, startingWidth: c.sourceWidth)
		let b = RiverGeometry.offset(flux: c.points.map { $0[2] }.max()!, pointIndex: c.points.count - 1, widthFactor: c.widthFactor, startingWidth: c.sourceWidth)
		#expect(b > a)
		#expect(!path.curves.isEmpty)
	}
}
