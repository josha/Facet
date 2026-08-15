# A freshness marker that exists in both versions is not a freshness check

**2026-08-15.** Live-verifying two new gallery fixtures in a Studio Play session.
The standing rule is the right one and I followed it:

> Check the datamodel carries a string you committed minutes ago before trusting
> any live result; `require` is cached per datamodel, so reading the right source
> does not prove you ran it.

I ran the check. It passed. **It could not have failed**, and the run underneath
it was against stale code.

## What happened

`examples/gallery/scenarios/sorted_entries.luau` went through two drafts within
the hour. Draft 1 laid its two columns out in a wrapping `UI.HStack`; the solver
refused that (a wrapping stack has no single leftover to share, so a `fill` child
takes a whole line), and draft 2 replaced the node with a `UI.AdaptiveStack`.
Everything else in the file — 300 lines of it — was untouched.

My freshness gate asked whether the synced `Source` contained the fixture's
title:

```lua
sortedMarker = string.find(se.Source, "The same twelve scores, built three ways", 1, true) ~= nil
```

`true`. So I mounted the fixture and drove it — and `controller.diagnostics()`
came back with two findings naming **`hwrap`**, a mechanism only draft 1 used. I
had already fixed that defect and watched the headless sweep go green on it.

The title string was in both drafts. The gate was asking *"did my file arrive?"*
when the only question that mattered was *"did my CHANGE arrive?"*, and for a
file that exists in two versions those are different questions.

## Why the run was stale at all

Rojo syncs into the **Edit** datamodel. A running **Play** session's Client
datamodel is a copy taken when Play started, so an edit made mid-session reaches
Edit and never reaches the session you are probing. Measured both sides:

```
Edit   : bytes=11328  hasAdaptiveStack=true   hasWrapDraft=false
Client : bytes=10824  hasAdaptiveStack=false  hasWrapDraft=true
```

Stop and restart Play and the Client copy is retaken from Edit. There is no way
to make a live Play session pick up a mid-session edit.

## How it was caught, which is the transferable part

Not by re-reading the gate — the gate looked fine, and re-reading a check that
cannot fail produces more confidence, not less. It was caught by **running the
thing and reading what came back**: a finding that named a mechanism the current
source does not contain is a statement about which bytes actually executed. The
gate was then *re-measured* with a token chosen to tell the drafts apart, and it
answered immediately.

`ENGINEERING.md` says measure, don't infer, and the same applies to your
instruments: a probe reading a stale surface produces confident false data.

## The rule

> A freshness marker must be a token that exists in the **new** version and not
> in the old one — ideally the exact thing you changed. If the marker would be
> present whether or not your change landed, the gate is decoration.

In practice:

- **Gate on the diff, not on the file.** `hasAdaptiveStack` / `hasWrapDraft` is a
  two-sided check: one must be true and the other false. A single positive is
  weaker than a pair, because a single positive cannot express "and not the old
  one".
- **Prefer a witness that RUNS over one that READS.** A `Source` read proves
  Rojo synced; it does not prove `require` returned those bytes (the cache is per
  datamodel, and a module required before your edit stays required). The
  strongest freshness evidence is behaviour only the new version can produce —
  in this case, having the framework hand back a `branchScope` label, and having
  the fixture report zero findings where the draft reported two.
- **`#Source` is a cheap discriminator** when nothing else is handy: two drafts
  of the same file almost never have identical byte counts (10824 vs 11328 here),
  and it needs no judgement about which string to pick.
- **When probing a Play session, verify Edit first, then restart Play.** Checking
  the datamodel you are about to probe is the whole point; checking the one Rojo
  writes to tells you only that your editor and disk agree.

## The family this belongs to

This repo already records *stale-session markers* and *`require` is cached per
datamodel*. This is the third member and the quietest: the marker was live, the
sync was real, the string genuinely arrived — and the check still proved nothing,
because it was not sensitive to the only variable under test.

It is the same shape as the "check that proves nothing" class the Step 5.5
simplicity gate named, and the same shape as the determinism test written *in
this same task*, which passed with the bug in place until it was rebuilt
(`tests/sorted_entries.spec.luau`, "the naive determinism check would PASS with
pairs"). Two instances in one task — one caught by design, one caught only by
running it — is the signal:

> Before trusting any check, ask what would have to be true for it to FAIL. If
> you cannot name that state, you have not written a check.
