# Plan: release 0.2.0

Status: prepared 2026-10-21, **nothing is released**. Every outward step below (merging to `main`, pushing, tagging, the GitHub Release) waits for the author's explicit yes.

## What 0.2.0 is

Everything on the local `develop` branch since 0.1.0: the renamed libraries, `MapSettings`, the one-call map and realm functions, `MapControls`, `PinNote`, the demo built on them and the guide's Controls section. The notes are in [`CHANGELOG.md`](../../CHANGELOG.md).

**It is a breaking change for 0.1.0 users** (the two library names change places, which is why `FantasyMapKit` now means something else). It was accepted for a 0.x package whose only user is the author; the changelog says how to migrate. **The saved formats do not change** (land file 1 to 3, water file 1) and the geography fingerprint is the same, so files and anything keyed to a fingerprint carry over. *Checked by comparing each format file against the published 0.1.0, file against file:* the water file, the compression, the SHA-256 and the realm layer are identical, and the land file and land map differ only in the name of the enum that holds the version numbers; the fingerprint's domain string is unchanged, and the tests that pin two fixed files' digests and read a fixed version-3 file pass.

## Where it stands (checked 2026-10-21)

- **Tests:** both suites pass in release and in debug (view and drawing 205, core 369), no warnings.
- **iOS:** both libraries compile for a generic iOS device. Not run: gestures and the look on iOS.
- **Swift 6.2:** the one compile error found with a 6.2.4 toolchain is fixed; the full build and tests were only run with Swift 6.4 on macOS.
- **Linux:** not run (nice to have, decided not required).
- **History scan of the new commits** (every file version in the 7 commits since `main`, one revision at a time, with a pattern that must hit as a control): no local paths, keys, tokens, session links or private addresses. The project name of the author's app appeared once in a plan note and was reworded. The owner name `codelynx` appears in the repository's own URLs only. The author and committer of every new commit is `kaz.yoshikawa@gmail.com`.
- **Demo screenshot:** the README picture shows 0.1.0's controls. **Left as it is, at the author's wish.**

## Steps

1. **Prepare (can be done now):** `CHANGELOG.md` (written), this plan (written), and the one line in the guide that names the version to depend on (`from: "0.1.0"` becomes `from: "0.2.0"`, made together with the tag so it is never ahead of it).
2. **The final check, on the candidate:** a fresh clone of the tip of `develop` with an empty build folder, both suites in release and debug, the iOS compile, and the scan above repeated on whatever the prepare step adds. Report each as pass, fail or not run, with what was not checked.
3. **Merge to `main`:** `develop` is 7 commits ahead of `main` and `main` has nothing `develop` lacks, so a fast-forward keeps the step-by-step history as it is. **Needs the author's yes**, and the choice below.
4. **Tag `0.2.0`** (annotated) on the merged tip, then push `main` and the tag. **Needs the author's yes.**
5. **The GitHub Release** for `0.2.0`, with the changelog's notes and the migration paragraph first. **Needs the author's yes.**
6. **Afterwards:** nothing changes for an app that points at the package by a local path; the author's other apps that name the products are updated by the table in the changelog.

## To decide

- **How the history reaches `main`:** a fast-forward, which publishes each step's commit (the messages say what each step is, and carry the same `Co-Authored-By` line as the public commit already there), or a single squashed commit for the whole of 0.2.0. *Recommendation:* the fast-forward, because the step commits are the record of how each part was tested.

## Not in this release

Linux, a retaken screenshot, and anything new.
