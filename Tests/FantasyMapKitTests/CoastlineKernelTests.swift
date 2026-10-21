import Foundation
import Testing
@testable import FantasyMapKit

/// The displacement kernel ported from the original's coastline generator, compared EXACTLY with fixtures captured from the
/// original's own code (Fixtures/original/coastline-original.json). No tolerance is used.
struct CoastlineKernelTests {
	struct Settings: Decodable {
		var enabled: Bool, maxDepth: Int, baseAmplitude: Double, amplitudeDecay: Double, minEdge: Double
		var smoothThreshold: Double, roughnessContrast: Double, roughnessScale: Double, lakeSmoothThreshMult: Double, variant: Int
		var value: CoastlineSettings {
			CoastlineSettings(enabled: enabled, maxDepth: maxDepth, baseAmplitude: baseAmplitude, amplitudeDecay: amplitudeDecay, minEdge: minEdge, smoothThreshold: smoothThreshold, roughnessContrast: roughnessContrast, roughnessScale: roughnessScale, lakeSmoothThreshMult: lakeSmoothThreshMult, variant: variant)
		}
	}
	struct Outline: Decodable { var width: Double, height: Double, points: [[Double]] }
	struct Seed: Decodable { var seed: String, id: Int, variant: Int, value: Int32 }
	struct Noise: Decodable { var seed: Int32, values: [Double], value: Double }
	struct Roughness: Decodable { struct Sample: Decodable { var x: Double, y: Double, value: Double }; var settings: String, seed: Int32, samples: [Sample] }
	struct Fractalized: Decodable { var outline: String, settings: String, seed: Int32, points: [[Double]], origIndices: [Int] }
	struct Shaped: Decodable { var mapSeed: String, featureId: Int, type: String, settings: String, enabled: Bool, featureOverride: Bool, points: [[Double]], origIndices: [Int] }
	struct Shape: Decodable { var points: [[Double]], origIndices: [Int] }
	struct LocalEdit: Decodable { var seed: Int32, ring: [[Double]], moved: [[Double]], before: Shape, after: Shape }
	struct Fixture: Decodable {
		var settings: [String: Settings], outlines: [String: Outline]
		var featureSeeds: [Seed], noises: [Noise], roughness: [Roughness], fractalized: [Fractalized], shapes: [Shaped], localEdit: LocalEdit
	}

	func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("coastline-original")) }
	func pts(_ raw: [[Double]]) -> [Point] { raw.map { Point(x: $0[0], y: $0[1]) } }

	@Test func featureSeedsMatchTheOriginal() throws {
		let f = try fixture()
		var wrong = 0
		for s in f.featureSeeds where CoastlineKernel.featureSeed(mapSeed: s.seed, featureId: s.id, variant: s.variant) != s.value { wrong += 1 }
		#expect(f.featureSeeds.count == 144 && wrong == 0, "\(wrong) seeds differ")
	}

	@Test func theIntegerNoiseMatchesTheOriginalExactly() throws {
		let f = try fixture()
		var wrong = 0
		for n in f.noises where CoastlineKernel.noise(seed: n.seed, n.values) != n.value { wrong += 1 }
		#expect(f.noises.count == 180 && wrong == 0, "\(wrong) noise values differ")
	}

	@Test func theRoughnessFieldMatchesTheOriginalExactly() throws {
		let f = try fixture()
		var wrong = 0, total = 0, worst = 0.0
		for r in f.roughness {
			let settings = try #require(f.settings[r.settings]).value
			for s in r.samples {
				total += 1
				let v = CoastlineKernel.roughness(seed: r.seed, x: s.x, y: s.y, settings: settings)
				if v != s.value { wrong += 1; worst = max(worst, abs(v - s.value)) }
			}
		}
		// the power function is where Swift's result could differ from V8's in the last bit: it is reported, not tolerated
		#expect(total == 1200 && wrong == 0, "\(wrong) of \(total) roughness values differ (largest difference \(worst))")
	}

	@Test func fractalizedOutlinesMatchTheOriginalPointForPoint() throws {
		let f = try fixture()
		var wrong = 0
		var firstWrong = ""
		for r in f.fractalized {
			let outline = try #require(f.outlines[r.outline])
			let settings = try #require(f.settings[r.settings]).value
			let shape = CoastlineKernel.fractalize(pts(outline.points), seed: r.seed, settings: settings, width: outline.width, height: outline.height)
			if shape.points != pts(r.points) || shape.originalIndices != r.origIndices {
				wrong += 1
				if firstWrong.isEmpty { firstWrong = "\(r.outline)/\(r.settings)/\(r.seed): \(shape.points.count) vs \(r.points.count) points" }
			}
		}
		#expect(f.fractalized.count == 336 && wrong == 0, "\(wrong) of \(f.fractalized.count) outlines differ, first \(firstWrong)")
	}

	@Test func theShapeLayerMatchesTheOriginalIncludingTheBypassAndTheLakeShore() throws {
		let f = try fixture()
		let outline = try #require(f.outlines["irregular"])
		var wrong = 0
		for s in f.shapes {
			var settings = try #require(f.settings[s.featureOverride ? "depth1" : s.settings]).value
			settings.enabled = s.enabled
			let seed = CoastlineKernel.featureSeed(mapSeed: s.mapSeed, featureId: s.featureId, variant: settings.variant)
			let shape = CoastlineKernel.shape(pts(outline.points), seed: seed, isLake: s.type == "lake", settings: settings, width: outline.width, height: outline.height)
			if shape.points != pts(s.points) || shape.originalIndices != s.origIndices { wrong += 1 }
			if !s.enabled { #expect(shape.points == pts(outline.points), "disabled gives the outline unchanged") }
		}
		#expect(f.shapes.count == 16 && wrong == 0, "\(wrong) shapes differ")
	}

	@Test func theOriginalsOwnLocalEditRingMatches() throws {
		let l = try fixture().localEdit
		let defaults = CoastlineSettings()
		let before = CoastlineKernel.fractalize(pts(l.ring), seed: l.seed, settings: defaults, width: 100, height: 100)
		let after = CoastlineKernel.fractalize(pts(l.moved), seed: l.seed, settings: defaults, width: 100, height: 100)
		#expect(before.points == pts(l.before.points) && before.originalIndices == l.before.origIndices)
		#expect(after.points == pts(l.after.points) && after.originalIndices == l.after.origIndices)
	}

	// MARK: properties the original's own tests expect

	let square = [Point(x: 10, y: 10), Point(x: 90, y: 10), Point(x: 90, y: 90), Point(x: 10, y: 90)]

	@Test func theSameSeedAndSettingsRepeatTheShapeAndAnotherMapSeedOrVariantChangesIt() {
		let defaults = CoastlineSettings()
		func shape(_ seed: String, variant: Int = 0, settings: CoastlineSettings = CoastlineSettings()) -> [Point] {
			CoastlineKernel.fractalize(square, seed: CoastlineKernel.featureSeed(mapSeed: seed, featureId: 1, variant: variant), settings: settings, width: 100, height: 100).points
		}
		let a = shape("kaz-1")
		#expect(a == shape("kaz-1") && a.count > 4)
		#expect(a != shape("kaz-2"))
		#expect(a != shape("kaz-1", variant: 1))
		#expect(a == shape("kaz-1", variant: 0), "a variant is a choice, not a one-way roll")
		var shallow = defaults
		shallow.maxDepth = 1
		#expect(shape("kaz-1", settings: shallow).count < a.count, "a smaller depth gives fewer points")
	}

	@Test func movingOneVertexChangesOnlyTheStretchAroundIt() throws {
		let l = try fixture().localEdit
		let a = pts(l.before.points), b = Set(pts(l.after.points).map { "\($0.x),\($0.y)" })
		let changed = a.filter { !b.contains("\($0.x),\($0.y)") }.count
		#expect(changed > 0 && changed < a.count / 4, "\(changed) of \(a.count) points changed (a stream-indexed noise would change nearly all)")
	}

	@Test func theNoiseReadsNumbersAsJavaScriptDoesAndRoundingGoesHalvesUp() {
		// | 0 wraps: 2^32 reads as 0, 2^32 - 1 as -1, 2^31 as -2^31
		#expect(CoastlineKernel.noise(seed: 5, [4294967296]) == CoastlineKernel.noise(seed: 5, [0]))
		#expect(CoastlineKernel.noise(seed: 5, [4294967295]) == CoastlineKernel.noise(seed: 5, [-1]))
		#expect(CoastlineKernel.noise(seed: 5, [2147483648]) == CoastlineKernel.noise(seed: 5, [-2147483648]))
		// the value is in [0, 1) for any input
		for v in [0.0, -1, 1e9, -1e9, 123456.789] { let n = CoastlineKernel.noise(seed: -77, [v, v * 3]); #expect(n >= 0 && n < 1) }
		// Math.round: halves go toward positive infinity
		#expect(JSNumber.round(-2.5) == -2 && JSNumber.round(2.5) == 3 && JSNumber.round(-0.5) == 0)
	}

	@Test func anEdgeAlongTheBorderIsNeverDisplacedAndNoAmplitudeLeavesTheOutlineAlone() {
		var rough = CoastlineSettings()
		rough.smoothThreshold = 0
		let edge = [Point(x: 0, y: 10), Point(x: 0, y: 60), Point(x: 40, y: 30)]
		let shape = CoastlineKernel.fractalize(edge, seed: 99, settings: rough, width: 100, height: 100)
		// the first edge runs along x = 0, both ends on the border: no point is inserted between indices 0 and 1
		#expect(shape.originalIndices[1] == 1)
		var flat = rough
		flat.baseAmplitude = 0
		#expect(CoastlineKernel.fractalize(edge, seed: 99, settings: flat, width: 100, height: 100).points == edge)
	}

	// MARK: the open-chain path (this package's own: no original to compare with, so properties and the closed path itself)

	@Test func anOpenChainKeepsBothEndsAddsNoClosingEdgeAndDisplacesOnlyConsecutiveSegments() throws {
		let f = try fixture()
		var checked = 0
		for (name, outline) in f.outlines {
			let chain = pts(outline.points)
			for settingsName in ["default", "allRough", "depth1", "noDecay", "contrast1"] {
				let settings = try #require(f.settings[settingsName]).value
				for seed: Int32 in [0, 424242, -31337] {
					let closed = CoastlineKernel.fractalize(chain, seed: seed, settings: settings, width: outline.width, height: outline.height)
					let open = CoastlineKernel.fractalizeOpen(chain, seed: seed, settings: settings, width: outline.width, height: outline.height)
					#expect(open.points.first == chain.first && open.points.last == chain.last, "\(name): both ends are kept")
					#expect(open.originalIndices.count == chain.count && open.originalIndices.first == 0 && open.originalIndices.last == open.points.count - 1, "\(name): the last original vertex ends the chain")
					// each consecutive span is exactly the closed path's span for the same edge (same seed, settings and border treatment)
					for i in 0..<(chain.count - 1) {
						let o = Array(open.points[open.originalIndices[i]...open.originalIndices[i + 1]])
						let c = Array(closed.points[closed.originalIndices[i]...closed.originalIndices[i + 1]])
						#expect(o == c, "\(name)/\(settingsName)/\(seed): span \(i) differs from the closed path")
					}
					// and what the closed path adds after the last vertex (the closing edge's displaced points) is absent
					#expect(open.points.count == closed.originalIndices[chain.count - 1] + 1, "\(name): no closing edge")
					checked += 1
				}
			}
		}
		#expect(checked == 7 * 5 * 3)
	}

	@Test func openChainsWithFewOrCoincidentPointsAreHandledSafely() {
		let settings = { var s = CoastlineSettings(); s.smoothThreshold = 0; s.minEdge = 0; return s }()
		func open(_ p: [Point]) -> FractalizedShape { CoastlineKernel.fractalizeOpen(p, seed: 7, settings: settings, width: 100, height: 100) }
		#expect(open([]).points.isEmpty && open([]).originalIndices.isEmpty)
		let one = [Point(x: 5, y: 5)]
		#expect(open(one).points == one && open(one).originalIndices == [0])
		let two = [Point(x: 5, y: 5), Point(x: 60, y: 30)]
		let displaced = open(two)
		#expect(displaced.points.first == two[0] && displaced.points.last == two[1] && displaced.points.count > 2 && displaced.originalIndices == [0, displaced.points.count - 1])
		// coincident points: a zero-length segment is not subdivided, even with minEdge 0 (no division by zero, no NaN)
		let same = [Point(x: 5, y: 5), Point(x: 5, y: 5), Point(x: 40, y: 20), Point(x: 40, y: 20)]
		let shape = open(same)
		#expect(shape.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
		#expect(shape.points.first == same.first && shape.points.last == same.last)
		let closedSame = CoastlineKernel.fractalize([Point(x: 5, y: 5), Point(x: 5, y: 5), Point(x: 5, y: 5)], seed: 7, settings: settings, width: 100, height: 100)
		#expect(closedSame.points.count == 3 && closedSame.points.allSatisfy { $0.x.isFinite })
	}

	@Test func anOpenChainEdgeWithBothEndsOnTheFrameIsNotDisplaced() {
		var settings = CoastlineSettings()
		settings.smoothThreshold = 0
		let chain = [Point(x: 0, y: 10), Point(x: 0, y: 60), Point(x: 40, y: 30), Point(x: 100, y: 80)]
		let shape = CoastlineKernel.fractalizeOpen(chain, seed: 99, settings: settings, width: 100, height: 100)
		#expect(shape.originalIndices[1] == 1, "no point between the two frame points")
		#expect(shape.originalIndices[3] > shape.originalIndices[2] + 1, "the interior edge was displaced")
		// the end on the frame stays exactly on the frame, since only midpoints are inserted
		#expect(shape.points.first!.x == 0 && shape.points.last!.x == 100)
	}
}
