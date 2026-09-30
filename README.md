<img src="macos/app/icon/AppIcon-preview.png" width="96" alt="">

# Steerpin

Mark text in a Claude Code chat with a hotkey. Highlight a sentence, press a key, and Claude keeps that mark in mind on every message until you remove it.

| Keys | Mark | What Claude does |
|---|---|---|
| `⌥⇧R` | **Priority** | Keeps it at the top of its attention, every turn |
| `⌥⇧W` | **Wrong** | Stops relying on it, and corrects anything built on it |
| `⌥⇧A` | **Add to roadmap** | Nothing. The text is saved to `.claude/steerpin/roadmap.md`, word for word |
| `⌥⇧S` | **Save for later** | Nothing. The text is saved to `.claude/steerpin/later.md`, word for word |

Marked the wrong thing? `⌥⇧Z` undoes your last mark. Using ChatGPT or Claude.ai? `⌥⇧C` copies your marks to paste into any chat.

`⌥` is Option and `⇧` is Shift. All the keys sit under your left hand.

**Why:** in long sessions, important points drift out of focus and wrong statements get reused as fact. The chat has no way to mark text, and plugins can't add buttons to it. So Steerpin marks text with system-wide hotkeys, and a Claude Code hook passes the marks to Claude. They survive long chats and `/compact`.

## Setup

About three minutes. You need:

- macOS 13 or later (on other systems, see [Without hotkeys](#without-hotkeys))
- [Claude Code](https://code.claude.com)
- [Node.js](https://nodejs.org) 18 or later. Check with `node --version`.

### Step 1: download the app

**[Download Steerpin.zip](https://github.com/gregkozakiewicz/steerpin/releases/latest/download/Steerpin.zip)**, unzip it, and drag **Steerpin.app** into **Applications**.

Steerpin is a small menu bar app. It owns the hotkeys, copies your selection, puts your clipboard back, and confirms each mark with a popup under its pin icon.

### Step 2: open it

The app isn't signed with a paid Apple developer account, so the first time you open it macOS says it can't verify it:

1. Click **Done** (not Move to Trash).
2. Open **System Settings › Privacy & Security**, scroll down to the message about Steerpin, and click **Open Anyway**. Confirm with your password or Touch ID.

You only do this once.

### Step 3: allow Accessibility

macOS asks right away. Click **Open System Settings** and turn on **Steerpin**. The app needs this to copy your selection, and it's the only permission it asks for.

When the pin icon appears in your menu bar and **Steerpin is ready** shows under it, this step is done.

### Step 4: connect to Claude Code

The app asks **Connect Steerpin to Claude Code?** Click **Connect**. It installs the Steerpin plugin into Claude Code for you. Then quit and reopen Claude Code.

Missed the question? Click the pin icon › **Connect to Claude Code**.

Finally, click the pin icon and turn on **Launch at Login**, so the hotkeys keep working after a restart.

### Test it

1. Select a sentence anywhere, for example in a browser.
2. Press `⌥⇧R`. A popup under the pin says **Marked as priority**.
3. In Claude Code, send any message. You'll see `steerpin: new mark [1]`, and Claude now has the mark.

If something doesn't work, see [Troubleshooting](#troubleshooting).

## Using it

1. Claude writes an answer.
2. Select the part you want to mark and press a hotkey. The popup tells you which mark you made.
3. Send your next message as normal.

With your message, Claude receives your active marks:

```
USER MARKS (set by the user by highlighting text in this chat)

Priority, keep these at the top of your attention:
[1] Tokens must stay platform-agnostic until the export step

Flagged as wrong, do not rely on or repeat these. If anything
you said or built depends on them, say so briefly and correct it:
[2] "Style Dictionary can't handle composite tokens"

New since last message: [2]
Start your reply with one short line per new wrong mark, e.g. "Noted, [2] was wrong: <what is actually true>". Then answer the message.
```

When you mark something as wrong, Claude opens its next reply with a line like *"Noted, [2] was wrong: …"*. Priority and wrong marks are sent again with every message until you remove them. Roadmap and later marks are written to their files once and aren't sent to Claude.

### Undo

- **Before you send your next message:** press `⌥⇧Z` (or pin menu › **Undo Last Mark**). The newest waiting mark is removed, and Claude never sees it.
- **After you sent it:** run `/steerpin:undo` in Claude Code. It removes what that message delivered, and if a mark replaced an older one (priority re-marked as wrong), it brings the old one back.

### Other chats (ChatGPT, Claude.ai, …)

Chats outside Claude Code can't receive marks automatically, so the app keeps them for you:

1. Mark text with `⌥⇧R` (priority) or `⌥⇧W` (wrong), as usual.
2. Press `⌥⇧C` (or pin menu › **Copy Marks**).
3. Paste into your chat with `⌘V`. Claude, ChatGPT or any other assistant gets a short block listing your priorities and what was wrong.

Paste it again whenever the chat starts drifting, or in a new chat. **Clear Chat Marks** in the pin menu starts over.

### The menu bar app

Click the pin icon to see the shortcuts, how many marks are waiting for your next message, your recent marks, the Claude Code connection, **Launch at Login**, and **Quit**. When the app is newer than your Claude Code plugin, it offers **Update Plugin**. A crossed-out pin means Accessibility access is off.

### Commands

| Command | What it does |
|---|---|
| `/steerpin:marks` | List active marks with their ids |
| `/steerpin:unmark 3` | Remove mark 3. Several at once: `/steerpin:unmark 3 5` |
| `/steerpin:clear-marks` | Remove all priority and wrong marks. Roadmap and later files are not touched |
| `/steerpin:undo` | Take back everything your last message delivered: marks, roadmap and later items |
| `/steerpin:mark wrong <text>` | Mark text without a hotkey. Also `priority`, `roadmap`, `later` |
| `/steerpin:setup-hotkeys` | Only for the [Hammerspoon alternative](#alternative-hammerspoon) |

## Troubleshooting

**Nothing happens when I press the keys.**
- Check that Steerpin is running: the pin icon should be in the menu bar. If not, open it from Applications.
- If the pin is crossed out, click it › **Allow Accessibility Access…** and turn Steerpin on.
- If Accessibility looks on but the pin stays crossed out, macOS is holding an outdated entry. This can happen once when updating from 0.2.1 or earlier. Run `tccutil reset Accessibility com.gregkozakiewicz.steerpin` in Terminal, then allow Steerpin again.
- Click the pin icon. If a shortcut says **(used by another app)**, another app has taken that key combination. Quit that app, then quit and reopen Steerpin.

**The popup says "No text selected".**
Select the text again and press the key while the selection is still highlighted. Some apps clear the selection when you click elsewhere.

**Claude doesn't see my marks.**
- Click the pin icon and check that the **Claude Code** section says **Connected**. If it offers **Connect** or **Update Plugin**, click it.
- Quit and reopen Claude Code after connecting.
- Check that Node.js works: `node --version`.
- Run `/steerpin:marks` to see what's active.

**My clipboard changed.**
It shouldn't: Steerpin puts back whatever you had copied. If it happens, tell us in an [issue](https://github.com/gregkozakiewicz/steerpin/issues) which app you were marking from.

## Alternative: Hammerspoon

If you already use [Hammerspoon](https://www.hammerspoon.org), you can run the hotkeys there instead of the app. Don't run both: they use the same shortcuts.

1. Install Hammerspoon (`brew install --cask hammerspoon`), open it, and turn it on in **System Settings › Privacy & Security › Accessibility**.
2. In Claude Code, run `/steerpin:setup-hotkeys`. It adds the Steerpin script to `~/.hammerspoon/` and restarts Hammerspoon. Your existing Hammerspoon config stays as it is.

When a plugin update changes the hotkeys, a session-start message reminds you to run `/steerpin:setup-hotkeys` again.

To change keys, replace `require("steerpin")` in `~/.hammerspoon/init.lua` with, for example:

```lua
require("steerpin").setup({
  keys = {
    priority = { { "ctrl", "alt" }, "r" },
    later = false, -- turns this key off
  },
})
```

## Installing the plugin by hand

The app installs the plugin for you. To do it yourself instead, for example on Linux or Windows, run these in Claude Code, then restart it:

```
/plugin marketplace add gregkozakiewicz/steerpin
```

```
/plugin install steerpin@steerpin
```

## Without hotkeys

On Linux or Windows, or if you'd rather not install the app, mark text inside Claude Code with `/steerpin:mark`:

```
/steerpin:mark wrong esbuild can't generate type declarations
```

Other hotkey tools (Raycast, Keyboard Maestro, AutoHotkey) can write to the same inbox by running:

```bash
node ~/.claude/plugins/marketplaces/steerpin/scripts/steerpin.mjs capture wrong "the selected text"
```

## Settings

Optional, per project, in `.claude/steerpin/config.json`. Anything you leave out uses the default:

```json
{
  "roadmap": ".claude/steerpin/roadmap.md",
  "later": ".claude/steerpin/later.md",
  "maxActiveMarks": 15,
  "maxMarkLength": 500
}
```

- `roadmap`, `later`: where saved items go, relative to the project root. Missing files and folders are created. To share your roadmap with the team, point it somewhere git tracks, such as `"docs/roadmap.md"`.
- `maxActiveMarks`: at most this many marks (the newest) are sent to Claude.
- `maxMarkLength`: longer marks are shortened in what Claude sees. The full text stays in `marks.md`.

## Where things are saved

Everything stays private to you, in one folder per project:

| Path | What | Cleared by `/steerpin:clear-marks`? |
|---|---|---|
| `.claude/steerpin/marks.md` | Active priority and wrong marks | Yes |
| `.claude/steerpin/roadmap.md` | Roadmap items | No |
| `.claude/steerpin/later.md` | Save-for-later items | No |
| `.claude/steerpin/config.json` | Optional [settings](#settings) | No |
| `~/.steerpin/inbox.jsonl` | Where the hotkeys write, in your home folder. Emptied on your next message | |

All of these are plain Markdown or JSON, so you can open and edit them by hand.

The first time Steerpin saves something in a git repository, it adds `.claude/steerpin/` to the project's `.gitignore` and tells you once. Your marks, roadmap and later items are never committed unless you change that.

Each project folder has its own set. Opening Claude Code in a different folder starts with no marks; the old folder's marks are still there when you go back.

## Good to know

- **New chat, same project.** Marks belong to the project folder, so a new chat starts with the old ones. You'll see `steerpin: 3 marks carried over from an earlier chat…`. Keep going if you're continuing the same work, or run `/steerpin:clear-marks` to start fresh.
- **Two Claude Code sessions open at once.** The hotkeys don't know which project you're in. Marks go to whichever session you send the next message in.
- **Marking while Claude is still answering** is fine. The marks arrive with your next message.
- **Marking the same text twice** does nothing. Marking it with a different type (priority, then wrong) replaces the old mark.
- **If something breaks**, your message still goes through. Steerpin never blocks a prompt.

## Development

```bash
node test/run-tests.mjs
```

```bash
macos/app/build.sh
```

The app is plain Swift built with the Command Line Tools, no Xcode needed. `build.sh` makes a universal `Steerpin.app` and `Steerpin.zip` in `macos/app/build/`.

```bash
claude --plugin-dir .
```

Set `STEERPIN_HOME` to use a separate inbox folder while testing.

## License

MIT
