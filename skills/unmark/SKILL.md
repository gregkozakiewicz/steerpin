---
description: Remove one or more steerpin marks by id.
argument-hint: <id> [id...]
disable-model-invocation: true
allowed-tools: Bash(node *)
---

The user wants to remove these steerpin mark ids: $ARGUMENTS

Run this command with Bash, passing only the numeric ids (digits separated by spaces; drop anything else):

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/steerpin.mjs" unmark <ids>
```

Report the output in one or two lines. For any mark it removed, stop applying it from now on.
