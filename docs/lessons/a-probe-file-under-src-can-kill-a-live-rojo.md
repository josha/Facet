# A probe file under `src/` can kill a live Rojo server

**Found:** 2026-08-16, during D0 of the navigation-and-menus round, by a Rojo server dying
in the background while the gate that killed it reported green.

## What happened

`tools/suite_cache_selftest.sh` proves the Rascal Rally fingerprint is content-sensitive to
a Facet edit. It did that the obvious way: write a probe file under `src/`, re-hash,
delete the probe.

`examples/showcase.project.json` mounts `../src`. A `rojo serve` running the ordinary dev
loop watches it, saw the create, went to canonicalize the path after the event, and found
it already gone:

```
[ERROR rojo] Rojo crashed! You are running Rojo 7.7.0.
[ERROR rojo] Details: called `Result::unwrap()` on an `Err` value: Custom { kind: NotFound,
  error: Error { kind: Canonicalize, source: Os { code: 2, kind: NotFound } },
  path: ".../Facet/src/.suite_cache_selftest_probe.luau" }
[ERROR rojo] in file src/change_processor.rs on line 172
```

## Why it is worse than it looks

Re-running the same create/delete sequence twice afterwards did **not** crash it. This is a
**race**, not a behaviour — and the selftest is a gate check (`d0-cache-guards-bite`), so
every sweep rolled the dice on killing whatever Rojo server the human had running. A
reliable failure would have been found in minutes; an intermittent one gets attributed to
Rojo, to Studio, to anything but the sweep.

The gate stayed green throughout. Nothing in the check could have noticed: it was asserting
a fingerprint, and the fingerprint was correct.

## The rule

**A tool that creates and deletes files does it outside every mounted path.** Before
writing a probe, temp file, scratch artifact or lockfile into the tree, check what the
project files mount:

```sh
grep -o '"\$path": "[^"]*"' examples/*.project.json
```

At the time of writing, `showcase.project.json` mounts `../src`, `gallery/examples`,
`gallery/scenarios`, `gallery/client` and `themes`. **`tests/` is mounted by no project
file**, which is why the Facet half of the same selftest never crashed anything.

`globIgnorePaths` is not a defence. It filters the snapshot, not necessarily the filesystem
event that precedes it, and relying on it means relying on the ordering inside someone
else's change processor.

## What replaced it

The probe moved to `tests/`, which is inside Rascal Rally's fingerprint for the same reason
`src/` is — its specs require Facet's `tests/lib` directly — so the behavioural claim ("a
Facet-side edit moves the game's fingerprint") is unchanged and still proved by an actual
edit.

The claim the move *would* have weakened — that `src/` specifically is covered — is now a
separate, explicitly-labelled **declaration** check: `tools/suite_transcript.sh --roots`
prints the roots the hasher walks, from the same function the hasher uses, and the selftest
asserts `src` is among them. A declaration and a behavioural probe, each labelled as what
it is, beats one behavioural probe that intermittently kills the dev loop.

## The general shape

This is the "a test that damages its own environment" family. The tell is that the damage
lands somewhere the test does not look: a running server, another agent's index, a shared
cache. The check passes, and something else fails later with no visible cause.
