#!/usr/bin/env bash
# Install (or remove) a LaunchAgent that regenerates the wallpaper every day.
#
#   ./scripts/install-launchagent.sh          install, run daily at 00:05
#   ./scripts/install-launchagent.sh 09:30    install, run daily at 09:30
#   ./scripts/install-launchagent.sh --uninstall
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.shivampwm2020.yearwallpaper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$REPO/bin/YearWallpaper"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled. The wallpaper will stay as-is; nothing further will run."
  exit 0
fi

TIME="${1:-00:05}"
if [[ ! $TIME =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
  echo "Time must look like HH:MM (24-hour), e.g. 00:05 or 09:30" >&2
  exit 1
fi
HOUR="${BASH_REMATCH[1]}"
MINUTE="${BASH_REMATCH[2]}"

# The regex bounds digit count, not range, so 99:99 would otherwise slip
# through and later break printf. 10# forces base-10: plain $(( 09 )) is an
# invalid octal literal in bash 3.2.
if (( 10#$HOUR > 23 )) || (( 10#$MINUTE > 59 )); then
  echo "Hour must be 00-23 and minutes 00-59 (got $TIME)" >&2
  exit 1
fi

if [[ ! -x "$BIN" ]]; then
  echo "No binary at $BIN -- run ./scripts/build.sh first." >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

# StartCalendarInterval fires the job once a day at the given wall-clock time.
# If the Mac is asleep at that moment, launchd runs it shortly after wake.
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$HOUR</integer>
        <key>Minute</key>
        <integer>$MINUTE</integer>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/year-wallpaper.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/year-wallpaper.err.log</string>
</dict>
</plist>
PLIST_EOF

# bootout first so re-installing over an existing job works.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

# bootstrap also runs the job immediately (RunAtLoad), and that run happens
# inside this script -- so warn before, not after.
# Clear old logs first so the check below only sees this run's output.
: > /tmp/year-wallpaper.out.log
: > /tmp/year-wallpaper.err.log

echo "Loading the agent (it runs once now as a test)..."
echo "If macOS asks for permission to change your desktop picture, allow it."
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# RunAtLoad fires in the background, so give it a moment, then check the log
# to catch the common failure (denied desktop-picture permission).
sleep 3
if [[ -s /tmp/year-wallpaper.err.log ]]; then
  echo
  echo "Note: the test run reported errors:" >&2
  sed 's/^/  /' /tmp/year-wallpaper.err.log >&2
fi

HOUR_PAD=$(( 10#$HOUR ))
HOUR_PAD=$(printf '%02d' "$HOUR_PAD")
echo "Installed $LABEL -- runs daily at $HOUR_PAD:$MINUTE."
echo "Plist:  $PLIST"
echo "Logs:   /tmp/year-wallpaper.out.log and /tmp/year-wallpaper.err.log"
echo "Remove: ./scripts/install-launchagent.sh --uninstall"
