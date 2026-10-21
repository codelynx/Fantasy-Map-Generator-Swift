import CoreGraphics
import FantasyMapKit
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKitUI

/// The zoomable view drawn through SwiftUI's `ImageRenderer`. **The gestures themselves (pinch, drag, double click, Option-scroll, the keys and the accessibility
/// actions) are not exercised here**: they cannot be driven from a test, so their wiring is checked only through the pure functions they call
/// (`MapViewportTests`) and by looking at the demo. This file checks what the view draws for a viewport.
struct FantasyMapViewZoomTests {
	func map() throws -> LandMap {
		try LandMap.generate(seed: "kaz-1", width: 800, height: 500, cellsDesired: 3000, template: try #require(HeightmapTemplate.named("continents")))
	}

	/// How many pixels differ (any channel). **The SwiftUI renderer's output varies a little from render to render** (see `ViewRendering`), so pictures that should be
	/// the same are compared with a small allowance, and pictures that should differ must differ by far more than it.
	func differing(_ a: [UInt8], _ b: [UInt8]) -> Int {
		var count = 0
		for i in stride(from: 0, to: min(a.count, b.count), by: 4) where a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] { count += 1 }
		return count
	}

	/// The most pixels (of 400,000) two renders of the same picture were seen to differ by: 14,592 between a drawing's first renders and the later ones. A bound of 20,000 (5%)
	/// is weak evidence of equality; the sampled agreement with the enlarged image renderer's picture is the stronger check. Pictures that should differ differ by 385,000 or more.
	static let noise = 20_000
	static let different = 100_000

	/// **The first renders of a process differ from the later ones** (measured: a view's first render differed from a later render of the same view by about 14,600
	/// pixels of 400,000, and from then on they were identical), so a few renders are made once before any picture is compared.
	@MainActor private static var warmedUp = false
	@MainActor static func warmUp(_ drawing: MapDrawing) {
		guard !warmedUp else { return }
		warmedUp = true
		for _ in 0..<4 { _ = ImageRenderer(content: FantasyMapView(drawing: drawing).frame(width: 800, height: 500)).cgImage }
	}

	@MainActor
	func view(_ drawing: MapDrawing, viewport: MapViewport?, interactive: Bool = true, width: Int = 800, height: Int = 500) throws -> [UInt8] {
		Self.warmUp(drawing)
		var image: CGImage?
		for _ in 0..<5 { // the first renders of a view differ from the later ones, and the fourth is the first that matched the rest (see `ViewRendering`)
			let content: AnyView = viewport.map { v in AnyView(FantasyMapView(drawing: drawing, viewport: .constant(v), isInteractive: interactive).frame(width: Double(width), height: Double(height))) }
				?? AnyView(FantasyMapView(drawing: drawing, isInteractive: interactive).frame(width: Double(width), height: Double(height)))
			let renderer = ImageRenderer(content: content)
			renderer.scale = 1
			image = renderer.cgImage
		}
		return RiverDrawingTests.pixels(try #require(image))
	}

	@Test func theDrawingKnowsTheCellSizeTheZoomLimitFollows() throws {
		let m = try map()
		#expect(MapDrawing(map: m).cellSpacing == m.grid.spacing && m.grid.spacing > 0)
	}

	@MainActor
	@Test func atFitTheInteractiveViewDrawsWhatTheViewDrewBeforeZooming() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		let image = RiverDrawingTests.pixels(try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 500))
		let fitted = try view(drawing, viewport: .fit), plain = try view(drawing, viewport: nil)
		#expect(differing(fitted, plain) <= Self.noise, "an unbound view starts at fit, the same picture (\(differing(fitted, plain)) pixels differ)")
		// the same drawing commands and transform as the image renderer, within the rendering tolerance
		var agreed = 0, total = 0
		for fill in drawing.fills.prefix(400) {
			let p = m.grid.points[fill.cell]
			let x = Int(p.x), y = Int(p.y)
			guard x > 1, y > 1, x < 799, y < 499 else { continue }
			let i = (y * 800 + x) * 4
			total += 1
			if abs(Int(fitted[i]) - Int(image[i])) <= 6 && abs(Int(fitted[i + 1]) - Int(image[i + 1])) <= 6 && abs(Int(fitted[i + 2]) - Int(image[i + 2])) <= 6 { agreed += 1 }
		}
		#expect(total > 200 && Double(agreed) / Double(total) > 0.95, "\(agreed) of \(total) sampled sites agree with the image renderer")
	}

	@MainActor
	@Test func aZoomedViewShowsThePartOfTheMapTheViewportSays() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		// zoom 4 on the 800 by 500 map in an 800 by 500 view: the view shows a 200 by 125 part, centred on the centre we give
		let viewport = MapViewport(zoom: 4, center: Point(x: 400, y: 250))
		let zoomed = try view(drawing, viewport: viewport)
		// the image renderer drawn four times as large shows the same part: its pixels (centre × 4 ± half the view) are the view's pixels
		let big = RiverDrawingTests.pixels(try MapImage.render(drawing, pixelWidth: 3200, pixelHeight: 2000))
		var agreed = 0, total = 0
		for y in stride(from: 10, to: 490, by: 7) {
			for x in stride(from: 10, to: 790, by: 7) {
				let bx = 1600 - 400 + x, by = 1000 - 250 + y
				let i = (y * 800 + x) * 4, j = (by * 3200 + bx) * 4
				total += 1
				if abs(Int(zoomed[i]) - Int(big[j])) <= 8 && abs(Int(zoomed[i + 1]) - Int(big[j + 1])) <= 8 && abs(Int(zoomed[i + 2]) - Int(big[j + 2])) <= 8 { agreed += 1 }
			}
		}
		#expect(Double(agreed) / Double(total) > 0.9, "\(agreed) of \(total) sampled pixels of the zoomed view equal the same part of the enlarged picture")
		// and it is not the fitted picture
		#expect(differing(zoomed, try view(drawing, viewport: .fit)) > Self.different)
		// another centre shows another part
		let moved = try view(drawing, viewport: MapViewport(zoom: 4, center: Point(x: 200, y: 150)))
		#expect(differing(moved, zoomed) > Self.different)
	}

	@MainActor
	@Test func theViewLimitsTheZoomWithTheDrawingsOwnCellSize() throws {
		let m = try map()
		let drawing = MapDrawing(map: m)
		let g = MapViewportGeometry(mapWidth: drawing.width, mapHeight: drawing.height, viewWidth: 800, viewHeight: 500, cellSpacing: drawing.cellSpacing)
		let maximum = g.maximumZoom
		#expect(maximum > 2 && maximum < 64, "a zoom limit that follows these cells: \(maximum)")
		let centre = Point(x: 400, y: 250)
		// asking for far more than the limit draws the picture at the limit, not beyond it
		let limited = try view(drawing, viewport: MapViewport(zoom: 1e6, center: centre))
		let atLimit = try view(drawing, viewport: MapViewport(zoom: maximum, center: centre))
		#expect(differing(limited, atLimit) <= Self.noise)
		#expect(differing(atLimit, try view(drawing, viewport: MapViewport(zoom: maximum / 2, center: centre))) > Self.different)
	}

	@MainActor
	@Test func withInteractionOffTheViewStaysAtFitWhateverTheViewportSays() throws {
		let drawing = MapDrawing(map: try map())
		let off = try view(drawing, viewport: MapViewport(zoom: 4, center: Point(x: 100, y: 100)), interactive: false)
		#expect(differing(off, try view(drawing, viewport: .fit)) <= Self.noise)
	}

	@MainActor
	@Test func aViewportThatIsNotUsableDrawsAtFitNotAGarbledMap() throws {
		let drawing = MapDrawing(map: try map())
		let fit = try view(drawing, viewport: .fit)
		for bad in [MapViewport(zoom: .nan, center: Point(x: .nan, y: .infinity)), MapViewport(zoom: -5), MapViewport(zoom: .infinity)] {
			#expect(differing(try view(drawing, viewport: bad), fit) <= Self.noise, "\(bad)")
		}
	}

	@MainActor
	@Test func inkThatReachesBeyondTheMapIsClippedToTheMapsOwnRectangle() throws {
		// an ink line across the whole view, drawn unclipped by the land: only the clip to the map's own rectangle keeps it off the paper around the map
		var drawing = MapDrawing(map: try map())
		drawing.ink = [InkCommand(points: [Point(x: -300, y: 250), Point(x: 1100, y: 250)], isClosed: false, color: MapColor(red: 1, green: 0, blue: 1), width: 8)]
		let pixels = try view(drawing, viewport: .fit, width: 1000, height: 500) // the 800 wide map is centred: 100 points of paper on each side
		func at(_ x: Int, _ y: Int) -> [Double] { let i = (y * 1000 + x) * 4; return [Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255] }
		let paper = [drawing.paper.red, drawing.paper.green, drawing.paper.blue]
		for x in [20, 60, 940, 980] { #expect(zip(at(x, 250), paper).allSatisfy { abs($0 - $1) < 0.02 }, "paper at x = \(x)") }
		#expect(abs(at(500, 250)[1] - 0) < 0.1 && at(500, 250)[0] > 0.8, "the line shows over the map")
	}

	@MainActor
	@Test func zoomLimitsThatOverflowTheTransformDrawOnlyThePaper() throws {
		let drawing = MapDrawing(map: try map())
		var policy = ViewportPolicy()
		policy.floorZoom = 1e308
		policy.ceilingZoom = 1e308
		#expect(policy.isValid)
		FantasyMapViewZoomTests.warmUp(drawing)
		var image: CGImage?
		for _ in 0..<5 {
			let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing, viewport: .constant(MapViewport(zoom: 1e308, center: Point(x: 1, y: 1))), policy: policy).frame(width: 800, height: 500))
			renderer.scale = 1
			image = renderer.cgImage
		}
		let pixels = RiverDrawingTests.pixels(try #require(image))
		for (x, y) in [(400, 250), (50, 50), (700, 400)] {
			let i = (y * 800 + x) * 4
			#expect(abs(Double(pixels[i]) / 255 - drawing.paper.red) < 0.02 && abs(Double(pixels[i + 1]) / 255 - drawing.paper.green) < 0.02, "only the paper at \(x), \(y)")
		}
	}

	@MainActor
	@Test func aPolicyThatIsNotValidDrawsOnlyThePaperNotAGarbledMap() throws {
		let drawing = MapDrawing(map: try map())
		var bad = ViewportPolicy()
		bad.floorZoom = 0.5
		FantasyMapViewZoomTests.warmUp(drawing)
		var image: CGImage?
		for _ in 0..<5 {
			let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing, policy: bad).frame(width: 800, height: 500))
			renderer.scale = 1
			image = renderer.cgImage
		}
		let pixels = RiverDrawingTests.pixels(try #require(image))
		let i = (250 * 800 + 400) * 4
		#expect(abs(Double(pixels[i]) / 255 - drawing.paper.red) < 0.02 && abs(Double(pixels[i + 1]) / 255 - drawing.paper.green) < 0.02, "only the paper is drawn")
	}

	@MainActor
	@Test func theMapIsClippedToItsOwnRectangleWhenZoomedOut() throws {
		// at fit in a view with room around the map, the paper shows around it and nothing is drawn there
		let drawing = MapDrawing(map: try map())
		let wide = try view(drawing, viewport: .fit, width: 1000, height: 500)
		let paper = drawing.paper
		let i = (250 * 1000 + 40) * 4 // left of the map, in the margin
		#expect(abs(Double(wide[i]) / 255 - paper.red) < 0.02 && abs(Double(wide[i + 1]) / 255 - paper.green) < 0.02 && abs(Double(wide[i + 2]) / 255 - paper.blue) < 0.02, "the margin is paper")
	}
}
