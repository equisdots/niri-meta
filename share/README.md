# share/

Static data vendored by `dotsniri` so the meta is self-contained.

## `default_settings.json`

A copy of the shared equisdots default settings schema. `deploy` prefers the
canonical copy from the shared `hyprland` clone
(`config/hypr/default_settings.json`), refreshes
`~/.config/hypr/default_settings.json`, and seeds `~/.config/hypr/settings.json`
from it when that file is absent. When the shared clone is unavailable, this
vendored copy is the fallback, so a standalone niri install still works without
running `dots`.

It is never used to overwrite user choices: on every deploy the defaults are
merged with the existing `settings.json` (the user's values win) and legacy keys
are migrated. It is not the place to edit your settings: edit
`~/.config/hypr/settings.json` (or use the shell's settings UI) instead.

When the canonical default changes upstream, refresh this copy so the fallback
matches `hyprland/config/hypr/default_settings.json` byte-for-byte.
