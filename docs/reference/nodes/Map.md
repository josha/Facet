# Facet documentation

Before UI work, open [Design.guide](Design.guide.md) and read the required
design foundations and relevant chapters in the use-facet skill.

Read the recipe for the main structure. Add another recipe only for a missing
pattern, then reuse it across similar pages. For a HUD with a shop, start with
Tasks.hud and Tasks.shop. Open a card or option node only for a missing detail.
Never reread a node already in context.

In Studio, read `ServerStorage.FacetDocs.docs.reference.nodes["<path>.md"].Value`
in Edit mode. A control starts at `<Control>.card`; its options are
`<Control>.props`. Link labels below are paths. Read one node at a time.
With shell access, use `lute run tools/facet docs <path>` or `docs --search TEXT`.

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
| Preview an object or editable appearance | [Stage.card](Stage.card.md) |
| Guide a player through live actions | [Callout.card](Callout.card.md) |

Browse [Tasks](Tasks.md), [Controls](Controls.md),
[Reference](Reference.md) or [Themes.index](Themes.index.md).
Control cards show small calls. Reference links lead to complete option groups.
Read `Sheet.card`, then `Sheet.detents` only if that detail is missing.
Check with Studio Play, input, Output, and captures. Filesystem projects can
also use [Tools.verify](Tools.verify.md). Wait for a check to finish.
