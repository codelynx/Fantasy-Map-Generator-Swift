import FantasyMapCore
import Foundation
import Testing
@testable import FantasyMapKit

/// Applying settings without any view (docs/plans/map-controls.md, step 3).
struct MapSettingsApplyTests {
	/// Settings for a quick test: fewer cells.
	func settings(_ edit: (inout MapSettings) -> Void = { _ in }) -> MapSettings {
		var s = MapSettings()
		s.seed = "kaz-1"
		s.cells = 3_000
		edit(&s)
		return s
	}

	// MARK: the style

	@Test func theDefaultSettingsDrawWithTheStandardStyle() {
		#expect(MapSettings().style == MapStyle.standard)
	}

	@Test func theStyleFollowsTheCoastTheRiversAndTheRealms() throws {
		var s = MapSettings()
		s.coast.smoothing = 3
		s.coast.inkWidth = 2.5
		s.rivers.widthScale = 1.8
		s.realms.drawn = false
		let style = s.style
		#expect(style.smoothing == 3 && style.inkWidth == 2.5 && style.riverWidthScale == 1.8 && !style.showRealms && style.roughness == nil)
		s.coast.rough = true
		s.coast.amplitude = 1.25
		s.coast.variant = 7
		let rough = try #require(s.style.roughness)
		#expect(rough.baseAmplitude == 1.25 && rough.variant == 7)
		// the amplitude and variant are kept but not used while the coast is not rough
		s.coast.rough = false
		#expect(s.style.roughness == nil)
	}

	@Test func theDrawingShowsTheRiversOnlyWhenTheSettingsDo() throws {
		let water = try WaterMap.generate(settings: settings())
		let withRivers = MapDrawing(water: water, settings: settings())
		#expect(!withRivers.rivers.isEmpty)
		let without = MapDrawing(water: water, settings: settings { $0.rivers.shown = false })
		#expect(without.rivers.isEmpty)
		#expect(!MapDrawing(water: water, settings: settings { $0.realms.drawn = false }).rivers.isEmpty)
		#expect(MapDrawing(water: water, settings: settings { $0.realms.drawn = false }).realmWash.isEmpty)
		#expect(!withRivers.realmWash.isEmpty)
	}

	// MARK: making a map from settings

	@Test func theSameSettingsGiveTheSameMapAndTheDefaultsMatchTheOldCall() throws {
		let a = try WaterMap.generate(settings: settings()), b = try WaterMap.generate(settings: settings())
		#expect(try a.encoded() == b.encoded())
		let template = try #require(HeightmapTemplate.named("continents"))
		let old = try WaterMap.generate(seed: "kaz-1", template: template, cellsDesired: 3_000)
		#expect(try a.encoded() == old.encoded())
		#expect(a.land.seed == "kaz-1" && a.land.cellsDesired == 3_000 && a.land.recipe.template == "continents")
	}

	@Test func theLandShapeAndTheSeedDecideTheLand() throws {
		let a = try WaterMap.generate(settings: settings())
		let shape = try WaterMap.generate(settings: settings { $0.landShape = "archipelago" })
		let seed = try WaterMap.generate(settings: settings { $0.seed = "kaz-2" })
		#expect(shape.land.fingerprint != a.land.fingerprint && seed.land.fingerprint != a.land.fingerprint)
		#expect(shape.land.recipe.template == "archipelago")
	}

	@Test func aChosenNumberOfRealmsIsWhatYouGet() throws {
		for count in [3, 6, 9] {
			let map = try WaterMap.generate(settings: settings { $0.realms.count = count })
			let layer = try #require(map.land.realms)
			#expect(layer.ownership.realms.count == count && layer.recipe.chosenCount == count && layer.recipe.resolvedCount == count, "\(count)")
			#expect(layer.colors?.count == count)
		}
		// automatic is not the same as a chosen count
		let automatic = try #require(try WaterMap.generate(settings: settings()).land.realms)
		#expect(automatic.recipe.chosenCount == nil)
	}

	@Test func theRealmSettingsReachTheRecipeAndShapeTheRealms() throws {
		let base = try #require(try WaterMap.generate(settings: settings()).land.realms)
		var tuned = settings()
		tuned.realms.reach = 60
		tuned.realms.typicalArea = 20_000
		tuned.realms.hillFactor = 5
		tuned.realms.mountainFactor = 12
		tuned.realms.crossingFactor = 6
		tuned.realms.unevenness = 7
		tuned.realms.seed = "other-realms"
		let layer = try #require(try WaterMap.generate(settings: tuned).land.realms)
		let r = layer.recipe
		#expect(r.reach == 60 && r.typicalRealmArea == 20_000 && r.hillFactor == 5 && r.mountainFactor == 12 && r.crossingFactor == 6 && r.unevenness == 7 && r.realmSeed == "other-realms")
		#expect(layer.ownership.owner != base.ownership.owner)
		#expect(base.recipe.realmSeed == "kaz-1")
	}

	/// Each realm setting changes the realms **by itself** (the others left alone): the recipe only records what was asked, so this is what shows the setting reaches the
	/// growth. The crossing factor only matters where realms span the sea, so it is tried on an archipelago with a reach that joins some islands.
	@Test func eachRealmSettingChangesTheRealmsOnItsOwn() throws {
		func owners(_ shape: String, _ edit: (inout MapSettings.Realms) -> Void) throws -> [Int32] {
			var s = settings { $0.landShape = shape }
			edit(&s.realms)
			return try #require(try WaterMap.generate(settings: s).land.realms).ownership.owner
		}
		let continents = try owners("continents") { _ in }
		let edits: [(String, (inout MapSettings.Realms) -> Void)] = [
			("reach", { $0.reach = 0 }), ("typicalArea", { $0.typicalArea = 10_000 }), ("hillFactor", { $0.hillFactor = 30 }),
			("mountainFactor", { $0.mountainFactor = 200 }), ("unevenness", { $0.unevenness = 30 }), ("count", { $0.count = 6 }), ("seed", { $0.seed = "other-realms" }),
		]
		for (name, edit) in edits { #expect(try owners("continents", edit) != continents, "\(name)") }
		let islands = try owners("archipelago") { $0.reach = 60 }
		#expect(try owners("archipelago") { $0.reach = 60; $0.crossingFactor = 100 } != islands, "crossingFactor")
	}

	// MARK: reading the settings back from a map

	@Test func aMapDescribesTheSettingsItWasMadeWith() throws {
		let defaults = settings()
		#expect(MapSettings(describing: try WaterMap.generate(settings: defaults).land) == defaults)
		var tuned = settings {
			$0.landShape = "archipelago"
			$0.realms.count = 6
			$0.realms.seed = "other-realms"
			$0.realms.reach = 60
			$0.realms.typicalArea = 20_000
			$0.realms.hillFactor = 5
			$0.realms.mountainFactor = 12
			$0.realms.crossingFactor = 6
			$0.realms.unevenness = 7
		}
		let land = try WaterMap.generate(settings: tuned).land
		#expect(MapSettings(describing: land) == tuned)
		// a realm seed equal to the map's own seed reads back as "the map's own"
		tuned.realms.seed = "kaz-1"
		#expect(MapSettings(describing: try WaterMap.generate(settings: tuned).land).realms.seed == nil)
		// what a map does not keep is the default, whatever the settings said
		var look = settings { $0.coast.smoothing = 4; $0.rivers.widthScale = 3; $0.realms.drawn = false; $0.pin.color = "blue" }
		look.pin.marker = "dot"
		let described = MapSettings(describing: try WaterMap.generate(settings: look).land)
		#expect(described.coast == MapSettings.Coast() && described.rivers == MapSettings.Rivers() && described.realms.drawn && described.pin == MapSettings.Pin())
	}

	@Test func aMapWithoutRealmsIsDescribedWithTheDefaultRealmSettingsAndTheSettingsRoundTripThroughRegrowing() throws {
		let template = try #require(HeightmapTemplate.named("pangea"))
		let bare = try LandMap.generate(seed: "bare", cellsDesired: 2_000, template: template)
		let described = MapSettings(describing: bare)
		#expect(described.seed == "bare" && described.landShape == "pangea" && described.cells == 2_000 && described.realms == MapSettings.Realms())
		// settings read from a map and applied again give the same map back
		let made = try WaterMap.generate(settings: settings { $0.realms.count = 4 })
		let again = try made.regrowingRealms(settings: MapSettings(describing: made.land))
		#expect(try again.encoded() == made.encoded())
	}

	@Test func settingsThePackageCannotUseMakeNothing() {
		#expect(throws: MapSettings.Problem.invalid("cells")) { try WaterMap.generate(settings: settings { $0.cells = 10 }) }
		#expect(throws: MapSettings.Problem.invalid("landShape")) { try WaterMap.generate(settings: settings { $0.landShape = "flat" }) }
		#expect(throws: MapSettings.Problem.invalid("realms.count")) { try WaterMap.generate(settings: settings { $0.realms.count = 0 }) }
	}

	// MARK: realms made again on the same land

	@Test func realmsMadeAgainAreTheSameAsAWholeMapWithThoseRealmSettings() throws {
		let first = try WaterMap.generate(settings: settings())
		var tuned = settings { $0.realms.count = 7; $0.realms.unevenness = 6 }
		let again = try first.regrowingRealms(settings: tuned)
		let whole = try WaterMap.generate(settings: tuned)
		#expect(try again.encoded() == whole.encoded())
		#expect(again.land.realms?.ownership.realms.count == 7)
		// the original realm settings give the original realms back
		tuned.realms = MapSettings.Realms()
		#expect(try first.regrowingRealms(settings: tuned).encoded() == first.encoded())
	}

	@Test func realmsMadeAgainKeepTheLandTheRiversAndThePins() throws {
		let first = try WaterMap.generate(settings: settings())
		let pins = [MapPin(id: "a", position: Point(x: 100, y: 100), note: "harbour"), MapPin(id: "b", position: Point(x: 300, y: 200), color: "green")]
		let pinned = try first.settingPins(pins)
		let again = try pinned.regrowingRealms(settings: settings { $0.realms.count = 5 })
		#expect(again.land.pins == pins)
		#expect(again.land.fingerprint == pinned.land.fingerprint && again.land.heights == pinned.land.heights)
		#expect(again.rivers == pinned.rivers && again.flux == pinned.flux && again.riverIds == pinned.riverIds)
		#expect(again.temperature == pinned.temperature && again.precipitation == pinned.precipitation)
		#expect(again.land.realms?.ownership.realms.count == 5)
		#expect(again.land.realms?.ownership.owner != pinned.land.realms?.ownership.owner)
		// and it saves and opens identically
		let loaded = try WaterMap(decoding: try again.compressedEncoded())
		#expect(loaded.land == again.land)
	}

	@Test func realmsMadeAgainWithSettingsThePackageCannotUseChangeNothing() throws {
		let first = try WaterMap.generate(settings: settings())
		#expect(throws: MapSettings.Problem.invalid("realms.reach")) { try first.regrowingRealms(settings: settings { $0.realms.reach = -1 }) }
		#expect(try first.encoded() == WaterMap.generate(settings: settings()).encoded())
	}

	@Test func aWaterMapAcceptsARealmLayerWithoutChangingTheWater() throws {
		let first = try WaterMap.generate(settings: settings())
		let other = try first.land.addingRealms(settings: { var r = MapSettings.Realms(); r.count = 4; return r }())
		let swapped = try first.adding(try #require(other.realms))
		#expect(swapped.rivers == first.rivers && swapped.land.heights == first.land.heights && swapped.land.realms == other.realms)
		// a layer that does not fit this land is refused and nothing changes
		let small = try LandMap.generate(seed: "small", cellsDesired: 1_000, template: try #require(HeightmapTemplate.named("continents"))).addingRealms()
		#expect(throws: (any Error).self) { try first.adding(try #require(small.realms)) }
	}
}
