# Plan: public readiness

Status: published 2026-10-21 at https://github.com/codelynx/Fantasy-Map-Generator-Swift (public, one-commit snapshot of the final state, tag `0.1.0`). Decided: package name stays `Fantasy-Map-Generator-Swift`; licence MIT, as the original; first tag `0.1.0`. Done: `LICENSE`, README credit, thanks and status, the programming guide, the large images reduced, the test warnings fixed, the final preflight on the snapshot. Remaining, all optional: a GitHub Release page for `0.1.0`, a Linux build and test job, a note to the original's author (the author's own to send).

## What

Before the port can be shown, these must be settled or written down.

1. **Names.** Decided. The package is `Fantasy-Map-Generator-Swift`; the libraries `FantasyMapCore` and `FantasyMapKit`; the demo `FantasyMapDemo`; the view `FantasyMapView`.
2. **Licence.** Decided: MIT. The original is MIT with one added paragraph (maps made with it are free to use); its notice is kept in `ACKNOWLEDGEMENTS.md`.
3. **README.** Done: status paragraph, credit, picture, link to the programming guide. It says plainly that this is an unofficial, independent port.
4. **Credits.** README credit section, `ACKNOWLEDGEMENTS.md` (original licence reproduced, third-party notices), `docs/dependencies.md` (alea, delaunator, robust-predicates, d3 parts, fdlibm, lineclip). To be checked in the preflight against the code as it is then.
5. **Repository hygiene.** What a stranger would see: fixture size, absolute paths or user names, commit messages that carry session links and co-author lines (54 of 54), the `docs/` working notes (plans, steps, research), and the capture tool's dependence on a local clone of the original. Reviewed by inventory first; the author chooses what to keep.
6. **Version.** `0.1.0` is the first tag, made only when the repository goes public. 1.0 waits until the Swift API and the saved-file formats are settled. Each saved format has its own version (the land file, now 3 with pins; the water file separately); neither follows the package version.

## Not in this plan

- Creating or publishing a repository, pushing, tagging a release.
- Asking the original author. Optional courtesy, the author decides if and when.
- New features.
- Rewriting or deleting the existing history. The preflight only reports.

## The preflight check

Report only: no fixes, tags or publication. It describes what is checked; how it runs is decided when it is built.

**What it names.** The candidate commit, the toolchain, the operating system and the exact commands, so that the result can be repeated. A clean clone leaves out staged and untracked work, so the final run is made on the completed candidate commit, with an empty build directory. Earlier runs are rehearsals.

**Checks**

1. **A fresh clone works.** It builds and passes the core and the drawing tests with no local paths and no copy of the original's code. Anything that needs the original (the capture tool) says so and is not part of the default tests.
2. **Licence and credit are complete.** `LICENSE` exists, `ACKNOWLEDGEMENTS.md` reproduces the original's licence, `docs/dependencies.md` matches the third-party code in the sources, and ported files name the original file.
3. **The history that would be published, not only the tip.** Deleted files stay in reachable history, so the scan covers every reachable file version, commit messages, tag messages, author and committer metadata and session links, on every ref meant for publication. Automated scanning (for tokens, keys, absolute paths, addresses) and manual review are reported separately, and neither is claimed to prove that nothing sensitive is there.
4. **Personal information is a finding to classify, not a failure.** Copyright holders, the original author's name and attribution addresses can be intentional or required. Each is listed and classified: required, intended, or to be removed. Session links are listed explicitly and reviewed even if they need a sign-in to open.
5. **The README tells the truth.** What is built and not built, the version and the run command match the code. The code in the programming guide compiles.
6. **Size and content.** Repository size, the largest files, and whether the `docs/` working notes are meant to be public.
7. **Version readiness.** `0.1.0` is the agreed release version and the tag is absent until publication is authorised. Each saved format is checked on its own: the version the code writes, the versions it reads, and the variation by optional layer (realms, pins).
8. **Platforms, one result each (pass, fail or not run).** Core build and tests; drawing build and tests; iOS compilation; live gestures on screen; a Linux attempt. A run on macOS does not verify iOS. **Linux is nice to have, not required for 0.1.0 (decided 2026-10-21):** it is reported as not run and the README keeps saying Apple platforms. What is known: the core library compiles for WebAssembly with Swift 6.2.4 (the compressed save falls back to `compressionUnavailable` without Apple's Compression framework); a real Linux build and test run waits for a Linux machine or a hosted job. The same check on 6.2.4 found and fixed one compile error that Swift 6.4 accepted (`f1c9f6f`).
9. **Publishing stays separate.** No remote, no push and no tag until the author says so.

**Output.** One short report with pass, fail or not run for each check, with the evidence, and plainly what was not checked.

## History

Decided 2026-10-21:

- **Publish a clean snapshot of the final state, as one first commit**, and keep the full development history privately. Whichever is published, every required credit and notice stays. The existing history is not rewritten or deleted.
- **The address on public commits is `kaz.yoshikawa@gmail.com`.** It is set globally and for this repository. The earlier development commits stay in the private history.
- **The working notes stay public:** `docs/plans/` and `docs/steps/` are kept, as the record of how each stage was compared with the original.
- **The large images are downscaled** before the snapshot (the ones of about 0.9 to 1.2 MB each, to roughly 300 KB), so that `docs/images` shrinks from about 8.6 MB to about 3 MB.

Following from the snapshot: the session links and the co-author lines are in the old commit messages only, so they do not reach the public history. They are not in any tracked file (checked in the preflight rehearsal).

## Facts gathered

- 54 commits on `develop`; `main` is at the first commit; no remote.
- `Package.swift`: tools 6.0, macOS 14 and iOS 17.
- No absolute home paths in tracked non-JSON files (checked 2026-10-21; the JSON fixtures were not checked).
- Fixture folder 12 MB, `docs` 7.9 MB, `.git` 14 MB.

## Order of work

1. Done 2026-10-21: the saved pin layer, the licence, README and guide, the inventory, the preflight rehearsal, the images, the test warnings, the author's own check of the pins in the demo, the snapshot, the final preflight on it, publication and the `0.1.0` tag.
2. Optional: a GitHub Release page, a Linux build and test job, a note to the original's author.
