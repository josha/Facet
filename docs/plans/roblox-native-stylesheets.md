# Plan: adopting Roblox native StyleSheets as LuauUI's styling backing store

> **2026-07-22 correction:** Read
> [`roblox-native-audit-corrections.md`](roblox-native-audit-corrections.md) first.
> In particular: `GuiState` is read-only; LuauUI-owned states use tags;
> `StyleQuery` accepts a closed set of built-in conditions rather than arbitrary
> environment keys; `ReducedMotionEnabled` is a built-in query; and preferred text
> size must be tested for double application. The addendum governs on conflict.

- **Status:** Draft / proposal — **Revision 2 (2026-07-21, director rulings).** No
  code changed by this document.
- **Author brief:** investigate whether LuauUI's bespoke styling/token system can
  leverage Roblox's native UI styling (`StyleSheet` / `StyleRule` / `StyleDerive` /
  `StyleLink`, editable in Studio's visual Style Editor) so a user can author a
  stylesheet that **lives in the DataModel**, edit it with the **visual Style
  Editor**, using **human-readable rule/token names**, while LuauUI consumes it —
  additively, never in conflict with native styling.
- **Scope note:** this is a design plan with a phased build-out and verification
  gates. Several load-bearing engine facts are marked as **open questions** with a
  concrete Studio experiment; do not treat the capability matrix as settled until
  those run. A wrong confident claim about native `StyleRule` behaviour would
  poison every phase below, so uncertainty is called out rather than smoothed over.

---

## 0. Revision 2 changelog — what the director's rulings changed and why

Three premises of Revision 1 were challenged. The rewrite below applies these
rulings throughout; this section is the summary of the delta.

**R1 — the boundary is *headless testability*, not engine-agnosticism.** LuauUI is
Roblox-only; portability is not a goal, so R1's original justification for the
paint/layout split ("keep the core engine-agnostic") is **void**. What survives —
and is load-bearing — is that the 595-test Lune suite, the gates, the fuzzer, and
the preview solver all run **without a Roblox process** and must continue to. The
consequence is *narrower and more honest* than "no engine concepts in core": core
and layout may now freely **model** Roblox concepts (StyleSheet token semantics,
`GuiState`, CollectionService tags) — they just may not **depend on a live
DataModel/Instance at test time**. The design invariant therefore reduces to a
single crisp rule: **any value that feeds the headless layout solver must be
resolvable in plain Luau, headlessly** (font sizes, spacing, layout radii, target
sizes, motion durations). Paint values, consumed only at the client edge, carry no
such constraint and may live entirely in the DataModel sheet. §2.6, §5, and §9 are
reframed accordingly; the source-of-truth/sync story for the small set of
layout-affecting tokens is designed explicitly in the new **§6.9**.

**R2 — maximise native leverage; native is *not* restricted to paint.** Revision 1
recommended "native-first for the *paint* layer only." The director: "ideally we
leverage Roblox's systems as much as possible vs inventing our own." So
**everything native styling can express is native-first**: paint, corners/strokes
(Q2 permitting), per-state styling via `GuiState` selectors, theming via
`StyleDerive`, per-platform via `StyleQuery`, **and motion via the new Styling
Transitions beta** (as capability-probed progressive enhancement, never a hard
dependency). Bespoke survives **only** for what native demonstrably cannot do, each
with a stated reason. The "what stays bespoke" list (§6.5) shrinks — most visibly,
**state-driven motion** (hover/press/selection polish, theme cross-fades) moves
from bespoke `TweenService` to native transitions.

**R3 — LuauUI must be *additive* to native styling, never in conflict.** The
director's example: a stylesheet defines a default font size; LuauUI's
accessibility scaling applies *on top of it*. This collides head-on with the
pivotal 2026-07-19 spike truth (§3): an explicit instance-property write **silently
and permanently defeats** a `StyleRule`. So additive layering may **not** be
implemented as explicit writes to styled properties. New **§6.9** specifies the
layering contract — which value classes are sheet-owned base, which are
LuauUI-owned modifiers, and the composition rule per class — and picks the
mechanism. The chosen mechanism reuses the composition seam LuauUI **already**
ships: the type-scale resolver (`env.typographyScale` = base preference × ten-foot
floor, `src/env/environment.luau:52-62`, applied in `applyTextScale`,
`src/render/renderer.luau:352-368`) is exactly "one place where a base value and
LuauUI's modifiers compose," and it already runs headlessly.

Preserved unchanged: the explicit-write-defeats-StyleRule constraint and the
hand-off discipline (`src/render/authority.luau` as the map; delete explicit writes
for handed-off properties); human-readable naming (§6.1); token-mapping direction;
capability-probe + opt-in-flag staging; pixel-parity verification; the migration
story; and the honest open-questions-with-verification-steps format. LuauUI's
reduced-motion support, logical focus ring, and four-input-paradigm interaction
model (ADR-0015/0016) remain **requirements, not negotiable**.

---

## 1. Summary and recommendation

Roblox native styling and LuauUI's current renderer are, today, **mutually
exclusive for any given property**: LuauUI's client adapter paints by writing
instance properties *explicitly*, and a Studio spike this project already ran
proved that an explicitly-set property **silently and permanently defeats a
`StyleRule` for that property** and fires no change signal
(`docs/research/2026-07-19-studio-spikes.md:17-20`). So "leverage native styling"
cannot mean "layer a StyleSheet on top of what we already do" — it means
**handing specific properties off**: LuauUI must *stop* writing the properties it
wants native rules to own, tag/name the instances so native selectors match, and
let a DataModel `StyleSheet` paint them. This same constraint is what makes R3's
"additive" requirement a design problem rather than a one-liner (§6.9).

**Recommendation: a staged, native-*maximal* hybrid.** Everything native styling
can express is expressed natively — paint, corner/stroke geometry (Q2 permitting),
per-state styling, theming, per-platform variants, and state-driven motion — with a
one-way scaffold generator as the Phase 1 on-ramp. The split that remains is **not**
paint-vs-everything; it is **"does this value feed the headless layout solver?"**
Values the solver consumes (spacing, type sizes, layout radii, target sizes, motion
*durations* used for measurement/scheduling) must be resolvable as plain Luau
headlessly (R1) and so stay authoritative in LuauUI's compiled token set — with an
honest source-of-truth/sync story so a designer can still see and edit them in the
Style Editor (§6.9). Everything else — the colour palette, surface fills, corner
radius, hairline stroke, per-state fills, and the transitions that animate state
changes — moves into a DataModel `StyleSheet` that becomes its source of truth,
visually editable, with human-readable token and rule names derived from LuauUI's
own semantic vocabulary. LuauUI's client adapter switches from *painting* those
properties to **classifying** instances (class + app-state tags, one `StyleLink`
per screen), while Roblox supplies read-only native button states.

Two capabilities this unlocks are new to LuauUI: **runtime theming** (light/dark and
beyond) via `StyleDerive` swaps — no runtime path exists today (a game passes
exactly one compiled style at target-creation time,
`src/client/screen_target.luau:49-50`) — and **free state-driven motion**, because
if LuauUI expresses app state as **tag changes instead of property writes** and
uses engine-owned hover/press states, native Styling Transitions animate them with no Luau
tween loop. The single biggest *risk* is that state styling (`:Hover`/`:Press`),
modifier-instance styling (`::UICorner`/`::UIStroke`/`::UIScale`), transition
trigger semantics, StyleSheet GA status, and Rojo authorability are not yet
confirmed against LuauUI's exact instance shapes; those are the Phase 0 gate. The
plan therefore treats transitions as **progressive enhancement** (natural fallback:
instant change, which is exactly today's behaviour) and lands **state-as-tags before
transitions**, so switching the beta on later is zero-rework.

---

## 2. How LuauUI styles today (current system)

### 2.1 The pipeline in one paragraph

A screen is a tree of immutable **blueprints** (data). Styling never appears as a
colour in a blueprint — it appears as **semantic hints**: `surface` on containers
(`"base" | "raised" | "control" | "scrim" | "accent" | "chip" | "badge" | "plain"`)
and `role` on text (`"secondary"`), plus two modifier functions `UI.shadow` and
`UI.corners` that attach *normalized, validated data* to a node
(`docs/guide/05-styling.md:64-77`, `ADR-0006-studio-neutral-default-style.md:6`).
The renderer diffs the tree and, for each style hint, calls
`adapter.setProp(handle, styleProp, hint, "style")`
(`src/render/renderer.luau:332-336`). **All colour resolution happens inside the
one client adapter** — `src/client/screen_target.luau` — which is the only module
in the codebase that touches engine `Instance`s (ADR-0003 seam rule, enforced by
`check_boundary`; header at `src/client/screen_target.luau:1-16`).

### 2.2 Tokens

`src/tokens/tokens.luau` compiles a game's semantic token **schema** into a frozen
Luau table plus a completeness/contrast report (`tokens.compile`, L35). It
*requires* colour pairs (`surface`/`content`, `surfaceStrong`/`contentStrong`,
`accent`/`onAccent`), spacing steps (`xs…xl`), text roles (`body/label/heading/
title`), a minimum target size, and motion durations (L12-18), and it fails the
build if any surface/content pair is below 4.5:1 contrast (L60-78). Notably, the
file's own header records that **StyleSheet generation is deliberately deferred
"while style transitions are beta"** because "LuauUI always has a non-beta path"
(`src/tokens/tokens.luau:1-6`) — this plan is the revisit of that deferral. (Note
the reframing under R2: the deferral rationale — "always a non-beta path" — still
holds for *depending* on transitions, but no longer justifies deferring the whole
StyleSheet effort; transitions become opt-in enhancement over a native base that
ships without them.)

The built-in default, **"Studio Neutral"**, is `src/tokens/default_style.luau`: a
dark surface ramp, one accent, extended non-contract roles (`control`,
`controlHover`, `controlPressed`, `controlSelected`, `contentSecondary`,
`hairline`, focus-ring thickness, pressed scale, ten-foot focus strengthening —
L37-55), radii (`control/panel/pill`, L58), engine-true `UIShadow` presets
(L62-83), strokes, target sizes, motion (L84-86).

### 2.3 Resolution at the edge — the explicit-write model

`screen_target.new` reads the style once and builds a `COLOR` table of `Color3`s
(`src/client/screen_target.luau:72-85`). Resolution is a set of imperative
functions:

- `applySurface` maps each surface hint to background colour + corner + hairline
  (L199-282) — e.g. `"raised"` → `surfaceStrong` fill, panel radius, hairline;
  `"control"` → `control` fill, control radius; `"scrim"` → dimmed backdrop that
  *strips* chrome and suppresses states.
- `wireInteractiveStates` wires rest/hover/pressed **fills** as `TweenService`
  tweens plus a `UIScale` pressed-dip (L286-366), reduced-motion-aware, and — key
  detail — the **hover** fill is only wired when the pointer class is actually
  live (`adapter.enableHover`, L838-849; a pure-touch device allocates no hover).
  *Under R2 this is the biggest candidate to move to native `:Hover`/`:Press` +
  transitions (§6.3, §6.10).*
- `setFocusVisual` draws the focus ring as a `UIStroke` driven by LuauUI's
  *logical* focus graph (not engine `GuiState`), and on a ten-foot display adds a
  bounds-checked `UIScale` lift (L856-939, thickness/scale at L871,910,927).
- `applyShadow` / `applyCorners` materialize `UIShadow` / `UICorner` **behind
  capability detection** (probe at L100-114) — on an engine that lacks them the
  declaration stays harmless data (`docs/guide/05-styling.md:160-168`).

### 2.4 The property-authority manifest — the exact hand-off list

`src/render/authority.luau` declares **exactly one authority per engine property
per class** (L14-63): `layout` (rects, `textSize`, padding, zIndex), `style`
(`surface`, `role`, `backgroundColor`, `cornerRadius`, `shadow`, `corners`,
`strokeColor`, `font`, `textColor`), `binding` (data: `text`, `value`, `enabled`,
`selected`, `active`, `image`, TextField props), and `presentation` (transient
transform/opacity). `authority.assertWrite` errors if any writer touches a
property it does not own (L76-84). The header explains *why* this manifest exists:
the Studio spike proved the engine will not police conflicts, "an explicit write
silently defeats StyleRules and fires no signals" (L2-7). **This manifest is
already, almost exactly, the map of what could be handed to native styling** — the
`style`-authority rows are the candidate hand-off set; the `layout` and `binding`
rows are what must stay bespoke. Note `textSize` is `layout`, not `style`
(L36,47) — deliberately, because it feeds the solver (§2.6, R1).

### 2.5 Theming today

There is **no runtime light/dark switch.** A game supplies one compiled style at
target creation (`screen_target.new({ style })`, `src/client/screen_target.luau:49-50`);
Studio Neutral is the default. "Themes" only vary by *environment-derived*
strengthening (ten-foot text floor 1.5×, thicker focus ring, overscan insets —
`src/env/environment.luau:34,60,96,118`), which is layout/geometry, not a colour
theme. Runtime colour re-theming would be entirely new.

### 2.6 The headless-testability boundary (must be respected) — reframed under R1

Revision 1 called this "the engine-agnostic boundary." **R1 renames and narrows
it.** LuauUI is Roblox-only; the invariant is not portability but that the whole
pipeline runs **headlessly** under Lune with **no Roblox process**: the headless
render target `tests/lib/fake_target.luau` implements the same
`RenderTargetAdapter` contract (`src/render/target_contract.luau`) so the 595-test
library suite, the 2000+ game tests, the gates, the fuzzer, and the preview solver
all run without an engine. Confirmed by grep, `src/core`, `src/render`, `src/present`,
`src/layout`, and `src/env` contain **zero** `game:GetService` or `Instance.new`
calls; only `src/client/*` adapters (`screen_target`, `edit_preview`,
`billboard_target`) touch Instances.

The reframing changes what is *allowed*, not what is *required*:

- **Still forbidden:** a live DataModel `StyleSheet` (or any `Instance`) as a
  dependency of anything the headless suite touches. Make it one, and the suite
  goes dark.
- **Now explicitly allowed (new under R1):** core/layout may *model* Roblox
  concepts — the token schema may mirror StyleSheet token names, the solver may
  reason about `GuiState`/tags, a Luau value object may represent a rule. Modelling
  is not depending. This is what lets the layout-affecting tokens have a clean
  Luau home that a Rojo-authored sheet or an exported snapshot can mirror (§6.9)
  without pretending the framework is engine-neutral.

The hard consequence, unchanged in force: **any value the headless solver consumes
must be resolvable in plain Luau at test time.** That is the sole reason spacing /
type sizes / layout radii / target sizes / measurement-time motion durations stay
Luau-authoritative — not portability. Paint values carry no such constraint.

---

## 3. The pivotal constraint (read before the options)

> An explicitly-set instance property **silently and permanently defeats** a
> `StyleRule` for that property, and style application fires **no**
> `GetPropertyChangedSignal` and does not change property reads.
> — `docs/research/2026-07-19-studio-spikes.md:17-20` (Studio Play-Solo spike,
> machine evidence in `artifacts/studio/property-authority-spike.json`)

Consequences that constrain everything below:

1. **A property is either bespoke-explicit OR native-ruled — never both.** You
   cannot "mostly" style a `BackgroundColor3` with a rule and occasionally poke
   it; the poke wins forever and silently. So adopting native styling for a
   property means *deleting* the explicit write for it in `screen_target`.
2. **Layout must never be handed to native.** LuauUI's solver owns `Size`,
   `Position`, and `TextSize` (the ten-foot 1.5× floor is a *layout* concern,
   `src/render/renderer.luau:352-368`). A `StyleRule` that set any of these would
   fight the solver invisibly. The style/layout split in the authority manifest is
   exactly what keeps native styling out of layout.
3. **No change signal means LuauUI cannot observe native-applied values.** Any
   value LuauUI needs to *read back* for its own logic (e.g. a resolved colour fed
   into a `Lerp`) cannot be sourced from a rule; it must come from a token LuauUI
   also holds.
4. **R3's "additive" therefore cannot be an explicit write.** LuauUI's
   accessibility scaling, ten-foot lift, density cap, and reduced-motion adjustments
   must layer over the sheet **without** poking a styled property — or they defeat
   the very rule they mean to modify. §6.9 is the design that honours this.

---

## 4. Native styling capability matrix

Sources: the styling landing page (`https://create.roblox.com/docs/ui/styling`),
the CSS-comparison page (`https://create.roblox.com/docs/ui/styling/css-comparisons`),
the Style Editor page (`https://create.roblox.com/docs/ui/styling/editor`, incl. the
[Style Transitions](https://create.roblox.com/docs/ui/styling/editor#style-transitions)
section), the [Styling Transitions studio-beta
thread](https://devforum.roblox.com/t/studio-beta-styling-transitions/4646870), and the
engine class references for
[StyleSheet](https://create.roblox.com/docs/reference/engine/classes/StyleSheet),
[StyleRule](https://create.roblox.com/docs/reference/engine/classes/StyleRule),
[StyleDerive](https://create.roblox.com/docs/reference/engine/classes/StyleDerive),
[StyleLink](https://create.roblox.com/docs/reference/engine/classes/StyleLink),
[StyleQuery](https://create.roblox.com/docs/reference/engine/classes/StyleQuery).

### 4.1 Confirmed from docs

| Capability | What the docs say | LuauUI relevance |
|---|---|---|
| **Instances** | `StyleSheet` holds `StyleRule`s (`GetStyleRules`, `InsertStyleRule(rule, priority?)`, `SetStyleRules`; `StyleRulesChanged`) and can `SetDerives`/`GetDerives` other sheets. `StyleLink.StyleSheet` applies one sheet to a tree; **"Only one StyleSheet can apply to a given tree."** | A single `StyleLink` under each LuauUI `ScreenGui` is the application point. |
| **Class selectors** | `rule.Selector = "Frame"` / `"TextButton"` targets by class. | Matches LuauUI's `CLASS_TO_INSTANCE` map (`Frame`/`TextButton`/`TextLabel`/`ImageLabel`/`TextBox`, `screen_target.luau:26-33`). |
| **Name selectors** | `#InstanceName` (CSS ID analogue). | LuauUI already names every instance by its **path** (`instance.Name = path`, `screen_target.luau:474`) — usable but paths are unstable/verbose; class+tag is better. |
| **Tag selectors** | CollectionService tags, CSS-class analogue. | The clean carrier for LuauUI **surface roles and app-state pseudo-states** (e.g. tag `luau-surface-raised`, `luau-selected`), and — crucially under R2 — the **trigger for state-driven transitions** (§6.10). |
| **State selectors** | `:Hover`, `:Press` — one of four `Enum.GuiState` values ("similar to CSS pseudo-classes"). | Candidate replacement for `wireInteractiveStates` hover/press *fills*, with free transitions — **but see Q1/Q2**. |
| **Modifier / pseudo-instance selectors** | `::UICorner`, `::UIStroke` ("pseudo-elements → pseudo-instances"). | Could let a rule own corner radius and hairline stroke. Whether a rule *creates* a missing modifier or only styles an existing one is **open Q2**. |
| **Combinators / lists / nesting** | child `>`, descendant `>>` (not whitespace), comma lists, SCSS-style nesting with selector merging. | Enables e.g. "text inside a raised surface" rules. |
| **Tokens** | Custom **attributes** on a StyleSheet, referenced `"$TokenName"` in `SetProperties`. Editor: "Add a Token…", "Link Token". Runtime mutation of a token attribute updates every rule referencing it. | Direct home for LuauUI's paint palette; **runtime token mutation is additive-mechanism candidate (a) in §6.9**, and may (unconfirmed, Q9) trigger transitions. |
| **Derives / inheritance** | `SetDerives` chains sheets; higher `StyleDerive.Priority` wins on conflicting tokens/rules. Editor exposes **themes as radio buttons** = derive swaps. | **The runtime theming mechanism** LuauUI lacks, **and** additive-mechanism candidate (b) in §6.9. A `SetDerives` swap **is documented to trigger transitions** (editor page) → animated theme cross-fade, if confirmed (Q10). |
| **Transitions** | Per-rule default and per-property transitions using `TweenInfo` and reusable transition tokens. They run for styling-system changes, not ordinary layout/property writes. **Currently Studio beta** — do not require them in a published experience. | **Progressive enhancement.** App state uses tags; hover/press use engine-owned state. Fallback is instant state change. Prefer a `ReducedMotionEnabled` query for the no-motion variant. |
| **Queries** | `@`-prefixed selectors + `::StyleQuery`, with a closed set of built-in conditions including preferred input, display size, size/aspect ranges, and reduced motion. Unknown custom names fail. | Use for engine-native facts only. LuauUI's filtered paradigm and pointer-live policy use tags. |
| **Selector validation** | `StyleRule.SelectorError` (read-only) reports malformed selectors; `StyleRule.Priority` orders rules. | LuauUI's generator/loader can assert `SelectorError == ""` at apply time. |
| **Style Editor** | Visually creates tokens, sheets, rules, themes, state rules (`New ▸ GuiState ▸ Hover`), queries, transitions (`Insert ▸ Transition`, default 1s/Quad/Out/0-delay), and token links; manages `StyleDerive` automatically; **warns you not to modify/delete the base style sheet**. | Satisfies the user's "visually editable, human-readable names" requirement directly. |

### 4.2 Open questions (NOT confirmed — each has a verification step)

The docs are explicitly silent on several mechanics the CSS-comparison page itself
flags as "not addressed": **properties that cannot be styled, specificity/cascade
resolution, whether explicit instance properties override rules (LuauUI's own spike
answered this — they do), and inheritance behaviour.** The transition docs also
carry an internal **conflict worth resolving early**: the Style Editor page lists
"explicit property writes" among transition triggers, while the studio-beta thread
states transitions fire *only* for styling-system changes and explicitly *not* for
non-styling changes — this plan treats the devforum wording as authoritative
(styling-system changes only) pending Q9. See §10 for the full list; the
load-bearing ones are Q1–Q5 (unchanged) plus the new transition/additive questions
Q9–Q12.

---

## 5. Architecture options

### (a) Full replacement — LuauUI styling API becomes a thin authoring layer over native

The public `UI.*` styling surface (`surface`, `role`, `UI.shadow`, `UI.corners`,
`tokens.compile`) becomes sugar that ultimately emits StyleSheet instances; the
adapter stops resolving colours entirely.

- **Pros:** one styling model; maximal visual-editor leverage; smallest long-term
  surface area — attractive under R2's "leverage native as much as possible."
- **Cons — disqualifying as stated:** it breaks **headless testability** (§2.6,
  R1). The headless solver *needs* spacing/type/radius/target-size/motion-duration
  values as plain Luau at test time; those cannot come from a DataModel sheet. It
  also throws away the working, spike-hardened explicit-write path for things native
  cannot express (logical focus ring, ten-foot lift, choreographed/value-driven
  animation, reduced-motion, pointer-gated hover). **Rejected as a whole;
  salvageable only for the sub-layer native can express, which is what (c) does —
  now maximally.**

### (b) Compile / one-way bridge — bespoke stays source of truth, emit a StyleSheet

`tokens.compile` output is transformed into a `StyleSheet` model (tokens →
attributes, surface roles → rules) written into the DataModel. One-way: edits in
the Style Editor do **not** flow back.

- **Pros:** low risk; the bespoke system and all its tests are untouched; produces
  a *human-readable starter sheet* a designer can inspect; a natural first
  increment.
- **Cons:** fails the user's actual requirement — they want to **edit in the
  Studio tool and have LuauUI consume it**, i.e. round-trip. A generated sheet the
  engine ignores at runtime (because the adapter still explicit-writes, §3) is
  documentation, not styling. Editor edits get clobbered on regeneration.
- **Verdict:** **valuable as a scaffold, not an end state.** Adopt it as the Phase 1
  generator that *seeds* a human-readable sheet with stable names — meaningful once
  the adapter (option (c)) actually reads that sheet.

### (c) Native-*maximal* hybrid — the DataModel StyleSheet owns everything native can express (paint, corners/strokes, state, theming, queries, transitions); LuauUI keeps only what feeds the headless solver, plus what native provably cannot do

Split by **"does the value feed the headless layout solver?"** (not "paint vs
everything" — that was Revision 1's narrower cut, loosened by R2):

- **Layout-affecting tokens** (spacing, type sizes, layout radii, target sizes,
  motion *durations used for measurement/scheduling*) — consumed *headlessly* by the
  solver → **stay** Luau-authoritative (R1), with an honest sheet-mirroring /
  source-of-truth story so a designer still sees and edits them (§6.9).
- **Everything native can express** — the colour palette, surface fills, corner
  radius, hairline stroke, per-state fills, per-platform variants, theme derives,
  and **the transitions that animate state changes** — consumed *only at the edge*
  → **move** into the DataModel `StyleSheet` as their source of truth.
- The client adapter stops explicit-writing handed-off properties; instead it
  **classifies** each node (class + tags) and parents one `StyleLink`
  per `ScreenGui`. Roblox supplies read-only native `GuiState` values for hover,
  press, and non-interactable rules; LuauUI adds/removes tags for app-owned states.
  Those styling changes let native rules paint and, when available, animate them.
  Everything native still can't express stays bespoke and
  explicit (§6.5, now shorter).

- **Pros:** satisfies the requirement exactly (sheet in DataModel, visually
  editable, human-readable names); maximises native leverage per R2 (paint + state +
  corners/strokes + theming + queries + motion); unlocks runtime theming; gets
  state-driven motion for free once the beta ships; respects headless testability
  (only the client adapter changes; headless keeps its Luau tokens); reuses the
  authority manifest as the hand-off map; degrades to today's explicit-write path
  when the sheet/engine capability is absent, and to *instant* state change when
  transitions are absent.
- **Cons:** two token homes (layout-affecting in Luau, everything else in the
  sheet) — a real cognitive cost and a sync surface to police (§6.9); depends on the
  open questions (state selectors, modifier styling, transition triggers, GA
  status, Rojo authorability); the adapter grows a second rendering mode to maintain
  until the old one is retired.
- **Verdict: recommended**, staged, with (b) as its Phase 1 scaffold.

### Decision

**Adopt (c), native-maximal, staged, seeded by (b).** Rationale: it is the only
option that meets the literal requirement (editable-in-DataModel, round-trip,
human-readable), maximises native leverage per R2, *and* preserves the one invariant
that keeps LuauUI testable — the headless core. The two-token-home cost is real but
bounded and honest: it is the direct consequence of the layout solver being
headless, which is a feature, not an accident.

---

## 6. Integration design

### 6.1 Naming conventions (human-readable, the user's explicit ask)

Names derive mechanically from LuauUI's existing semantic vocabulary so a designer
opening the Style Editor sees words they already know from the API docs:

- **Tokens** (StyleSheet attributes) mirror the schema keys: `Surface`,
  `SurfaceStrong`, `Content`, `ContentStrong`, `Accent`, `OnAccent`, `Control`,
  `ControlHover`, `ControlPressed`, `ControlSelected`, `ContentSecondary`,
  `Hairline`. These are exactly the `default_style` colour + `extra` role names
  (`src/tokens/default_style.luau:27-46`), PascalCased.
- **Classes / tags** name the surface role: tag `luau-surface-raised`,
  `luau-surface-control`, `luau-surface-scrim`, `luau-surface-accent`, … (one per
  `applySurface` branch, `screen_target.luau:199-282`), plus state tags
  `luau-selected`, `luau-focused` for app-state pseudo-states native can't infer.
- **Rules** get readable Names in the sheet: `Raised panel`, `Control fill`,
  `Control — hover`, `Control — pressed`, `Scrim backdrop`, `Primary button`,
  `Selected row`. The Style Editor shows these Names, satisfying "human-readable
  rule names."
- **Transition tokens** (§6.10) mirror the motion tokens: `$MotionFast`,
  `$MotionNormal` linked to `TweenInfo(0.12,…)` / `TweenInfo(0.2,…)` so a designer
  edits durations in one place, exactly as `default_style.motion` does today
  (`default_style.luau:86`).

### 6.2 Token mapping (semantic tokens → StyleSheet tokens/attributes)

| LuauUI token | Home under (c) | Native carrier |
|---|---|---|
| `colors.*`, `extra.control*`, `extra.hairline`, `extra.contentSecondary` | **Sheet** (source of truth) | StyleSheet attributes `$Surface`, `$Accent`, `$Control`, … |
| `radii.control` / `.panel` (as *paint*) | **Sheet** | rule `CornerRadius = UDim.new(0, …)` via `::UICorner` (pending Q2) |
| `strokes.hairline` colour + `extra.hairline` | **Sheet** | rule via `::UIStroke` (pending Q2) |
| `shadows.*` presets | **Luau** until Q8 confirms | `UIShadow` stays adapter-materialized behind capability detection (`screen_target.luau:144-185`) unless `::UIShadow` rules prove reliable |
| `motion.fast/.normal` (as *transition durations*) | **Sheet** (as transition tokens) **and** Luau (for bespoke choreography) | `$MotionFast`/`$MotionNormal` transition tokens (§6.10); the Luau copy still drives non-state animation |
| `space.*`, `type.*`, `targetSizes.*`, radii *as consumed by the solver* | **Luau** (source of truth, R1) | mirrored into sheet as editor-visible reference tokens `$SpaceM`, `$TypeBody` via the §6.9 sync path |

The contrast/completeness gate (`tokens.compile`, `tokens.luau:60-78`) stays the
authority: a sheet's paint tokens are validated by round-tripping them back through
`contrastRatio` at generation/load, so "a game's style is not allowed to ship
unreadable text" (`05-styling.md:26`) survives the move to the DataModel — and every
*theme's* tokens are gated the same way (§6.7).

### 6.3 Per-state styling (hover / pressed / focus / selected)

- **Hover, Pressed** → native `:Hover` / `:Press` state rules **if Q1 confirms**
  they fire for `AutoButtonColor=false` buttons. Under R2 this is the *preferred*
  path even before transitions ship, because expressing state as `GuiState` (native)
  or a tag flip (§6.10) is what makes state motion free later. Caveat: LuauUI gates
  hover to live pointers (`enableHover`, `screen_target.luau:838-849`); native
  `:Hover` has no paradigm gate, so on a touch device native hover could flash on
  tap. Use a native `PreferredInput` query only if its raw engine semantics are good
  enough for the visual. Otherwise have LuauUI add/remove a pointer-live tag from its
  filtered interaction-class fact. Do not invent a custom StyleQuery condition.
  If the native-state path cannot preserve touch behavior, hover/press stay bespoke.
- **Focus** → **stays bespoke.** LuauUI's focus ring follows its *logical* focus
  graph, not engine `GuiState` focus (`setFocusVisual`, driven by
  `controller.setFocusPath`, `renderer.luau:516`), and the ten-foot lift is a
  computed bounds-fit decision (`screen_target.luau:883-927`). Native has no concept
  of either. The focus ring `UIStroke` and lift `UIScale` remain explicit writes.
  *Why native can't:* native `GuiState` focus is a single-object engine concept;
  LuauUI's is a four-paradigm logical graph (ADR-0015/0016) that native cannot
  represent.
- **Selected** → **tag-driven native rule.** `selected` is a data binding
  (`authority.luau` binding authority; `screen_target.luau:1050-1058`). The adapter
  adds/removes CollectionService tag `luau-selected`, and a native rule
  `.luau-selected { BackgroundColor3 = $ControlSelected }` paints it — **and the tag
  flip triggers the selection transition for free** (§6.10). This keeps the colour
  in the editable sheet while the *state* stays app-driven.

### 6.4 Per-platform / per-paradigm variation

Two mechanisms compose:

1. **Environment strengthening (stays LuauUI/layout):** ten-foot text floor,
   overscan insets, focus thickening are *layout/geometry* computed from
   `env.displaySize` / `distanceProfile` (`environment.luau:34,60,96,118`) and
   remain in the solver — native queries cannot compute a bounds-fit lift. *Why
   native can't:* these are measurement/geometry decisions the headless solver owns.
2. **Paint variants (native):** use only the documented built-in StyleQuery
   conditions for engine facts such as display size, preferred input, size/aspect
   ranges, and reduced motion. Express LuauUI's filtered paradigm and pointer-live
   decisions with tags. `SetCondition("preferredInput", …)` is invalid and must not
   be implemented.

### 6.5 What stays bespoke (native demonstrably cannot express) — re-derived under R2

Under R2 this list **shrinks** versus Revision 1 (which kept *all* motion and hedged
state fills bespoke). Each survivor now carries a "why native can't":

1. **All layout** — rects, `TextSize` incl. the ten-foot 1.5× floor, padding,
   clip-host geometry (`renderer.luau:352-368`, `screen_target.luau:459-470`). *Why
   native can't:* native styling cannot solve layout or measure text; a rule setting
   `Size`/`Position`/`TextSize` would fight the solver invisibly (§3.2).
2. **All data-driven values** — `text`, toggle `value`, `enabled`, `active`,
   `image`, TextField props (binding authority, `authority.luau:36-62`). *Why native
   can't:* these are application data, not style; no selector expresses them.
3. **Logical focus ring + ten-foot lift** — env + geometry computed
   (`screen_target.luau:856-939`). *Why native can't:* see §6.3 (four-paradigm
   logical focus, bounds-fit lift).
4. **Choreographed / timeline / spring / value-driven motion** — countdown
   sequences, celebration beats, drag-release springs, and gauges that animate a
   *value* rather than a *state* (see `sponsor-view-parity.md` B1). *Why native
   can't:* native transitions fire **only on a styling-system state change** (tag /
   `GuiState`), have no timeline/phase/spring model, and no value-driven mode
   (devforum confirms no spring physics / `SmoothDamp`). State-*driven* motion,
   however, **moves to native** (§6.10) — this is the shrink.
5. **Reduced-motion enforcement** — prefer the built-in
   `ReducedMotionEnabled` StyleQuery for native transitions. Keep a tested
   strip/clear fallback only if the beta cannot express the required rule variant;
   choreographed motion keeps its separate LuauUI policy.
6. **Pointer-liveness hover gate** — bespoke condition even if the fill is native
   (§6.3). *Why native can't:* native `PreferredInput` is not LuauUI's filtered
   interaction class; the framework can express this decision with a tag.
7. **The Toggle knob-track assembly** — a bespoke child hierarchy with animated
   knob position (`buildToggleVisual`, `screen_target.luau:373-409`). *Why native
   can't:* native rules can paint its colours but cannot *build* the hierarchy or
   animate a *position* (a value, not a state) — though the two knob *end-states*
   could become `GuiState`-free tag states with a transition, a candidate refinement
   deferred past Phase 3.
8. **Capability fallbacks** — `UIShadow` / per-corner radii degradation
   (`screen_target.luau:100-114,144-185`). *Why native can't:* these exist precisely
   for engines/contexts where the native feature is absent.

Moved **out** of this list versus Revision 1: hover/press *fills* (→ native
`:Hover`/`:Press`, §6.3), selection *fill* (→ tag rule, §6.3), and all
**state-driven** motion (→ native transitions, §6.10).

### 6.6 Interaction with the reactive system

LuauUI styles that depend on app state stay in LuauUI's reactive path: the blueprint
carries a hint or a binding, the renderer diffs it, and the adapter either
  explicit-writes (bespoke path) or **toggles a tag** (native path) — native
  `GuiState` is read-only and engine-owned. The tag flip is the reactive → native
  bridge and a transition trigger. Native
tokens themselves are *static* per theme; anything genuinely value-dynamic
(interpolated, per-frame, gauge-like) stays a LuauUI presentation/binding write. Rule
of thumb: **native owns the palette, static paint, and state→state motion; LuauUI
owns layout, data, and anything that animates a *value*.**

### 6.7 Theming (light/dark)

New capability. Ship the base sheet + a `StyleDerive` per theme (dark = base Studio
Neutral; a light theme as a second derive). A runtime theme switch is
`StyleSheet:SetDerives({ activeTheme })` (or the editor's theme radio buttons at
author time) — no remount, the `StyleLink` propagates. **If Q10 confirms `SetDerives`
triggers transitions, a theme swap cross-fades for free.** This is strictly additive
over today's single-style-at-creation model (`screen_target.luau:49-50`) and a
headline reason to pursue (c). Contrast-gate **every** theme's paint tokens through
`tokens.compile`'s `contrastRatio` before it can be selected.

### 6.8 Preview / hot-reload

`src/client/edit_preview.luau` already runs the real pipeline into a ScreenGui
during Studio Edit and live-updates on Heartbeat (L98-113). Because the Style Editor
edits the DataModel sheet directly and `StyleLink` repaints live, native paint edits
would preview **without** LuauUI's refresh loop at all — a genuine ergonomic win.
LuauUI's preview harness keeps driving layout/state; the sheet drives paint. Confirm
the two do not double-apply (Q2/Q4 interplay), and that runtime token mutation for
additive scaling (§6.9) does not fight the editor's live view of the sheet (Q11).

### 6.9 The additive-layering contract (R3) — how LuauUI modifiers compose over sheet-owned base

R3 requires LuauUI to layer *on top of* native styling without ever writing a styled
property (which would defeat the rule, §3.4). This section defines **which value
classes are sheet-owned base, which are LuauUI-owned modifiers, the composition rule
per class, and the single mechanism** — chosen so the headless solver computes the
*same* effective value the edge paints.

**The key realisation: LuauUI already ships the shared resolver.** The type-scale
memo composes a base and a modifier in one headless place:

```
-- src/env/environment.luau:52-62
authoredTextScale = displaySize == "Large" ? 1.5 : 1
preferredTextReserve = injected engine preference used by headless measurement
-- applied at the paint+measure seam, src/render/renderer.luau:352-368 (applyTextScale)
```

This is *exactly* the "one place where base-from-sheet and LuauUI-modifiers compose,"
and it already runs under Lune. The additive design generalises it rather than
inventing a new seam.

**Layering contract — value classes, ownership, composition rule:**

| Value class | Base owner | LuauUI modifier(s) | Composition rule | Where they compose (shared resolver) |
|---|---|---|---|---|
| **Type size** | Sheet-authored base font size, mirrored to Luau (R1) | authored/ten-foot scale; engine-owned preferred text rendering | **measure once, paint once** | A Phase 0 matrix must split engine preference from LuauUI-authored scale and prove no double application |
| **Geometric size** (whole-UI lift) | native/instrinsic | ten-foot focus lift, density | **multiply via `UIScale`** | LuauUI-owned `UIScale` (option (c) below); solver accounts for it |
| **Spacing / density** | Sheet-mirrored Luau tokens | density cap | **multiply or offset** in solver | layout solver (headless) |
| **Paint (colour/fill/stroke)** | **Sheet** (source of truth) | accessibility contrast/dim overlays | **override** via generated derive | native `StyleDerive` swap (option (b)) |
| **Motion** | Sheet transition tokens | reduced-motion | **strip / gate** | LuauUI strip-transitions mode (§6.10, Q12) |
| **Focus strengthening** | Luau `extra.*` | ten-foot thickness/scale | **override/additive** | `setFocusVisual` (bespoke, §6.3) |

**Chosen mechanism, by value class** (the four candidates R3 named, applied where
each fits — not one mechanism for everything, because the value classes genuinely
differ):

- **Type & layout-affecting values → one measured and painted result.** Roblox may
  already apply `PreferredTextSize`; LuauUI must not multiply that preference into
  `TextSize` a second time. Phase 0 therefore measures the live engine across all
  preference values and splits the current `typographyScale` into an authored scale
  (including ten-foot treatment) and a headless preferred-text reserve if the
  evidence confirms double application. The base font size remains available to the
  solver through the synchronization workflow below.
- **Paint accessibility overlays (high-contrast, dim) → generated `StyleDerive`
  overlay, candidate (b).** LuauUI generates/maintains a small derive (e.g. "A11y
  High Contrast") overriding paint tokens, swapped via `SetDerives`. Trade-off: this
  is **discrete steps**, not a continuous scale — acceptable for contrast/dim, which
  are stepped preferences anyway, and it may **cross-fade for free** if Q10 holds. For
  a genuinely *continuous* paint adjustment, fall back to runtime token mutation
  (candidate (a)) — flagged with its two open risks: does it trigger transitions
  (Q9), and does it fight the editor's live view of the sheet (Q11).
- **Whole-UI geometric scaling → `UIScale`, candidate (c).** LuauUI already uses a
  `UIScale` for the ten-foot lift (`screen_target.luau:883-927`); density and any
  future global geometric scale ride the same instance. Scales *everything*, so the
  solver must account for it — which it already does for the lift's bounds-fit check.

**Rejected as the primary type mechanism:** candidate (d) class/tag swap (a
different class carrying pre-scaled values) — it cannot express a *continuous*
accessibility scale (0.5–3×) without an explosion of discrete classes, and the scaled
value must reach the *headless solver*, which a native rule cannot feed (§3.3).
Candidate (a) runtime token mutation is likewise rejected for type/layout because the
solver cannot read a DataModel token headlessly.

**The source-of-truth / sync problem (the honest part of R1).** Only the small set of
**layout-affecting** tokens (type sizes, spacing, layout radii, target sizes,
measurement-time motion durations) has a real problem: the requirement says the sheet
lives in the DataModel and is Style-Editor-editable, yet the headless suite must read
the *same* base values in plain Luau. Paint tokens have no such problem — headless
never reads them. Resolution, tied to the Rojo-authorability open question (Q5), in
priority order:

1. **Preferred — Rojo-authored shared file (if Q5 confirms `StyleSheet` is
   Rojo-authorable).** The layout-affecting tokens are authored once in the Rojo tree;
   both the DataModel `StyleSheet` and the headless resolver read that single file.
   One source, no staleness, editor round-trips paint freely.
2. **Fallback A — exported snapshot + staleness gate (if not Rojo-authorable).** The
   DataModel sheet is authoritative; an export step serialises the layout-affecting
   tokens to a committed snapshot file the headless suite reads, and a **gate
   recomputes and diffs** — a stale snapshot (sheet ≠ file) fails the build. This is
   the standard "generated artifact with a freshness check" discipline.
3. **Fallback B — Luau data file is source of truth; generator emits the sheet.** A
   single Luau token file is authoritative; the Phase 1 generator emits the sheet
   *from* it (one-way for layout tokens); the editor may still freely edit **paint**
   tokens (which round-trip), while layout-token edits in the editor are
   re-generated, not consumed. This is the safest for correctness, weakest for
   editor round-trip of *layout* values — acceptable because designers overwhelmingly
   edit paint, not the spacing scale.

Whichever lands, the **composition** stays in the one shared resolver, so future
features (ten-foot lift, density cap, reduced-motion) layer identically.

### 6.10 Motion via native Styling Transitions (R2, progressive enhancement)

Native transitions fire when a property changes through the styling system. Roblox
owns read-only native `GuiState`; LuauUI-owned state changes through tags. Ordinary
layout or direct property writes are not transition triggers. Design:

- **Transition tokens** `$MotionFast` / `$MotionNormal` mirror `default_style.motion`
  (`default_style.luau:86`), linked to `TweenInfo`; per-property transitions on the
  hover/press/selected rules (per-property is higher-precedence and more performant
  per the docs).
- **Trigger discipline:** native state changes and LuauUI tag changes are the
  triggers; explicit writes are not used for handed-off state props.
- **Progressive enhancement:** transitions are Studio-beta and cannot ship to live
  experiences yet; the plan **never depends** on them. With the beta off (or on a
  client without it), a tag flip changes the property *instantly* — which is a
  perfectly good fallback and, for non-animated state, already today's look. So
  transitions are capability-probed (Q3-style probe) and enabled purely as polish;
  **no earlier phase depends on them.**
- **Reduced-motion:** prefer a `ReducedMotionEnabled` StyleQuery that selects rules
  with no transition or zero-duration transition. Keep a tested strip/clear fallback
  only if the beta cannot express the required query behavior.
- **State-as-tags lands *before* transitions** (phase order, §7) so enabling the beta
  later is zero-rework: the triggers already exist; only the transition tokens and
  the probe get switched on.

---

## 7. Phased implementation plan

Each phase is independently shippable and gated. Artifacts follow the existing
`artifacts/phase-*/gate.json` convention (`phases.json`). Re-cut under the rulings:
state-as-tags lands in Phase 2, *before* transitions in Phase 3, so the beta is
zero-rework to enable.

### Phase 0 — Feasibility spike (no production code)
- **Scope:** resolve the load-bearing open questions in a throwaway Studio place via
  the Studio MCP, mirroring the 2026-07-19 spike method. **Adds under the rulings:**
  transition trigger semantics (does a CollectionService tag change transition? do
  engine-owned `GuiState` changes? does `SetDerives` cross-fade? does runtime token mutation trigger
  transitions and does it fight the editor's view?), and the additive-mechanism probes
  (token mutation vs derive overlay behaviour), on top of the original Q1–Q5, Q8.
- **Deliverables:** `docs/research/2026-07-2x-native-stylesheet-spike.md` +
  `artifacts/studio/native-stylesheet-spike.json` recording every Q1–Q12 answer with
  machine evidence.
- **Gate:** every Q1–Q12 answered with evidence, or explicitly deferred with the
  bespoke fallback named. **No later phase starts on an unproven capability.**
- **Risks:** a capability (esp. state selectors / transition triggers on LuauUI's
  exact buttons) may not work → those sub-features stay bespoke / instant; plan still
  proceeds for tokens/derives/paint.

### Phase 1 — One-way generator + the layout-token sync decision (option (b) scaffold)
- **Scope:** a headless-authored generator that turns a compiled token set into a
  `StyleSheet` model with human-readable token + rule Names (§6.1), written into the
  DataModel by the client (never the core). Paint tokens as attributes; **layout-token
  source-of-truth decided per §6.9** (Rojo shared file / snapshot+staleness /
  Luau-source), driven by the Q5 result.
- **Deliverables:** `src/client/native_style/generate.luau` (client-only) + a
  Studio/CLI entry that emits the sheet for Studio Neutral; the sheet is inspectable
  in the Style Editor. Contrast gate reused on the emitted palette. If §6.9 lands on
  Fallback A, the staleness gate ships here.
- **Verification gate:** generated sheet opens in the Style Editor with readable
  names; a headless test asserts token *values* equal `default_style`; **no runtime
  behaviour change yet** (adapter still explicit-writes). Library + game suites green.
- **Risks:** Rojo vs `.rbxm` authoring (Q5) — if Rojo can't hold it, ship as a
  generated model asset and adopt §6.9 Fallback A/B.

### Phase 2 — Adapter "native paint + state-as-tags" mode behind capability + opt-in flag
- **Scope:** add a second code path in `screen_target` that, when a sheet is present
  and capability-probed, **classifies** nodes (class + surface/app-state tags),
  observes engine-owned `GuiState`, parents one `StyleLink` per root, and **omits** the explicit
  writes for the handed-off `style`-authority properties (background fills, corner
  radius, hairline; hover/press/selected fills as native rules per §6.3). Crucially,
  **app state is expressed as tag changes, not property writes** — the zero-rework
  setup for transitions. The authority manifest gains a per-property
  `style-native` vs `style-bespoke` distinction so the renderer knows which writes to
  suppress.
- **Deliverables:** native-paint path gated by
  `screen_target.new({ nativeStyle = sheet })`; fallback to explicit-write when
  absent/unsupported; a headless conformance test on the fake target proving the
  *data* (tags/classes/state changes) is emitted even where paint is a no-op.
- **Verification gate:** Studio drive shows a native-painted RascalRally settings
  modal **pixel-matching** the explicit-write version (before/after screenshots, the
  ADR-0006 method); state changes read as instant (transitions still off) and *look
  identical* to today; the property-authority assert never fires; toggling the flag
  off restores today's look byte-for-byte.
- **Risks:** the §3 constraint — any residual explicit write to a ruled property
  silently wins; the gate's job is to catch exactly that. Touch-hover flash (Q1/Q4).

### Phase 3 — Transitions + theming + additive a11y scaling
- **Scope:** three additive-over-Phase-2 layers, each capability-probed and each a
  no-op-fallback: (a) **native transitions** — attach `$MotionFast`/`$MotionNormal`
  transition tokens to the state rules; because Phase 2 already changes tags and
  relies on native button states,
  this is switch-on-only (§6.10); reduced-motion via strip-transitions mode. (b)
  **theming** — ship a second theme as a `StyleDerive` with a runtime `SetDerives`
  switch (§6.7), contrast-gated, cross-fading if Q10 holds. (c) **additive a11y
  scaling** — wire the corrected §6.9 contract: base font size sheet-authored via the
  sync path, engine preference applied exactly once, and authored/ten-foot scale
  measured consistently; paint a11y
  overlays as a generated derive.
- **Deliverables:** theme-switch API on the target; a light theme sheet;
  strip-transitions reduced-motion path; the shared-resolver wiring proving headless
  measure == edge paint for the scaled base.
- **Verification gate:** device passes on touch/mouse/gamepad confirm hover does not
  flash on touch, selection paints from the sheet, a runtime theme swap repaints
  without remount or focus loss, transitions animate state on a beta-enabled client
  and are *instant* (identical to Phase 2) with the beta off, reduced-motion strips
  them, and a headless test asserts the solver's measured size equals the edge's
  painted size for a scaled base.
- **Risks:** touch hover flash (Q1); paradigm-query timing (Q4); transition trigger
  semantics (Q9); token-mutation-vs-editor (Q11).

### Phase 4 — Round-trip + migration + retire the deferral
- **Scope:** make the DataModel sheet the *source of truth* for paint (editor edits
  win; the generator becomes a one-time seeder, not a clobberer); document the
  two-token-home model and the §6.9 sync path; update `src/tokens/tokens.luau` header
  to lift the "StyleSheet generation deferred" note (`tokens.luau:1-6`), noting
  transitions are now opt-in enhancement rather than a blocker; write the guide
  chapter update.
- **Deliverables:** `docs/guide/05-styling.md` new "Native stylesheets" section; an
  ADR (`ADR-00xx-native-stylesheets`) recording the headless-testability reframing
  (R1), native-maximal decision (R2), and the additive-layering contract (R3);
  existing **LuauUI-based** RascalRally screens opted in reversibly (§8). This does
  not migrate or default-flip Sponsor Mode.
- **Verification gate:** a designer edits a colour in the Style Editor, and the
  running RascalRally UI reflects it with no code change; full suites green; api.md
  surface check passes.
- **Risks:** editor-vs-generator source-of-truth conflict — resolved by making the
  paint generator seed-once and never overwrite an existing sheet; layout-token
  round-trip resolved per the §6.9 mechanism chosen in Phase 1.

---

## 8. Migration story (existing LuauUI screens)

The real consumers are the RascalRally LuauUI screens at
`games/RascalRally/code/src/client/LuauUI*.luau`. The migration cost is
**deliberately near-zero for screen authors**, because styling was designed as
semantic hints resolved only at the edge:

- **Pure blueprint screens need no change.** `LuauUISettingsScreen.luau` builds its
  tree with `surface = "raised"` and `role`/`textSize` hints and *never names a
  colour* (`.../LuauUISettingsScreen.luau:83`). Under native paint those same hints
  become tag stamps; the blueprint is untouched. Same for `LuauUIRacerListScreen`.
- **Only the "Gui" glue half opts in.** `LuauUISettingsGui.luau` constructs the
  target with `screen_target.new()` (`.../LuauUISettingsGui.luau:34,80`). Migration
  = pass `{ nativeStyle = <sheet> }` and ensure the sheet exists under
  `ReplicatedStorage.LuauUI` (a generated asset from Phase 1). If the sheet is absent,
  the adapter falls back to explicit-write and the screen looks exactly as today.
- **Contrast/behaviour parity** is the gate, screenshot-matched per ADR-0006, so a
  migrated screen is provably identical before any editor customization — and,
  because state is now tag-driven, *before* any transition is enabled it is identical
  down to the instant state change.
- **No headless test changes.** The fake target and all `*.spec.luau` keep asserting
  on layout + semantic hints; paint was never in the headless dumps
  (`05-styling.md:154-159`). The only new headless assertion is that the solver's
  measured size equals the effective scaled base (§6.9) — a strengthening, not a
  rewrite.

The migration is therefore **opt-in per target, invisible to screen code, and
reversible by a flag** — the same graceful-degradation shape LuauUI already uses for
`UIShadow`/per-corner radii.

---

## 9. Non-goals

- **Replacing the layout solver or moving any layout-affecting value's *resolution*
  into the sheet.** Rects, `TextSize` (incl. the ten-foot floor), padding, and target
  sizes stay solver-resolved in Luau; the sheet may *mirror/author* the base values
  (§6.9) but the headless solver reads them as plain Luau, not from a live DataModel.
- **Depending on native transitions.** Studio-beta and not shippable to live yet;
  they are progressive enhancement with an instant-change fallback (§6.10). Motion
  that is choreographed/timeline/spring/value-driven stays bespoke and
  reduced-motion-aware regardless of transition GA.
- **Sourcing layout-affecting tokens from a *live* DataModel at test time.** The
  headless solver's values stay Luau-resolvable (R1, §2.6, §6.9).
- **A live-Instance dependency in `src/core|render|present|layout|env`.** These
  modules may *model* Roblox concepts (R1) but must run headlessly; no `Instance.new`
  / `game:GetService`. (This is the reframed successor to Revision 1's
  "engine-agnostic boundary" non-goal — the mechanism-forbidding rule is the same;
  the *justification* is headless testability, and modelling engine concepts is now
  explicitly fine.)
- **Additive layering implemented as explicit writes to styled properties.** Forbidden
  by §3.4 — additive means multiply-in-the-resolver / derive-overlay / `UIScale`
  (§6.9), never a poke at a ruled property.
- **Round-tripping the focus ring, ten-foot lift, or reduced-motion logic** into the
  editor — these are computed, not authored.
- **Modifying the engine base style sheet** (docs explicitly warn against it).

## 10. Open questions and verification steps

Q1–Q8 carry over from Revision 1 (Q5 is now *more* central — it decides the §6.9 sync
mechanism); Q9–Q12 are new under the rulings. None were fully mooted by the rulings —
the layout/paint split survives under headless testability rather than
engine-agnosticism, so its questions stand.

| # | Question | Why it matters | Verification |
|---|---|---|---|
| Q1 | Do `:Hover`/`:Press` fire for `AutoButtonColor=false` buttons, and on **touch**? | Whether hover/press fills can be native at all (and whether touch flashes hover) — and whether state motion can be free | Studio place: `TextButton:Hover`/`:Press` rules, drive on desktop + touch emulator via Studio MCP |
| Q2 | Can rules style modifier children (`::UICorner`, `::UIStroke`, `::UIScale`), and do they **create** a missing modifier or only style an existing one? | Corner radius, hairline, and (if it works) shadow/scale via rules; else these stay bespoke | Studio rule on a Frame with and without the modifier present |
| Q3 | Is core StyleSheet **GA** (not beta), and what is the min engine version + capability probe? | LuauUI needs a `hasStyleSheet` probe like `hasUIShadow` (`screen_target.luau:100-105`) | `pcall(Instance.new,"StyleSheet")` on min client; check channel notes |
| Q4 | How do the documented built-in `StyleQuery` conditions re-evaluate, and when should LuauUI tags represent a filtered framework fact instead? | Per-platform paint + the touch-hover gate | Studio place changing preferred input/display/reduced-motion; separately toggle the LuauUI pointer-live tag and observe repaint |
| Q5 | Can `StyleSheet`/`StyleRule` trees be authored in the **Rojo** project, or must they be an `.rbxm`? | **Decides the §6.9 layout-token source-of-truth mechanism** (Rojo shared file vs snapshot+staleness vs Luau-source) *and* how the sheet ships | Attempt `$className: StyleSheet` in a Rojo node; inspect round-trip |
| Q6 | **Specificity/cascade** when class + tag + state + query rules all match — which wins, and how does `StyleRule.Priority` interact? | Predictable paint; the docs are explicitly silent | Studio: overlapping rules with varied `Priority`, read resulting property |
| Q7 | Does applying/swapping a `StyleLink`/derive at runtime cost proportional to tree size? Any documented budget? | Theme-swap perf on device (the style lint already watches a shadow budget, `05-styling.md:140-144`) | Measure a derive swap over a large tree on a mid device (device numbers authoritative, design §14.3) |
| Q8 | Can a rule set `UIShadow` params (`::UIShadow`), or must shadows stay adapter-materialized? | Whether §6.2's shadow row moves to the sheet | Studio rule targeting `::UIShadow` |
| **Q9** | Do CollectionService tag changes, engine-owned `GuiState` changes, derive swaps, and token changes trigger transitions exactly as documented? Confirm direct writes do not. | The state-to-native-motion premise (§6.10) | Studio place with native-state and tag rules; exercise each styling change and a direct property write; record which animates |
| **Q10** | Does a **`SetDerives` theme swap** trigger transitions (animated cross-fade)? | Free theme cross-fade (§6.7); if not, theme swaps are instant (acceptable) | Studio: two derives with a transition on the shared rules; `SetDerives` at runtime; observe |
| **Q11** | Does **runtime token (attribute) mutation** trigger transitions, and does it **fight the visual editor's live view** of the sheet? | Additive candidate (a) viability for continuous paint scaling (§6.9); preview correctness (§6.8) | Studio: mutate a `$Token` at runtime with a transition present + editor open; observe animation and editor sync |
| **Q12** | Is there a **reduced-motion / global disable** for transitions? If not, does `SetPropertyTransitions` zero-duration / clearing reliably strip them? | LuauUI's non-negotiable reduced-motion requirement (§6.5 item 5, §6.10) | Studio: apply transitions, then strip via `SetPropertyTransitions` zero-duration; confirm instant changes |
