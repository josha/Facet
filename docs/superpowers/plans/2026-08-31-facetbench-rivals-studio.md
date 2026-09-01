# FacetBench Rivals + Studio Runner (Plan 2 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the five rival frameworks (vendored + adapters), two more game workloads, and a live Roblox Studio runner with microprofiler capture — Phases 2–3 of the approved spec.

**Architecture:** Rival adapters are **top-level Lune-safe** (module scope touches no vendored code and no Roblox globals; `capabilities.headless = false`; all vendor access happens inside `mount`/`applyStep` via instance requires) so the existing Lune harness loads them, shape-checks them, and reports honest `live-only` rows, while Studio measures them for real. The Studio runner reuses the SAME pure measurement core (`run_one_lib`) via a rojo place project that mirrors the on-disk layout — probe-verified: string requires (`./`, `../`, nested) work inside Studio ModuleScripts. Results leave Studio through marker-prefixed console JSON scraped by the MCP driver.

**Tech Stack:** As Plan 1 (Lune 0.10.4, StyLua 2.5.2, tabs) + rojo 7.7.0 and wally (rokit-pinned) + npm (Blend) + Roblox Studio via MCP tools.

**Spec:** `GameStudio/ui/Facet/docs/superpowers/specs/2026-08-31-facetbench-and-perf-fixes-design.md` (Part 1, Phases 2–3). Carried items: `GameStudio/ui/Facet/docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md`.

## Global Constraints

- All paths relative to `GameStudio/ui/FacetBench/` unless prefixed. FacetBench commits only; the sibling `GameStudio/ui/Facet` repo is read-only for every task in this plan.
- Toolchain: existing pins; Task 4 adds `rojo = "rojo-rbx/rojo@7.7.0"` and `wally = "UpliftGames/wally@0.3.2"` to `rokit.toml`.
- **Pristine-vendor rule:** everything under `frameworks/<name>/vendor/` is a byte-exact upstream copy — never edited, never stylua'd. `stylua --check` must exclude vendor dirs (Task 4 adds a `stylua.toml` with an `excludes` glob or moves the check to explicit non-vendor paths in `tools/check.sh` — whichever StyLua 2.5.2 supports; verify). Each `frameworks/<name>/` carries `UPSTREAM.md`: source URL, tag/commit, fetch command, license note.
- **Licenses:** Vide/Fusion/React-lua/Blend are MIT — vendor them WITH their LICENSE files. **Flux has NO license** (verified 2026-08-31): its code is NEVER committed. `frameworks/flux/vendor/` is gitignored; `frameworks/flux/FETCH.sh` clones it locally at pinned commit `7cb254b`; the adapter reports honestly when vendor is absent.
- **Registry rename (supersedes Plan 1's `@self` form):** `frameworks/init.luau` → `frameworks/registry.luau` and `workloads/init.luau` → `workloads/registry.luau`, with sibling requires as plain `require("./name")` (legal in Lune outside init.luau; probe-verified legal in Studio; `@self` in Studio is UNVERIFIED and now unused). Every consumer require updated (`require("../frameworks")` → `require("../frameworks/registry")` etc.).
- **Rival adapter rule (fairness + dual-runtime):** module scope must be pure Luau — no `game`, no `script`, no vendor requires; declare `capabilities.headless = false`; resolve vendor modules inside `mount` via the `target` argument's tree or `script`-relative instance requires guarded to Studio. `applyStep` must FLUSH the framework's work before returning (contract rule from Plan 1).
- Workload scripts: seeded PRNG only, cycle-safe (two-pass `scene.validateSteps` must pass), exact step-mix counts pinned by tests.
- Every task: `lune run tests/run` green, `tools/check.sh` green before commit, TDD where the task creates testable Luau, SPECS registration for new specs.
- Studio work targets ONLY the open blank place (`Place1`, unsaved); create instances under dedicated folders and clean up; never touch the user's other Studio state. Standing trap: probe a commit marker in synced sources before trusting any Studio reading.
- Results: `artifacts/` for smoke output (gitignored); committed `results/` baselines remain Plan 3.

---

### Task 1: Opening chores (carried fixes) + registry rename

**Files:**
- Modify: `tests/facet_adapter.spec.luau` (dead guard), `runner/lune/lib/matrix_util.luau` (+ its spec), `tools/check.sh`, `runner/lune/lib/stable_json.luau` (+ scene/stable_json spec), `tests/run.luau`
- Rename: `frameworks/init.luau` → `frameworks/registry.luau`; `workloads/init.luau` → `workloads/registry.luau`; update every require of `"../frameworks"`, `"../../frameworks"`, `"../workloads"`, `"../../workloads"`, `"../../../workloads"` to the `/registry` form (grep the whole repo; the old directory-form requires now FAIL since no init.luau exists — that failure is the proof the sweep is complete)

**Interfaces:**
- Produces: `require("<path>/frameworks/registry")` and `require("<path>/workloads/registry")` as the only registry access form (consumed by every later task; sibling entries inside the registries use `require("./battle_hud")` / `require("./_fixture/adapter")` plain relative form).

- [ ] **Step 1: Failing/red first.** Make the five carried fixes test-first where a test exists:
  1. `tests/facet_adapter.spec.luau:53` — change `#before` to `#beforeOrder` (dead guard becomes live; run the spec to confirm it still passes — the guard should hold with real rows).
  2. `matrix_util.acceptChild` — require the decoded last line to be a JSON OBJECT (reject arrays): add spec case (array last line → error), see it fail, then add an `assert(type(decoded) == "table" and decoded[1] == nil and next(decoded) ~= nil, ...)`-style object check (a row always has string keys).
  3. `matrix_util.parseArgs` — trailing flag with no value must error loudly: spec case first (`{"--sizes"}` → error), then implement (`assert(args[i+1] ~= nil, ...)`).
  4. `stable_json` — non-finite numbers must error (invalid JSON otherwise): spec case (`math.huge`, `0/0` → error), then implement (`assert(v == v and v ~= math.huge and v ~= -math.huge, "stable_json: non-finite number")`).
  5. `tools/check.sh` — drop the duplicate selftest execution: remove `lune run tools/check_runner` from check.sh **and instead** keep it but drop the `runner_selftest.spec` registration? NO — ruling: keep the SPEC (it also tests assertBand bite) but change its final section to run `selftest.run()` ONLY when env var `FACETBENCH_FULL=1` is set (Lune: `require("@lune/process").env.FACETBENCH_FULL`); `tools/check.sh` exports `FACETBENCH_FULL=` (empty) before `tests/run` and keeps `check_runner` as the single real measurement. Spec asserts band-bite always; the measured run becomes conditional. Verify: `time tools/check.sh` drops by roughly one selftest (~10-20s).
- [ ] **Step 2: Registry rename.** `git mv frameworks/init.luau frameworks/registry.luau && git mv workloads/init.luau workloads/registry.luau`; inside them, change `require("@self/<x>")` to `require("./<x>")`. Sweep every consumer: `grep -rn '"\.\./frameworks"\|"\.\./\.\./frameworks"\|"\.\./workloads"\|"\.\./\.\./workloads"\|"\.\./\.\./\.\./workloads"' --include="*.luau" .` and append `/registry` to each. Run `lune run tests/run` — any missed site fails loudly.
- [ ] **Step 3: Green + commit.** `tools/check.sh` fully green. Commit: "chore: carried fixes (guard, object rows, loud args, finite json, single selftest) + registry rename for dual-runtime requires"

---

### Task 2: war_room_inventory workload

**Files:**
- Create: `workloads/war_room_inventory.luau`
- Modify: `workloads/registry.luau` (one line), `tests/run.luau`
- Test: `tests/war_room_inventory.spec.luau`

**Interfaces:**
- Produces: registry entry `war_room_inventory` (Workload shape as battle_hud: `{name, requires = {"reactive","keyedList"}, sizes = {S=150, M=500, L=1500}, build, script}`). This is the workload that finally EMITS `reorder` steps.

**Scene (build):** state: `items` list of N entries `{ key = "i"..k, name, tier (1..5), power (rng int), icon }`; scalar states `sortMode` (string), `gold` (number). Root vertical panel: header horizontal panel (label bound `{ref="sortMode"}`, label bound `{ref="gold"}`), then the `items` list — row template: horizontal panel with name label `{item="name"}`, tier bar `{value={item="tier"}}` (adapter scales), power label `{item="power"}`, icon image `{item="icon"}`.

**Script (600 steps = 30 × 20-slot pattern, all via rng, cycle-safe):**
- Slots 1–6: `updateItem` power on a random LIVE item (generator tracks the live set).
- Slots 7–8: `reorder` — the generator maintains a model of live items and emits `order` = live keys sorted by (slot 7) power descending, (slot 8) name ascending — full deterministic permutations of the CURRENT live set.
- Slots 9–12: churn — a FIFO discipline like battle_hud's damage queue but over a "stash" of removed item keys: slot behavior = if the stash is below `n // 5` and there are live items beyond a floor of `n // 2`, `removeItem` a random live key (push to stash); otherwise `addItem` re-adding the oldest stashed item (same key, fresh table, rng-refreshed power). The generator guarantees by construction that BY SCRIPT END the stash is empty (every removed key re-added) — mirror battle_hud's drain: once remaining churn slots ≤ stash size, always re-add.
- Slots 13–14: `updateItem` tier on a random live item.
- Slots 15–16: `setState` gold / sortMode (rng pick from {"power","name","tier"}).
- Slots 17–19: `updateItem` power again (hot path weighting).
- Slot 20: `noop`.

Pinned counts (assert in spec): `updateItem == 330` (6+2+3 per pattern × 30), `reorder == 60`, `addItem + removeItem == 120`, `setState == 60`, `noop == 30`, total 600. Cycle-safety: every removed key re-added by end (stash empty ⇒ live set returns to initial membership, so pass 2's removes/adds replay validly); `reorder.order` is always a permutation of the CURRENT live set at that point in the script (the generator's model makes this exact).

- [ ] **Step 1: Failing spec** mirroring `tests/battle_hud.spec.luau`'s structure: registry entry exists; sizes 150/500/1500; build determinism (deepEqual twice, same seed); script determinism; `scene.validate` + `scene.validateSteps` (two-pass — this ALONE proves cycle-safety incl. every reorder permutation); exact counts above; per-size validateSteps sweep S/M/L; plus: at least one reorder's `order` differs from the current insertion order (proves permutations are non-trivial — compute by replaying the generator's model or simply assert `steps` contains a reorder whose `order[1] ~= "i1"` for seed 2).
- [ ] **Step 2: Implement** the workload per the shape above (battle_hud is the structural precedent in-repo; the generator's live-set + stash model is the new part — keep it a small pure closure over arrays, no clock, no math.random).
- [ ] **Step 3: Green** (`lune run tests/run`), register spec, `stylua --check`, commit: "feat: war_room_inventory workload (reorder + churn stress, cycle-safe)"

---

### Task 3: killfeed_nameplates workload

**Files:**
- Create: `workloads/killfeed_nameplates.luau`
- Modify: `workloads/registry.luau`, `tests/run.luau`
- Test: `tests/killfeed_nameplates.spec.luau`

**Interfaces:**
- Produces: registry entry `killfeed_nameplates`, sizes `{S=50, M=200, L=600}` (peak concurrent elements). Stress: mount/unmount churn.

**Scene:** state: `feed` list (starts empty) — template: label `{item="text"}`; `plates` list (starts at n/2 entries `{key="p"..k, name, hp}`) — template: horizontal panel (name label `{item="name"}`, hp bar `{value={item="hp"}}`); scalar `alive` (number). Root: vertical panel (feed list, plates list, footer label `{ref="alive"}`).

**Script (600 = 30 × 20):** slots 1–8: feed churn — addItem fresh `{key="k"..counter, text="X eliminated Y"}` OR removeItem oldest, FIFO capped at `n // 4`, drained to empty by script end (battle_hud's exact discipline, bigger share); slots 9–14: plates churn — spawn/despawn plates with a stash-and-re-add discipline (as war_room churn) bounded so live plates stay within [n/4, n/2], returned to initial membership by end; slots 15–16: `updateItem` hp on a random live plate; slot 17: `setState` alive; slots 18–19: feed churn again; slot 20: noop.
Pinned counts: `addItem + removeItem == 480` (8+6+2 churn slots × 30), `updateItem == 60`, `setState == 30`, `noop == 30`, total 600.

- [ ] **Step 1: Failing spec** (same checklist as Task 2: determinism, two-pass validateSteps at S/M/L, exact counts, churn dominance `(addItem+removeItem)/600 == 0.8`).
- [ ] **Step 2: Implement.** The two churn disciplines are the battle_hud drain generalized; keep one shared local helper INSIDE the file (a `churnQueue(cap)` closure factory) rather than a cross-file abstraction.
- [ ] **Step 3: Green, register, stylua, commit:** "feat: killfeed_nameplates workload (mount/unmount churn, cycle-safe)"

---

### Task 4: Vendor the rivals (verified recipes) + toolchain + stylua exclusion

**Files:**
- Modify: `rokit.toml` (add rojo 7.7.0, wally 0.3.2), `tools/check.sh` (vendor-excluded stylua), `.gitignore` (add `frameworks/flux/vendor/`, `node_modules/`)
- Create: `frameworks/{vide,fusion,react,blend,flux}/UPSTREAM.md`, `frameworks/flux/FETCH.sh` (executable — remember `git update-index --chmod=+x`), vendored trees below
- Test: `tests/vendor_integrity.spec.luau` (+ register)

**Interfaces:**
- Produces: on-disk vendor layout every adapter task consumes:
  - `frameworks/vide/vendor/vide/` = clone of github.com/centau/vide at tag `0.4.1` (BARE tag, no v) — keep `src/` + `LICENSE.md`; entry for headless-core probing is `src/lib.luau`, Roblox entry `src/init.luau`.
  - `frameworks/fusion/vendor/Fusion/` = clone of github.com/dphfox/Fusion at tag `v0.3-beta` (the ONLY 0.3 tag) — keep `src/` + `LICENSE`. Instance-requires only; Roblox-only (RobloxExternal calls game:GetService at module scope).
  - `frameworks/react/vendor/` = wally output: write `frameworks/react/vendor/wally.toml` with `[dependencies] React = "jsdotlua/react@17.2.1"`, `ReactRoblox = "jsdotlua/react-roblox@17.2.1"`; run `wally install` there; COMMIT the resulting `Packages/` (~18 packages incl. luau-polyfill closure) + copy the repo LICENSE from github.com/jsdotlua/react-lua into `frameworks/react/vendor/LICENSE`.
  - `frameworks/blend/vendor/` = npm: `cd frameworks/blend/vendor && npm init -y >/dev/null && npm install @quenty/blend` then COMMIT `node_modules/@quenty/*` ONLY (prune everything else; keep each package's src + package.json; the monorepo LICENSE.md → `frameworks/blend/vendor/LICENSE.md`). Blend's dep closure (verified): acceltween, brio, ducktype, instanceutils, loader, maid, promise, rx, signal, spring, steputils, string, uiobjectutils, valuebaseutils, valueobject. NOTE: `.gitignore`'s `node_modules/` must NOT swallow this — use `!frameworks/blend/vendor/node_modules/` negation or vendor into a renamed `quenty/` dir (renaming the DIR is allowed — renaming/editing FILES inside packages is not). Prefer the rename: `frameworks/blend/vendor/quenty/@quenty/...`.
  - `frameworks/flux/vendor/` = GITIGNORED. `FETCH.sh`: `git clone https://github.com/tarekmahmouduix/Flux.git "$(dirname "$0")/vendor/Flux" && git -C "$(dirname "$0")/vendor/Flux" checkout 7cb254b`. UPSTREAM.md states loudly: NO LICENSE upstream ("all rights reserved" default) → never committed, fetched locally only; remove if the author objects; ask author for a license to lift this.
- Produces: `tests/vendor_integrity.spec.luau` asserting (fs-based, no requires of vendored code): each committed vendor dir exists with its LICENSE file and its UPSTREAM.md names a pinned tag/commit; flux vendor dir is ABSENT from git (`process.exec("git", {"ls-files", "frameworks/flux/vendor"})` → empty stdout) while FETCH.sh exists and is committed 100755 (`git ls-files -s` shows 100755).

- [ ] **Step 1:** rokit additions + `rokit install`; verify `rojo --version` (7.7.0), `wally --version`.
- [ ] **Step 2:** stylua vendor exclusion. StyLua 2.5.2 supports `stylua.toml` — but the pristine-vendor rule is better served by scoping the CHECK: change `tools/check.sh` line to `stylua --check runner workloads tests tools frameworks/_fixture frameworks/facet frameworks/vide/adapter.luau frameworks/fusion/adapter.luau frameworks/react/adapter.luau frameworks/blend/adapter.luau frameworks/flux/adapter.luau` — explicit non-vendor paths (adapter files may not exist yet; guard with a loop over existing paths). Simpler robust form: `find . -name "*.luau" -not -path "./frameworks/*/vendor/*" -not -path "./artifacts/*" | xargs stylua --check`. Use the find form.
- [ ] **Step 3: Failing spec** (`tests/vendor_integrity.spec.luau`) written first — fails on missing vendor dirs.
- [ ] **Step 4:** Execute the four vendor fetches EXACTLY as above (network required; if a fetch fails, STOP and report BLOCKED with the exact error — do not substitute versions). Write the five UPSTREAM.md files (URL, tag/commit, fetch command, license status, date).
- [ ] **Step 5:** Green: vendor_integrity spec passes; `tools/check.sh` green (stylua skips vendor); suite unchanged otherwise. Commit: "feat: vendor vide 0.4.1, fusion v0.3-beta, react-lua 17.2.1 (wally), blend (quenty npm closure); flux fetch-only (no upstream license)"

---

### Adapter tasks 5–9 — shared contract (read once; applies verbatim to each)

Every rival adapter file `frameworks/<name>/adapter.luau`:
- Module scope: pure Luau. NO `game`, NO `script`, NO vendor requires, NO Roblox APIs. Requires allowed at top: `runner/lune/lib/stable_json` and other pure FacetBench libs only.
- Shape: full Adapter contract (`name`, `version` = the vendored tag/commit, `license` (`"MIT"`, or `"UNLICENSED (fetch-only)"` for flux), `capabilities`, `mount`, `applyStep`, `snapshot`, `liveCount`, `unmount`).
- `capabilities`: `{ reactive = true, keyedList = true, headless = false, styling = true }` for vide/fusion/react/blend; flux: `{ styling = true, headless = false }` (no reactive, no keyedList — flux is a styling utility layer, it CANNOT run the current workloads and must honestly report unsupported).
- `mount(spec, target)`: `assert(target ~= nil and typeof(target) == "Instance", "<name> adapter is live-only: mount requires a Roblox Instance target")` FIRST. `target` is the container the Studio runner provides (a ScreenGui-like Instance whose tree also carries the vendored framework — see Task 10's `vendorRoot` convention: the runner passes a SECOND argument via `target:FindFirstChild("__vendorRoot")`? NO — convention: the Studio runner sets `_G.FacetBenchVendor` before any mount? NO. RULING — the clean convention: `mount(spec, target)` where `target` is a **Folder** with two children created by the Studio runner: `Host` (the ScreenGui to build UI under) and `Vendor` (the mounted vendor tree for THIS framework). The adapter reads both via `target:FindFirstChild(...)` with asserts. `_fixture`/`facet` ignore `target` extras (facet uses `target.Host` when target ~= nil — see Task 10 facet-live step). This keeps every runtime dependency flowing through the one `target` argument — no globals, no path guessing.
- Under Lune the adapter file must LOAD cleanly (registry thunk + conformance shape check + run_one's capability/headless gates run before mount is ever called → `live-only` rows).
- Idiomatic translation of the scene spec (same semantics as facet/_fixture): panels → container frames with the framework's layout idiom (UIListLayout with vertical/horizontal FillDirection), label → TextLabel with bound text, image → ImageLabel, bar → Frame whose Size X scales with value (0..1 → 0..100 px), list → the framework's keyed-list primitive keyed by `item.key`. All reactive bindings through the framework's own reactive primitives (that IS the benchmark).
- `applyStep` mutates the framework's reactive state per step kind (setState/updateItem/addItem/removeItem/reorder/noop) and FLUSHES synchronously before returning (each task names the flush mechanism below).
- `snapshot(handle)`: stable_json over a projection the adapter computes from ITS OWN state model (framework-agnostic: scalar states + per-list array of {key, fields}) — NOT from Instance reads (Instance reads are the Studio conformance check's job, Task 10). Deterministic by construction.
- `liveCount(handle)`: count of live UI Instances the adapter created (walk `handle.root:GetDescendants()` filtered to GuiObjects, or the framework's own accounting); MUST be 0 after unmount (destroy the created tree).
- `unmount(handle)`: the framework's idiomatic teardown (destroy/cleanup scope), then assert the framework's own error channel is clean where one exists.
- Each task writes `frameworks/<name>/NOTES.md`: API facts used (with vendor file:line), the flush mechanism and WHY it's the idiomatic complete-the-work call, binding choices, teardown proof.
- Each task's spec (`tests/<name>_adapter.spec.luau`, registered): under LUNE — registry entry loads; shape validates (`adapterLib.validateShape`); capabilities exact; `conformance.check` returns `"shape-only (not headless)"`; `run_one` on battle_hud S returns `status == "live-only"` (flux: `status == "unsupported"` and note names missing caps); `mount(spec, nil)` errors with the live-only message. NO Studio execution in these specs (Task 11 does live).
- Commit message per task: "feat: <name> adapter (live-only; idiomatic <primitive>)"

### Task 5: Vide adapter

**Files:** Create `frameworks/vide/adapter.luau`, `frameworks/vide/NOTES.md`; Modify `frameworks/registry.luau`, `tests/run.luau`; Test `tests/vide_adapter.spec.luau`.

- [ ] **Step 1 (investigate, NOTES.md):** read `frameworks/vide/vendor/vide/src/` — confirm: `source()` create/read/write signatures; `mount(fn, target)`; `indexes`/`values` signatures and which is keyed-by-value (our stable-key idiom: hold items as an array source and render with `values` keyed by item identity — item tables are stable per key in our model, replaced on updateItem → per-item `source` fields is the finer idiom; DECIDE from vide's docs/source which is idiomatic for keyed collections and record why); how batched updates flush (vide is synchronous fine-grained — confirm `source:set` propagates effects synchronously vs deferred via `batch`; the flush call if any).
- [ ] **Step 2:** failing spec (shared checklist). **Step 3:** implement per shared contract — mount: `local vide = require(target.Vendor.vide.src)` (the Roblox entry; instance require against the mounted vendor tree), `vide.mount(function() return build(spec) end, target.Host)`; state: `vide.source` per scalar + per item field; lists via the primitive chosen in Step 1. **Step 4:** green (Lune suite), NOTES.md complete, commit.

### Task 6: Fusion adapter

**Files:** Create `frameworks/fusion/adapter.luau`, `frameworks/fusion/NOTES.md`; Modify registry + tests/run; Test `tests/fusion_adapter.spec.luau`.

- [ ] **Step 1 (investigate, NOTES.md):** from `frameworks/fusion/vendor/Fusion/src/`: 0.3-beta's scoped API (`Fusion.scoped`, `scope:Value`, `scope:Computed`, `scope:New`, `scope:ForPairs/ForValues/ForKeys`), `peek`, and the update model — 0.3 is "hybrid execution": confirm whether `Value:set` propagates synchronously to bound Instance properties or defers; identify the flush (if deferred, the documented settle call — investigate `External.luau`/`RobloxExternal.luau` scheduling and name the mechanism; if truly deferred-only via RunService step, the adapter's applyStep must force one scheduler step — find the internal `External.performDropoffs`-style entry and record it; calling a vendored internal IS acceptable when it is the only complete-the-work path — document prominently).
- [ ] **Step 2:** failing spec. **Step 3:** implement — mount: `local Fusion = require(target.Vendor.Fusion.src)`; one `scoped` per mount; lists via `ForValues` keyed appropriately (0.3 keys computed objects by value identity — our stable item tables per key work; updateItem replaces the item table → confirm ForValues recomputes just that row); `unmount`: `scope:doCleanup()`; liveCount via Host descendants. **Step 4:** green, NOTES.md, commit.

### Task 7: React-lua adapter

**Files:** Create `frameworks/react/adapter.luau`, `frameworks/react/NOTES.md`; Modify registry + tests/run; Test `tests/react_adapter.spec.luau`.

- [ ] **Step 1 (investigate, NOTES.md):** from `frameworks/react/vendor/Packages/`: wally's link-module layout (`Packages/React.luau` etc. are instance-require links into `_Index`) — confirm the two roots to require from the mounted vendor tree: `target.Vendor.Packages.React` and `target.Vendor.Packages.ReactRoblox`. Confirm `ReactRoblox.createRoot(container)` + `root:render(element)` + `root:unmount()`, and the SYNC path: React 17 legacy/blocking roots vs `ReactRoblox.act` — the flush mechanism for a benchmark step is `ReactRoblox.act(function() root:render(next) end)` or a blocking root; decide from the vendored source which guarantees synchronous commit and record it.
- [ ] **Step 2:** failing spec. **Step 3:** implement — one function component reading a top-level state table held in a `useState`-free external store? NO — idiomatic React: the adapter keeps a root component with `useSyncExternalStore` OR simple prop-driven re-render: `root:render(App(model))` per step with `React.memo` on rows keyed by `item.key` (classic keyed `.map`). Choose the idiomatic form (keys + memo rows; re-render from the top is HOW React apps update) and record why. liveCount via Host descendants; unmount `root:unmount()` then Host clear. **Step 4:** green, NOTES.md, commit.

### Task 8: Blend adapter

**Files:** Create `frameworks/blend/adapter.luau`, `frameworks/blend/NOTES.md`; Modify registry + tests/run; Test `tests/blend_adapter.spec.luau`.

- [ ] **Step 1 (investigate, NOTES.md):** Nevermore loader wiring — from `frameworks/blend/vendor/quenty/@quenty/loader/`: how the loader bootstraps over an Instance tree (`require(loader).bootstrapGame`/`.load` patterns — read the loader source, it's small) and what tree shape the vendored packages need (each package's `src/Shared` etc. mapped as siblings; Task 10's place project builds this shape — this task defines it in NOTES.md as the `Vendor.quenty` mount contract: a Folder per package with the loader able to resolve `require("Blend")`, `require("Rx")`, `require("Maid")`, `require("Brio")`, `require("ObservableList")`... NOTE the closure has valueobject/valuebaseutils — ObservableList lives in one of the vendored packages; find which and record).
- [ ] **Step 2:** failing spec. **Step 3:** implement — mount: resolve `Blend` via the loader from `target.Vendor`; scalars as `Blend.State`; lists as `ObservableList` + `Blend.ComputedPairs`/Brio-based children (whichever the vendored Blend version's keyed idiom is — record); flush: Rx/Blend applies synchronously on `:SetValue`/list mutation (confirm from source; if any Maid-deferred scheduling exists, name the settle). unmount: maid cleanup + Host clear. **Step 4:** green, NOTES.md, commit.

### Task 9: Flux adapter (styling-only, fetch-gated)

**Files:** Create `frameworks/flux/adapter.luau`, `frameworks/flux/NOTES.md`; Modify registry + tests/run; Test `tests/flux_adapter.spec.luau`.

- [ ] **Step 1:** run `frameworks/flux/FETCH.sh` locally (vendor stays untracked); read `vendor/Flux/src/flux/` enough to record in NOTES.md what it actually offers (utility-class styling applied to existing GUI trees) and the honest capability statement: no reactive model, no keyed lists → `capabilities = { styling = true, headless = false }`.
- [ ] **Step 2:** failing spec: registry loads; shape ok; conformance "shape-only"; `run_one` on battle_hud/war_room/killfeed ALL return `status == "unsupported"` with note naming `reactive`/`keyedList`; mount(spec, nil) errors live-only; PLUS: when `frameworks/flux/vendor/Flux` is absent, `mount` errors with a message naming FETCH.sh (test by pcall with a fake Folder target lacking Vendor.Flux).
- [ ] **Step 3:** implement the thin adapter (mount asserts target + Vendor.Flux presence with the FETCH.sh message; builds the static scene as plain Instances and applies flux utility classes — the styling-only demonstration; applyStep only accepts `noop`/`setState` on... NO: capabilities gate means run_one never calls applyStep for unsupported workloads; implement applyStep as `error("flux adapter supports no current workload steps")` and snapshot/liveCount honestly over the static tree). **Step 4:** green, NOTES.md (incl. the licensing statement), commit: "feat: flux adapter (styling-only, fetch-gated, honest unsupported rows)"

---

### Task 10: Studio runner (rojo place, in-place matrix, console-JSON protocol, facet live mode)

**Files:**
- Create: `runner/studio/place.project.json`, `runner/studio/main.luau` (ModuleScript), `runner/studio/protocol.luau`, `runner/studio/DRIVING.md`
- Modify: `frameworks/facet/adapter.luau` (live-target mode), `runner/lune/lib/schema.luau` (studio metrics), `tests/run.luau`
- Test: `tests/studio_protocol.spec.luau`, extension of `tests/facet_adapter.spec.luau`

**Interfaces:**
- Produces: the rojo place project (consumed by Task 11) mapping a mirror of the DISK layout so string requires resolve (probe-verified in Studio for ./ ../ nested):

```json
{
  "name": "FacetBenchStudio",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": { "ui": {
      "Facet":      { "src":  { "$path": "../../../Facet/src" },
                      "tests": { "lib": { "$path": "../../../Facet/tests/lib" } } },
      "FacetBench": {
        "frameworks": { "$path": "../../frameworks" },
        "workloads":  { "$path": "../../workloads" },
        "runner":     { "$path": "../../runner" }
      }
    } }
  }
}
```
  (Paths are relative to `runner/studio/`; vendor dirs ride along inside `frameworks`; `$path` on `runner` brings `run_one_lib` + `lib/` — the `@lune/*`-importing files (proc, matrix_util, run_one, run_matrix, tests) are simply never required from Studio code. VERIFY rojo maps `.luau` files as ModuleScripts and plain dirs as Folders; adjust with explicit `$path` entries per subdir if the flat mapping mis-shapes anything.)
- Produces: `runner/studio/protocol.luau` (PURE — Lune-testable): `protocol.encodeRow(row) -> "FACETBENCH_ROW <stable_json>"`, `protocol.encodeDone(count) -> "FACETBENCH_DONE <n>"`, `protocol.parse(consoleLines: {string}) -> { rows: {any}, done: number? }` (scans marker lines, decodes via... stable_json has no decoder — parse uses a tolerant hand-rolled or the DRIVER decodes; RULING: `parse` extracts the raw JSON strings only; the LUNE-side driver decodes with @lune/serde. So `parse -> { rowJsons: {string}, done: number? }`).
- Produces: `runner/studio/main.luau` — the in-place matrix. API: `main.run(opts) -> ()` where opts = `{ frameworks: {string}?, workloads: {string}?, sizes: {string}?, seed: number?, samples: number?, warmup: number?, mode: "loop" | "frames" }`. Behavior:
  1. Resolves registries via string requires (`require("../../frameworks/registry")` relative to main's mounted position — mirror of disk, so the SAME paths work).
  2. Per (framework, workload, size), builds the `target` Folder contract: `Host` = a fresh ScreenGui parented to `game:GetService("CoreGui")`? NO — parent under `game.StarterGui` is wrong in edit; RULING: parent Host ScreenGui to `game:GetService("RunService"):IsRunning()` and PlayerGui when playing, else to a `Folder` in `workspace`? GUI must be under a PlayerGui/CoreGui to layout. DECISION DEFERRED TO EVIDENCE: Step 3 probes whether AbsoluteSize/UIListLayout resolve for a ScreenGui under StarterGui in edit mode; the runner requires PLAY mode (Task 11 drives play) and parents to `game.Players.LocalPlayer.PlayerGui` — main.run asserts a running client context and errors with a clear message otherwise. `Vendor` = the framework's subtree located from the mounted tree (`script.Parent.Parent.frameworks[name].vendor` instance walk — main.luau MAY use `script` since it is Studio-only).
  3. `mode = "loop"`: calls the SHARED `run_one_lib.run` with injected registries and an injected `mountTarget` — REQUIRES a small run_one_lib change: opts gains `target: any?` passed through to `a.mount(spec, opts.target)` (default nil; Lune callers unaffected). Add that (with a Lune spec assertion that target passes through — extend tests/run_one.spec.luau's recorder adapter to capture it).
  4. `mode = "frames"`: per-frame stepping — one applyStep per `RunService.Heartbeat:Wait()`, `samples` frames, collecting per-frame dt (ms) → metrics `frameP50Ms/frameP95Ms/frameP99Ms` via shared `stats.summarize`, plus `guiObjects` (Host descendant count at end), `memoryMb` (`Stats:GetTotalMemoryUsageMb()` delta start→end). Row shape: same envelope row with `metrics` extended.
  5. Emits `print(protocol.encodeRow(row))` per row and `print(protocol.encodeDone(n))` at end; wraps each combo in pcall → error rows, never a dead run.
  6. Cleans up every Host/instances between combos.
- Produces: `schema.luau` extension — mode "studio" rows allow the additional numeric metrics `frameP50Ms, frameP95Ms, frameP99Ms, guiObjects, memoryMb` (required for status ok when `run.mode == "studio"` and row.meta.mode == "frames"; loop-mode studio rows carry the standard ten). Schema spec gains biting cases both ways.
- Produces: facet adapter live mode — when `target ~= nil`: use `target.Host` as the real render surface. **Investigation step:** find Facet's production Roblox render target (how RascalRally attaches — grep `Facet/src/render/` for the Instance-backed target the renderer.attach expects; likely a `roblox_target`/presenter path; record file:line in NOTES.md) and attach to it instead of `fake_target`. liveCount live mode = Host GuiObject descendants; snapshot unchanged (model projection).
- Produces: `DRIVING.md` — the exact drive sequence Task 11 automates (build, marker probe, play, run, scrape, validate), including the standing stale-serve trap and the commit-marker convention: `runner/studio/main.luau` top comment carries `-- FACETBENCH_MARKER <git short sha>` updated by the driver check, and main.run prints it first so the scraper can refuse stale sources.

- [ ] **Step 1:** failing Lune specs: `tests/studio_protocol.spec.luau` (encode/parse round-trip incl. noise lines between markers, done-line parsing, missing-done → nil); run_one target-passthrough assertion; schema studio-mode biting cases.
- [ ] **Step 2:** implement protocol.luau + schema extension + run_one_lib `opts.target` passthrough; green under Lune.
- [ ] **Step 3:** implement place.project.json + main.luau + facet live mode. Verify what can be verified WITHOUT Studio: `rojo build runner/studio/place.project.json --output artifacts/studio-place.rbxl` succeeds (structure sanity); `lune run tests/run` green (main.luau is never required by Lune tests).
- [ ] **Step 4:** stylua (non-vendor find), commit: "feat: studio runner (mirrored rojo place, shared measurement core, frame mode, console protocol)"

---

### Task 11: Live Studio drive — first cross-framework numbers + microprofiler

This task RUNS Studio via MCP tools (mcp__Roblox_Studio__*; the implementer loads them via ToolSearch). Target: the open blank place ONLY. It is evidence-producing, not code-heavy.

**Files:**
- Create: `tools/studio_scrape.luau` (Lune: takes a console dump file + expected marker sha; extracts protocol rows, decodes, assembles `{run = {mode="studio", ...}, rows}`, schema-validates, writes `artifacts/studio-<stamp>.json`), `docs/studio-runs/2026-08-31-first-live-matrix.md` (the evidence record)
- Test: `tests/studio_scrape.spec.luau` (fixture console dump → envelope; stale-marker dump → loud error)

- [ ] **Step 1:** failing scrape spec → implement scrape → green under Lune. Commit: "feat: studio scrape tool".
- [ ] **Step 2 (live):** `rojo build runner/studio/place.project.json --output artifacts/studio-place.rbxl`. Get the built place into the open Studio: preferred path = MCP `run_as_job`/`execute_luau` cannot open files — so: serve (`rojo serve runner/studio/place.project.json`) and connect the open place's Rojo plugin IF present; if no Rojo plugin, fall back to opening the built .rbxl (`open artifacts/studio-place.rbxl` from bash opens a NEW Studio window — acceptable: the user offered Studio for this; note which path was taken). FIRST READING RULE: before trusting anything, `execute_luau` a read of the FACETBENCH_MARKER comment from the mounted main.luau Source and compare to `git rev-parse --short HEAD` — stale → stop and resync (standing CloudStorage stale-serve trap).
- [ ] **Step 3 (live):** enter Play (`start_stop_play`), then `execute_luau` a client-context bootstrap that requires the mounted `runner/studio/main` and calls `main.run({ sizes = {"S"}, samples = 200, warmup = 20, mode = "loop" })` followed by a second `main.run({ sizes = {"S"}, samples = 300, mode = "frames" })`. Collect console via `get_console_output` into `artifacts/studio-console-<stamp>.txt`. Expect rows for facet + all four mountable rivals (vide/fusion/react/blend) + flux unsupported rows + `_fixture` (explicitly included via opts to validate the runner in-engine once). ANY adapter erroring live → capture the error row, keep going (pcall design), and file the failure in the evidence doc — fixing live adapter bugs is EXPECTED here; loop with the responsible adapter file until the matrix completes, committing fixes with clear messages.
- [ ] **Step 4 (live):** microprofiler evidence: use the Studio MCP microprofiler skill (`mcp__Roblox_Studio__skill` — list/load the microprofiler capability it exposes) to capture a profile during a battle_hud L frames-mode run for facet and for the fastest rival; save dumps under `docs/studio-runs/` (or artifacts + reference). If the MCP skill surface offers no capture, record the manual capture instructions in the evidence doc and note the gap.
- [ ] **Step 5:** `lune run tools/studio_scrape artifacts/studio-console-<stamp>.txt <sha>` → schema-valid `artifacts/studio-<stamp>.json`. Write `docs/studio-runs/2026-08-31-first-live-matrix.md`: the numbers table (per framework × workload, loop + frames), environment (Studio version, device), marker sha, anomalies, microprofiler pointers. Leave Studio stopped (exit Play), place clean.
- [ ] **Step 6:** commit evidence + any adapter fixes: "feat: first live cross-framework matrix (evidence + fixes)"

---

### Task 12: Wrap — hazards audit, docs, hygiene

**Files:**
- Create: `tools/check_bare_loops.luau` (+ register a spec)
- Modify: `CONTRIBUTING.md`, `README.md`

- [ ] **Step 1 (audit):** the Luau loop-shape bimodality (see fixture burn comment): grep-audit every VENDORED tree + adapters for bare accumulate-only hot loops (`for ... do <numeric accumulate only> end` without branch/call in body) — implement `tools/check_bare_loops.luau` as a HEURISTIC lint over non-vendor FacetBench code only (vendor code is reported, never edited): scans `frameworks/*/adapter.luau`, `workloads/`, `runner/`, prints findings; spec proves it bites on a fixture string containing a bare loop and stays quiet on the immune shape. Record the vendor-tree findings (report-only) in CONTRIBUTING's methodology section as named hazards, with file paths.
- [ ] **Step 2 (docs):** README: status → "arena with 6 frameworks + 3 workloads; Lune + Studio modes"; frameworks table (name, version, license, headless?, keyed-list primitive); Flux licensing note (fetch-only, why). CONTRIBUTING: add "Adding a LIVE-ONLY framework" (the rival-adapter rule: pure module scope, target contract Host/Vendor, flush rule), the Studio drive quickstart (point at runner/studio/DRIVING.md), and the bare-loop audit note.
- [ ] **Step 3:** full `tools/check.sh` green; commit: "docs: plan-2 wrap (hazards audit, live-framework guide, frameworks table)"

---

## After this plan

Plan 3: committed baselines (Lune + Studio) with drift gating, chart page, demonstrators D1–D3 red, Facet fixes F1–F3 (in the Facet repo, RR lockstep), public polish + methodology writeup. Spec D2 correction (no forced GC under Lune) lands with Plan 3's authoring.
