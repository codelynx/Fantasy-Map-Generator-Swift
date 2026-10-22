# Realms: a bounded inspection of growth (measurement)

Measured 2026-10-20 with `Tests/FantasyMapCoreTests/RealmInspection.swift`, which asserts nothing and runs only on request (`FMK_MEASURE=1 swift test -c release --filter RealmInspection`). It follows the review of the diagnostic overlay: inspect a bounded selection before designing cleanup, and separate **unavoidable group-size imbalance** from **growth artifacts**. It decides nothing, and **the speck rules are unchanged: they are the author's decision.** The reach is fixed at 25 map units, the growth factors at 3, 8 and 4, the typical realm area at 40,000 map units², and the cap at 500; all provisional.

## What was run

`continents`, `pangea`, `archipelago` and `shattered`; seeds `kaz-1` to `kaz-3` at 10,000 cells, and `kaz-1` at 100,000 cells; four count rules and two unevenness values (0 and 6) with the geography and the seeds held fixed:

- **C:** the minimum, one realm per group.
- **C+4:** a modest increase.
- **global:** the package's automatic count today: at least C, otherwise the total land area over the typical area.
- **perGroup:** *an experiment, not a proposal adopted:* the sum over the groups of max(1, round(group area ÷ typical area)); it is given to the allocation as a chosen count, so the split among groups is the allocation's own (by area), which only approximates a per-group rule.

**Metrics** (medians over the seeds): the largest realm's share of the land area; **tiny realms** (at most 5 cells at 10,000 cells, 50 at 100,000); **realms of at least a quarter of the typical area**; **realms bordered by exactly one other realm** over land adjacency, a proxy for enclaves that also counts legitimate peninsulas and islands; and the **worst dead-end share**, the share of a realm's cells (for realms of over 20 cells) with at most one same-realm land neighbour, a proxy for tendrils that also counts naturally thin land. The proxies are crude and are not verdicts.

## Results

### 10,000 cells (median of 3 seeds)

| Map | Count rule | K | Unevenness | Largest realm's share of land | Tiny realms | Realms of at least a quarter of the typical area | Realms bordered by one other realm | Worst dead-end share |
|---|---|---|---|---|---|---|---|---|
| continents | C | 3 | (any) | 55% | 2 | 2 | 0 | 1.6% |
| continents | C+4 | 7 | 0 | 26% | 2 | 5 | 2 | 5.4% |
| continents | C+4 | 7 | 6 | 37% | 2 | 5 | 4 | 7.9% |
| continents | global | 9 | 0 | 24% | 2 | 7 | 2 | 2.5% |
| continents | global | 9 | 6 | 32% | 2 | 7 | 3 | 3.5% |
| continents | perGroup | 11 | 0 | 22% | 2 | 9 | 1 | 17.9% |
| continents | perGroup | 11 | 6 | 26% | 2 | 8 | 2 | 5.4% |
| pangea | C | 3 | (any) | 99% | 1 | 1 | 0 | 0.4% |
| pangea | C+4 | 7 | 0 | 30% | 1 | 5 | 0 | 1.1% |
| pangea | C+4 | 7 | 6 | 28% | 1 | 5 | 0 | 0.8% |
| pangea | global | 13 | 0 | 12% | 1 | 11 | 1 | 1.7% |
| pangea | global | 13 | 6 | 24% | 1 | 11 | 2 | 2.4% |
| pangea | perGroup | 15 | 0 | 12% | 1 | 13 | 1 | 2.4% |
| pangea | perGroup | 15 | 6 | 18% | 1 | 12 | 3 | 2.4% |
| archipelago | C | 7 | (any) | 65% | 3 | 2 | 0 | 13.0% |
| archipelago | C+4 | 11 | 0 | 25% | 3 | 6 | 4 | 13.0% |
| archipelago | C+4 | 11 | 6 | 36% | 3 | 6 | 3 | 13.0% |
| archipelago | global | 7 | 0 | 65% | 3 | 2 | 0 | 13.0% |
| archipelago | global | 7 | 6 | 65% | 3 | 2 | 0 | 13.0% |
| archipelago | perGroup | 9 | 0 | 40% | 3 | 4 | 4 | 13.0% |
| archipelago | perGroup | 9 | 6 | 40% | 3 | 5 | 4 | 13.0% |
| shattered | C | 9 | (any) | 96% | 6 | 1 | 0 | 6.9% |
| shattered | C+4 | 13 | 0 | 30% | 6 | 5 | 2 | 6.9% |
| shattered | C+4 | 13 | 6 | 32% | 6 | 5 | 3 | 6.9% |
| shattered | global | 9 | 0 | 96% | 6 | 1 | 0 | 6.9% |
| shattered | global | 9 | 6 | 96% | 6 | 1 | 0 | 6.9% |
| shattered | perGroup | 15 | 0 | 30% | 6 | 6 | 2 | 6.9% |
| shattered | perGroup | 15 | 6 | 32% | 6 | 6 | 3 | 6.9% |

### 100,000 cells (one seed)

| Map | Count rule | K | Unevenness | Largest realm's share of land | Tiny realms | Realms of at least a quarter of the typical area | Realms bordered by one other realm | Worst dead-end share |
|---|---|---|---|---|---|---|---|---|
| continents | C | 3 | (any) | 100% | 2 | 1 | 0 | 0.6% |
| continents | C+4 | 7 | 0 | 35% | 2 | 5 | 2 | 2.4% |
| continents | C+4 | 7 | 6 | 39% | 2 | 5 | 3 | 2.5% |
| continents | global | 11 | 0 | 21% | 2 | 8 | 2 | 4.0% |
| continents | global | 11 | 6 | 24% | 2 | 9 | 2 | 2.5% |
| continents | perGroup | 13 | 0 | 19% | 2 | 10 | 2 | 4.0% |
| continents | perGroup | 13 | 6 | 18% | 2 | 11 | 1 | 2.6% |
| pangea | C | 3 | (any) | 93% | 1 | 2 | 0 | 1.1% |
| pangea | C+4 | 7 | 0 | 35% | 1 | 6 | 2 | 1.1% |
| pangea | C+4 | 7 | 6 | 36% | 1 | 6 | 1 | 1.1% |
| pangea | global | 9 | 0 | 24% | 1 | 8 | 1 | 1.1% |
| pangea | global | 9 | 6 | 24% | 1 | 8 | 1 | 1.1% |
| pangea | perGroup | 10 | 0 | 24% | 1 | 8 | 1 | 1.5% |
| pangea | perGroup | 10 | 6 | 24% | 1 | 8 | 3 | 1.6% |
| archipelago | C | 12 | (any) | 41% | 6 | 4 | 0 | 10.1% |
| archipelago | C+4 | 16 | 0 | 17% | 6 | 5 | 6 | 10.1% |
| archipelago | C+4 | 16 | 6 | 17% | 6 | 6 | 6 | 10.1% |
| archipelago | global | 12 | 0 | 41% | 6 | 4 | 0 | 10.1% |
| archipelago | global | 12 | 6 | 41% | 6 | 4 | 0 | 10.1% |
| archipelago | perGroup | 12 | 0 | 41% | 6 | 4 | 0 | 10.1% |
| archipelago | perGroup | 12 | 6 | 41% | 6 | 4 | 0 | 10.1% |
| shattered | C | 8 | (any) | 60% | 5 | 2 | 0 | 18.5% |
| shattered | C+4 | 12 | 0 | 26% | 5 | 6 | 2 | 18.5% |
| shattered | C+4 | 12 | 6 | 25% | 5 | 6 | 0 | 18.5% |
| shattered | global | 8 | 0 | 60% | 5 | 2 | 0 | 18.5% |
| shattered | global | 8 | 6 | 60% | 5 | 2 | 0 | 18.5% |
| shattered | perGroup | 12 | 0 | 26% | 5 | 6 | 2 | 18.5% |
| shattered | perGroup | 12 | 6 | 25% | 5 | 6 | 0 | 18.5% |

## What the numbers say, and do not say

- **Unavoidable imbalance (the rules, not growth):** with K = C, one realm owns most of the land wherever one group dominates: the largest realm held 55% on `continents`, 99% on `pangea`, 65% on `archipelago` and 96% on `shattered` (10,000 cells). Growth cannot even this out because each group is one realm.
- **A modest increase above C already splits it:** C+4 brings the largest share to 25 to 36% on all four maps (26 to 37% on `continents`), at both densities.
- **The automatic count as it is today does not help the island-heavy maps:** `global` gives K = C on `archipelago` and `shattered` (the total area over 40,000 is below C), so the largest realm stays at 65% and 96%. The **per-group experiment** gave K above C there (9 and 15 against 7 and 9) and brought the largest share to 40% and 30%; at 100,000 cells on `archipelago` it also stayed at C (12), so it is not a general fix. **Any such count policy needs its own review**; it does not make the tiny realms disappear.
- **Tiny realms are the groups made of specks and do not depend on the count:** 1 to 6 per map (`shattered` 6 at 10,000 cells, 5 at 100,000), whatever the rule and unevenness. That is the author's question.
- **Unevenness acts as intended, modestly:** raising it from 0 to 6 raised the largest share in most rows (`continents` C+4: 26 to 37%, global: 24 to 32%) and sometimes lowered it (`pangea` C+4), as chance of which realm is fast allows; it cannot affect K = C.
- **Realms bordered by exactly one other realm: 0 to 6 per map, mostly 1 to 4,** which includes peninsulas and island realms; **dead-end shares are small on the large landmasses (0.4 to 5%) and 7 to 18% on `archipelago` and `shattered`,** most likely from the thin shapes of the land there. **These proxies cannot separate growth artifacts from geography,** and **no close-up pictures were made in this pass:** narrow corridors, crossing end points captured by competitors, long tendrils and enclosed realms still need to be looked at one by one before step 4 is designed.
- 100,000-cell results (one seed) follow the same pattern; identical borders across densities are not expected.

## Limits

Three seeds at 10,000 cells and one at 100,000; four templates; one reach, one set of growth factors and one typical area, all provisional; areas are the raw clipped cell polygons; the proxies are crude. The results describe how growth behaves under these values, not what good territories look like.
