// Ported from Azgaar's Fantasy Map Generator, `src/generators/precipitation-generator.ts` (the original at commit 8936c9c, 2026-10-19).
// The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// The simplest precipitation model: winds enter the map from its sides, carry humidity over water and drop it as rain over land, more on
// rising ground, until they run dry or meet a mountain too high to pass.

import Foundation

/// The climate values the original keeps in `options.map.climate`: the rain level (a percentage; 100 is the original's default) and the
/// six prevailing wind angles, one for each 30° latitude tier from north to south. A plain value with the original's defaults.
public struct PrecipitationSettings: Equatable, Sendable {
	/// The rain level in percent. Finite, 0 to 1000 (package policy: the original only requires a number that is not negative).
	public var precipitation = 100.0
	/// Six wind angles in degrees, each finite and from 0 up to (not including) 360. The original takes whole degrees; the package accepts
	/// fractions, which the comparisons below treat the same way.
	public var winds: [Double] = [225, 45, 225, 315, 135, 315]

	public init() {}

	func validate() throws {
		guard precipitation.isFinite, precipitation >= 0, precipitation <= 1000, winds.count == 6, winds.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 360 }) else { throw Precipitation.Problem.invalidSettings }
	}
}

public enum Precipitation {
	public enum Problem: Error, Equatable, Sendable {
		/// A setting is not finite, is out of its range or the wind list is not six angles (a safety check; the original takes the values as given).
		case invalidSettings
		/// The inputs are inconsistent (the arrays' lengths, the grid's shape, the latitude span, the cell count).
		case invalidInputs
	}

	/// A row or column the wind enters through: the first cell and the latitude modifier of its band (the original's `[firstCellId,
	/// latitudeModifier, windTier]` with the tier kept too).
	public struct Band: Equatable, Sendable {
		public var firstCell: Int
		public var latitudeModifier: Double
		public var tier: Int
	}

	/// The winds the original's `getWinds` finds: the rows the westerly and easterly winds enter through, and how many rows send a wind
	/// from the north and from the south.
	public struct Winds: Equatable, Sendable {
		public var westerly: [Band] = []
		public var easterly: [Band] = []
		public var northerly = 0
		public var southerly = 0
	}

	/// The precipitation modifier per 5° latitude band.
	static let latitudeModifier: [Double] = [4, 2, 2, 2, 1, 1, 2, 2, 2, 2, 3, 3, 2, 2, 1, 1, 1, 0.5]
	static let maxPassableElevation = 85

	/// The precipitation of every grid cell, as the original's `Uint8Array` (so a sum above 255 wraps, as it does there). **The random
	/// stream is a fresh `Alea(seed)`** (the original replaces its stream with that at the start, "the same winds for the same map,
	/// whoever rolled before"). The temperature is the grid's, from `Temperature.compute`; the latitudes come from `geography`.
	public static func compute(for map: LandMap, geography: Geography, temperature: [Int8], settings: PrecipitationSettings = PrecipitationSettings()) throws -> [UInt8] {
		var random = Alea(seed: map.seed)
		return try compute(heights: map.heights, temperature: temperature, cellsX: map.grid.cellsX, cellsY: map.grid.cellsY, cellsDesired: map.cellsDesired, latN: geography.coordinates.latN, latT: geography.coordinates.latT, settings: settings, random: &random)
	}

	/// The same over explicit values, with the caller's stream. **The consumed latitude interval is validated** as the temperature's is
	/// (`latN` and the southern bound `latN - latT`, rounded to one decimal, within -90 to 90); the stored `latS` is not read.
	static func compute(heights: [Height], temperature: [Int8], cellsX: Int, cellsY: Int, cellsDesired: Int, latN: Double, latT: Double, settings: PrecipitationSettings, random: inout Alea) throws -> [UInt8] {
		try settings.validate()
		let (winds, latS) = try checkedWinds(cells: heights.count, cellsX: cellsX, cellsY: cellsY, latN: latN, latT: latT, settings: settings)
		guard temperature.count == heights.count, cellsDesired > 0 else { throw Problem.invalidInputs }
		let n = heights.count
		var prec = [UInt8](repeating: 0, count: n)

		let cellsNumberModifier = pow(Double(cellsDesired) / 10000, 0.25)
		let modifier = cellsNumberModifier * (settings.precipitation / 100)
		guard modifier.isFinite else { throw Problem.invalidInputs }

		/// A height as the original reads it: outside the array it is `undefined`, which compares false with everything.
		func height(_ i: Int) -> Int? { i >= 0 && i < n ? Int(heights[i]) : nil }
		func add(_ i: Int, _ amount: Double) { prec[i] = JSNumber.toUInt8(Double(prec[i]) + amount) }

		func getPrecipitation(_ humidity: Double, _ i: Int, _ next: Int) -> Double {
			let normalLoss = max(humidity / (10 * modifier), 1) // precipitation in normal conditions
			let ahead = Double(height(i + next) ?? 0)
			let diff = max(ahead - Double(heights[i]), 0) // difference in height
			let mod = pow(ahead / 70, 2) // 50 stands for hills, 70 for mountains
			return min(max(normalLoss + diff * mod, 1), humidity)
		}

		/// `sources` are first cells, each with the band's latitude modifier for the westerly and easterly winds and none for the vertical ones.
		func passWind(_ sources: [(first: Int, latitudeModifier: Double?)], _ initialMaxPrec: Double, _ next: Int, _ steps: Int) {
			var maxPrec = initialMaxPrec
			for source in sources {
				if let latitudeModifier = source.latitudeModifier {
					if source.first == 0 { continue } // legacy quirk: a band starting at cell 0 is skipped, fixing it changes every map
					maxPrec = min(initialMaxPrec * latitudeModifier, 255)
				}
				let first = source.first
				var humidity = maxPrec - Double(heights[first]) // initial water amount
				if humidity <= 0 { continue } // if first cell in row is too elevated consider wind dry

				for s in 0..<steps {
					let current = first + s * next
					if temperature[current] < -5 { continue } // no flux in permafrost

					if heights[current] < Heights.seaLevel {
						if let ahead = height(current + next), ahead >= Int(Heights.seaLevel) {
							add(current + next, max(humidity / (floor(random.next() * 11) + 10), 1)) // coastal precipitation: rand(10, 20)
						} else {
							humidity = min(humidity + 5 * modifier, maxPrec) // wind gets more humidity passing water cell
							add(current, 5 * modifier) // water cells precipitation (need to correctly pour water through lakes)
						}
						continue
					}

					// land cell
					let isPassable = (height(current + next) ?? Int.max) <= maxPassableElevation
					let precipitation = isPassable ? getPrecipitation(humidity, current, next) : humidity
					add(current, precipitation)
					let evaporation = precipitation > 1.5 ? 1.0 : 0.0 // some humidity evaporates back to the atmosphere
					humidity = isPassable ? min(max(humidity - precipitation + evaporation, 0), maxPrec) : 0
				}
			}
		}

		if !winds.westerly.isEmpty { passWind(winds.westerly.map { ($0.firstCell, $0.latitudeModifier) }, 120 * modifier, 1, cellsX) }
		if !winds.easterly.isEmpty { passWind(winds.easterly.map { ($0.firstCell, $0.latitudeModifier) }, 120 * modifier, -1, cellsX) }

		let vertical = Double(winds.southerly + winds.northerly)
		let mean = latitudeModifier.reduce(0, +) / Double(latitudeModifier.count)
		if winds.northerly > 0 {
			let modifierN = latT > 60 ? mean : latitudeModifier[try band(latN)]
			let maxPrecN = (Double(winds.northerly) / vertical) * 60 * modifier * modifierN
			passWind((0..<cellsX).map { ($0, nil) }, maxPrecN, cellsX, cellsY)
		}
		if winds.southerly > 0 {
			let modifierS = latT > 60 ? mean : latitudeModifier[try band(latS)]
			let maxPrecS = (Double(winds.southerly) / vertical) * 60 * modifier * modifierS
			passWind((n - cellsX..<n).map { ($0, nil) }, maxPrecS, -cellsX, cellsY)
		}
		return prec
	}

	/// The rows and columns the prevailing winds enter the map through, from the map position and the wind angles; free of randomness.
	/// The latitude interval is validated as in `compute`.
	public static func winds(for map: LandMap, geography: Geography, settings: PrecipitationSettings = PrecipitationSettings()) throws -> Winds {
		try settings.validate()
		return try checkedWinds(cells: map.heights.count, cellsX: map.grid.cellsX, cellsY: map.grid.cellsY, latN: geography.coordinates.latN, latT: geography.coordinates.latT, settings: settings).winds
	}

	static func checkedWinds(cells n: Int, cellsX: Int, cellsY: Int, latN: Double, latT: Double, settings: PrecipitationSettings) throws -> (winds: Winds, latS: Double) {
		guard cellsX > 0, cellsY > 0, n == cellsX * cellsY, latN.isFinite, latT.isFinite, latT >= 0, latT <= 180 else { throw Problem.invalidInputs }
		let latS = JSNumber.rn(latN - latT, 1)
		guard latN >= -90, latN <= 90, latS >= -90, latS <= 90 else { throw Problem.invalidInputs }
		var winds = Winds()
		for rowId in 0..<cellsY {
			let cellId = rowId * cellsX
			let lat = latN - (Double(rowId) / Double(cellsY)) * latT
			let latMod = latitudeModifier[try band(lat)]
			let tier = Int(abs(lat - 89) / 30) // 30° tiers from 0 to 5, north to south
			guard tier >= 0, tier < settings.winds.count else { throw Problem.invalidInputs }
			let angle = settings.winds[tier]
			if angle > 40 && angle < 140 { winds.westerly.append(Band(firstCell: cellId, latitudeModifier: latMod, tier: tier)) }
			if angle > 220 && angle < 320 { winds.easterly.append(Band(firstCell: cellId + cellsX - 1, latitudeModifier: latMod, tier: tier)) }
			if angle > 100 && angle < 260 { winds.northerly += 1 }
			if angle > 280 || angle < 80 { winds.southerly += 1 }
		}
		return (winds, latS)
	}

	/// `((|latitude| - 1) / 5) | 0`: the index of the 5° band, truncated toward zero.
	private static func band(_ latitude: Double) throws -> Int {
		let index = Int(((abs(latitude) - 1) / 5).rounded(.towardZero))
		guard index >= 0, index < latitudeModifier.count else { throw Problem.invalidInputs }
		return index
	}
}
