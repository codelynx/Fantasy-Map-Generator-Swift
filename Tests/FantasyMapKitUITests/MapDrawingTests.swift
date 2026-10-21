import CoreGraphics
import FantasyMapKit
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKitUI

/// Stage 1 of docs/design-drawing.md: the height picture, its geometry and its image renderer.
struct MapDrawingTests {
	func map(_ key: String = "highIsland", seed: String = "kaz-1", width: Double = 400, height: Double = 300, cells: Int = 800) throws -> LandMap {
		try LandMap.generate(seed: seed, width: width, height: height, cellsDesired: cells, template: try #require(HeightmapTemplate.named(key)))
	}

	/// A map with every cell the same height, kept consistent (one feature, no coast), to test the flat cases.
	func flat(height value: Height, border: Bool = true) throws -> LandMap {
		var saved = try map().saved
		let land = Heights.isLand(value)
		saved.heights = [Height](repeating: value, count: saved.heights.count)
		saved.featureIds = [UInt16](repeating: 1, count: saved.heights.count)
		saved.coastDistance = [Int8](repeating: 0, count: saved.heights.count)
		saved.features = [SavedFeature(Feature(id: 1, land: land, border: border, kind: land ? .island : .ocean))]
		return try LandMap(saved: saved)
	}

	/// Midpoints of edges that two cell polygons really share (the cell across is a cell point, not a boundary point), well away
	/// from the frame so that the frame extension is not involved. Each is `(midpoint, cellA, cellB)`.
	func sharedEdgeMidpoints(_ m: LandMap, limit: Int) -> [(Point, Int, Int)] {
		var found: [(Point, Int, Int)] = []
		let v = m.voronoi
		let margin = 5 * m.grid.spacing
		for cell in 0..<m.heights.count where v.cells.b[cell] == 0 {
			let corners = v.cells.v[cell]
			for k in 0..<corners.count {
				let a = corners[k], b = corners[(k + 1) % corners.count]
				let across = Set(v.vertices.c[a]).intersection(v.vertices.c[b]).subtracting([cell])
				guard let other = across.first, across.count == 1, other < m.heights.count, other > cell else { continue }
				let mid = Point(x: (v.vertices.p[a].x + v.vertices.p[b].x) / 2, y: (v.vertices.p[a].y + v.vertices.p[b].y) / 2)
				guard mid.x > margin, mid.x < m.width - margin, mid.y > margin, mid.y < m.height - margin else { continue }
				found.append((mid, cell, other))
				if found.count >= limit { return found }
			}
		}
		return found
	}

	func area(_ polygon: [Point]) -> Double {
		var sum = 0.0
		for (a, b) in zip(polygon, polygon.dropFirst() + [polygon[0]]) { sum += a.x * b.y - b.x * a.y }
		return abs(sum) / 2
	}

	// MARK: geometry

	@Test func everyCellIsDrawnInsideTheMapAsAProperPolygon() throws {
		for key in ["highIsland", "archipelago", "shattered"] {
			let m = try map(key)
			let drawing = MapDrawing(map: m)
			#expect(drawing.fills.count == m.heights.count, "\(key): one polygon per cell")
			#expect(drawing.fills.map(\.cell) == Array(0..<m.heights.count))
			for fill in drawing.fills {
				#expect(fill.points.count >= 3)
				#expect(fill.points.allSatisfy { $0.x >= -1e-9 && $0.x <= m.width + 1e-9 && $0.y >= -1e-9 && $0.y <= m.height + 1e-9 }, "\(key): cell \(fill.cell) inside the map")
				#expect(area(fill.points) > 0, "\(key): cell \(fill.cell) has area")
			}
		}
	}

	@Test func clippingKeepsWhatIsInsideAndCutsWhatIsOutside() {
		let square = [Point(x: -10, y: -10), Point(x: 30, y: -10), Point(x: 30, y: 30), Point(x: -10, y: 30)]
		let clipped = MapDrawing.clip(square, width: 20, height: 20)
		#expect(abs(area(clipped) - 400) < 1e-9)
		#expect(clipped.allSatisfy { $0.x >= 0 && $0.x <= 20 && $0.y >= 0 && $0.y <= 20 })
		let inside = [Point(x: 1, y: 1), Point(x: 5, y: 1), Point(x: 3, y: 4)]
		#expect(MapDrawing.clip(inside, width: 20, height: 20) == inside)
		let outside = [Point(x: 30, y: 30), Point(x: 40, y: 30), Point(x: 35, y: 40)]
		#expect(MapDrawing.clip(outside, width: 20, height: 20).isEmpty)
		#expect(MapDrawing.clip([], width: 20, height: 20).isEmpty)
	}

	// MARK: coverage of the rectangle

	/// Even-odd point-in-polygon.
	func contains(_ polygon: [Point], _ x: Double, _ y: Double) -> Bool {
		var inside = false
		var j = polygon.count - 1
		for i in 0..<polygon.count {
			let a = polygon[i], b = polygon[j]
			if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
			j = i
		}
		return inside
	}

	/// Every sample point in the rectangle is inside at least one cell polygon; returns the points that are not. Samples run
	/// along the whole perimeter (just inside the frame, where the defect was) and over a grid of the interior.
	func uncovered(_ drawing: MapDrawing) -> [Point] {
		let boxes = drawing.fills.map { fill -> (minX: Double, maxX: Double, minY: Double, maxY: Double) in
			(fill.points.map(\.x).min()!, fill.points.map(\.x).max()!, fill.points.map(\.y).min()!, fill.points.map(\.y).max()!)
		}
		var samples: [Point] = []
		let inset = 1e-6
		var t = 0.0
		// every sample is at least `inset` inside the frame on both axes: a point exactly on a polygon's edge is outside
		// under the even-odd rule used here, which says nothing about coverage
		func clamped(_ v: Double, _ limit: Double) -> Double { min(max(v, inset), limit - inset) }
		while t <= drawing.width { samples.append(Point(x: clamped(t, drawing.width), y: inset)); samples.append(Point(x: clamped(t, drawing.width), y: drawing.height - inset)); t += 0.25 }
		t = 0
		while t <= drawing.height { samples.append(Point(x: inset, y: clamped(t, drawing.height))); samples.append(Point(x: drawing.width - inset, y: clamped(t, drawing.height))); t += 0.25 }
		for gx in 0..<120 { for gy in 0..<90 { samples.append(Point(x: (Double(gx) + 0.5) * drawing.width / 120, y: (Double(gy) + 0.5) * drawing.height / 90)) } }
		var missing: [Point] = []
		for p in samples {
			var covered = false
			for (n, fill) in drawing.fills.enumerated() where p.x >= boxes[n].minX && p.x <= boxes[n].maxX && p.y >= boxes[n].minY && p.y <= boxes[n].maxY {
				if contains(fill.points, p.x, p.y) { covered = true; break }
			}
			if !covered { missing.append(p) }
		}
		return missing
	}

	@Test func theWholeFrameAndTheInteriorAreCoveredOnFlatAndMixedMaps() throws {
		// all land, all water, and mixed maps (including land that reaches the frame); sampled along the full perimeter
		var landTouchesFrame = false
		for (label, m) in [("all land", try flat(height: 60)), ("all water", try flat(height: 5)), ("highIsland", try map("highIsland")), ("continents", try map("continents")), ("archipelago", try map("archipelago"))] {
			let drawing = MapDrawing(map: m)
			let missing = uncovered(drawing)
			#expect(missing.isEmpty, "\(label): \(missing.count) sample points are covered by no cell, first at \(String(describing: missing.first))")
			if label != "all water", m.grid.points.indices.contains(where: { Heights.isLand(m.heights[$0]) && (m.grid.points[$0].x < m.grid.spacing || m.grid.points[$0].y < m.grid.spacing || m.grid.points[$0].x > m.width - m.grid.spacing || m.grid.points[$0].y > m.height - m.grid.spacing) }) { landTouchesFrame = true }
		}
		#expect(landTouchesFrame, "the mixed maps include land reaching the frame")
	}

	@Test func theExtensionTakesTheSliverNextToACellNotAnOceanRectangleUnderneath() throws {
		// on an all-land map, a base ocean rectangle would show as water at the frame; with extension every pixel at the frame is land
		let m = try flat(height: 60)
		let drawing = MapDrawing(map: m)
		let image = try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 600)
		let land = MapStyle.standard.land.color(at: 0.5)
		for (x, y) in [(0, 0), (799, 0), (0, 599), (799, 599), (400, 0), (400, 599), (0, 300), (799, 300)] {
			let sampled = try pixel(image, x, y)
			#expect(close(sampled, land), "pixel \(x), \(y) is land colour")
		}
		// the frame has no paper-coloured pixels on a mixed map either
		let mixed = MapDrawing(map: try map("continents"))
		let picture = try MapImage.render(mixed, pixelWidth: 800, pixelHeight: 600)
		var paperPixels = 0
		for y in 0..<600 { for x in [0, 799] { if close(try pixel(picture, x, y), mixed.paper, tolerance: 2.0 / 255) { paperPixels += 1 } } }
		for x in 0..<800 { for y in [0, 599] { if close(try pixel(picture, x, y), mixed.paper, tolerance: 2.0 / 255) { paperPixels += 1 } } }
		#expect(paperPixels == 0, "\(paperPixels) frame pixels show paper")
	}

	// MARK: a raster diagnostic of coverage and overlap

	struct Coverage {
		var width = 0, height = 0
		var uncovered = 0, single = 0, multiple = 0
		var multipleDifferentColour = 0
		var uncoveredOutsideBand = 0, multipleOutsideBand = 0, differentOutsideBand = 0
		var multipleAtCorners = 0
		var worstMultiplicity = 0
		var deepestOverlap = 0.0 // furthest an overlapping pixel centre lies from the frame, in map units
		var total: Int { width * height }
	}

	/// Counts, for each pixel centre of a raster at `scale` pixels per map unit, how many polygons cover it. "Band" is the strip of
	/// width `band` along the frame; corners are where two bands meet.
	func coverage(_ drawing: MapDrawing, scale: Double, band: Double) -> Coverage {
		var c = Coverage()
		c.width = Int((drawing.width * scale).rounded(.up)); c.height = Int((drawing.height * scale).rounded(.up))
		var count = [UInt8](repeating: 0, count: c.width * c.height)
		var first = [Int32](repeating: -1, count: c.width * c.height)
		var differs = [Bool](repeating: false, count: c.width * c.height)
		for (n, fill) in drawing.fills.enumerated() {
			let ys = fill.points.map(\.y)
			let rowMin = max(0, Int((ys.min()! * scale - 0.5).rounded(.up))), rowMax = min(c.height - 1, Int((ys.max()! * scale - 0.5).rounded(.down)))
			guard rowMin <= rowMax else { continue }
			for row in rowMin...rowMax {
				let y = (Double(row) + 0.5) / scale
				var crossings: [Double] = []
				var j = fill.points.count - 1
				for i in 0..<fill.points.count {
					let a = fill.points[i], b = fill.points[j]
					if (a.y > y) != (b.y > y) { crossings.append((b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) }
					j = i
				}
				crossings.sort()
				var k = 0
				while k + 1 < crossings.count {
					let from = max(0, Int((crossings[k] * scale - 0.5).rounded(.up))), to = min(c.width - 1, Int((crossings[k + 1] * scale - 0.5).rounded(.down)))
					if from <= to {
						for col in from...to {
							let p = row * c.width + col
							if count[p] == 0 { first[p] = Int32(n) } else if drawing.fills[Int(first[p])].color != fill.color { differs[p] = true }
							count[p] &+= 1
						}
					}
					k += 2
				}
			}
		}
		for row in 0..<c.height {
			for col in 0..<c.width {
				let p = row * c.width + col
				let x = (Double(col) + 0.5) / scale, y = (Double(row) + 0.5) / scale
				let nearX = x < band || x > drawing.width - band, nearY = y < band || y > drawing.height - band
				let inBand = nearX || nearY
				if count[p] == 0 { c.uncovered += 1; if !inBand { c.uncoveredOutsideBand += 1 } }
				else if count[p] == 1 { c.single += 1 }
				else {
					c.multiple += 1
					c.worstMultiplicity = max(c.worstMultiplicity, Int(count[p]))
					c.deepestOverlap = max(c.deepestOverlap, min(x, drawing.width - x, y, drawing.height - y))
					if nearX && nearY { c.multipleAtCorners += 1 }
					if !inBand { c.multipleOutsideBand += 1 }
					if differs[p] { c.multipleDifferentColour += 1; if !inBand { c.differentOutsideBand += 1 } }
				}
			}
		}
		return c
	}

	@Test func aRasterCoverageDiagnosticMeasuresUncoveredAndMultiplyCoveredPixels() throws {
		// at 2 pixels per map unit, on flat and mixed maps; "band" is four spacings: border cells reach about 1.5 spacings inward and the extension adds 2 (deepest overlap measured 3.9)
		for (label, m) in [("all land", try flat(height: 60)), ("all water", try flat(height: 5)), ("highIsland", try map("highIsland")), ("continents", try map("continents")), ("archipelago", try map("archipelago")), ("shattered", try map("shattered"))] {
			let c = coverage(MapDrawing(map: m), scale: 2, band: 4 * m.grid.spacing)
			print("COVERAGE \(label): \(c.width)x\(c.height) pixels, uncovered \(c.uncovered) (\(c.uncoveredOutsideBand) outside the band), single \(c.single), multiple \(c.multiple) (\(String(format: "%.3f", 100 * Double(c.multiple) / Double(c.total)))%; worst \(c.worstMultiplicity); deepest overlap \(String(format: "%.2f", c.deepestOverlap / m.grid.spacing)) spacings from the frame; \(c.multipleOutsideBand) outside the band; \(c.multipleAtCorners) at corners; \(c.multipleDifferentColour) of different colours, \(c.differentOutsideBand) outside the band)")
			#expect(c.uncovered == 0, "\(label): \(c.uncovered) uncovered pixels")
			#expect(c.multipleOutsideBand == 0, "\(label): overlap outside the frame band")
			#expect(c.multiple < c.total / 50, "\(label): \(c.multiple) of \(c.total) pixels are covered more than once")
		}
	}

	// MARK: colours

	@Test func landAndWaterAreDecidedByHeightAndWaterIsShadedByCoastDistanceAsADisplayPolicy() {
		let style = MapStyle.standard
		let near = style.water.color(at: 0), far = style.water.color(at: 1)
		// water: -1 is near, -9 is far, 0 is far, and a positive marker on a water cell is near, not an unexplained dark patch
		#expect(MapDrawing.color(height: 10, distance: -1, style: style) == near)
		#expect(MapDrawing.color(height: 10, distance: -9, style: style) == far)
		#expect(MapDrawing.color(height: 10, distance: 0, style: style) == far)
		#expect(MapDrawing.color(height: 19, distance: 1, style: style) == near)
		let mid = MapDrawing.color(height: 10, distance: -5, style: style)
		#expect(mid != near && mid != far && mid == style.water.color(at: 0.5))
		// the distance never decides land or water: a land cell with a negative or zero distance is still land
		#expect(MapDrawing.color(height: 20, distance: -3, style: style) == style.land.color(at: 0))
		#expect(MapDrawing.color(height: 100, distance: 0, style: style) == style.land.color(at: 1))
		#expect(MapDrawing.color(height: 60, distance: 1, style: style) == style.land.color(at: 0.5))
		// sea level: 19 is water, 20 is land
		#expect(MapDrawing.color(height: 19, distance: -1, style: style) == near)
		#expect(MapDrawing.color(height: 20, distance: -1, style: style) == style.land.color(at: 0))
	}

	@Test func aColourScaleBlendsBetweenStopsAndClampsAtTheEnds() {
		let scale = ColorScale(stops: [.init(0, MapColor(red: 0, green: 0, blue: 0)), .init(1, MapColor(red: 1, green: 0.5, blue: 0.25, alpha: 0.5))])
		#expect(scale.color(at: 0) == MapColor(red: 0, green: 0, blue: 0))
		#expect(scale.color(at: 1) == MapColor(red: 1, green: 0.5, blue: 0.25, alpha: 0.5))
		#expect(scale.color(at: 0.5) == MapColor(red: 0.5, green: 0.25, blue: 0.125, alpha: 0.75))
		#expect(scale.color(at: -3) == scale.color(at: 0) && scale.color(at: 7) == scale.color(at: 1) && scale.color(at: .nan) == scale.color(at: 0))
		#expect(ColorScale(stops: []).color(at: 0.5) == MapColor(red: 0, green: 0, blue: 0))
	}

	@Test func anAllWaterMapIsOneFlatColourAndAnAllLandMapIsOneHeightColour() throws {
		let water = MapDrawing(map: try flat(height: 5))
		#expect(Set(water.fills.map(\.color)).count == 1 && water.fills[0].color == MapStyle.standard.water.color(at: 1))
		let land = MapDrawing(map: try flat(height: 60))
		#expect(Set(land.fills.map(\.color)).count == 1 && land.fills[0].color == MapStyle.standard.land.color(at: 0.5))
	}

	@Test func aRealMapUsesBothLandAndWaterColoursAndMatchesTheHeightsCellByCell() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		for fill in drawing.fills {
			let expected = MapDrawing.color(height: m.heights[fill.cell], distance: m.features.distanceField[fill.cell], style: .standard)
			#expect(fill.color == expected)
		}
		let land = drawing.fills.filter { Heights.isLand(m.heights[$0.cell]) }.count
		#expect(land > 0 && land < drawing.fills.count)
		// the drawing is a pure function of the map and the style
		#expect(MapDrawing(map: m) == drawing)
		var other = MapStyle.standard
		other.paper = MapColor(red: 1, green: 1, blue: 1)
		#expect(MapDrawing(map: m, style: other).fills == drawing.fills.map { $0 }.self && MapDrawing(map: m, style: other).paper == other.paper)
	}

	// MARK: the image renderer

	func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> (Double, Double, Double, Double) {
		let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		var bytes = [UInt8](repeating: 0, count: 4)
		let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
		return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255, Double(bytes[3]) / 255)
	}

	func close(_ a: (Double, Double, Double, Double), _ c: MapColor, tolerance: Double = 3.0 / 255) -> Bool {
		abs(a.0 - c.red) <= tolerance && abs(a.1 - c.green) <= tolerance && abs(a.2 - c.blue) <= tolerance && abs(a.3 - c.alpha) <= tolerance
	}

	@Test func theImageHasTheRequestedSizeAndEachCellsPointHasItsColour() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		let image = try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 600) // exactly the map's ratio, scale 2
		#expect(image.width == 800 && image.height == 600)
		let f = MapImage.fit(width: m.width, height: m.height, pixelWidth: 800, pixelHeight: 600)
		#expect(f.scale == 2 && f.originX == 0 && f.originY == 0)
		var checked = 0
		for fill in drawing.fills.prefix(200) {
			let p = m.grid.points[fill.cell]
			let x = Int(p.x * f.scale), y = Int(p.y * f.scale)
			guard x >= 1 && y >= 1 && x < 799 && y < 599 else { continue }
			let sampled = try pixel(image, x, y)
			#expect(close(sampled, fill.color), "cell \(fill.cell) at pixel \(x), \(y)")
			checked += 1
		}
		#expect(checked > 100)
	}

	@Test func aWiderBitmapFitsTheMapAndCentresItWithPaperOnBothSides() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		let image = try MapImage.render(drawing, pixelWidth: 1200, pixelHeight: 600) // wider than 4:3: margins left and right
		let f = MapImage.fit(width: m.width, height: m.height, pixelWidth: 1200, pixelHeight: 600)
		#expect(f.scale == 2 && f.originX == 200 && f.originY == 0)
		let leftMargin = try pixel(image, 10, 300), rightMargin = try pixel(image, 1190, 300)
		#expect(close(leftMargin, drawing.paper) && close(rightMargin, drawing.paper))
		// inside the map the colours are the cells', not the paper's
		let some = drawing.fills[drawing.fills.count / 2]
		let p = m.grid.points[some.cell]
		let inside = try pixel(image, Int(p.x * 2 + 200), Int(p.y * 2))
		#expect(close(inside, some.color))
		// a taller bitmap: margins above and below
		let tall = try MapImage.render(drawing, pixelWidth: 400, pixelHeight: 600)
		let g = MapImage.fit(width: m.width, height: m.height, pixelWidth: 400, pixelHeight: 600)
		#expect(g.scale == 1 && g.originX == 0 && g.originY == 150)
		let top = try pixel(tall, 200, 10), bottom = try pixel(tall, 200, 590)
		#expect(close(top, drawing.paper) && close(bottom, drawing.paper))
	}

	@Test func theRendererRefusesBadSizesAndMakesRepeatablePNGs() throws {
		let drawing = MapDrawing(map: try map())
		for (w, h) in [(0, 10), (10, 0), (-5, 10), (MapImage.maximumPixels + 1, 10)] {
			#expect(throws: MapImage.Failure.invalidSize) { try MapImage.render(drawing, pixelWidth: w, pixelHeight: h) }
		}
		let a = try MapImage.pngData(drawing, pixelWidth: 200, pixelHeight: 150)
		let b = try MapImage.pngData(drawing, pixelWidth: 200, pixelHeight: 150)
		#expect(a == b)
		#expect(a.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
		let source = try #require(CGImageSourceCreateWithData(a as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
		#expect(image.width == 200 && image.height == 150)
	}

	@Test func strokeWidthsScaleWithTheMapSoASmallAndALargeImageKeepTheirProportions() throws {
		// the one fixed-size element, the half-pixel seam outline, is in pixels; the fit scale is what everything else follows
		let m = try map()
		let small = MapImage.fit(width: m.width, height: m.height, pixelWidth: 400, pixelHeight: 300)
		let large = MapImage.fit(width: m.width, height: m.height, pixelWidth: 800, pixelHeight: 600)
		#expect(large.scale == small.scale * 2)
	}

	@MainActor
	@Test func theSwiftUIViewDrawsTheSameDrawingAtTheSameSize() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		let view = FantasyMapView(map: m).frame(width: 400, height: 300)
		let renderer = ImageRenderer(content: view)
		renderer.scale = 1
		let image = try #require(renderer.cgImage)
		#expect(image.width == 400 && image.height == 300)
		let reference = try MapImage.render(drawing, pixelWidth: 400, pixelHeight: 300)
		// the view and the image renderer execute one drawing: inside cells they agree on colour
		var agreed = 0, checked = 0
		for fill in drawing.fills.prefix(150) {
			let p = m.grid.points[fill.cell]
			let x = Int(p.x), y = Int(p.y)
			guard x >= 1 && y >= 1 && x < 399 && y < 299 else { continue }
			let a = try pixel(image, x, y), b = try pixel(reference, x, y)
			checked += 1
			if abs(a.0 - b.0) <= 4.0 / 255 && abs(a.1 - b.1) <= 4.0 / 255 && abs(a.2 - b.2) <= 4.0 / 255 { agreed += 1 }
		}
		#expect(checked > 50 && Double(agreed) / Double(checked) > 0.95, "the view agreed with the image renderer at \(agreed) of \(checked) sampled cells")
	}

	@Test func theRendererRefusesInvalidDrawingsBeforeTransformingAnything() throws {
		let good = MapDrawing(map: try map())
		func with(_ edit: (inout MapDrawing) -> Void) -> MapDrawing { var d = good; edit(&d); return d }
		let bad = [
			with { $0.width = .infinity }, with { $0.height = .infinity }, with { $0.width = .nan }, with { $0.height = -1 },
			with { $0.width = 0 },
			with { $0.width = 1e-320; $0.height = 1e-320 }, // both sides tiny: the fit scale would overflow
		]
		for drawing in bad {
			#expect(throws: MapImage.Failure.invalidSize, "width \(drawing.width), height \(drawing.height)") { try MapImage.render(drawing, pixelWidth: 100, pixelHeight: 100) }
		}
		// a huge drawing in a tiny bitmap has a tiny but finite, positive fit scale and is not refused (the seam outline stays finite)
		let huge = with { $0.width = 1.7e308; $0.height = 1.7e308 }
		_ = try MapImage.render(huge, pixelWidth: 1, pixelHeight: 1)
	}

	@Test func theRendererHasATotalPixelBudgetAsWellAsALongestSide() throws {
		let drawing = MapDrawing(map: try map())
		#expect(MapImage.maximumTotalPixels == 32_000_000)
		// refused without allocating: each side is allowed, the product is not
		#expect(throws: MapImage.Failure.invalidSize) { try MapImage.render(drawing, pixelWidth: 8001, pixelHeight: 4000) }
		#expect(throws: MapImage.Failure.invalidSize) { try MapImage.render(drawing, pixelWidth: MapImage.maximumPixels, pixelHeight: MapImage.maximumPixels) }
		#expect(MapImage.maximumPixels * 2 < MapImage.maximumTotalPixels) // a long thin image is still possible
	}

	@Test func aTranslucentFillIsCompositedOnceOverTransparentPaperAndNotStrokedAtItsEdges() throws {
		// translucent blue (alpha 0.5) over TRANSPARENT paper: premultiplied output is (0, 0, 0.5) with alpha 0.5 after one fill,
		// which can reveal a second composite (a stroke over a fill, or an overlap), unlike alpha over an opaque background
		var style = MapStyle.standard
		let blue = MapColor(red: 0, green: 0, blue: 1, alpha: 0.5)
		style.water = ColorScale(stops: [.init(0, blue), .init(1, blue)])
		style.paper = MapColor(red: 0, green: 0, blue: 0, alpha: 0)
		let m = try flat(height: 5)
		let drawing = MapDrawing(map: m, style: style)
		let image = try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 600)
		let interior = try pixel(image, 400, 300)
		#expect(abs(interior.3 - 0.5) < 3.0 / 255 && abs(interior.2 - 0.5) < 3.0 / 255 && interior.0 < 3.0 / 255, "one translucent fill over nothing is premultiplied (0, 0, 0.5, 0.5); got \(interior)")
		// the actual shared edges between neighbouring cells (not the midpoints between cell sites), away from the frame:
		// no extra seam stroke, so no more opaque than the interior
		let f = MapImage.fit(width: m.width, height: m.height, pixelWidth: 800, pixelHeight: 600)
		let edges = sharedEdgeMidpoints(m, limit: 150)
		var denser = 0
		for (mid, _, _) in edges {
			let p = try pixel(image, Int(mid.x * f.scale), Int(mid.y * f.scale))
			if p.3 > interior.3 + 0.02 { denser += 1 }
		}
		#expect(edges.count > 100 && denser == 0, "\(denser) of \(edges.count) actual shared-edge points were more opaque than the interior")
		// where extended translucent border cells overlap near the frame they DO composite (a documented consequence of the
		// extension, which is a stage-1 diagnostic treatment and not coastline topology); that is not the seam stroke
		let c = coverage(drawing, scale: 2, band: 4 * m.grid.spacing)
		#expect(c.multiple > 0 && c.multipleOutsideBand == 0, "any overlap is confined to the frame band")
	}

	@MainActor
	@Test func theViewAgreesWithTheRendererAtTwiceTheDisplayScaleAtCellsAndAtActualEdges() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing).frame(width: 400, height: 300))
		renderer.scale = 2
		let image = try #require(renderer.cgImage)
		#expect(image.width == 800 && image.height == 600)
		let reference = try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 600)
		// tight interior colour check: each cell's own point
		var cellAgree = 0, cellChecked = 0
		for fill in drawing.fills.prefix(250) {
			let p = m.grid.points[fill.cell]
			let x = Int(p.x * 2), y = Int(p.y * 2)
			guard x >= 1 && y >= 1 && x < 799 && y < 599 else { continue }
			let a = try pixel(image, x, y), b = try pixel(reference, x, y)
			cellChecked += 1
			if abs(a.0 - b.0) <= 4.0 / 255 && abs(a.1 - b.1) <= 4.0 / 255 && abs(a.2 - b.2) <= 4.0 / 255 { cellAgree += 1 }
		}
		#expect(cellChecked > 100 && Double(cellAgree) / Double(cellChecked) > 0.95, "at 2x the view agreed with the renderer at \(cellAgree) of \(cellChecked) cell points")
		// a separate edge comparison at the midpoints of edges two cells really share (normal output; anti-aliasing is not turned off)
		var worst = 0.0, edgeChecked = 0, within24 = 0
		for (mid, _, _) in sharedEdgeMidpoints(m, limit: 200) {
			let x = Int(mid.x * 2), y = Int(mid.y * 2)
			let a = try pixel(image, x, y), b = try pixel(reference, x, y)
			let difference = max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
			worst = max(worst, difference)
			edgeChecked += 1
			if difference <= 24.0 / 255 { within24 += 1 }
		}
		print("EDGES view against renderer at actual shared-edge midpoints: \(within24) of \(edgeChecked) within 24/255, worst \(Int(worst * 255))/255")
		// the observed bound on these maps, not a general anti-aliasing bound
		#expect(edgeChecked > 100 && Double(within24) / Double(edgeChecked) > 0.9, "\(within24) of \(edgeChecked) edge points within 24/255, worst \(Int(worst * 255))/255")
	}

	@MainActor
	@Test func aPreparedDrawingIsKeptAsIsAndRenderingItAgainGivesTheSamePicture() throws {
		let m = try map()
		let prepared = MapDrawing(map: m)
		#expect(FantasyMapView(drawing: prepared).drawing == prepared)
		#expect(FantasyMapView(map: m).drawing == prepared) // the convenience builds the same drawing, every time it runs
		func image() throws -> CGImage {
			let r = ImageRenderer(content: FantasyMapView(drawing: prepared).frame(width: 200, height: 150))
			r.scale = 1
			return try #require(r.cgImage)
		}
		let first = try image(), second = try image()
		var same = true
		for (x, y) in [(5, 5), (100, 75), (190, 140), (60, 20), (150, 100)] { let a = try pixel(first, x, y), b = try pixel(second, x, y); if a != b { same = false } }
		#expect(same, "an unrelated parent update that recreates the view gives the same picture")
	}
}
