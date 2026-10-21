import Foundation
import Testing
@testable import FantasyMapKit

/// A measurement, not a test of behaviour: land area, landmass counts and the number of groups C across reaches, for every template
/// and several seeds. It asserts nothing and runs only on request:
///
///     FMK_MEASURE=1 swift test -c release --filter GeographyMeasurement
///
/// `FMK_CELLS` (default 10000) sets the cell count.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FMK_MEASURE"] != nil))
struct GeographyMeasurement {
	@Test func measure() throws {
		let width = 1280.0, height = 800.0
		let reaches = [0.0, 4, 8, 20, 40, 80]
		let cells = Int(ProcessInfo.processInfo.environment["FMK_CELLS"] ?? "") ?? 10_000
		// a landmass of at most this many cells is called tiny; the cell count changes what that means in map units, so it is scaled
		let tinyCells = max(1, 5 * cells / 10_000)
		for template in HeightmapTemplate.all {
			for n in 1...5 {
				let seed = "kaz-\(n)"
				let m = try LandMap.generate(seed: seed, width: width, height: height, cellsDesired: cells, template: template)
				let v = m.voronoi
				var area = 0.0
				for c in 0..<m.heights.count where Heights.isLand(m.heights[c]) {
					let p = RectangleClip.clip(v.cells.v[c].map { v.vertices.p[$0] }, width: width, height: height)
					if p.count >= 3 { area += abs(RealmSeeds.polygonArea(p)) }
				}
				var fields = ["M", template.key, seed, String(format: "%.0f", area), String(m.heights.filter { Heights.isLand($0) }.count)]
				var landmasses = 0, tiny = 0
				var row: [String] = []
				for reach in reaches {
					let g = try LandGroups.find(in: m, reach: reach)
					if reach == 0 {
						landmasses = g.landmasses.count
						tiny = g.landmasses.filter { $0.cellCount <= tinyCells }.count
						fields += [String(landmasses), String(tiny)]
					}
					let tinyGroups = g.groups.filter { $0.cellCount <= tinyCells }.count
					row.append("\(g.groups.count)/\(tinyGroups)")
				}
				print((fields + row).joined(separator: "|") + "|cells=\(cells)")
			}
		}
	}
}
