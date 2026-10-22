// Ported from Azgaar's Fantasy Map Generator, `src/generators/lakes.ts` (`detectCloseLakes`, `defineClimateData`, `cleanupLakeData`; the
// original at commit 8936c9c, 2026-10-19). The original is MIT licensed, © 2017–2024 Max Haniyeu (Azgaar), with the added paragraph kept
// in ACKNOWLEDGEMENTS.md. (`defineShoreline` and `getHeight`, which `markupPack` needs, are in PackedFeatures.swift.)
//
// The lake helpers the river generator uses: which lakes sit in a deep depression and cannot overflow, the climate of every lake and its
// outlet, and the removal of the temporary fields once the rivers exist. **The original runs them inside `Rivers.generate`, in its order,
// and the port keeps that order: these are ported and tested on their own and are not a stage to run before the rivers.**

import Foundation

extension PackedFeatures {
	public enum LakeProblem: Error, Equatable, Sendable {
		/// A lake without a shore cell where the original reduces over the shore (it throws). **Only there:** a closed lake without a shore passes
		/// `defineClimateData`, as in the original.
		case lakeWithoutShore
		/// The heights, the grid arrays or the neighbour lists do not fit the packed map.
		case invalidInputs
		/// The elevation limit or the height exponent is not finite or is out of range (a safety check; the original takes the values as given).
		case invalidSettings
	}

	/// The lowest shore cell of a lake in the given heights: the first of equals, as the original's `reduce` with a strict comparison.
	/// (The shoreline's cells are checked to be in range before this is called.)
	private static func lowestShoreCell(_ shoreline: [Int], _ heights: [Double]) throws -> Int {
		guard var lowest = shoreline.first else { throw LakeProblem.lakeWithoutShore }
		for cell in shoreline.dropFirst() where heights[cell] < heights[lowest] { lowest = cell }
		return lowest
	}

	/// The checks the helpers make before they change anything: the heights are finite and as many as the cells, and every lake's shore cells
	/// (and, where it is used, its first cell) are cells. A refused call leaves the features as they were.
	private func validate(heights: [Double], firstCellUsed: Bool) throws {
		let n = featureIds.count
		guard heights.count == n, heights.allSatisfy(\.isFinite) else { throw LakeProblem.invalidInputs }
		for lake in features where lake.kind == .lake {
			guard lake.shoreline.allSatisfy({ $0 >= 0 && $0 < n }) else { throw LakeProblem.invalidInputs }
			if firstCellUsed && lake.cells < 6 && !(lake.firstCell >= 0 && lake.firstCell < n) { throw LakeProblem.invalidInputs }
		}
	}

	/// `Lakes.detectCloseLakes(h)`: for every lake, sets `closed`: true if the water cannot get out (a flood from its lowest shore cell,
	/// through cells under the lake's height plus the elevation limit, meets neither an ocean nor a lake lower than itself), false if it can.
	/// A lake whose height plus the limit passes 99 is open without a search. **The heights are the caller's and exact:** `[Double]`, because the
	/// river generator's working copy is fractional (it adds gradients and raises cells by fractions such as 0.1), and truncating it to bytes would
	/// change the flood threshold and the lowest shore cell (the packed map's own byte heights go through the `byteHeights:` form). The neighbour
	/// lists are the packed diagram's. The elevation limit is finite, 0 to 100 (package policy; the original's option is 20 by default). **Every
	/// index the search uses (cells, shore cells, neighbours and the feature numbers of water cells) is checked before anything is changed, and a
	/// refused call changes nothing.**
	public mutating func detectCloseLakes(heights h: [Double], neighbours: [[Int]], elevationLimit: Double) throws {
		var unlimited = RiverWork(limit: Int.max)
		try detectCloseLakes(heights: h, neighbours: neighbours, elevationLimit: elevationLimit, work: &unlimited)
	}

	/// The same, charging the work counter for every attempt before it is filtered: 1 for each lake started, 1 for each shore cell examined for the
	/// lowest, and 1 for each neighbour examined in the flood (before the visited and height tests).
	public mutating func detectCloseLakes(heights h: [Double], neighbours: [[Int]], elevationLimit: Double, work: inout RiverWork) throws {
		guard elevationLimit.isFinite, elevationLimit >= 0, elevationLimit <= 100 else { throw LakeProblem.invalidSettings }
		try validate(heights: h, firstCellUsed: false)
		guard neighbours.count == h.count, neighbours.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0 < h.count } }) else { throw LakeProblem.invalidInputs }
		// the feature numbers of the water cells the flood can look at must be in the table (0 is the original's placeholder entry, which has no
		// kind and no height, so it changes nothing; a number past the table would make the original fail on a missing feature)
		guard zip(h, featureIds).allSatisfy({ $0 >= Double(Heights.seaLevel) || Int($1) <= self.features.count }) else { throw LakeProblem.invalidInputs }
		var features = self.features // worked on as a copy: a refused call changes nothing
		var w = work
		for index in features.indices where features[index].kind == .lake {
			try w.charge(1, .detectCloseLakes)
			features[index].closed = nil
			let height = features[index].height
			let maxElevation = height + elevationLimit
			if maxElevation > 99 {
				features[index].closed = false
				continue
			}

			var isDeep = true
			try w.charge(features[index].shoreline.count, .detectCloseLakes)
			let lowestShorelineCell = try Self.lowestShoreCell(features[index].shoreline, h)
			var queue = [lowestShorelineCell]
			var checked: Set<Int> = [lowestShorelineCell]

			while !queue.isEmpty && isDeep {
				let cellId = queue.removeLast()
				try w.charge(neighbours[cellId].count, .detectCloseLakes)
				for neibCellId in neighbours[cellId] {
					if checked.contains(neibCellId) { continue }
					if h[neibCellId] >= maxElevation { continue }

					if h[neibCellId] < Double(Heights.seaLevel), let neighbourFeature = feature(Int(featureIds[neibCellId])) {
						if neighbourFeature.kind == .ocean || height > neighbourFeature.height { isDeep = false }
					}

					checked.insert(neibCellId)
					queue.append(neibCellId)
				}
			}
			features[index].closed = isDeep
		}
		self.features = features
		work = w
	}

	/// The same with byte heights (the packed map's own), converted exactly.
	public mutating func detectCloseLakes(byteHeights: [Height], neighbours: [[Int]], elevationLimit: Double) throws {
		try detectCloseLakes(heights: byteHeights.map(Double.init), neighbours: neighbours, elevationLimit: elevationLimit)
	}

	/// `Lakes.defineClimateData(heights)`: for every lake sets `flux` (the sum of the grid precipitation under its shore cells), `temp` (the
	/// grid temperature under its first cell if it has fewer than 6 cells, else the mean under its shore cells, to one decimal),
	/// `evaporation` (the original's Penman-based formula, times the cells) and, unless the lake is `closed`, `outCell`, its lowest shore cell
	/// in the **given** heights. Returns the packed cells' list of lake outlets (the lake's number at its outlet cell, else 0). The packed
	/// cells' grid cells give the grid's precipitation and temperature. The height exponent is finite, 0.1 to 5 (as the temperature's).
	public mutating func defineClimateData(heights: [Double], gridCell: [Int], precipitation: [UInt8], temperature: [Int8], heightExponent: Double) throws -> [UInt16] {
		let n = featureIds.count
		guard heightExponent.isFinite, heightExponent >= 0.1, heightExponent <= 5 else { throw LakeProblem.invalidSettings }
		try validate(heights: heights, firstCellUsed: true)
		guard gridCell.count == n, precipitation.count == temperature.count, gridCell.allSatisfy({ $0 >= 0 && $0 < precipitation.count }) else { throw LakeProblem.invalidInputs }
		var features = self.features // worked on as a copy: a refused call changes nothing
		var lakeOutCells = [UInt16](repeating: 0, count: n)

		for index in features.indices where features[index].kind == .lake {
			let lake = features[index]
			features[index].flux = Double(lake.shoreline.reduce(0) { $0 + Int(precipitation[gridCell[$1]]) })
			let temp: Double
			if lake.cells < 6 { temp = Double(temperature[gridCell[lake.firstCell]]) }
			else if lake.shoreline.isEmpty { temp = .nan } // d3's mean of nothing is undefined, and rn(undefined) is not a number
			else { temp = JSNumber.rn(Double(lake.shoreline.reduce(0) { $0 + Int(temperature[gridCell[$1]]) }) / Double(lake.shoreline.count), 1) }
			features[index].temp = temp
			let heightInMetres = pow(lake.height - 18, heightExponent)
			let evaporation = ((700 * (temp + 0.006 * heightInMetres)) / 50 + 75) / (80 - temp) // based on Penman formula, [1-11]
			features[index].evaporation = JSNumber.rn(evaporation * Double(lake.cells))
			if lake.closed == true { continue } // no outlet for lakes in depressed areas

			let outCell = try Self.lowestShoreCell(lake.shoreline, heights)
			features[index].outCell = outCell
			lakeOutCells[outCell] = UInt16(truncatingIfNeeded: lake.id)
		}
		self.features = features
		return lakeOutCells
	}

	/// The same with byte heights (the packed map's own), converted exactly.
	public mutating func defineClimateData(byteHeights: [Height], gridCell: [Int], precipitation: [UInt8], temperature: [Int8], heightExponent: Double) throws -> [UInt16] {
		try defineClimateData(heights: byteHeights.map(Double.init), gridCell: gridCell, precipitation: precipitation, temperature: temperature, heightExponent: heightExponent)
	}

	/// `Lakes.cleanupLakeData()`: removes the temporary river, entering flux, outlet cell and closed fields, rounds each lake's height to three
	/// decimals, keeps only the inlets that are rivers of the given list (and drops the list if none is), and keeps the outlet only if it is
	/// one of them. **An outlet number of 0 is dropped even if a river 0 exists** (the original tests the number as a truth value).
	public mutating func cleanupLakeData(riverIds: Set<Int>) {
		for index in features.indices where features[index].kind == .lake {
			features[index].river = nil
			features[index].enteringFlux = nil
			features[index].outCell = nil
			features[index].closed = nil
			features[index].height = JSNumber.rn(features[index].height, 3)

			let inlets = features[index].inlets?.filter { riverIds.contains($0) }
			features[index].inlets = (inlets?.isEmpty ?? true) ? nil : inlets
			if let outlet = features[index].outlet, outlet != 0, riverIds.contains(outlet) {} else { features[index].outlet = nil }
		}
	}
}
