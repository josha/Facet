# Picker.selected

Picker requires a writable `selected` and `options`. Each option has `value` and
`label`, and an optional `id`, `icon` and `enabled`. Options can be a plain
array or a readable.
A row keeps its node and its focus when a replacement changes the option. The
row shows the new icon. When the replacement removes the icon, the row hides
it. A row that starts with no icon does not add one later.

The styles are `automatic`, `segmented`, `inline`, `radioGroup`,
`navigationLink`, `menu` and `cards`. The `automatic` style never chooses
`cards`. The `automatic` style follows the options, the
measured width and the native PreferredInput:

- If you supply `query`, it uses the navigation-link presentation.
- It uses `segmented` for four options or fewer when no option has a
  description and the measured labels and segment spacing fit in the width.
- Otherwise, for keyboard and mouse, and for touch, it uses a menu.
- For other input, it uses `inline` for six options or fewer, and a menu for
  larger sets.

A `label` shows on the leading edge of a horizontal segmented row, with the
control at its natural width on the trailing edge. With `sizing = "fill"` (the
default) each segment starts at its label's width, at least a 44 pixel target,
and the segments share the space that is left. With touch input, each horizontal
segment is at least 44 pixels high. The strip includes its top and bottom
padding outside that target, also when you supply a strip height. A strip that does not fit in the
width of the row can wrap through native `UIListLayout.Wraps`. The strip
reserves the full native `AbsoluteContentSize` height, including all lines and
its padding. A label wraps between words, and a word that cannot fit its line
ends in "…". With
`hug` the segments keep their natural widths. A segment is never wider than the
strip, or than the row of a labelled strip. A radio group or card label that does not
fit wraps inside its row. A segmented picker
takes no `query` and causes an error: a strip shows every option at once, so
use `navigationLink` or `menu` for a searchable list. The label shows above a vertical
segmented, inline or radio group control. A menu shows the label on the leading
edge of the row and the value on the trailing edge.

`onChanging(next, previous)` can return `false` to veto a change. The control
writes `selected`, and then calls `onChange(next)`. An optional writable `query`
filters the labels. The other options include `label`, `placeholder`, `axis`,
`sizing`, `iconOnly`, `textSize`, `isPresented` and `enabled`.

Picker is a field. These options apply:
