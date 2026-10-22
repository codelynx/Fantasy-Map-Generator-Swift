import Foundation

public enum SavedWaterMapError: Error, Equatable, Sendable {
	case unsupportedFormatVersion(Int)
	case unsupportedAlgorithmRevision(Int)
	/// A setting is out of its range or not finite.
	case invalidSettings
	/// The geography is not finite, or its box is not the one its size and shifts give.
	case invalidGeography
	/// The grid climate does not have one value for each grid cell.
	case climateCountsDiffer
	/// The packed arrays differ in length, or there is no packed cell or too many.
	case packedCountsDiffer
	/// A packed cell with a point outside the map, a grid cell outside the grid, a height above 100, a bad distance or harbour, or a river number that is no river.
	case invalidPackedCell(index: Int)
	/// The packed cells could not be rebuilt from the points.
	case packedCellsCouldNotBeBuilt
	/// The saved area of a packed cell is not the one the rebuilt cell gives (a corrupt file, or an algorithm that changed under the same revision).
	case packedCellsDoNotMatch(index: Int)
	/// The cells, features and heights do not agree (water in a land feature, a haven that is not a neighbouring water cell, a lake without a shore ...).
	case structureInvalid
	/// A feature record (0 for the table as a whole) that is inconsistent.
	case invalidFeature(id: Int)
	/// A river record (0 for the list as a whole) that is inconsistent.
	case invalidRiver(id: Int)
	/// The compressed file is not a valid LZFSE stream, or it is cut short.
	case invalidCompression
	/// The compressed file would expand past the limit.
	case decompressedTooLarge
	/// Compression is not available on this platform.
	case compressionUnavailable
}

/// A lake's or feature's record as the rivers leave it: the temporary fields (`closed`, `outCell`, `river`, `enteringFlux`) are gone.
public struct SavedWaterFeature: Codable, Equatable, Sendable {
	public var id: Int
	public var kind: FeatureKind
	public var land: Bool
	public var border: Bool
	public var cells: Int
	public var firstCell: Int
	public var vertices: [Int]
	public var area: Double
	public var shoreline: [Int]
	public var height: Double
	public var flux: Double, temp: Double, evaporation: Double
	public var inlets: [Int]?
	public var outlet: Int?

	init(_ f: PackedFeature) {
		id = f.id; kind = f.kind; land = f.land; border = f.border; cells = f.cells; firstCell = f.firstCell; vertices = f.vertices
		area = f.area; shoreline = f.shoreline; height = f.height; flux = f.flux; temp = f.temp; evaporation = f.evaporation
		inlets = f.inlets; outlet = f.outlet
	}

	var feature: PackedFeature {
		var f = PackedFeature(id: id, kind: kind, land: land, border: border, cells: cells, firstCell: firstCell, vertices: vertices, area: area, shoreline: shoreline, height: height)
		f.flux = flux; f.temp = temp; f.evaporation = evaporation; f.inlets = inlets; f.outlet = outlet
		return f
	}
}

/// The saved form of a water map: **the exact state**, with the land map inside (one file, decided 2026-10-21). The packed cells'
/// neighbours and corners are rebuilt on load, and nothing else is recomputed.
public struct SavedWaterMap: Codable, Equatable, Sendable {
	public static let supportedFormatVersions = [1]
	public static let supportedAlgorithmRevisions = [1]
	public static let currentFormatVersion = 1
	public static let currentAlgorithmRevision = 1

	public var formatVersion = SavedWaterMap.currentFormatVersion
	public var algorithmRevision = SavedWaterMap.currentAlgorithmRevision
	public var land: SavedLandMap
	public var settings: WaterSettings
	public var geography: Geography
	public var temperature: [Int8]
	public var precipitation: [UInt8]
	public var packedPoints: [Point]
	public var packedGridCell: [Int]
	public var packedHeights: [Height]
	public var packedAreas: [UInt16]
	public var featureIds: [UInt16]
	public var distanceField: [Int8]
	public var haven: [Int]
	public var harbor: [UInt8]
	public var features: [SavedWaterFeature]
	public var flux: [UInt16]
	public var riverIds: [UInt16]
	public var confluence: [UInt16]
	public var rivers: [River]

	/// The version checks, made before anything else is read.
	func validateShape() throws {
		guard Self.supportedFormatVersions.contains(formatVersion) else { throw SavedWaterMapError.unsupportedFormatVersion(formatVersion) }
		guard Self.supportedAlgorithmRevisions.contains(algorithmRevision) else { throw SavedWaterMapError.unsupportedAlgorithmRevision(algorithmRevision) }
	}
}
