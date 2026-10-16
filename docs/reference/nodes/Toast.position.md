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
  native glyph rendering). `false` only slides.

At most three toasts show on an edge and eight wait. The queue is in priority
order, first in first out within a priority. A more urgent toast replaces the
weakest showing one, but only after that toast's read floor. At the cap the
least urgent waiting toast retires with `capacity`; a showing toast never does.

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
