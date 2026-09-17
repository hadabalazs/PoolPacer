#!/usr/bin/env bash
# PoolPacer -- switch the manifest app ID between the two Connect IQ listings.
#
# The store keys a listing to the manifest's app ID, so the ID must match the
# listing you are building for. Connect IQ has no way to convert a beta app to
# a public one, which is why there are two:
#
#   beta   -- original testing-only listing, for trying things on the watch
#   public -- live public listing, for real releases
#
# Usage:  ./switch-app-id.sh [beta|public|status]
#
# Always rebuild after switching -- the ID is compiled into the .iq.

set -euo pipefail

BETA_ID=36e4cb1ee7da4f5a9a27283984123a5e
PUBLIC_ID=8ca92568669844049358da7b3fb94cd6

cd "$(dirname "$0")"
MANIFEST=manifest.xml

current() { grep -o 'id="[0-9a-f]\{32\}"' "$MANIFEST" | head -1 | sed 's/id="//;s/"//'; }

label() {
  case "$1" in
    "$BETA_ID")   echo "beta" ;;
    "$PUBLIC_ID") echo "public" ;;
    *)            echo "UNKNOWN" ;;
  esac
}

cur=$(current)

case "${1:-status}" in
  beta)   new=$BETA_ID ;;
  public) new=$PUBLIC_ID ;;
  status) echo "current: $(label "$cur")  ($cur)"; exit 0 ;;
  *)      echo "usage: $(basename "$0") [beta|public|status]" >&2; exit 1 ;;
esac

if [ "$cur" = "$new" ]; then
  echo "already set to $(label "$new")  ($new)"
  exit 0
fi

sed -i.tmp "s/id=\"$cur\"/id=\"$new\"/" "$MANIFEST"
rm -f "$MANIFEST.tmp" 2>/dev/null || true   # some sandboxes cannot unlink
echo "switched: $(label "$cur") -> $(label "$new")  ($new)"
echo "rebuild before uploading."
