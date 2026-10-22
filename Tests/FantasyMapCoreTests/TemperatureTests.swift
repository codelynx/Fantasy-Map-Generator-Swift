import CryptoKit
import Foundation
import Testing
@testable import FantasyMapCore

/// Water chain, stage 2: temperature, compared EXACTLY with fixtures captured from the original's own `Temperature.generate`
/// (Fixtures/original/temperature-original.json), which runs after the original's own grid, heightmap, lake and Coordinates steps.
struct TemperatureTests {
	struct Request: Decodable { var mapSize: Double?, latitude: Double?, longitude: Double? }
	struct Box: Decodable { var latT: Double, latN: Double, latS: Double, lonT: Double, lonW: Double, lonE: Double }
	struct Climate: Decodable { struct T: Decodable { var equator: Double, northPole: Double, southPole: Double }; var temperature: T, exponent: Double }
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, climateName: String, climate: Climate
		var requested: Request, coordinates: Box, cells: Int, cellsX: Int, tempSha256: String, min: Int, max: Int, temp: [Int8]?
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("temperature-original")).runs }

	func settings(_ r: Run) -> TemperatureSettings {
		var s = TemperatureSettings()
		s.equator = r.climate.temperature.equator
		s.northPole = r.climate.temperature.northPole
		s.southPole = r.climate.temperature.southPole
		s.heightExponent = r.climate.exponent
		return s
	}

	func sha(_ temp: [Int8]) -> String { SHA256.hash(data: Data(temp.map { UInt8(bitPattern: $0) })).map { String(format: "%02x", $0) }.joined() }

	func map(_ r: Run) throws -> LandMap {
		try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
	}

	@Test func temperatureMatchesTheOriginalGivenTheOriginalsOwnBounds() throws {
		// isolates this stage: our heights and grid points (proven against the original by the land layer) with the bounds the original had
		let all = try runs()
		var wrong = 0, wholeWrong = 0, whole = 0
		for r in all {
			let m = try map(r)
			let t = try Temperature.compute(heights: m.heights, points: m.grid.points, cellsX: m.grid.cellsX, mapHeight: m.height, latN: r.coordinates.latN, latT: r.coordinates.latT, settings: settings(r))
			if t.count != r.cells || m.grid.cellsX != r.cellsX || sha(t) != r.tempSha256 { wrong += 1 }
			if let expected = r.temp { whole += 1; if t != expected { wholeWrong += 1 } }
		}
		#expect(all.count == 174 && whole == 48)
		#expect(wrong == 0, "\(wrong) of \(all.count) runs differ from the original")
		#expect(wholeWrong == 0, "\(wholeWrong) of the \(whole) whole arrays differ")
	}

	@Test func theWholeChainMatchesTheOriginalFromTheMapAlone() throws {
		// our map -> our geography (a fresh stream, the request of the run) -> our temperature, against the original's chain
		let all = try runs()
		var wrong = 0
		for r in all {
			let m = try map(r)
			let g = try Geography.generate(for: m, request: GeographyRequest(mapSize: r.requested.mapSize, latitude: r.requested.latitude, longitude: r.requested.longitude))
			let t = try Temperature.compute(for: m, geography: g, settings: settings(r))
			if sha(t) != r.tempSha256 { wrong += 1 }
		}
		#expect(wrong == 0, "\(wrong) of \(all.count) differ from the original")
	}

	@Test func theRangeOfTheCapturedTemperaturesCoversTheBranchesOfTheOriginal() throws {
		let all = try runs()
		#expect(all.contains { $0.min <= -100 } && all.contains { $0.max >= 40 } && all.contains { $0.climateName == "exponent3" } && all.contains { $0.coordinates.latT >= 179 }, "polar, hot, odd-exponent and whole-world runs are present")
		#expect(all.contains { $0.coordinates.latT < 10 }, "narrow slices are present")
	}

	// MARK: hand-computed cases

	/// One row per latitude, each EXACT: a zero-span geography (latitude span 0) puts every row at the northern edge's latitude, so a
	/// one-row map at latN = latitude has exactly that latitude (a latitude recovered from a row's y is not exact in floating point).
	func at(_ latitude: Double, height: Height = 5, settings: TemperatureSettings = TemperatureSettings()) throws -> Int8 {
		try Temperature.compute(heights: [height], points: [Point(x: 5, y: 0)], cellsX: 1, mapHeight: 100, latN: latitude, latT: 0, settings: settings)[0]
	}

	@Test func seaLevelTemperatureFollowsTheTropicalAndPolarGradients() throws {
		// the tropics are -20 to 16 degrees: 27 - |latitude| x 0.15, stored by the Int8 store (truncated toward zero)
		#expect(try [0, 10, -10, 16, -20].map { try at($0) } == [27, 25, 25, 24, 24], "27, 25.5, 25.5, 24.6, 24.0")
		// just outside the tropics the other gradients start: 16.0001 north is 24.5999 and -20.0001 south is 23.99994, which stores as 23
		#expect(try at(16.0001) == 24 && at(-20.0001) == 23, "the bounds are inclusive: -20 is tropical (24), -20.0001 is not (23)")
		// north of the tropic: from 24.6 at 16 degrees toward -30 at 90 degrees, a gradient of 54.6 / 74 per degree
		#expect(try [45, 60, 89].map { try at($0) } == [3, -7, -29], "3.20, -7.86 and -29.26, stored toward zero")
		// south of the tropic: from 24 at -20 degrees toward -15 at -90 degrees, a gradient of 39 / 70 per degree
		#expect(try [-45, -60, -89].map { try at($0) } == [10, 1, -14], "10.07, 1.71 and -14.44, stored toward zero")
	}

	@Test func altitudeCoolsBySixAndAHalfDegreesPerKilometre() throws {
		// the drop is rn((height - 18)^2 / 1000 x 6.5): none below sea level, 0.026 at 20 (0 after rounding), 3.146 at 40 (3), 43.706 at 100 (44)
		let t = try [5, 19, 20, 40, 100].map { try at(0, height: $0) }
		#expect(t == [27, 27, 27, 24, -17], "27 minus 0, 0, 0, 3 and 44: \(t)")
		// another exponent: (100 - 18)^1.5 / 1000 x 6.5 = 4.826 -> 5
		var s = TemperatureSettings()
		s.heightExponent = 1.5
		#expect(try at(0, height: 100, settings: s) == 22)
	}

	@Test func theStoreTruncatesTowardZeroAndTheValueIsClampedToTheInt8Range() throws {
		var s = TemperatureSettings()
		s.equator = 3.9
		#expect(try at(0, settings: s) == 3, "3.9 is stored as 3")
		s.equator = -3.5
		#expect(try at(0, settings: s) == -3, "-3.5 is stored as -3 (toward zero, not floor)")
		s.equator = -100
		#expect(try at(0, height: 255, settings: s) == -128, "a drop of hundreds is clamped to -128 before the store, not wrapped")
		s.equator = 100
		#expect(try at(0, settings: s) == 100)
	}

	@Test func theLatitudeOfARowIsReadFromItsFirstCellOnly() throws {
		// two rows of three cells: the later cells of a row have wildly different y, which must not matter; the first cell's y does
		func run(_ y: [Double]) throws -> [Int8] {
			let pts = [Point(x: 1, y: y[0]), Point(x: 2, y: y[1]), Point(x: 3, y: y[2]), Point(x: 1, y: y[3]), Point(x: 2, y: y[4]), Point(x: 3, y: y[5])]
			return try Temperature.compute(heights: [Height](repeating: 5, count: 6), points: pts, cellsX: 3, mapHeight: 100, latN: 90, latT: 180, settings: TemperatureSettings())
		}
		let base = try run([10, 10, 10, 60, 60, 60])
		#expect(try run([10, 99, 0, 60, 3, 77]) == base, "other cells' y are ignored")
		#expect(try run([40, 10, 10, 60, 60, 60]) != base, "the first cell's y decides the row")
		#expect(base[0] == base[1] && base[1] == base[2] && base[3] == base[4] && base[4] == base[5], "a row has one sea-level temperature")
	}

	@Test func aZeroSpanGeographyGivesOneLatitudeEverywhere() throws {
		let pts = (0..<6).map { Point(x: Double($0), y: Double($0) * 10) }
		let t = try Temperature.compute(heights: [Height](repeating: 5, count: 6), points: pts, cellsX: 1, mapHeight: 100, latN: 20, latT: 0, settings: TemperatureSettings())
		#expect(Set(t).count == 1, "with a latitude span of 0 every row is at the northern edge's latitude")
	}

	@Test func settingsAndInputsAreValidatedWithNamedErrors() {
		let pts = [Point(x: 0, y: 0), Point(x: 1, y: 1)]
		func bad(_ change: (inout TemperatureSettings) -> Void) -> Bool {
			var s = TemperatureSettings()
			change(&s)
			return (try? Temperature.compute(heights: [5, 5], points: pts, cellsX: 1, mapHeight: 10, latN: 90, latT: 180, settings: s)) == nil
		}
		#expect(bad { $0.equator = .nan } && bad { $0.northPole = .infinity } && bad { $0.southPole = 101 } && bad { $0.equator = -101 })
		#expect(bad { $0.heightExponent = 0 } && bad { $0.heightExponent = 6 } && bad { $0.heightExponent = .nan })
		let good = TemperatureSettings()
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5], points: pts, cellsX: 1, mapHeight: 10, latN: 90, latT: 180, settings: good) }
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5, 5], points: pts, cellsX: 3, mapHeight: 10, latN: 90, latT: 180, settings: good) }
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5, 5], points: pts, cellsX: 0, mapHeight: 10, latN: 90, latT: 180, settings: good) }
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5, 5], points: pts, cellsX: 1, mapHeight: 0, latN: 90, latT: 180, settings: good) }
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5, 5], points: pts, cellsX: 1, mapHeight: 10, latN: .nan, latT: 180, settings: good) }
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5, 5], points: pts, cellsX: 1, mapHeight: 10, latN: 90, latT: 181, settings: good) }
		#expect(throws: Temperature.Problem.invalidInputs) { try Temperature.compute(heights: [5, 5], points: pts, cellsX: 1, mapHeight: 10, latN: 90, latT: -1, settings: good) }
		#expect((try? Temperature.compute(heights: [], points: [], cellsX: 1, mapHeight: 10, latN: 90, latT: 180, settings: good)) == [], "no cells, no temperatures")
	}

	@Test func theLatitudeIntervalThatIsConsumedMustLieWithinThePoles() throws {
		let m = try LandMap.generate(seed: "kaz-1", width: 640, height: 400, cellsDesired: 600, template: try #require(HeightmapTemplate.named("continents")))
		func with(_ c: MapCoordinates) -> Result<[Int8], Temperature.Problem> {
			var g = try! Geography.generate(for: m)
			g.coordinates = c
			do { return .success(try Temperature.compute(for: m, geography: g)) } catch let p as Temperature.Problem { return .failure(p) } catch { fatalError("\(error)") }
		}
		func box(latN: Double, latT: Double, latS: Double? = nil) -> MapCoordinates { MapCoordinates(latT: latT, latN: latN, latS: latS ?? (latN - latT), lonT: 90, lonW: 0, lonE: 90) }
		// malformed intervals: past the north pole, past the south pole, both
		for (latN, latT) in [(100.0, 10.0), (91.0, 0.0), (-91.0, 0.0), (-90.0, 180.0), (90.0, 181.0), (50.0, 150.0), (.nan, 10.0), (20.0, .infinity)] {
			if case .success = with(box(latN: latN, latT: latT)) { Issue.record("latN \(latN), latT \(latT) was accepted") }
		}
		#expect({ if case .failure(.invalidInputs) = with(box(latN: -90, latT: 180)) { return true } else { return false } }(), "latN -90 with a span of 180 reaches -270")
		// valid: the whole globe, a polar slice at each end, zero spans at both poles and in between
		for (latN, latT) in [(90.0, 180.0), (90.0, 10.0), (-80.0, 10.0), (90.0, 0.0), (-90.0, 0.0), (0.0, 0.0), (45.3, 135.3)] {
			if case .failure(let p) = with(box(latN: latN, latT: latT)) { Issue.record("latN \(latN), latT \(latT) was refused: \(p)") }
		}
		// just over the south pole after the package's own one-decimal rounding is refused; exactly on it is accepted
		if case .success = with(box(latN: 45.3, latT: 135.4)) { Issue.record("a southern bound of -90.1 was accepted") }
		// the stored latS is neither trusted nor read: a wrong one changes nothing
		#expect(with(box(latN: 90, latT: 180, latS: 9999)) == with(box(latN: 90, latT: 180)), "only latN and latT are consumed")
	}

	@Test func timingAtTenAndAHundredThousandCells() throws {
		for cells in [10_000, 100_000] {
			let m = try LandMap.generate(seed: "kaz-1", width: 1280, height: 800, cellsDesired: cells, template: try #require(HeightmapTemplate.named("continents")))
			let g = try Geography.generate(for: m)
			let start = Date()
			let t = try Temperature.compute(for: m, geography: g)
			print("TEMPERATURE \(cells) cells: \(Int(Date().timeIntervalSince(start) * 1000)) ms, range \(t.min() ?? 0) to \(t.max() ?? 0)")
			#expect(t.count == m.heights.count)
		}
	}
}
