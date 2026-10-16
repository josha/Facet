# VirtualList-and-VirtualGrid.from

Use these controls for data rows or tiles that need selection, reordering or
collection focus, even when the data is small. They also window large or
unbounded collections. A Button may supply row content while the collection
owns the interaction. See [choosing collections](../../guide/14-choosing-controls.md#interactive-collections)
and the shared [editable collection contract](Editable-collections.md).

Required: `from` (an array, readable or body) and
`render(current, placement, key)`. `key` is a function `(item, index) -> key`
or the name of the field that holds the identity, for example `key = "id"`. A
field name gives `tostring(item[field])` as the key. If you omit `key`, Compose
uses item identity. Render receives readables for the current item and its
placement, and returns native content. Keep durable row state outside that
render owner.
