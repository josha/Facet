--!strict
--[[ THE RENDERER'S SOURCE, AS ONE TEXT.

	A family of pins anchors on the exact line that carries a ruling — "the measure
	seam and the paint seam call the SAME function", "the wrap verdict has a write
	site" — because the two halves of such a rule cannot be compared any other way.
	That instrument only works if it reads ALL of the renderer, and the renderer is
	no longer one file.

	WHY IT SPLIT. Roblox refuses a `Script.Source` assignment at 200,000 characters
	or more, and every LIVE path is a write: Rojo's Studio plugin, `execute_luau`,
	any plugin. So a module over the cap silently stops live-syncing into an open
	Studio session, and a live check against it then tests the code baked into the
	place file rather than the edits on disk
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). `renderer.luau`
	was 242,943 characters and has shed seam after seam since: the measure seam
	(`render/layout_node.luau`), the presentation channel
	(`render/presentation_channel.luau`), the prop-channel manifest
	(`render/prop_channels.luau`), the ordered rect apply
	(`render/rect_pass.luau`) and the commit walks
	(`render/commit_walks.luau`).

	ADD A PART HERE WHENEVER MORE OF THE RENDERER MOVES OUT — otherwise the pins
	quietly stop seeing the code they name, which is the failure this file exists
	to prevent. `tests/lib/adapter_source.luau` is the same instrument for the
	engine adapter, and says the same thing.

	AND THE PROSE ABOVE IS NOW CHECKED AGAINST THE LIST BELOW (review MEDIUM-4,
	2026-08-21). The commit-walk split rewrote that paragraph to name five modules
	and added only one of them to `PARTS`; `rect_pass.luau` had never been in it.
	No pin went blind — that file writes no `adapter.setProp(` at all — but a hand
	list beside a paragraph that describes it is the exact shape
	`tools/lune/check_prop_parity.luau` records going stale "the next time a split
	landed". `tests/commit_walks_seam.spec.luau` now asserts every
	`render/<module>.luau` this header names is a part, so the two cannot drift.
]]
local fs = require("@lune/fs")

local PARTS = {
	"src/render/renderer.luau",
	"src/render/layout_node.luau",
	"src/render/presentation_channel.luau",
	-- ...and the prop-channel manifest (2026-08-17): `BINDING_PROPS`,
	-- `STYLE_PROPS`, `STYLE_PROP_ORDER`, `BINDING_PROP_CLASSES`, `DIRECT_PROPS`
	-- and `emitsBinding`. Adding it here is what kept `tests/button_shape.spec`'s
	-- "shape is applied FIRST" pin looking at the list it names.
	"src/render/prop_channels.luau",
	--[[ ...and the COMMIT WALKS (2026-08-21): the six write loops that spend a
		finished solve — `textScale`, `padding`, `textVerdicts`, `visible`,
		`hitRects`, `scrollRegions`. Adding it here is what kept
		`tests/button_shape.spec`'s "the renderer really carries it across" pin
		looking at the `textWrapped` write it names, which moved with the walk. ]]
	"src/render/commit_walks.luau",
	--[[ ...and the ORDERED RECT APPLY, which this header has named since the
		commit-walk split and this list did not carry until the review found the gap.
		It holds no `adapter.setProp(` and no `setRect(` outside its own `applyOne`,
		so no existing pin's count moves — it is added because a part missing from an
		instrument is only ever discovered by the pin that needed it. ]]
	"src/render/rect_pass.luau",
}

local renderer_source = {}

renderer_source.PARTS = PARTS

-- the whole renderer, joined by a newline so a per-line scan still sees every
-- line exactly once and no two files' lines ever merge into one
function renderer_source.all(): string
	local parts: { string } = {}
	for _, path in PARTS do
		table.insert(parts, fs.readFile(path))
	end
	return table.concat(parts, "\n")
end

return renderer_source
