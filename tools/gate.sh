#!/usr/bin/env bash
# Facet canonical aggregate gate. Usage: tools/gate.sh [phase-gate-name]
#
# THE NAME IS THE ENTRY, THE COORDINATOR IS THE IMPLEMENTATION (D7, 2026-08-30).
# Everything in this repository that says "run the gate" says `tools/gate.sh
# <phase>`, and it still answers the same question and still writes
# `artifacts/<phase>/gate.json` in the `facet-gate/1` shape. What changed is
# underneath: the phase is a VIEW over one run of the verification graph rather
# than a list of shell commands that each restarted the suite.
#
# `tools/verify.sh full --gate <phase>` makes sure that phase's producers are in
# the run, and every other phase is evaluated from the same results — which is
# also what replaced `tools/prior_gates.sh`'s recursive replay.
#
# The pre-conversion path is still runnable for the parity proof:
#   lune run tools/lune/gate_legacy <phase>
set -euo pipefail
cd "$(dirname "$0")/.."
# ROKIT'S rojo, NOT whatever is first on PATH. A stale /usr/local/bin/rojo
# (7.7.0-rc.1, Nov 2025) shadowed the rokit-managed 7.7.0 for months; its
# reflection database does not know `Workspace.PlayerScriptsUseInputActionSystem`,
# so a project declaring it FAILED THE BUILD with "Unknown property" while the
# pinned toolchain built it fine. Measured 2026-08-15.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec tools/verify.sh full --gate "${1:-phase-0-foundation}"
