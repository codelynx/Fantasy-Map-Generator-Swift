# Plan: Zooming and panning the map view

Status: plan, amended after review 2026-10-21, cell target decided; **built 2026-10-21** ([step page](../steps/drawing-zoom-1-viewport.md)). Design phase: **what the view does and what it promises, not how it is built.** Nothing here is built or measured live. It follows [the drawing design](../design-drawing.md) and [the view-speed measurement](../steps/drawing-view-speed-2026-10-20.md).

## What it decides (the author, 2026-10-21)

**Zoom and pan are part of the library's `FantasyMapView`, and on by default,** so that client code gets them without writing any: an app that shows a map with `FantasyMapView` can zoom and pan it. A client turns them off if it does not want them. The image renderer (`MapImage`) is unchanged: it draws the whole map at the size it is asked for.

## The viewport (what the state is)

- **The state is a zoom and a centre:** the **zoom relative to fit** (1 is the whole map fitted in the view, as drawn today; larger is closer) and the **centre in map coordinates** (map units, origin at the map's top-left, y down, as the drawing's own). The map-to-view and the view-to-map transforms are defined together from these two numbers and the view's size: the view shows the map rectangle of `size / (fitScale × zoom)` centred on the centre. **A state that is not finite, or a zoom outside the limits, never reaches a drawing transform:** it is clamped (a zoom into its range, a centre into the pan limit) before use.
- **The limits take precedence over anchoring.** Zooming keeps the point under the pointer or pinch fixed **until a limit intervenes**: at the largest or smallest zoom the zoom stops, and where the pan limit would be passed the centre stops. The tests check the unclamped anchoring and the clamped behaviour separately.
- **The pan limit keeps a meaningful part of the map in view:** the centre may not leave the map, and at least **a stated fraction (provisionally a quarter) of the view's width and height stays covered by the map** whatever the zoom, so a map cannot be almost lost with only a sliver in view. At fit the map is centred and cannot be moved.
- **Resizing keeps the map-space centre,** then clamps; at fit the map stays centred.
- **The maximum zoom depends on the map's cell size, not a fixed number** (the author's point: a fixed 16 times is too much for a map of 1,000 or 10,000 cells, whose cells are already large, and too little for 100,000). It is chosen so that **at the maximum zoom one cell is about a stated size on the screen (provisionally 64 points across)**: `maximum = cell target ÷ (cell spacing × fit scale)`, never below a floor (provisionally 2) and never above a ceiling (provisionally 64). Worked for the default 1280 × 800 map in a 1000-point-wide view (fit scale 0.78): about 2 for 1,000 cells (spacing about 40 units), about 6.5 for 10,000 (about 12.6 units), about 20 for 100,000 (about 4 units). The target, the floor and the ceiling are configurable and **provisional**; the first live look decides them.

## What the view does

- **Gestures:** pinch to zoom; drag to pan; **Option-scroll (the wheel or two-finger scroll with the Option key held) to zoom on a Mac, and plain scrolling is left to the surrounding interface;** double-click or double-tap zooms in **one step around that location**, up to the maximum (it does not toggle). Pinch and drag together move and zoom the map at once, each applied to the same viewport. When interaction is switched off the view draws as it did before, with a fixed viewport at fit and no gesture handled.
- **Fit is its own action, never only a gesture:** a "Fit" action (a button the client can place, a keyboard shortcut, and an accessibility action on the view) returns to zoom 1 centred. Keyboard zoom in and out are provided too.
- **Replacement and identity:** a client **tells the view when the map is a different one** (an explicit map identity or a reset it triggers); the view never works that out by comparing a large `MapDrawing` on each update. **Presentation-only changes keep the viewport** (colours, line widths, overlays, layer visibility); a **different map, or one made again with other geography or topology, resets it to fit**, which the client controls. A client that binds the viewport chooses any other policy.
- **Overlays use the same transform.** Anything drawn over the map with the view's coordinates (the demo's raw-cell overlay, seeds and crossing links) is given the same viewport transform, or is disabled while zoomed, so that it cannot drift from the map.
- **State bound by the client:** the zoom and centre can be bound to the client's own state (to save, reset or move the map from outside); with no binding the view keeps its own.
- **The drawing is the same geometry** (the same `MapDrawing` and the same commands, with the transform applied). Zoom introduces **no raster enlargement**: it is vector drawing at the new size. **Line widths are in map units and grow with the zoom,** as the original's SVG strokes do; **the one exception is the thin seam-hiding outline of the land and water cells, which stays a fraction of a device pixel** (it is there to hide seams between neighbouring cells, not to be seen).

## What it promises, and what it does not

- At zoom 1 the view uses **the same transform and the same drawing commands as today**; the pictures agree **within the established rendering tolerance** (the SwiftUI renderer's output was seen to vary from run to run, so no pixel-for-pixel equality is promised), and the whole map is visible, centred.
- Zooming and panning change what part of the map is shown and how large, and nothing else: no regeneration, no change to the map or the drawing.
- **No frame rate is promised, and nothing is said yet about large maps.** A redraw of the whole drawing was measured offscreen at about 10 ms for 10,000 cells and about 40 ms for 100,000 (one machine, not a frame rate); a live redraw while zooming is **not measured**. It will be, with a prepared `MapDrawing`, **separating drawing construction from redraw and from gesture latency**, and profiled before any remedy such as drawing only what is in view is chosen (geometry traversal, clipping and transparency layers can each be the bottleneck).
- **Platform gestures are reported honestly:** results on macOS verify macOS only; **iOS touch interaction is not verified by a macOS result** and is reported separately.

## What it does not do

No minimap, no level-of-detail change (the coast and rivers are drawn the same at every zoom), no rotation, no zoom controls beyond those above, and no change to the image renderer.

## How it would be tested (what, not how)

- The transforms: map to view and back round-trip; a non-finite or out-of-range bound state is clamped and never reaches the drawing.
- **Anchoring unclamped** (the point under the pointer stays fixed) **and clamped** (a limit stops the zoom or the pan, and the limit wins), tested separately; the pan limit keeps the stated fraction of the view covered at every zoom; at fit the map is centred.
- The maximum zoom follows the cell size (1,000, 10,000 and 100,000 cells give different maxima, the floor and the ceiling hold).
- Resizing keeps the map-space centre; a presentation change keeps the viewport; a new map or an explicit reset returns to fit; a bound state is read and written; interaction off behaves as today.
- Gestures: each gesture changes the viewport as stated; the Mac modifier is named and plain scrolling is not handled; Fit, the keyboard actions and the accessibility action work.
- Overlays share the transform. At zoom 1 the view and the image renderer agree within the tolerance; a zoomed view shows the part the zoom and centre say (a pixel check on a rendered view).
- A live redraw and gesture latency are measured at 10,000 and 100,000 cells and reported as measurements.

## What this plan does not claim

How smooth a zoom is on a large map is not known. The values marked provisional (the cell target of 64 points, the floor of 2, the ceiling of 64, the quarter of the view kept covered, the zoom step of a double click) have not been looked at live. Which gestures a given platform delivers (a mouse wheel, a trackpad, touch) has not been tried here, and iOS interaction has not been verified.

## Decided (the author, 2026-10-21)

1. **The maximum zoom starts from a cell target of 64 points across** (a cell about as big as a small icon at full zoom): about 2 times for 1,000 cells, 6.5 for 10,000 and 20 for 100,000 on the default map in a 1000-point-wide view. It stays configurable and provisional; the first live look may change it.
