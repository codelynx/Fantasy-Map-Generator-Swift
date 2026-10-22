import FantasyMapCore

/// Everything that makes and shows a map, as one value an app owns and the controls edit (docs/plans/map-controls.md). The defaults make a finished map:
/// rivers on, realms on with `RealmDefaults`, the demo's coast, 10,000 cells. `validate()` refuses what the package could not use, with the name of the setting.
public struct MapSettings: Equatable, Hashable, Sendable {
	public static let maximumSeedLength = 200
	public static let cellRange = 1_000...100_000

	/// The seed of the land. The same seed, shape and cells always make the same map.
	public var seed = "12345"
	/// The land shape, by the key of one of the package's templates.
	public var landShape = "continents"
	public var cells = MapSettings.cellRange.upperBound / 10
	public var coast = Coast()
	public var rivers = Rivers()
	public var realms = Realms()
	public var pin = Pin()

	public init() {}

	/// The settings a map was made with, read back from the map: its seed, land shape and cells, and, if it has realms, the realm recipe (the reach, the number asked for, the
	/// realm seed, the typical size, the growth factors, how uneven). Everything that is not part of a map (the coast, the rivers' look, whether realms are drawn, the next pin)
	/// is the default. **For a map made from settings that validate, these settings equal them in everything a map keeps**; a map made another way (an older file with
	/// fewer than 1,000 cells, say) is described as it is, and `validate()` says whether the package would make it again.
	public init(describing map: LandMap) {
		self.init()
		seed = map.seed
		landShape = map.recipe.template ?? landShape
		cells = map.cellsDesired
		if let recipe = map.realms?.recipe {
			realms.reach = recipe.reach
			realms.count = recipe.chosenCount
			realms.seed = recipe.realmSeed == map.seed ? nil : recipe.realmSeed
			realms.typicalArea = recipe.typicalRealmArea
			realms.hillFactor = recipe.hillFactor
			realms.mountainFactor = recipe.mountainFactor
			realms.crossingFactor = recipe.crossingFactor
			realms.unevenness = recipe.unevenness
		}
	}

	/// A random seed, a number of up to nine digits as the original makes them: what "another seed" asks for.
	public static func randomSeed() -> String { String(Int.random(in: 100_000...999_999_999)) }

	public struct Coast: Equatable, Hashable, Sendable {
		/// Rounds of corner cutting, 0 to `CoastOutlines.maximumSmoothing`.
		public var smoothing = 2
		public var inkWidth = 1.5
		public var rough = false
		public var amplitude = 0.75
		public var variant = 0
		public init() {}
	}

	public struct Rivers: Equatable, Hashable, Sendable {
		public var shown = true
		/// How wide rivers are drawn, as a multiple of the standard width.
		public var widthScale = 1.0
		public init() {}
	}

	public struct Realms: Equatable, Hashable, Sendable {
		/// Whether the realms are drawn (they are made either way).
		public var drawn = true
		/// The longest sea crossing that joins islands into one group (map units).
		public var reach = RealmDefaults.reach
		/// Nil lets the package work the count out from the land and `typicalArea`.
		public var count: Int?
		/// Whether the number of realms is worked out from the land (`count` is nil). Setting it to false asks for a number: the last one asked for, or 8.
		public var automaticCount: Bool {
			get { count == nil }
			set { count = newValue ? nil : (count ?? 8) }
		}
		/// Nil uses the map's own seed, so that a seed alone remembers the realms.
		public var seed: String?
		public var typicalArea = RealmDefaults.typicalRealmArea
		public var hillFactor = RealmDefaults.hillFactor
		public var mountainFactor = RealmDefaults.mountainFactor
		public var crossingFactor = RealmDefaults.crossingFactor
		public var unevenness = RealmDefaults.unevenness
		public init() {}
	}

	/// What the next pin dropped looks like.
	public struct Pin: Equatable, Hashable, Sendable {
		public var marker = "pin"
		public var color = "red"
		public init() {}
	}

	/// What an app has to redo when settings change, so that it does the least work (docs/plans/map-controls.md). A change can need more than one.
	public struct Change: OptionSet, Sendable {
		public let rawValue: Int
		public init(rawValue: Int) { self.rawValue = rawValue }

		/// The land is made again: a new seed, land shape or number of cells. The realms, the water and the **pins** go with the old map.
		public static let newMap = Change(rawValue: 1)
		/// The realms are grown again **on the same land**: the land, the rivers and the pins are kept.
		public static let realms = Change(rawValue: 2)
		/// Only the drawing changes: the coast, the rivers' look, whether the realms are drawn.
		public static let look = Change(rawValue: 4)
	}

	/// What it takes to go from `old` to these settings. Empty when nothing the map is made of or drawn with differs; the pin marker and colour are
	/// the next pin's and change no map. A seed is compared as it is written, so a seed that differs only by spaces counts as another (an app that trims
	/// seeds trims before it compares).
	public func change(from old: MapSettings) -> Change {
		var result: Change = []
		if seed != old.seed || landShape != old.landShape || cells != old.cells { result.insert(.newMap) }
		var newRealms = realms
		newRealms.drawn = old.realms.drawn
		if newRealms != old.realms { result.insert(.realms) }
		if coast != old.coast || rivers != old.rivers || realms.drawn != old.realms.drawn { result.insert(.look) }
		return result
	}

	public enum Problem: Error, Equatable, Sendable {
		/// The named setting is out of its range, not a number, or not a known value.
		case invalid(String)
	}

	/// Throws ``Problem/invalid(_:)`` naming the first setting the package could not use. The defaults pass.
	public func validate() throws {
		func check(_ ok: Bool, _ name: String) throws { if !ok { throw Problem.invalid(name) } }
		func finite(_ value: Double, in range: ClosedRange<Double>) -> Bool { value.isFinite && range.contains(value) }
		func key(_ text: String) -> Bool { !text.isEmpty && text.count <= PinLimits.maximumKeyLength }

		let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
		try check(!trimmed.isEmpty && seed.count <= Self.maximumSeedLength, "seed")
		try check(HeightmapTemplate.named(landShape) != nil, "landShape")
		try check(Self.cellRange.contains(cells), "cells")

		try check((0...CoastOutlines.maximumSmoothing).contains(coast.smoothing), "coast.smoothing")
		try check(finite(coast.inkWidth, in: 0...10), "coast.inkWidth")
		var roughness = RoughnessSettings()
		roughness.baseAmplitude = coast.amplitude
		try check((try? roughness.validate()) != nil, "coast.amplitude")
		roughness.variant = coast.variant
		try check((try? roughness.validate()) != nil, "coast.variant")
		try check(finite(rivers.widthScale, in: 0.05...10), "rivers.widthScale")

		try check(finite(realms.reach, in: 0...10_000), "realms.reach")
		if let count = realms.count { try check((1...RealmDefaults.maximumRealms).contains(count), "realms.count") }
		if let seed = realms.seed { try check(!seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seed.count <= Self.maximumSeedLength, "realms.seed") }
		try check(realms.typicalArea.isFinite && realms.typicalArea > 0 && realms.typicalArea <= 1e9, "realms.typicalArea")
		try check(finite(realms.hillFactor, in: 1...GrowthPolicy.maximumFactor), "realms.hillFactor")
		try check(finite(realms.mountainFactor, in: 1...GrowthPolicy.maximumFactor), "realms.mountainFactor")
		try check(finite(realms.crossingFactor, in: 1...GrowthPolicy.maximumFactor), "realms.crossingFactor")
		try check(finite(realms.unevenness, in: 0...GrowthPolicy.maximumUnevenness), "realms.unevenness")

		try check(key(pin.marker), "pin.marker")
		try check(key(pin.color), "pin.color")
	}
}
