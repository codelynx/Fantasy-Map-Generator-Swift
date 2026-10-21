// The resource policy and named refusals of the river generator (see docs/plans/water-7-rivers.md). The original has no limits; these are
// this package's, explicit and adjustable one by one.

import Foundation

/// The parts of the river generator that charge the work budget.
public enum RiverPart: String, Sendable {
	case detectCloseLakes, resolveDepressions, drainWater
}

/// Why the river generator refused to run.
public enum RiverError: Error, Equatable, Sendable {
	/// A setting is not finite or is out of its range (a safety check; the original takes the values as given).
	case invalidSettings
	/// The inputs are inconsistent: arrays that do not fit one another, an index or a feature number outside its table, heights that are not
	/// finite, a cell without neighbours.
	case invalidInputs
	/// A lake without a shore cell where the original would compute with nothing (its result would be a not-a-number height).
	case lakeWithoutShore
	/// The counted work (attempts, charged before anything is filtered or skipped) passed the budget in the named part.
	case workBudgetExceeded(RiverPart)
	/// The meandering geometry of a river (its points, or the bytes its temporary arrays need at their peak) would pass the policy's limits, or
	/// a river's entry list is too long for the geometry to be sized: refused before anything is allocated.
	case riverGeometryBudgetExceeded
	/// A river's geometry would not be finite (the differences, midpoints or reflections of finite positions overflowed).
	case nonFiniteGeometry
	/// A lake's climate is not a finite number (for example a temperature of exactly 80 degrees makes the evaporation's denominator 0, or a lake of
	/// six or more cells has no shore): refused immediately after the lake climate is defined, before the drainage consumes it.
	case nonFiniteLakeClimate(lake: Int, field: LakeClimateField)
	/// More rivers than the 16-bit river numbers can hold (65,535): refused before a number that would wrap is assigned.
	case tooManyRivers
	/// The river lists would pass the policy's entry limit: refused before the entry is appended.
	case riverEntriesBudgetExceeded
}

/// Which of a lake's climate values was not finite.
public enum LakeClimateField: String, Sendable {
	case flux, temperature, evaporation
}

/// Every limit of the river generator, each adjustable on its own. **All defaults are provisional development values for measurement, not
/// recommended production limits.**
public struct RiverResourcePolicy: Equatable, Sendable {
	/// The work budget as charges per packed cell (the budget is this times the number of cells, overflow-checked).
	public var workPerCell = 10_000
	/// The number of depression-resolving iterations (the original's `resolveDepressionsSteps`, 250). A whole number from 1 to 1,000; zero
	/// iterations is unsupported by this package.
	public var resolveDepressionsSteps = 250
	/// The most meander points all rivers may hold together (provisional, to be measured; not a proven bound).
	public var maximumRiverPoints = 4_000_000
	/// The most bytes the rivers' geometry may need at its peak: what the finished rivers hold plus the temporary arrays of the river being
	/// made (an estimate from the formula in `RiverGeometryTotals`, not a measurement; 256 MiB, provisional).
	public var maximumGeometryBytes = 268_435_456
	/// The most entries all river lists may hold together, as a multiple of the packed cells (provisional, a refusal policy and not a proven bound).
	public var maximumRiverEntriesPerCell = 4

	public init() {}

	func validate() throws {
		guard workPerCell >= 1, resolveDepressionsSteps >= 1, resolveDepressionsSteps <= 1000, maximumRiverPoints >= 0, maximumGeometryBytes >= 0, maximumRiverEntriesPerCell >= 0 else { throw RiverError.invalidSettings }
	}
}

/// A counter of attempts. A charge that would pass the limit, or whose sum would overflow, is refused.
public struct RiverWork: Equatable, Sendable {
	public private(set) var charged = 0
	/// What was charged, by part (so the totals can be reported beside the overall figure).
	public private(set) var chargedByPart: [RiverPart: Int] = [:]
	public let limit: Int

	/// The budget for a graph of `cells` packed cells under the policy: the policy's work per cell times the cells. **Construction is refused**
	/// (`invalidSettings`) for an invalid policy, a negative cell count, or a product that does not fit an `Int` (a budget that cannot be
	/// represented is a misconfiguration, not an unlimited budget: nothing saturates). Zero cells have a zero budget.
	public init(cells: Int, policy: RiverResourcePolicy) throws {
		try policy.validate()
		guard cells >= 0 else { throw RiverError.invalidSettings }
		let (product, overflow) = policy.workPerCell.multipliedReportingOverflow(by: cells)
		guard !overflow else { throw RiverError.invalidSettings }
		limit = product
	}

	/// A counter with an explicit limit (for the stand-alone helpers, which are not under a policy).
	init(limit: Int) { self.limit = limit }

	mutating func charge(_ amount: Int, _ part: RiverPart) throws {
		guard amount >= 0 else { throw RiverError.invalidInputs }
		let (sum, overflow) = charged.addingReportingOverflow(amount)
		guard !overflow, sum <= limit else { throw RiverError.workBudgetExceeded(part) }
		charged = sum
		chargedByPart[part, default: 0] += amount
	}
}

/// What the rivers' geometry holds so far, for the limits checked **before** a river's points are allocated.
public struct RiverGeometryTotals: Equatable, Sendable {
	/// The points of the finished rivers, and the bytes they hold (each is a river point: x, y and a flux, a stride of 24 bytes).
	public private(set) var points = 0
	public private(set) var retainedBytes = 0
	/// The largest number of bytes the geometry has needed at its peak so far (a river's temporary arrays on top of what was retained).
	public private(set) var peakBytes = 0

	public init() {}

	/// The estimated **peak** bytes of one river's temporary buffers for `entries` list entries, from the element sizes of the implementation
	/// (`MemoryLayout` strides: a point 16, an index 8, a flag 1, a river point with its flux 24) and the most points a river can have (3 per
	/// entry). The buffers that coexist in each phase of `addMeandering`, and the peak is the largest:
	/// - **meander**: the anchor points (a point per entry), the points (3 per entry), the anchor indices (an index per entry), the water flags
	///   (a flag per entry);
	/// - **relaxation**: all of those still held, and for the points an anchor flag (1), a previous and a next anchor index (8 and 8) and a
	///   snapshot (16) each;
	/// - **output**: the points, the anchor indices, the flux list (8 per point), the river points (24 per point) and the water flags.
	/// **An estimate, not a measurement:** it leaves out the allocator's overhead and growth, and any copy the compiler makes. Overflow gives nil.
	static func temporaryBytes(entries: Int) -> Int? {
		let point = MemoryLayout<Point>.stride, index = MemoryLayout<Int>.stride, flag = MemoryLayout<Bool>.stride
		let riverPoint = MemoryLayout<RiverGeometry.RiverPoint>.stride, flux = MemoryLayout<Double>.stride
		let (points, o) = entries.multipliedReportingOverflow(by: 3)
		if o { return nil }
		func total(_ parts: [(count: Int, size: Int)]) -> Int? {
			var sum = 0
			for part in parts {
				let (bytes, o1) = part.count.multipliedReportingOverflow(by: part.size)
				let (next, o2) = sum.addingReportingOverflow(bytes)
				if o1 || o2 { return nil }
				sum = next
			}
			return sum
		}
		let held: [(count: Int, size: Int)] = [(entries, point), (entries, index), (entries, flag), (points, point)] // anchors, indices, flags, points
		guard let meander = total(held),
			let relaxation = total(held + [(points, flag), (points, index), (points, index), (points, point)]),
			let output = total([(points, point), (entries, index), (entries, flag), (points, flux), (points, riverPoint)]) else { return nil }
		return max(meander, relaxation, output)
	}

	/// Checks a river of `entries` list entries against the limits, before its geometry is allocated: its points (at most 3 per entry) with the
	/// finished rivers', and its temporary arrays at their peak with what is retained. Overflow-checked.
	mutating func preflight(entries: Int, policy: RiverResourcePolicy) throws {
		let (maxPoints, o1) = entries.multipliedReportingOverflow(by: 3)
		let (pointTotal, o2) = points.addingReportingOverflow(maxPoints)
		guard !o1, !o2, pointTotal <= policy.maximumRiverPoints, let temporary = Self.temporaryBytes(entries: entries) else { throw RiverError.riverGeometryBudgetExceeded }
		let (peak, o3) = retainedBytes.addingReportingOverflow(temporary)
		guard !o3, peak <= policy.maximumGeometryBytes else { throw RiverError.riverGeometryBudgetExceeded }
		peakBytes = max(peakBytes, peak)
	}

	/// Records a finished river's actual points.
	mutating func add(points count: Int) {
		points += count
		retainedBytes += count * MemoryLayout<RiverGeometry.RiverPoint>.stride
	}
}
