import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKit

/// The controls view (docs/plans/map-controls.md, step 4): which groups show, and that drawing it edits nothing. The look and the gestures are the author's to check.
struct MapControlsTests {
	typealias Groups = MapControls.Groups

	/// The height of the controls drawn at a fixed width, 0 when nothing is drawn.
	@MainActor
	func height(_ groups: Groups, pinCount: Int? = nil, settings: MapSettings = MapSettings()) -> Int {
		var image: CGImage?
		for _ in 0..<3 { // see `FantasyMapViewZoomTests.view`: the first renders are not stable
			let renderer = ImageRenderer(content: MapControls(settings: .constant(settings), groups: groups, pinCount: pinCount).frame(width: 300))
			renderer.scale = 1
			image = renderer.cgImage
		}
		return image?.height ?? 0
	}

	@Test func theGroupsAreSixAndAllIsEveryOneOfThem() {
		let groups: [Groups] = [.seedAndShape, .detail, .coast, .rivers, .realms, .pins]
		#expect(Set(groups.map(\.rawValue)).count == 6)
		#expect(Groups.all == Groups(groups))
		#expect(MapControls.order == groups)
		for (i, a) in groups.enumerated() { for (j, b) in groups.enumerated() where i != j { #expect(a.intersection(b).isEmpty) } }
	}

	@MainActor
	@Test func eachGroupAloneDrawsSomethingAndNoGroupsDrawNothing() {
		#expect(height([]) == 0)
		for group in MapControls.order { #expect(height(group) > 0, "\(group.rawValue)") }
	}

	@MainActor
	@Test func hidingAGroupMakesTheControlsShorterAndShowingMoreMakesThemTaller() {
		let all = height(.all)
		for group in MapControls.order {
			#expect(height(Groups.all.subtracting(group)) < all, "without \(group.rawValue)")
			#expect(height(group) < all, "only \(group.rawValue)")
		}
		#expect(height([.coast, .rivers]) > height(.coast))
		// the groups add up: one divider and spacing between each pair
		let parts = MapControls.order.map { height($0) }.reduce(0, +)
		#expect(all > parts)
	}

	@MainActor
	@Test func theRealmsGroupShowsOnlyAShortSetUntilMoreIsOpened() {
		var automatic = MapSettings()
		automatic.realms.count = nil
		var chosen = MapSettings()
		chosen.realms.count = 5
		// a chosen number replaces nothing in the short set but adds the stepper for it
		#expect(height(.realms, settings: chosen) > height(.realms, settings: automatic))
	}

	@MainActor
	@Test func thePinsGroupSaysHowManyPinsThereAre() {
		#expect(height(.pins, pinCount: 3) > height(.pins))
		#expect(height(.pins, pinCount: 1) == height(.pins, pinCount: 3))
	}

	/// Drawing the controls reads the settings and writes nothing.
	@MainActor
	@Test func drawingTheControlsChangesNoSetting() {
		var writes = 0
		var settings = MapSettings()
		settings.realms.count = 4
		let before = settings
		let binding = Binding(get: { settings }, set: { settings = $0; writes += 1 })
		let renderer = ImageRenderer(content: MapControls(settings: binding).frame(width: 300))
		renderer.scale = 1
		_ = renderer.cgImage
		#expect(writes == 0 && settings == before)
	}

	@Test func anotherSeedIsANumberOfUpToNineDigitsAndDiffersEachTime() throws {
		let seeds = (0..<20).map { _ in MapSettings.randomSeed() }
		for seed in seeds {
			#expect(seed.count >= 6 && seed.count <= 9 && Int(seed) != nil, "\(seed)")
			var s = MapSettings()
			s.seed = seed
			try s.validate()
		}
		#expect(Set(seeds).count > 15)
	}

	@Test func theAutomaticCountSwitchAsksForANumberOrGivesItUp() {
		var realms = MapSettings.Realms()
		#expect(realms.automaticCount && realms.count == nil)
		realms.automaticCount = false
		#expect(!realms.automaticCount && realms.count == 8)
		realms.count = 5
		realms.automaticCount = false
		#expect(realms.count == 5, "turning it off again keeps the number asked for")
		realms.automaticCount = true
		#expect(realms.count == nil && realms.automaticCount)
		realms.automaticCount = false
		#expect(realms.count == 8, "a number given up is not remembered")
	}
}
