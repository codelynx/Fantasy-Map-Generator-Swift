# Plan: Drawing the realms (the territory drawing)

Status: plan, 2026-10-21, border line and wash opacity decided; **built 2026-10-21** ([step page](../steps/drawing-realms-1-wash-and-borders.md)). Design phase: **what is drawn and what the picture promises, not how it is built.** Nothing here is built. The principle for this plan is the author's: **"i respect original where possible"** (2026-10-21), so each choice below starts from what the original does and says where this plan would differ. It follows [the realms design](../design-realms.md), [the realms plan](realms.md) (the realms are made and checked; the demo draws them only as a raw-cell diagnostic) and [the river drawing](drawing-water.md).

## What the original does (read 2026-10-21: `draw-states.ts`, `draw-borders.ts`, `isoline-fills.ts`, `states-generator.ts` `assignColors`, and `public/styles/*.json`, commit `8936c9c`)

- **The fill is a soft colour wash per state,** one path per state from the outline of its cells, at low opacity so the terrain shows (state body opacity 0.2 in `atlas`, 0.1 in `ink`, 0.45 in `watercolor`, 0.4 in `monochrome`). A state's fill also has a **water gap**: where the state meets water a stroke in the state's colour (width 3) is drawn along the shore.
- **A halo** along each state's edge in a darker shade of its colour (`d3 color.darker`), clipped to the state, with a style-set width (5 to 10), opacity and blur.
- **The border line** between two states is its own layer, drawn only along **land-to-land edges between different owners** (a water edge is not a border), traced as a chain of vertices per border. It is **dashed** in every style read, thin to coast-like width, and its colour and opacity are set by the style: `atlas` dark purple width 1 dashes `4 2 0 2`; `ink` black 0.6 `4 1.5 0.6 1.5`; `watercolor` grey-purple 1 at 0.6 opacity dashes `3`; `monochrome` grey 1 `2`; `pale` 0.8 at 0.6 opacity `1 2.5`. The coast in the same styles is 0.1 to 0.7 wide, so the border is **not thinner than the coast; it is told apart by its dashes and colour.** (The original also draws a thinner dotted line for provinces: outside this package.)
- **Colours:** a greedy colouring from six fixed soft colours (d3's Set2) so that **neighbouring states never share a colour**, with the colours rotated as it goes; a state that finds no free colour takes a random one, and a colour used by several states is mixed a little for each repeat.

## What the drawing would be

Following the original, with the land outline kept as the one shape that everything is clipped to (as for the land fill, the ink and the rivers):

- **A soft wash per realm** at a low opacity, clipped to the drawn land outline (smoothed and optionally roughened), so a colour never crosses the sea. The original's per-state **water gap stroke and halo** are carried over as the style allows: a darker edge shade of the realm's colour along its outline, clipped to the realm.
- **A border line between neighbouring realms:** dashed, thin, in a grey by default (the author's idea of a thin grey line, which the `monochrome` and `watercolor` styles also use), **only along edges between land cells of different realms** (never on a coast), traced along the cell edges between two owners and smoothed to follow the same corners as the outline. Its colour, width, opacity and dash pattern are style settings; a plain line is a dash pattern of none.
- **Colours** by the original's rule: neighbouring realms always differ, from a small fixed set of soft colours, with repeats mixed a little. Deterministic for the same realms and seed (the original's random steps become a seeded choice).
- **The realms stay readable with the terrain and the rivers over them;** the wash is translucent, the rivers and the coast ink are drawn above it.
- **The drawing only reads the realms and the map.** The same inputs give the same picture, in the image renderer and the SwiftUI view alike.

## Built, and what changed from this plan (2026-10-21)

- **One partition** for the wash and the borders (land cells plus the water cells beside land, each taking its nearest land neighbour's realm), so a border is exactly where the wash changes colour and it continues through the water cells beside the land to the displayed coast. Interior borders stay raw, as in the original. The text above that says borders run "only along edges between land cells" is superseded: they run along every edge between cells of different realms of the partition.
- **The wash is opaque** (a palette alpha is dropped) and drawn as a group at the wash opacity.
- **Colours are a deterministic adaptation** of the original's (seeded mixing; palette entries, not values, are compared).
- **The halo and the water-gap stroke are not built.**

## What was built, and how it differs from the plan's first wording (2026-10-21, after review)

- **One partition for the wash and the borders** (land cells, and the water cells beside land in their nearest realm's colour), so a border is where the wash changes colour. **Interior borders are raw vertex chains, as in the original; where a border reaches a coast it continues over the water cells beside the land to the displayed coast** (not by a straight extension, which could run through one wash). Nothing is claimed to be smoothed.
- **The wash is opaque by construction** (a palette's alpha is dropped); the wash opacity is the only transparency control.
- **The colour mixing is a deterministic adaptation** (seeded, not the original's random rainbow colour).
- **The halo is deferred;** saving the realm ownership and its presentation comes next.

## Where this plan would differ from the original (to be confirmed, one at a time)

- **Realms, not states:** no provinces, no names, no capitals. A realm is a territory with a number and a colour.
- **The border default is grey,** as the author suggested; the original's default differs by style (dark purple in `atlas`).
- **The realm data itself is not yet saved in the file,** and the realm settings (reach, typical area) are provisional: realm cleanup (step 4) comes first for a saved picture.

## What it does not do

No names or labels, no province lines, no halo blur effects beyond what the style can express, no animation, no editing.

## How it would be tested (what, not how)

Hand-built small maps with two and three realms (the wash stays inside the land outline; the border runs only between two owners and never on a coast; neighbours differ in colour; the border meets the coast where three bodies meet); a realm touching the map edge; one realm only (no border); realms on separate islands (no border between them); identical inputs give identical drawing and pixels; the wash and border are clipped to the land silhouette in both renderers (a whole-map test fill, as for the rivers); work and point budgets. The look is judged by eye in the demo.

## What this plan does not claim

Nothing has been drawn. I have not read how the original traces borders at triple junctions, or how its isolines are simplified and smoothed (`getIsolines`), and this package smooths with its own Chaikin cutting, so a border may not match the original's curve exactly. The size of the work is not estimated.

## Decided (the author, 2026-10-21)

1. **The realm border is a thin grey dashed line,** as recommended, following the original (dashed in every style read) and the author's idea of a thin grey line; the dash pattern is a style setting, so a plain line is possible. It is thinner than the coast ink so the two are not confused.
2. **The wash opacity default is about 0.3** (the middle of the original's 0.1 to 0.45 range), so the terrain and the rivers stay visible; it is a style setting.
