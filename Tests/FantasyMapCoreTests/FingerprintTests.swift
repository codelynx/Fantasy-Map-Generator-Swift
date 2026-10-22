import Foundation
import Testing
@testable import FantasyMapCore

/// SHA-256 against the published vectors, and the map's fingerprint (docs/plans/map-pins.md: a client keeps its pins with the exact map they were dropped on).
struct FingerprintTests {
	@Test func sha256MatchesThePublishedVectors() {
		#expect(SHA256.hex([]) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
		#expect(SHA256.hex(Array("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
		#expect(SHA256.hex(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
		#expect(SHA256.hex([UInt8](repeating: 0x61, count: 1_000_000)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
		// the lengths around a block boundary (55, 56, 63, 64 and 65 bytes) pad correctly
		let known: [Int: String] = [
			55: "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
			56: "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
			63: "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
			64: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
			65: "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
			119: "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
			120: "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"
		]
		for (count, digest) in known { #expect(SHA256.hex([UInt8](repeating: 0x61, count: count)) == digest, "\(count) bytes") }
	}

	func map(_ seed: String = "kaz-1", template: String = "continents", cells: Int = 600) throws -> LandMap {
		try LandMap.generate(seed: seed, width: 640, height: 400, cellsDesired: cells, template: try #require(HeightmapTemplate.named(template)))
	}

	@Test func theFingerprintByteFormatIsFrozenAndPinnedByFixedFiles() throws {
		// the digests of two committed files, computed by an independent implementation of the documented byte format (a script that reads the file's JSON and builds the
		// bytes as `LandMap.fingerprint`'s documentation says): if the format, the arithmetic or the loading of a file changes, these change
		let highIsland = try #require(Bundle.module.url(forResource: "Fixtures/revision1/map-highIsland-300-limit20", withExtension: "json"))
		#expect(try LandMap(decoding: Data(contentsOf: highIsland)).fingerprint == "cfd093a5ac60df6e4653210ef2903feb9640544d955de58601ef5f5b1f2bb462")
		let realms = try #require(Bundle.module.url(forResource: "Fixtures/realmsrevision2/realms-continents-1500", withExtension: "json"))
		#expect(try LandMap(decoding: Data(contentsOf: realms)).fingerprint == "3b2b65c148ba5b77dea5c04d0ccfe6a1539ae9f214875543ae30b3ee5c83faee")
		#expect(LandMap.fingerprintDomain == "FantasyMapKit/geography-fingerprint/v1")
	}

	@Test func theFingerprintIsStableAndMakesTheGeographyIdentifiable() throws {
		let m = try map()
		let f = m.fingerprint
		#expect(f.count == 64 && f.allSatisfy { "0123456789abcdef".contains($0) })
		let again = try map(), reopened = try LandMap(decoding: try m.encoded())
		#expect(f == again.fingerprint, "the same map again")
		#expect(f == reopened.fingerprint, "a map saved and opened again")
		// another seed, land shape or number of cells is another map
		let others = [try map("other"), try map(template: "highIsland"), try map(cells: 900)]
		#expect(others.allSatisfy { $0.fingerprint != f })
		// a different size is another map even with the same cells asked for
		let wide = try LandMap.generate(seed: "kaz-1", width: 800, height: 400, cellsDesired: 600, template: try #require(HeightmapTemplate.named("continents")))
		#expect(f != wide.fingerprint)
	}

	@Test func aChangeToTheLandOrTheSeaChangesTheFingerprint() throws {
		let m = try map()
		// a height change that keeps land land: raise a land cell
		var raised = m.saved
		let land = try #require(raised.heights.indices.first { Heights.isLand(raised.heights[$0]) && raised.heights[$0] < 90 })
		raised.heights[land] += 5
		let higher = try LandMap(saved: raised)
		#expect(higher.fingerprint != m.fingerprint)
		// a point moved a little
		var moved = m.saved
		moved.points[3].x += 0.001
		if let other = try? LandMap(saved: moved) { #expect(other.fingerprint != m.fingerprint) }
	}

	@Test func everyPartOfTheGeographyThatCanChangeInAValidFileChangesTheFingerprint() throws {
		let m = try map()
		// the coast distance (a value in range that differs)
		var distance = m.saved
		let cell = try #require(distance.coastDistance.indices.first { distance.coastDistance[$0] == 0 || distance.coastDistance[$0] == -3 })
		distance.coastDistance[cell] = distance.coastDistance[cell] == 0 ? -3 : 0
		#expect(try LandMap(saved: distance).fingerprint != m.fingerprint, "the coast distance")
		// a water cell moved to another water feature (the table must stay consistent: land flags agree): on a map that has two water features
		var found: LandMap?
		for template in ["archipelago", "shattered", "highIsland", "continents", "mediterranean"] {
			for seed in ["a", "b", "c", "d", "e"] where found == nil {
				let candidate = try map(seed, template: template)
				if candidate.saved.features.filter({ !$0.land }).count >= 2 { found = candidate }
			}
		}
		let two = try #require(found, "a map with two water features")
		var ids = two.saved
		let waterFeatures = ids.features.filter { !$0.land }.map(\.id)
		let cellOfFirst = try #require(ids.featureIds.indices.first { Int(ids.featureIds[$0]) == waterFeatures[0] })
		ids.featureIds[cellOfFirst] = UInt16(waterFeatures[1])
		#expect(try LandMap(saved: ids).fingerprint != two.fingerprint, "the feature ids")
		// the number of cells asked for (the same cells, another request)
		var asked = m.saved
		asked.cellsDesired += 1
		if let other = try? LandMap(saved: asked) { #expect(other.fingerprint != m.fingerprint, "the number of cells asked for") }
		// the seed alone
		var seed = m.saved
		seed.seed = "another"
		#expect(try LandMap(saved: seed).fingerprint != m.fingerprint, "the seed")
		// the size alone is covered by `aChangeToTheLandOrTheSeaChangesTheFingerprint`'s siblings: a different size is another map
	}

	@Test func theRealmsTheWaterAndTheRecipeAreNotPartOfTheFingerprint() throws {
		let m = try map()
		let groups = try LandGroups.find(in: m, reach: 25)
		let seeds = try RealmSeeds.place(in: m, groups: groups, count: .automatic, realmSeed: "r", policy: RealmPolicy(typicalRealmArea: 40_000, maximumRealms: 500))
		let ownership = try RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: "r", policy: GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3))
		let layer = RealmLayer(ownership: ownership, recipe: RealmRecipe(realmSeed: "r", reach: 25, resolvedCount: seeds.resolvedCount, typicalRealmArea: 40_000, maximumRealms: 500, hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3))
		let withRealms = try m.adding(layer)
		#expect(withRealms.fingerprint == m.fingerprint, "realms do not change the land and sea")
		let water = try WaterMap.generate(land: withRealms)
		#expect(water.fingerprint == m.fingerprint)
	}
}
