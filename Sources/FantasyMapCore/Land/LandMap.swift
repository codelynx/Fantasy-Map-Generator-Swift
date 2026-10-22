import Foundation

/// A generated land layer: the grid points, the cells, the heights, the features and the coast distance, all as the
/// original's pipeline leaves them for the land (points, cells, a template's heights, the features, the lakes).
///
/// Make one with `generate`, save it with `encoded()` and load it with `init(decoding:)`. A loaded map is **identical** to the
/// one saved: the saved file holds the exact state (including the feature records and coast distance the lakes changed), and
/// loading only rebuilds the cells' neighbours and corners from the points, never the heights, features or lakes.
public struct LandMap: Sendable {
	public let seed: String
	public let width: Double
	public let height: Double
	/// The number of cells asked for.
	public let cellsDesired: Int
	/// The grid points, boundary points and the geometry of the grid.
	public let grid: GridPoints
	/// The final heights, one per cell (0 ... 100; below 20 is water).
	public let heights: [Height]
	/// The features, the cell-to-feature ids and the coast distance, as left after the lakes.
	public let features: LandFeatures
	/// How the map was made.
	public let recipe: GenerationRecipe
	/// The realms, if the map has them: the exact territorial partition, its records, its recipe and the realms' resolved colours. **A map without realms
	/// (nil) is a distinct valid state, not a map with one realm.** Realms are added with `adding(_:)`.
	public let realms: RealmLayer?
	/// The map's pins, in order (docs/plans/pins-saving.md): **empty is no pin layer**, and a map whose pins were all removed is saved exactly like one that never had any.
	/// Pins travel with their map and are not part of the fingerprint. Set them with `settingPins(_:)`.
	public let pins: [MapPin]
	/// The cells (neighbours and corners). Derived from the points, so it is rebuilt on load and not saved.
	public let voronoi: VoronoiDiagram

	/// Makes a land map as the original's pipeline does for the land: the grid points from the seed, the cells, the template's
	/// heights, the features, then the deep-depression and near-sea lakes.
	///
	/// - Parameters:
	///   - cellsDesired: the number of cells asked for. The original's density steps are 1,000 to 100,000 (default 10,000);
	///     any count is accepted within the point budget.
	///   - elevationLimit: the original's lake elevation limit (default 20; exactly 80 switches depression lakes off).
	public static func generate(
		seed: String,
		width: Double = 1280,
		height: Double = 800,
		cellsDesired: Int = 10_000,
		template: HeightmapTemplate,
		elevationLimit: Double = 20
	) throws -> LandMap {
		let grid = try GridPoints.generate(seed: seed, width: width, height: height, cellsDesired: cellsDesired)
		let voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary)
		let heights = try HeightmapGenerator.generate(grid: grid, voronoi: voronoi, template: template, seed: seed)
		let marked = try LandFeatures.markup(heights: heights, voronoi: voronoi)
		// the original's template option holds the template's key, which is what the Atoll comparison is made against
		let lakes = try LandLakes.apply(heights: heights, features: marked, voronoi: voronoi, elevationLimit: elevationLimit, templateOption: template.key)
		let recipe = GenerationRecipe(
			template: template.key,
			steps: template.steps,
			settings: ["elevationLimit": String(elevationLimit), "templateOption": template.key]
		)
		return LandMap(seed: seed, width: width, height: height, cellsDesired: cellsDesired, grid: grid, heights: lakes.heights, features: lakes.features, recipe: recipe, realms: nil, pins: [], voronoi: voronoi)
	}

	/// This map with the realm layer attached. The layer is **validated against the map** (the owner array and the records against the cells, each realm
	/// connected, the colours), and nothing is attached if it fails.
	public func adding(_ layer: RealmLayer) throws -> LandMap {
		try layer.validate(for: self)
		return LandMap(seed: seed, width: width, height: height, cellsDesired: cellsDesired, grid: grid, heights: heights, features: features, recipe: recipe, realms: layer, pins: pins, voronoi: voronoi)
	}

	/// This map with these pins. **The pins are validated for this map** (the limits of `PinLimits`; ids not empty, not too long and unique; places finite and inside the map; keys not
	/// empty and not too long; memos within the limit) **and nothing changes if they are not.** An empty list removes the pin layer.
	public func settingPins(_ pins: [MapPin]) throws -> LandMap {
		try PinValidation.validate(pins, width: width, height: height)
		return LandMap(seed: seed, width: width, height: height, cellsDesired: cellsDesired, grid: grid, heights: heights, features: features, recipe: recipe, realms: realms, pins: pins, voronoi: voronoi)
	}

	/// **A fingerprint of the geography** (64 hex characters, SHA-256): the seed, the size, the number of cells asked for, the cell points, the boundary points, the final
	/// heights, the feature ids and the coast distance, as canonical bytes (fixed-width little-endian numbers, doubles by their bit patterns), so it is the same on every
	/// platform and does not depend on the JSON encoder. **Two maps with the same fingerprint have the same land and sea.** The realms, the water and the recipe are not
	/// part of it: a client that keeps pins (or any data tied to a place on the map) keeps them with this fingerprint and can tell whether the map it is shown is the one they
	/// were made on, so that they are never silently moved to another picture. (It says nothing about secrecy and is not a checksum of a file.)
	/// **The byte format of `fingerprint`, version 1** (frozen: a change to any part of it must change this string): the domain string; then the seed (its length, then its UTF-8
	/// bytes); the width and the height (doubles, by bit pattern); the number of cells asked for; the cell points and then the boundary points (each: the count, then x and y of every
	/// point as doubles by bit pattern); the heights (the count, then the bytes); the feature ids (the count, then each as a 64-bit number); the coast distance (the count, then each as
	/// a byte). All numbers are little-endian 64-bit. The digest is SHA-256, in lower-case hex. A fixed saved file pins the digest in the tests.
	public static let fingerprintDomain = "FantasyMapKit/geography-fingerprint/v1"

	public var fingerprint: String {
		var bytes = FingerprintBytes()
		bytes.add(Self.fingerprintDomain) // the format's name and version come first, so a different format can never give the same digest
		bytes.add(seed)
		bytes.add(width); bytes.add(height)
		bytes.add(cellsDesired)
		for points in [grid.points, grid.boundary] { bytes.add(points.count); for p in points { bytes.add(p.x); bytes.add(p.y) } }
		bytes.add(heights)
		bytes.add(features.featureIds.count); for id in features.featureIds { bytes.add(UInt64(id)) }
		bytes.add(features.distanceField.map { UInt8(bitPattern: $0) })
		return SHA256.hex(bytes.bytes)
	}

	/// This map without its realm layer.
	public func removingRealms() -> LandMap {
		LandMap(seed: seed, width: width, height: height, cellsDesired: cellsDesired, grid: grid, heights: heights, features: features, recipe: recipe, realms: nil, pins: pins, voronoi: voronoi)
	}

	// MARK: Saving and loading

	/// The map as a saved record (the exact state).
	public var saved: SavedLandMap {
		SavedLandMap(
			formatVersion: !pins.isEmpty ? FantasyMapCore.formatVersionWithPins : realms == nil ? FantasyMapCore.formatVersion : FantasyMapCore.formatVersionWithRealms,
			seed: seed, width: width, height: height, cellsDesired: cellsDesired,
			points: grid.points, boundaryPoints: grid.boundary, heights: heights,
			featureIds: features.featureIds, coastDistance: features.distanceField,
			features: features.features.map(SavedFeature.init), recipe: recipe, realms: realms.map(SavedRealmLayer.init), pins: pins.isEmpty ? nil : pins
		)
	}

	/// The map as JSON, with keys sorted, so the same map gives the same bytes in the environment this is tested in (sorted keys
	/// are repeatable output, not a universal canonical-JSON guarantee across Foundation versions).
	public func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try encoder.encode(saved)
	}

	/// Loads a saved map. A file with no recipe loads with an empty one and so, saved again, has the field present: saving
	/// what was loaded gives the same bytes only for files `encoded()` produced. Everything saved is validated first (see `SavedLandMap.validate`); then the grid's geometry is checked
	/// against the saved size (the point count and the boundary points must be the ones that size and cell count give), and
	/// the cells are rebuilt from the points. **Nothing else is recomputed: the heights, the features, the feature ids, the
	/// feature records and the coast distance are exactly the saved ones, and the lakes are never re-run.**
	public init(decoding data: Data) throws {
		try self.init(saved: JSONDecoder().decode(SavedLandMap.self, from: data))
	}

	/// Builds the map from a saved record (validating it, as decoding does).
	public init(saved: SavedLandMap) throws {
		try saved.validate()
		// the size and the cell count are untrusted: bound the work they imply before any counting loop runs
		let spacing: Double
		do { spacing = try GridPoints.preflight(width: saved.width, height: saved.height, cellsDesired: saved.cellsDesired) } catch { throw SavedLandMapError.gridDoesNotMatchSize }
		let cellsX = GridPoints.cellsCount(spacing: spacing, size: saved.width)
		let cellsY = GridPoints.cellsCount(spacing: spacing, size: saved.height)
		guard cellsX > 0, cellsY > 0,
			saved.points.count == GridPoints.exactCellPointCount(width: saved.width, height: saved.height, spacing: spacing),
			saved.boundaryPoints == GridPoints.boundaryPoints(width: saved.width, height: saved.height, spacing: spacing)
		else { throw SavedLandMapError.gridDoesNotMatchSize }
		let grid = GridPoints(width: saved.width, height: saved.height, cellsDesired: saved.cellsDesired, spacing: spacing, cellsX: cellsX, cellsY: cellsY, points: saved.points, boundary: saved.boundaryPoints)
		let voronoi: VoronoiDiagram
		do { voronoi = try VoronoiDiagram.calculate(points: grid.points, boundary: grid.boundary) } catch { throw SavedLandMapError.cellsCouldNotBeBuilt }
		let bare = LandMap(
			seed: saved.seed, width: saved.width, height: saved.height, cellsDesired: saved.cellsDesired, grid: grid, heights: saved.heights,
			features: LandFeatures(featureIds: saved.featureIds, distanceField: saved.coastDistance, features: saved.features.map(\.feature)),
			recipe: saved.recipe ?? GenerationRecipe(), realms: nil, pins: [], voronoi: voronoi
		)
		// the realm layer, if there is one, is validated against the cells just rebuilt (not regrown: nothing is recomputed that is saved)
		var layer: RealmLayer?
		if let savedRealms = saved.realms {
			layer = savedRealms.layer
			try layer?.validate(for: bare)
		}
		// the pin layer, if there is one, against the map's size (a version 3 file with an empty list is refused: an empty list is not a layer)
		var pins: [MapPin] = []
		if let savedPins = saved.pins {
			guard !savedPins.isEmpty else { throw SavedLandMapError.pinLayerDoesNotMatchVersion }
			do { try PinValidation.validate(savedPins, width: bare.width, height: bare.height) } catch let error as PinLayerError { throw SavedLandMapError.invalidPins(error) }
			pins = savedPins
		}
		self = LandMap(seed: bare.seed, width: bare.width, height: bare.height, cellsDesired: bare.cellsDesired, grid: bare.grid, heights: bare.heights, features: bare.features, recipe: bare.recipe, realms: layer, pins: pins, voronoi: bare.voronoi)
	}

	private init(seed: String, width: Double, height: Double, cellsDesired: Int, grid: GridPoints, heights: [Height], features: LandFeatures, recipe: GenerationRecipe, realms: RealmLayer?, pins: [MapPin], voronoi: VoronoiDiagram) {
		self.seed = seed
		self.width = width
		self.height = height
		self.cellsDesired = cellsDesired
		self.grid = grid
		self.heights = heights
		self.features = features
		self.recipe = recipe
		self.realms = realms
		self.pins = pins
		self.voronoi = voronoi
	}
}

extension LandMap: Equatable {
	/// Two maps are equal when everything saved is equal; the cells are derived from the points and are not compared.
	public static func == (a: LandMap, b: LandMap) -> Bool {
		a.seed == b.seed && a.width == b.width && a.height == b.height && a.cellsDesired == b.cellsDesired
			&& a.grid == b.grid && a.heights == b.heights && a.features == b.features && a.recipe == b.recipe && a.realms == b.realms && a.pins == b.pins
	}
}
