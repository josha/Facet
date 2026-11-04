# Themes.resolution

`themes.forResolution(package, width, height)` derives a theme for the full display viewport.
Use the package in the existing app's `theme` option. Derive it in a Compose formula from the
game's observed viewport so a display change updates the controls and StyleSheet together.
Pass the display dimensions, rather than a panel's bounds. The theme does not observe the camera.

`adaptive.resolutionScale(width, height)` returns `max(1, min(width, height) / 1080)`.
Phone, tablet and 1080p layouts keep their authored size. A 2560 by 1440 viewport uses
four-thirds scale; 3840 by 2160 uses two. An ultrawide display uses its short edge.
Zero, negative and non-finite dimensions never shrink the interface.

The transform scales theme lengths, control sizes, targets, icons, type and chrome.
Text reaches the 14 pixel reading floor before enlargement. At two times scale the
smallest near text is at least 28 pixels. Chrome insets, plaques, tiles and image slice
scales grow with the controls. Colors, ratios, counts and motion timing keep their values.
Literal native properties in authored theme rules keep their authored values.

`UI.environment().scaled(number)` and `metricScale` follow the resolution of the supplied
theme. Use them for game-specific pixel geometry. Native layout still places the controls;
no extra UIScale or application tree is added.

The call is idempotent, cached for frozen themes, and reversible. Applying the same dimensions
twice does not compound the scale. Returning to 1080p returns the original near package.
`forDistance` and `forResolution` compose in either order. A ten-foot package keeps its reading
ladder and gains the resolution factor; changing distance preserves the chosen resolution.
Controls and StyleSheets keep the distance already selected on a supplied package.
Automatic ten-foot detection applies the ladder without compounding that distance.
