# Picker.menu

A labelled `menu` picker shows its title above a trigger at the leading edge.
With `valueAlignment = "start"`, it shows the title and the trigger on one row.
A labelled `navigationLink` shows the title and the chosen value in one row
button. It opens its list as a Popover attached to the button: a panel with
the theme plate and a tail, `controls.popup.panelWidth` wide and at most
`maxHeight` (400 pixels by default) tall, below the button's trailing end
where the value shows, and no page dim.
On a touch layer narrower than 600 pixels it opens as a sheet, the Popover's
compact route. A searchable list marks the chosen row with a check and paints no
selection plate. Opening a menu puts the selection on the chosen row.

The `cards` style shows each option as a card with the `facet-card-option`
tag: the icon, the label, the description, `meta` and `badge`. The chosen card
has the emphasis plate and is selected, so a skinned theme shows its selected
art. With `axis = "x"`, the cards wrap onto more lines.
With `required = false`, activating the chosen card again sets `selected` to
`nil`.

Options also take `meta` (secondary text), `sectionTitle` (a caption heading
above the option in menus and in stacked rows), `avatar = { name, image?,
userId? }` (an Avatar at the leading edge of a menu row, which adds no stop)
and `indicator = { status, form?, count? }` (a StatusIndicator that follows
the live option record). A menu row, a stacked row and a searchable list row
show `badge` as a `Badge` named `Count`; a segmented option keeps the count in
its words. Menu items take the same `badge`, `meta`, `avatar` and `sectionTitle`
fields, and Menu takes `maxHeight`.
