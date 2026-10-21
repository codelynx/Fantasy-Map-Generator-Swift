import CoreGraphics
import FantasyMapKit
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKitUI

/// Pins on the map (docs/plans/map-pins.md). **The gestures (tap to select, drag to move, press and hold or click to drop, the Delete key) cannot be driven from a
/// test**: what they call (placement, hit-testing, the drop and move arithmetic, the events' payloads) is tested here, and the rest by looking at the demo.
struct PinTests {
	func geometry(view: (Double, Double) = (800, 500)) -> MapViewportGeometry {
		MapViewportGeometry(mapWidth: 800, mapHeight: 500, viewWidth: view.0, viewHeight: view.1, cellSpacing: 12)
	}

	let markers = StandardPinMarkers()

	// MARK: the value

	@Test func aPinIsAnIdentifierAPlaceAndAMarkerKeyThatRoundTripsAsJSON() throws {
		let pin = MapPin(id: "camp", position: Point(x: 120.5, y: 300), marker: "dot", color: "blue")
		#expect(pin.marker == "dot" && pin.color == "blue" && MapPin(id: "x", position: Point(x: 1, y: 2)).marker == "pin" && MapPin(id: "x", position: Point(x: 1, y: 2)).color == "red")
		let back = try JSONDecoder().decode(MapPin.self, from: try JSONEncoder().encode(pin))
		#expect(back == pin)
		// a pin saved before it had a colour reads as red
		let old = try JSONDecoder().decode(MapPin.self, from: Data(#"{"id":"o","position":[1,2],"marker":"pin"}"#.utf8))
		#expect(old.color == "red" && old.id == "o")
		#expect(!MapPin(id: "n", position: Point(x: .nan, y: 1)).isPlaceable && !MapPin(id: "i", position: Point(x: 1, y: .infinity)).isPlaceable && pin.isPlaceable)
	}

	// MARK: placement keeps the size and follows the map

	@Test func aMarkerKeepsItsSizeWhateverTheZoomAndOnlyItsAnchorFollowsTheMap() {
		let g = geometry()
		let pin = MapPin(id: "a", position: Point(x: 300, y: 200))
		var sizes: [CGSize] = [], anchors: [CGPoint] = []
		for zoom in [1.0, 2, 4] {
			let viewport = MapViewport(zoom: zoom, center: Point(x: 300, y: 200))
			let p = PinGeometry.placements(pins: [pin], markers: markers, geometry: g, viewport: viewport)
			sizes.append(p[0].frame.size)
			anchors.append(p[0].anchor)
			let expected = g.toView(pin.position, viewport)
			#expect(abs(p[0].anchor.x - expected.x) < 1e-9 && abs(p[0].anchor.y - expected.y) < 1e-9, "the anchor is where the map puts the pin's place")
		}
		#expect(sizes[0] == sizes[1] && sizes[1] == sizes[2] && sizes[0] == markers.pinSize, "the marker is the same size at every zoom")
		// the pin is at the centre of the view when the viewport is centred on it
		#expect(abs(anchors[2].x - 400) < 1e-9 && abs(anchors[2].y - 250) < 1e-9)
		// panning moves the anchor with the map
		let panned = PinGeometry.placements(pins: [pin], markers: markers, geometry: g, viewport: MapViewport(zoom: 4, center: Point(x: 310, y: 200)))
		#expect(abs(panned[0].anchor.x - (400 - 10 * g.scale(zoom: 4))) < 1e-9)
	}

	@Test func theMarkerFrameIsPositionedByItsAnchor() {
		let g = geometry()
		let at = Point(x: 400, y: 250) // the centre of the view at fit (scale 1)
		for (kind, expectedOrigin) in [("pin", CGPoint(x: 400 - 12, y: 250 - 34)), ("dot", CGPoint(x: 400 - 7, y: 250 - 7)), ("unknown", CGPoint(x: 400 - 12, y: 250 - 34))] {
			let p = PinGeometry.placements(pins: [MapPin(id: kind, position: at, marker: kind)], markers: markers, geometry: g, viewport: .fit)[0]
			#expect(p.frame.origin == expectedOrigin, "\(kind): \(p.frame.origin)")
			#expect(p.anchor == CGPoint(x: 400, y: 250))
		}
	}

	@Test func aPinOutOfViewIsNotVisibleButOneWhoseMarkerReachesInIs() {
		let g = geometry()
		let pins = [MapPin(id: "in", position: Point(x: 400, y: 250)), MapPin(id: "off", position: Point(x: 790, y: 490)), MapPin(id: "edge", position: Point(x: 400, y: 500 + 20))]
		// zoomed in on the middle, the corner pin is far outside the view; a pin just below the view whose marker (it rises above its tip) reaches in is visible
		let zoomed = MapViewport(zoom: 3, center: Point(x: 400, y: 250))
		let placed = PinGeometry.placements(pins: pins, markers: markers, geometry: g, viewport: zoomed)
		#expect(placed.first { $0.id == "in" }!.isVisible && !placed.first { $0.id == "off" }!.isVisible)
		let below = PinGeometry.placements(pins: [MapPin(id: "t", position: g.toMap(Point(x: 400, y: 510), .fit))], markers: markers, geometry: g, viewport: .fit)[0]
		#expect(below.anchor.y == 510 && below.isVisible, "the marker rises from below the view into it")
		let farBelow = PinGeometry.placements(pins: [MapPin(id: "t", position: g.toMap(Point(x: 400, y: 600), .fit))], markers: markers, geometry: g, viewport: .fit)[0]
		#expect(!farBelow.isVisible)
	}

	@Test func pinsThatCannotBePlacedAreLeftOut() {
		let g = geometry()
		let pins = [MapPin(id: "ok", position: Point(x: 1, y: 1)), MapPin(id: "nan", position: Point(x: .nan, y: 1)), MapPin(id: "inf", position: Point(x: 1, y: .infinity))]
		#expect(PinGeometry.placements(pins: pins, markers: markers, geometry: g, viewport: .fit).map(\.id) == ["ok"])
		// an unusable geometry places nothing
		let broken = MapViewportGeometry(mapWidth: 0, mapHeight: 500, viewWidth: 800, viewHeight: 500, cellSpacing: 12)
		#expect(PinGeometry.placements(pins: pins, markers: markers, geometry: broken, viewport: .fit).isEmpty)
		// a marker layout that is not a size is not placed
		struct BadMarkers: PinMarkers {
			func layout(for pin: MapPin) -> PinMarkerLayout { PinMarkerLayout(size: CGSize(width: Double.nan, height: 10), anchor: .center) }
			@MainActor func view(for pin: MapPin, isSelected: Bool) -> AnyView { AnyView(EmptyView()) }
		}
		#expect(PinGeometry.placements(pins: pins, markers: BadMarkers(), geometry: g, viewport: .fit).isEmpty)
		// each way a layout can be wrong: a height or a width that is not a number or is negative or infinite, and an anchor that is not finite
		struct Layout: PinMarkers {
			var value: PinMarkerLayout
			func layout(for pin: MapPin) -> PinMarkerLayout { value }
			@MainActor func view(for pin: MapPin, isSelected: Bool) -> AnyView { AnyView(EmptyView()) }
		}
		let one = [MapPin(id: "ok", position: Point(x: 1, y: 1))]
		let bad: [PinMarkerLayout] = [
			PinMarkerLayout(size: CGSize(width: 10, height: Double.nan), anchor: .center), PinMarkerLayout(size: CGSize(width: -1, height: 10), anchor: .center),
			PinMarkerLayout(size: CGSize(width: 10, height: -1), anchor: .center), PinMarkerLayout(size: CGSize(width: Double.infinity, height: 10), anchor: .center),
			PinMarkerLayout(size: CGSize(width: 10, height: Double.infinity), anchor: .center), PinMarkerLayout(size: CGSize(width: 10, height: 10), anchor: UnitPoint(x: Double.nan, y: 0.5)),
			PinMarkerLayout(size: CGSize(width: 10, height: 10), anchor: UnitPoint(x: 0.5, y: Double.infinity))
		]
		for layout in bad { #expect(PinGeometry.placements(pins: one, markers: Layout(value: layout), geometry: g, viewport: .fit).isEmpty, "\(layout)") }
		#expect(PinGeometry.placements(pins: one, markers: Layout(value: PinMarkerLayout(size: CGSize(width: 10, height: 10), anchor: .center)), geometry: g, viewport: .fit).count == 1)
		// a place so far out that its position on the screen overflows is not placed
		#expect(PinGeometry.placements(pins: [MapPin(id: "far", position: Point(x: 1e308, y: 1e308))], markers: markers, geometry: g, viewport: MapViewport(zoom: 4, center: Point(x: 400, y: 250))).isEmpty)
	}

	// MARK: hit-testing

	@Test func theTopmostPinUnderAPointIsHitAndNoneElsewhere() {
		let g = geometry()
		// two dots, 8 points apart: their frames (14 wide) overlap
		let pins = [MapPin(id: "under", position: Point(x: 400, y: 250), marker: "dot"), MapPin(id: "over", position: Point(x: 408, y: 250), marker: "dot")]
		let placed = PinGeometry.placements(pins: pins, markers: markers, geometry: g, viewport: .fit)
		#expect(PinGeometry.hit(at: CGPoint(x: 404, y: 250), placements: placed) == "over", "in the overlap the later pin is on top")
		#expect(PinGeometry.hit(at: CGPoint(x: 394, y: 250), placements: placed) == "under")
		#expect(PinGeometry.hit(at: CGPoint(x: 414, y: 250), placements: placed) == "over")
		#expect(PinGeometry.hit(at: CGPoint(x: 100, y: 100), placements: placed) == nil)
		// the slop grows a frame: just outside is a miss without it, a hit with it
		#expect(PinGeometry.hit(at: CGPoint(x: 430, y: 250), placements: placed) == nil)
		#expect(PinGeometry.hit(at: CGPoint(x: 417, y: 250), placements: placed) == nil && PinGeometry.hit(at: CGPoint(x: 417, y: 250), placements: placed, slop: 4) == "over")
		// a pin out of view is never hit
		var hidden = placed
		hidden[1].isVisible = false
		#expect(PinGeometry.hit(at: CGPoint(x: 414, y: 250), placements: hidden) == nil)
		// the marker's frame rises from the anchor: a map pin is hit above its tip, not below it
		let one = PinGeometry.placements(pins: [MapPin(id: "p", position: Point(x: 400, y: 250))], markers: markers, geometry: g, viewport: .fit)
		#expect(PinGeometry.hit(at: CGPoint(x: 400, y: 230), placements: one) == "p" && PinGeometry.hit(at: CGPoint(x: 400, y: 260), placements: one) == nil)
	}

	@Test func theHitFrameIsTheMarkersFrameGrownBySlopAndTheHitTestUsesIt() {
		let g = geometry()
		let p = PinGeometry.placements(pins: [MapPin(id: "p", position: Point(x: 400, y: 250))], markers: markers, geometry: g, viewport: .fit)[0]
		#expect(p.hitFrame(slop: 0) == p.frame && p.hitFrame(slop: 4) == CGRect(x: p.frame.minX - 4, y: p.frame.minY - 4, width: p.frame.width + 8, height: p.frame.height + 8))
		// a point just outside the frame and inside the slop is on the pin (selects it, and is not a tap on the map); just beyond is not
		let outside = CGPoint(x: p.frame.maxX + 3, y: p.frame.midY)
		#expect(PinGeometry.hit(at: outside, placements: [p], slop: 0) == nil && PinGeometry.hit(at: outside, placements: [p], slop: 4) == "p")
		#expect(PinGeometry.hit(at: CGPoint(x: p.frame.maxX + 5, y: p.frame.midY), placements: [p], slop: 4) == nil)
	}

	@Test func aSingleTapOnTheMapDeselectsDropsOrDoesNothingAndNeverActsOnAPin() {
		let g = geometry()
		let placed = PinGeometry.placements(pins: [MapPin(id: "p", position: Point(x: 400, y: 250))], markers: markers, geometry: g, viewport: .fit)
		let onPin = CGPoint(x: 400, y: 235), nearPin = CGPoint(x: 414, y: 240) // the second is within the slop of the frame (x up to 412), not inside it
		let away = CGPoint(x: 100, y: 100)
		for mode in [PinDropMode.click, .longPress, .off] {
			for selected in [true, false] {
				#expect(PinTapAction.decide(tapAt: onPin, placements: placed, hasSelection: selected, dropMode: mode, slop: 4) == .none, "on a pin: the marker takes it")
				#expect(PinTapAction.decide(tapAt: nearPin, placements: placed, hasSelection: selected, dropMode: mode, slop: 4) == .none, "within the slop of a pin it is still the pin's")
			}
		}
		// away from every pin: a selection is ended first, whatever the mode
		for mode in [PinDropMode.click, .longPress, .off] { #expect(PinTapAction.decide(tapAt: away, placements: placed, hasSelection: true, dropMode: mode, slop: 4) == .deselect) }
		// nothing selected: only click mode drops
		#expect(PinTapAction.decide(tapAt: away, placements: placed, hasSelection: false, dropMode: .click, slop: 4) == .drop)
		#expect(PinTapAction.decide(tapAt: away, placements: placed, hasSelection: false, dropMode: .longPress, slop: 4) == .none)
		#expect(PinTapAction.decide(tapAt: away, placements: placed, hasSelection: false, dropMode: .off, slop: 4) == .none)
		// the tap outside the slop but near the pin is a tap on the map
		#expect(PinTapAction.decide(tapAt: CGPoint(x: 420, y: 240), placements: placed, hasSelection: false, dropMode: .click, slop: 4) == .drop)
	}

	// MARK: dropping and moving

	@Test func aPinDroppedInTheViewLandsOnTheMapPointUnderItAndNotInTheMargin() {
		let g = geometry(view: (1000, 500)) // the 800 wide map is centred: 100 points of paper on each side
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 500, y: 250), geometry: g, viewport: .fit) == Point(x: 400, y: 250))
		let zoomed = MapViewport(zoom: 2, center: Point(x: 200, y: 100))
		let place = PinGeometry.dropPoint(atView: CGPoint(x: 500, y: 250), geometry: g, viewport: zoomed)
		#expect(place == g.toMap(Point(x: 500, y: 250), zoomed))
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 50, y: 250), geometry: g, viewport: .fit) == nil, "the margin is not the map")
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 1000, y: 250), geometry: g, viewport: .fit) == nil)
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: Double.nan, y: 250), geometry: g, viewport: .fit) == nil)
		// the same above and below the map: a view taller than the map has margin at the top and the bottom
		let tall = geometry(view: (800, 700)) // the 500 high map is centred: 100 points of paper above and below
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 400, y: 50), geometry: tall, viewport: .fit) == nil)
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 400, y: 650), geometry: tall, viewport: .fit) == nil)
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 400, y: 100), geometry: tall, viewport: .fit) == Point(x: 400, y: 0))
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 400, y: 600), geometry: tall, viewport: .fit) == Point(x: 400, y: 500))
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: Double.nan, y: 250), geometry: g, viewport: .fit) == nil && PinGeometry.dropPoint(atView: CGPoint(x: 400, y: Double.infinity), geometry: g, viewport: .fit) == nil)
		// the corners of the map are inside
		#expect(PinGeometry.dropPoint(atView: CGPoint(x: 100, y: 0), geometry: g, viewport: .fit) == Point(x: 0, y: 0))
	}

	@Test func aDraggedPinLandsWhereItIsDroppedAndStopsAtTheMapsEdge() {
		let g = geometry()
		let anchor = CGPoint(x: 400, y: 250)
		#expect(PinGeometry.movedPosition(anchor: anchor, translation: CGSize(width: 30, height: -20), geometry: g, viewport: .fit) == Point(x: 430, y: 230))
		let zoomed = MapViewport(zoom: 2, center: Point(x: 400, y: 250))
		let moved = PinGeometry.movedPosition(anchor: anchor, translation: CGSize(width: 40, height: 0), geometry: g, viewport: zoomed)
		#expect(moved != nil && abs(moved!.x - 420) < 1e-9, "at zoom 2 a drag of 40 points is 20 map units: \(String(describing: moved))")
		// dragged beyond the map the pin stops at its edge
		#expect(PinGeometry.movedPosition(anchor: anchor, translation: CGSize(width: 5000, height: -5000), geometry: g, viewport: .fit) == Point(x: 800, y: 0))
		#expect(PinGeometry.movedPosition(anchor: anchor, translation: CGSize(width: -5000, height: 5000), geometry: g, viewport: .fit) == Point(x: 0, y: 500))
		#expect(PinGeometry.movedPosition(anchor: anchor, translation: CGSize(width: Double.nan, height: 0), geometry: g, viewport: .fit) == nil)
	}

	// MARK: the standard markers

	@Test func theStandardMarkersHaveTheirAnchorsAndSizes() {
		let m = StandardPinMarkers()
		#expect(m.layout(for: MapPin(id: "a", position: Point(x: 0, y: 0))) == PinMarkerLayout(size: CGSize(width: 24, height: 34), anchor: UnitPoint(x: 0.5, y: 1)))
		#expect(m.layout(for: MapPin(id: "a", position: Point(x: 0, y: 0), marker: "dot")) == PinMarkerLayout(size: CGSize(width: 14, height: 14), anchor: .center))
		#expect(m.layout(for: MapPin(id: "a", position: Point(x: 0, y: 0), marker: "tab")) == m.layout(for: MapPin(id: "a", position: Point(x: 0, y: 0))), "an unknown marker is a map pin")
		var big = StandardPinMarkers()
		big.pinSize = CGSize(width: 40, height: 56)
		#expect(big.layout(for: MapPin(id: "a", position: Point(x: 0, y: 0))).size == CGSize(width: 40, height: 56), "sizes are the client's to set")
	}

	@Test func theStandardMarkersOfferAFewLightColoursAndAnUnknownKeyIsRed() {
		let m = StandardPinMarkers()
		#expect(StandardPinMarkers.colorKeys == ["red", "orange", "yellow", "green", "blue", "purple"])
		#expect(Set(StandardPinMarkers.colorKeys).count == 6 && StandardPinMarkers.colorKeys.allSatisfy { m.colors[$0] != nil })
		#expect(m.color(for: "nonsense") == m.color(for: "red") && m.color(for: "blue") != m.color(for: "red"))
		var custom = StandardPinMarkers()
		custom.colors = ["red": .black]
		#expect(custom.color(for: "blue") == .black, "a client's own palette: an unknown key is its red")
	}

	@Test func theMapPinIsACircleOnAPoint() {
		let rect = CGRect(x: 0, y: 0, width: 24, height: 34)
		let path = TeardropShape().path(in: rect)
		#expect(abs(path.boundingRect.minX) < 1 && abs(path.boundingRect.maxX - 24) < 1 && abs(path.boundingRect.minY) < 1 && abs(path.boundingRect.maxY - 34) < 1)
		#expect(path.contains(CGPoint(x: 12, y: 12)), "the round head")
		#expect(path.contains(CGPoint(x: 12, y: 30)), "the tapering point")
		#expect(!path.contains(CGPoint(x: 1, y: 33)) && !path.contains(CGPoint(x: 23, y: 33)) && !path.contains(CGPoint(x: 1, y: 1)) && !path.contains(CGPoint(x: 23, y: 1)), "the corners are empty")
	}

	// MARK: events

	@Test func anEventCarriesWhatTheClientNeeds() {
		let events: [PinEvent] = [.dropped(at: Point(x: 1, y: 2)), .selected(id: "a", anchor: CGPoint(x: 3, y: 4)), .deselected, .moved(id: "a", to: Point(x: 5, y: 6)), .removeRequested(id: "a")]
		#expect(events.count == 5 && events[0] == .dropped(at: Point(x: 1, y: 2)) && events[1] != .selected(id: "a", anchor: CGPoint(x: 0, y: 0)))
		let layer = PinLayer(pins: [])
		#expect(layer.dropMode == .longPress && layer.isDraggable && layer.hitSlop == 4 && layer.selectedID == nil)
	}
}
