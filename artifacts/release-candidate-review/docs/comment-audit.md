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

## What is left, and why — the honest disposition

**122 sites in 47 files.** 80 distinct codes, 51 of them appearing exactly once.
The long tail is the point: no family is large enough to resolve mechanically,
and each one needs a human to say what the code meant. The largest are `ADAPT-8`,
`RR-1` and `TDN-2` at four sites each.

They are dispositioned, not hidden: the ceiling is 122, so the count cannot grow,
`--list` prints every one with its file and line, and the next comment pass has a
worklist rather than a slogan.

**185 more in the five extraction-locked modules** (`table`, `virtual_list`,
`solver`, `renderer`, `presenter`). Counted separately by the checker and
reported on every run. Their sweep belongs to the extraction that holds them.

**`RC-18` therefore stays `PENDING`.** The controller reverted it in `9401845`
and this round does not ask for it back. A checker that counts codes cannot read
a sentence, and 122 unexplained codes remain in maintained source. The row is a
controller call once the residual is judged.

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
