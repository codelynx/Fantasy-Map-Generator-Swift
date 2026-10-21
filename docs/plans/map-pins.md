# Plan: Pins on the map

Status: plan, 2026-10-21, screen-size decision taken; **built 2026-10-21** ([step page](../steps/map-pins-1-layer.md)). Design phase: **what pins are and what the framework does and does not own, not how they are built.** Nothing here is built. It follows [the zoomable view](drawing-zoom.md) (a pin must follow the map when it zooms and pans) and the note of the maps trial that **a pin belongs to an exact map picture** (annotations must never silently move to a different map).

## What it is (the author's idea, 2026-10-21)

Like a map app: **you drop a pin on the map and annotate it.** The marker need not be a round map pin: it can be **like 凸, a block with a tab on top, as on old military strategy maps**, or anything else; **client code can override the marker and the behaviour**. **(Changed 2026-10-21: the framework no longer ships a 凸 marker, for now; the standard markers are a map pin and a dot, and a client that wants a 凸 supplies it through its own `PinMarkers`.)** **The pins' data is saved by the client, separately from the framework's own saved map data.**

## What the framework owns

- **A pin layer in `FantasyMapView`:** it keeps pins at their places in map coordinates, so they stay on the same spot of the map while it zooms and pans, and it hides one that is scrolled out of view.
- **Placing and handling:** dropping a pin where the user chooses (a click, a long press or a tap, as the client decides), hit-testing which pin is under a point, selecting a pin, and dragging a pin to move it. The framework reports these to the client as events (a pin was dropped at this map point, selected, moved, removed) and **changes nothing in the client's data itself.**
- **Markers:** a small set of built-in markers, **a map pin (teardrop) and a plain dot** (a tab marker 凸 was planned and is left out for now), each with its anchor (the tip of the map pin, the centre of the dot) at the pin's place, **in a few light colours the pin names by key** (red, orange, yellow, green, blue, purple). **A client can replace the marker with its own,** and can say how large it is, how it looks when selected, and what a pin of each kind of its own looks like.
- **The pin's place** is a point in map coordinates (map units, the viewport's own), which the framework also converts to and from the view's points.

## What the framework does not own

- **The annotation:** the text, the picture, the colour, the kind, the author. A pin carries **an identifier the client chooses and nothing else the framework needs**; what it means is the client's. **The framework draws no annotation editor:** it tells the client a pin was selected and **where it is in the view**, so the client can show its own callout or sheet beside it.
- **Saving pins.** The framework's saved map holds the map (and its realms and water), not pins; **the client saves its pins in its own store.** The framework may offer a small Codable value for a pin's place and identifier as a convenience, which a client is free not to use.
- **Which map the pins belong to:** the framework gives the client a way to **tell whether a map is the same one** (a stable identity or fingerprint of the saved map) so that a client can keep pins with the exact map they were dropped on and **never silently move them to another**; what to do when the map differs (ask, hide, keep) is the client's.

## Defaults and promises

- Pins are **off until the client gives the view pins**; a view with none behaves as it does today.
- The framework draws pins above the map and below nothing else it draws; they never change the map, the drawing or its saved data.
- The same pins and the same viewport give the same picture.
- **The marker keeps its own size on the screen at any zoom** (decided), anchored at the pin's place.

## What it does not do

No routes or lines between pins, no clustering, no search, no names or labels of its own, no editing UI, no persistence, no sharing or sync, no geographic coordinates (a pin's place is map units, not latitude and longitude), and no change to the image renderer (a picture with pins is a client's composition unless a later step adds it).

## How it would be tested (what, not how)

Pins keep their map place through zoom and pan (the same pin shows at the transformed point); the anchors of each built-in marker sit at the pin's place; hit-testing picks the topmost pin under a point and none elsewhere, including pins at the edge and overlapping pins; dropping, selecting, moving and removing report the events and change nothing else; a pin out of view is not drawn; a client marker replaces the built-in one; a view with no pins draws as today. The look of the markers is judged by eye in the demo.

## What this plan does not claim

How the gestures for dropping and dragging pins combine with the pan and zoom gestures (a drag on a pin must not pan the map) has not been worked out. Touch on iOS is not covered.

## Decided (the author, 2026-10-21)

1. **A pin keeps its size on the screen when the map is zoomed,** as in ordinary map apps: the map zooms and pans under it, the pin's anchor stays on its place in the map, and the marker is not scaled. It stays readable and tappable at any zoom. A client that wants a pin that scales with the map can override that in its own marker.

## Added 2026-10-21 (the author): a memo on tap, and a few pin colours

1. **Tapping a pin opens a light memo beside it** (a sticky note: a few lines of text), in which the pin's colour is chosen from a few. **This is the client's:** the framework only reports the selection and where the pin is, and keeps the pin's colour key; **the demo shows the memo as a popover** attached to the pin's marker (which follows the map as it zooms and pans), and keeps the note and the colour in its own data and its own pins file. A newly dropped pin opens its memo at once.
2. **The colour is part of the pin** (`MapPin.color`, a key of the standard markers' palette; a pin saved without one reads as red), so a client that saves its pins can keep it. The selected pin is shown by a white halo and a heavier outline, not by changing its colour.

## Decided (the author, 2026-10-21, later)

1. **The current pins may be saved as part of the map's own data** (an optional pin layer in the map file, as the realm layer is): this reverses the first plan, where the client saved all pins separately. What is saved is what a pin is: its id, its place, its marker key, its colour key and a short memo. **A client can still plug in its own pins and design:** the `PinMarkers` provider (the marker's size, anchor and look, any SwiftUI view in a rectangular frame) and the `PinLayer` events (drop, select, move, remove) are the delegate the client uses to place custom pins and to draw how they look, and a client's richer data stays its own, keyed by the pin's id. **Limits are accepted:** a marker is a view in a rectangular frame at a stated size and anchor; shapes or behaviours that need more than that are deferred.
2. **The current pins are what the author is happy with:** nothing further is wanted from the pin layer for now beyond saving them in the map data; larger plug-in machinery (for example client-defined pin kinds that take part in saving) is deferred.
3. **Consequence for the demo:** the demo's own pins file and its fingerprint check are interim; once pins are saved in the map file they are not needed (pins travel with their map), and the review's pins-file corrections (decoding defaults, unique ids, fresh identifiers) become part of the saved layer's validation.
