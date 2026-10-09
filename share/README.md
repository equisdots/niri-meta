# share/

Static data vendored by `dotsniri` so the meta is self-contained.

## `default_settings.json`

A copy of the shared equisdots default settings schema. `dotsniri` copies it to
`~/.config/hypr/settings.json` (and `~/.config/hypr/default_settings.json`) only
when those files are absent, so a standalone niri install has a working shell
configuration without running `dots`.

It is never used to overwrite existing user configuration, and it is not the
place to edit your settings: edit `~/.config/hypr/settings.json` (or use the
shell's settings UI) instead.

When the canonical default changes upstream, refresh this copy.
