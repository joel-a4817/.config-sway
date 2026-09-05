#!/usr/bin/env bash
set -euo pipefail

OUT="$(swaymsg -t get_outputs -r | jq -r '.[] | select(.focused) | .name' | head -n1)"

[[ -n "$OUT" ]] || exit 1

TRANSFORM="$(
    swaymsg -t get_outputs -r |
    jq -r --arg out "$OUT" '
        .[] | select(.name==$out) | (.transform // "normal")
    '
)"

[[ -n "$TRANSFORM" ]] || TRANSFORM="normal"
need() { command -v "$1" >/dev/null 2>&1 || exit 1; }
need swaymsg
need jq

# Reload sway (this resets output + input state)
swaymsg reload

# Reapply the previous transform IF it was not normal
if [[ "$TRANSFORM" != "normal" ]]; then
  swaymsg output "$OUT" transform "$TRANSFORM"
fi

# Reapply pointer calibration matrix to match output transform
case "$TRANSFORM" in
  normal)
    swaymsg 'input type:pointer calibration_matrix 1 0 0 0 1 0'
    ;;
  90)
    swaymsg 'input type:pointer calibration_matrix 0 1 0 -1 0 1'
    ;;
  180)
    swaymsg 'input type:pointer calibration_matrix -1 0 1 0 -1 1'
    ;;
  270)
    swaymsg 'input type:pointer calibration_matrix 0 -1 1 1 0 0'
    ;;
esac
