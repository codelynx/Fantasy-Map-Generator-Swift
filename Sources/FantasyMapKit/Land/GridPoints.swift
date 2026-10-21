// Ported from the original's src/generators/grid-generator.ts (Azgaar's Fantasy Map Generator, MIT; see
// ACKNOWLEDGEMENTS.md), read at commit 8936c9c: getSpacing, getCellsCount, getBoundaryPoints, getJitteredPoints and the
// start of generate(). The Voronoi cells are step 3.

import Foundation

/// Why the grid points could not be made.
public enum GridPointsError: Error, Equatable, Sendable {
	case invalidSize
	case invalidCellCount
	/// The spacing the size and cell count give is zero, not finite or not representable, so no points can be placed.
	case unusableSpacing
	/// More points than `GridPoints.maximumPoints` would be made; refused before anything is allocated.
	case tooManyPoints
	/// The size and spacing leave no room for any cell point (for example a very thin map and a coarse spacing).
	case noCellPoints
}

/// The first stage of the land: a square grid of points, each shifted at random, plus pseudo-points along the map edge.
///
/// The cell points become the cells; the boundary points clip the outer cells and get no cells of their own, but the
/// cells are built from both sets.
public struct GridPoints: Equatable, Sendable {
	/// The map's size in map units and the cell count asked for, kept with the points so no later stage has to be handed
	/// contradictory copies of them.
	public var width: Double
	public var height: Double
	public var cellsDesired: Int
	/// Distance between points before jittering.
	public var spacing: Double
	/// How many cells fit across and down the map.
	public var cellsX: Int
	public var cellsY: Int
	/// The cell points, row by row.
	public var points: [Point]
	/// The boundary pseudo-points.
	public var boundary: [Point]

	/// A provisional safety ceiling on the cell points and, **separately**, on the boundary points: each is limited to
	/// this many, so it does **not** bound the combined input to the triangulation (step 3 budgets that, and its working
	/// arrays). It is not a performance claim or a recommended size. Twice the original's largest density step (100,000
	/// cells).
	///
	/// It is checked from an **estimate** made before any array exists, and the estimate is conservative: it can refuse a
	/// map whose actual point count would just fit, so `tooManyPoints` is not proof that the actual count exceeds the
	/// limit. A final cap while points are appended backs it up. A caller may impose a smaller limit of its own.
	public static let maximumPoints = 200_000

	/// Makes the points for a map, as the original's `Grid.generate` does before it builds the cells: the generator is
	/// seeded from `seed` first, the jitter draws two values per point (x, then y) in row order, and nothing else draws.
	///
	/// - Parameters:
	///   - cellsDesired: the number of cells asked for; the number made is close but not equal.
	public static func generate(seed: String, width: Double, height: Double, cellsDesired: Int) throws -> GridPoints {
		let spacing = try Self.preflight(width: width, height: height, cellsDesired: cellsDesired)

		var random = Alea(seed: seed)
		let boundary = Self.boundaryPoints(width: width, height: height, spacing: spacing)
		let points = try Self.jitteredPoints(width: width, height: height, spacing: spacing, random: &random)
		guard !points.isEmpty else { throw GridPointsError.noCellPoints }
		return GridPoints(
			width: width,
			height: height,
			cellsDesired: cellsDesired,
			spacing: spacing,
			cellsX: Self.cellsCount(spacing: spacing, size: width),
			cellsY: Self.cellsCount(spacing: spacing, size: height),
			points: points,
			boundary: boundary
		)
	}

	/// The checks that must pass before any counting loop runs or any array is built from a size and a cell count, shared by
	/// generation and by loading a saved map (whose size and cell count are untrusted input). Returns the spacing. Nothing here
	/// loops over cells: the counts are estimated in floating point from the size and the spacing, so a size and cell count
	/// that imply excessive work are refused before any enumeration. The arithmetic for accepted maps is unchanged.
	static func preflight(width: Double, height: Double, cellsDesired: Int) throws -> Double {
		guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw GridPointsError.invalidSize }
		guard cellsDesired > 0 else { throw GridPointsError.invalidCellCount }

		let spacing = Self.spacing(cellsDesired: cellsDesired, width: width, height: height)
		guard spacing.isFinite, spacing > 0 else { throw GridPointsError.unusableSpacing }
		// estimate the counts in floating point first, so nothing is allocated, looped over or converted to Int unsafely
		let limit = Double(Self.maximumPoints)
		let estimatedCellPoints = (width / spacing + 1) * (height / spacing + 1)
		let estimatedBoundaryPoints = 2 * ((width / spacing + 1) + (height / spacing + 1)) // boundary spacing is twice the grid's
		guard estimatedCellPoints.isFinite, estimatedBoundaryPoints.isFinite,
			estimatedCellPoints <= limit, estimatedBoundaryPoints <= limit else { throw GridPointsError.tooManyPoints }
		guard spacing / 2 < height, spacing / 2 < width else { throw GridPointsError.noCellPoints }
		return spacing
	}

	/// The original's `getSpacing`: `rn(sqrt(width * height / cellsDesired), 2)`.
	static func spacing(cellsDesired: Int, width: Double, height: Double) -> Double {
		JSNumber.rn((width * height / Double(cellsDesired)).squareRoot(), 2)
	}

	/// The original's `getCellsCount`: how many cells fit the given map dimension.
	static func cellsCount(spacing: Double, size: Double) -> Int {
		let count = ((size + 0.5 * spacing - 1e-10) / spacing).rounded(.down)
		return count.isFinite && abs(count) < 1e15 ? Int(count) : 0
	}

	/// The original's `getBoundaryPoints`: pseudo-points along the map edge, outside it by `|offset|` map units, where
	/// the offset is the spacing rounded to a whole number (`rn(-spacing)`), so "one spacing" only approximately.
	static func boundaryPoints(width: Double, height: Double, spacing: Double) -> [Point] {
		let offset = JSNumber.rn(-1 * spacing)
		let bSpacing = spacing * 2
		let w = width - offset * 2
		let h = height - offset * 2
		let numberX = (w / bSpacing).rounded(.up) - 1
		let numberY = (h / bSpacing).rounded(.up) - 1
		var points: [Point] = []

		var i = 0.5
		while i < numberX {
			let x = ((w * i) / numberX + offset).rounded(.up)
			points.append(Point(x: x, y: offset))
			points.append(Point(x: x, y: h + offset))
			i += 1
		}

		i = 0.5
		while i < numberY {
			let y = ((h * i) / numberY + offset).rounded(.up)
			points.append(Point(x: offset, y: y))
			points.append(Point(x: w + offset, y: y))
			i += 1
		}
		return points
	}

	/// The original's `getJitteredPoints`: a square grid of points, each shifted within its square by up to 90 % of
	/// half the spacing. `x` and `y` are accumulated by repeated addition, as the original's loops do, so the same
	/// floating-point values result.
	static func jitteredPoints(width: Double, height: Double, spacing: Double, random: inout Alea) throws -> [Point] {
		let radius = spacing / 2
		let jittering = radius * 0.9
		let doubleJittering = jittering * 2

		var points: [Point] = []
		var y = radius
		while y < height {
			var x = radius
			while x < width {
				let jitterX = random.next() * doubleJittering - jittering // x first, then y, as the original evaluates them
				let jitterY = random.next() * doubleJittering - jittering
				points.append(Point(
					x: min(JSNumber.rn(x + jitterX, 2), width),
					y: min(JSNumber.rn(y + jitterY, 2), height)
				))
				// the final backstop behind the estimate: it changes neither the order nor the arithmetic of accepted maps
				guard points.count <= Self.maximumPoints else { throw GridPointsError.tooManyPoints }
				x += spacing
			}
			y += spacing
		}
		return points
	}

	/// How many cell points the loops would make, counted the way they walk (no allocation, no random numbers). Used to
	/// show that the admission estimate is conservative.
	static func exactCellPointCount(width: Double, height: Double, spacing: Double) -> Int {
		var rows = 0
		var y = spacing / 2
		while y < height { rows += 1; y += spacing }
		var columns = 0
		var x = spacing / 2
		while x < width { columns += 1; x += spacing }
		return rows * columns
	}
}
