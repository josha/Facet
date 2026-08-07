# Fresh-context reviews — example-quality-pass (EQ-22)

| Review | Trigger | Verdict | Report |
|---|---|---|---|
| Architecture | Required: the stage changed **shared property authority and framework code** (renderer, focus map, solver text metrics, two controls, the engine adapter) | **ACCEPT-WITH-FINDINGS** — 0 BLOCKER, 5 MAJOR, 8 MINOR | `architecture.md` |
| Phase gate | Required once at the stage boundary | **REJECT** — 3 BLOCKER, 9 MAJOR, 9 MINOR | `phase-gate.md` |
| Roblox platform | Triggered (engine-facing behaviour changed in `screen_target.luau`) | **NOT RUN** — see the disposition below | — |

## Architecture findings and what was done

| ID | Finding | Disposition |
|---|---|---|
| **M-1** | `assertEnumValue` claims to guard "every enum prop" and guards 5 of 21 — the paint/semantics channels only. Every solver-consumed enum (`anchor`, `alignH`/`alignV`, `overflow`, `align`, `reveal`, `axis`, `minColumnWidth`, **`itemSizing`**, `focusVisual`) is still accepted-and-ignored when bound. `itemSizing` is one this stage newly depends on. | **CLAIM CORRECTED, COVERAGE NOT EXTENDED.** The overstatement is fixed in both places it was made (`src/render/renderer.luau` scope comment, ownership-ledger §A F-1) and now names the uncovered props explicitly. Moving the check to `mount.luau`'s binding write — the reviewer's (a), and the genuinely complete seam — is a framework change with its own consumer-lockstep obligations and is **an open follow-up**, recorded here rather than attempted at the end of a stage. |
| **M-2** | `linkGridBoundaries` infers "visual neighbour" from array adjacency, which only holds for groups this module emits. A contribution's bundle is spliced in whole, in the order it returned, so a Grid beside a contributing control could be handed an exit into that control's *last* row. Also: an exit into a group whose members all filtered away. | **FIXED.** `src/present/focus_map.luau` now links only to a candidate whose name begins `auto-` **and** whose `order` is non-empty. Suite green. |
| **M-3** | `recoverPressDip` restores `handle.motionScale`, which belongs to the **presentation** authority (`setPresentationTransform`, and `parkEligible` refuses to recycle a handle that has one). Two authorities writing one engine property. Pre-existing on `MouseLeave`; **this stage's F-3 extended it to every mouse release**, turning a rare exposure into a common one. | **FIXED.** `src/client/screen_target.luau` reads `handle.uiScale` only. This was a regression this stage introduced and the review caught it. |
| **M-4** | `Table.rowGap` has two resolvers that disagree when `spec.env == nil`: the memo falls back to `themeSnapshot.neutral()` while the blueprint's `gap` resolves against the live snapshot. An env-less Table under a non-neutral package computes row tops from Studio Neutral's number. | **OPEN.** Real, and narrower than it looks: every shipped caller passes an env or a number. Recorded rather than fixed — the correct repair is to refuse a metric-name `rowGap` at the authoring boundary when no env was supplied, which is a public-contract narrowing and wants its own consumer sweep. |
| **M-5** | The drift lint does not mechanically cover two of the ledger's four claim clauses: "no platform branch" is one pattern, and "no parallel control machinery" has no rule. The `sizeClass -> 40/56/72` branch this stage removed would pass all four rules if rewritten with metric names. | **OPEN, and the sharpest finding.** The lint proves the value/authority half of the claim and not the adaptation half. The reviewer's R5 (ban an example reading `sizeClass`/`preferredInput`/`interactionClasses`/`safeArea*`/`viewport*` off `env`, with an allowlist) is the right shape and is the recorded follow-up. |
| m-1 | A refused bound enum throws *after* `takeDirty()` has drained the queue, so one bad value discards the rest of the batch and skips the solve. | **OPEN.** Inherent to the renderer seam and another argument for M-1's `mount.luau` move; they should be fixed together. |
| m-2 | Per-write schema lookup on the mount path, duplicating work `checkValue` already did for static values. | **OPEN, unmeasured.** The reviewer did not benchmark and neither did I. Same fix as M-1. |
| m-3 | `linkGridBoundaries` derives structural identity by parsing a group *name*; `emitGridGroups` should stamp `gridPath` on the table instead. | **OPEN.** Cosmetic given the M-2 fix now also requires an `auto-` prefix. |
| m-4 | The two focus derivations disagree about a Grid inside a contribution subtree, decided by an unrelated sibling. | **OPEN, pre-existing.** Worth a deliberate pinning test. |
| m-5 | **Leading and trailing space runs are still unreserved** — measure < paint, the unsafe direction, in the very function this stage fixed for interior runs. | **OPEN.** Correct and I accept it: `"  ab"` reserves the same as `"ab"`. Small (n × ~2.5 px) but the same family, one character away. |
| m-6 | The space-run change can move line COUNT, not just width, which is consumer-visible geometry the ledger described as width-only. | **PARTLY ANSWERED.** `consumer-impact.md` records the grep: no multi-space literals in the Sponsor surfaces, and the game suite is green at the judged source. The ledger wording is the part still owed. |
| m-7 | `rating.luau`'s public contract is intact and the director ruling's four requirements survive; the trade is that neither shape has a floor under the glyph. | **ACCEPTED AS DESIGNED.** The reviewer agrees the new failure mode is the better one. |
| m-8 | Three lifecycle defects in the new `examples` scenario: a failed `install` orphans the controller permanently; `dispose` runs before `dismiss`; the runner keeps a stale handle after a re-select. | **OPEN.** Verification-surface code, not shipped framework or example code. The live census (`studio/lifecycle.json`: 83 → 83 GuiObjects across a full seven-example cycle) shows no leak in practice, but the reviewer's reading of the failure paths is correct and they should be closed before the scenario is relied on further. |

## Phase-gate findings and what was done

The verdict is **REJECT**, and the charge is correct: three rows carried `PASS_AUTOMATED` that the
stored evidence did not earn. Nothing was argued away. The ledger and the gate were both corrected
so they now refuse.

| ID | Finding | Disposition |
|---|---|---|
| **BLOCKER-1** | **No captures exist anywhere in the artifact family**, yet six rows named captures as their artifact and were marked passed. The contract requires geometry **plus** a capture for layout/text/paint rows. | **ROWS DEMOTED.** EQ-1, EQ-3, EQ-5, EQ-11, EQ-12, EQ-13 → `PENDING`. Producing the capture set is open work. |
| **BLOCKER-2** | `audit.md` is the **pre-implementation** audit — verdicts still read `FAIL_PRODUCT`, no post-fix re-audit, and zero occurrences of `touch`/`gamepad`/`tablet`/`landscape`/`ten-foot`, which is the coverage EQ-1 demands. The guard grepped a heading prefix and so passed against it. | **GATE NOW REFUSES.** `play-teaching-matrix` → `FAIL_RECOVERABLE` with the reason inline. The source fixes are real; the evidence for the row is not. |
| **BLOCKER-3** | EQ-10/EQ-15 claim input paths nobody drove. `ex05.json` is pointer-only; `device-matrix.json` has no VirtualInput traces at all. And the stage had already MEASURED that `SendKey` cannot insert a character into a focused TextBox without recording it as `FAIL_ENVIRONMENT`. | **EQ-10 and EQ-15 → `FAIL_ENVIRONMENT`**; `example-05-native-input` and `device-matrix` → `FAIL_RECOVERABLE`. |
| **MAJOR-1** | The raw-event instrument was **dark** (InputBegan read 0 while the UI responded) and the artifacts explained it away using a different run against a different example. | **EQ-8, EQ-16, EQ-17 → `PENDING`.** The contract says mark `FAIL_ENVIRONMENT`, repair, rerun — not infer. |
| **MAJOR-2** | EQ-7 requires pointer **and** focus-based keyboard activation; only pointer was driven. | **EQ-7 → `PENDING`.** |
| **MAJOR-3** | EQ-5 says all seven examples; the evidence records example 1, and the check asserts only example 1. | **`theme-package-swap` → `FAIL_RECOVERABLE`.** |
| **MAJOR-4/5** | The device-matrix artifact drops the `judgedTrees` anti-vacuity counter the tool emits, drops the live-getter discriminators, collapses four rows to a hand-authored scalar, and no row exercised the KeyboardAndMouse presentation without disclosing it. | Folded into the `device-matrix` refusal above. |
| **MAJOR-6** | `rascalrally-consumer` PASSED on a ledger that declares its own Studio canary skipped. The ledger's honesty was fine; the check was the defect. | **CHECK FIXED** — it now fails while the canary is declared missing. Currently `FAIL_RECOVERABLE`, correctly. |
| **MAJOR-7** | `acceptance-ledger` is a **self-attesting guard**: it greps this ledger for its own status column and cannot detect any BLOCKER. | **PARTLY ADDRESSED.** It now asserts the honest states (including that EQ-10/EQ-15 are `FAIL_ENVIRONMENT` and that the capture gap is written down). The structural fix — asserting evidence rather than the status column — is **open**. |
| **MAJOR-8** | EQ-18's tree assertion does not exist; seven place files are byte-identical, so the stored evidence cannot tell a current place from a stale one. | **OPEN.** |
| **MAJOR-9** | Ledger/gate divergence and a stale closing note. | **FIXED** — the ledger's closing section now records the REJECT and the demotions. |
| MINOR-1..8 | Census scope, declared overlap exclusions, drift-lint soundness holes, `severity()` missing a `FAIL_PRODUCT` entry, lint scope. | **OPEN, all recorded.** |
| **MINOR-9** | **The tree was being written while the verifier read it** — its first gate run saw an all-`PENDING` manifest, its second a broken grep. | **ACCEPTED AS PROCESS.** A phase gate should be handed to acceptance control against a frozen tree. |

**The one thing the verifier asked NOT to change:** EQ-6 / LT-F3 stays `FAIL_PRODUCT`. It called the
scoping and the instrument caveat "the most rigorous work in this stage".

## The disposition that matters most

**Two of the five MAJORs are about this stage overstating what it closed** (M-1) **and one is a
regression this stage introduced** (M-3). Both are exactly what an independent read is for, and
both are now fixed or corrected in source. The remaining three are recorded open with the specific
change each would need — none is claimed as resolved.

## Why the Roblox-platform review was not run

It is triggered — `src/client/screen_target.luau` is engine-facing. It was not run, and this stage
does not claim it. The two engine-path findings the architecture review raised there (M-3, and the
`ensureScale` half of it) are stated from source with named headless corrective tests; a platform
reviewer would still be the right authority for the `UIScale` ownership question and for whether the
press dip needs its own instance. **This is an open acceptance control, not a passed one.**
