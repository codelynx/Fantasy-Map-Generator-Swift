# Drawing layer: the cost of building and showing a large map

Measured 2026-10-20 with `Tests/FantasyMapKitUITests/ViewSpeedMeasurement.swift`, which asserts nothing about speed and runs only on request:

    FMK_MEASURE=1 swift test -c release --filter ViewSpeedMeasurement

**What this is, and is not.** One machine (Apple M4 Pro, 12 cores, macOS 27.0.1 build 26A434), a **release** build, the median or the list of three runs of each step, one process. The SwiftUI view is rendered **offscreen through `ImageRenderer`**, which runs the view's `Canvas` drawing commands in this process: it measures the cost of those commands, not the on-screen display with a window server and GPU compositing, and **it is not a frame rate**. An on-screen redraw of a live `Canvas` (scrolling, resizing, zooming) was **not measured**. Drawing construction and display are kept apart below. Maps: the `continents` and `shattered` templates, seed `kaz-1`, 1280×800 map units. Nothing here is a performance promise for other machines or maps.

## Drawing construction (`MapDrawing(map:style:)`), release

| Map | Style | Build | of which `CoastOutlines` | Roughening |
|---|---|---|---|---|
| continents, 10,000 cells | standard (smoothing 2) | 11 ms | 1 ms | off |
| continents, 10,000 cells | smoothing 0 | 10 ms | 0 ms | off |
| continents, 10,000 cells | smoothing 2 + roughness (amplitude 0.75, threshold 0.05) | 14 ms | 3 ms | applied |
| continents, 100,000 cells | standard | 137 ms | 19 ms | off |
| continents, 100,000 cells | smoothing 0 | 131 ms | 19 ms | off |
| continents, 100,000 cells | smoothing 2 + roughness | 141 ms | 30 ms | applied |
| shattered, 100,000 cells | standard / smoothing 0 / roughness | 130 / 132 / 139 ms | 17 / 18 / 29 ms | off / off / applied |

At 100,000 cells most of the build is the cell polygons (about 100 ms); the coast outlines, including smoothing, roughening and every roughening check, are 17 to 30 ms. Generating the map itself took 195 ms (continents) and 125 ms (shattered) at 100,000 cells, 13 ms at 10,000. The 100,000-cell drawings hold 100,000 fills, about 5,700 exposed and 5,700 receded borrowed fills, 238 to 253 ink lines and about 49,000 outline points.

## Display, release, `ImageRenderer`, a 1280×800-point frame

| Map | Style | Display scale | SwiftUI view, first render | Repeats (fresh renderer, same prepared drawing) | `MapImage.render` at 1280×800 |
|---|---|---|---|---|---|
| continents, 10,000 | any of the three | 1 and 2 | about 10 ms (the very first render in the process 63 ms: warm-up) | 9 to 11 ms | 35 to 46 ms |
| continents, 100,000 | standard | 1 / 2 | 100 / 97 ms | 97 to 101 ms | 270 ms |
| continents, 100,000 | smoothing 0 | 1 / 2 | 97 / 95 ms | 97 to 101 ms | 242 ms |
| continents, 100,000 | roughness applied | 1 / 2 | 108 / 98 ms | 98 to 100 ms | 274 ms |
| shattered, 100,000 | standard / 0 / roughness | 1 / 2 | 94 to 97 ms | 94 to 111 ms | 237 to 270 ms |

On a grid of sampled pixels (135 at scale 1, 493 at scale 2) the view's image **agreed with `MapImage.render` at every sample in every case**, so these timings are for the real picture, not a blank. The display scale (1 or 2) made no visible difference to the time. "Repeat" here is a fresh `ImageRenderer` and a fresh view value over the **same** prepared drawing; `ImageRenderer` keeps its image after the first call, so asking it again measures nothing (an earlier version of the measurement did exactly that and printed 0 ms; it was fixed).

## What can be said

- Preparing a drawing once and showing it is cheap relative to the work it replaces: at 100,000 cells about 130 to 140 ms to build and about 100 ms to draw offscreen on this machine; the roughening and its checks add about 10 ms to the build. The image renderer is slower than the view here (about 240 to 280 ms), probably because it fills and strokes every opaque cell; that was not investigated.
- The earlier caution stands where it matters: **no claim is made** about interactive behaviour on screen, other machines, iOS devices, or maps bigger than 100,000 cells.
- This is the baseline the review asked for **before per-ring roughening fallback** is attempted; that work should rerun it and compare.
