# Facet documentation

Before UI work, open [Design.guide](Design.guide.md) and read the required
design foundations and relevant chapters in the use-facet skill.

Open every task recipe that matches a part of your screen. For a HUD with a
shop, open Tasks.hud and Tasks.shop. Open a card or option node only for a missing detail.
Never reread a node already in context.

Query: `lute run tools/facet docs <path>`. Search paths: `docs --search TEXT`.
Each call returns one bounded node. Link labels below are query paths.

| Player task | Recipe |
| --- | --- |
| Read currency and use HUD actions | [Tasks.hud](Tasks.hud.md) |
| Browse and buy shop items | [Tasks.shop](Tasks.shop.md) |
| Open modal details with dismissal and child-page Back | [Tasks.sheet](Tasks.sheet.md) |
| Change pages or segmented choices | [Tasks.tabs](Tasks.tabs.md) |
| Set the game theme | [Tasks.theme](Tasks.theme.md) |
| Read progress and timers | [Tasks.progress](Tasks.progress.md) |
| Read toasts and notices | [Tasks.notices](Tasks.notices.md) |
| Change settings | [Tasks.settings](Tasks.settings.md) |
| Use gamepad and touch-safe layout | [Tasks.safe-layout](Tasks.safe-layout.md) |

Browse [Tasks](Tasks.md), [Controls](Controls.md),
[Reference](Reference.md) or [Themes.index](Themes.index.md).
Control cards show small calls. Reference links lead to complete option groups.
Use `docs Sheet.card`, then `docs Sheet.detents` only if that detail is missing.
Use `project [directory]` to find application files.
Use [Tools.verify](Tools.verify.md) for device checks, expected duration,
capture directories and the verdict. Wait for the command to finish.
