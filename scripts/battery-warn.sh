
#!/usr/bin/env bash
# Battery warnings via swaynag: every 5 minutes, trigger once at each new % from 25 down.
# Visible over fullscreen via --layer overlay.

set -euo pipefail

BAT_PATH="/sys/class/power_supply/BAT0"   # change to BAT1 if your machine uses that
INTERVAL_SEC=300                          # 5 minutes
LOWEST_TRIGGER=25                         # start issuing warnings at 25%, then 24, 23, ...
SWAYNAG="/run/current-system/sw/bin/swaynag"   # NixOS path; use `which swaynag` to verify
LOG="${HOME}/.local/state/battery-interval-swaynag.log"
mkdir -p "$(dirname "$LOG")"

# If you want the "Open Terminal" button to run inside foot:
export TERMINAL=foot  # swaynag runs -b/-z actions inside this terminal if set.  (See swaynag(1))
# If you don't want a terminal button, you can unset this.

# Track which percentages have been notified during the current discharge session.
declare -A notified=()

echo "$(date -Iseconds) [START] battery interval swaynag watcher" >> "$LOG"

while true; do
  # Verify sysfs files exist
  if [[ ! -r "$BAT_PATH/capacity" || ! -r "$BAT_PATH/status" ]]; then
    echo "$(date -Iseconds) [ERR] $BAT_PATH not readable" >> "$LOG"
    sleep "$INTERVAL_SEC"
    continue
  fi

  cap=$(<"$BAT_PATH/capacity")
  status=$(<"$BAT_PATH/status")
  cap=${cap//[[:space:]]/}

  # ---- TEST MODE (uncomment for a quick test) ----
  # cap=15
  # status="Discharging"
  # -----------------------------------------------

  # Reset cache when charging/full
  if [[ "$status" != "Discharging" ]]; then
    notified=()
    echo "$(date -Iseconds) [INFO] status=$status cap=${cap}% (cache reset)" >> "$LOG"
    sleep "$INTERVAL_SEC"
    continue
  fi

  # Trigger only for integer percentages at/below LOWEST_TRIGGER and not yet notified
  if [[ "$cap" =~ ^[0-9]+$ ]] && (( cap <= LOWEST_TRIGGER )); then
    if [[ -z "${notified[$cap]:-}" ]]; then
      msg="Battery is at ${cap}%. Plug in now!"

      # Show swaynag over fullscreen using the overlay layer
      # NOTE:
      # - Use -s "OK" for a dismiss button with NO action.
      # - If you want a terminal button, add -b "Open Terminal" '<command>'
      "$SWAYNAG" --layer overlay \
        -t warning \
        -m "$msg" \
        -s "OK" \
        
      notified[$cap]=1
      echo "$(date -Iseconds) [WARN] ${msg} (triggered)" >> "$LOG"
    else
      echo "$(date -Iseconds) [INFO] ${cap}% already notified" >> "$LOG"
    fi
  else
    echo "$(date -Iseconds) [INFO] status=Discharging cap=${cap}% (above threshold)" >> "$LOG"
  fi

  sleep "$INTERVAL_SEC"
done

