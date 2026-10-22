// A small window to try the package: pick a seed, a land shape and a few settings and see the map drawn by FantasyMapKit's
// `FantasyMapView`. It uses the two libraries; they do not use it. Run it with
//
//   swift run -c release FantasyMapDemo
//
// (release is much faster than debug for large maps).

import AppKit
import FantasyMapCore
import FantasyMapKit
import SwiftUI

/// What the controls hold: the package's `MapSettings` (edited by `MapControls`) and the demo's own diagnostic switches. Hashable so that `.task(id:)` makes the map again
/// whenever a setting that makes or draws it changes.
struct DemoSettings: Hashable {
	var map = MapSettings()
	/// The raw-cell diagnostic overlay of the realms, with its seeds and crossing links.
	var realmOverlay = false
	var showSeeds = true
	var showLinks = true

	init() { map.seed = "kaz-1" }

	/// What decides the map and its picture: **not the next pin's marker and colour**, which change no map.
	var making: DemoSettings {
		var s = self
		s.map.pin = MapSettings.Pin()
		return s
	}
}

/// One raw cell polygon coloured by its realm: a diagnostic rendering of the cells, **not** the coast-aligned territory drawing.
struct RealmCellShape: Sendable { var points: [Point]; var realm: Int }
struct RealmSegment: Sendable { var from: Point; var to: Point }

struct RealmOverlay: Sendable {
	var cells: [RealmCellShape]
	var seeds: [Point]
	var links: [RealmSegment]
	var width: Double
	var height: Double
}

/// A finished map, its drawing and what happened while making them.
struct DemoResult: Sendable {
	var map: LandMap
	/// The water map, when the rivers are shown.
	var water: WaterMap?
	var drawing: MapDrawing
	/// Tells the view the map is a different one (the viewport then returns to fit); a presentation change keeps it.
	var identity: String
	/// The fingerprint of the map's geography: pins are kept with it, so they are never shown on another map.
	var fingerprint: String
	var summary: String
	var overlay: RealmOverlay?
	/// What happened to the realms: their summary, or why they could not be made.
	var realmMessage: String?
}

enum Maker {
	/// A map or water map read from a file, drawn with the settings' style: **its realms are drawn with the colours saved with them.**
	static func open(_ data: Data, settings s: DemoSettings, name: String, identity: String) throws -> DemoResult {
		var water: WaterMap?
		let map: LandMap
		if let w = try? WaterMap(decoding: data) { water = w; map = w.land } else { map = try LandMap(decoding: data) }
		let drawing = water.map { MapDrawing(water: $0, style: s.map.style) } ?? MapDrawing(map: map, style: s.map.style)
		var summary = "opened \(name): \(map.heights.count) cells"
		if let water { summary += ", \(water.rivers.count) rivers" }
		if let layer = map.realms {
			// the recipe is shown as provenance: how the realms were made, not evidence that today's generators would make them again; it starts nothing
			let r = layer.recipe
			summary += ", \(layer.ownership.realms.count) realms; recipe (provenance only): seed \(r.realmSeed), reach \(Int(r.reach)), \(r.chosenCount.map { "chosen count \($0)" } ?? "automatic count"), resolved count \(r.resolvedCount); "
			summary += layer.colors == nil ? "colours derived (they may change with the colouring rule until saved)" : "colours saved with the map"
		} else { summary += ", no realms" }
		if let problem = drawing.realmProblem { summary += "; realms not drawn: \(problem)" }
		return DemoResult(map: map, water: water, drawing: drawing, identity: identity, fingerprint: map.fingerprint, summary: summary, overlay: nil, realmMessage: nil)
	}

	/// Makes the map the settings describe and its drawing (off the main thread, called from a detached task): the land, its realms with their colours saved, and, when
	/// the rivers are shown, its water. The settings are checked first, and a refusal is shown in words.
	static func make(_ s: DemoSettings) throws -> DemoResult {
		let m = s.map
		try m.validate()
		let t0 = Date()
		let water: WaterMap?
		let map: LandMap
		if m.rivers.shown {
			let made = try WaterMap.generate(settings: m)
			(water, map) = (made, made.land)
		} else {
			guard let template = HeightmapTemplate.named(m.landShape) else { throw MapSettings.Problem.invalid("landShape") }
			map = try LandMap.generate(seed: m.seed, cellsDesired: m.cells, template: template).addingRealms(settings: m.realms, style: m.style)
			water = nil
		}
		let t1 = Date()
		let drawing = water.map { MapDrawing(water: $0, settings: m) } ?? MapDrawing(map: map, style: m.style)
		let t2 = Date()
		let land = map.heights.filter { Heights.isLand($0) }.count
		var summary = "\(map.heights.count) cells, \(land * 100 / max(map.heights.count, 1))% land; made in \(Int(t1.timeIntervalSince(t0) * 1000)) ms (land, realms\(water == nil ? "" : " and water")), drawn in \(Int(t2.timeIntervalSince(t1) * 1000)) ms"
		if let water {
			summary += "; \(water.rivers.count) rivers, \(drawing.rivers.count) drawn"
			if drawing.riversInWater > 0 { summary += ", \(drawing.riversInWater) wholly in drawn water" }
			if drawing.riversSkipped > 0 { summary += ", \(drawing.riversSkipped) skipped" }
		}
		if m.coast.rough {
			switch drawing.coast.roughness {
			case .applied: summary += "; roughness applied"
			case .fellBack(let reason): summary += "; roughness fell back to the smoothed coast (\(reason))"
			case .off: break
			}
		}
		// the realms of the picture, and, when asked, the diagnostic overlay made from the same settings
		var overlay: RealmOverlay?
		var realmMessage: String?
		if s.realmOverlay {
			let made = realms(for: map, m.realms)
			(overlay, realmMessage) = (made.overlay, made.message)
		} else if let layer = map.realms {
			realmMessage = "\(layer.ownership.realms.count) realms, \(layer.recipe.chosenCount == nil ? "automatic" : "chosen") count"
		}
		// the geography decides the identity: the seed, the land shape and the number of cells; colours, line widths, rivers and realms are presentation
		return DemoResult(map: map, water: water, drawing: drawing, identity: "\(m.seed)|\(m.landShape)|\(m.cells)", fingerprint: map.fingerprint, summary: summary, overlay: overlay, realmMessage: realmMessage)
	}

	/// The diagnostic overlay of the realms: the groups for the reach, the seeds for the count, and raw cell polygons coloured by owner, made from the same realm settings the
	/// picture used. A refusal is reported in words, not hidden.
	static func realms(for map: LandMap, _ r: MapSettings.Realms) -> (overlay: RealmOverlay?, message: String) {
		do {
			let realmSeed = r.seed ?? map.seed
			let groups = try LandGroups.find(in: map, reach: r.reach)
			let policy = RealmPolicy(typicalRealmArea: r.typicalArea, maximumRealms: RealmDefaults.maximumRealms)
			let seeds = try RealmSeeds.place(in: map, groups: groups, count: r.count.map { .chosen($0) } ?? .automatic, realmSeed: realmSeed, policy: policy)
			let growth = GrowthPolicy(hillFactor: r.hillFactor, mountainFactor: r.mountainFactor, crossingFactor: r.crossingFactor, unevenness: r.unevenness)
			let ownership = try RealmOwnership.grow(in: map, groups: groups, seeds: seeds, realmSeed: realmSeed, policy: growth)
			let problems = RealmOwnership.problems(in: ownership, groups: groups, seeds: seeds, neighbours: map.voronoi.cells.c)
			let v = map.voronoi
			var cells: [RealmCellShape] = []
			for cell in 0..<map.heights.count where ownership.owner[cell] > 0 {
				let polygon = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: map.width, height: map.height)
				if polygon.count >= 3 { cells.append(RealmCellShape(points: polygon, realm: Int(ownership.owner[cell]))) }
			}
			let sizes = ownership.realms.map(\.cellCount)
			var message = "\(groups.landmasses.count) landmasses, \(groups.minimumRealms) groups at reach \(Int(r.reach)); \(seeds.resolvedCount) realms (\(r.count == nil ? "automatic" : "chosen")); realm sizes \(sizes.min() ?? 0) to \(sizes.max() ?? 0) cells"
			if !problems.isEmpty { message += "; CHECK FAILED: \(problems.first!)" }
			let overlay = RealmOverlay(cells: cells, seeds: seeds.realms.map { map.grid.points[$0.cell] },
				links: groups.links.map { RealmSegment(from: $0.pointA, to: $0.pointB) }, width: map.width, height: map.height)
			return (overlay, message)
		} catch {
			return (nil, "no realms: \(error)")
		}
	}
}

/// The diagnostic overlay: raw cell polygons washed by realm, with optional seeds and crossing links, over the same fitted frame as
/// `FantasyMapView`. Labelled as a diagnostic: it is not the coast-aligned territory drawing.
struct RealmOverlayView: View {
	var overlay: RealmOverlay
	var showSeeds: Bool
	var showLinks: Bool
	/// The map view's viewport: **the overlay uses the same transform**, so it cannot drift from the map when zoomed.
	var viewport: MapViewport
	var cellSpacing: Double

	static func color(_ realm: Int) -> Color {
		let hue = (Double(realm) * 0.61803398875).truncatingRemainder(dividingBy: 1)
		return Color(hue: hue, saturation: 0.65, brightness: 0.95)
	}

	var body: some View {
		let overlay = overlay, showSeeds = showSeeds, showLinks = showLinks, viewport = viewport, cellSpacing = cellSpacing
		Canvas { context, size in
			guard overlay.width > 0, overlay.height > 0, size.width > 0, size.height > 0 else { return }
			let t = MapViewportGeometry(mapWidth: overlay.width, mapHeight: overlay.height, viewWidth: size.width, viewHeight: size.height, cellSpacing: cellSpacing).transform(viewport)
			let scale = t.scale
			context.translateBy(x: t.offsetX, y: t.offsetY)
			context.scaleBy(x: scale, y: scale)
			for cell in overlay.cells {
				guard let first = cell.points.first else { continue }
				var path = Path()
				path.move(to: CGPoint(x: first.x, y: first.y))
				for p in cell.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
				path.closeSubpath()
				context.fill(path, with: .color(Self.color(cell.realm).opacity(0.5)))
			}
			if showLinks {
				for link in overlay.links {
					var path = Path()
					path.move(to: CGPoint(x: link.from.x, y: link.from.y))
					path.addLine(to: CGPoint(x: link.to.x, y: link.to.y))
					context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.5 / scale, dash: [4 / scale, 3 / scale]))
				}
			}
			if showSeeds {
				for seed in overlay.seeds {
					let r = 5 / scale
					let dot = Path(ellipseIn: CGRect(x: seed.x - r, y: seed.y - r, width: 2 * r, height: 2 * r))
					context.fill(dot, with: .color(.white))
					context.stroke(dot, with: .color(.black), lineWidth: 1.5 / scale)
				}
			}
		}
		.allowsHitTesting(false)
	}
}

enum DemoError: Error, CustomStringConvertible {
	case message(String)
	var description: String { if case .message(let m) = self { return m }; return "" }
}

struct ContentView: View {
	@State private var settings = DemoSettings()
	@State private var result: DemoResult?
	/// A map read from a file: shown until a setting changes (then the settings make the map again).
	@State private var opened: DemoResult?
	@State private var failure: String?
	@State private var working = false
	/// The zoom and centre, bound to the map view and shared with the overlay so that both move together.
	@State private var viewport = MapViewport.fit
	/// Each successful open is a new map, whatever its file name or size: it gets a fresh identity (and the viewport returns to fit).
	@State private var openCount = 0
	/// The pins, kept with the fingerprint of the map they were dropped on: a different map shows its own pins, never these.
	@State private var pinsByMap: [String: [MapPin]] = [:]
	@State private var selectedPin: String?
	@State private var helpIsShown = false

	/// What is on show: an opened map, or the map the settings make.
	var shown: DemoResult? { opened ?? result }

	var body: some View {
		HStack(spacing: 0) {
			ScrollView { controls.padding() }
				.frame(width: 280)
			Divider()
			GeometryReader { proxy in
				ZStack {
					if let result = shown {
						FantasyMapView(drawing: result.drawing, viewport: $viewport, mapIdentity: result.identity, pinLayer: pinLayer(for: result))
						if let overlay = result.overlay, settings.realmOverlay { RealmOverlayView(overlay: overlay, showSeeds: settings.showSeeds, showLinks: settings.showLinks, viewport: viewport, cellSpacing: result.drawing.cellSpacing) }
					} else {
						Color.clear
					}
					if working { ProgressView().controlSize(.large) }
				}
				// **the memo for the selected pin opens beside it** (the pin's own place on the screen, which follows the map as it zooms and pans)
				.popover(isPresented: pinNoteIsShown(in: proxy.size), attachmentAnchor: .rect(.rect(selectedPinFrame(in: proxy.size))), arrowEdge: .bottom) { pinNote }
			}
			.frame(minWidth: 640, minHeight: 400)
		}
		.onChange(of: settings.making) { opened = nil }
		.task(id: settings.making) {
			working = true
			let s = settings
			do {
				try await Task.sleep(for: .milliseconds(150)) // wait for typing or dragging to settle; a newer change cancels this
				// the detached work is not cancelled with this task, so check before publishing: an old result must never replace a newer one
				let made = try await Task.detached { try Maker.make(s) }.value
				try Task.checkCancellation()
				result = made
				failure = nil
			} catch is CancellationError {
				return // a newer task owns the state, including `working`
			} catch {
				guard !Task.isCancelled else { return }
				failure = "\(error)"
			}
			guard !Task.isCancelled else { return }
			working = false
		}
	}

	var controls: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Fantasy map").font(.headline)
			// **all the map's controls in one box**: the package's `MapControls` over `MapSettings`
			MapControls(settings: $settings.map, pinCount: shown.map { pinsByMap[$0.fingerprint]?.count ?? 0 })
			Text("Press and hold on the map to drop a pin and write its memo; tap a pin for its memo, drag it to move it, Delete removes it. The pins are saved with the map.")
				.font(.caption2).foregroundStyle(.secondary)
			if let fingerprint = shown?.fingerprint {
				let elsewhere = pinsByMap.filter { $0.key != fingerprint }.values.reduce(0) { $0 + $1.count }
				if elsewhere > 0 { Text("\(elsewhere) pins belong to other maps (not shown)").font(.caption) }
			}
			Divider()
			// the demo's own: a diagnostic view of the realms, and files
			Toggle("Raw-cell realm overlay (diagnostic)", isOn: $settings.realmOverlay)
			Text("Raw cell polygons for looking at territories; not the coast-aligned drawing.").font(.caption2).foregroundStyle(.secondary)
			if settings.realmOverlay {
				Toggle("Show seeds", isOn: $settings.showSeeds)
				Toggle("Show crossing links", isOn: $settings.showLinks)
			}
			Divider()
			HStack {
				Button("Save picture…") { savePicture() }
				Button("Save map…") { saveMap() }
			}.disabled(shown == nil)
			Button("Open map…") { openMap() }
			HStack {
				Button("Fit") { viewport = .fit }.keyboardShortcut("0", modifiers: .command)
				Text(String(format: "zoom %.1f×", viewport.zoom)).font(.caption).foregroundStyle(.secondary)
				Spacer()
				Button { helpIsShown.toggle() } label: { Image(systemName: "info.circle") }
					.buttonStyle(.borderless)
					.help("How zoom, save and open work")
					.popover(isPresented: $helpIsShown) { help }
			}
			if let failure { Text(failure).foregroundStyle(.red).font(.caption) }
			if let result = shown { Text(result.summary).font(.caption).foregroundStyle(.secondary) }
			if opened == nil, let message = result?.realmMessage { Text(message).font(.caption).foregroundStyle(message.hasPrefix("no realms") || message.contains("CHECK FAILED") ? .red : .secondary) }
		}
	}

	/// The notes on zoom, save and open, kept out of the window until asked for.
	var help: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Zoom: pinch, double-click, Option-scroll, or + and - after clicking the map; drag to pan; Fit or ⌘0 returns. The most you can zoom depends on the cell size.")
			Text("Save map… saves the water map (the land map inside it) with rivers on, otherwise the land map; with realms drawn it keeps them, with the colours they are drawn in. Open map… reads either and shows its realms in the saved colours until a setting changes.")
		}
		.font(.callout)
		.frame(width: 320)
		.padding()
	}

	func savePicture() {
		guard let result = shown else { return }
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.png]
		panel.nameFieldStringValue = "map.png"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do { try MapImage.pngData(result.drawing, pixelWidth: 2560, pixelHeight: 1600).write(to: url) } catch { failure = "could not save the picture: \(error)" }
	}

	func pinLayer(for result: DemoResult) -> PinLayer {
		let fingerprint = result.fingerprint
		return PinLayer(pins: pinsByMap[fingerprint] ?? [], selectedID: $selectedPin) { event in
			switch event {
			case .dropped(let place):
				guard (pinsByMap[fingerprint]?.count ?? 0) < PinLimits.maximumPins else { return } // a map holds at most `PinLimits.maximumPins`
				let id = MapPin.newID()
				pinsByMap[fingerprint, default: []].append(MapPin(id: id, position: place, marker: settings.map.pin.marker, color: settings.map.pin.color))
				selectedPin = id
			case .moved(let id, let place):
				if let i = pinsByMap[fingerprint]?.firstIndex(where: { $0.id == id }) { pinsByMap[fingerprint]?[i].position = place }
			case .removeRequested(let id):
				pinsByMap[fingerprint]?.removeAll { $0.id == id }
				selectedPin = nil
			case .selected, .deselected: break
			}
		}
	}

	/// The pin the memo is for: the selected one, if the demo has it for this map.
	var selectedDemoPin: (fingerprint: String, index: Int)? {
		guard let fingerprint = shown?.fingerprint, let id = selectedPin, let index = pinsByMap[fingerprint]?.firstIndex(where: { $0.id == id }) else { return nil }
		return (fingerprint, index)
	}

	/// Where the selected pin's marker is in the map area now (zero if it is not shown).
	func selectedPinFrame(in size: CGSize) -> CGRect {
		guard let result = shown, let selected = selectedDemoPin, let pin = pinsByMap[selected.fingerprint]?[selected.index] else { return .zero }
		return PinGeometry.markerFrame(of: pin, in: result.drawing, viewSize: size, viewport: viewport) ?? .zero
	}

	/// The memo is open while a pin of this map is selected and in view; closing it deselects.
	func pinNoteIsShown(in size: CGSize) -> Binding<Bool> {
		Binding(get: { selectedDemoPin != nil && selectedPinFrame(in: size) != .zero }, set: { if !$0 { selectedPin = nil } })
	}

	/// The memo: a light sticky note for the selected pin, with a few colours for the pin and a delete. **The note and the colour are the demo's own data** (the framework draws no editor).
	@ViewBuilder
	var pinNote: some View {
		if let selected = selectedDemoPin {
			let fingerprint = selected.fingerprint, index = selected.index
			PinNote(
				note: Binding(get: { pinsByMap[fingerprint]?[index].note ?? "" }, set: { pinsByMap[fingerprint]?[index].note = $0 }),
				color: Binding(get: { pinsByMap[fingerprint]?[index].color ?? "red" }, set: { pinsByMap[fingerprint]?[index].color = $0; settings.map.pin.color = $0 }),
				onDelete: { pinsByMap[fingerprint]?.remove(at: index); selectedPin = nil })
		}
	}

	func openMap() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.json]
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			let made = try Maker.open(try Data(contentsOf: url), settings: settings, name: url.lastPathComponent, identity: "opened:\(openCount + 1)")
			openCount += 1
			opened = made
			pinsByMap[made.fingerprint] = made.map.pins // a map opened again shows the pins it was saved with
			failure = nil
		} catch { failure = "could not open the map: \(error)" }
	}

	func saveMap() {
		guard let result = shown else { return }
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.json]
		panel.nameFieldStringValue = "map.json"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			// the pins are part of the map's data: they are put in the map as it is saved
			let pins = pinsByMap[result.fingerprint] ?? []
			let data = try result.water.map { try $0.settingPins(pins).encoded() } ?? result.map.settingPins(pins).encoded()
			try data.write(to: url)
		} catch { failure = "could not save the map: \(error)" }
	}
}

@main
struct FantasyMapDemoApp: App {
	init() {
		// started from a terminal, the process is not a regular app yet: make it one so that it gets a window and the keyboard
		NSApplication.shared.setActivationPolicy(.regular)
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	var body: some Scene {
		WindowGroup("Fantasy map") { ContentView() }
	}
}


/// A light sticky note: a few lines of memo on yellow paper, a few colours for the pin, and a delete.
