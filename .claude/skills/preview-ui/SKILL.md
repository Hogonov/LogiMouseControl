---
# What: builds the debug app, renders the shipping SwiftUI views to PNG with --render-artwork-preview and reviews the images.
# Runs: when you type /preview-ui [what to look at], or when Claude needs to check layout after changing a view.
# Side effects: writes .build/ and the PNGs in .build/preview/. No AppModel, HID access, preferences or actions; never touches dist/ or signing.
# Remove: delete .claude/skills/preview-ui/.
name: preview-ui
description: Renders the app's real SwiftUI views to PNG without launching the app or using the mouse, then looks at the images and reports layout problems. Use after changing MainView, MouseIllustration, RingActionIcon, RingController, Theme, ArtworkPreview or another view, or when the user asks to check the layout or colours ("проверь вёрстку", "предпросмотр").
argument-hint: "[what to look at]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/render.sh *), Bash(${CLAUDE_SKILL_DIR}/render.sh)
---

Check the layout in the preview images. Focus: $ARGUMENTS

1. Run `${CLAUDE_SKILL_DIR}/render.sh`. It builds the debug binary and prints the absolute path of each PNG. If the build fails with "Operation not permitted" for a path under `.build/`, that is the agent sandbox: run the script again with the sandbox disabled and say so. If the build fails for another reason, report the first error lines and stop.
2. Open every printed PNG with the Read tool. The current set:
   - `buttons.png`: button map and assignment list, mint accent;
   - `buttons-violet.png`: the same with the violet accent, to see that the accent reaches the map;
   - `gestures.png`: the gesture button selected, five direction pickers. The frame is 580 px tall, so the list below the gesture block is cut off at the bottom; that is expected;
   - `overview.png`: mouse illustration on the overview card;
   - `appearance.png`: the «Оформление» card with six accent swatches, violet selected.
   If `ArtworkPreview.swift` gained or lost a file, describe what you find.
3. Report per image: fine, or what looks broken: clipped or overlapping text, missing elements, colours that don't follow the accent, unreadable contrast, wrong alignment. Give the most relevant finding for the focus first.

Don't change files while checking. Never launch the app without `--render-artwork-preview`, don't open the action ring, and don't press «Проверить действие»: the preview confirms layout only, not the mouse or the actions. Pages not covered by the preview (sidebar, whole pages, the ring) go to the user as a manual check.
