# Changelog

## 0.1.0

First release.

- Zone presets as rows of columns, on Hyprland's scrolling layout; windows stay tiled and swap.
- Overlay and editor (`SUPER+Z`): switch presets, add or remove columns (2 to 9), drag dividers, name, save, delete.
- `CTRL+ALT+1..9` snap into zone N of the selected preset.
- Drag-to-zone with `SUPER+SHIFT` + left button (press/release binding, no compositor plugin).
- Windows beyond the column count fold into the last zone as a window group.
- Layout-aware `SUPER+J` and a `SUPER+SHIFT+Z` scrolling/dwindle toggle.
- `lanesnap-doctor`, a scratch-workspace smoke test, `make install/uninstall`.
