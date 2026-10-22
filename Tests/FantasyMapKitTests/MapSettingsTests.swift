import FantasyMapCore
import Testing
@testable import FantasyMapKit

/// The settings value the controls edit (docs/plans/map-controls.md, step 1).
struct MapSettingsTests {
	@Test func theDefaultsMakeAFinishedMapAndAreValid() throws {
		let s = MapSettings()
		try s.validate()
		#expect(s.landShape == "continents" && s.cells == 10_000 && s.seed == "12345")
		#expect(s.rivers.shown && s.rivers.widthScale == 1)
		#expect(s.realms.drawn && s.realms.count == nil && s.realms.seed == nil)
		#expect(s.realms.reach == RealmDefaults.reach && s.realms.typicalArea == RealmDefaults.typicalRealmArea)
		#expect(s.realms.hillFactor == RealmDefaults.hillFactor && s.realms.mountainFactor == RealmDefaults.mountainFactor)
		#expect(s.realms.crossingFactor == RealmDefaults.crossingFactor && s.realms.unevenness == RealmDefaults.unevenness)
		#expect(s.coast.smoothing == 2 && s.coast.inkWidth == 1.5 && !s.coast.rough && s.coast.amplitude == 0.75 && s.coast.variant == 0)
		#expect(s.pin.marker == "pin" && s.pin.color == "red")
	}

	/// Each setting that is out of range, and the name the refusal gives it.
	@Test func everyOutOfRangeSettingIsRefusedByName() {
		let cases: [(String, (inout MapSettings) -> Void)] = [
			("seed", { $0.seed = "" }), ("seed", { $0.seed = "  \n" }), ("seed", { $0.seed = String(repeating: "x", count: 201) }),
			("landShape", { $0.landShape = "flat" }), ("landShape", { $0.landShape = "" }),
			("cells", { $0.cells = 999 }), ("cells", { $0.cells = 100_001 }), ("cells", { $0.cells = 0 }),
			("coast.smoothing", { $0.coast.smoothing = -1 }), ("coast.smoothing", { $0.coast.smoothing = 5 }),
			("coast.inkWidth", { $0.coast.inkWidth = -0.1 }), ("coast.inkWidth", { $0.coast.inkWidth = 10.1 }), ("coast.inkWidth", { $0.coast.inkWidth = .nan }), ("coast.inkWidth", { $0.coast.inkWidth = .infinity }),
			("coast.amplitude", { $0.coast.amplitude = -1 }), ("coast.amplitude", { $0.coast.amplitude = 1001 }), ("coast.amplitude", { $0.coast.amplitude = .nan }),
			("coast.variant", { $0.coast.variant = 1_000_001 }), ("coast.variant", { $0.coast.variant = -1_000_001 }),
			("rivers.widthScale", { $0.rivers.widthScale = 0.04 }), ("rivers.widthScale", { $0.rivers.widthScale = 10.1 }), ("rivers.widthScale", { $0.rivers.widthScale = .nan }),
			("realms.reach", { $0.realms.reach = -1 }), ("realms.reach", { $0.realms.reach = 10_001 }), ("realms.reach", { $0.realms.reach = .infinity }),
			("realms.count", { $0.realms.count = 0 }), ("realms.count", { $0.realms.count = 501 }), ("realms.count", { $0.realms.count = -3 }),
			("realms.seed", { $0.realms.seed = "" }), ("realms.seed", { $0.realms.seed = " " }), ("realms.seed", { $0.realms.seed = String(repeating: "x", count: 201) }),
			("realms.typicalArea", { $0.realms.typicalArea = 0 }), ("realms.typicalArea", { $0.realms.typicalArea = -1 }), ("realms.typicalArea", { $0.realms.typicalArea = 1e9 + 1 }), ("realms.typicalArea", { $0.realms.typicalArea = .nan }),
			("realms.hillFactor", { $0.realms.hillFactor = 0.9 }), ("realms.hillFactor", { $0.realms.hillFactor = 1_001 }), ("realms.hillFactor", { $0.realms.hillFactor = .nan }),
			("realms.mountainFactor", { $0.realms.mountainFactor = 0.9 }), ("realms.mountainFactor", { $0.realms.mountainFactor = 1_001 }),
			("realms.crossingFactor", { $0.realms.crossingFactor = 0.9 }), ("realms.crossingFactor", { $0.realms.crossingFactor = 1_001 }),
			("realms.unevenness", { $0.realms.unevenness = -0.1 }), ("realms.unevenness", { $0.realms.unevenness = 100.1 }), ("realms.unevenness", { $0.realms.unevenness = .nan }),
			("pin.marker", { $0.pin.marker = "" }), ("pin.marker", { $0.pin.marker = String(repeating: "m", count: 65) }),
			("pin.color", { $0.pin.color = "" }), ("pin.color", { $0.pin.color = String(repeating: "c", count: 65) }),
		]
		for (name, change) in cases {
			var s = MapSettings()
			change(&s)
			#expect(throws: MapSettings.Problem.invalid(name), "\(name)") { try s.validate() }
		}
	}

	/// The edges of each range are accepted.
	@Test func theEdgesOfEveryRangeAreAccepted() throws {
		var s = MapSettings()
		s.seed = String(repeating: "x", count: 200)
		s.cells = 1_000
		s.coast.smoothing = 0
		s.coast.inkWidth = 0
		s.coast.amplitude = 0
		s.coast.variant = -1_000_000
		s.rivers.widthScale = 0.05
		s.realms.reach = 0
		s.realms.count = 1
		s.realms.seed = "x"
		s.realms.typicalArea = 1e9
		s.realms.hillFactor = 1
		s.realms.mountainFactor = GrowthPolicy.maximumFactor
		s.realms.crossingFactor = 1
		s.realms.unevenness = 0
		s.pin.marker = String(repeating: "m", count: 64)
		try s.validate()
		s.cells = 100_000
		s.coast.smoothing = CoastOutlines.maximumSmoothing
		s.coast.inkWidth = 10
		s.rivers.widthScale = 10
		s.realms.reach = 10_000
		s.realms.count = RealmDefaults.maximumRealms
		s.realms.unevenness = GrowthPolicy.maximumUnevenness
		try s.validate()
	}

	@Test func everyLandShapeThePackageHasIsAccepted() throws {
		for template in HeightmapTemplate.all {
			var s = MapSettings()
			s.landShape = template.key
			try s.validate()
		}
	}

	@Test func settingsAreValuesThatCompareAndHashByEverySetting() {
		let a = MapSettings()
		var b = a
		#expect(a == b && a.hashValue == b.hashValue)
		let changes: [(inout MapSettings) -> Void] = [
			{ $0.seed = "other" }, { $0.landShape = "pangea" }, { $0.cells = 3_000 }, { $0.coast.smoothing = 3 }, { $0.coast.rough = true },
			{ $0.rivers.shown = false }, { $0.rivers.widthScale = 2 }, { $0.realms.drawn = false }, { $0.realms.count = 5 }, { $0.realms.seed = "r" },
			{ $0.realms.reach = 30 }, { $0.realms.unevenness = 4 }, { $0.pin.color = "blue" },
		]
		for change in changes {
			b = a
			change(&b)
			#expect(a != b && Set([a, b]).count == 2)
		}
	}
}
