#!/usr/bin/env bash
# RETIRED 2026-08-30 (distribution-readiness D7). Use: tools/verify.sh release
#
# This script re-ran every gate preceding a stage so that a `prior-gates-
# unregressed` row could compare a stored roll-up against a regenerated one. It
# was right about the requirement — a checked-in old PASS is never evidence for
# changed source — and wrong about the method: re-running a gate re-runs every
# producer that gate names, and sixteen stages did it to each other, so the work
# was factorial in the number of regenerating gates rather than linear. It
# needed a recursion guard, a global lock, and a load-average settle just to
# terminate.
#
# The requirement survives EXACTLY, and costs nothing. `tools/verify.sh`
# evaluates every phase's rows from ONE run's structured results, so
# "does every earlier phase still pass at this source?" is now a lookup over
# rows that have already been judged. The sixteen rows are still in the graph as
# class `prior-phases`; the coverage map records each one.
#
# Exits 2 rather than 0, deliberately: a caller that has not been updated must
# stop, not silently succeed.
echo "prior_gates: RETIRED. Prior-phase regression is now re-evaluated, not replayed:" >&2
echo "  tools/verify.sh release            every producer once, every phase view judged" >&2
echo "  tools/verify.sh full --gate <phase>  one phase, with every earlier phase evaluated too" >&2
exit 2
