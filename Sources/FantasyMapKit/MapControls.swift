import FantasyMapCore
import SwiftUI

/// **All the controls of a map in one box**, beside a `FantasyMapView` (docs/plans/map-controls.md): the seed and land shape, the detail, the coast, the rivers, the
/// realms and the pins. It edits `MapSettings` and does nothing else: the app decides what a change takes (`MapSettings.change(from:)`) and what to do with it. By
/// default it shows every group; an app that does not want some passes the `groups` it wants, and the rest stay at their settings.
///
/// It is a plain column of controls with no scrolling of its own and no background, so an app puts it in a `ScrollView` or a sidebar of its own.
public struct MapControls: View {
	/// The groups of controls, in the order they are shown.
	public struct Groups: OptionSet, Sendable {
		public let rawValue: Int
		public init(rawValue: Int) { self.rawValue = rawValue }

		/// The seed, **Another Seed** and the land shape.
		public static let seedAndShape = Groups(rawValue: 1)
		/// The number of cells.
		public static let detail = Groups(rawValue: 2)
		/// Smoothing, ink width and the rough coast.
		public static let coast = Groups(rawValue: 4)
		/// Whether rivers are shown, and how wide.
		public static let rivers = Groups(rawValue: 8)
		/// Whether realms are drawn, the number of realms, how uneven they are and the reach; the rest under **More**.
		public static let realms = Groups(rawValue: 16)
		/// The marker and colour of the next pin, and how many pins there are.
		public static let pins = Groups(rawValue: 32)
		public static let all: Groups = [.seedAndShape, .detail, .coast, .rivers, .realms, .pins]
	}

	/// The groups in the order they are shown.
	nonisolated static let order: [Groups] = [.seedAndShape, .detail, .coast, .rivers, .realms, .pins]

	@Binding private var settings: MapSettings
	private let groups: Groups
	private let pinCount: Int?

	/// `pinCount` is how many pins the map has, for the pins group to say; nil says nothing.
	public init(settings: Binding<MapSettings>, groups: Groups = .all, pinCount: Int? = nil) {
		_settings = settings
		self.groups = groups
		self.pinCount = pinCount
	}

	public var body: some View {
		let shown = Self.order.filter { groups.contains($0) }
		VStack(alignment: .leading, spacing: 12) {
			ForEach(Array(shown.enumerated()), id: \.offset) { index, group in
				if index > 0 { Divider() }
				content(of: group)
			}
		}
	}

	@ViewBuilder
	private func content(of group: Groups) -> some View {
		switch group {
		case .seedAndShape: seedAndShape
		case .detail: detail
		case .coast: coast
		case .rivers: rivers
		case .realms: MapRealmControls(settings: $settings)
		default: pins
		}
	}

	// MARK: Seed and land shape

	private var seedAndShape: some View {
		VStack(alignment: .leading, spacing: 8) {
			LabeledContent("Seed") { TextField("seed", text: $settings.seed).textFieldStyle(.roundedBorder) }
			Button("Another Seed") { settings.seed = MapSettings.randomSeed() }
			Picker("Land shape", selection: $settings.landShape) {
				ForEach(HeightmapTemplate.all.map(\.key), id: \.self) { Text($0).tag($0) }
			}
		}
	}

	// MARK: Detail

	/// The numbers of cells the original offers, and the settings' own when it is another.
	private var cellChoices: [Int] {
		let steps = [1_000, 3_000, 10_000, 30_000, 100_000]
		return steps.contains(settings.cells) ? steps : (steps + [settings.cells]).sorted()
	}

	private var detail: some View {
		Picker("Cells", selection: $settings.cells) {
			ForEach(cellChoices, id: \.self) { Text($0.formatted()).tag($0) }
		}
	}

	// MARK: Coast

	private var coast: some View {
		VStack(alignment: .leading, spacing: 8) {
			Stepper("Smoothing: \(settings.coast.smoothing)", value: $settings.coast.smoothing, in: 0...CoastOutlines.maximumSmoothing)
			VStack(alignment: .leading) {
				Text("Coast ink width: \(settings.coast.inkWidth, specifier: "%.1f")")
				Slider(value: $settings.coast.inkWidth, in: 0...4)
			}
			Toggle("Rough coast", isOn: $settings.coast.rough)
			VStack(alignment: .leading) {
				Text("Roughness amplitude: \(settings.coast.amplitude, specifier: "%.2f")")
				Slider(value: $settings.coast.amplitude, in: 0.1...3)
			}
			.disabled(!settings.coast.rough)
			Stepper("Roughness variant: \(settings.coast.variant)", value: $settings.coast.variant, in: 0...99)
				.disabled(!settings.coast.rough)
		}
	}

	// MARK: Rivers

	private var rivers: some View {
		VStack(alignment: .leading, spacing: 8) {
			Toggle("Rivers", isOn: $settings.rivers.shown)
			VStack(alignment: .leading) {
				Text("River width: \(settings.rivers.widthScale, specifier: "%.1f")×")
				Slider(value: $settings.rivers.widthScale, in: 0.2...4)
			}
			.disabled(!settings.rivers.shown)
		}
	}

	// MARK: Pins

	private var pins: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("New pin", selection: $settings.pin.marker) {
				Text("Map pin").tag("pin")
				Text("Dot").tag("dot")
			}
			.pickerStyle(.segmented)
			HStack(spacing: 6) {
				Text("Colour").font(.caption)
				ForEach(StandardPinMarkers.colorKeys, id: \.self) { key in
					Circle()
						.fill(StandardPinMarkers().color(for: key))
						.frame(width: 16, height: 16)
						.overlay(Circle().stroke(Color.primary.opacity(settings.pin.color == key ? 0.9 : 0.2), lineWidth: settings.pin.color == key ? 2 : 1))
						.onTapGesture { settings.pin.color = key }
						.accessibilityLabel(key)
						.accessibilityAddTraits(settings.pin.color == key ? .isSelected : [])
				}
			}
			if let pinCount {
				Text(pinCount == 1 ? "1 pin on this map" : "\(pinCount) pins on this map").font(.caption)
			}
		}
	}
}

/// The realms group: what most people change in the open, and the rest under **More**.
struct MapRealmControls: View {
	@Binding var settings: MapSettings
	@State private var more = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Toggle("Draw realms", isOn: $settings.realms.drawn)
			Toggle("Automatic number of realms", isOn: $settings.realms.automaticCount)
			if !settings.realms.automaticCount {
				Stepper("Realms: \(settings.realms.count ?? 8)", value: Binding(get: { settings.realms.count ?? 8 }, set: { settings.realms.count = $0 }), in: 1...200)
			}
			VStack(alignment: .leading) {
				Text("How uneven: \(settings.realms.unevenness, specifier: "%.1f")")
				Slider(value: $settings.realms.unevenness, in: 0...20)
			}
			VStack(alignment: .leading) {
				Text("Reach (longest sea crossing): \(Int(settings.realms.reach)) map units")
				Slider(value: $settings.realms.reach, in: 0...150, step: 1)
			}
			DisclosureGroup("More", isExpanded: $more) {
				VStack(alignment: .leading, spacing: 8) {
					if settings.realms.automaticCount {
						VStack(alignment: .leading) {
							Text("Typical realm area: \(Int(settings.realms.typicalArea)) map units²")
							Slider(value: $settings.realms.typicalArea, in: 5_000...200_000, step: 5_000)
						}
					}
					VStack(alignment: .leading) {
						Text("Hill / mountain cost: \(settings.realms.hillFactor, specifier: "%.0f") / \(settings.realms.mountainFactor, specifier: "%.0f")")
						Slider(value: $settings.realms.hillFactor, in: 1...10, step: 1)
						Slider(value: $settings.realms.mountainFactor, in: 1...30, step: 1)
					}
					VStack(alignment: .leading) {
						Text("Sea crossing cost: \(settings.realms.crossingFactor, specifier: "%.0f")")
						Slider(value: $settings.realms.crossingFactor, in: 1...20, step: 1)
					}
					LabeledContent("Realm seed") {
						TextField("the map's seed", text: Binding(get: { settings.realms.seed ?? "" }, set: { settings.realms.seed = $0.isEmpty ? nil : $0 }))
							.textFieldStyle(.roundedBorder)
					}
				}
				.padding(.top, 6)
			}
		}
	}
}
