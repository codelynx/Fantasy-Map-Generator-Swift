import FantasyMapCore

/// Making a whole map in one call: the land, its realms with their colours saved, and its water. `MapSettings` says how; with no settings the realms use
/// `RealmDefaults`, the settings the demo starts from.
public enum RealmDefaults {
	/// The longest sea crossing that joins islands into one group (map units).
	public static let reach = 25.0
	/// The land area a realm typically gets; the automatic count is the land area divided by it.
	public static let typicalRealmArea = 40_000.0
	public static let maximumRealms = 500
	public static let hillFactor = 3.0
	public static let mountainFactor = 8.0
	public static let crossingFactor = 4.0
	public static let unevenness = 3.0
}

extension LandMap {
	/// This map with a realm layer made from `RealmDefaults` and `realmSeed` (the map's own seed when nil, so that a seed alone remembers the realms), with the
	/// automatic count and **the colours resolved in `style` and saved**, so that the map shows the same colours when it is opened again.
	/// Throws what the steps throw (the land could not be grouped, a seed could not be placed, the palette is empty); nothing is half done.
	public func addingRealms(realmSeed: String? = nil, style: MapStyle = .standard) throws -> LandMap {
		var settings = MapSettings.Realms()
		settings.seed = realmSeed
		return try addingRealms(settings: settings, style: style)
	}

	/// This map with a realm layer made from these settings: **the number of realms** (automatic from the land and the typical size, or the number asked for),
	/// the reach, the growth factors, how uneven they are and the realm seed (the map's own seed when nil). The colours are resolved in `style` and saved. Any realm
	/// layer the map had is replaced; the land and the pins are kept. Throws what the steps throw, and nothing is half done.
	public func addingRealms(settings: MapSettings.Realms, style: MapStyle = .standard) throws -> LandMap {
		let realmSeed = settings.seed ?? seed
		let groups = try LandGroups.find(in: self, reach: settings.reach)
		let policy = RealmPolicy(typicalRealmArea: settings.typicalArea, maximumRealms: RealmDefaults.maximumRealms)
		let count: RealmCount = settings.count.map { .chosen($0) } ?? .automatic
		let seeds = try RealmSeeds.place(in: self, groups: groups, count: count, realmSeed: realmSeed, policy: policy)
		let growth = GrowthPolicy(hillFactor: settings.hillFactor, mountainFactor: settings.mountainFactor, crossingFactor: settings.crossingFactor, unevenness: settings.unevenness)
		let ownership = try RealmOwnership.grow(in: self, groups: groups, seeds: seeds, realmSeed: realmSeed, policy: growth)
		let recipe = RealmRecipe(realmSeed: realmSeed, reach: settings.reach, chosenCount: settings.count, resolvedCount: seeds.resolvedCount, typicalRealmArea: settings.typicalArea,
			maximumRealms: RealmDefaults.maximumRealms, sampleSize: policy.sampleSize, hillFactor: settings.hillFactor, mountainFactor: settings.mountainFactor,
			crossingFactor: settings.crossingFactor, unevenness: settings.unevenness)
		let colors = try MapDrawing.resolvedRealmColors(for: self, ownership: ownership, style: style)
		return try adding(RealmLayer(ownership: ownership, recipe: recipe, colors: colors))
	}
}

extension WaterMap {
	/// **A whole map from a seed:** the land from `seed`, `template` and `cellsDesired`, its realms as `LandMap.addingRealms` makes them, and its water (temperature, rain
	/// and rivers). The same inputs always give the same map. Synchronous; run it off the main thread for large maps.
	public static func generate(seed: String, template: HeightmapTemplate, cellsDesired: Int = 10_000, realmSeed: String? = nil, style: MapStyle = .standard) throws -> WaterMap {
		let land = try LandMap.generate(seed: seed, cellsDesired: cellsDesired, template: template).addingRealms(realmSeed: realmSeed, style: style)
		return try WaterMap.generate(land: land)
	}

	/// **A whole map from settings:** the seed, land shape and cells, the realms as the settings say, and the water. Throws ``MapSettings/Problem`` for settings the package
	/// cannot use, and nothing is made. The same settings always give the same map. The coast and the rivers' look are not part of the map (see ``MapSettings/style``);
	/// only the palette the realm colours are resolved in is.
	public static func generate(settings: MapSettings) throws -> WaterMap {
		try settings.validate()
		guard let template = HeightmapTemplate.named(settings.landShape) else { throw MapSettings.Problem.invalid("landShape") }
		let land = try LandMap.generate(seed: settings.seed, cellsDesired: settings.cells, template: template).addingRealms(settings: settings.realms, style: settings.style)
		return try WaterMap.generate(land: land)
	}

	/// **The realms made again on the same land,** as the settings say: the land, the rivers, the climate and the pins are untouched, and only the realm layer (with its
	/// recipe and colours) is replaced. It gives the same map as ``generate(settings:)`` would with these realm settings and the seed, shape and cells this map was made with.
	/// Only `settings.realms` is read, and the palette of `settings.style`; throws ``MapSettings/Problem`` for settings the package cannot use, and nothing changes.
	public func regrowingRealms(settings: MapSettings) throws -> WaterMap {
		try settings.validate()
		return try adding(land.addingRealms(settings: settings.realms, style: settings.style).realms!)
	}
}

extension MapSettings {
	/// The style these settings draw with: the standard style, with the coast (smoothing, ink width, and the rough coast with its amplitude and variant), the rivers'
	/// width and whether the realms are drawn taken from the settings. Whether rivers are shown is not a style: see ``MapDrawing/init(water:settings:)``.
	public var style: MapStyle {
		var style = MapStyle.standard
		style.smoothing = coast.smoothing
		style.inkWidth = coast.inkWidth
		if coast.rough {
			var roughness = RoughnessSettings()
			roughness.baseAmplitude = coast.amplitude
			roughness.variant = coast.variant
			style.roughness = roughness
		}
		style.riverWidthScale = rivers.widthScale
		style.showRealms = realms.drawn
		return style
	}
}

extension MapDrawing {
	/// The drawing of a water map as the settings say: its `style`, and **its rivers only when the settings show them** (otherwise the land alone is drawn).
	public init(water: WaterMap, settings: MapSettings) {
		if settings.rivers.shown {
			self.init(water: water, style: settings.style)
		} else {
			self.init(map: water.land, style: settings.style)
		}
	}
}
