import Foundation
import Testing
@testable import FantasyMapCore

/// Saving the pins in the map file (docs/plans/pins-saving.md): an optional layer of the land file, format version 3.
struct PinLayerTests {
	func map(_ seed: String = "kaz-1", cells: Int = 600) throws -> LandMap {
		try LandMap.generate(seed: seed, width: 640, height: 400, cellsDesired: cells, template: try #require(HeightmapTemplate.named("continents")))
	}

	func pins() -> [MapPin] {
		[
			MapPin(id: MapPin.newID(), position: Point(x: 100, y: 50), marker: "pin", color: "red", note: "the camp"),
			MapPin(id: "ford", position: Point(x: 320.5, y: 200.25), marker: "dot", color: "blue", note: "line one\nline two — 日本語 👨‍👩‍👧‍👦"),
			MapPin(id: "corner", position: Point(x: 640, y: 400), marker: "my-own-marker", color: "mauve"),
			MapPin(id: "origin", position: Point(x: 0, y: 0))
		]
	}

	func realmLayer(_ m: LandMap) throws -> RealmLayer {
		let groups = try LandGroups.find(in: m, reach: 25)
		let seeds = try RealmSeeds.place(in: m, groups: groups, count: .automatic, realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 40_000, maximumRealms: 500))
		let ownership = try RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: "r", policy: GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3))
		return RealmLayer(ownership: ownership, recipe: RealmRecipe(realmSeed: "r", reach: 25, resolvedCount: seeds.resolvedCount, typicalRealmArea: 40_000, maximumRealms: 500, hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3))
	}

	func refused(_ saved: SavedLandMap, _ expected: SavedLandMapError? = nil, line: Int = #line) {
		var failed = false
		let location = SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1)
		do { _ = try LandMap(saved: saved) } catch { failed = true; if let expected { #expect("\(error)" == "\(expected)", "\(error)", sourceLocation: location) } }
		#expect(failed, "refused", sourceLocation: location)
	}

	// MARK: round trips

	@Test func aMapWithPinsRoundTripsExactlyInOrderAndSavesToTheSameBytes() throws {
		let m = try map().settingPins(pins())
		#expect(m.pins.count == 4 && m.saved.formatVersion == 3 && m.saved.pins?.count == 4)
		let data = try m.encoded()
		let loaded = try LandMap(decoding: data)
		#expect(loaded == m && loaded.pins == m.pins, "the same pins in the same order, with their memos and keys")
		let resaved = try loaded.encoded()
		#expect(resaved == data, "the same bytes on a second save")
		#expect(loaded.pins[1].note == "line one\nline two — 日本語 👨‍👩‍👧‍👦" && loaded.pins[2].marker == "my-own-marker" && loaded.pins[2].color == "mauve")
	}

	@Test func aMapWithoutPinsIsWrittenAsBeforeAndTheLayersCombine() throws {
		let plain = try map()
		let text = String(decoding: try plain.encoded(), as: UTF8.self)
		#expect(plain.pins.isEmpty && plain.saved.formatVersion == 1 && !text.contains("\"pins\""))
		// realms only: version 2, as before; realms and pins: version 3 with both; pins only: version 3 with no realm layer
		let withRealms = try plain.adding(try realmLayer(plain))
		#expect(withRealms.saved.formatVersion == 2 && withRealms.saved.pins == nil)
		let both = try withRealms.settingPins(pins())
		#expect(both.saved.formatVersion == 3 && both.saved.realms != nil && both.saved.pins != nil)
		let loadedBoth = try LandMap(decoding: try both.encoded())
		#expect(loadedBoth == both && loadedBoth.realms == withRealms.realms && loadedBoth.pins == both.pins)
		let pinsOnly = try plain.settingPins(pins())
		let pinsOnlyLoaded = try LandMap(decoding: try pinsOnly.encoded())
		#expect(pinsOnly.saved.formatVersion == 3 && pinsOnly.saved.realms == nil && pinsOnlyLoaded.realms == nil)
		// adding or removing realms keeps the pins
		let pinsThenRealms = try pinsOnly.adding(try realmLayer(plain))
		#expect(pinsThenRealms.pins == pinsOnly.pins && both.removingRealms().pins == both.pins)
	}

	@Test func aMapWhosePinsWereAllRemovedIsSavedExactlyAsIfItNeverHadAny() throws {
		let plain = try map()
		let removed = try plain.settingPins(pins()).settingPins([])
		#expect(removed.pins.isEmpty && removed == plain)
		let a = try removed.encoded(), b = try plain.encoded()
		#expect(a == b, "no pin layer, version 1, the same bytes")
		// with realms: version 2 again
		let withRealms = try plain.adding(try realmLayer(plain))
		let emptied = try withRealms.settingPins(pins()).settingPins([])
		let c = try emptied.encoded(), d = try withRealms.encoded()
		#expect(c == d && emptied.saved.formatVersion == 2)
	}

	@Test func aWaterMapCarriesThePinsOfItsLandMapAndTheFingerprintIgnoresThem() throws {
		let m = try map()
		let water = try WaterMap.generate(land: m).settingPins(pins())
		#expect(water.land.pins.count == 4)
		let loaded = try WaterMap(decoding: try water.encoded())
		#expect(loaded == water && loaded.land.pins == water.land.pins)
		let compressed = try WaterMap(decoding: try water.compressedEncoded())
		#expect(compressed.land.pins == water.land.pins)
		let withPins = try m.settingPins(pins())
		#expect(water.fingerprint == m.fingerprint && withPins.fingerprint == m.fingerprint, "pins are not part of the geography's fingerprint")
	}

	@Test func aPinSavedBeforeItHadAColourOrAMemoStillLoadsWithTheDefaults() throws {
		let old = try JSONDecoder().decode(MapPin.self, from: Data(#"{"id":"o","position":[1,2],"marker":"pin"}"#.utf8))
		#expect(old == MapPin(id: "o", position: Point(x: 1, y: 2)) && old.color == "red" && old.note.isEmpty)
		// in a whole file: a version 3 file whose pins carry no colour and no memo
		var saved = try map().settingPins([MapPin(id: "a", position: Point(x: 5, y: 5))]).saved
		saved.pins = [old]
		let loaded = try LandMap(saved: saved)
		#expect(loaded.pins == [old])
		// a pin missing a required field is not a pin
		#expect(throws: Error.self) { try JSONDecoder().decode(MapPin.self, from: Data(#"{"id":"o","position":[1,2]}"#.utf8)) }
		#expect(throws: Error.self) { try JSONDecoder().decode(MapPin.self, from: Data(#"{"position":[1,2],"marker":"pin"}"#.utf8)) }
	}

	@Test func aFreshIdentifierIsAUUIDThatPassesTheChecks() throws {
		let ids = (0..<1_000).map { _ in MapPin.newID() }
		#expect(Set(ids).count == 1_000 && ids.allSatisfy { UUID(uuidString: $0) != nil && $0.count == 36 })
		_ = try map().settingPins(ids.prefix(50).enumerated().map { MapPin(id: $1, position: Point(x: Double($0), y: 1)) })
	}

	// MARK: the version says which layers

	@Test func theVersionSaysWhichLayersAFileMayHold() throws {
		let withPins = try map().settingPins(pins()).saved
		var v2 = withPins
		v2.formatVersion = 2
		refused(v2, .pinLayerDoesNotMatchVersion) // pins in a version 2 file
		var v1 = withPins
		v1.formatVersion = 1
		refused(v1, .pinLayerDoesNotMatchVersion)
		var noPins = withPins
		noPins.pins = nil
		refused(noPins, .pinLayerDoesNotMatchVersion) // a version 3 file with no pin layer
		var empty = withPins
		empty.pins = []
		refused(empty, .pinLayerDoesNotMatchVersion) // an empty list is not a layer
		var v4 = withPins
		v4.formatVersion = 4
		refused(v4)
		// a version 1 file with realms is still refused (as before) and a version 2 file with realms and no pins is still read
		let realmsOnly = try map().adding(try realmLayer(try map())).saved
		_ = try LandMap(saved: realmsOnly)
		var v3NoRealmsClaim = realmsOnly
		v3NoRealmsClaim.formatVersion = 1
		refused(v3NoRealmsClaim, .realmLayerDoesNotMatchVersion)
	}

	// MARK: refusals

	@Test func everyPinIsCheckedAgainstTheLimitsAndTheMap() throws {
		let base = try map().settingPins([MapPin(id: "a", position: Point(x: 5, y: 5))]).saved
		func with(_ edit: (inout MapPin) -> Void) -> SavedLandMap { var s = base; edit(&s.pins![0]); return s }
		let long = String(repeating: "x", count: 65)
		refused(with { $0.id = "" }, .invalidPins(.invalidID(index: 0)))
		refused(with { $0.id = long }, .invalidPins(.invalidID(index: 0)))
		_ = try LandMap(saved: with { $0.id = String(repeating: "x", count: 64) }) // exactly at the limit
		refused(with { $0.marker = "" }, .invalidPins(.invalidMarker(index: 0)))
		refused(with { $0.marker = long }, .invalidPins(.invalidMarker(index: 0)))
		_ = try LandMap(saved: with { $0.marker = String(repeating: "m", count: 64) })
		refused(with { $0.color = "" }, .invalidPins(.invalidColor(index: 0)))
		refused(with { $0.color = long }, .invalidPins(.invalidColor(index: 0)))
		// the place: finite, and inside the map (the edges are inside)
		for place in [Point(x: .nan, y: 5), Point(x: 5, y: .infinity), Point(x: -0.001, y: 5), Point(x: 5, y: -0.001), Point(x: 640.001, y: 5), Point(x: 5, y: 400.001)] {
			refused(with { $0.position = place }, .invalidPins(.invalidPlace(index: 0)))
		}
		for place in [Point(x: 0, y: 0), Point(x: 640, y: 400), Point(x: 0, y: 400), Point(x: 640, y: 0)] { _ = try LandMap(saved: with { $0.position = place }) }
		// the memo: 2,000 characters, and 16,000 bytes
		_ = try LandMap(saved: with { $0.note = String(repeating: "n", count: 2_000) })
		refused(with { $0.note = String(repeating: "n", count: 2_001) }, .invalidPins(.noteTooLong(index: 0)))
		refused(with { $0.note = String(repeating: "👨‍👩‍👧‍👦", count: 700) }, .invalidPins(.noteTooLong(index: 0))) // 700 characters, 17,500 bytes
		_ = try LandMap(saved: with { $0.note = String(repeating: "日", count: 2_000) }) // 2,000 characters, 6,000 bytes
	}

	@Test func idsMustBeUniqueAndThePinsMustNotBeTooMany() throws {
		let base = try map().settingPins([MapPin(id: "a", position: Point(x: 5, y: 5))]).saved
		var duplicate = base
		duplicate.pins = [MapPin(id: "a", position: Point(x: 1, y: 1)), MapPin(id: "b", position: Point(x: 2, y: 2)), MapPin(id: "a", position: Point(x: 3, y: 3))]
		refused(duplicate, .invalidPins(.duplicateID("a")))
		// ids that differ only in case are different (a plain text comparison)
		var cases = base
		cases.pins = [MapPin(id: "a", position: Point(x: 1, y: 1)), MapPin(id: "A", position: Point(x: 2, y: 2))]
		_ = try LandMap(saved: cases)
		// the count: 5,000 is the most
		var many = base
		many.pins = (0..<5_000).map { MapPin(id: "p\($0)", position: Point(x: Double($0 % 640), y: Double($0 % 400))) }
		let atLimit = try LandMap(saved: many)
		#expect(atLimit.pins.count == 5_000)
		many.pins!.append(MapPin(id: "one-more", position: Point(x: 1, y: 1)))
		refused(many, .invalidPins(.tooManyPins(5_001)))
		// the first problem is the one reported, by position
		var two = base
		two.pins = [MapPin(id: "a", position: Point(x: 1, y: 1)), MapPin(id: "", position: Point(x: 1, y: 1)), MapPin(id: "c", position: Point(x: .nan, y: 1))]
		refused(two, .invalidPins(.invalidID(index: 1)))
	}

	@Test func settingPinsThatDoNotFitChangesNothing() throws {
		let m = try map().settingPins(pins())
		let before = m
		#expect(throws: PinLayerError.duplicateID("x")) { try m.settingPins([MapPin(id: "x", position: Point(x: 1, y: 1)), MapPin(id: "x", position: Point(x: 2, y: 2))]) }
		#expect(throws: PinLayerError.invalidPlace(index: 0)) { try m.settingPins([MapPin(id: "x", position: Point(x: 641, y: 1))]) }
		#expect(throws: PinLayerError.tooManyPins(5_001)) { try m.settingPins((0..<5_001).map { MapPin(id: "p\($0)", position: Point(x: 1, y: 1)) }) }
		#expect(m == before && m.pins.count == 4)
		let water = try WaterMap.generate(land: try map())
		#expect(throws: PinLayerError.invalidID(index: 0)) { try water.settingPins([MapPin(id: "", position: Point(x: 1, y: 1))]) }
	}

	@Test func twoMapsDifferWhenTheirPinsDiffer() throws {
		let m = try map()
		let a = try m.settingPins(pins())
		#expect(a != m)
		var changed = pins()
		changed[0].note = "another memo"
		let changedMap = try m.settingPins(changed)
		#expect(a != changedMap)
		var reordered = pins()
		reordered.swapAt(0, 1)
		let reorderedMap = try m.settingPins(reordered)
		#expect(a != reorderedMap, "the order is part of the saved state")
		let copy = try m.settingPins(a.pins)
		#expect(copy == a)
	}

	// MARK: the fixed file

	@Test(.enabled(if: ProcessInfo.processInfo.environment["MAP_WRITE_PINS_REVISION3"] != nil))
	func writeTheFixture() throws {
		let out = URL(filePath: try #require(ProcessInfo.processInfo.environment["MAP_WRITE_PINS_REVISION3"]))
		let m = try map("kaz-1", cells: 600)
		let fixed = [
			MapPin(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", position: Point(x: 100, y: 50), marker: "pin", color: "red", note: "the camp"),
			MapPin(id: "ford", position: Point(x: 320.5, y: 200.25), marker: "dot", color: "blue", note: "line one\nline two — 日本語"),
			MapPin(id: "corner", position: Point(x: 640, y: 400), marker: "my-own-marker", color: "mauve")
		]
		try m.settingPins(fixed).encoded().write(to: out.appending(path: "pins-continents-600.json"))
	}

	@Test func theFixedVersionThreeFileStillLoadsToTheSamePins() throws {
		let url = try #require(Bundle.module.url(forResource: "Fixtures/pinsrevision3/pins-continents-600", withExtension: "json"))
		let data = try Data(contentsOf: url)
		let loaded = try LandMap(decoding: data)
		#expect(loaded.pins.count == 3 && loaded.saved.formatVersion == 3)
		let again = try loaded.encoded()
		#expect(again == data, "re-saving gives the same bytes")
		#expect(loaded.pins[0].id == "6F9619FF-8B86-D011-B42D-00C04FC964FF" && loaded.pins[1].note == "line one\nline two — 日本語" && loaded.pins[2].marker == "my-own-marker")
		#expect(loaded.fingerprint == (try map("kaz-1", cells: 600)).fingerprint, "the same geography as the map made today")
	}
}
