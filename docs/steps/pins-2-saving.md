# Pins on the map, stage 2: saving

Built 2026-10-21, from [the plan](../plans/pins-saving.md) (limits accepted). A map keeps its pins in its own file.

## What it does

- **`MapPin` moved to `FantasyMapCore`** (it was in the drawing library): an id, a place in map units, a marker key, a colour key and a memo. `MapPin.newID()` makes a fresh id (a UUID string). A pin saved without a colour or a memo loads as red with an empty memo.
- **`LandMap.pins`, `settingPins(_:)`** (also on `WaterMap`): setting pins checks them first and changes nothing if they do not fit. `adding` and `removingRealms` keep the pins.
- **The land file's version says which layers it may hold:** version 3 holds pins (and realms if there are any); version 2 realms only; version 1 neither. A map with no pins, or whose pins were all removed, is written exactly as before, so older files and their bytes do not change. A file whose layers do not match its version is refused.
- **Limits (`PinLimits`):** 5,000 pins; ids, marker keys and colour keys 1 to 64 characters; a memo up to 2,000 characters and 16,000 bytes of UTF-8; ids unique; every place finite and inside the map (the edges are inside). Loading checks all of it and throws `SavedLandMapError.invalidPins(…)` on the first problem.
- **The fingerprint ignores pins:** two maps with the same geography have the same fingerprint, so the demo can still keep pins per map and a map's pins can change without it becoming another map.
- **The demo** keeps its pins in the map: "Save map…" saves them with it and "Open map…" shows them. The separate demo pins file is gone.

## Tests

`PinLayerTests` (13):
- a map with pins round-trips in order and saves to the same bytes; a map without pins is written as before and the layers combine (realms with pins); a map whose pins were all removed is saved exactly as if it never had any;
- a water map carries its land map's pins;
- a pin saved without a colour or memo loads with the defaults; a fresh id passes the checks;
- the version says which layers a file may hold (each wrong pairing is refused);
- every pin against the limits and the map: id, marker and colour lengths at and past the limit, non-finite and out-of-map places, edges inside, memo characters and bytes (a long run of family emoji is refused by bytes, a long run of Japanese by neither);
- ids unique and not too many; setting pins that do not fit changes nothing; two maps differ when their pins differ;
- a fixed version 3 file (`Fixtures/pinsrevision3/`) still loads to the same pins.

**Mutation checks (lighter policy, once for the feature):** 29 mutants of the pin checks, the version rules, saving, loading, `settingPins` and the carry-over; 28 caught. The one survivor was the "finite" part of the place check: it was redundant, because the bounds comparisons already refuse NaN and the infinities. It was removed, with a comment, and the existing NaN and infinity cases still pass. Not re-run after that edit.

Suites after this stage: core 365 (release and debug), drawing 159 (release); the drawing suite was not run in debug.

## What it does not show

- The pin layer's gestures in the live demo (drag without panning, drop, edit the memo, save and reopen) need the author's eyes; they cannot be driven from a test.
- A file written by a later version with more layers is not read; a file's version is the only signal. The limits are accepted numbers, not measured needs.
