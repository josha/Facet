--!strict
type Demo = typeof(require("@repo/examples/types").Demo)
local demos: { Demo } = {
	{
		id = "ascent",
		title = "Ascent",
		blurb = "A growing skill tree with themed tiles, unlock feedback and spatial navigation",
		kind = "example",
		module = "16_ascent",
	},
	{
		id = "garage",
		title = "Garage",
		blurb = "Adaptive layouts and color controls for a 3D car configurator",
		kind = "example",
		module = "08_garage",
	},
	{
		id = "sipworks",
		title = "Sipworks",
		blurb = "Navigation stacks and disclosures for browsing tea recipes",
		kind = "example",
		module = "14_sipworks",
	},
	{
		id = "hud",
		title = "Screen-anchored HUD",
		blurb = "Screen regions that adapt and recover hidden HUD commands",
		kind = "fixture",
		module = "hud",
	},
	{
		id = "ex02",
		title = "Playlist",
		blurb = "Table selection, sorting and row reordering for a playlist",
		kind = "example",
		module = "02_playlist_table",
	},
	{
		id = "arcade",
		title = "Arcade",
		blurb = "Retained tabs and reactive state across four playable games",
		kind = "example",
		module = "13_arcade",
	},
	{
		id = "files",
		title = "File library",
		blurb = "Shared selection and editing across grid, outline and table views",
		kind = "fixture",
		module = "collection_workbench",
	},
}
local EXAMPLES = {
	[0] = { module = "02_playlist_table", title = "Playlist" },
	{ module = "01_temperature_converter", title = "Temperature converter" },
	{ module = "02_playlist_table", title = "Playlist" },
	{ module = "03_settings_sync", title = "Settings sync" },
	{ module = "04_confirm_dialog", title = "Confirm dialog" },
	{ module = "05_word_game", title = "Word Guess" },
	{ module = "06_tile_game", title = "Crossword" },
	{ module = "07_match3", title = "Match-3" },
}
local catalogue = {}
function catalogue.list(example: number?): { Demo }
	if example ~= nil then
		local _, booted = catalogue.boot(nil, nil, example)
		return if booted then { booted } else {}
	end
	return table.clone(demos)
end
function catalogue.next(current: string, step: number?)
	local selected = 1
	for index, demo in demos do
		if demo.id == current then
			selected = index
			break
		end
	end
	return demos[(selected - 1 + (step or 1)) % #demos + 1].id
end

function catalogue.boot(demo: string?, scenario: string?, example: number?): (string, Demo?)
	if type(scenario) == "string" and scenario ~= "" then
		return scenario, { id = scenario, title = scenario, kind = "fixture", module = scenario }
	end
	local entry = if type(example) == "number" then EXAMPLES[example] else nil
	if entry then
		return entry.module, { id = entry.module, title = entry.title, kind = "example", module = entry.module }
	end
	return demo or "garage", nil
end
return catalogue
