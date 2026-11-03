#!/usr/bin/env bash
# Smoke test: runs lanesnap against throwaway terminals on a scratch workspace and checks where
# the windows end up. Needs a running Hyprland session. Your windows are not touched, but the
# test briefly switches workspace, so don't type while it runs. Takes about a minute.
#   LANESNAP_TEST_WS=9 tests/smoke.sh
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$root/bin:$PATH"
# shellcheck source=../lib/hypr.sh
source "$root/lib/hypr.sh"

ws=${LANESNAP_TEST_WS:-9}
term=${LANESNAP_TEST_TERMINAL:-foot}
export LANESNAP_CONFIG=${LANESNAP_CONFIG:-$root/config/layouts.json}

if [[ $(hyprctl clients -j | jq --argjson ws "$ws" '[.[] | select(.workspace.id == $ws)] | length') != 0 ]]; then
  echo "workspace $ws is not empty; set LANESNAP_TEST_WS to an empty one" >&2; exit 2
fi
prev=$(hyprctl activeworkspace -j | jq .id)
pass=0 failed=0

# shellcheck disable=SC2329  # runs from the EXIT trap
cleanup() {
  for a in $(hyprctl clients -j | jq -r --argjson ws "$ws" '.[] | select(.workspace.id == $ws) | .address'); do hl_close_window "$a"; done
  hl_workspace_layout "$ws" dwindle
  hl_focus_workspace "$prev"
}
trap cleanup EXIT

spawn() { for _ in $(seq 1 "$1"); do hl_spawn_on "$ws" "$term"; sleep 0.6; done; hl_focus_workspace "$ws"; }
clear_ws() { for a in $(windows); do hl_close_window "$a"; done; sleep 0.5; }
windows() { hyprctl clients -j | jq -r --argjson ws "$ws" '.[] | select(.workspace.id == $ws) | .address'; }
# x and width of a window as fractions of the usable width (monitor minus bar and outer gaps)
frac() {
  local gaps
  gaps=$(hyprctl getoption general:gaps_out -j | jq -r '.css | split(" ")[0]')
  hyprctl clients -j | jq -r --arg a "$1" --argjson g "$gaps" --argjson m "$(hyprctl monitors -j | jq -c --argjson ws "$ws" '[.[] | select(.activeWorkspace.id == $ws)][0] // .[0]')" '
    ($m.x + $m.reserved[0] + $g) as $ux | ($m.width / $m.scale - $m.reserved[0] - $m.reserved[2] - 2 * $g) as $W
    | (.[] | select(.address == $a)) as $w
    | "\(($w.at[0] - $ux) / $W) \($w.size[0] / $W)"'
}
check() { # name actual expected tolerance
  if awk -v a="$2" -v e="$3" -v t="${4:-0.03}" 'BEGIN { d = a - e; if (d < 0) d = -d; exit !(d <= t) }'; then
    pass=$((pass + 1)); printf '  ok    %s (%.3f)\n' "$1" "$2"
  else failed=$((failed + 1)); printf '  FAIL  %s: got %.3f, expected %.3f\n' "$1" "$2" "$3"; fi
}

echo "thirds: one window into zones 1, 2, 3"
spawn 3; mapfile -t W < <(windows)
for z in 1 2 3; do
  LANESNAP_WINDOW=${W[0]} lanesnap thirds "$z"
  read -r x w < <(frac "${W[0]}")
  check "zone $z x" "$x" "$(awk -v z="$z" 'BEGIN { print (z - 1) / 3 }')"
  check "zone $z width" "$w" 0.333
done

echo "centre focus: middle zone is half the width"
LANESNAP_WINDOW=${W[0]} lanesnap focus 2; read -r x w < <(frac "${W[0]}"); check "x" "$x" 0.25; check "width" "$w" 0.5

echo "overflow: five windows in three zones fold the extras into the last zone"
clear_ws; spawn 5; mapfile -t W < <(windows)
LANESNAP_WINDOW=${W[0]} lanesnap focus 2
cols=$(hyprctl clients -j | jq --argjson ws "$ws" '[.[] | select(.workspace.id == $ws) | .at[0]] | unique | length')
check "column count" "$cols" 3 0
grouped=$(hyprctl clients -j | jq --argjson ws "$ws" '[.[] | select(.workspace.id == $ws and (.grouped | length) > 1)] | length')
check "windows in the tab group" "$grouped" 3 0

echo "single window: centred at its zone width"
clear_ws; spawn 1; mapfile -t W < <(windows)
LANESNAP_WINDOW=${W[0]} lanesnap focus 2; read -r x w < <(frac "${W[0]}"); check "x" "$x" 0.25; check "width" "$w" 0.5

echo "four columns from a custom layout"
clear_ws; spawn 4; mapfile -t W < <(windows)
tmp=$(mktemp); echo '{"layouts":{"q":{"label":"Q","zones":[[0,0,200,1000],[200,0,300,1000],[500,0,300,1000],[800,0,200,1000]]}},"order":["q"],"default":"q"}' >"$tmp"
LANESNAP_CONFIG=$tmp LANESNAP_WINDOW=${W[0]} lanesnap q 3; read -r x w < <(frac "${W[0]}"); check "zone 3 x" "$x" 0.5; check "zone 3 width" "$w" 0.3
rm -f "$tmp"

echo; echo "$pass passed, $failed failed"
exit $(( failed > 0 ))
