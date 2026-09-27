#!/bin/bash
# UI tap tests on an iPad simulator (CI, GitHub macOS runner), with the original demo pack only.
#   gate:    DayDayUpUITests/NavigationTapTests - sidebar, 书架 article, 雅思 prompt, 设置 row, top tab bar.
#            Must pass: the script exits with its result.
#   control: DayDayUpUITests/LegacyRootTapDiagnosisTests - the same taps with 1.0.0's root tap gesture put
#            back (-DDULegacyRootTap 1). They pass when those taps lead nowhere (A/B evidence); never blocks.
# Results go to annotations (ci/ui_summary.py) and to <out dir>.
# Usage: ci/ui_tests.sh <demo.ecopack> <out dir>
set -u
PACK="$1"
OUT="$2"
mkdir -p "$OUT"
LOG="$OUT/ui-run.log"
: > "$LOG"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r.get("platform") == "iOS"]
rs.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')
log "runtime: $RUNTIME"

devtypes() {  # every device type whose name contains $1, newest first
  xcrun simctl list devicetypes -j | python3 -c '
import json, sys
want = sys.argv[1]
ts = [t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if want in t["name"]]
print("\n".join(reversed(ts)))' "$1"
}

# The 12.9-inch iPad Pro has the learner's screen (1024 x 1366 pt); the 13-inch one is the fallback.
UDID=""
for want in "iPad Pro (12.9-inch)" "iPad Pro 13-inch"; do
  for type in $(devtypes "$want"); do
    UDID=$(xcrun simctl create DDU-UITest "$type" "$RUNTIME" 2>> "$LOG") && break 2
    UDID=""
  done
done
if [ -z "$UDID" ]; then
  log "no iPad simulator could be created"
  echo "::error title=UI tests::no iPad simulator could be created with $RUNTIME"
  exit 1
fi
log "created DDU-UITest ($type) $UDID"
xcrun simctl boot "$UDID" >> "$LOG" 2>&1
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
DEST="platform=iOS Simulator,id=$UDID"

xcodebuild build-for-testing \
  -project DayDayUp.xcodeproj \
  -scheme DayDayUp \
  -configuration Debug \
  -destination "$DEST" \
  -derivedDataPath uibuild \
  CODE_SIGNING_ALLOWED=NO \
  > "$OUT/ui-build.log" 2>&1
if ! grep -q "TEST BUILD SUCCEEDED" "$OUT/ui-build.log"; then
  log "build-for-testing failed"
  grep -E "error:" "$OUT/ui-build.log" | awk '!seen[$0]++' | head -n 10 | sed -e 's/%/%25/g' -e 's/^/::error title=UI test build::/'
  tail -n 40 "$OUT/ui-build.log"
  exit 1
fi
log "built for testing"

APP=uibuild/Build/Products/Debug-iphonesimulator/DayDayUp.app
cp "$PACK" "$APP/demo.ecopack"
XCTESTRUN=$(ls uibuild/Build/Products/*.xctestrun | head -n 1)
log "xctestrun: $XCTESTRUN"

run_tests() {  # name, test selection
  local name="$1"
  shift
  xcodebuild test-without-building \
    -xctestrun "$XCTESTRUN" \
    -destination "$DEST" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$OUT/$name.xcresult" \
    "$@" > "$OUT/$name.log" 2>&1
  local status=$?
  grep -E "^Test Case|error: -\[|Executed" "$OUT/$name.log" | tee -a "$LOG"
  log "$name: xcodebuild exit $status"
  return $status
}

run_tests gate -only-testing:DayDayUpUITests/NavigationTapTests
GATE=$?
run_tests control -only-testing:DayDayUpUITests/LegacyRootTapDiagnosisTests
CONTROL=$?

for name in gate control; do
  xcrun xcresulttool export attachments --path "$OUT/$name.xcresult" --output-path "$OUT/$name-shots" \
    >> "$LOG" 2>&1 || log "$name: no attachments exported"
done
python3 ci/ui_summary.py "$OUT"
xcrun simctl shutdown "$UDID" >> "$LOG" 2>&1
log "gate=$GATE control=$CONTROL"
exit $GATE
