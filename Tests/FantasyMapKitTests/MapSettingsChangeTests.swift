import Testing
@testable import FantasyMapKit

/// What changed between two settings (docs/plans/map-controls.md, step 2).
struct MapSettingsChangeTests {
	typealias Edit = (inout MapSettings) -> Void

	/// Every setting, a change to it, and what that change takes. **A setting added to `MapSettings` must be added here**: the test below fails until it is.
	let table: [(path: String, edit: Edit, expected: MapSettings.Change)] = [
		("seed", { $0.seed = "other" }, .newMap),
		("landShape", { $0.landShape = "pangea" }, .newMap),
		("cells", { $0.cells = 3_000 }, .newMap),
		("coast.smoothing", { $0.coast.smoothing = 3 }, .look),
		("coast.inkWidth", { $0.coast.inkWidth = 2 }, .look),
		("coast.rough", { $0.coast.rough = true }, .look),
		("coast.amplitude", { $0.coast.amplitude = 1 }, .look),
		("coast.variant", { $0.coast.variant = 4 }, .look),
		("rivers.shown", { $0.rivers.shown = false }, .look),
		("rivers.widthScale", { $0.rivers.widthScale = 2 }, .look),
		("realms.drawn", { $0.realms.drawn = false }, .look),
		("realms.reach", { $0.realms.reach = 40 }, .realms),
		("realms.count", { $0.realms.count = 6 }, .realms),
		("realms.seed", { $0.realms.seed = "r" }, .realms),
		("realms.typicalArea", { $0.realms.typicalArea = 20_000 }, .realms),
		("realms.hillFactor", { $0.realms.hillFactor = 4 }, .realms),
		("realms.mountainFactor", { $0.realms.mountainFactor = 9 }, .realms),
		("realms.crossingFactor", { $0.realms.crossingFactor = 5 }, .realms),
		("realms.unevenness", { $0.realms.unevenness = 5 }, .realms),
		("pin.marker", { $0.pin.marker = "dot" }, []),
		("pin.color", { $0.pin.color = "blue" }, []),
	]

	/// The name of every setting, found by looking inside the value: a setting nobody classified cannot hide.
	func leaves(_ value: Any, _ prefix: String = "") -> [String] {
		let mirror = Mirror(reflecting: value)
		guard mirror.displayStyle == .struct, !mirror.children.isEmpty else { return [] }
		return mirror.children.flatMap { child -> [String] in
			let name = prefix + (child.label ?? "?")
			let inner = leaves(child.value, name + ".")
			return inner.isEmpty ? [name] : inner
		}
	}

	@Test func everySettingIsClassifiedAndItsChangeIsWhatTheTableSays() {
		#expect(Set(leaves(MapSettings())) == Set(table.map(\.path)), "a setting was added or removed without being classified here")
		#expect(Set(table.map(\.path)).count == table.count)
		for (path, edit, expected) in table {
			var changed = MapSettings()
			edit(&changed)
			#expect(changed != MapSettings(), "\(path): the edit must change the settings")
			#expect(changed.change(from: MapSettings()) == expected, "\(path)")
			#expect(MapSettings().change(from: changed) == expected, "\(path) the other way")
		}
	}

	@Test func theThreeKindsOfChangeAreDistinctAndDoNotOverlap() {
		let all: [MapSettings.Change] = [.newMap, .realms, .look]
		for (i, a) in all.enumerated() {
			#expect(!a.isEmpty)
			for (j, b) in all.enumerated() where i != j { #expect(a.intersection(b).isEmpty, "\(i) and \(j)") }
		}
		#expect(MapSettings.Change([.newMap, .realms, .look]).rawValue == 7)
	}

	@Test func nothingChangedTakesNothing() {
		#expect(MapSettings().change(from: MapSettings()).isEmpty)
		var s = MapSettings()
		s.realms.count = 4
		#expect(s.change(from: s).isEmpty)
	}

	@Test func severalChangesAreAllReported() {
		var s = MapSettings()
		s.seed = "x"
		s.realms.reach = 30
		s.coast.rough = true
		#expect(s.change(from: MapSettings()) == [.newMap, .realms, .look])
		var t = MapSettings()
		t.realms.unevenness = 6
		t.rivers.shown = false
		#expect(t.change(from: MapSettings()) == [.realms, .look])
	}

	/// Drawing the realms or not is only a look: the realms are made either way, so nothing is grown again.
	@Test func switchingTheRealmsOffAndOnOnlyChangesTheLook() {
		var off = MapSettings()
		off.realms.drawn = false
		#expect(off.change(from: MapSettings()) == .look)
		off.realms.count = 5
		#expect(off.change(from: MapSettings()) == [.realms, .look])
	}

	@Test func theChangeIsComparedBySettingsNotByHowTheyWereReached() {
		var a = MapSettings()
		a.cells = 3_000
		a.cells = 10_000
		#expect(a.change(from: MapSettings()).isEmpty)
		var b = MapSettings()
		b.seed = "x "
		#expect(b.change(from: MapSettings()) == .newMap)
	}
}
