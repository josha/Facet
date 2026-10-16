# Motion.Fade

Motion.Fade option values and behavior.

- A modal panel keeps its CanvasGroup named `Fade` for its complete lifetime.
  Its children do not change parent at the end of an entrance. Alert, Dialog,
  Popover and floating Menu use a cross-fade at their final size. This avoids
  live text measurement changes from UIScale. Sheet keeps its travel.
- Other fades use a CanvasGroup named `Fade` only while they run. The group holds
  the faded node's children. When the fade ends, the children move back and
  the group is removed, so settled text and art are never rasterised. A
  `UIGradient` named `FadePaint` fades the node's own paint. A new group
  draws one frame almost transparent before the fade shows it, and the node's
  own paint waits for that frame, so the panel and its text appear together.
- A faded node also carries a `UIStroke` named `FadeStroke` (tag
  `facet-fade-stroke`) with its own `FadePaint` gradient. It is disabled at
  rest. Every theme stroke rule `S::UIStroke` has a twin
  `S > .facet-fade-stroke` with the same properties, so the stroke resolves
  exactly like the node's theme stroke. While a fade runs the node is tagged
  `facet-fading`: its `::UIStroke` is disabled and `FadeStroke` is enabled in
  the same style pass, so the outline fades with the fill and the content. A
  game rule on `S::UIStroke` gets the same twin. `FindFirstChildWhichIsA("UIStroke")`
  on a faded node returns `FadeStroke`.
- A presentation's fade leads its travel. An Alert, Dialog, Popover, Menu,
  Callout, Button `help` plate and Sheet (its scrim) is fully opaque once 60
  percent of its entrance time has run (`presentFadeIn`) and fully clear once
  half of its exit time has run (`presentFadeOut`); the scale, slide or rise
  runs its whole time. The scrim and a tail fade with the panel. A presentation
  reversed mid-entrance or mid-exit continues its fade from where it is.
- An Alert, a Dialog, a Popover, a Menu (and each Menu level), a Callout and
  a Button `help` plate measure themselves at rest before the entrance: each
  waits, invisible and at scale 1, until its size holds for one frame, at most
  the theme's `motion.restLimit` (0.25 seconds by default). The placement then
  reads that rested size for the whole entrance and exit, so the scale never
  moves the anchor or its tail. The panel animates around content held at its
  final layout size. The content fade group keeps that size during the motion.
  This prevents a new render texture allocation on each animation frame.
  Text is never scaled by this entrance, and fractional
  text extents round up so a wrapped line is not clipped. The wait applies
  at every motion level.
