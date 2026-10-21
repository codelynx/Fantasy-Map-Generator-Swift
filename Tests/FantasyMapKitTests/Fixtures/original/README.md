# Fixtures captured from the original

`alea.json` and `grid.json` were produced by `tools/capture-fixtures.mjs` against the original's npm dependencies
(alea 1.0.1, delaunator 5.1.0, robust-predicates 3.0.3; the versions are in each file).

- `alea.json`: the first 20 values of Alea for each seed, including the empty seed, ASCII, digits, non-ASCII, a surrogate
  pair, and a precomposed ("\u00E9") and a decomposed ("e\u0301") "é", with each seed's UTF-16 code units; and a long run for
  one seed (selected outputs across 10,000 calls and the final generator state).
- `grid.json`: for three seeds and sizes, the spacing, the jittered interior points, the boundary points, and
  Delaunator's `triangles`, `halfedges` and `hull`. **The points are re-implemented in the script from the original's
  `grid-generator.ts`, not executed from the original's own code**; the random numbers and the triangulation are the real
  dependencies. This is a small oracle for the port's first three steps, not a substitute for later comparisons against
  the original's own output.

Regenerate with `node tools/capture-fixtures.mjs <clone> Tests/FantasyMapKitTests/Fixtures/original`.

## `grid-original.json` (added with step 2)

Produced by `tools/capture-original-grid.mjs`, which runs **the original's own `Grid.generate`** (see
`tools/original-bundle/README.md`). Six grids: three tiny ones (with the original's own Voronoi cell neighbours, cell
vertices, border flags and vertex points, for step 3), the original's default map (1280 × 800, 10,000 cells asked), and
1,000-cell maps for the precomposed and decomposed "é". Unlike `grid.json`, nothing here is re-implemented. `grid.json`
agrees with it for its three grids and is kept for its Delaunator triangulation.

## `orient2d.json` and the cell hashes (added with step 3)

`orient2d.json` holds 167 `orient2d` results from `robust-predicates` 3.0.3, produced by `tools/capture-fixtures.mjs`: a few
clear-cut and exactly collinear triples and 160 deterministic cases built to be nearly collinear (a point on the line through
the other two, nudged by a few units in the last place, at scales from 1e-4 to 1e8). `grid-original.json` now also holds, for
every grid, a hash of the integer structure of the original's cells and vertices, the vertex count and the first 20 vertex
points, so the large grids' cells can be compared without storing them.

## Added after the review of step 3

`orient2d.json` now also holds `branchCases` (six cases for each of the five return points of `orient2d`, found by running an
instrumented copy of the library's source and checked against the real library), `permutations` (every ordering of one case
per branch), `collinear` (exactly collinear triples in every order) and `convention` (the value for (0,0), (1,0), (0,1), which
is -1). `grid-original.json` now also holds `vertexPointsSha256`, a digest of every vertex coordinate (little-endian IEEE-754
bytes of x then y, in order).

## `heights-original.json` (added with step 4)

Produced by `tools/capture-original-heights.mjs`, which runs **the original's own `HeightmapGenerator`** through its own
`addStep` one step at a time, on grids made by the original's own `Grid.generate`, after the same PRNG reset the original's
`generate` performs (`Math.random = Alea(seed)`). For six runs it holds the step lines, the blob and line powers, and the
complete heights **and the random generator's state** after every step. The wrapper (`tools/capture-original.sh`) bundles the heightmap module with the grid module
and checks both fixtures.


## `coastline-original.json` (added with drawing stage 2c, step 1)

Produced by `tools/capture-original-coastline.mjs`, which runs **the original's own `Coastline`** (`coastline-generator.ts`, at the pinned commit) on explicit inputs; nothing is re-implemented. The wrapper's bundle now also exposes `Coastline`. It holds: `featureSeed` (144 values: eight map seeds including empty, non-ASCII, composed and decomposed "é" and a surrogate pair, six feature ids, three variants), `noises` (180 values of the integer hash for nine seeds and integer tuples including negatives and values beyond 2³¹), `roughness` (1,200 samples of `roughnessAt`, five settings, three seeds), `fractalized` (336 runs of `fractalize` on seven explicit **closed** outlines, twelve named settings and four seeds, with `origIndices`), `shapes` (16 runs of `getFeatureShape`, the layer that implements `enabled: false` and the calmer lake shore, with and without a feature-specific override) and `localEdit` (the original's own test ring of 24 vertices, before and after moving one). Two of the outlines have edge midpoints whose coordinate times 64 is exactly a negative half, so that JavaScript's `Math.round` and Swift's default rounding differ (added after a mutation check showed the first fixtures could not tell them apart). `fractalize` closes its input, last point back to first; `simplify` and the clipping are not exercised because the outlines are supplied. some of the 336 `fractalize` runs add no point (calm settings or seeds), which is expected and kept as cases. Numbers are JSON doubles. Captured twice with identical results (`--check` passes).
