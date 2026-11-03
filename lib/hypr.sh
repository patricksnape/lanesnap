#!/usr/bin/env bash
# Every Hyprland Lua-dispatcher string lanesnap uses lives in this file. The dispatcher API has
# changed between Hyprland releases, so a break should be a one-file fix. Sourced, not executed.

LANESNAP_SETTLE=${LANESNAP_SETTLE:-0.3}   # seconds to let the compositor lay out after a dispatch

hl_dispatch()        { hyprctl dispatch "$1" >/dev/null 2>&1 || true; sleep "$LANESNAP_SETTLE"; }
hl_focus_window()    { hl_dispatch "hl.dsp.focus({ window = \"address:$1\" })"; }
hl_focus_workspace() { hl_dispatch "hl.dsp.focus({ workspace = \"$1\" })"; }
hl_float_off()       { hl_dispatch "hl.dsp.window.float({ action = \"disable\", window = \"address:$1\" })"; }
hl_close_window()    { hl_dispatch "hl.dsp.window.close({ window = \"address:$1\" })"; }
# Prints a harmless "expected a dispatcher" error but applies the rule and re-lays out the workspace.
hl_workspace_layout() { hl_dispatch "hl.workspace_rule({ workspace = \"$1\", layout = \"$2\" })"; }
hl_layoutmsg()       { hl_dispatch "hl.dsp.layout(\"$1\")"; }
hl_group_toggle()    { hl_dispatch 'hl.dsp.group.toggle()'; }
hl_move_into_group() { hl_dispatch "hl.dsp.window.move({ into_group = \"$1\" })"; }
hl_out_of_group()    { hl_dispatch 'hl.dsp.window.move({ out_of_group = true })'; }
hl_cursor_move()     { hl_dispatch "hl.dsp.cursor.move({ x = $1, y = $2 })"; }
hl_spawn_on()        { hl_dispatch "hl.dsp.exec_cmd(\"$2\", { workspace = \"$1 silent\" })"; }

lanesnap_config() { printf '%s' "${LANESNAP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/lanesnap/layouts.json}"; }
