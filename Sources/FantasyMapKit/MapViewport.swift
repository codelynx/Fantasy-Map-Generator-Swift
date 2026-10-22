import FantasyMapCore
import Foundation

/// Which part of the map a view shows: **a zoom relative to fit and a centre in map coordinates** (docs/plans/drawing-zoom.md). A zoom of 1 is the whole map
/// fitted in the view, centred, as the view drew it before zooming existed; larger is closer. The centre is a point of the map in map units (the origin at the
/// map's top-left, y down, as the drawing's own), **nil for the map's own centre.** Resizing a view therefore keeps what is in the middle of it: the state is in
/// map coordinates, not in view points.
///
/// **A state that is not finite, or a zoom or centre outside the limits, never reaches a drawing transform:** `MapViewportGeometry.effective` clamps it first.
public struct MapViewport: Equatable, Sendable {
	public var zoom: Double
	public var center: Point?

	public init(zoom: Double = 1, center: Point? = nil) {
		self.zoom = zoom
		self.center = center
	}

	/// The whole map, fitted and centred.
	public static let fit = MapViewport()
}

/// The numbers behind the zoom: all configurable, all **provisional** until the first live look (docs/plans/drawing-zoom.md).
public struct ViewportPolicy: Equatable, Sendable {
	/// How wide one cell is on the screen, in points, at the maximum zoom (the author's rule: the maximum zoom follows the cell size, so a map of few large
	/// cells does not zoom into huge polygons and a map of many small cells zooms far enough).
	public var cellTargetPoints = 64.0
	/// The maximum zoom is never below this ...
	public var floorZoom = 2.0
	/// ... and never above this.
	public var ceilingZoom = 64.0
	/// The share of the view's width and of its height that the map must keep covering when panned, 0 to 1: a map cannot be almost lost with a sliver in view.
	public var minimumCovered = 0.25
	/// The zoom step of a double click or double tap and of the keyboard's zoom in and out (a factor above 1).
	public var doubleClickFactor = 2.0
	public var keyboardFactor = 1.5
	/// How much a scroll point zooms when zooming by scrolling: the factor is `exp(delta × sensitivity)`.
	public var scrollSensitivity = 0.01

	public init() {}

	var isValid: Bool {
		[cellTargetPoints, floorZoom, ceilingZoom, minimumCovered, doubleClickFactor, keyboardFactor, scrollSensitivity].allSatisfy(\.isFinite)
			&& cellTargetPoints > 0 && floorZoom >= 1 && ceilingZoom >= floorZoom && minimumCovered >= 0 && minimumCovered <= 1 && doubleClickFactor > 1 && keyboardFactor > 1 && scrollSensitivity > 0
	}
}

/// The viewport's transforms for one map in one view: the map to the view and back **together**, and the zoom and pan operations that keep the limits.
///
/// **Order of the transform:** a map point `p` shows at the view point `(p − centre) × scale + view size / 2`, where `scale = fit scale × zoom` and the fit scale is
/// the one that fits the whole map in the view. **Anchoring:** zooming keeps the map point under the pointer fixed until a limit intervenes; the limits win.
public struct MapViewportGeometry: Equatable, Sendable {
	public var mapWidth: Double
	public var mapHeight: Double
	public var viewWidth: Double
	public var viewHeight: Double
	/// The cells' grid spacing in map units (`MapDrawing.cellSpacing`): the maximum zoom follows it.
	public var cellSpacing: Double
	public var policy: ViewportPolicy

	public init(mapWidth: Double, mapHeight: Double, viewWidth: Double, viewHeight: Double, cellSpacing: Double, policy: ViewportPolicy = ViewportPolicy()) {
		self.mapWidth = mapWidth
		self.mapHeight = mapHeight
		self.viewWidth = viewWidth
		self.viewHeight = viewHeight
		self.cellSpacing = cellSpacing
		self.policy = policy
	}

	/// Whether the geometry can be used: the sizes finite and above 0, a valid policy, **and the numbers derived from them sound**: the fit scale above 0 (the ratio of
	/// two finite sizes can underflow to 0, or overflow, which the products below catch), and the map's width and height on the screen at the maximum zoom finite. A
	/// geometry that is not usable draws only the paper.
	public var isUsable: Bool {
		guard [mapWidth, mapHeight, viewWidth, viewHeight].allSatisfy({ $0.isFinite && $0 > 0 }), policy.isValid else { return false }
		// (the policy's validity makes the maximum zoom finite and at least 1, and a fit scale that overflowed makes the products below infinite)
		let fit = fitScale, maximum = maximumZoom
		return fit > 0 && (mapWidth * fit * maximum).isFinite && (mapHeight * fit * maximum).isFinite
	}

	/// The scale that fits the whole map in the view (view points per map unit).
	public var fitScale: Double { min(viewWidth / mapWidth, viewHeight / mapHeight) }

	/// The largest zoom: one cell about `policy.cellTargetPoints` across at the most, within the floor and the ceiling (a spacing that is not positive and finite
	/// gives the floor).
	public var maximumZoom: Double {
		guard cellSpacing.isFinite, cellSpacing > 0, fitScale.isFinite, fitScale > 0 else { return policy.floorZoom }
		return min(max(policy.cellTargetPoints / (cellSpacing * fitScale), policy.floorZoom), policy.ceilingZoom)
	}

	/// The scale at a zoom (view points per map unit).
	public func scale(zoom: Double) -> Double { fitScale * zoom }

	/// A viewport the view may use: the zoom within 1 ... the maximum (a value that is not finite becomes 1), the centre a finite point inside the pan limit, **the
	/// map's own centre when the zoom is 1** (at fit the map is centred and cannot be moved). Returns the centre as numbers.
	public func effective(_ viewport: MapViewport) -> (zoom: Double, centerX: Double, centerY: Double) {
		var zoom = viewport.zoom.isFinite ? viewport.zoom : 1
		zoom = min(max(zoom, 1), max(maximumZoom, 1))
		let middleX = mapWidth / 2, middleY = mapHeight / 2
		guard zoom > 1, isUsable else { return (zoom, middleX, middleY) }
		let (x, y) = (viewport.center?.x, viewport.center?.y)
		let s = scale(zoom: zoom)
		return (zoom, clampCentre(x.flatMap { $0.isFinite ? $0 : nil } ?? middleX, extent: viewWidth / s, map: mapWidth), clampCentre(y.flatMap { $0.isFinite ? $0 : nil } ?? middleY, extent: viewHeight / s, map: mapHeight))
	}

	/// The pan limit along one axis: the view shows `extent` map units; at least `minimumCovered` of it (or the whole map, if smaller) must be covered by the map.
	private func clampCentre(_ centre: Double, extent: Double, map: Double) -> Double {
		let need = min(policy.minimumCovered * extent, map)
		let low = need - extent / 2, high = map + extent / 2 - need
		return low > high ? map / 2 : min(max(centre, low), high)
	}

	/// The view point where a map point shows.
	public func toView(_ p: Point, _ viewport: MapViewport) -> Point {
		let e = effective(viewport), s = scale(zoom: e.zoom)
		return Point(x: (p.x - e.centerX) * s + viewWidth / 2, y: (p.y - e.centerY) * s + viewHeight / 2)
	}

	/// The map point shown at a view point (the inverse of `toView`).
	public func toMap(_ p: Point, _ viewport: MapViewport) -> Point {
		let e = effective(viewport), s = scale(zoom: e.zoom)
		return Point(x: (p.x - viewWidth / 2) / s + e.centerX, y: (p.y - viewHeight / 2) / s + e.centerY)
	}

	/// The transform for a viewport **only if every number of it is finite and the scale above 0** (the scale, the offsets and the map's rectangle on the screen), or nil:
	/// what a view passes to its graphics context, so that an overflow can never reach it.
	public func validTransform(_ viewport: MapViewport) -> (scale: Double, offsetX: Double, offsetY: Double)? {
		guard isUsable else { return nil }
		let t = transform(viewport)
		let numbers = [t.scale, t.offsetX, t.offsetY, mapWidth * t.scale, mapHeight * t.scale, t.offsetX + mapWidth * t.scale, t.offsetY + mapHeight * t.scale]
		return numbers.allSatisfy(\.isFinite) && t.scale > 0 ? t : nil
	}

	/// The scale and the offset a drawing needs: a map point `p` shows at `p × scale + offset`.
	public func transform(_ viewport: MapViewport) -> (scale: Double, offsetX: Double, offsetY: Double) {
		let e = effective(viewport), s = scale(zoom: e.zoom)
		return (s, viewWidth / 2 - e.centerX * s, viewHeight / 2 - e.centerY * s)
	}

	/// The viewport after zooming by `factor` around a view point: the map point under it stays fixed **until a limit intervenes** (the zoom stops at 1 and at the
	/// maximum, the centre at the pan limit), and the limits win. A factor that is not finite and above 0 changes nothing.
	public func zoomed(_ viewport: MapViewport, by factor: Double, around anchor: Point) -> MapViewport {
		let e = effective(viewport)
		guard isUsable, factor.isFinite, factor > 0, anchor.x.isFinite, anchor.y.isFinite else { return MapViewport(zoom: e.zoom, center: Point(x: e.centerX, y: e.centerY)) }
		let before = toMap(anchor, viewport)
		let zoom = min(max(e.zoom * factor, 1), max(maximumZoom, 1))
		let s = scale(zoom: zoom)
		let wanted = MapViewport(zoom: zoom, center: Point(x: before.x - (anchor.x - viewWidth / 2) / s, y: before.y - (anchor.y - viewHeight / 2) / s))
		let result = effective(wanted)
		return MapViewport(zoom: result.zoom, center: Point(x: result.centerX, y: result.centerY))
	}

	/// The viewport after dragging the map by a distance in view points (the map follows the pointer), within the pan limit.
	public func panned(_ viewport: MapViewport, byViewPoints dx: Double, _ dy: Double) -> MapViewport {
		let e = effective(viewport)
		guard isUsable, dx.isFinite, dy.isFinite else { return MapViewport(zoom: e.zoom, center: Point(x: e.centerX, y: e.centerY)) }
		let s = scale(zoom: e.zoom)
		let result = effective(MapViewport(zoom: e.zoom, center: Point(x: e.centerX - dx / s, y: e.centerY - dy / s)))
		return MapViewport(zoom: result.zoom, center: Point(x: result.centerX, y: result.centerY))
	}

	/// The map rectangle on show, in map units (x, y, width, height), for a viewport.
	public func visibleRect(_ viewport: MapViewport) -> (x: Double, y: Double, width: Double, height: Double) {
		let e = effective(viewport), s = scale(zoom: e.zoom)
		return (e.centerX - viewWidth / s / 2, e.centerY - viewHeight / s / 2, viewWidth / s, viewHeight / s)
	}
}


/// **One gesture session for a drag and a pinch together** (the review's point: they must combine, not overwrite each other). The session starts from the viewport
/// the first of them began at and composes the pinch's magnification (around the pinch point) and then the drag's translation, both from that one baseline; when
/// one of them ends the baseline moves to what is on show and the other carries on from there, so nothing jumps and neither undoes the other. Pure, so it is tested
/// without a gesture.
struct ViewportGestureSession: Equatable {
	private(set) var base: MapViewport
	private(set) var isDragging = false
	private(set) var isMagnifying = false
	private var translation = (dx: 0.0, dy: 0.0), foldedTranslation = (dx: 0.0, dy: 0.0)
	private var magnification = 1.0, foldedMagnification = 1.0
	private var anchor = Point(x: 0, y: 0)

	init(base: MapViewport) { self.base = base }

	static func == (a: ViewportGestureSession, b: ViewportGestureSession) -> Bool {
		a.base == b.base && a.isDragging == b.isDragging && a.isMagnifying == b.isMagnifying && a.translation == b.translation && a.foldedTranslation == b.foldedTranslation
			&& a.magnification == b.magnification && a.foldedMagnification == b.foldedMagnification && a.anchor == b.anchor
	}

	var isIdle: Bool { !isDragging && !isMagnifying }

	/// The viewport on show now: the baseline zoomed by the pinch (since it was last folded) around its point, then moved by the drag (since it was last folded).
	func viewport(_ g: MapViewportGeometry) -> MapViewport {
		var v = base
		if isMagnifying, foldedMagnification > 0 { v = g.zoomed(v, by: magnification / foldedMagnification, around: anchor) }
		if isDragging { v = g.panned(v, byViewPoints: translation.dx - foldedTranslation.dx, translation.dy - foldedTranslation.dy) }
		return v
	}

	/// The drag moved: `translation` is the drag's total since it began, in view points.
	mutating func dragChanged(dx: Double, dy: Double) {
		isDragging = true // a drag that starts mid-session counts from zero: its translation is the total since it began, and nothing of it is folded yet
		translation = (dx, dy)
	}

	/// The pinch changed: `magnification` is the pinch's total since it began, `anchor` its start point in the view.
	mutating func magnifyChanged(magnification: Double, anchor: Point) {
		if !isMagnifying { isMagnifying = true; self.anchor = anchor } // a pinch counts from 1: its magnification is the total since it began
		self.magnification = magnification
	}

	/// The drag ended: what is on show becomes the baseline, and a pinch that carries on continues from it.
	mutating func dragEnded(_ g: MapViewportGeometry) {
		let current = viewport(g)
		isDragging = false
		base = current
		foldedMagnification = magnification
		foldedTranslation = (0, 0)
	}

	mutating func magnifyEnded(_ g: MapViewportGeometry) {
		let current = viewport(g)
		isMagnifying = false
		base = current
		foldedTranslation = translation
		magnification = 1; foldedMagnification = 1
	}
}
