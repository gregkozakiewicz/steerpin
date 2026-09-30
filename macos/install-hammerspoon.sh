#!/bin/sh
# Copies steerpin.lua into ~/.hammerspoon, loads it from init.lua and restarts Hammerspoon. Run again after updating.
set -e
if [ ! -d /Applications/Hammerspoon.app ] && [ ! -d "$HOME/Applications/Hammerspoon.app" ]; then
  echo "Hammerspoon is not installed. Install it first: brew install --cask hammerspoon"
  exit 1
fi
if pgrep -xq Steerpin; then
  echo "The Steerpin app is running and already handles the hotkeys. Quit it first if you want to use Hammerspoon instead."
  exit 1
fi
src="$(cd "$(dirname "$0")" && pwd)/hammerspoon/steerpin.lua"
dir="$HOME/.hammerspoon"
mkdir -p "$dir"
cp "$src" "$dir/steerpin.lua"
touch "$dir/init.lua"
if ! grep -q 'require("steerpin")' "$dir/init.lua"; then
  printf '\nrequire("steerpin")\n' >> "$dir/init.lua"
fi
# Restart Hammerspoon so it loads the new config.
if pgrep -xq Hammerspoon; then
  pkill -x Hammerspoon
  while pgrep -xq Hammerspoon; do sleep 0.1; done
fi
open -g -a Hammerspoon
echo "Hotkeys are on: ⌥⇧R priority, ⌥⇧W wrong, ⌥⇧A roadmap, ⌥⇧S later."
