import FantasyMapCore
import Foundation
import Testing
@testable import FantasyMapKit

/// Making a whole map in one call: realms with saved colours, and the water.
struct MapMakingTests {
	func land(_ seed: String = "kaz-1", template: String = "continents", cells: Int = 3_000) throws -> LandMap {
		try LandMap.generate(seed: seed, cellsDesired: cells, template: try #require(HeightmapTemplate.named(template)))
	}

	@Test func realmsAreAttachedWithTheirColoursSavedAndEveryLandCellOwned() throws {
		let m = try land().addingRealms()
		let layer = try #require(m.realms)
		#expect(layer.ownership.realms.count >= 2)
		#expect(layer.colors?.count == layer.ownership.realms.count)
		for cell in 0..<m.heights.count where Heights.isLand(m.heights[cell]) { #expect(layer.ownership.owner[cell] > 0) }
		for cell in 0..<m.heights.count where Heights.isWater(m.heights[cell]) { #expect(layer.ownership.owner[cell] == 0) }
		// the recipe names what was used
		#expect(layer.recipe.realmSeed == m.seed && layer.recipe.chosenCount == nil && layer.recipe.reach == RealmDefaults.reach && layer.recipe.resolvedCount == layer.ownership.realms.count)
	}

	@Test func theSameInputsGiveTheSameRealmsAndTheSameBytes() throws {
		let a = try land().addingRealms(), b = try land().addingRealms()
		#expect(a == b)
		#expect(try a.encoded() == b.encoded())
		// the realm seed decides them: the map's own seed by default, another when given
		#expect(try land().addingRealms(realmSeed: a.seed) == a)
		let other = try land().addingRealms(realmSeed: "another-realms")
		#expect(other.realms?.ownership.owner != a.realms?.ownership.owner)
	}

	@Test func aMapWithRealmsIsSavedAndOpenedIdentically() throws {
		let a = try land().addingRealms()
		let loaded = try LandMap(decoding: try a.encoded())
		#expect(loaded == a && loaded.realms?.colors == a.realms?.colors)
	}

	@Test func realmsDoNotChangeTheGeographyFingerprint() throws {
		let plain = try land()
		#expect(try plain.addingRealms().fingerprint == plain.fingerprint)
	}

	@Test func everyLandShapeGetsRealms() throws {
		for template in ["continents", "archipelago", "pangea", "shattered", "highIsland", "lowIsland", "atoll"] {
			let m = try land("shape-\(template)", template: template, cells: 2_000).addingRealms()
			#expect(m.realms != nil, "\(template)")
		}
	}

	@Test func anEmptyPaletteIsRefusedAndNothingIsAttached() throws {
		var style = MapStyle.standard
		style.realmColors = []
		let plain = try land()
		#expect(throws: (any Error).self) { try plain.addingRealms(style: style) }
		#expect(plain.realms == nil)
	}

	@Test func aWholeMapFromASeedHasRealmsAndWaterAndRoundTrips() throws {
		let template = try #require(HeightmapTemplate.named("continents"))
		let a = try WaterMap.generate(seed: "kaz-1", template: template, cellsDesired: 3_000)
		let b = try WaterMap.generate(seed: "kaz-1", template: template, cellsDesired: 3_000)
		#expect(a.land.realms != nil && !a.rivers.isEmpty)
		#expect(try a.encoded() == b.encoded())
		let loaded = try WaterMap(decoding: try a.compressedEncoded())
		#expect(loaded.land == a.land && loaded.rivers == a.rivers)
		// the same land as the steps make
		#expect(a.land == (try land("kaz-1").addingRealms()))
	}
}
