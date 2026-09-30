---
description: Mark text without a hotkey. Types are priority, wrong, roadmap, later.
argument-hint: <priority|wrong|roadmap|later> <text>
disable-model-invocation: true
allowed-tools: Bash(node *)
---

The user ran `/steerpin:mark` with: $ARGUMENTS

The first word is the type (priority, wrong, roadmap or later). The rest is the text to mark. If the type is missing or not one of those four, or there is no text, show the usage `/steerpin:mark <priority|wrong|roadmap|later> <text>` and stop.

Otherwise run this with Bash, putting the text between the heredoc markers exactly as the user wrote it (do not reword, summarise or fix it):

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/steerpin.mjs" add <type> <<'STEERPIN_TEXT'
<text>
STEERPIN_TEXT
```

Report the output in one line. If you marked something as wrong, briefly say whether anything earlier in this conversation relied on it.
