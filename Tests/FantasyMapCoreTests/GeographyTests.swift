import Foundation
import Testing
@testable import FantasyMapCore

/// Water chain, stage 1: the map's place on the globe, compared EXACTLY with fixtures captured from the original's own
/// `Coordinates.generate` (Fixtures/original/coordinates-original.json), including the random stream's state before and after.
struct GeographyTests {
	struct Request: Decodable { var mapSize: Double?, latitude: Double?, longitude: Double? }
	struct Triple: Decodable { var mapSize: Double, latitude: Double, longitude: Double }
	struct Box: Decodable { var latT: Double, latN: Double, latS: Double, lonT: Double, lonW: Double, lonE: Double }
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, heightmapKey: String, templateOption: String
		var requested: Request, isPartial: Bool, stateBefore: [Double], stateAfter: [Double], geography: Triple, coordinates: Box
	}
	struct Fixture: Decodable { var runs: [Run] }

	func fixture() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("coordinates-original")).runs }

	func compare(_ g: Geography, _ r: Run) -> Bool {
		g.mapSize == r.geography.mapSize && g.latitude == r.geography.latitude && g.longitude == r.geography.longitude
			&& g.coordinates == MapCoordinates(latT: r.coordinates.latT, latN: r.coordinates.latN, latS: r.coordinates.latS, lonT: r.coordinates.lonT, lonW: r.coordinates.lonW, lonE: r.coordinates.lonE)
	}

	@Test func theGeographyMatchesTheOriginalAndTheStreamMovesTheSameWay() throws {
		let runs = try fixture()
		var wrong = 0, streamWrong = 0, startWrong = 0, drew = 0
		for r in runs {
			var random = Alea(seed: r.seed)
			if random.state != r.stateBefore { startWrong += 1 } // the stream starts as a fresh Alea(seed)
			guard let g = try? Geography.generate(template: r.templateOption, isPartial: r.isPartial, width: r.width, height: r.height,
				request: GeographyRequest(mapSize: r.requested.mapSize, latitude: r.requested.latitude, longitude: r.requested.longitude), random: &random) else { wrong += 1; continue }
			if !compare(g, r) { wrong += 1 }
			if random.state != r.stateAfter { streamWrong += 1 }
			if r.stateAfter != r.stateBefore { drew += 1 }
		}
		#expect(runs.count == 123)
		#expect(startWrong == 0, "\(startWrong) runs did not start from a fresh Alea(seed)")
		#expect(wrong == 0, "\(wrong) of \(runs.count) differ from the original")
		#expect(streamWrong == 0, "\(streamWrong) runs consumed a different number of draws")
		#expect(drew > 80, "the random branches were exercised (\(drew) runs drew)")
	}

	@Test func theGeographyOfAGeneratedMapMatchesTheOriginalWithoutAssumingAnyState() throws {
		// the whole loop: our own map, its recipe's template, its features and a fresh stream, against the original's chain
		let runs = try fixture().filter { $0.templateOption == $0.heightmapKey && $0.requested.mapSize == nil && $0.requested.latitude == nil && $0.requested.longitude == nil }
		#expect(runs.count == 84)
		var wrong = 0, partialWrong = 0
		for r in runs {
			let m = try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.heightmapKey)))
			if m.features.features.contains(where: { $0.land && $0.border }) != r.isPartial { partialWrong += 1 }
			if !compare(try Geography.generate(for: m), r) { wrong += 1 }
		}
		#expect(partialWrong == 0, "\(partialWrong) maps disagree with the original on whether land reaches the border")
		#expect(wrong == 0, "\(wrong) of \(runs.count) differ from the original")
	}

	@Test func aLoadedMapGivesTheSameGeographyAsTheMapItWasSavedFrom() throws {
		let m = try LandMap.generate(seed: "kaz-1", width: 640, height: 400, cellsDesired: 800, template: try #require(HeightmapTemplate.named("continents")))
		let loaded = try LandMap(decoding: try m.encoded())
		#expect(try Geography.generate(for: loaded) == (try Geography.generate(for: m)))
	}

	@Test func probabilityAtTheEdgesDrawsNothingAndInsideItDrawsOne() {
		var a = Alea(seed: "p")
		let before = a.state
		#expect(JSRandom.p(1, &a) && JSRandom.p(2, &a) && !JSRandom.p(0, &a) && !JSRandom.p(-1, &a))
		#expect(a.state == before, "P at 1 or more and at 0 or less draws nothing")
		_ = JSRandom.p(0.5, &a)
		var b = Alea(seed: "p")
		_ = b.next()
		#expect(a.state == b.state, "a probability in between draws exactly one value")
	}

	@Test func gaussStaysInBoundsRoundsAndNeedsAtLeastTwoDraws() {
		var a = Alea(seed: "g")
		for _ in 0..<2000 {
			let v = JSRandom.gauss(30, 20, 15, 80, 0, &a)
			#expect(v >= 15 && v <= 80 && v == v.rounded(), "\(v)")
		}
		var b = Alea(seed: "g")
		for _ in 0..<500 { let v = JSRandom.gauss(3, 2, 1, 5, 1, &b); #expect(v >= 1 && v <= 5 && abs(v * 10 - (v * 10).rounded()) < 1e-9) }
		var c = Alea(seed: "g")
		let start = c.state
		_ = JSRandom.gauss(0, 1, -10, 10, 3, &c)
		#expect(c.state != start, "a gauss call draws at least one pair of values")
		// a fixed expected value with no deviation is returned as is, after the polar draws
		var e = Alea(seed: "g")
		#expect(JSRandom.gauss(42, 0, 0, 100, 0, &e) == 42)
	}

	@Test func theBoxIsCalculatedFromTheSizeAndTheShifts() {
		let whole = try! Geography.calculate(mapSize: 100, latitude: 50, longitude: 50, width: 1280, height: 800)
		#expect(whole == MapCoordinates(latT: 180, latN: 90, latS: -90, lonT: 288, lonW: -144, lonE: 144), "the whole world on a 1280 x 800 map")
		let half = try! Geography.calculate(mapSize: 50, latitude: 0, longitude: 100, width: 800, height: 800)
		// latT = 0.5 x 180 = 90; no north-south shift keeps latN at 90, so latS = 0; lonT = 90 on a square map; a full east shift puts lonE at 180 - (360 - 90) = -90
		#expect(half.latT == 90 && half.latN == 90 && half.latS == 0 && half.lonT == 90 && half.lonE == -90 && half.lonW == -180)
		let zero = try! Geography.calculate(mapSize: 0, latitude: 50, longitude: 50, width: 100, height: 100)
		#expect(zero.latT == 0 && zero.lonT == 0 && zero.latN == 0 && zero.lonE == 0)
		#expect(try! Geography.calculate(mapSize: 100, latitude: 50, longitude: 50, width: 10_000, height: 10).lonT == 360, "the longitude span is limited to 360")
	}

	@Test func requestsAreUsedWhenGivenAndStillCostTheTemplatesDraws() throws {
		var drawn = Alea(seed: "r")
		let free = try Geography.generate(template: "continents", isPartial: false, width: 1280, height: 800, request: GeographyRequest(), random: &drawn)
		var given = Alea(seed: "r")
		let all = try Geography.generate(template: "continents", isPartial: false, width: 1280, height: 800, request: GeographyRequest(mapSize: 33, latitude: 44, longitude: 55), random: &given)
		#expect(all.mapSize == 33 && all.latitude == 44 && all.longitude == 55)
		#expect(given.state == drawn.state, "the original draws for the template even when everything is requested")
		#expect(free.longitude == 50 || free.mapSize == 100, "an unrequested value comes from the template")
		var zero = Alea(seed: "r")
		#expect(try Geography.generate(template: "continents", isPartial: false, width: 1280, height: 800, request: GeographyRequest(mapSize: 0), random: &zero).mapSize == 0, "0 is a value, not 'not given'")
	}

	@Test func invalidRequestsAndSizesAreRefusedAsADocumentedDivergence() {
		var r = Alea(seed: "x")
		for bad in [GeographyRequest(mapSize: -1), GeographyRequest(mapSize: 101), GeographyRequest(latitude: .nan), GeographyRequest(longitude: .infinity), GeographyRequest(latitude: -0.5)] {
			#expect(throws: Geography.Problem.invalidRequest) { try Geography.generate(template: "continents", isPartial: false, width: 100, height: 100, request: bad, random: &r) }
		}
		for (w, h) in [(0.0, 100.0), (100.0, 0.0), (.nan, 100.0), (100.0, .infinity), (-5.0, 100.0)] {
			#expect(throws: Geography.Problem.invalidSize) { try Geography.generate(template: "continents", isPartial: false, width: w, height: h, request: GeographyRequest(), random: &r) }
		}
		#expect(r.state == Alea(seed: "x").state, "a refused call draws nothing")
	}

	@Test func anExtremeAspectRatioIsRefusedNotTurnedIntoNaN() throws {
		// width / height overflows although both are finite and positive: with a map size of 0 the longitude span would be infinity x 0
		for size in [0.0, 50, 100] {
			var r = Alea(seed: "aspect")
			let before = r.state
			#expect(throws: Geography.Problem.unsupportedAspectRatio) { try Geography.generate(template: "continents", isPartial: false, width: 1e300, height: 1e-300, request: GeographyRequest(mapSize: size, latitude: 50, longitude: 50), random: &r) }
			#expect(r.state == before, "a refused aspect ratio draws nothing")
			#expect(throws: Geography.Problem.unsupportedAspectRatio) { try Geography.calculate(mapSize: size, latitude: 50, longitude: 50, width: 1e300, height: 1e-300) }
		}
		// the largest and smallest ratios that are still finite are accepted, with finite results, and the original's arithmetic
		let big = try Geography.calculate(mapSize: 0, latitude: 50, longitude: 50, width: 1e300, height: 1e-8)
		#expect(big.lonT == 0 && [big.latT, big.latN, big.latS, big.lonT, big.lonW, big.lonE].allSatisfy { $0.isFinite }, "ratio 1e308 times a zero span is a zero span")
		let small = try Geography.calculate(mapSize: 100, latitude: 50, longitude: 50, width: 1e-300, height: 1e300)
		#expect(small.lonT == 0 && [small.lonW, small.lonE].allSatisfy { $0.isFinite }, "a ratio that underflows to 0 gives a zero longitude span")
		let wide = try Geography.calculate(mapSize: 100, latitude: 50, longitude: 50, width: 1e300, height: 1e100)
		#expect(wide.lonT == 360, "a huge finite ratio is limited to 360")
		// an ordinary map is unchanged by the validation
		#expect(try Geography.calculate(mapSize: 100, latitude: 50, longitude: 50, width: 1280, height: 800) == MapCoordinates(latT: 180, latN: 90, latS: -90, lonT: 288, lonW: -144, lonE: 144))
	}

	@Test func thePublicCalculateValidatesLikeGenerate() {
		#expect(throws: Geography.Problem.invalidRequest) { try Geography.calculate(mapSize: -1, latitude: 50, longitude: 50, width: 100, height: 100) }
		#expect(throws: Geography.Problem.invalidRequest) { try Geography.calculate(mapSize: 50, latitude: .nan, longitude: 50, width: 100, height: 100) }
		#expect(throws: Geography.Problem.invalidRequest) { try Geography.calculate(mapSize: 50, latitude: 50, longitude: 101, width: 100, height: 100) }
		#expect(throws: Geography.Problem.invalidSize) { try Geography.calculate(mapSize: 50, latitude: 50, longitude: 50, width: 0, height: 100) }
		#expect(throws: Geography.Problem.invalidSize) { try Geography.calculate(mapSize: 50, latitude: 50, longitude: 50, width: .infinity, height: 100) }
	}

	@Test func aSuccessfulGenerateCommitsItsDrawsAndARefusedOneLeavesTheStreamAlone() throws {
		var ok = Alea(seed: "commit")
		var reference = Alea(seed: "commit")
		_ = try Geography.generate(template: "continents", isPartial: false, width: 1280, height: 800, request: GeographyRequest(), random: &ok)
		var local = reference
		_ = Geography.sizeAndPositionForTests(template: "continents", isPartial: false, random: &local)
		reference = local
		#expect(ok.state == reference.state, "a successful call advances the caller's stream by the template's draws")
	}
}
