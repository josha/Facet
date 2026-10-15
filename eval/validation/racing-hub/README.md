# Racing hub reference handoff

The strong reference has one interface module for each system and a shared reference kit. One hub owns panel navigation. The server owns one wallet, part ownership, selected loadout, free crates, XP, and race rewards. The weak reference keeps the same content but removes selection support, forces large panels, and leaves purchase state stale. Its directory holds the three files that differ: `Kit.luau`, `shop/init.luau`, and `round-hud/init.luau`; `validation/games.json` reads the other files from `strong`.

The starter and the strong overlay build with Rojo. The corpus check, formatting check, both type solvers, and both suite plans are static evidence. They do not prove live input, geometry, captures, or a strong versus weak result. No Studio check has run for these references.

The base scenario has 134 cases on each of the five devices. The shop, garage, and settings turns each have 137. The scoreboard turn has 136. Each turn includes the entire base scenario. There are 39 base audited screens per device. The turns add their own audited screens.

The reference uses native `UIListLayout`, `UIGridLayout`, `UIPadding`, `ScrollingFrame`, `GuiService.SelectedObject`, `GuiObject.SelectionGroup`, and `ContextActionService.BindActionAtPriority`. The engine API and the existing reference kit cover layout, selection, and input. The Compose runtime and component APIs were checked. They are not used in the plain reference because the reference must work without a UI package. The score code uses the public Verify interface dump and context APIs. It adds game-specific observations and uses the existing play host for execution and reports.

When Studio is available, run from the repository root:

```sh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1
```

For an existing interface workspace, run all devices:

```sh
lute run eval/tasks/racing-hub/hidden/play.luau --workspace <workspace> --outputs <evidence>/out --captures <evidence>/captures --report <evidence>/report.json --run racing-hub-manual --scores <evidence>/scores.json --devices desktop,phone-portrait,phone-landscape,tablet,console
```

Use each turn's `hidden/play.luau` for its completed workspace. Review the Verify report, each named screen, the dumps, and `coherence.json`. Check the weak failures as well as the strong results before recording a calibration result.

See [the racing world handoff](../scenery.md) for the playable place, controls, deterministic scenarios, cost model, and the new HUD calibration fault.
