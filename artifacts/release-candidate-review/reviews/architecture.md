# Release-candidate architecture review (fresh-context verifier, 2026-08-17)

Reviewed at commit b230b87. Stored verbatim by the controller from the
verifier's returned report (the verifier stub has no file-write tool). Compact
form: verdict + findings table; reproduction and triage happen in the stage's
finding ledger (findings.md).

[ARCH-REVIEW]: CONCERNS

ARCH-1 | High | High | src/mount.luau:354-366 | A row-factory throw with no ErrorBoundary aborts ForEach's rebuild: disposed rows stay in `node.children`, no `structure` dirty is pushed.
ARCH-2 | High | High | src/render/renderer.luau:2997,3019 | Because structuralSync only runs on a `structure` dirty entry, ARCH-1's stale disposed rows keep their Instances on screen, frozen, forever.
ARCH-3 | Medium | High | src/render/renderer.luau:696,703 | Two `adapter.setProp(..., "dragHeld", ...)` writes skip `authority.assertWrite`, contradicting "asserts every write" (constitution §11).
ARCH-4 | Medium | High | docs/guide/02-architecture.md:176-180 | Guide states `host` authority has "no property uses it today"/"four live authorities"; authority.luau:184 has shipped `Foreign.Parent = "host"`.
ARCH-5 | Medium | High | docs/reference/api.md:6851 vs constitution.md:229 | api.md says NINE blessed client entry points (incl. `haptics`); constitution §12 and guide 02-architecture.md:28 still say eight.
ARCH-6 | Medium | High | docs/reference/api.md:211 | `UI.schema` is asserted to have "eleven members"; the live table has 15 — `checkOpacity`, `checkScaleFactor`, `checkDegrees`, `refusal` undocumented.
ARCH-7 | Medium | High | tools/lune/check_registration.luau:50-63 | NESTED_NAMESPACES omits `UI` (so `UI.schema`'s members), `pathShapes`, `contribution`, `renderer` — the hole that let ARCH-6 land.
ARCH-8 | Medium | High | src/spec_guard.luau:1-37 | `spec_guard` is required by 22 control modules but is not exported from src/init.luau, so an out-of-repo control cannot meet constitution §4 strictness.
ARCH-9 | Medium | Medium | docs/extending/new-control.md:113-123 | The control playbook teaches strictness only for `UI.*` specs and never tells an author to validate its own spec — no public route exists (see ARCH-8).
ARCH-10 | Medium | Medium | src/render/layout_node.luau:42 | `render` requires `controls/contract`, inverting the documented layering (guide 02: composites are built *on top of* primitives).
ARCH-11 | Medium | Medium | src/controls/contract.luau:24 | The file is a registry of PRIMITIVE classes (Screen/VStack/Text/Grip), not composite controls; its placement under `controls/` misleads every reader.
ARCH-12 | Medium | Medium | docs/reference/api.md:3555-3574 | `newActionSystem` is a `newX` factory holding session state with no dispose and no stated lifetime contract (constitution §2/§8).
ARCH-13 | Medium | Medium | docs/reference/api.md:4806-4830 | `newResourceProvider` likewise: caches, in-flight requests and `gaveUp` state, no teardown seam, no stated session-lifetime contract.
ARCH-14 | Low | High | src/themes/package.luau:439 | Comment names "a UI.Custom host" — a class that never shipped; the escape hatch is `UI.Foreign` (ADR-0034).
ARCH-15 | Low | High | src/tokens/chrome_slots.luau:33-101 | The public theme-authoring tag vocabulary is still `luau-*` under a framework named Facet; not covered by ADR-0036's "did not move" list.
ARCH-16 | Low | High | tools/check_brand_drift.py:36 | `BRAND = luau[\s._-]?ui` structurally cannot see the `luau-*` tag family, so ARCH-15 can never be flagged by the rename guard.
ARCH-17 | Low | High | src/spec_guard.luau:45; src/blueprint_schema.luau:2479; src/themes/package.luau:547; src/motion/classes.luau:71 | Four Levenshtein copies with three different suggest thresholds.
ARCH-18 | Low | Medium | src/tokens/sheet_model.luau:30 | `tokens/` requires `themes/package` while `themes/package` requires three `tokens/` modules — a directory-level layering inversion (no true cycle).
ARCH-19 | Low | Medium | src/themes/package.luau:28 | The pure theme compiler requires `render/authority`, coupling the "engine-free theme data" layer to the render layer's manifest.
ARCH-20 | Low | Medium | tools/lune/check_prop_parity.luau:48-50 | SRC_RENDERER_PARTS lists only 3 of 12 `src/render/` modules; rect_pass/stage_content/hit_lift/foreign_content are unscanned.
ARCH-21 | Low | Medium | docs/reference/api.md:3844-3845 | The `contribution` entry sends extension authors to `src/input/contribution.luau` for the bundle's full field list — internals as documentation.
ARCH-22 | Low | Medium | src/controls/path_shapes.luau (via Facet.pathShapes) | `MAX_CONTROL_POINTS` and `contribution.PROP` are public members with no api.md entry (consequence of ARCH-7).
ARCH-23 | Low | Medium | src/layout/text_metrics.luau:118,188 | Process-global mutable `calibration`/`exactWidths` caches in a module documented as pure; shared across every core/surface with no owner or reset seam.
ARCH-24 | Low | Medium | src/motion/classes.luau:54; src/motion/curves.luau:218 | `registerClass`/`registerCurve` write process-global registries; two independent Facet consumers in one VM silently share and can collide.
ARCH-25 | Low | Low | src/render/authority.luau:198 vs src/client/screen_target.luau:1747 | The only `host`-authority assert lives in the engine adapter, not the renderer, weakening "the renderer asserts every write".
ARCH-26 | Low | Low | tools/lune/scaffold.luau:443 | `scaffold control` edits `src/init.luau` and generates in-repo `../src/...` requires, so the seam it scaffolds is in-repo-only despite constitution §1's "written outside the library".
