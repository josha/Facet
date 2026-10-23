# Themes.definition

Themes.definition option values and behavior.

For a complete typed definition, open [Tasks.theme](Tasks.theme.md).

- `neutralPackage()` returns a mutable copy of the neutral theme package. It
  declares two palettes, `Dark` (the default) and `Light`. Both palettes pass
  the contrast gate of `define`.
- `define(definition)` derives from `base` (neutral by default) and returns
  `package?, report`. It also accepts a theme package as its input. A chrome
  override can omit `kind` when the base supplies it. Check `report.ok` before
  use. An accepted theme package is
  recursively frozen. Callbacks, cycles and malformed definitions are rejected.
  A type role needs a positive size. Each `metrics.space` step needs a pixel
  size of 0 or more. A chrome shadow name must be a
  package shadow or a preset (`raised` or `overlay`). A native chrome shadow
  keeps the opacity of the fill that casts it. A clear fill casts none, and a
  tint such as the `soft` appearance casts a lighter one. A chrome art link
  `rotation` must be 0 or 180, and its `tint` needs `r`, `g` and `b` from 0
  to 1. Each palette pair needs a
  contrast of at least 4.5:1, which includes `onSelected` (or `content`) on
  `controlSelected`.
  Color channels and semantic contrast pairs are validated. A package that
  does not declare `style.themes` gets only the first palette of its base. Thus
  a package derived from Neutral has one palette unless it declares more.
- `checkCoverage(package, needs)` returns `{ ok, covered, missing }`.
- `resolveIcon(package, name, state?)` resolves real image content. A name
  that ends in `.fill`, such as `"star.fill"`, is the filled variant. The
  package art for that name wins. Without it, the regular icon draws.
- `createStyleSheet(runtime, packageOrReadable?, options?)` returns a native
  StyleSheet that Compose owns. See the list below.
- `forDistance(package, distance)` is the ten-foot metric ladder. `"near"`
  returns the authored package (the same table). `"ten-foot"` returns a frozen
  package whose lengths are 1.5 times (`adaptive.TEN_FOOT_SCALE`): `space`,
  `targetSizes` (a 44 pixel target is 66), `iconSizes`, `strokes`, every
  `controlSizes` field, `radii` (rounded to whole pixels) and each type role
  size. Text never goes below the console reading floors: 24 pixels for
  `caption` and 28 for every other role (the Xbox Accessibility Guidelines ask
  for text 26 pixels tall at 1080p), so a 16 pixel `body` is 28, not 24. A
  `metrics.controls` value scales unless
  its name ends in `TextSize`, `Lines`, `Count`, `Duration`, `Seconds`,
  `Ratio`, `Fraction`, `Scale`, `Opacity` or `Weight`. Motion, colors, chrome
  art and art insets do not scale. Above the floors, every proportion of text
  to its control is the same at both distances. The call is idempotent and reversible:
  `forDistance(far, "near")` returns the authored package. You rarely call it:
  controls and a StyleSheet apply it from the ten-foot fact. A frozen
  package's ladder is cached.
