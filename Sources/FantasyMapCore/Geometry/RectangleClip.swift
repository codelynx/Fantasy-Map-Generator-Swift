import Foundation

/// Clipping a convex polygon to the map's rectangle, narrowly: the one operation the land layer's realm geometry and the drawing
/// layer both need, so there is one implementation.
public enum RectangleClip {
	/// A polygon clipped to the rectangle 0 ... width by 0 ... height (Sutherland–Hodgman). A convex polygon gives one convex
	/// polygon, possibly empty (fewer than three points, or nothing). A concave polygon is clipped as the algorithm does and may
	/// get edges along the rectangle's border that join separate pieces.
	public static func clip(_ polygon: [Point], width: Double, height: Double) -> [Point] {
		var output = polygon
		// each edge: a point is inside when `inside` is true; `cross` finds where a segment meets the edge
		let edges: [(inside: (Point) -> Bool, cross: (Point, Point) -> Point)] = [
			({ $0.x >= 0 }, { a, b in let t = (0 - a.x) / (b.x - a.x); return Point(x: 0, y: a.y + t * (b.y - a.y)) }),
			({ $0.x <= width }, { a, b in let t = (width - a.x) / (b.x - a.x); return Point(x: width, y: a.y + t * (b.y - a.y)) }),
			({ $0.y >= 0 }, { a, b in let t = (0 - a.y) / (b.y - a.y); return Point(x: a.x + t * (b.x - a.x), y: 0) }),
			({ $0.y <= height }, { a, b in let t = (height - a.y) / (b.y - a.y); return Point(x: a.x + t * (b.x - a.x), y: height) })
		]
		for edge in edges {
			let input = output
			output = []
			guard var previous = input.last else { return [] }
			for current in input {
				if edge.inside(current) {
					if !edge.inside(previous) { output.append(edge.cross(previous, current)) }
					output.append(current)
				} else if edge.inside(previous) {
					output.append(edge.cross(previous, current))
				}
				previous = current
			}
		}
		return output
	}
}
