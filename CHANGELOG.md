# Changelog

Versions follow the package's git tags. While it is 0.x, the API may change.

## 0.2.0 (2026-10-21)

**Breaking: the libraries are renamed.** The data library is now `FantasyMapCore` (it was `FantasyMapKit`) and the drawing library is now `FantasyMapKit` (it was `FantasyMapKitUI`). Change `import FantasyMapKit` to `import FantasyMapCore` where you use maps as data, `import FantasyMapKitUI` to `import FantasyMapKit` where you draw them, and the product and target names in your `Package.swift` the same way. **Nothing in a saved map changes:** files written by 0.1.0 open in 0.2.0, and a map's fingerprint is the same, so anything you keyed to it still matches.

**New**
- `MapSettings`: everything that makes and shows a map as one value (seed, land shape, cells, coast, rivers, realms, the next pin). It validates itself, naming the setting it refuses. `MapSettings.change(from:)` says whether a change needs a new map, the realms again on the same land (the pins stay) or only a redraw. `MapSettings(describing:)` reads the settings back from a map.
- `WaterMap.generate(settings:)` makes a whole map (land, realms and water) in one call; `WaterMap.regrowingRealms(settings:)` makes only the realms again; `LandMap.addingRealms(settings:style:)`; `WaterMap.adding(_:)` swaps a realm layer. Realms take a chosen or automatic number, the reach, the growth factors, how uneven and a seed.
- `MapControls`: all the map's controls in one view, with one optional setting for which groups to show. The demo is built on it.
- `PinNote` (the sticky note for a pin), `PinGeometry.markerFrame` (where a pin's marker is) and `PinLimits.limiting(note:)` (a memo cut to what a map can save, by characters and by UTF-8 bytes).
- `MapDrawing(water:settings:)`, and `MapSettings.style`.
- A programming guide for using the libraries in your own app, with a Controls section.

**Fixed**
- A compile error with Swift 6.2 (a closure in the lake step named a value declared on the next line); Swift 6.4 accepted it.
- A memo of many multi-byte characters could be kept by an editor and then refused when the map was saved.

**Not done:** a Linux build and test run, and the README's demo picture still shows the earlier controls.

## 0.1.0

First release: the land, the water (temperature, precipitation, rivers), realms, drawing in SwiftUI with zoom, pan and pins, and saving and loading.
