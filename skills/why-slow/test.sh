#!/usr/bin/env bash
# Checks config parsing and the protection guard, then runs a full snapshot. Run: bash skills/why-slow/test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
parent=""; tmp=$(mktemp -d); child=""; trap 'kill $parent $child 2>/dev/null; rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

# A script named whyslowparent (its process name) with a plain `sleep` child.
printf '#!/bin/sh\nsleep 60\n' > "$tmp/whyslowparent"; chmod +x "$tmp/whyslowparent"
"$tmp/whyslowparent" & parent=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do child=$(pgrep -P "$parent"); [ -n "$child" ] && break; sleep 0.1; done
[ -n "$child" ] || fail "test setup: no child process"

export WHY_SLOW_CONFIG="$tmp/config"

printf 'PROTECT_NAMES=whyslowparent\nPROTECT_ANCESTORS==\n' > "$WHY_SLOW_CONFIG"
"$here/snapshot.sh" --guard "$parent" | grep -q 'PROTECTED(whyslowparent)' || fail "name not protected"
"$here/snapshot.sh" --guard "$child" | grep -qx ok || fail "unrelated child flagged"

printf 'PROTECT_ANCESTORS=whyslowparent\n' > "$WHY_SLOW_CONFIG"
"$here/snapshot.sh" --guard "$child" | grep -q 'PROTECTED(inside whyslowparent:' || fail "descendant not protected"
"$here/snapshot.sh" --guard "$parent" | grep -q 'PROTECTED(whyslowparent)' || fail "protected ancestor itself not protected"

printf 'PROTECT_NAMES==sleep\n' > "$WHY_SLOW_CONFIG"
"$here/snapshot.sh" --guard "$child" | grep -q 'PROTECTED(sleep)' || fail "replace list failed"

"$here/snapshot.sh" --guard 999999999 >/dev/null; [ $? -eq 2 ] || fail "missing PID not reported"

"$here/snapshot.sh" > "$tmp/out" 2>&1 || fail "snapshot exited non-zero"
grep -q 'protect names: sleep$' "$tmp/out" || fail "= prefix did not replace built-in list"
for s in 'load / memory' 'top CPU' 'top memory' 'thermals' 'warnings since'; do
  grep -q "=== $s" "$tmp/out" || fail "section missing: $s"
done
echo "all checks passed"
