# Dialog.title

- `title`, `actionLabel`: strings or bound strings. An empty bound title hides
  until it has text.
- `content`: a factory for the one body. The body scrolls between the pinned
  header, hero, action label and actions.
- `hero`: the shared media shape.
- `actionLayout`: `automatic`, `row` or `stacked`. `automatic` puts two short
  actions in a row and stacks three or more. A row that cannot show the full
  labels also stacks. The row gives each action an equal share of its width,
  so the longest label decides. The actions of an Alert, a Dialog and a Sheet
  also stack on a ten-foot screen (`ctx.tenFoot()`) or at the `Larger` and
  `Largest` preferred text sizes, each full width.
- `width`: `automatic`, `narrow` or `wide`.
- `contentSelectable`: `true` (the default) makes an overflowing body one
  selectable stop. With the selection on it, Up and Down scroll the body. At
  each end the selection moves on.

A dialog needs a title, content, a hero, an action label or actions. The
height is the layer height less the keyboard height and the margins. When the
pinned regions and a short body do not fit, every region moves into one
scrolling column named `Room`. The panel is a Frame. The complete panel
fades in at its final size with its scrim. See [Motion](Motion.md).
