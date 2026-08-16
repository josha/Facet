# Declarative 3D — fresh-context reviews and resolutions

Four fresh-context reviewers received the ADR, alternatives, use-case inventory,
research memo, raw spike, topology traces, and costs. Verdict lines verbatim;
every finding resolved below. Agent gate verdicts are advisory; the human gate
is the director's read of the ADR (STUDIO.md).

```
[ARCH-D3]: CONCERNS double-construction overclaim under streaming; welded-subtree model diverges from engine truth; unenforced world authority; two doc/code mismatches
[RUNTIME-D3]: CONCERNS read-then-subscribe lost updates (silent desync); per-item reactive resources never scope-owned (unbounded churn growth, teardown not at baseline); ADR/costs teardown + write-count claims overstated
[PLATFORM-D3]: CONCERNS signal-mode scope; "structurally prevented" double-build; parent-last + uncounted welds; PivotTo cost framing; WorldPivot vs PrimaryPart; SA/Deferred evidence missing
[PHASE-GATE-D3]: CONCERNS — suite floor exceeds the committed-tree count; two gate-cited Studio probes are emitted by no checked-in runner; the Studio record is hand-transcribed
```

After resolution, the spike was re-run headless (18/18) and the full Studio
session re-executed with the corrected code (19/19 probes, raw output preserved
verbatim). **No unresolved factual findings remain**; every judgment finding was
either adopted into the ADR/artifacts or answered below.

## Architecture review — resolutions

1. Double-construction overclaim — **RESOLVED**: ADR rewritten as two layers
   (home-partitioned id namespaces = the structural rule; the stamped
   check-first scan = a belt), streamed-out-owner and mount races added to
   Evidence still required; topology.luau header carries the same statement.
2. Welded-subtree divergence from engine truth — **RESOLVED in code**: mount now
   REFUSES a non-welded descendant inside a welded subtree (rigid all the way
   down), pinned by new headless case 15; DESIGN.md updated.
3. Authority asserted, not mechanized — **RESOLVED**: "world authority manifest
   asserted at the adapter write site" is now a named v0.1 deliverable in the
   ADR; the welded `anchored`/reactive-transform refusals are its first
   mount-time instances (also closes the fake-vs-engine `anchored` two-writer
   case: scene no longer writes `anchored` on welded parts at all).
4. Dead anchored guard — **RESOLVED in code**: guard removed; validation owns
   the rule now (see 3).
5. Runtime duplicate-key semantics misdocumented — **RESOLVED**: DESIGN.md
   states the real semantic (poisoned update discarded wholesale, prior tree
   survives, lastError names the key), pinned by new headless case 18.
6. alternatives.md cited ADR-0023 — **RESOLVED**: pointer corrected to ADR-0024.
7. Blessing wording undersold the gated addition — **RESOLVED**: ADR now names
   the runtime entry (core/custom), the boundary-check/api.md/ledger additions,
   and the consumer rider explicitly.
8. "Full reorder = zero churn" oversounded — **RESOLVED**: ADR and costs.json
   now say identity-keyed placement is zero-churn by construction and
   order-derived placement is the headless-proven half.
9. ADR marked Accepted before reviews — **RESOLVED**: status now reads
   "Accepted at stage PASS" and points at this file.
10. Registration swept into a foreign commit (65627b2, another session's
    whole-file `git add`) — **PROCESS NOTE, flagged to the director**: nothing
    from src/ rode along (verified by that commit's stat); the stage's
    registration is no longer separable in history. The standing
    whole-file-add trap strikes again; nothing further to fix in-repo.

## Reactive-runtime review — resolutions

1. Read-then-subscribe lost updates — **RESOLVED in code**: ForEach/When/node
   transforms all re-check their source after subscribing (bounded convergence
   loop; a source that never settles is reported on the quarantine channel).
   Pinned by new case 16, mutation-proven (disabling the loop reddens it).
2. Per-item resources never scope-owned — **RESOLVED in code**: builds now
   RECEIVE their item/arm scope; the Studio runner owns its per-item
   memos/signals there; teardown-at-baseline is asserted against the
   leak-capable churned shape headless (case 17) AND live (rebuilt
   destroy-cleanup probe). ADR carries the rule as inherited finding 4.
3. Per-transaction write counts nondeterministic across signals — **RESOLVED as
   documentation**: DESIGN.md and the ADR scope one-change-one-write as a
   per-signal guarantee; multi-signal claims are bounds. Deterministic
   intra-flush ordering is future work under the authority-manifest umbrella.
4. Survivors ignore item content — **RESOLVED as documentation**: the corollary
   is stated in DESIGN.md and the ADR's Identity fit bullet; the safe per-item
   pattern is exactly the scope-owned Readables from finding 2.
5. Engine adapter lacked the destroyed-handle tripwire — **RESOLVED in code**:
   roblox_adapter tracks children and retires the whole subtree's bookkeeping
   recursively; an external engine Destroy before disposal is now a live probe
   (external-destroy-tolerated, PASS).
6. Two probes emitted by no checked-in runner — **RESOLVED in code**: they are
   `runner_server.crossCheck()` now; re-run live (both PASS).
7. Reorder vacuous on transform churn — same as ARCH 8, **RESOLVED**.
8. Fake adapter logs unbounded — **RESOLVED as documentation**: declared a
   headless diagnostic recorder by design; production adapters must not keep
   call logs (DESIGN.md).
9. Quarantine does not roll back build side effects — **RESOLVED as
   documentation**: stated plainly in DESIGN.md's containment bullet.

## Roblox-platform review — resolutions

1. (verification of research claims) — no action; claims confirmed current.
2. Research summary bullet overstated SA/CFrame gating — **RESOLVED**: bullet
   softened to match its own §3 body (predicted instances only; non-predicted
   behavior undocumented → UNCONFIRMED #7).
3. Removal-signal finding was SignalBehavior-scoped — **RESOLVED**: runner
   comment, topology honesty label, and ADR finding 1 all scope it to
   Immediate; the task.defer belt is stated as safe under both modes; a
   Deferred replay is owed evidence (ADR item 3). A live Deferred re-run was
   ATTEMPTED and is impossible in this host: Workspace.SignalBehavior is not
   reflection-accessible from this Studio's scripting context (read and write
   both refused, 2026-08-13) — recorded in the topology artifact.
4. "Structurally prevented" double-build — **RESOLVED** (see ARCH 1) plus the
   ordering correctives IN CODE: the tree is built detached, stamped, then
   parented last, so no cross-kind replication ordering can present an
   unstamped root; Team Test races added to future evidence.
5. Parent-at-create vs parent-last — **RESOLVED in code**: adapter attach()
   seam; mountOnce stamps then attaches; costs.json notes single replication.
6. Welds uncounted / phantom anchored write — **RESOLVED in code**: welds count
   into creates/liveInstances (budget note: ~2x for welded assemblies); the
   welded anchored write no longer exists (see ARCH 3/4).
7. Weld-idiom gotchas absent — **RESOLVED**: ADR authority section carries
   anchored→unanchored as an authority transfer (assembly split / root
   re-election / ownership migration), and welded-child anchoring is
   validation-refused.
8. PivotTo conflation — **RESOLVED**: ADR and costs.json frame PivotTo as a
   Luau-call-count win that replicates N CFrame writes server-side.
9. WorldPivot ignored under PrimaryPart — **RESOLVED in code**: Model placement
   uses PivotTo (correct with and without PrimaryPart); template-clone probe
   added to future evidence (ADR item 7).
10. Belt is single-instance — **RESOLVED as scope**: stated in the runner and
    the ADR's v0.1 milestone (per-instance identity, N anchors, Spawned
    pattern, destroy+recreate discrimination).
11. Attribute/tag constraints missing from ADR — **RESOLVED**: authority
    section carries the replication criteria, the 1KB payload trap, and the
    never-client-stamp-a-server-instance rule.
12. Missing future evidence — **RESOLVED**: SA place probe, Deferred replay,
    replication bandwidth, destroy+recreate identity, ReplicationFocus
    prerequisite all added (ADR items 1–6).
13. gate.json "16 rows" vs 18 — **RESOLVED**: the gate row now cites all 19
    rows (the two cross rows are checked-in code) and requires the three raw
    transcripts; stale gate.json is regenerated by every gate run.
14. (consistency with ROBLOX.md) — no action; consistent.

## Phase-gate audit — resolutions

1. Suite floor above committed tree — **RESOLVED**: floor re-pinned to 4624,
   the count I re-measured myself from a clean `git archive HEAD` export
   (4624 passed / 0 failed); the manifest note records why (a concurrent
   session's uncommitted src/controls work had inflated the live tree).
2. Two probes not emitted by checked-in code — **RESOLVED in code** (see
   RUNTIME 6).
3. Hand-transcribed Studio record — **RESOLVED**: raw runner JSON preserved
   verbatim (studio-raw-server/client/cross.json), required non-empty by the
   gate row; editorial prose confined to provenance/honesty/finding fields.
4. costs.json authored — **RESOLVED**: provenance field points at the raw
   files; every number traceable to a runner-emitted row.
5. adr-decisive greps changed after gate.json — **PROCESS NOTE, said plainly**:
   the row's first registration pinned two phrases that spanned hard-wrapped
   lines, so the greps missed text that WAS in the ADR; the fix shortened the
   greps to single-line fragments of the same claims (evidence unchanged at
   that moment). The reviewer independently verified all greps hit substantive
   claims. Later legitimate ADR edits (this resolution round) adjusted one
   pinned phrase and its grep together.
6. spike-isolated single-quote evasion — **RESOLVED**: the require regex now
   matches both quote styles; mutation-proven (a single-quoted src require
   reddens it).
7. Concurrent src/tests dirt in the stage's window — **PROCESS NOTE**: other
   live sessions' work (src/controls + spec files, no 3D/spike content);
   nothing from this stage touches src/, tests/, or examples/.
8. Floor instrument critique — **RESOLVED** via 1 (sound logic, instrument
   re-pinned to a reproducible count).
9. (clean checks) — no action.

## What did NOT change under review

The decision itself. No reviewer disputed the shape (sibling on the shared
kernel, bless-don't-extract, build gated on a concrete consumer); the
architecture review explicitly confirmed the decision follows from checkable
structural facts and that no alternative was unfairly dismissed. The findings
made the evidence honest and the inherited rules sharper — which is what the
disproof spike was for.
