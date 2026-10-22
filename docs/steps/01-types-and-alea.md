# Step 1: Basic Types, the Saved Schema, and Alea

Built 2026-10-20, as step 1 of [the land plan](../plans/land-layer.md).

## What it does

- **`Alea`** (`Sources/FantasyMapCore/Random/Alea.swift`): a seeded random generator that reproduces the original's `Alea(seed)`. It is a port of the npm package `alea` 1.0.1 and its Mash hash, with the same arithmetic. The seed string is hashed by its **UTF-16 code units**, as JavaScript reads it, so non-ASCII seeds match. Its state is local to the value: there is no global generator, and separate generations can run concurrently. `next()` returns the value `Math.random()` would have returned in the original.
- **`JSNumber`** (`Land/JSNumber.swift`): the JavaScript conversions the original relies on (`>>> 0`, `| 0`, and what a `Uint8Array` holds after a store), computed on Doubles. Kept apart from the algorithms' own clamp.
- **`Heights`** (`Land/Heights.swift`): a height is a byte, 0 to 100 as the algorithms limit it, with 20 as sea level. `Heights.limit` is the algorithm's clamp; `Heights.stored` is the storage conversion (truncate toward zero, wrap modulo 256). They are different, and each is applied only where the original applies it.
- **`Point`, `SavedLandMap`** (`Land/LandTypes.swift`): the saved form of the land layer, defined now and written last. It holds a format version, an algorithm revision, the seed and size, the cells asked for, the cell points and the boundary points, and the final heights. A point is saved as a two-number array.

## How it is tested

- **Alea against the original, short:** the first 20 values for nine seeds are compared **exactly** with the values the original's `alea` 1.0.1 gave, captured by `tools/capture-fixtures.mjs`. The seeds are the empty seed, ASCII, digits, non-ASCII, a surrogate pair, and a precomposed ("\u00E9") and a decomposed ("e\u0301") "é". The fixture records each seed's **UTF-16 code units**, and a test checks the seeds really are those sequences, because Swift string equality treats canonically equivalent spellings as equal and cannot establish the distinction. All nine match, to the last bit.
- **Alea against the original, long:** one seed over **10,000 calls**: selected outputs (calls 0, 1, 9, 99, 999, 4999 and 9999) and the generator's final four-number state are compared with the original's, to catch accumulated divergence. They match.
- **Optimised build:** the same 17 tests also pass in a release build (`swift test -c release -Xswiftc -enable-testing`). This supports "matches these reference sequences in debug and release builds on this machine", not universal equivalence.
- **The conversions:** truncation, wrap modulo 256 (where a clamp would not wrap), non-finite values, `>>> 0` and `| 0`.
- **The schema:** it round-trips exactly, a map with no recipe is complete and loads, and **validation** refuses what a build cannot accept: unsupported format version or algorithm revision, a non-finite or non-positive size, a non-positive cell count, a different number of points and heights, a height above 100, and non-finite points. A point must have **exactly two** coordinates; a trailing or missing one is a decoding error. Decoding validates, so a refused map never loads half-formed.

## Versions

Format version 0 and algorithm revision 0 mean "unreleased and provisional". The first supported persisted format will be **format version 1**. The algorithm revision advances when output-affecting behaviour changes, and it governs how saved points are **rebuilt** (topology and derived fields) as well as how heights are generated, because a changed triangulator reads the same points differently. Once saved files matter, a revision is supported or explicitly refused, never silently rebuilt differently.

## The optional recipe

A saved map may carry a `GenerationRecipe` (the template, the resolved step list, and the settings that mattered). It is provenance: it explains or lets someone regenerate the map, and loading never regenerates heights from it. A map without one is complete.

## What it does not show

Alea matches for the reference sequences above; that is strong evidence, not a proof for every seed or build. The other stages (points, cells, heights, features) are not built, so nothing here says anything about parity beyond the random numbers.
