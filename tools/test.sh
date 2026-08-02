#!/usr/bin/env bash
# LuauUI test: runs the deterministic Lune suite and REFUSES a green verdict if
# the summary line is missing (a main-thread yield truncates the suite with
# exit 0 — docs/lessons/lune-main-thread-yield-truncates-suite.md).
# Writes artifacts/test.json. Optional arg: minimum expected pass count.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p artifacts
min_expected="${1:-1}"

out="$(./run-tests.sh 2>&1)"
code=$?
# Strip ANSI color codes before parsing.
plain="$(printf '%s' "$out" | sed $'s/\x1b\\[[0-9;]*m//g')"
passed="$(printf '%s' "$plain" | grep -Eo '^[0-9]+ passed' | grep -Eo '^[0-9]+' | tail -1)"
failed="$(printf '%s' "$plain" | grep -Eo '^[0-9]+ failed' | grep -Eo '^[0-9]+' | tail -1)"

status=FAIL
reason=""
if [ $code -ne 0 ]; then
  reason="suite exited $code"
elif [ -z "$passed" ]; then
  reason="no 'N passed' summary line - suite truncated (see lessons)"
elif [ -n "$failed" ] && [ "$failed" != "0" ]; then
  reason="$failed tests failed"
elif [ "$passed" -lt "$min_expected" ]; then
  reason="only $passed passed; expected >= $min_expected (unregistered spec is a silent zero)"
else
  status=PASS
fi

cat > artifacts/test.json <<EOF
{
  "schema": "luauui-test/1",
  "status": "$status",
  "requirement": "UI-AGENT-001",
  "passed": ${passed:-0},
  "failed": ${failed:-0},
  "minExpected": $min_expected,
  "exitCode": $code,
  "reason": "$reason"
}
EOF
echo "test: $status passed=${passed:-0} ${reason:+($reason)} (artifacts/test.json)"
[ "$status" = "PASS" ]
