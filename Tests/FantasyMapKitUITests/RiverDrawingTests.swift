import CoreGraphics
import FantasyMapKit
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKitUI

/// Drawing a water map's rivers: trimmed to the drawn land and extended to it (decided 2026-10-21, docs/plans/drawing-water.md).
struct RiverDrawingTests {
	typealias P = RiverGeometry.RiverPoint
	/// Land is the square 20 ... 80 in both directions of a 100 by 100 map, with a lake hole 45 ... 55 in the middle.
	static let rings: [[Point]] = [
		[Point(x: 20, y: 20), Point(x: 80, y: 20), Point(x: 80, y: 80), Point(x: 20, y: 80)],
		[Point(x: 45, y: 45), Point(x: 55, y: 45), Point(x: 55, y: 55), Point(x: 45, y: 55)]
	]
	let index = RingIndex(rings: RiverDrawingTests.rings, height: 100)

	func line(_ xs: [(Double, Double)]) -> [P] { xs.map { P(x: $0.0, y: $0.1, flux: 1) } }

	@Test func theLandIndexAnswersTheEvenOddRule() {
		#expect(index.contains(Point(x: 30, y: 30)))
		#expect(!index.contains(Point(x: 10, y: 30)))
		#expect(!index.contains(Point(x: 90, y: 30)))
		#expect(!index.contains(Point(x: 50, y: 50)), "a lake hole is water")
		#expect(index.contains(Point(x: 50, y: 60)))
		#expect(!index.contains(Point(x: 30, y: 10)) && !index.contains(Point(x: 30, y: 90)))
	}

	@Test func theFirstCrossingOfASegmentIsFoundAlongIt() throws {
		let t = try #require(index.firstCrossing(from: Point(x: 0, y: 30), to: Point(x: 40, y: 30)))
		#expect(abs(t - 0.5) < 1e-9, "the left edge at x = 20")
		#expect(index.firstCrossing(from: Point(x: 25, y: 25), to: Point(x: 35, y: 35)) == nil)
		// the line of an edge is not the edge: this segment crosses the extension of the left edge (x = 20) below the land, and meets no edge
		#expect(index.firstCrossing(from: Point(x: 0, y: 10), to: Point(x: 30, y: 10)) == nil)
		let d = try #require(index.firstCrossing(from: Point(x: 50, y: 70), direction: Point(x: 0, y: -1), reach: 100))
		#expect(abs(d - 15) < 1e-9, "the lake's lower edge at y = 55")
		#expect(index.firstCrossing(from: Point(x: 50, y: 70), direction: Point(x: 0, y: -1), reach: 10) == nil, "beyond the reach")
	}

	@Test func aRiverThatEndsShortOfTheCoastIsExtendedToIt() throws {
		let trimmed = try #require(RiverDrawing.trim(line([(40, 70), (35, 60), (30, 50), (28, 40)]), end: .water, index: index, reach: 40))
		let end = try #require(trimmed.last)
		#expect(trimmed.count == 5)
		#expect(!index.contains(Point(x: end.x, y: end.y)) || abs(end.y - 20) < 1e-6, "the new end is on the outline")
		#expect(abs(end.y - 20) < 1e-6, "it reaches the top edge, y = 20, along its last direction")
		#expect(end.x < 28 && end.x > 20)
	}

	@Test func aRiverThatRunsPastTheCoastIsCutWhereItLeaves() throws {
		let trimmed = try #require(RiverDrawing.trim(line([(40, 40), (30, 30), (15, 25), (5, 20)]), end: .water, index: index, reach: 40))
		let end = try #require(trimmed.last)
		#expect(trimmed.count == 3)
		#expect(abs(end.x - 20) < 1e-6, "cut at the left edge, x = 20")
		#expect(end.y > 25 && end.y < 30)
	}

	@Test func aRiverThatBeginsInWaterStartsWhereItEntersTheLand() throws {
		let trimmed = try #require(RiverDrawing.trim(line([(10, 40), (30, 40), (60, 40), (70, 40)]), end: .water, index: index, reach: 40))
		#expect(abs(trimmed[0].x - 20) < 1e-6, "starts at the left edge")
		#expect(trimmed[0].flux == 0, "a point made by the cut has no flux of its own")
		#expect(trimmed.count >= 3)
	}

	@Test func aRiverWhollyInDrawnWaterIsNotDrawn() {
		#expect(RiverDrawing.trim(line([(5, 5), (10, 10), (90, 90)]), end: .water, index: index, reach: 40) == nil)
		#expect(RiverDrawing.trim(line([(48, 48), (50, 50), (52, 52)]), end: .water, index: index, reach: 40) == nil, "inside the lake")
		#expect(RiverDrawing.trim(line([(30, 30)]), end: .water, index: index, reach: 40) == nil)
	}

	@Test func aDuplicatedLastPointDoesNotStopTheExtension() throws {
		let trimmed = try #require(RiverDrawing.trim(line([(40, 70), (35, 60), (30, 50), (30, 50)]), end: .water, index: index, reach: 40))
		#expect(abs(trimmed.last!.x - 20) < 1e-6 && abs(trimmed.last!.y - 30) < 1e-6 && trimmed.count == 5, "extended along the direction of the last distinct pair, to the left edge")
	}

	@Test func tooFewPointsGiveNothingEvenAtTheBorder() {
		#expect(RiverDrawing.trim(line([(30, 30)]), end: .border, index: index, reach: 40) == nil)
		#expect(RiverDrawing.trim([], end: .water, index: index, reach: 40) == nil)
		// two points that stay on land and cannot be extended are a stub too
		#expect(RiverDrawing.trim(line([(30, 30), (40, 30)]), end: .water, index: index, reach: 1) == nil)
	}

	@Test func theReachIsFourSpacings() {
		#expect(RiverDrawing.reach(spacing: 7.5) == 30)
	}

	@Test func aRiverThatSpansANarrowLakeBetweenTwoLandPointsIsCutWhereItEntersIt() throws {
		// both neighbouring points are on land, the lake hole (x 45 ... 55) lies between them
		let points = line([(25, 50), (30, 50), (70, 50), (75, 50)])
		#expect(index.contains(Point(x: 30, y: 50)) && index.contains(Point(x: 70, y: 50)))
		let trimmed = try #require(RiverDrawing.trim(points, end: .water, index: index, reach: 40))
		#expect(trimmed.count == 3 && abs(trimmed.last!.x - 45) < 1e-6, "ends at the lake's near shore, x = 45")
		#expect(trimmed.allSatisfy { $0.x <= 45 + 1e-6 })
	}

	@Test func aTributaryThatEndsOnLandAtAConfluenceIsNotExtended() throws {
		let points = line([(40, 70), (35, 60), (30, 50), (28, 40)])
		let tributary = try #require(RiverDrawing.trim(points, end: .land, index: index, reach: 40))
		#expect(tributary.count == 4 && tributary.last!.x == 28 && tributary.last!.y == 40, "kept as it is: no branch beyond the junction")
		let river = try #require(RiverDrawing.trim(points, end: .water, index: index, reach: 40))
		#expect(river.count == 5, "the same line ending at water is extended")
		// a tributary is still cut where it leaves the land
		let leaving = try #require(RiverDrawing.trim(line([(40, 40), (30, 30), (15, 25), (5, 20)]), end: .land, index: index, reach: 40))
		#expect(leaving.count == 3 && abs(leaving.last!.x - 20) < 1e-6)
	}

	@Test func theEndOfARiverIsReadFromItsLastCell() throws {
		let water = try water()
		let heights = water.packed.heights
		var kinds: [RiverDrawing.End: Int] = [:]
		for river in water.rivers {
			let end = RiverDrawing.end(of: river, heights: heights)
			kinds[end, default: 0] += 1
			let last = river.cells.last!
			if last < 0 { #expect(end == .border) } else { #expect(end == (heights[last] < Heights.seaLevel ? .water : .land)) }
		}
		#expect((kinds[.water] ?? 0) > 5 && (kinds[.land] ?? 0) > 5, "both water mouths and confluences on this map: \(kinds)")
		var empty = water.rivers[0]
		empty.cells = []
		#expect(RiverDrawing.end(of: empty, heights: heights) == .land)
	}

	@Test func aRiverCutToAStubOfFewerThanThreePointsIsNotDrawn() {
		// it starts on the land and leaves it at the next point: the stub keeps two points
		#expect(RiverDrawing.trim(line([(25, 30), (15, 30), (5, 30)]), end: .water, index: index, reach: 40) == nil)
	}

	@Test func aRiverThatLeavesByTheBorderEndsThereAndIsNotExtended() throws {
		// its last point is on the frame (here the map edge x = 100); the land ring ends at 80, so the point would be water if it were asked
		let points = line([(40, 70), (60, 70), (100, 70)])
		let trimmed = try #require(RiverDrawing.trim(points, end: .border, index: index, reach: 40))
		#expect(trimmed.last!.x < 100 && abs(trimmed.last!.x - 80) < 1e-6, "cut where it leaves the drawn land, not extended to the frame")
		// a border river that stays on land to the end keeps its last point
		let inside = RingIndex(rings: [[Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 100), Point(x: 0, y: 100)]], height: 100)
		let kept = try #require(RiverDrawing.trim(line([(40, 70), (60, 70), (100, 70)]), end: .border, index: inside, reach: 40))
		#expect(kept.count == 3 && kept.last!.x == 100)
	}

	@Test func aRiverThatIsAlreadyOnLandAndMeetsTheCoastIsLeftAlone() throws {
		// the end is on land with the outline further than the reach: nothing is added
		let far = try #require(RiverDrawing.trim(line([(40, 70), (50, 70), (60, 70)]), end: .water, index: index, reach: 1))
		#expect(far.count == 3)
	}

	// MARK: a generated map

	func water() throws -> WaterMap {
		let land = try LandMap.generate(seed: "kaz-1", width: 800, height: 500, cellsDesired: 1500, template: try #require(HeightmapTemplate.named("continents")))
		return try WaterMap.generate(land: land)
	}

	@Test func aWaterMapDrawsItsRiversTrimmedToTheDrawnLand() throws {
		let water = try water()
		let drawing = MapDrawing(water: water)
		#expect(!drawing.rivers.isEmpty && drawing.rivers.count + drawing.riversInWater + drawing.riversSkipped == water.rivers.count)
		#expect(drawing.rivers.allSatisfy { $0.points.count >= 4 && $0.color == MapStyle.standard.river })
		// every river's centre lies on the land or within a river's width of it: sample the polygons' points
		let rings = try #require(drawing.landClip)
		let index = RingIndex(rings: rings, height: water.land.height)
		let onLand = drawing.rivers.flatMap(\.points).filter { index.contains($0) }.count
		let all = drawing.rivers.reduce(0) { $0 + $1.points.count }
		#expect(Double(onLand) / Double(all) > 0.97, "\(onLand) of \(all) outline points on the drawn land")
	}

	@Test func theBudgetOfPolygonPointsIsRespected() throws {
		let water = try water()
		let drawing = MapDrawing(map: water.land)
		let all = RiverDrawing.build(water: water, landRings: drawing.landClip, style: .standard)
		let few = RiverDrawing.build(water: water, landRings: drawing.landClip, style: .standard, maximumPolygonPoints: 200)
		#expect(all.skipped == 0 && few.skipped > 0 && few.fills.reduce(0) { $0 + $1.points.count } <= 200)
		#expect(few.fills.count + few.skipped + few.inWater == water.rivers.count)
	}

	@Test func riversWithNothingOnTheDrawnLandAreCountedAndTheOthersDrawn() throws {
		var found = 0
		for i in 0..<60 where found == 0 {
			let land = try LandMap.generate(seed: "iw\(i)", width: 640, height: 400, cellsDesired: 600, template: try #require(HeightmapTemplate.all[i % HeightmapTemplate.all.count] as HeightmapTemplate?))
			let water = try WaterMap.generate(land: land)
			let drawing = MapDrawing(water: water)
			#expect(drawing.rivers.count + drawing.riversInWater + drawing.riversSkipped == water.rivers.count)
			if drawing.riversInWater > 0 { found = 1 }
		}
		#expect(found == 1, "a small map with a river that has nothing on the drawn land")
	}

	@Test func aRiverThatLeavesByTheBorderIsDrawnToTheFrame() throws {
		var checked = 0
		for i in 0..<60 where checked < 3 {
			let land = try LandMap.generate(seed: "bd\(i)", width: 640, height: 400, cellsDesired: 600, template: try #require(HeightmapTemplate.all[i % HeightmapTemplate.all.count] as HeightmapTemplate?))
			let water = try WaterMap.generate(land: land)
			let drawing = MapDrawing(water: water)
			for river in water.rivers where river.cells.last == -1 {
				guard let fill = drawing.rivers.first(where: { $0.river == river.id }) else { continue }
				let nearFrame = fill.points.contains { $0.x < 2 || $0.y < 2 || $0.x > land.width - 2 || $0.y > land.height - 2 }
				#expect(nearFrame, "river \(river.id) reaches the frame")
				checked += 1
			}
		}
		#expect(checked > 0, "some small map has a river that leaves by the border")
	}

	@Test func aWiderScaleDoublesTheOutlineAroundTheSameCentreLine() throws {
		let water = try water()
		var two = MapStyle.standard
		two.riverWidthScale = 2
		let one = MapDrawing(water: water).rivers, twice = MapDrawing(water: water, style: two).rivers
		func area(_ p: [Point]) -> Double { abs(PolygonArea.of(p)) }
		let ratios = zip(one, twice).map { area($1.points) / area($0.points) }.sorted()
		#expect(ratios.count == one.count && one.count > 20)
		#expect(abs(ratios[ratios.count / 2] - 2) < 0.15, "the median area ratio is \(ratios[ratios.count / 2])")
	}

	@Test func theLandOnlyDrawingHasNoRiversAndTheSwitchesTurnThemOff() throws {
		let water = try water()
		#expect(MapDrawing(map: water.land).rivers.isEmpty)
		var off = MapStyle.standard
		off.riverWidthScale = 0
		#expect(MapDrawing(water: water, style: off).rivers.isEmpty)
		off.riverWidthScale = 1
		off.river.alpha = 0
		#expect(MapDrawing(water: water, style: off).rivers.isEmpty)
		var wide = MapStyle.standard
		wide.riverWidthScale = 3
		let normal = MapDrawing(water: water).rivers, big = MapDrawing(water: water, style: wide).rivers
		func area(_ p: [Point]) -> Double { abs(PolygonArea.of(p)) }
		#expect(normal.count == big.count && zip(normal, big).filter { area($0.points) < area($1.points) }.count > normal.count * 9 / 10, "a wider scale gives wider shapes")
	}

	@Test func theSamePictureComesFromTheSameInputs() throws {
		let water = try water()
		#expect(MapDrawing(water: water) == MapDrawing(water: water))
		let a = try MapImage.render(MapDrawing(water: water), pixelWidth: 400, pixelHeight: 250)
		let b = try MapImage.render(MapDrawing(water: water), pixelWidth: 400, pixelHeight: 250)
		#expect(Self.pixels(a) == Self.pixels(b))
	}

	@Test func theImageShowsTheRiversAndTheViewAndImageShareTheCommands() throws {
		let water = try water()
		let with = try MapImage.render(MapDrawing(water: water), pixelWidth: 800, pixelHeight: 500)
		var style = MapStyle.standard
		style.riverWidthScale = 0
		let without = try MapImage.render(MapDrawing(water: water, style: style), pixelWidth: 800, pixelHeight: 500)
		let a = Self.pixels(with), b = Self.pixels(without)
		#expect(a != b && zip(a, b).filter { $0 != $1 }.count > 500, "river pixels differ from the land picture")
		// the land-only picture of the same map equals the picture with the rivers switched off
		let landOnly = Self.pixels(try MapImage.render(MapDrawing(map: water.land), pixelWidth: 800, pixelHeight: 500))
		#expect(landOnly == b)
	}

	/// The land outline as a mask at the picture's size (map units = pixels), with the picture's own orientation.
	static func landMask(_ rings: [[Point]], width: Int, height: Int) -> [Bool] {
		var data = [UInt8](repeating: 0, count: width * height)
		let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
		context.translateBy(x: 0, y: Double(height))
		context.scaleBy(x: 1, y: -1)
		context.setFillColor(gray: 1, alpha: 1)
		context.beginPath()
		for ring in rings {
			guard let first = ring.first else { continue }
			context.move(to: CGPoint(x: first.x, y: first.y))
			for p in ring.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }
			context.closePath()
		}
		context.fillPath(using: .evenOdd)
		return data.map { $0 > 127 }
	}

	@Test func aTrustedRiverFillNeverPaintsOutsideTheLandSilhouette() throws {
		let water = try water()
		let drawing = MapDrawing(water: water)
		let rings = try #require(drawing.landClip)
		var style = MapStyle.standard
		style.riverWidthScale = 0
		let w = 800, h = 500 // the map is 800 by 500 units: one pixel is one unit
		let with = Self.pixels(try MapImage.render(drawing, pixelWidth: w, pixelHeight: h)), without = Self.pixels(try MapImage.render(MapDrawing(water: water, style: style), pixelWidth: w, pixelHeight: h))
		let mask = Self.landMask(rings, width: w, height: h)
		var changed = 0, outside = 0
		for y in 0..<h {
			for x in 0..<w {
				let i = (y * w + x) * 4
				guard with[i] != without[i] || with[i + 1] != without[i + 1] || with[i + 2] != without[i + 2] else { continue }
				changed += 1
				// the outline's own anti-aliased edge may differ by a pixel: look at the pixel and its eight neighbours
				var near = false
				for dy in -1...1 { for dx in -1...1 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && mask[(y + dy) * w + x + dx] { near = true } }
				if !near { outside += 1 }
			}
		}
		#expect(changed > 500, "rivers were painted (\(changed) pixels)")
		#expect(outside == 0, "\(outside) river pixels more than a pixel outside the land silhouette")
	}

	/// How many pixels differ between two pictures, and how many of those are more than a pixel away from the land mask.
	static func differences(_ a: [UInt8], _ b: [UInt8], mask: [Bool], width w: Int, height h: Int) -> (changed: Int, outside: Int) {
		var changed = 0, outside = 0
		for y in 0..<h {
			for x in 0..<w {
				let i = (y * w + x) * 4
				guard a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] else { continue }
				changed += 1
				var near = false
				for dy in -1...1 { for dx in -1...1 where x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h && mask[(y + dy) * w + x + dx] { near = true } }
				if !near { outside += 1 }
			}
		}
		return (changed, outside)
	}

	@MainActor
	@Test func aRiverShapeThatReachesOverTheWaterIsClippedToTheLandByBothRenderers() throws {
		// a fill that covers the whole map, so that the clip is what decides where it shows
		let water = try water()
		var drawing = MapDrawing(map: water.land)
		let rings = try #require(drawing.landClip)
		var plain = drawing
		plain.rivers = []
		drawing.rivers = [RiverFill(points: [Point(x: -10, y: -10), Point(x: 810, y: -10), Point(x: 810, y: 510), Point(x: -10, y: 510)], color: MapColor(red: 1, green: 0, blue: 1), river: 1)]
		let mask = Self.landMask(rings, width: 800, height: 500)
		let image = Self.differences(Self.pixels(try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 500)), Self.pixels(try MapImage.render(plain, pixelWidth: 800, pixelHeight: 500)), mask: mask, width: 800, height: 500)
		#expect(image.changed > 50_000 && image.outside == 0, "image renderer: \(image.changed) pixels changed, \(image.outside) outside the land")
		func view(_ d: MapDrawing) throws -> [UInt8] { try ViewRendering.pixels(d, width: 800, height: 500) }
		let swiftUI = Self.differences(try view(drawing), try view(plain), mask: mask, width: 800, height: 500)
		// the SwiftUI renderer's output was seen to vary by up to about 700 pixels from run to run (see `ViewRendering`); a failed clip would change tens of thousands
		#expect(swiftUI.changed > 50_000 && swiftUI.outside <= ViewRendering.tolerance, "SwiftUI view: \(swiftUI.changed) pixels changed, \(swiftUI.outside) outside the land")
	}

	@Test func whenTheCoastIsNotTrustedTheRiversAreDrawnAsGeneratedAndUnclipped() throws {
		let water = try water()
		var coast = CoastOutlines(map: water.land, smoothing: 2)
		coast.frameClosureIsConsistent = false
		var drawing = MapDrawing(map: water.land, style: .standard, coast: coast, fills: MapDrawing(map: water.land).fills)
		#expect(drawing.landClip == nil)
		drawing.rivers = RiverDrawing.build(water: water, landRings: nil, style: .standard).fills
		#expect(!drawing.rivers.isEmpty)
		var plain = drawing
		plain.rivers = []
		let a = Self.pixels(try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 500)), b = Self.pixels(try MapImage.render(plain, pixelWidth: 800, pixelHeight: 500))
		#expect(zip(a, b).filter { $0 != $1 }.count > 500, "the fallback still draws the rivers")
	}

	static func pixels(_ image: CGImage) -> [UInt8] {
		var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
		let space = CGColorSpace(name: CGColorSpace.sRGB)!
		let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
		return data
	}
}

/// Renders a drawing through the SwiftUI view. **The first two renders of a given view differ from the later ones** (measured: the third render of the same
/// view differed from the second in about 11,000 channel values, and from then on they were stable), so each drawing is rendered three times and the last
/// is used, which makes comparisons between drawings independent of the order the tests run in.
enum ViewRendering {
	/// How many pixels outside a mask a view render may differ in, as noise of the renderer: measured at about 660 in a run and never more than 700, so 1,500 leaves room and still
	/// fails a clip that does not work (that changes tens of thousands of pixels).
	static let tolerance = 1_500

	@MainActor static func pixels(_ drawing: MapDrawing, width: Int, height: Int) throws -> [UInt8] {
		var image: CGImage?
		for _ in 0..<3 {
			let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing).frame(width: Double(width), height: Double(height)))
			renderer.scale = 1
			image = renderer.cgImage
		}
		return RiverDrawingTests.pixels(try #require(image))
	}
}

enum PolygonArea {
	static func of(_ polygon: [Point]) -> Double {
		guard var b = polygon.last else { return 0 }
		var area = 0.0
		for p in polygon { let a = b; b = p; area += a.y * b.x - a.x * b.y }
		return area / 2
	}
}
