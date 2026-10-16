## Layout

<!-- aliases: Layout | layout -->

The layout constructors make ordinary native containers. A container is a
`Frame` or a `ScrollingFrame` with a `UIListLayout` or a `UIGridLayout`, and a
`UIPadding` when you set `padding`. Roblox does the layout. Facet adds no
solver and no measurement pass. Each constructor accepts the native properties
of its root, and a native property that you set replaces the default value.

Write the children as dense numeric children. The container sets the
`LayoutOrder` of each child to its position in the list. Nodes that a
`Compose.show` or `Compose.keyed` child adds sit at the position of that child,
in the directive's own order: a keyed child keeps its rows in list order. A
`LayoutOrder` that you set in a row orders it within that child. When the list
has such a child, the positions are spaced by 65536 (position 2 is 131072).

```luau
local sound = Compose.cell(true)
local function save() print("Saved") end
return UI.Screen "Settings" {
    gap = "s",
    UI.Text { text = "Settings", textRole = "title" },
    UI.ScrollView "Page" {
        gap = "s",
        UI.Toggle { label = "Sound", value = sound },
        UI.Button { label = "Save", onActivate = save },
    },
}
```

Open:

- [AdaptiveStack.reference](AdaptiveStack.reference.md)
- [Composition.reference](Composition.reference.md)
- [Divider.reference](Divider.reference.md)
- [ErrorBoundary.reference](ErrorBoundary.reference.md)
- [Grid.reference](Grid.reference.md)
- [Layout-options](Layout-options.md)
- [Screen.reference](Screen.reference.md)
- [ScrollView.reference](ScrollView.reference.md)
- [Spacer.reference](Spacer.reference.md)
- [VStack-and-HStack](VStack-and-HStack.md)
- [ViewThatFits.reference](ViewThatFits.reference.md)
- [ZStack.reference](ZStack.reference.md)
- [fill](fill.md)
- [scrollTo-and-scrollToVisible](scrollTo-and-scrollToVisible.md)
