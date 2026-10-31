# Facet documentation

Use [Design.guide](Design.guide.md) for task-based design routes.

Read the recipe for your task. Follow detail when needed.
Do not reread nodes in context.

In Studio Edit mode, read
`ServerStorage.FacetDocs.docs.reference.nodes["<path>.md"].Value`.
Read `<Control>.card` when a screen first needs that control, then
`<Control>.props` for options. [Controls](Controls.md) names every card; do not
list the folder.
With shell access, use `lute run tools/facet docs <path>` or `docs --search TEXT`.

| Player task | Recipe |
| --- | --- |
| Enter from a world-visible lobby | [Tasks.hub](Tasks.hub.md) |
| Track an objective and use its command | [Tasks.hud](Tasks.hud.md) |
| Show a minimap and open a larger map | [Tasks.minimap](Tasks.minimap.md) |
| Browse objects and selected detail | [Tasks.collection-detail](Tasks.collection-detail.md) |
| Inspect art beside a decision | [Tasks.inspect](Tasks.inspect.md) |
| Open a destination from gameplay and return | [Tasks.pages](Tasks.pages.md) |
| Open a short contextual task | [Tasks.sheet](Tasks.sheet.md) |
| Change pages or segmented choices | [Tasks.tabs](Tasks.tabs.md) |
| Set the game theme | [Tasks.theme](Tasks.theme.md) |
| Read progress and timers | [Tasks.progress](Tasks.progress.md) |
| Read toasts and notices | [Tasks.notices](Tasks.notices.md) |
| Change settings | [Tasks.settings](Tasks.settings.md) |
| Use gamepad and touch-safe layout | [Tasks.safe-layout](Tasks.safe-layout.md) |
| Preview an object or editable appearance | [Stage.card](Stage.card.md) |
| Guide a player through live actions | [Callout.card](Callout.card.md) |
| Author a screen as a design document | [Design-library](Design-library.md) |

Browse [Tasks](Tasks.md), [Controls](Controls.md),
[Reference](Reference.md) or [Themes.index](Themes.index.md).
Control cards show small calls. Reference links lead to complete option groups.
Check with Studio Play, input, Output, and captures. Filesystem projects can
also use [Tools.verify](Tools.verify.md). Wait for a check to finish.
