-- Builds every dispatcher that lib/hypr.sh sends, so `Hyprland --verify-config` fails if Hyprland
-- renames or removes one. Keep in sync with lib/hypr.sh (tests/lint checks the names match).
local win = "address:0x0"
local _ = {
  hl.dsp.focus({ window = win }),
  hl.dsp.focus({ workspace = "1" }),
  hl.dsp.window.float({ action = "disable", window = win }),
  hl.dsp.window.close({ window = win }),
  hl.dsp.layout("swapcol l"),
  hl.dsp.group.toggle(),
  hl.dsp.window.move({ into_group = "l" }),
  hl.dsp.window.move({ out_of_group = true }),
  hl.dsp.cursor.move({ x = 1, y = 1 }),
  hl.dsp.exec_cmd("true", { workspace = "1 silent" }),
}
hl.workspace_rule({ workspace = "1", layout = "scrolling" })
