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
	first (`screen_chrome`), then the scroll seam (`screen_scroll_indicators`),
	the bespoke paint vocabulary (`screen_paint`), the presentation channel
	(`screen_presentation`), the pointer seam (`screen_pointer`) and the engine
	vocabulary the adapter declares before its closure opens (`screen_vocabulary`).

	WHAT `live()` IS, AND IS NOT. It is the adapter minus chrome. `screen_chrome`
	left long enough ago that the specs which pin it read it explicitly by name;
	folding it in here would silently change what every existing occurrence count
	means. The parts listed below are the ones a pin written against "the adapter"
	expects to be looking at.

	ADD A PART HERE WHENEVER MORE OF THE ADAPTER MOVES OUT — otherwise the pins
	quietly stop seeing the code they name, which is the failure this file exists
	to prevent. `screen_props` (the per-class `setProp` chain) joined 2026-08-28,
	the SOURCE_CAP_LEDGER extraction this document's own header predicted.
]]
local fs = require("@lune/fs")

local PARTS = {
	"src/client/screen_target.luau",
	"src/client/screen_vocabulary.luau",
	"src/client/screen_paint.luau",
	"src/client/screen_scroll_indicators.luau",
	"src/client/screen_presentation.luau",
	"src/client/screen_pointer.luau",
	"src/client/screen_props.luau",
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

--[[ ONE FUNCTION'S TEXT, WITHOUT GUESSING HOW LONG IT IS.

	The pins that read this adapter as text nearly all say
	`string.sub(source, at, at + N)` and then look inside. N is a guess about how
	long a function is, and every comment anyone adds to that function walks the
	code they were pinning out the far end of the window. That has already
	happened at least twice: `adaptive.spec`'s RS-A16-D1b window was widened
	900 -> 1500 in the 2026-07-28 fix round with the note "the invariant itself is
	unchanged", and it ran out again the moment ADR-0032's write-skip comment
	landed in `applyRect`. A pin that fails because somebody EXPLAINED the code is
	a pin that trains people to delete explanations.

	So: take the text from the anchor to the start of the next sibling declaration
	instead. Every one of these lives one tab inside `screen_target.new`/
	`screen_presentation.new`, so `\n\tlocal function ` is where the next one
	begins, and `\n\tfunction ` catches the `adapter.*` members that follow the
	last local. Falls back to the rest of the file when neither appears, which is
	still strictly better than a fixed count.

	It is deliberately NOT a Luau parser. A pin wants "the region this rule lives
	in" and this is the cheapest honest answer to that; anything cleverer would be
	a second implementation of the language for the benefit of a substring search.
]]
function adapter_source.bodyOf(source: string, anchor: string): string
	local at = string.find(source, anchor, 1, true)
	if at == nil then
		return ""
	end
	local from = at + #anchor
	local stop = #source
	for _, nextDecl in { "\n\tlocal function ", "\n\tfunction " } do
		local found = string.find(source, nextDecl, from, true)
		if found ~= nil and found < stop then
			stop = found
		end
	end
	return string.sub(source, at, stop)
end

return adapter_source
