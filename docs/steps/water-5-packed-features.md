# Water chain, stage 5: the packed graph's features (`markupPack`)

Status: built 2026-10-20 (plan: [water.md](../plans/water.md)). Fifth stage of the faithful port of the original's water chain. It marks the oceans, lakes and islands of the packed graph, their rings of Voronoi vertices, the distance of every cell from the coast and the havens, and for lakes the shoreline and height.

## What was built

- **`PackedFeatures.markup(for:width:height:)`** (`Sources/FantasyMapCore/Pack/PackedFeatures.swift`), a port of `Features.markupPack` (and its `markup` pass) in `features-generator.ts` at the pinned original (commit `8936c9c`). Over the packed cells it:
  - **floods the features** (an explicit stack, popped from the end, as the original's array is; the order matters, below), numbering them from 1: a feature is land, or water that touches the map border (an ocean) or not (a lake);
  - **marks the coast distance** (`distanceField`, the original's `Int8Array`): 1 for a land coast cell, −1 for the water cell across it, 2 for land beside a coast cell, then ring by ring 3, 4, … inland and −2, −3, … out to sea, **stopping at −9** (the loop's limit is −10, so cells farther out stay 0);
  - **gives each land coast cell its haven and harbor:** the closest water neighbour (by squared distance, **the first listed on a tie**) and the number of water neighbours; **a haven of cell 0 cannot be told from "none"** (the original tests `!haven[cell]`), kept;
  - **finds each island's and lake's ring** from its first cell on a border: it walks the Voronoi vertices around the cells with `connectVertices`, clips the ring to the map with the original's `clipPoly`, measures its area, and for a lake **reverses the ring when the clipped area is positive**, then lists the lake's **shoreline** (the land cells around its ring, each once, in order of first appearance; boundary points are not land) and its **height** (the lowest shore cell less 0.1, rounded to two decimals, with 20 in place of a missing or zero lowest).
  An ocean has no ring: its area is the sum of its cells' areas, and its first cell is the first cell found.
- **The result** is `PackedFeatures`: `distanceField`, `featureIds` (`Uint16`), `haven`, `harbor` (`Uint8`) and `features` (numbered from 1; `feature(_:)` looks one up; the original's placeholder at index 0 is not kept).
- **`LineClip`** (`Sources/FantasyMapCore/Geometry/LineClip.swift`) is a port of lineclip 2.0.0's `clipPolygon` (and the original's `clipPoly`, without its `secure` option, which `markupPack` does not use). **It is not the land layer's `RectangleClip`:** lineclip clips against the sides in its own order (left, right, bottom, top), with bit codes whose tests are strict, and its own crossing formulas, so the points and the order of the ring differ from `RectangleClip`'s. `RectangleClip` stays as it is for the drawing and the realm geometry.
- **`VertexRing.connect`** ports `connectVertices`, **keeping its stops:** it ends and returns the ring so far when the next vertex is outside the list (a hull edge holds −1), is the current one, or the walk has gone on for as many steps as there are vertices (the original logs an error only with its debug flag on).
- **Refusals, documented as divergences:** a feature number past 65535 (the original's `Uint16Array` would wrap) throws `tooManyFeatures`; a feature with no border cell or no starting vertex throws `noBorderCell` or `noStartingVertex` (the original throws too); disagreeing arrays throw `invalidInputs`.
- **A packed map with no cell is supported** (the contract the stage 4 review asked for): the original returns without marking anything, and this returns no features and empty arrays.
- **New dependency notices:** d3-polygon 3.0.1 (the polygon area, ported in stage 4 and noticed now) and lineclip 2.0.0 (ISC, © 2015 Mapbox), in `ACKNOWLEDGEMENTS.md` and `docs/dependencies.md`, from each package's own LICENSE file.

## An order dependence worth knowing

The "landlocked" mark (2) is set only from a cell already known to be a coast cell when its neighbour is looked at, in the order the flood visits the cells and the neighbours. A cell can therefore miss its 2 and be numbered by the later ring pass instead (a test shows one on a path of cells). It is the original's behaviour, and the fixtures confirm the port reproduces it on real maps.

## Fixtures and tests

`tools/capture-original-markup-pack.mjs` (wired into `tools/capture-original.sh`) runs the original's own chain up to `Pack.generate` and then `Features.markupPack` for **98 runs** (the fourteen templates on seven map configurations), and records the sizes, a sha256 of each of the four cell arrays (explicitly little-endian Int32) and **every feature** (972 in all: 197 oceans, 535 islands, 240 lakes): its scalar fields exactly, and a sha256 of its ring and shoreline, with both lists whole on the small maps; four runs have no packed cell. `tools/capture-original-clip.mjs` runs the original's own `clipPoly` on **702 polygons** (random ones, with points snapped onto the edges and corners, wholly inside, wholly outside, concave, repeated points, 0 to 12 points, on three rectangles) and records the output exactly. The nine earlier fixtures came out identical.

`PackedFeaturesTests` (12): **all 98 runs equal the original** (the four arrays, every feature's fields, rings and shorelines; the whole arrays cell for cell), **all 702 clipped polygons equal the original exactly**; the runs cover oceans, islands, lakes with shores, islands on and off the border, cells with several water neighbours and the empty map. Hand cases: the clipping (inside, fewer than two points, outside, a triangle clipped on the right, points on the edges); the ring walk on hand-made vertices (a closed cycle, with and without closing, each stop of the original, and the walk that never returns); an ocean, an island and a lake on a path of cells with their distances, harbors, havens, first cells and the haven-of-cell-0 quirk; the haven on a tie and by distance; the water distance stopping at −9; the land distance and the order dependence above; a lake's shoreline order and height (with and without a shore); and the empty packed map.

**Mutation checks** (57, each made and undone): the haven rules (the unset test, tie order, nearest, the count), every distance value and both landlocked branches, the flood order (stack versus queue), the border and kind of a feature, its cell count and areas, the ocean area, the ring area's rounding and sign, the lake ring's reversal (and reversing islands too), the border cell and starting vertex tests, the shoreline's uniqueness and land test, the lake height's delta, rounding, default and minimum, the markup's starts and limits and its previous ring, each condition of the ring walk and each of its stops, the empty map, the feature limit, and in the clipping the side order, every bit code, every crossing formula, the order of crossing and point, and the two-point rule. **51 were caught at first. One survivor was a gap (the walk's "next is the current vertex" stop away from the start), fixed with a test and now caught. Five survive and are equivalent, not gaps:**

- recomputing the haven of a coast cell every time instead of only when unset (the result is the same: the haven is a pure function of the cell, the original's test only saves work);
- starting a feature's border flag as false instead of from its first cell (the first cell is popped and tested first anyway);
- a boundary point's feature number as 0 instead of undefined (feature numbers start at 1, so 0 differs from every feature as undefined does);
- rounding a lake's height to one decimal instead of two (the heights are whole numbers, so the height less 0.1 has one decimal either way);
- not breaking out of the clipping loop when a side leaves nothing (the next pass returns nothing too).

## Limits

- 98 runs and 702 clipping cases are samples; exact equality is observed on them. The clipping fixtures check the clipping on its own, and the runs check it through the rings.
- A lake's ring is clipped to the map, and the clipped area decides the ring's direction; a ring that the walk stops early (a stop above) is clipped as it is.
- The search for a border cell scans all cells for each feature, as the original does; it is quadratic in the worst case (many features), not measured here.
