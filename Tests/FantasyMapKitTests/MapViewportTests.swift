import FantasyMapCore
import Foundation
import Testing
@testable import FantasyMapKit

/// The viewport's transforms and limits (docs/plans/drawing-zoom.md).
struct MapViewportTests {
	/// The default 1280 by 800 map in a 1000 by 1000 view (fit scale 0.78125), with a cell spacing.
	func geometry(spacing: Double = 12.6, view: (Double, Double) = (1000, 1000), policy: ViewportPolicy = ViewportPolicy()) -> MapViewportGeometry {
		MapViewportGeometry(mapWidth: 1280, mapHeight: 800, viewWidth: view.0, viewHeight: view.1, cellSpacing: spacing, policy: policy)
	}

	// MARK: the transforms

	@Test func fitIsTheWholeMapCentredAsTheViewDrawsItWithoutZoom() {
		let g = geometry()
		let e = g.effective(.fit)
		#expect(e.zoom == 1 && e.centerX == 640 && e.centerY == 400)
		let t = g.transform(.fit)
		// the view's own earlier arithmetic: scale = min(width ratio, height ratio), the map centred
		#expect(t.scale == 1000.0 / 1280 && t.offsetX == 0 && abs(t.offsetY - (1000 - 800 * t.scale) / 2) < 1e-9)
		#expect(g.toView(Point(x: 0, y: 0), .fit) == Point(x: t.offsetX, y: t.offsetY))
	}

	@Test func theMapToViewAndViewToMapTransformsAreInverses() {
		let g = geometry()
		for viewport in [MapViewport.fit, MapViewport(zoom: 2, center: Point(x: 300, y: 200)), MapViewport(zoom: 5.5, center: Point(x: 1200, y: 700))] {
			for p in [Point(x: 0, y: 0), Point(x: 640, y: 400), Point(x: 1279, y: 799), Point(x: 333.3, y: 71.1)] {
				let back = g.toMap(g.toView(p, viewport), viewport)
				#expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
			}
		}
		// the transform is the same as toView: p × scale + offset
		let v = MapViewport(zoom: 3, center: Point(x: 500, y: 300))
		let t = g.transform(v), p = Point(x: 640, y: 123)
		#expect(abs(g.toView(p, v).x - (p.x * t.scale + t.offsetX)) < 1e-9 && abs(g.toView(p, v).y - (p.y * t.scale + t.offsetY)) < 1e-9)
		// the visible rectangle is the view's extent in map units around the centre
		let r = g.visibleRect(v)
		#expect(abs(r.width - 1000 / t.scale) < 1e-9 && abs(r.x + r.width / 2 - 500) < 1e-9 && abs(r.y + r.height / 2 - 300) < 1e-9)
	}

	// MARK: bad values never reach a transform

	@Test func aStateThatIsNotFiniteOrIsOutsideTheLimitsIsClampedBeforeAnyUse() {
		let g = geometry()
		let max = g.maximumZoom
		for zoom in [Double.nan, .infinity, -.infinity, -3, 0, 0.5] { #expect(g.effective(MapViewport(zoom: zoom, center: Point(x: 10, y: 10))).zoom == 1, "zoom \(zoom)") }
		#expect(g.effective(MapViewport(zoom: 1e9)).zoom == max)
		for centre in [Point(x: .nan, y: 5), Point(x: 5, y: .infinity), Point(x: -.infinity, y: .nan)] {
			let e = g.effective(MapViewport(zoom: 3, center: centre))
			#expect(e.centerX.isFinite && e.centerY.isFinite)
			if !centre.x.isFinite { #expect(e.centerX == 640) }
			if !centre.y.isFinite { #expect(e.centerY == 400) }
		}
		// a centre far outside the map is brought back inside the pan limit
		let far = g.effective(MapViewport(zoom: 4, center: Point(x: 1e12, y: -1e12)))
		#expect(far.centerX < 1280 + 1000 && far.centerY > -1000)
		// at fit the centre cannot be moved
		#expect(g.effective(MapViewport(zoom: 1, center: Point(x: 5, y: 5))).centerX == 640)
		// unusable sizes or policy do not trap
		let broken = MapViewportGeometry(mapWidth: 0, mapHeight: .nan, viewWidth: 100, viewHeight: 100, cellSpacing: 1)
		#expect(!broken.isUsable)
		_ = broken.effective(MapViewport(zoom: 5, center: Point(x: 1, y: 1)))
		var bad = ViewportPolicy()
		bad.floorZoom = 0.5
		#expect(!bad.isValid && !geometry(policy: bad).isUsable)
		#expect(geometry(policy: bad).effective(MapViewport(zoom: 3)).zoom >= 1)
	}

	// MARK: the maximum zoom follows the cell size

	@Test func theMaximumZoomFollowsTheCellSizeWithAFloorAndACeiling() {
		// 1,000 cells (spacing about 40), 10,000 (about 12.6), 100,000 (about 4) on the default map in a 1000-point view: about 2, 6.5 and 20
		let few = geometry(spacing: 40).maximumZoom, some = geometry(spacing: 12.6).maximumZoom, many = geometry(spacing: 4).maximumZoom
		#expect(abs(few - 2.048) < 1e-9, "\(few)")
		#expect(geometry(spacing: 100).maximumZoom == 2, "the floor for cells larger than the target allows")
		#expect(abs(some - 64 / (12.6 * 0.78125)) < 1e-9 && abs(some - 6.5) < 0.1, "\(some)")
		#expect(abs(many - 64 / (4 * 0.78125)) < 1e-9 && abs(many - 20.5) < 0.1, "\(many)")
		#expect(few < some && some < many)
		// at the maximum one cell is about the target across
		#expect(abs(geometry(spacing: 12.6).scale(zoom: some) * 12.6 - 64) < 1e-9)
		// the ceiling and the floor; a spacing that is not usable gives the floor
		#expect(geometry(spacing: 0.01).maximumZoom == 64)
		for spacing in [0.0, -1, .nan, .infinity] { #expect(geometry(spacing: spacing).maximumZoom == 2, "spacing \(spacing)") }
		// the target is configurable
		var policy = ViewportPolicy()
		policy.cellTargetPoints = 96
		#expect(abs(geometry(spacing: 12.6, policy: policy).maximumZoom - 96 / (12.6 * 0.78125)) < 1e-9)
		// a smaller view (a smaller fit scale) allows more zoom for the same cell target
		#expect(geometry(spacing: 12.6, view: (500, 500)).maximumZoom > some)
	}

	// MARK: anchoring and the limits

	@Test func zoomingKeepsThePointUnderThePointerFixedWhenNoLimitIntervenes() {
		let g = geometry()
		let start = MapViewport(zoom: 2, center: Point(x: 640, y: 400))
		for anchor in [Point(x: 500, y: 500), Point(x: 120, y: 300), Point(x: 800, y: 700)] {
			let before = g.toMap(anchor, start)
			let after = g.zoomed(start, by: 1.5, around: anchor)
			#expect(after.zoom == 3)
			let held = g.toMap(anchor, after)
			#expect(abs(held.x - before.x) < 1e-9 && abs(held.y - before.y) < 1e-9, "the map point under \(anchor) stayed at \(before), now \(held)")
		}
		// from fit, zooming in around a point away from the middle moves the centre so that the point stays put
		let fromFit = g.zoomed(.fit, by: 2, around: Point(x: 200, y: 450))
		#expect(abs(g.toMap(Point(x: 200, y: 450), fromFit).x - g.toMap(Point(x: 200, y: 450), .fit).x) < 1e-9)
	}

	@Test func theLimitsWinOverAnchoring() {
		let g = geometry()
		let max = g.maximumZoom
		// the zoom stops at the maximum, however large the factor
		let big = g.zoomed(MapViewport(zoom: 2, center: Point(x: 640, y: 400)), by: 1e6, around: Point(x: 500, y: 500))
		#expect(big.zoom == max)
		// and at 1 when zooming out (the map is then centred again, the anchor cannot hold)
		let out = g.zoomed(MapViewport(zoom: 3, center: Point(x: 300, y: 300)), by: 1e-6, around: Point(x: 100, y: 100))
		#expect(out.zoom == 1 && out.center == Point(x: 640, y: 400))
		// near the map's corner at a high zoom the pan limit stops the centre: the anchor drifts, the viewport stays valid, and the result is already clamped
		let corner = g.zoomed(MapViewport(zoom: max / 2, center: Point(x: 1270, y: 790)), by: 2, around: Point(x: 990, y: 990))
		#expect(corner.zoom == max && g.effective(corner).centerX == corner.center?.x && g.effective(corner).centerY == corner.center?.y)
		// a factor or an anchor that is not usable changes nothing
		let v = MapViewport(zoom: 2, center: Point(x: 400, y: 300))
		for factor in [Double.nan, 0, -2, .infinity] { #expect(g.zoomed(v, by: factor, around: Point(x: 5, y: 5)) == v.normalised(g), "factor \(factor)") }
		#expect(g.zoomed(v, by: 2, around: Point(x: .nan, y: 5)) == v.normalised(g))
	}

	@Test func theMapNeverLeavesTheViewBeyondTheCoveredShare() {
		let g = geometry()
		let q = g.policy.minimumCovered
		for zoom in [1.01, 1.5, 2, 6, g.maximumZoom] {
			for target in [Point(x: -1e6, y: -1e6), Point(x: 1e6, y: 1e6), Point(x: -1e6, y: 1e6), Point(x: 1e6, y: -1e6), Point(x: 640, y: 400)] {
				let e = g.effective(MapViewport(zoom: zoom, center: target))
				let r = g.visibleRect(MapViewport(zoom: zoom, center: Point(x: e.centerX, y: e.centerY)))
				let coveredX = min(r.x + r.width, 1280) - max(r.x, 0), coveredY = min(r.y + r.height, 800) - max(r.y, 0)
				#expect(coveredX >= min(q * r.width, 1280) - 1e-9 && coveredY >= min(q * r.height, 800) - 1e-9, "zoom \(zoom) centre \(target): covered \(coveredX / r.width) of the width, \(coveredY / r.height) of the height")
			}
		}
		// the same share is kept after dragging far, step by step
		var v = MapViewport(zoom: 4, center: Point(x: 640, y: 400))
		for _ in 0..<200 { v = g.panned(v, byViewPoints: 500, 500) }
		let e = g.effective(v)
		#expect(e.centerX < 640 && e.centerY < 400 && g.effective(v).centerX == v.center?.x)
		// at fit nothing can be dragged
		#expect(g.panned(.fit, byViewPoints: 300, 300) == MapViewport(zoom: 1, center: Point(x: 640, y: 400)))
	}

	@Test func draggingMovesTheMapWithThePointer() {
		let g = geometry()
		let v = MapViewport(zoom: 3, center: Point(x: 640, y: 400))
		let p = Point(x: 600, y: 350)
		let before = g.toView(p, v)
		let dragged = g.panned(v, byViewPoints: 40, -25)
		let after = g.toView(p, dragged)
		#expect(abs(after.x - before.x - 40) < 1e-9 && abs(after.y - before.y + 25) < 1e-9, "the map point moved with the pointer")
		#expect(g.panned(v, byViewPoints: .nan, 5) == v.normalised(g) && g.panned(v, byViewPoints: 5, .infinity) == v.normalised(g))
	}

	@Test func aViewMuchTallerThanTheMapStillLetsTheMapBePanned() {
		// the view shows far more than the map's height, so a quarter of the view is more than the whole map: the share required is capped at the map's own extent
		let g = geometry(view: (1000, 4000))
		let e = g.effective(MapViewport(zoom: 1.2, center: Point(x: 640, y: 100)))
		#expect(e.centerY == 100, "the map can be moved vertically here: \(e.centerY)")
		// the least the centre can be: the share required is the map's whole height (800), not a quarter of the view (about 1,067)
		let extent = 4000 / g.scale(zoom: 1.2)
		#expect(extent / 4 > 800, "a quarter of the view is more than the map")
		let far = g.effective(MapViewport(zoom: 1.2, center: Point(x: 640, y: -1e9)))
		#expect(abs(far.centerY - (800 - extent / 2)) < 1e-6, "\(far.centerY) against \(800 - extent / 2)")
	}

	// MARK: a drag and a pinch together

	func near(_ a: MapViewport, _ b: MapViewport, _ g: MapViewportGeometry, tolerance: Double = 1e-9) -> Bool {
		let x = g.effective(a), y = g.effective(b)
		return abs(x.zoom - y.zoom) < tolerance && abs(x.centerX - y.centerX) < tolerance * 100 && abs(x.centerY - y.centerY) < tolerance * 100
	}

	@Test func aPinchAndADragCombineFromOneBaselineAndDoNotOverwriteEachOther() {
		let g = geometry()
		let base = MapViewport(zoom: 2, center: Point(x: 640, y: 400))
		let anchor = Point(x: 400, y: 300)
		var session = ViewportGestureSession(base: base)
		// the pinch begins and reaches 1.5
		session.magnifyChanged(magnification: 1.2, anchor: anchor)
		session.magnifyChanged(magnification: 1.5, anchor: anchor)
		#expect(near(session.viewport(g), g.zoomed(base, by: 1.5, around: anchor), g))
		// the drag begins while the pinch is on: the zoom stays (the drag does not restore the zoom the pinch began at), and the map moves
		session.dragChanged(dx: 20, dy: 10)
		let both = session.viewport(g)
		#expect(g.effective(both).zoom == 3, "the pinch's zoom is kept: \(g.effective(both).zoom)")
		#expect(near(both, g.panned(g.zoomed(base, by: 1.5, around: anchor), byViewPoints: 20, 10), g))
		// the pinch goes on: the drag is kept (a pinch update does not discard the drag)
		session.magnifyChanged(magnification: 2, anchor: anchor)
		#expect(near(session.viewport(g), g.panned(g.zoomed(base, by: 2, around: anchor), byViewPoints: 20, 10), g))
		// and the drag goes on: the pinch is kept
		session.dragChanged(dx: 30, dy: 15)
		let later = session.viewport(g)
		#expect(g.effective(later).zoom == 4 && near(later, g.panned(g.zoomed(base, by: 2, around: anchor), byViewPoints: 30, 15), g))
		// the pinch ends: nothing jumps; the drag carries on from what is on show
		session.magnifyEnded(g)
		#expect(near(session.viewport(g), later, g), "no jump when the pinch ends")
		session.dragChanged(dx: 50, dy: 15)
		#expect(near(session.viewport(g), g.panned(later, byViewPoints: 20, 0), g), "the drag continues from where it was")
		#expect(!session.isIdle)
		session.dragEnded(g)
		#expect(session.isIdle && near(session.viewport(g), g.panned(later, byViewPoints: 20, 0), g), "the drag ends where it was")
	}

	@Test func aDragThatEndsFirstLeavesThePinchGoingFromWhatIsOnShow() {
		let g = geometry()
		let base = MapViewport(zoom: 3, center: Point(x: 500, y: 300))
		let anchor = Point(x: 600, y: 600)
		var session = ViewportGestureSession(base: base)
		session.dragChanged(dx: 15, dy: -10)
		session.magnifyChanged(magnification: 1.1, anchor: anchor)
		session.magnifyChanged(magnification: 1.3, anchor: anchor)
		session.dragChanged(dx: 25, dy: -12)
		let before = session.viewport(g)
		session.dragEnded(g)
		#expect(near(session.viewport(g), before, g), "no jump when the drag ends")
		session.magnifyChanged(magnification: 1.6, anchor: anchor)
		// the pinch from 1.3 to 1.6 is a further 1.6 / 1.3 around the same point
		#expect(near(session.viewport(g), g.zoomed(before, by: 1.6 / 1.3, around: anchor), g))
		session.magnifyEnded(g)
		#expect(session.isIdle)
	}

	@Test func aSessionOfOneGestureIsTheGestureAlone() {
		let g = geometry()
		let base = MapViewport(zoom: 2, center: Point(x: 640, y: 400))
		var drag = ViewportGestureSession(base: base)
		drag.dragChanged(dx: 33, dy: -21)
		#expect(near(drag.viewport(g), g.panned(base, byViewPoints: 33, -21), g))
		var pinch = ViewportGestureSession(base: base)
		pinch.magnifyChanged(magnification: 1.7, anchor: Point(x: 123, y: 456))
		#expect(near(pinch.viewport(g), g.zoomed(base, by: 1.7, around: Point(x: 123, y: 456)), g))
		#expect(!drag.isIdle && !pinch.isIdle, "a session with one gesture on is not idle")
		// a session that has not begun is the baseline
		#expect(ViewportGestureSession(base: base).viewport(g) == base && ViewportGestureSession(base: base).isIdle)
	}

	@Test func theSessionAlwaysStaysWithinTheLimits() {
		let g = geometry()
		var session = ViewportGestureSession(base: MapViewport(zoom: 2, center: Point(x: 640, y: 400)))
		for step in 1...60 {
			session.magnifyChanged(magnification: 1 + Double(step) * 0.5, anchor: Point(x: 900, y: 100))
			session.dragChanged(dx: Double(step) * 40, dy: Double(step) * -35)
			let v = session.viewport(g)
			#expect(v == v.normalised(g), "step \(step): the viewport is already clamped")
			#expect(g.effective(v).zoom <= g.maximumZoom)
		}
	}

	// MARK: the derived transform is sound

	@Test func aGeometryWhoseDerivedNumbersOverflowOrUnderflowIsNotUsable() {
		// finite sizes whose ratio overflows: the fit scale is infinite
		let tiny = MapViewportGeometry(mapWidth: 1e-308, mapHeight: 1e-308, viewWidth: 100, viewHeight: 100, cellSpacing: 1e-309)
		#expect(tiny.fitScale == .infinity && !tiny.isUsable && tiny.validTransform(.fit) == nil)
		// ... or underflows to 0
		let huge = MapViewportGeometry(mapWidth: 1e300, mapHeight: 1e300, viewWidth: 1e-300, viewHeight: 1e-300, cellSpacing: 1)
		#expect(huge.fitScale == 0 && !huge.isUsable && huge.validTransform(.fit) == nil)
		// zoom limits that overflow the scale: a floor of 1e308 times a fit scale of 0.78 is finite, but the map on the screen is not
		var policy = ViewportPolicy()
		policy.floorZoom = 1e308
		policy.ceilingZoom = 1e308
		let overflow = geometry(policy: policy)
		#expect(policy.isValid && overflow.maximumZoom == 1e308 && !overflow.isUsable)
		#expect(overflow.validTransform(MapViewport(zoom: 1e308, center: Point(x: 1, y: 1))) == nil)
		// the map's width or its height alone overflows on the screen at the maximum zoom (each is needed): a tall map in a tall view, and a wide one in a wide view
		var floor100 = ViewportPolicy()
		floor100.floorZoom = 100
		floor100.ceilingZoom = 100
		let tall = MapViewportGeometry(mapWidth: 1, mapHeight: 1e307, viewWidth: 100, viewHeight: 1e307, cellSpacing: 1, policy: floor100)
		let wideOne = MapViewportGeometry(mapWidth: 1e307, mapHeight: 1, viewWidth: 1e307, viewHeight: 100, cellSpacing: 1, policy: floor100)
		#expect(tall.fitScale == 1 && wideOne.fitScale == 1 && !tall.isUsable && !wideOne.isUsable)
		let fine = MapViewportGeometry(mapWidth: 1, mapHeight: 1e305, viewWidth: 100, viewHeight: 1e305, cellSpacing: 1, policy: floor100)
		#expect(fine.isUsable, "the same shape a little smaller is usable")
		// a map so large that its rectangle on the screen overflows only when zoomed in: refused as a whole
		let wide = MapViewportGeometry(mapWidth: 1e300, mapHeight: 1e300, viewWidth: 1000, viewHeight: 1000, cellSpacing: 1e290)
		#expect(!wide.isUsable || wide.validTransform(MapViewport(zoom: wide.maximumZoom)) != nil)
		// an ordinary geometry is usable and its valid transform is the transform
		let g = geometry()
		let v = MapViewport(zoom: 3, center: Point(x: 500, y: 300))
		#expect(g.isUsable && g.validTransform(v)?.scale == g.transform(v).scale && g.validTransform(v)?.offsetX == g.transform(v).offsetX)
		// a transform with a non-finite number is nil, never passed on
		var broken = g
		broken.viewWidth = .nan
		#expect(broken.validTransform(.fit) == nil)
	}

	@Test func aTransformWithEveryNumberFiniteIsReturnedAtEveryZoom() {
		let g = geometry()
		for zoom in [1.0, 1.5, g.maximumZoom / 2, g.maximumZoom] {
			let t = g.validTransform(MapViewport(zoom: zoom, center: Point(x: 640, y: 400)))
			#expect(t != nil && t!.scale > 0 && t!.offsetX.isFinite && t!.offsetY.isFinite, "zoom \(zoom)")
		}
	}

	// MARK: resizing

	@Test func resizingTheViewKeepsTheMapSpaceCentre() {
		let v = MapViewport(zoom: 3, center: Point(x: 400, y: 300))
		let a = geometry(view: (1000, 700)).effective(v), b = geometry(view: (600, 900)).effective(v), c = geometry(view: (1400, 500)).effective(v)
		#expect(a.centerX == 400 && b.centerX == 400 && c.centerX == 400 && a.centerY == 300 && b.centerY == 300 && c.centerY == 300)
		// at fit the map stays centred whatever the view
		for view in [(1000.0, 700.0), (600, 900), (1400, 500)] { #expect(geometry(view: view).effective(.fit).centerX == 640) }
		// and what is clamped by the new size is clamped: a very small view shows a small part, the centre stays inside the pan limit
		let small = geometry(view: (50, 50)).effective(MapViewport(zoom: 2, center: Point(x: 5000, y: 5000)))
		#expect(small.centerX < 5000)
	}
}

extension MapViewport {
	/// The viewport as the geometry would clamp it, for comparing with results (a nil centre becomes the map's).
	func normalised(_ g: MapViewportGeometry) -> MapViewport {
		let e = g.effective(self)
		return MapViewport(zoom: e.zoom, center: Point(x: e.centerX, y: e.centerY))
	}
}
