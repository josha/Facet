### Callout

Callout requires a native `anchor` with a separate parent and `onRetire`. The
callout borrows the anchor. When a native ancestor of the anchor is hidden, the
callout is suspended. `seen`, `sessions`, `afterSessions`, `featureUsed` and
priority set eligibility and queue order. Each fact can be a value, a readable
or a function of `use`. Retirement is delivered once. A callout is contextual
teaching attached to a control. It is not a second application presenter.
Without an authored `edge`, a callout prefers above its anchor on touch and
below for other input. The default follows live input changes.
`edge = "top"` puts the callout above the anchor. If there is no room above
and there is room below, the callout goes below the anchor. The callout
scales and fades from the edge nearest to its anchor. See [Motion](Motion.md).
A tail points from the plate to the centre of the anchor.
The plate stays inside its layer by the `space.s` step of the theme on each
side. The step follows a live theme change. The layer is the safe area of the
ScreenGui, so a device safe inset adds to the step.
A callout and a help plate paint above a toast with an action and below a presented modal.

The plate parts are optional, but the plate must show something:

- `content`: an Instance or a factory.
- `title`: a string or a bound string. It shows as a heading.
- `media`: `{ image, aspectRatio | height, scaleMode?, background? }`.
- `steps`: `{ index, count }`. It shows `index of count`.
- `actions`: one or two `{ id, label, role?, enabled?, busy?, onActivate }`.
  They replace the bottom `Got it` button. A press retires the plate with the
  reason `action`, once, also when `onActivate` fails. A disabled or busy
  action does not run.
- `closeButton`: `true` adds a close control at the top. It retires the plate
  with the reason `dismissed`.

A failure in `onShow` does not stop the plate. The failure goes to the
`onError` factory option, or to a warning.
