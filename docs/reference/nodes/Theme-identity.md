# Theme-identity

Turn the art direction of a game into a theme that reads over its world.

- Start from a written direction: setting and tone, shape, material, type
  voice, accent and motion. The use-facet visual language chapter shows how.
  Then map each part to roles. A toy kart racer can map to warm light plates,
  a primary red `accent`, large `radii` and a rounded display face. A
  night-city racer can map to near-black plates, a sodium amber `accent`,
  thin `strokes` and a wide technical face. An expedition can map to
  parchment `panel` art, ink `content` and a calligraphic `heading`.
- Keep plates visible over the scene: `control` and `surfaceStrong` must
  separate clearly from the world behind them. Over a dark world, make them
  clearly lighter than the world and keep `content` pale. Faint text and
  plates that vanish into the scene read as unfinished.
- Use a legible font family and a few sizes. At 1080p, keep body text at 18 or
  more, captions and HUD labels at 15 or more, and HUD numbers at 20 or more.
  Smaller text reads as unfinished on a TV and is hard to read on a phone.
  Check clocks and numbers in the chosen font: some display fonts draw a colon
  so thin that "24:51" reads as "2451" at small sizes. Wide display fonts can
  make ordinary captions compete with headings and force short labels to
  wrap. Put the display face on `title` and `heading`, and keep the body
  plain. Express character through the palette, shape, icons and surface
  treatment before you change all text.
- Set `font.family` for each typography role. A `body` override does not
  change all roles. The recipe patches the base font tables and keeps their
  weight, style and line height. `strong` derives from an authored `body`, and
  `numeral` from an authored `control`, unless you set those roles too.
- Use `strong` for an item name, `caption` for supporting facts and `numeral`
  for an important balance, cost or reward. Give the name, cost and current
  state distinct places. Avoid one caption that combines category, price,
  description and ownership with equal weight. Check headings, main values
  and captions together with long translated text over the game world.
- Keep selection, ownership and purchase emphasis distinct. A quiet Owned
  state must not compete with Buy. Preserve the words as well as any color
  difference. Use stable icons or category marks when they help identify items.
- Choose a surface for the task. Give recurring destinations a readable
  [page](Tasks.pages.md), with art and comparison space. Use a content-sized
  Sheet for a short interruption. A large empty panel makes a small decision
  harder to scan; a small scrolling window hides a collection's useful choices.
- Use quiet boundaries when they help separate items from their container.
  Reserve the accent and strong outlines for the current selection or action;
  equal bright strokes on every nested panel erase that hierarchy.
- `rules` add native StyleSheet rules. `{ role = "accent" }` and
  `{ metric = "..." }` follow palette and distance changes.
- Check `report` before you pass the package to the app. When a main color
  pair is below 4.5:1, `define` returns nil and `report.ok` is false.

Back to [Tasks.theme](Tasks.theme.md).
