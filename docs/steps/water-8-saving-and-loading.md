# Water chain, stage 8: saving and loading the water map (`WaterMap`)

Status: built 2026-10-21 (plan: [water-8-saving.md](../plans/water-8-saving.md)). It makes the water chain usable as a whole: `WaterMap.generate` runs the original's chain on a land map, and `encoded()` and `init(decoding:)` save and load the exact state in **one file** that holds the land map and the water state (the author's decision, 2026-10-21).

## What it does

- **`WaterMap.generate(land:settings:policy:)`** (`Sources/FantasyMapCore/Water/WaterMap.swift`) runs, in the original's order: the geography (`Geography.generate`), the temperature, the rain, the packed graph, its features, then `Rivers.generate`. `WaterSettings` is one plain value with the original's defaults: the geography request, the three temperatures, **one height exponent** (passed to both the temperature and the lake climate, so the two cannot disagree), the rain level and winds, and the river options (erosion, lake elevation limit, depression-resolving iterations). The iterations are a setting because they change the result and so must be saved with the map; the resource limits of `RiverResourcePolicy` are not saved, since they only refuse work.
- **The map holds:** the land map; the settings; the geography; the temperature and rain of every grid cell; the packed graph with its **final** heights (after the beds were cut); the features with the lakes' final fields; the flux, river numbers and confluence flux of every packed cell; and the rivers.
- **What is saved** (`SavedWaterMap`, format version 1, algorithm revision 1): all of the above, with the land map as its own `SavedLandMap` (its own version and revision). **Not saved:** the packed cells' neighbours and corners (rebuilt from the points), the temporary lake fields the original deletes (`river`, `enteringFlux`, `outCell`, `closed`), the working heights before the erosion, the random state, the work report and the meandered points (temporary; the river records keep cells and scalar dimensions).
- **What loading does:** the land map is loaded and validated as the land layer does (its work bounded first); the settings, geography, climate arrays, packed arrays, features and rivers are validated; the packed cells are rebuilt from the saved points. **No generation step is run again**: a saved river's discharge or a lake's evaporation is kept as saved, not worked out again (tested by editing them).

## What loading refuses (each has a test)

An unsupported format version or algorithm revision; settings out of range or not finite; a geography that is not finite or whose latitude and longitude box is not the one its size and shifts give (a cheap check that the algorithm did not change under the revision); a climate array that does not have one value per grid cell; packed arrays of different lengths, no packed cell, or more points than the budget; a packed point outside the map or not finite, a grid cell outside the grid, a height above 100; a saved area that is not the area of the rebuilt cell (the same kind of drift check); the structure the river generator relies on (1 to 20 neighbours, feature numbers in the table, water in water features and land in land, a nonzero haven that is a neighbouring water cell, lakes with a land shore and a first cell of their own); a feature table whose numbers are not 1, 2, 3 … in order or whose land flag disagrees with its kind; a distance under -10 or a harbour count above the neighbours; a feature whose cell count is not the number of cells carrying its number, whose first cell, vertices or shoreline are outside the packed graph, whose numbers are not finite, that still carries a temporary lake field, that is not a lake and has inlets or an outlet, or whose inlets or outlet are not rivers of the list; river numbers repeated, 0 or above 65,535; a river with a non-finite or negative measure, fewer than three cells, a cell outside the map (-1 is the border), a source or mouth that is not a cell (below 0; the upper bound follows from the cells' range) or not where the cells say, or a parent outside 0 … 65,535; a feature whose first cell does not carry the feature's own number (a lake's first cell is checked by the generator's structural validation, the others by the loader); a river number on a cell that is no river. **A river's parent is a historical river number that may not resolve to a retained record:** the original's own rivers can name themselves, or a short river that was dropped, as parent, so it is only bounded (a stricter check refused real maps in the first round trip of the tests). Consumers must not assume a tree of live rivers.

## How it is tested

`WaterMapTests` (14), `WaterRevisionOneFixtureTests` (2):
- **The whole chain in one call equals the original's end state** on 40 captured runs (flux, river numbers, confluences and the final packed heights, by digest).
- **Round trips:** all 14 templates, two seeds each, two cell counts: the loaded map equals the generated one, the rebuilt land and packed cells equal the generated ones, a second save gives the same bytes. The runs carried rivers and lakes with inlets. A loaded map also equals one generated again from the same inputs.
- **Determinism, settings validation, one exponent, loading recomputes nothing, the version checks, each refusal above, no temporary lake field in a file.**
- **Fixed revision-1 files** (`Fixtures/waterrevision1`: two saved maps, one with erosion and one of another template without it, and a manifest): committed once, never regenerated by a test. They guard the bytes, the loaded counts, the packed cells rebuilt from the points (digest) and **the original's own** flux, river, confluence and height digests for the captured run each was made from. Rewritten only deliberately: `MAP_WRITE_WATER_REVISION1=<folder> swift test --filter WaterRevisionOneFixtureTests/writeTheFixtures`, with a revision bump explained in the commit.

## Mutation checks

57 mutants of `WaterMap.swift` (each check of the generation and of the validation removed or weakened, one at a time, made and undone by a script): **55 caught** (nine after the first run showed they were not: the lower bound of a packed point's y, the first cell and shoreline of a feature that is not a lake, a river of fewer than three cells whose source and mouth agree with its cells, a river measure below zero, and the source and mouth lower bounds and a feature's first-cell membership, added after review). **Four were removed as redundant, not tested:** the upper bounds of a river's source and mouth (implied by the cells' range), a limit of 65,535 rivers (implied by unique numbers from 1 to 65,535) and the check that a loaded feature carries no temporary lake field (the saved record has no such fields, so a loaded feature never has one). Mutants of the other files (the saved record's coding and the generator) are not made; the round trips and the fixed files cover them.

## Measurements (release, one run each on the machine this was built on; not a benchmark, not a promise)

A `continents` map, default settings, seed `kaz-1`:

| cells asked | packed cells | rivers | land | water chain | save | file | load |
|---|---|---|---|---|---|---|---|
| 10,000 | 6,449 | 198 | 13 ms | 84 ms | 9 ms | 611 KB | 34 ms |
| 100,000 | 61,201 | 855 | 189 ms | 1,082 ms | 88 ms | 5.8 MB | 340 ms |

The file is readable JSON; a packed binary form would be smaller and was not tried. **These are one map each:** lake-heavy maps and erosion on and off at 100,000 cells are still to be measured before any resource default is recommended.

## The compatibility claim, narrowed

Stored climate, heights, river records and lake fields are kept without regeneration. The topology is rebuilt with the **current** geometry implementation, the coordinate and area checks use **current** calculations, and the meandered points will be regenerated for drawing, so keeping old files readable needs revision-specific behaviour or an explicit refusal when a derived algorithm changes. The fixed files and topology digests are safeguards, not a universal guarantee. Byte-identical resaving is a claim for the tested environment.

## Binary property list, measured (not adopted)

Asked 2026-10-21 whether a binary property list would be smaller. The same saved record, release, one map each:

| cells asked | JSON | binary plist | JSON, LZFSE-compressed | plist, LZFSE-compressed |
|---|---|---|---|---|
| 10,000 | 611 KB (9 ms encode, 20 ms decode) | 705 KB (37 ms, 86 ms) | 178 KB | 398 KB |
| 100,000 | 5.8 MB (88 ms, 190 ms) | 7.2 MB (359 ms, 818 ms) | 1.5 MB | 3.1 MB |

The binary plist is **larger and slower** here: every array element is an object of its own with an offset-table entry, so the many small integers cost more than their text, and the property list does not pack arrays of bytes. Compressing the JSON gives the best size (about a third). The format stays JSON; compression on top, or a packed binary form made for these arrays, can be considered when a real storage or loading need shows up.

## Optional compression (added 2026-10-21)

`compressedEncoded()` gives the same JSON compressed as a whole with LZFSE (Apple platforms; about a third of the size, see the table above), and `init(decoding:)` reads either form: an LZFSE stream starts with `bvx`, JSON never does. **The decompressed size is bounded** (a provisional 256 MiB; the 100,000-cell file is about 6 MB), checked as the stream is produced, because a few bytes can describe gigabytes; a damaged or cut-short stream is refused with `invalidCompression` and an oversized one with `decompressedTooLarge`; a platform without the Compression framework refuses with `compressionUnavailable`. Tests: smaller than half, the same map back, saving what was loaded gives the plain file's bytes, the same compressed bytes twice (in the tested environment), a cut, garbage, an empty input, damage in the middle, a stream of zeros that expands past a lowered limit, and the limit exact (met, and one byte under refused). Mutation checks of the helper: 8 mutants, 5 caught; **3 survive as defensive code** (the empty-input guard, which the stream's own error already covers, and the two halves of the "no progress" guard, which overlap: no test input produced an end-without-progress or an error with output). They are kept to avoid a force-unwrap on empty input and an endless loop on a stream that stops making progress. Only the water map has the wrapper; the land map's own file is unchanged.

## What it does not show

Only the original's end state is compared, and only at the captured runs. The meandered river points are not saved and no drawing exists yet. A water map with biomes, realms or a drawing is later work.
