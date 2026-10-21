# Plan: Drawing the water (rivers first)

Status: plan, 2026-10-21, trimming decision taken; **stage 1 (rivers) built 2026-10-21** ([step page](../steps/drawing-water-1-rivers.md)). Design phase: **what is drawn and what the picture promises, not how it is built.** Nothing here is built. It follows [the drawing design](../design-drawing.md) (stages 1 and 2 are built for the land) and [the water plan](water.md) (stages 1 to 8 are built). It is the "drawing" stage 9 of the water plan, in its first, plain form.

## What the original does (read 2026-10-21, `src/renderers/draw-rivers.ts`, `river-generator.ts` and `components/layers.ts` at commit `8936c9c`)

- **A river is a filled shape, not a stroked line.** For each river it meanders the cells' points (`addMeandering`, which the core already has), then builds a **closed polygon**: for each point it offsets left and right by the river's width there (`getOffset`: the width grows with the point's index along the river and with the flux there, scaled by the river's width factor, starting from its source width), joins the two sides with a Catmull-Rom curve (alpha 0.1), and fills it. There is no outline stroke of its own; the colour comes from the style.
- **The river's cell list ends one cell past the mouth:** in the sea or a lake cell, or `-1` for the map edge, which is projected to the nearest edge. The meandering is damped over water cells (a quarter as much). So **a river always ends at a water point and always reaches the water, by construction.**
- **No clipping and no extension.** The original draws each river exactly as generated, on top of the land and water, in a layer above the height picture and the lakes. The packed graph's coast and the drawn coast are the same coast there, so it needs neither.
- **Not read:** the satellite and erosion renderers, which draw rivers another way.

## What it adds

On top of the land picture that exists (height colours clipped to the inked, smoothed and roughened coast), the first water drawing adds **rivers**, drawn from a `WaterMap`:

- **Each river is a filled shape, as in the original,** from its source to the sea or a lake, **wider from source to mouth** by the river's own measures (source width, width factor, and the flux at each point), in map units so the picture keeps its proportions at any size. The curve through the offset points is the original's Catmull-Rom (a port of d3-shape's, with its notice in the acknowledgements).
- **A river follows the generator's meandering path,** which the drawing regenerates from the river's cells and the saved flux and final heights; the path is not saved.
- **Style settings:** whether rivers are drawn, their fill colour, and one overall width scale, in the style beside the coast settings, with defaults. An outline of the river in the coast's ink is an option for the manga look and is not in the original.

**Lakes are not drawn again.** The land picture already shows an enclosed water body as water inside the land outline. The water map's lakes (finer shapes from the packed graph) are not drawn on top, because two slightly different lake shapes in one picture would look wrong. The packed lakes' climate (flux, evaporation) is data, not a drawing.

## What the demo shows

`FantasyMapDemo` gets a **water switch**: off shows today's picture, on builds the water map from the current land map in the background and draws the rivers. A new seed or template rebuilds it. (The author launches the app; the demo is only a way to look.)

## Promises

- **The drawing only reads the map.** It never changes a water map and never regenerates the water chain.
- **The view and the image renderer share their drawing commands**, as for the land, so they cannot disagree.
- **Identical inputs (the same water map and style) give the same picture.**
- **A river that the generator dropped (fewer than three cells) is not drawn,** and a river whose path leaves by the map border ends at the border.
- **Hard cases are bounded:** a map with no rivers draws as the land picture; a very large map draws its rivers within a stated work and point budget, refusing rather than hanging.

## What it does not do

No river labels or names, no river type (stream, creek), no biomes or rain shading, no lake outlines of its own, no bridges, no animation, no editing. It does not decide the realm borders and does not use the rivers for them.

## How it would be tested (what, not how)

Hand-built small maps with a known river (its drawn line starts at the source and ends at the water edge; widths grow along it); a map with no river; a river leaving by the border; rivers meeting (a tributary joins its parent); a lake with an inlet and outlet; identical output for identical inputs; the work and point budgets; the same picture from the view and the image renderer. The look itself is judged by eye in the demo, and nothing here claims a river looks right beyond that.

## What this plan does not claim

The meandering path was generated for the original's SVG renderer; whether it looks good in this ink style is not known and will be judged from the demo. The size of the work has not been estimated, and no timing has been measured for drawing rivers.

## Decided (the author, 2026-10-21)

1. **A river is trimmed to the drawn land and extended to the drawn coast,** chosen after reading what the original does (it draws each river as generated and neither trims nor extends; see above). So every river visibly reaches the sea or a lake of the picture and never runs over it. The rule is one rule for every kind of water:
   - **The sea and lakes alike are "the drawn water":** the water outside the land outline, and the water holes inside it. A river that ends short of the drawn water is extended along its last direction to meet it; a river that runs into it is cut where it enters.
   - **The map edge:** a river that leaves by the map border ends at the border, as the generator says; the frame is not coast.
   - **The trimming uses the same outline the land fill and the ink use,** so a river meets the same coast the eye sees, after smoothing and roughening.
   - **A river that ends on land at a confluence is not extended** (only a river whose last cell is water is), or it would grow a branch beyond the junction. **The finished river fill is clipped to the same land outline,** not only its centre line, since the widened shape can reach past it.
   - **Not decided here (how, for the build):** how the extension and the cut are made, what happens to a river whose whole path lies in drawn water, and how the width at the cut is chosen. A river that is entirely in drawn water is not drawn.
   - **What the original's way would have given** (draw as generated, ending in the water cell) stays a possible fallback if the trimmed rivers look wrong in the demo; it is not planned.
