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
	was 242,943 characters and shed two seams: the measure seam
	(`render/layout_node.luau`) and the presentation channel
	(`render/presentation_channel.luau`).

	ADD A PART HERE WHENEVER MORE OF THE RENDERER MOVES OUT — otherwise the pins
	quietly stop seeing the code they name, which is the failure this file exists
	to prevent. `tests/lib/adapter_source.luau` is the same instrument for the
	engine adapter, and says the same thing.
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
