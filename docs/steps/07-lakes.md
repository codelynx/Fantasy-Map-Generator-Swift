# Step 7: Lakes

Built 2026-10-20, as step 7 of [the land plan](../plans/land-layer.md). They run right after the features are marked, as in the original's pipeline: `markupGrid`, then `addDeepDepressionLakes`, then `openNearSeaLakes`, with nothing in between reading the features.

## What it does

`LandLakes` (`Sources/FantasyMapCore/Land/LandLakes.swift`) ports three routines of the original's `grid-generator.ts`:

- **`findDeepDepressionLakes`.** For each land cell that is not on the map's edge, is not lower than all its neighbours' minimum (a cell with a lower neighbour is skipped), a flood (last-in-first-out) looks for water within an **elevation limit**: cells at or above the cell's height plus the limit are not crossed, and reaching a cell below sea level means the cell can pour to water, so it is not a lake. A cell that cannot pour becomes a lake along with its neighbours of equal height. **A working copy of the heights is used, so a lake found earlier is water that a later check can reach.** An elevation limit of exactly **80 switches depression lakes off** (the original's sentinel); the default setting in the original is 20.
- **`addDeepDepressionLakes`.** For each lake found: its cells get height 19, water coast (-1) and a new feature number (the next number after the existing features); their neighbours outside the lake become coast land (1); and a new feature (water, not touching the edge, a lake) is added. **Heights, the coast distance, the feature ids and the feature records change together.**
- **`openNearSeaLakes`.** Near-sea lakes get a lot of water inflow, so where a coast-land cell of height 22 or less touches both a lake and an ocean, that cell becomes water (height 19, water coast, the ocean's number), its land neighbours become coast land, **every cell of the lake takes the ocean's number**, and **the former lake's feature record is kept with its kind changed to ocean**. That record keeps `land` false and `border` false, so it is an "ocean" that does not touch the edge, which a re-marking of the features would never produce; **running the feature marking again is not equivalent**, and the port does not do it.
- **The kept record has no cells.** After an opening, the former lake's numbers are merged into the ocean's, so its record is historical pipeline state, not a second current ocean body: **feature records need not all be referenced by cells.** No "opened lake" property is exposed; explicit provenance can be added when a caller needs it.
- **Failure behaviour.** `apply(...)` works on copies and publishes only a successful result. The public `addDeepDepressionLakes` changes its `inout` arguments in place, so if a later lake overflows the feature numbers and it throws, the earlier lakes have already been applied (and `openNearSeaLakes` can only fail by validation, before any change).
- **For saving and loading:** final points and heights alone cannot reconstruct these exact post-lake feature ids, retained records and coast markers by running the feature marking again, and lake creation must not be re-run on final heights. Whether a loaded map preserves this state or gets freshly canonicalised features is decided in step 8.
- **Feature numbering.** The original's table has a dummy element at index 0 so that feature numbers index it directly; here `features[0]` is feature 1, and lake feature numbers are `features.count + 1`. A new lake needing a number above 65,535 throws `tooManyFeatures` (the original would wrap).
- **Random numbers:** neither routine draws any, so none is passed or reset. Climate-dependent lake behaviour (the original's `lakes.ts`, which needs temperature and rain) belongs to a later layer.
- **Input checks:** the elevation limit must be finite and non-negative (`invalidElevationLimit`); the heights, features and diagram must match and the feature ids must refer to the table (`inconsistentInput`).

## The Atoll exception, as written

`openNearSeaLakes` begins `if (options.generation.template === "Atoll") return;`. In the original, the template option holds a template's **key** (`atoll`, lower case), which is what `HeightmapGenerator.generate` looks up; `Atoll` is its display name. So **the comparison never matches a real selection, and the early return is dead code for the Atoll template** (it only fires for an option that is exactly the string `Atoll`). This looks like a latent bug in the original. It is **kept as written** for parity: `LandLakes.openNearSeaLakes` takes the option's value as `templateOption` (for a `HeightmapTemplate`, pass its `key`, not its display name) and returns early only for exactly `"Atoll"` (`LandLakes.atollTemplateOption`), and the documentation says all of this. The fixtures run the Atoll template with its key (the step runs) and with the literal string "Atoll" (it does not).

## How it is tested (against the original's own routines)

`tools/capture-original-lakes.mjs` runs the original's own `Grid.findDeepDepressionLakes`, `Grid.addDeepDepressionLakes` and `Grid.openNearSeaLakes` after `Features.markupGrid()` on heightmaps from its own `HeightmapGenerator.generate`, with `options.generation` set, and saves a snapshot after each stage (digests of the heights, the coast distance and the feature ids, written explicitly as bytes and little-endian 16-bit numbers, the feature list, the land-cell count) and the lakes the finder reports.

- **420 maps:** all 14 templates × six grids (the default 10,000-cell map, 1,000 and 2,000 cells with other seeds, 300, 24 and 1,000 cells on other sizes) × five elevation limits (**0, 5, 20, 35 and 80**). At every stage — the features before the lakes, the lakes the finder reports, after the depression lakes, after the near-sea lakes — the digests, the feature records and the land counts match. **154 of the maps have depression lakes and 176 have a lake opened;** the fixtures include oceans that do not touch the edge, the case a re-marking would not give. At limit 80 the finder reports nothing.
- **The Atoll option:** twelve maps with the option set to the exact string "Atoll" (the step is skipped, and the original's output matches) and the same templates with their keys (the step runs).
- **Cell for cell:** two maps (a 24-cell map and a 1,000-cell map) compare heights, coast distance and feature ids in full.
- **Hand-made cases:** a deep depression becomes a lake and its shore becomes coast, and the same map with limit 80 gets none; a lake beside the sea, built from the graph so a low coast cell touches both a lake and an ocean, opens and keeps its record with kind ocean, `land` false and `border` false; and unsafe or inconsistent input is refused.

The same 87 tests pass in a release build, and the wrapper's `--check` finds all five fixtures identical on recapture.

## What it does not show

Parity with the original's lake routines for these maps and limits at the dependency versions in `Fixtures/original/provenance.json`; not for every map. Climate-dependent lakes, saving and loading of the land layer, and everything above the land layer are not built.
