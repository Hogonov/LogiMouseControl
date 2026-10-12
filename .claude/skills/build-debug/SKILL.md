---
# What: debug build of the app to check that the code compiles.
# Runs: when you type /build-debug, or when Claude needs to check compilation after a code change.
# Side effects: writes only to .build/. Never touches dist/, signing, the keychain or the mouse, and never launches the app.
# Remove: delete .claude/skills/build-debug/.
name: build-debug
description: Builds the debug LogiMouseControl binary into .build/ to check that the code compiles, without touching dist/ or signing. Use after changing Swift code in Sources/, or when the user asks to build, compile or "собрать" the app for a check.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/build.sh)
---

Run the debug build and report the result. Don't change any files and don't fix errors unless the user asked for that.

1. Run `${CLAUDE_SKILL_DIR}/build.sh`.
2. If it fails with "Operation not permitted" or "You don't have permission to save" for a path under `.build/`, that is the agent sandbox: the Swift build service can't write `.build` from inside it. Run the same script again with the sandbox disabled and say so.
3. Report in one line: PASS with build time, or FAIL with the first error lines (file:line and message). Mention new compiler warnings from `Sources/`.

Never run `./scripts/build.sh` or `./scripts/setup-local-signing.sh` from this skill, and never launch the built binary. To look at the layout, use `/preview-ui`.
