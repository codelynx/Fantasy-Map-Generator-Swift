// Ported from Azgaar's Fantasy Map Generator, `src/generators/river-generator.ts` (`generate` with its inner `drainWater`, `flowDown`,
// `defineRivers`, `calculateConfluenceFlux` and `downcutRivers`; the original at commit 8936c9c, 2026-10-19). The original is MIT licensed,
// © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept in ACKNOWLEDGEMENTS.md.
//
// The rivers of a packed graph: the working heights (stage 7a), the lake helpers (stage 6) and the river geometry (stage 7b) put in the original's
// order, with the water drained downhill cell by cell from the highest cell to the lowest, the rivers defined from the cells the water flowed
// through, and the river beds cut into the heights. **The original runs its steps inside one function and so does this: nothing here is published
// unless the whole operation succeeds.**

import Foundation

/// The settings of the river generator: the original's options with its defaults.
public struct RiverSettings: Equatable, Sendable {
	/// Whether the working heights are applied to the packed heights and the river beds cut into them (the original's `allowErosion`).
	public var allowErosion = true
	/// The lake elevation limit (the original's `options.generation.lakeElevationLimit`, 20). Finite, 0 to 100 (package policy); fractions are kept.
	public var lakeElevationLimit = 20.0
	/// The height exponent of the lake evaporation (`options.map.units.height.exponent`, 2). Finite, 0.1 to 5 (package policy). **One value for the
	/// temperature and the lake climate:** the caller passes the same to both.
	public var heightExponent = 2.0

	public init() {}

	func validate() throws {
		guard lakeElevationLimit.isFinite, lakeElevationLimit >= 0, lakeElevationLimit <= 100, heightExponent.isFinite, heightExponent >= 0.1, heightExponent <= 5 else { throw RiverError.invalidSettings }
	}
}

/// A river, as the original's `pack.rivers` record after `defineRivers` (the naming, type, basin and drawing fields belong to later stages).
public struct River: Equatable, Codable, Sendable {
	public var id: Int
	/// The first cell of the river, and the cell its water leaves by (the second to last entry: the last is the cell after it).
	public var source: Int, mouth: Int
	/// The flux at the mouth (cubic metres a second in the original's words).
	public var discharge: Double
	/// The length of the meandering path, to two decimals, and the mouth width.
	public var length: Double, width: Double
	public var widthFactor: Double, sourceWidth: Double
	/// The river this one flows into, or 0.
	public var parent: Int
	/// The cells of the river from its source on; **-1 is the map border** (water poured out of the screen).
	public var cells: [Int]
}

/// What the generator measured about itself (so that timings can be read beside the counts).
public struct RiverReport: Equatable, Sendable {
	public var work: RiverWork
	/// The entries of all river lists, before the short rivers were dropped.
	public var riverEntries: Int
	/// How many river numbers were handed out (the short rivers that are dropped took numbers too).
	public var riverNumbersAssigned: Int
	public var geometry: RiverGeometryTotals
}

/// The result of `Rivers.generate`.
public struct RiverSystem: Equatable, Sendable {
	/// The flux of every packed cell (the original's `cells.fl`, a `Uint16Array`: every addition truncates and wraps).
	public var flux: [UInt16]
	/// The river of every cell (`cells.r`), and the confluence flux of the cells where rivers met (`cells.conf`).
	public var riverIds: [UInt16]
	public var confluence: [UInt16]
	/// The packed heights after the rivers (the working heights truncated to bytes with the beds cut, or the unchanged heights without erosion).
	public var heights: [Height]
	public var rivers: [River]
	/// The features with the lakes' fields as the original leaves them: the climate (`flux`, `temp`, `evaporation`), the heights rounded to three
	/// decimals, and the inlets and outlet that are rivers of the list.
	public var features: PackedFeatures
	public var report: RiverReport
}

public enum Rivers {
	/// The river flux below which a cell's water does not form a river.
	static let minFluxToFormRiver = 30.0

	/// `array[i] += x` on a `Uint16Array`: the sum is stored truncated toward zero and wrapped modulo 65,536.
	static func addToUInt16(_ current: UInt16, _ amount: Double) -> UInt16 { JSNumber.toUInt16(Double(current) + amount) }

	/// `array[i] += x` on a `Uint8Array`: the sum is stored truncated toward zero and wrapped modulo 256.
	static func addToUInt8(_ current: UInt8, _ amount: Double) -> UInt8 { JSNumber.toUInt8(Double(current) + amount) }

	/// `Rivers.generate(allowErosion)`. The inputs are the packed map and its features (`PackedFeatures.markup`), the grid's precipitation and
	/// temperature (stages 2 and 3), `cellsDesired` (the original's `options.map.graph.points`, which scales the rain and the river widths) and the
	/// map's size. **Nothing is changed in the inputs, and a refused or failed call publishes nothing.**
	///
	/// One structural validation is made first, so that the passes after it can rely on it: the arrays fit one another, every cell has at most 20
	/// neighbours, every cell's feature number is in the table, water cells belong to water features and the havens are water cells, every lake has
	/// a shore of land cells and a first cell of its own, and the grid cells the packed cells came from are in the grid arrays.
	public static func generate(packed: PackedMap, features: PackedFeatures, precipitation: [UInt8], temperature: [Int8], cellsDesired: Int, width: Double, height: Double, settings: RiverSettings = RiverSettings(), policy: RiverResourcePolicy = RiverResourcePolicy()) throws -> RiverSystem {
		try generate(packed: packed, features: features, precipitation: precipitation, temperature: temperature, cellsDesired: cellsDesired, width: width, height: height, settings: settings, policy: policy, riverIdLimit: Int(UInt16.max))
	}

	/// The same with a lower limit on the river numbers (the tests use it: 65,535 rivers are not made by a test map).
	static func generate(packed: PackedMap, features: PackedFeatures, precipitation: [UInt8], temperature: [Int8], cellsDesired: Int, width: Double, height: Double, settings: RiverSettings, policy: RiverResourcePolicy, riverIdLimit: Int, entryLimit entryLimitOverride: Int? = nil) throws -> RiverSystem {
		try policy.validate()
		try settings.validate()
		let n = packed.points.count
		let cells = packed.voronoi.cells
		let neighbours = cells.c, border = cells.b
		guard n > 0, cellsDesired > 0, width.isFinite, width > 0, height.isFinite, height > 0, neighbours.count == n, border.count == n, packed.heights.count == n, packed.gridCell.count == n,
			features.featureIds.count == n, features.distanceField.count == n, features.haven.count == n, precipitation.count == temperature.count else { throw RiverError.invalidInputs }
		try validateStructure(packed: packed, features: features, gridCount: precipitation.count)

		var work = try RiverWork(cells: n, policy: policy)
		var f = features
		let heights = packed.heights

		// alterHeights, detectCloseLakes, resolveDepressions
		var h = try RiverHeights.alterHeights(packedHeights: heights, distance: f.distanceField, neighbours: neighbours)
		try f.detectCloseLakes(heights: h, neighbours: neighbours, elevationLimit: settings.lakeElevationLimit, work: &work)
		try RiverHeights.resolveDepressions(heights: &h, features: &f, packedHeights: heights, neighbours: neighbours, border: border, steps: policy.resolveDepressionsSteps, work: &work)

		// drainWater
		let cellsNumberModifier = pow(Double(cellsDesired) / 10000, 0.25)
		var fl = [UInt16](repeating: 0, count: n) // water flux array
		var r = [UInt16](repeating: 0, count: n) // rivers array
		var conf8 = [UInt8](repeating: 0, count: n) // confluences array: a byte while the water drains, as the original's `Uint8Array`
		var riverNext = 1 // first river id is 1
		var riversData: [Int: [Int]] = [:]
		var riverParents: [Int: Int] = [:]
		var entries = 0
		let (entryCap, capOverflow) = n.multipliedReportingOverflow(by: policy.maximumRiverEntriesPerCell)
		guard entryLimitOverride != nil || !capOverflow else { throw RiverError.invalidSettings } // an unrepresentable limit is refused, not replaced
		let entryLimit = entryLimitOverride ?? entryCap

		func addCellToRiver(_ cellId: Int, _ riverId: Int) throws {
			guard entries < entryLimit else { throw RiverError.riverEntriesBudgetExceeded }
			entries += 1
			riversData[riverId, default: []].append(cellId)
		}
		func newRiverId() throws -> Int {
			guard riverNext <= min(riverIdLimit, Int(UInt16.max)) else { throw RiverError.tooManyRivers }
			defer { riverNext += 1 }
			return riverNext
		}
		/// `fl[i] += x`: the sum is stored truncated toward zero and wrapped, as a `Uint16Array` stores it.
		func addFlux(_ cell: Int, _ amount: Double) { fl[cell] = addToUInt16(fl[cell], amount) }

		func flowDown(_ toCell: Int, _ fromFlux: Int, _ river: Int) throws {
			try work.charge(1, .drainWater)
			let toFlux = Int(fl[toCell]) - Int(conf8[toCell])
			let toRiver = Int(r[toCell])

			if toRiver != 0 {
				// downhill cell already has river assigned
				if fromFlux > toFlux {
					conf8[toCell] = addToUInt8(conf8[toCell], Double(fl[toCell])) // mark confluence
					if h[toCell] >= 20 { riverParents[toRiver] = river } // min river is a tributary of current river
					r[toCell] = UInt16(river) // re-assign river if downhill part has less flux
				} else {
					conf8[toCell] = addToUInt8(conf8[toCell], Double(fromFlux)) // mark confluence
					if h[toCell] >= 20 { riverParents[river] = toRiver } // current river is a tributary of min river
				}
			} else {
				r[toCell] = UInt16(river) // assign the river to the downhill cell
			}

			if h[toCell] < 20 {
				// pour water to the water body
				let waterBody = Int(f.featureIds[toCell]) - 1
				if f.features[waterBody].kind == .lake {
					if (f.features[waterBody].river ?? 0) == 0 || Double(fromFlux) > (f.features[waterBody].enteringFlux ?? 0) {
						f.features[waterBody].river = river
						f.features[waterBody].enteringFlux = Double(fromFlux)
					}
					f.features[waterBody].flux += Double(fromFlux)
					if f.features[waterBody].inlets == nil { f.features[waterBody].inlets = [] }
					f.features[waterBody].inlets?.append(river)
				}
			} else {
				addFlux(toCell, Double(fromFlux)) // propagate flux and add next river segment
			}

			try addCellToRiver(toCell, river)
		}

		let bits = Int.bitWidth - n.leadingZeroBitCount
		let lakeOutCells = try f.defineClimateData(heights: h, gridCell: packed.gridCell, precipitation: precipitation, temperature: temperature, heightExponent: settings.heightExponent)
		// **refused here, before the drainage consumes it:** every lake's flux, temperature and evaporation (closed lakes included) must be finite
		for lake in f.features where lake.kind == .lake {
			if !lake.flux.isFinite { throw RiverError.nonFiniteLakeClimate(lake: lake.id, field: .flux) }
			if !lake.temp.isFinite { throw RiverError.nonFiniteLakeClimate(lake: lake.id, field: .temperature) }
			if !lake.evaporation.isFinite { throw RiverError.nonFiniteLakeClimate(lake: lake.id, field: .evaporation) }
		}

		try work.charge(n, .drainWater)
		let (sortCharge, sortOverflow) = n.multipliedReportingOverflow(by: bits)
		guard !sortOverflow else { throw RiverError.workBudgetExceeded(.drainWater) }
		try work.charge(sortCharge, .drainWater)
		// the land cells, highest first; equal heights keep the cell order (the original's stable sort)
		let land = (0..<n).filter { h[$0] >= 20 }.sorted { (-h[$0], $0) < (-h[$1], $1) }

		for i in land {
			try work.charge(1, .drainWater)
			addFlux(i, Double(precipitation[packed.gridCell[i]]) / cellsNumberModifier) // add flux from precipitation

			// create lake outlet if lake is not in deep depression and flux > evaporation
			var lakes: [Int] = [] // indices into the feature list
			if lakeOutCells[i] != 0 {
				try work.charge(f.features.count, .drainWater)
				lakes = f.features.indices.filter { i == f.features[$0].outCell && f.features[$0].flux > f.features[$0].evaporation }
			}
			for lakeIndex in lakes {
				try work.charge(neighbours[i].count + 1, .drainWater)
				let lakeId = f.features[lakeIndex].id
				// the water cell of the lake next to the outlet: the original asserts it exists
				guard let lakeCell = neighbours[i].first(where: { h[$0] < 20 && Int(f.featureIds[$0]) == lakeId }) else { throw RiverError.invalidInputs }
				addFlux(lakeCell, max(f.features[lakeIndex].flux - f.features[lakeIndex].evaporation, 0)) // not evaporated lake water drains to outlet

				// allow chain lakes to retain identity
				if Int(r[lakeCell]) != (f.features[lakeIndex].river ?? -1) {
					try work.charge(neighbours[lakeCell].count, .drainWater)
					let sameRiver = f.features[lakeIndex].river.map { river in neighbours[lakeCell].contains { Int(r[$0]) == river } } ?? false
					if sameRiver {
						let river = f.features[lakeIndex].river!
						r[lakeCell] = UInt16(river)
						try addCellToRiver(lakeCell, river)
					} else {
						let id = try newRiverId()
						r[lakeCell] = UInt16(id)
						try addCellToRiver(lakeCell, id)
					}
				}

				f.features[lakeIndex].outlet = Int(r[lakeCell])
				try flowDown(i, Int(fl[lakeCell]), f.features[lakeIndex].outlet!)
			}

			// assign all tributary rivers to outlet basin
			let outlet = lakes.first.flatMap { f.features[$0].outlet }
			for lakeIndex in lakes {
				guard let inlets = f.features[lakeIndex].inlets else { continue }
				try work.charge(inlets.count, .drainWater)
				for inlet in inlets { riverParents[inlet] = outlet ?? 0 }
			}

			// near-border cell: pour water out of the screen
			if border[i] != 0 && r[i] != 0 {
				try addCellToRiver(-1, Int(r[i]))
				continue
			}

			// downhill cell (make sure it's not in the source lake)
			var minCell: Int?
			if lakeOutCells[i] != 0 {
				try work.charge(neighbours[i].count * (lakes.count + 1), .drainWater)
				let lakeIds = Set(lakes.map { f.features[$0].id })
				let filtered = neighbours[i].filter { !lakeIds.contains(Int(f.featureIds[$0])) }
				// the first of the equally low cells, as the original's stable sort leaves first
				if var lowest = filtered.first {
					for c in filtered.dropFirst() where h[c] < h[lowest] { lowest = c }
					minCell = lowest
				}
			} else if f.haven[i] != 0 {
				minCell = f.haven[i]
			} else {
				try work.charge(neighbours[i].count, .drainWater)
				var lowest = neighbours[i][0]
				for c in neighbours[i].dropFirst() where h[c] < h[lowest] { lowest = c }
				minCell = lowest
			}

			// cells is depressed
			if let minCell, h[i] <= h[minCell] { continue }

			if Double(fl[i]) < minFluxToFormRiver {
				// flux is too small to operate as a river
				if let minCell, h[minCell] >= 20 { addFlux(minCell, Double(fl[i])) }
				continue
			}
			// a land cell whose neighbours all belong to its own lakes has nowhere to flow: the original would then write outside its arrays
			guard let minCell else { throw RiverError.invalidInputs }

			// proclaim a new river
			if r[i] == 0 {
				let id = try newRiverId()
				r[i] = UInt16(id)
				try addCellToRiver(i, id)
			}

			try flowDown(minCell, Int(fl[i]), Int(r[i]))
		}

		// defineRivers
		var riverIds = [UInt16](repeating: 0, count: n)
		var confluence = [UInt16](repeating: 0, count: n)
		var rivers: [River] = []
		let flDouble = fl.map(Double.init)
		let defaultWidthFactor = JSNumber.rn(1 / pow(Double(cellsDesired) / 10000, 0.25), 2)
		let mainStemWidthFactor = defaultWidthFactor * 1.2
		var geometry = RiverGeometryTotals()

		for key in riversData.keys.sorted() {
			let riverCells = riversData[key]!
			if riverCells.count < 3 { continue } // exclude tiny rivers

			let riverId = key
			for cell in riverCells {
				if cell < 0 || heights[cell] < Heights.seaLevel { continue }

				// mark real confluences and assign river to cells
				if riverIds[cell] != 0 { confluence[cell] = 1 } else { riverIds[cell] = UInt16(riverId) }
			}

			let source = riverCells[0]
			let mouth = riverCells[riverCells.count - 2]
			// the original's `fl[mouth]` of a border exit would be undefined: not produced by the maps it ran on (none in the fixtures), refused
			guard source >= 0, mouth >= 0 else { throw RiverError.invalidInputs }
			let parent = riverParents[key] ?? 0

			let widthFactor = parent == 0 || parent == riverId ? mainStemWidthFactor : defaultWidthFactor
			let meandered = try RiverGeometry.addMeandering(riverCells: riverCells, positions: packed.points, heights: heights, flux: flDouble, width: width, height: height, policy: policy, totals: &geometry)
			let discharge = flDouble[mouth] // m3 in second
			let length = RiverGeometry.approximateLength(meandered.map { Point(x: $0.x, y: $0.y) })
			let sourceWidth = RiverGeometry.sourceWidth(flux: flDouble[source])
			let riverWidth = RiverGeometry.width(offset: RiverGeometry.offset(flux: discharge, pointIndex: meandered.count, widthFactor: widthFactor, startingWidth: sourceWidth))

			rivers.append(River(id: riverId, source: source, mouth: mouth, discharge: discharge, length: length, width: riverWidth, widthFactor: widthFactor, sourceWidth: sourceWidth, parent: parent, cells: riverCells))
		}

		// calculateConfluenceFlux
		for i in 0..<n where confluence[i] != 0 {
			try work.charge(neighbours[i].count, .drainWater)
			let influx = neighbours[i].filter { riverIds[$0] != 0 && h[$0] > h[i] }.map { fl[$0] }.sorted(by: >)
			confluence[i] = JSNumber.toUInt16(Double(influx.enumerated().reduce(0) { $1.offset == 0 ? $0 : $0 + Int($1.element) }))
		}

		f.cleanupLakeData(riverIds: Set(rivers.map(\.id)))

		var finalHeights = heights
		if settings.allowErosion {
			finalHeights = h.map { JSNumber.toUInt8($0) } // apply gradient
			// downcutRivers: the beds of the rivers cut into the heights, cell by cell in order (later cells see the lowered neighbours)
			let maxDowncut = 5.0
			for i in 0..<n {
				if finalHeights[i] < 35 { continue } // don't downcut lowlands
				if fl[i] == 0 { continue }

				let higherCells = neighbours[i].filter { finalHeights[$0] > finalHeights[i] }
				let higherFlux = Double(higherCells.reduce(0) { $0 + Int(fl[$1]) }) / Double(higherCells.count)
				if higherFlux == 0 || higherFlux.isNaN { continue }

				let downcut = (Double(fl[i]) / higherFlux).rounded(.down)
				if downcut != 0 { finalHeights[i] = JSNumber.toUInt8(Double(finalHeights[i]) - min(downcut, maxDowncut)) }
			}
		}

		return RiverSystem(flux: fl, riverIds: riverIds, confluence: confluence, heights: finalHeights, rivers: rivers, features: f, report: RiverReport(work: work, riverEntries: entries, riverNumbersAssigned: riverNext - 1, geometry: geometry))
	}

	/// The structural validation, once (see `generate`).
	static func validateStructure(packed: PackedMap, features: PackedFeatures, gridCount: Int) throws {
		let n = packed.points.count
		let neighbours = packed.voronoi.cells.c
		guard packed.gridCell.allSatisfy({ $0 >= 0 && $0 < gridCount }),
			neighbours.allSatisfy({ !$0.isEmpty && $0.count <= 20 && $0.allSatisfy { $0 >= 0 && $0 < n } }),
			features.featureIds.allSatisfy({ $0 >= 1 && Int($0) <= features.features.count }) else { throw RiverError.invalidInputs }
		for i in 0..<n {
			let isWater = packed.heights[i] < Heights.seaLevel
			let feature = features.features[Int(features.featureIds[i]) - 1]
			guard feature.land == !isWater else { throw RiverError.invalidInputs } // a water cell belongs to a water feature, a land cell to land
			let haven = features.haven[i]
			if haven != 0 { guard haven > 0, haven < n, packed.heights[haven] < Heights.seaLevel, neighbours[i].contains(haven) else { throw RiverError.invalidInputs } } // a haven is a neighbouring water cell; 0 reads as none, as upstream
		}
		for lake in features.features where lake.kind == .lake {
			guard !lake.shoreline.isEmpty, lake.shoreline.allSatisfy({ $0 >= 0 && $0 < n && packed.heights[$0] >= Heights.seaLevel }),
				lake.firstCell >= 0, lake.firstCell < n, Int(features.featureIds[lake.firstCell]) == lake.id else { throw RiverError.lakeWithoutShore }
		}
	}
}
