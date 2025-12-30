
#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_FILE="$CACHE_DIR/sway-float-tile-geom.json"
mkdir -p "$CACHE_DIR"
[[ -f "$CACHE_FILE" ]] || printf '{}' > "$CACHE_FILE"

# ---- helpers for cache ----
cache_get() {
  local key="$1"
  # Prefer per-window (con_id) entry; fall back to per-app_id entry
  jq -c --arg k "$key" --arg aid "$APP_ID" '
    if has($k) then .[$k]
    elif (.by_app // {} | has($aid)) then .by_app[$aid]
    else empty end
  ' "$CACHE_FILE"
}

cache_set() {
  local key="$1"
  local json="$2"
  local tmp
  tmp="$(mktemp)"
  jq -c --arg k "$key" --arg aid "$APP_ID" --argjson obj "$json" '
    .[$k] = $obj
    | .by_app = (.by_app // {})
    | .by_app[$aid] = $obj
  ' "$CACHE_FILE" > "$tmp"
  mv "$tmp" "$CACHE_FILE"
}

# ---- read sway tree once ----
TREE="$(swaymsg -t get_tree)"

# Focused leaf container (tiled or floating)
FOCUSED="$(jq -c '
  .. | objects
  | select((.type=="con" or .type=="floating_con") and (.focused==true))
  | {id, app_id, floating, rect}
' <<<"$TREE" | head -n 1)"

[[ -n "${FOCUSED:-}" ]] || exit 0

CON_ID="$(jq -r '.id' <<<"$FOCUSED")"
APP_ID="$(jq -r '.app_id // "unknown"' <<<"$FOCUSED")"
FLOATING_STATE="$(jq -r '.floating // ""' <<<"$FOCUSED")"

CUR_W="$(jq -r '.rect.width'  <<<"$FOCUSED")"
CUR_H="$(jq -r '.rect.height' <<<"$FOCUSED")"
CUR_X="$(jq -r '.rect.x'      <<<"$FOCUSED")"
CUR_Y="$(jq -r '.rect.y'      <<<"$FOCUSED")"

# Find the workspace name containing this container
CUR_WS="$(jq -r --argjson cid "$CON_ID" '
  .. | objects
  | select(.type=="workspace")
  | select([.. | objects | select(.id? == $cid)] | length > 0)
  | .name
' <<<"$TREE" | head -n 1)"

# Determine if currently floating (suffix _on in sway: user_on/auto_on)
IS_FLOATING=0
[[ "$FLOATING_STATE" == *"_on" ]] && IS_FLOATING=1

# ---- load stored state (if exists) ----
KEY="$CON_ID"
STORED="$(cache_get "$KEY" || true)"

# Defaults if nothing saved yet
# float defaults:
SF_W=1200; SF_H=800; SF_X=60; SF_Y=60
# tile defaults:
ST_W="$CUR_W"; ST_H="$CUR_H"; ST_X="$CUR_X"; ST_Y="$CUR_Y"; ST_WS="$CUR_WS"

if [[ -n "${STORED:-}" ]]; then
  SF_W="$(jq -r '.float.w // 1200' <<<"$STORED")"
  SF_H="$(jq -r '.float.h // 800'  <<<"$STORED")"
  SF_X="$(jq -r '.float.x // 60'   <<<"$STORED")"
  SF_Y="$(jq -r '.float.y // 60'   <<<"$STORED")"

  ST_W="$(jq -r '.tile.w // '"$CUR_W" <<<"$STORED")"
  ST_H="$(jq -r '.tile.h // '"$CUR_H" <<<"$STORED")"
  ST_X="$(jq -r '.tile.x // '"$CUR_X" <<<"$STORED")"
  ST_Y="$(jq -r '.tile.y // '"$CUR_Y" <<<"$STORED")"
  ST_WS="$(jq -r '.tile.ws // "'"$CUR_WS"'"' <<<"$STORED")"
fi

# ---- main toggle logic ----
if [[ "$IS_FLOATING" -eq 1 ]]; then
  # ========== FLOATING -> TILED ==========
  # Save CURRENT floating geometry
  NEW_OBJ="$(jq -n --arg aid "$APP_ID" \
    --argjson fw "$CUR_W" --argjson fh "$CUR_H" --argjson fx "$CUR_X" --argjson fy "$CUR_Y" \
    --argjson tw "$ST_W" --argjson th "$ST_H" --argjson tx "$ST_X" --argjson ty "$ST_Y" --arg tws "$ST_WS" \
    '{app_id:$aid, float:{w:$fw,h:$fh,x:$fx,y:$fy}, tile:{w:$tw,h:$th,x:$tx,y:$ty,ws:$tws}}'
  )"
  cache_set "$KEY" "$NEW_OBJ"

  # Go back to the workspace we were tiled on (if known)
  if [[ -n "${ST_WS:-}" ]]; then
    swaymsg -q -- "[con_id=$CON_ID] move container to workspace \"$ST_WS\"" || true
  fi

  # Disable floating
  swaymsg -q -- "[con_id=$CON_ID] floating disable"

  # Re-fetch tree after state change
  TREE2="$(swaymsg -t get_tree)"

  # Find best-overlap tiled container on that workspace to swap with
  # Then swap positions (this restores the "tiled side/slot" best-effort).
  TARGET_ID="$(jq -r --arg ws "$ST_WS" --argjson cid "$CON_ID" \
    --argjson tx "$ST_X" --argjson ty "$ST_Y" --argjson tw "$ST_W" --argjson th "$ST_H" '
    def overlap(a; b):
      ( [ (a.x + a.w), (b.x + b.w) ] | min ) as $rx
      | ( [ a.x, b.x ] | max ) as $lx
      | ( [ (a.y + a.h), (b.y + b.h) ] | min ) as $by
      | ( [ a.y, b.y ] | max ) as $tyy
      | (($rx - $lx) | if . > 0 then . else 0 end) as $ow
      | (($by - $tyy) | if . > 0 then . else 0 end) as $oh
      | ($ow * $oh);

    [ .. | objects
      | select(.type=="workspace" and .name==$ws)
      | .. | objects
      | select(.type=="con" and (.id? != $cid))
      | {id, r:{x:.rect.x, y:.rect.y, w:.rect.width, h:.rect.height}}
    ]
    | map(. + {score: overlap({x:$tx,y:$ty,w:$tw,h:$th}; .r)})
    | sort_by(.score) | last
    | if .score > 0 then .id else empty end
  ' <<<"$TREE2" | head -n 1)"

  if [[ -n "${TARGET_ID:-}" ]]; then
    # swap container with con_id is a real sway command (expected syntax shown in sway source) [4](https://rgoswami.me/posts/lowering-resource-usage-foot-systemd/)
    swaymsg -q -- "[con_id=$CON_ID] swap container with con_id $TARGET_ID" || true
  fi

  # Restore the resized tile dimensions too
  # resize set <w> [px|ppt] <h> [px|ppt] is supported [3](https://glfs-book.github.io/slfs/graph/foot.html)
  swaymsg -q -- "[con_id=$CON_ID] resize set ${ST_W} px ${ST_H} px" || true

else
  # ========== TILED -> FLOATING ==========
  # Save CURRENT tiled geometry + workspace ("other side" memory)
  NEW_OBJ="$(jq -n --arg aid "$APP_ID" \
    --argjson fw "$SF_W" --argjson fh "$SF_H" --argjson fx "$SF_X" --argjson fy "$SF_Y" \
    --argjson tw "$CUR_W" --argjson th "$CUR_H" --argjson tx "$CUR_X" --argjson ty "$CUR_Y" --arg tws "$CUR_WS" \
    '{app_id:$aid, float:{w:$fw,h:$fh,x:$fx,y:$fy}, tile:{w:$tw,h:$th,x:$tx,y:$ty,ws:$tws}}'
  )"
  cache_set "$KEY" "$NEW_OBJ"

  # Enable floating and restore floating size+position
  # Use move *absolute* position to avoid output-relative behavior issues [1](https://www.usna.edu/Users/cs/wcbrown/courses/IC221/classes/L12/Class.html)[2](https://www.geeksforgeeks.org/python/change-the-line-opacity-in-matplotlib/)
  swaymsg -q -- "[con_id=$CON_ID] floating enable, resize set ${SF_W} px ${SF_H} px, move absolute position ${SF_X} ${SF_Y}" || true
fi

