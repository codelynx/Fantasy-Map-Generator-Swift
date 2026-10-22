import Foundation
import Testing
@testable import FantasyMapCore

/// The validated surface over the displacement kernel (drawing stage 2c, step 3).
struct RougheningTests {
	let square = [Point(x: 10, y: 10), Point(x: 90, y: 10), Point(x: 90, y: 90), Point(x: 10, y: 90)]

	@Test func defaultsAreTheOriginalsExceptTheDocumentedAmplitudeAndValidate() throws {
		let s = RoughnessSettings()
		#expect(CoastlineSettings().baseAmplitude == 1.5, "the parity kernel keeps the original's amplitude")
		#expect(s.maxDepth == 4 && s.baseAmplitude == 0.75 && s.amplitudeDecay == 0.9 && s.minEdge == 1 && s.smoothThreshold == 0.25)
		#expect(s.roughnessContrast == 1.5 && s.roughnessScale == 60 && s.lakeSmoothThreshMult == 2 && s.variant == 0)
		try s.validate()
	}

	@Test func settingsOutsideTheLimitsAreRefusedNotClamped() {
		func refused(_ change: (inout RoughnessSettings) -> Void) -> Bool {
			var s = RoughnessSettings()
			change(&s)
			return (try? s.validate()) == nil
		}
		#expect(refused { $0.maxDepth = -1 } && refused { $0.maxDepth = Roughening.maximumDepth + 1 } && refused { $0.maxDepth = Int.max })
		for bad in [Double.nan, .infinity, -.infinity] {
			#expect(refused { $0.baseAmplitude = bad } && refused { $0.amplitudeDecay = bad } && refused { $0.minEdge = bad })
			#expect(refused { $0.smoothThreshold = bad } && refused { $0.roughnessContrast = bad } && refused { $0.roughnessScale = bad } && refused { $0.lakeSmoothThreshMult = bad })
		}
		#expect(refused { $0.baseAmplitude = -1 } && refused { $0.amplitudeDecay = 1.1 } && refused { $0.smoothThreshold = 1.5 } && refused { $0.minEdge = -0.1 })
		#expect(refused { $0.roughnessContrast = 0 } && refused { $0.roughnessScale = 0.5 } && refused { $0.lakeSmoothThreshMult = -1 } && refused { $0.variant = 2_000_000 })
		#expect(!refused { $0.maxDepth = 0 } && !refused { $0.maxDepth = Roughening.maximumDepth } && !refused { $0.baseAmplitude = 0 })
	}

	@Test func worstCaseOutputIsExactAndOverflowChecked() throws {
		// closed: n * 2^depth points + n stored indices; open: (n - 1) * 2^depth + 1 points + n indices
		#expect(Roughening.worstCaseOutput(vertexCount: 4, closed: true, depth: 4) == 4 * 16 + 4)
		#expect(Roughening.worstCaseOutput(vertexCount: 4, closed: false, depth: 4) == 3 * 16 + 1 + 4)
		#expect(Roughening.worstCaseOutput(vertexCount: 0, closed: true, depth: 4) == 0 && Roughening.worstCaseOutput(vertexCount: 0, closed: false, depth: 4) == 0)
		#expect(Roughening.worstCaseOutput(vertexCount: 1, closed: false, depth: 6) == 1 + 1) // one point, no edges
		#expect(Roughening.worstCaseOutput(vertexCount: Int.max / 2, closed: true, depth: 6) == nil, "overflow gives nil, not a wrapped number")
		#expect(Roughening.worstCaseOutput(vertexCount: 10, closed: true, depth: 200) == nil)
		// the bound is real: the actual output never exceeds it, with every edge rough (calm threshold 0) and the deepest depth
		var s = RoughnessSettings()
		s.smoothThreshold = 0
		s.minEdge = 0
		for depth in 0...Roughening.maximumDepth {
			s.maxDepth = depth
			for closed in [true, false] {
				let chain = try Roughening.displace(square, closed: closed, isLake: false, seed: 5, settings: s, width: 100, height: 100, budget: .max)
				let worst = try #require(Roughening.worstCaseOutput(vertexCount: 4, closed: closed, depth: depth))
				#expect(chain.points.count + chain.originalIndices.count <= worst, "depth \(depth) closed \(closed): \(chain.points.count)")
			}
		}
	}

	@Test func theBudgetIsChecked_beforeAnyWorkAndInputsAreValidated() throws {
		let s = RoughnessSettings()
		#expect(throws: RoughnessSettings.Problem.outputBudget) { try Roughening.displace(square, closed: true, isLake: false, seed: 1, settings: s, width: 100, height: 100, budget: 10) }
		#expect(throws: RoughnessSettings.Problem.invalidInput("coordinates")) { try Roughening.displace([Point(x: .nan, y: 0), Point(x: 1, y: 1)], closed: false, isLake: false, seed: 1, settings: s, width: 100, height: 100, budget: .max) }
		#expect(throws: RoughnessSettings.Problem.invalidInput("coordinates")) { try Roughening.displace([Point(x: 1e12, y: 0), Point(x: 1, y: 1)], closed: false, isLake: false, seed: 1, settings: s, width: 100, height: 100, budget: .max) }
		#expect(throws: RoughnessSettings.Problem.invalidInput("size")) { try Roughening.displace(square, closed: true, isLake: false, seed: 1, settings: s, width: 0, height: 100, budget: .max) }
		var bad = s
		bad.maxDepth = 50
		#expect(throws: RoughnessSettings.Problem.invalidSetting("maxDepth")) { try Roughening.displace(square, closed: true, isLake: false, seed: 1, settings: bad, width: 100, height: 100, budget: .max) }
	}

	@Test func theLakeShoreIsCalmerAndTheMapSeedPolicyIsStable() throws {
		var s = RoughnessSettings()
		s.smoothThreshold = 0.3
		let outline = (0..<30).map { i in Point(x: 50 + 40 * cos(Double(i) * 0.2094), y: 50 + 40 * sin(Double(i) * 0.2094)) }
		let seed = Roughening.seed(mapSeed: "kaz-1", variant: 0)
		let sea = try Roughening.displace(outline, closed: true, isLake: false, seed: seed, settings: s, width: 100, height: 100, budget: .max)
		let lake = try Roughening.displace(outline, closed: true, isLake: true, seed: seed, settings: s, width: 100, height: 100, budget: .max)
		#expect(lake.points.count < sea.points.count, "a lake shore is calmer: \(lake.points.count) vs \(sea.points.count)")
		#expect(seed == Roughening.seed(mapSeed: "kaz-1", variant: 0) && seed != Roughening.seed(mapSeed: "kaz-1", variant: 1) && seed != Roughening.seed(mapSeed: "kaz-2", variant: 0))
	}
}
