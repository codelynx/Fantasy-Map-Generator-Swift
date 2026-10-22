// Ported from Azgaar's Fantasy Map Generator: `getRiverPath` in `src/generators/river-generator.ts` (the polygon `src/renderers/draw-rivers.ts`
// fills), and the Catmull-Rom curve of d3-shape 3.x (`curve/catmullRom.js`, ISC, © Mike Bostock; the notice is in ACKNOWLEDGEMENTS.md). The original
// is at commit 8936c9c, 2026-10-19, MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// The shape of a river as plain geometry: its meandered centre line widened to a closed polygon whose width grows with the distance along the river and
// the flux there, with both sides joined through a Catmull-Rom curve. **The port keeps full precision:** the original's path string is rounded twice
// (d3-shape's path keeps 3 decimals and the original's `round` then keeps 1), so its numbers differ from these by a little under 0.05 map units (the measured
// largest difference over the captured paths is in the tests and the step page); the tests apply both roundings to compare. This is geometry only; nothing here draws, and it needs no window system.

import Foundation

public enum RiverOutline {
	/// One cubic Bézier curve of the outline, from the point before it.
	public struct Curve: Equatable, Sendable {
		public var control1: Point, control2: Point, end: Point
	}

	/// The outline as the original builds it: a start point and the curves from it, closed implicitly back to the start. It runs along one bank from the
	/// mouth to the source and then, **as the original does**, continues with the curves of the other bank (whose own first point is dropped, so its first
	/// curve starts where the first bank ended).
	public struct Path: Equatable, Sendable {
		public var start: Point
		public var curves: [Curve]

		/// Every number of the path in order (start, then the six numbers of each curve): what the original's path string holds.
		public var numbers: [Double] { [start.x, start.y] + curves.flatMap { [$0.control1.x, $0.control1.y, $0.control2.x, $0.control2.y, $0.end.x, $0.end.y] } }
	}

	/// The most points the curve code accepts: the river's meandered points are budgeted where they are made, and this is a second guard for a caller
	/// who passes points of its own.
	public static let maximumPoints = 4_000_000

	/// `getRiverPath`: the outline of a river from its meandered points (with the flux at each), width factor and source width. **Nil for fewer than
	/// three points** (the original's curve then draws straight segments, which no river made by the generator has), for a non-finite point or number, or
	/// for more points than `maximumPoints`.
	public static func path(points: [RiverGeometry.RiverPoint], widthFactor: Double, sourceWidth: Double) -> Path? {
		guard points.count >= 3, points.count <= maximumPoints, widthFactor.isFinite, sourceWidth.isFinite,
			points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.flux.isFinite }) else { return nil }
		var left: [Point] = [], right: [Point] = []
		left.reserveCapacity(points.count)
		right.reserveCapacity(points.count)
		var flux = 0.0
		for i in points.indices {
			let before = points[i > 0 ? i - 1 : i], here = points[i], after = points[i + 1 < points.count ? i + 1 : i]
			if here.flux > flux { flux = here.flux }
			let offset = RiverGeometry.offset(flux: flux, pointIndex: i, widthFactor: widthFactor, startingWidth: sourceWidth)
			let angle = atan2(before.y - after.y, before.x - after.x)
			let sinOffset = sin(angle) * offset, cosOffset = cos(angle) * offset
			left.append(Point(x: here.x - sinOffset, y: here.y + cosOffset))
			right.append(Point(x: here.x + sinOffset, y: here.y - cosOffset))
		}
		guard left.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), right.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
		let rightCurve = catmullRom(Array(right.reversed()), alpha: 0.1), leftCurve = catmullRom(left, alpha: 0.1)
		return Path(start: rightCurve.start, curves: rightCurve.curves + leftCurve.curves)
	}

	/// The number of points `polygon` makes for a path and a sampling, by checked arithmetic, or nil if it overflows.
	public static func flattenedCount(_ path: Path, samplesPerCurve: Int = 6) -> Int? {
		let steps = max(samplesPerCurve, 1)
		let (product, o1) = path.curves.count.multipliedReportingOverflow(by: steps)
		let (total, o2) = product.addingReportingOverflow(1)
		return o1 || o2 ? nil : total
	}

	/// The path as a polygon: every curve cut into `samplesPerCurve` straight pieces (at least 1). **The flattened size is checked, with overflow
	/// checked, against `maximumPoints` before any point is made**, and the path's numbers and the polygon's coordinates must be finite; otherwise nil.
	/// The straight pieces approximate the curves (six to a curve by default): the curve-command comparison with the original is for the curves, not for
	/// this flattening.
	public static func polygon(_ path: Path, samplesPerCurve: Int = 6, maximumPoints: Int = RiverOutline.maximumPoints) -> [Point]? {
		guard let count = flattenedCount(path, samplesPerCurve: samplesPerCurve), count <= maximumPoints, path.numbers.allSatisfy(\.isFinite) else { return nil }
		let steps = max(samplesPerCurve, 1)
		var points = [path.start]
		points.reserveCapacity(count)
		var from = path.start
		for curve in path.curves {
			for k in 1...steps {
				let t = Double(k) / Double(steps), u = 1 - t
				let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
				points.append(Point(x: a * from.x + b * curve.control1.x + c * curve.control2.x + d * curve.end.x,
					y: a * from.y + b * curve.control1.y + c * curve.control2.y + d * curve.end.y))
			}
			from = curve.end
		}
		return points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? points : nil
	}

	/// d3-shape's `curveCatmullRom.alpha(alpha)` through the points: the same arithmetic in the same order. The first curve starts at the first point;
	/// the last point is used twice, as d3's line end does.
	static func catmullRom(_ points: [Point], alpha: Double) -> (start: Point, curves: [Curve]) {
		let epsilon = 1e-12
		var x0 = Double.nan, y0 = Double.nan, x1 = Double.nan, y1 = Double.nan, x2 = Double.nan, y2 = Double.nan
		var l01a = 0.0, l12a = 0.0, l23a = 0.0, l01_2a = 0.0, l12_2a = 0.0, l23_2a = 0.0
		var state = 0
		var start = points.first ?? Point(x: 0, y: 0)
		var curves: [Curve] = []
		curves.reserveCapacity(points.count)

		func curve(toX x: Double, y: Double) {
			var cx1 = x1, cy1 = y1, cx2 = x2, cy2 = y2
			if l01a > epsilon {
				let a = 2 * l01_2a + 3 * l01a * l12a + l12_2a
				let n = 3 * l01a * (l01a + l12a)
				cx1 = (x1 * a - x0 * l12_2a + x2 * l01_2a) / n
				cy1 = (y1 * a - y0 * l12_2a + y2 * l01_2a) / n
			}
			if l23a > epsilon {
				let b = 2 * l23_2a + 3 * l23a * l12a + l12_2a
				let m = 3 * l23a * (l23a + l12a)
				cx2 = (x2 * b + x1 * l23_2a - x * l12_2a) / m
				cy2 = (y2 * b + y1 * l23_2a - y * l12_2a) / m
			}
			curves.append(Curve(control1: Point(x: cx1, y: cy1), control2: Point(x: cx2, y: cy2), end: Point(x: x2, y: y2)))
		}

		func add(_ x: Double, _ y: Double) {
			if state != 0 {
				let x23 = x2 - x, y23 = y2 - y
				l23_2a = pow(x23 * x23 + y23 * y23, alpha)
				l23a = l23_2a.squareRoot()
			}
			switch state {
			case 0: state = 1; start = Point(x: x, y: y)
			case 1: state = 2
			case 2: state = 3; curve(toX: x, y: y)
			default: curve(toX: x, y: y)
			}
			l01a = l12a; l12a = l23a
			l01_2a = l12_2a; l12_2a = l23_2a
			x0 = x1; x1 = x2; x2 = x
			y0 = y1; y1 = y2; y2 = y
		}

		for p in points { add(p.x, p.y) }
		switch state {
		case 2: curves.append(Curve(control1: Point(x: x2, y: y2), control2: Point(x: x2, y: y2), end: Point(x: x2, y: y2))) // a straight line: not produced for three points or more
		case 3: add(x2, y2)
		default: break
		}
		return (start, curves)
	}
}
