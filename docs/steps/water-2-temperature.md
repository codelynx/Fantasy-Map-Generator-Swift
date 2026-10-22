# Water chain, stage 2: temperature

Status: built 2026-10-20; review correction applied (the consumed latitude interval is validated) (plan: [water.md](../plans/water.md)). Second stage of the faithful port of the original's water chain; it reads the latitude bounds stage 1 produces.

## What was built

- **`Temperature.compute(for:geography:settings:)`** (`Sources/FantasyMapCore/Climate/Temperature.swift`), a port of `temperature-generator.ts` at the pinned original (commit `8936c9c`): the temperature, in whole degrees, of every **grid** cell as the original's `Int8Array`. A gradient from the equator through the tropics (16° north to −20° south) to each pole (0.15 °C per degree inside the tropics, then straight lines to the pole temperatures), less **6.5 °C per kilometre of altitude** (`rn((height − 18)^exponent / 1000 × 6.5)`, none below sea level), clamped to −128 … 127 and stored the way an `Int8Array` stores (**truncated toward zero**).
- **Each row's latitude comes from the first cell's `y` of the row** (the points are jittered, and the original reads only the first), with `latN` and `latT` from the geography and the map's height.
- **`TemperatureSettings`:** the original's defaults (equator 27 °C, north pole −30, south pole −15, height exponent 2), validated. `JSNumber.toInt8` is the new storage conversion.
- **Safety refusals, documented as divergences:** settings that are not finite or out of range (temperatures −100 … 100 °C, exponent 0.1 … 5; **these are this package's policy, not upstream limits and not needed for arithmetic safety:** the original's controls are narrower, temperatures −50 … 50 and the exponent 1.5 … 2.2, and its schema is broader) and inconsistent inputs (cell counts, a row width that does not divide the cells, a map height out of range, a latitude span outside 0 … 180) are refused with named errors (`invalidSettings`, `invalidInputs`); the original takes the values as given. **The latitude interval actually consumed is validated:** `latN` and the southern bound `latN − latT` (rounded to one decimal as `Geography` rounds it) must lie within −90 … 90, so a malformed `Geography` (it is publicly mutable) cannot extrapolate beyond the poles; the stored `latS` is neither trusted nor read. A zero span stays supported. **A zero-span geography** (latitude span 0, accepted by stage 1) is handled: every row is at the northern edge's latitude, and the result is finite.

## Fixtures and tests

`tools/capture-original-temperature.mjs` (wired into `tools/capture-original.sh`) runs the original's own `Grid.generate`, `HeightmapGenerator.generate`, `Features.markupGrid`, the two lake steps, `Coordinates.generate` and then `Temperature.generate`, and records for **174 runs** the bounds the original had, the number of cells, a sha256 of the Int8 bytes and the minimum and maximum; 48 runs keep the **whole array**. The runs: every one of the fourteen templates on six map configurations with the default climate; the seven climates (the default, hot, cold, an extreme one reaching −105 °C before the clamp, and the exponents 1.5, 2.2 and 3) on the whole world and on three slices (a narrow equatorial one, a narrow polar one and a temperate one). The fixtures check (capture twice, identical; the seven earlier fixtures unchanged).

`TemperatureTests` (11): **all 174 runs equal the original exactly, fed the original's own bounds** (which isolates this stage) and **all 174 again through the whole chain from the map alone** (our map, a fresh-stream geography with the run's request, our temperature); the 48 whole arrays are equal cell for cell. Hand-computed cases, with values worked out independently in plain double arithmetic: the tropical and both polar gradients at exactly representable latitudes (27, 25, 24 in the tropics; 3, −7, −29 north; 10, 1, −14 south); **the tropic bounds inclusive** (−20 gives 24, −20.0001 gives 23); the altitude drop (43.7 rounds to 44 at height 100, and the exponent 1.5); the Int8 store (3.9 gives 3, −3.5 gives −3, a drop of hundreds is clamped to −128 and not wrapped); the row latitude read from the first cell only; the zero-span geography; every refusal; **the latitude interval** (past either pole, `latN` −90 with a span of 180, NaN and infinite values refused; the whole globe, polar slices, zero spans at both poles and in between, and a southern bound of exactly −90 after rounding accepted; a wrong stored `latS` changes nothing). (Two of my first hand expectations were wrong, one of them because a latitude recovered from a row's y is not exact: −20 came back as −20.000000000000014 and fell outside the tropics. The tests now use exact latitudes and values computed independently.)

**Mutation checks** (each made and undone): the tropics zone moved, the tropical gradient changed, the south tropic taken from the wrong side, the southern gradient's divisor wrong, the altitude rounding replaced by a floor, the exponent ignored, the Int8 store rounding instead of truncating, no clamp, the row latitude read from the last cell, the latitude span ignored: all fail. **Three mutants survive and are equivalent, not gaps:** making either tropic bound exclusive (the gradients are continuous there: at 16° both branches give 24.6 and at −20° both give 24.0) and starting the altitude drop at height 18 instead of 20 (the drop at 18 and 19 rounds to 0).

## Measured

Release timings are tiny (the loop is one pass over the cells): about 1 ms at 10,000 cells and 13 ms at 100,000 in a debug test run, one machine.

## Limits

- 174 runs are a sample; exact equality is observed on them, not guaranteed for every input (`pow` is used for the exponent; it agreed with V8 on all of them, and for the exponent 2 on every height).
- The temperature is per **grid** cell, as in the original; the packed graph (stage 4) maps back to it through the grid-cell numbers.

## Notes from the review

- The height exponent is also used outside temperature (lake evaporation). The eventual generation settings should provide **one authoritative height-conversion setting** so that temperature and evaporation cannot use different exponents; for now `TemperatureSettings` carries its own and `ClimateSettings` can compose temperature, precipitation and winds later without merging their implementations.
- The equivalent mutants are documented and the original's branches kept: rewriting a faithful port to remove them would bring no benefit.
- Fixture equality is **observed on the tested inputs, fractional powers included; it is not a cross-platform guarantee** for every supported exponent.
