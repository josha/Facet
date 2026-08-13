# A verifier that ends on its opening sentence

**Found:** 2026-08-13, four times in one mission, across two different
`luauui-*-verifier` agent types.
**Cost:** roughly 340k subagent tokens and 120 tool calls of real investigation
thrown away, plus three redispatches — and, the first time, very nearly a
milestone closed without its architecture gate.

## The symptom

A specialist verifier is dispatched with a complete brief. It runs 30–55 tool
calls of genuine work — reading source, running checkers, building probes — and
then ends its turn with its **opening sentence** as the entire result:

```
I'll start by orienting in the repo and reading the governing docs.
```
```
I'll start by exploring the repository structure and the key files.
```

No findings. No verdict. The work happened; the report never got written. The
harness records the agent as `completed`, so nothing about the task status says
it failed — only the empty result does.

## What it is not

- **Not a bad brief.** The same brief, verbatim, produced a full nine-finding
  report from a `general-purpose` agent minutes later.
- **Not context exhaustion** in any obvious sense — one instance stopped at 57k
  tokens, another ran to 148k. The stall is not correlated with budget.
- **Not the nudge fixing it.** A resume message ("your turn ended on a plan;
  continue and deliver the report") worked once and failed once, at greater
  cost each time.

## The rule

**When a specialist verifier agent type returns its opening sentence, redispatch
to `general-purpose` with the same brief rather than nudging it.** The
redispatch has worked every time; the nudge has not.

Two riders that cost nothing and save the whole run:

1. **Put the delivery instruction in the brief, not just the format section.**
   The wording that has worked: *"Deliver a written report as your final
   message. Budget your context so the findings get written — a partial report
   with three verified findings beats a complete investigation nobody can
   read."* State the failure explicitly; a verifier told that its predecessor
   stalled does not stall.

2. **Never let a milestone close on a verifier's silence.** An empty result is
   indistinguishable from "nothing to report" if you are not looking, and a
   `completed` status actively suggests success. In this mission a stop-hook
   caught two milestones whose gates had produced nothing; without it they would
   have been reported done. **A gate that returns no verdict has not run.**

## Why this matters more than it looks

The gates exist because a green suite is not evidence — every one of nine
device-reported defects in this mission passed a green suite. A verifier that
silently produces nothing converts a mandatory gate into a no-op **while leaving
every outward sign that it ran**: the dispatch is in the transcript, the agent
reports `completed`, the token spend looks right. It is the same failure shape as
a check that cannot fail, one level up: the instrument is present, the
measurement never happened, and only somebody asking "what did it actually say?"
finds out.
