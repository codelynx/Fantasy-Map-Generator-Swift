# Water chain, stage 4: the packed graph

Status: built 2026-10-20 (plan: [water.md](../plans/water.md)). Fourth stage of the faithful port of the original's water chain. It reads the grid after the lake steps and builds the second Voronoi diagram that markupPack and the rivers work on.

## What was built

- **`PackedMap.generate(for:)`** (`Sources/FantasyMapKit/Pack/PackedMap.swift`), a port of `Pack.generate` in `pack-generator.ts` at the pinned original (commit `8936c9c`). For each grid cell in grid order it decides whether the cell has a packed point:
  - **Deep ocean is dropped:** a water cell whose coast distance is neither −1 nor −2 (neither a water cell on the coast nor the next ring out; the lake and shallow-sea cells keep their points).
  - **Inland lake cells are thinned:** a cell at distance −2 is dropped if its grid number is a multiple of 4 or its feature is a lake.
  - **Coasts are split:** a kept coast cell (distance 1 or −1) away from the map border adds the midpoint, rounded to one decimal, with each neighbour that has a **higher** grid number, the same coast distance and a distance of at least the grid spacing.
  The points, the **boundary points of the grid** and the Voronoi port of the land layer give the packed cells and vertices.
- **What a `PackedMap` holds** (the seams into the rest of the chain):
  - `points`, in the original's order (each kept grid cell's own point, then its midpoints);
  - **`gridCell`**, the explicit packed-to-grid mapping (the original's `g`; several packed cells can share one grid cell, and the grid's order is kept, so the list is non-decreasing);
  - `heights`, **a copy** of the grid cells' heights (the original's `Uint8Array.from`): later stages change the packed heights, never the grid's;
  - `areas`, the original's `Uint16Array`: the **absolute shoelace area capped at 65535 and then truncated toward zero** (a value of 65536 is held at 65535 and does not wrap to 0; a not-a-number stores as 0);
  - `voronoi`, the cells (`v`, `c`, `b`, `i`) and vertices (`p`, `v`, `c`) in the triangulation's order, clipped by the grid's boundary points exactly as for the grid.
- **`PackedMap.polygonArea`** is d3-polygon 3.0.1's function with its summation order (`a[1] * b[0] - a[0] * b[1]`, starting from the last point), an empty polygon being 0. `JSNumber.toUInt16` is the new storage conversion.
- **The point-expansion budget.** The packed graph has at most one point per grid cell plus one per coastal neighbour pair (a planar graph has fewer than 3 × cells edges), so under 4 × cells, and in practice far fewer (deep ocean is dropped). The budget is **enforced while the points are added**: the packed points plus the grid's boundary points must stay within `VoronoiDiagram.maximumInputPoints` (400,000, a safety ceiling and not a performance claim), or `PackedMap.Problem.tooManyPoints` is thrown before anything large exists. The original has no such ceiling. At the biggest density step (100,000 cells) the packed graph stays under it (a test).
- **A packed graph with no cell at all** (a map that is all deep ocean) is valid, as in the original: the packed points, the mapping, the heights, the areas and the cell arrays are empty, while the diagram is still built from the boundary points alone and **keeps the original's boundary-derived vertex arrays** (the triangulation of the boundary points still has triangles and vertices).
- **Other refusals:** inconsistent arrays or a feature number without a feature give `invalidInputs`; the Voronoi errors pass through.
- **The climate does not matter here:** the packed graph reads heights, the coast distance field, the features, the neighbours, the border flags and the grid's points, spacing and boundary. In the original it runs after the climate steps, but nothing in between touches those.

## Fixtures and tests

`tools/capture-original-pack.mjs` (wired into `tools/capture-original.sh`) runs the original's own `Grid.generate`, `HeightmapGenerator.generate`, `Features.markupGrid`, the two lake steps and then `Pack.generate`, and records for **98 runs** (the fourteen templates on seven map configurations, from 24 to 10,000 cells) the sizes and a **sha256 of each array** (Float64 for points, Int32 for the rest, so the Swift side recomputes them byte for byte without formatting numbers): the packed points, the parent grid cells, the heights, the areas, the cells' vertices, neighbours and border flags and the vertices' points, neighbours and cells; **28 runs keep every array whole**. **The hashes are written explicitly little-endian in the capture script** (`writeDoubleLE`, `writeInt32LE`), as the Swift side writes them, and not as the machine typed-array storage; recapturing gave the same fixture byte for byte on this machine. The fixtures check: the nine earlier fixtures came out identical.

`PackedMapTests` (12): **all 98 runs equal the original on every array**, and the 28 whole graphs equal cell for cell; the captured runs include a map with **no packed cell at all**, maps with more packed cells than grid cells (coast splitting) and maps with far fewer (deep ocean dropped). Structure checks derived from the map independently: packed cells keep the grid's order, heights and points, a grid cell's first packed cell is at its own point and the others are rounded midpoints with a neighbour; deep water and inland lake cells are absent and every land cell is present; only coast cells away from the border are split. Hand cases for the area (the sign of the shoelace sum, the empty and one-point polygons, a triangle, the cap at 65535 versus 65536, truncation of a fraction, not-a-number), the `Uint16` store, the coast-splitting rule on hand data (the exact-spacing equality, the midpoint rounding, border cells and unlike neighbours), and the budget (a ceiling of exactly the point count is allowed, one fewer is refused).

**Mutation checks** (33, each made and undone): the deep-ocean and lake conditions (each bound, each operator and the `i % 4` rule), the coast types, the border test, the neighbour-order test, the neighbour type test, the distance computation and the spacing, the midpoint rounding and its source cell, the area cap, its sign, its halving, its summation order and start, the empty polygon, and the budget bound and boundary count. **31 were caught at first; one survivor was a gap (below), fixed after the review, and one is equivalent:** `i >= e` in the neighbour-order test (a cell is never its own neighbour, so the two tests are the same); and `dist2 <= spacing2` for `<` was **not** equivalent in general (it survived the fixtures only because they never reach equality, and a loaded map can carry other accepted point arrangements): after the review a hand case pins the original's inclusive admission (a neighbour exactly one spacing away is split, 9.99 is not, 10.01 is), and the mutant is caught.

## Limits

- 98 runs are a sample; exact equality is observed on them, not guaranteed for every input. `pow(x, 2)` (used for the squared distances and the spacing) agreed with V8 on all of them.
- The area's cap at 65535 is not reached in the captured runs (the largest area is 27,163), so it is verified by hand cases and not by the original's output.
- The time and memory of the packed graph at the biggest sizes are not measured here. The 400,000 ceiling is the existing provisional triangulation policy, a resource limit and not evidence that the largest grid always fits or that peak memory is acceptable; the under-4 x cells argument concerns packed cell points, the boundary points are counted separately, and one 100,000-cell test establishes that case and not every template or loaded geometry.

## Notes from the review

- A reverse (grid-to-packed) mapping is deferred until a consumer needs it: packed-to-grid is many-to-one, so a reverse mapping needs lists or ranges and an explicit representation for dropped grid cells, not an assumed one-to-one inverse.
- **Stage 5 contract must say explicitly what it supports and refuses for an empty packed cell set.**
