# DisclosureGroup-and-CollapsibleView.appearance

DisclosureGroup `appearance` is `plain` (the default), `contained`, `divided`
or `outline`. The root has the `facet-disclosure-<appearance>` tag. `outline`
is a tree row: the header starts its chevron and label at the leading edge, it
does not get the `facet-selected` tag while the group is expanded, and it keeps
focus and activation. `textSize` is a type role or a
number of pixels for the header label, as on Button. The content sits 8 pixels
below the header and is inset on both sides by the control's horizontal padding
(`controlSizes.regular.paddingX`, 12 in Neutral), so it lines up with the header
label; an `outline` group has no side inset. `indent` is a spacing step (`xs`,
`s`, `m`, `l` or `xl`) or a number of pixels. It replaces the left inset of
`RevealFade`, so nested groups read as an outline.
