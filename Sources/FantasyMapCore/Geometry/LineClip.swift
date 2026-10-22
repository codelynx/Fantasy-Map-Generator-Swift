// Ported from lineclip 2.0.0 (index.js, `clipPolygon`), © 2015 Mapbox, ISC licence (the notice is in ACKNOWLEDGEMENTS.md and
// docs/dependencies.md), and from Azgaar's Fantasy Map Generator, `src/utils/commonUtils.ts` (`clipPoly`; the original at commit 8936c9c).
//
// Clipping a polygon to the map rectangle the way the original does. This is **not** `RectangleClip`: lineclip clips against the four
// sides in its own order (left, right, bottom, top), decides "inside" with its bit codes and computes the crossing points with its own
// formulas, so the points and their order differ from `RectangleClip`'s in the last digits and sometimes in the order of the ring.

import Foundation

public enum LineClip {
	/// lineclip's `clipPolygon(points, [0, 0, width, height])` (Sutherland–Hodgman). Needs at least one point; an input of none returns none.
	public static func clipPolygon(_ polygon: [Point], width: Double, height: Double) -> [Point] {
		var points = polygon
		var result: [Point] = []
		var edge = 1
		while edge <= 8 {
			result = []
			guard var prev = points.last else { return [] }
			var prevInside = bitCode(prev, width: width, height: height) & edge == 0
			for p in points {
				let inside = bitCode(p, width: width, height: height) & edge == 0
				// if segment goes through the clip window, add an intersection
				if inside != prevInside { result.append(intersect(prev, p, edge, width: width, height: height)) }
				if inside { result.append(p) } // add a point if it's inside
				prev = p
				prevInside = inside
			}
			points = result
			if points.isEmpty { break }
			edge *= 2
		}
		return result
	}

	/// The original's `clipPoly(points, width, height)` without the `secure` option (the packed-graph markup does not use it): fewer than
	/// two points are returned as they are.
	public static func clipPoly(_ points: [Point], width: Double, height: Double) -> [Point] {
		if points.count < 2 { return points }
		return clipPolygon(points, width: width, height: height)
	}

	/// The crossing of a segment with one of the four lines of the rectangle (8 top, 4 bottom, 2 right, 1 left).
	private static func intersect(_ a: Point, _ b: Point, _ edge: Int, width: Double, height: Double) -> Point {
		if edge & 8 != 0 { return Point(x: a.x + (b.x - a.x) * (height - a.y) / (b.y - a.y), y: height) }
		if edge & 4 != 0 { return Point(x: a.x + (b.x - a.x) * (0 - a.y) / (b.y - a.y), y: 0) }
		if edge & 2 != 0 { return Point(x: width, y: a.y + (b.y - a.y) * (width - a.x) / (b.x - a.x)) }
		return Point(x: 0, y: a.y + (b.y - a.y) * (0 - a.x) / (b.x - a.x))
	}

	/// The point's position relative to the rectangle: 1 left, 2 right, 4 bottom (y below 0), 8 top (y above the height).
	private static func bitCode(_ p: Point, width: Double, height: Double) -> Int {
		var code = 0
		if p.x < 0 { code |= 1 } else if p.x > width { code |= 2 }
		if p.y < 0 { code |= 4 } else if p.y > height { code |= 8 }
		return code
	}
}
