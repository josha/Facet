# TabView.tabBottomTrack

| Group | Fields and neutral values |
| --- | --- |
| `tabBottomTrack` | `height = 64`, `sideInset = 16`, `bottomInset = 12`, `radius = 20`, `contentGap = 8` |
| `tabRailTrack` | `sideInset = 8`, `topInset = 8`, `bottomInset = 8`, `radius = 16` |
| `tabMark` | `width = 20`, `height = 4`, `gap = 4`, `radius = 2` |
| `tabRailSelection` | `insetX = 8`, `insetY = 4`, `radius = 8` |

These metrics only change the floating track or mark options. The existing
track and selection defaults keep their geometry. Colours use the existing
`facet-tab-plate` and `facet-selection-indicator` StyleSheet roles.

A tab's `badgeAnchor` can be `"topLeading"`, `"topTrailing"`,
`"bottomLeading"` or `"bottomTrailing"`. It positions the badge on the icon.
The default is `"topTrailing"`. Without an icon the count stays beside the
label. The anchor can be a readable.

```lua
UI.TabView {
    selection = selected,
    placement = "bottomBar",
    track = "floating",
    indicator = "mark",
    labelPlacement = "belowIcon",
    controlSize = "compact",
    tabs = {
        { id = "games", label = "Games", icon = "view.grid", badge = 1,
          badgeAnchor = "topLeading", content = gamesPage },
        { id = "profile", label = "Profile", icon = "person", content = profilePage },
    },
}
```

`controlSize` (`xsmall`, `compact`, `regular` or `large`, or a readable) is the
size step of the tabs. Each tab is `controlSizes.<step>.height` high and has the
`controlSize` attribute. The strip stays `targetSizes.minimum` high (44
pixels, 66 at ten feet) and centres the tabs in it. Without `controlSize`,
each tab is that high too.

A TabView that is built inside the page of another TabView is nested, also
when a branch of that page builds it later. A nested TabView uses a top band.
An outer TabView with `placement = "none"` shows no bar, so a TabView in its
page is not nested and takes the full home policy.

A page change uses a native crossfade. The default is
`transition = { seconds = 0.2, ease = Compose.easing.outQuad }`. Supply other
direct Compose tween options to change it. Use `false` to disable motion. Named
Facet transition presets do not exist. The first page shows without motion.
