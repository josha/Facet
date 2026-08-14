# The 200k `Source` cap is on WRITING, not on loading

**Measured 2026-08-13, live Studio, `LuauUI-PerformanceLab.rbxl`.**

Two LuauUI modules are over 200,000 characters on disk:

| file | on disk |
|---|---|
| `src/client/screen_target.luau` | 229,860 |
| `src/controls/row_actions.luau` | 219,701 |

This session was carrying "two source files are over the 200k sync cap" as an
open risk that needed the files split. **It is not a risk, and they do not need
splitting for that reason.** Asked directly, the running Studio holds both in
full:

```
screen_target: 228676 chars, tail="ter\nend\n\nreturn screen_target\n"
row_actions:   219701 chars, tail="l,\n\t}\nend\n\nreturn row_actions\n"
```

Both end on their real final line. `screen_target` reads 1,184 characters
shorter than the file on disk — that is line-ending normalisation (one character
per line), not truncation.

## What the cap actually is

The limit we hit is on **assigning `Script.Source` from code** — the plugin /
Studio-MCP write path. A place file built by Rojo and opened by Studio does not
go through that path, so a module of any size loads intact.

So:

- **Writing** a >200k module via `execute_luau` / a plugin: refused. Split the
  write, or edit on disk and rebuild the place.
- **Loading** a >200k module from a `.rbxl`: fine, verified above.

## CORRECTION (2026-08-14, later): the cap was NOT the main cause that day

The section below is true about the cap and **wrong about why nothing synced**.
The primary cause was far more boring, and finding it took a split mission
noticing that `rojo serve` disagreed with disk:

**The showcase `rojo serve` had been running since 2026-07-26 — nineteen days —
and its file watcher was dead.** It served `screen_target` at 228,076 and had
never heard of eleven files created since, with 26 more stale. `touch`ing them
changed nothing. The perf-lab serve, started that same morning, was stale from
its own start time. The repo lives on a Dropbox CloudStorage path, which is the
prime suspect for the watcher never firing.

So the observation "additions land, modifications do not" — which I explained
with a story about an oversized write aborting the batch — was really "this
serve knows about the tree as it existed 19 days ago". A file added since simply
was not in its snapshot at all. **The story was plausible, fitted the evidence,
and was wrong**; the tell was that a 13,748-char module was stale, which no cap
can explain. Restarting both serves fixed it, verified by querying
`/api/read/<rootInstanceId>` for files created that day.

**Both failures are real and they stack.** A stale serve syncs nothing; a healthy
serve still cannot write a module at or over the cap. Check the serve's age
FIRST — `ps -o lstart -p <pid>` — and only then reach for the cap.

**And the cap is `>=`, not `>`.** Bracketed on the live engine: 200,000 refused,
199,999 written. Every write-up here originally said "over 200,000", and
`tools/check_source_size.py` used `>` until it was fixed — so a module at exactly
200,000 read as compliant while being silently unsyncable.

## And Rojo live-sync is a WRITING path (2026-08-14)

This is the operational bite, found by measuring a live session rather than
assuming the connection worked.

The showcase Studio was connected to `rojo serve` and looked healthy. Probing the
Edit datamodel directly:

| module | on disk | in Studio | current? |
|---|---|---|---|
| `LuauUI.row_capability` (**added** this round) | 5,735 | 5,735 | **yes** |
| `LuauUI.core.contract` (modified, small) | 3.4k | 3,420 | **no** |
| `LuauUI.core.custom` (modified, small) | 15,267 | 13,748 | **no** |
| `LuauUI.render.renderer` (modified, **220,891**) | 220,891 | 207,117 | **no** |
| `LuauUIScenarios/*` (separately mapped path) | — | — | **yes** |

**Additions land; modifications do not.** A live-sync patch has to assign
`Script.Source`, and three files now exceed the cap on disk — `renderer.luau`
220,891, `screen_target.luau` 234,055, `row_actions.luau` 234,591. Studio was
holding a 207,117-char `renderer`, i.e. the source baked into the place at build
time, because `rojo build` writes the file directly and is NOT capped.

So the same cap that is harmless for loading silently breaks the whole Studio
verification workflow: an agent runs a live check, sees a result, and reports it
as evidence about code the session has never seen.

**How to tell, in one probe:** ask the Edit datamodel for a string you committed
minutes ago. Do not infer sync from a connected-looking plugin.

**The workaround is a rebuild, not a hand-patch.** `tools/build_places.sh`
regenerates the place uncapped; the session has to be reopened for it to take.
Hand-writing `Source` into a running datamodel fails outright on the oversized
files and leaves a half-old, half-patched place — one had to be thrown away on
2026-08-13 for exactly that.

**This turns "should we split the big files?" from a taste question into an
operational one.** Three files over the cap cost live sync, and live sync is how
every device-class defect in this project has been caught.

### FOUR files, later the same day (2026-08-14)

`src/present/presenter.luau` crossed the line while ruling 9 was being built:
**207,333 on disk against 198,387 in the running showcase session** — probed
directly rather than inferred, exactly as the paragraph above says to. The fix
was in the tree, the suite was green on it, and the live session could not be
made to carry it at all: the sanctioned route is `tools/build_places.sh` plus
reopening the place, which throws away whatever session is open, and a
concurrent agent was using that one.

So the practical bite is now on the framework's THIRD most-edited file, and it
lands as a straight loss: a change to the presenter can no longer be watched
happen. The number to watch is the file, not the feature — `presenter.luau` sat
at 205,909 before this round and no single change put it over; it crossed on
ordinary growth. The list is `renderer.luau`, `screen_target.luau`,
`row_actions.luau`, `presenter.luau`.

**A cheap operational half-measure worth having:** a check that fails when a
module crosses 200,000 characters, naming the live-sync consequence, so the
crossing is a decision somebody makes rather than something a session discovers
three files later.

### The cap is `>=`, not `>` — measured, not read (2026-08-14)

Asked directly, in a live session, on a throwaway ModuleScript, at four lengths:

| assigned `Source` length | engine |
|---|---|
| 234,757 (`row_actions.luau`, before) | **refused** |
| **200,000 exactly** | **refused** |
| 198,960 | wrote, read back 198,960 |
| 183,738 (`row_actions.luau`, after) | wrote, read back 183,738 |

> `Unable to assign property Source. Provided string length (200000) is greater
> than or equal to max length (200000)`

Every write-up above, this file's own first line included, said "over 200,000".
The boundary is **at** 200,000. `tools/check_source_size.py` was written with
`size > CAP`, so a module sitting at exactly 200,000 characters would have read
as compliant and been silently unsyncable — the precise failure this whole file
exists to prevent, reintroduced by the check built to prevent it. Fixed to `>=`,
with a mutation proving it bites at 200,000 and stays silent at 199,999.

The general form is the same one this file already argues: **a limit is a
property of an operation. Run the operation.** One `pcall` in a live session
answered a question that three careful write-ups had all been slightly wrong
about.

### The first file back under, and what the seam actually was (2026-08-14)

`row_actions.luau`: **234,757 -> 183,738**, six commits, `buildEngine` untouched.
The list above is now `renderer.luau`, `screen_target.luau`, `solver.luau`,
`presenter.luau`.

The architecture gate's own read of this file was that ~375 lines of periphery
were extractable — under 9%, and nowhere near enough — because it stopped at the
top-level functions. **The seam is bigger than the top level, and the test that
finds it is one question, asked per block:**

> does this read or WRITE a *mutable* upvalue of the big closure?

`buildEngine`'s ~65 nested functions share ~60 upvalues, but only about twenty
are ever reassigned (`spring`, `controller`, `drag`, `committed`, `commitLatched`,
`menuHandle`, `rootPath`, `restorePending`, `api`, …). The rest — every
`core:signal`/`core:memo` — are created ONCE and never reassigned, so a block that
merely READS them can take them as arguments and behave identically. That is what
took the two largest pieces out (the tray views, 18k; the row node, 19k) without
threading any state record anywhere.

**Mechanise the question rather than eyeballing it.** A twenty-line script that
lists every `local` in the closure and every line that assigns one afterwards
separates "shared and mutable" from "shared and frozen" in seconds, and that list
is the extraction plan. Two false-positive classes to expect: table-constructor
keys (`id = ...` inside a `UI.Button{}`) and same-named locals in inner scopes.

**Two traps this run actually hit, both caught by a check rather than by care:**

* **A new file under `src/controls/` needs a `controls_registry` row AND a
  large-text `UNSWEEPABLE` reason.** The first extraction shipped with the
  registry row and without the sweep reason; the failure was real and invisible,
  because nine other agents' reds were in the same transcript. If the full suite
  is noisy, build a focused runner over the specs your file owns and treat THAT
  as the gate — one crisp number you can compare run to run.
* **Landing at 198,960 is not landing.** The header comment explaining where the
  six siblings went cost 2,267 characters and put the file back over at 201,227.
  Stop at a real margin, not at 199,9xx: a ceiling reached by a hair is a file
  that crosses again on its next honest comment.

## The cap is NECESSARY, not sufficient: a stale `rojo serve` is the other half

**Measured 2026-08-14, at the end of the `screen_target` split.** Getting the file
under the cap was verified two ways and both passed:

* **The cap, bracketed on the live engine.** Assigning the split file's 189,670
  characters onto a running `ModuleScript.Source` SUCCEEDS; the same file padded
  back to 217,670 is REFUSED. So the file is once again writable through every
  live path.
* **The sender carries it.** A freshly started `rojo serve` on the showcase
  project serves `screen_target` at 189,163 chars (the disk file less its line
  endings) plus both new siblings.

**And live sync was still dead — for a completely different reason.** The
`rojo serve` the showcase Studio has been connected to (`--port 34873`) was
started **2026-07-26**, nineteen days earlier, and its file watcher had stopped
seeing the tree. Asked for its own tree it reported:

| | shared serve (19 days old) | disk / fresh serve |
|---|---|---|
| `screen_target` | 228,076 | 189,163 |
| `screen_chrome` | 111,737 | 114,846 |
| `screen_paint`, `screen_scroll_indicators`, `presentation`, the six `row_actions_*` | **absent** | present |

Eleven files it had never seen and twenty-six more stale. `touch`ing two of them
and re-reading changed nothing, so this is not a debounce.

**Two independent processes, the same failure.** The performance-lab serve
(`--port 34874`) was started the same morning and is stale from *its own* start
time — current on `screen_chrome`, five hours behind on `screen_target`. The
repo lives on a Dropbox CloudStorage path, where fsevents are not dependable.

So the diagnosis "the file is over the cap, that is why it does not sync" was
right about the file and incomplete about the pipeline. **Check the SENDER too,
and check it the same way you check the receiver — by asking it what it holds:**

```
ROOT=$(curl -s http://127.0.0.1:34873/api/rojo | python3 -c "import sys,json;print(json.load(sys.stdin)['rootInstanceId'])")
curl -s "http://127.0.0.1:34873/api/read/$ROOT" | python3 -c "…len of Properties.Source.String…"
```

A serve older than the change you are looking for cannot be the reason your edit
arrived, and it is a silent one: the plugin shows connected, the port answers,
and the tree is a fortnight old. **Restart `rojo serve` before trusting any live
check**, and prefer a serve whose start time is younger than your edit.

## Why this is worth a file

A cap observed on one path was generalised to every path, and that generalisation
turned into a standing "these files must be extracted" item that would have cost
a large, risky refactor of the two most defect-dense files in the framework for
no correctness reason at all.

There are still good reasons to split those two files — they are hard to review
and hard to reason about, and `row_actions.luau` has a documented history of
repeat defects. **Split them for maintainability if and when that is the goal, on
its own evidence.** Do not split them because of this cap.

*(Updated 2026-08-14: that paragraph is still right about WHY, and the cap turned
out to supply the evidence anyway — not because loading fails, but because the
verification workflow stops working. `row_actions.luau` was split on exactly that
argument; see the section above.)*

The general rule: a limit is a property of an *operation*, not of a *file*.
Before inheriting "X is too big", ask which operation refused it, and test the
operation you actually care about.
