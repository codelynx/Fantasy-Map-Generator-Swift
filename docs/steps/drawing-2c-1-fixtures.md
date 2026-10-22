# Drawing stage 2c, step 1: fixtures from the original's coastline generator

Status: done 2026-10-20 (plan: [roughening-2c.md](../plans/roughening-2c.md)). Nothing is ported yet.

- `tools/capture-original-coastline.mjs` runs the original's own `Coastline` on explicit inputs; `tools/capture-original.sh` bundles it with the other captures (the entry file now also exposes `Coastline`), adds the script and the new fixture's hash to `provenance.json`, and compares it with the committed copy. The five earlier fixtures came out identical; the new one was captured twice with the same result (`--check` passes).
- The fixture is `Tests/FantasyMapCoreTests/Fixtures/original/coastline-original.json` (442 KB); what it holds is described in the fixtures' README.
- Following the review: points are compared **exactly** first; if `**` (power) mismatches in the Swift port it is captured and investigated before any tolerance is introduced. `enabled: false` is captured from `getFeatureShape`, the layer that implements it, not from `fractalize`. Outlines are **closed**, as `fractalize` treats them; the open-chain path has no original to compare with and is tested on its own properties.
- Not exercised: `simplify`, `clipPoly`, the SVG path builder.
- Evidence limit: fixtures cover five outlines, twelve settings and four seeds on 100×100 to 400×300 maps; they are a sample, not the whole input space.
