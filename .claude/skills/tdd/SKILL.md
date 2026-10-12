---
# What: a project skill that builds a feature test-first, one behavior at a time.
# Runs: when you type /tdd <feature>, or when Claude matches your request to the description.
# Side effects: Claude edits code and tests, runs ./scripts/test.sh and commits, with your usual permission prompts.
# Requires: Claude Code and a project with a test command. Platforms: any.
# Remove: delete .claude/skills/tdd/.
# Based on the guide's lesson 1 skill, tested in Claude Code v2.1.285 (stable) on macOS, 2026-10-06
name: tdd
description: Builds a feature or fixes a bug test-first with a red, green, refactor loop, one behavior at a time, and commits the tests with the code. Use when the user asks for test-first or TDD work ("test-first", "TDD", "сначала тест", "через TDD"), or asks to add logic together with its tests, especially pure logic in Sources/MouseCore.
argument-hint: "[feature or bug]"
---

Build this test-first, one behavior at a time: $ARGUMENTS

If no feature is given, ask for one in a single sentence, then stop.

1. Red: write one failing test for the next behavior. Run the tests and confirm that it fails, and fails for the reason you expect. Don't change code outside the tests in this step. In Swift a call to a missing function fails to compile, which says nothing about behavior: add the smallest stub that compiles, such as one returning a wrong constant, and run again until the test itself fails.
2. Green: write the least production code that makes that test pass, even if it looks naive. Run the tests and confirm that all of them pass, not only the new one. Don't change the tests in this step, and don't add behavior that no failing test asked for.
3. Refactor: with every test green, remove duplication and improve names and structure in the code and the tests, without changing behavior. Run the tests after each change. If one turns red, undo that change instead of fixing forward.

Repeat until the feature is done, then run the whole test suite and commit the tests and the code together. Report each behavior you added and the test that covers it.
