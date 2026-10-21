import FantasyMapKit
import Foundation

/// What happened to the optional roughening of a coast (stage 2c).
public enum RoughnessOutcome: Equatable, Sendable {
	/// Roughening was not asked for.
	case off
	/// The coast is roughened and passed every check.
	case applied
	/// Roughening was asked for but a check failed, so the whole outline is the validated smoothed one.
	case fellBack(RoughnessFallback)
}

/// Why roughening fell back to the smoothed outline. Nothing is retried with weaker settings.
public enum RoughnessFallback: Error, Equatable, Sendable {
	case invalidSettings
	case outputBudget
	case nonFinite
	case frameClosure
	case degenerateGeometry // a repeated point, or an ink segment lying along the frame
	case crossings // a crossing, or a contact that breaks the topology (touching, overlapping or backtracking edges)
	case validationBudget
	case colourSupport
}

extension CoastOutlines {
	/// How far a roughened point may lie from the smoothed input segment it came from, in grid spacings. A **total** bound on the
	/// distance from the input line (not on one midpoint's offset), applied by pulling a farther point back to this distance. It
	/// is a trial value for the first pictures and **not** a guarantee that the colours cover the new outline; that is what the
	/// colour-support check is for.
	public static let displacementBound = 0.1
	/// The work the crossing check may spend (segment insertions plus pair tests) before it gives up and the drawing falls back.
	public static let validationBudget = 20_000_000

	/// Roughens the smoothed pieces and loops and checks the result; a failure of any check is returned as the reason.
	static func roughen(pieces: [[Point]], loops: [[Point]], frameIsLand: Bool, map: LandMap, settings: RoughnessSettings) -> Result<(rings: [[Point]], ink: [InkLine], consistent: Bool), RoughnessFallback> {
		do { try settings.validate() } catch { return .failure(.invalidSettings) }
		let w = map.width, h = map.height
		// the worst case over the whole drawing is known before any work, and refused as a whole
		var worst = 0
		for chain in pieces { guard let c = Roughening.worstCaseOutput(vertexCount: chain.count, closed: false, depth: settings.maxDepth), let t = Optional(worst.addingReportingOverflow(c)), !t.overflow else { return .failure(.outputBudget) }; worst = t.partialValue }
		for loop in loops { guard let c = Roughening.worstCaseOutput(vertexCount: loop.count, closed: true, depth: settings.maxDepth), let t = Optional(worst.addingReportingOverflow(c)), !t.overflow else { return .failure(.outputBudget) }; worst = t.partialValue }
		guard worst <= Roughening.defaultBudget else { return .failure(.outputBudget) }

		let seed = Roughening.seed(mapSeed: map.seed, variant: settings.variant)
		let cap = displacementBound * map.grid.spacing
		var remaining = Roughening.defaultBudget
		func rough(_ input: [Point], closed: Bool, isLake: Bool) throws -> [Point] {
			let chain = try Roughening.displace(input, closed: closed, isLake: isLake, seed: seed, settings: settings, width: w, height: h, budget: remaining)
			remaining -= chain.points.count + chain.originalIndices.count
			return constrain(chain, input: input, closed: closed, cap: cap, w, h)
		}
		let roughPieces: [[Point]], roughLoops: [[Point]]
		do {
			roughPieces = try pieces.map { try rough($0, closed: false, isLake: false) }
			// a closed loop with negative area is water enclosed by land: this package's first convention for a lake shore
			roughLoops = try loops.map { try rough($0, closed: true, isLake: signedArea($0) < 0) }
		} catch RoughnessSettings.Problem.outputBudget { return .failure(.outputBudget) } catch { return .failure(.invalidSettings) }

		let all = roughPieces + roughLoops
		guard all.allSatisfy({ $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }) else { return .failure(.nonFinite) }
		let candidate = assemble(pieces: roughPieces, loops: roughLoops, frameIsLand: frameIsLand, w, h)
		guard candidate.consistent else { return .failure(.frameClosure) }
		guard hasNoDegenerateGeometry(candidate.rings, candidate.ink, w, h) else { return .failure(.degenerateGeometry) }
		switch conflictCount(candidate.rings, cellSize: map.grid.spacing, w, h, budget: validationBudget) {
		case nil: return .failure(.validationBudget)
		case let count? where count > 0: return .failure(.crossings)
		default: break
		}
		guard hasColourSupport(roughPieces.map { ($0, false) } + roughLoops.map { ($0, true) }, map: map) else { return .failure(.colourSupport) }
		return .success(candidate)
	}

	static func signedArea(_ ring: [Point]) -> Double {
		var sum = 0.0
		for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) { sum += a.x * b.y - b.x * a.y }
		return sum / 2
	}

	/// Pulls every inserted point back to at most `cap` from the input segment its span came from (the original vertices
	/// stay put), then clamps inserted points into the rectangle.
	static func constrain(_ chain: RoughenedChain, input: [Point], closed: Bool, cap: Double, _ w: Double, _ h: Double) -> [Point] {
		var points = chain.points
		let n = input.count
		for i in 0..<n {
			let start = chain.originalIndices[i]
			let end = i + 1 < n ? chain.originalIndices[i + 1] : (closed ? points.count : start)
			guard end - start > 1 else { continue }
			let a = input[i], b = input[(i + 1) % n]
			let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
			for j in (start + 1)..<end {
				var p = points[j]
				let t = length2 == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length2, 0), 1)
				let q = Point(x: a.x + t * dx, y: a.y + t * dy)
				let ox = p.x - q.x, oy = p.y - q.y, distance = (ox * ox + oy * oy).squareRoot()
				if distance > cap { p = Point(x: q.x + ox * cap / distance, y: q.y + oy * cap / distance) }
				points[j] = Point(x: min(max(p.x, 0), w), y: min(max(p.y, 0), h))
			}
		}
		return points
	}

	/// No repeated consecutive point in a ring, and no ink segment lying along the frame.
	static func hasNoDegenerateGeometry(_ rings: [[Point]], _ ink: [InkLine], _ w: Double, _ h: Double) -> Bool {
		for ring in rings {
			for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) where a == b { return false }
		}
		for line in ink {
			let pts = line.isClosed ? line.points + [line.points[0]] : line.points
			for (a, b) in zip(pts, pts.dropFirst()) {
				if a == b { return false }
				if (a.x == b.x && (a.x == 0 || a.x == w)) || (a.y == b.y && (a.y == 0 || a.y == h)) { return false }
			}
		}
		return true
	}

	/// Proper crossings between non-adjacent segments of the rings (the closing segment included) and between different rings.
	/// Returns nil when the work would exceed `budget`.
	static func crossingCount(_ rings: [[Point]], cellSize: Double, _ w: Double, _ h: Double, budget: Int) -> Int? {
		topologyConflicts(rings, cellSize: cellSize, budget: budget, strict: false)
	}

	/// What the roughening check refuses: proper crossings **and** the contacts that break a simple outline: non-adjacent
	/// segments that touch (a vertex on an edge, a repeated non-consecutive vertex) or overlap collinearly, between or within
	/// rings, and adjacent edges that backtrack over each other. Adjacent edges may share their expected end point. Contacts are
	/// found with ordinary Double arithmetic and exact-zero comparisons: the predicates have no tolerance, but their intermediate
	/// results still round, so they are **not robust exact predicates**, and a near miss passes. This is conservative against exact contacts (which clamping to the
	/// frame can create), not a clearance guarantee. Returns nil when the work would exceed `budget`.
	static func conflictCount(_ rings: [[Point]], cellSize: Double, _ w: Double, _ h: Double, budget: Int) -> Int? {
		topologyConflicts(rings, cellSize: cellSize, budget: budget, strict: true)
	}

	/// The shared search, with a uniform grid. **Every candidate visit is charged to the budget,** including a pair met again in
	/// another bucket that the first-shared-bucket rule then skips, so the budget bounds the time spent and not just the number of
	/// distinct tests.
	static func topologyConflicts(_ rings: [[Point]], cellSize: Double, budget: Int, strict: Bool) -> Int? {
		struct Segment { var ring: Int, index: Int, count: Int, a: Point, b: Point, minX: Int, minY: Int, maxX: Int, maxY: Int }
		let size = max(cellSize, 1e-9)
		var segments: [Segment] = []
		var work = 0
		var grid: [Int64: [Int32]] = [:]
		func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(truncatingIfNeeded: y)) }
		for (r, ring) in rings.enumerated() {
			for i in ring.indices {
				let a = ring[i], b = ring[(i + 1) % ring.count]
				let s = Segment(ring: r, index: i, count: ring.count, a: a, b: b,
					minX: Int((min(a.x, b.x) / size).rounded(.down)), minY: Int((min(a.y, b.y) / size).rounded(.down)),
					maxX: Int((max(a.x, b.x) / size).rounded(.down)), maxY: Int((max(a.y, b.y) / size).rounded(.down)))
				work += (s.maxX - s.minX + 1) * (s.maxY - s.minY + 1)
				if work > budget { return nil }
				let id = Int32(segments.count)
				segments.append(s)
				for x in s.minX...s.maxX { for y in s.minY...s.maxY { grid[key(x, y), default: []].append(id) } }
			}
		}
		func side(_ p: Point, _ q: Point, _ r: Point) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
		func onSegment(_ p: Point, _ q: Point, _ r: Point) -> Bool { min(p.x, q.x) <= r.x && r.x <= max(p.x, q.x) && min(p.y, q.y) <= r.y && r.y <= max(p.y, q.y) }
		var conflicts = 0
		for (k, bucket) in grid {
			let cx = Int(k >> 32), cy = Int(Int32(truncatingIfNeeded: k))
			for ii in 0..<bucket.count {
				for jj in (ii + 1)..<bucket.count {
					work += 1 // charged before the first-bucket rule below
					if work > budget { return nil }
					let s = segments[Int(bucket[ii])], t = segments[Int(bucket[jj])]
					// test the pair only in the first bucket both occupy, so it is counted once
					guard max(s.minX, t.minX) == cx, max(s.minY, t.minY) == cy else { continue }
					if s.ring == t.ring {
						let lo = s.index < t.index ? s : t, hi = s.index < t.index ? t : s
						let gap = hi.index - lo.index
						if gap == 1 || gap == lo.count - 1 {
							// adjacent: they share one end point; refuse an overlap, that is, a backtrack along the same line
							if strict {
								let (p, q, r) = gap == 1 ? (lo.a, lo.b, hi.b) : (hi.a, hi.b, lo.b)
								if side(p, q, r) == 0 && (q.x - p.x) * (r.x - q.x) + (q.y - p.y) * (r.y - q.y) < 0 { conflicts += 1 }
							}
							continue
						}
					}
					let d1 = side(s.a, s.b, t.a), d2 = side(s.a, s.b, t.b), d3 = side(t.a, t.b, s.a), d4 = side(t.a, t.b, s.b)
					if d1 * d2 < 0 && d3 * d4 < 0 { conflicts += 1; continue }
					if strict, (d1 == 0 && onSegment(s.a, s.b, t.a)) || (d2 == 0 && onSegment(s.a, s.b, t.b)) || (d3 == 0 && onSegment(t.a, t.b, s.a)) || (d4 == 0 && onSegment(t.a, t.b, s.b)) { conflicts += 1 }
				}
			}
		}
		return conflicts
	}

	/// A **sampled** check of the colour support of the changed strip: every output point (the ends of an open chain included) and
	/// every segment midpoint (the closing segment of a closed loop included) of the roughened outlines must lie in a cell that
	/// touches the other kind (land touching water, water touching land), because only those cells have the borrowed colours
	/// (`exposed` and `receded`) that paint the strip. A sample in a cell with no such neighbour would show the wrong colour.
	/// Samples in supported cells do **not** prove that a whole segment or the whole strip is covered; the rendering tests give
	/// further sampled evidence, and neither is a coverage proof.
	static func hasColourSupport(_ outlines: [(points: [Point], isClosed: Bool)], map: LandMap) -> Bool {
		let n = map.heights.count
		guard n > 0 else { return true }
		var touches = [Bool](repeating: false, count: n)
		for cell in 0..<n {
			let land = Heights.isLand(map.heights[cell])
			touches[cell] = map.voronoi.cells.c[cell].contains { $0 < n && Heights.isLand(map.heights[$0]) != land }
		}
		let size = max(map.grid.spacing, 1e-9)
		let columns = Int((map.width / size).rounded(.up)) + 2, rows = Int((map.height / size).rounded(.up)) + 2
		var buckets = [[Int32]](repeating: [], count: columns * rows)
		for cell in 0..<n {
			let p = map.grid.points[cell]
			let bx = min(max(Int(p.x / size), 0), columns - 1), by = min(max(Int(p.y / size), 0), rows - 1)
			buckets[by * columns + bx].append(Int32(cell))
		}
		func nearest(_ p: Point) -> Int? {
			let bx = min(max(Int(p.x / size), 0), columns - 1), by = min(max(Int(p.y / size), 0), rows - 1)
			var best: Int?, bestDistance = Double.infinity
			for radius in 1...4 {
				for y in max(by - radius, 0)...min(by + radius, rows - 1) {
					for x in max(bx - radius, 0)...min(bx + radius, columns - 1) {
						for cell in buckets[y * columns + x] {
							let q = map.grid.points[Int(cell)]
							let d = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
							if d < bestDistance { bestDistance = d; best = Int(cell) }
						}
					}
				}
				if let _ = best, bestDistance.squareRoot() <= Double(radius) * size { return best }
			}
			return best
		}
		for outline in outlines {
			var samples = outline.points
			let pairs = outline.isClosed && outline.points.count > 1 ? Array(zip(outline.points, outline.points.dropFirst() + [outline.points[0]])) : Array(zip(outline.points, outline.points.dropFirst()))
			samples += pairs.map { Point(x: ($0.0.x + $0.1.x) / 2, y: ($0.0.y + $0.1.y) / 2) }
			for p in samples {
				guard let cell = nearest(p), touches[cell] else { return false }
			}
		}
		return true
	}
}
