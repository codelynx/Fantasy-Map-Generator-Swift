# Realms, step 2: the count and the seeds

Status: built 2026-10-20; review corrections applied (public-entry validation, exact work preflight) (plan: [realms.md](../plans/realms.md)). Step 1 ([realms-1](realms-1-connectivity.md)) gives the groups. **No growth yet**: this step resolves the count K and places one seed cell per realm.

## What was built (`Sources/FantasyMapCore/Realms/RealmSeeds.swift`)

- **`RealmSeeds.place(in:groups:count:realmSeed:policy:)`**, over the map and its step-1 groups (**the groups must come from `LandGroups.find` for this same map:** they are publicly mutable, so they are **validated structurally before any work, after the policy**: the per-cell arrays have the map's length, every landmass and group index is in range, land and water agree with the map's heights, each landmass belongs to the group its cells say, and the stored cell counts equal the counts of the cells; a failure is `invalidGroups`; the geometric search is not repeated), with `RealmCount` (`.automatic` or `.chosen(K)`) and **`RealmPolicy`**: the explicit, validated inputs **typical realm area** (map units², finite, above 0), **maximum realms**, **sample size** and **work budget**. **There are no hidden placeholder constants;** the defaults of the typical area and the maximum are unsettled, so a caller supplies them (the sample size and work budget have documented resource defaults, 24 and 50 million).
- **Validation, first:** invalid policy; no land (`noLand`); C above the maximum (`minimumAboveMaximum(minimum:maximum:)`, **in both modes, never reduced or widened**); for a chosen K: below 1, **below C (`belowMinimum`, reporting C: incompatible with the reach)**, above the land-cell count, above the maximum. **The supported interval is C … min(land cells, maximum), within the work budget.** **The automatic count was revised the same day (see below): each group gets max(1, round(its area ÷ the typical area)) realms, at most its cell count, and the sum is the count.** No realm is added after a count is accepted.
- **Allocation** (`allocate`): every group first gets one realm; the extra K − C is shared by **capacity-constrained largest remainder**: quotas over the unsaturated groups, any group whose floored quota exceeds its residual capacity (cell count − 1) is saturated and removed and the quotas recomputed, then floors, then the realms still owed one at a time by largest fractional part, ties to the smaller group number, never past a capacity. **A group's weight is the summed area of its land cells' raw polygons clipped to the rectangle** (cell counts only if every area is zero). Double arithmetic, no randomness.
- **Seeds:** per group, a pool of the group's cells; the first seed is a seeded random cell, each next one is the farthest (straight-line map units between cell sites) of a **sample drawn without replacement** from the pool, **ties to the smaller cell index**; a chosen cell leaves the pool at once. The work is **the exact count of candidate-to-seed distance evaluations,** summed before any seed is placed: the k-th seed of a group (k seeds placed, a pool of N − k cells) evaluates min(sample size, N − k) candidates against k seeds, so a shrinking pool is counted as it is. Every product and sum is overflow-checked and the total is bounded by the policy's budget. (The first version used the conservative s × m(m − 1)/2, which refuses some inputs that fit; the review asked for either a documented conservative estimate or the exact count, and the exact count was chosen.) An exhausted pool would be a `poolExhausted` failure, never fewer seeds. One `Alea` stream, in group order, from the map seed and the realm seed.
- **Realm numbers 1 … K** run in group order, then placement order; not renumbered after growth. **Deterministic for identical inputs;** nothing is promised across a changed count, reach or geography.

## Tests (`RealmSeedsTests`, 20)

Validation at every edge (no land, K below 1, K below C reporting C, K = C, K = land cells, above both limits, C above the maximum in both modes with nothing reduced, a reach joining the islands making it supported); the automatic count against the formula and its three bounds; policy validation (even with no land); allocation (sums to K and respects capacity on 300 random cases, the saturation rule with a one-round and a two-round case, ties by group number, fractions, capacity blocking a remainder, zero weights); weights from areas and not from cell counts; seeds distinct, in the right group, counts as allocated, numbering in group order; K = land cells uses every cell once; **a sample of one still never repeats a cell**; identical inputs give identical seeds, other seeds change the result on a nontrivial case only (a one-cell group cannot vary and no test claims otherwise); **equally far candidates tie to the smaller cell index**; the work bound refused before any seed (exactly the counted work succeeds, one fewer refuses); and, on generated maps, seeds are land cells of their own group, deterministic. **The public entry point** is tested with mismatched groups: shorter per-cell arrays (which must not trap), out-of-range and negative indices, land marked as water and water as land, inconsistent stored counts, a wrong group on a landmass, groups of another map with a different number of cells, **consistent groups of another map with the same number of cells (describing different land),** empty groups; the policy is refused first even when the groups are also wrong. **The work preflight** is checked against a shrinking pool: ten realms in ten cells with a sample of 24 cost exactly 165 (the plain formula would say 1,080), and a budget of 165 succeeds while 164 refuses.

**Mutation checks** (each made and undone): no saturation (126 issues), a tie to the larger group (2), understated work (2), and, after tests were added because the first suite missed them, **no pool removal** (5), **a tie to the larger cell** (10), **no policy check at the public entry** (1), **an inexact work count** (1) and **no land/water membership check** (1; the first public-entry tests did not notice it because a relabelled cell also breaks the stored counts, so a case of consistent groups from another map was added). Removing the stored-group-count check changes nothing, because the sum of the landmass counts already catches it: that check is redundant, not a gap.

**Spread (evidence, not a promise):** on an open 16 × 16 land the mean least distance between six seeds over 60 realm seeds was **60.9 with best-candidate sampling against 21.2 for plain random choice.**

## Measured (release, one run, Apple M4 Pro; archipelago template, reach 20)

10,000 cells (C = 12): K 12, 32, 200 in 2 ms each. 100,000 cells (C = 18): K 18, 38, 200 in 9 ms each. One map, one seed, one machine; the maximum count still needs timing evidence of its own at the counts a product will allow, and the defaults of the typical area and the maximum are still to be chosen.

## Limits

- **Determinism includes the policy** (the sample size changes the seeds and the work); it belongs in the generation recipe if reproducible regeneration is supported.
- Seeds are placed by straight-line distance: a heuristic, not evidence that a place is reachable or connected for growth. In a group of several islands two seeds can land on one small island while a large island has none; growth must cover it through the links. Path-distance placement, coast avoidance and mandatory seeds on large islands are deferred until growth shows a concrete need.
- Best-candidate sampling does not guarantee spacing; very small groups or very small K per group may show poor spacing.
- The allocation can give a tiny group one realm and a large group many, as intended; a K close to C leaves little room for the "how uneven" setting (step 3) to matter.
- Any constraint added later (a minimum realm area, spacing) must not silently invalidate a supported count.

## Geography measured

The measurement of land area, landmass counts and C across reaches on the fourteen templates (five seeds each, three densities) is in [realms-geography-2026-10-20.md](realms-geography-2026-10-20.md). It informs, and does not settle, the default reach and the typical realm area.

## Next

Measure, several seeds per template, land area, landmass count and C across explicit reaches (and the effect of tiny islands) to inform the typical realm area and a default reach; the maximum is a resource policy. Then step 3: complete connected growth with the "how uneven" setting.

## The automatic count, revised (2026-10-20, after the diagnostic overlay)

**Why:** the first rule (the total land area over the typical area, at least C) let the groups of specks use up the count meant for large land: on island-heavy maps K came out equal to C, so one group owned most of the land (`shattered`: one realm held 96%). The reviewer proposed a per-group rule and the author chose to change it.

**The rule now:** each group asks for max(1, round(its clipped land area ÷ the typical realm area)) realms, never more than its cells; **the sum is K.** It is at least C by construction, a large landmass gets several realms and a speck keeps one. If the sum exceeds the maximum, K is the maximum and the realms are shared among the groups by area as before (each group keeps one). A chosen count is unchanged. The split among groups is the asked numbers themselves (no longer an area-proportional split of the total).

**Measured** (the inspection selection, reach 25, typical area 40,000 map units², growth factors 3, 8, 4, unevenness 0; 10,000 cells: median of three seeds; 100,000 cells: one seed):

| Cells | Map | Rule | K | C | Largest realm's share | Realms of at least a quarter of the typical area |
|---|---|---|---|---|---|---|
| 10,000 | continents | old | 9 | 3 | 24% | 7 |
| 10,000 | continents | **new** | 11 | 3 | 22% | 9 |
| 10,000 | pangea | old | 13 | 3 | 12% | 11 |
| 10,000 | pangea | **new** | 15 | 3 | 12% | 13 |
| 10,000 | archipelago | old | 7 | 7 | 65% | 2 |
| 10,000 | archipelago | **new** | 9 | 7 | 28% | 4 |
| 10,000 | shattered | old | 9 | 9 | 96% | 1 |
| 10,000 | shattered | **new** | 15 | 9 | 30% | 6 |
| 100,000 | continents | old | 11 | 3 | 21% | 8 |
| 100,000 | continents | **new** | 13 | 3 | 19% | 10 |
| 100,000 | pangea | old | 9 | 3 | 24% | 8 |
| 100,000 | pangea | **new** | 10 | 3 | 19% | 9 |
| 100,000 | archipelago | old | 12 | 12 | 41% | 4 |
| 100,000 | archipelago | **new** | 12 | 12 | 41% | 4 |
| 100,000 | shattered | old | 8 | 8 | 60% | 2 |
| 100,000 | shattered | **new** | 12 | 8 | 35% | 6 |

**What it says, and does not say:** the new rule never lowers K and splits the large group on the island-heavy maps (`shattered` 96% to 30%, `archipelago` 65% to 28% at 10,000 cells); on the maps that already had enough realms it adds a couple. At 100,000 cells `archipelago` did not change (its groups each ask for one realm at this typical area). Tiny realms are unchanged: they are the speck groups. One reach, one typical area and one growth setting, three seeds at 10,000 cells and one at 100,000: not a general result. **Like any count policy this one needs its own review,** and the typical area is still an explicit input with no package default.

**Tests:** a landmass of 11 cells with three one-cell specks asks for four realms and one each (K = 7; the old rule gave 5); two equal landmasses each under one and a half typical areas get one each (the total area would have said three); a very large typical area gives one per group; a group never asks for more than its cells (checked with a maximum high enough that the cell count, not the cap, decides); over the cap, K is the cap and the groups keep one each. Mutation checks (made and undone): the floor at one removed, rounding down, the old total-area rule, the cap ignored, and (after a test was corrected so that the cap did not hide it) the cell cap removed.
