import FantasyMapCore
import SwiftUI

/// **A light sticky note for a pin** (docs/plans/map-controls.md, step 5): a memo to write, the six colours for the pin, and a delete. An app shows it in a popover beside
/// the selected pin (`PinGeometry.markerFrame` says where the marker is). It edits what it is given and nothing else: the note is cut to what a map can save
/// (`PinLimits.limiting(note:)`), and **the app keeps the memo, the colour and the delete**, as it keeps every pin.
public struct PinNote: View {
	@Binding private var note: String
	@Binding private var color: String
	private let onDelete: () -> Void
	@FocusState private var focused: Bool

	public init(note: Binding<String>, color: Binding<String>, onDelete: @escaping () -> Void) {
		_note = note
		_color = color
		self.onDelete = onDelete
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextEditor(text: Binding(get: { note }, set: { note = PinLimits.limiting(note: $0) }))
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
						.accessibilityLabel(key)
						.accessibilityAddTraits(color == key ? .isSelected : [])
				}
				Spacer()
				Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
					.buttonStyle(.borderless)
					.accessibilityLabel("Delete pin")
			}
		}
		.padding(10)
		.background(Color(red: 1, green: 0.96, blue: 0.66))
		.foregroundStyle(Color.black.opacity(0.85))
		.onAppear { focused = true }
	}
}
