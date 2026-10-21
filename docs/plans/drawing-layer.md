# Plan: The Drawing Layer

Status: started 2026-10-20; the scope is decided and [the design note for stages 1 and 2](../design-drawing.md) is approved. **Stage 1 is built** ([step page](../steps/drawing-1-height-picture.md)); **stage 2a (unsmoothed coast) is built and committed** ([step page](../steps/drawing-2a-coast-outlines.md)); **2b (smoothing, aligned fills) is built and committed** ([step page](../steps/drawing-2b-smoothing-and-aligned-fills.md)); **2c (roughening) is built through integration, optional and off by default** ([plan](roughening-2c.md), [step 3](../steps/drawing-2c-3-integration.md)), awaiting review; stage 3 is not.

## Decided

- **A second library target in the same package,** apart from the core, which never depends on it. It takes a `LandMap` and gives a SwiftUI view; macOS and iOS from one SwiftUI `Canvas`, with thin AppKit and UIKit wrappers only if an app needs them.
- **Scope: all three stages** (the author's choice, 2026-10-20), each usable on its own, in this order:
  1. **A height picture:** every cell filled by a colour for its height, clipped to the map's rectangle (cells on the edge stick out past it).
  2. **Coastlines:** the edges where land meets water, drawn as an inked line, in three substeps: unsmoothed, then smoothed, then (after those have been seen) roughened with the original's seeded fractal technique, with an off switch.
  3. **The flat inked fantasy-map look,** **in the spirit of the original's default look (the author's later decision, below): painted height colours, inked coasts, and little drawn mountains and trees, with symbols and fills drawn for this package.** (An earlier wording of this line said black-and-white manga with screentone; that look was set aside.)

## What the land map already gives it

Each cell's corner points in order (a ready-made polygon), the heights (0 to 100, sea level 20), the features (island, ocean, lake) and each cell's graph distance from the coast.

## Constraints that carry over from the package

- **No borrowed assets.** The original's icons, textures and emblems are not copied; symbols and fills are drawn for this package.
- **Credit** for any ported drawing technique (for example the fractal coastline) goes in the acknowledgements and the file header, as for the other ports.
- **Evidence limits:** geometry can be tested without pictures (every land cell drawn, polygons inside the map after clipping, **fill outlines closed, with holes and several outer rings, while coast strokes may be open and none runs along the frame**, and everything repeatable for identical inputs); a picture can only be judged by eye, and claims stay within what is seen. Speed at 100,000 cells is unmeasured.

## Open

1. ~~The look.~~ **Decided 2026-10-20: close in spirit to the original's default look,** the one the author liked: painted height colours, inked coasts, and little drawn mountains and trees, with the symbols and fills **drawn for this package** (none of the original's icons, textures or emblems is copied). Black-and-white manga and a look of the author's own were set aside for now. Stages 1 and 2 serve every look, so they come first and stage 3 is refined after a first picture has been seen.
2. **Drawing performance** at large cell counts (one `Canvas`, or cell polygons merged into a few paths).
3. **Clipping of edge cells,** and how to draw them cleanly.
5. **The edge-colour extension rule** for land newly exposed when the outline is smoothed or roughened (decided in stage 2).
6. **Settled by the review of the design note:** the ink follows the grid cells' boundaries (no packed graph), outlines are compound (holes and several outer rings), strokes are in map units.
4. ~~Whether to export an image.~~ **Decided in review: image export is in stage 1,** sharing geometry and drawing commands with the view (see the design note for pixel dimensions, aspect-fit, background and stroke units).
