# Menu-and-SplitButton.edge

- When the player navigates by selection, an open menu selects its first
  enabled item. If an enabled selected item holds the value of its group, the
  menu selects that item instead. Back and Left close one level and return the selection to the
  item that opened it.
- Each level of a floating menu fades in at its final position and size. On
  dismiss it fades out, faster than it came in. In a sheet, a
  submenu slides in from the trailing side, and Back slides the parent level in
  from the leading side. Reduced motion removes the slide. See
  [Motion](Motion.md).
- `edge` (`top`, `bottom`, `leading` or `trailing`) and `align` (`start`,
  `center` or `end`) place the root panel against its trigger. The default is
  `bottom` and `start`. When the panel does not fit on its edge and fits on
  the opposite edge, it flips. Submenus keep their position beside their
  parent level. A malformed value causes an error that names the option.
- The panel follows its trigger when the trigger moves while the menu is open.
  The panel stays 8 pixels inside the safe area. When the screen of the menu
  has `IgnoreGuiInset` or `ScreenInsets = None`, the safe area removes the
  `GuiService:GetGuiInset()` insets. A sheet uses the same insets.
- `width` is the width of the floating panel. It takes pixels, a `UDim` or a
  `UDim2` (the X part, against the room of the screen), a dimension table, or
  a readable of one of these. The dimension tables are `{ type = "fixed", px }`,
  `{ type = "fill" }`, `{ type = "hug", min?, max? }`,
  `{ type = "percent", fraction, offset?, min?, max? }`,
  `{ type = "minMax", min?, preferred?, max? }` and `{ type = "content" }`.
  `px`, `min`, `preferred` and `max` take pixels or a theme metric name such as
  `"targetSizes.minimum"`. `hug` and `content` start from the natural width of
  the rows. The width never goes past the room of the screen. A malformed width
  causes an error that names the field.
- `maxHeight` bounds the whole floating panel in pixels. The panel is always
  bounded by the screen, and its rows scroll inside it. On skinned panel art,
  the panel is its rows plus the art carve (`chrome.panel.contentInsets`) on
  each side, and the rows scroll inside the carve. The row ids and the
  activation do not change. The `MenuPanel` Frame is the plate. It holds the
  `MenuScroll` ScrollingFrame that holds `MenuRows`. When the menu fades, the
  `MenuGroup` Frame sits between them and is the size of the panel, so
  a long list never makes a tall fade group, and its text stays sharp.
