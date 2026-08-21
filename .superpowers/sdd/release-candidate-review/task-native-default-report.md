# Native-style default flip — implementer's report

**Status: DONE.** `native_style.DEFAULT_ENABLED` is `true`. Facet suite **6905**
(baseline 6892), Rascal Rally suite **3460** (baseline 3449), both zero red, both
measured in private rsync exports. Two Facet commits, one Rascal Rally commit.

| | Facet | Rascal Rally |
|---|---|---|
| commits | `c1120fc`, `50887a8` | `5dff3de` |
| suite | 6905 passed (was 6892) | 3460 passed (was 3449) |
| red rounds | 8 red, then 1 red | 10 red |

---

## 1. What changed, and the shape it took

The flip itself is one boolean. The thing that made it a *task* is what the red
round found: **nothing in the repository pinned the old default.**
`DEFAULT_ENABLED` appeared in exactly two source lines and no spec, because its
only reader — `screen_target.new` — needs a `LocalPlayer` and a DataModel and
cannot run headlessly at all. The library's most consequential single boolean
could have been flipped, or flipped *back*, by an edit no gate could see.

So the default-resolution rule left the closure it was buried in:

* `native_style.resolveOpt(opt)` — pure, the only reader of `DEFAULT_ENABLED`.
  `nil` → the library default; `false` → `false`, untouched; anything else →
  itself, **by identity** (the config table's `handle`/`model`/`host`/`theme`/
  `transitions` are read back off the object the caller passed, so a resolver
  that rebuilt the table would drop every key it did not know). It never answers
  `nil`, which is why the caller's whole condition is now `~= false`.
* `screen_target.new` calls it instead of re-deriving it. That is also why a
  product-behaviour change cost the near-cap `screen_target.luau` **108
  characters** (193,206 → 193,314; trigger 194,000, 686 away). Its
  `SOURCE_CAP_LEDGER` row is re-recorded with the new number and the note that
  the seam analysis was re-read and stands.

`tests/native_style_default.spec.luau` (new, 13 cases) is the witness: the
default, the escape hatch, the identity pass-through, the never-`nil` invariant,
the seam really being the one the shipped adapter asks, who the default does
**not** sweep, the ADR row, and the gallery's A/B precedence.

## 2. Every red, and its verdict

**Round 1 — Facet, 8 red.** All eight were *new pins on the new behaviour*, not
existing specs that had to be re-verdicted. **No pre-existing Facet spec went red
from the flip**, for the structural reason above: the only consumer of the
default is engine-bound, so nothing headless could have been pinning it.

| red | verdict |
|---|---|
| the default IS sheet paint | **new pin** — `DEFAULT_ENABLED` had no spec at all before today |
| NO opt resolves to the library default | **new pin** — the flip's whole meaning, red because the resolver did not exist |
| an explicit `false` STILL refuses | **new pin** — guards the escape hatch; would have gone red if the flip had taken the fallback branch with it |
| an explicit `true`/table passes through untouched | **new pin** — identity, so a config table keeps keys the resolver never heard of |
| the resolver never answers `nil` | **new pin** — a `nil` answer would make `~= false` true for "no answer", the original defect in reverse |
| `screen_target` routes through the seam, no second copy | **new pin** — a pure function agrees with itself; this is what says the shipped adapter asks it |
| the flip is RECORDED in ADR-0040 | **new pin** — the record is what makes it legal on an unreleased `0.10.0` |
| gallery: neither attribute set → the library default | **fix** — the boot hardcoded `false` there, which would have left the framework's own demo place the last consumer unable to see the framework's own default |

Four gallery-precedence cases were **green on the first run**, deliberately:
`paint_mode.luau` was first written as a faithful extraction of the shipped
`and`/`or` expression, so the three answers that must *not* move proved
themselves before the one that must moved.

**Round 2 — Facet, 1 red.** See §5 (the edit preview).

**Round 3 — Rascal Rally, 10 red**, run against the *pre-flip* Facet in a
two-tree export so the reds were real: five tri-state flag cases and five
paint-path contract cases. One further red appeared on the green run and was a
**re-verdict**: the shipped `nativeStyle`-site sweep counts *lines containing the
word*, and the four call-site comments now name the reader in prose — so the
check failed for saying what it does. It now skips comment lines and requires a
**call** to a `nativeStyle*` reader rather than the word, which is strictly
tighter than what it replaced (the word was vacuous: every swept line contains it
by construction).

## 3. The consumers

**`screen_target.new({})` → sheet paint; `nativeStyle = false` → still refused.**
Both pinned. The gallery's A/B driver moved out of a LocalScript argument list
into `examples/gallery/client/paint_mode.luau`, beside `boot_mode.luau`, for the
same reason and with the same spec technique (each attribute read exactly once,
into the decision, asserted by counting). Precedence, verified red-first:

1. `Facet_ForceStyleFallback` wins over everything → explicit `false`;
2. `Facet_NativeStyle` = redundant-but-harmless, still the carrier for
   `transitions`;
3. neither → **`nil`**, so the place follows the library. This is the one answer
   the flip moves.

`Facet_NativeTransitions` alone now also opts in — before the flip it did nothing
without `Facet_NativeStyle` beside it, and an attribute whose only purpose is
enhancing sheet paint asking for nothing would be a dead switch in the place that
demonstrates it.

Boots and copy corrected:

* **theme picker console line** — was *"Set `Facet_NativeStyle = true` before Play
  to see the full transaction"*, which now instructs a designer to set an
  attribute that is already the default. Now: *something opted OUT — clear
  `Facet_ForceStyleFallback`*.
* **`docs/guide/09-custom-themes.md`** — same instruction, same fix.
* **`docs/guide/05-styling.md` §5.7** — retitled from "(opt-in)" to "(the
  default)"; three-line example showing default / explicit / **opt-out**; the
  fallback paragraph now says it is a first-class path, not a legacy one.
* **`docs/reference/api.md`** — the `nativeStyle` opt row: absent **is** sheet
  paint; `false` **is** the opt-out and wins.
* **ADR-0018** — status line and Decision preamble record that the opt is
  inverted; nothing about the mechanism changed.
* **performance lab** — keeps its explicit `false` **on purpose** and now says
  why: every budget and capture in `artifacts/perf/` was measured with the
  adapter as the only writer of every paint property. Taking the sheet path there
  would move instance counts and paint timings under numbers recorded against the
  other painter. Flagged as a follow-up in §7, not changed.

## 4. The record

* **ADR-0040 row B-15** added under ruling R15, immediately after B-14 with no
  blank line (a blank line severs the table). It names what moved, what a
  consumer's own code touches (no `UICorner`/`UIStroke` instances exist under a
  Facet root any more), that the adoption evidence measured the two paths
  byte-equal so the *mechanism* is what changed, the opt-out, and that Rascal
  Rally moves with it in the same task. The existing ADR-0040 instrument needed
  no change: it pins blueprint **props**, and this is a library default, so the
  new spec carries the "record exists" half itself.
* **`artifacts/native-stylesheets/promotion-readiness.json`** — the `refreshed`
  block now carries a `decision` field (made by the director, 2026-08-21,
  `DEFAULT_ENABLED = true`) and a `remaining` field (Step 14 publish). It states
  plainly that the block used to say this was "the owner's call at the Step 14
  checkpoint" and that the owner has now made it ahead of that checkpoint, so
  `stillRequired` is no longer a gate *on* the decision but the evidence the
  publish event collects about a default that is already live. The frozen
  2026-07-24 rows are untouched.

## 5. The defect the flip exposed: the Studio edit preview

The flag's own comment claimed **two** exemptions from the default — billboards
and the edit preview — and the code only had one. `billboard_target` has always
passed an explicit `nativeStyle = false`; `edit_preview.luau` passed nothing, so
the flip swept it.

That is not cosmetic. The preview harness runs in the **Studio Edit DataModel**,
where `native_style.ensure` seeds a persistent `FacetStyle` StyleSheet that the
next place save commits — the exact furniture that module's header promises never
to leave behind (verifier F5) — and `dispose()` cannot take it back, because the
sheet is seed-once by design. It costs nothing to look at: the two paint paths
were measured byte-equal on every mapped property, so a preview painted the
explicit-write way shows what the game shows.

Fixed red-first in `50887a8`, with the case pinning **both** exemptions rather
than the one that moved — "who the default does not sweep" is the half of a
default nobody writes down.

## 6. Rascal Rally lockstep

**The flip changed this game's live paint path with nothing in the package
changing**, and that is the finding rather than an inconvenience: all four
adapter sites (`GaragePilotGui`, `FacetRacerListGui`, `FacetSettingsGui`,
`FacetSponsor/init`) pass the flag's answer straight through, and with the
workspace attribute absent — what every shipped place carries — that answer is
**no opt**, which is exactly what the framework's default answers. Their comments
already predicted it ("so the game follows the framework's default flip
automatically").

**The one behaviour question, and a judgement call the controller may veto.**
`FacetFlags.nativeStyleOn()` answers `== true`, which maps **both** "absent" and
"explicitly `false`" onto the same call-site argument (`nil`). That was harmless
while both meant the bespoke painter. The moment "absent" started meaning the
sheet they became opposites, and leaving the boolean in place would have **left
`UseFacetNativeStyle = false` doing nothing at all** — a Studio-togglable flag
that silently stopped being a switch, on exactly the attribute somebody reaches
for to roll back.

`FacetFlags.nativeStyleOpt()` passes the framework's own tri-state through:
absent → `nil` (the library decides), `true` → `true`, `false` → **the rollback**,
still winning over everything, through both spellings of the attribute. A
non-boolean value reads as absent, never as `false`, so a typo cannot force the
fallback painter on a shipped place.

**This changes no behaviour beyond what the flip implies.** With the attribute
absent — the shipped state, confirmed: no RR place file or project JSON sets it —
the tri-state and the boolean produce the identical answer. With it explicitly
`false`, the tri-state *preserves* the pre-flip behaviour that the boolean would
have discarded. It is the same shape the studio already used when the Sponsor
default flipped in 2026-08-03 (`UseFacetSponsor = false` = the rollback), which
the root constitution cites by name. **The legacy Sponsor modules are shipped and
untouched, and `UseFacetSponsor = false` remains the Sponsor rollback**; nothing
in this task read or wrote that flag's behaviour.

Game-side evidence:

* `tests/facet_theme_paint_contract.spec.luau` — new block, 5 cases: the
  framework copy this package requires really carries the flip; the flag's answer
  **composed with the framework's own resolver** is sheet paint with nothing set;
  the rollback survives through both spellings; explicit `true` is
  redundant-but-harmless; and all four sites really pass the *opt* (a site that
  reverted to `if …nativeStyleOn() then true else nil` would silently delete the
  rollback and nothing else in the suite would notice).
* The tinted-plate case written as *"the compatibility floor for the day that
  flag flips"* is **re-verdicted, not re-pinned**: the day came, so it is a live
  assertion about the shipped paint path now.
* `tests/facet_flag_migration.spec.luau` — 6 tri-state cases, dual-read across
  the rename preserved. Its `luau.load` fixture moved to
  `tests/lib/facet_flags_fixture.luau` because a second spec needed it.
* `games/RascalRally/docs/migrations/facet-attribute-migration.md` updated.
  **Note: that path is not under version control** (the RR git root is
  `games/RascalRally/code`), so the edit is on disk only, not in `5dff3de`.

## 7. Guards, evidence, and concerns

**Guards, all run in the export** (`check_brand_drift` needs `git ls-files`, so it
ran in the shared tree and is read-only):

| guard | result |
|---|---|
| `check_theme_artifacts` | PASS (8 artifacts, 137 checks) |
| `check_library_purity` | PASS |
| `tools/check_types.py` | PASS |
| `check_brand_drift` | PASS |
| `check_source_size` | PASS (`screen_target` 193,314; 686 from its trigger) |
| `check_doc_style` | PASS — *failed first*: my guide edits used `B-15`/`NSS-A10` as bare shorthand in consumer-facing prose; rewritten to cite ADR-0040 by link and to say "the native-stylesheets adoption evidence" |
| `check_flat_baseline` | PASS (1461 flat nodes byte-compared) |
| `check_example_drift_cli` | PASS (74 files) |
| `check_docs_cli` | PASS |
| `stylua --check src tests tools examples` | PASS |

**The 99-token style-editor-sync evidence
(`artifacts/theme-packages-and-skinning/theme-sync/parchment-live-dump.json`) was
NOT regenerated, and the flip does not invalidate its premise.** It is a token
dump read off a live theme sheet's typed attributes, captured with native paint
active. The flip makes that state the *default* rather than an opt-in; nothing
the capture asserts depends on how the target arrived there. If anything the
capture is now more representative, since it documents the shipped path.

**Concerns for the controller:**

1. **A place saved with `UseFacetNativeStyle = false` will now paint bespoke in
   Rascal Rally.** Before this task it would have painted bespoke too, so this is
   preservation rather than a change — but the same-session Studio canary should
   **check that attribute before concluding anything from the screenshots**. No
   RR place file or project JSON sets it, so the expected canary state is sheet
   paint.
2. **The tri-state (§6) is my judgement, not the director's ruling.** It is one
   function and four call sites; reverting to the boolean is mechanical if the
   controller would rather the flag simply become inert.
3. **The performance lab still measures the non-default path.** Deliberate and now
   documented, but it means the perf budgets no longer describe what ships. A
   re-baseline of `artifacts/perf/` on the sheet path is a real follow-up — out of
   scope here because it invalidates every recorded number.
4. **`screen_target.luau` is 686 characters from its extraction trigger.** The
   flip's edit went the right way (a seam left, not a line added), but the next
   change of any size to that file should take the `screen_vocabulary.luau`
   extraction its ledger row names.

**Nothing was CONTESTED.** No locked file (`renderer`, `presenter`, `solver`,
`virtual_list`, `table`) was touched, and none needed to be.
