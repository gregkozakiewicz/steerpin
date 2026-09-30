#!/bin/sh
# Copies steerpin.lua into ~/.hammerspoon and loads it from init.lua. Run again after updating.
set -e
if [ ! -d /Applications/Hammerspoon.app ] && [ ! -d "$HOME/Applications/Hammerspoon.app" ]; then
  echo "Hammerspoon is not installed. Install it first: brew install --cask hammerspoon"
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
echo "Installed $dir/steerpin.lua. Reload Hammerspoon (menu bar icon > Reload Config)."
