# Realms, step 1: connectivity and reach

Status: built 2026-10-20; review corrections applied (primitive-work budget, budget validation, wording); links extended with their closest boundary points 2026-10-20 (for realms step 3) (plan: [realms.md](../plans/realms.md), design: [design-realms.md](../design-realms.md)). Nothing here grows a realm.

## What was built

- **`RectangleClip`** (`Sources/FantasyMapKit/Geometry/RectangleClip.swift`): the one rectangle clip (a convex polygon against the map's rectangle). The drawing layer's `MapDrawing.clip` now calls it; its existing tests pass unchanged.
- **`LandGroups.find(in:reach:)`** (`Sources/FantasyMapKit/Realms/LandGroups.swift`):
  - **Landmasses:** maximal sets of land cells (height 20 or more) connected through the cell neighbour lists; water and lakes are not land; corner contact does not make one landmass; the frame joins nothing. Numbered by smallest cell index.
  - **Reach** is an explicit finite number of map units, 0 or more (NaN, infinite and negative are refused with `invalidReach`). **Reach 0 disables sea connections.** For a positive reach two landmasses are joined by a **proximity link** when the distance between their raw cell polygons clipped to the rectangle is at most the reach (inclusive); the distance is computed with Double arithmetic. **A positive reach therefore joins corner-touching landmasses (distance 0) and reach 0 does not.**
  - **Groups** are the transitive closure, numbered by smallest cell index; **`minimumRealms`** is their number (0 with no land).
  - **`links`:** a **minimum spanning forest of the landmasses by distance** (Kruskal, ties by smallest cell indices) with the **closest pair of land cells** of each link and its distance, so that growth can use real end points and not group membership alone. **Each link also holds the closest boundary points `pointA` (on the polygon of `cellA`) and `pointB` (on the polygon of `cellB`), so it is a real segment whose length is `distance`.** When several point pairs are equally close the first found in a fixed order (the vertices of A against the edges of B, then the vertices of B against the edges of A, a strictly smaller distance replacing) is kept, so the choice is deterministic. **The segment is not verified here to lie over water;** that is done by realms step 3 before growth, which refuses an unusable one.
  - **The search** cannot miss a pair, as a mathematical argument for this construction under ordinary floating-point arithmetic and the stated geometry assumptions (the brute-force comparisons are the evidence for the implementation): the bounding boxes of the coast cells' polygons are grown by half the reach and put in a hash whose buckets are at least the reach and never below a floor (a quarter of the grid spacing, so a tiny reach cannot make an unbounded number of buckets); two polygons are candidates when their grown boxes overlap, which they must if their distance is within the reach. Reach 0 does no search. Only **coast cells** take part: land cells with a water (or lake) neighbour. (The plan also listed cells touching the rectangle; nothing lies beyond the frame, so they are not coast.) Each pair is distance-tested once, and a polygon with fewer than three points or no area is left out (its landmass stays its own group if it has no other).
  - **Bounds, refused and never approximated:** bucket insertions (5 million), candidate visits (50 million; every visit is charged, including pairs the once-per-pair rule skips), distance computations (10 million) and **primitive point-to-segment evaluations (400 million; one pair of polygons with a and b vertices costs 2 × a × b, counted with overflow-checked arithmetic before the pair's distance is computed)** throw `workBudget`. Float-to-integer conversions are clamped. **The budgets are public, with documented defaults, and are validated first:** a negative budget throws `invalidBudget` even when no search would be needed (zero is a valid policy that refuses any search).
  - **A deviation from the plan:** the plan listed an early exit when everything is one group. It is not there, because the links must be the closest pairs and so need the candidate distances; a very large reach on a very dense map is refused by the bounds instead.

## Tests (`LandGroupsTests`, 17)

Hand-made square cells with exact gaps and a brute-force comparison: polygon distance on known shapes (3, 5, 0 for a shared edge or corner, a zero-length segment); the clip on known polygons; reach 0 against a positive reach; **exactly at a gap joins and just below does not**; a huge reach and a tiny positive reach; a chain of islands with far ends (one group); **corner contact (not one landmass; joined by a positive reach, not by reach 0)**; two landmasses both touching the frame (not joined by it); an island in a lake; no land (C = 0) and all land; numbering by smallest cell; the links as a spanning forest of closest pairs; a degenerate polygon left out; invalid reach and geometry; each bound refused; **the distance work equals exactly the number of distinct candidate pairs** (a budget of that many succeeds, one fewer refuses). **40 random grids at 11 reaches (440 cases)** equal a brute-force comparison of every pair of land cells, with a larger reach never increasing C and each link's end points at the stated distance. On generated maps (five templates, six reaches, 800 cells) the groups equal a brute-force pass, results are deterministic and numbered by smallest cell, and the groups cover all the land.

A pair of **600-vertex polygons** (one candidate pair, 720,000 primitive evaluations) is refused at one fewer than 2 × a × b and accepted at exactly that, and a budget of `Int.max` does not wrap; negative budgets are refused on trivial inputs (all water, reach 0, a real search); zero budgets are valid and refuse a search. Removing the primitive check makes that test fail.

**Checks that the tests catch errors** (each mutation made and undone): an exclusive reach, a candidate-box growth of a quarter instead of a half of the reach, and the once-per-pair rule dropped. The first two fail many tests; the third only costs work and is caught by the exact distance-work test, added because the first version of the suite did not notice it.

## Measured (release, one run, Apple M4 Pro; archipelago template, 1280×800, one seed)

| Cells | Landmasses | Reach 0 | Reach 5 | Reach 20 | Reach 60 |
|---|---|---|---|---|---|
| 10,000 | 39 | 39 groups, 0 ms | 36 groups, 2 ms | 12 groups, 1 ms | 4 groups, 3 ms |
| 100,000 | 114 | 114 groups, 0 ms | 48 groups, 5 ms | 18 groups, 8 ms | 1 group, 46 ms |

One map, one seed: the numbers say how groups shrink as the reach grows on this map, not what a good default is. **The default reach is still deferred;** its choice needs the gaps on all fourteen templates.

## Limits

- **The links are a compact connectivity witness, not a complete catalogue of crossings,** and their cell numbers and distance do not specify a verified over-water segment. Step 3 must decide what end-point geometry and alternative crossings growth actually needs and extend or query the search for it; the forest must not become the only set of crossings growth may use.
- Polygons with fewer than three points or no area are skipped by policy; a landmass with no usable polygon stays its own group (also stated in the public documentation).

- Brute force and the exact-gap tests use the same polygon-distance function; the formula itself is tested only on the known shapes above. The search logic, not the formula, is what the comparisons check.
- A corner contact between landmasses cannot occur in a generic Voronoi diagram (every vertex joins three cells that are pairwise neighbours); the policy is tested on hand-made cells.
- The geometry is the raw clipped cell polygons; the coast drawn on screen can differ.
- A very large reach on a dense map can exceed a bound and be refused; the bounds are first values chosen with the timing above, not tuned.

## Next, as the review said

Measure the gaps between landmasses on the fourteen templates with **several seeds per template**, and report how C changes with the reach, including the effect of tiny islands, before a default reach is chosen; a map-size fraction is a possible default policy, not something single-map timings establish, and the resolved reach stays in map units. Step 2 (count and seeds) can be planned meanwhile with an explicit reach.

## Closest points added (before realms step 3)

`LandGroups.closestPair` returns the distance with the pair of points that gives it (the distance is the same value `polygonDistance` returned before, now computed through it). Tests: known shapes (a corner-to-corner 3-4-5 gap with its two corner points, facing sides with a perpendicular segment, a corner contact as a **zero-length segment** at the shared point, the argument order mirroring the points, determinism); on 440 random hand-made grid cases and on generated maps every link's points lie on the boundaries of the two cells' polygons (within 1e-9) and are **exactly** `distance` apart. Swapping the two points in a link fails about a thousand expectations, and giving the second loop the wrong orientation fails seven (both checked and undone).
