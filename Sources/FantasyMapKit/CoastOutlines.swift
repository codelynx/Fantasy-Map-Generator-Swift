import FantasyMapCore
import Foundation

/// A line to ink, in map units. Open lines begin and end on the map's frame; closed lines lie inside it.
public struct InkLine: Equatable, Sendable {
	public var points: [Point]
	public var isClosed: Bool
}

/// The coast as the grid cells give it (stage 2a, unsmoothed): where land meets water, found from the **current cells and
/// their height-based land/water classification**, never from the feature records and never from the stage-1 polygons.
///
/// Two things are made from the same land–water edges:
/// - `landRings`: **closed** polygons that together describe the land (compound: an island is an outer ring, a lake or a bay
///   closed off inside the land is a hole, one land mass can be several rings). Each ring runs with land on its **left**, so an
///   outer ring has positive signed area and a hole negative; either fill rule gives the land. A land mass that meets the frame
///   is closed along the frame, and **those closing segments are part of the fill, not coastline.**
/// - `ink`: only the land–water boundaries. A coast that leaves the map is an **open** line ending on the frame; **nothing is
///   drawn along the frame.**
///
/// Where a coast reaches the cells next to the frame its line ends at a Voronoi vertex that can lie inside the rectangle (the
/// boundary pseudo-points cut the border cells short). Such an end is continued along its last edge to the frame, the
/// natural continuation of the bisector between the two cells; if that ray would run further than three spacings it goes to the
/// nearest point of the frame instead. Ends outside the rectangle are clipped to it.
///
/// **Roughening (stage 2c, optional).** When roughness settings are given, the smoothed coast pieces and loops are roughened
/// before the frame closure and, if every check passes, replace the smoothed ones; otherwise `roughness` says why they did not
/// and the outline is exactly the smoothed one. **A closed loop with negative area (water enclosed by land) is given the lake
/// multiplier of the calm threshold; every other outline is not.** This is this package's own convention for enclosed water,
/// not the original's feature classification.
///
/// Limits: the continuation of two coasts could in principle cross; the tests check the rings on the sample maps, which is
/// evidence and not a proof. A map where two cells have identical points (degenerate Voronoi vertices) may lose an edge.
public struct CoastOutlines: Equatable, Sendable {
	public var landRings: [[Point]]
	public var ink: [InkLine]
	/// Whether closing the land along the frame paired every coast end with exactly one coast start, so that every ring returns to
	/// its own first piece. **False means the pairing was invalid** (for example two coasts crossing at the frame): the rings are
	/// then not to be trusted, rather than silently closed anyway.
	public var frameClosureIsConsistent: Bool
	/// What happened to the optional roughening (stage 2c): off, applied, or **fell back to the validated smoothed outline**,
	/// with the reason. Settings are never reduced silently until something passes.
	public var roughness: RoughnessOutcome

	/// `smoothing` is the number of corner-cutting rounds (Chaikin) applied to every outline; 0 keeps the cells' own edges (2a).
	/// Smoothing is applied to the coast pieces and closed loops **before** the land rings are closed along the frame and before
	/// the ink is taken, so fills and ink share the same smoothed outline.
	public init(map: LandMap, smoothing: Int = 0, roughness requested: RoughnessSettings? = nil) {
		let w = map.width, h = map.height
		let v = map.voronoi
		let n = map.heights.count
		let vertexCount = v.vertices.p.count

		// directed coast edges, land on the left: next[a] = b
		var next = [Int32](repeating: -1, count: vertexCount)
		var previous = [Int32](repeating: -1, count: vertexCount)
		for cell in 0..<n {
			let corners = v.cells.v[cell]
			guard corners.count >= 3 else { continue }
			let isLand = Heights.isLand(map.heights[cell])
			for k in 0..<corners.count {
				let a = corners[k], b = corners[(k + 1) % corners.count]
				guard let other = Self.sharedCell(v.vertices.c[a], v.vertices.c[b], except: cell), other < n, other > cell,
					Heights.isLand(map.heights[other]) != isLand else { continue }
				let landCell = isLand ? cell : other
				let site = map.grid.points[landCell], pa = v.vertices.p[a], pb = v.vertices.p[b]
				let cross = (pb.x - pa.x) * (site.y - pa.y) - (pb.y - pa.y) * (site.x - pa.x)
				let (from, to) = cross > 0 ? (a, b) : (b, a)
				guard cross != 0, next[from] < 0, previous[to] < 0 else { continue }
				next[from] = Int32(to)
				previous[to] = Int32(from)
			}
		}

		// chains of vertices: open ones start where nothing comes in; what is left over is closed
		var used = [Bool](repeating: false, count: vertexCount)
		var open: [[Point]] = [], closed: [[Point]] = []
		for start in 0..<vertexCount where next[start] >= 0 && previous[start] < 0 {
			var chain: [Point] = []
			var at = start
			while at >= 0, !used[at] {
				used[at] = true
				chain.append(v.vertices.p[at])
				at = Int(next[at])
			}
			open.append(chain)
		}
		for start in 0..<vertexCount where next[start] >= 0 && !used[start] {
			var loop: [Point] = []
			var at = start
			while at >= 0, !used[at] {
				used[at] = true
				loop.append(v.vertices.p[at])
				at = Int(next[at])
			}
			closed.append(loop)
		}

		let reach = 3 * map.grid.spacing
		var pieces: [[Point]] = []
		var ink: [InkLine] = []
		for var chain in open {
			if let first = chain.first, Self.isInside(first, w, h), let d = Self.direction(chain, atStart: true) {
				chain.insert(Self.extend(first, d, w, h, reach: reach), at: 0)
			}
			if let last = chain.last, Self.isInside(last, w, h), let d = Self.direction(chain, atStart: false) {
				chain.append(Self.extend(last, d, w, h, reach: reach))
			}
			pieces.append(contentsOf: Self.clipOpen(chain, w, h))
		}
		let rounds = min(max(smoothing, 0), Self.maximumSmoothing)
		for loop in closed {
			if loop.allSatisfy({ Self.isInsideOrOn($0, w, h) }) {
				ink.append(InkLine(points: loop, isClosed: true))
				continue
			}
			// a loop that leaves the rectangle: start at a vertex outside it so that every piece is cut at the frame
			let k = loop.firstIndex { !Self.isInsideOrOn($0, w, h) }!
			let rotated = Array(loop[k...] + loop[..<k])
			pieces.append(contentsOf: Self.clipOpen(rotated + [rotated[0]], w, h))
		}
		pieces = pieces.map { Self.chaikin($0, closed: false, rounds: rounds) }
		let loops = ink.map { Self.chaikin($0.points, closed: true, rounds: rounds) }
		// with no coast reaching the frame, the frame's cells are all land or all water
		let border = (0..<n).first { v.cells.b[$0] != 0 } ?? 0
		let frameIsLand = n > 0 && Heights.isLand(map.heights[border])

		let smooth = Self.assemble(pieces: pieces, loops: loops, frameIsLand: frameIsLand, w, h)
		(landRings, self.ink, frameClosureIsConsistent) = smooth
		roughness = .off
		guard let settings = requested else { return }
		switch Self.roughen(pieces: pieces, loops: loops, frameIsLand: frameIsLand, map: map, settings: settings) {
		case .success(let rough):
			(landRings, self.ink, frameClosureIsConsistent) = rough
			self.roughness = .applied
		case .failure(let reason):
			self.roughness = .fellBack(reason)
		}
	}

	/// The land rings, the ink and whether the frame closure was consistent, from coast pieces and closed loops.
	static func assemble(pieces: [[Point]], loops: [[Point]], frameIsLand: Bool, _ w: Double, _ h: Double) -> (rings: [[Point]], ink: [InkLine], consistent: Bool) {
		var (rings, consistent) = Self.rings(from: pieces, w, h)
		if pieces.isEmpty && frameIsLand { rings.append([Point(x: 0, y: 0), Point(x: w, y: 0), Point(x: w, y: h), Point(x: 0, y: h)]) }
		return (rings + loops, pieces.map { InkLine(points: $0, isClosed: false) } + loops.map { InkLine(points: $0, isClosed: true) }, consistent)
	}

	// MARK: building blocks

	/// The most smoothing rounds accepted (each round doubles the points of an outline).
	public static let maximumSmoothing = 4

	/// Chaikin corner cutting: each round replaces every segment a→b by the points a + ¼(b−a) and a + ¾(b−a). An open line keeps
	/// its two ends, so a coast still meets the frame where it did. The curve stays inside the convex hull of each stretch of the
	/// original, so it never leaves the map; it is not promised to stay simple (the tests look for crossings).
	static func chaikin(_ points: [Point], closed: Bool, rounds: Int) -> [Point] {
		var pts = points
		for _ in 0..<rounds {
			guard pts.count >= 2 else { break }
			var out: [Point] = []
			out.reserveCapacity(pts.count * 2)
			if !closed { out.append(pts[0]) }
			let last = closed ? pts.count : pts.count - 1
			for i in 0..<last {
				let a = pts[i], b = pts[(i + 1) % pts.count]
				out.append(Point(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
				out.append(Point(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
			}
			if !closed { out.append(pts[pts.count - 1]) }
			pts = out
		}
		return pts
	}

	/// The one cell, other than `cell`, that both vertices touch, if there is exactly one.
	static func sharedCell(_ a: [Int], _ b: [Int], except cell: Int) -> Int? {
		var found: Int?
		for x in a where x != cell && b.contains(x) {
			if let f = found, f != x { return nil }
			found = x
		}
		return found
	}

	static func isInside(_ p: Point, _ w: Double, _ h: Double) -> Bool { p.x > 0 && p.x < w && p.y > 0 && p.y < h }
	static func isInsideOrOn(_ p: Point, _ w: Double, _ h: Double) -> Bool { p.x >= 0 && p.x <= w && p.y >= 0 && p.y <= h }

	/// The direction in which a chain leaves its start (pointing out of the chain) or its end, skipping coincident points.
	static func direction(_ chain: [Point], atStart: Bool) -> Point? {
		let pts = atStart ? chain : chain.reversed()
		guard let end = pts.first else { return nil }
		for p in pts.dropFirst() {
			let dx = end.x - p.x, dy = end.y - p.y
			if dx != 0 || dy != 0 { return Point(x: dx, y: dy) }
		}
		return nil
	}

	/// Where the ray from `p` (strictly inside the rectangle) along `d` meets the frame, or the nearest frame point when that is
	/// further than `reach`. The point is placed exactly on the frame.
	static func extend(_ p: Point, _ d: Point, _ w: Double, _ h: Double, reach: Double) -> Point {
		let tx = d.x > 0 ? (w - p.x) / d.x : d.x < 0 ? -p.x / d.x : Double.infinity
		let ty = d.y > 0 ? (h - p.y) / d.y : d.y < 0 ? -p.y / d.y : Double.infinity
		let t = min(tx, ty)
		let length = (d.x * d.x + d.y * d.y).squareRoot()
		if t.isFinite, t * length <= reach {
			return tx <= ty ? Point(x: d.x > 0 ? w : 0, y: p.y + t * d.y) : Point(x: p.x + t * d.x, y: d.y > 0 ? h : 0)
		}
		let sides = [(p.x, Point(x: 0, y: p.y)), (w - p.x, Point(x: w, y: p.y)), (p.y, Point(x: p.x, y: 0)), (h - p.y, Point(x: p.x, y: h))]
		return sides.min { $0.0 < $1.0 }!.1
	}

	/// The open polyline cut to the rectangle: the pieces inside it, their cut ends placed exactly on the frame.
	static func clipOpen(_ points: [Point], _ w: Double, _ h: Double) -> [[Point]] {
		var pieces: [[Point]] = []
		var current: [Point] = []
		let tolerance = 1e-9 * max(w, h)
		func snapped(_ p: Point) -> Point {
			var x = min(max(p.x, 0), w), y = min(max(p.y, 0), h)
			if x < tolerance { x = 0 } else if w - x < tolerance { x = w }
			if y < tolerance { y = 0 } else if h - y < tolerance { y = h }
			return Point(x: x, y: y)
		}
		func finish() {
			if current.count >= 2, current.first != current.last || current.count > 2 { pieces.append(current) }
			current = []
		}
		for (a, b) in zip(points, points.dropFirst()) {
			guard let (t0, t1) = clipSegment(a, b, w, h) else { finish(); continue }
			let p0 = t0 > 0 ? snapped(Point(x: a.x + t0 * (b.x - a.x), y: a.y + t0 * (b.y - a.y))) : a
			let p1 = t1 < 1 ? snapped(Point(x: a.x + t1 * (b.x - a.x), y: a.y + t1 * (b.y - a.y))) : b
			if t0 > 0 { finish() }
			if current.isEmpty { current = [p0] }
			current.append(p1)
			if t1 < 1 { finish() }
		}
		finish()
		return pieces
	}

	/// Liang–Barsky: the parameter range of the segment a→b that lies inside the rectangle, if any.
	static func clipSegment(_ a: Point, _ b: Point, _ w: Double, _ h: Double) -> (Double, Double)? {
		var t0 = 0.0, t1 = 1.0
		let dx = b.x - a.x, dy = b.y - a.y
		for (p, q) in [(-dx, a.x), (dx, w - a.x), (-dy, a.y), (dy, h - a.y)] {
			if p == 0 {
				if q < 0 { return nil }
			} else {
				let r = q / p
				if p < 0 { if r > t1 { return nil }; t0 = max(t0, r) } else { if r < t0 { return nil }; t1 = min(t1, r) }
			}
		}
		return t0 <= t1 ? (t0, t1) : nil
	}

	/// Position of a frame point along the frame, going round it with the rectangle on the left (in the plane's usual
	/// orientation): bottom edge left to right, then right, top, left.
	static func position(_ p: Point, _ w: Double, _ h: Double) -> Double {
		if p.y == 0 { return p.x }
		if p.x == w { return w + p.y }
		if p.y == h { return w + h + (w - p.x) }
		return 2 * w + h + (h - p.y)
	}

	/// Closed land rings from open coast pieces: each piece ends on the frame with land on its left, and the frame is followed
	/// from there, with the rectangle on the left, to the start of the next piece.
	/// The second value is false when the pairing of ends to starts is not a permutation (some start has no predecessor or two
	/// ends chose the same start) or a walk does not return to its own first piece.
	static func rings(from pieces: [[Point]], _ w: Double, _ h: Double) -> (rings: [[Point]], consistent: Bool) {
		guard !pieces.isEmpty else { return ([], true) }
		let perimeter = 2 * (w + h)
		let starts = pieces.map { position($0[0], w, h) }, ends = pieces.map { position($0[$0.count - 1], w, h) }
		func gap(_ from: Double, _ to: Double) -> Double {
			var d = to - from
			if d < 0 { d = d < -1e-9 ? d + perimeter : 0 }
			return d
		}
		var successor = [Int](repeating: 0, count: pieces.count)
		for i in pieces.indices {
			var best = i, bestGap = Double.infinity
			for j in pieces.indices {
				let g = gap(ends[i], starts[j])
				if g < bestGap { bestGap = g; best = j }
			}
			successor[i] = best
		}
		var consistent = Set(successor).count == pieces.count
		let corners: [(Double, Point)] = [(0, Point(x: 0, y: 0)), (w, Point(x: w, y: 0)), (w + h, Point(x: w, y: h)), (2 * w + h, Point(x: 0, y: h))]
		var visited = [Bool](repeating: false, count: pieces.count)
		var rings: [[Point]] = []
		for first in pieces.indices where !visited[first] {
			var ring: [Point] = []
			var at = first
			while !visited[at] {
				visited[at] = true
				ring.append(contentsOf: pieces[at])
				let to = successor[at]
				let span = gap(ends[at], starts[to])
				let between = corners.map { (gap(ends[at], $0.0), $0.1) }.filter { $0.0 > 1e-12 && $0.0 < span - 1e-12 }.sorted { $0.0 < $1.0 }
				ring.append(contentsOf: between.map(\.1))
				at = to
			}
			if at != first { consistent = false }
			if ring.count >= 3 { rings.append(ring) }
		}
		return (rings, consistent)
	}
}
