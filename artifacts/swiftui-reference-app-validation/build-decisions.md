# Stage build decisions — swiftui-reference-app-validation

Fixed by the lead 2026-08-08 so the implementation packages stay disjoint. Every
package follows these; deviations need a decision packet, not silent divergence.

## Code layout (engine-free, like examples/gallery/examples)

```
examples/reference/
  p1_glade/     init.luau (buildScreen(ctx) -> Blueprint + api), services/, content/
  p2_cartwheel/ same shape
  p3_sipworks/  same shape (+ entry_compact.luau for the compact entry flow)
  p4_foyer/     same shape
  p5_wardrobe/  same shape (client-side stage content mounts ONLY via
                controller.stageHost from the scenario/client bootstrap seam)
```

- Modules are pure Luau: no engine types, no `script`-relative tricks beyond the
  repo's dual-context require conventions; blueprints + fake services only.
- Every fake service takes `{ clock, seed }` injected by ctx; no `os.*`,
  `math.random`, or wall time in proof code. Scenario reset = rebuild from seed.
- All strings route through the proof's own `content/strings.luau` table keyed
  by locale (`en`, `xa` pseudo-expansion ≥1.4×); locale comes from `ctx.locale`
  or the env fact.

## Shared integration points — OWNED BY THE LEAD, not by packages

To keep packages conflict-free, only the lead edits: `tests/run.luau`,
`examples/gallery/scenarios/init.luau` (ORDER), any shared build script, the gate
manifest, and `docs/reference/api.md`. The lead scaffolds, per proof:

- `examples/gallery/scenarios/ref_<name>.luau` — the scenario (select, reset,
  report, theme drive) following the Step 10 `examples` scenario pattern;
- `tests/reference/<name>_spec.luau` — the proof's spec file (packages own its
  contents); registered in tests/run.luau by the lead;
- a `tools/build_reference_places.sh` entry emitting `examples/places/LuauUI-Ref-<Name>.rbxl`.

Packages edit ONLY their own `examples/reference/<proof>/` folder and their own
`tests/reference/<name>_spec.luau`.

## Proof obligations (identical for all five)

1. The complete representative loop from acceptance.md (RA-P*) drivable
   headlessly through the public controller/presenter APIs and through the
   scenario in Studio; no test-only shortcuts standing in for on-screen controls.
2. Success, failure/rejection, interruption, empty, and reset states reachable
   through on-screen controls alone; every rejection shows player-facing copy.
3. Public LuauUI only; the responsibility-ledger forbidden list is a hard gate.
4. Both reference theme packages must mount it (Studio Neutral + Fantasy
   Parchment) with zero source edits.
5. Deterministic dumps: same seed + same steps ⇒ identical `dump()`.
6. Focus/keyboard obligations: presenter `keyboardNavigation = true` for these
   UI-first scenarios; every verb reachable per the spec's input table.
7. Suite pins for the loop's domain logic (E1) live in the proof's spec file;
   Studio evidence rows are the lead's pass, not the package's.

## Approximation rules (from capability-ledger §A/§G — restated as binding)

- Hero/shared-element transitions: presentModal/When + materialize + canvasGroup
  fade. No matched-geometry claims anywhere in code or comments.
- Card flip: motion-driven width-collapse (scale-X through zero swap).
- Charts: read-only; Path polylines (≤100 pts), Box bars, banded Box strips.
- Swipe rows/long-press: visible affordances on every input class instead.
- Blur/materials: translucent surfaces + scrim tokens; never claimed as blur.
- P5/P2 3D: `UI.Stage` + `controller.stageHost`; content mounts from the client
  bootstrap seam; a nil host presents the declared fallback plate.

## Naming

Proof ids `ref_glade`, `ref_cartwheel`, `ref_sipworks`, `ref_foyer`,
`ref_wardrobe`; place names `LuauUI-Ref-Glade` etc. Original content per the
specs in `specs/`; no Apple or Roblox names, copy, art, or iconography.

## Tab-adaptation ruling (director, 2026-08-09, post-close fix round)

The reference behavior (Backyard Birds' own source: `prefersTabNavigation` =
idiom `.phone`) keeps bottom tabs on a phone in BOTH orientations and gives
tablet/desktop the sidebar. LuauUI proofs cannot branch on device idiom, and
the director ruled the current shape-fact behavior acceptable with one fix:

- **Portrait phone: tabs at the BOTTOM** (thumb zone, below the content —
  never stacked under the engine topbar). Sipworks violated this via the
  `column` preset (lane order lead->main->trail seats a "lead" nav group on
  top); fixed with a custom `tabsBelow` arrangement and a geometry pin.
- **Landscape phone: the sidebar is accepted** (deviation from the reference,
  ruled OK live — height is the scarce axis there and the rail spends the
  abundant one). The `isCompact or isShort` SwiftUI-faithful alternative is
  recorded in the conversation and available if the ruling changes.
- Lane-order-vs-declaration-order is the trap: arrangements decide STACKING by
  lane order; group declaration order decides FOCUS order only.

## Tab-adaptation ruling v2 (director, 2026-08-09, HIG round)

Superseding the first ruling's "landscape sidebar accepted": the behavior now
follows the platform tab-bar guidance, encoded as PUBLIC framework policy
(`adaptive.navPlacement` + the reactive `conditions.navPlacement`):

- Phone portrait → full-width bottom tab bar (thumb zone), search as the
  TAB-BAR ACCESSORY directly above it.
- Phone landscape → the same bar in its reduced INLINE form: short labels,
  tighter band, CENTERED and hugging its tabs (never a full-width stretch),
  with a fit fallback to the shared full-width band at the 1.4x locale +
  largest text.
- Tablet shape (touch/gamepad + Medium/Large DisplaySize) and ten-foot → a
  CENTER-ALIGNED top tab bar that HUGS its tabs, search on the band's
  trailing edge.
- Desktop (pointer-primary) → sidebar.
- Touch/gamepad with a Small or unknown display → bottom tabs ("Small and
  joystick can vary"; when we cannot differentiate a phone/handheld from a
  tablet, the bottom bar is the safe home). Touch ALONE is never the top-bar
  indicator — DisplaySize + preferred input are.
- Every placement is proven GAMEPAD-TRAVERSABLE (enter, through, away,
  ButtonA action) — the top bar by a real DPad walk in a keyboard-less world.

Trap ledger from the implementation: the `align` prop overload (framework
finding 15) bit AGAIN — a hug row's own `align="stretch"` was read by its
centering parent and stretched the cluster back to full width; hug rows must
not declare `align`.
