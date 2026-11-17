# Toast.position

Toast.position option values and behavior.

- `position`: `top` (the default) or `bottom`, the edge that the stack docks
  to. Each edge of a layer has its own stack. The stack docks clear of the
  app's reserved chrome on that edge: the deepest `FacetInsetTop` or
  `FacetInsetBottom` reservation of its layer and of every enabled sibling
  ScreenGui (a TabView bottom bar, a visible toast with an action, an affixed
  Notice), read each frame while a toast shows.
- `width`: `fill` (the default) spans the layer less 16 pixels on each side.
  `hug` fits the content, centred, up to 560 pixels, and wraps longer text.
  Width and placement use the configured overlay parent when one is supplied.
- `fade`: by default the row fades in and out as it slides (the fade draws
  the row through a CanvasGroup only while it runs, so settled text keeps
  native glyph rendering). `false` disables the fade.

At most three toasts show on an edge and eight wait. The queue is in priority
order, first in first out within a priority. A more urgent toast replaces the
weakest showing one, but only after that toast's read floor. At the cap the
least urgent waiting toast retires with `capacity`; a showing toast never does.

`Facet.app` and `Facet.controls` accept these passive Toast settings:

- `toastParent`: a native GuiBase2d or a readable GuiBase2d-or-nil value. When
  supplied, passive toasts wait for this host instead of using the screen.
  Keep the host Instance stable while notices exist; resize its native bounds
  for layout changes. Other overlays and action toasts keep their normal host.
  Rows fade in place so entrance and exit do not cross the host's bounds.
- `toastMaxVisible`: a positive integer, default `3`, for each passive edge.
  Use `1` when the host has room for only one notice. Content must still fit;
  this limit does not clip or shrink a row.
- `toastQueueCapacity`: a positive integer, default `8`, for waiting notices
  on each passive edge. `math.huge` removes capacity eviction. Same-key
  replacement and priority preemption still apply. Action toasts keep their
  normal queue capacity.
- `toastPaused`: a readable boolean, default `false`. While true, passive
  reading time stops. The current row remains visible and waiting rows retain
  their place. Action toasts keep their own focus and hover pause behavior.

The row is input-transparent: it is neither `Active` nor `Interactable`,
nothing in it is `Selectable`, it binds no input and it never takes the
selection, so the controls under it work as before. Rows (`ToastRow`) paint
at `ZIndex` 70, above the page and below a modal. A new row slides in from its
edge and fades in (unless `fade = false`), and the others slide to close the slot a
retired row leaves. Under reduced motion the rows are placed at once, for the
same times in the same order.

With an action:

- `action`: `{ label, onActivate }`. Unbound, it runs and retires the row
  with `action`. Bound, it runs once and the row leaves when the fact is
  false.
- `closeButton`: `true` (the default) or `false`.
