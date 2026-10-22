# Plan: map controls

Status: plan, 2026-10-21, **for review**. Design phase: **what the component offers, not how it is coded.** Nothing here is built. It comes from an app that wants the demo's controls in its own map window without copying them.

## What it is

**One controls view, all in one box**, beside `FantasyMapView`. It edits the settings that make and show a map, and **only edits them**: the app decides what to do with a change (make a new map, grow the realms again, redraw). The package's demo uses the same view, so there is one copy of the controls and a new option appears in the demo and in every app together.

It is **one view with one optional setting**: which groups to show. By default it shows all of them; an app that does not want some passes the ones it wants. There is no kit of pieces to assemble.

## The groups

- **Seed and land shape:** the seed (typed, or another at random) and the fourteen land shapes.
- **Detail:** the number of cells.
- **Coast:** smoothing, ink width, and the rough coast with its amplitude and variant.
- **Rivers:** the switch and the width.
- **Realms:** the settings that make them (see below), and whether they are drawn.
- **Pins:** the marker (map pin or dot), the colour, and how many pins there are.

**What stays in the demo, and is not in the component:** saving and opening files, the saved picture, and the raw-cell diagnostic overlay.

## How it behaves

- **A settings value in, the same value out.** The app owns it. The view tells the app *which part changed*, so that the app can do the right amount of work: a new **seed, shape or number of cells** needs a new map (the pins go with the old one); a **realm setting** grows the realms again on the same land and keeps the pins; a **coast or river setting** only redraws.
- **Defaults are the demo's today.** An app that hides a group gets its defaults and nothing to wire.
- **Nothing is stored by the component.** The seed, shape, cells and realm recipe are already in a saved map; the look settings are the app's to keep or not.

## An app's use

The app that asked shows **seed and land shape, realms and pins** only. The cells, coast and rivers are fixed at their defaults (10,000 cells, the default coast, rivers always on), so those groups are hidden and no look settings are kept with a map.

## Realm settings (decided 2026-10-21)

**The Realms group shows the number of realms (automatic or a number), how uneven the sizes are and the reach, in the open;** the typical realm size, how much hills, mountains and sea crossings slow growth, and the realm seed sit under one "More" disclosure inside the same group. The all-in-one view stays short, with no extra setting.

## Not in this plan

- Any control the demo does not already have.
- Naming and the exact shape of the settings type, which are decided when it is built.
- A release: the package is at 0.1.0 and the rename and the one-call helper are on `develop`; this ships in 0.2.0 only when the author says the package has settled.
