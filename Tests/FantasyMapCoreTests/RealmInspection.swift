import Foundation
import Testing
@testable import FantasyMapCore

/// A measurement, not a test: realm sizes and shape proxies for a bounded selection of maps, counts and unevenness values. Asserts
/// nothing; runs only on request:  FMK_MEASURE=1 swift test -c release --filter RealmInspection
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FMK_MEASURE"] != nil))
struct RealmInspection {
	@Test func inspect() throws {
		let typical = 40_000.0
		let growth = { (u: Double) in GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: u) }
		for (cells, seedNames) in [(10_000, ["kaz-1", "kaz-2", "kaz-3"]), (100_000, ["kaz-1"])] {
			for key in ["continents", "pangea", "archipelago", "shattered"] {
				for seed in seedNames {
					let m = try LandMap.generate(seed: seed, width: 1280, height: 800, cellsDesired: cells, template: try #require(HeightmapTemplate.named(key)))
					let groups = try LandGroups.find(in: m, reach: 25)
					let v = m.voronoi
					var areas = [Double](repeating: 0, count: m.heights.count)
					for c in 0..<m.heights.count where groups.landmassOfCell[c] >= 0 {
						let p = RectangleClip.clip(v.cells.v[c].map { v.vertices.p[$0] }, width: m.width, height: m.height)
						areas[c] = p.count >= 3 ? abs(RealmSeeds.polygonArea(p)) : 0
					}
					var groupArea = [Double](repeating: 0, count: groups.groups.count)
					for c in 0..<areas.count where groups.groupOfCell[c] >= 0 { groupArea[Int(groups.groupOfCell[c])] += areas[c] }
					let landArea = groupArea.reduce(0, +)
					let c = groups.minimumRealms
					let perGroup = groupArea.reduce(0) { $0 + max(1, Int(($1 / typical).rounded())) }
					let global = max(c, Int((landArea / typical).rounded()))
					let landCells = groups.groups.reduce(0) { $0 + $1.cellCount }
					// "global" is the OLD automatic rule (total area over the typical area, at least C), "auto" is the package's automatic count now
					let chosen: [(String, Int)] = [("C", c), ("C+4", c + 4), ("global", global), ("perGroup", perGroup)].map { ($0.0, min($0.1, min(landCells, 500))) }
					var counts: [(String, RealmCount)] = chosen.map { ($0.0, .chosen($0.1)) }
					counts.append(("auto", .automatic))
					for (mode, count) in counts {
						for u in [0.0, 6.0] {
							guard let seeds = try? RealmSeeds.place(in: m, groups: groups, count: count, realmSeed: "r", policy: RealmPolicy(typicalRealmArea: typical, maximumRealms: 500)),
								let o = try? RealmOwnership.grow(in: m, groups: groups, seeds: seeds, realmSeed: "r", policy: growth(u)) else { continue }
							let k = seeds.resolvedCount
							let sizes = o.realms.map(\.area)
							let largest = (sizes.max() ?? 0) / max(landArea, 1)
							let tiny = o.realms.filter { $0.cellCount <= (cells == 100_000 ? 50 : 5) }.count
							let substantial = o.realms.filter { $0.area >= typical / 4 }.count
							// realms bordered by exactly one other realm over land adjacency (a proxy for enclaves and peninsulas), and dead-end cells
							var neighbours = [Set<Int32>](repeating: [], count: o.realms.count)
							var deadEnds = [Int](repeating: 0, count: o.realms.count)
							for cell in 0..<m.heights.count where o.owner[cell] > 0 {
								let r = Int(o.owner[cell]) - 1
								var same = 0
								for other in v.cells.c[cell] where other >= 0 && other < m.heights.count && o.owner[other] > 0 {
									if o.owner[other] == o.owner[cell] { same += 1 } else { neighbours[r].insert(o.owner[other]) }
								}
								if same <= 1 { deadEnds[r] += 1 }
							}
							let single = neighbours.filter { $0.count == 1 }.count
							var worstDead = 0.0
							for (i, realm) in o.realms.enumerated() where realm.cellCount > 20 { worstDead = max(worstDead, Double(deadEnds[i]) / Double(realm.cellCount)) }
							print("R|\(cells)|\(key)|\(seed)|\(mode)|u\(Int(u))|C\(c)|K\(k)|largest \(String(format: "%.3f", largest))|tiny \(tiny)|substantial \(substantial)|single \(single)|dead \(String(format: "%.3f", worstDead))")
						}
					}
				}
			}
		}
	}
}
