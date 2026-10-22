import Foundation

/// Everything that makes one water map from a land map: the original's options with its defaults. **One height exponent** serves the
/// temperature and the lake climate, so the two cannot disagree.
public struct WaterSettings: Equatable, Codable, Sendable {
	/// Where the map sits on the globe; a value left out is drawn from the template.
	public var geography = GeographyRequest()
	/// The temperatures at sea level, in degrees Celsius.
	public var equator = 27.0, northPole = -30.0, southPole = -15.0
	/// The metres of a height, `(height - 18) ^ exponent`.
	public var heightExponent = 2.0
	/// The rain level in percent, and the six wind angles.
	public var precipitation = 100.0
	public var winds: [Double] = [225, 45, 225, 315, 135, 315]
	/// The river generator's options: erosion, the lake elevation limit and the depression-resolving iterations.
	public var allowErosion = true
	public var lakeElevationLimit = 20.0
	public var resolveDepressionsSteps = 250

	public init() {}

	var temperature: TemperatureSettings {
		var s = TemperatureSettings()
		s.equator = equator; s.northPole = northPole; s.southPole = southPole; s.heightExponent = heightExponent
		return s
	}

	var rain: PrecipitationSettings {
		var s = PrecipitationSettings()
		s.precipitation = precipitation; s.winds = winds
		return s
	}

	var rivers: RiverSettings {
		var s = RiverSettings()
		s.allowErosion = allowErosion; s.lakeElevationLimit = lakeElevationLimit; s.heightExponent = heightExponent
		return s
	}

	/// Whether every setting is acceptable to the stage that reads it (the stages check them again).
	func isValid() -> Bool {
		(try? temperature.validate()) != nil && (try? rain.validate()) != nil && (try? rivers.validate()) != nil && resolveDepressionsSteps >= 1 && resolveDepressionsSteps <= 1000
			&& [geography.mapSize, geography.latitude, geography.longitude].allSatisfy { $0 == nil || ($0!.isFinite && $0! >= 0 && $0! <= 100) }
	}
}

/// A land map with its water: where it sits on the globe, the temperature and rain, the packed graph, its features with the lakes'
/// climate, and the rivers. Make one with `generate`, save it with `encoded()` and load it with `init(decoding:)`: **one file holds the
/// land map and the water state**, a loaded map is identical to the one saved, and loading recomputes none of the stages.
public struct WaterMap: Sendable {
	public let land: LandMap
	public let settings: WaterSettings
	public let geography: Geography
	/// The temperature and the rain of every grid cell.
	public let temperature: [Int8]
	public let precipitation: [UInt8]
	/// The packed graph with its **final** heights (after the rivers cut their beds).
	public let packed: PackedMap
	/// The packed features with the lakes' fields as the rivers leave them.
	public let features: PackedFeatures
	/// The flux, river number and confluence flux of every packed cell, and the rivers.
	public let flux: [UInt16]
	public let riverIds: [UInt16]
	public let confluence: [UInt16]
	public let rivers: [River]

	/// The original's chain from a land map: coordinates, temperature, rain, the packed graph and its features, then the rivers.
	public static func generate(land: LandMap, settings: WaterSettings = WaterSettings(), policy: RiverResourcePolicy = RiverResourcePolicy()) throws -> WaterMap {
		guard settings.isValid() else { throw SavedWaterMapError.invalidSettings }
		var policy = policy
		policy.resolveDepressionsSteps = settings.resolveDepressionsSteps
		let geography = try Geography.generate(for: land, request: settings.geography)
		let temperature = try Temperature.compute(for: land, geography: geography, settings: settings.temperature)
		let precipitation = try Precipitation.compute(for: land, geography: geography, temperature: temperature, settings: settings.rain)
		let packed = try PackedMap.generate(for: land)
		let marked = try PackedFeatures.markup(for: packed, width: land.width, height: land.height)
		let system = try Rivers.generate(packed: packed, features: marked, precipitation: precipitation, temperature: temperature, cellsDesired: land.cellsDesired, width: land.width, height: land.height, settings: settings.rivers, policy: policy)
		let final = PackedMap(points: packed.points, gridCell: packed.gridCell, heights: system.heights, areas: packed.areas, voronoi: packed.voronoi)
		return WaterMap(land: land, settings: settings, geography: geography, temperature: temperature, precipitation: precipitation, packed: final, features: system.features, flux: system.flux, riverIds: system.riverIds, confluence: system.confluence, rivers: system.rivers)
	}

	/// The fingerprint of the geography this water map was made on (see `LandMap.fingerprint`): the same land and sea, whatever the water or the realms.
	public var fingerprint: String { land.fingerprint }

	/// This water map with these pins on its land map (validated as `LandMap.settingPins` does; nothing changes if they are not). The water, the climate and the rivers are unchanged.
	public func settingPins(_ pins: [MapPin]) throws -> WaterMap {
		WaterMap(land: try land.settingPins(pins), settings: settings, geography: geography, temperature: temperature, precipitation: precipitation, packed: packed, features: features, flux: flux, riverIds: riverIds, confluence: confluence, rivers: rivers)
	}

	/// This water map with this realm layer on its land map, **validated against the land as `LandMap.adding(_:)` does; nothing changes if it fails.** The water, the
	/// climate, the rivers and the pins are unchanged: realms do not depend on them, so nothing is made again.
	public func adding(_ layer: RealmLayer) throws -> WaterMap {
		WaterMap(land: try land.adding(layer), settings: settings, geography: geography, temperature: temperature, precipitation: precipitation, packed: packed, features: features, flux: flux, riverIds: riverIds, confluence: confluence, rivers: rivers)
	}

	// MARK: Saving and loading

	/// The map as a saved record (the exact state).
	public var saved: SavedWaterMap {
		SavedWaterMap(
			land: land.saved, settings: settings, geography: geography, temperature: temperature, precipitation: precipitation,
			packedPoints: packed.points, packedGridCell: packed.gridCell, packedHeights: packed.heights, packedAreas: packed.areas,
			featureIds: features.featureIds, distanceField: features.distanceField, haven: features.haven, harbor: features.harbor,
			features: features.features.map(SavedWaterFeature.init), flux: flux, riverIds: riverIds, confluence: confluence, rivers: rivers
		)
	}

	/// The map as JSON with sorted keys (the same bytes for the same map in the environment this is tested in).
	public func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try encoder.encode(saved)
	}

	/// The same file compressed with LZFSE (about a third of the size; Apple platforms). `init(decoding:)` reads either form.
	public func compressedEncoded() throws -> Data { try SavedFileCompression.compress(try encoded()) }

	/// Loads a saved water map. Everything is validated; only the cells of the land map and of the packed graph are rebuilt from their
	/// points. **Nothing else is recomputed, and no generation step is run again.**
	public init(decoding data: Data) throws {
		try self.init(decoding: data, decompressedLimit: SavedFileCompression.maximumDecompressedBytes)
	}

	/// With the limit on a compressed file's decompressed size (the tests lower it).
	init(decoding data: Data, decompressedLimit: Int) throws {
		let json = SavedFileCompression.isCompressed(data) ? try SavedFileCompression.decompress(data, limit: decompressedLimit) : data
		try self.init(saved: JSONDecoder().decode(SavedWaterMap.self, from: json))
	}

	public init(saved: SavedWaterMap) throws {
		try saved.validateShape()
		let land = try LandMap(saved: saved.land)
		let n = land.grid.points.count
		guard saved.settings.isValid() else { throw SavedWaterMapError.invalidSettings }
		// the coordinates are what the size and the shifts give: a different box would be another algorithm under the same revision
		guard let box = try? Geography.calculate(mapSize: saved.geography.mapSize, latitude: saved.geography.latitude, longitude: saved.geography.longitude, width: land.width, height: land.height), box == saved.geography.coordinates else { throw SavedWaterMapError.invalidGeography }
		guard saved.temperature.count == n, saved.precipitation.count == n else { throw SavedWaterMapError.climateCountsDiffer }

		let m = saved.packedPoints.count
		guard saved.packedGridCell.count == m, saved.packedHeights.count == m, saved.packedAreas.count == m, saved.featureIds.count == m, saved.distanceField.count == m,
			saved.haven.count == m, saved.harbor.count == m, saved.flux.count == m, saved.riverIds.count == m, saved.confluence.count == m else { throw SavedWaterMapError.packedCountsDiffer }
		guard m > 0, m + land.grid.boundary.count <= VoronoiDiagram.maximumInputPoints else { throw SavedWaterMapError.packedCountsDiffer }
		for (i, p) in saved.packedPoints.enumerated() {
			guard p.x.isFinite, p.y.isFinite, p.x >= 0, p.x <= land.width, p.y >= 0, p.y <= land.height else { throw SavedWaterMapError.invalidPackedCell(index: i) }
			guard saved.packedGridCell[i] >= 0, saved.packedGridCell[i] < n, saved.packedHeights[i] <= Heights.maximum else { throw SavedWaterMapError.invalidPackedCell(index: i) }
		}
		let voronoi: VoronoiDiagram
		do { voronoi = try VoronoiDiagram.calculate(points: saved.packedPoints, boundary: land.grid.boundary) } catch { throw SavedWaterMapError.packedCellsCouldNotBeBuilt }
		// the areas are derived from the cells: they must be what the rebuilt cells give
		for i in 0..<m where PackedMap.storedArea(voronoi.cells.v[i].map { voronoi.vertices.p[$0] }) != saved.packedAreas[i] { throw SavedWaterMapError.packedCellsDoNotMatch(index: i) }
		let packed = PackedMap(points: saved.packedPoints, gridCell: saved.packedGridCell, heights: saved.packedHeights, areas: saved.packedAreas, voronoi: voronoi)

		let features = PackedFeatures(distanceField: saved.distanceField, featureIds: saved.featureIds, haven: saved.haven, harbor: saved.harbor, features: saved.features.map(\.feature))
		try Self.validate(saved: saved, packed: packed, features: features, gridCount: n)
		self.init(land: land, settings: saved.settings, geography: saved.geography, temperature: saved.temperature, precipitation: saved.precipitation, packed: packed, features: features, flux: saved.flux, riverIds: saved.riverIds, confluence: saved.confluence, rivers: saved.rivers)
	}

	private init(land: LandMap, settings: WaterSettings, geography: Geography, temperature: [Int8], precipitation: [UInt8], packed: PackedMap, features: PackedFeatures, flux: [UInt16], riverIds: [UInt16], confluence: [UInt16], rivers: [River]) {
		self.land = land; self.settings = settings; self.geography = geography; self.temperature = temperature; self.precipitation = precipitation
		self.packed = packed; self.features = features; self.flux = flux; self.riverIds = riverIds; self.confluence = confluence; self.rivers = rivers
	}

	/// The saved features, ids, distances, havens, harbours and rivers against the rebuilt cells.
	private static func validate(saved: SavedWaterMap, packed: PackedMap, features: PackedFeatures, gridCount: Int) throws {
		let m = packed.points.count
		let neighbours = packed.voronoi.cells.c
		// the structure the river generator relies on (neighbour counts, feature ids, water in water features, havens, lake shores)
		guard !features.features.isEmpty, features.features.count <= Int(UInt16.max),
			features.features.enumerated().allSatisfy({ $0.element.id == $0.offset + 1 && $0.element.land == ($0.element.kind == .island) }) else { throw SavedWaterMapError.invalidFeature(id: 0) }
		do { try Rivers.validateStructure(packed: packed, features: features, gridCount: gridCount) } catch { throw SavedWaterMapError.structureInvalid }
		var counts = [Int](repeating: 0, count: features.features.count + 1)
		for i in 0..<m {
			counts[Int(features.featureIds[i])] += 1
			guard features.distanceField[i] >= -10, Int(features.harbor[i]) <= neighbours[i].count else { throw SavedWaterMapError.invalidPackedCell(index: i) }
		}
		let riverIds = Set(saved.rivers.map(\.id))
		guard riverIds.count == saved.rivers.count, saved.rivers.allSatisfy({ $0.id >= 1 && $0.id <= Int(UInt16.max) }) else { throw SavedWaterMapError.invalidRiver(id: 0) }
		let vertexCount = packed.voronoi.vertices.p.count
		for f in features.features {
			// every record's first cell is in range and carries the record's own number
			let finite = [f.area, f.height, f.flux, f.temp, f.evaporation].allSatisfy(\.isFinite)
			guard finite, f.cells == counts[f.id], f.firstCell >= 0, f.firstCell < m, Int(features.featureIds[f.firstCell]) == f.id, f.vertices.allSatisfy({ $0 >= 0 && $0 < vertexCount }), f.shoreline.allSatisfy({ $0 >= 0 && $0 < m }),
				f.kind == .lake || ((f.inlets ?? []).isEmpty && f.outlet == nil),
				(f.inlets ?? []).allSatisfy({ riverIds.contains($0) }), f.outlet.map({ riverIds.contains($0) }) ?? true else { throw SavedWaterMapError.invalidFeature(id: f.id) }
		}
		for r in saved.rivers {
			// the parent is a river number: it can be the river's own number, or one of a short river the generator dropped, so it is only bounded
			// source and mouth are cells (their upper bound follows from the cells' range, since they are entries of the list)
			let finite = [r.discharge, r.length, r.width, r.widthFactor, r.sourceWidth].allSatisfy { $0.isFinite && $0 >= 0 }
			guard finite, r.cells.count >= 3, r.cells.allSatisfy({ $0 >= -1 && $0 < m }), r.source >= 0, r.mouth >= 0, r.source == r.cells[0], r.mouth == r.cells[r.cells.count - 2],
				r.parent >= 0, r.parent <= Int(UInt16.max) else { throw SavedWaterMapError.invalidRiver(id: r.id) }
		}
		for i in 0..<m where saved.riverIds[i] != 0 && !riverIds.contains(Int(saved.riverIds[i])) { throw SavedWaterMapError.invalidPackedCell(index: i) }
	}
}

extension WaterMap: Equatable {
	/// Two maps are equal when everything saved is equal (the cells are derived and not compared).
	public static func == (a: WaterMap, b: WaterMap) -> Bool {
		a.land == b.land && a.settings == b.settings && a.geography == b.geography && a.temperature == b.temperature && a.precipitation == b.precipitation
			&& a.packed.points == b.packed.points && a.packed.gridCell == b.packed.gridCell && a.packed.heights == b.packed.heights && a.packed.areas == b.packed.areas
			&& a.features == b.features && a.flux == b.flux && a.riverIds == b.riverIds && a.confluence == b.confluence && a.rivers == b.rivers
	}
}
