### Toggle

`value` is a boolean source. `onChange(next)` requests a new value. Without it,
the control updates the writable cell. `presentation` is `switch`, `checkbox` or
`button`. The checkbox presentation supports `mixed`. A read-only `value` or
`mixed` source requires `onChange`. `indicatorPosition` is
`leading` or `trailing`. A checkbox with `controlSize` sizes its box to the
icon size of the rung plus the `xs` space. Without `controlSize` the box is 24
pixels. The label, row, hint, enabled and common button styling
options apply.

`controlSize` also sizes the switch. The track is the rung `iconSize` plus 4
pixels high, its width scales 38 by 24 to that height, and the knob is 6 pixels
smaller than the track. Without `controlSize`, the switch is 38 by 24 pixels.

A switch Toggle's knob glides between its ends on a critically damped spring
(`motion.springs.control`, a 0.25 second period) while the track colour
fades, and a change mid-flight turns it without a jump. Below motion level
`"normal"` the knob lands at once.

A switch or checkbox Toggle paints no plate and takes no `control` art from a
theme package. A settings row (a Toggle with `row`, `hint` or `icon`) has the
`facet-toggle-settings` tag. Its horizontal padding is the padding of a
Button, so its content lines up with Button rows in each theme. The row shows
`icon` or `row.icon` first. A Toggle with `row` puts its switch last unless
`indicatorPosition` is `leading`, so its label starts where the label of a
Button row starts.

The checked mark of a switch and a checkbox uses the `selection` color of the
palette, and its knob or tick uses `onSelection`. Without them, it uses
`accent` and `onAccent`. An off switch's knob also uses `onSelection`
when it has at least 3:1 contrast on the `control` track. Otherwise the
knob uses `content`, so the off switch stays visible.

`appearance = "plain"` makes a switch or checkbox a bare row. The row does not
get the `facet-selected` tag, so only the mark shows the state. The row has the
`facet-toggle-plain` tag and no settings padding. Use it for a checkbox in a
toolbar. The `button` presentation refuses `plain`, because its plate shows the
state. `textSize` is a type role or a number of pixels for the label, as on
Button. The default is the `control` role.

`disclose = true` lets a player read the whole label of a Toggle whose label
truncates, as on Button: the label shows in the `Disclosure` panel while the
engine reports that the painted label does not fit (`TextFits` of the label
itself on a settings row). Without `disclose` the Toggle shows no panel.
