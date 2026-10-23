# VirtualList-and-VirtualGrid.from

Use these controls for data rows or tiles that need selection, reordering or
collection focus, even when the data is small. They also window large or
unbounded collections. A Button may supply row content while the collection
owns the interaction. See [choosing collections](../../guide/choosing-controls.md#interactive-collections)
and the shared [editable collection contract](Editable-collections.md).

Required: `from` (an array, readable or body) and
`render(current, placement, key)`. `key` is a function `(item, index) -> key`
or the name of the field that holds the identity, for example `key = "id"`. A
field name gives `tostring(item[field])` as the key. If you omit `key`, Compose
uses item identity. Render receives readables for the current item and its
placement, and returns native content. Keep durable row state outside that
render owner.

A retained key can receive a new record. Read `current` in property functions
for the title, price, eligibility and other changing fields. Read
`current:peek()` when an action starts. Do not capture the first record with
`local item = current:peek()` and use that snapshot in later property bindings.
An identity key can be captured; a wallet, ownership map or item record can
change.

Derive a filtered `from` array from the current query, category and ownership
cells. Do not change keys when a filter changes. Empty the array for no
matches, show a clear result message and keep a route to clear the filter.
Test empty and refill on the same mounted collection. For a small collection
inside a Sheet, use the [content-sized pattern](VirtualList-and-VirtualGrid.sizing.md);
for direct card actions, use [Card.browseTarget](Card.browseTarget.md).
