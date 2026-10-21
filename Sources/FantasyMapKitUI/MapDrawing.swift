import FantasyMapKit
import Foundation

/// One stroked line, in map units; its width is in map units too, so it scales with the map.
public struct InkCommand: Equatable, Sendable {
	public var points: [Point]
	public var isClosed: Bool
	public var color: MapColor
	public var width: Double
	/// The dash pattern in map units (on, off, on, off ...), or empty for a solid line.
	public var dash: [Double] = []
}

/// One filled polygon, in map units.
public struct FillCommand: Equatable, Sendable {
	public var points: [Point]
	public var color: MapColor
	/// The cell this polygon fills (stage 1 draws one polygon per cell).
	public var cell: Int
	/// Whether the cell is land (height 20 or more).
	public var isLand: Bool
}

/// What to draw for a map, as plain geometry and colours: the single description both the SwiftUI view and the image renderer
/// execute, so they cannot disagree. Nothing here draws.
///
/// Stage 1 (the height picture): one filled polygon per cell, clipped to the map's rectangle, coloured by the cell's height
/// (land) or by its coast distance (water).
///
/// **Frame coverage.** A cell's Voronoi region is cut short by the boundary pseudo-points that clip the outer cells, and in
/// places that leaves a thin sliver of the rectangle that no cell covers. So each edge a cell shares with a **boundary
/// point** is extended outward, each end along the ray from the cell's point through it, before the polygon is clipped to the rectangle: the cell takes the
/// sliver next to it, never a rectangle of one colour laid underneath (which would be wrong where land reaches the frame).
/// The core map is not changed. Extended border cells overlap each other near the frame (measured on the tested grid: 0.054% of
/// pixels, within four spacings of it); the later cell in cell order paints over the earlier one there. These polygons are
/// diagnostic drawing geometry, not coastline topology.
public struct MapDrawing: Equatable, Sendable {
	/// The map's size in map units.
	public var width: Double
	public var height: Double
	/// The grid's spacing in map units: how large the cells are, which the view's zoom limit follows.
	public var cellSpacing: Double
	/// The colour behind the map.
	public var paper: MapColor
	/// The polygons, in cell order.
	public var fills: [FillCommand]
	/// The coast as the cells give it (stage 2a), unsmoothed: closed land rings and open or closed ink lines. See `CoastOutlines`.
	public var coast: CoastOutlines
	/// The land silhouette (stage 2b): closed rings, land on the left, the same outline the ink follows. When it is not nil the
	/// water cells are drawn as they are, and the land (`exposed` first, then the land cells' `fills`) is drawn **clipped to these
	/// rings** with the even-odd rule. It is nil when the frame closure was inconsistent, and then every fill is drawn as in stage 1.
	public var landClip: [[Point]]?
	/// Water cells next to land, in the colour of their nearest land neighbour: they paint land that smoothing newly exposes
	/// (concave coasts move into them). Only used inside `landClip`, under the land cells, so existing land colours are kept.
	public var exposed: [FillCommand]
	/// The other side of the changed boundary (stage 2b): land cells next to water, in the colour of their nearest water neighbour.
	/// Smoothing cuts convex land corners, and that area is outside the land clip but inside an original land cell, so these are
	/// drawn **first, under the water cells**, wherever `landClip` is used. Without them the paper would show there.
	public var receded: [FillCommand]
	/// The rivers of a water map as filled polygons, trimmed to the land outline (`landClip`) and extended to it; drawn over the land and under the ink.
	/// Empty when the drawing was made from a land map alone. `riversSkipped` counts rivers left out for a limit, and `riversInWater` rivers with nothing left on the drawn land (wholly in drawn water, or cut to fewer than three points).
	/// The realms (see `RealmDrawing`): the wash, as opaque polygons in each realm's colour that are drawn **together at the wash opacity**, clipped to the land
	/// outline, under the rivers; and the dashed border lines between realms, over the rivers. Empty when no ownership was given.
	public var realmWash: [FillCommand] = []
	public var realmWashOpacity = 0.0
	public var realmBorders: [InkCommand] = []
	/// Why the map's realm layer was not drawn, if it was not (the style's colours, for example, were refused).
	public var realmProblem: String?
	public var rivers: [RiverFill] = []
	public var riversSkipped = 0
	public var riversInWater = 0
	/// The coastline ink, drawn over the fills; empty when the style's ink width is 0 or its ink is transparent.
	public var ink: [InkCommand]

	/// Builds the drawing of a map.
	public init(map: LandMap, style: MapStyle = .standard) {
		let voronoi = map.voronoi
		var fills: [FillCommand] = []
		fills.reserveCapacity(map.heights.count)
		let cellCount = map.heights.count
		let reach = 2 * map.grid.spacing // far enough to cross any sliver (boundary points sit about one spacing outside the frame)
		for cell in 0..<cellCount {
			let corners = Self.extendedPolygon(cell: cell, cellPoint: map.grid.points[cell], voronoi: voronoi, cellCount: cellCount, reach: reach)
			let clipped = Self.clip(corners, width: map.width, height: map.height)
			guard clipped.count >= 3 else { continue }
			fills.append(FillCommand(points: clipped, color: Self.color(height: map.heights[cell], distance: map.features.distanceField[cell], style: style), cell: cell, isLand: Heights.isLand(map.heights[cell])))
		}
		let coast = CoastOutlines(map: map, smoothing: style.smoothing, roughness: style.roughness)
		self.init(map: map, style: style, coast: coast, fills: fills)
		// a map with a realm layer draws it, with the colours saved with it (a map opened again shows the colours it was saved with)
		if style.showRealms, let layer = map.realms {
			do { try addRealms(layer.ownership, map: map, colors: layer.colors, style: style) } catch { realmProblem = "\(error)" }
		}
	}

	/// The drawing of a map with its realms: the land as above, and the wash and the borders of the realms.
	public init(map: LandMap, ownership: RealmOwnership, style: MapStyle = .standard) throws {
		self.init(map: map, style: style)
		try addRealms(ownership, map: map, style: style)
	}

	/// The drawing of a water map with its realms.
	public init(water: WaterMap, ownership: RealmOwnership, style: MapStyle = .standard) throws {
		self.init(water: water, style: style)
		try addRealms(ownership, map: water.land, style: style)
	}

	/// Adds the realms' wash and borders (throws if the ownership does not describe the map, and then changes nothing). **Internal:** the map must be the one this
	/// drawing was made from, which only the initialisers above can guarantee.
	mutating func addRealms(_ ownership: RealmOwnership, map: LandMap, colors: [RealmColor]? = nil, style: MapStyle) throws {
		let result = try RealmDrawing.build(map: map, ownership: ownership, colors: colors, fills: fills, style: style)
		realmWash = style.realmWashOpacity > 0 ? result.wash : []
		realmWashOpacity = style.realmWashOpacity
		realmBorders = result.borders
	}

	/// The colours the realms of an ownership take in the style: derived by the original's greedy rule (neighbouring realms differ). **An app saves these with the
	/// realms** (`RealmLayer.colors`) so that the map shows the same colours when it is opened again.
	public static func resolvedRealmColors(for map: LandMap, ownership: RealmOwnership, style: MapStyle = .standard) throws -> [RealmColor] {
		guard !style.realmColors.isEmpty else { throw RealmDrawingError.invalidPalette }
		return try RealmDrawing.build(map: map, ownership: ownership, fills: [], style: style).colors
	}

	/// The drawing of a water map: its land as above, and its rivers trimmed to the drawn land (or drawn as generated when the coast is not trusted).
	public init(water: WaterMap, style: MapStyle = .standard) {
		self.init(map: water.land, style: style)
		let result = RiverDrawing.build(water: water, landRings: landClip, style: style)
		rivers = result.fills
		riversSkipped = result.skipped
		riversInWater = result.inWater
	}

	/// The part of the drawing that depends on the coast, split out so a test can hand in a coast whose frame closure is marked
	/// inconsistent.
	init(map: LandMap, style: MapStyle, coast: CoastOutlines, fills: [FillCommand]) {
		width = map.width
		height = map.height
		cellSpacing = map.grid.spacing
		paper = style.paper
		self.fills = fills
		self.coast = coast
		let trusted = coast.frameClosureIsConsistent
		// an inconsistent frame closure means the rings and the ink are not to be trusted: fall back to the stage-1 fills, and
		// draw no coastline either, instead of inking an outline the fill does not follow
		landClip = trusted ? coast.landRings : nil
		ink = trusted && style.inkWidth > 0 && style.ink.alpha > 0
			? coast.ink.map { InkCommand(points: $0.points, isClosed: $0.isClosed, color: style.ink, width: style.inkWidth) } : []
		let cellCount = map.heights.count
		var fillOfCell: [Int: Int] = [:]
		for (index, fill) in fills.enumerated() { fillOfCell[fill.cell] = index }
		/// Cells of one kind that touch the other kind, each in the colour of its nearest neighbour of the other kind.
		func borrowed(landCells: Bool) -> [FillCommand] {
			var result: [FillCommand] = []
			for cell in 0..<cellCount where Heights.isLand(map.heights[cell]) == landCells {
				guard let own = fillOfCell[cell] else { continue }
				let site = map.grid.points[cell]
				var nearest: Int?, best = Double.infinity
				for other in map.voronoi.cells.c[cell] where other < cellCount && Heights.isLand(map.heights[other]) != landCells {
					let p = map.grid.points[other]
					let d = (p.x - site.x) * (p.x - site.x) + (p.y - site.y) * (p.y - site.y)
					if d < best { best = d; nearest = other }
				}
				guard let source = nearest, let from = fillOfCell[source] else { continue }
				result.append(FillCommand(points: fills[own].points, color: fills[from].color, cell: cell, isLand: false))
			}
			return result
		}
		exposed = borrowed(landCells: false) // water cells that smoothing may turn into land
		receded = borrowed(landCells: true) // land cells that smoothing may turn into water
	}

	/// A cell's polygon with every edge it shares with a boundary point pushed outward, each end along the ray from the cell's point through it, by `reach`, so
	/// that clipping to the rectangle leaves no sliver between the cell and the frame. The other edges are untouched.
	static func extendedPolygon(cell: Int, cellPoint: Point, voronoi: VoronoiDiagram, cellCount: Int, reach: Double) -> [Point] {
		let corners = voronoi.cells.v[cell]
		// only a border cell (the diagram flags them) has an edge shared with a boundary point
		guard corners.count >= 3, voronoi.cells.b[cell] != 0 else { return corners.map { voronoi.vertices.p[$0] } }
		var polygon: [Point] = []
		for k in 0..<corners.count {
			let a = corners[k], b = corners[(k + 1) % corners.count]
			let pa = voronoi.vertices.p[a], pb = voronoi.vertices.p[b]
			polygon.append(pa)
			// the point across this edge is the one the two triangles share besides the cell
			let across = Set(voronoi.vertices.c[a]).intersection(voronoi.vertices.c[b]).subtracting([cell])
			guard across.contains(where: { $0 >= cellCount }) else { continue }
			// each end of the edge is pushed outward along the ray from the cell's point through that end: unlike pushing along
			// the edge's normal, this also reaches the wedge at a corner of the frame
			func pushed(_ p: Point) -> Point {
				let dx = p.x - cellPoint.x, dy = p.y - cellPoint.y
				let length = (dx * dx + dy * dy).squareRoot()
				guard length > 0 else { return p }
				return Point(x: p.x + dx / length * reach, y: p.y + dy / length * reach)
			}
			polygon.append(pushed(pa))
			polygon.append(pushed(pb))
		}
		return polygon
	}

	/// The colour of a cell. **Land or water is decided by the height** (land at 20 or more); the coast distance never decides
	/// that. Land is coloured by height from 20 to 100. Water is coloured by coast distance as a display policy, **not depth**:
	/// -1 is the near-coast colour and -9 the far-water colour, with the shades between; **0 takes the far-water colour** (so a map
	/// with no land is one flat colour); **a positive marker on a water cell** (the original can leave one beside a lake) takes
	/// the near-coast colour.
	public static func color(height: Height, distance: Int8, style: MapStyle) -> MapColor {
		if Heights.isLand(height) {
			return style.land.color(at: (Double(height) - 20) / 80)
		}
		if distance >= 1 { return style.water.color(at: 0) }
		if distance == 0 { return style.water.color(at: 1) }
		return style.water.color(at: (Double(-Int(distance)) - 1) / 8)
	}

	/// A polygon clipped to the rectangle 0 ... width by 0 ... height: the core's shared `RectangleClip`, which the realm geometry
	/// uses too. The cells are convex, and so is the rectangle, so the result is a single polygon, possibly empty.
	static func clip(_ polygon: [Point], width: Double, height: Double) -> [Point] {
		RectangleClip.clip(polygon, width: width, height: height)
	}
}
