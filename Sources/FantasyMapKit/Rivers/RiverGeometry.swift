// Ported from Azgaar's Fantasy Map Generator: `src/utils/pathUtils.ts` (`meander`, `relaxAcuteAngles`, `cornerCos`, `reflectAcrossLine`,
// `projectToNearestEdge`) and `src/generators/river-generator.ts` (`addMeandering`, `getOffset`, `getSourceWidth`, `getWidth`,
// `getApproximateLength`); the original at commit 8936c9c, 2026-10-19. The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with
// the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// The meandering geometry of a river: a path through the cells' points, with extra points that bend it, the corners relaxed, and the numbers
// of its length and width. Deterministic: nothing here draws random numbers.

import Foundation

public enum RiverGeometry {
	static let waterMeanderScale = 0.25
	static let relaxIterations = 4

	/// The point of the map's rectangle edge nearest to `point` (ties go to the top edge, then the bottom, the left and the right, in the
	/// original's order).
	public static func projectToNearestEdge(_ point: Point, width: Double, height: Double) -> Point {
		let minDist = min(point.y, height - point.y, point.x, width - point.x)
		if minDist == point.y { return Point(x: point.x, y: 0) }
		if minDist == height - point.y { return Point(x: point.x, y: height) }
		if minDist == point.x { return Point(x: 0, y: point.y) }
		return Point(x: width, y: point.y)
	}

	/// The options of `meander`, with the original's defaults.
	public struct MeanderOptions: Equatable, Sendable {
		/// Custom anchors, one per cell, used where present (the generator passes none).
		public var anchors: [Point]?
		public var meandering = 0.5
		public var startStep = 10
		/// The number of cells the thresholds use; the cells' count if absent.
		public var cellCount: Int?
		/// For each cell, whether it is water (the meander is then a quarter as strong).
		public var isWaterCell: [Bool]?
		/// The map's size, to project a border exit (-1) onto the nearest edge; without it a border exit stays at the previous cell.
		public var bounds: (width: Double, height: Double)?

		public init() {}

		public static func == (a: MeanderOptions, b: MeanderOptions) -> Bool {
			a.anchors == b.anchors && a.meandering == b.meandering && a.startStep == b.startStep && a.cellCount == b.cellCount && a.isWaterCell == b.isWaterCell
				&& a.bounds?.width == b.bounds?.width && a.bounds?.height == b.bounds?.height
		}
	}

	/// `meander(cells, cellPositions, options)`, **budgeted**: the river's points. `cells` are cell numbers, or -1 for a border exit; each point of
	/// the path is a cell's point (an anchor) with, between two anchors that are far enough apart, one or two points bent to the side; then the
	/// acute corners are relaxed. Returns the points and the index of each anchor among them. **The list entries are checked against the policy
	/// and the finished rivers' totals before anything is allocated** (the points, the temporary arrays), and the points are added to the totals
	/// when it succeeds; a refused call changes nothing. A cell number outside the positions, a start step that would overflow, positions or
	/// bounds that are not finite (or bounds that are not positive), and geometry that is not finite are refused.
	public static func meander(cells: [Int], cellPositions: [Point], options: MeanderOptions = MeanderOptions(), policy: RiverResourcePolicy = RiverResourcePolicy(), totals: inout RiverGeometryTotals) throws -> (points: [Point], anchorIndices: [Int]) {
		try policy.validate()
		var t = totals
		try t.preflight(entries: cells.count, policy: policy)
		let result = try meanderKernel(cells: cells, cellPositions: cellPositions, options: options)
		t.add(points: result.points.count)
		totals = t
		return result
	}

	/// The port of `meander` itself, **without the resource budget** (internal: the oracle tests use it, and the budgeted entry points call it
	/// after their own preflight).
	static func meanderKernel(cells: [Int], cellPositions: [Point], options: MeanderOptions = MeanderOptions()) throws -> (points: [Point], anchorIndices: [Int]) {
		guard cells.allSatisfy({ $0 == -1 || ($0 >= 0 && $0 < cellPositions.count) }), options.meandering.isFinite, options.startStep >= 1,
			options.startStep <= Int.max - cells.count - 1, // the step along the river is added to without overflow
			cellPositions.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), options.isWaterCell.map({ $0.count >= cells.count }) ?? true,
			options.anchors.map({ $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }) ?? true,
			options.bounds.map({ $0.width.isFinite && $0.width > 0 && $0.height.isFinite && $0.height > 0 }) ?? true else { throw RiverError.invalidInputs }
		let cellCount = options.cellCount ?? cells.count

		let anchorPoints: [Point] = cells.enumerated().map { i, cell in
			if let anchors = options.anchors, i < anchors.count { return anchors[i] }
			if cell == -1 {
				let previousCell = i > 0 ? cells[i - 1] : nil
				let previous = previousCell.flatMap { $0 >= 0 ? cellPositions[$0] : nil } ?? Point(x: 0, y: 0)
				guard let bounds = options.bounds else { return previous }
				return projectToNearestEdge(previous, width: bounds.width, height: bounds.height)
			}
			return cellPositions[cell]
		}

		var points: [Point] = []
		var anchorIndices: [Int] = []
		let lastStep = cells.count - 1
		for i in 0...max(lastStep, 0) where lastStep >= 0 {
			let step = options.startStep + i // the step along the river (no overflow: checked above)
			let (x1, y1) = (anchorPoints[i].x, anchorPoints[i].y)
			anchorIndices.append(points.count)
			points.append(Point(x: x1, y: y1))

			if i == lastStep { break }

			let nextCell = cells[i + 1]
			if nextCell == -1 { continue } // boundary anchor will be emitted on next iter without interpolation

			let (x2, y2) = (anchorPoints[i + 1].x, anchorPoints[i + 1].y)
			let dist2 = pow(x2 - x1, 2) + pow(y2 - y1, 2)
			if dist2 <= 25 && cellCount >= 6 { continue }

			var meanderVal = options.meandering + 1 / Double(step) + max(options.meandering - Double(step) / 100, 0)
			if let water = options.isWaterCell, water[i] || (i + 1 < water.count && water[i + 1]) { meanderVal *= waterMeanderScale }
			let angle = FdLibm.atan2(y2 - y1, x2 - x1)
			let sinMeander = FdLibm.sin(angle) * meanderVal
			let cosMeander = FdLibm.cos(angle) * meanderVal

			if step < 20 && (dist2 > 64 || (dist2 > 36 && cellCount < 5)) {
				let p1x = (x1 * 2 + x2) / 3 + -sinMeander
				let p1y = (y1 * 2 + y2) / 3 + cosMeander
				let p2x = (x1 + x2 * 2) / 3 + sinMeander / 2
				let p2y = (y1 + y2 * 2) / 3 - cosMeander / 2
				points.append(Point(x: p1x, y: p1y))
				points.append(Point(x: p2x, y: p2y))
			} else if dist2 > 25 || cellCount < 6 {
				let p1x = (x1 + x2) / 2 + -sinMeander
				let p1y = (y1 + y2) / 2 + cosMeander
				points.append(Point(x: p1x, y: p1y))
			}
		}

		relaxAcuteAngles(&points, anchorIndices: anchorIndices)
		// differences, midpoints and reflections of finite positions can still overflow: refuse before anything is published
		guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw RiverError.nonFiniteGeometry }
		return (points, anchorIndices)
	}

	/// The cosine of the corner at `b` between `a` and `c` (-1 if either arm has no length).
	static func cornerCos(_ a: Point, _ b: Point, _ c: Point) -> Double {
		let ax = a.x - b.x, ay = a.y - b.y
		let cx = c.x - b.x, cy = c.y - b.y
		let la = JSNumber.hypot(ax, ay)
		let lc = JSNumber.hypot(cx, cy)
		if la == 0 || lc == 0 { return -1 }
		return (ax * cx + ay * cy) / (la * lc)
	}

	/// `m` reflected across the line through `p` and `q` (unchanged if they coincide).
	static func reflectAcrossLine(_ m: Point, _ p: Point, _ q: Point) -> Point {
		let dx = q.x - p.x
		let dy = q.y - p.y
		let len2 = dx * dx + dy * dy
		if len2 == 0 { return Point(x: m.x, y: m.y) }
		let t = ((m.x - p.x) * dx + (m.y - p.y) * dy) / len2
		let footX = p.x + t * dx
		let footY = p.y + t * dy
		return Point(x: 2 * footX - m.x, y: 2 * footY - m.y)
	}

	/// `relaxAcuteAngles`: at most four passes; in each, every point that is not an anchor is flipped across the line of the two anchors around
	/// it if that lowers the acute-corner score of the three corners it takes part in by more than 1e-6. Scoring uses a snapshot taken at the
	/// start of the pass, the flips are written into the points. No point is added or removed.
	static func relaxAcuteAngles(_ points: inout [Point], anchorIndices: [Int]) {
		let n = points.count
		if n < 3 { return }

		var isAnchor = [Bool](repeating: false, count: n)
		for index in anchorIndices { isAnchor[index] = true }

		// The two anchors bounding each meander point define its segment baseline (the axis to flip about).
		var prevAnchor = [Int](repeating: -1, count: n)
		var nextAnchor = [Int](repeating: -1, count: n)
		var last = -1
		for i in 0..<n {
			prevAnchor[i] = last
			if isAnchor[i] { last = i }
		}
		last = -1
		for i in stride(from: n - 1, through: 0, by: -1) {
			nextAnchor[i] = last
			if isAnchor[i] { last = i }
		}

		// Penalty for an acute corner at vertex i
		func acuteCost(_ position: (Int) -> Point, _ i: Int) -> Double {
			if i <= 0 || i >= n - 1 { return 0 } // endpoints have no corner
			let cos = cornerCos(position(i - 1), position(i), position(i + 1))
			return cos > 0 ? cos : 0
		}

		for _ in 0..<relaxIterations {
			let snapshot = points
			let at = { (k: Int) in snapshot[k] }
			var flippedAny = false

			for i in 1..<(n - 1) {
				if isAnchor[i] { continue } // never move a real control point
				let p = prevAnchor[i]
				let q = nextAnchor[i]
				if p < 0 || q < 0 { continue }

				let flipped = reflectAcrossLine(snapshot[i], snapshot[p], snapshot[q])
				let withFlip = { (k: Int) in k == i ? flipped : snapshot[k] }

				// Score the three corners this point participates in (at i-1, i, i+1) before and after the flip.
				let before = acuteCost(at, i - 1) + acuteCost(at, i) + acuteCost(at, i + 1)
				let after = acuteCost(withFlip, i - 1) + acuteCost(withFlip, i) + acuteCost(withFlip, i + 1)

				if after < before - 1e-6 {
					points[i] = flipped
					flippedAny = true
				}
			}

			if !flippedAny { break } // converged — no beneficial flip left
		}
	}

	/// A river's meandered point: where it is and the flux there.
	public struct RiverPoint: Equatable, Sendable {
		public var x: Double, y: Double, flux: Double

		public init(x: Double, y: Double, flux: Double) {
			self.x = x; self.y = y; self.flux = flux
		}
	}

	/// `addMeandering(riverCells)`: the river's meandered points with the flux at each anchor (the cell's flux, or the previous cell's for a border
	/// exit; 0 at the other points). `heights` are the packed heights (the river starts as a stream, step 1, when its first cell is water),
	/// `flux` the cells' flux (`fl`), `positions` the cells' points. **The geometry is budgeted before it is allocated:** the river's list entries
	/// give at most three points each, and the temporary arrays are counted too (`totals`, `policy`).
	public static func addMeandering(riverCells: [Int], positions: [Point], heights: [Height], flux fl: [Double], width: Double, height: Double, policy: RiverResourcePolicy = RiverResourcePolicy(), totals: inout RiverGeometryTotals) throws -> [RiverPoint] {
		guard heights.count == positions.count, fl.count == positions.count, width.isFinite, width > 0, height.isFinite, height > 0, fl.allSatisfy(\.isFinite) else { throw RiverError.invalidInputs }
		try policy.validate()
		var t = totals
		try t.preflight(entries: riverCells.count, policy: policy)
		let first = riverCells.first
		let startStep = first.map { $0 >= 0 && $0 < heights.count && heights[$0] < Heights.seaLevel } == true ? 1 : 10
		var options = MeanderOptions()
		options.meandering = 0.5
		options.startStep = startStep
		options.isWaterCell = riverCells.map { $0 != -1 && $0 >= 0 && $0 < heights.count && heights[$0] < Heights.seaLevel }
		options.bounds = (width, height)
		let (points, anchorIndices) = try meanderKernel(cells: riverCells, cellPositions: positions, options: options)

		var flux = [Double](repeating: 0, count: points.count)
		for (anchorIndex, pointIndex) in anchorIndices.enumerated() {
			let cellId = riverCells[anchorIndex]
			let fluxCell = cellId == -1 ? (anchorIndex >= 1 ? riverCells[anchorIndex - 1] : nil) : cellId
			flux[pointIndex] = fluxCell.flatMap { $0 >= 0 && $0 < fl.count ? fl[$0] : nil } ?? 0
		}
		t.add(points: points.count)
		totals = t
		return points.enumerated().map { RiverPoint(x: $1.x, y: $1.y, flux: flux[$0]) }
	}

	private static let fluxFactor = 500.0, maxFluxWidth = 1.0, lengthFactor = 200.0
	private static let lengthStepWidth = 1 / lengthFactor
	private static let lengthProgression = [1, 1, 2, 3, 5, 8, 13, 21, 34].map { Double($0) / lengthFactor }

	/// `getOffset`: the half width of a river at a point, from its flux, how far along it is, its width factor and starting width.
	public static func offset(flux: Double, pointIndex: Int, widthFactor: Double, startingWidth: Double) -> Double {
		if pointIndex == 0 { return startingWidth }
		let fluxWidth = min(pow(flux, 0.7) / fluxFactor, maxFluxWidth)
		// the table entry, or its last entry past the table's ends (the original's `PROGRESSION[i] || at(-1)`: a negative index is undefined too)
		let progression = pointIndex >= 0 && pointIndex < lengthProgression.count && lengthProgression[pointIndex] != 0 ? lengthProgression[pointIndex] : lengthProgression[lengthProgression.count - 1]
		let lengthWidth = Double(pointIndex) * lengthStepWidth + progression
		return widthFactor * (lengthWidth + fluxWidth) + startingWidth
	}

	/// `getSourceWidth`.
	public static func sourceWidth(flux: Double) -> Double { JSNumber.rn(min(pow(flux, 0.9) / fluxFactor, maxFluxWidth), 2) }

	/// `getWidth`: the mouth width in km from the offset.
	public static func width(offset: Double) -> Double { JSNumber.rn(pow(offset / 1.5, 1.8), 2) }

	/// `getApproximateLength`: the length of the path through the points, to two decimals.
	public static func approximateLength(_ points: [Point]) -> Double {
		var length = 0.0
		for (i, point) in points.enumerated() where i > 0 { length += JSNumber.hypot(point.x - points[i - 1].x, point.y - points[i - 1].y) }
		return JSNumber.rn(length, 2)
	}
}
