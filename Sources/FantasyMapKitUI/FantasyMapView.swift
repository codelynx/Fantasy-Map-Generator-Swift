import FantasyMapKit
import SwiftUI

/// A SwiftUI view of a land map: the same drawing the image renderer makes, drawn into a `Canvas` that fills the space it is
/// given and keeps the map's proportions, with the style's paper colour around it.
///
/// **Prepare the drawing once.** Building a `MapDrawing` costs time (about 9 ms for 10,000 cells and 105 ms for 100,000, in a
/// release build on the machine this was built on), and SwiftUI may recreate a view's value whenever its parent updates, so
/// the recommended path is `init(drawing:)`: the caller keeps a prepared `MapDrawing` and rebuilds it only when the map or the
/// style changes. `init(map:style:)` is a convenience for small maps and one-off use and builds the drawing every time it runs.
public struct FantasyMapView: View {
	public let drawing: MapDrawing
	/// Whether the view zooms and pans (on by default: client code gets zoom without writing any). Off, the view is fixed at fit, as it drew before zooming existed.
	public var isInteractive: Bool
	/// The numbers behind the zoom (provisional; see `ViewportPolicy`).
	public var policy: ViewportPolicy
	/// Tells the view the map is a different one: **when it changes, the viewport returns to fit.** The client says so explicitly; the view never compares a large
	/// drawing to find out. A presentation change (colours, line widths, overlays) keeps the viewport, because the identity stays the same.
	public var mapIdentity: AnyHashable?

	/// The pins on the map and how they behave (docs/plans/map-pins.md); nil shows none, and the view behaves as before.
	public var pinLayer: PinLayer?
	private var boundViewport: Binding<MapViewport>?
	@State private var ownSelection: String?
	@State private var dragging: (id: String, translation: CGSize)?
	@State private var ownViewport = MapViewport.fit
	/// The drag and the pinch together, from one baseline (see `ViewportGestureSession`); cleared when interaction is switched off or the map changes.
	@State private var session: ViewportGestureSession?

	/// Builds the drawing here, every time this runs: a convenience, not the recommended path for a large map.
	public init(map: LandMap, style: MapStyle = .standard, viewport: Binding<MapViewport>? = nil, mapIdentity: AnyHashable? = nil, isInteractive: Bool = true, policy: ViewportPolicy = ViewportPolicy(), pinLayer: PinLayer? = nil) {
		self.init(drawing: MapDrawing(map: map, style: style), viewport: viewport, mapIdentity: mapIdentity, isInteractive: isInteractive, policy: policy, pinLayer: pinLayer)
	}

	/// The same for a water map: its land and its rivers.
	public init(water: WaterMap, style: MapStyle = .standard, viewport: Binding<MapViewport>? = nil, mapIdentity: AnyHashable? = nil, isInteractive: Bool = true, policy: ViewportPolicy = ViewportPolicy(), pinLayer: PinLayer? = nil) {
		self.init(drawing: MapDrawing(water: water, style: style), viewport: viewport, mapIdentity: mapIdentity, isInteractive: isInteractive, policy: policy, pinLayer: pinLayer)
	}

	/// The recommended path: a drawing the caller has prepared and keeps. **`viewport`** binds the zoom and centre to the client's own state (to save, reset or
	/// move the map from outside); without it the view keeps its own.
	public init(drawing: MapDrawing, viewport: Binding<MapViewport>? = nil, mapIdentity: AnyHashable? = nil, isInteractive: Bool = true, policy: ViewportPolicy = ViewportPolicy(), pinLayer: PinLayer? = nil) {
		self.drawing = drawing
		self.boundViewport = viewport
		self.mapIdentity = mapIdentity
		self.isInteractive = isInteractive
		self.policy = policy
		self.pinLayer = pinLayer
	}

	private var viewport: Binding<MapViewport> { boundViewport ?? $ownViewport }

	private func geometry(_ size: CGSize) -> MapViewportGeometry {
		MapViewportGeometry(mapWidth: drawing.width, mapHeight: drawing.height, viewWidth: size.width, viewHeight: size.height, cellSpacing: drawing.cellSpacing, policy: policy)
	}

	public var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .topLeading) {
				canvas(size: proxy.size)
					.modifier(ViewportInteraction(isInteractive: isInteractive, size: proxy.size, geometry: geometry(proxy.size), viewport: viewport, session: $session, singleTap: pinLayer.map { layer in { point in singleTap(at: point, layer: layer, size: proxy.size) } }))
					.modifier(PinDropModifier(layer: pinLayer, makeGesture: { layer in dropGesture(layer, size: proxy.size, geometry: geometry(proxy.size), shown: isInteractive ? viewport.wrappedValue : .fit, placements: PinGeometry.placements(pins: layer.pins, markers: layer.markers, geometry: geometry(proxy.size), viewport: isInteractive ? viewport.wrappedValue : .fit)) }))
				if let pinLayer { pinOverlay(pinLayer, size: proxy.size) }
			}
		}
		.onChange(of: mapIdentity) { session = nil; viewport.wrappedValue = .fit }
		.onChange(of: isInteractive) { session = nil }
	}

	private func canvas(size viewSize: CGSize) -> some View {
		let drawing = drawing
		let g = geometry(viewSize)
		let shown = isInteractive ? viewport.wrappedValue : .fit
		return Canvas { context, size in
			context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color(drawing.paper)))
			guard drawing.width > 0, drawing.height > 0, size.width > 0, size.height > 0,
				// every number of the transform is checked to be finite before the graphics context sees it: an overflow draws only the paper
				let t = g.validTransform(shown) else { return }
			// the viewport's transform: a map point p shows at p × scale + offset, and the map is clipped to its own rectangle on the screen
			let scale = t.scale
			context.clip(to: Path(CGRect(x: t.offsetX, y: t.offsetY, width: drawing.width * scale, height: drawing.height * scale)))
			context.translateBy(x: t.offsetX, y: t.offsetY)
			context.scaleBy(x: scale, y: scale)
			// half a DEVICE pixel in map units (a point is more than one device pixel on a 2x or 3x display): hides seams between
			// neighbouring cells, as the image renderer's half output pixel does
			let hairline = 0.5 / (scale * max(context.environment.displayScale, 1))
			func paint(_ fills: [FillCommand], in context: GraphicsContext) {
				for fill in fills {
					guard let first = fill.points.first else { continue }
					var path = Path()
					path.move(to: CGPoint(x: first.x, y: first.y))
					for p in fill.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
					path.closeSubpath()
					let color = Self.color(fill.color)
					context.fill(path, with: .color(color))
					if fill.color.alpha >= 1 { context.stroke(path, with: .color(color), lineWidth: hairline) } // opaque cells only
				}
			}
			func paintRivers(in context: GraphicsContext) {
				for river in drawing.rivers {
					guard let first = river.points.first else { continue }
					var path = Path()
					path.move(to: CGPoint(x: first.x, y: first.y))
					for p in river.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
					path.closeSubpath()
					context.fill(path, with: .color(Self.color(river.color)))
				}
			}
			if let rings = drawing.landClip {
				// water as it is, then the land clipped to the same outline the ink follows
				paint(drawing.receded, in: context)
				paint(drawing.fills.filter { !$0.isLand }, in: context)
				var land = context
				var clip = Path()
				for ring in rings {
					guard let first = ring.first else { continue }
					clip.move(to: CGPoint(x: first.x, y: first.y))
					for p in ring.dropFirst() { clip.addLine(to: CGPoint(x: p.x, y: p.y)) }
					clip.closeSubpath()
				}
				land.clip(to: clip, style: FillStyle(eoFill: true))
				paint(drawing.exposed, in: land)
				paint(drawing.fills.filter(\.isLand), in: land)
				// the realms' wash: opaque polygons drawn together at the wash opacity (so overlaps do not darken), under the rivers
				if drawing.realmWashOpacity > 0, !drawing.realmWash.isEmpty {
					var washed = land
					washed.opacity = drawing.realmWashOpacity
					washed.drawLayer { layer in paint(drawing.realmWash, in: layer) }
				}
				// the rivers, over the land and clipped to the same outline, so a widened river never paints on the water
				paintRivers(in: land)
				// the realms' borders, dashed, over the rivers, clipped to the land
				for line in drawing.realmBorders {
					guard let first = line.points.first, line.width > 0 else { continue }
					var path = Path()
					path.move(to: CGPoint(x: first.x, y: first.y))
					for p in line.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
					if line.isClosed { path.closeSubpath() }
					land.stroke(path, with: .color(Self.color(line.color)), style: StrokeStyle(lineWidth: line.width, lineCap: .butt, lineJoin: .round, dash: line.dash.map { CGFloat($0) }))
				}
			} else {
				paint(drawing.fills, in: context)
				paintRivers(in: context) // the coast is not trusted: the rivers are drawn as generated
			}
			// the coastline ink, over the fills, in map units
			for line in drawing.ink {
				guard let first = line.points.first, line.width > 0 else { continue }
				var path = Path()
				path.move(to: CGPoint(x: first.x, y: first.y))
				for p in line.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
				if line.isClosed { path.closeSubpath() }
				context.stroke(path, with: .color(Self.color(line.color)), style: StrokeStyle(lineWidth: line.width, lineCap: .round, lineJoin: .round))
			}
		}
	}

	nonisolated static func color(_ c: MapColor) -> Color {
		Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
	}
}

/// The gestures and keys of the zoom, as one modifier so that the drawing stays apart from the interaction. **Gestures:** pinch zooms around the pinch point and
/// drag pans (together they move and zoom at once, each applied to the viewport the gesture started from); a double click or double tap zooms in one step around
/// the point; on a Mac Option-scroll zooms around the pointer and plain scrolling is left to the interface around the view; `+`, `-` and `0` zoom in, out and to
/// fit from the keyboard, and the view offers Fit, Zoom in and Zoom out as accessibility actions. **Fit is never only a gesture.** Interaction off, nothing is handled.
struct ViewportInteraction: ViewModifier {
	var isInteractive: Bool
	var size: CGSize
	var geometry: MapViewportGeometry
	@Binding var viewport: MapViewport
	@Binding var session: ViewportGestureSession?
	/// What a single tap on the map does (nil: nothing, as in a view without pins). **It is handed only a tap that was not the first of a double tap:** the double tap that zooms
	/// takes precedence, and the single tap waits for it to fail.
	var singleTap: ((CGPoint) -> Void)? = nil

	/// The double tap zooms and has precedence; a single tap is only offered once the double tap has failed.
	private var tapGestures: some Gesture {
		SpatialTapGesture(count: 2)
			.onEnded { value in
				viewport = geometry.zoomed(viewport, by: geometry.policy.doubleClickFactor, around: Point(x: value.location.x, y: value.location.y))
			}
			.exclusively(before: SpatialTapGesture(count: 1).onEnded { value in singleTap?(value.location) })
	}

	func body(content: Content) -> some View {
		if !isInteractive {
			content
		} else {
			content
				.contentShape(Rectangle())
				.gesture(
					DragGesture(minimumDistance: 2)
						.onChanged { value in
							var s = session ?? ViewportGestureSession(base: viewport)
							s.dragChanged(dx: value.translation.width, dy: value.translation.height)
							session = s
							viewport = s.viewport(geometry)
						}
						.onEnded { _ in
							guard var s = session else { return }
							s.dragEnded(geometry)
							session = s.isIdle ? nil : s
						}
				)
				.simultaneousGesture(
					MagnifyGesture()
						.onChanged { value in
							var s = session ?? ViewportGestureSession(base: viewport)
							s.magnifyChanged(magnification: value.magnification, anchor: Point(x: value.startLocation.x, y: value.startLocation.y))
							session = s
							viewport = s.viewport(geometry)
						}
						.onEnded { _ in
							guard var s = session else { return }
							s.magnifyEnded(geometry)
							session = s.isIdle ? nil : s
						}
				)
				.gesture(tapGestures)
				#if os(macOS)
				.background(OptionScrollZoom { delta, location in
					viewport = geometry.zoomed(viewport, by: exp(delta * geometry.policy.scrollSensitivity), around: Point(x: location.x, y: location.y))
				})
				#endif
				.focusable()
				.focusEffectDisabled()
				.onKeyPress(characters: CharacterSet(charactersIn: "+=-_0")) { press in
					let center = Point(x: size.width / 2, y: size.height / 2)
					switch press.characters {
					case "+", "=": viewport = geometry.zoomed(viewport, by: geometry.policy.keyboardFactor, around: center)
					case "-", "_": viewport = geometry.zoomed(viewport, by: 1 / geometry.policy.keyboardFactor, around: center)
					default: viewport = .fit
					}
					return .handled
				}
				.accessibilityAction(named: "Fit to window") { viewport = .fit }
				.accessibilityAction(named: "Zoom in") { viewport = geometry.zoomed(viewport, by: geometry.policy.keyboardFactor, around: Point(x: size.width / 2, y: size.height / 2)) }
				.accessibilityAction(named: "Zoom out") { viewport = geometry.zoomed(viewport, by: 1 / geometry.policy.keyboardFactor, around: Point(x: size.width / 2, y: size.height / 2)) }
		}
	}
}

#if os(macOS)
import AppKit

/// Option-scroll on a Mac: a local scroll-wheel monitor that handles a scroll over its view **only while Option is held** and passes every other scroll on, so
/// plain scrolling stays available to the interface around the map. It takes no mouse events itself (it is only a background).
struct OptionScrollZoom: NSViewRepresentable {
	var onZoom: (_ delta: Double, _ location: CGPoint) -> Void

	func makeNSView(context: Context) -> MonitorView {
		let view = MonitorView()
		view.onZoom = onZoom
		return view
	}

	func updateNSView(_ view: MonitorView, context: Context) { view.onZoom = onZoom }

	final class MonitorView: NSView {
		var onZoom: ((Double, CGPoint) -> Void)?
		private var monitor: Any?

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			// leaving a window removes the monitor (this is also how it is released when the view goes away)
			if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
			guard window != nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
				guard let self, event.window === self.window, event.modifierFlags.contains(.option) else { return event }
				let point = self.convert(event.locationInWindow, from: nil)
				guard self.bounds.contains(point) else { return event }
				// the view's y runs up, SwiftUI's down
				self.onZoom?(Double(event.scrollingDeltaY), CGPoint(x: point.x, y: self.bounds.height - point.y))
				return nil
			}
		}

		override func hitTest(_ point: NSPoint) -> NSView? { nil }
	}
}
#endif


// MARK: the pin layer

extension FantasyMapView {
	private var selection: Binding<String?> { pinLayer?.selectedID ?? $ownSelection }

	/// The markers over the map, each at its anchor and at its own size; a marker has its own tap and drag (taking priority over the map's pan, so dragging a pin does not
	/// move the map), and the rest of the layer takes no events. A tap on the map away from any pin deselects (and, in click mode with nothing selected, drops a pin); a press
	/// and hold drops one in the default mode; Delete asks the client to remove the selected pin.
	@ViewBuilder
	func pinOverlay(_ layer: PinLayer, size: CGSize) -> some View {
		let g = geometry(size)
		let shown = isInteractive ? viewport.wrappedValue : MapViewport.fit
		let placements = PinGeometry.placements(pins: layer.pins, markers: layer.markers, geometry: g, viewport: shown)
		let byID = Dictionary(placements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		let selected = selection.wrappedValue
		// the selected marker is drawn last, on top
		let ordered = layer.pins.filter { byID[$0.id] != nil && $0.id != selected } + layer.pins.filter { byID[$0.id] != nil && $0.id == selected }
		ZStack(alignment: .topLeading) {
			Color.clear.allowsHitTesting(false)
			ForEach(ordered) { pin in
				if let placement = byID[pin.id], placement.isVisible {
					let isSelected = pin.id == selected
					let offset = dragging.flatMap { $0.id == pin.id ? $0.translation : nil } ?? .zero
					layer.markers.view(for: pin, isSelected: isSelected)
						.frame(width: placement.frame.width, height: placement.frame.height)
						.padding(layer.hitSlop) // the marker's selection area is its frame grown by the slop, as the hit test's
						.contentShape(Rectangle())
						.position(x: placement.frame.midX + offset.width, y: placement.frame.midY + offset.height)
						.highPriorityGesture(markerGesture(layer, pin: pin, placement: placement, geometry: g, shown: shown))
				}
			}
		}
		.frame(width: size.width, height: size.height)
		.clipped()
		.focusable()
		.focusEffectDisabled()
		.onKeyPress(keys: [.delete, .deleteForward]) { _ in
			guard let id = selection.wrappedValue else { return .ignored }
			layer.onEvent(.removeRequested(id: id))
			return .handled
		}
	}

	/// A tap selects the pin; a drag moves it (when the layer allows). The pin follows the pointer while dragging, and the client is told where it landed.
	private func markerGesture(_ layer: PinLayer, pin: MapPin, placement: PinPlacement, geometry g: MapViewportGeometry, shown: MapViewport) -> some Gesture {
		DragGesture(minimumDistance: layer.isDraggable ? 4 : .infinity)
			.onChanged { value in dragging = (pin.id, value.translation) }
			.onEnded { value in
				dragging = nil
				if let landed = PinGeometry.movedPosition(anchor: placement.anchor, translation: value.translation, geometry: g, viewport: shown) { layer.onEvent(.moved(id: pin.id, to: landed)) }
			}
			.simultaneously(with: TapGesture().onEnded { select(pin.id, placement: placement, layer: layer) })
	}

	private func select(_ id: String, placement: PinPlacement, layer: PinLayer) {
		selection.wrappedValue = id
		layer.onEvent(.selected(id: id, anchor: placement.anchor))
	}

	/// What a single tap on the map does, by `PinTapAction`: deselect, or (in click mode with nothing selected) drop a pin. A tap on a pin is the marker's, and a double tap never gets here.
	func singleTap(at point: CGPoint, layer: PinLayer, size: CGSize) {
		let g = geometry(size)
		let shown = isInteractive ? viewport.wrappedValue : MapViewport.fit
		let placements = PinGeometry.placements(pins: layer.pins, markers: layer.markers, geometry: g, viewport: shown)
		switch PinTapAction.decide(tapAt: point, placements: placements, hasSelection: selection.wrappedValue != nil, dropMode: layer.dropMode, slop: layer.hitSlop) {
		case .none: break
		case .deselect:
			selection.wrappedValue = nil
			layer.onEvent(.deselected)
		case .drop:
			if let place = PinGeometry.dropPoint(atView: point, geometry: g, viewport: shown) { layer.onEvent(.dropped(at: place)) }
		}
	}

	/// Dropping by press and hold, on the map itself (away from any pin).
	func dropGesture(_ layer: PinLayer, size: CGSize, geometry g: MapViewportGeometry, shown: MapViewport, placements: [PinPlacement]) -> some Gesture {
		LongPressGesture(minimumDuration: 0.6)
			.sequenced(before: DragGesture(minimumDistance: 0))
			.onEnded { value in
				guard layer.dropMode == .longPress, case .second(true, let drag?) = value else { return }
				guard PinGeometry.hit(at: drag.startLocation, placements: placements, slop: layer.hitSlop) == nil else { return }
				if let place = PinGeometry.dropPoint(atView: drag.startLocation, geometry: g, viewport: shown) { layer.onEvent(.dropped(at: place)) }
			}
	}
}


/// Attaches the press-and-hold drop to the map itself, alongside the zoom and pan gestures (which keep working), when the view has a pin layer.
struct PinDropModifier<G: Gesture>: ViewModifier {
	var layer: PinLayer?
	var makeGesture: (PinLayer) -> G

	@ViewBuilder
	func body(content: Content) -> some View {
		if let layer {
			content.simultaneousGesture(makeGesture(layer))
		} else {
			content
		}
	}
}
