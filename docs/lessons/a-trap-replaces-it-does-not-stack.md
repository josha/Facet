# A second `trap ... EXIT` silently deletes the first

**2026-08-15.** `tools/prior_gates.sh` had never released its lock. Not
sometimes, not on crashes — **never, on any path, including a clean run.** The
sweep that finished at 16:43 left `/tmp/facet_prior_gates.lock` behind, created
at 12:54, with no process holding it.

## The bug

Three lines, spread over a hundred, each correct on its own:

```bash
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT   # line 52 — releases the lock
...
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT                        # line 89 — DELETES the above
...
mv "$tmp" "$out"
trap - EXIT                                     # line 157 — clears what is left
```

**bash EXIT traps replace; they do not accumulate.** Line 89 does not add a
second handler, it overwrites the only one. So the lock release was gone before
the script had done any work, and the success path then cleared the trap
entirely.

Four lines are enough to see it, and it is worth running rather than recalling:

```bash
D=/tmp/t_$$; mkdir "$D"
trap 'rmdir "$D"' EXIT
T="$(mktemp)"; trap 'rm -f "$T"' EXIT
trap - EXIT; exit 0
# => $D survives
```

## Why it cost more than a stale directory

The lock is acquired with `mkdir`, and the refusal is one line to **stderr**:

```
prior_gates: another sweep holds /tmp/facet_prior_gates.lock — refusing to start a second
exit 2
```

The caller reads the roll-up file, not stderr. So the next sweep does not run,
writes no roll-up, and the gate row that shells it reports a failure with no
diagnosis. That is the entire *"the prior-gates lock refuses SILENTLY (exit 2)"*
folklore this project has carried for weeks: it was never a race between agents,
it was every run poisoning the next one.

Worse, and the reason this is a correctness bug and not a tidiness one:

> **A leaked lock from a COMPLETED run is indistinguishable from a live hung
> run.**

Both are a directory with no owner in the process table. The round-3 design's own
process finding #2 records a lock *"hung for 2 h 37 m"*, investigated and killed
with director authorisation. A finished sweep looks exactly like that. The
standing advice — *`pgrep` before clearing, never clear blind* — is still right,
and it is what stops you deleting a real run's lock; but it cannot tell you the
orphan was harmless, so every occurrence bought a fresh investigation.

## The fix

One handler doing both jobs, installed once, and **no `trap - EXIT` on the
success path** — `$tmp` is already moved by then, so `rm -f` on it is a no-op and
letting cleanup run is what finally releases the lock.

```bash
cleanup() {
	[ -n "${tmp:-}" ] && rm -f "$tmp" 2>/dev/null
	rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT
```

Verified on **both** exit paths, because the interesting one is the path that
succeeds:

- early exit (`prior_gates.sh <out> phase-0-foundation`, no priors, exit 2) → released
- success (`prior_gates.sh <out> phase-1-minimal-screen`, one prior, exit 0, roll-up
  written with its `DONE` line) → released

## The general shape

`trap` is the one place a shell script keeps its invariants, and it is
last-writer-wins. If a script installs an EXIT trap anywhere other than once, at
the top, covering everything it must undo, it has no cleanup at all — it has the
*last* cleanup somebody added.

If you add a `trap ... EXIT` to a file that already has one, you are not adding
cleanup. **You are choosing which cleanup to delete.**
