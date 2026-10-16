# Selection.SelectedObject

Selection.SelectedObject option values and behavior.

- Entry. When nothing is selected, the first D-pad press selects the first
  control of the active screen in layout order. An open modal is the active
  screen. The press does not move a selection that already exists.
- Presentation. A modal presented while a control is selected, or while a
  gamepad is the preferred input, selects its first control. It waits until
  the surface is shown, so it never selects a hidden control.
- Leaving. A Facet presenter hands the selection back to its anchor or opener
  as it starts to leave. A game's own panel is not a presenter: when its
  buttons stop being selectable before it is gone, the engine moves the
  selection to another control on the page. Set `SelectedObject` yourself
  first, or present the panel through `UI.responder` or a modal.
- Tab and Shift+Tab. Tab selects the next control in layout order. In a
  collection that is row order (each row's `LayoutOrder` is its index), even
  after scrolling has recycled the row containers.
  Shift+Tab selects the previous control. The walk wraps at both ends. It
  stays inside an open modal. It skips hidden, disabled and removed controls,
  and scroll containers, except one that is itself a documented stop (an
  overflowing Dialog body, a Collection or Pagination root).
  The native `SelectionOrder` of a control is its traversal tier: a lower
  value comes first, and within a tier layout order wins (the `tabindex`
  model). The `FacetTraversal` input context is a child of `inputParent`, or
  of the local `PlayerGui` when you do not set `inputParent`. It is enabled
  only while `UserInputService.KeyboardEnabled` is true, so a phone binds
  nothing. The engine keeps Tab and Escape from input actions, so Facet also
  reads both keys from `UserInputService.InputBegan` and runs the one enabled
  Facet action with the highest priority for each press (Tab: traversal;
  Escape: the top modal's Back). A real Escape still opens the Roblox menu as
  well; the engine reserves it. Closing Facet's top modal on the same press is
  deliberate, and an Escape while the Roblox menu is already open closes
  nothing in Facet. Escape does nothing in Facet while a TextBox has the
  keyboard, and Tab leaves only a Facet text field (a game's own box or the
  chat keeps it). Tab with Ctrl, Alt or Meta held does nothing. With several
  `Facet.controls` sets on one `UserInputService`, one press runs one action
  across all of them: the highest priority, then the one whose control holds
  the selection, then the newest. The factory option `keyboardNavigation = false` disables it for a
  HUD over live gameplay, where Tab belongs to the game. A passive
  [responder](responder.md) binds it only while it is engaged, and one with
  `traversalWrap = false` stops the walk at its ends.
