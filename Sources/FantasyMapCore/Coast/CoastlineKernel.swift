// Ported from the displacement code of Azgaar's Fantasy Map Generator, `src/generators/coastline-generator.ts`
// (the original at commit 8936c9c, 2026-10-19): the feature seed, the integer noise, the roughness field, the recursive
// midpoint displacement of an outline, and the bypass and the calmer lake shore of `getFeatureShape`. The original is MIT
// licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// NOT ported: the original's simplification (simplify.js) and clipping of a feature's outline, and the SVG path it builds
// from the displaced points (B-spline and Catmull-Rom spans). Nothing here draws.
//
// The arithmetic follows JavaScript's number semantics (`Math.imul`, `>>>`, `| 0`, `Math.round`, `**`), because the
// port's target is the original's own numbers for explicit inputs (compared exactly against fixtures captured from the
// original's code). This kernel is **unvalidated**: it trusts its settings (finite, a small depth), and the settings are
// checked and bounded before any of it is exposed (plan: docs/plans/roughening-2c.md, step 3).

import Foundation

/// The original's `CoastlineSettings`.
struct CoastlineSettings: Equatable, Sendable {
	/// Master toggle; honoured by `CoastlineKernel.shape`, **not** by `fractalize` (as in the original).
	var enabled = true
	/// Maximum recursion depth per edge.
	var maxDepth = 4
	/// Peak displacement; scales with the square root of the edge length.
	var baseAmplitude = 1.5
	/// Amplitude multiplier per recursion level.
	var amplitudeDecay = 0.9
	/// Edges shorter than this are never subdivided.
	var minEdge = 1.0
	/// Roughness values below this give no displacement.
	var smoothThreshold = 0.25
	/// Power applied to the roughness field.
	var roughnessContrast = 1.5
	/// Size of a calm or rough stretch of coast, in map units.
	var roughnessScale = 60.0
	/// Smooth-threshold multiplier for lake shores.
	var lakeSmoothThreshMult = 2.0
	/// Reshuffles every coast, changing nothing else about it.
	var variant = 0
}

/// A displaced outline: the points, and where each original vertex sits among them.
struct FractalizedShape: Equatable, Sendable {
	var points: [Point]
	var originalIndices: [Int]
}

enum CoastlineKernel {
	private static let quantum = 64.0 // coordinates are keyed to 1/64 of a map unit
	private static let octaveWeight = 0.35
	private static let fieldStretch = 1.9

	/// The seed of a feature's coastline: `Alea("<mapSeed>_c<featureId>_<variant>").uint32() | 0`, where the original's
	/// `uint32` is one `next()` times 2^32 (a fractional Double), truncated by `| 0`.
	static func featureSeed(mapSeed: String, featureId: Int, variant: Int) -> Int32 {
		var alea = Alea(seed: "\(mapSeed)_c\(featureId)_\(variant)")
		return JSNumber.toInt32(alea.next() * 4294967296)
	}

	/// A deterministic value in [0, 1) for a tuple of numbers (murmur3-style mixing in 32-bit integer arithmetic). The
	/// numbers are converted as `value | 0`.
	static func noise(seed: Int32, _ values: [Double]) -> Double {
		var h = UInt32(bitPattern: seed)
		for value in values {
			h = (h ^ UInt32(bitPattern: JSNumber.toInt32(value))) &* 0x5bd1_e995
			h ^= h >> 13
		}
		h = (h ^ (h >> 16)) &* 0x85eb_ca6b
		h = (h ^ (h >> 13)) &* 0xc2b2_ae35
		return Double(h ^ (h >> 16)) / 4294967296
	}

	/// Smoothstep-interpolated value noise on a lattice of `scale` map units.
	private static func fieldAt(seed: Int32, x: Double, y: Double, scale: Double) -> Double {
		let fx = x / scale, fy = y / scale
		let ix = fx.rounded(.down), iy = fy.rounded(.down)
		let tx = fx - ix, ty = fy - iy
		let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
		func corner(_ cx: Double, _ cy: Double) -> Double { noise(seed: seed, [cx, cy]) }
		let top = corner(ix, iy) * (1 - sx) + corner(ix + 1, iy) * sx
		let bottom = corner(ix, iy + 1) * (1 - sx) + corner(ix + 1, iy + 1) * sx
		return top * (1 - sy) + bottom * sy
	}

	/// Roughness at a place in [0, 1]: two octaves of value noise, keyed by position, stretched and raised to the contrast.
	static func roughness(seed: Int32, x: Double, y: Double, settings: CoastlineSettings) -> Double {
		let scale = max(settings.roughnessScale, 1)
		let base = fieldAt(seed: seed, x: x, y: y, scale: scale)
		let detail = fieldAt(seed: seed ^ Int32(bitPattern: 0x9e37_79b9), x: x, y: y, scale: scale / 2)
		let combined = base * (1 - octaveWeight) + detail * octaveWeight
		let spread = min(max((combined - 0.5) * fieldStretch + 0.5, 0), 1)
		return pow(spread, settings.roughnessContrast)
	}

	/// Displaces a **closed** polygon into a coastline, as the original's `fractalize`: the last point is joined back to the
	/// first, and an edge with both ends on the map's border is skipped. `width` and `height` are the map's size.
	static func fractalize(_ points: [Point], seed: Int32, settings: CoastlineSettings, width: Double, height: Double) -> FractalizedShape {
		displace(points, closed: true, seed: seed, settings: settings, width: width, height: height)
	}

	/// Displaces an **open** chain (a coast running from one place to another, not a loop): the same recursion on every
	/// **consecutive** pair of points and nothing else. Both end points are kept exactly where they are, and **no edge is
	/// ever added from the last point back to the first**. This path is this package's own: the original only closes its input.
	/// Zero or one point is returned unchanged.
	static func fractalizeOpen(_ points: [Point], seed: Int32, settings: CoastlineSettings, width: Double, height: Double) -> FractalizedShape {
		displace(points, closed: false, seed: seed, settings: settings, width: width, height: height)
	}

	private static func displace(_ points: [Point], closed: Bool, seed: Int32, settings: CoastlineSettings, width: Double, height: Double) -> FractalizedShape {
		var result: [Point] = []
		var indices: [Int] = []
		let n = points.count
		func onBorder(_ p: Point) -> Bool { p.x == 0 || p.x == width || p.y == 0 || p.y == height }
		for i in 0..<n {
			indices.append(result.count)
			result.append(points[i])
			if !closed && i == n - 1 { break } // an open chain has no edge after its last point
			let a = points[i], b = points[(i + 1) % n]
			if onBorder(a) && onBorder(b) { continue } // edges running along the border
			subdivide(a, b, depth: settings.maxDepth, amplitude: settings.baseAmplitude, seed: seed, settings: settings, into: &result)
		}
		return FractalizedShape(points: result, originalIndices: indices)
	}

	/// Recursively subdivides an edge, inserting displaced midpoints in rough zones.
	private static func subdivide(_ a: Point, _ b: Point, depth: Int, amplitude: Double, seed: Int32, settings: CoastlineSettings, into result: inout [Point]) {
		let dx = b.x - a.x, dy = b.y - a.y
		let length = (dx * dx + dy * dy).squareRoot()
		// a zero-length segment (and a NaN length) is never subdivided: the original would divide by zero when minEdge is 0
		if depth == 0 || !(length >= settings.minEdge) || length == 0 || amplitude == 0 { return }
		let mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2
		let rough = roughness(seed: seed, x: mx, y: my, settings: settings)
		if rough < settings.smoothThreshold { return }
		let displacement = (segmentNoise(seed: seed, a, b, depth: depth) - 0.5) * length.squareRoot() * amplitude * rough
		let mid = Point(x: mx + (-dy / length) * displacement, y: my + (dx / length) * displacement)
		let next = amplitude * settings.amplitudeDecay
		subdivide(a, mid, depth: depth - 1, amplitude: next, seed: seed, settings: settings, into: &result)
		result.append(mid)
		subdivide(mid, b, depth: depth - 1, amplitude: next, seed: seed, settings: settings, into: &result)
	}

	/// One displacement per segment, keyed by the segment's own ends quantised to 1/64 with JavaScript's `Math.round`.
	private static func segmentNoise(seed: Int32, _ a: Point, _ b: Point, depth: Int) -> Double {
		func q(_ v: Double) -> Double { JSNumber.round(v * quantum) }
		return noise(seed: seed, [q(a.x), q(a.y), q(b.x), q(b.y), Double(depth)])
	}

	/// The original's `getFeatureShape` for an outline already prepared: a lake shore is calmer by its multiplier; a
	/// disabled setting (or fewer than three points) returns the outline unchanged with an identity index list.
	static func shape(_ outline: [Point], seed: Int32, isLake: Bool, settings: CoastlineSettings, width: Double, height: Double) -> FractalizedShape {
		var shore = settings
		if isLake && settings.lakeSmoothThreshMult != 1 { shore.smoothThreshold = min(1, settings.smoothThreshold * settings.lakeSmoothThreshMult) }
		if outline.count < 3 || !shore.enabled { return FractalizedShape(points: outline, originalIndices: Array(outline.indices)) }
		return fractalize(outline, seed: seed, settings: shore, width: width, height: height)
	}
}
