# Rivers and lakes: Design (just started)

Status: started 2026-10-20 at the author's request ("I am interested in rivers and lakes shaping"). **Superseded in part 2026-10-20:** the author chose a **faithful port of the original's water chain** (temperature, rain, the packed graph, lakes and rivers), see [the port plan](plans/water.md). The "first version, in plain words" section below describes a simpler own rain and own drainage that was set aside before it was committed; the "marks on the map first" decision still stands as the order of drawing. Design phase: this says **what**, not how. Nothing is built. It belongs to layer 2 of [the design](design.md) (water and terrain), which also lists temperature, rain and terrain types.

## What the package already has

The land layer already makes **lakes**: deep-depression lakes and near-sea lakes (opened to the ocean), as the original's land step does, and a feature record for every lake, island and ocean. It has no rain, no temperature, no rivers and no lake outlets or evaporation.

## Background: what the original does (read 2026-10-20, with limits; a history label: this was written while an own approach was still being considered)

Read: `river-generator.ts` (836 lines, the main `generate`, `alterHeights`, `resolveDepressions` and the signatures of the rest), the head of `lakes.ts` (`defineClimateData`, `detectCloseLakes`) and the head of `precipitation-generator.ts`; the original at commit `8936c9c`. **Not read:** the temperature generator, the path-drawing and width functions in detail, the renderers, the naming and the parts after line 507 of the river file. Nothing was run. *(History: when this was written the intention was background only, with parity not assumed; the port plan supersedes that.)*

- **Rain comes first.** Winds enter from the sides and drop humidity as they pass cells (more over hills and mountains, a latitude band multiplier, none in permafrost), filling a precipitation value per grid cell.
- **Water is routed downhill.** Land cells are taken from the highest to the lowest; each adds its rain to a flux, and the flux flows to the lowest neighbour. A cell whose flux reaches a threshold (30) becomes part of a river; two rivers meeting is a confluence, and the one with less flux becomes a tributary. Water that reaches the map border leaves; water that reaches a lake adds to the lake.
- **Depressions are filled first** (a few thousand iterations) so water can flow out of hollows; lakes that sit in deep depressions are "closed" and have no outlet, the others get an outlet at the lowest shore cell if their incoming water exceeds their evaporation (a Penman-style estimate from temperature, height and size).
- **The land is shaped by the rivers:** after routing, cells with flux are lowered ("downcut", at most 5 height units, never on lowlands under 35).
- **Drawing is separate:** a river is a list of cells; its path gets meanders, a width that grows with flux and a smooth outline; lakes get a shoreline.

## Decided so far

- **Marks on the map first (decided 2026-10-20).** The first *drawing* of rivers and lakes is simple: plain lines and filled areas. **This is about the drawing only, not about the generation:** the faithful port changes **the packed heights** (the original raises a working copy to route the water and then downcuts the packed heights along rivers); **the grid heights stay unchanged.** The elaborate drawing (meanders, widths that grow downstream, soft shores) comes later; it is not ruled out.

## History: the own simple version, set aside (kept for the record)

Decided with the author on 2026-10-20: **marks on the map first**, and the author is **not interested in the rain model**, so the simplest is used and can be replaced later.

- **Rain:** a simple rain of our own: the same on every land cell, a little more on higher ground, with **one "wetness" setting** (a drier or wetter world). It is a stand-in; a wind-and-latitude model like the original's could replace it later without changing how rivers are made.
- **Rivers:** water falls on the land and **flows downhill**; where enough water has gathered a river forms, and rivers join into bigger rivers (a smaller one becomes a tributary). A river ends in the sea, in a lake, or at the map's edge. Water never flows uphill: hollows are handled so water can find its way out.
- **Lakes:** the lakes the land layer already makes receive the rivers that run into them. A lake that can drain has an **outlet** and the river **continues from it**; a lake in a closed basin keeps its water and ends the river. **No evaporation and no temperature in the first version.**
- **The land does not change:** no carving of valleys, the heights stay as they are. *(Superseded: the faithful port changes the packed heights by downcutting; the grid heights stay unchanged.)*
- **What the map holds:** for every land cell how much water flows through it, and a list of rivers (their cells from source to mouth, their parent river and where they end), plus the lakes' inflow and outlet. Saved in the map's own JSON as exact state, so a loaded map recomputes nothing, as the land layer does.
- **How it is drawn (first version):** rivers as plain blue lines whose width grows with the water in them, lakes as the water areas they already are, under the coast ink. Meanders, soft shores and names are later.
- **Not in the first version:** carving, meanders, widths that look natural, names, navigability, deltas and estuaries, evaporation, temperature, a wind rain model, editing rivers by hand.

## Questions, still open (the author may leave them to the defaults above)

1. How rivers relate to realms (a river as a natural border).
2. Whether the author wants to edit rivers by hand later.

## What this note does not claim

Nothing here is prototyped. The size, the look and the method are not decided.
