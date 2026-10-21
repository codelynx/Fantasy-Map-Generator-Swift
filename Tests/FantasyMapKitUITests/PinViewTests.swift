import CoreGraphics
import FantasyMapKit
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKitUI

/// What the view draws for pins, through `ImageRenderer` (the gestures are not exercised: see `PinTests`).
struct PinViewTests {
	func map() throws -> LandMap {
		try LandMap.generate(seed: "kaz-1", width: 800, height: 500, cellsDesired: 3000, template: try #require(HeightmapTemplate.named("continents")))
	}

	@MainActor
	func render(_ drawing: MapDrawing, viewport: MapViewport = .fit, pins: PinLayer?) throws -> [UInt8] {
		FantasyMapViewZoomTests.warmUp(drawing)
		var image: CGImage?
		for _ in 0..<5 { // see `FantasyMapViewZoomTests.view`
			let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing, viewport: .constant(viewport), pinLayer: pins).frame(width: 800, height: 500))
			renderer.scale = 1
			image = renderer.cgImage
		}
		return RiverDrawingTests.pixels(try #require(image))
	}

	/// The pixels that differ from the picture without pins: their count and their bounding box.
	func changed(_ a: [UInt8], _ b: [UInt8]) -> (count: Int, box: CGRect?) {
		var count = 0, minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
		for y in 0..<500 {
			for x in 0..<800 {
				let i = (y * 800 + x) * 4
				if abs(Int(a[i]) - Int(b[i])) > 12 || abs(Int(a[i + 1]) - Int(b[i + 1])) > 12 || abs(Int(a[i + 2]) - Int(b[i + 2])) > 12 {
					count += 1; minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
				}
			}
		}
		return (count, count == 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
	}

	func rgb(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Double] { let i = (y * 800 + x) * 4; return [Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255] }

	@MainActor
	@Test func aPinIsDrawnAtItsAnchorAndNowhereElse() throws {
		let drawing = MapDrawing(map: try map())
		let plain = try render(drawing, pins: nil)
		let layer = PinLayer(pins: [MapPin(id: "a", position: Point(x: 400, y: 250))])
		let with = try render(drawing, pins: layer)
		let c = changed(with, plain)
		let box = try #require(c.box)
		// the marker's frame at fit (scale 1): 24 by 34 with its tip at (400, 250)
		#expect(c.count > 300, "the marker is drawn: \(c.count) pixels")
		#expect(box.minX >= 388 - 2 && box.maxX <= 412 + 2 && box.minY >= 216 - 2 && box.maxY <= 250 + 2, "the change is inside the marker's frame: \(box)")
		let head = rgb(with, 400, 221)
		#expect(abs(head[0] - 0.86) < 0.12 && abs(head[1] - 0.22) < 0.12 && abs(head[2] - 0.20) < 0.12, "the head is the marker's red: \(head)")
	}

	@MainActor
	@Test func theMarkerKeepsItsSizeWhenTheMapZoomsAndFollowsTheMap() throws {
		let drawing = MapDrawing(map: try map())
		let layer = PinLayer(pins: [MapPin(id: "a", position: Point(x: 300, y: 200), marker: "pin")])
		var counts: [Int] = []
		for zoom in [1.0, 3.0] {
			let viewport = MapViewport(zoom: zoom, center: Point(x: 300, y: 200))
			let c = changed(try render(drawing, viewport: viewport, pins: layer), try render(drawing, viewport: viewport, pins: nil))
			counts.append(c.count)
		}
		#expect(counts.allSatisfy { $0 > 300 } && abs(Double(counts[0] - counts[1])) / Double(counts[0]) < 0.1, "marker pixels at zoom 1 and 3: \(counts)")
		// panned away from the pin's place, the marker is where the map puts its anchor
		let g = MapViewportGeometry(mapWidth: 800, mapHeight: 500, viewWidth: 800, viewHeight: 500, cellSpacing: drawing.cellSpacing)
		let viewport = MapViewport(zoom: 3, center: Point(x: 330, y: 215))
		let c = changed(try render(drawing, viewport: viewport, pins: layer), try render(drawing, viewport: viewport, pins: nil))
		let anchor = g.toView(Point(x: 300, y: 200), viewport)
		let box = try #require(c.box)
		#expect(abs(box.midX - anchor.x) < 3 && abs(box.maxY - anchor.y) < 3, "the map pin stands on its anchor \(anchor): \(box)")
	}

	@MainActor
	@Test func aPinOutOfViewDrawsNothing() throws {
		let drawing = MapDrawing(map: try map())
		let layer = PinLayer(pins: [MapPin(id: "far", position: Point(x: 780, y: 480))])
		let viewport = MapViewport(zoom: 4, center: Point(x: 100, y: 80))
		let c = changed(try render(drawing, viewport: viewport, pins: layer), try render(drawing, viewport: viewport, pins: nil))
		#expect(c.count < 50, "\(c.count) pixels differ")
	}

	@MainActor
	@Test func aPinTakesItsColourFromItsKeyAndAnUnknownKeyIsRed() throws {
		let drawing = MapDrawing(map: try map())
		for (key, expected) in [("green", [0.27, 0.68, 0.33]), ("blue", [0.22, 0.47, 0.86]), ("nonsense", [0.86, 0.22, 0.20])] {
			let pixels = try render(drawing, pins: PinLayer(pins: [MapPin(id: "a", position: Point(x: 400, y: 250), color: key)]))
			let head = rgb(pixels, 400, 221)
			#expect(zip(head, expected).allSatisfy { abs($0 - $1) < 0.12 }, "\(key): \(head) against \(expected)")
		}
	}

	@MainActor
	@Test func theSelectedMarkerKeepsItsColourAndGainsAHalo() throws {
		let drawing = MapDrawing(map: try map())
		let pins = [MapPin(id: "a", position: Point(x: 400, y: 250), color: "blue")]
		let plain = try render(drawing, pins: PinLayer(pins: pins, selectedID: .constant(nil)))
		let selected = try render(drawing, pins: PinLayer(pins: pins, selectedID: .constant("a")))
		// the head's colour does not change when selected ...
		let a = rgb(plain, 400, 221), b = rgb(selected, 400, 221)
		#expect(zip(a, b).allSatisfy { abs($0 - $1) < 0.05 } && abs(b[2] - 0.86) < 0.12, "the fill: \(a) and \(b)")
		// ... but a white halo shows just outside the edge of the round head (its left edge at x = 388, y = 228) only when selected
		let outsideSelected = rgb(selected, 386, 228), outsidePlain = rgb(plain, 386, 228)
		#expect(outsideSelected.allSatisfy { $0 > 0.85 }, "the halo: \(outsideSelected)")
		#expect(!outsidePlain.allSatisfy { $0 > 0.85 }, "no halo when not selected: \(outsidePlain)")
	}

	@MainActor
	@Test func theSelectedPinIsDrawnOnTopOfOverlappingPins() throws {
		let drawing = MapDrawing(map: try map())
		// two dots (14 across) 8 points apart: the first is under the second where they overlap, unless it is selected
		let pins = [MapPin(id: "a", position: Point(x: 400, y: 250), marker: "dot", color: "blue"), MapPin(id: "b", position: Point(x: 408, y: 250), marker: "dot", color: "red")]
		let none = try render(drawing, pins: PinLayer(pins: pins, selectedID: .constant(nil)))
		let first = try render(drawing, pins: PinLayer(pins: pins, selectedID: .constant("a")))
		let overlap = (404, 250)
		let a = rgb(none, overlap.0, overlap.1), b = rgb(first, overlap.0, overlap.1)
		#expect(abs(a[0] - 0.86) < 0.12 && abs(a[2] - 0.20) < 0.12, "nothing selected: the later (red) pin is on top: \(a)")
		#expect(abs(b[0] - 0.22) < 0.12 && abs(b[2] - 0.86) < 0.12, "the selected (blue) pin is on top: \(b)")
	}

	@MainActor
	@Test func aClientCanReplaceTheMarkerItsSizeAndItsAnchor() throws {
		struct Green: PinMarkers {
			func layout(for pin: MapPin) -> PinMarkerLayout { PinMarkerLayout(size: CGSize(width: 20, height: 20), anchor: .center) }
			@MainActor func view(for pin: MapPin, isSelected: Bool) -> AnyView { AnyView(Rectangle().fill(Color(red: 0, green: 1, blue: 0))) }
		}
		let drawing = MapDrawing(map: try map())
		let with = try render(drawing, pins: PinLayer(pins: [MapPin(id: "a", position: Point(x: 400, y: 250), marker: "anything")], markers: Green()))
		for (x, y) in [(400, 250), (392, 242), (408, 258)] {
			let p = rgb(with, x, y)
			#expect(p[1] > 0.9 && p[0] < 0.1 && p[2] < 0.1, "green at \(x), \(y): \(p)")
		}
		let outside = rgb(with, 420, 270)
		#expect(!(outside[1] > 0.9 && outside[0] < 0.1), "the square is 20 across, centred on the anchor")
	}

	@MainActor
	@Test func aViewWithNoPinLayerIsTheViewAsBefore() throws {
		let drawing = MapDrawing(map: try map())
		let a = try render(drawing, pins: nil), b = try render(drawing, pins: PinLayer(pins: []))
		#expect(changed(a, b).count < 50, "an empty layer draws nothing")
	}
}
