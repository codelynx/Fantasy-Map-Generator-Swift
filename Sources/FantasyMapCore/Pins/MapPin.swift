import Foundation

/// A pin: a place on the map. **`id` is the client's** (any text, up to `PinLimits.maximumKeyLength` characters, unique among a map's pins: `MapPin.newID()` makes a fresh UUID
/// string); **`position` is in map units** (the viewport's own); `marker` names the marker to draw (`"pin"` or `"dot"` for the standard markers, or any key a client's own markers
/// understand); `color` names the pin's colour in the standard markers' palette (a few light colours; an unknown key draws red); `note` is a short memo. **This is everything a map saves
/// about a pin** (docs/plans/pins-saving.md): how a pin looks is the client's, and a client's richer data stays its own, keyed by the id.
public struct MapPin: Identifiable, Hashable, Codable, Sendable {
	public var id: String
	public var position: Point
	public var marker: String
	public var color: String
	public var note: String

	public init(id: String, position: Point, marker: String = "pin", color: String = "red", note: String = "") {
		self.id = id
		self.position = position
		self.marker = marker
		self.color = color
		self.note = note
	}

	/// A fresh identifier: a UUID string (Apple's standard form), collision-free for all practical purposes.
	public static func newID() -> String { UUID().uuidString }

	/// A pin saved before it had a colour or a memo reads as red and empty.
	public init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(String.self, forKey: .id)
		position = try c.decode(Point.self, forKey: .position)
		marker = try c.decode(String.self, forKey: .marker)
		color = try c.decodeIfPresent(String.self, forKey: .color) ?? "red"
		note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
	}

	private enum CodingKeys: String, CodingKey { case id, position, marker, color, note }

	/// Whether the pin has a place to show (a position that is not finite is never drawn or hit).
	public var isPlaceable: Bool { position.x.isFinite && position.y.isFinite }
}

/// The limits of a map's pin layer: a resource policy (the author accepted these as a starting point, 2026-10-21), so that a file's pin layer is bounded whatever the file says.
public enum PinLimits {
	/// The most pins a map holds.
	public static let maximumPins = 5_000
	/// The longest id, marker key or colour key, in characters.
	public static let maximumKeyLength = 64
	/// The longest memo, in characters, and also in UTF-8 bytes (a character can be many bytes).
	public static let maximumNoteLength = 2_000
	public static let maximumNoteBytes = 16_000
}

public enum PinLayerError: Error, Equatable, Sendable {
	case tooManyPins(Int)
	/// An id (by position in the list) that is empty or too long.
	case invalidID(index: Int)
	/// An id that appears more than once.
	case duplicateID(String)
	/// A place that is not finite or is outside the map.
	case invalidPlace(index: Int)
	/// A marker key or a colour key that is empty or too long.
	case invalidMarker(index: Int)
	case invalidColor(index: Int)
	/// A memo over the limit.
	case noteTooLong(index: Int)
}

enum PinValidation {
	/// The pin layer's checks for a map of the given size, in list order; the first problem is reported. An empty list is fine (it is no layer).
	static func validate(_ pins: [MapPin], width: Double, height: Double) throws {
		guard pins.count <= PinLimits.maximumPins else { throw PinLayerError.tooManyPins(pins.count) }
		var seen = Set<String>()
		for (i, pin) in pins.enumerated() {
			guard !pin.id.isEmpty, pin.id.count <= PinLimits.maximumKeyLength else { throw PinLayerError.invalidID(index: i) }
			guard seen.insert(pin.id).inserted else { throw PinLayerError.duplicateID(pin.id) }
			// inside the map, which also refuses NaN and the infinities (every comparison with them fails)
			guard pin.position.x >= 0, pin.position.x <= width, pin.position.y >= 0, pin.position.y <= height else { throw PinLayerError.invalidPlace(index: i) }
			guard !pin.marker.isEmpty, pin.marker.count <= PinLimits.maximumKeyLength else { throw PinLayerError.invalidMarker(index: i) }
			guard !pin.color.isEmpty, pin.color.count <= PinLimits.maximumKeyLength else { throw PinLayerError.invalidColor(index: i) }
			guard pin.note.count <= PinLimits.maximumNoteLength, pin.note.utf8.count <= PinLimits.maximumNoteBytes else { throw PinLayerError.noteTooLong(index: i) }
		}
	}
}
