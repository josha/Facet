### TabView

<!-- aliases: TabView | tabview -->

Open one option group below. Each group gives part of this contract.

For native vector art, a tab can supply `glyph = function(): GuiObject` instead
of an image `icon`. It works with icon-only tabs and labelled sidebars. The callback runs in the tab's
Compose owner. Button places it in the native content row and sizes it from the control icon metric;
the result can contain `UI.Path` controls in a `UI.ZStack`. Selected paths use
the active palette's `onAccent` colour. Keep `label` for the accessible name.
Badges, selection, activation and cleanup remain owned by TabView.

Open:

- [TabView.indicator](TabView.indicator.md)
- [TabView.selection](TabView.selection.md)
- [TabView.tabBottomTrack](TabView.tabBottomTrack.md)
