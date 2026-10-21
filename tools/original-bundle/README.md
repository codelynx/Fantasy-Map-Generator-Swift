**One command:** `tools/capture-original.sh <clone> Tests/FantasyMapKitTests/Fixtures/original [--replace]` does all the steps below in a temporary folder, writes `provenance.json` (the original's commit, Node and bundler versions, the resolved Alea, Delaunator and robust-predicates versions, and the capture script's identity), and compares the result with the committed fixture. It replaces the committed fixture only when `--replace` is given; `--check` exits nonzero if the fixtures differ and replaces nothing. A reference checkout with uncommitted changes to tracked files is refused. `provenance.json` also records the hashes of the wrapper, the capture script and both templates. The manual steps follow, for understanding or when something goes wrong.

# Running the original's own code for fixtures

Some fixtures should come from the original's own generator code, not from a re-implementation. `grid-generator.ts`
(the original, `src/generators/grid-generator.ts`) is TypeScript written for the browser, so it is bundled once with the
bundler the original already uses (rolldown, from its `node_modules`) and then run in Node with a few globals stubbed.
Nothing from the clone is copied into this repository except the numbers the run prints.

1. Clone `Azgaar/Fantasy-Map-Generator` and run `npm install --ignore-scripts` in it (this port read commit `8936c9c`).
2. Copy `rolldown.config.template.mjs` and `utils-stub.template.ts` to a scratch folder (not the clone), replace
   `__CLONE__` and `__SCRATCH__` with absolute paths, and name the copies `rolldown.config.mjs` and `utils-stub.ts`.
3. In the clone: `./node_modules/.bin/rolldown -c <scratch>/rolldown.config.mjs` (this writes `grid-bundle.mjs` to the scratch folder).
4. `node tools/capture-original-grid.mjs <scratch>/grid-bundle.mjs Tests/FantasyMapKitTests/Fixtures/original`

The stubs are wiring only: they stand in for the original's browser globals (`window`, `document`, `options`, `TIME`), and
the original's `rn` and `SEA_LEVEL` are re-exported from its own files. `Grid.generate` is then the original's own code.
