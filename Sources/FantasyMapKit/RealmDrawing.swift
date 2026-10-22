// Follows Azgaar's Fantasy Map Generator: the greedy colouring of `assignColors` in `src/generators/states-generator.ts` (d3's Set2 colours, rotated, so
// that neighbouring realms differ, repeats mixed a little: `getMixedColor` in `src/utils/colorUtils.ts`), and the border lines of
// `src/renderers/draw-borders.ts` (chains of the cells' own vertices between land cells of different owners, straight lines, dashed). The original is at
// commit 8936c9c, 2026-10-19, MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md. The wash and the
// way it is held inside the land outline are this package's own (see docs/plans/drawing-realms.md).

import FantasyMapCore
import Foundation

public enum RealmDrawingError: Error, Equatable, Sendable {
	/// The ownership does not describe this map: its length is not the number of cells, the realms are not numbered 1, 2, 3 ... in order, a land cell names no
	/// realm (or one that is not in the list), or a water cell names one.
	case ownershipDoesNotMatchMap
	/// A realm colour is not a colour (a channel that is not finite or not 0 to 1).
	case invalidPalette
	/// The saved realm colours are not one for each realm.
	case colorsDoNotMatchRealms
}

/// The realms' drawing as plain geometry, held in `MapDrawing`.
enum RealmDrawing {
	struct Result: Equatable {
		var wash: [FillCommand]
		var borders: [InkCommand]
		/// The colour of each realm (1 ... K, in order) as used: the saved ones, or the derived ones.
		var colors: [RealmColor] = []
	}

	/// The original's `getMixedColor`: the colour mixed 20% with another colour, then brightened by d3's `brighter(0.3)` (each channel times (1/0.7)^0.3).
	/// The other colour is **seeded**, not random, so the same realms always get the same colours.
	static func mixed(_ c: MapColor, seed: String) -> MapColor {
		var random = Alea(seed: seed)
		let other = (random.next(), random.next(), random.next())
		let factor = pow(1 / 0.7, 0.3)
		func channel(_ a: Double, _ b: Double) -> Double { min(1, (a + (b - a) * 0.2) * factor) }
		return MapColor(red: channel(c.red, other.0), green: channel(c.green, other.1), blue: channel(c.blue, other.2), alpha: c.alpha)
	}

	/// The colour of every realm 1 … K (index 0 unused): **greedy colouring so that neighbouring realms differ.** In realm order, a realm takes the first
	/// colour of the rotating palette that none of its already coloured neighbours has, and the palette rotates by one after each realm; a realm that finds none
	/// takes a seeded colour. A colour that several realms ended with is mixed a little for each repeat after the first (as the original does).
	/// **Colours are told apart by their place in the palette, not by value**, so neighbouring realms differ in palette entry, and a custom palette that
	/// repeats a colour can give neighbours the same value; and a realm that takes the seeded fallback colour is only unlikely to match a neighbour.
	static func colors(realmCount: Int, neighbours: [Set<Int>], palette: [MapColor]) -> [MapColor] {
		var result = [MapColor](repeating: MapColor(red: 0, green: 0, blue: 0, alpha: 0), count: realmCount + 1)
		guard !palette.isEmpty, realmCount > 0 else { return result }
		var rotating = Array(palette.indices), assigned = [Int?](repeating: nil, count: realmCount + 1)
		for realm in 1...realmCount {
			let taken = Set(neighbours[realm].compactMap { assigned[$0] })
			if let entry = rotating.first(where: { !taken.contains($0) }) {
				assigned[realm] = entry
				result[realm] = palette[entry]
			} else {
				result[realm] = mixed(palette[realm % palette.count], seed: "realm-colour-\(realm)")
			}
			rotating.append(rotating.removeFirst())
		}
		var seen = [Int: Int]() // palette entry -> how many realms have it so far
		for realm in 1...realmCount {
			guard let entry = assigned[realm] else { continue }
			seen[entry, default: 0] += 1
			if seen[entry]! > 1 { result[realm] = mixed(result[realm], seed: "realm-mix-\(realm)") }
		}
		return result
	}

	/// **The one partition the wash and the borders both use.** Every land cell has its realm; a water cell beside owned land takes the realm of its nearest
	/// owned land neighbour (these cells lie under the displayed coast wherever smoothing turns water into land, so no sliver of land is left bare); every
	/// other water cell has none (0). Wash colours and border lines both come from this array, so a border always separates two different washes.
	static func extendedOwners(map: LandMap, owner: [Int32]) -> [Int] {
		let n = map.heights.count
		let cells = map.voronoi.cells
		var result = owner.map(Int.init)
		for cell in 0..<n where !Heights.isLand(map.heights[cell]) {
			var best = Double.infinity
			let site = map.grid.points[cell]
			for other in cells.c[cell] where other < n && owner[other] > 0 { // (owner is 0 on every water cell, so this is owned land)
				let p = map.grid.points[other]
				let d = (p.x - site.x) * (p.x - site.x) + (p.y - site.y) * (p.y - site.y)
				if d < best { best = d; result[cell] = Int(owner[other]) }
			}
		}
		return result
	}

	/// The drawing of the realms of a map. `ownership` must describe the map. `fills` are the map's cell polygons (`MapDrawing.fills`).
	/// `colors` are the realms' resolved colours saved with them, if any: they are used as they are; without them the colours are derived by the rule above.
	static func build(map: LandMap, ownership: RealmOwnership, colors saved: [RealmColor]? = nil, fills: [FillCommand], style: MapStyle) throws -> Result {
		let n = map.heights.count
		let realmCount = ownership.realms.count
		// the style's palette is asked only when the colours are to be derived: **colours saved with the realms are used on their own**, whatever the palette is
		if saved == nil { guard style.realmColors.allSatisfy({ [$0.red, $0.green, $0.blue, $0.alpha].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 } }) else { throw RealmDrawingError.invalidPalette } }
		// the realms are numbered 1, 2, 3 ... in order; every land cell names one of them and every water cell none
		guard ownership.owner.count == n, ownership.realms.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }),
			(0..<n).allSatisfy({ cell in
				let owner = Int(ownership.owner[cell])
				return Heights.isLand(map.heights[cell]) ? owner >= 1 && owner <= realmCount : owner == 0
			}) else { throw RealmDrawingError.ownershipDoesNotMatchMap }
		let cells = map.voronoi.cells
		let owners = extendedOwners(map: map, owner: ownership.owner)
		var resolved: [RealmColor] = []

		var colours: [MapColor]
		if let saved {
			// the colours saved with the realms are used as they are (a map opened again shows the colours it was saved with)
			guard saved.count == realmCount else { throw RealmDrawingError.colorsDoNotMatchRealms }
			colours = [MapColor(red: 0, green: 0, blue: 0)] + saved.map { MapColor(red: $0.red, green: $0.green, blue: $0.blue) }
		} else {
			// which realms touch: wherever two cells of the partition meet with different realms, on land or in the water cells beside it (the wash changes colour
			// there, and a border is drawn), so every pair that shows a border between them gets different colours
			var neighbours = [Set<Int>](repeating: [], count: realmCount + 1)
			for cell in 0..<n where owners[cell] > 0 {
				for other in cells.c[cell] where other < n && owners[other] > 0 && owners[other] != owners[cell] { neighbours[owners[cell]].insert(owners[other]) }
			}
			// **the wash is opaque:** the realms' polygons are drawn together at the wash opacity, which only avoids darkening where they overlap if each is opaque, so a
			// palette colour's own alpha is dropped here (the style's `realmWashOpacity` is the transparency control)
			colours = colors(realmCount: realmCount, neighbours: neighbours, palette: style.realmColors).map { MapColor(red: $0.red, green: $0.green, blue: $0.blue) }
		}
		resolved = colours.dropFirst().map { RealmColor(red: $0.red, green: $0.green, blue: $0.blue) }

		var wash: [FillCommand] = []
		if saved != nil || !style.realmColors.isEmpty {
			var fillOfCell: [Int: Int] = [:]
			for (index, fill) in fills.enumerated() { fillOfCell[fill.cell] = index }
			for cell in 0..<n where owners[cell] > 0 {
				guard let own = fillOfCell[cell] else { continue }
				wash.append(FillCommand(points: fills[own].points, color: colours[owners[cell]], cell: cell, isLand: Heights.isLand(map.heights[cell])))
			}
		}
		return Result(wash: wash, borders: borders(map: map, owners: owners, style: style), colors: resolved)
	}

	/// The border lines: chains of the cells' own vertices along every edge between two cells of different realms **in the partition above**, as the original
	/// traces them (straight lines through the raw vertices), a chain ending where the edges meet at a junction of three or more or at the map's frame. So a
	/// border is exactly where the wash changes colour. Between two land cells that is the usual border; where a border reaches a coast it **continues over
	/// the water cells beside the land** (the edges between such cells of two realms, and the raw coast edge where a water cell takes one realm's colour beside
	/// another realm's land), as far as the displayed coast reaches over them, and the land clip cuts the rest. An edge between a land cell and a water cell of
	/// the **same** realm is not a border, so nothing is drawn along a coast or the frame.
	static func borders(map: LandMap, owners: [Int], style: MapStyle) -> [InkCommand] {
		guard style.realmBorderWidth > 0, style.realmBorder.alpha > 0 else { return [] }
		let n = map.heights.count
		let v = map.voronoi
		// the edges between two cells of different realms and of the same kind (land with land, water with water), each once, as a pair of vertex numbers
		var edges: [(Int, Int)] = []
		for cell in 0..<n where owners[cell] > 0 {
			let corners = v.cells.v[cell]
			guard corners.count >= 3 else { continue }
			for k in 0..<corners.count {
				let a = corners[k], b = corners[(k + 1) % corners.count]
				for other in Set(v.vertices.c[a]).intersection(v.vertices.c[b]) where other != cell && other > cell && other < n && owners[other] > 0 && owners[other] != owners[cell] {
					edges.append((a, b))
				}
			}
		}
		var incident: [Int: [Int]] = [:]
		for (index, edge) in edges.enumerated() {
			incident[edge.0, default: []].append(index)
			incident[edge.1, default: []].append(index)
		}
		var used = [Bool](repeating: false, count: edges.count)
		var lines: [InkCommand] = []
		func other(_ edge: Int, from vertex: Int) -> Int { edges[edge].0 == vertex ? edges[edge].1 : edges[edge].0 }
		/// Follows the chain from a vertex along an unused edge until a junction, a dead end or a return to the start.
		func walk(from start: Int, along first: Int) -> [Int] {
			var chain = [start]
			var vertex = start, edge = first
			while true {
				used[edge] = true
				vertex = other(edge, from: vertex)
				chain.append(vertex)
				guard let next = incident[vertex], next.count == 2, let following = next.first(where: { !used[$0] }) else { break }
				edge = following
			}
			return chain
		}
		func command(_ chain: [Int]) -> InkCommand {
			InkCommand(points: chain.map { v.vertices.p[$0] }, isClosed: chain.count > 3 && chain.first == chain.last, color: style.realmBorder, width: style.realmBorderWidth, dash: style.realmBorderDash)
		}
		// open chains first: from the vertices where they end (not exactly two edges meet)
		for (vertex, list) in incident.sorted(by: { $0.key < $1.key }) where list.count != 2 {
			for edge in list where !used[edge] { lines.append(command(walk(from: vertex, along: edge))) }
		}
		// what is left are closed loops
		for edge in edges.indices where !used[edge] { lines.append(command(walk(from: edges[edge].0, along: edge))) }
		return lines
	}
}
