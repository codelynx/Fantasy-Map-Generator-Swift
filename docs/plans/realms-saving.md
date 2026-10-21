# Plan: Saving the realms

Status: plan, 2026-10-21, colours-saved decision taken; **built 2026-10-21** ([step page](../steps/realms-4-saving.md)). Design phase: **what is saved and what loading promises, not how it is coded.** Nothing here is built. It follows [the realms design](../design-realms.md) (which decided that the realm of every land cell is saved in the map's own JSON, that old files with no realm layer stay valid, and that the format version is raised), [the realms plan](realms.md), [the realm drawing](drawing-realms.md) and [the water saving](water-8-saving.md), whose rules it keeps: the exact state is saved, loading recomputes nothing and never re-runs a generation step, and loading validates and bounds its work before it enumerates anything. The review of 2026-10-21 asked for this next, before a picture can be called a saved realm picture: the demo's seed and settings do not preserve exact ownership across algorithm changes.

## What it promises

A map saved with realms loads with **identical** realms: the same owner for every cell, the same realm records, the same recipe, and saving it again gives the same bytes (in the tested environment). Loading does not group the land, place seeds or grow the realms again. A map saved without realms loads as a map with no realms: **a distinct valid state, not an error and not a map with one realm**, as the design decided. A realm picture reopens with the colours it was saved with (below).

## What is saved (the realm data)

| Part | Saved | Why |
|---|---|---|
| Owner | for every cell its realm number (1 to K for land, 0 for water) | the exact territorial partition |
| Realm records | per realm: number, group, seed cell, cell count, area | what `RealmOwnership` holds beyond the owner array |
| Colours | one resolved colour per realm (a few bytes each), kept apart from the owner data | **decided 2026-10-21:** a map opened again shows the same colours it was saved with |
| Recipe | the realm seed, the reach, the count mode (automatic or chosen) and the resolved count, the realm policy (typical area, maximum realms) and the growth policy (hill, mountain and crossing factors, unevenness) | how they were made (provenance, shown and kept; **never used to regenerate on load**) |

**Not saved:** the land groups and links (derived from the land and the reach, and only needed to check or regrow), the seeds' sampling work, and the resource budgets (they only refuse work).

## Where it lives

**Inside the land map's own file, as an optional realm layer** (the design's decision), so a water map, which already embeds the land map, carries the realms with it and there is one place that holds them. The land format version is raised; **files at the old version stay readable and load as a map with no realms**, and the fixed revision-1 fixtures keep loading.

## What loading refuses

Everything the land file already refuses, plus for a realm layer: an owner array that is not one value per cell; a water cell with a realm or a land cell with none; a realm number outside 1 to K or realms not numbered 1, 2, 3 in order; a realm record whose cell count is not the number of cells carrying its number, whose seed cell is not owned by it, or whose area is not the area of its cells' polygons; a realm with no cell; and non-finite numbers. **Connectivity:** realms are built connected over land and the permitted sea crossings; a loaded map is checked against the same rule by finding the groups again from the land and the saved reach (a validation, not a regeneration), and a realm that is not connected is refused. The recipe's values are range-checked like the generator's own settings.

## Presentation (decided 2026-10-21)

**The resolved realm colours are saved with the realms** (the author's decision): a map that is read and opened again must show the colours it had, since colours that change between a save and an open would be confusing, so the colour a realm has is persistent and belongs to the saved map. They are kept apart from the owner data so that exact ownership and presentation can be told apart, and a later "reassign colours" action changes only them. **Everything else about the picture stays in the style and is not saved:** the wash opacity, the border colour, width and dashes, and the palette the colours were first drawn from (an app may choose them). A loaded map with realms and colours draws with the saved colours; a map with realms and no saved colours (a file made before colours were saved, or one that never had them) takes the colours the drawing derives, as today. Loading refuses a colour that is not finite or outside 0 to 1, and a colour list that is not one per realm.

## How it would be tested (what, not how)

Round trips on maps with realms (all templates; automatic and chosen counts; several unevenness settings): the loaded ownership and records equal the saved ones, saving again gives the same bytes, and the loaded realms equal realms grown again from the saved recipe; an old file loads with no realms and saves back unchanged; each refusal above has a test; the fixed revision files stay readable; mutation checks as before; file size and time measured at 10,000 and 100,000 cells.

## After review (2026-10-21)

- **Connectivity is verified, and bounded:** the links that connectivity may use are verified as over-water crossings by growth's own verification with an explicit budget, and the ownership check is linear in the cells, neighbours and links whatever the number of realms.
- **The recipe's count cap is checked** (the resolved count does not pass the maximum number of realms).
- **Saved colours are used on their own** whatever the style's palette; the palette is asked only to derive colours.
- **A layer without saved colours** is shown as derived and possibly revision-dependent; an explicit "save current colours" action (never a rewrite on open) is a later step.
- **A saved map is data, not the whole picture;** a saved presentation preset would be a separate versioned feature.

## Not in this stage

Realm cleanup (step 4), editing realms, names, the halo, and any change to the drawing.

## Decided (the author, 2026-10-21)

1. **The resolved realm colours are saved with the realms,** so a map opened again keeps its colours; the style's opacity, border and palette are not saved.
