# Drawing stage 2c, step 2: the displacement kernel

Status: done 2026-10-20 (plan: [roughening-2c.md](../plans/roughening-2c.md)). The kernel is ported and compared; it is **not yet used** by the drawing, and is internal to the core target until step 3 adds parameter validation and bounds.

## What was ported

`Sources/FantasyMapCore/Coast/CoastlineKernel.swift`, from the original's `coastline-generator.ts` (commit `8936c9c`): `featureSeed` (`Alea("<seed>_c<id>_<variant>")`, one `next()` times 2³² truncated by `| 0`), `noise` (murmur-style 32-bit mixing; inputs read as `value | 0`), the two-octave `roughness` field (including the `**` power), the recursive `fractalize` of a **closed** polygon (edges with both ends on the border are skipped; the last point joins back to the first), the quantising of segment ends with JavaScript's `Math.round`, and `shape` (the layer that implements `enabled: false` and the calmer lake shore). Not ported: `simplify.js`, `clipPoly`, the SVG path building.

## Evidence

`CoastlineKernelTests` compare with the step-1 fixtures **exactly, with no tolerance**: 144 feature seeds, 180 noise values, 1,200 roughness samples (so the `pow` result is bit-identical to V8's on these inputs), 336 `fractalize` runs (seven outlines, twelve settings, four seeds, including the `origIndices`), 16 `getFeatureShape` runs (bypass, lake shore, feature override) and the original's own local-edit ring. Properties the original's tests expect also pass: repeatable for the same seed and settings; another map seed or variant changes the coast, and returning to variant 0 returns it; a smaller depth gives fewer points; moving one vertex changes well under a quarter of the points; `| 0` wrapping in the noise; no point inserted along a border edge; zero amplitude leaves the outline alone.

**A mutation check found a gap in the first fixtures and it was closed.** Replacing JavaScript's `Math.round` with Swift's default rounding in the quantising still passed, because the first outlines had only positive coordinates (where the two agree). Two outlines whose edge midpoints land exactly on negative halves (×64) were added to the capture; with them, that mutation fails (73 of 336 runs differ) and the correct port passes. A second mutation (one constant of the mixing changed) failed from the start.

## Limits

- Compared on seven outlines, twelve settings and four seeds; a sample, not the whole input space. Exact agreement of `pow` is observed on these inputs, not guaranteed for all.
- The kernel trusts its settings (finite values, a small depth): an unbounded depth would recurse for a very long time. Validation, a depth maximum and an output-point budget come in step 3, before anything is exposed.
- Also fixed in passing: a main-actor warning in `FantasyMapView` from stage 2b (`color` is now `nonisolated`).

## The open-chain path (added after review)

`CoastlineKernel.fractalizeOpen` is this package's own path for a coast that runs from one place to another: the same recursion on **consecutive** pairs only, **both end points kept exactly**, and **no edge from the last point back to the first** (zero or one point is returned unchanged). It has no original to compare with, so it is tested against the closed path itself: for seven outlines, five settings and three seeds (105 cases), every span of the open result between consecutive original vertices is **point-for-point identical** to the closed path's span for the same edge, the open result ends at the last vertex (the closing edge's points are absent), both ends are kept, and the original-index list is right. Also tested: empty, one-point, two-point and coincident-point chains (a zero-length segment is never subdivided, even with `minEdge` 0, so there is no division by zero and no NaN; the original would divide by zero there), and a chain whose first edge runs along the frame (not displaced; the end stays on the frame). A mutation that lets the open path add the closing edge fails the tests.

Step 3 notes from the review, not yet built: derive and check the worst-case output before allocating (closed: n × 2^depth points; open: (n − 1) × 2^depth + 1) with overflow-checked arithmetic and a **drawing-wide** budget (starting at one million points across all outlines); bound the validation work as well (crossing checks are pairwise), by spatial filtering or a budget that falls back to the smoothed result; keep the raw kernel internal and expose only validated roughness settings (nil = off) through a narrow cross-module operation.
