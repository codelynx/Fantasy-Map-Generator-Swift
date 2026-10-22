# Realms: the geography of the fourteen templates (measurement)

Measured 2026-10-20 with `Tests/FantasyMapCoreTests/GeographyMeasurement.swift`, which asserts nothing and runs only on request (`FMK_MEASURE=1 swift test -c release --filter GeographyMeasurement`; `FMK_CELLS` sets the cell count). It informs the **default reach** and the **typical realm area** for the realms layer ([plan](../plans/realms.md)); it **decides neither**, and the review asked that defaults stay provisional until growth (step 3) has been tried.

## What was measured

Every one of the fourteen templates, seeds `kaz-1` to `kaz-5`, a **1280 × 800** map, **10,000 cells** (the spacing between cell points is about 10 map units); then, for the density check, the same at 3,000 and 30,000 cells. For each map: the land area (summed clipped cell polygons) as a share of the map, the number of landmasses, the number of **tiny** landmasses (at most 5 cells at 10,000 cells, scaled with the cell count in the density run; an arbitrary threshold), and the number of groups **C** at explicit reaches of 0, 4, 8, 20, 40 and 80 map units (0, about 0.4, 0.8, 2, 4 and 8 cell spacings at 10,000 cells; 0.5% to 10% of the shorter side). Cells are medians over the five seeds, with the range in brackets.

## Land share, landmasses and C by reach (10,000 cells)

| Template | Land % of map | Landmasses | Tiny (≤5 cells) | C @0 | C @4 | C @8 | C @20 | C @40 | C @80 |
|---|---|---|---|---|---|---|---|---|---|
| volcano | 27.8928 (21.5102–29.4704) | 7 (4–8) | 5 (3–7) | 7 (4–8) | 6 (2–8) | 4 (1–5) | 1 (1–3) | 1 (1–2) | 1 (1–1) |
| highIsland | 32.9225 (29.0729–34.5034) | 6 (5–19) | 4 (3–14) | 6 (5–19) | 6 (3–15) | 5 (1–12) | 2 (1–7) | 1 (1–3) | 1 (1–2) |
| lowIsland | 31.1284 (24.2766–33.586) | 12 (3–21) | 11 (2–19) | 12 (3–21) | 10 (3–17) | 8 (2–8) | 2 (1–6) | 1 (1–3) | 1 (1–1) |
| continents | 36.0985 (30.7703–40.1586) | 12 (9–19) | 7 (4–13) | 12 (9–19) | 8 (6–17) | 7 (5–15) | 4 (3–8) | 2 (1–5) | 1 (1–2) |
| archipelago | 19.8205 (16.3335–23.8166) | 23 (15–39) | 11 (11–29) | 23 (15–39) | 22 (14–37) | 15 (11–28) | 9 (6–12) | 5 (4–7) | 2 (1–3) |
| atoll | 6.50039 (4.00957–8.97373) | 3 (2–5) | 1 (0–3) | 3 (2–5) | 2 (2–5) | 2 (2–3) | 2 (2–2) | 2 (2–2) | 1 (1–2) |
| mediterranean | 58.9054 (47.5566–62.3198) | 11 (10–28) | 7 (7–18) | 11 (10–28) | 6 (6–22) | 4 (3–12) | 2 (1–9) | 1 (1–7) | 1 (1–2) |
| peninsula | 29.3054 (24.2809–32.1716) | 11 (7–18) | 7 (3–10) | 11 (7–18) | 10 (6–18) | 10 (6–15) | 6 (5–14) | 5 (4–9) | 3 (1–6) |
| pangea | 51.0276 (41.4341–57.8831) | 8 (6–15) | 6 (5–10) | 8 (6–15) | 6 (4–14) | 5 (3–12) | 3 (3–8) | 1 (1–4) | 1 (1–2) |
| isthmus | 54.4244 (53.2892–65.6334) | 14 (4–19) | 10 (2–15) | 14 (4–19) | 8 (4–12) | 5 (4–10) | 3 (1–5) | 2 (1–2) | 1 (1–1) |
| shattered | 25.3012 (19.5328–26.7911) | 41 (33–57) | 31 (24–47) | 41 (33–57) | 30 (23–41) | 18 (10–30) | 9 (5–17) | 4 (3–7) | 1 (1–3) |
| taklamakan | 87.7794 (74.4956–93.7727) | 6 (4–8) | 4 (3–7) | 6 (4–8) | 5 (3–7) | 4 (1–5) | 2 (1–3) | 1 (1–2) | 1 (1–2) |
| oldWorld | 46.0155 (35.1394–51.1156) | 11 (5–12) | 7 (2–9) | 11 (5–12) | 8 (5–10) | 5 (2–7) | 4 (1–4) | 1 (1–3) | 1 (1–2) |
| fractious | 58.4683 (57.398–68.6449) | 73 (43–105) | 60 (36–93) | 73 (43–105) | 52 (26–70) | 27 (15–42) | 2 (1–8) | 1 (1–1) | 1 (1–1) |

## Groups made only of tiny landmasses (median)

A group counts as tiny-only when all its land is at most 5 cells. These are the realms C forces for specks.

| Template | tiny-only groups @0 | @4 | @8 | @20 | @40 | @80 |
|---|---|---|---|---|---|---|
| volcano | 5 | 4 | 3 | 0 | 0 | 0 |
| highIsland | 4 | 4 | 4 | 1 | 0 | 0 |
| lowIsland | 11 | 8 | 6 | 1 | 0 | 0 |
| continents | 7 | 5 | 5 | 2 | 0 | 0 |
| archipelago | 11 | 10 | 7 | 3 | 2 | 0 |
| atoll | 1 | 0 | 0 | 0 | 0 | 0 |
| mediterranean | 7 | 5 | 2 | 0 | 0 | 0 |
| peninsula | 7 | 6 | 6 | 3 | 2 | 0 |
| pangea | 6 | 4 | 4 | 2 | 0 | 0 |
| isthmus | 10 | 5 | 2 | 1 | 0 | 0 |
| shattered | 31 | 19 | 12 | 4 | 2 | 0 |
| taklamakan | 4 | 4 | 2 | 0 | 0 | 0 |
| oldWorld | 7 | 4 | 2 | 1 | 0 | 0 |
| fractious | 60 | 42 | 23 | 1 | 0 | 0 |

## The automatic count at three typical realm areas (10,000 cells)

K is the land area divided by the typical area, rounded (median and range over five seeds), and "forced" is how many of the five seeds have C at reach 20 above that K, so that the minimum, not the area, decides the count.

| Template | K = area/20,000 | K = area/40,000 | K = area/80,000 |
|---|---|---|---|
| volcano | 14 (11–15) / forced 0 of 5 | 7 (6–8) / forced 0 of 5 | 4 (3–4) / forced 0 of 5 |
| highIsland | 17 (15–18) / forced 0 of 5 | 8 (7–9) / forced 0 of 5 | 4 (4–4) / forced 1 of 5 |
| lowIsland | 16 (12–17) / forced 0 of 5 | 8 (6–9) / forced 0 of 5 | 4 (3–4) / forced 1 of 5 |
| continents | 18 (16–21) / forced 0 of 5 | 9 (8–10) / forced 0 of 5 | 5 (4–5) / forced 2 of 5 |
| archipelago | 10 (8–12) / forced 1 of 5 | 5 (4–6) / forced 5 of 5 | 3 (2–3) / forced 5 of 5 |
| atoll | 3 (2–5) / forced 0 of 5 | 2 (1–2) / forced 1 of 5 | 1 (1–1) / forced 5 of 5 |
| mediterranean | 30 (24–32) / forced 0 of 5 | 15 (12–16) / forced 0 of 5 | 8 (6–8) / forced 1 of 5 |
| peninsula | 15 (12–16) / forced 1 of 5 | 8 (6–8) / forced 1 of 5 | 4 (3–4) / forced 5 of 5 |
| pangea | 26 (21–30) / forced 0 of 5 | 13 (11–15) / forced 0 of 5 | 7 (5–7) / forced 1 of 5 |
| isthmus | 28 (27–34) / forced 0 of 5 | 14 (14–17) / forced 0 of 5 | 7 (7–8) / forced 0 of 5 |
| shattered | 13 (10–14) / forced 1 of 5 | 6 (5–7) / forced 3 of 5 | 3 (3–3) / forced 5 of 5 |
| taklamakan | 45 (38–48) / forced 0 of 5 | 22 (19–24) / forced 0 of 5 | 11 (10–12) / forced 0 of 5 |
| oldWorld | 24 (18–26) / forced 0 of 5 | 12 (9–13) / forced 0 of 5 | 6 (4–7) / forced 0 of 5 |
| fractious | 30 (29–35) / forced 0 of 5 | 15 (15–18) / forced 0 of 5 | 7 (7–9) / forced 1 of 5 |

## How it changes with the cell count (median over five seeds)

| Template | C @20: 3k / 10k / 30k cells | C @40: 3k / 10k / 30k | Landmasses @0: 3k / 10k / 30k |
|---|---|---|---|
| volcano | 1 / 1 / 3 | 1 / 1 / 1 | 1 / 7 / 22 |
| highIsland | 1 / 2 / 2 | 1 / 1 / 1 | 2 / 6 / 20 |
| lowIsland | 1 / 2 / 3 | 1 / 1 / 1 | 1 / 12 / 30 |
| continents | 2 / 4 / 3 | 1 / 2 / 1 | 3 / 12 / 31 |
| archipelago | 8 / 9 / 11 | 5 / 5 / 3 | 14 / 23 / 43 |
| atoll | 3 / 2 / 3 | 3 / 2 / 2 | 3 / 3 / 26 |
| mediterranean | 1 / 2 / 3 | 1 / 1 / 1 | 2 / 11 / 27 |
| peninsula | 4 / 6 / 36 | 2 / 5 / 18 | 5 / 11 / 66 |
| pangea | 2 / 3 / 4 | 1 / 1 / 2 | 2 / 8 / 30 |
| isthmus | 1 / 3 / 3 | 1 / 2 / 1 | 1 / 14 / 35 |
| shattered | 4 / 9 / 4 | 1 / 4 / 1 | 15 / 41 / 67 |
| taklamakan | 1 / 2 / 1 | 1 / 1 / 1 | 1 / 6 / 21 |
| oldWorld | 2 / 4 / 3 | 1 / 1 / 1 | 3 / 11 / 19 |
| fractious | 2 / 2 / 2 | 1 / 1 / 1 | 2 / 73 / 268 |

## What the numbers say, and do not say

- **Land share varies enormously:** from about 6% (`atoll`) to 88% (`taklamakan`) of the map. A typical realm area in map units therefore gives very different counts per template: at 40,000 map units² the median K runs from 1 or 2 (`atoll`) to 22 (`taklamakan`), mostly 5 to 15.
- **Tiny landmasses dominate the island count:** `shattered` has a median of 41 landmasses of which 31 are tiny, and `fractious` 73 of which 60. At reach 0 (and at reach 4, under half a cell spacing) C is therefore mostly specks, and any chosen count must be at least that.
- **A reach of about two cell spacings (20 map units here) collapses most of that:** the median C is 1 to 4 for nine of the fourteen templates, 6 to 9 for `archipelago`, `peninsula` and `shattered`, and tiny-only groups fall to 0 to 4. A reach of 40 gives median C of 1 to 5 and 80 gives 1 to 3. (`atoll` stays at 2 to 3 groups because its ring and its centre are far apart.)
- **For island-heavy templates the minimum C, not the area, decides the automatic count** once the typical area is large (for example `archipelago` and `shattered` at 40,000 to 80,000 map units²).
- **Density matters, so map units do not make the grouping density-independent.** Landmasses at reach 0 grow with the cell count (`fractious` 2, 73 and 268 landmasses at 3,000, 10,000 and 30,000 cells; `shattered` 15, 41 and 67), because finer cells resolve more specks. C at reach 20 is much steadier but not constant (`peninsula` 4, 6 and 36; `shattered` 4, 9 and 4). This is consistent with the design note's qualification (map-unit distances remove an artificial density dependence but do not promise unchanged geography) and says a **default reach would need to be expressed with the cell spacing in mind, or paired with a rule for specks,** rather than as one fixed number of map units. Not decided.

## Limits

One map size (1280 × 800), five seeds per template and density, one run each; the tiny threshold is arbitrary; C counts landmasses of any size; the medians hide outliers (see the ranges). The numbers describe the generated land, not how realms will look: whether a reach or count gives good territories is for growth to show. The land areas use the raw clipped cell polygons, not the drawn coast.
