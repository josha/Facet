# Geometric patterns

`src/design/patterns` is the pure geometry-planning entry point used by the 3D editor and host adapters.
`rows(properties)` returns stable `id`, display `name`, `position`, `rotation`, `size` and `color` records. It creates no
instances or reactive resources. `fields` describes those records for Design iteration templates.

`mode` is `linear`, `grid` or `radial`. Linear patterns use `count` and a `spacing` vector. Radial
patterns use `count` and `radius`. Grids use positive integer `columns`/`rows` and a centered `extent`.
`order` selects row or column traversal. `fit = true` divides the grid span into cells, subtracts
`gap` from each cell and retains the authored Y size. Patterns contain at most 500 instances.

`position` and degree `rotation` place the pattern. `size` and hex or three-channel RGB `color` provide row defaults.
Up to 32 `variants` repeat position offsets, rotations, sizes, colors and display names. Display names
can preserve authored labels while generated ids retain their stable index identity. `variantBy = "sum"` uses
the grid column plus row; its default uses the instance index. `namePattern` accepts one `%d`, or
two for grid column/row names. `indexOrigin` defaults to one. Invalid values fail explicitly.

Radial `phase` is an optional start angle in radians. When supplied, each angle is `phase + index *
(2 * pi / count)`, preserving a host's exact angular construction order. Omitting it retains the
ordinary unshifted radial arithmetic. Integer name placeholders may specify one digit of padding,
such as `%02d`.

Variants may set `visible = false`. Rows retain their stable ids and geometry, while a template can
condition its geometry on the boolean `visible` field. A Fragment template with a conditional child
authors sparse crown stones or missing members without expanding a complete radial pattern into
literal coordinates. Visibility defaults to true.

The 3D `Pattern` control authors one `render` template with these parameters. Its membership inputs
are values and rebuild with the document. Host adapters may flatten the authoring group while
retaining row order. Select the group to translate the whole pattern; position-bound template
instances preserve their binding when selected with the gizmo.

Use a `Fragment` as the Array or Pattern template when each repeated item contains several sibling
parts. A Fragment has children, a layer name and optional position, rotation or ordered transform
operations. Its transform composes before each child's authored or row-bound pose. The editor previews
it as an organizational Model; host adapters flatten it without creating a game instance, preserving
part order and existing hierarchy. This keeps a shared construction basis editable without changing
the game's model hierarchy. The preview's pivot marker is editor-only.
Use Model or Folder when the grouping itself belongs in the built instance tree.
