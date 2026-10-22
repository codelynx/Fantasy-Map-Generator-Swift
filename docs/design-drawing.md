# The Drawing Layer: Design for Stages 1 and 2

Status: draft revised after review, 2026-10-20, for the author's approval. Design phase: this says **what** the drawing layer is and does, not how it is built. **Stage 1 is built** ([step page](steps/drawing-1-height-picture.md)); **stage 2a is built** ([step page](steps/drawing-2a-coast-outlines.md)); **2b is built** ([step page](steps/drawing-2b-smoothing-and-aligned-fills.md)); **2c is built, optional and off by default** ([plan](plans/roughening-2c.md), [step 3](steps/drawing-2c-3-integration.md)). Scope and the look are decided in [the drawing plan](plans/drawing-layer.md): stages 1 (a height picture, with image export) and 2 (inked coastlines) come first; stage 3 (the flat inked look in the spirit of the original's default) follows once a first picture has been seen.

## What it is

A second library target in this package (working name `FantasyMapKit`, undecided), separate from the core. **The core never depends on it:** a build of the core target alone must not need the drawing target, and that is to be verified (building or testing the whole package may still build the UI code). A separate package is not needed. The layer takes a `LandMap` and a style and gives a picture: a SwiftUI view for macOS and iOS, and an image.

## What it takes and gives

- **Takes:** a `LandMap` (the cells' polygons, the heights, the features, each cell's distance from the coast) and a `MapStyle`, a small plain value with defaults.
- **Gives:** a view, `FantasyMapView(map, style: ...)`, that fills the space it is given and keeps the map's proportions; and an **image renderer** that makes a bitmap of the same picture, needing no visible view. Intent only, not a fixed interface.
- **The view and the image renderer share their drawing geometry and drawing commands,** so they cannot disagree. The image renderer specifies: its **pixel dimensions** (the caller's width and height in pixels), its **aspect-fit behaviour** (the map is scaled to fit inside the bitmap, keeping its proportions, and centred), its **background** (the style's paper colour fills the whole bitmap, including any margin), and its **stroke-width units** (a stroke width is in map units and scales with the map, so a bitmap at twice the size has strokes twice as wide in pixels).
- **It draws only what the map holds.** It does not change the map and never regenerates anything.

## Stage 1: the height picture (with image export)

- **Land and water come from the height first.** A cell is land if its height is at least 20 and water otherwise, as the rest of the package decides it. The coast distance is not used to decide that.
- **Water is shaded by coastal distance: near to far from the coast, not shallow to deep.** The distance field is a graph distance from the coast (-1 next to land, down to -9), not bathymetry. It is only what `markupGrid` computed: **0 can mean water more than nine steps out, or any water on a map with no land, and a lake's shore marking can leave a positive value on a water cell.** So every water cell gets a defined colour, as a **display policy, not a recovered depth**: -1 to -9 shade from the near-coast colour to the far-water colour; **0 takes the far-water colour (so an all-water map is one flat colour); a positive marker on a water cell takes the near-coast colour,** so there is no unexplained dark patch beside a lake. Lakes read as water in the same way.
- **Land is coloured by height:** lowland to mountain, from 20 to 100.
- **The picture is clipped to the map's rectangle.** Cells on the edge reach past it (the boundary points clip them only roughly), so the view clips them.
- **The colours are chosen for this package,** as a named, replaceable scheme in the style (a short list of colour stops for water and for land).
- **What it shows:** where the land and sea are, how high the land is, how near water is to a coast, and where the lakes are. It says nothing about rivers, climate or realms, which do not exist yet.

## Stage 2: inked coastlines, in three substeps

- **2a, unsmoothed: the coastline as the cells give it.** Internally, cell fills with raw boundary strokes are fine as a diagnostic; the finished 2a result agrees with the compound-outline fill. Substeps 2b and 2c each change how the same outlines look; 2c is separate and optional.
- **The geometry is the grid cells' boundaries,** found from the current cells and their **height-based land/water classification**, not from the feature records. No packed graph is introduced to resemble the original's renderer. **Outlines are compound:** a land body can have **lake holes**, one land mass can be several outer rings, a feature record can cover disconnected land after lake operations, and a retained record can have no cells at all, so the boundaries are not assumed to be one loop per feature. The same processed boundaries are used for fills and ink.
- **Two different things are made from the land–water edges:**
  - **Fill outlines are closed polygons (outer rings and holes).** A land body that meets the map's edge is an open chain of coast inside the rectangle; to fill it, the polygon is closed **along the rectangle's boundary**, and those closing segments are part of the fill's outline, **not coastline**.
  - **Ink strokes follow only the land–water boundaries, and may be open.** **No artificial coastline is drawn along the map frame.** A coast that leaves the map is an open stroke.
- **Fills and ink stay aligned.** Whatever outlines are used for the ink are also used for the land fill, so the coloured silhouette never drifts from its coastline: **in stage 2 the land is drawn clipped to the same (smoothed, and later roughened) outline the ink follows,** with the water behind it. The stage-1 per-cell fill is therefore replaced by "the land's height colours clipped to the land outline" once outlines exist; the stroke is never a diagnostic overlay displaced from the fill.
- **2b, smoothed:** straight cell edges look like a mesh, so each outline is smoothed into a curve. **Decided in 2b: Chaikin corner cutting** (an approximating curve, not a spline through the points): it stays inside the convex hull of each stretch, so it never leaves the map and cannot overshoot, it keeps the ends of an open line, and it is local and cheap. It does not by itself guarantee simple rings, so crossings are tested at every supported round count. **Smoothing or roughening moves the boundary both ways, and both sides need colour:** land that moves into old water takes the colour of the nearest adjacent land cell, and water that moves into old land takes the colour of the nearest adjacent water cell, so no paper shows at a cut convex corner. **The rule chosen in 2b is per cell** (each boundary cell borrows from its nearest neighbour of the other kind), and existing interior colours are kept.
- **2c, roughened (after 2a and 2b have been seen, with an off switch):** a seeded fractal displacement so the coasts look hand-drawn, ported from the original's coastline generator. **The original's pipeline for this is longer than the displacement alone:** a feature's outline (from its packed-graph vertices, not the grid cells this package has) is simplified (a vendored `simplify.js`, tolerance 0.3), clipped to the map, displaced by the fractal (settings such as depth 4, a base amplitude, a roughness field with a calm threshold, a lake multiplier and a `variant`, seeded per feature and keyed to position in units of 1/64), and built into a path joining smooth and jagged spans (B-spline and Catmull-Rom). **Its dependencies (the simplification, the clipping, the curve construction and the packed-graph outlines) must be read before it is stated exactly which technique is ported, and what this package's outlines, which come from the grid, can and cannot reproduce.**
- **Repeatability, stated narrowly:** **identical inputs (the same map and the same style) give the same line.** Beyond that, the original keys its displacement to position but also seeds it with the feature's number; editing the land can renumber features, alter a segment's endpoints or change its orientation. So a stretch of coast stays the same after an edit **only when its seed, endpoints, orientation and settings are unchanged**, and the package does not promise that any local edit leaves every other coast untouched.
- **A ported technique gets the same credit as the other ports:** a header comment naming the original file and version, and the notice already in the acknowledgements.
- **Ink settings in the style:** the line's colour and width, **in map units** (so the picture keeps its proportions at any export size; **pixel-width strokes can be a later, explicit option, and the two conventions are not mixed implicitly**), how smooth, how rough (off, or an amount), and whether lakes are inked more lightly than the sea.

## The style

One plain value with sensible defaults and named starting points. It holds the colour scheme, the ink (colour, width), the smoothing and roughening (off, or an amount) and the paper colour behind the map. A later stage adds symbols and fills to it. Changing a style never changes the map.

## Platforms

SwiftUI first, since one view serves macOS and iOS; thin AppKit and UIKit wrappers only if an app needs them. The image renderer needs no visible view; which drawing system it uses is chosen when it is built, so "no UI dependency" is not promised before that choice.

## How it will be tested

- **Geometry without pictures:** every cell is drawn; every polygon stays inside the map's rectangle after clipping; fill outlines are closed polygons; ink strokes are exactly the land–water boundaries (none along the frame); each closed loop separates land from water; a lake gets its own loop; and the same map and style give the same loops, point for point. Cases: **an all-land map, an all-water map, land crossing the map's edge, and an enclosed lake.**
- **Parity of the ported displacement, where it is ported (2c):** compared with the original's on **identical explicit outlines, seeds and settings**, as the other ports were. **Whole-map SVG parity is not a target:** the original draws packed-feature outlines with simplification and clipping that this land layer does not reproduce.
- **Rendered images judged by eye,** kept as examples; any image comparison in tests is for catching accidental change, not for judging beauty. No claim goes beyond what is seen.
- **Speed:** measured on the default map and on 100,000 cells before any claim about large maps.

## What it will not do yet

Rivers, biomes, realms, names and symbols (they need layers that do not exist); interaction and animation (zoom and drag belong to the app or a later view); and the original's layered SVG styles.

## Open questions

1. The target's final name.
2. **Performance at 100,000 cells:** one `Canvas`, or cell polygons merged into a few paths.
3. **How edge cells are drawn cleanly** when clipped.
4. **How much of the roughening's settings to expose** (an on/off and an amount, or the original's full set), decided at 2c.
5. **The edge-colour extension rule** for land newly exposed by smoothing or roughening, decided in stage 2.

(Settled by review: the ink follows the grid cells' boundaries; image export is in stage 1; strokes are in map units.)

## What this note does not claim

Nothing here has been prototyped. The original's coastline generator was read at the level of its headers, imports and its main functions (outline, simplify, clip, displace, path), not line by line, and nothing has been ported or compared.

**Naming (2026-10-21):** the SwiftUI view was first called `LandMapView`; it is now `FantasyMapView` (it also draws rivers, realms and pins), matching the package's working name. Older step pages use the new name throughout.
