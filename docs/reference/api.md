# Facet documentation

Start with one task recipe. Open a card or option node only for a missing detail.
Never reread a node already in context.

Query: `lute run tools/facet docs <path>`. Search paths: `docs --search TEXT`.
Each call returns one bounded node. Link labels below are query paths.

| Player task | Recipe |
| --- | --- |
| Read currency and use HUD actions | [Tasks.hud](nodes/Tasks.hud.md) |
| Browse and buy shop items | [Tasks.shop](nodes/Tasks.shop.md) |
| Open modal details with Close and Back | [Tasks.sheet](nodes/Tasks.sheet.md) |
| Change pages or segmented choices | [Tasks.tabs](nodes/Tasks.tabs.md) |
| Set the game theme | [Tasks.theme](nodes/Tasks.theme.md) |
| Read progress and timers | [Tasks.progress](nodes/Tasks.progress.md) |
| Read toasts and notices | [Tasks.notices](nodes/Tasks.notices.md) |
| Change settings | [Tasks.settings](nodes/Tasks.settings.md) |
| Use gamepad and touch-safe layout | [Tasks.safe-layout](nodes/Tasks.safe-layout.md) |

Browse [Tasks](nodes/Tasks.md), [Controls](nodes/Controls.md),
[Reference](nodes/Reference.md) or [Themes.index](nodes/Themes.index.md).
Control cards show small calls. Reference links lead to complete option groups.
Use `docs Sheet.card`, then `docs Sheet.detents` only if that detail is missing.
Use `project [directory]` to find application files.
