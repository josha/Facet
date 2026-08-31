#!/usr/bin/env bash
# Single command to run the Facet deterministic test suite (pure Luau, headless).
#
# Usage:
#   ./run-tests.sh          THE SUITE — every spec file. This is what the gate
#                           runs and the only thing that may be called green.
#   ./run-tests.sh --fast   the INNER-LOOP tier: the same list minus the eleven
#                           measured-slowest files (tests/lib/tiers.luau). ~8 s
#                           instead of ~43 s. It prints a FACET-FAST-TIER
#                           banner on both ends, and tools/test.sh refuses that
#                           transcript, so it cannot be mistaken for the suite.
set -euo pipefail
cd "$(dirname "$0")"
# ROKIT'S toolchain first, exactly as tools/verify.sh and tools/build_model.sh
# insist: a Homebrew lune that drifts from rokit.toml would otherwise run the
# suite on an unpinned interpreter while the result store records the pinned one.
export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

case "${1:-}" in
	--fast)
		exec lune run tests/run_fast
		;;
	"")
		exec lune run tests/run
		;;
	*)
		echo "run-tests.sh: unknown argument '$1' (expected --fast or nothing)" >&2
		exit 2
		;;
esac
