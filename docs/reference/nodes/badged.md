### badged

<!-- aliases: badged | badged -->

`UI.badged(host, value, options?) -> Frame` puts a dot or a count on the
corner of a host, such as a Button, an icon Button or an Avatar. It returns a
Frame named `<host name>+badge` that hugs the host and takes its
`LayoutOrder`. A zero-size `Corner` frame sits at the top-right corner of the
host, or at the top-left when `options.direction` is `"rtl"`. It holds a Badge named
`CornerBadge`, centred on the corner. The Corner frame has no size, so the host
keeps its layout box, its hit area and its selection. `value` is a string, a
whole count (above 99 shows "99+"), `true` for a dot (a `StatusIndicator` named `CornerDot`, not a text pill), or a readable of one.
`nil`, `false`, `0` and `""` show nothing. A TabView tab or a segmented Picker
option with an `icon` shows its `badge` on the corner of the icon. A text tab or
option keeps the count in its words.
`Facet.BadgedOptions` types `options`.
`options.status` is a status or a readable of one. It sets the color of the dot
and of the count. Without it, the seal uses `error`, the danger color of the
theme, so it shows on sky, on terrain and on a Button that has the color of the
Badge plate.
The seal paints past the host by half its size, so give a host at a clipping
edge that much room.

Give `badged` a dot or a count. Use a string only for a short count, such as
`"1.2K"`. Put a word, such as Ready or New, in the host label, for example
`label = "Daily · Ready"`, and use `true` for the dot. The seal is centred on
the corner, so a word covers the next control in a tight stack.
