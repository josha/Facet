#!/usr/bin/env bash


set -uo pipefail
cd "$(dirname "$0")/.."





export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"







python3 tools/sync_compose.py --check || exit $?









mkdir -p artifacts build

fail=0
checks=""

add_check() {
  checks="${checks}${checks:+,}
    {\"name\":\"$1\",\"status\":\"$2\",\"detail\":\"$3\",\"required\":$4}"
  if [ "$2" = "FAIL" ] && [ "$4" = "true" ]; then fail=1; fi
}

LUNE_V="$(lune --version 2>/dev/null)" && add_check lune OK "$LUNE_V" true || add_check lune FAIL "lune not on PATH" true
ROJO_V="$(rojo --version 2>/dev/null)" && add_check rojo OK "$ROJO_V" true || add_check rojo FAIL "rojo not on PATH" true
[ -f tests/run.luau ] && add_check testkit OK "tests/run.luau present" true || add_check testkit FAIL "tests/run.luau missing" true
[ -f src/init.luau ] && add_check library OK "native Facet entry point present" true || add_check library FAIL "src/init.luau missing" true
[ -f tools/lune/native_verify.py ] && add_check verification OK "native verification runner present" true || add_check verification FAIL "tools/lune/native_verify.py missing" true


if rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl >/dev/null 2>&1; then
  add_check rojo-build OK "gallery place builds" true
else
  add_check rojo-build FAIL "rojo build examples/gallery.project.json failed" true
fi



add_check studio-mcp ENV "verified per-session via Studio MCP, not from shell" false

status=$([ $fail -eq 0 ] && echo PASS || echo FAIL)
cat > artifacts/doctor.json <<EOF
{
  "schema": "facet-doctor/1",
  "status": "$status",
  "requirement": "UI-AGENT-001",
  "checks": [$checks
  ]
}
EOF
echo "doctor: $status (artifacts/doctor.json)"
exit $fail
