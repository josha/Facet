# Plain source comments — the audit, with a runnable scan

**What this file records:** the instrument, the numbers it produces, what was
rewritten, and an honest disposition of what is left.

Fix round 1 replaced this file's first version, whose "Scans used" block was a
heredoc containing a regex in a comment and nothing else. A scan block that
cannot be run certifies nothing.

## The instrument

`tools/check_comment_codes.py` is new in this round, and it is the first
automated check that reads `src/` comments at all. `check_doc_style.py` scans
`docs/guide` and `docs/extending`; nothing scanned source.

```sh
python3 tools/check_comment_codes.py            # PASS/FAIL against the ceiling
python3 tools/check_comment_codes.py --list     # every site, file:line
python3 tools/check_comment_codes.py --json     # the counts, and the count per code
python3 tools/check_comment_codes.py --selftest # proves it sees a planted code
```

**What it counts.** A token shaped `AB-12`, `ABC-A7` or `SF-M9` inside a Luau
comment: two to five capitals, a hyphen, an optional letter, digits. Those
resolve only in this repository's private ledgers.

**What it does not count, each for a reason that is a fact:** `ADR-nnnn` (a
decision record that ships), `UI-XXX-nnn` (a requirement id that resolves in
`requirements.json`, which ships), `SW-nnn` (a citation id in the comparison
document, which ships), and `UTF-8` (an encoding). A code inside a string
literal is not a comment, and the scanner tracks quotes so it does not count one.

**It is a ratchet, not a zero.** `CEILING` is the count achieved by the commit
that introduced it. The count may fall and may never rise.

## The numbers

Measured in private exports, base `5d97826` against this round:

| | base | wave T12 (`2b05191`) | fix round 1 |
|---|---|---|---|
| private codes in maintained src/ comments | **531** | 405 | **122** |
| files carrying one | 107 | 80 | 47 |
| distinct codes | — | 154 | 80 |
| the five extraction-locked modules | 185 | 185 | 185 |

The re-review independently reconstructed 531 → 405 for the first wave. This
checker reproduces both numbers exactly, which is what makes 122 checkable
rather than asserted.

**The first wave's own record measured a narrower thing than it claimed.** Its
"88 → 29" was module HEADERS only — the first 40 lines of each file — and the
artifact did not say so. Whole-file, the same wave moved 531 → 405. Both numbers
are true of what they measured; only one of them was the claim a reader would
take away, and the wrong one was printed.

## What was rewritten in this round

The rule applied: a comment may keep an exact API name, a Roblox class name, a
mathematical term, a measured number and a platform constraint. It may not keep
a code that only resolves inside a private ledger.

- **Structural removals.** ` (SF-D2)`, `(row LT-1, …`, `row SF-M9 ` and their
  relatives are deleted with the punctuation they carried, leaving the sentence
  that was already there. 62 files.
- **Whole families resolved to the fact they stood for.** `RS-A16` (42 sites)
  became "rich-skinning v2", `RUNG-2` "rung-2", `NS-A*` "the native substrate",
  `LTN-*` "large-text accessibility", `NSS-*` "the native stylesheets work",
  `SF-M9` "the headless-green/device-wrong class".
- **`ADR-nnnn` citations and requirement ids stayed**, deliberately. An ADR is a
  document a reader can open; a requirement id resolves in a file that ships.
- **`host.luau`'s module header** lost its `ADAPT-1` and keeps its date. A date
  records when a decision was made; the plan's example of the bad shape is a
  code *plus* a date, and the code is what a reader cannot follow.
- **Two stale factual claims were corrected, not just reworded.**
  `src/client/roblox_input.luau` said both `InputAction:Fire()` and `GetState()`
  were deprecated; only `Fire()` is.
- **One ghost class was removed.** `src/themes/package.luau` pointed at
  `UI.Custom`, reserved and never shipped; `UI.Foreign` is the class that did.

## The rule RC-18 is closed against

The plan's bar is that a maintained source comment carries no **UNEXPLAINED**
gate ID, finding code, phase label, evidence-row name or acronym. It is not that
a code may never appear. A code that resolves is a citation; a code that resolves
nowhere is folklore. So the checker classifies every site and the two classes
carry different ceilings.

**RESOLVABLE** — the code has a referent a reader can reach, by one of four
routes, and the checker reports which route per site so a reviewer can disagree
with a site rather than with a number:

1. `requirements.json` names the code;
2. the same comment block cites an `ADR-nnnn` that exists as a file;
3. the same comment block names a `docs/**` file that exists;
4. the same comment block DEFINES the code in plain language, in the same breath
   — `-- ADAPT-18: a collapsed column's heading leaves paint, focus and…`.

**ORPHAN** — none of the four. The code is the whole explanation, and the
explanation is not in the repository.

**The block is the unit**, not the file and not the line: a code and the sentence
that defines it belong to one thought, and a citation three paragraphs away is
not one a reader connects.

## Both counts

| | base `5d97826` | wave T12 | fix round 1 | fix round 2 |
|---|---|---|---|---|
| private codes in maintained src/ comments | 531 | 405 | 122 | **25** |
| …ORPHAN (resolve nowhere) | not classified | not classified | **87** | **0** |
| …RESOLVABLE (a referent a reader can reach) | — | — | 35 | **25** |
| files carrying one | 107 | 80 | 47 | 20 |

**The orphan ceiling is 0 and is not a ratchet.** There is no allowance for a
code that resolves nowhere, because that is the thing the rule prohibits. The
**total ceiling is 25** and is a ratchet: resolvable sites may not grow either,
so a new code has to displace an old one.

The 25 that stay, by route:

| Route | Sites |
|---|---|
| defined in its own comment block | 19 |
| cites `ADR-0013` or `ADR-0019` | 4 |
| names `docs/plans/performance-stress-places.md` | 1 |
| names `docs/reference/api.md` | 1 |

## How the 87 orphans were closed

Two mechanical passes and thirty targeted rewrites, all comment-only:

- **A parenthetical that was only the code** — ` (PLAT-9, 2026-08-17)`,
  `(reuse audit REUSE-122)` — is deleted with the punctuation it carried.
- **A code leading or trailing a parenthetical that carries more** loses the
  code and keeps the rest: `(api-architecture-consistency F-7 / ledger BP-F4)`
  became `(api-architecture-consistency F-7)`.
- **A possessive** became the thing it owned: `PLAT-12's disposal token` →
  `the disposal token`.
- **A code carrying the sentence** was replaced by what it meant:
  `which is the whole of ADAPT-1` → `which is the whole point of taking them
  from the surface`; `DB-4 lived exactly there` → `the device defect this note
  records lived exactly there`; `the pre-ADAPT-9 meaning` → `the older meaning`.
- **A compound** lost its private half: `(ARCH-TI-1)` → nothing, because the
  sentence beside it already said "reject it at BUILD, exactly as TextInput
  does".

Nothing was moved to an allowlist and no orphan was reclassified to make the
number fall.

## The extraction-locked five, still dispositioned

185 sites, unchanged and untouched: **150 orphan, 35 resolvable**. The checker
counts and prints them separately on every run, so their debt is visible rather
than averaged into the maintained number. Their sweep belongs to the extraction
that holds those files.

## The selftest

`python3 tools/check_comment_codes.py --selftest` plants the SAME code four
ways and requires four different answers:

```
-- planted: this rule came from row TP-A12.            -> ORPHAN
-- TP-A12: a column collapses before it clips.         -> RESOLVABLE (defined-in-block)
-- planted TP-A12, and the reason is in ADR-0011.      -> RESOLVABLE (ADR-0011)
-- ADR-0011, UI-INPUT-001, SW-141, UTF-8               -> not a private code at all
local s = "not a comment: XX-9"                        -> not a comment
```

Then it requires the restored tree to have zero orphans and to be at or under
the total ceiling.

**`RC-18` is `PASS_AUTOMATED` from fix round 2.** The rule it is closed against
is the one stated above — no UNEXPLAINED code — and both halves of that rule are
checked on every run: zero orphans, and a ratcheted total of resolvable
citations. It was `PENDING` through fix round 1 because 87 codes resolved
nowhere; those are gone.

What the row does NOT claim: that the prose is good. A checker that classifies
codes cannot read a sentence. Comment QUALITY is judged by the fresh-reader
exercises, which are `RC-17` and still open.

## Reader-facing defects the first wave introduced, and their repair

The re-review found 19. All are closed in this round:

| Class | Count | Repair |
|---|---|---|
| orphaned punctuation in comments (`FACTS : the font`) | 13 measured here, 15 reported | the space before the punctuation is closed; base was 0, head is 0 |
| mangled quotation in `virtual_grid.luau` | 1 | the header states the fact in Facet's words and cites the comparison document for the source |
| broken grammar in `check_flat_baseline.luau` | 1 | "from the same a physical phone pass" → "from the same physical-phone pass" |
| half-swept error string in `virtual_grid.luau:260` | 1 | finished; the whole framework-type family is now matched by the guard |
| wrong fact in `docs/guide/README.md` | 1 | "six playbooks" → seven, which is what the list has |
| unattributable quotations (opening quote lower-cased, source removed) | 6 | the quote marks are dropped and the guidance is stated as a paraphrase, which is what it now is |

## A trap this round fixed rather than dodged

`tools/lune/check_prop_parity.luau` derived an exported type's field set with a
scanner that did not strip comments. A plain-language line of the natural shape
`term: explanation` inside a record type invented a field on that type and on
every type intersecting it: one reworded comment in `BoxProps` invented `hide` on
twenty-two spec types.

The first wave reworded the comment to dodge it. This round strips comments in
`recordFields` — block to its closer, line to end of line, quote-aware — and
`tests/authoring.spec.luau` plants that exact shape inside the real `BoxProps`
and requires the checker to stay green.

## The other instrument this round committed

`tools/check_gate_pins.py`. A gate row proves something by grepping a fixed
sentence out of a file; rewrite the sentence and the row stops proving anything,
and a NEGATED pin starts passing for the wrong reason. It reads every literal
`grep -qF` pin out of the manifest and checks it against the tree without running
a gate: **237 pins, 0 broken**. Regex pins are skipped and counted, because
grep's dialect is not Python's and reporting a dialect difference as a broken pin
would be a false alarm in a guard about false alarms.
