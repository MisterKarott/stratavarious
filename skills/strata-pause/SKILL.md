---
name: strata-pause
description: Toggle capture pause — run once to pause, again to resume
---

# StrataVarious Pause

Toggle session capture on/off.

## When to use

- Exploratory sessions you don't want in the vault
- Debugging messy experiments
- Temporary breaks from capture

## Instructions

Check if the file `${STRATAVARIOUS_HOME}/memory/.stratavarious-paused` exists (where STRATAVARIOUS_HOME defaults to `~/.claude/workspace/stratavarious`).

**If it exists (currently paused):**
1. Delete the file
2. Tell the user: "Capture resumed."

**If it doesn't exist (currently active):**
1. Create the file with the current timestamp as content
2. Tell the user: "Capture paused. Run /strata-pause again to resume."
