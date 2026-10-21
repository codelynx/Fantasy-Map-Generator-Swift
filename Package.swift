// swift-tools-version: 6.0
import PackageDescription

// Working names: the package and library names are undecided (see docs/design.md).
let package = Package(
	name: "Fantasy-Map-Generator-Swift",
	platforms: [.macOS(.v14), .iOS(.v17)],
	products: [
		.library(name: "FantasyMapKit", targets: ["FantasyMapKit"]),
		.library(name: "FantasyMapKitUI", targets: ["FantasyMapKitUI"]),
		.executable(name: "FantasyMapDemo", targets: ["FantasyMapDemo"]),
	],
	targets: [
		.target(name: "FantasyMapKit"),
		// the drawing layer: depends on the core, and the core never depends on it
		.target(name: "FantasyMapKitUI", dependencies: ["FantasyMapKit"]),
		// a small window to try the package: it uses the libraries, and they do not use it
		.executableTarget(name: "FantasyMapDemo", dependencies: ["FantasyMapKit", "FantasyMapKitUI"]),
		.testTarget(name: "FantasyMapKitUITests", dependencies: ["FantasyMapKitUI", "FantasyMapKit"]),
		.testTarget(
			name: "FantasyMapKitTests",
			dependencies: ["FantasyMapKit"],
			resources: [.copy("Fixtures")]
		),
	]
)
