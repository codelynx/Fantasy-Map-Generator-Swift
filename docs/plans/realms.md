# Plan: Realms, how-phase (starting with connectivity and reach)

Status: plan, 2026-10-20, for review. **Nothing is built.** The design is [design-realms.md](../design-realms.md) (committed). This plan is the how-phase and covers in detail only its **first step, a pure connectivity-and-reach operation before any growth**; the later steps are listed with what each must settle, not designed yet.

## What was read, and what was not

Read for this plan: the package's own land layer (cells, polygons, heights, features) and the realms design. The original's states generator was read in part (see the design note's background section); **nothing from it is used by this step.** Nothing here has been run or prototyped.

## Steps

1. **Connectivity and reach** (this plan, below). A pure function of a map and a reach: which land belongs to which reach-connected group, and the minimum realm count C.
2. **Count and seeds:** validate a requested count against C and the land; the automatic count; place at least one seed in every group, spaced and seeded.
3. **Complete connected growth** with size variation ("how uneven"): every group's land claimed, every realm non-empty and connected (by land or permitted crossings), no unclaimed land; failure to claim is a generation failure.
4. **Cleanup that preserves ownership and connectivity.**
5. **Saved format** (realm layer, settings, requested mode and resolved count; old files stay valid with no realms).
6. **Drawing:** one authoritative partition, boundaries ending at the final displayed coast, checked as the coast is.
Each step is tested before the next and gets a step page, as the earlier layers did.

## Step 1: connectivity and reach

Status: amended after review 2026-10-20; **built 2026-10-20, awaiting review** ([step page](../steps/realms-1-connectivity.md); it records two small deviations: only land cells with a water neighbour are coast cells, and there is no early exit because the links need the candidate distances).

### Definitions

- **Land** is a cell whose height is at least 20, as everywhere in the package. The feature records are **not** used (they can hold retained records with no cells), only the current cells.
- **A landmass** is a maximal set of land cells connected through **shared cell edges, that is, the cell neighbour lists.** Water cells, lakes included, are not land; a landmass round a lake is one landmass. Two landmasses that touch only at a corner (a shared Voronoi vertex) **are not one landmass.** The map frame joins nothing.
- **The reach** is an explicit finite number of map units, 0 or more, **required** by this step (a default is deferred, below). **Reach 0 disables sea connections:** every landmass is its own group.
- **A proximity link** joins two landmasses when the **distance between their raw cell polygons clipped to the map rectangle** is at most the reach, for a **positive** reach (inclusive). Polygon distance is computed with Double arithmetic. **Because of the corner exception, a positive reach joins corner-touching landmasses (their polygon distance is zero), while reach 0 does not;** this is stated and tested, and is why the links are called proximity links and not claimed to be positive-length segments whose interior is water.
- **Groups** are the transitive closure of proximity links; a chain of nearby islands connects a group over a much longer total distance, as the design says. **C**, the minimum realm count, is the number of groups (0 for a map with no land).
- **What the over-water argument does and does not give.** If the direct shortest segment between A and B passes over a third landmass C, A to C and C to B are each no longer than A to B, so A, B and C land in one group: this is valid **for finding groups.** It does **not** show the direct A to B link is a usable sea crossing. Later growth must not connect two parts of one realm through intervening land that another realm owns, so **step 1 also returns the links it relies on, with their actual end-point cells and distances** (below), instead of group membership alone.
- **Geometry:** the **raw Voronoi cell polygons clipped to the rectangle**, one shared clipping operation. **Not** the drawing layer's ray-extended border polygons, which overlap on purpose. The coast drawn on screen can differ from this underlying geometry, and the documentation says so. A clipped polygon that is empty or degenerate (fewer than three points, or no area) is **left out of distance work** but its cell stays part of its landmass; a landmass with no usable polygon at all cannot be linked and stays its own group (reported by a test).

### What it returns

For every cell the number of its landmass and its group (none for water); the landmasses and groups with their cell counts; **C;** and the **links** it chose: for each, the two landmasses, the pair of land cells (one in each) whose polygons are closest, and the distance. **The links form a minimum spanning forest of the landmasses by distance** (Kruskal order, ties broken by the smallest cell indices), so they are the shortest links that connect each group and are deterministic; growth can reconstruct or test further crossings from them. **Numbering is deterministic:** landmasses and groups are numbered by the smallest cell index they contain. No random numbers.

### How (sketch)

- Find landmasses by a flood over the cell neighbour lists (real cells only).
- **Candidate discovery must not miss a pair:** index the **bounding boxes of the coast cells' clipped polygons** and consider two polygons candidates when their boxes are within the reach of each other; a search keyed on cell sites could miss polygons whose sites are far apart, so it is not used. Only **coast cells** (land cells with a water neighbour, or touching the rectangle) take part, since only they can be closest.
- **Zero and tiny reaches:** reach 0 does no search. For a tiny positive reach the bucket size is never smaller than a stated floor (a fraction of the grid spacing), so the number of buckets and insertions stays bounded; **bucket enumeration and insertions, candidate visits and distance computations are each counted and bounded before the expensive loops run**, all float-to-integer conversions are range-checked, and exceeding a bound refuses (a defined error), not an approximation. A candidate-pair budget alone is not enough.
- Exact polygon-to-polygon distance for convex polygons (Double arithmetic); links sorted by distance with the stated tie-break; union-find over landmasses as links are taken in order; early exit when one group remains.
- Ordinary Double arithmetic with `<=` comparisons; **no claim of robust exact predicates.**
- **One shared rectangle-clipping operation in the core,** narrowly scoped (a convex polygon against an axis-aligned rectangle), **used by the drawing layer too** instead of two copies: the drawing layer's `MapDrawing.clip` becomes a call to it, with its existing tests unchanged as the check.

### Tests

- **Brute force with the same policy:** the accelerated search is compared with comparing every pair of landmasses directly, under reach 0 and positive reaches, on small generated and constructed maps, **including corner contacts and tiny positive reaches.**
- Constructed patterns (the package's own patterned heights): isolated islands at known gaps; a chain whose ends are far apart (one group); a reach just below and exactly at a gap (inclusive); **reach 0 (each landmass its own group) against a tiny positive reach (corner-touching landmasses join), with that exception stated;** one landmass; all water (C = 0); all land; two landmasses touching the frame (not joined by it); an island in a lake; landmasses whose clipped polygons are empty or degenerate.
- The links: they form a spanning forest of each group, each end-point pair is the closest pair of its two landmasses (checked by brute force), and the distances are at most the reach; deterministic ties.
- Properties: groups partition the landmasses; numbering is deterministic and stable; a larger reach never increases C; a reach beyond the map's diagonal gives one group (or none).
- Invalid reach (NaN, infinite, negative) refused; each work bound refused with its error; no unsafe integer conversion (huge and tiny reaches, huge maps).
- The shared clip: the drawing layer's tests still pass unchanged, and a direct test of the clip against known polygons.
- Release timing at 10,000 and 100,000 cells with its limits stated.

### Open for this step

1. **The default reach is deferred.** Step 1 requires an explicit reach. After step 1 exists, the gaps between landmasses on the fourteen templates are measured and a default chosen from them, without making it a universal "short crossing" across maps of different sizes (it may be a fraction of the map's size or a fixed distance; the measurement decides).
2. **The floor for the bucket size** and the **bounds** for insertions, candidate visits and distance work: values chosen when the operation is written and timed.

## Step 2: count and seeds

Status: plan, amended after review 2026-10-20; **built 2026-10-20, awaiting review** ([step page](../steps/realms-2-count-and-seeds.md)). Step 1 ([step page](../steps/realms-1-connectivity.md), committed) gives the groups and C for an explicit reach. Step 2 turns a requested count mode into a **resolved count K** and places the **seeds**, with no growth yet.

### Inputs and output

- **In:** the map, the reach, a **count mode** (automatic, or a chosen K), a **realm seed** (a string; with the map's own seed it drives every choice, through `Alea`, one stream, in a fixed order), and two **explicit, validated policy inputs, the typical realm area (map units²) and the maximum count.** Their defaults are **not settled**, so the code carries **no hidden placeholder constants:** a caller supplies them (a documented default is added only after the measurements below). The "how uneven" setting acts in growth (step 3), not here.
- **Out (`RealmSeeds`):** the mode, the **resolved count K**, how many realms each group holds, and the **seed cell of every realm** with its group. **Realm numbers 1 to K are assigned in group order, then in the order the group's seeds were placed,** and are **not renumbered after growth** for presentation: they identify the seeds that growth expands. **Deterministic for identical inputs;** no stability is promised across a changed count, reach or geography.

### The supported counts, and validating a count (first, before any work)

- **The supported interval is C … min(land-cell count, maximum),** subject to the work budget. (Not every count up to the land-cell count: the maximum is a resource cap.)
- **No land:** refused. **A chosen K below 1:** refused. **A chosen K below C:** refused as **incompatible with the reach**, reporting C; the reach is never raised and no distant leftover is assigned. **A chosen K above the land-cell count or above the maximum:** refused.
- **When C itself exceeds the maximum** (many isolated islands), no count satisfies both K ≥ C and K ≤ maximum: refused with a **named error reporting C and the maximum** for **both** modes; K is never silently reduced and the reach never silently increased.
- **The automatic count** is at least C and, within the supported interval, otherwise the land area divided by the typical realm area, rounded; it never exceeds the interval. **No extra realms are added after a count is accepted.**

### The automatic count

A **deterministic function of the map, the reach and the two policy inputs, no randomness.** The **typical realm area is a product choice** informed by measurements, and the **maximum is a resource policy** that needs work and timing evidence, not geography alone. The count uses map units, not cells; the original's own default count and growth settings were not read.

### Spreading K over the groups

- **A group's weight is the summed area of its land cells' raw polygons clipped to the map rectangle** (the step 1 geometry, grouped by step 1's groups), **not** cell counts, bounding boxes or the drawing layer's extended polygons. This measures the represented land, with its documented frame limitations.
- **Capacity-constrained largest remainder, exactly:** every group first gets one realm; its **residual capacity** is its land-cell count minus one; the extra E = K − C is shared as follows. (1) Over the groups not yet saturated, compute each one's quota as E_remaining × weight ÷ (sum of the weights of the unsaturated groups). (2) Any group whose floored quota exceeds its residual capacity is **saturated at its capacity and removed**, its extra realms are taken off E_remaining, and the quotas are recomputed over the groups that remain; repeat until no floored quota exceeds a capacity (each repeat saturates at least one group, so it ends). (3) Give each remaining group its floored quota, then hand out the realms still owed one at a time to the unsaturated groups by **largest fractional part, ties to the smaller group number, never past a group's capacity.** Since K is at most the land-cell count, the capacities always suffice. Deterministic, no randomness.

### Placing the seeds of a group

- **Without replacement, bounded:** each group keeps the pool of its cells that are not yet seeds; a chosen cell is removed from the pool at once (a swap-remove, so the pool stays contiguous). Nothing is drawn repeatedly until an unused cell appears, so the cost stays flat near K = land-cell count. **An exhausted pool before the accepted count is placed is an implementation failure,** reported as such, never permission to return fewer seeds.
- **The rule:** the first seed is a seeded random cell of the pool; each next seed is the best of a **seeded random sample drawn from the pool without replacement,** the cell farthest from the seeds already placed, **measured in map units between cell sites** (straight lines: a placement heuristic, not evidence that the place is reachable or connected for growth). **Ties go to the smaller cell index.** The sample size is `min(pool size, a stated sample size)`; the **cumulative work (sample size × seeds placed, summed over groups) is counted and bounded before the loops, and refused beyond the bound,** as in step 1.
- **Deferred until growth shows a concrete need:** path-distance placement, coast avoidance, and mandatory seeds on large islands of a multi-landmass group.

### Tests

- Count validation: no land; K below 1; K below C (reporting C); K equal to C; K equal to the land-cell count; K above it; K above the maximum; **C above the maximum (the named error in both modes);** the supported interval's ends; automatic never outside it.
- Allocation: sums to K; at least one per group; never above a group's capacity; the **saturation loop** (a tiny group beside large ones, a case needing two rounds); largest-remainder ties by group number; K = C and K = the land-cell count; deterministic; **weights are clipped-polygon areas** (a constructed case where cell counts and areas disagree).
- Seeds: distinct land cells in the right group; counts match the allocation; the **pool never repeats or exhausts early** (K = land-cell count uses every land cell exactly once); identical inputs give identical results; **different seeds change the result on chosen nontrivial cases only** (identical results are legitimate for one-cell groups or when every cell is selected, and no test claims otherwise); ties by smaller cell index.
- Spread (evidence, not a promise): on generated maps the least distance between a group's seeds is, on average, larger than for plain random choice with the same stream.
- The work bound refused; invalid inputs (an empty realm seed is allowed; non-finite or non-positive policy inputs refused).
- Release timing at 10,000 and 100,000 cells.

### Measurements, kept apart from the code

The reusable allocation and seed code does not wait for them. Separately, **several seeds per template** are measured and recorded: land area, landmass count and C across explicit reaches, with the effect of tiny islands. They inform the typical realm area and a default reach; **the maximum count also needs timing evidence of its own.**

### Open for this step

1. The **typical realm area** (a product choice) and the **maximum** (a resource policy), as explicit inputs until settled.
2. The **sample size** for best-candidate sampling and its **work bound** (chosen when the code is timed).

## Step 3: complete connected growth

Status: plan, amended after review 2026-10-20; **built 2026-10-20, awaiting review** ([step page](../steps/realms-3-growth.md)). Inputs: the map, the step-1 groups and links, the step-2 seeds, and an explicit growth policy. Output: **the owner of every land cell** (water has none). **Supplied groups, links and seeds are validated against the map at the public boundary,** as step 2 does for groups.

### What the result must be

Every land cell belongs to exactly one realm; **every realm is non-empty and connected;** the result is **deterministic** for identical inputs; and a failure to claim any land is a **generation failure, never permission to leave land unclaimed.** Cleanup (step 4) is not responsible for repairing disconnected growth: growth must construct connected territories.

**What "connected" means for a realm.** A realm's cells are connected through **shared cell edges within a landmass** and through **usable crossings between landmasses,** where a usable crossing is a **verified over-water segment** (below) between their cells.

### The growth: connected frontier growth, not shortest-path ownership

**This is a deliberate choice.** With realm-specific expansion factors, "give each cell to the realm with the lowest unrestricted path cost" is a different algorithm from "build connected territories": a faster realm can have the cheapest path to a cell *through another realm's territory*, and keeping one label per cell can discard a slower realm that would win farther on. **Counterexample, kept as a test:** a chain A — B — X with seeds at A and B, edge lengths 1 and 3, expansion factors 10 for A and 1 for B. Unrestricted costs give X to A (0.4 against 3), but B must keep its own seed cell, so A's territory would be cut in two. Connected frontier growth gives X to B.

- **Reserve every seed for its realm before growth begins** (every seed owns its own cell).
- **Queue proposals only from cells the realm has already claimed,** and **finalize each unclaimed cell once:** the first proposal popped for a cell wins, and a **finalized owner is never overwritten**; later proposals for an owned cell are discarded as stale.
- **Propagate only through the realm's own claimed cells** over land adjacency and over the verified crossings.
- **Order of finalization:** a binary heap keyed by (cost, realm number, cell index), a total order, so ties are broken by the smaller realm number, then the smaller cell index, and the result does not depend on iteration order. A proposal's cost is the realm's accumulated cost at the claiming cell plus the step cost divided by the realm's expansion factor.
- **What this is, and is not:** competitive frontier growth that constructs connected territories and can **completely cover a connected seeded graph.** It is **not** a guarantee of the globally lowest unrestricted source-specific shortest-path cost, and the notes will say so. The idea comes from the original's state growth, written for this package's data; parity is not a goal.
- **Costs are in map units:** a step to a neighbouring land cell costs the **distance between the two cell sites** times a terrain factor for the cell entered: 1 on lowland, **`hillFactor`** from height 44, **`mountainFactor`** from height 67 (the original's thresholds, as multiplicative costs per unit distance). Cell sites are kept as the distance convention (as in seeding); the map-unit costs avoid per-cell penalties, they do **not** make the borders invariant to density.
- **No cost cap.** A lone realm in a group takes its whole reachable group. Exhausting the **resource budget** is a **named failure distinct from limiting a realm's extent.**
- **Expansion factors** come from the "how uneven" setting: realm i gets 1 + `unevenness` × r_i, r_i drawn once per realm from the seeded stream in realm-number order. **`unevenness` 0 means equal expansion factors, not equal-sized realms.** Which realm is large and which small is decided by the seed. `unevenness` belongs to the growth policy (a user interface can show it beside the count).

### Crossings: actual geometry, verified

- **First version: only the step-1 links** (the minimum spanning forest), used in both directions: they supply enough graph connectivity, and they restrict territorial choices, which is accepted for now; alternative crossings are deferred.
- **A link must carry its geometry.** Today `Link` holds cell numbers and a distance. **Step 1 is extended** so a link also holds the **closest boundary points** on the two polygons (`pointA`, `pointB`), recovered by the polygon distance (which then returns the witness points as well as the distance), so a crossing is a real segment.
- **Verification before growth:** each crossing's **open segment** (between its two points) is checked against **all other land cell polygons** (candidates found by a spatial hash over the segment's bounding box, with a bound on the work): it must not pass through the interior of any land cell other than its two end cells, which it touches only at its end points. **Corner contacts and numerical ambiguity are defined, not ignored:** a zero-length crossing (the two polygons touch at a point) is usable and is recorded as a contact; a segment that touches another land polygon exactly at a vertex or runs collinear with an edge is **ambiguous and refused.** An unusable witness is a **named failure** (`unusableCrossing`, naming the landmasses), **never silently dropped** and discovered later as unowned land. The Kruskal argument (a closest segment cannot pass over land) is why verification is expected to pass on non-degenerate geometry; **it is not a substitute for the check,** above all at zero-distance contacts.
- **Crossing cost includes the land approaches.** Crossing a link costs: the distance from the departure cell's site to its shoreline point times that cell's terrain factor, **plus `crossingFactor` times the sea length** (the segment between the two points), **plus** the distance from the arrival point to the arrival cell's site times that cell's terrain factor; all divided by the realm's expansion factor. The land portions are not free.

### Policy, derived costs and bounded work

- **Explicit policy, no hidden constants:** `hillFactor`, `mountainFactor`, `crossingFactor` and `unevenness`, validated: finite, the factors at least 1 and at most a stated upper bound, `unevenness` 0 or more and at most a stated upper bound. **Finite inputs do not guarantee finite accumulated costs, so every derived cost is checked finite before a proposal enters the heap;** a non-finite cost is a named failure (`nonFiniteCost`). The policy is saved with the other generation settings and the seed.
- **Work is counted and bounded:** heap proposals pushed, heap pops and edge examinations are each counted during the run against stated bounds (estimated before the run where the graph allows, and always enforced while it runs), refused beyond with a named failure (`workBudget`).

### What it checks and returns

`RealmOwnership`: the owner of every cell (the realm number, or 0 for water), for each realm its cell count and area, and a record of the policy. **A validation function** (also the tests' independent check) confirms: every land cell has an owner and no water cell has one; every realm 1 … K owns at least its seed; **each realm is connected** by a separate breadth-first search over land adjacency and the verified crossings; and no crossing joins a realm's pieces unless both end cells belong to it. A group with no seed, or land the search cannot reach (a hand-built input with links missing), is a named failure (`unreachableLand`).

### Tests

- **The chain counterexample** (A — B — X, factors 10 and 1, lengths 1 and 3): X goes to B and A stays connected; alongside the independent connectivity checks.
- **Completeness and connectivity** on hand-made cells and generated maps (all fourteen templates, several seeds, reaches and counts) by the independent validation: every land cell owned, no water owned, every realm non-empty and connected, a realm spanning islands connected through verified crossings only.
- **K = C** (each group one realm, owning the whole group), **K = the land-cell count** (one cell each), **K = 1** per group, a group whose only seed is on one island, a seed on a tiny island.
- **Crossing geometry:** the stored points are the closest points (checked against a brute force), each crossing's segment is verified against the land polygons on every generated map tested; hand-made cases for a segment over land (refused as `unusableCrossing`), a vertex touch (ambiguous, refused), a collinear touch, and a zero-length corner contact (usable). **The land approaches are charged:** a constructed case where the approach distance changes which realm wins an island.
- **Determinism** and tie-breaks on symmetric hand-made cells (the realm number, then the cell index); changing the realm seed changes the result on nontrivial cases only.
- **Size variation (observational, not asserted beyond direction):** the spread of realm sizes is recorded for `unevenness` 0 and larger values across seeds; **0 gives equal factors and no claim of equal sizes.**
- **Terrain:** a mountain ridge between two seeds moves the border toward the seed that is farther across it, in a constructed height pattern.
- **Failures and bounds:** a group without a seed, missing links, invalid policy, a non-finite derived cost, each work bound, each a named error, none leaving land unowned; groups, links and seeds that do not belong to the map refused at the public boundary.
- Mutation checks as in the earlier steps; release timing at 10,000 and 100,000 cells.

### Measurements and pictures

Realm size distributions (the largest realm's share, the smallest realm's cells) across the templates and `unevenness` values; a first picture of realms by eye, with its limits stated. Nothing is concluded about the look until step 6 draws the boundaries.

### Open for this step

1. **The values** of `hillFactor`, `mountainFactor`, `crossingFactor` and the **bounds and range** of the policy: provisional until growth has been tried on generated maps.
2. **Crossings beyond the spanning forest:** whether the first pictures show realms that need more than one link per island pair.
3. **Tendrils and enclaves** that frontier growth can leave: left to step 4's cleanup, which must preserve ownership and connectivity (and is not asked to repair disconnected growth).
4. **A seed on a tiny island** gives a realm that can only grow across its crossings against larger neighbours, so it may stay tiny; step 2's straight-line placement may need to change if that is common.

## What this plan does not claim

Steps 1 and 2 are built and tested (see their step pages). Step 3, its policy inputs and every default are untested ideas. The later steps are named, not designed. Nothing says the first pictures of realms will look like the original's.
