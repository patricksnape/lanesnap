#!/usr/bin/env bash
# Checks lanesnap's Hyprland Lua against the installed Hyprland without starting a compositor:
# hypr/lanesnap.lua must load and ci/api-check.lua must build every dispatcher lib/hypr.sh uses.
# Needs `Hyprland` on PATH; run it as an unprivileged user. Used by hyprland-compat.yml.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d); chmod 700 "$tmp"; trap 'rm -rf "$tmp"' EXIT
export XDG_RUNTIME_DIR=$tmp

# `o.bind` is Omarchy's helper; this stand-in lets hypr/lanesnap.lua load unmodified.
cat >"$tmp/good.lua" <<LUA
o = {
  bind = function(keys, description, dispatcher, options)
    local opts = options or {}
    if description then opts.description = description end
    if type(dispatcher) == "string" then dispatcher = hl.dsp.exec_cmd(dispatcher) end
    hl.bind(keys, dispatcher, opts)
  end,
}
dofile("$root/hypr/lanesnap.lua")
dofile("$root/ci/api-check.lua")
LUA
echo 'hl.bind("SUPER + Z", hl.dsp.window.no_such_dispatcher(), {})' >"$tmp/bad.lua"

verify() { Hyprland --verify-config -c "$1" 2>&1 | sed -n '/Config parsing result/,$p'; return "${PIPESTATUS[0]}"; }

echo "Hyprland $(Hyprland --version | head -1)"
# Control first: a config with a nonexistent dispatcher must fail, or a pass below means nothing.
if verify "$tmp/bad.lua" >/dev/null; then echo "control failed: a broken config passed" >&2; exit 1; fi
echo "control: broken config is rejected"

if verify "$tmp/good.lua"; then echo "lanesnap Lua OK"; else echo "lanesnap Lua FAILED on this Hyprland" >&2; exit 1; fi
