# Playbook: adopting a new engine feature

Audience: an agent with no prior context. This is the path for adopting a
NEW Roblox instance class or property (a hypothetical `UIBlur`, a new
layout-adjacent instance, a new text capability) WITHOUT letting engine
specifics leak past the adapter layer. The shipped worked example is the
UIShadow + per-corner UICorner adoption — read these as you go:
`src/tokens/styling.luau`, `src/render/authority.luau`,
`src/render/renderer.luau` (style-prop write list),
`src/client/screen_target.luau` (`applyShadow`/`applyCorners` + capability
detection), `src/render/style_lint.luau`,
`docs/research/2026-07-20-uishadow-percorner-engine-facts.md`.

Read [`../reference/constitution.md`](../reference/constitution.md) first — the
rules your addition must follow.

Also follow
[`../plans/agent-execution-contract.md`](../plans/agent-execution-contract.md).
Engine adoption requires both a live property/event probe and an integrated visible
Studio slice; successful Instance construction or a headless adapter write alone is
not completion evidence.

Engine features enter ONLY through the render-authority/adapter layer with
capability detection and a headless fallback. If your plan touches the
layout solver, the mount layer, or the core, stop — that is a design change,
not a feature adoption.

## 1. Verify the engine facts (never trust memory)

Write down, with sources (creator docs / release post) and a live probe
where possible: exact property names and TYPES (UDim vs UDim2 vs number —
the UIShadow adoption caught two type errors in the design's own prose),
value ranges and clamps, which instances it applies to, interaction hazards
(e.g. alias-vs-individual-property mixing), performance guidance, and GA vs
beta status. Record it as `docs/research/<date>-<feature>-engine-facts.md`.
Run a Studio probe that round-trips every property and record the artifact under
`artifacts/studio/`. If Studio is unavailable or its viewport/capture/input preflight
fails, record `FAIL_ENVIRONMENT` and leave the engine-evidence row pending rather than
approving the feature from source or Lune behavior.

## 2. Failing tests first

Add a spec (register it in `tests/run.luau` — see the silent-zero trap in
[new-control.md](new-control.md)) asserting, before any implementation:

1. the declaration API you intend (modifier or prop) normalizes to
   engine-true data, with validation errors for illegal values;
2. the data lands on the adapter under the correct PROPERTY AUTHORITY;
3. the feature never affects layout (identical rects with/without it) unless
   it is genuinely a layout feature — in which case stop (design change);
4. any engine guidance becomes a lint warning or budget.

## 3. Implement along the one seam

0. **Declare it in the schema** — `src/blueprint_schema.luau`. Since strict
   authoring (0.5.0, ADR-0011), a public property that is not in the schema is
   REJECTED at construction with a "did you mean" diagnostic: every `UI.*` call
   using your new prop errors before any of the work below can run. Declare the
   property (its class, accepted types, enum values and default) first, or you
   will implement normalization, authority, renderer and adapter and then watch
   the feature refuse to be authored at all. `new-control.md` §"Add the prop"
   states the same obligation from the control side.
1. **Normalization**: a pure module (or extension of
   `src/tokens/styling.luau`) turning the public spec into frozen,
   validated, engine-true data. Token names resolve against the active
   style.
2. **Public surface**: a blueprint modifier (`UI.<thing>(bp, spec)`) or prop,
   returning a NEW blueprint (blueprints are immutable).
3. **Authority**: add the property to `src/render/authority.luau` MANIFEST
   under the right authority (usually `style`). One authority per property —
   the renderer asserts every write.
4. **Renderer**: add the prop to the style-authority write list in
   `src/render/renderer.luau` (`ensureTree`); the renderer stays
   engine-free — it just forwards data.
5. **Client adapter**: materialize in `src/client/screen_target.luau` behind
   a `pcall(Instance.new, "<Class>")`-style capability flag with a
   documented fallback (older engines and Lune: keep the declaration as
   data, degrade gracefully). Lune's reflection does NOT know new classes —
   never construct engine instances outside the client adapter.
6. **Lint/budget**: engine guidance ("at most ~N", "misbehaves with X")
   becomes a `src/render/style_lint.luau` rule and/or a perf-runner scene
   (`bench/perf_scenes.luau`; re-baseline with `tools/perf.sh baseline`).

## 4. Documentation + evidence

- `docs/reference/api.md` entry for the public surface (the registration
  checker fails without it), plus a paragraph in `docs/guide/05-styling.md`
  or the relevant guide page.
- Gates: `./run-tests.sh`, `lune run tools/lune/check_registration_cli`,
  `lune run tools/lune/check_prop_parity_cli`,
  `lune run tools/lune/gate phase-4-hardening` — all exit 0. The parity checker
  is the one that belongs to THIS playbook specifically: it pins a property's
  whole chain against itself — schema ↔ dirty class ↔ authority ↔ renderer
  emission ↔ adapter `setProp` branch ↔ spec type ↔ api.md — so a step skipped
  above fails here by name instead of shipping as a silent no-op on a device.
- Evidence: research doc, spec transcript (red then green), Studio probe artifact,
  and an integrated visible gallery artifact that pairs runtime state/geometry with a
  capture. Hardware-only behavior remains an explicitly named pending row until it is
  physically observed.
