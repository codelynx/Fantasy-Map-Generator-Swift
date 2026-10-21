# Realms (territories): Design

Status: design questions answered 2026-10-20, revised after review, for the author's approval. Design phase: this says **what** realms are and do, not how they are made. Nothing is built. The original's state generator was read in part (see the background section at the end, with what was and was not read), and it is background, not an adopted algorithm. This is layer 3 of [the design](design.md), which already says: a chosen number of realms, each owning a connected area, with borders, simpler than the original's states.

## What the author wants

Territories on the map, as in Azgaar's pictures: each territory has its own soft colour and a **boundary line** between it and its neighbours, drawn differently from the coastline. **Decided 2026-10-20: realms are made automatically** (the package makes the territories from a seed and a count, which is automatic unless the author gives one). Editing them by hand is a later step, not version one.

## What a realm is

- **A set of land cells** owned by exactly one realm; realms do not overlap. **Decided 2026-10-20: every piece of land belongs to a realm** (no unclaimed land, tiny islands included). **Decided 2026-10-20: a realm may span several islands that are near each other,** joined across short stretches of sea, so the author can ask for few realms even on a map of many islands (how near is settled below, as the reach). Without that, every island would need a realm of its own.
- **A number and a seed** drive the result (**decided 2026-10-20, changed by the author the same day: the number of realms is automatic by default, and the author can override it.** The package suggests a count from the map; a count the author gives is used instead. The reach sets the minimum, and a smaller request is reported as incompatible. **Count bounds are validated first** (a map with no land, and a count above the number of land cells, are refused), **and no extra realms are added after a requested count is accepted.** How the automatic count is worked out is a how-phase matter. The map records the requested mode (automatic or chosen) and the **resolved count** as recipe metadata; a loaded map uses its saved ownership and resolved count and never runs a newer automatic-count rule): the same map, the same number of realms and the same seed give the same realms. Changing the realm seed reshuffles the realms and nothing else about the map.
- **Different sizes,** not all equal: some large, some small, as in the original's picture. **Decided 2026-10-20: the author controls this with a single "how uneven" setting,** from roughly even realms to a few big and many small ones; the seed decides which realm is which. The setting is saved with the other generation settings, while the saved ownership stays authoritative on load. Per-realm sizes may be added later; whether that needs a format change depends on the eventual schema. The setting's range and default are how-phase matters.
- **Borders follow natural lines where the map offers them:** coasts and mountain ridges (the heights exist already). **Lakes already exist in the land layer; rivers and detailed hydrology do not.** Whether the existing lake geometry guides realm borders is undecided; rivers cannot guide them until that layer is built, and this is revisited then.
- **Distances and costs use map units rather than cell counts.** Changing the density may change the sampled terrain and the resulting boundaries; identical realm geometry across densities is not promised.
- **Which realm a place belongs to** is shown by colour in the picture, and **the realm number of every land cell is available as data** (decided 2026-10-20), so an app can show it, for example on hover or as its own label. The picture itself carries no text, as the rest of the drawing layer.
- **No more than that in version one:** no names, no capitals as towns, no diplomacy, wars, economies, religions or cultures, no roads. A realm is only a territory with a number and a colour.

## Connectivity, reach and the number of realms

These rules are settled together, because with them short crossings, complete ownership and any requested count cannot always coexist.

- **Connectivity** is by **land adjacency plus permitted sea crossings.** Water gives a permitted connection but is never owned: **every land cell has exactly one owner when realms exist, and water has none.**
- **Reach is a hard limit on one crossing,** a **maximum length of a single sea crossing in map units**, not on the total distance. A chain of nearby islands can therefore connect one realm over a much longer total distance; that is intended and is stated here so it does not surprise anyone.
- **A cost is not a limit.** A penalty for crossing water makes far crossings expensive but still possible. The reach limit must decide which crossings are permitted at all.
- **Islands joined by the permitted crossings form groups.** If the reach produces **C** disconnected groups, complete ownership by connected realms needs **at least C realms.** **A requested count below C is reported as incompatible with the reach.** The package never silently increases the reach, and never hands distant leftover land to some realm to make the count work. **The algorithm must place at least one realm seed in every reach-connected group and claim all of that group's land.** With C groups and a valid count K at least C, no group needs a distant owner, and failing to place and claim is a **generation failure, not permission to leave land unclaimed.** C is a necessary minimum; it is sufficient for connected, non-empty territories only if the algorithm may split groups without extra minimum-area or spacing constraints, and any such later constraint must not silently invalidate a count that is otherwise supported.
- **Decided 2026-10-20: the reach is an author-set limit with a short default.** The default is a short crossing, so by default realms span only nearby islands; a larger value allows farther crossings, and the minimum number of realms C follows from the chosen reach. The default's value is a how-phase matter, and it is expressed in map units, not in cells.

## What a map holds and draws

- **Saved (built 2026-10-21, [step page](steps/realms-4-saving.md)):** for every land cell, which realm owns it, in the map's own JSON, so a loaded map has identical realms and nothing is recomputed. The realm seed, the reach, the "how uneven" setting, the requested count mode and the resolved count are saved with it as generation settings. The file's format version is raised when this lands, and **old files with no realm layer remain a distinct valid state** (a map with no realms), not an error and not a map with one realm.
- **Drawn (an option in the style, off if there are no realms):**
  - **A soft colour wash per realm** that leaves the terrain visible (the colour scheme is replaceable, like the others).
  - **A boundary line between two realms,** distinct from the coastline: a different colour, weight and dash. **No boundary is drawn along the coast or the map frame,** since the coast already has its own ink.
  - **Built 2026-10-21 (see [the step page](steps/drawing-realms-1-wash-and-borders.md)):** the wash and the borders come from one partition (land plus the water cells beside it); interior borders are raw vertex chains as in the original and continue through the water cells beside the land to the displayed coast; the wash is opaque and drawn at one opacity.
  - Fills and boundary lines come from the **same outlines,** as the coast does, so they never drift apart. **A requirement for the drawing plan:** one authoritative territorial partition, with realm boundaries ending at the **final displayed coast** (after smoothing and roughening); smoothing each realm independently would risk gaps and overlaps. **Built 2026-10-21 as one partition** (the realms' cells and the water cells beside the land in their nearest realm): wash and borders both come from it, interior borders are raw vertex chains as in the original, and a border that reaches a coast continues over those water cells to the displayed coast (see [the step page](steps/drawing-realms-1-wash-and-borders.md)); the border is not smoothed like the coast.

## Questions, one at a time (all answered)

1. ~~Should every piece of land belong to a realm?~~ **Yes, decided 2026-10-20.**
2. ~~Can one realm span several islands?~~ **Yes, nearby islands, decided 2026-10-20.**
3. ~~How near is near?~~ **An author-set reach (the longest single sea crossing), short by default, decided 2026-10-20.**
4. ~~How can the author influence the sizes of the realms?~~ **A single "how uneven" setting, decided 2026-10-20.**
5. ~~Who chooses the number of realms?~~ **Automatic by default, with the author able to override, decided 2026-10-20 (first answered "the author, with a default", then changed by the author).**
6. ~~How does the author see which realm a place belongs to?~~ **Colour in the picture, the realm number available as data, decided 2026-10-20.**

All the design questions are answered. What remains is the how-phase: the algorithm plan, **starting with a pure connectivity-and-reach operation before any growth** (specify the crossing end points, how the length of a crossing is measured and whether a crossing must stay over water; return the groups and the minimum C deterministically; test isolated islands, island chains, zero reach, exact reach boundaries and all-water maps), then seed allocation across groups, complete connected growth, size variation, the automatic count and connectivity-preserving cleanup, the saved-format change, the drawing plan for one authoritative partition, and tests.

## Background: what the original does for its states

Read 2026-10-20 from `src/generators/states-generator.ts` (1,441 lines; the original at commit `8936c9c`): `createStates`, `expandStates`, `normalize`, the cost helpers and the start of `recreate`. **Not read:** how towns are placed, the defaults of the size-variety and growth options, provinces, diplomacy, campaigns and the rest of the file. Nothing was run. This is background, **not an adopted algorithm**; whatever this package does is its own, inspired by the original, and will not aim at parity.

- One state per **capital town**, chosen by population times a random number with a minimum spacing between capitals; state 0 is "Neutrals", unclaimed. Each state has an **expansionism** of 1 plus a random amount up to a size-variety setting.
- **Growth:** all states grow at once from their capitals over neighbouring cells, always taking the cheapest next step; a cell goes to the state that reaches it most cheaply; growth stops beyond a cost limit; only land is assigned. A step costs 10 plus the cell's cost divided by the state's expansionism. The cell's cost adds a culture term (−9 for the state's own culture, +100 for another), a **population term** (`max(20 − suitability, 0)` on suitable land and 5000 on unsuitable land), a biome-mismatch term, a height term (sea 1000, hills from 44 cost 300, mountains from 67 cost 2200, with exceptions by culture type, for example 300 at sea for naval and 10000 for nomadic), a river-crossing term (20 to 100 by flux) and a coast/land-level term.
- **Clean-up (`normalize`):** a land cell that is not a town, not beside a capital and not in a locked state, with at least two foreign neighbours, at most two of its own, and **more foreign neighbours than own**, takes the first foreign neighbour's state.
- It depends on layers this package lacks (towns, cultures, biomes, population suitability, rivers), and land the growth never reaches stays unclaimed, which differs from the decision here that all land is claimed.

## What this note does not claim

Nothing here is prototyped. The size, the look and the method are not decided; the original's picture is a guide, not a specification. No code, saved format change or drawing change has been made.
