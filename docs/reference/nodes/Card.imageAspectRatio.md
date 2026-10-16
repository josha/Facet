# Card.imageAspectRatio

- The artwork frame is as wide as the card. Its height is the measured card
  width divided by `imageAspectRatio`.
- `artwork` is a factory that returns a GuiObject, such as a `Stage` preview.
  The card mounts it once in the artwork frame and sizes it to fill the frame. With `image`, the image shows under the
  artwork. The card owns the artwork and releases it with the card.
- With `onActivate`, the body is a Button. `onActivate(input)` receives the
  native input of the activation, or `nil`. Without it, the body is plain
  artwork and text. The primary action is a Button. `menu` is a Menu behind a
  More trigger (`menu.label`, default "More"). The body, the primary action
  and More are sibling targets under a root that is not a Button. Thus a press
  runs exactly one of them. `enabled = false` applies to all three.
- A late value of `title` or `image` that is empty or of the wrong type keeps
  the last legal paint, with a warning and a diagnostic line.
- `always` keeps the action plate visible. `automatic` (the default) shows it
  at rest when the session has touch (`TouchEnabled` or a touch
  `PreferredInput`), and otherwise while the card is engaged. The card is
  engaged while the pointer is in it, the selection is in it, a press is held
  on one of its actions, its menu is open, its actions are entered, or the
  `browseTarget` is selected. A card with no body action and no
  `browseTarget` has no stop of its own, so it shows its actions at rest.
- The plate is a Frame directly below the body in the card's own layout.
  With `automatic`, it paints a panel surface under the action row. The
  primary action fills the row and More is an icon button at its end.
  A card with no primary action and no menu does not paint an empty plate. With
  `always`, the row has no plate and sits a small gap below the body. The plate
  is always laid out, so the card size never changes and the siblings never move.
  At rest it is transparent and not `Interactable`, so its actions take no
  press and no selection. The fade uses a Compose tween, so a quick reversal
  continues from the current value. Reduced motion shows and hides it
  immediately.
- While engaged, the card's `UIScale` named `Lift` rises to 1.04 on a spring,
  and a body Button shows its `UIShadow` named `LiftShadow`. A card with no
  body action has no shadow. When `PreferredInput` is `Touch`, the card does
  not lift and shows no shadow: a tap on the body, the primary action or More
  gives only the press paint of that control. The lift is for pointer hover,
  selection and a held mouse press. The scale is paint only: the artwork height
  uses the width without the lift, so the card size does not change. When no `Position` is supplied, the card uses its native `AnchorPoint`
  to grow evenly around its centre without integer position steps. Keep gutters of at least half the scaled growth
  around each card. Reduced motion keeps only the shadow.
  When a `browseTarget` exists, the card puts a `UIScale` named `CardLift` with
  the same scale on it, so the selection ring grows with the card.
