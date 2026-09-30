-- Steerpin hotkeys for Hammerspoon.
-- Copies the current selection, appends it to ~/.steerpin/inbox.jsonl with a type,
-- restores your clipboard, and shows a notification.
--
-- Load it from ~/.hammerspoon/init.lua:
--   require("steerpin")
-- or with your own keys:
--   require("steerpin").setup({ keys = { priority = {{"ctrl","alt"}, "p"} } })

local M = {}

M.defaults = {
  inboxDir = os.getenv("HOME") .. "/.steerpin",
  longSelection = 500, -- warn above this many characters (matches maxMarkLength)
  keys = {
    priority = { { "alt", "shift" }, "p" },
    wrong    = { { "alt", "shift" }, "x" },
    roadmap  = { { "alt", "shift" }, "r" },
    later    = { { "alt", "shift" }, "l" }, -- set to false to disable
  },
}

local labels = {
  priority = "Marked as priority",
  wrong    = "Marked as wrong",
  roadmap  = "Saved to roadmap",
  later    = "Saved for later",
}

local function notify(title, text)
  hs.notify.new({ title = title, informativeText = text or "", withdrawAfter = 3 }):send()
end

-- Sends Cmd+C and waits for the pasteboard to change. Returns the copied text or nil.
local function copySelection()
  local before = hs.pasteboard.changeCount()
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  local deadline = hs.timer.secondsSinceEpoch() + 0.6
  while hs.pasteboard.changeCount() == before do
    if hs.timer.secondsSinceEpoch() > deadline then return nil end
    hs.timer.usleep(20000)
  end
  return hs.pasteboard.getContents()
end

local function appendToInbox(dir, entry)
  hs.fs.mkdir(dir)
  local f, err = io.open(dir .. "/inbox.jsonl", "a")
  if not f then return false, err end
  f:write(hs.json.encode(entry) .. "\n")
  f:close()
  return true
end

function M.capture(markType, opts)
  opts = opts or M.defaults
  local app = hs.application.frontmostApplication()
  local saved = hs.pasteboard.readAllData()

  local text = copySelection()

  -- Put the user's clipboard back, whatever it held.
  if saved and next(saved) then hs.pasteboard.writeAllData(saved) else hs.pasteboard.clearContents() end

  if not text or not text:match("%S") then
    notify("Steerpin", "No text selected")
    return
  end

  local ok, err = appendToInbox(opts.inboxDir, {
    type = markType,
    text = text,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    source_app = app and app:name() or "",
  })
  if not ok then
    notify("Steerpin failed", tostring(err))
    return
  end

  local preview = text:gsub("%s+", " ")
  if #preview > 80 then preview = preview:sub(1, 77) .. "..." end
  if #text > opts.longSelection then
    preview = "Long selection, will be shortened in Claude's context. " .. preview
  end
  notify(labels[markType], preview)
end

M.hotkeys = {}

function M.setup(user)
  user = user or {}
  local opts = {
    inboxDir = user.inboxDir or M.defaults.inboxDir,
    longSelection = user.longSelection or M.defaults.longSelection,
    keys = {},
  }
  for markType, key in pairs(M.defaults.keys) do opts.keys[markType] = key end
  for markType, key in pairs(user.keys or {}) do opts.keys[markType] = key end

  for _, hk in ipairs(M.hotkeys) do hk:delete() end
  M.hotkeys = {}
  for markType, key in pairs(opts.keys) do
    if key then
      local hk = hs.hotkey.bind(key[1], key[2], function()
        -- Let the hotkey's own key events settle before sending Cmd+C.
        hs.timer.doAfter(0.05, function() M.capture(markType, opts) end)
      end)
      table.insert(M.hotkeys, hk)
    end
  end
  return M
end

return M.setup()
