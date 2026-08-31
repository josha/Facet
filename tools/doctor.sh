#!/usr/bin/env bash
# Facet doctor: verifies the toolchain and library invariants (design §16.1).
# Writes artifacts/doctor.json. Exits nonzero if any REQUIRED check fails.
set -uo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
# BOTH output directories, because BOTH are gitignored and this script writes
# into both. `build/` used to be missing from this line, and the rojo-build row
# below writes `-o build/Facet-Gallery.rbxl`: rojo does NOT create the parent
# directory of its output, it exits 1 with "No such file or directory". So on a
# CLEAN CHECKOUT the doctor's first REQUIRED failure was a missing folder,
# reported as "rojo build examples/gallery.project.json failed" — which reads
# like a broken project to the one person guaranteed to be reading it, someone
# who has just cloned the repository. Measured independently by two fresh-context
# agents, 2026-08-21.
mkdir -p artifacts build

fail=0
checks=""

add_check() { # name status detail required
  checks="${checks}${checks:+,}
    {\"name\":\"$1\",\"status\":\"$2\",\"detail\":\"$3\",\"required\":$4}"
  if [ "$2" = "FAIL" ] && [ "$4" = "true" ]; then fail=1; fi
}

LUNE_V="$(lune --version 2>/dev/null)" && add_check lune OK "$LUNE_V" true || add_check lune FAIL "lune not on PATH" true
ROJO_V="$(rojo --version 2>/dev/null)" && add_check rojo OK "$ROJO_V" true || add_check rojo FAIL "rojo not on PATH" true
[ -f tests/run.luau ] && add_check testkit OK "tests/run.luau present" true || add_check testkit FAIL "tests/run.luau missing" true
[ -f requirements.json ] && add_check requirements OK "requirements.json present" true || add_check requirements FAIL "requirements.json missing" true
[ -f tools/lune/verify/graph.json ] && add_check verify-graph OK "verification graph present" true || add_check verify-graph FAIL "tools/lune/verify/graph.json missing" true

# Gallery place must build (proves the Rojo project maps the library).
if rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl >/dev/null 2>&1; then
  add_check rojo-build OK "gallery place builds" true
else
  add_check rojo-build FAIL "rojo build examples/gallery.project.json failed" true
fi

# Studio automation reachability cannot be probed from a shell; the agent drives
# it via the Studio MCP server. Recorded as ENV so gates treat it as external.
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
