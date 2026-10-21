# Fantasy Map Generator for Swift: Design

Status: draft for the author's approval, 2026-10-20. Design phase: this says **what** the package is and does, not how it is built. Nothing here is built, and nothing has been tried beyond reading the original and running it in a browser.

Working name: *Fantasy-Map-Generator-Swift* (the directory name). The final name is undecided; it must say that the package is **unofficial** and must not be confusable with the original project.

## What it is

A Swift package that makes fantasy maps like [Azgaar's Fantasy Map Generator](https://github.com/Azgaar/Fantasy-Map-Generator) does: a continent, an island or a region with sea, mountains, rivers, lakes, forests, deserts and, later, realms and their borders, seen from above. It is a **port of the ideas and algorithms, written in Swift**, for apps on Apple platforms, not for a browser. An app gives it a seed and a few settings, gets a map, shows it, and can save and load it.

## Credit and licence

- **The original** is © 2017–2024 Max Haniyeu (Azgaar), under the MIT licence with an added paragraph that maps, map images, screenshots and videos made with the tool are free to use. Its licence text is kept in this package in an acknowledgements file, in full, and the README names the original project and links to it.
- **This package** is © the author (Kaz Yoshikawa) for the Swift code. The licence of this package is the author's choice (MIT is the natural fit) and is settled before the repository goes public.
- **Any file that is a port** says so in a short header comment, naming the original file and the version it was read at (the clone read for this design is commit `8936c9c`, 2026-10-19).
- **Unofficial:** the README says it is independent, is not endorsed by the original author, and does not use the original's name as its own.
- **No borrowed assets.** The package contains only code written or ported by us. Nothing is copied from the original's icons, textures, height maps, name lists, emblems or brand images. **The two small algorithm libraries the original uses, Alea (random numbers) and Delaunator (triangulation), are ported as dependencies of the port,** with their own notices in the acknowledgements: the versions checked in the original's lock file are alea 1.0.1 (MIT), delaunator 5.1.0 (ISC) and its robust-predicates 3.0.3 (Unlicense), per the review of 2026-10-20, to be confirmed from their licence files when the notices are written.

## What the first version makes

Layered, each layer usable alone, in this order:

1. **Land.** A map of cells with heights: sea, coast, land, islands, lakes. Several land shapes (for example a continent, an island, an archipelago) chosen by name or by an editable list of steps.
2. **Water and terrain.** Temperature and rain, rivers that run from high ground to the sea or a lake, and a terrain type for every cell (forest, desert, grassland, snow and so on).
3. **Realms.** A chosen number of realms, each owning a connected area, with borders. Simpler than the original's states: no diplomacy, wars, economies, religions or cultures.
4. **A drawn look.** A flat, inked fantasy-map picture: coasts, rivers, mountains, forests, deserts, borders. Plain enough to suit a manga page.

**Left out of version one:** cultures, religions, towns, roads, markets, goods, military, journeys, name generation, 3D, an editor, and reading the original's `.map` files.

## Two layers

- **The core** makes and holds the map as plain data. It needs no windows, no SwiftUI, AppKit or UIKit, and no drawing, so it is easy to test and could run anywhere Swift does.
- **The drawing layer** turns the data into a picture. SwiftUI first, since one SwiftUI view serves macOS and iOS; thin AppKit and UIKit wrappers only if someone needs them. The core never depends on the drawing layer.

## Simple to use

An app should be able to do the following, and the design is judged by how little more it takes. This is an illustration of intent, not a fixed interface:

```swift
let map = try FantasyMap.generate(seed: "kaz-1", settings: .continent)   // some background work
FantasyMapView(map)                                                       // show it
let data = try map.encoded()                                              // save it
let again = try FantasyMap(decoding: data)                                // load it
```

- **Settings** are one plain value with sensible defaults and named starting points (continent, island, archipelago), and a few documented knobs: size, how much land, how mountainous, how wet, how many realms.
- **Generation runs in the background** and can be cancelled, because a large map takes time; the types are safe to hand between threads.
- **Same seed and settings, same map.** The package keeps its random state local to a generation (no global generator), so work can run concurrently. **Matching the original's maps for the same seed is a development target, not a promise:** the port tries to reproduce the original's random numbers, points, cells and heights at a pinned original version, step by step, and uses that as a test. If an exact match proves impractical, the package will choose its own deterministic behaviour **explicitly**, record the decision, and say what no longer matches. No public claim of identity with the original is made.

## Saving and loading

- **Its own format only,** decided 2026-10-20. Plain JSON the package defines, with a **format version number**, so a later release can still read an older file. Reading the original's `.map` files may be added later as an extra and is not part of version one.
- **What a saved map holds:** the exact state, so a loaded map is identical to the one saved and loading recomputes nothing. For the land layer (built: `LandMap`, see [step 8](steps/08-saving-and-loading.md)) that is the seed and size, the cell and boundary points, the final heights, the feature ids and records and the coast distance, and the recipe; the rivers, terrain types and realms will be added with their layers. The file is JSON with a format version and an algorithm revision; for 10,000 cells it is 231 KB.
- **What a map does not hold:** pictures, styles or app state. A drawing is made from the data and is not part of it.

## What done looks like for version one

- A map can be made from a seed and settings, shown in a SwiftUI view on macOS and iOS, saved, and loaded back **identical**.
- The same seed twice gives the same map, in a test.
- Credit and licence are present in the repository, and the repository contains no borrowed asset.
- Each layer has a short documentation page, since the original is thin on comments in places.

## Open questions

1. The package's final name, and its licence.
2. How the realms are made. The original's states grow outward from capitals; the first version may use a simpler method of our own, which needs a closer look at how theirs works.
3. How much of the saved map is stored and how much is rebuilt on load.
4. Which land shapes to start with.
5. Whether to ask the original author before the repository is public.

## What this note does not claim

Sizes and effort were estimated from line counts of the original, not measured. The algorithms were read only at the level of file headers and the original's own pipeline document, not line by line, and none has been ported or tested.
