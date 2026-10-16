### Modal input

<!-- aliases: Modal input | modal-input -->

Dialog, Alert, Sheet, Popover, Menu and the other modal
surfaces put an Active full-screen root and an Active scrim button over the
layer. Thus a press, a tap or a drag under the modal does not reach the
content below.

Roblox can send a touch pan or the mouse wheel to a ScrollingFrame below the
scrim. Thus, while a modal is open, Facet sets `ScrollingEnabled = false` on
each ScrollingFrame in the same LayerCollector that is outside the top modal:

- Facet records the value of each frame before it changes the frame. When no
  modal holds the frame, Facet writes the recorded value back. A frame that
  was already `false` stays `false`.
- With stacked modals, only the ScrollingFrames of the top modal scroll. When
  the top modal closes, the modal below it scrolls again.
- A ScrollingFrame that is added to the layer while a modal is open is held
  in the same way. A held frame that leaves the layer gets its recorded value
  back at once.
- A modal gives the frames back when its exit starts, not when its exit ends.
- ScrollingFrames in a different LayerCollector do not change.
- Do not write `ScrollingEnabled` on a frame outside the modal while the modal
  is open. Facet writes the recorded value back when the modal closes.
