// swift-tools-version: 6.0
import PackageDescription

// Working names: the package and library names are undecided (see docs/design.md).
let package = Package(
	name: "Fantasy-Map-Generator-Swift",
	platforms: [.macOS(.v14), .iOS(.v17)],
	products: [
		.library(name: "FantasyMapCore", targets: ["FantasyMapCore"]),
		.library(name: "FantasyMapKit", targets: ["FantasyMapKit"]),
		.executable(name: "FantasyMapDemo", targets: ["FantasyMapDemo"]),
	],
	targets: [
		.target(name: "FantasyMapCore"),
		// the drawing layer: depends on the core, and the core never depends on it
		.target(name: "FantasyMapKit", dependencies: ["FantasyMapCore"]),
		// a small window to try the package: it uses the libraries, and they do not use it
		.executableTarget(name: "FantasyMapDemo", dependencies: ["FantasyMapCore", "FantasyMapKit"]),
		.testTarget(name: "FantasyMapKitTests", dependencies: ["FantasyMapKit", "FantasyMapCore"]),
		.testTarget(
			name: "FantasyMapCoreTests",
			dependencies: ["FantasyMapCore"],
			resources: [.copy("Fixtures")]
		),
	]
)
