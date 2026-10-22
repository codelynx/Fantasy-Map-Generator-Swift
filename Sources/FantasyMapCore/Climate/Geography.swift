// Ported from Azgaar's Fantasy Map Generator, `src/generators/coordinates.ts` (the original at commit 8936c9c, 2026-10-19), with the
// small random helpers it uses from `src/utils/probabilityUtils.ts` (`P`, `gauss`, which uses d3-random 3.0.1's `randomNormal`) and
// `numberUtils.ts` (`rn`, `minmax`). The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in
// ACKNOWLEDGEMENTS.md; d3-random is ISC licensed, © Mike Bostock (the notice is in ACKNOWLEDGEMENTS.md).
//
// Where the map sits on the globe: its share of the world, a north-south and a west-east shift, and the latitude and longitude box
// that follows. Temperature and rain (the next steps of the water chain) read the latitude box.

import Foundation

/// What the author asks for: each value is used when given and drawn from the template otherwise. Percentages: the map's size as a
/// share of the world, and its north-south and west-east shifts, each 0 to 100.
public struct GeographyRequest: Equatable, Codable, Sendable {
	public var mapSize: Double?
	public var latitude: Double?
	public var longitude: Double?

	public init(mapSize: Double? = nil, latitude: Double? = nil, longitude: Double? = nil) {
		self.mapSize = mapSize
		self.latitude = latitude
		self.longitude = longitude
	}
}

/// The latitude and longitude box of the map, in degrees.
public struct MapCoordinates: Equatable, Codable, Sendable {
	/// The latitude span, `latN` the northern and `latS` the southern edge; `lonT` the longitude span, `lonW` the western and
	/// `lonE` the eastern edge.
	public var latT: Double, latN: Double, latS: Double
	public var lonT: Double, lonW: Double, lonE: Double
}

/// Where the map sits on the globe.
public struct Geography: Equatable, Codable, Sendable {
	public var mapSize: Double
	public var latitude: Double
	public var longitude: Double
	public var coordinates: MapCoordinates

	public enum Problem: Error, Equatable, Sendable {
		/// A requested value is not finite or is outside 0 to 100 (a safety check; the original takes the values as given).
		case invalidRequest
		/// The map's width or height is not finite and above 0.
		case invalidSize
		/// The aspect ratio width / height is not finite (an overflow), so the longitude span cannot be calculated.
		case unsupportedAspectRatio
	}

	private static let templatePositions: [String: (Double, Double, Double)] = [
		"africa-centric": (45, 53, 38), "arabia": (20, 35, 35), "atlantics": (42, 23, 65), "britain": (7, 20, 51.3),
		"caribbean": (15, 40, 74.8), "east-asia": (11, 28, 9.4), "eurasia": (38, 19, 27), "europe": (20, 16, 44.8),
		"europe-accented": (14, 22, 44.8), "europe-and-central-asia": (25, 10, 39.5), "europe-central": (11, 22, 46.4),
		"europe-north": (7, 18, 48.9), "greenland": (22, 7, 55.8), "hellenica": (8, 27, 43.5), "iceland": (2, 15, 55.3),
		"indian-ocean": (45, 55, 14), "mediterranean-sea": (10, 29, 45.8), "middle-east": (8, 31, 34.4), "north-america": (37, 17, 87),
		"us-centric": (66, 27, 100), "us-mainland": (16, 30, 77.5), "world": (78, 27, 40), "world-from-pacific": (75, 32, 30)
	]

	/// The chance for a random template to cover the whole world, if the land does not go over the map borders.
	private static let wholeWorldChance: [String: Double] = ["pangea": 1, "shattered": 0.7, "continents": 0.5, "archipelago": 0.35, "highIsland": 0.25, "lowIsland": 0.1]

	/// The size distribution (expected, deviation, min, max) for a random template.
	private static let randomSize: [String: (Double, Double, Double, Double)] = [
		"pangea": (70, 20, 30, 100), "volcano": (20, 20, 10, 100), "mediterranean": (25, 30, 15, 80), "peninsula": (15, 15, 5, 80),
		"isthmus": (15, 20, 3, 80), "atoll": (3, 2, 1, 5)
	]

	/// The geography of a map. **The random stream is a fresh `Alea(seed)`**, which is what the original's stream is at this point of its
	/// pipeline: `Features.markupGrid` resets it to the seed and the lake steps after it draw nothing (the fixtures check this by
	/// comparing the stream's state before the call). So this does not depend on what the height generator left behind, and works the
	/// same from a loaded map. The template is the map's recipe template (an empty string if it has none: **a missing template is the
	/// generic size distribution, not a recovery of the map's original template**; the resolved geography should be kept with the
	/// climate state so that a later load need not infer it from the recipe).
	public static func generate(for map: LandMap, request: GeographyRequest = GeographyRequest()) throws -> Geography {
		var random = Alea(seed: map.seed)
		let isPartial = map.features.features.contains { $0.land && $0.border }
		return try generate(template: map.recipe.template ?? "", isPartial: isPartial, width: map.width, height: map.height, request: request, random: &random)
	}

	/// The same over explicit values, with the caller's stream. The original draws for the template's size and position **even when
	/// the request gives every value**, and so does this: the stream moves the same way. **A refused call draws nothing:** everything
	/// that can be refused is checked before any draw, and the stream is advanced on a local copy that is committed only on success.
	public static func generate(template: String, isPartial: Bool, width: Double, height: Double, request: GeographyRequest, random: inout Alea) throws -> Geography {
		try validate(width: width, height: height)
		for value in [request.mapSize, request.latitude, request.longitude] { try validate(percentage: value) }
		var local = random
		let (size, latitude, longitude) = sizeAndPosition(template: template, isPartial: isPartial, random: &local)
		let mapSize = request.mapSize ?? size, latitudeShift = request.latitude ?? latitude, longitudeShift = request.longitude ?? longitude
		let coordinates = box(mapSize: mapSize, latitude: latitudeShift, longitude: longitudeShift, width: width, height: height)
		guard [coordinates.latT, coordinates.latN, coordinates.latS, coordinates.lonT, coordinates.lonW, coordinates.lonE].allSatisfy({ $0.isFinite }) else { throw Problem.unsupportedAspectRatio }
		random = local
		return Geography(mapSize: mapSize, latitude: latitudeShift, longitude: longitudeShift, coordinates: coordinates)
	}

	/// The latitude and longitude bounds from the size and the shifts (the original's `calculate`), **validated**: the percentages must
	/// be finite and 0 to 100, the size finite and above 0, and the aspect ratio finite; the result is finite.
	public static func calculate(mapSize: Double, latitude: Double, longitude: Double, width: Double, height: Double) throws -> MapCoordinates {
		try validate(width: width, height: height)
		for value in [mapSize, latitude, longitude] { try validate(percentage: value) }
		let coordinates = box(mapSize: mapSize, latitude: latitude, longitude: longitude, width: width, height: height)
		guard [coordinates.latT, coordinates.latN, coordinates.latS, coordinates.lonT, coordinates.lonW, coordinates.lonE].allSatisfy({ $0.isFinite }) else { throw Problem.unsupportedAspectRatio }
		return coordinates
	}

	private static func validate(width: Double, height: Double) throws {
		guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw Problem.invalidSize }
		guard (width / height).isFinite else { throw Problem.unsupportedAspectRatio } // an overflow would turn infinity x 0 into NaN
	}

	private static func validate(percentage: Double?) throws {
		if let v = percentage, !(v.isFinite && v >= 0 && v <= 100) { throw Problem.invalidRequest }
	}

	/// The original's `calculate`, unchecked, with its arithmetic in its order.
	private static func box(mapSize: Double, latitude: Double, longitude: Double, width: Double, height: Double) -> MapCoordinates {
		let sizeFraction = mapSize / 100, latShift = latitude / 100, lonShift = longitude / 100
		let latT = JSNumber.rn(sizeFraction * 180, 1)
		let latN = JSNumber.rn(90 - (180 - latT) * latShift, 1)
		let latS = JSNumber.rn(latN - latT, 1)
		let lonT = JSNumber.rn(min(width / height * latT, 360), 1)
		let lonE = JSNumber.rn(180 - (360 - lonT) * lonShift, 1)
		let lonW = JSNumber.rn(lonE - lonT, 1)
		return MapCoordinates(latT: latT, latN: latN, latS: latS, lonT: lonT, lonW: lonW, lonE: lonE)
	}

	/// For the tests: the template's draws alone.
	static func sizeAndPositionForTests(template: String, isPartial: Bool, random: inout Alea) -> (Double, Double, Double) {
		sizeAndPosition(template: template, isPartial: isPartial, random: &random)
	}

	private static func sizeAndPosition(template: String, isPartial: Bool, random: inout Alea) -> (Double, Double, Double) {
		if let real = templatePositions[template] { return real }
		if !isPartial && JSRandom.p(wholeWorldChance[template] ?? 0, &random) { return (100, 50, 50) }
		let maxSize: Double = isPartial ? 80 : 100
		// Continents, Archipelago, High Island and Low Island fall back to the default distribution
		let (expected, deviation, lower, upper) = randomSize[template] ?? (30, 20, 15, maxSize)
		let round = template == "atoll" ? 1 : 0
		let size = JSRandom.gauss(expected, deviation, lower, min(upper, maxSize), round, &random)
		let shiftBase: Double = JSRandom.p(0.5, &random) ? 40 : 60
		let latitude = JSRandom.gauss(shiftBase, 20, 25, 75, 0, &random) // latitude shift
		return (size, latitude, 50)
	}
}

/// The original's random helpers, over a seeded `Alea` stream.
enum JSRandom {
	/// `P(probability)`: true with the probability. At 1 or more it is true and at 0 or less false **without drawing**.
	static func p(_ probability: Double, _ random: inout Alea) -> Bool {
		if probability >= 1 { return true }
		if probability <= 0 { return false }
		return random.next() < probability
	}

	/// `gauss(expected, deviation, min, max, round)`: d3-random 3.0.1's `randomNormal` (Marsaglia's polar method; a fresh generator for
	/// each call, so the second value of a pair is never kept), clamped to min and max and rounded to `round` decimals with
	/// JavaScript's rounding.
	static func gauss(_ expected: Double, _ deviation: Double, _ lower: Double, _ upper: Double, _ round: Int, _ random: inout Alea) -> Double {
		var x = 0.0, y = 0.0, r = 0.0
		repeat {
			x = random.next() * 2 - 1
			y = random.next() * 2 - 1
			r = x * x + y * y
		} while r == 0 || r > 1
		let value = expected + deviation * y * (-2 * log(r) / r).squareRoot()
		return JSNumber.rn(min(max(value, lower), upper), round)
	}
}
