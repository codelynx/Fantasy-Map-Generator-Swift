import Foundation

/// A realm's colour as red, green and blue, each 0 to 1, in the sRGB colour space. **Plain numbers, so the core needs no drawing code**; the drawing layer
/// turns it into its own colour. The colour a realm has is saved with the realms (docs/plans/realms-saving.md).
public struct RealmColor: Codable, Equatable, Sendable {
	public var red: Double
	public var green: Double
	public var blue: Double

	public init(red: Double, green: Double, blue: Double) {
		self.red = red
		self.green = green
		self.blue = blue
	}

	/// Each channel 0 to 1 (a channel that is not a number fails both comparisons, and an infinite one the second).
	var isValid: Bool { [red, green, blue].allSatisfy { $0 >= 0 && $0 <= 1 } }
}

/// How a realm layer was made: shown and kept as provenance, **never used to regenerate on load**. The seed, the reach, the count asked for, the policy of
/// the seed placement and of the growth, as the generators take them.
public struct RealmRecipe: Codable, Equatable, Sendable {
	public var realmSeed: String
	/// The longest sea crossing that joins islands into one group (map units).
	public var reach: Double
	/// The count the author asked for, or nil when the package worked it out; and the count that was used.
	public var chosenCount: Int?
	public var resolvedCount: Int
	public var typicalRealmArea: Double
	public var maximumRealms: Int
	public var sampleSize: Int
	public var hillFactor: Double
	public var mountainFactor: Double
	public var crossingFactor: Double
	public var unevenness: Double

	public init(realmSeed: String, reach: Double, chosenCount: Int? = nil, resolvedCount: Int, typicalRealmArea: Double, maximumRealms: Int, sampleSize: Int = 24, hillFactor: Double, mountainFactor: Double, crossingFactor: Double, unevenness: Double) {
		self.realmSeed = realmSeed
		self.reach = reach
		self.chosenCount = chosenCount
		self.resolvedCount = resolvedCount
		self.typicalRealmArea = typicalRealmArea
		self.maximumRealms = maximumRealms
		self.sampleSize = sampleSize
		self.hillFactor = hillFactor
		self.mountainFactor = mountainFactor
		self.crossingFactor = crossingFactor
		self.unevenness = unevenness
	}
}

public enum RealmLayerError: Error, Equatable, Sendable {
	/// A recipe value is out of its range or not finite, or the counts disagree.
	case invalidRecipe
	/// The owner array does not describe this map: its length is not the number of cells, a land cell names no realm (or one that is not in the list), or a
	/// water cell names one.
	case ownershipDoesNotMatchMap
	/// A realm record (by number) is not consistent with the owner array: its number, its cell count, its seed cell, its group or its area.
	case invalidRealmRecord(number: Int)
	/// The land could not be grouped again from the map and the saved reach (a named refusal of that work).
	case groupsCouldNotBeFound
	/// A realm is not connected over land and the permitted sea crossings, or another check of the ownership failed (the first finding, in words).
	case ownershipIsNotValid(String)
	/// The colours are not one for each realm, or a colour is not a colour.
	case invalidColors
}

/// The realms of a land map as saved: **the exact territorial partition**, the realms' records, the recipe and, if known, the resolved colours. A map with a
/// realm layer saves it inside the land map's own file (format version 2); a map without one is a distinct valid state, not a map with one realm.
public struct RealmLayer: Equatable, Sendable {
	public var ownership: RealmOwnership
	public var recipe: RealmRecipe
	/// One colour for each realm, in realm order, or nil when none were saved (the drawing then derives them).
	public var colors: [RealmColor]?

	public init(ownership: RealmOwnership, recipe: RealmRecipe, colors: [RealmColor]? = nil) {
		self.ownership = ownership
		self.recipe = recipe
		self.colors = colors
	}

	/// Everything a loaded or attached layer must satisfy for the map: the recipe's ranges, the owner array and the realm records against the map's cells, each
	/// realm connected (found by grouping the land again from the map and the saved reach, **verifying the links as over-water crossings** with growth's own
	/// verification, and checking each realm over land and those links: a validation of what is saved, not a regeneration), and the colours. **The work is
	/// bounded by three things:** the grouping's own budgets, the crossing verification's explicit budget, and one pass over the cells, their neighbours and the
	/// links for the counts and the connectivity (linear, whatever the number of realms).
	func validate(for map: LandMap, crossingBudget: Int = GrowthPolicy(hillFactor: 1, mountainFactor: 1, crossingFactor: 1, unevenness: 0).verificationTests) throws {
		let n = map.heights.count
		let r = recipe, o = ownership
		// the recipe, by the generators' own rules
		guard RealmPolicy(typicalRealmArea: r.typicalRealmArea, maximumRealms: r.maximumRealms, sampleSize: r.sampleSize).isValid,
			GrowthPolicy(hillFactor: r.hillFactor, mountainFactor: r.mountainFactor, crossingFactor: r.crossingFactor, unevenness: r.unevenness).isValid,
			r.reach.isFinite, r.reach >= 0, r.resolvedCount == o.realms.count, r.resolvedCount >= 1, r.resolvedCount <= r.maximumRealms,
			r.chosenCount.map({ $0 == r.resolvedCount }) ?? true else { throw RealmLayerError.invalidRecipe }
		// the owner array: every land cell has a realm 1 ... K, every water cell none; the realms are numbered in order
		let k = o.realms.count
		guard o.owner.count == n, o.realms.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }),
			(0..<n).allSatisfy({ cell in
				let owner = Int(o.owner[cell])
				return Heights.isLand(map.heights[cell]) ? owner >= 1 && owner <= k : owner == 0
			}) else { throw RealmLayerError.ownershipDoesNotMatchMap }
		// the groups, found again from the land and the reach
		let groups: LandGroups
		do { groups = try LandGroups.find(in: map, reach: r.reach) } catch { throw RealmLayerError.groupsCouldNotBeFound }
		// the records: the cell count and the area (summed in cell order, as growth sums them), the seed cell, the group
		let v = map.voronoi
		var counts = [Int](repeating: 0, count: k + 1), areas = [Double](repeating: 0, count: k + 1)
		var polygons = [[Point]](repeating: [], count: n)
		for cell in 0..<n where o.owner[cell] > 0 {
			let polygon = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: map.width, height: map.height)
			polygons[cell] = polygon
			counts[Int(o.owner[cell])] += 1
			areas[Int(o.owner[cell])] += polygon.count >= 3 ? abs(RealmSeeds.polygonArea(polygon)) : 0
		}
		for record in o.realms {
			let number = record.number
			// (a count equal to the cells carrying the number and a seed cell that carries it make the count at least 1; an area that equals a sum of finite areas is finite)
			guard record.cellCount == counts[number], record.area == areas[number],
				record.seedCell >= 0, record.seedCell < n, Int(o.owner[record.seedCell]) == number,
				record.group == Int(groups.groupOfCell[record.seedCell]) else { throw RealmLayerError.invalidRealmRecord(number: number) }
		}
		// (every other cell of a realm is in its group too: connectivity below joins a realm's cells only over land and the crossings of one group)
		// **the links that connectivity may use are verified as over-water crossings** (each a genuine witness and a clean crossing), by growth's own verification
		// with an explicit budget, before a realm is trusted to be connected over them; a link that is not is refused
		do { try RealmOwnership.verifyCrossings(groups: groups, polygons: polygons, width: map.width, height: map.height, budget: crossingBudget) } catch { throw RealmLayerError.ownershipIsNotValid("a crossing between landmasses could not be verified: \(error)") }
		// connectivity (linear in the cells, their neighbours and the links) and the rest of the ownership's own independent check
		var perGroup = [Int](repeating: 0, count: groups.groups.count)
		for record in o.realms { perGroup[record.group] += 1 }
		let seeds = RealmSeeds(mode: r.chosenCount.map { .chosen($0) } ?? .automatic, resolvedCount: k, realmsPerGroup: perGroup, realms: o.realms.map { RealmSeeds.Realm(number: $0.number, group: $0.group, cell: $0.seedCell) })
		if let first = RealmOwnership.problems(in: o, groups: groups, seeds: seeds, neighbours: v.cells.c).first { throw RealmLayerError.ownershipIsNotValid(first) }
		// the colours
		if let colors, colors.count != k || !colors.allSatisfy(\.isValid) { throw RealmLayerError.invalidColors }
	}
}

/// A realm's record as saved.
public struct SavedRealm: Codable, Equatable, Sendable {
	public var number: Int
	public var group: Int
	public var seedCell: Int
	public var cellCount: Int
	public var area: Double
}

/// The saved form of a realm layer (an optional part of `SavedLandMap`).
public struct SavedRealmLayer: Codable, Equatable, Sendable {
	/// For every cell its realm number (1 to K) or 0 for water.
	public var owner: [Int32]
	public var realms: [SavedRealm]
	public var recipe: RealmRecipe
	public var colors: [RealmColor]?

	init(_ layer: RealmLayer) {
		owner = layer.ownership.owner
		realms = layer.ownership.realms.map { SavedRealm(number: $0.number, group: $0.group, seedCell: $0.seedCell, cellCount: $0.cellCount, area: $0.area) }
		recipe = layer.recipe
		colors = layer.colors
	}

	/// The layer, with the growth policy the recipe holds (the budgets are the generator's defaults: they only refuse work).
	var layer: RealmLayer {
		let growth = GrowthPolicy(hillFactor: recipe.hillFactor, mountainFactor: recipe.mountainFactor, crossingFactor: recipe.crossingFactor, unevenness: recipe.unevenness)
		return RealmLayer(
			ownership: RealmOwnership(owner: owner, realms: realms.map { RealmOwnership.Realm(number: $0.number, group: $0.group, seedCell: $0.seedCell, cellCount: $0.cellCount, area: $0.area) }, policy: growth),
			recipe: recipe, colors: colors)
	}
}
