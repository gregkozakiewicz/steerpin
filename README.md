# Steerpin

Mark text in a Claude Code chat as **priority**, **wrong**, or **roadmap** with a hotkey. Claude gets your active marks with every message until you remove them, so they survive long sessions and `/compact`.

In a long session, important points drift out of focus and wrong statements get reused as fact. The chat UI has no way to mark text, and plugins can't add buttons to it. Steerpin does the marking at the OS level with hotkeys, and a Claude Code hook picks the marks up.

## How it works

1. Claude writes an answer.
2. You highlight a sentence and press a hotkey:

   | Key | Mark | What happens |
   |---|---|---|
   | `⌥⇧R` | priority | Sent to Claude on every message: "keep this at the top of your attention" |
   | `⌥⇧W` | wrong | Sent to Claude on every message: "don't rely on this; correct anything built on it" |
   | `⌥⇧A` | roadmap | Appended to `docs/steerpin/roadmap.md` in the project, word for word |
   | `⌥⇧S` | later | Appended to `docs/steerpin/later.md`, word for word |

3. A notification confirms it. The mark goes into a global inbox, `~/.steerpin/inbox.jsonl`.
4. You send your next message as normal. Before Claude reads it, the hook:
   - writes roadmap and later items to their files (a script does this, so nothing is lost or reworded)
   - saves priority and wrong marks to `.claude/steerpin/marks.md` with a numeric id
   - adds the active marks to your message as context, like this:

   ```
   USER MARKS (set by the user by highlighting text in this chat)

   Priority, keep these at the top of your attention:
   [1] Tokens must stay platform-agnostic until the export step

   Flagged as wrong, do not rely on or repeat these. If anything
   you said or built depends on them, say so briefly and correct it:
   [2] "Style Dictionary can't handle composite tokens"

   New since last message: [2] (acknowledge these briefly in your reply)
   ```

5. The marks are sent again with every message, and when a session starts, resumes or compacts, until you remove them.

## Install

You need [Claude Code](https://code.claude.com), and [Node.js](https://nodejs.org) 18 or later on your `PATH` (the hook is a small Node script with no dependencies).

### 1. The plugin

In Claude Code:

```
/plugin marketplace add gregkozakiewicz/steerpin
/plugin install steerpin@steerpin
```

Or from a shell:

```bash
claude plugin marketplace add gregkozakiewicz/steerpin
```

```bash
claude plugin install steerpin@steerpin
```

Restart Claude Code after installing so the hooks load.

### 2. The hotkeys (macOS)

The hotkeys use [Hammerspoon](https://www.hammerspoon.org), a free automation tool. It copies your selection with `⌘C`, reads the clipboard, then puts back whatever was on your clipboard before. This approach works in terminals and in Electron apps (VS Code, the Claude desktop app), where macOS Services often don't get the selected text.

1. Install Hammerspoon: `brew install --cask hammerspoon`, or download it from the website. Open it once.
2. In **System Settings › Privacy & Security › Accessibility**, turn on Hammerspoon. It needs this to send `⌘C`.
3. Clone this repo and run the installer:

   ```bash
   git clone https://github.com/gregkozakiewicz/steerpin.git ~/steerpin
   ```

   ```bash
   ~/steerpin/macos/install-hammerspoon.sh
   ```

   This copies `steerpin.lua` into `~/.hammerspoon/` and adds `require("steerpin")` to your `init.lua`.
4. Reload Hammerspoon (menu bar icon › Reload Config). Allow notifications when macOS asks.

To test: select some text anywhere, press `⌥⇧R`, and check that a "Marked as priority" notification appears and that `~/.steerpin/inbox.jsonl` has a new line.

**Changing the keys.** Replace `require("steerpin")` in `~/.hammerspoon/init.lua` with:

```lua
require("steerpin").setup({
  keys = {
    priority = { { "ctrl", "alt" }, "r" },
    later = false, -- turn a key off
  },
})
```

## Commands

| Command | What it does |
|---|---|
| `/steerpin:marks` | List active marks with their ids (also processes the inbox) |
| `/steerpin:unmark <id> [id...]` | Remove marks |
| `/steerpin:clear-marks` | Remove all priority and wrong marks. Roadmap and later files are untouched |
| `/steerpin:mark <priority\|wrong\|roadmap\|later> <text>` | Mark text without a hotkey. Works on any OS |

You can also delete a section from `.claude/steerpin/marks.md` by hand.

## Config

Optional, per project: `.claude/steerpin/config.json`. Any key you leave out uses the default.

```json
{
  "roadmap": "docs/steerpin/roadmap.md",
  "later": "docs/steerpin/later.md",
  "maxActiveMarks": 15,
  "maxMarkLength": 500
}
```

- `roadmap`, `later`: file paths, relative to the project root. Missing files and folders are created.
- `maxActiveMarks`: at most this many marks (the newest) are sent to Claude. The block says how many were left out.
- `maxMarkLength`: longer marks are shortened in Claude's context. The full text stays in `marks.md`.

## Files

| Path | What |
|---|---|
| `~/.steerpin/inbox.jsonl` | Global inbox the hotkeys write to. Emptied on your next message |
| `.claude/steerpin/marks.md` | Active priority and wrong marks for this project |
| `docs/steerpin/roadmap.md`, `docs/steerpin/later.md` | Saved roadmap and later items |

Marks are personal to your session, so you'll usually want to keep them out of git:

```gitignore
.claude/steerpin/marks.md
```

## Good to know

- **Two sessions open at once.** The hotkeys don't know which project you're in, so the inbox goes to whichever session gets the next message. Send your next message in the session you marked from.
- **Marking while Claude is still answering** is fine. The marks are picked up with your next message.
- **Duplicates.** Marking the same text twice does nothing. Marking it with a different type (priority, then wrong) replaces the old mark.
- **Other hotkey tools, Linux, Windows.** Anything that can run a command can add to the inbox:

  ```bash
  node /path/to/steerpin/scripts/steerpin.mjs capture wrong "the selected text"
  ```

  Or use `/steerpin:mark` inside Claude Code.
- **If the hook breaks** (Node missing, unreadable file), your message still goes through. The hook never blocks a prompt.

## Development

```bash
node test/run-tests.mjs
```

```bash
claude --plugin-dir .
```

Set `STEERPIN_HOME` to use a different inbox folder while testing.

## License

MIT
