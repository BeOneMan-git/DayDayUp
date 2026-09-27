#!/bin/bash
# iPad simulator smoke test for CI (GitHub macOS runner): installs the Debug simulator build, imports the
# original demo pack (ci/demo_pack.py) through the Debug-only launch hooks (DayDayUp/App/DebugHooks.swift),
# and takes screenshots of the main pages: landscape and portrait, light and dark, largest text size, iPad mini.
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

devtype() {  # newest device type whose name contains $1
  xcrun simctl list devicetypes -j | python3 -c '
import json, sys
want = sys.argv[1]
ts = [t for t in json.load(sys.stdin)["devicetypes"] if want in t["name"]]
print(ts[-1]["identifier"] if ts else "")' "$1"
}

UDID=""
DATA=""
setup() {  # label, device type name part
  local type
  type=$(devtype "$2")
  if [ -z "$RUNTIME" ] || [ -z "$type" ]; then
    log "skip $1: no runtime or no device type for '$2'"
    return 1
  fi
  UDID=$(xcrun simctl create "$1" "$type" "$RUNTIME")
  log "created $1 ($type) $UDID"
  xcrun simctl boot "$UDID" >> "$LOG" 2>&1
  xcrun simctl bootstatus "$UDID" -b >> "$LOG" 2>&1
  xcrun simctl install "$UDID" "$APP" >> "$LOG" 2>&1 || { log "install failed"; return 1; }
  DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  cp "$PACK" "$DATA/Documents/"
  log "data container: $DATA"
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
  log "$name: $state"
}

finish() {  # label
  cp "$DATA/Library/Caches/diag.log" "$OUT/$1-diag.log" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl shutdown "$UDID" >> "$LOG" 2>&1
}

if setup DDU-Pro13 "iPad Pro 13-inch"; then
  ui appearance light
  shot 00-import -DDUImportInbox 1 -DDUTab library -DDUOrientation landscape
  shot 01-today-landscape -DDUTab today -DDUOrientation landscape
  shot 02-library-landscape -DDUTab library -DDUOrientation landscape
  shot 03-reader-landscape -DDUOpenArticle "$ARTICLE" -DDUOrientation landscape
  shot 04-shadow-landscape -DDUTab shadow -DDUOrientation landscape
  shot 05-vocab-landscape -DDUTab vocab -DDUOrientation landscape
  shot 06-ielts-landscape -DDUTab ielts -DDUOrientation landscape
  shot 07-progress-landscape -DDUTab progress -DDUOrientation landscape
  shot 08-settings-landscape -DDUTab settings -DDUOrientation landscape
  shot 10-reader-portrait -DDUOpenArticle "$ARTICLE" -DDUOrientation portrait
  shot 11-today-portrait -DDUTab today -DDUOrientation portrait
  ui appearance dark
  shot 20-today-dark -DDUTab today -DDUOrientation landscape
  shot 21-reader-dark -DDUOpenArticle "$ARTICLE" -DDUOrientation landscape
  shot 22-progress-dark -DDUTab progress -DDUOrientation landscape
  ui appearance light
  ui content_size accessibility-extra-extra-extra-large
  shot 30-today-largest-text -DDUTab today -DDUOrientation portrait
  shot 31-reader-largest-text -DDUOpenArticle "$ARTICLE" -DDUOrientation portrait
  shot 32-shadow-largest-text -DDUTab shadow -DDUOrientation portrait
  shot 33-settings-largest-text -DDUTab settings -DDUOrientation portrait
  ui content_size large
  finish pro13
fi

if setup DDU-mini "iPad mini"; then
  ui appearance light
  shot 40-mini-import -DDUImportInbox 1 -DDUTab library -DDUOrientation portrait
  shot 41-mini-reader -DDUOpenArticle "$ARTICLE" -DDUOrientation portrait
  shot 42-mini-today -DDUTab today -DDUOrientation portrait
  shot 43-mini-library -DDUTab library -DDUOrientation portrait
  finish mini
fi

mkdir -p "$OUT/crashes"
cp ~/Library/Logs/DiagnosticReports/DayDayUp* "$OUT/crashes/" 2>/dev/null || true
log "files: $(ls "$OUT" | tr '\n' ' ')"
grep -c "NOT RUNNING" "$LOG" | xargs -I{} echo "launches that were not running: {}" | tee -a "$LOG"
exit 0
