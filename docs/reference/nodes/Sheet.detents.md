# Sheet.detents

Sheet requires a writable `isPresented`. `detent` is a writable cell or a
detent id. With an id or without `detent`, the sheet keeps the selected detent.
It starts at that id, or at the first detent when the id is not in `detents`.
With a cell, the sheet writes the selected detent to the cell. The default
detents are `medium` and `large`. A custom entry is `{ id, fraction }` or
`{ id, height }`, never both. The `hug` entry fits the body and the pinned
regions. It measures the content of the body, not the scroll canvas, so it does
not grow to fill the room. It measures again when the content changes, and it
stays inside the safe room and above a minimum of four target heights.

Supply a `title` and a `content` factory that returns native children. The
sheet calls the factory without arguments. Its subtree fills the body region.
The body uses a native vertical ScrollingFrame named `SheetContent`. Thus
content taller than the selected detent stays reachable, and the sheet chrome
stays fixed.

Layout options:
