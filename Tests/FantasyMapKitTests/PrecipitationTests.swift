import CryptoKit
import Foundation
import Testing
@testable import FantasyMapKit

/// Water chain, stage 3: precipitation, compared EXACTLY with fixtures captured from the original's own `Precipitation.generate`
/// (Fixtures/original/precipitation-original.json), which runs after the original's own grid, heightmap, lake, Coordinates and
/// Temperature steps. The random stream is compared too: the next value after each run.
struct PrecipitationTests {
	struct Request: Decodable { var mapSize: Double?, latitude: Double?, longitude: Double? }
	struct Box: Decodable { var latT: Double, latN: Double, latS: Double }
	struct FoundWinds: Decodable { var westerly: [[Double]], easterly: [[Double]], northerly: Int, southerly: Int }
	struct Run: Decodable {
		var seed: String, width: Double, height: Double, cellsDesired: Int, key: String, windName: String, winds: [Double], precName: String, precipitation: Double
		var requested: Request, coordinates: Box, cells: Int, cellsX: Int, cellsY: Int, tempSha256: String, precSha256: String, min: Int, max: Int
		var windsFound: FoundWinds, nextRandom: Double, prec: [UInt8]?
	}
	struct Fixture: Decodable { var runs: [Run] }

	func runs() throws -> [Run] { try JSONDecoder().decode(Fixture.self, from: Fixtures.data("precipitation-original")).runs }

	func settings(_ r: Run) -> PrecipitationSettings {
		var s = PrecipitationSettings()
		s.precipitation = r.precipitation
		s.winds = r.winds
		return s
	}

	func sha<T: FixedWidthInteger>(_ values: [T]) -> String {
		SHA256.hash(data: Data(values.map { UInt8(truncatingIfNeeded: $0) })).map { String(format: "%02x", $0) }.joined()
	}

	func map(_ r: Run) throws -> LandMap {
		try LandMap.generate(seed: r.seed, width: r.width, height: r.height, cellsDesired: r.cellsDesired, template: try #require(HeightmapTemplate.named(r.key)))
	}

	func temperature(_ m: LandMap, latN: Double, latT: Double) throws -> [Int8] {
		try Temperature.compute(heights: m.heights, points: m.grid.points, cellsX: m.grid.cellsX, mapHeight: m.height, latN: latN, latT: latT, settings: TemperatureSettings())
	}

	func bands(_ found: [[Double]]) -> [Precipitation.Band] { found.map { Precipitation.Band(firstCell: Int($0[0]), latitudeModifier: $0[1], tier: Int($0[2])) } }

	@Test func precipitationMatchesTheOriginalGivenTheOriginalsOwnBounds() throws {
		// isolates this stage: our heights, grid and temperature (proven against the original by the earlier stages) with the original's bounds
		let all = try runs()
		var wrong = 0, wrongStream = 0, wrongWinds = 0, wholeWrong = 0, whole = 0
		for r in all {
			let m = try map(r)
			#expect(m.grid.cellsX == r.cellsX && m.grid.cellsY == r.cellsY && m.heights.count == r.cells)
			let temp = try temperature(m, latN: r.coordinates.latN, latT: r.coordinates.latT)
			#expect(sha(temp) == r.tempSha256, "the temperature of \(r.seed) \(r.key) differs, so this stage cannot be isolated")
			var random = Alea(seed: m.seed)
			let prec = try Precipitation.compute(heights: m.heights, temperature: temp, cellsX: m.grid.cellsX, cellsY: m.grid.cellsY, cellsDesired: m.cellsDesired, latN: r.coordinates.latN, latT: r.coordinates.latT, settings: settings(r), random: &random)
			if prec.count != r.cells || sha(prec) != r.precSha256 { wrong += 1 }
			if random.next() != r.nextRandom { wrongStream += 1 }
			let (found, _) = try Precipitation.checkedWinds(cells: r.cells, cellsX: r.cellsX, cellsY: r.cellsY, latN: r.coordinates.latN, latT: r.coordinates.latT, settings: settings(r))
			if found.westerly != bands(r.windsFound.westerly) || found.easterly != bands(r.windsFound.easterly) || found.northerly != r.windsFound.northerly || found.southerly != r.windsFound.southerly { wrongWinds += 1 }
			if let expected = r.prec { whole += 1; if prec != expected { wholeWrong += 1 } }
		}
		#expect(all.count == 300 && whole == 54)
		#expect(wrong == 0, "\(wrong) of \(all.count) runs differ from the original")
		#expect(wrongStream == 0, "\(wrongStream) runs left the random stream somewhere else than the original")
		#expect(wrongWinds == 0, "\(wrongWinds) runs found other winds than the original")
		#expect(wholeWrong == 0, "\(wholeWrong) of the \(whole) whole arrays differ")
	}

	@Test func theWholeChainMatchesTheOriginalFromTheMapAlone() throws {
		// our map -> our geography -> our temperature -> our precipitation, against the original's chain
		let all = try runs()
		var wrong = 0
		for r in all {
			let m = try map(r)
			let g = try Geography.generate(for: m, request: GeographyRequest(mapSize: r.requested.mapSize, latitude: r.requested.latitude, longitude: r.requested.longitude))
			let temp = try Temperature.compute(for: m, geography: g)
			let prec = try Precipitation.compute(for: m, geography: g, temperature: temp, settings: settings(r))
			if sha(prec) != r.precSha256 { wrong += 1 }
		}
		#expect(wrong == 0, "\(wrong) of \(all.count) differ from the original")
	}

	@Test func theCapturedRunsCoverTheBranchesOfTheOriginal() throws {
		let all = try runs()
		#expect(all.contains { $0.max == 0 } && all.contains { $0.max > 100 }, "dry and wet runs")
		#expect(all.contains { $0.windsFound.northerly > 0 } && all.contains { $0.windsFound.southerly > 0 } && all.contains { !$0.windsFound.westerly.isEmpty } && all.contains { !$0.windsFound.easterly.isEmpty })
		#expect(all.contains { $0.coordinates.latT > 60 } && all.contains { $0.coordinates.latT <= 60 }, "both sides of the vertical-wind latitude rule")
		#expect(all.contains { $0.windsFound.westerly.contains { $0[0] == 0 } }, "a band starting at cell 0 occurs, so the legacy skip is exercised")
		#expect(Set(all.map(\.cellsDesired)).count >= 5 && Set(all.map(\.precName)).count == 6 && Set(all.map(\.windName)).count == 10)
	}

	// MARK: hand-computed cases (small grids, expected values worked out by hand in plain arithmetic)

	/// Explicit grids at cellsDesired 10,000 (the modifier is 1 at the default rain level), the latitude zero everywhere (a zero span), so
	/// the latitude modifier is 4, the wind tier 2, and the stream is a fresh `Alea("x")`.
	func prec(_ heights: [Height], temp: [Int8]? = nil, cellsX: Int, cellsY: Int, winds: [Double], latN: Double = 0, latT: Double = 0, rain: Double = 100, cellsDesired: Int = 10000, random: inout Alea) throws -> [UInt8] {
		var s = PrecipitationSettings()
		s.winds = winds
		s.precipitation = rain
		return try Precipitation.compute(heights: heights, temperature: temp ?? [Int8](repeating: 20, count: heights.count), cellsX: cellsX, cellsY: cellsY, cellsDesired: cellsDesired, latN: latN, latT: latT, settings: s, random: &random)
	}

	func prec(_ heights: [Height], temp: [Int8]? = nil, cellsX: Int, cellsY: Int, winds: [Double], latN: Double = 0, latT: Double = 0, rain: Double = 100, cellsDesired: Int = 10000) throws -> [UInt8] {
		var random = Alea(seed: "x")
		return try prec(heights, temp: temp, cellsX: cellsX, cellsY: cellsY, winds: winds, latN: latN, latT: latT, rain: rain, cellsDesired: cellsDesired, random: &random)
	}

	let west = [Double](repeating: 90, count: 6), east = [Double](repeating: 270, count: 6)
	let fromNorth = [Double](repeating: 180, count: 6), fromSouth = [Double](repeating: 0, count: 6)

	@Test func aBandStartingAtCellZeroIsSkipped() throws {
		// one row: the only westerly band starts at cell 0, so no wind blows at all (the original's legacy quirk)
		#expect(try prec([30, 30, 30, 30], cellsX: 4, cellsY: 1, winds: west) == [0, 0, 0, 0])
		// the second row is not skipped
		#expect(try prec([30, 30, 30, 30], cellsX: 2, cellsY: 2, winds: west).prefix(2) == [0, 0])
		#expect(try prec([30, 30, 30, 30], cellsX: 2, cellsY: 2, winds: west).suffix(2).contains { $0 > 0 })
	}

	@Test func aWesterlyWindDrawsTheCoastalRainFromTheStreamAndTheLandRainByTheRules() throws {
		// row 1 of a 4 x 2 grid is [sea, sea, land, land] at heights 10, 10, 30, 30; the wind starts with 255 - 10 = 245 at cell 4
		// (max 120 x 4 capped at 255): cell 4 is sea with sea ahead: humidity min(245 + 5, 255) = 250, rain 5; cell 5 is sea with land
		// ahead: coastal rain 250 / rand(10, 20) on cell 6; cell 6: normal loss 25, height 30 to 30 adds nothing: rain 25, humidity
		// 250 - 25 + 1 = 226; cell 7 has nothing ahead (outside the array): it rains all its 226
		var probe = Alea(seed: "x")
		let d = floor(probe.next() * 11) + 10
		let coastal = Int(250 / d)
		var random = Alea(seed: "x")
		let result = try prec([30, 30, 30, 30, 10, 10, 30, 30], cellsX: 4, cellsY: 2, winds: west, random: &random)
		#expect(result == [0, 0, 0, 0, 5, 0, UInt8(coastal + 25), 226], "rand(10, 20) was \(d)")
		#expect(random.next() == probe.next(), "one draw was used")
	}

	@Test func sumsWrapAroundLikeAByteArray() throws {
		// row 1 is [sea 10, land 30]: coastal rain 245 / rand(10, 20) (12 to 24) lands on cell 3, then cell 3 rains all 245 on top: over 255
		var probe = Alea(seed: "x")
		let d = floor(probe.next() * 11) + 10
		let expected = (Int(245 / d) + 245) % 256
		#expect(Int(245 / d) + 245 > 255, "the case does exercise the wrap")
		#expect(try prec([30, 30, 10, 30], cellsX: 2, cellsY: 2, winds: west)[3] == UInt8(expected))
	}

	@Test func permafrostStopsTheWindFlux() throws {
		// the same land row, with and without a frozen cell: the frozen cell gets no rain and the humidity carries on unchanged
		let free = try prec([30, 30, 30, 30, 30, 30], cellsX: 3, cellsY: 2, winds: west)
		let frozen = try prec([30, 30, 30, 30, 30, 30], temp: [20, 20, 20, 20, -6, 20], cellsX: 3, cellsY: 2, winds: west)
		#expect(free[4] > 0 && frozen[4] == 0)
		#expect(try prec([30, 30, 30, 30, 30, 30], temp: [20, 20, 20, 20, -5, 20], cellsX: 3, cellsY: 2, winds: west) == free, "-5 is not frozen")
	}

	@Test func aNortherlyWindRainsDownTheColumns() throws {
		// 3 rows, 2 columns, all land at 30, every row sends a northerly wind: max 3/3 x 60 x 4 = 240, humidity 210 at the top
		// rain 21, then 190 gives 19, then 172 is rained out at the bottom (nothing ahead)
		#expect(try prec([Height](repeating: 30, count: 6), cellsX: 2, cellsY: 3, winds: fromNorth) == [21, 21, 19, 19, 172, 172])
	}

	@Test func risingGroundRainsMoreAndAMountainWallStopsTheWind() throws {
		// one column [30, 60, 90] from the north: cell 0: normal loss 21 + (60 - 30) x (60/70)^2 = 43.04..., humidity 210 - 43.04 + 1;
		// cell 1 has 90 ahead, above 85, so it rains all of 167.95...; cell 2 has no wind left
		#expect(try prec([30, 60, 90], cellsX: 1, cellsY: 3, winds: fromNorth) == [43, 167, 0])
	}

	@Test func aSoutherlyWindRainsUpTheColumns() throws {
		#expect(try prec([90, 60, 30], cellsX: 1, cellsY: 3, winds: fromSouth) == [0, 167, 43])
	}

	@Test func anEasterlyWindEntersEachRowAtItsLastCell() throws {
		// 2 x 2 land at 30: row 0 enters at cell 1 (not 0, so it is not skipped): 225 humidity, rain 22.5 stores as 22, then
		// 225 - 22.5 + 1 = 203.5 and cell 0 (nothing ahead, cell -1) rains 203. Row 1 enters at cell 3, rains 22, and its last cell 2
		// looks ahead to cell 1, the other row's last cell, which the original reads too (a row's wind runs on into its neighbour's
		// cells): normal loss 203.5 / 10 = 20.35 stores as 20
		#expect(try prec([30, 30, 30, 30], cellsX: 2, cellsY: 2, winds: east) == [203, 22, 20, 22])
	}

	@Test func theVerticalWindsTakeTheLatitudeModifierFromTheBandOrTheMeanOverSixtyDegrees() throws {
		// a span of 60 or less uses the band of the northern edge (90: modifier 0.5, so max 30 and the rain is 1, then 4)
		#expect(try prec([25, 25], cellsX: 1, cellsY: 2, winds: fromNorth, latN: 90, latT: 60) == [1, 4])
		// a span above 60 uses the mean of the table, 33.5 / 18 = 1.861: max 111.67, humidity 81.67, rain 8.17 stores as 8, then 74.5
		#expect(try prec([30, 30], cellsX: 1, cellsY: 2, winds: fromNorth, latN: 90, latT: 180) == [8, 74])
	}

	@Test func theSouthernWindAlsoSwitchesToTheMeanJustOverSixtyDegrees() throws {
		// a southerly wind over a span of 61: the mean (max 111.67, humidity 81.67, rain 8.17 stores as 8, then 74.5 stores as 74)
		// and not the band of the southern edge (29 degrees, modifier 1: max 60, humidity 30, rain 3, then 28)
		#expect(try prec([30, 30], cellsX: 1, cellsY: 2, winds: fromSouth, latN: 90, latT: 61) == [74, 8])
		#expect(try prec([30, 30], cellsX: 1, cellsY: 2, winds: fromSouth, latN: 90, latT: 60) == [28, 3])
	}

	@Test func aWindThatStartsExactlyDryDoesNotBlow() throws {
		// a northerly wind of exactly 15 (60 x 0.5 band x modifier 0.5) over a sea cell of height 15 has humidity exactly 0 and is skipped,
		// so the coast ahead gets no rain; with any more humidity it would
		#expect(try prec([15, 30], cellsX: 1, cellsY: 2, winds: fromNorth, latN: 90, latT: 0, rain: 50) == [0, 0])
		#expect(try prec([14, 30], cellsX: 1, cellsY: 2, winds: fromNorth, latN: 90, latT: 0, rain: 50)[1] > 0)
	}

	@Test func theRainLevelAndTheCellCountScaleTheModifier() throws {
		// no rain level, no rain
		#expect(try prec([30, 30, 30, 30, 30, 30], cellsX: 3, cellsY: 2, winds: west, rain: 0) == [0, 0, 0, 0, 0, 0])
		// the cell count scales the modifier by its quarter power: 160,000 cells give 2, so the max 120 x 2 x 4 = 960 is capped at 255
		// all the same and the normal loss 225 / (10 x 2) = 11.25 stores as 11
		#expect(try prec([30, 30, 30, 30], cellsX: 2, cellsY: 2, winds: west, cellsDesired: 160000)[2] == 11)
	}

	// MARK: winds, validation

	@Test func windsFollowTheLatitudeTiersAndTheBandModifiers() throws {
		// 3 rows at latitudes 90, 30 and -30: tiers 0, 1 and 3 with the default angles 225, 45 and 315; bands 17, 5 and 5.
		// 225 is easterly and northerly; 45 is westerly and also southerly (under 80); 315 is easterly and southerly (over 280)
		let (w, latS) = try Precipitation.checkedWinds(cells: 6, cellsX: 2, cellsY: 3, latN: 90, latT: 180, settings: PrecipitationSettings())
		#expect(w.westerly == [Precipitation.Band(firstCell: 2, latitudeModifier: 1, tier: 1)])
		#expect(w.easterly == [Precipitation.Band(firstCell: 1, latitudeModifier: 0.5, tier: 0), Precipitation.Band(firstCell: 5, latitudeModifier: 1, tier: 3)])
		#expect(w.northerly == 1 && w.southerly == 2 && latS == -90)
	}

	@Test func theAngleLimitsAreExclusive() throws {
		func found(_ angle: Double) throws -> (Bool, Bool, Int, Int) {
			var s = PrecipitationSettings()
			s.winds = [Double](repeating: angle, count: 6)
			let w = try Precipitation.checkedWinds(cells: 2, cellsX: 1, cellsY: 2, latN: 0, latT: 0, settings: s).winds
			return (!w.westerly.isEmpty, !w.easterly.isEmpty, w.northerly, w.southerly)
		}
		// 40 and 140 are not westerly, 41 and 139 are; 220 and 320 are not easterly; 100 and 260 are not northerly; 280 and 80 are not southerly
		#expect(try [40, 41, 139, 140].map { try found($0).0 } == [false, true, true, false])
		#expect(try [220, 221, 319, 320].map { try found($0).1 } == [false, true, true, false])
		#expect(try [100, 101, 259, 260].map { try found($0).2 } == [0, 2, 2, 0])
		#expect(try [279, 280, 281, 79, 80, 359, 0].map { try found($0).3 } == [0, 0, 2, 2, 0, 2, 2])
	}

	@Test func settingsAndInputsAreValidated() throws {
		let h = [Height](repeating: 30, count: 4)
		for rain in [-1.0, .nan, .infinity, 1001] { #expect(throws: Precipitation.Problem.invalidSettings) { try prec(h, cellsX: 2, cellsY: 2, winds: west, rain: rain) } }
		for winds in [[Double](repeating: 90, count: 5), [Double](repeating: 360, count: 6), [Double](repeating: -1, count: 6), [90, 90, 90, 90, 90, .nan]] { #expect(throws: Precipitation.Problem.invalidSettings) { try prec(h, cellsX: 2, cellsY: 2, winds: winds) } }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 2, cellsY: 3, winds: west) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 0, cellsY: 2, winds: west) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, temp: [20, 20, 20], cellsX: 2, cellsY: 2, winds: west) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 2, cellsY: 2, winds: west, cellsDesired: 0) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 2, cellsY: 2, winds: west, latN: 91) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 2, cellsY: 2, winds: west, latN: -80, latT: 20) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 2, cellsY: 2, winds: west, latN: 0, latT: 181) }
		#expect(throws: Precipitation.Problem.invalidInputs) { try prec(h, cellsX: 2, cellsY: 2, winds: west, latN: .nan) }
	}
}
