# Facet stabilization pass — 2026-09-07

Branch: `facet-stabilization` (from main 5a9338d1). Owner: this session.
Working tiers: `tools/verify.sh affected|fast` while iterating; the proposal
tier is `tools/verify.sh full` plus Studio drives and rebuilt places.

## Streams and acceptance criteria

### A. HUD chrome-sequence regression (root cause, not a reset)
Sequence: landscape → URL bar on → portrait → URL bar off → landscape.
Observed (`hud.mov`, repo root): restored landscape loses score, feed, tasks,
weapon cards and the round pill while the probe says 14/14 rows painting.
- [ ] A1 Headless reproduction of the sequence fails BEFORE the fix, in a spec
      that compares the restored landscape to a clean landscape mount
      (node set, rects, visibility, focus ring, action bindings).
- [ ] A2 Root cause named in the commit message: which invalidation / state /
      layout authority kept stale state, and why the prior fix could not close it.
- [ ] A3 Fix is in the authority that owns the state — no sequence-specific reset,
      no hidden-symptom patch.
- [ ] A4 Coverage: the exact sequence; URL bar on/off in every position of the
      sequence; N≥3 repeated rotations; teardown (dispose after the sequence
      leaves zero live nodes / connections).
- [ ] A5 `tools/verify.sh fast` green; hud_* specs green.

### B. Showcase fixes
- [ ] B1 Classic Desktop: selected chip/row text is white on the dark-blue
      selection surface (theme role, not a literal) — headless GetStyled check.
- [ ] B2 The screen-anchored HUD's Freeze debug card is gone from the shipped
      scenario; the probe machinery it drove is removed or moved behind a
      non-shipped switch; no dangling copy/ids.
- [ ] B3 The dedicated Settings button is removed; Settings is reached only
      through the Demos/Settings toggle in the demo menu; focus/gamepad
      bindings (LB/RB) still reach both sections.
- [ ] B4 Under Facet Neutral the demo list opens with "Demos" selected and
      painted in the accent blue (selected state present at first paint, not
      after an interaction).
- [ ] B5 Existing showcase specs updated; new checks fail before, pass after.

### C. Inherited `tint` and inherited disabled subtrees
- [ ] C1 One authority each: tint inherits through the environment/style path
      (theme roles, reactive, no hard-coded Color3); disabled inherits through
      the same channel focus/input already read (`enabled`).
- [ ] C2 Precedence defined and tested: nearest ancestor wins over farther;
      a descendant's own `enabled=false` cannot be re-enabled by an ancestor;
      a descendant's own `tint` overrides an inherited tint (documented rule).
- [ ] C3 Disabled subtree blocks activation, focus (Tab/pad/arrows), pointer,
      touch, keyboard, gamepad, and secondary actions (row actions / menus);
      focus leaving a subtree that becomes disabled restores to a legal node.
- [ ] C4 Disabled visuals are themed (disabled role/state), applied to
      non-control descendants where the theme defines it; reactive both ways.
- [ ] C5 No duplicate state channel; no per-control workaround; schema, class
      contract, `docs/reference/api.md`, guide catalog, boundary check,
      types check all updated.
- [ ] C6 Themes: at least Facet Neutral + one reference package prove the
      tint/disabled paint through the sheet, not the node.

### D. Showcase demonstration
- [ ] D1 Nested inheritance, override, dynamic toggle, focus restoration,
      lifecycle cleanup shown in the gallery (existing example where natural).
- [ ] D2 Works under pointer, touch, gamepad paradigms; scenario registered;
      docs/registration checks pass.

### E. Lockstep, docs, verification
- [ ] E1 Rascal Rally: compatibility test/evidence updated for any changed
      contract; RR suite green.
- [ ] E2 CHANGELOG, `Facet.VERSION`, deprecations as needed; api.md current.
- [ ] E3 `tools/package.sh build && status` pass; never publish.
- [ ] E4 `tools/verify.sh full` PASS; Studio drives/canaries; places rebuilt;
      before/after perf checks within budget (investigate, never rebase).
- [ ] E5 Unrelated defects reported, not fixed.
