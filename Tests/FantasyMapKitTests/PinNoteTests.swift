import CoreGraphics
import FantasyMapCore
import SwiftUI
import Testing
@testable import FantasyMapKit

/// The pin note and where a pin's marker is, for an app to put the note beside it (docs/plans/map-controls.md, step 5). The popover itself is the app's; typing, the
/// colours and the delete are the author's to try in the demo.
struct PinNoteTests {
	func drawing() throws -> MapDrawing {
		MapDrawing(map: try LandMap.generate(seed: "kaz-1", width: 800, height: 500, cellsDesired: 1_500, template: try #require(HeightmapTemplate.named("continents"))))
	}

	// MARK: where the marker is

	@Test func aMapPinsFrameStandsOnItsPlaceAndADotsFrameIsCentredOnIt() throws {
		let d = try drawing()
		let size = CGSize(width: 800, height: 500)
		let pin = MapPin(id: "a", position: Point(x: 400, y: 250))
		let frame = try #require(PinGeometry.markerFrame(of: pin, in: d, viewSize: size, viewport: .fit))
		#expect(abs(frame.midX - 400) < 0.5 && abs(frame.maxY - 250) < 0.5, "a map pin's tip is on the place")
		#expect(frame.size == StandardPinMarkers().layout(for: pin).size)
		let dot = MapPin(id: "d", position: Point(x: 400, y: 250), marker: "dot")
		let dotFrame = try #require(PinGeometry.markerFrame(of: dot, in: d, viewSize: size, viewport: .fit))
		#expect(abs(dotFrame.midX - 400) < 0.5 && abs(dotFrame.midY - 250) < 0.5, "a dot is centred on the place")
	}

	@Test func theFrameIsTheSameAsThePlacementTheViewDraws() throws {
		let d = try drawing()
		let size = CGSize(width: 700, height: 600)
		let viewport = MapViewport(zoom: 2, center: Point(x: 300, y: 200))
		let pin = MapPin(id: "a", position: Point(x: 320, y: 210))
		let g = MapViewportGeometry(mapWidth: d.width, mapHeight: d.height, viewWidth: size.width, viewHeight: size.height, cellSpacing: d.cellSpacing)
		let placed = try #require(PinGeometry.placements(pins: [pin], markers: StandardPinMarkers(), geometry: g, viewport: viewport).first)
		#expect(PinGeometry.markerFrame(of: pin, in: d, viewSize: size, viewport: viewport) == placed.frame)
	}

	@Test func aPinOutOfViewOrNotPlaceableHasNoFrame() throws {
		let d = try drawing()
		let size = CGSize(width: 800, height: 500)
		let corner = MapPin(id: "c", position: Point(x: 10, y: 10))
		#expect(PinGeometry.markerFrame(of: corner, in: d, viewSize: size, viewport: .fit) != nil)
		// zoomed in on the far corner, the first corner is out of view
		#expect(PinGeometry.markerFrame(of: corner, in: d, viewSize: size, viewport: MapViewport(zoom: 8, center: Point(x: 700, y: 450))) == nil)
		#expect(PinGeometry.markerFrame(of: MapPin(id: "n", position: Point(x: .nan, y: 5)), in: d, viewSize: size, viewport: .fit) == nil)
		// a view with no size has no frame
		#expect(PinGeometry.markerFrame(of: corner, in: d, viewSize: .zero, viewport: .fit) == nil)
	}

	@Test func aCustomMarkersSizeAndAnchorAreUsed() throws {
		struct Flag: PinMarkers {
			func layout(for pin: MapPin) -> PinMarkerLayout { PinMarkerLayout(size: CGSize(width: 40, height: 20), anchor: UnitPoint(x: 0, y: 0)) }
			@MainActor func view(for pin: MapPin, isSelected: Bool) -> AnyView { AnyView(EmptyView()) }
		}
		let d = try drawing()
		let frame = try #require(PinGeometry.markerFrame(of: MapPin(id: "f", position: Point(x: 400, y: 250)), in: d, viewSize: CGSize(width: 800, height: 500), viewport: .fit, markers: Flag()))
		#expect(abs(frame.minX - 400) < 0.5 && abs(frame.minY - 250) < 0.5 && frame.size == CGSize(width: 40, height: 20))
	}

	// MARK: the note

	@MainActor
	@Test func theNoteDrawsAndDrawingItEditsNothing() {
		var writes = 0
		var note = "the harbour"
		var color = "blue"
		let noteBinding = Binding(get: { note }, set: { note = $0; writes += 1 })
		let colorBinding = Binding(get: { color }, set: { color = $0; writes += 1 })
		let renderer = ImageRenderer(content: PinNote(note: noteBinding, color: colorBinding, onDelete: { writes += 1 }))
		renderer.scale = 1
		let image = renderer.cgImage
		#expect(image != nil && (image?.width ?? 0) > 200 && (image?.height ?? 0) > 100)
		#expect(writes == 0 && note == "the harbour" && color == "blue")
	}
}
