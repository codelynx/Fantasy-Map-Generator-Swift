import FantasyMapCore

/// Making a whole map in one call: the land, its realms with their colours saved, and optionally its water. The realms use the settings of the original-like
/// defaults the demo starts from (docs/programming-guide.md), and **no setting is offered**: an app that wants the sliders makes the realms in steps, as the
/// demo does.
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
	/// This map with a realm layer made from `realmSeed` (the map's own seed when nil, so that a seed alone remembers the realms) and `RealmDefaults`, with the
	/// automatic count, and with **the colours resolved in `style` and saved** in the layer, so that the map shows the same colours when it is opened again.
	/// Throws what the steps throw (the land could not be grouped, a seed could not be placed, the palette is empty); nothing is half done.
	public func addingRealms(realmSeed: String? = nil, style: MapStyle = .standard) throws -> LandMap {
		let realmSeed = realmSeed ?? seed
		let groups = try LandGroups.find(in: self, reach: RealmDefaults.reach)
		let policy = RealmPolicy(typicalRealmArea: RealmDefaults.typicalRealmArea, maximumRealms: RealmDefaults.maximumRealms)
		let seeds = try RealmSeeds.place(in: self, groups: groups, count: .automatic, realmSeed: realmSeed, policy: policy)
		let growth = GrowthPolicy(hillFactor: RealmDefaults.hillFactor, mountainFactor: RealmDefaults.mountainFactor, crossingFactor: RealmDefaults.crossingFactor, unevenness: RealmDefaults.unevenness)
		let ownership = try RealmOwnership.grow(in: self, groups: groups, seeds: seeds, realmSeed: realmSeed, policy: growth)
		let recipe = RealmRecipe(realmSeed: realmSeed, reach: RealmDefaults.reach, chosenCount: nil, resolvedCount: seeds.resolvedCount, typicalRealmArea: RealmDefaults.typicalRealmArea,
			maximumRealms: RealmDefaults.maximumRealms, sampleSize: policy.sampleSize, hillFactor: RealmDefaults.hillFactor, mountainFactor: RealmDefaults.mountainFactor,
			crossingFactor: RealmDefaults.crossingFactor, unevenness: RealmDefaults.unevenness)
		let colors = try MapDrawing.resolvedRealmColors(for: self, ownership: ownership, style: style)
		return try adding(RealmLayer(ownership: ownership, recipe: recipe, colors: colors))
	}
}

extension WaterMap {
	/// **A whole map from a seed:** the land from `seed`, `template` and `cellsDesired`, its realms as `addingRealms` makes them, and its water (temperature, rain
	/// and rivers). The same inputs always give the same map. Synchronous; run it off the main thread for large maps.
	public static func generate(seed: String, template: HeightmapTemplate, cellsDesired: Int = 10_000, realmSeed: String? = nil, style: MapStyle = .standard) throws -> WaterMap {
		let land = try LandMap.generate(seed: seed, cellsDesired: cellsDesired, template: template).addingRealms(realmSeed: realmSeed, style: style)
		return try WaterMap.generate(land: land)
	}
}
