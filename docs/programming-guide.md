# Programming guide

How to use the two libraries in your own app. Short on purpose: the types have doc comments, and each stage has a note in [`steps/`](steps/).

Requires macOS 14 or iOS 17, Swift 6. `FantasyMapKit` makes and saves maps and has no UI; `FantasyMapKitUI` draws and shows them in SwiftUI and depends on it.

## Add it

    .package(url: "https://github.com/codelynx/Fantasy-Map-Generator-Swift", from: "0.1.0")

then add the products `FantasyMapKit` and `FantasyMapKitUI` to your target.

## Make a map

```swift
import FantasyMapKit

let template = HeightmapTemplate.named("continents")!   // `HeightmapTemplate.all` lists the fourteen
let land = try LandMap.generate(seed: "12345", cellsDesired: 10_000, template: template)
let water = try WaterMap.generate(land: land)           // temperature, precipitation and rivers; optional
```

The same seed, template and cell count give the same map. Generation is synchronous and takes tens of milliseconds at 10,000 cells; run it off the main thread for 100,000 (build in release mode).

## Read the data (no UI needed)

`FantasyMapKit` alone is enough for a game that draws its own map. It has two kinds of cell, and mixing them up is the commonest mistake:

| | Grid cells | Packed cells |
|---|---|---|
| Where | `LandMap`: `grid.points`, `voronoi`, `heights` | `WaterMap.packed` |
| What | the regular Voronoi cells, 10,000 for `cellsDesired: 10_000` | a second diagram that drops deep ocean and splits coast cells, so it is finer where land meets water |
| Per cell | height, feature, coast distance, **temperature, rain, realm owner** | **river flux, river number**, final height, area |
| To the other | | `packed.gridCell[i]` is the grid cell packed cell `i` came from (several packed cells can share one) |

**Grid cells** (index `0 ..< land.heights.count`, the same index in every array):

```swift
let land = water.land
let v = land.voronoi

for cell in 0..<land.heights.count {
	let height = land.heights[cell]                          // 0 to 100, UInt8
	let isLand = Heights.isLand(height)                      // sea level is 20 (`Heights.seaLevel`)
	let featureID = Int(land.features.featureIds[cell])      // which island, ocean or lake the cell belongs to
	let kind = land.features.feature(featureID)?.kind        // .island, .ocean or .lake
	let coast = land.features.distanceField[cell]            // 1 land coast, 2 and up inland, -1 water coast, -2 and down out to sea
	let neighbours = v.cells.c[cell]                         // neighbouring cell indices
	let polygon = v.cells.v[cell].map { v.vertices.p[$0] }   // the cell's corners, in map units
	let centre = land.grid.points[cell]                      // the cell's point
	let temperature = water.temperature[cell]                // degrees Celsius, Int8
	let rain = water.precipitation[cell]                     // UInt8
}
```

Positions are in map units: `land.width` by `land.height` (as in the original's SVG map: the origin is the top-left corner, `y` grows down). Cells along the map edge have `v.cells.b[cell] == 1`. `land.features.features` lists every island, ocean and lake once (`Feature` has `kind`, `land`, `border`).

**Rivers** are lists of packed cells:

```swift
for river in water.rivers {
	for packedCell in river.cells where packedCell >= 0 {   // -1 means the water left the map
		let at = water.packed.points[packedCell]
		let gridCell = water.packed.gridCell[packedCell]
		let flux = water.flux[packedCell]                    // how much water passes; grows downstream
	}
}
```

A `River` also has `source` and `mouth` cells, `discharge`, `length`, `width`, and `parent` (the river it flows into, or 0). `water.riverIds[packedCell]` is the river number of a packed cell, 0 for none, and `water.packed.heights` are the heights after the rivers have cut their beds. The picture you see in `FantasyMapView` is drawn from the same arrays.

**Realms** are made in three steps and give one realm number per grid cell:

```swift
let groups = try LandGroups.find(in: land, reach: 25)    // landmasses joined by sea crossings no longer than `reach` map units
let policy = RealmPolicy(typicalRealmArea: 40_000, maximumRealms: 500)
let seeds = try RealmSeeds.place(in: land, groups: groups, count: .automatic, realmSeed: "realms-1", policy: policy)
let growth = GrowthPolicy(hillFactor: 3, mountainFactor: 8, crossingFactor: 4, unevenness: 3)
let ownership = try RealmOwnership.grow(in: land, groups: groups, seeds: seeds, realmSeed: "realms-1", policy: growth)

ownership.owner[cell]        // 1 ... realms.count, or 0 for water
ownership.realms             // each: number, seedCell, cellCount, area
```

`count: .chosen(8)` asks for a number of realms instead of the automatic count (land area divided by `typicalRealmArea`). Hills and mountains slow a realm's growth (`hillFactor`, `mountainFactor`), crossing the sea slows it more (`crossingFactor`), and `unevenness` makes realm sizes differ. The seed string and the policies decide the result, so keep them if you want to regenerate the same realms. Realms are **this port's own growth**, not the original's algorithm; the original's own states are not ported.

**Same seed, same map.** `generate` is deterministic: the seed, the template and the cell count decide everything, and the land and water stages were compared number for number with the original's own output (see [`steps/`](steps/)). A saved file keeps what was made rather than a recipe to remake it. The library reads every file format it has written so far (versions 1 to 3), but while it is 0.x, no promise goes further. To check that two files hold the same geography, compare `land.fingerprint`.

**Cost.** Making a map takes tens of milliseconds at 10,000 cells in release mode and grows with the cell count; the grid is limited to 200,000 points. Run it off the main thread, and use release mode for large maps.

**Example: where could towns go?** A game that wants settlements derives them from the arrays above. Rivers are in packed cells, so first turn them into grid cells with `packed.gridCell`, then score the grid cells:

```swift
/// The grid cells a river passes through.
func riverCells(_ water: WaterMap) -> Set<Int> {
	var cells = Set<Int>()
	for river in water.rivers {
		for packedCell in river.cells where packedCell >= 0 {
			cells.insert(water.packed.gridCell[packedCell])
		}
	}
	return cells
}

/// The best cells for a town: low land, near the coast, wet enough, and by a river if possible.
func townSites(_ water: WaterMap, count: Int) -> [Point] {
	let land = water.land
	let onRiver = riverCells(water)
	var scored: [(cell: Int, score: Int)] = []
	for cell in 0..<land.heights.count {
		let height = land.heights[cell]
		guard Heights.isLand(height), height < 50 else { continue }   // low land only
		let coast = land.features.distanceField[cell]
		guard coast >= 1, coast <= 3 else { continue }                // on the coast or one or two cells in
		var score = Int(water.precipitation[cell])                    // wetter is better
		if coast == 1 { score += 50 }                                 // a harbour
		if onRiver.contains(cell) { score += 100 }                    // fresh water
		scored.append((cell, score))
	}
	scored.sort { $0.score > $1.score }
	return scored.prefix(count).map { land.grid.points[$0.cell] }
}
```

The weights are arbitrary, so change them to taste. The best cells are often neighbours, so a real game would also skip any site too close to one already chosen.

**Not here yet:** biomes, cultures, religions, towns, roads and names. Compute what you need from the arrays above (for example, biome from `temperature`, `precipitation` and `heights`).

## Show it

```swift
import FantasyMapKitUI

FantasyMapView(water: water)    // or FantasyMapView(map: land)
```

`FantasyMapView` zooms (pinch, double-click, Option-scroll, `+` `-` `0`) and pans by itself. To keep or drive the zoom, pass a binding and an identity that changes when the map does:

```swift
@State private var viewport = MapViewport.fit

FantasyMapView(water: water, viewport: $viewport, mapIdentity: water.land.fingerprint)
```

Draw differently with a `MapStyle` (smoothing, coast ink width, rough coast, river width, realms on or off): `FantasyMapView(map: land, style: style)`.

## Render a picture

```swift
let png = try MapImage.pngData(MapDrawing(water: water, style: .standard), pixelWidth: 1600, pixelHeight: 1000)
```

`MapImage.render` gives a `CGImage` instead. Build the `MapDrawing` once and reuse it.

## Save and load

```swift
let data = try water.settingPins(pins).compressedEncoded()   // LZFSE, about a third of the size; `encoded()` is plain JSON
let loaded = try WaterMap(decoding: data)                     // reads either; `LandMap(decoding:)` for a land-only file
```

One file holds the land map, and the rivers if there are any, the realms and the pins. A loaded map is identical to the saved one. Loading checks everything and throws on a bad file. The file has its own format version (now 3) that does not follow the package version.

## Pins

Pins are kept in the map file and shown by the view. You give the view a `PinLayer` and handle its events; nothing changes until you change your pins.

```swift
FantasyMapView(
	water: water,
	pinLayer: PinLayer(pins: pins, selectedID: $selected) { event in
		switch event {
		case .dropped(let point): pins.append(MapPin(id: MapPin.newID(), position: point))
		case .moved(let id, let point): /* update that pin's position */
		case .removeRequested(let id): pins.removeAll { $0.id == id }
		case .selected, .deselected: break
		}
	})
```

A `MapPin` has an `id`, a `position` in map units, a `marker` key, a `color` key and a `note` (limits are in `PinLimits`: 5,000 pins, 2,000 characters per note). Markers keep their size on screen as the map zooms. Drop on press and hold by default (`dropMode:` `.click` or `.off`).

Your own marker look: conform to `PinMarkers` (a size and anchor for each pin, and a view) and pass `markers:`. Your own richer data about a pin stays in your app, keyed by the pin's `id`.

## Realms

Realms (territories) are the port's own growth over the cells: find the landmasses, place seeds, grow, then attach the result with `map.adding(RealmLayer(...))`; the view then draws a soft wash and thin borders. The sequence is longer than the rest, so read `Maker.realms` in `Sources/FantasyMapDemo/FantasyMapDemoApp.swift` and [`design-realms.md`](design-realms.md).

## The demo

`Sources/FantasyMapDemo` is a working app that uses all of the above; `swift run -c release FantasyMapDemo` opens it. It is a good place to copy from.
