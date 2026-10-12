---
# What: runs every automatic check this project allows on the current changes and reports the result.
# Runs: only when you type /verify. Routine and mechanical, so it uses a smaller model and low effort.
# Side effects: builds into .build/ and renders the layout preview into .build/preview/. Never touches dist/, signing or the mouse.
# Remove: delete .claude/skills/verify/.
name: verify
description: Runs the project's automatic checks on the current changes (core checks, patch format, debug build, layout preview for UI changes) and reports pass or fail, plus what the user must check on the mouse by hand.
model: sonnet
effort: low
disable-model-invocation: true
allowed-tools: Bash(git status *)
---

Verify the current changes. Don't change any files, and don't fix failures: report them.

Changed files:

!`git status --short`

Run these in order from the project root, and keep going after a failure:

1. Core checks: `./scripts/test.sh`
2. Patch format: `git diff --check`
3. Debug build, which leaves `dist/` and signing alone:
   `CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --scratch-path .build --product LogiMouseControl`
4. Only if a changed file is a view (`MainView`, `MouseIllustration`, `RingActionIcon`, `RingController`, `ArtworkPreview`, `LogiMouseControlApp` or a `*View*.swift` file) and step 3 passed: get the binary folder with the same command plus `--show-bin-path`, run `"<that folder>/LogiMouseControl" --render-artwork-preview .build/preview`, then open `.build/preview/buttons.png` and `.build/preview/overview.png` with the Read tool and describe anything that looks broken. Never run the app without `--render-artwork-preview`.

Report:

- one line per step: PASS, FAIL or SKIPPED, and for a failure the first error lines;
- if a changed file touches the device, scrolling, buttons, gestures or the ring, the items from `docs/HARDWARE_VALIDATION.md` the user should check on the mouse. Don't run those checks yourself.
