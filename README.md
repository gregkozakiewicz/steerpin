# Steerpin

Mark text in a Claude Code chat with a hotkey. Highlight a sentence, press a key, and Claude keeps that mark in mind on every message until you remove it.

| Keys | Mark | What Claude does |
|---|---|---|
| `⌥⇧R` | **Priority** | Keeps it at the top of its attention, every turn |
| `⌥⇧W` | **Wrong** | Stops relying on it, and corrects anything built on it |
| `⌥⇧A` | **Add to roadmap** | Nothing. The text is saved to `docs/steerpin/roadmap.md`, word for word |
| `⌥⇧S` | **Save for later** | Nothing. The text is saved to `docs/steerpin/later.md`, word for word |

`⌥` is Option and `⇧` is Shift. All four keys sit under your left hand.

**Why:** in long sessions, important points drift out of focus and wrong statements get reused as fact. The chat has no way to mark text, and plugins can't add buttons to it. So Steerpin marks text with system-wide hotkeys, and a Claude Code hook passes the marks to Claude. They survive long chats and `/compact`.

## Setup

About five minutes. You need:

- macOS (for the hotkeys; on other systems, see [Without hotkeys](#without-hotkeys))
- [Claude Code](https://code.claude.com)
- [Node.js](https://nodejs.org) 18 or later. Check with `node --version`.

### Step 1: install the plugin

In Claude Code, run these two commands:

```
/plugin marketplace add gregkozakiewicz/steerpin
```

```
/plugin install steerpin@steerpin
```

Then quit and reopen Claude Code so the plugin loads.

### Step 2: install Hammerspoon

[Hammerspoon](https://www.hammerspoon.org) is a free, open source Mac app that runs small scripts when you press a key. Steerpin uses it for the hotkeys.

1. **Install it.** With [Homebrew](https://brew.sh):

   ```bash
   brew install --cask hammerspoon
   ```

   Or download the latest `Hammerspoon-x.x.x.zip` from [its releases page](https://github.com/Hammerspoon/hammerspoon/releases/latest), unzip it, and drag **Hammerspoon.app** into **Applications**.

2. **Open it** from Applications. If macOS says it was downloaded from the internet, click **Open**.

3. **Set its preferences.** A Preferences window opens the first time (later: click the hammer icon in the menu bar › **Preferences…**). Tick:
   - **Launch Hammerspoon at login**, so the hotkeys work after a restart
   - **Show menu icon**, so you can reload it from the menu bar

4. **Give it Accessibility access.** Hammerspoon needs this to copy your selection.
   1. Open **System Settings › Privacy & Security › Accessibility**. (The **Enable Accessibility** button in Hammerspoon's Preferences takes you there too.)
   2. Turn on the switch next to **Hammerspoon**. macOS asks for your password or Touch ID.
   3. If Hammerspoon isn't in the list, click **+** at the bottom, choose **Applications › Hammerspoon**, then turn it on.

   Note: **Accessibility** is a different page from **Menu Bar** in System Settings. The switch has to be on the Accessibility page.

### Step 3: add the Steerpin hotkeys

In Claude Code, run:

```
/steerpin:setup-hotkeys
```

If you forget, Steerpin reminds you: when a session starts and Hammerspoon is installed but the hotkeys aren't, you'll see `steerpin: Hammerspoon found. Run /steerpin:setup-hotkeys to turn on the hotkeys.` The same reminder appears when a plugin update brings new hotkeys.

This copies the hotkey script into `~/.hammerspoon/` and loads it from your `~/.hammerspoon/init.lua`. Any Hammerspoon config you already have stays as it is.

Then click the hammer icon in the menu bar › **Reload Config**. When macOS asks whether Hammerspoon can send notifications, click **Allow**.

### Step 4: test it

1. Select a sentence anywhere, for example in a browser.
2. Press `⌥⇧R`.
3. A notification should say **Marked as priority** with a preview of your text.

Then in Claude Code, send any message. You'll see a line like `steerpin: new mark [1]`, and Claude now has the mark.

If something doesn't work, see [Troubleshooting](#troubleshooting).

## Using it

1. Claude writes an answer.
2. Select the part you want to mark and press a hotkey. The notification's title tells you which mark you made.
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

### Commands

| Command | What it does |
|---|---|
| `/steerpin:marks` | List active marks with their ids |
| `/steerpin:unmark 3` | Remove mark 3. Several at once: `/steerpin:unmark 3 5` |
| `/steerpin:clear-marks` | Remove all priority and wrong marks. Roadmap and later files are not touched |
| `/steerpin:mark wrong <text>` | Mark text without a hotkey. Also `priority`, `roadmap`, `later` |
| `/steerpin:setup-hotkeys` | Install or update the Hammerspoon hotkeys |

## Troubleshooting

**Nothing happens when I press the keys.**
- Check that Hammerspoon is running: the hammer icon should be in the menu bar.
- Check that its switch is on in **System Settings › Privacy & Security › Accessibility**. If it is and the keys still don't work, turn it off and on again, then **Reload Config**.
- Click the hammer icon › **Console…** and look for red error lines.

**The notification says "No text selected".**
Select the text again and press the key while the selection is still highlighted. Some apps clear the selection when you click elsewhere.

**No notification appears, but marks do arrive.**
Allow notifications for Hammerspoon in **System Settings › Notifications › Hammerspoon**.

**Claude doesn't see my marks.**
- Quit and reopen Claude Code after installing the plugin.
- Check that Node.js works: `node --version`.
- Run `/steerpin:marks` to see what's active.

**My clipboard changed.**
It shouldn't: Steerpin puts back whatever you had copied. If it happens, tell us in an [issue](https://github.com/gregkozakiewicz/steerpin/issues) which app you were marking from.

## Changing the keys

Open `~/.hammerspoon/init.lua` and replace the line `require("steerpin")` with, for example:

```lua
require("steerpin").setup({
  keys = {
    priority = { { "ctrl", "alt" }, "r" },
    later = false, -- turns this key off
  },
})
```

Keys you don't list keep their defaults. Reload Config afterwards. Running `/steerpin:setup-hotkeys` again won't undo your changes.

## Without hotkeys

On Linux or Windows, or if you'd rather not use Hammerspoon, mark text inside Claude Code with `/steerpin:mark`:

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
  "roadmap": "docs/steerpin/roadmap.md",
  "later": "docs/steerpin/later.md",
  "maxActiveMarks": 15,
  "maxMarkLength": 500
}
```

- `roadmap`, `later`: where saved items go, relative to the project root. Missing files and folders are created.
- `maxActiveMarks`: at most this many marks (the newest) are sent to Claude.
- `maxMarkLength`: longer marks are shortened in what Claude sees. The full text stays in `marks.md`.

## Where things are saved

| Path | What |
|---|---|
| `~/.steerpin/inbox.jsonl` | Where the hotkeys write. Emptied on your next message |
| `.claude/steerpin/marks.md` | Active priority and wrong marks for this project. You can edit it by hand |
| `docs/steerpin/roadmap.md`, `docs/steerpin/later.md` | Saved roadmap and later items |

Marks are personal, so you'll usually want to keep them out of git. Add this to `.gitignore`:

```gitignore
.claude/steerpin/marks.md
```

## Good to know

- **Two Claude Code sessions open at once.** The hotkeys don't know which project you're in. Marks go to whichever session you send the next message in.
- **Marking while Claude is still answering** is fine. The marks arrive with your next message.
- **Marking the same text twice** does nothing. Marking it with a different type (priority, then wrong) replaces the old mark.
- **If something breaks**, your message still goes through. Steerpin never blocks a prompt.

## Development

```bash
node test/run-tests.mjs
```

```bash
claude --plugin-dir .
```

Set `STEERPIN_HOME` to use a separate inbox folder while testing.

## License

MIT
