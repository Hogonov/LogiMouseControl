---
# What: hands the current uncommitted changes in Sources/ to the hid-reviewer subagent.
# Runs: only when you type /hid-review. The diff is inserted before the subagent starts, so it needs no shell access.
# Side effects: none; git status and git diff only read.
# Remove: delete .claude/skills/hid-review/.
name: hid-review
description: Sends the uncommitted changes under Sources/ to the read-only hid-reviewer subagent for a hardware safety review.
context: fork
agent: hid-reviewer
disable-model-invocation: true
allowed-tools: Bash(git status *), Bash(git diff *)
---

Review these uncommitted changes. Focus: $ARGUMENTS

Changed files (untracked ones, marked `??`, are not in the diff: read them with the Read tool):

!`git status --short -- Sources`

Diff against HEAD:

```!
git diff HEAD -- Sources
```

If both lists are empty, report that there is nothing to review and stop.
