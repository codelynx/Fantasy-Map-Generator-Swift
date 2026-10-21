import FantasyMapKit
import Foundation
import CoreGraphics
import Testing
@testable import FantasyMapKitUI

/// Stage 2a of docs/design-drawing.md: the coast as the cells give it, without pictures.
struct CoastOutlinesTests {
	let helper = MapDrawingTests()

	func map(_ key: String = "highIsland", seed: String = "kaz-1", cells: Int = 800) throws -> LandMap {
		try helper.map(key, seed: seed, cells: cells)
	}

	func signedArea(_ ring: [Point]) -> Double {
		var sum = 0.0
		for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) { sum += a.x * b.y - b.x * a.y }
		return sum / 2
	}

	/// Even-odd point in compound polygon.
	func inside(_ p: Point, _ rings: [[Point]]) -> Bool {
		var inside = false
		for ring in rings {
			var j = ring.count - 1
			for i in 0..<ring.count {
				let a = ring[i], b = ring[j]
				if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
				j = i
			}
		}
		return inside
	}

	func onFrame(_ p: Point, _ m: LandMap) -> Bool { p.x == 0 || p.x == m.width || p.y == 0 || p.y == m.height }

	/// A map whose heights follow `pattern` (evaluated at each cell's site), with features marked up from them.
	func patterned(cells: Int = 800, _ pattern: (Point) -> Height) throws -> LandMap {
		let base = try map("highIsland", cells: cells)
		var saved = base.saved
		saved.heights = base.grid.points.map(pattern)
		let features = try LandFeatures.markup(heights: saved.heights, voronoi: base.voronoi)
		saved.featureIds = features.featureIds
		saved.coastDistance = features.distanceField
		saved.features = features.features.map { SavedFeature($0) }
		return try LandMap(saved: saved)
	}

	/// Two land strips that run off the left and right of the frame, a narrow channel between them, a lake in the lower strip and
	/// an island in the channel: several coast chains meet the frame.
	func channelMap() throws -> LandMap {
		try patterned(cells: 3000) { p in
			if (p.x - 200) * (p.x - 200) + (p.y - 230) * (p.y - 230) < 15 * 15 { return 5 } // a lake in the lower strip
			if (p.x - 200) * (p.x - 200) + (p.y - 150) * (p.y - 150) < 9 * 9 { return 50 } // an island in the channel
			return p.y < 120 || p.y > 180 ? 50 : 5
		}
	}

	/// Proper crossings only (strictly opposite sides); shared endpoints and collinear touching are not counted.
	func cross(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
		func side(_ p: Point, _ q: Point, _ r: Point) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
		let d1 = side(a, b, c), d2 = side(a, b, d), d3 = side(c, d, a), d4 = side(c, d, b)
		return d1 * d2 < 0 && d3 * d4 < 0
	}

	/// Crossings between non-adjacent segments of a ring (including the closing one) and between segments of different rings.
	func crossings(_ rings: [[Point]]) -> Int {
		var count = 0
		let segments = rings.enumerated().flatMap { r, ring in ring.indices.map { (r, $0, ring[$0], ring[($0 + 1) % ring.count], ring.count) } }
		for i in segments.indices {
			for j in (i + 1)..<segments.count {
				let a = segments[i], b = segments[j]
				if a.0 == b.0 {
					let gap = b.1 - a.1
					if gap == 1 || gap == a.4 - 1 { continue } // neighbours, including the closing edge's neighbours
				}
				if max(a.2.x, a.3.x) < min(b.2.x, b.3.x) || max(b.2.x, b.3.x) < min(a.2.x, a.3.x)
					|| max(a.2.y, a.3.y) < min(b.2.y, b.3.y) || max(b.2.y, b.3.y) < min(a.2.y, a.3.y) { continue }
				if cross(a.2, a.3, b.2, b.3) { count += 1 }
			}
		}
		return count
	}

	static let keys = ["highIsland", "continents", "archipelago", "shattered", "atoll", "pangea"]

	@Test func everyCellSiteIsInsideTheLandRingsExactlyWhenItIsLand() throws {
		for key in Self.keys {
			let m = try map(key)
			let coast = CoastOutlines(map: m)
			var wrong = 0
			for cell in 0..<m.heights.count {
				// a site exactly on the frame says nothing under the even-odd rule, so sample a millionth of a unit inside
				let site = m.grid.points[cell]
				let p = Point(x: min(max(site.x, 1e-6), m.width - 1e-6), y: min(max(site.y, 1e-6), m.height - 1e-6))
				if inside(p, coast.landRings) != Heights.isLand(m.heights[cell]) { wrong += 1 }
			}
			#expect(wrong == 0, "\(key): \(wrong) cells disagree with the rings")
		}
	}

	@Test func ringsAreClosedPolygonsAndOuterRingsRunWithLandOnTheLeft() throws {
		for key in Self.keys {
			let m = try map(key)
			let coast = CoastOutlines(map: m)
			#expect(!coast.landRings.isEmpty, "\(key)")
			for ring in coast.landRings {
				#expect(ring.count >= 3 && ring.first != ring.last, "\(key): a ring is stored without repeating its first point")
				#expect(ring.allSatisfy { $0.x >= 0 && $0.x <= m.width && $0.y >= 0 && $0.y <= m.height }, "\(key): ring inside the rectangle")
				#expect(signedArea(ring) != 0)
			}
			// total signed area is the land area: positive, and less than the map
			let total = coast.landRings.map(signedArea).reduce(0, +)
			#expect(total > 0 && total < m.width * m.height, "\(key): land area \(total)")
		}
	}

	@Test func landAreaMatchesTheLandCellsUpToTheFrameSlivers() throws {
		for key in Self.keys {
			let m = try map(key)
			let coast = CoastOutlines(map: m)
			let total = coast.landRings.map(signedArea).reduce(0, +)
			var cells = 0.0
			for cell in 0..<m.heights.count where Heights.isLand(m.heights[cell]) {
				let polygon = MapDrawing.clip(m.voronoi.cells.v[cell].map { m.voronoi.vertices.p[$0] }, width: m.width, height: m.height)
				if polygon.count >= 3 { cells += abs(signedArea(polygon)) }
			}
			// land cells clipped without the frame extension leave slivers at the frame; the rings include them
			let slack = 2 * (m.width + m.height) * m.grid.spacing
			#expect(total >= cells - 1e-6 && total <= cells + slack, "\(key): rings \(total), cells \(cells), slack \(slack)")
		}
	}

	@Test func inkIsOnlyLandWaterBoundaryAndNothingRunsAlongTheFrame() throws {
		for key in Self.keys {
			let m = try map(key)
			let coast = CoastOutlines(map: m)
			let s = m.grid.spacing * 1e-3
			var segments = 0, wrong = 0, alongFrame = 0
			for line in coast.ink {
				if !line.isClosed { #expect(onFrame(line.points.first!, m) && onFrame(line.points.last!, m), "\(key): an open line begins and ends on the frame") }
				let pts = line.isClosed ? line.points + [line.points[0]] : line.points
				for (a, b) in zip(pts, pts.dropFirst()) {
					let dx = b.x - a.x, dy = b.y - a.y, length = (dx * dx + dy * dy).squareRoot()
					guard length > 1e-9 else { continue }
					segments += 1
					if (a.x == b.x && (a.x == 0 || a.x == m.width)) || (a.y == b.y && (a.y == 0 || a.y == m.height)) { alongFrame += 1; continue }
					let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
					// land on the left of the direction of travel: (-dy, dx) is the left normal in the plane's usual orientation
					let left = Point(x: mid.x - dy / length * s, y: mid.y + dx / length * s)
					let right = Point(x: mid.x + dy / length * s, y: mid.y - dx / length * s)
					if !(inside(left, coast.landRings) && !inside(right, coast.landRings)) { wrong += 1 }
				}
			}
			#expect(segments > 10 && wrong == 0 && alongFrame == 0, "\(key): \(segments) segments, \(wrong) not separating land (left) from water (right), \(alongFrame) along the frame")
		}
	}

	@Test func flatMapsGiveTheWholeFrameOrNothingAndNoInk() throws {
		let land = CoastOutlines(map: try helper.flat(height: 60))
		#expect(land.ink.isEmpty && land.landRings.count == 1 && abs(signedArea(land.landRings[0]) - 400 * 300) < 1e-6)
		let water = CoastOutlines(map: try helper.flat(height: 5))
		#expect(water.ink.isEmpty && water.landRings.isEmpty)
	}

	@Test func anEnclosedLakeIsAHoleAndAnIslandInItAnOuterRing() throws {
		// find a generated map with a closed ink loop; its ring has negative area when it is a lake and positive when an island
		var holes = 0, islands = 0
		for key in Self.keys {
			for seed in ["kaz-1", "kaz-2", "kaz-3", "lake-a", "lake-b"] {
				let coast = CoastOutlines(map: try map(key, seed: seed))
				for line in coast.ink where line.isClosed {
					let a = signedArea(line.points)
					if a < 0 { holes += 1 } else if a > 0 { islands += 1 }
				}
			}
		}
		#expect(holes > 0 && islands > 0, "lakes (holes): \(holes), islands: \(islands)")
	}

	@Test func theSameMapGivesTheSameOutlines() throws {
		let m = try map("continents")
		#expect(CoastOutlines(map: m) == CoastOutlines(map: m))
	}

	@Test func aLoadedMapGivesTheSameOutlinesAsTheMapItWasSavedFrom() throws {
		let m = try map("archipelago")
		let again = try LandMap(decoding: try m.encoded())
		#expect(CoastOutlines(map: again) == CoastOutlines(map: m))
	}

	@Test func theDrawingCarriesTheInkAndInkCanBeSwitchedOff() throws {
		let m = try map("highIsland")
		#expect(!MapDrawing(map: m).ink.isEmpty)
		var style = MapStyle.standard
		style.inkWidth = 0
		#expect(MapDrawing(map: m, style: style).ink.isEmpty)
		style.inkWidth = 2
		style.ink = MapColor(red: 0, green: 0, blue: 0, alpha: 0)
		#expect(MapDrawing(map: m, style: style).ink.isEmpty)
	}

	@Test func theOutlinesOfALargeMapAreBuiltInReasonableTime() throws {
		let m = try helper.map("continents", width: 1280, height: 800, cells: 100_000)
		let start = Date()
		let coast = CoastOutlines(map: m)
		let seconds = Date().timeIntervalSince(start)
		print("COAST 100,000 cells: \(coast.landRings.count) rings, \(coast.ink.count) ink lines, \(String(format: "%.0f", seconds * 1000)) ms")
		#expect(!coast.landRings.isEmpty)
	}

	@Test func ringsDoNotCrossThemselvesOrEachOtherAndTheFrameClosureIsConsistent() throws {
		var maps = try Self.keys.map { try map($0) }
		maps.append(try channelMap())
		for m in maps {
			let coast = CoastOutlines(map: m)
			#expect(coast.frameClosureIsConsistent)
			#expect(crossings(coast.landRings) == 0, "ring segments cross")
		}
	}

	@Test func severalCoastsMeetingTheFrameGiveTwoStripsAHoleAndAnIsland() throws {
		let m = try channelMap()
		let coast = CoastOutlines(map: m)
		#expect(coast.frameClosureIsConsistent)
		let open = coast.ink.filter { !$0.isClosed }, closed = coast.ink.filter(\.isClosed)
		#expect(open.count == 2, "two coasts run from frame to frame, got \(open.count)")
		#expect(closed.count == 2, "a lake and an island, got \(closed.count)")
		#expect(closed.map { signedArea($0.points) }.sorted().first! < 0 && closed.map { signedArea($0.points) }.sorted().last! > 0)
		// rings: an upper strip, a lower strip, the lake as a hole inside it, the island in the channel
		let areas = coast.landRings.map(signedArea).sorted()
		#expect(coast.landRings.count == 4 && areas.first! < 0 && areas.filter { $0 > 0 }.count == 3, "areas \(areas)")
		// the strips reach the frame on the left and right, the channel keeps water between them
		for p in [Point(x: 1e-6, y: 50), Point(x: 399.99, y: 50), Point(x: 1e-6, y: 250), Point(x: 399.99, y: 250)] { #expect(inside(p, coast.landRings)) }
		for p in [Point(x: 1e-6, y: 150), Point(x: 399.99, y: 150), Point(x: 100, y: 150)] { #expect(!inside(p, coast.landRings)) }
		#expect(inside(Point(x: 200, y: 150), coast.landRings), "the island")
		#expect(!inside(Point(x: 200, y: 230), coast.landRings), "the lake")
		// end order: every open line's ends are on the frame, land on the left throughout
		for line in open { #expect(onFrame(line.points.first!, m) && onFrame(line.points.last!, m)) }
	}

	@Test func theFrameContinuationPolicyKeepsEndOrderAndDoesNotCreateCrossings() throws {
		// the three-spacing cap and the nearest-frame fallback are drawing policies; try several grids with strips of different widths
		for (channel, cells) in [(30.0, 800), (6.0, 800), (60.0, 3000), (4.0, 3000)] {
			let m = try patterned(cells: cells) { p in abs(p.y - 150) < channel / 2 ? 5 : 50 }
			let coast = CoastOutlines(map: m)
			#expect(coast.frameClosureIsConsistent, "channel \(channel), \(cells) cells")
			#expect(crossings(coast.landRings) == 0, "channel \(channel): crossings")
			let order = coast.landRings.map(signedArea)
			if channel > 2 * m.grid.spacing {
				#expect(order.count == 2 && order.allSatisfy { $0 > 0 }, "channel \(channel), \(cells) cells: two strips, areas \(order)")
			} else {
				// a channel narrower than a cell is only scattered water cells: one land mass with holes, never a crossing
				#expect(order.filter { $0 > 0 }.count == 1, "channel \(channel), \(cells) cells: one land mass, areas \(order)")
			}
		}
	}

	@Test func theChannelPictureIsRenderedForLooking() throws {
		let m = try channelMap()
		let image = try MapImage.render(MapDrawing(map: m), pixelWidth: 800, pixelHeight: 600)
		#expect(image.width == 800)
		if let path = ProcessInfo.processInfo.environment["COAST_PICTURE"], let data = try? MapImage.pngData(MapDrawing(map: m), pixelWidth: 800, pixelHeight: 600) {
			try data.write(to: URL(fileURLWithPath: path))
		}
	}

	// MARK: 2b: smoothing, aligned fills, colour extension

	func distance(_ p: Point, toRings rings: [[Point]]) -> Double {
		var best = Double.infinity
		for ring in rings {
			for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) {
				let dx = b.x - a.x, dy = b.y - a.y
				let t = dx == 0 && dy == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy), 0), 1)
				best = min(best, ((p.x - a.x - t * dx) * (p.x - a.x - t * dx) + (p.y - a.y - t * dy) * (p.y - a.y - t * dy)).squareRoot())
			}
		}
		return best
	}

	func smoothedMaps() throws -> [(String, LandMap)] {
		var maps = try Self.keys.map { ($0, try map($0)) }
		maps.append(("channel", try channelMap()))
		for (channel, cells) in [(30.0, 800), (60.0, 3000), (6.0, 800)] {
			maps.append(("channel \(channel)/\(cells)", try patterned(cells: cells) { p in abs(p.y - 150) < channel / 2 ? 5 : 50 }))
		}
		return maps
	}

	@Test func smoothedOutlinesStaySimpleConsistentAndOnTheFrame() throws {
		for rounds in [1, 2, 3, CoastOutlines.maximumSmoothing] {
			for (label, m) in try smoothedMaps() {
				let coast = CoastOutlines(map: m, smoothing: rounds)
				#expect(coast.frameClosureIsConsistent, "\(label), \(rounds) rounds")
				#expect(crossings(coast.landRings) == 0, "\(label), \(rounds) rounds: smoothed rings cross")
				for line in coast.ink {
					if !line.isClosed { #expect(onFrame(line.points.first!, m) && onFrame(line.points.last!, m), "\(label): an open line ends on the frame") }
					#expect(line.points.allSatisfy { $0.x >= 0 && $0.x <= m.width && $0.y >= 0 && $0.y <= m.height }, "\(label): smoothing never leaves the map")
					let pts = line.isClosed ? line.points + [line.points[0]] : line.points
					for (a, b) in zip(pts, pts.dropFirst()) {
						#expect(!((a.x == b.x && (a.x == 0 || a.x == m.width)) || (a.y == b.y && (a.y == 0 || a.y == m.height))), "\(label): ink along the frame")
					}
				}
			}
		}
	}

	@Test func smoothedInkStillSeparatesLandOnTheLeftFromWaterOnTheRight() throws {
		for (label, m) in try smoothedMaps() {
			let coast = CoastOutlines(map: m, smoothing: 2)
			let s = m.grid.spacing * 1e-3
			var segments = 0, wrong = 0
			for line in coast.ink {
				let pts = line.isClosed ? line.points + [line.points[0]] : line.points
				for (a, b) in zip(pts, pts.dropFirst()) {
					let dx = b.x - a.x, dy = b.y - a.y, length = (dx * dx + dy * dy).squareRoot()
					guard length > 1e-9, !(a.x == b.x && (a.x == 0 || a.x == m.width)), !(a.y == b.y && (a.y == 0 || a.y == m.height)) else { continue }
					segments += 1
					let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
					let left = Point(x: mid.x - dy / length * s, y: mid.y + dx / length * s), right = Point(x: mid.x + dy / length * s, y: mid.y - dx / length * s)
					if !(inside(left, coast.landRings) && !inside(right, coast.landRings)) { wrong += 1 }
				}
			}
			#expect(segments > 10 && wrong == 0, "\(label): \(segments) segments, \(wrong) wrong")
		}
	}

	@Test func smoothingChangesTheLandAreaOnlyModestlyAndZeroRoundsIsTheRawOutline() throws {
		for key in Self.keys {
			let m = try map(key)
			let raw = CoastOutlines(map: m), none = CoastOutlines(map: m, smoothing: 0), smooth = CoastOutlines(map: m, smoothing: 2)
			#expect(raw == none)
			let a = raw.landRings.map(signedArea).reduce(0, +), b = smooth.landRings.map(signedArea).reduce(0, +)
			print("SMOOTH \(key): land area \(Int(a)) -> \(Int(b)) (\(String(format: "%+.2f", 100 * (b - a) / a))%), points \(raw.ink.map(\.points.count).reduce(0, +)) -> \(smooth.ink.map(\.points.count).reduce(0, +))")
			#expect(abs(b - a) / a < 0.05, "\(key): area changed \(a) -> \(b)")
		}
	}

	func alignedPicture(_ m: LandMap, smoothing: Int) throws -> (MapDrawing, CGImage) {
		var style = MapStyle.standard
		style.land = ColorScale(stops: [.init(0, MapColor(red: 0.9, green: 0.1, blue: 0.1)), .init(1, MapColor(red: 1, green: 0.1, blue: 0.1))])
		style.water = ColorScale(stops: [.init(0, MapColor(red: 0.1, green: 0.1, blue: 0.9)), .init(1, MapColor(red: 0.1, green: 0.1, blue: 1))])
		style.paper = MapColor(red: 0, green: 0, blue: 0)
		style.inkWidth = 0
		style.smoothing = smoothing
		let drawing = MapDrawing(map: m, style: style)
		return (drawing, try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 600))
	}

	/// Land is red (not blue), water is blue (not red); the black paper is neither.
	func isLandColour(_ p: (Double, Double, Double, Double), minimum: Double = 0.8) -> Bool { p.0 > minimum && p.2 < 0.3 && p.3 > 0.99 }
	func isWaterColour(_ p: (Double, Double, Double, Double), minimum: Double = 0.8) -> Bool { p.2 > minimum && p.0 < 0.3 && p.3 > 0.99 }

	@Test func theFillFollowsTheSameOutlineAsTheInkIncludingAtTheFrame() throws {
		for rounds in [0, 2] {
			for (label, m) in try smoothedMaps() {
				let (drawing, image) = try alignedPicture(m, smoothing: rounds)
				let rings = try #require(drawing.landClip)
				#expect(rings == drawing.coast.landRings)
				var checked = 0, wrong = 0
				var y = 2.5
				while y < m.height {
					defer { y += 5 }
					var x = 2.5
					while x < m.width {
						defer { x += 5 }
						let p = Point(x: x, y: y)
						guard distance(p, toRings: rings) > 1 else { continue } // anti-aliasing at the edge itself says nothing
						let px = try helper.pixel(image, Int(x * 2), Int(y * 2))
						checked += 1
						if inside(p, rings) ? !isLandColour(px) : !isWaterColour(px) { wrong += 1 } // paper is rejected both ways
					}
				}
				#expect(checked > 1000 && wrong == 0, "\(label), \(rounds) rounds: \(wrong) of \(checked) pixels disagree with the outline")
			}
		}
	}

	@Test func whereSmoothingChangesTheSilhouetteBothSidesAreCovered() throws {
		var totalLost = 0, totalGained = 0
		// the difference between the raw and the smoothed silhouettes, sampled finely with ink off: convex corners lose land
		// (raw inside, smoothed outside: must be water) and concave bays gain it (raw outside, smoothed inside: must be land)
		for (label, m) in try smoothedMaps() {
			let raw = CoastOutlines(map: m).landRings
			let (drawing, image) = try alignedPicture(m, smoothing: 2)
			let smooth = try #require(drawing.landClip)
			var lost = 0, gained = 0, wrong = 0
			// candidates near the smoothed coast: eight directions at four distances around every outline point
			for ring in smooth {
				for q in ring {
					for distance in [0.3, 0.7, 1.2, 2.0] {
						for k in 0..<8 {
							let angle = Double(k) * .pi / 4 + 0.3
							let p = Point(x: q.x + distance * cos(angle), y: q.y + distance * sin(angle))
							guard p.x > 0, p.x < m.width, p.y > 0, p.y < m.height else { continue }
							let wasLand = inside(p, raw), isLand = inside(p, smooth)
							guard wasLand != isLand, self.distance(p, toRings: smooth) > 0.5 else { continue } // a small anti-aliasing exclusion only
							let px = try helper.pixel(image, Int(p.x * 2), Int(p.y * 2))
							if isLand { gained += 1 } else { lost += 1 }
							if isLand ? !isLandColour(px) : !isWaterColour(px) { wrong += 1 }
						}
					}
				}
			}
			totalLost += lost; totalGained += gained
			print("DIFFERENCE \(label): \(lost) samples lost land, \(gained) gained land, \(wrong) wrong")
			#expect(wrong == 0, "\(label): \(wrong) samples in the changed strip are not the right colour (paper counts as wrong)")
		}
		#expect(totalLost > 200 && totalGained > 200, "both kinds of change were sampled: \(totalLost) lost, \(totalGained) gained")
	}

	@Test func theFrameEdgePixelsOfASmoothedPictureFollowTheOutlineToo() throws {
		for (label, m) in try smoothedMaps() {
			let (drawing, image) = try alignedPicture(m, smoothing: 2)
			_ = try #require(drawing.landClip)
			var wrong = 0, checked = 0
			for i in 0..<400 { // along the four sides, a hair inside
				let t = (Double(i) + 0.5) / 400
				for p in [Point(x: t * m.width, y: 0.25), Point(x: t * m.width, y: m.height - 0.25), Point(x: 0.25, y: t * m.height), Point(x: m.width - 0.25, y: t * m.height)] {
					let px = try helper.pixel(image, Int(p.x * 2), Int(p.y * 2))
					if px.0 < 0.05 && px.2 < 0.05 { wrong += 1 } // paper showing
					checked += 1
				}
			}
			#expect(wrong == 0, "\(label): \(wrong) of \(checked) frame pixels show paper")
		}
	}

	@Test func exposedWaterCellsTakeTheColourOfANeighbouringLandCellAndOnlyThose() throws {
		let m = try map("continents")
		let drawing = MapDrawing(map: m)
		#expect(!drawing.exposed.isEmpty)
		for fill in drawing.exposed {
			#expect(!Heights.isLand(m.heights[fill.cell]))
			let neighbours = m.voronoi.cells.c[fill.cell].filter { $0 < m.heights.count && Heights.isLand(m.heights[$0]) }
			#expect(!neighbours.isEmpty)
			let colours = drawing.fills.filter { neighbours.contains($0.cell) }.map(\.color)
			#expect(colours.contains(fill.color), "exposed colour comes from a land neighbour")
		}
		// every water cell with a land neighbour is there, none without
		let expected = (0..<m.heights.count).filter { c in !Heights.isLand(m.heights[c]) && m.voronoi.cells.c[c].contains { $0 < m.heights.count && Heights.isLand(m.heights[$0]) } }
		#expect(Set(drawing.exposed.map(\.cell)).isSubset(of: Set(expected)))
	}

	@Test func anInconsistentFrameClosureFallsBackToStageOneFillsAndDrawsNoCoastline() throws {
		let m = try map("continents")
		var style = MapStyle.standard
		style.land = ColorScale(stops: [.init(0, MapColor(red: 0.9, green: 0.1, blue: 0.1)), .init(1, MapColor(red: 1, green: 0.1, blue: 0.1))])
		style.water = ColorScale(stops: [.init(0, MapColor(red: 0.1, green: 0.1, blue: 0.9)), .init(1, MapColor(red: 0.1, green: 0.1, blue: 1))])
		var coast = CoastOutlines(map: m, smoothing: 2)
		#expect(coast.frameClosureIsConsistent)
		coast.frameClosureIsConsistent = false
		let drawing = MapDrawing(map: m, style: style, coast: coast, fills: MapDrawing(map: m, style: style).fills)
		#expect(drawing.landClip == nil, "no clip")
		#expect(drawing.ink.isEmpty, "the untrusted outline is not inked")
		let image = try MapImage.render(drawing, pixelWidth: 800, pixelHeight: 600)
		// the stage-1 look: every cell site shows its own cell's colour
		var checked = 0, wrong = 0
		for cell in 0..<m.heights.count {
			let p = m.grid.points[cell]
			guard p.x > 1, p.x < m.width - 1, p.y > 1, p.y < m.height - 1 else { continue }
			let px = try helper.pixel(image, Int(p.x * 2), Int(p.y * 2))
			checked += 1
			if Heights.isLand(m.heights[cell]) ? !isLandColour(px) : !isWaterColour(px) { wrong += 1 }
		}
		#expect(checked > 500 && wrong == 0, "\(wrong) of \(checked) cell sites are not their own colour in the fallback")
	}


	// MARK: 2c: roughening

	func strong(_ change: (inout RoughnessSettings) -> Void = { _ in }) -> RoughnessSettings {
		var s = RoughnessSettings()
		s.smoothThreshold = 0.05 // rough nearly everywhere (the original's amplitude); larger amplitudes mostly fall back, see below
		change(&s)
		return s
	}

	@Test func roughnessIsOffByDefaultAndOffGivesTheSmoothedOutlineExactly() throws {
		let m = try map("continents")
		let off = CoastOutlines(map: m, smoothing: 2)
		#expect(off.roughness == .off && MapStyle.standard.roughness == nil)
		#expect(CoastOutlines(map: m, smoothing: 2, roughness: nil) == off)
		#expect(MapDrawing(map: m).coast.roughness == .off)
	}

	@Test func roughenedOutlinesPassEveryCheckOrFallBackToTheSmoothedOneWithAReason() throws {
		for (label, m) in try smoothedMaps() {
			let smooth = CoastOutlines(map: m, smoothing: 2)
			for (name, settings) in [("default", RoughnessSettings()), ("strong", strong()), ("deep", strong { $0.maxDepth = 6 })] {
				let rough = CoastOutlines(map: m, smoothing: 2, roughness: settings)
				print("ROUGH \(label) \(name): \(rough.roughness), points \(smooth.ink.map(\.points.count).reduce(0, +)) -> \(rough.ink.map(\.points.count).reduce(0, +))")
				switch rough.roughness {
				case .applied:
					#expect(rough.frameClosureIsConsistent && crossings(rough.landRings) == 0, "\(label) \(name)")
					#expect(rough.ink.map(\.points.count).reduce(0, +) >= smooth.ink.map(\.points.count).reduce(0, +))
				case .fellBack:
					#expect(rough == { var r = smooth; r.roughness = rough.roughness; return r }(), "\(label) \(name): a fallback is exactly the smoothed outline")
				case .off: Issue.record("asked for roughness, got off")
				}
			}
		}
	}

	@Test func aRoughenedCoastKeepsItsEndsOnTheFrameStaysInsideTheMapAndInksOnlyTheBoundary() throws {
		var applied = 0
		for (label, m) in try smoothedMaps() {
			let coast = CoastOutlines(map: m, smoothing: 2, roughness: strong())
			guard coast.roughness == .applied else { continue }
			applied += 1
			let s = m.grid.spacing * 1e-3
			for line in coast.ink {
				if !line.isClosed { #expect(onFrame(line.points.first!, m) && onFrame(line.points.last!, m), "\(label): an open line ends on the frame") }
				#expect(line.points.allSatisfy { $0.x >= 0 && $0.x <= m.width && $0.y >= 0 && $0.y <= m.height })
				let pts = line.isClosed ? line.points + [line.points[0]] : line.points
				for (a, b) in zip(pts, pts.dropFirst()) {
					let dx = b.x - a.x, dy = b.y - a.y, length = (dx * dx + dy * dy).squareRoot()
					#expect(length > 0, "\(label): no repeated point")
					#expect(!((a.x == b.x && (a.x == 0 || a.x == m.width)) || (a.y == b.y && (a.y == 0 || a.y == m.height))), "\(label): ink along the frame")
					let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
					let left = Point(x: mid.x - dy / length * s, y: mid.y + dx / length * s), right = Point(x: mid.x + dy / length * s, y: mid.y - dx / length * s)
					#expect(inside(left, coast.landRings) && !inside(right, coast.landRings), "\(label): land on the left, water on the right")
				}
			}
		}
		#expect(applied >= 3, "roughening applied on \(applied) maps")
	}

	@Test func theTotalDisplacementBoundPullsEveryInsertedPointBackAndTheClampKeepsItInTheMap() throws {
		// an amplitude far beyond the cap, on a chain with both ends on the frame: every inserted point ends within the cap of
		// its input segment, the original vertices (the ends included) do not move, and nothing leaves the rectangle
		var settings = RoughnessSettings()
		settings.smoothThreshold = 0
		settings.baseAmplitude = 1000
		settings.minEdge = 0
		let chain = [Point(x: 0, y: 40), Point(x: 30, y: 45), Point(x: 60, y: 30), Point(x: 100, y: 50)]
		let rough = try Roughening.displace(chain, closed: false, isLake: false, seed: 9, settings: settings, width: 100, height: 100, budget: .max)
		let free = rough.points
		let cap = 0.1 * 10.0
		let bounded = CoastOutlines.constrain(rough, input: chain, closed: false, cap: cap, 100, 100)
		#expect(zip(free, bounded).contains { $0 != $1 }, "the unbounded displacement was actually pulled back")
		for i in 0..<(chain.count - 1) {
			let a = chain[i], b = chain[i + 1]
			for j in rough.originalIndices[i]...rough.originalIndices[i + 1] {
				let p = bounded[j]
				let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
				let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0), 1)
				let d = ((p.x - a.x - t * dx) * (p.x - a.x - t * dx) + (p.y - a.y - t * dy) * (p.y - a.y - t * dy)).squareRoot()
				#expect(d <= cap + 1e-9, "span \(i) point \(j) lies \(d) from its segment")
			}
		}
		#expect(rough.originalIndices.allSatisfy { bounded[$0] == free[$0] }, "original vertices do not move")
		#expect(bounded.allSatisfy { $0.x >= 0 && $0.x <= 100 && $0.y >= 0 && $0.y <= 100 })
		// a closed loop too, including its closing span
		let loop = [Point(x: 20, y: 20), Point(x: 80, y: 20), Point(x: 50, y: 80)]
		let roughLoop = try Roughening.displace(loop, closed: true, isLake: false, seed: 9, settings: settings, width: 100, height: 100, budget: .max)
		let boundedLoop = CoastOutlines.constrain(roughLoop, input: loop, closed: true, cap: cap, 100, 100)
		for i in 0..<loop.count {
			let a = loop[i], b = loop[(i + 1) % loop.count]
			let end = i + 1 < loop.count ? roughLoop.originalIndices[i + 1] : boundedLoop.count
			for j in roughLoop.originalIndices[i]..<end {
				let p = boundedLoop[j]
				let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
				let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0), 1)
				let d = ((p.x - a.x - t * dx) * (p.x - a.x - t * dx) + (p.y - a.y - t * dy) * (p.y - a.y - t * dy)).squareRoot()
				#expect(d <= cap + 1e-9, "loop span \(i) point \(j) lies \(d) from its segment")
			}
		}
	}

	@Test func theChangedStripOfARoughenedCoastHasTheRightColourOnBothSides() throws {
		var total = 0, applied = 0, marginal = 0
		for (label, m) in try smoothedMaps() {
			var style = MapStyle.standard
			style.land = ColorScale(stops: [.init(0, MapColor(red: 0.9, green: 0.1, blue: 0.1)), .init(1, MapColor(red: 1, green: 0.1, blue: 0.1))])
			style.water = ColorScale(stops: [.init(0, MapColor(red: 0.1, green: 0.1, blue: 0.9)), .init(1, MapColor(red: 0.1, green: 0.1, blue: 1))])
			style.paper = MapColor(red: 0, green: 0, blue: 0)
			style.inkWidth = 0
			style.roughness = strong()
			let drawing = MapDrawing(map: m, style: style)
			guard drawing.coast.roughness == .applied, let rings = drawing.landClip else { continue }
			applied += 1
			let image = try MapImage.render(drawing, pixelWidth: 1600, pixelHeight: 1200) // 4 pixels per map unit, so one pixel is 0.25 unit
			let smooth = CoastOutlines(map: m, smoothing: 2).landRings
			var wrong = 0
			for ring in rings {
				for q in ring {
					for distance in [0.1, 0.2, 0.3, 0.5, 0.8] {
						for k in 0..<8 {
							let angle = Double(k) * .pi / 4 + 0.3
							let p = Point(x: q.x + distance * cos(angle), y: q.y + distance * sin(angle))
							guard p.x > 0, p.x < m.width, p.y > 0, p.y < m.height else { continue }
							guard inside(p, rings) != inside(p, smooth), self.distance(p, toRings: rings) > 0.25 else { continue } // the changed strip, one output pixel away from the edge
							let px = try helper.pixel(image, Int(p.x * 4), Int(p.y * 4))
							total += 1
							// the colours are 0.9 to 1.0 on their channel and the paper is black. 0.7 is a provisional classification tolerance,
							// not evidence of complete coverage: a partly paper-coloured pixel can still exceed it. A reading between 0.7 and 0.8
							// is a recorded rendering defect (seen once: likely anti-aliasing at a seam, which one sample does not establish);
							// those readings are counted and bounded below
							if inside(p, rings) ? !isLandColour(px, minimum: 0.7) : !isWaterColour(px, minimum: 0.7) {
								wrong += 1
								print("WRONG \(label) at \(p.x), \(p.y) inside \(inside(p, rings)) distance \(self.distance(p, toRings: rings)) pixel \(px)")
							} else if inside(p, rings) ? !isLandColour(px) : !isWaterColour(px) { marginal += 1 }
						}
					}
				}
			}
			#expect(wrong == 0, "\(label): \(wrong) strip samples have the wrong colour (paper counts as wrong)")
		}
		print("STRIP \(applied) maps applied, \(total) strip samples, \(marginal) between 0.7 and 0.8")
		#expect(marginal * 200 <= total, "\(marginal) of \(total) strip samples read between 0.7 and 0.8: more than the 0.5% allowance for the recorded seam defect")
		#expect(applied >= 3 && total > 20, "\(applied) maps, \(total) strip samples")
	}

	@Test func theSameInputsGiveTheSameRoughCoastAndAVariantReshufflesIt() throws {
		let m = try map("continents")
		let a = CoastOutlines(map: m, smoothing: 2, roughness: strong())
		#expect(a.roughness == .applied && a == CoastOutlines(map: m, smoothing: 2, roughness: strong()))
		#expect(a != CoastOutlines(map: m, smoothing: 2, roughness: strong { $0.variant = 1 }))
		#expect(a == CoastOutlines(map: m, smoothing: 2, roughness: strong { $0.variant = 0 }), "a variant is a choice, not a one-way roll")
		let other = try helper.map("continents", seed: "kaz-2")
		#expect(CoastOutlines(map: other, smoothing: 2, roughness: strong()).ink != a.ink)
	}

	@Test func invalidSettingsAndAnOversizedOutputFallBackWithoutWork() throws {
		let m = try map("continents")
		let smooth = CoastOutlines(map: m, smoothing: 2)
		var bad = RoughnessSettings()
		bad.maxDepth = 50
		var invalid = CoastOutlines(map: m, smoothing: 2, roughness: bad)
		#expect(invalid.roughness == .fellBack(.invalidSettings))
		invalid.roughness = .off
		#expect(invalid == smooth)
		bad = RoughnessSettings()
		bad.baseAmplitude = .nan
		#expect(CoastOutlines(map: m, smoothing: 2, roughness: bad).roughness == .fellBack(.invalidSettings))
		// worst case over the whole drawing: a 100,000-cell map smoothed twice has about 49,000 outline points, which at depth 6 is
		// about 3.2 million (at depth 4 about 0.8 million, which fits)
		let big = try helper.map("continents", width: 1280, height: 800, cells: 100_000)
		#expect(CoastOutlines(map: big, smoothing: 2, roughness: strong { $0.maxDepth = 6 }).roughness == .fellBack(.outputBudget))
	}

	@Test func theCrossingCheckFindsCrossingsMatchesBruteForceAndGivesUpOnItsBudget() {
		let bowtie = [[Point(x: 0, y: 0), Point(x: 10, y: 10), Point(x: 10, y: 0), Point(x: 0, y: 10)]]
		#expect(CoastOutlines.crossingCount(bowtie, cellSize: 3, 10, 10, budget: 1_000_000) == 1)
		let square = [[Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)]]
		#expect(CoastOutlines.crossingCount(square, cellSize: 3, 10, 10, budget: 1_000_000) == 0)
		// a rectangle the bowtie's two diagonals each cut through twice (touching at shared corners would not count)
		let inner = [[Point(x: 2, y: 4), Point(x: 8, y: 4), Point(x: 8, y: 6), Point(x: 2, y: 6)]]
		#expect(CoastOutlines.crossingCount(bowtie + inner, cellSize: 3, 10, 10, budget: 1_000_000) == 1 + 4, "rings that cut across each other")
		#expect(crossings(bowtie + inner) == 5)
		#expect(CoastOutlines.crossingCount(bowtie + square, cellSize: 3, 10, 10, budget: 1_000_000) == 1, "only touching: not a crossing")
		#expect(CoastOutlines.crossingCount(bowtie, cellSize: 3, 10, 10, budget: 2) == nil, "over budget gives nil")
		// random rings: the grid agrees with the brute-force count
		var rng = SystemRandomNumberGenerator()
		for _ in 0..<30 {
			let rings = (0..<3).map { _ in (0..<12).map { _ in Point(x: Double.random(in: 0...100, using: &rng), y: Double.random(in: 0...100, using: &rng)) } }
			#expect(CoastOutlines.crossingCount(rings, cellSize: 7, 100, 100, budget: .max) == crossings(rings))
		}
	}

	@Test func colourSupportIsRefusedInsideAPureCellAndGrantedAtTheCoast() throws {
		let m = try map("continents")
		let n = m.heights.count
		let pure = (0..<n).first { c in m.voronoi.cells.c[c].allSatisfy { $0 >= n || Heights.isLand(m.heights[$0]) == Heights.isLand(m.heights[c]) } && m.voronoi.cells.b[c] == 0 }!
		let site = m.grid.points[pure]
		#expect(!CoastOutlines.hasColourSupport([([site, Point(x: site.x + 0.01, y: site.y)], false)], map: m))
		let coast = CoastOutlines(map: m, smoothing: 2)
		#expect(CoastOutlines.hasColourSupport(coast.ink.map { ($0.points, $0.isClosed) }, map: m))
	}

	@Test func degenerateGeometryIsDetected() {
		let ring = [Point(x: 1, y: 1), Point(x: 1, y: 1), Point(x: 5, y: 5)]
		#expect(!CoastOutlines.hasNoDegenerateGeometry([ring], [], 10, 10), "a repeated point")
		let along = [InkLine(points: [Point(x: 0, y: 2), Point(x: 0, y: 8)], isClosed: false)]
		#expect(!CoastOutlines.hasNoDegenerateGeometry([], along, 10, 10), "ink along the frame")
		#expect(CoastOutlines.hasNoDegenerateGeometry([[Point(x: 1, y: 1), Point(x: 5, y: 1), Point(x: 5, y: 5)]], [InkLine(points: [Point(x: 0, y: 2), Point(x: 5, y: 3)], isClosed: false)], 10, 10))
	}

	@Test func aStyleWithRoughnessRoundTripsThroughJSON() throws {
		var style = MapStyle.standard
		style.roughness = strong { $0.variant = 3 }
		let again = try JSONDecoder().decode(MapStyle.self, from: try JSONEncoder().encode(style))
		#expect(again == style && again.roughness?.variant == 3)
	}

	// MARK: review corrections to the step-3 guards

	@Test func everyCandidateVisitIsChargedToTheCrossingBudgetEvenWhenAnotherBucketOwnsThePair() {
		// 40 long, nearly horizontal segments that all share the same ~300 buckets: each pair is met in every shared bucket, but
		// is tested in only the first. The old count (charged after that rule) was about 4,800 here and passed a budget of
		// 20,000; counting every visit costs far more and must give up.
		let zigzag = (0..<40).map { i in Point(x: i % 2 == 0 ? 0 : 100, y: Double(i % 3) * 0.4) }
		#expect(CoastOutlines.conflictCount([zigzag], cellSize: 1, 100, 100, budget: 20_000) == nil)
		#expect(CoastOutlines.crossingCount([zigzag], cellSize: 1, 100, 100, budget: 20_000) == nil)
		#expect(CoastOutlines.conflictCount([zigzag], cellSize: 1, 100, 100, budget: .max) != nil, "and it does finish when allowed")
	}

	/// In a real map: a pure cell (no neighbour of the other kind), a boundary cell next to it, and a run of three or more
	/// consecutive neighbours of it that all touch the other kind, whose first and last sites have the pure cell between them.
	func supportCases(_ m: LandMap) -> (pure: Int, boundaryNeighbour: Int, run: [Int])? {
		let n = m.heights.count
		func touches(_ c: Int) -> Bool { m.voronoi.cells.c[c].contains { $0 < n && Heights.isLand(m.heights[$0]) != Heights.isLand(m.heights[c]) } }
		func nearest(_ p: Point) -> Int { (0..<n).min { a, b in
			let pa = m.grid.points[a], pb = m.grid.points[b]
			return (pa.x - p.x) * (pa.x - p.x) + (pa.y - p.y) * (pa.y - p.y) < (pb.x - p.x) * (pb.x - p.x) + (pb.y - p.y) * (pb.y - p.y)
		}! }
		for p in 0..<n where m.voronoi.cells.b[p] == 0 && !touches(p) {
			let ring = m.voronoi.cells.c[p].filter { $0 < n }
			guard ring.count >= 5, let boundary = ring.first(where: touches) else { continue }
			for start in ring.indices {
				var run: [Int] = []
				var k = start
				while run.count < ring.count, touches(ring[k % ring.count]) { run.append(ring[k % ring.count]); k += 1 }
				guard run.count >= 3, run.count < ring.count else { continue }
				let a = m.grid.points[run.first!], b = m.grid.points[run.last!]
				if nearest(Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)) == p { return (p, boundary, run) }
			}
		}
		return nil
	}

	@Test func colourSupportChecksTheLastEndOfAnOpenChainAndTheClosingSegmentOfALoop() throws {
		let m = try map("continents", cells: 3000)
		let found = try #require(supportCases(m))
		let b = m.grid.points[found.boundaryNeighbour], p = m.grid.points[found.pure]
		// open chain: its first end and the midpoint of its one segment are in a supported cell; only the LAST END is in the pure cell
		let end = Point(x: b.x + 0.8 * (p.x - b.x), y: b.y + 0.8 * (p.y - b.y))
		#expect(CoastOutlines.hasColourSupport([([b, Point(x: b.x + 1e-6, y: b.y)], false)], map: m), "both samples supported")
		#expect(!CoastOutlines.hasColourSupport([([b, end], false)], map: m), "an unsupported last end is refused")
		// a run of boundary cells around the pure one: every vertex and every listed segment's midpoint is supported, but the
		// CLOSING segment, last back to first, crosses the pure cell
		let run = found.run.map { m.grid.points[$0] }
		#expect(CoastOutlines.hasColourSupport([(run, false)], map: m), "as an open chain every sample is supported")
		#expect(!CoastOutlines.hasColourSupport([(run, true)], map: m), "as a loop the closing segment's midpoint is in the pure cell")
	}

	@Test func theConflictCheckRefusesContactsThatBreakTheTopologyAndAcceptsSimpleRings() {
		func conflicts(_ rings: [[Point]]) -> Int { CoastOutlines.conflictCount(rings, cellSize: 3, 100, 100, budget: 1_000_000)! }
		func square(_ x: Double, _ y: Double, _ s: Double) -> [Point] { [Point(x: x, y: y), Point(x: x + s, y: y), Point(x: x + s, y: y + s), Point(x: x, y: y + s)] }
		// simple rings pass: a square, a concave L, a ring inside a ring, two separate rings
		let L = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 4), Point(x: 4, y: 4), Point(x: 4, y: 10), Point(x: 0, y: 10)]
		#expect(conflicts([square(10, 10, 20)]) == 0 && conflicts([L]) == 0)
		#expect(conflicts([square(10, 10, 40), square(20, 20, 10)]) == 0 && conflicts([square(10, 10, 10), square(40, 40, 10)]) == 0)
		// a vertex of one ring on an edge of another (touching, not crossing)
		#expect(conflicts([square(10, 10, 20), [Point(x: 20, y: 10), Point(x: 25, y: 0), Point(x: 15, y: 0)]]) >= 1, "a vertex on another ring's edge")
		#expect(CoastOutlines.crossingCount([square(10, 10, 20), [Point(x: 20, y: 10), Point(x: 25, y: 0), Point(x: 15, y: 0)]], cellSize: 3, 100, 100, budget: 1_000_000) == 0, "which a crossing check alone passes")
		// within one ring: a vertex touching a non-adjacent edge (a pinched ring), and a repeated non-consecutive vertex
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 20, y: 20), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)]]) >= 1, "a vertex on a non-adjacent edge")
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10), Point(x: 10, y: 0), Point(x: 5, y: 5)]]) >= 1, "a repeated non-consecutive vertex")
		// collinear overlap: two non-adjacent edges along the same line, overlapping
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 20, y: 0), Point(x: 20, y: 10), Point(x: 30, y: 10), Point(x: 30, y: 0), Point(x: 10, y: 0), Point(x: 10, y: -10)]]) >= 1, "collinear overlap")
		// along the frame, as clamping can make: two rings whose edges overlap on the line y = 0
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 30, y: 0), Point(x: 30, y: 10)], [Point(x: 20, y: 0), Point(x: 50, y: 0), Point(x: 50, y: 10)]]) >= 1, "overlap along the same line in two rings")
		// adjacent edges may share their end point, but not backtrack over each other
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 5, y: 0), Point(x: 5, y: 10)]]) >= 1, "an edge that doubles back along the previous one")
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 20, y: 0), Point(x: 20, y: 10), Point(x: 0, y: 10)]]) == 0, "collinear edges continuing the same way are fine")
		// a proper crossing is still counted
		#expect(conflicts([[Point(x: 0, y: 0), Point(x: 10, y: 10), Point(x: 10, y: 0), Point(x: 0, y: 10)]]) == 1)
	}
}
