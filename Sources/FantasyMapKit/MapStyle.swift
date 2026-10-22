import FantasyMapCore
import Foundation

/// A colour as red, green, blue and alpha, each 0 to 1, in the sRGB colour space. Plain numbers, so the style and the drawing
/// geometry need no UI framework.
public struct MapColor: Equatable, Hashable, Codable, Sendable {
	public var red: Double
	public var green: Double
	public var blue: Double
	public var alpha: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}
}

/// A colour scale: colour stops from 0 to 1, blended in straight lines between neighbours in red, green, blue and alpha. A
/// position outside 0 ... 1 takes the nearest end.
public struct ColorScale: Equatable, Codable, Sendable {
	public struct Stop: Equatable, Codable, Sendable {
		public var position: Double
		public var color: MapColor

		public init(_ position: Double, _ color: MapColor) {
			self.position = position
			self.color = color
		}
	}

	/// The stops, in increasing position.
	public var stops: [Stop]

	public init(stops: [Stop]) {
		self.stops = stops
	}

	/// The colour at `t`.
	public func color(at t: Double) -> MapColor {
		guard let first = stops.first, let last = stops.last else { return MapColor(red: 0, green: 0, blue: 0) }
		if !(t > first.position) { return first.color } // also NaN
		if t >= last.position { return last.color }
		for (a, b) in zip(stops, stops.dropFirst()) where t <= b.position {
			let span = b.position - a.position
			let f = span > 0 ? (t - a.position) / span : 1
			return MapColor(
				red: a.color.red + (b.color.red - a.color.red) * f,
				green: a.color.green + (b.color.green - a.color.green) * f,
				blue: a.color.blue + (b.color.blue - a.color.blue) * f,
				alpha: a.color.alpha + (b.color.alpha - a.color.alpha) * f
			)
		}
		return last.color
	}
}

/// How a map is coloured. A plain value with defaults; changing a style never changes the map.
///
/// The water colours are **a display policy, not depth**: the coast distance the map holds is a graph distance from the coast
/// (-1 next to land down to -9), and 0 can mean water far out or any water on a map with no land. See `MapDrawing`.
public struct MapStyle: Equatable, Codable, Sendable {
	/// Water from near the coast (position 0) to far from it (position 1).
	public var water: ColorScale
	/// Land from lowland (position 0, height 20) to the highest ground (position 1, height 100).
	public var land: ColorScale
	/// The colour behind the map, and around it when an image is wider or taller than the map.
	public var paper: MapColor
	/// The coastline ink (stage 2).
	public var ink: MapColor
	/// The ink's width **in map units**, so the picture keeps its proportions at any export size; 0 turns the coastline off.
	public var inkWidth: Double
	/// How many rounds of corner cutting smooth the coast (0 to `CoastOutlines.maximumSmoothing`); 0 keeps the cells' own edges.
	public var smoothing: Int
	/// Optional roughening of the coast (stage 2c): nil, the default, is off. Applied after smoothing; if a check fails the drawing
	/// falls back to the smoothed outline (see `CoastOutlines.roughness`).
	public var roughness: RoughnessSettings?
	/// The colour of the rivers (a water map's rivers, drawn as filled shapes), and a scale for their width: 1 is the original's width, 0 turns the
	/// rivers off.
	public var river: MapColor
	public var riverWidthScale: Double
	/// The realms (a map with realms): the wash opacity (0 turns the wash off), the colours the realms take (the original's six, d3's Set2; none turns the wash
	/// off), and the border lines between realms: thin, grey and dashed by default (width 0 or a transparent colour turns them off; an empty dash is a solid line).
	public var realmWashOpacity: Double
	/// Whether a map's realm layer is drawn (a map with realms draws them by default; a map without realms draws none).
	public var showRealms: Bool
	public var realmColors: [MapColor]
	public var realmBorder: MapColor
	public var realmBorderWidth: Double
	public var realmBorderDash: [Double]

	public init(water: ColorScale, land: ColorScale, paper: MapColor, ink: MapColor = MapColor(red: 0.25, green: 0.18, blue: 0.12), inkWidth: Double = 1.5, smoothing: Int = 2, roughness: RoughnessSettings? = nil, river: MapColor = MapColor(red: 0.20, green: 0.42, blue: 0.62), riverWidthScale: Double = 1,
		realmWashOpacity: Double = 0.3, realmColors: [MapColor] = MapStyle.defaultRealmColors, realmBorder: MapColor = MapColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 0.9), realmBorderWidth: Double = 0.8, realmBorderDash: [Double] = [3, 2], showRealms: Bool = true) {
		self.showRealms = showRealms
		self.realmWashOpacity = realmWashOpacity
		self.realmColors = realmColors
		self.realmBorder = realmBorder
		self.realmBorderWidth = realmBorderWidth
		self.realmBorderDash = realmBorderDash
		self.river = river
		self.riverWidthScale = riverWidthScale
		self.smoothing = smoothing
		self.roughness = roughness
		self.water = water
		self.land = land
		self.paper = paper
		self.ink = ink
		self.inkWidth = inkWidth
	}

	/// The original's six soft realm colours (d3's Set2: #66c2a5, #fc8d62, #8da0cb, #e78ac3, #a6d854, #ffd92f).
	public static let defaultRealmColors: [MapColor] = [
		MapColor(red: 0x66 / 255.0, green: 0xc2 / 255.0, blue: 0xa5 / 255.0), MapColor(red: 0xfc / 255.0, green: 0x8d / 255.0, blue: 0x62 / 255.0),
		MapColor(red: 0x8d / 255.0, green: 0xa0 / 255.0, blue: 0xcb / 255.0), MapColor(red: 0xe7 / 255.0, green: 0x8a / 255.0, blue: 0xc3 / 255.0),
		MapColor(red: 0xa6 / 255.0, green: 0xd8 / 255.0, blue: 0x54 / 255.0), MapColor(red: 0xff / 255.0, green: 0xd9 / 255.0, blue: 0x2f / 255.0)
	]

	/// The package's own default colours: pale to deep blue for water, green to tan to brown to white for land, warm paper.
	public static let standard = MapStyle(
		water: ColorScale(stops: [
			.init(0, MapColor(red: 0.62, green: 0.82, blue: 0.88)),
			.init(1, MapColor(red: 0.20, green: 0.42, blue: 0.62))
		]),
		land: ColorScale(stops: [
			.init(0, MapColor(red: 0.74, green: 0.82, blue: 0.55)),
			.init(0.45, MapColor(red: 0.85, green: 0.78, blue: 0.55)),
			.init(0.8, MapColor(red: 0.60, green: 0.50, blue: 0.40)),
			.init(1, MapColor(red: 0.95, green: 0.95, blue: 0.95))
		]),
		paper: MapColor(red: 0.96, green: 0.93, blue: 0.86)
	)
}
