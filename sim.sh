#!/usr/bin/env bash
# Build and run PoolPacer in the Connect IQ simulator with the dry-land
# distance harness ON, then put the harness back to release state on the way
# out -- including on Ctrl+C, which is how you will normally stop it.
#
#   ./sim.sh                  # Descent Mk3 51mm (your watch)
#   ./sim.sh descentmk343mm   # or any other device id from the manifest
#
# To test wide distance readouts, set startM in source/Debug.mc first:
#   9900  -> hits 10000 m (5 digits) after a couple of lengths
#   99900 -> hits 100000 m (6 digits)

set -uo pipefail

DEVICE="${1:-descentmk351mm}"
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin"
export PATH="$PATH:$SDK"

cd "$(dirname "$0")"
VIEW=source/PoolPacerView.mc

restore() {
  echo
  echo "-- restoring release state (harness off)"
  sed -i.tmp 's|^        dist = debugDistance|        // dist = debugDistance|' "$VIEW"
  rm -f "$VIEW.tmp" 2>/dev/null || true
  grep -n "debugDistance(dist" "$VIEW"
}
trap restore EXIT INT TERM

echo "-- enabling harness"
sed -i.tmp 's|^        // dist = debugDistance|        dist = debugDistance|' "$VIEW"
rm -f "$VIEW.tmp" 2>/dev/null || true
grep -n "debugDistance(dist" "$VIEW"

echo "-- building for $DEVICE"
monkeyc -d "$DEVICE" -f monkey.jungle -o bin/sim.prg -y ~/developer_key || exit 1

echo "-- starting simulator"
connectiq >/dev/null 2>&1 &
sleep 5

echo "-- launching app; Ctrl+C here when you are done"
monkeydo bin/sim.prg "$DEVICE"
