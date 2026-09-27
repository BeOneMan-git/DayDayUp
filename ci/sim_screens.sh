#!/bin/bash
# iPad simulator smoke test for CI (GitHub macOS runner): installs the Debug simulator build, imports the
# original demo pack (ci/demo_pack.py) through the Debug-only launch hooks (DayDayUp/App/DebugHooks.swift),
# and takes screenshots of the main pages: portrait, dark, largest text size, landscape (when the Simulator app
# can be rotated on the runner) and iPad mini.
# Usage: ci/sim_screens.sh <path/to/DayDayUp.app> <demo.ecopack> <out dir>
set -u
APP="$1"
PACK="$2"
OUT="$3"
mkdir -p "$OUT"
LOG="$OUT/run.log"
: > "$LOG"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
ARTICLE="2026-01-03/trees"
log "app bundle: $BUNDLE"

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r.get("platform") == "iOS"]
rs.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')
log "runtime: $RUNTIME"
xcrun simctl list devicetypes | grep -i ipad >> "$LOG" 2>&1

devtypes() {  # every device type whose name contains $1, newest first
  xcrun simctl list devicetypes -j | python3 -c '
import json, sys
want = sys.argv[1]
ts = [t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if want in t["name"]]
print("\n".join(reversed(ts)))' "$1"
}

UDID=""
DATA=""
setup() {  # label, device type name part
  UDID=""
  if [ -z "$RUNTIME" ]; then
    log "skip $1: no iOS runtime"
    return 1
  fi
  local type
  for type in $(devtypes "$2"); do
    UDID=$(xcrun simctl create "$1" "$type" "$RUNTIME" 2>> "$LOG") && break
    UDID=""
  done
  if [ -z "$UDID" ]; then
    log "skip $1: no device type for '$2' works with $RUNTIME"
    return 1
  fi
  log "created $1 ($type) $UDID"
  xcrun simctl boot "$UDID" >> "$LOG" 2>&1
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
  xcrun simctl install "$UDID" "$APP" >> "$LOG" 2>&1 || { log "install failed"; return 1; }
  DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  cp "$PACK" "$DATA/Documents/"
  log "booted and installed"
  return 0
}

ui() {
  xcrun simctl ui "$UDID" "$@" >> "$LOG" 2>&1 || log "simctl ui $* not supported"
}

shot() {  # file name, launch arguments...
  local name="$1"
  shift
  local wait=7
  case "$name" in *import*) wait=12 ;; esac
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >> "$LOG" 2>&1
  sleep "$wait"
  local state="running"
  if ! xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE"; then
    state="NOT RUNNING (crash?)"
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  local size
  size=$(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" 2>/dev/null | awk '/pixel/ {printf "%s ", $2}')
  log "$name: $state ($size)"
}

# The app supports every orientation and multitasking, so it cannot turn itself; the Simulator app can
# (Device > Rotate, cmd-arrow) when the runner allows GUI scripting.
rotate() {  # left / right
  local key=124
  [ "$1" = "left" ] && key=123
  open -a Simulator --args -CurrentDeviceUDID "$UDID" >> "$LOG" 2>&1
  sleep 6
  osascript -e 'tell application "Simulator" to activate' -e 'delay 1' \
    -e "tell application \"System Events\" to key code $key using {command down}" >> "$LOG" 2>&1 \
    || log "rotate $1: GUI scripting not allowed on this runner"
  sleep 3
}

finish() {  # label
  cp "$DATA/Library/Caches/diag.log" "$OUT/$1-diag.log" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl shutdown "$UDID" >> "$LOG" 2>&1
}

if setup DDU-Pro13 "iPad Pro 13-inch"; then
  ui appearance light
  shot 00-import -DDUImportInbox 1 -DDUTab library
  shot 01-today -DDUTab today
  shot 02-library -DDUTab library
  shot 03-reader -DDUOpenArticle "$ARTICLE"
  shot 04-shadow -DDUTab shadow
  shot 05-vocab -DDUTab vocab
  shot 06-ielts -DDUTab ielts
  shot 07-progress -DDUTab progress
  shot 08-settings -DDUTab settings
  ui appearance dark
  shot 20-today-dark -DDUTab today
  shot 21-reader-dark -DDUOpenArticle "$ARTICLE"
  shot 22-progress-dark -DDUTab progress
  ui appearance light
  ui content_size accessibility-extra-extra-extra-large
  shot 30-today-largest-text -DDUTab today
  shot 31-reader-largest-text -DDUOpenArticle "$ARTICLE"
  shot 32-shadow-largest-text -DDUTab shadow
  shot 33-settings-largest-text -DDUTab settings
  ui content_size large
  rotate right
  shot 50-today-landscape -DDUTab today
  shot 51-reader-landscape -DDUOpenArticle "$ARTICLE"
  shot 52-shadow-landscape -DDUTab shadow
  shot 53-library-landscape -DDUTab library
  rotate left
  finish pro13
fi

if setup DDU-mini "iPad mini"; then
  ui appearance light
  shot 60-mini-import -DDUImportInbox 1 -DDUTab library
  shot 61-mini-reader -DDUOpenArticle "$ARTICLE"
  shot 62-mini-today -DDUTab today
  shot 63-mini-shadow -DDUTab shadow
  finish mini
fi

mkdir -p "$OUT/crashes"
cp ~/Library/Logs/DiagnosticReports/DayDayUp* "$OUT/crashes/" 2>/dev/null || true
log "files: $(ls "$OUT" | tr '\n' ' ')"
log "launches that were not running: $(grep -c 'NOT RUNNING' "$LOG")"
exit 0
