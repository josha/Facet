# Lune hangs — it does not error — on a circular require

**Found:** 2026-07-25, theme-packages-and-skinning integration.

`src/tokens/sheet_model.luau` required `../themes/package` (for the schema
assertion), and an integration edit added the reverse require (package wanted
`sheet_model.dangerPair` for contrast-gate parity). Under Lune the whole suite —
and any script requiring either module — **hung silently**: no error, no output,
no stack. It looked exactly like a slow suite until a watchdog bisect
(per-spec mini-runner with a kill timer) showed *every* spec touching the chain
hanging, which is the signature: the common factor was the require graph, not
any test body.

**Rules:**

- A cross-module value both sides need lives in a **lower, dep-free module**
  (here: `tokens.dangerPair`), never in either of the two that would cycle.
- When a Lune run that used to finish stops producing output at all, suspect the
  require graph *before* the test bodies: bisect with a temp mini-runner that
  requires one spec at a time under a kill timer.
- `grep -n "^local.*require" <suspects>` and walk the edges; the cycle is
  usually one edge added by each of two independent changes — neither author
  saw both.
