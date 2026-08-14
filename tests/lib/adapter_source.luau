--!strict
--[[ THE LIVE ScreenTarget'S SOURCE, AS ONE TEXT.

	`src/client/screen_target.luau` cannot load headlessly — it reaches engine
	globals at load time — so a large family of pins reads it as TEXT instead and
	anchors on the exact lines that carry a ruling. That instrument only works if
	it reads ALL of the adapter, and the adapter is no longer one file.

	WHY IT SPLIT. Roblox refuses a `Script.Source` assignment over 200,000
	characters, and every live path is a write: Rojo's Studio plugin,
	`execute_luau`, any plugin. So a module over that line silently stops
	live-syncing into an open Studio session, and a live check against it then
	tests the code baked into the place file rather than the edits on disk
	(docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md). screen_target
	has been split along that pressure: the chrome/decoration materializer left
	first (`screen_chrome`), then the scroll seam (`screen_scroll_indicators`) and
	the bespoke paint vocabulary (`screen_paint`).

	WHAT `live()` IS, AND IS NOT. It is the adapter minus chrome. `screen_chrome`
	left long enough ago that the specs which pin it read it explicitly by name;
	folding it in here would silently change what every existing occurrence count
	means. The three parts below are the ones a pin written against "the adapter"
	expects to be looking at.

	ADD A PART HERE WHENEVER MORE OF THE ADAPTER MOVES OUT — otherwise the pins
	quietly stop seeing the code they name, which is the failure this file exists
	to prevent.
]]
local fs = require("@lune/fs")

local PARTS = {
	"src/client/screen_target.luau",
	"src/client/screen_paint.luau",
	"src/client/screen_scroll_indicators.luau",
}

local adapter_source = {}

adapter_source.PARTS = PARTS

-- the whole live adapter, joined by a newline so a per-line scan still sees
-- every line exactly once and no two files' lines ever merge into one
function adapter_source.live(): string
	local parts: { string } = {}
	for _, path in PARTS do
		table.insert(parts, fs.readFile(path))
	end
	return table.concat(parts, "\n")
end

return adapter_source
