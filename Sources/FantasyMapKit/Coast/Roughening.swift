import Foundation

/// How a coast is roughened (drawing stage 2c): the knobs of the original's coastline generator in absolute map units. A plain
/// value; **validate before use** (`validate()` is also called by `Roughening.displace`).
///
/// **One documented departure from the original's defaults:** `baseAmplitude` defaults to 0.75, not the original's 1.5. At 1.5
/// the roughened coast of 11 of 15 realistic test maps (1280×800, 10,000 cells, smoothed twice) failed the crossing check and
/// fell back to the smoothed outline; at 0.75 all 15 passed. That is a provisional choice on a small sample, not a general
/// success rate. The parity fixtures and `CoastlineKernel`'s own defaults keep the original's 1.5.
public struct RoughnessSettings: Equatable, Codable, Sendable {
	/// Maximum recursion depth per edge, 0 to `Roughening.maximumDepth`.
	public var maxDepth = 4
	/// Peak displacement, scaling with the square root of the edge length (map units^½).
	public var baseAmplitude = 0.75
	/// Amplitude multiplier per level, 0 to 1.
	public var amplitudeDecay = 0.9
	/// Edges shorter than this are never subdivided (map units).
	public var minEdge = 1.0
	/// Roughness below this gives no displacement, 0 to 1.
	public var smoothThreshold = 0.25
	/// Power applied to the roughness field, above 0.
	public var roughnessContrast = 1.5
	/// Size of a calm or rough stretch of coast, in map units, at least 1.
	public var roughnessScale = 60.0
	/// Multiplier of the calm threshold on a shore treated as a lake's, 0 or more (the threshold is capped at 1). This only
	/// describes the multiplier; it does not decide which outline is a lake shore (`Roughening.displace`'s `isLake` does, and the
	/// drawing layer says how it chooses).
	public var lakeSmoothThreshMult = 2.0
	/// Reshuffles every coast and changes nothing else about it.
	public var variant = 0

	public init() {}

	/// Why settings or inputs were refused.
	public enum Problem: Error, Equatable, Sendable {
		case invalidSetting(String)
		case invalidInput(String)
		case outputBudget
	}

	/// Checks every value: finite and in range. Settings outside the limits are refused, never clamped.
	public func validate() throws {
		func check(_ name: String, _ value: Double, _ range: ClosedRange<Double>) throws {
			guard value.isFinite, range.contains(value) else { throw Problem.invalidSetting(name) }
		}
		guard (0...Roughening.maximumDepth).contains(maxDepth) else { throw Problem.invalidSetting("maxDepth") }
		try check("baseAmplitude", baseAmplitude, 0...1000)
		try check("amplitudeDecay", amplitudeDecay, 0...1)
		try check("minEdge", minEdge, 0...1_000_000)
		try check("smoothThreshold", smoothThreshold, 0...1)
		try check("roughnessContrast", roughnessContrast, 0.01...100)
		try check("roughnessScale", roughnessScale, 1...1_000_000)
		try check("lakeSmoothThreshMult", lakeSmoothThreshMult, 0...1000)
		guard (-1_000_000...1_000_000).contains(variant) else { throw Problem.invalidSetting("variant") }
	}

	var kernel: CoastlineSettings {
		CoastlineSettings(enabled: true, maxDepth: maxDepth, baseAmplitude: baseAmplitude, amplitudeDecay: amplitudeDecay, minEdge: minEdge, smoothThreshold: smoothThreshold, roughnessContrast: roughnessContrast, roughnessScale: roughnessScale, lakeSmoothThreshMult: lakeSmoothThreshMult, variant: variant)
	}
}

/// A roughened outline: the points, and where each input vertex sits among them.
public struct RoughenedChain: Equatable, Sendable {
	public var points: [Point]
	public var originalIndices: [Int]
}

/// The validated, narrow way to the displacement kernel ported from the original's coastline generator. The kernel itself
/// stays internal: it trusts its settings.
public enum Roughening {
	/// The deepest recursion accepted (the default is 4).
	public static let maximumDepth = 6
	/// A starting resource policy for the points one drawing may produce across all its outlines, counting the stored
	/// original-vertex indices as well: one million. A policy, not a performance guarantee.
	public static let defaultBudget = 1_000_000
	/// Coordinates beyond this are refused.
	public static let coordinateLimit = 1e9

	/// The seed used for a whole map: **this package's integration policy**, not the original's per-feature seed (which
	/// `CoastlineKernel.featureSeed` reproduces for the fixtures). The noise is keyed by position, so one seed per map avoids
	/// changes when features renumber; it does not promise that a stretch of coast stays the same when the ends or the
	/// orientation of its segment change.
	public static func seed(mapSeed: String, variant: Int) -> Int32 {
		CoastlineKernel.featureSeed(mapSeed: mapSeed, featureId: 0, variant: variant)
	}

	/// The most output (points plus the stored original-vertex indices) a chain of `vertexCount` vertices can produce at
	/// `depth`, by overflow-checked arithmetic; nil if it does not fit in an `Int`. Closed: n × 2^depth points. Open: (n − 1) ×
	/// 2^depth + 1 points (none for n = 0).
	public static func worstCaseOutput(vertexCount n: Int, closed: Bool, depth: Int) -> Int? {
		guard n >= 0, depth >= 0, depth < 62 else { return nil }
		if n == 0 { return 0 }
		let pieces = 1 << depth
		let edges = closed ? n : n - 1
		let (points, o1) = edges.multipliedReportingOverflow(by: pieces)
		guard !o1 else { return nil }
		let (withEnd, o2) = points.addingReportingOverflow(closed ? 0 : 1)
		guard !o2 else { return nil }
		let (total, o3) = withEnd.addingReportingOverflow(n) // the stored indices
		return o3 ? nil : total
	}

	/// Roughens one outline: a closed loop or an open chain (a coast, whose two ends are kept exactly and which is never
	/// closed). `isLake` gives the calmer shore. Refuses invalid settings, non-finite or huge coordinates, and any chain whose
	/// worst-case output exceeds `budget`, **before allocating**.
	public static func displace(_ points: [Point], closed: Bool, isLake: Bool, seed: Int32, settings: RoughnessSettings, width: Double, height: Double, budget: Int) throws -> RoughenedChain {
		try settings.validate()
		guard width.isFinite, height.isFinite, width > 0, height > 0, width <= coordinateLimit, height <= coordinateLimit else { throw RoughnessSettings.Problem.invalidInput("size") }
		guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= coordinateLimit && abs($0.y) <= coordinateLimit }) else { throw RoughnessSettings.Problem.invalidInput("coordinates") }
		guard let worst = worstCaseOutput(vertexCount: points.count, closed: closed, depth: settings.maxDepth), worst <= budget else { throw RoughnessSettings.Problem.outputBudget }
		var kernel = settings.kernel
		if isLake && kernel.lakeSmoothThreshMult != 1 { kernel.smoothThreshold = min(1, kernel.smoothThreshold * kernel.lakeSmoothThreshMult) }
		let shape = closed
			? CoastlineKernel.fractalize(points, seed: seed, settings: kernel, width: width, height: height)
			: CoastlineKernel.fractalizeOpen(points, seed: seed, settings: kernel, width: width, height: height)
		return RoughenedChain(points: shape.points, originalIndices: shape.originalIndices)
	}
}
