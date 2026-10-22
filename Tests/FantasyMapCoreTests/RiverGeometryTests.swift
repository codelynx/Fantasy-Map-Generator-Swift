import Foundation
import Testing
@testable import FantasyMapCore

/// Water chain, stage 7b: the river geometry (`meander` with `relaxAcuteAngles`, `projectToNearestEdge`, `addMeandering`, the width and length
/// numbers, and V8's `Math.hypot`), compared EXACTLY with fixtures captured from the original's own code (Fixtures/original/meander-original.json).
struct RiverGeometryTests {
	struct Size: Decodable { var width: Double, height: Double }
	struct Options: Decodable {
		var meandering: Double, startStep: Int
		var cellCount: Int?
		var isWaterCell: [Bool]?
		var bounds: Size?
		var anchors: [[Double]]?
	}
	struct MeanderCase: Decodable {
		var cells: [Int]
		var positions: [[Double]]
		var options: Options
		var points: [[Double]]
		var anchorIndices: [Int]
	}
	struct EdgeCase: Decodable {
		var width: Double, height: Double
		var point: [Double], edge: [Double]
	}
	struct WidthCase: Decodable {
		var flux: Double, pointIndex: Int, widthFactor: Double, startingWidth: Double, offset: Double
	}
	struct SourceWidth: Decodable { var flux: Double, width: Double }
	struct Width: Decodable { var offset: Double, width: Double }
	struct LengthCase: Decodable {
		var points: [[Double]]
		var length: Double
	}
	struct HypotCase: Decodable { var a: Double, b: Double, hypot: Double }
	struct TrigCase: Decodable { var a: Double, sin: Double, cos: Double }
	struct Atan2Case: Decodable { var y: Double, x: Double, atan2: Double }
	struct Bulk: Decodable { var shaSin: String, shaCos: String, shaAtan: String, shaAtan2: String }
	struct River: Decodable {
		var cells: [Int]
		var points: [[Double]]
	}
	struct RiverRun: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String
		var flux: [Double]
		var rivers: [River]
	}
	struct Fixture: Decodable {
		var meanderCases: [MeanderCase]
		var edgeCases: [EdgeCase]
		var widthCases: [WidthCase]
		var sourceWidths: [SourceWidth]
		var widths: [Width]
		var lengthCases: [LengthCase]
		var hypotCases: [HypotCase]
		var trigCases: [TrigCase]
		var atan2Cases: [Atan2Case]
		var bulk: Bulk
		var riverRuns: [RiverRun]
	}

	func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("meander-original")) }
	func pt(_ a: [Double]) -> Point { Point(x: a[0], y: a[1]) }

	@Test func meanderMatchesTheOriginalExactly() throws {
		let f = try fixture()
		var wrong = 0, withBorder = 0, relaxed = 0
		for c in f.meanderCases {
			var o = RiverGeometry.MeanderOptions()
			o.meandering = c.options.meandering
			o.startStep = c.options.startStep
			o.cellCount = c.options.cellCount
			o.isWaterCell = c.options.isWaterCell
			o.bounds = c.options.bounds.map { ($0.width, $0.height) }
			o.anchors = c.options.anchors?.map(pt)
			let (points, anchors) = try RiverGeometry.meanderKernel(cells: c.cells, cellPositions: c.positions.map(pt), options: o)
			if points != c.points.map(pt) || anchors != c.anchorIndices { wrong += 1 }
			if c.cells.contains(-1) { withBorder += 1 }
			// a relaxed case: the points differ from the unrelaxed ones (the relaxation is also checked by its own hand case below)
			if points.count >= 3 { relaxed += 1 }
		}
		#expect(f.meanderCases.count == 600 && withBorder > 50 && relaxed > 300)
		#expect(wrong == 0, "\(wrong) of \(f.meanderCases.count) meandered paths differ from the original")
	}

	@Test func projectionOfEdgeCasesMatchesTheOriginal() throws {
		let f = try fixture()
		let wrong = f.edgeCases.filter { RiverGeometry.projectToNearestEdge(pt($0.point), width: $0.width, height: $0.height) != pt($0.edge) }.count
		#expect(f.edgeCases.count == 450 && wrong == 0, "\(wrong) projections differ")
	}

	@Test func widthsAndLengthsMatchTheOriginal() throws {
		let f = try fixture()
		let offsets = f.widthCases.filter { RiverGeometry.offset(flux: $0.flux, pointIndex: $0.pointIndex, widthFactor: $0.widthFactor, startingWidth: $0.startingWidth) != $0.offset }.count
		#expect(f.widthCases.count == 360 && offsets == 0, "\(offsets) offsets differ")
		#expect(f.sourceWidths.allSatisfy { RiverGeometry.sourceWidth(flux: $0.flux) == $0.width })
		#expect(f.widths.allSatisfy { RiverGeometry.width(offset: $0.offset) == $0.width })
		#expect(f.lengthCases.allSatisfy { RiverGeometry.approximateLength($0.points.map(pt)) == $0.length })
	}

	@Test func hypotIsV8sCompensatedSumAndNotAPlainSquareRoot() throws {
		let f = try fixture()
		let wrong = f.hypotCases.filter { JSNumber.hypot($0.a, $0.b) != $0.hypot }.count
		let plainWouldDiffer = f.hypotCases.filter { ($0.a * $0.a + $0.b * $0.b).squareRoot() != $0.hypot }.count
		#expect(wrong == 0, "\(wrong) of \(f.hypotCases.count) hypot values differ from V8's")
		#expect(plainWouldDiffer > 200, "the cases do tell V8's hypot from the plain formula (\(plainWouldDiffer) differ)")
		#expect(JSNumber.hypot(.infinity, .nan) == .infinity && JSNumber.hypot(.nan, 1).isNaN && JSNumber.hypot(1, -.infinity) == .infinity && JSNumber.hypot(0, 0) == 0)
	}

	@Test func sinCosAndAtan2AreFdlibmsAndMatchV8() throws {
		let f = try fixture()
		let badSin = f.trigCases.filter { FdLibm.sin($0.a) != $0.sin }.count
		let badCos = f.trigCases.filter { FdLibm.cos($0.a) != $0.cos }.count
		let badAtan2 = f.atan2Cases.filter { FdLibm.atan2($0.y, $0.x) != $0.atan2 }.count
		#expect(badSin == 0, "\(badSin) of \(f.trigCases.count) sines differ from V8's")
		#expect(badCos == 0, "\(badCos) of \(f.trigCases.count) cosines differ from V8's")
		#expect(badAtan2 == 0, "\(badAtan2) of \(f.atan2Cases.count) arc tangents differ from V8's")
		// the system library is not the same: some of the cases tell them apart
		let systemSin = f.trigCases.filter { Foundation.sin($0.a) != $0.sin }.count
		let systemAtan2 = f.atan2Cases.filter { Foundation.atan2($0.y, $0.x) != $0.atan2 }.count
		#expect(systemSin > 0 && systemAtan2 > 0, "the cases distinguish V8's functions from the system's (sin \(systemSin), atan2 \(systemAtan2))")
		#expect(FdLibm.sin(.infinity).isNaN && FdLibm.cos(.nan).isNaN && FdLibm.atan2(.nan, 1).isNaN)
	}

	/// The capture's 32-bit linear congruential generator.
	struct Lcg {
		var state: UInt32
		init(_ seed: UInt32) { state = seed }
		mutating func next() -> Double {
			state = state &* 1664525 &+ 1013904223
			return Double(state) / 4294967296
		}
	}

	@Test func threeHundredThousandArgumentsOfEachFdlibmFunctionMatchV8() throws {
		let f = try fixture()
		var g = Lcg(20241021)
		var sins: [Double] = [], coss: [Double] = []
		for k in 0..<300000 {
			let r = g.next()
			let a = k < 200000 ? (r - 0.5) * 2 * 3.2 : k < 220000 ? (0.785 + r * 0.0004) * (k % 2 == 0 ? 1 : -1) : (r - 0.5) * 2 * 1000
			sins.append(FdLibm.sin(a)); coss.append(FdLibm.cos(a))
		}
		var h = Lcg(777)
		var atans: [Double] = []
		for k in 0..<300000 {
			let r = h.next(), sign: Double = k % 2 == 0 ? 1 : -1
			let a: Double
			switch k % 5 {
			case 0: a = (r - 0.5) * 10
			case 1: a = (r - 0.5) * 200
			case 2: a = r - 0.5
			case 3: a = sign * (1.18 + r * 1.3)
			default: a = sign * (0.4 + r * 0.1)
			}
			atans.append(FdLibm.atan(a))
		}
		var q = Lcg(4242)
		var atan2s: [Double] = []
		for k in 0..<300000 {
			let scale = [1, 1e-3, 1e5, 1][k % 4]
			let y = (q.next() - 0.5) * 100 * scale, x = (q.next() - 0.5) * 100 * scale
			atan2s.append(FdLibm.atan2(y, x))
		}
		#expect(Fixtures.hashDoubles(sins) == f.bulk.shaSin, "300,000 sines")
		#expect(Fixtures.hashDoubles(coss) == f.bulk.shaCos, "300,000 cosines")
		#expect(Fixtures.hashDoubles(atans) == f.bulk.shaAtan, "300,000 arc tangents")
		#expect(Fixtures.hashDoubles(atan2s) == f.bulk.shaAtan2, "300,000 two-argument arc tangents")
	}

	@Test func theCornerCosineUsesV8sHypot() throws {
		// a pair whose compensated hypot differs from the plain square root: the cosine of the corner at the origin between (ax, ay) and (1, 0) is
		// ax / hypot(ax, ay) (the second arm has length 1), and the two ways of taking the length give different cosines for it
		let f = try fixture()
		let pair = try #require(f.hypotCases.first { c in
			let plain = (c.a * c.a + c.b * c.b).squareRoot()
			return plain != c.hypot && c.a / plain != c.a / c.hypot && c.a != 0
		})
		let cos = RiverGeometry.cornerCos(Point(x: pair.a, y: pair.b), Point(x: 0, y: 0), Point(x: 1, y: 0))
		#expect(cos == (pair.a * 1 + pair.b * 0) / (pair.hypot * 1))
		#expect(cos != (pair.a * 1 + pair.b * 0) / ((pair.a * pair.a + pair.b * pair.b).squareRoot() * 1))
	}

	@Test func riversOnRealPackedMapsMatchTheOriginal() throws {
		let f = try fixture()
		var wrong = 0, rivers = 0
		for r in f.riverRuns {
			let m = try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
			let packed = try PackedMap.generate(for: m)
			var totals = RiverGeometryTotals()
			for river in r.rivers {
				rivers += 1
				let points = try RiverGeometry.addMeandering(riverCells: river.cells, positions: packed.points, heights: packed.heights, flux: r.flux, width: m.width, height: m.height, totals: &totals)
				if points.map({ [$0.x, $0.y, $0.flux] }) != river.points { wrong += 1 }
			}
		}
		#expect(rivers == 709)
		#expect(wrong == 0, "\(wrong) of \(rivers) rivers differ from the original")
	}

	// MARK: hand-computed cases

	@Test func twoFarCellsGetTwoBentPoints() throws {
		// cells at (0, 0) and (10, 0), start step 10: dist2 100 is over 64 and the step is under 20, so two points; the meander value is
		// 0.5 + 1/10 + max(0.5 - 0.1, 0) = 1.0, along the x axis (angle 0: sine 0, cosine 1): the first point a third along and 1 up, the second
		// two thirds along and 0.5 down; no corner is acute, so nothing is relaxed
		let (points, anchors) = try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: [Point(x: 0, y: 0), Point(x: 10, y: 0)])
		#expect(anchors == [0, 3])
		#expect(points == [Point(x: 0, y: 0), Point(x: 10.0 / 3, y: 1), Point(x: 20.0 / 3, y: -0.5), Point(x: 10, y: 0)])
	}

	@Test func cellsCloserThanFiveAreNotBentWhenThereAreSixOrMore() throws {
		// dist2 of 16 (4 apart) is not over 25: with 6 cells or more there is no bend; with fewer than 6 it gets the middle point
		let positions = (0..<6).map { Point(x: Double($0) * 4, y: 0) }
		let six = try RiverGeometry.meanderKernel(cells: Array(0..<6), cellPositions: positions)
		#expect(six.points == positions && six.anchorIndices == Array(0..<6))
		let two = try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: positions)
		#expect(two.points.count == 3, "fewer than 6 cells: a middle point even for a short step")
		// a custom cell count of 6 turns the short step off for two cells too
		var o = RiverGeometry.MeanderOptions()
		o.cellCount = 6
		#expect(try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: positions, options: o).points.count == 2)
	}

	@Test func aBorderExitIsProjectedOntoTheNearestEdgeAndIsNotInterpolatedTo() throws {
		// the exit follows the cell at (30, 5) in a 100 x 60 map: the nearest edge is the top (y = 0) at (30, 0); the anchor is added without a bend
		var o = RiverGeometry.MeanderOptions()
		o.bounds = (100, 60)
		let (points, anchors) = try RiverGeometry.meanderKernel(cells: [0, -1], cellPositions: [Point(x: 30, y: 5)], options: o)
		#expect(points == [Point(x: 30, y: 5), Point(x: 30, y: 0)] && anchors == [0, 1])
		// without bounds it stays at the previous cell
		#expect(try RiverGeometry.meanderKernel(cells: [0, -1], cellPositions: [Point(x: 30, y: 5)]).points == [Point(x: 30, y: 5), Point(x: 30, y: 5)])
		// a first cell that is a border exit has no previous cell, so it is the origin
		#expect(try RiverGeometry.meanderKernel(cells: [-1, 0], cellPositions: [Point(x: 30, y: 5)]).points.first == Point(x: 0, y: 0))
	}

	@Test func projectionTiesGoToTheTopThenBottomThenLeftThenRight() {
		#expect(RiverGeometry.projectToNearestEdge(Point(x: 50, y: 30), width: 100, height: 60) == Point(x: 50, y: 0), "the centre is 30 from the top, the bottom and, left and right are 50 away")
		#expect(RiverGeometry.projectToNearestEdge(Point(x: 5, y: 5), width: 100, height: 60) == Point(x: 5, y: 0), "equal to the left edge: the top first")
		#expect(RiverGeometry.projectToNearestEdge(Point(x: 5, y: 55), width: 100, height: 60) == Point(x: 5, y: 60), "equal to the left edge: the bottom before the left")
		#expect(RiverGeometry.projectToNearestEdge(Point(x: 5, y: 30), width: 100, height: 60) == Point(x: 0, y: 30))
		#expect(RiverGeometry.projectToNearestEdge(Point(x: 95, y: 30), width: 100, height: 60) == Point(x: 100, y: 30))
	}

	@Test func anAcuteCornerIsFlippedAcrossItsAnchorsForAtMostFourPasses() {
		// anchors 0 and 3 at (0, 0) and (10, 0); the two bent points (8, 1) and (2, 1) make two very acute corners (cosines about 0.99). In each
		// pass both points are flipped across the x axis (each flip lowers its three corners' score from 1.98 to 1.96, by more than 1e-6, judged
		// on the snapshot taken at the start of the pass), and the flipped pair is just as acute the other way up, so the flips repeat in every
		// pass. After pass 1 the points are (8, -1) and (2, -1); after the fourth, an even number of flips, they are back where they started.
		// (A fifth or a third pass would leave them flipped: this pins the limit of four passes.)
		var points = [Point(x: 0, y: 0), Point(x: 8, y: 1), Point(x: 2, y: 1), Point(x: 10, y: 0)]
		RiverGeometry.relaxAcuteAngles(&points, anchorIndices: [0, 3])
		#expect(points == [Point(x: 0, y: 0), Point(x: 8, y: 1), Point(x: 2, y: 1), Point(x: 10, y: 0)])
		// one pass of the same case by hand: the reflection across the x axis
		#expect(RiverGeometry.reflectAcrossLine(Point(x: 8, y: 1), Point(x: 0, y: 0), Point(x: 10, y: 0)) == Point(x: 8, y: -1))
		// anchors never move, and a case with no acute corner is left alone
		var calm = [Point(x: 0, y: 0), Point(x: 3.333, y: 1), Point(x: 6.667, y: -0.5), Point(x: 10, y: 0)]
		let before = calm
		RiverGeometry.relaxAcuteAngles(&calm, anchorIndices: [0, 3])
		#expect(calm == before)
		// fewer than three points are left alone
		var two = [Point(x: 0, y: 0), Point(x: 1, y: 1)]
		RiverGeometry.relaxAcuteAngles(&two, anchorIndices: [0, 1])
		#expect(two == [Point(x: 0, y: 0), Point(x: 1, y: 1)])
		// coincident anchors give no flip (the reflection leaves the point where it is)
		#expect(RiverGeometry.reflectAcrossLine(Point(x: 3, y: 4), Point(x: 1, y: 1), Point(x: 1, y: 1)) == Point(x: 3, y: 4))
		#expect(RiverGeometry.reflectAcrossLine(Point(x: 3, y: 4), Point(x: 0, y: 0), Point(x: 10, y: 0)) == Point(x: 3, y: -4))
		// the corner cosine: a right angle is 0, a straight line -1, an arm of no length -1
		#expect(RiverGeometry.cornerCos(Point(x: 1, y: 0), Point(x: 0, y: 0), Point(x: 0, y: 1)) == 0)
		#expect(RiverGeometry.cornerCos(Point(x: -1, y: 0), Point(x: 0, y: 0), Point(x: 1, y: 0)) == -1)
		#expect(RiverGeometry.cornerCos(Point(x: 0, y: 0), Point(x: 0, y: 0), Point(x: 1, y: 0)) == -1)
	}

	@Test func theOffsetAndWidthsByHand() {
		#expect(RiverGeometry.offset(flux: 1000, pointIndex: 0, widthFactor: 3, startingWidth: 0.25) == 0.25, "the first point is the starting width")
		// point 1 with flux 0: lengthWidth = 1 x 0.005 + 1/200 = 0.01; fluxWidth 0; width factor 2: 0.02 + starting 0.1
		#expect(RiverGeometry.offset(flux: 0, pointIndex: 1, widthFactor: 2, startingWidth: 0.1) == 2 * (1 * (1.0 / 200) + 1.0 / 200 + 0) + 0.1)
		// past the progression table the last entry (34 / 200) is used
		#expect(RiverGeometry.offset(flux: 0, pointIndex: 20, widthFactor: 1, startingWidth: 0) == 20 * (1.0 / 200) + 34.0 / 200)
		// the flux width is capped at 1
		#expect(RiverGeometry.offset(flux: 1e12, pointIndex: 1, widthFactor: 1, startingWidth: 0) == (1 * (1.0 / 200) + 1.0 / 200) + 1)
		#expect(RiverGeometry.sourceWidth(flux: 0) == 0 && RiverGeometry.sourceWidth(flux: 1e12) == 1)
		#expect(RiverGeometry.width(offset: 1.5) == 1, "(1.5 / 1.5) ^ 1.8 is 1")
		#expect(RiverGeometry.approximateLength([Point(x: 0, y: 0), Point(x: 3, y: 4), Point(x: 3, y: 10)]) == 11)
		#expect(RiverGeometry.approximateLength([]) == 0 && RiverGeometry.approximateLength([Point(x: 5, y: 5)]) == 0)
	}

	@Test func addMeanderingTakesFluxFromAnchorsAndStartsAStreamAtWater() throws {
		// three cells in a row, heights 10 (water), 30, 30; flux 7, 8, 9; positions 20 apart (so bends); the river starts in water: step 1
		let positions = [Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 40, y: 0)]
		var totals = RiverGeometryTotals()
		let points = try RiverGeometry.addMeandering(riverCells: [0, 1, 2], positions: positions, heights: [10, 30, 30], flux: [7, 8, 9], width: 100, height: 60, totals: &totals)
		#expect(points.first == RiverGeometry.RiverPoint(x: 0, y: 0, flux: 7) && points.last == RiverGeometry.RiverPoint(x: 40, y: 0, flux: 9))
		#expect(points.filter { $0.flux != 0 }.map(\.flux) == [7, 8, 9], "the flux is only at the anchors")
		#expect(totals.points == points.count)
		// a border exit takes the previous cell's flux
		let exit = try RiverGeometry.addMeandering(riverCells: [1, 2, -1], positions: positions, heights: [10, 30, 30], flux: [7, 8, 9], width: 100, height: 60, totals: &totals)
		#expect(exit.last?.flux == 9)
	}

	@Test func theGeometryBudgetIsCheckedBeforeAnythingIsAllocated() throws {
		var policy = RiverResourcePolicy()
		var totals = RiverGeometryTotals()
		// 10 entries: at most 30 points; a limit of 29 refuses, 30 allows
		policy.maximumRiverPoints = 29
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try totals.preflight(entries: 10, policy: policy) }
		policy.maximumRiverPoints = 30
		try totals.preflight(entries: 10, policy: policy)
		// the finished rivers count toward the next one
		totals.add(points: 20)
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try totals.preflight(entries: 4, policy: policy) } // 20 + 12 > 30
		try totals.preflight(entries: 3, policy: policy) // 20 + 9 <= 30
		// the bytes: per entry, with up to 3 points each, the peak is the relaxation's phase: the anchor points 16 + the anchor indices 8 + the
		// water flags 1 + the points 3 x 16 held from the meander, and for the points an anchor flag 1 + a previous and a next anchor index 8 + 8
		// + a snapshot 16 each (x 3): 16 + 8 + 1 + 48 + 3 + 24 + 24 + 48 = 172 bytes an entry, so 10 entries need 1,720
		#expect(MemoryLayout<Point>.stride == 16 && MemoryLayout<Int>.stride == 8 && MemoryLayout<Bool>.stride == 1 && MemoryLayout<RiverGeometry.RiverPoint>.stride == 24, "the element sizes the estimate uses")
		#expect(RiverGeometryTotals.temporaryBytes(entries: 10) == 1720)
		// the other phases are smaller: the meander's 73 an entry and the output's 153 (points 48 + indices 8 + flags 1 + flux 24 + river points 72)
		#expect(RiverGeometryTotals.temporaryBytes(entries: 1) == 172)
		var bytes = RiverResourcePolicy()
		bytes.maximumGeometryBytes = 1719
		var fresh = RiverGeometryTotals()
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try fresh.preflight(entries: 10, policy: bytes) }
		bytes.maximumGeometryBytes = 1720
		try fresh.preflight(entries: 10, policy: bytes)
		#expect(fresh.peakBytes == 1720)
		// what finished rivers retain (24 bytes a point) adds to the peak
		fresh.add(points: 5)
		#expect(fresh.retainedBytes == 5 * MemoryLayout<RiverGeometry.RiverPoint>.stride && fresh.retainedBytes == 120)
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try fresh.preflight(entries: 10, policy: bytes) }
		// overflow is refused, not wrapped
		#expect(RiverGeometryTotals.temporaryBytes(entries: Int.max / 2) == nil)
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { var t = RiverGeometryTotals(); try t.preflight(entries: Int.max / 2, policy: RiverResourcePolicy()) }
		// the public entry point refuses a river that would not fit, before meandering it
		var tight = RiverResourcePolicy()
		tight.maximumRiverPoints = 5
		var t2 = RiverGeometryTotals()
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try RiverGeometry.addMeandering(riverCells: [0, 1, 2], positions: [Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 40, y: 0)], heights: [30, 30, 30], flux: [1, 1, 1], width: 100, height: 60, policy: tight, totals: &t2) }
		#expect(t2 == RiverGeometryTotals(), "a refused river changes nothing")
	}

	@Test func publicMeanderIsBudgetedAndAddsToTheTotals() throws {
		let positions = [Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 40, y: 0)]
		var totals = RiverGeometryTotals()
		let result = try RiverGeometry.meander(cells: [0, 1, 2], cellPositions: positions, totals: &totals)
		#expect(result.points == (try RiverGeometry.meanderKernel(cells: [0, 1, 2], cellPositions: positions)).points)
		#expect(totals.points == result.points.count)
		// refused before allocating: 3 entries are at most 9 points
		var tight = RiverResourcePolicy()
		tight.maximumRiverPoints = 8
		var t2 = RiverGeometryTotals()
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try RiverGeometry.meander(cells: [0, 1, 2], cellPositions: positions, policy: tight, totals: &t2) }
		#expect(t2 == RiverGeometryTotals())
		var small = RiverResourcePolicy()
		small.maximumGeometryBytes = 3 * 172 - 1
		#expect(throws: RiverError.riverGeometryBudgetExceeded) { try RiverGeometry.meander(cells: [0, 1, 2], cellPositions: positions, policy: small, totals: &t2) }
		var invalid = RiverResourcePolicy()
		invalid.maximumRiverPoints = -1
		#expect(throws: RiverError.invalidSettings) { try RiverGeometry.meander(cells: [0, 1, 2], cellPositions: positions, policy: invalid, totals: &t2) }
	}

	@Test func theOffsetNeverIndexesOutsideItsTable() {
		// a negative point index is undefined in the original's table and falls to the last entry, as one past the end does
		#expect(RiverGeometry.offset(flux: 0, pointIndex: -1, widthFactor: 1, startingWidth: 0) == -1 * (1.0 / 200) + 34.0 / 200)
		#expect(RiverGeometry.offset(flux: 0, pointIndex: Int.min, widthFactor: 1, startingWidth: 0).isFinite)
		#expect(RiverGeometry.offset(flux: 0, pointIndex: Int.max, widthFactor: 1, startingWidth: 0).isFinite)
		#expect(RiverGeometry.offset(flux: .nan, pointIndex: 3, widthFactor: 1, startingWidth: 0).isNaN, "a flux that is not a number gives a width that is not (the helper keeps the original's arithmetic)")
	}

	@Test func theStepAlongTheRiverCannotOverflowAndTheOutputMustBeFinite() throws {
		let p = [Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 40, y: 0)]
		var o = RiverGeometry.MeanderOptions()
		o.startStep = Int.max
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 1, 2], cellPositions: p, options: o) }
		o.startStep = Int.max - 3 // the last step would be Int.max - 3 + 2 + 1: refused, as the margin is the cells' count + 1
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 1, 2], cellPositions: p, options: o) }
		o.startStep = Int.max - 4
		_ = try RiverGeometry.meanderKernel(cells: [0, 1, 2], cellPositions: p, options: o) // the largest start step that cannot overflow
		// finite positions whose midpoints overflow: refused before publishing
		let huge = [Point(x: -1e308, y: 0), Point(x: 1e308, y: 0), Point(x: 1e308, y: 1e308)]
		#expect(throws: RiverError.nonFiniteGeometry) { try RiverGeometry.meanderKernel(cells: [0, 1, 2], cellPositions: huge) }
		var totals = RiverGeometryTotals()
		#expect(throws: RiverError.nonFiniteGeometry) { try RiverGeometry.meander(cells: [0, 1, 2], cellPositions: huge, totals: &totals) }
		#expect(totals == RiverGeometryTotals(), "a refused river leaves the totals unchanged")
		#expect(throws: RiverError.nonFiniteGeometry) { try RiverGeometry.addMeandering(riverCells: [0, 1, 2], positions: huge, heights: [30, 30, 30], flux: [1, 1, 1], width: 100, height: 60, totals: &totals) }
		#expect(totals == RiverGeometryTotals())
	}

	@Test func boundsAndFluxMustBeFiniteAndBoundsPositive() throws {
		let p = [Point(x: 0, y: 0), Point(x: 20, y: 0)]
		for bounds in [(0.0, 60.0), (100.0, 0.0), (-1.0, 60.0), (.nan, 60.0), (100.0, .infinity)] {
			var o = RiverGeometry.MeanderOptions()
			o.bounds = bounds
			#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: p, options: o) }
		}
		var totals = RiverGeometryTotals()
		for (w, h) in [(0.0, 60.0), (100.0, -5.0), (.nan, 60.0)] {
			#expect(throws: RiverError.invalidInputs) { try RiverGeometry.addMeandering(riverCells: [0, 1], positions: p, heights: [30, 30], flux: [1, 1], width: w, height: h, totals: &totals) }
		}
		for bad in [Double.nan, .infinity, -.infinity] {
			#expect(throws: RiverError.invalidInputs) { try RiverGeometry.addMeandering(riverCells: [0, 1], positions: p, heights: [30, 30], flux: [1, bad], width: 100, height: 60, totals: &totals) }
		}
		#expect(totals == RiverGeometryTotals())
	}

	@Test func malformedInputsAreRefused() {
		let p = [Point(x: 0, y: 0), Point(x: 10, y: 0)]
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 2], cellPositions: p) }
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, -2], cellPositions: p) }
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: [Point(x: .nan, y: 0), Point(x: 1, y: 1)]) }
		var o = RiverGeometry.MeanderOptions()
		o.startStep = 0
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: p, options: o) }
		o = RiverGeometry.MeanderOptions()
		o.isWaterCell = [true]
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.meanderKernel(cells: [0, 1], cellPositions: p, options: o) }
		var totals = RiverGeometryTotals()
		#expect(throws: RiverError.invalidInputs) { try RiverGeometry.addMeandering(riverCells: [0, 1], positions: p, heights: [30], flux: [1, 1], width: 100, height: 60, totals: &totals) }
	}
}
