---
description: Take back what your last message delivered to Steerpin (marks, roadmap or later items).
disable-model-invocation: true
allowed-tools: Bash(node *)
---

!`node "${CLAUDE_PLUGIN_ROOT}/scripts/steerpin.mjs" undo`

Tell the user the result above in one or two lines. For any mark it removed, stop applying it from now on.
