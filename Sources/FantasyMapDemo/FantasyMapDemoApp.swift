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

/// What the controls hold. Hashable so that `.task(id:)` rebuilds the map whenever anything changes.
struct DemoSettings: Hashable {
	var seed = "kaz-1"
	var template = "continents"
	var cells = 10_000
	var smoothing = 2
	var roughness = false
	var amplitude = 0.75
	var variant = 0
	var inkWidth = 1.5
	// water: rivers drawn from a water map made from the land map
	var showRivers = false
	var riverScale = 1.0
	// realms (diagnostic): explicit values, no hidden defaults inside the package
	var showRealms = false
	/// With realms on: the picture's own wash and borders (follow the coast), and the raw-cell diagnostic overlay.
	var realmPicture = true
	var realmOverlay = false
	var reach = 25.0
	var automaticCount = true
	var realmCount = 8
	var realmSeed = "realms-1"
	var typicalArea = 40_000.0
	var hillFactor = 3.0
	var mountainFactor = 8.0
	var crossingFactor = 4.0
	var unevenness = 3.0
	var showSeeds = true
	var showLinks = true
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
	/// The style the settings ask for.
	static func style(for s: DemoSettings) throws -> MapStyle {
		var style = MapStyle.standard
		style.smoothing = s.smoothing
		style.inkWidth = s.inkWidth
		if s.roughness {
			var r = RoughnessSettings()
			r.baseAmplitude = s.amplitude
			r.variant = s.variant
			try r.validate()
			style.roughness = r
		}
		style.riverWidthScale = s.riverScale
		style.showRealms = s.realmPicture
		return style
	}

	/// A map or water map read from a file, drawn with the settings' style: **its realms are drawn with the colours saved with them.**
	static func open(_ data: Data, settings s: DemoSettings, name: String, identity: String) throws -> DemoResult {
		let style = try Self.style(for: s)
		var water: WaterMap?
		let map: LandMap
		if let w = try? WaterMap(decoding: data) { water = w; map = w.land } else { map = try LandMap(decoding: data) }
		let drawing = water.map { MapDrawing(water: $0, style: style) } ?? MapDrawing(map: map, style: style)
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

	/// Generates the map and builds its drawing (off the main thread, called from a detached task).
	static func make(_ s: DemoSettings) throws -> DemoResult {
		guard let template = HeightmapTemplate.named(s.template) else { throw DemoError.message("no land shape named \(s.template)") }
		let t0 = Date()
		var map = try LandMap.generate(seed: s.seed, cellsDesired: s.cells, template: template)
		let t1 = Date()
		let style = try Self.style(for: s)
		// the realms first: with the picture on, they are attached to the map as its realm layer, with the colours they are drawn in, so that saving the map keeps
		// them and opening it again shows the same picture
		var overlay: RealmOverlay?
		var realmMessage: String?
		if s.showRealms {
			let made = realms(for: map, s)
			(overlay, realmMessage) = (made.overlay, made.message)
			if s.realmPicture, let ownership = made.ownership, let recipe = made.recipe {
				do {
					let colours = try MapDrawing.resolvedRealmColors(for: map, ownership: ownership, style: style)
					map = try map.adding(RealmLayer(ownership: ownership, recipe: recipe, colors: colours))
				} catch { realmMessage = "no realm picture: \(error)" }
			}
		}
		var water: WaterMap?
		var waterNote = ""
		let tw0 = Date()
		if s.showRivers { water = try WaterMap.generate(land: map) }
		let drawing = water.map { MapDrawing(water: $0, style: style) } ?? MapDrawing(map: map, style: style)
		if let water {
			waterNote = "; water \(Int(Date().timeIntervalSince(tw0) * 1000)) ms: \(water.rivers.count) rivers, \(drawing.rivers.count) drawn"
			if drawing.riversInWater > 0 { waterNote += ", \(drawing.riversInWater) wholly in drawn water" }
			if drawing.riversSkipped > 0 { waterNote += ", \(drawing.riversSkipped) skipped" }
		}
		let t2 = Date()
		let land = map.heights.filter { Heights.isLand($0) }.count
		var summary = "\(map.heights.count) cells, \(land * 100 / max(map.heights.count, 1))% land; generate \(Int(t1.timeIntervalSince(t0) * 1000)) ms, draw \(Int(t2.timeIntervalSince(t1) * 1000)) ms\(waterNote)"
		if s.roughness {
			switch drawing.coast.roughness {
			case .applied: summary += "; roughness applied"
			case .fellBack(let reason): summary += "; roughness fell back to the smoothed coast (\(reason))"
			case .off: break
			}
		}
		// the geography decides the identity: the seed, the land shape and the number of cells; colours, line widths, rivers and realms are presentation
		return DemoResult(map: map, water: water, drawing: drawing, identity: "\(s.seed)|\(s.template)|\(s.cells)", fingerprint: map.fingerprint, summary: summary, overlay: overlay, realmMessage: realmMessage)
	}

	/// The realms of the map: the groups for the reach, the seeds for the count, the growth, and a diagnostic overlay of raw cell
	/// polygons coloured by owner. A refusal is reported in words, not hidden.
	static func realms(for map: LandMap, _ s: DemoSettings) -> (overlay: RealmOverlay?, message: String, ownership: RealmOwnership?, recipe: RealmRecipe?) {
		do {
			let groups = try LandGroups.find(in: map, reach: s.reach)
			let policy = RealmPolicy(typicalRealmArea: s.typicalArea, maximumRealms: 500)
			let seeds = try RealmSeeds.place(in: map, groups: groups, count: s.automaticCount ? .automatic : .chosen(s.realmCount), realmSeed: s.realmSeed, policy: policy)
			let growth = GrowthPolicy(hillFactor: s.hillFactor, mountainFactor: s.mountainFactor, crossingFactor: s.crossingFactor, unevenness: s.unevenness)
			let ownership = try RealmOwnership.grow(in: map, groups: groups, seeds: seeds, realmSeed: s.realmSeed, policy: growth)
			let problems = RealmOwnership.problems(in: ownership, groups: groups, seeds: seeds, neighbours: map.voronoi.cells.c)
			let v = map.voronoi
			var cells: [RealmCellShape] = []
			for cell in 0..<map.heights.count where ownership.owner[cell] > 0 {
				let polygon = RectangleClip.clip(v.cells.v[cell].map { v.vertices.p[$0] }, width: map.width, height: map.height)
				if polygon.count >= 3 { cells.append(RealmCellShape(points: polygon, realm: Int(ownership.owner[cell]))) }
			}
			let sizes = ownership.realms.map(\.cellCount)
			var message = "\(groups.landmasses.count) landmasses, \(groups.minimumRealms) groups at reach \(Int(s.reach)); \(seeds.resolvedCount) realms (\(s.automaticCount ? "automatic" : "chosen")); realm sizes \(sizes.min() ?? 0) to \(sizes.max() ?? 0) cells"
			if !problems.isEmpty { message += "; CHECK FAILED: \(problems.first!)" }
			let overlay = RealmOverlay(cells: cells, seeds: seeds.realms.map { map.grid.points[$0.cell] },
				links: groups.links.map { RealmSegment(from: $0.pointA, to: $0.pointB) }, width: map.width, height: map.height)
			let recipe = RealmRecipe(realmSeed: s.realmSeed, reach: s.reach, chosenCount: s.automaticCount ? nil : s.realmCount, resolvedCount: seeds.resolvedCount, typicalRealmArea: s.typicalArea, maximumRealms: 500, hillFactor: s.hillFactor, mountainFactor: s.mountainFactor, crossingFactor: s.crossingFactor, unevenness: s.unevenness)
			return (overlay, message, ownership, recipe)
		} catch {
			return (nil, "no realms: \(error)", nil, nil)
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
	@State private var newMarker = "pin"
	@State private var newColor = "red"
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
						if let overlay = result.overlay, settings.showRealms, settings.realmOverlay { RealmOverlayView(overlay: overlay, showSeeds: settings.showSeeds, showLinks: settings.showLinks, viewport: viewport, cellSpacing: result.drawing.cellSpacing) }
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
		.onChange(of: settings) { opened = nil }
		.task(id: settings) {
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
			LabeledContent("Seed") { TextField("seed", text: $settings.seed).textFieldStyle(.roundedBorder) }
			Picker("Land shape", selection: $settings.template) {
				ForEach(HeightmapTemplate.all.map(\.key), id: \.self) { Text($0).tag($0) }
			}
			Picker("Cells", selection: $settings.cells) {
				ForEach([1_000, 3_000, 10_000, 30_000, 100_000], id: \.self) { Text($0.formatted()).tag($0) }
			}
			Stepper("Smoothing: \(settings.smoothing)", value: $settings.smoothing, in: 0...CoastOutlines.maximumSmoothing)
			VStack(alignment: .leading) {
				Text("Coast ink width: \(settings.inkWidth, specifier: "%.1f")")
				Slider(value: $settings.inkWidth, in: 0...4)
			}
			Divider()
			Toggle("Rough coast", isOn: $settings.roughness)
			VStack(alignment: .leading) {
				Text("Roughness amplitude: \(settings.amplitude, specifier: "%.2f")")
				Slider(value: $settings.amplitude, in: 0.1...3)
			}.disabled(!settings.roughness)
			Stepper("Roughness variant: \(settings.variant)", value: $settings.variant, in: 0...99).disabled(!settings.roughness)
			Divider()
			Toggle("Rivers (water map)", isOn: $settings.showRivers)
			VStack(alignment: .leading) {
				Text("River width: \(settings.riverScale, specifier: "%.1f")×")
				Slider(value: $settings.riverScale, in: 0.2...4)
			}.disabled(!settings.showRivers)
			Divider()
			Text("Pins").font(.headline)
			pinControls
			Divider()
			Toggle("Realms", isOn: $settings.showRealms)
			if settings.showRealms { realmControls }
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
			if settings.showRealms, opened == nil, let message = result?.realmMessage { Text(message).font(.caption).foregroundStyle(message.hasPrefix("no realms") || message.contains("CHECK FAILED") ? .red : .secondary) }
			Spacer()
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

	var realmControls: some View {
		VStack(alignment: .leading, spacing: 8) {
			Toggle("Draw realms in the picture", isOn: $settings.realmPicture)
			Text("A soft wash per realm, held inside the coast, and a thin grey dashed border between realms.").font(.caption2).foregroundStyle(.secondary)
			Toggle("Raw-cell overlay (diagnostic)", isOn: $settings.realmOverlay)
			Text("The overlay is raw cell polygons for looking at territories; not the coast-aligned drawing.").font(.caption2).foregroundStyle(.secondary)
			VStack(alignment: .leading) {
				Text("Reach (longest sea crossing): \(Int(settings.reach)) map units")
				Slider(value: $settings.reach, in: 0...150, step: 1)
			}
			Toggle("Automatic realm count", isOn: $settings.automaticCount)
			if settings.automaticCount {
				VStack(alignment: .leading) {
					Text("Typical realm area: \(Int(settings.typicalArea)) map units²")
					Slider(value: $settings.typicalArea, in: 5_000...200_000, step: 5_000)
				}
			} else {
				Stepper("Realms: \(settings.realmCount)", value: $settings.realmCount, in: 1...200)
			}
			LabeledContent("Realm seed") { TextField("seed", text: $settings.realmSeed).textFieldStyle(.roundedBorder) }
			VStack(alignment: .leading) {
				Text("Unevenness: \(settings.unevenness, specifier: "%.1f")")
				Slider(value: $settings.unevenness, in: 0...20)
			}
			VStack(alignment: .leading) {
				Text("Hill / mountain cost: \(settings.hillFactor, specifier: "%.0f") / \(settings.mountainFactor, specifier: "%.0f")")
				Slider(value: $settings.hillFactor, in: 1...10, step: 1)
				Slider(value: $settings.mountainFactor, in: 1...30, step: 1)
			}
			VStack(alignment: .leading) {
				Text("Sea crossing cost: \(settings.crossingFactor, specifier: "%.0f")")
				Slider(value: $settings.crossingFactor, in: 1...20, step: 1)
			}
			Toggle("Show seeds", isOn: $settings.showSeeds)
			Toggle("Show crossing links", isOn: $settings.showLinks)
		}
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
				pinsByMap[fingerprint, default: []].append(MapPin(id: id, position: place, marker: newMarker, color: newColor))
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
		let g = MapViewportGeometry(mapWidth: result.drawing.width, mapHeight: result.drawing.height, viewWidth: size.width, viewHeight: size.height, cellSpacing: result.drawing.cellSpacing)
		return PinGeometry.placements(pins: [pin], markers: StandardPinMarkers(), geometry: g, viewport: viewport).first { $0.isVisible }?.frame ?? .zero
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
			PinNoteView(
				note: Binding(get: { pinsByMap[fingerprint]?[index].note ?? "" }, set: { pinsByMap[fingerprint]?[index].note = String($0.prefix(PinLimits.maximumNoteLength)) }),
				color: Binding(get: { pinsByMap[fingerprint]?[index].color ?? "red" }, set: { pinsByMap[fingerprint]?[index].color = $0; newColor = $0 }),
				onDelete: { pinsByMap[fingerprint]?.remove(at: index); selectedPin = nil })
		}
	}

	/// The side panel: how new pins look, how many there are. **Tap a pin on the map for its memo.**
	@ViewBuilder
	var pinControls: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("New pin", selection: $newMarker) {
				Text("Map pin").tag("pin"); Text("Dot").tag("dot")
			}.pickerStyle(.segmented)
			HStack(spacing: 6) {
				Text("Colour").font(.caption)
				ForEach(StandardPinMarkers.colorKeys, id: \.self) { key in
					Circle().fill(StandardPinMarkers().color(for: key)).frame(width: 16, height: 16)
						.overlay(Circle().stroke(Color.primary.opacity(newColor == key ? 0.9 : 0.2), lineWidth: newColor == key ? 2 : 1))
						.onTapGesture { newColor = key }
				}
			}
			Text("Press and hold on the map to drop a pin and write its memo; tap a pin for its memo, drag it to move it, Delete removes it. The pins are saved with the map.").font(.caption2).foregroundStyle(.secondary)
			if let fingerprint = shown?.fingerprint {
				let count = pinsByMap[fingerprint]?.count ?? 0
				let elsewhere = pinsByMap.filter { $0.key != fingerprint }.values.reduce(0) { $0 + $1.count }
				Text("\(count) pins on this map" + (elsewhere > 0 ? "; \(elsewhere) belong to other maps (not shown)" : "")).font(.caption)
			}
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
struct PinNoteView: View {
	@Binding var note: String
	@Binding var color: String
	var onDelete: () -> Void
	@FocusState private var focused: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextEditor(text: $note)
				.font(.system(size: 13))
				.scrollContentBackground(.hidden)
				.focused($focused)
				.frame(width: 220, height: 110)
				.overlay(alignment: .topLeading) {
					if note.isEmpty { Text("Memo…").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
				}
			HStack(spacing: 8) {
				ForEach(StandardPinMarkers.colorKeys, id: \.self) { key in
					Circle().fill(StandardPinMarkers().color(for: key)).frame(width: 18, height: 18)
						.overlay(Circle().stroke(Color.black.opacity(color == key ? 0.8 : 0.15), lineWidth: color == key ? 2 : 1))
						.onTapGesture { color = key }
				}
				Spacer()
				Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
			}
		}
		.padding(10)
		.background(Color(red: 1, green: 0.96, blue: 0.66))
		.foregroundStyle(Color.black.opacity(0.85))
		.onAppear { focused = true }
	}
}
