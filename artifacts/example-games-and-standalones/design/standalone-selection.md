# Which places ship, and why — the curated standalone set

Binding scope: `docs/plans/example-games-and-standalones.md`, "Curated standalone
places". The target is **five to seven curated existing showcase standalones plus the
required world terminal — six to eight in total** — not one place per scenario, on top
of the seven tutorial places the guide teaches.

---

## 1. What exists today

**Seven tutorial places** (`examples/places/01_…` – `07_…`), built by
`tools/build_places.sh`. These stay: the guide teaches them in order, and a reader who
follows it needs to open them.

**One superseded settings demo** (`examples/places/00_settings_demo.rbxl`). The plan
allows removing it "if the new shared standalone chrome covers its purpose" — and only
then.

**Five reference-proof places** (`Facet-Ref-Glade`, `-Cartwheel`, `-Sipworks`,
`-Foyer`, `-Wardrobe`), built by `tools/build_reference_places.sh`. Wardrobe retires.

**Fifty-seven showcase scenarios**, none of which has a standalone place today.

**No manifest.** The seven tutorial names are written out independently in five files
and the five reference proofs in six, and nothing cross-checks any of them against each
other. That is the parallel-list problem the plan names, and closing it is what makes
this selection enforceable rather than aspirational.

## 2. The required capability families

The plan names seven. Each must be covered by at least one curated place:

1. adaptive controls and input paradigms
2. row actions, or another platform-dependent interaction
3. `withAnimation` and reduced motion
4. one realistic large virtualized collection
5. one async-resource loading-and-recovery screen
6. one large-text or narrow-layout adaptation screen
7. the Outpost Power Terminal on a real `SurfaceGui` world target

## 3. The selection

Seven places: six curated from what already exists, plus the required terminal. The
rule the plan gives for choosing between candidates is "prefer one place that teaches
more than one related feature", so each row below carries more than one family where it
honestly can.

| Place | Source | Families | Why this one, and not a neighbour |
|---|---|---|---|
| **Sipworks** — serve a customer and earn a reward | `examples/reference/p3_sipworks` | 1, 5, 6 | The only candidate whose loop is a *transaction*: choose, order, be accepted or rejected, earn, redeem. That makes it the natural home for the async accept/reject/recovery lesson, and its adaptive nav shell (sidebar ⇄ bottom bar, chosen by fit failure rather than by width) is the clearest statement of what adaptation means in this framework. Required by name in the plan. |
| **Glade** — prepare a home for a visiting wisp | `examples/reference/p1_glade` | 1, 3, 6 | A two-condition goal with visible progress and a draining supply, which is a different shape of task from Sipworks' transaction — and the arrival is the motion lesson attached to something the player wanted to happen. Required by name in the plan. |
| **Playlist table** — sort, filter, and reorder a real library | `examples/gallery/examples/02_playlist_table` + the showcase's table scenarios | 2, 4 | Carries both of the families that are otherwise hard to place: a genuinely large virtualized collection, and row actions with the column sort/resize work that retired the standalone `table_columns` scenario. One place, two families, and it is a screen a real game would have. |
| **Cartwheel operations** — a dashboard that reacts | `examples/reference/p2_cartwheel` | 3, 5, 6 | The widest adaptation surface in the repository: split navigation, a countdown state machine, an entitlement gate, charts, and a sign-up form. It is where large text and narrow layouts have the most to break, which is exactly why it is worth shipping as a place someone can open at Largest text. |
| **Foyer** — a home feed that changes shape | `examples/reference/p4_foyer` | 1, 6 | The nav rail ⇄ bottom bar transition and the search collapse are the compact-layout lesson in its purest form. Kept over a bespoke "narrow layout" fixture because it is a screen, not a diagnostic. |
| **Sensory feedback** — what an interaction meant | `examples/gallery/scenarios/sensory_feedback` | 2 | The other platform-dependent interaction, and the one with no standalone today. After its rework it is four playable comparisons rather than eight panels, which is what makes it worth opening on its own. |
| **Outpost Power Terminal** — walk up and use it | new | 7 | Required. |

**Six existing plus the terminal is seven**, inside the six-to-eight target.

## 4. Why each unchosen scenario stays showcase-only

The plan requires this half too — an unchosen scenario needs a reason, not silence.

| Scenario family | Why it stays in the showcase |
|---|---|
| The eight Sponsor labs (`sponsor_motion`, `sponsor_celebration`, `sponsor_list`, `sponsor_drop`, `sponsor_toast`, `sponsor_avatars`, `sponsor_markers`, `sponsor_billboard`) | They are fixtures for a specific consumer's screens, and they are most useful side by side where a reviewer can compare them. Individually they teach a mechanism, not a game. |
| The verification fixtures (`probe`, `safe_area`, `scroll_host`, `preferred_text`, `preferred_transparency`, `selection_bridge`, `native_style`, `perf_capture`, `surface_overlap`) | Diagnostics by design. The plan's own bar — "a standalone should feel like a small screen from a real game first" — is one these cannot meet, and dressing them up would make them worse instruments. |
| Single-construct demos (`callout`, `menu`, `tab_view`, `progress_ring`, `path_ring`, `flow_wrap`, `branch_scope`, `sorted_entries`, `time_curves`, `canvas_group`, `level_picker`) | Each teaches one construct in a minute. They belong in the picker where a reader can step through them, and the guide links them there. A place per construct is exactly the "one place per scenario" outcome the plan rules out. |
| `with_animation`, `lifecycle_hidden`, `text_degrade`, `variable_extents`, `measured_extents`, `row_capabilities` | Mechanism demonstrations whose lesson is already carried, in a game context, by a chosen place. |
| `composition`, `hud`, `keyboard_navigation`, `nested_compositing`, `adaptive_controls`, `theme_authoring` | Framework-surface fixtures. `adaptive_controls` and `theme_authoring` come closest to earning a place; both are covered by the chosen places' own adaptation and theme chrome, and shipping them separately would duplicate a lesson rather than add one. |
| `examples`, `row_actions`, `table_virtualized`, `virtual_grid`, `virtual_hgrid`, `card_rail` | Covered by the playlist-table place, which is the same lesson attached to content. |
| `ref_cartwheel` / `ref_glade` / `ref_sipworks` / `ref_foyer` as *scenarios* | Unchanged: the scenario is how the showcase reaches them and how the device matrix drives them. The standalone is a second host for the same module, never a fork. |
| `ref_wardrobe` | Retired. See the Wardrobe rows. |

## 5. What every place has to show

The plan's bar, applied to all fourteen shipped places (seven tutorials, seven curated):

- a title;
- the player goal or task, in a sentence;
- a discoverable first action;
- visible success and failure feedback;
- a reset;
- a short optional **What this shows** explanation *after* the play task, never in place
  of it;
- the theme picker, with the public reference themes actually mapped into the place —
  today the tutorial builds map no `FacetThemes` folder at all, so every tutorial place
  offers one theme and the picker is a chip that does nothing;
- the shared Full / Reduced motion control, wherever the place has decorative or
  informational motion, writing the same `reducedMotion` environment fact as the
  showcase and reusing the showcase's settings model rather than a copy.

And what must not be on the player surface: test-only jargon, stage IDs, gate language,
capability-ledger codes, "reference proof", and raw counters — unless the number *is*
the lesson.

## 6. The manifest

One checked-in manifest is the source for: the showcase registry, presentation-target
and world-fixture metadata, standalone project generation, build outputs,
documentation, and the drift tests. Nothing else keeps a list.

It replaces the copies currently living in `tools/build_places.sh`,
`tools/build_reference_places.sh`, `examples/gallery/client/boot_mode.luau`,
`examples/gallery/scenarios/examples.luau`, `examples/gallery/client/demo_picker.luau`,
`examples/gallery/scenarios/init.luau`, `tools/lune/triage_overflow_waivers.luau`,
`tests/overflow_sweep.spec.luau`, and the embedded literals in
`tools/lune/gate_manifest.luau` — each of which is a place a rename can go wrong
silently today.

`tools/build_themes.sh` already works this way and says so in its own header: *"THE
LIST IS DERIVED, NEVER TYPED HERE."* That is the shape to copy, including its refusal
to build when the enumerator returns nothing — because a manifest that can quietly
describe an empty world is not a manifest.

The drift test must prove the manifest **rejects** an orphaned output and a missing
one. A manifest that cannot fail is a list with extra steps.
