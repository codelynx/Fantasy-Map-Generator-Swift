/// An unofficial Swift port of the ideas and algorithms of Azgaar's Fantasy Map Generator.
/// See ACKNOWLEDGEMENTS.md and docs/design.md. The land layer is built (docs/plans/land-layer.md); `LandMap` is its entry point.
public enum FantasyMapKit {
	/// The version of the saved-map format this package writes. The first supported persisted format is 1.
	public static let formatVersion = 1
	/// The version of the saved-map format a map **with a realm layer** is written in (a map without one is still written in `formatVersion`, byte for byte as
	/// before, and both are read).
	public static let formatVersionWithRealms = 2
	/// The version of the saved-map format a map **with pins** is written in (with or without realms). The version says which layers a file may hold: 1 none, 2 realms, 3 pins
	/// (and realms if it has them).
	public static let formatVersionWithPins = 3
	/// The version of the generation algorithms and of the cell rebuilding. 1 is the first complete land layer.
	public static let algorithmRevision = 1
}
