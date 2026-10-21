// Ported from Azgaar's Fantasy Map Generator, `src/generators/temperature-generator.ts` (the original at commit 8936c9c, 2026-10-19).
// The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// The temperature of every grid cell from its latitude and its altitude: a gradient from the equator through the tropics to each pole,
// less 6.5 °C per kilometre of altitude.

import Foundation

/// The temperatures the original keeps in `options.map.climate.temperature` (degrees Celsius, at sea level), and the height exponent of
/// `options.map.units.height`. A plain value with the original's defaults.
public struct TemperatureSettings: Equatable, Sendable {
	/// At the equator, the northern pole and the southern pole. Each finite, -100 to 100 °C.
	public var equator = 27.0
	public var northPole = -30.0
	public var southPole = -15.0
	/// The exponent that turns a height above 18 into metres, `metres = (height - 18) ^ exponent`. Finite, 0.1 to 5; the original's is 2.
	/// (These ranges are this package's policy. The original's controls are narrower, temperatures -50 to 50 and the exponent 1.5 to
	/// 2.2, and its schema broader; the package's ranges include the controls and allow more fantasy settings. They are not upstream
	/// limits and not needed for arithmetic safety. Later the height exponent should be one authoritative setting shared with the
	/// lake evaporation, so the two cannot disagree.)
	public var heightExponent = 2.0

	public init() {}

	func validate() throws {
		for t in [equator, northPole, southPole] { guard t.isFinite, t >= -100, t <= 100 else { throw Temperature.Problem.invalidSettings } }
		guard heightExponent.isFinite, heightExponent >= 0.1, heightExponent <= 5 else { throw Temperature.Problem.invalidSettings }
	}
}

public enum Temperature {
	public enum Problem: Error, Equatable, Sendable {
		/// A setting is not finite or is out of its range (a safety check; the original takes the values as given).
		case invalidSettings
		/// The inputs are inconsistent (the number of cells, the row width, the latitude span).
		case invalidInputs
	}

	/// The temperature, in whole degrees, of every grid cell of a map, as the original's `Int8Array`. The latitude of each row comes
	/// from `geography.coordinates` (`latN` and `latT`) and the **first cell's `y` of the row** (the cells' points are jittered, so
	/// the rows are not exactly level, and the original reads the first one only). **The consumed interval is validated:** `latN` and
	/// the southern bound `latN - latT` (rounded to one decimal as `Geography` rounds it) must lie within -90 to 90, so a malformed or
	/// inconsistent geography cannot extrapolate beyond the poles. The stored `latS` is not trusted or read. A zero span is fine.
	public static func compute(for map: LandMap, geography: Geography, settings: TemperatureSettings = TemperatureSettings()) throws -> [Int8] {
		try compute(heights: map.heights, points: map.grid.points, cellsX: map.grid.cellsX, mapHeight: map.height, latN: geography.coordinates.latN, latT: geography.coordinates.latT, settings: settings)
	}

	/// The same over explicit values.
	static func compute(heights: [Height], points: [Point], cellsX: Int, mapHeight: Double, latN: Double, latT: Double, settings: TemperatureSettings) throws -> [Int8] {
		try settings.validate()
		let n = heights.count
		guard points.count == n, cellsX > 0, n % cellsX == 0, mapHeight.isFinite, mapHeight > 0, latN.isFinite, latT.isFinite, latT >= 0, latT <= 180 else { throw Problem.invalidInputs }
		// the interval actually used: from latN down to latN - latT, both within the poles
		let latS = JSNumber.rn(latN - latT, 1)
		guard latN >= -90, latN <= 90, latS >= -90, latS <= 90 else { throw Problem.invalidInputs }
		var temp = [Int8](repeating: 0, count: n)

		let tropics = [16.0, -20.0] // tropics zone
		let tropicalGradient = 0.15
		let tempNorthTropic = settings.equator - tropics[0] * tropicalGradient
		let northernGradient = (tempNorthTropic - settings.northPole) / (90 - tropics[0])
		let tempSouthTropic = settings.equator + tropics[1] * tropicalGradient
		let southernGradient = (tempSouthTropic - settings.southPole) / (90 + tropics[1])

		func seaLevelTemperature(_ latitude: Double) -> Double {
			let isTropical = latitude <= 16 && latitude >= -20
			if isTropical { return settings.equator - abs(latitude) * tropicalGradient }
			return latitude > 0
				? tempNorthTropic - (latitude - tropics[0]) * northernGradient
				: tempSouthTropic + (latitude - tropics[1]) * southernGradient
		}

		// temperature drops by 6.5 °C per 1 km of altitude
		func altitudeDrop(_ height: Height) -> Double {
			if !Heights.isLand(height) { return 0 }
			return JSNumber.rn((pow(Double(height) - 18, settings.heightExponent) / 1000) * 6.5)
		}

		for rowCell in stride(from: 0, to: n, by: cellsX) {
			let y = points[rowCell].y
			let rowLatitude = latN - (y / mapHeight) * latT // [90; -90]
			let seaLevelTemp = seaLevelTemperature(rowLatitude)
			for cell in rowCell..<(rowCell + cellsX) {
				temp[cell] = JSNumber.toInt8(min(max(seaLevelTemp - altitudeDrop(heights[cell]), -128), 127))
			}
		}
		return temp
	}
}
