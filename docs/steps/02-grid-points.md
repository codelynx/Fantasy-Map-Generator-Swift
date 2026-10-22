# Step 2: The Grid Points

Built 2026-10-20, as step 2 of [the land plan](../plans/land-layer.md).

## What it does

`GridPoints.generate(seed:width:height:cellsDesired:)` (`Sources/FantasyMapCore/Land/GridPoints.swift`) makes the first stage of the land, as the original's `Grid.generate` does before it builds the cells:

1. **Spacing:** `rn(sqrt(width × height / cellsDesired), 2)`, with the original's rounding.
2. **Boundary points:** pseudo-points along the map edge, outside it by `|offset|` map units, where the offset is `rn(-spacing)`, the spacing rounded to a whole number (so "one spacing outside" only approximately). They clip the outer cells and get no cells of their own, and use no random numbers.
3. **Cell points:** a square grid of points, each shifted within its square by up to 90 % of half the spacing. The generator is seeded from the seed first (`Alea`, step 1), and the jitter draws **two values per point, x then y, in row order**; nothing else draws. The rows and columns are walked by repeated addition, as in the original, so the floating-point values are the same.
4. **Cells across and down:** `floor((size + 0.5 × spacing − 1e-10) / spacing)`.

The count of points made is close to, not equal to, the cells asked for.

**Input is checked before anything is allocated or looped over** (added after review): a non-finite or non-positive size or cell count throws; so does a **spacing that is zero, not finite or not representable** (a tiny map with a huge cell count; finite dimensions whose area overflows or underflows), because a zero spacing would make the loops run forever; so does an estimate of more than `GridPoints.maximumPoints` (200,000, twice the original's largest density step) cell points or boundary points, estimated in floating point from the size and spacing before any array exists. **The ceiling is provisional, applies to the cell points and the boundary points separately (it does not bound their combined triangulation input; step 3 budgets that and its working arrays), and is not a performance claim.** **The estimate is conservative:** it can refuse a map whose actual count would just fit (1000 × 1000 with 198,500 cells asked makes 198,916 points but is refused, and a test shows it), so `tooManyPoints` is not proof that the actual count exceeds the limit; a final cap while points are appended backs it up; and so does a map with **no room for any cell point** (for example 1000 by 1 with a coarse spacing). `GridPoints` is therefore never empty. A caller may impose a smaller limit; the triangulation's own minimums are step 3's. The arithmetic for ordinary inputs is unchanged, so parity is preserved.

**JavaScript rounding.** The original's `rn` uses `Math.round`, which rounds halves toward positive infinity (so −2.5 gives −2), unlike Swift's default rounding (−3). The port has `JSNumber.round` and `JSNumber.rn`, and tests the difference, including `0.49999999999999994`, where the common `floor(x + 0.5)` shortcut would be wrong.

## How it is tested

- **Against the original's own code.** `tools/capture-original-grid.mjs` runs the original's `Grid.generate` itself (bundled once with the original's own bundler and run in Node with the browser globals stubbed; see `tools/original-bundle/README.md`) and saves what it returns. Eight grids are compared **exactly** (spacing, cells across and down, boundary points, and every cell point): three tiny grids (seeds `kaz-1`, the empty seed and `日本語`), **the original's default map (1280 × 800, 10,000 cells asked, 9,954 points made)**, a 1,000-cell map for each of the precomposed and decomposed "é", and **two odd aspect ratios** (1000 × 90 and 90 × 1000, 300 cells). All match.
- **The earlier transcription fixture.** `grid.json` (a re-implementation in a script) is now cross-checked against the original's own run for its three grids, and agrees. It stays as the source of the Delaunator triangulation for step 3.
- **Properties:** points inside the map, the same seed gives the same points, a different seed does not, the count is near the cells asked for, tiny and narrow maps work, bad input is refused.
- **Resource and input limits:** unusable spacing, overflow and underflow, counts far above or just above the budget, the original's largest density step (100,000 cells, which fits), and a map with no room for a point, all tested.
- **Optimised build:** the same tests pass in a release build.

## What it does not show

Eight grids match; this is **exact agreement for the captured inputs and the dependency versions in `Fixtures/original/provenance.json`, not universal grid parity**. The Voronoi cells, which the same `Grid.generate` also makes, are not built yet; the original's own cells and vertices for the three tiny grids are already in `grid-original.json` as the oracle for step 3.
