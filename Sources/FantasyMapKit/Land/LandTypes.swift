import Foundation

/// A point on the map, in map units.
public struct Point: Hashable, Codable, Sendable {
	public var x: Double
	public var y: Double

	public init(x: Double, y: Double) {
		self.x = x
		self.y = y
	}

	/// Saved as a two-number array, like the original's points. Exactly two coordinates: more, fewer or non-finite
	/// numbers are an error.
	public init(from decoder: any Decoder) throws {
		var container = try decoder.unkeyedContainer()
		x = try container.decode(Double.self)
		y = try container.decode(Double.self)
		guard container.isAtEnd else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "A point has exactly two coordinates.")
		}
		guard x.isFinite, y.isFinite else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "A point's coordinates must be finite.")
		}
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.unkeyedContainer()
		try container.encode(x)
		try container.encode(y)
	}
}

/// How a map was made, kept so it can be explained or regenerated. Provenance only: loading never regenerates heights
/// from it, and a map without one is complete. Reserved before the first released format (see the review of step 1).
public struct GenerationRecipe: Codable, Equatable, Sendable {
	/// The named template, if the map came from one.
	public var template: String?
	/// The resolved step list that produced the heights, one step per line in the original's format.
	public var steps: [String]
	/// The settings that mattered, by name, as text.
	public var settings: [String: String]

	public init(template: String? = nil, steps: [String] = [], settings: [String: String] = [:]) {
		self.template = template
		self.steps = steps
		self.settings = settings
	}
}

/// A feature as saved: its record in the table, including records no cell refers to any more.
public struct SavedFeature: Codable, Equatable, Sendable {
	public var id: Int
	public var land: Bool
	public var border: Bool
	public var kind: FeatureKind

	public init(_ feature: Feature) {
		id = feature.id
		land = feature.land
		border = feature.border
		kind = feature.kind
	}

	var feature: Feature { Feature(id: id, land: land, border: border, kind: kind) }
}

/// Why a saved map was refused.
public enum SavedLandMapError: Error, Equatable, Sendable {
	case unsupportedFormatVersion(Int)
	case unsupportedAlgorithmRevision(Int)
	case invalidSize
	case invalidCellCount
	case tooManyCells
	case pointAndHeightCountsDiffer(points: Int, heights: Int)
	case heightOutOfRange(index: Int)
	case pointOutsideFiniteRange
	/// A cell point is not inside the map.
	case pointOutsideMap(index: Int)
	/// The cell points are not the number the size and cell count give, or the boundary points are not the ones the size and
	/// cell count give (a corrupt file, or an algorithm that changed under the same revision).
	case gridDoesNotMatchSize
	case featureIdCountDiffers(ids: Int, cells: Int)
	case coastDistanceCountDiffers(distances: Int, cells: Int)
	/// The feature table is empty or its ids are not 1, 2, 3 ... in order, or a record's kind and land flag disagree.
	case invalidFeatureTable
	case featureIdOutOfRange(index: Int)
	/// A cell's feature is land and its height is below sea level, or the reverse.
	case featureDisagreesWithHeight(index: Int)
	/// A coast distance outside -9 ... 1.
	case invalidCoastDistance(index: Int)
	/// The cells could not be rebuilt from the points.
	case cellsCouldNotBeBuilt
	/// A realm layer is present in a file of version 1, or a version 2 file has none (the version says whether there is one).
	case realmLayerDoesNotMatchVersion
	/// A pin layer is present in a file whose version is not 3, or a version 3 file has none.
	case pinLayerDoesNotMatchVersion
	/// The pin layer is not acceptable (see `PinLayerError`).
	case invalidPins(PinLayerError)
}

/// The saved form of the land layer: **the exact state** (decided 2026-10-20). Beside the cell points, the boundary points
/// and the final heights it holds the feature ids, the feature records (including records no cell refers to any more, such as
/// a lake that was opened into an ocean) and the coast distance, so a loaded map is identical to the one saved and loading
/// recomputes none of them and never re-runs lake creation. Only the cells' neighbours and corners are rebuilt on load,
/// deterministically from the points (the algorithm revision governs that rebuilding: a changed triangulator reads the same
/// points differently).
public struct SavedLandMap: Codable, Equatable, Sendable {
	/// The version of this file format. Bumped when the format changes shape.
	public var formatVersion: Int
	/// The version of the algorithms that made the map and that rebuild its cells. Bumped when they change, so an old map is
	/// never silently read differently.
	public var algorithmRevision: Int
	public var seed: String
	/// The map's size in map units.
	public var width: Double
	public var height: Double
	/// The number of cells asked for (the real number is close but not equal to it).
	public var cellsDesired: Int
	/// The cell points, in cell order.
	public var points: [Point]
	/// The boundary points the cells are clipped by; they get no cells of their own, but the cells are built from both sets.
	public var boundaryPoints: [Point]
	/// The final heights, one per cell point and in the same order (0 ... 100, 20 is sea level).
	public var heights: [Height]
	/// The feature each cell belongs to (a number from 1), one per cell.
	public var featureIds: [UInt16]
	/// Each cell's graph distance from the coast: -9 ... 1, one per cell.
	public var coastDistance: [Int8]
	/// The feature table, in order: the first is feature 1.
	public var features: [SavedFeature]
	/// How the map was made, if known. Optional provenance; never used to regenerate on load.
	public var recipe: GenerationRecipe?
	/// The realms, if the map has them (format version 2); nil for a map without realms, written in version 1 as before.
	public var realms: SavedRealmLayer?
	/// The pins, if the map has any (format version 3); nil for a map without pins. **An empty list is not a layer:** a map whose pins were all removed is saved without one.
	public var pins: [MapPin]?

	public init(
		formatVersion: Int = FantasyMapKit.formatVersion,
		algorithmRevision: Int = FantasyMapKit.algorithmRevision,
		seed: String,
		width: Double,
		height: Double,
		cellsDesired: Int,
		points: [Point],
		boundaryPoints: [Point],
		heights: [Height],
		featureIds: [UInt16],
		coastDistance: [Int8],
		features: [SavedFeature],
		recipe: GenerationRecipe? = nil,
		realms: SavedRealmLayer? = nil,
		pins: [MapPin]? = nil
	) {
		self.formatVersion = formatVersion
		self.algorithmRevision = algorithmRevision
		self.seed = seed
		self.width = width
		self.height = height
		self.cellsDesired = cellsDesired
		self.points = points
		self.boundaryPoints = boundaryPoints
		self.heights = heights
		self.featureIds = featureIds
		self.coastDistance = coastDistance
		self.features = features
		self.recipe = recipe
		self.realms = realms
		self.pins = pins
	}

	/// The format versions this build reads. 0 was provisional; the first supported persisted format is 1.
	public static let supportedFormatVersions: Set<Int> = [FantasyMapKit.formatVersion, FantasyMapKit.formatVersionWithRealms, FantasyMapKit.formatVersionWithPins]
	/// The algorithm revisions this build can rebuild. An unsupported one is refused, never silently rebuilt differently.
	public static let supportedAlgorithmRevisions: Set<Int> = [FantasyMapKit.algorithmRevision]

	/// Throws if the map is not one this build can accept: supported versions; a finite positive size and a positive cell
	/// count within the point budget; one height, feature id and coast distance per cell point; heights within 0 ... 100;
	/// finite cell points inside the map; a feature table numbered 1, 2, 3 ... whose records are consistent; every cell's
	/// feature present in the table and agreeing with the cell's height (land or water); and coast distances in -9 ... 1.
	public func validate() throws {
		guard Self.supportedFormatVersions.contains(formatVersion) else { throw SavedLandMapError.unsupportedFormatVersion(formatVersion) }
		guard Self.supportedAlgorithmRevisions.contains(algorithmRevision) else { throw SavedLandMapError.unsupportedAlgorithmRevision(algorithmRevision) }
		// the version says whether there is a realm layer: version 1 has none, version 2 has one (a map without realms is saved in version 1)
		// the version says which layers a file may hold: 1 none, 2 realms, 3 pins (and realms if it has them)
		let hasPins = pins != nil
		guard hasPins == (formatVersion == FantasyMapKit.formatVersionWithPins) else { throw SavedLandMapError.pinLayerDoesNotMatchVersion }
		if formatVersion != FantasyMapKit.formatVersionWithPins { guard (formatVersion == FantasyMapKit.formatVersionWithRealms) == (realms != nil) else { throw SavedLandMapError.realmLayerDoesNotMatchVersion } }
		guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw SavedLandMapError.invalidSize }
		guard cellsDesired > 0 else { throw SavedLandMapError.invalidCellCount }
		guard points.count <= GridPoints.maximumPoints, boundaryPoints.count <= GridPoints.maximumPoints else { throw SavedLandMapError.tooManyCells }
		guard points.count == heights.count else { throw SavedLandMapError.pointAndHeightCountsDiffer(points: points.count, heights: heights.count) }
		guard featureIds.count == points.count else { throw SavedLandMapError.featureIdCountDiffers(ids: featureIds.count, cells: points.count) }
		guard coastDistance.count == points.count else { throw SavedLandMapError.coastDistanceCountDiffers(distances: coastDistance.count, cells: points.count) }
		if let bad = heights.firstIndex(where: { $0 > Heights.maximum }) { throw SavedLandMapError.heightOutOfRange(index: bad) }
		guard (points + boundaryPoints).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw SavedLandMapError.pointOutsideFiniteRange }
		if let bad = points.firstIndex(where: { $0.x < 0 || $0.x > width || $0.y < 0 || $0.y > height }) { throw SavedLandMapError.pointOutsideMap(index: bad) }
		guard !features.isEmpty, features.count <= Int(UInt16.max),
			features.enumerated().allSatisfy({ $0.element.id == $0.offset + 1 && $0.element.land == ($0.element.kind == .island) })
		else { throw SavedLandMapError.invalidFeatureTable }
		for i in points.indices {
			let id = Int(featureIds[i])
			guard id >= 1 && id <= features.count else { throw SavedLandMapError.featureIdOutOfRange(index: i) }
			guard features[id - 1].land == Heights.isLand(heights[i]) else { throw SavedLandMapError.featureDisagreesWithHeight(index: i) }
			// the range only: the original itself can leave a positive distance on a water cell (a depression lake's shore marking
			// reaches a neighbouring water cell), so the sign is not tied to land or water
			guard coastDistance[i] >= -9 && coastDistance[i] <= 1 else { throw SavedLandMapError.invalidCoastDistance(index: i) }
		}
	}

	/// Decoding validates, so a map this build cannot accept never loads half-formed.
	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		formatVersion = try container.decode(Int.self, forKey: .formatVersion)
		algorithmRevision = try container.decode(Int.self, forKey: .algorithmRevision)
		seed = try container.decode(String.self, forKey: .seed)
		width = try container.decode(Double.self, forKey: .width)
		height = try container.decode(Double.self, forKey: .height)
		cellsDesired = try container.decode(Int.self, forKey: .cellsDesired)
		points = try container.decode([Point].self, forKey: .points)
		boundaryPoints = try container.decode([Point].self, forKey: .boundaryPoints)
		heights = try container.decode([Height].self, forKey: .heights)
		featureIds = try container.decode([UInt16].self, forKey: .featureIds)
		coastDistance = try container.decode([Int8].self, forKey: .coastDistance)
		features = try container.decode([SavedFeature].self, forKey: .features)
		recipe = try container.decodeIfPresent(GenerationRecipe.self, forKey: .recipe)
		realms = try container.decodeIfPresent(SavedRealmLayer.self, forKey: .realms)
		pins = try container.decodeIfPresent([MapPin].self, forKey: .pins)
		do { try validate() } catch {
			throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an acceptable saved map: \(error)"))
		}
	}

	private enum CodingKeys: String, CodingKey {
		case formatVersion, algorithmRevision, seed, width, height, cellsDesired, points, boundaryPoints, heights, featureIds, coastDistance, features, recipe, realms, pins
	}
}
