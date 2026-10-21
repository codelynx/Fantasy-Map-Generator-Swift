import FantasyMapKit
import Foundation
import SwiftUI

// Pins on the map (docs/plans/map-pins.md). The framework owns the layer: it keeps pins at their places in map coordinates while the map zooms and pans, draws their
// markers at a constant size on the screen, hit-tests them, and reports dropping, selecting, moving and removing as events. It owns **no annotation and no saving**:
// a pin carries an identifier the client chooses and a marker key, and the client keeps its own data about it.

/// How large a marker is on the screen and which point of it sits on the pin's place: **in view points, whatever the zoom** (a pin keeps its size as the map zooms).
/// `anchor` is within the marker: (0.5, 1) is the middle of its foot (a map pin's tip, the foot of a 凸), (0.5, 0.5) its centre.
public struct PinMarkerLayout: Equatable, Sendable {
	public var size: CGSize
	public var anchor: UnitPoint

	public init(size: CGSize, anchor: UnitPoint) {
		self.size = size
		self.anchor = anchor
	}
}

/// What a client can replace: how large each pin's marker is, where it is anchored, and what it looks like (selected or not).
public protocol PinMarkers: Sendable {
	func layout(for pin: MapPin) -> PinMarkerLayout
	@MainActor func view(for pin: MapPin, isSelected: Bool) -> AnyView
}

/// The standard markers: **a map pin** (a teardrop, anchored at its tip) and **a dot** (anchored at its centre); a pin whose `marker` is neither draws as a map pin. The
/// colour comes from the pin's `color` key in `colors`, **a few light colours** by default (`colorKeys`); the selected pin is drawn with a white halo and a heavier outline.
/// Colours and sizes are the style's, and a client can replace the whole marker with its own `PinMarkers`.
public struct StandardPinMarkers: PinMarkers {
	/// The colour keys in the order a client would offer them.
	public static let colorKeys = ["red", "orange", "yellow", "green", "blue", "purple"]
	public var colors: [String: Color] = [
		"red": Color(red: 0.86, green: 0.22, blue: 0.20), "orange": Color(red: 0.96, green: 0.58, blue: 0.14), "yellow": Color(red: 0.97, green: 0.82, blue: 0.20),
		"green": Color(red: 0.27, green: 0.68, blue: 0.33), "blue": Color(red: 0.22, green: 0.47, blue: 0.86), "purple": Color(red: 0.58, green: 0.35, blue: 0.78)
	]
	public var outline = Color(red: 0.20, green: 0.10, blue: 0.08)
	public var halo = Color.white
	public var pinSize = CGSize(width: 24, height: 34)
	public var dotSize = CGSize(width: 14, height: 14)

	public init() {}

	/// The colour of a key; an unknown key is red.
	public func color(for key: String) -> Color { colors[key] ?? colors["red"] ?? .red }

	public func layout(for pin: MapPin) -> PinMarkerLayout {
		switch pin.marker {
		case "dot": PinMarkerLayout(size: dotSize, anchor: .center)
		default: PinMarkerLayout(size: pinSize, anchor: UnitPoint(x: 0.5, y: 1))
		}
	}

	@MainActor public func view(for pin: MapPin, isSelected: Bool) -> AnyView {
		let color = color(for: pin.color)
		switch pin.marker {
		case "dot":
			return AnyView(ZStack {
				if isSelected { Circle().stroke(halo, lineWidth: 5) }
				Circle().fill(color)
				Circle().stroke(outline, lineWidth: isSelected ? 2 : 1.2)
			})
		default:
			// the teardrop with a small light dot where a map pin has its hole
			let hole = pinSize.width * 0.36
			return AnyView(ZStack(alignment: .top) {
				if isSelected { TeardropShape().stroke(halo, lineWidth: 5) }
				TeardropShape().fill(color)
				TeardropShape().stroke(outline, lineWidth: isSelected ? 2 : 1.2)
				Circle().fill(Color.white.opacity(0.9)).frame(width: hole, height: hole).padding(.top, pinSize.width * 0.5 - hole / 2)
			})
		}
	}
}

/// A map pin: a circle with a point at the bottom.
public struct TeardropShape: Shape {
	public init() {}

	public func path(in rect: CGRect) -> Path {
		let w = rect.width, r = rect.width / 2
		var p = Path()
		let tip = CGPoint(x: rect.minX + w / 2, y: rect.maxY)
		p.move(to: tip)
		p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control1: CGPoint(x: rect.minX + w / 2 - r * 0.3, y: rect.maxY - r * 0.9), control2: CGPoint(x: rect.minX, y: rect.minY + r + r * 0.9))
		p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
		p.addCurve(to: tip, control1: CGPoint(x: rect.maxX, y: rect.minY + r + r * 0.9), control2: CGPoint(x: rect.minX + w / 2 + r * 0.3, y: rect.maxY - r * 0.9))
		p.closeSubpath()
		return p
	}
}

/// What the layer reports to the client. **The framework changes none of the client's data:** the client updates its own pins in response.
public enum PinEvent: Equatable, Sendable {
	/// A pin was asked for at this place on the map (map units, inside the map).
	case dropped(at: Point)
	/// A pin was selected; `anchor` is where its anchor is in the view now (view points), so that the client can show its own callout beside it.
	case selected(id: String, anchor: CGPoint)
	/// The selection ended (a tap on the map away from any pin).
	case deselected
	/// A pin was dragged to this place (map units, kept inside the map). The pin has not moved in the client's data until the client moves it.
	case moved(id: String, to: Point)
	/// The user asked to remove the selected pin (the Delete key). Nothing is removed until the client does.
	case removeRequested(id: String)
}

/// How a pin is asked for on the map.
public enum PinDropMode: Equatable, Sendable {
	/// Press and hold, as in a map app (the default).
	case longPress
	/// A single click or tap (when no pin is selected: a tap with a pin selected only deselects it).
	case click
	/// The layer does not drop pins (the client places them its own way).
	case off
}

/// The pins on a map view and how they behave. **Pass it to `FantasyMapView`; without it the view shows no pins and behaves as before.**
public struct PinLayer {
	public var pins: [MapPin]
	/// The selected pin's id, bound to the client's state; nil keeps the selection inside the view.
	public var selectedID: Binding<String?>?
	public var markers: any PinMarkers
	public var dropMode: PinDropMode
	/// Whether a pin can be dragged to move it.
	public var isDraggable: Bool
	/// How far beyond a marker's frame, in view points, still counts as touching it.
	public var hitSlop: CGFloat
	public var onEvent: (PinEvent) -> Void

	public init(pins: [MapPin], selectedID: Binding<String?>? = nil, markers: any PinMarkers = StandardPinMarkers(), dropMode: PinDropMode = .longPress, isDraggable: Bool = true, hitSlop: CGFloat = 4, onEvent: @escaping (PinEvent) -> Void = { _ in }) {
		self.pins = pins
		self.selectedID = selectedID
		self.markers = markers
		self.dropMode = dropMode
		self.isDraggable = isDraggable
		self.hitSlop = hitSlop
		self.onEvent = onEvent
	}
}

/// A pin as it shows in the view now.
public struct PinPlacement: Equatable, Sendable {
	public var id: String
	/// Where the pin's anchor is in the view (view points).
	public var anchor: CGPoint
	/// The marker's frame in the view.
	public var frame: CGRect
	/// Whether any of the marker is inside the view.
	public var isVisible: Bool

	/// **The area that selects the pin:** the marker's frame grown by `slop` view points on every side. The view's selection and the hit test both use it, so a tap just outside the
	/// marker and inside the slop selects the pin and is not treated as a tap on the map.
	public func hitFrame(slop: CGFloat) -> CGRect { frame.insetBy(dx: -slop, dy: -slop) }
}

/// What a single tap on the map does, decided apart from the platform's recognisers (which hand it a single tap only after a double tap has failed, so a double tap
/// that zooms never reaches it): nothing when it is on a pin (the marker takes it), a deselect when a pin is selected, a drop in click mode when none is, nothing otherwise.
public enum PinTapAction: Equatable, Sendable {
	case none, deselect, drop

	public static func decide(tapAt point: CGPoint, placements: [PinPlacement], hasSelection: Bool, dropMode: PinDropMode, slop: CGFloat) -> PinTapAction {
		if PinGeometry.hit(at: point, placements: placements, slop: slop) != nil { return .none }
		if hasSelection { return .deselect }
		return dropMode == .click ? .drop : .none
	}
}

/// The pins' geometry, pure: where each shows for a viewport, which one is under a point, where a pin dropped or dragged lands on the map.
public enum PinGeometry {
	/// The placement of every placeable pin, in order. **A marker keeps its size whatever the zoom:** only its anchor follows the map. An unusable geometry places nothing.
	public static func placements(pins: [MapPin], markers: any PinMarkers, geometry: MapViewportGeometry, viewport: MapViewport) -> [PinPlacement] {
		guard geometry.isUsable else { return [] }
		let bounds = CGRect(x: 0, y: 0, width: geometry.viewWidth, height: geometry.viewHeight)
		return pins.compactMap { pin in
			guard pin.isPlaceable else { return nil }
			let layout = markers.layout(for: pin)
			guard layout.size.width.isFinite, layout.size.height.isFinite, layout.size.width >= 0, layout.size.height >= 0, layout.anchor.x.isFinite, layout.anchor.y.isFinite else { return nil }
			let view = geometry.toView(pin.position, viewport)
			guard view.x.isFinite, view.y.isFinite else { return nil }
			let frame = CGRect(x: view.x - layout.size.width * layout.anchor.x, y: view.y - layout.size.height * layout.anchor.y, width: layout.size.width, height: layout.size.height)
			return PinPlacement(id: pin.id, anchor: CGPoint(x: view.x, y: view.y), frame: frame, isVisible: frame.intersects(bounds))
		}
	}

	/// The id of the pin under a view point: **the topmost, which is the last in order among those whose frame (grown by `slop`) contains it**, ignoring any that are out of view.
	public static func hit(at point: CGPoint, placements: [PinPlacement], slop: CGFloat = 0) -> String? {
		placements.last { $0.isVisible && $0.hitFrame(slop: slop).contains(point) }?.id
	}

	/// The place on the map for a pin dropped at a view point, or nil if that point is outside the map (in the margin around it).
	public static func dropPoint(atView point: CGPoint, geometry: MapViewportGeometry, viewport: MapViewport) -> Point? {
		guard geometry.isUsable else { return nil }
		let p = geometry.toMap(Point(x: point.x, y: point.y), viewport)
		guard p.x.isFinite, p.y.isFinite, p.x >= 0, p.x <= geometry.mapWidth, p.y >= 0, p.y <= geometry.mapHeight else { return nil }
		return p
	}

	/// Where a pin dragged by a translation (view points) from its anchor lands on the map, **kept inside the map** (a pin dragged into the margin stops at the map's edge).
	public static func movedPosition(anchor: CGPoint, translation: CGSize, geometry: MapViewportGeometry, viewport: MapViewport) -> Point? {
		guard geometry.isUsable else { return nil }
		let p = geometry.toMap(Point(x: anchor.x + translation.width, y: anchor.y + translation.height), viewport)
		guard p.x.isFinite, p.y.isFinite else { return nil }
		return Point(x: min(max(p.x, 0), geometry.mapWidth), y: min(max(p.y, 0), geometry.mapHeight))
	}
}
