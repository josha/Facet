# Research log — `docs/guide/14-choosing-a-ui-library.md`

Workstream E2 of the distribution-readiness stage. Every claim in the chapter
traces to a row below. Fetch date for every external source: **2026-08-30**.

## Pins

| Project | Pinned to | How the pin was taken |
|---|---|---|
| Facet | `Facet.VERSION` `0.10.0` (`src/init.luau:447`), repository commit `bb9944bddef80c32913fcfdca7d1699e021fd988`, recorded in the chapter's source table | `git rev-parse HEAD` and `grep VERSION src/init.luau` on 2026-08-30 |
| React Luau | newest tag `v17.1.3` → commit `7455fb005c68ec63326fcfb6b311da99800980b6` (tag object `fe94f117514847ddcfe02616d849c8a0d4ef256e`, tagged 2024-10-24); newest **published release** `v17.0.1` (2024-01-18); default branch `main` at `9351444c2db37caa08b38ad5de90f438db9221ea` (2026-07-30) | GitHub API: `/repos/Roblox/react-luau/{releases/latest,tags,commits,git/refs/tags/v17.1.3}` |
| Fusion | release `v0.3-beta`, published as "Fusion 0.3" on 2024-08-30; default branch `main` at `2790f7b6272bdf7cd0bbfee259a2f9d79ea20810` (2026-02-02); tags present: `v0.3-beta`, `v0.2-beta`, `v0.1-beta` | GitHub API: `/repos/dphfox/Fusion/{releases/latest,tags,commits}` |
| Vide | release `0.4.1` (2026-07-11) → commit `5ed4c01940e6bd578fb83253cfbeda0a6c05177c`; default branch `main` at `f3bfc65607834370ce84a6e16722282c4d30316c` (2026-08-05); earlier tags `0.4.0`, `0.3.1`, `0.3.0`, `0.2.0` | GitHub API: `/repos/centau/vide/{releases,tags,commits}` |
| Roblox styling | the live documentation page on the fetch date; Roblox does not version this page | direct fetch |

Two pin oddities are stated in the chapter itself: React Luau's newest tag is
ahead of its newest published release, and Vide tags releases without a leading
`v`.

## External sources and what each one established

| # | URL | Established |
|---|---|---|
| 1 | https://github.com/Roblox/react-luau | Repository description: "A comprehensive, but not exhaustive, translation of ReactJS 17.x into Luau. This is a read-only mirror." Default branch `main`. MIT licence. |
| 2 | raw `README.md` of the same repository (`main`) | The three bullet points: declarative, component-based, "Tuned for Roblox". The Bindings sentence quoted in the chapter: "React Luau introduces Bindings, a form of signals-based state that doesn't re-render, for highly-efficient animations driven by React." The `createElement` example that shows host components named by Roblox class string (`e("TextLabel", { … })`). Creator Store and Wally distribution badges. |
| 3 | https://roblox.github.io/roact-alignment/ | The documentation home. Confirms alignment with React 17.0.1, and lists the sections: Deviations, API Reference (React, ReactRoblox, RoactCompat), a migration guide from Roact 1.x, and Benchmarks. |
| 4 | https://roblox.github.io/roact-alignment/api-reference/react/ | The member list used for the "how much it supplies" row: `createElement`, `createRef`, `cloneElement`, `Fragment`, `forwardRef`, `createContext`, `memo`, `lazy`, `Suspense`; hooks `useState`, `useEffect`, `useContext`, `useReducer`, `useCallback`, `useMemo`, `useRef`, `useImperativeHandle`, `useLayoutEffect`, `useBinding`; Roblox-specific `createBinding`, `joinBindings`, `Event`, `Change`, `Tag`, `None`. `joinBindings` "combines a map or array of bindings into a single binding". `useEffect` returns a cleanup function. |
| 5 | https://roblox.github.io/roact-alignment/api-reference/react-roblox/ | `createRoot` is the current way to render into a Roblox instance container; `createBlockingRoot` and `createLegacyRoot` exist for migration; `createPortal` renders outside the parent tree; `act` is for tests. |
| 6 | https://roblox.github.io/roact-alignment/deviations/ | Bindings are "a unidirectional data binding that can be updated outside of the render cycle". Other deviations: no JSX, `useState` returns two values, `React.Component:extend()`, stable keys. |
| 7 | https://github.com/dphfox/Fusion | Repository description "Futuristic Luau for every universe"; default branch `main`; MIT licence; documentation at elttob.uk. |
| 8 | https://elttob.uk/Fusion/0.3/ | The documentation structure (Tutorials, Examples, API Reference) and the one-line descriptions of `Value`, `Computed`, `Observer`, `New`, `Tween`, `Spring`, `doCleanup`. |
| 9 | https://elttob.uk/Fusion/0.3/tutorials/fundamentals/scopes/ | The scope model quoted in the chapter: "Arrays that group together objects like this are given a special name: scopes"; `doCleanup()` destroys "in reverse order"; `scoped()` can re-use old arrays; `deriveScope()`; `innerScope()` cleans up with its parent. |
| 10 | https://elttob.uk/Fusion/0.3/api-reference/ | The complete member list by category, used for the "how much it supplies" row: General (Errors, Contextual, Safe, version), Memory (deriveScope, doCleanup, scoped), Graph (Observer), State (Computed, ForKeys, ForPairs, ForValues, peek, Value), Roblox (Attribute, AttributeChange, AttributeOut, Child, Children, Hydrate, New, OnChange, OnEvent, Out), Animation (Tween, Spring). |
| 11 | https://elttob.uk/Fusion/0.3/api-reference/roblox/members/new/ | "Given a class name, returns a component for constructing instances of that class"; string keys are assigned as properties; a state-object property "is re-assigned every time the value of the state object changes"; `Parent` is assigned after the descendants stage. |
| 12 | https://elttob.uk/Fusion/0.3/api-reference/roblox/members/hydrate/ | `Hydrate` takes an existing instance and returns a component that applies a property table to it, for "binding extra functionality to that instance". |
| 13 | https://github.com/centau/vide | Repository description "A reactive Luau library for creating UI"; README: "Vide is a reactive Luau UI library inspired by Solid"; the `create "TextButton"` counter sample. |
| 14 | https://centau.github.io/vide/ | Documentation home; MIT licence; tutorial plus API reference. |
| 15 | https://centau.github.io/vide/tut/crash-course/1-introduction | Design goals: "Syntax minimal", "Data oriented", "Typechecking compatible", "Instance independent". The honest cost line quoted in the chapter: "Vide's reactivity operates with the concept of scopes which carries a learning curve." |
| 16 | https://centau.github.io/vide/api/reactivity-core.html | `root()` "Runs a function in a new stable scope" and returns a destructor; `source()` is getter and setter in one; `effect()` "Runs a function in a new reactive scope" and reruns on update; `derive()` caches. Reactive scopes cannot nest directly; yielding is prohibited; destroying a parent scope destroys its children. |
| 17 | https://centau.github.io/vide/api/reactivity-dynamic.html | `show`, `switch`, `indexes`, `values`. The quoted line about choosing between the last two: "The main difference is performance, picking the right function to use can result in less property updates and less re-renders." |
| 18 | https://centau.github.io/vide/api/creation.html | `create()`'s property rules, including the one the chapter quotes: a string key whose value is a function and whose property is not an event means "create effect to update property". |
| 19 | https://centau.github.io/vide/api/animation.html | `spring()` "Returns a new source with a value always moving torwards the input source value", with its period and damping-ratio signature. |
| 20 | https://centau.github.io/vide/api/strict-mode.html | Strict mode runs reactive scopes twice to catch impure computations, is recommended for development, and switches off under the optimisation level Roblox compiles production code with. |
| 21 | https://create.roblox.com/docs/ui/styling | The engine's own styling system: a `StyleSheet` holds `StyleRule`s that "apply to every instance that matches the rule's Selector"; a `StyleLink` "links a StyleSheet and its associated rules to a parent ScreenGui and all of the GuiObjects within it. Only one StyleSheet can apply to a given tree"; tokens are defined as attributes of a token stylesheet; themes are "sets of specific tokens that can be swapped"; the Style Editor is part of the token pipeline. |

## Repository sources and what each one established

| File | Established |
|---|---|
| `README.md` (root) | The one-sentence description of Facet; the evidence limits the chapter repeats — headless performance scenes with budgets, a fake render target good for trends only, and empty checked-in device measurement slots. |
| `docs/guide/README.md` | The capability catalog: the nineteen composite controls, the layout primitives, the input/focus/adaptation surface, the render targets, and `Facet.VERSION` `0.10.0`. |
| `docs/guide/01-concepts.md` §1.3 | Signals, memos, observers, effects; transactions batching several writes into one recompute and one observer fire; scopes disposing what they own in reverse order, exactly once. |
| `docs/guide/02-architecture.md` §2.1–2.2 | The module map, including that everything except the client group is engine-free; the data-flow diagram; the dirty queue drained by one `presenter.refresh()` per frame; the minimal-write rule where a paint-only change does not re-run layout; the pure two-pass solver that reads no signal and no instance. |
| `docs/guide/05-styling.md` §5.7 | The native stylesheet path as the default since 2026-08-21; the generated sheet named `FacetStyle`; one `StyleLink` per screen; the Style Editor table showing token edits taking effect immediately and surviving regeneration. |
| `docs/guide/07-input.md` | Semantic actions over Roblox's Input Action System; navigation derived from the mounted layout; the `Workspace.PlayerScriptsUseInputActionSystem` requirement and the fact the property cannot be read or set from code. |
| `docs/guide/12-performance-lab.md` | The five evidence labels and the rule the chapter repeats: an emulator can never close a claim about a device's speed; only the shipped client on named hardware does. |
| `docs/reference/api.md` | `newCore` and its methods; `UI.When` / `UI.ForEach` as the only structural regions, each handing out a scope; the environment fact table (`preferredTextOffset`, `reducedMotion`, `preferredTransparency`, `effectiveTransparency`); the motion clock and its reduced-motion forms; `client.screen_target`, `client.billboard_target`, `client.surface_target`; the explicit statement that the surface target "is not VR, ray, hand, or gaze support". |
| `src/core/custom.luau` (header) | The core is the selected foundation of ADR-0002 and depends only on the contract types — "no engine or Lune APIs". |
| `src/init.luau` | The public surface and `VERSION = "0.10.0"`. |
| `docs/adr/ADR-0002-foundation-core-selection.md` | Decision: `custom`. Also its standing note that Fusion is not a dependency of Facet. |
| `docs/adr/ADR-0017-native-substrate-adoption.md` | The native-substrate rule cited for the adapter edge using engine mechanisms (native `ScrollingFrame`, `Path2D`). |
| `docs/adr/ADR-0018-native-stylesheets.md` | Native stylesheets as the runtime styling source of truth, and the default paint path since 2026-08-21. |
| `docs/adr/ADR-0063-surface-render-target.md` | The world-surface target ships as a thin root swap over `screen_target`; flat two-dimensional Facet on a `SurfaceGui`; the `PlayerGui` + `Adornee` ownership rule. |

## Claims deliberately NOT made

- **No relative speed claim, in either direction.** No matched, fair, checked-in
  benchmark of these four libraries exists in this repository. The chapter says
  so and describes each cost shape instead.
- **No comparison of anything but technical behavior and product fit.** Nothing
  about who works on a project, who employs them, how widely a library is used,
  or how often it publishes.
- **Nothing about Facet building on, vendoring, or depending on another library.**
  The chapter states the opposite in plain words, cites `src/core/custom.luau`
  and ADR-0002, and never describes another library as Facet's foundation.
- **Absence claims are marked `[INFERENCE]`, never `[FACT]`.** Where a library's
  pinned documentation does not describe a feature, the table says "yours to
  write" and marks the cell as an inference. It never says the feature is
  impossible.
- **No claim about the world-surface target beyond a flat two-dimensional
  `SurfaceGui`.** The chapter repeats the reference's own exclusion.

## Checks run

| Check | Result on 2026-08-30 |
|---|---|
| `python3 tools/check_doc_style.py` | PASS — 24 documents, no over-long instruction step, no unexpanded acronym, no internal shorthand. |
| `grep -nE -i 'stars\|popular\|official\|maintainer\|community\|faster\|slower\|built on Fusion'` on the chapter | no matches (exit 1). |
| `tools/check_brand_drift.py` vendor scan of the chapter, unplanted | 0 hits. |
| planted vendor word in the chapter | 0 hits — the new allowlist entry excuses it. |
| the same planted word in `docs/guide/01-concepts.md` | 1 hit — the entry is scoped to one file and does not leak to a sibling chapter. |
| `check_brand_drift.selftest_vendor()` | exit 0 with the new entry in place: a planted vendor word in `src/` and one in `docs/guide` outside a marked block are each still caught, the marked block still excuses its own text, and an over-long and an unclosed block are each still reported. |
| `python3 tools/check_brand_drift.py` (whole run) | FAIL with 5 hits, **all pre-existing and none in a file this workstream owns**: `docs/plans/facet-consolidated-roadmap.md` ×2, `phases.json` ×1, `tools/lune/gate_manifest.luau` ×2. The identical set was reproduced with the new chapter moved out of the tree, so the chapter and the allowlist entry add nothing to it. They belong to the concurrent Step 14 work on the private-comparison archive and the gate manifest. |
