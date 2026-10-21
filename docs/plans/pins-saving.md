# Plan: Saving the pins in the map file

Status: built 2026-10-21 ([step page](../steps/pins-2-saving.md)); limits accepted. Design phase: **what is saved and what loading promises, not how it is coded.** Nothing here is built. It follows [the pin plan](map-pins.md) (decision of 2026-10-21, later: the current pins may be saved as part of the map data, and a client can still plug in its own pins and design), [saving the realms](realms-saving.md) (whose rules it keeps: the exact state is saved, loading validates and recomputes nothing, an older file is a valid state without the layer) and the review of 2026-10-21 (the demo's interim pins file needs decoding defaults, unique identifiers and refusals that leave the existing pins unchanged: those become this layer's validation).

## What it promises

A map saved with pins loads with **the same pins**: the same ids, places, marker keys, colour keys and memos, in the same order, and saving it again gives the same bytes (in the tested environment). A pin travels with its map, so there is **no fingerprint check for these pins** (the fingerprint stays for a client's own data tied to a map). A file with no pins loads as a map with no pins, and **a map whose pins were all removed is saved without a pin layer**, exactly as a map that never had any.

## What is saved

- **For each pin, in order:** its **id** (the client's or the framework's own text), its **place** (map units, inside the map), its **marker key** (`"pin"`, `"dot"` or a key a client's own markers understand), its **colour key** (one of the standard markers' few, or a client's own) and its **memo** (a short free text, empty if none).
- **Nothing about how a pin looks:** the marker shape, size and design are the client's (`PinMarkers`), and a key the loading build does not know simply draws as the default; the file never holds a picture or a view.
- **Nothing of the client's richer data:** a client with more to keep per pin keeps it itself, keyed by the pin's id.

## Where it lives and the format

- **In the land map's own file, as an optional pin layer** (as the realm layer is), so a water map, which embeds the land map, carries the pins with it. The pins are **not part of the fingerprint** (the fingerprint is the geography only).
- **Versions:** a file with neither realms nor pins stays version 1 and one with realms only stays version 2, **byte for byte as today**; **a file with pins (with or without realms) is version 3**, which may hold either or both layers. All three are read. The version says which layers may be present (a layer in a file whose version does not allow it is refused).

## What loading refuses

Everything the land file refuses, plus for the pin layer: **ids that are empty, too long or not unique** (duplicate ids give an ambiguous selection and an ambiguous list identity); **a place that is not finite or is outside the map**; a marker key or a colour key that is empty or too long; **a memo longer than the limit**; **more pins than the limit**; a missing field is a refusal, except that **a pin without a colour reads as red** and **without a memo reads as empty**, so that a pin saved by an earlier build still loads. A refused layer leaves the map as it was (`adding` refuses before attaching, as for realms).

## The limits (provisional)

A resource policy, not a promise about what is sensible: **at most 5,000 pins**, ids and keys **at most 64 characters**, a memo **at most 2,000 characters**, so a file's pin layer is bounded (about 10 MB at the most) whatever a file says. The numbers are a starting point and are reported with what a real use needs.

## How a client uses it

- A client reads a map's pins and **passes them to the view's pin layer**; when its events say a pin was dropped, moved, edited or removed, **it updates the map's pins** (the map is a value, so it makes a changed copy) and saves the map. Its own markers, size, anchor and look plug in through `PinMarkers`, and its own placing, editing and removing through the events, as now.
- **The demo** keeps its pins in the map, so "Save map…" keeps them and "Open map…" shows them; its separate pins file and its fingerprint check are removed, and its memo popover edits the pins in the map.

## How it would be tested (what, not how)

Round trips (a map with pins, with realms and pins, with water; automatic order; the same bytes on a second save); a map without pins is written exactly as before (version 1, version 2 with realms) and loads with none; a file made before the colour and memo fields loads with the defaults; each refusal above (empty, long and duplicate ids, a place that is not finite or is outside the map, bad keys, a memo over the limit, too many pins, a layer in a file whose version does not allow it); a refused `adding` changes nothing; pins do not change the fingerprint; a map whose pins were all removed saves as it did without any; the demo's save and open keeps pins. A fixed version-3 file guards the format.

## Not in this stage

A client's extra per-pin data in the file, client-defined pin kinds that take part in saving, labels drawn for memos, pins in `MapImage`, and the realm cleanup.

## What this plan does not claim

The limits are provisional and have not been tried with real use. Nothing here is built.

## Decided (the author, 2026-10-21)

1. **The provisional limits are accepted as a starting point:** at most 5,000 pins, ids and keys of at most 64 characters, a memo of at most 2,000 characters. They bound the file; changing them later is a number to change, not a format change.
