import CoreGraphics
import FantasyMapCore
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKit

/// Drawing the realms: the wash and the dashed borders (docs/plans/drawing-realms.md).
struct RealmDrawingTests {
	func map(_ seed: String = "kaz-1", template: String = "continents") throws -> LandMap {
		try LandMap.generate(seed: seed, width: 800, height: 500, cellsDesired: 1500, template: try #require(HeightmapTemplate.named(template)))
	}

	func realms(_ map: LandMap) throws -> RealmOwnership {
		let groups = try LandGroups.find(in: map, reach: 25)
		let policy = RealmPolicy(typicalRealmArea: 40_000, maximumRealms: 500)
		let seeds = try RealmSeeds.place(in: map, groups: groups, count: .automatic, realmSeed: "realms-1", policy: policy)
		return try RealmOwnership.grow(in: map, groups: groups, seeds: seeds, realmSeed: "realms-1", policy: GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3))
	}

	// MARK: the colours

	@Test func neighbouringRealmsAlwaysDifferInColour() throws {
		let m = try map()
		let ownership = try realms(m)
		let drawing = try MapDrawing(map: m, ownership: ownership)
		var colourOfRealm: [Int: MapColor] = [:]
		for fill in drawing.realmWash where fill.isLand { colourOfRealm[Int(ownership.owner[fill.cell])] = fill.color }
		#expect(colourOfRealm.count == ownership.realms.count && ownership.realms.count >= 4)
		var pairs = 0
		for cell in 0..<m.heights.count where Heights.isLand(m.heights[cell]) {
			for other in m.voronoi.cells.c[cell] where other < m.heights.count && Heights.isLand(m.heights[other]) && ownership.owner[other] != ownership.owner[cell] {
				pairs += 1
				#expect(colourOfRealm[Int(ownership.owner[cell])] != colourOfRealm[Int(ownership.owner[other])], "realms \(ownership.owner[cell]) and \(ownership.owner[other]) touch and share a colour")
			}
		}
		#expect(pairs > 20)
	}

	@Test func theGreedyColouringFollowsTheOriginalsRule() {
		let palette = MapStyle.defaultRealmColors
		// three realms in a row, 1-2, 2-3: realm 1 takes the first colour, 2 the next (the palette rotated, and 1's is taken), 3 may reuse 1's
		let c = RealmDrawing.colors(realmCount: 3, neighbours: [[], [2], [1, 3], [2]], palette: palette)
		#expect(c[1] == palette[0] && c[2] == palette[1])
		#expect(c[3] != c[2])
		// every colour differs from its neighbours' when the realms are fewer than the colours
		let all = RealmDrawing.colors(realmCount: 6, neighbours: [[], [2, 3, 4, 5, 6], [1, 3, 4, 5, 6], [1, 2, 4, 5, 6], [1, 2, 3, 5, 6], [1, 2, 3, 4, 6], [1, 2, 3, 4, 5]], palette: palette)
		#expect(Set((1...6).map { all[$0] }).count == 6, "six mutually touching realms take six colours")
		// a seventh finds no free colour and takes a seeded one, different from the six and the same every time
		let seven = RealmDrawing.colors(realmCount: 7, neighbours: [[], [2, 3, 4, 5, 6, 7], [1, 3, 4, 5, 6, 7], [1, 2, 4, 5, 6, 7], [1, 2, 3, 5, 6, 7], [1, 2, 3, 4, 6, 7], [1, 2, 3, 4, 5, 7], [1, 2, 3, 4, 5, 6]], palette: palette)
		#expect(!(1...6).contains { seven[$0] == seven[7] })
		#expect(seven == RealmDrawing.colors(realmCount: 7, neighbours: [[], [2, 3, 4, 5, 6, 7], [1, 3, 4, 5, 6, 7], [1, 2, 4, 5, 6, 7], [1, 2, 3, 5, 6, 7], [1, 2, 3, 4, 6, 7], [1, 2, 3, 4, 5, 7], [1, 2, 3, 4, 5, 6]], palette: palette))
		// realms that do not touch may repeat a colour, and the repeat is mixed a little so that it is not identical
		let apart = RealmDrawing.colors(realmCount: 8, neighbours: [Set<Int>](repeating: [], count: 9), palette: palette)
		#expect(Set((1...8).map { apart[$0] }).count == 8, "the repeats are mixed")
		#expect(RealmDrawing.colors(realmCount: 3, neighbours: [[], [], [], []], palette: []).allSatisfy { $0.alpha == 0 })
	}

	@Test func thePaletteRotatesByOnePerRealmAndATouchedColourIsSkipped() {
		let p = MapStyle.defaultRealmColors
		// realms that touch nobody take the rotating palette in order; the seventh and eighth repeat the first two, mixed
		let apart = RealmDrawing.colors(realmCount: 8, neighbours: [Set<Int>](repeating: [], count: 9), palette: p)
		for k in 0..<6 { #expect(apart[k + 1] == p[k], "realm \(k + 1) takes palette entry \(k)") }
		#expect(apart[7] == RealmDrawing.mixed(p[0], seed: "realm-mix-7") && apart[8] == RealmDrawing.mixed(p[1], seed: "realm-mix-8"))
		// the seventh realm starts again at the first entry, but it touches realm 1 and so takes the next free one (entry 1, a repeat, so mixed)
		var neighbours = [Set<Int>](repeating: [], count: 8)
		neighbours[7] = [1]; neighbours[1] = [7]
		let touching = RealmDrawing.colors(realmCount: 7, neighbours: neighbours, palette: p)
		#expect(touching[7] == RealmDrawing.mixed(p[1], seed: "realm-mix-7"), "skips the entry its neighbour holds")
		#expect(touching[1] == p[0] && touching[2] == p[1])
	}

	@Test func theMixingIsTheOriginalsArithmeticWithASeededOtherColour() {
		// 20% of the way to the other colour, then each channel times (1 / 0.7) ^ 0.3 = 1.1129, held to 1
		var random = Alea(seed: "pin")
		let other = (random.next(), random.next(), random.next())
		let base = MapColor(red: 0.3, green: 0.5, blue: 0.7)
		let got = RealmDrawing.mixed(base, seed: "pin")
		func expected(_ a: Double, _ b: Double) -> Double { min(1, (a + (b - a) * 0.2) * 1.1129) }
		#expect(abs(got.red - expected(0.3, other.0)) < 0.002 && abs(got.green - expected(0.5, other.1)) < 0.002 && abs(got.blue - expected(0.7, other.2)) < 0.002)
		#expect(got.alpha == 1)
		#expect(RealmDrawing.mixed(MapColor(red: 1, green: 1, blue: 1), seed: "pin").red == 1, "held to 1")
	}

	@Test func aPaletteThatIsNotMadeOfColoursIsRefusedWithoutTrapping() throws {
		let m = try map()
		let ownership = try realms(m)
		var style = MapStyle.standard
		style.realmColors = [MapColor(red: .nan, green: 0.5, blue: 0.5)] + MapStyle.defaultRealmColors
		#expect(throws: RealmDrawingError.invalidPalette) { try MapDrawing(map: m, ownership: ownership, style: style) }
		style.realmColors = [MapColor(red: 1.5, green: 0.5, blue: 0.5)]
		#expect(throws: RealmDrawingError.invalidPalette) { try MapDrawing(map: m, ownership: ownership, style: style) }
		style.realmColors = [MapColor(red: 0.5, green: 0.5, blue: 0.5, alpha: .infinity)]
		#expect(throws: RealmDrawingError.invalidPalette) { try MapDrawing(map: m, ownership: ownership, style: style) }
		// a custom palette of one colour is allowed: every realm that finds none free takes a seeded colour
		style.realmColors = [MapColor(red: 0.5, green: 0.5, blue: 0.5)]
		#expect(!(try MapDrawing(map: m, ownership: ownership, style: style)).realmWash.isEmpty)
	}

	@Test func touchingRealmsAcrossTheRotationTakeTheirOwnColours() throws {
		// seven strips of land, the first labelled 7 so that realm 7 touches realm 1 where the palette rotates back to realm 1's colour
		let m = try map()
		var ownership = try realms(m)
		try #require(ownership.realms.count >= 7)
		ownership.realms = Array(ownership.realms.prefix(7))
		let labels: [Int32] = [7, 1, 2, 3, 4, 5, 6]
		for cell in 0..<m.heights.count where Heights.isLand(m.heights[cell]) { ownership.owner[cell] = labels[min(6, Int(m.grid.points[cell].x / (m.width / 7)))] }
		let drawing = try MapDrawing(map: m, ownership: ownership)
		var colour: [Int32: MapColor] = [:]
		for fill in drawing.realmWash where fill.isLand { colour[ownership.owner[fill.cell]] = fill.color }
		let p = MapStyle.defaultRealmColors
		#expect(colour[1] == p[0] && colour[7] == RealmDrawing.mixed(p[1], seed: "realm-mix-7"), "realm 7 touches realm 1 and skips its colour")
	}

	@Test func aMixedColourStaysAColourAndIsBrighterOnAverage() {
		let base = MapColor(red: 0.4, green: 0.5, blue: 0.6)
		let mixedColour = RealmDrawing.mixed(base, seed: "x")
		for channel in [mixedColour.red, mixedColour.green, mixedColour.blue] { #expect(channel >= 0 && channel <= 1) }
		#expect(mixedColour == RealmDrawing.mixed(base, seed: "x") && mixedColour != RealmDrawing.mixed(base, seed: "y"))
		let white = RealmDrawing.mixed(MapColor(red: 1, green: 1, blue: 1), seed: "z")
		#expect(white.red <= 1 && white.green <= 1 && white.blue <= 1)
	}

	// MARK: the borders

	/// The partition the drawing should use, worked out here independently: land cells keep their realm, a water cell beside owned land takes the realm of its
	/// nearest owned land neighbour, the rest none.
	func partition(_ m: LandMap, owner: [Int32]) -> [Int] {
		var result = owner.map(Int.init)
		let n = m.heights.count
		for cell in 0..<n where !Heights.isLand(m.heights[cell]) {
			let site = m.grid.points[cell]
			let near = m.voronoi.cells.c[cell].filter { $0 < n && Heights.isLand(m.heights[$0]) && owner[$0] > 0 }
			func d(_ c: Int) -> Double { let p = m.grid.points[c]; return (p.x - site.x) * (p.x - site.x) + (p.y - site.y) * (p.y - site.y) }
			if let nearest = near.min(by: { d($0) < d($1) }) { result[cell] = Int(owner[nearest]) }
		}
		return result
	}

	/// Every Voronoi edge between two cells of different realms of the partition, once, as the two vertex numbers and the two cells
	/// (found without the drawing's own code).
	func sharedEdges(_ m: LandMap, owner: [Int32]) -> [(a: Int, b: Int, cell: Int, other: Int)] {
		var edges: [(a: Int, b: Int, cell: Int, other: Int)] = []
		let v = m.voronoi
		let n = m.heights.count
		let owners = partition(m, owner: owner)
		for cell in 0..<n where owners[cell] > 0 {
			let corners = v.cells.v[cell]
			for k in 0..<corners.count {
				let a = corners[k], b = corners[(k + 1) % corners.count]
				for other in Set(v.vertices.c[a]).intersection(v.vertices.c[b]) where other > cell && other < n && owners[other] > 0 && owners[other] != owners[cell] {
					edges.append((a, b, cell, other))
				}
			}
		}
		return edges
	}

	static func key(_ a: Point, _ b: Point) -> String {
		let (p, q) = (a.x, a.y) < (b.x, b.y) ? (a, b) : (b, a)
		return "\(p.x.bitPattern),\(p.y.bitPattern)|\(q.x.bitPattern),\(q.y.bitPattern)"
	}

	/// The border chains as the drawing's own function makes them, from the partition worked out here.
	func rawBorders(_ m: LandMap, owner: [Int32], style: MapStyle = .standard) -> [InkCommand] {
		RealmDrawing.borders(map: m, owners: partition(m, owner: owner), style: style)
	}

	@Test func theBordersAreExactlyTheEdgesBetweenCellsOfDifferentRealmsOfOnePartition() throws {
		let m = try map()
		let ownership = try realms(m)
		let edges = sharedEdges(m, owner: ownership.owner)
		let p = m.voronoi.vertices.p
		let expected = edges.map { Self.key(p[$0.a], p[$0.b]) }.sorted()
		let chains = rawBorders(m, owner: ownership.owner)
		var drawn: [String] = []
		for chain in chains { for k in 1..<chain.points.count { drawn.append(Self.key(chain.points[k - 1], chain.points[k])) } }
		#expect(expected.count > 20 && drawn.sorted() == expected, "\(drawn.count) segments for \(expected.count) edges, compared one by one (an omitted edge and a duplicated one would not cancel)")
		#expect(Set(expected).count == expected.count, "no edge twice")
		#expect(chains.allSatisfy { $0.color == MapStyle.standard.realmBorder && $0.width == MapStyle.standard.realmBorderWidth && $0.dash == [3, 2] })
	}

	@Test func chainsEndAtJunctionsAndAreSingleStrokesSoTheDashesRunOnThroughTheirCorners() throws {
		let m = try map()
		let ownership = try realms(m)
		let edges = sharedEdges(m, owner: ownership.owner)
		var degree: [Int: Int] = [:]
		for e in edges { degree[e.a, default: 0] += 1; degree[e.b, default: 0] += 1 }
		// an open chain has two ends at vertices where the number of edges is not two; what is left forms closed loops (found with a union-find over the vertices)
		let ends = degree.filter { $0.value != 2 }.values.reduce(0, +)
		var parent = [Int: Int]()
		func find(_ x: Int) -> Int { var x = x; while let q = parent[x], q != x { x = q }; return x }
		for e in edges { parent[e.a] = parent[e.a] ?? e.a; parent[e.b] = parent[e.b] ?? e.b; parent[find(e.a)] = find(e.b) }
		var componentsWithAnEnd = Set<Int>(), components = Set<Int>()
		for (vertex, d) in degree { components.insert(find(vertex)); if d != 2 { componentsWithAnEnd.insert(find(vertex)) } }
		let loops = components.subtracting(componentsWithAnEnd).count
		let chains = rawBorders(m, owner: ownership.owner)
		#expect(chains.count == ends / 2 + loops, "\(chains.count) strokes for \(ends / 2) open chains and \(loops) loops: a chain is one stroke, never split at a corner")
		#expect(chains.filter(\.isClosed).count == loops)
		// at a junction of three realms three chains end
		let v = m.voronoi
		let junctions = degree.filter { $0.value >= 3 }.keys
		#expect(!junctions.isEmpty, "this map has a junction of three realms")
		for vertex in junctions {
			let point = v.vertices.p[vertex]
			let endsHere = chains.filter { !$0.isClosed }.reduce(0) { $0 + ($1.points.first == point ? 1 : 0) + ($1.points.last == point ? 1 : 0) }
			#expect(endsHere == degree[vertex]! && degree[vertex]! >= 3, "chains end at the junction of three realms")
		}
	}

	@Test func aRealmEnclosedInAnotherHasAClosedLoopOfBorder() throws {
		let m = try map()
		var ownership = try realms(m)
		ownership.realms = Array(ownership.realms.prefix(2))
		ownership.owner = ownership.owner.map { $0 > 0 ? 1 : 0 }
		let v = m.voronoi
		let n = m.heights.count
		let inner = try #require((0..<n).first { cell in Heights.isLand(m.heights[cell]) && v.cells.b[cell] == 0 && v.cells.c[cell].allSatisfy { $0 < n && Heights.isLand(m.heights[$0]) } })
		ownership.owner[inner] = 2
		let chains = rawBorders(m, owner: ownership.owner)
		#expect(chains.count == 1 && chains[0].isClosed && chains[0].points.first == chains[0].points.last)
		#expect(chains[0].points.count == v.cells.v[inner].count + 1, "the loop is the enclosed cell's own outline")
	}

	@Test func noBorderRunsAlongACoastOrBetweenCellsOfOneRealm() throws {
		let m = try map()
		var ownership = try realms(m)
		// one realm owning every land cell has no border at all
		ownership.owner = ownership.owner.map { $0 > 0 ? 1 : 0 }
		ownership.realms = Array(ownership.realms.prefix(1))
		let one = try MapDrawing(map: m, ownership: ownership)
		#expect(one.realmBorders.isEmpty, "no border inside one realm and none on a coast")
		#expect(!one.realmWash.isEmpty)
	}

	@Test func theStyleSwitchesTurnTheWashAndTheBordersOffAndKeepTheLandPicture() throws {
		let m = try map()
		let ownership = try realms(m)
		var style = MapStyle.standard
		style.realmWashOpacity = 0
		#expect(try MapDrawing(map: m, ownership: ownership, style: style).realmWash.isEmpty)
		style = .standard
		style.realmColors = []
		#expect(try MapDrawing(map: m, ownership: ownership, style: style).realmWash.isEmpty)
		style = .standard
		style.realmBorderWidth = 0
		#expect(try MapDrawing(map: m, ownership: ownership, style: style).realmBorders.isEmpty)
		style = .standard
		style.realmBorder.alpha = 0
		#expect(try MapDrawing(map: m, ownership: ownership, style: style).realmBorders.isEmpty)
		style = .standard
		style.realmBorderDash = []
		#expect(try MapDrawing(map: m, ownership: ownership, style: style).realmBorders.allSatisfy { $0.dash.isEmpty })
		#expect(MapDrawing(map: m).realmWash.isEmpty && MapDrawing(map: m).realmBorders.isEmpty, "a land-only drawing has no realms")
	}

	@Test func anOwnershipThatDoesNotDescribeTheMapIsRefusedAndChangesNothing() throws {
		let m = try map()
		var ownership = try realms(m)
		var short = ownership
		short.owner.removeLast()
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try MapDrawing(map: m, ownership: short) }
		ownership.owner[ownership.owner.firstIndex { $0 > 0 }!] = Int32(ownership.realms.count + 1)
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try MapDrawing(map: m, ownership: ownership) }
		var negative = try realms(m)
		negative.owner[0] = -1
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try MapDrawing(map: m, ownership: negative) }
		// every land cell must name a realm and every water cell none; the realms are numbered 1, 2, 3 ...
		let good = try realms(m)
		var landZero = good
		landZero.owner[landZero.owner.indices.first { Heights.isLand(m.heights[$0]) }!] = 0
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try MapDrawing(map: m, ownership: landZero) }
		var waterOwned = good
		waterOwned.owner[waterOwned.owner.indices.first { !Heights.isLand(m.heights[$0]) }!] = 1
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try MapDrawing(map: m, ownership: waterOwned) }
		var renumbered = good
		renumbered.realms[0].number = 7
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try MapDrawing(map: m, ownership: renumbered) }
		var drawing = MapDrawing(map: m)
		let before = drawing
		#expect(throws: RealmDrawingError.ownershipDoesNotMatchMap) { try drawing.addRealms(short, map: m, style: .standard) }
		#expect(drawing == before)
	}

	@Test func theWashHoldsTheOwnedLandAndTheWaterCellsBesideIt() throws {
		let m = try map()
		let ownership = try realms(m)
		let drawing = try MapDrawing(map: m, ownership: ownership)
		let owned = (0..<m.heights.count).filter { Heights.isLand(m.heights[$0]) && ownership.owner[$0] > 0 }
		let washed = Set(drawing.realmWash.filter(\.isLand).map(\.cell))
		#expect(owned.allSatisfy { washed.contains($0) } || owned.count - washed.count < 3, "every owned land cell has its wash polygon (a cell clipped away entirely has none)")
		let water = drawing.realmWash.filter { !$0.isLand }
		#expect(!water.isEmpty && water.allSatisfy { w in m.voronoi.cells.c[w.cell].contains { Heights.isLand(m.heights[$0]) && ownership.owner[$0] > 0 } }, "water cells in the wash lie beside owned land")
		// each water cell takes the colour of the realm of its NEAREST owned land neighbour
		var colourOfRealm: [Int32: MapColor] = [:]
		for fill in drawing.realmWash where fill.isLand { colourOfRealm[ownership.owner[fill.cell]] = fill.color }
		var checked = 0
		for w in water {
			let site = m.grid.points[w.cell]
			let neighbours = m.voronoi.cells.c[w.cell].filter { $0 < m.heights.count && Heights.isLand(m.heights[$0]) && ownership.owner[$0] > 0 }
			let nearest = neighbours.min { a, b in
				let pa = m.grid.points[a], pb = m.grid.points[b]
				return (pa.x - site.x) * (pa.x - site.x) + (pa.y - site.y) * (pa.y - site.y) < (pb.x - site.x) * (pb.x - site.x) + (pb.y - site.y) * (pb.y - site.y)
			}!
			if Set(neighbours.map { ownership.owner[$0] }).count > 1 { checked += 1 }
			#expect(w.color == colourOfRealm[ownership.owner[nearest]])
		}
		#expect(checked > 0, "some water cell sits beside two realms")
		#expect(drawing.realmWashOpacity == MapStyle.standard.realmWashOpacity)
	}

	@Test func identicalInputsGiveTheSameDrawing() throws {
		let m = try map()
		let ownership = try realms(m)
		#expect(try MapDrawing(map: m, ownership: ownership) == MapDrawing(map: m, ownership: ownership))
	}

	// MARK: saved realms

	/// The map with its realm layer attached, the colours saved being the ones the drawing derives (as the demo does).
	func savedRealmMap(colors custom: [RealmColor]? = nil) throws -> LandMap {
		let m = try map()
		let ownership = try realms(m)
		let colours = try custom ?? MapDrawing.resolvedRealmColors(for: m, ownership: ownership)
		let recipe = RealmRecipe(realmSeed: "realms-1", reach: 25, resolvedCount: ownership.realms.count, typicalRealmArea: 40_000, maximumRealms: 500, hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3)
		return try m.adding(RealmLayer(ownership: ownership, recipe: recipe, colors: colours))
	}

	@Test func aMapWithARealmLayerDrawsItsRealmsWithTheColoursSavedWithThem() throws {
		let m = try map()
		let ownership = try realms(m)
		let derived = try MapDrawing(map: m, ownership: ownership)
		// colours saved with the realms are used as they are: here a custom colour for every realm, which the derivation would never choose
		let custom = ownership.realms.map { RealmColor(red: Double($0.number) / 20, green: 0.9, blue: 0.1) }
		let drawing = MapDrawing(map: try savedRealmMap(colors: custom))
		#expect(drawing.realmProblem == nil && !drawing.realmWash.isEmpty && drawing.realmBorders == derived.realmBorders, "the same partition and borders")
		for fill in drawing.realmWash {
			let realm = Int(RealmDrawing.extendedOwners(map: m, owner: ownership.owner)[fill.cell])
			#expect(fill.color == MapColor(red: custom[realm - 1].red, green: custom[realm - 1].green, blue: custom[realm - 1].blue), "cell \(fill.cell) takes realm \(realm)'s saved colour")
		}
		#expect(drawing.realmWash.map(\.color) != derived.realmWash.map(\.color))
	}

	@Test func aMapOpenedAgainDrawsTheSamePictureAsBeforeItWasSaved() throws {
		let saved = try savedRealmMap()
		let before = MapDrawing(map: saved)
		let after = MapDrawing(map: try LandMap(decoding: try saved.encoded()))
		#expect(before == after && !after.realmWash.isEmpty, "the picture after save and open equals the picture before")
		let water = try WaterMap.generate(land: saved)
		#expect(MapDrawing(water: water) == MapDrawing(water: try WaterMap(decoding: try water.encoded())))
		// without saved colours the colours are derived, as for a layer that never had them
		var layerOnly = try #require(saved.realms)
		layerOnly.colors = nil
		let derived = MapDrawing(map: try saved.removingRealms().adding(layerOnly))
		#expect(derived.realmProblem == nil && derived.realmWash.map(\.color) == before.realmWash.map(\.color), "derived colours equal the ones that were saved from the same derivation")
	}

	@Test func theStyleSwitchHidesTheRealmsOfAMapAndAMapWithoutOnesDrawsNone() throws {
		let saved = try savedRealmMap()
		var style = MapStyle.standard
		style.showRealms = false
		let hidden = MapDrawing(map: saved, style: style)
		#expect(hidden.realmWash.isEmpty && hidden.realmBorders.isEmpty && hidden.realmProblem == nil)
		#expect(MapDrawing(map: saved.removingRealms()).realmWash.isEmpty)
	}

	@Test func realmsThatCannotBeDrawnAreReportedNotHidden() throws {
		// a layer with NO saved colours derives them from the style's palette, and a palette that is not made of colours is reported
		let withColours = try savedRealmMap()
		var layerOnly = try #require(withColours.realms)
		layerOnly.colors = nil
		let derived = try withColours.removingRealms().adding(layerOnly)
		var style = MapStyle.standard
		style.realmColors = [MapColor(red: .nan, green: 0, blue: 0)]
		let drawing = MapDrawing(map: derived, style: style)
		#expect(drawing.realmProblem != nil && drawing.realmWash.isEmpty && drawing.realmBorders.isEmpty)
		#expect(throws: RealmDrawingError.invalidPalette) { try MapDrawing.resolvedRealmColors(for: derived, ownership: layerOnly.ownership, style: style) }
		var none = MapStyle.standard
		none.realmColors = []
		#expect(throws: RealmDrawingError.invalidPalette) { try MapDrawing.resolvedRealmColors(for: derived, ownership: layerOnly.ownership, style: none) }
		// and an empty palette with no saved colours draws no wash (the borders still show)
		let emptyPalette = MapDrawing(map: derived, style: none)
		#expect(emptyPalette.realmProblem == nil && emptyPalette.realmWash.isEmpty && !emptyPalette.realmBorders.isEmpty)
	}

	@Test func savedColoursAreUsedOnTheirOwnWhateverTheStylesPaletteIs() throws {
		let saved = try savedRealmMap()
		let expected = MapDrawing(map: saved)
		#expect(!expected.realmWash.isEmpty && expected.realmProblem == nil)
		for palette in [[MapColor](), [MapColor(red: .nan, green: 0, blue: 0)], [MapColor(red: 9, green: 9, blue: 9)]] {
			var style = MapStyle.standard
			style.realmColors = palette
			let drawing = MapDrawing(map: saved, style: style)
			#expect(drawing.realmProblem == nil && drawing.realmWash == expected.realmWash && drawing.realmBorders == expected.realmBorders, "palette \(palette)")
		}
		// the realms are hidden by the switches, not by the palette
		var hidden = MapStyle.standard
		hidden.showRealms = false
		#expect(MapDrawing(map: saved, style: hidden).realmWash.isEmpty)
		var transparent = MapStyle.standard
		transparent.realmWashOpacity = 0
		#expect(MapDrawing(map: saved, style: transparent).realmWash.isEmpty && !MapDrawing(map: saved, style: transparent).realmBorders.isEmpty)
	}

	@Test func theResolvedColoursAreOneForEachRealmAndAreTheOnesTheDrawingUses() throws {
		let m = try map()
		let ownership = try realms(m)
		let colours = try MapDrawing.resolvedRealmColors(for: m, ownership: ownership)
		#expect(colours.count == ownership.realms.count)
		let drawing = try MapDrawing(map: m, ownership: ownership)
		let owners = RealmDrawing.extendedOwners(map: m, owner: ownership.owner)
		for fill in drawing.realmWash { #expect(fill.color == MapColor(red: colours[owners[fill.cell] - 1].red, green: colours[owners[fill.cell] - 1].green, blue: colours[owners[fill.cell] - 1].blue)) }
		#expect(colours.allSatisfy { [$0.red, $0.green, $0.blue].allSatisfy { $0 >= 0 && $0 <= 1 } })
		// the drawing refuses saved colours that are not one for each realm
		var wrong = try #require(try savedRealmMap().realms)
		wrong.colors = Array(wrong.colors!.dropLast())
		#expect(throws: RealmDrawingError.colorsDoNotMatchRealms) { try RealmDrawing.build(map: m, ownership: wrong.ownership, colors: wrong.colors, fills: MapDrawing(map: m).fills, style: .standard) }
	}

	// MARK: the pictures

	@MainActor
	@Test func theWashAndBordersShowOnlyOnTheLandAndBlendAtTheWashOpacityInBothRenderers() throws {
		let m = try map()
		let ownership = try realms(m)
		let with = try MapDrawing(map: m, ownership: ownership)
		let plain = MapDrawing(map: m)
		let mask = RiverDrawingTests.landMask(try #require(with.landClip), width: 800, height: 500)
		func view(_ d: MapDrawing) throws -> [UInt8] { try ViewRendering.pixels(d, width: 800, height: 500) }
		let imageWith = RiverDrawingTests.pixels(try MapImage.render(with, pixelWidth: 800, pixelHeight: 500)), imagePlain = RiverDrawingTests.pixels(try MapImage.render(plain, pixelWidth: 800, pixelHeight: 500))
		let viewWith = try view(with), viewPlain = try view(plain)
		for (name, a, b) in [("image", imageWith, imagePlain), ("view", viewWith, viewPlain)] {
			let d = RiverDrawingTests.differences(a, b, mask: mask, width: 800, height: 500)
			// the SwiftUI renderer's output varies a little from run to run (see `ViewRendering.tolerance`): some pixels are allowed there, none in the image renderer
			#expect(d.changed > 100_000 && d.outside <= (name == "image" ? 0 : ViewRendering.tolerance), "\(name): \(d.changed) pixels changed, \(d.outside) outside the land silhouette")
		}
		// the blend: at a land cell's site (no river or border near it) the pixel is the land colour with the realm colour at the wash opacity over it
		var checked = 0, agreed = 0
		for fill in with.realmWash.filter(\.isLand) {
			let p = m.grid.points[fill.cell]
			let x = Int(p.x), y = Int(p.y)
			guard x > 2, y > 2, x < 797, y < 497, mask[y * 800 + x] else { continue }
			let i = (y * 800 + x) * 4
			let base = (Double(imagePlain[i]) / 255, Double(imagePlain[i + 1]) / 255, Double(imagePlain[i + 2]) / 255)
			let expected = (base.0 * 0.7 + fill.color.red * 0.3, base.1 * 0.7 + fill.color.green * 0.3, base.2 * 0.7 + fill.color.blue * 0.3)
			for (pixels, label) in [(imageWith, "image"), (viewWith, "view")] where label == "image" {
				_ = label
				let got = (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
				checked += 1
				if abs(got.0 - expected.0) < 0.03 && abs(got.1 - expected.1) < 0.03 && abs(got.2 - expected.2) < 0.03 { agreed += 1 }
			}
		}
		#expect(checked > 200 && Double(agreed) / Double(checked) > 0.9, "\(agreed) of \(checked) sampled cells show the wash at its opacity")
		// the view and the image renderer agree on the wash too
		var same = 0, total = 0
		for fill in with.realmWash.filter(\.isLand).prefix(300) {
			let p = m.grid.points[fill.cell]
			let x = Int(p.x), y = Int(p.y)
			guard x > 2, y > 2, x < 797, y < 497 else { continue }
			let i = (y * 800 + x) * 4
			total += 1
			if abs(Int(imageWith[i]) - Int(viewWith[i])) <= 6 && abs(Int(imageWith[i + 1]) - Int(viewWith[i + 1])) <= 6 && abs(Int(imageWith[i + 2]) - Int(viewWith[i + 2])) <= 6 { same += 1 }
		}
		#expect(total > 100 && Double(same) / Double(total) > 0.95, "the view and the image agree at \(same) of \(total) sites")
	}

	// MARK: the coast and the clips

	static func pointKey(_ p: Point) -> String { "\(p.x.bitPattern),\(p.y.bitPattern)" }

	/// The distance from a point to the nearest edge of the rings.
	static func distance(_ p: Point, to rings: [[Point]]) -> Double {
		var best = Double.infinity
		for ring in rings {
			for i in ring.indices {
				let a = ring[i], b = ring[(i + 1) % ring.count]
				let dx = b.x - a.x, dy = b.y - a.y
				let len2 = dx * dx + dy * dy
				let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
				best = min(best, ((p.x - a.x - t * dx) * (p.x - a.x - t * dx) + (p.y - a.y - t * dy) * (p.y - a.y - t * dy)).squareRoot())
			}
		}
		return best
	}

	@Test func aBorderAlwaysSeparatesTwoDifferentWashesAndContinuesThroughTheWaterBesideTheLand() throws {
		let m = try map()
		let ownership = try realms(m)
		let drawing = try MapDrawing(map: m, ownership: ownership)
		let colourOfCell = Dictionary(uniqueKeysWithValues: drawing.realmWash.map { ($0.cell, $0.color) })
		let edges = sharedEdges(m, owner: ownership.owner)
		var water = 0
		for e in edges {
			// the two cells across every border edge have different wash colours: the border is the line between two washes, wherever it runs
			#expect(colourOfCell[e.cell] != nil && colourOfCell[e.other] != nil && colourOfCell[e.cell] != colourOfCell[e.other])
			if !Heights.isLand(m.heights[e.cell]) { water += 1 }
		}
		#expect(water > 0, "some border edges run through water cells beside the land (\(water) of \(edges.count)): the border continues to the displayed coast")
		// a chain that runs from the land into the water carries on along the same partition: some chain has an edge of each kind
		let p = m.voronoi.vertices.p
		let landEdges = Set(edges.filter { Heights.isLand(m.heights[$0.cell]) }.map { Self.key(p[$0.a], p[$0.b]) })
		var crossing = 0
		for chain in drawing.realmBorders {
			let keys = (1..<chain.points.count).map { Self.key(chain.points[$0 - 1], chain.points[$0]) }
			if keys.contains(where: { landEdges.contains($0) }) && keys.contains(where: { !landEdges.contains($0) }) { crossing += 1 }
		}
		#expect(crossing > 0, "\(crossing) chains run on from land into water")
	}

	@Test func theOpenEndsOfABorderAreOutsideTheDisplayedLandExceptAtTheFrame() throws {
		let m = try map()
		let ownership = try realms(m)
		let drawing = try MapDrawing(map: m, ownership: ownership)
		let index = RingIndex(rings: try #require(drawing.landClip), height: m.height)
		let slack = 3 * m.grid.spacing
		var ends = 0, inside = 0
		for chain in drawing.realmBorders where !chain.isClosed {
			for end in [chain.points.first!, chain.points.last!] {
				ends += 1
				let nearFrame = end.x < slack || end.y < slack || end.x > m.width - slack || end.y > m.height - slack
				if index.contains(end) && !nearFrame { inside += 1 }
			}
		}
		// an end inside the displayed land and away from the frame would be a border that stops short of the coast it should reach (a junction of three
		// is also an end: the three chains meet there, so only chain ends that are not junctions are asked)
		var degree: [Int: Int] = [:]
		for e in sharedEdges(m, owner: ownership.owner) { degree[e.a, default: 0] += 1; degree[e.b, default: 0] += 1 }
		let junctions = Set(degree.filter { $0.value >= 3 }.keys.map { Self.pointKey(m.voronoi.vertices.p[$0]) })
		var stopping = 0
		for chain in drawing.realmBorders where !chain.isClosed {
			for end in [chain.points.first!, chain.points.last!] where !junctions.contains(Self.pointKey(end)) {
				let nearFrame = end.x < slack || end.y < slack || end.x > m.width - slack || end.y > m.height - slack
				if index.contains(end) && !nearFrame { stopping += 1 }
			}
		}
		#expect(ends > 10 && stopping == 0, "\(stopping) of \(ends) border ends stop inside the displayed land away from the frame and from a junction (\(inside) counting junctions)")
	}

	@Test func theWashIsOpaqueWhateverThePaletteAlphaAndOverlapsDoNotDarkenIt() throws {
		let m = try map()
		let ownership = try realms(m)
		var style = MapStyle.standard
		style.realmColors = MapStyle.defaultRealmColors.map { MapColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 0.4) }
		let drawing = try MapDrawing(map: m, ownership: ownership, style: style)
		#expect(!drawing.realmWash.isEmpty && drawing.realmWash.allSatisfy { $0.color.alpha == 1 }, "a palette colour's alpha is dropped: the wash opacity is the control")
		// two overlapping polygons of one colour, drawn at 0.5 together: the overlap is the same as the rest (an opaque group is not darkened by overlap)
		let land = MapDrawing(map: m)
		let mask = RiverDrawingTests.landMask(try #require(land.landClip), width: 800, height: 500)
		var found: (Int, Int)?
		search: for y in stride(from: 40, to: 440, by: 10) { for x in stride(from: 40, to: 700, by: 10) where (0..<80).allSatisfy({ dy in (0..<80).allSatisfy { dx in mask[(y + dy) * 800 + x + dx] } }) { found = (x, y); break search } }
		let (x0, y0) = try #require(found, "an 80 by 80 patch of land")
		func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> [Point] { [Point(x: Double(x), y: Double(y)), Point(x: Double(x + w), y: Double(y)), Point(x: Double(x + w), y: Double(y + h)), Point(x: Double(x), y: Double(y + h))] }
		var layered = land
		layered.realmWash = [FillCommand(points: rect(x0, y0, 50, 50), color: MapColor(red: 1, green: 0, blue: 0), cell: 0, isLand: true), FillCommand(points: rect(x0 + 25, y0 + 25, 50, 50), color: MapColor(red: 1, green: 0, blue: 0), cell: 1, isLand: true)]
		layered.realmWashOpacity = 0.5
		let image = RiverDrawingTests.pixels(try MapImage.render(layered, pixelWidth: 800, pixelHeight: 500))
		func px(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [UInt8] { let i = (y * 800 + x) * 4; return Array(pixels[i..<i + 3]) }
		let single = px(image, x0 + 10, y0 + 10), overlap = px(image, x0 + 40, y0 + 40)
		let plain = px(RiverDrawingTests.pixels(try MapImage.render(land, pixelWidth: 800, pixelHeight: 500)), x0 + 10, y0 + 10)
		#expect(single != plain, "the wash shows")
		#expect(zip(single, overlap).allSatisfy { abs(Int($0) - Int($1)) <= 3 }, "overlap \(overlap) against single \(single)")
	}

	/// A drawing whose realm layers are a whole-map fill and thick lines across the whole map, so that the land clip alone decides where they show.
	@MainActor
	func wholeMapLayers(dash: [Double]) throws -> (drawing: MapDrawing, plain: MapDrawing, mask: [Bool]) {
		let m = try map()
		var drawing = MapDrawing(map: m)
		let rings = try #require(drawing.landClip)
		let plain = drawing
		drawing.realmWash = [FillCommand(points: [Point(x: -10, y: -10), Point(x: 810, y: -10), Point(x: 810, y: 510), Point(x: -10, y: 510)], color: MapColor(red: 1, green: 0, blue: 1), cell: 0, isLand: true)]
		drawing.realmWashOpacity = 1
		let lines = stride(from: 20.0, to: 500, by: 40).map { y in InkCommand(points: [Point(x: -10, y: y), Point(x: 810, y: y)], isClosed: false, color: MapColor(red: 0, green: 0, blue: 0), width: 6, dash: dash) }
		drawing.realmBorders = lines
		return (drawing, plain, RiverDrawingTests.landMask(rings, width: 800, height: 500))
	}

	@MainActor
	func renderBoth(_ d: MapDrawing) throws -> (image: [UInt8], view: [UInt8]) {
		return (RiverDrawingTests.pixels(try MapImage.render(d, pixelWidth: 800, pixelHeight: 500)), try ViewRendering.pixels(d, width: 800, height: 500))
	}

	@MainActor
	@Test func aWashAndBorderLinesThatReachOverTheWaterAreClippedToTheLandByBothRenderers() throws {
		let (drawing, plain, mask) = try wholeMapLayers(dash: [])
		let a = try renderBoth(drawing), b = try renderBoth(plain)
		for (name, with, without) in [("image", a.image, b.image), ("view", a.view, b.view)] {
			let d = RiverDrawingTests.differences(with, without, mask: mask, width: 800, height: 500)
			#expect(d.changed > 50_000 && d.outside <= (name == "image" ? 0 : ViewRendering.tolerance), "\(name): \(d.changed) pixels changed, \(d.outside) outside the land")
		}
		// the lines alone (no wash), over the water: nothing outside the land either
		var linesOnly = drawing
		linesOnly.realmWash = []
		let l = try renderBoth(linesOnly)
		for (name, with, without) in [("image", l.image, b.image), ("view", l.view, b.view)] {
			let d = RiverDrawingTests.differences(with, without, mask: mask, width: 800, height: 500)
			#expect(d.changed > 5_000 && d.outside <= (name == "image" ? 0 : ViewRendering.tolerance), "\(name) lines: \(d.changed) pixels changed, \(d.outside) outside the land")
		}
	}

	@MainActor
	@Test func theDashPatternIsAppliedByBothRenderers() throws {
		let solid = try wholeMapLayers(dash: []), dashed = try wholeMapLayers(dash: [12, 12])
		var solidOnly = solid.drawing, dashedOnly = dashed.drawing
		solidOnly.realmWash = []; dashedOnly.realmWash = []
		let base = try renderBoth(solid.plain)
		let s = try renderBoth(solidOnly), d = try renderBoth(dashedOnly)
		func changed(_ x: [UInt8], _ y: [UInt8]) -> Int { zip(x, y).enumerated().filter { $0.offset % 4 != 3 && $0.element.0 != $0.element.1 }.count }
		for (name, solidPixels, dashedPixels, basePixels) in [("image", s.image, d.image, base.image), ("view", s.view, d.view, base.view)] {
			let full = changed(solidPixels, basePixels), half = changed(dashedPixels, basePixels)
			#expect(full > 5_000 && Double(half) > Double(full) * 0.35 && Double(half) < Double(full) * 0.65, "\(name): the dashed lines paint \(half) of the solid lines' \(full) channel values")
		}
	}

	@Test func whenTheCoastIsNotTrustedNoRealmIsPaintedOverTheSea() throws {
		let m = try map()
		let ownership = try realms(m)
		var coast = CoastOutlines(map: m, smoothing: 2)
		coast.frameClosureIsConsistent = false
		var drawing = MapDrawing(map: m, style: .standard, coast: coast, fills: MapDrawing(map: m).fills)
		let plain = drawing
		try drawing.addRealms(ownership, map: m, style: .standard)
		#expect(drawing.landClip == nil && !drawing.realmWash.isEmpty)
		#expect(RiverDrawingTests.pixels(try MapImage.render(drawing, pixelWidth: 400, pixelHeight: 250)) == RiverDrawingTests.pixels(try MapImage.render(plain, pixelWidth: 400, pixelHeight: 250)), "the realms are left out of an untrusted picture")
	}
}
