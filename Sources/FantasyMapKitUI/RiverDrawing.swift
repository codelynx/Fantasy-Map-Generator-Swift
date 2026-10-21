import FantasyMapKit
import Foundation

/// One river as a filled polygon, in map units.
public struct RiverFill: Equatable, Sendable {
	public var points: [Point]
	public var color: MapColor
	/// The river's number in the water map.
	public var river: Int
}

/// The land outline as an index for two questions: is a point on the land (the even-odd rule over all rings), and where does a segment first cross the
/// outline. The edges are filed under horizontal bands of the map, so a question looks at the few edges in its band and not at the whole coast.
struct RingIndex {
	private struct Edge { var a: Point, b: Point }
	private let bands: [[Edge]]
	private let top: Double, bandHeight: Double

	init(rings: [[Point]], height: Double) {
		let count = max(1, min(512, Int(height.rounded(.up))))
		top = 0
		bandHeight = height / Double(count)
		var bands = [[Edge]](repeating: [], count: count)
		for ring in rings where ring.count >= 2 {
			for i in ring.indices {
				let a = ring[i], b = ring[(i + 1) % ring.count]
				let low = band(min(a.y, b.y), count: count), high = band(max(a.y, b.y), count: count)
				for k in low...high { bands[k].append(Edge(a: a, b: b)) }
			}
		}
		self.bands = bands

		func band(_ y: Double, count: Int) -> Int { max(0, min(count - 1, Int(((y - 0) / (height / Double(count))).rounded(.down)))) }
	}

	private func band(_ y: Double) -> Int { max(0, min(bands.count - 1, Int(((y - top) / bandHeight).rounded(.down)))) }

	/// The even-odd rule: a ray to the right of the point crosses an odd number of edges.
	func contains(_ p: Point) -> Bool {
		var inside = false
		for e in bands[band(p.y)] where (e.a.y > p.y) != (e.b.y > p.y) {
			let x = e.a.x + (p.y - e.a.y) / (e.b.y - e.a.y) * (e.b.x - e.a.x)
			if p.x < x { inside.toggle() }
		}
		return inside
	}

	/// The first place along the segment from `a` to `b` where it crosses an edge, as a fraction of the way (0 to 1), or nil if it crosses none.
	func firstCrossing(from a: Point, to b: Point, after minimum: Double = 0) -> Double? {
		var best: Double?
		let low = band(min(a.y, b.y)), high = band(max(a.y, b.y))
		for k in low...high {
			for e in bands[k] {
				if let t = Self.intersect(a, b, e.a, e.b), t > minimum || (minimum == 0 && t >= 0), best == nil || t < best! { best = t }
			}
		}
		return best
	}

	/// The first crossing of a ray from `origin` in the direction `(dx, dy)` within `reach`, as a distance along the ray.
	func firstCrossing(from origin: Point, direction d: Point, reach: Double) -> Double? {
		let end = Point(x: origin.x + d.x * reach, y: origin.y + d.y * reach)
		return firstCrossing(from: origin, to: end).map { $0 * reach }
	}

	/// Where the segment p→q meets the segment r→s, as a fraction along p→q, if it does.
	static func intersect(_ p: Point, _ q: Point, _ r: Point, _ s: Point) -> Double? {
		let d1x = q.x - p.x, d1y = q.y - p.y, d2x = s.x - r.x, d2y = s.y - r.y
		let denominator = d1x * d2y - d1y * d2x
		guard denominator != 0 else { return nil }
		let t = ((r.x - p.x) * d2y - (r.y - p.y) * d2x) / denominator
		let u = ((r.x - p.x) * d1y - (r.y - p.y) * d1x) / denominator
		return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? t : nil
	}
}

/// The rivers of a water map as filled polygons, trimmed to the drawn land and extended to the drawn coast (decided 2026-10-21, see
/// docs/plans/drawing-water.md).
enum RiverDrawing {
	/// The most polygon points all rivers may add together (provisional).
	static let maximumPolygonPoints = 4_000_000

	/// How a river's list of cells ends, which decides whether it is extended to the coast.
	enum End: Equatable, Sendable {
		/// The water leaves by the map border (the list ends in -1): the river ends at the frame.
		case border
		/// The last cell is water (the sea or a lake): the river is extended to the drawn coast if it stops short.
		case water
		/// The last cell is land: the river ends at another river (a confluence) and is **not extended**, or it would grow a branch beyond the junction.
		case land
	}

	/// The end of a river from its saved cells and the packed heights.
	static func end(of river: River, heights: [Height]) -> End {
		guard let last = river.cells.last else { return .land }
		if last < 0 { return .border }
		return last < heights.count && heights[last] < Heights.seaLevel ? .water : .land
	}

	/// How far a river is extended to meet the coast: four grid spacings.
	static func reach(spacing: Double) -> Double { 4 * spacing }

	struct Result: Equatable, Sendable {
		var fills: [RiverFill]
		/// Rivers left out because their geometry or the polygon total passed a limit, or because no path could be made.
		var skipped: Int
		/// Rivers not drawn because nothing of them is on the drawn land: wholly in drawn water, or cut to fewer than three points.
		var inWater: Int
	}

	/// The rivers' polygons. `landRings` are the closed rings of the drawn land (even-odd); nil draws each river as generated.
	static func build(water: WaterMap, landRings: [[Point]]?, style: MapStyle, policy: RiverResourcePolicy = RiverResourcePolicy(), maximumPolygonPoints: Int = RiverDrawing.maximumPolygonPoints) -> Result {
		guard style.riverWidthScale > 0, style.riverWidthScale.isFinite, style.river.alpha > 0 else { return Result(fills: [], skipped: 0, inWater: 0) }
		let packed = water.packed
		let flux = water.flux.map(Double.init)
		let index = landRings.map { RingIndex(rings: $0, height: water.land.height) }
		let reach = Self.reach(spacing: water.land.grid.spacing)
		var fills: [RiverFill] = [], skipped = 0, inWater = 0, total = 0
		for river in water.rivers {
			var totals = RiverGeometryTotals()
			guard var points = try? RiverGeometry.addMeandering(riverCells: river.cells, positions: packed.points, heights: packed.heights, flux: flux, width: water.land.width, height: water.land.height, policy: policy, totals: &totals) else { skipped += 1; continue }
			if let index {
				guard let trimmed = trim(points, end: Self.end(of: river, heights: packed.heights), index: index, reach: reach) else { inWater += 1; continue }
				points = trimmed
			}
			guard let path = RiverOutline.path(points: points, widthFactor: river.widthFactor * style.riverWidthScale, sourceWidth: river.sourceWidth * style.riverWidthScale) else { skipped += 1; continue }
			// the flattened size is checked against what is left of the budget before any point is made
			guard let polygon = RiverOutline.polygon(path, maximumPoints: maximumPolygonPoints - total) else { skipped += 1; continue }
			total += polygon.count
			fills.append(RiverFill(points: polygon, color: style.river, river: river.id))
		}
		return Result(fills: fills, skipped: skipped, inWater: inWater)
	}

	/// The centre line cut to the land, **segment by segment**: the part before the path first reaches land is dropped (and the path starts where it
	/// enters), the path ends at the first place any segment crosses the outline (so a path whose two ends are on land but which spans a lake or an inlet
	/// is cut where it enters it), and a path that ends on land at a water mouth is extended along its last direction to the outline, within `reach`.
	/// Nil when no point is on land, or fewer than three points are left (too short to give the outline a curve). **A river that leaves by the map
	/// border ends there** (its last point is on the frame, so it is asked a hair's breadth inside it) and is never extended, and **neither is one that
	/// ends on land at a confluence.**
	static func trim(_ points: [RiverGeometry.RiverPoint], end: End, index: RingIndex, reach: Double) -> [RiverGeometry.RiverPoint]? {
		guard points.count >= 2 else { return nil }
		let last = points.count - 1
		func onLand(_ i: Int) -> Bool {
			var p = Point(x: points[i].x, y: points[i].y)
			if i == last && end == .border {
				// the last point is on the frame, where the even-odd rule is undecided: ask a hair's breadth inside it, along the river
				let q = points[i - 1]
				p = Point(x: p.x + (q.x - p.x) * 1e-4, y: p.y + (q.y - p.y) * 1e-4)
			}
			return index.contains(p)
		}
		func point(_ a: RiverGeometry.RiverPoint, _ b: RiverGeometry.RiverPoint, _ t: Double) -> RiverGeometry.RiverPoint {
			RiverGeometry.RiverPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, flux: 0)
		}
		guard let first = points.indices.first(where: onLand) else { return nil }
		var result: [RiverGeometry.RiverPoint] = []
		if first > 0 {
			// it begins in water: start where it enters the land
			let a = points[first - 1], b = points[first]
			let t = index.firstCrossing(from: Point(x: a.x, y: a.y), to: Point(x: b.x, y: b.y)) ?? 1
			result.append(point(a, b, t))
		}
		result.append(points[first])
		for i in first..<last {
			let a = points[i], b = points[i + 1]
			// a crossing of the outline ends the river, even between two points that are both on land (the start itself, on the outline, is not one)
			if let t = index.firstCrossing(from: Point(x: a.x, y: a.y), to: Point(x: b.x, y: b.y), after: 1e-7) {
				result.append(point(a, b, t))
				return result.count >= 3 ? result : nil
			}
			guard onLand(i + 1) else { return result.count >= 3 ? result : nil } // numerically no crossing was found: end at the last land point
			result.append(b)
		}
		// it ends on land at a water mouth: meet the coast
		if end == .water, result.count >= 2 {
			let tip = result[result.count - 1]
			var before = result[result.count - 2], k = result.count - 2
			while k > 0, before.x == tip.x, before.y == tip.y { k -= 1; before = result[k] }
			let dx = tip.x - before.x, dy = tip.y - before.y
			let length = (dx * dx + dy * dy).squareRoot()
			if length > 0, let distance = index.firstCrossing(from: Point(x: tip.x, y: tip.y), direction: Point(x: dx / length, y: dy / length), reach: reach) {
				result.append(RiverGeometry.RiverPoint(x: tip.x + dx / length * distance, y: tip.y + dy / length * distance, flux: 0))
			}
		}
		return result.count >= 3 ? result : nil
	}
}
