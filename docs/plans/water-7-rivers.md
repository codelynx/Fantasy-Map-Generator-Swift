# Water chain, stage 7: `Rivers.generate` (work and output budgets, refusals, order)

Status: plan, 2026-10-21, for review. Written after the stage 6 review asked for the work and output budgets and the named non-finite-climate refusal to be established **before** implementation and capture. Nothing of stage 7 is built or captured. The original is read at commit `8936c9c`: `river-generator.ts` lines 189 to 635 (`generate` with its inner `drainWater`, `flowDown`, `defineRivers`, `downcutRivers`, `calculateConfluenceFlux`; `alterHeights`; `resolveDepressions`; `addMeandering`, `getRiverPoints`, `getOffset`, `getSourceWidth`, `getApproximateLength`, `getWidth`) and `utils/pathUtils.ts` `meander` with the whole of `relaxAcuteAngles`, `cornerCos`, `reflectAcrossLine` and `projectToNearestEdge` (lines 410 to 596).

## What the original does, in its order

`generate(allowErosion = true)`: reset the random stream to the seed (no river code draws from it: the naming functions that do are outside this port) → allocate `fl` (`Uint16Array`), `r` (`Uint16Array`) and `conf` (**`Uint8Array`**) → `alterHeights` (a fractional working copy of the packed heights: land cells with a positive coast distance get `+ t/100 + mean(neighbour t)/10000`) → `Lakes.detectCloseLakes(h)` → `resolveDepressions(h)` (in place) → `drainWater` (which begins with `Lakes.defineClimateData(h)`) → `defineRivers` (the river records, with the meandering geometry) → `calculateConfluenceFlux` → `Lakes.cleanupLakeData()` → if erosion is allowed: **apply the working heights to the packed heights** (`Uint8Array.from(h)`, truncating) and `downcutRivers` (at most 5, never under 35).

## Numeric and ordering traps found in this reading (each gets its own test)

1. **`fl` is a `Uint16Array`.** Every `fl[i] += x` stores the **truncated and wrapped** sum, so the flux is truncated at each addition, not at the end (`prec / cellsNumberModifier` is a fraction). The port stores through `toUInt16` at every addition.
2. **`conf` is a `Uint8Array` during drainage** (`conf[toCell] += fl[toCell]` wraps at 256), and is `flowDown`'s subtracted term. `defineRivers` then replaces it with a fresh `Uint16Array`, marks real confluences with 1, and `calculateConfluenceFlux` stores the sum of all but the largest inflow.
3. **`riverNext` and `r` are `Uint16`:** past 65,535 rivers the ids would wrap. Refused (below).
4. **`resolveDepressions` reassigns its parameter on a bad run** (`h = this.alterHeights()`), which replaces only the local variable: **the caller's array keeps the in-place raises, so the "set heights back" has no effect on the caller.** The port keeps this: it breaks out of the loop and leaves the caller's heights as they are.
5. **The thresholds are fractional:** the lake checks run for iterations under `0.85 × maxIterations` and a lake is forced closed over `0.75 × maxIterations` (for 250: 212.5 and 187.5, so iteration 188 is the first forced and 213 the first not checked).
6. **`height(i)` is `features[f[i]].height || h[i]`:** a lake's height of 0 falls back to the cell's. A lake that has no shore gives `min([])` undefined and `l.height > undefined` false.
7. **Sorting:** `land.sort((a, b) => h[b] - h[a])` (descending, in `drainWater`) and ascending in `resolveDepressions`: `Array.prototype.sort` is stable, so equal heights keep cell order; the port uses a stable sort with the same comparator on the fractional heights. `cells.c[i].filter(...).sort((a, b) => h[a] - h[b])[0]` in the lake-outlet case is also a stable sort's first element, which is the first minimum.
8. **Truthiness:** `cells.haven[i]` (a haven of cell 0 reads as none, stage 5), `lakeOutCells[i]`, `cells.r[...]`, `waterBody.river`, `parent` of 0, and `lakes[0]?.outlet`.
9. **Feature table offset:** `features[cells.f[...]]` uses the original's table with a placeholder at 0; the port's table starts at feature 1.
10. **`d3.mean` of an empty list is `undefined`** (`alterHeights` for a land cell with no neighbours, which a valid packed graph does not have): refused as inconsistent input.

## Resource policy (explicit, independently adjustable, reported)

One `RiverResourcePolicy` value holds every limit, each adjustable on its own, and the result carries a **`RiverReport`** with the observed numbers (work charged per part, river entries, geometry points and the estimated geometry bytes) so that timings can be read beside the counts. **All defaults below are provisional development values, for measurement; they are not recommended production limits** (the stage 6 review: 2,000 × n can permit substantial work at the maximum packed size).

`n` is the number of packed cells (at most the Voronoi ceiling minus the boundary points, 400,000, in practice a few times the grid's cell count).

### What the work budget charges

A deterministic counter of **attempts, charged before anything is filtered or skipped**, with **overflow-checked arithmetic** (`addingReportingOverflow`; an overflow is the same refusal as exceeding the budget). Exceeding it throws `RiverError.workBudgetExceeded(part)`. The charges:

| Where | Charged |
|---|---|
| `detectCloseLakes` | 1 for each lake started; 1 for each shore cell examined for the lowest; **1 for each neighbour examined in the flood, before the visited and height tests** |
| `resolveDepressions` | the initial filter and sort of the land cells: n for the filter and n × (bit length of n) for the sort (an upper bound of its comparisons); per iteration: for each lake, 1 plus its shore length; for each land cell, 1 plus its neighbour count (all examined before the tests) |
| `drainWater`, start | the filter and the descending sort of the land cells, as above |
| `drainWater`, per land cell | 1; **its neighbours** in each `find`, `filter`, `reduce` or `some` it runs (each element charged before the test); for a lake outlet cell: **the whole feature list** for the `features.filter` (the number of features), each lake it finds, its neighbours for the `find`, its inlets when they are assigned to the outlet's basin, and for the downhill search `lakes.map(...).includes(...)` over the neighbours (neighbours × lakes) |
| `flowDown` | 1 per call |
| `defineRivers`, `calculateConfluenceFlux`, `downcutRivers`, `alterHeights` | **linear passes: not counted one by one.** One structural validation establishes what bounds them: **every cell has at most 20 neighbours** (the Voronoi port stops at 20 around a point), so the total neighbour entries are at most 20 × n; the validation checks the entries' sum |

The default is **2,000 × n charges**, to be measured (on the 98 fixture maps and at 100,000 cells) before it is recommended; a normal map charges a small multiple of n.

### Output limits: policies, and what is and is not proven

- **The number of rivers ≤ 65,535**, checked **before assigning or storing an id** that the `Uint16` river array would wrap (`riverNext` itself is an ordinary number, as in the original): `tooManyRivers`. This one is a hard limit of the original's storage.
- **River entries ≤ 4 × n** is a **provisional refusal policy, not a proven bound.** The reading suggests each land cell adds at most one downhill entry and each lake outlet one, plus the border entries (−1) and the lake-chain entries, but a worst case has not been established. **It is enforced before every append to a river's list** (lake entries and border entries included), not only when `defineRivers` begins: `riverEntriesBudgetExceeded`.
- **Geometry.** Once a river's entry list is known (before its points are allocated), **its meander output is preflighted:** the points of a river are at most **3 × its entries** (up to 2 points inserted per segment, none removed by the relaxation), and **the temporary arrays are budgeted too**, not only the points: `relaxAcuteAngles` builds an anchor flag per point (1 byte), a previous and a next anchor index per point (8 bytes together) and, **in each of at most 4 passes, a full snapshot copy of the points** (16 bytes of coordinates per point plus its container), and `meander` builds a list of anchor points for the cells. The preflight estimates the **peak bytes** of the river's geometry (the points, the anchor lists and one snapshot at its peak) and refuses past `maximumGeometryBytes` (provisional 256 MiB for all rivers' geometry held at once) or `maximumRiverPoints` (provisional 4,000,000 in all): `riverGeometryBudgetExceeded`. **A point cap alone is not a peak-memory estimate**, and the estimate is itself unmeasured until the build.

## The named refusals (the integrated operation publishes no partial result)

The integrated `Rivers.generate` port works on **copies** of the packed heights, the flux, river and confluence arrays and the lake fields, and returns its result only on success; a refusal leaves the caller's `PackedMap` and `PackedFeatures` untouched.

- **`RiverError.nonFiniteLakeClimate(lake: Int, field: LakeClimateField)`**, with `LakeClimateField` one of `flux`, `temperature`, `evaporation`: thrown **immediately after `defineClimateData` returns and before the drainage loop consumes it**, checking **every** lake's three values, closed lakes included; the lake is named by its feature number. (The parity helpers keep their documented non-finite behaviour.)
- `invalidSettings` (the depression steps not a whole number from 1 to 1,000: **default 250; zero iterations is unsupported by this package** (the original with 0 would run none and return), which is documented; the elevation limit outside 0 … 100 and fractions kept, the height exponent outside 0.1 … 5: **one authoritative exponent** in the integrated settings, passed to the temperature and the lake climate), `invalidInputs` (the arrays and indices of the packed map, the features, the grid arrays and the temperature and precipitation do not fit one another), and the budget errors above, with the part that exceeded named.
- **One structural validation, once, at the integrated boundary** (the stage 6 review): the feature table's consistency (each water cell's feature is water, each lake has a shore, **each lake's first cell belongs to the lake itself (its feature number is the lake's: the first cell is a cell of the lake, not of its shore; the shoreline cells are the surrounding land and are validated separately, and a valid lake is never required to have its first cell in its shoreline)**, each cell's number is in the table, every cell has at most 20 neighbours, the havens are water cells next to their land cell), so the helpers' own guards stay as the last line.

## Stages and checkpoints (what the original lets us observe)

The original is read-only, and its drainage, flow and river-definition steps are **closures inside `generate`**: only `alterHeights()`, `resolveDepressions(h)` and the finished `generate()` can be called and observed. So:

- **7a: `alterHeights` and `resolveDepressions`** (stand-alone checkpoint): the working heights after them (a sha256 of the Float64 values, explicitly little-endian, and whole for small maps), and the lakes' `height`, `closed` afterwards, with `resolveDepressionsSteps` of 250, 40 and 5 and some maps raised to make depressions. **A case that really reaches the bad-progress branch (the parameter reassignment) must be captured, and the fixtures prove it:** fewer iterations do not themselves prove coverage, so the capture script wraps the original's `alterHeights` at run time (a monkeypatch of the loaded object, not an edit of the clone) and counts its calls during `resolveDepressions`, which the original calls only in that branch; each case records whether the branch was reached, the search over maps, raises and step counts continues until cases with it exist, and the tests assert that at least one is present. The forced-closed path (iterations past 0.75 of the steps) is covered the same way with a recorded flag (a lake closed by `resolveDepressions`).
- **7b: the meander geometry** (stand-alone: `meander`, `projectToNearestEdge`, `addMeandering`, `getApproximateLength`, `getSourceWidth`, `getOffset`, `getWidth` are callable): the points of generated paths for river-like cell lists on real packed maps and on synthetic edge cases (a river leaving by the border, a two-cell river, a lake start), compared exactly. **`relaxAcuteAngles` is part of it, with its numerics:** at most 4 passes; it **moves existing points and inserts none**; a pass scores every non-anchor point with a snapshot of the points taken at the pass's start (a flip in a pass does not change the scoring of the points after it) and writes the flips into the points themselves; a flip is taken only when it lowers the three corner scores by more than 1e-6; the corner score is the positive cosine at a vertex and 0 at the ends; the reflection is across the line of the two bounding anchors (unchanged if they coincide); fewer than 3 points are left alone. Its temporary arrays are in the geometry budget above, and the fixtures include cases that flip points, cases that need all 4 passes, cases that converge early, and coincident anchors.
- **7c: drainage, river definition, confluence flux, cleanup and downcut together** through `generate()`'s **end state**, which does expose them: the final `fl`, `r`, `conf` and `h`, `pack.rivers` (source, mouth, discharge, length, width, factors, parent, cells) and the lake fields (flux, outlet, inlets, river, entering flux, height). With `allowErosion` **true and false** (both kept in the fixtures). This checks the closures **jointly**; the plan does not claim an intermediate checkpoint inside them. If a mismatch needs one, it is found by a temporary instrumented copy of the original outside the clone (never by editing the clone).
- **7d: the integrated operation** with its budgets and refusals, in one `PackedRivers.generate(...)`-style call, compared with `generate()` for the whole fixture set. *(Consolidated into 7c, 2026-10-21: see [the 7c page](../steps/water-7c-river-generator.md); no separate code.)*

Randomness: none of this draws from the stream; the next-value checkpoint after `generate()` is recorded to confirm it equals a fresh stream's.

## Not in this stage

Rendering the river paths (`getRiverPath` and the curve generator), naming, types, labels, editing functions, the biomes and everything after the rivers.

## Decisions after the review (2026-10-21)

- The provisional defaults are acceptable **for development measurements, not as recommended production limits**; the policy is explicit, adjustable per field and reported with the observed counts and sizes.
- `resolveDepressionsSteps` is exposed: whole number 1 … 1,000, default 250; zero is unsupported.
- `relaxAcuteAngles` has been read in full; its resources are in the plan above. Territory drawing and realm cleanup do not block the water port.
