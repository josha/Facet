--!strict
type Demo = { id: string, title: string, blurb: string?, kind: "example" | "fixture", module: string }
local demos: { Demo } = {
	{
		id = "garage",
		title = "Garage",
		blurb = "Adaptive layouts and color controls for a 3D car configurator",
		kind = "example" :: "example",
		module = "08_garage",
	},
	{
		id = "sipworks",
		title = "Sipworks",
		blurb = "Navigation stacks and disclosures for browsing tea recipes",
		kind = "example" :: "example",
		module = "14_sipworks",
	},
	{
		id = "hud",
		title = "Screen-anchored HUD",
		blurb = "Screen regions that adapt and recover hidden HUD commands",
		kind = "fixture" :: "fixture",
		module = "hud",
	},
	{
		id = "ex02",
		title = "Playlist",
		blurb = "Table selection, sorting and row reordering for a playlist",
		kind = "example" :: "example",
		module = "02_playlist_table",
	},
	{
		id = "arcade",
		title = "Arcade",
		blurb = "Retained tabs and reactive state across four playable games",
		kind = "example" :: "example",
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
	[0] = "02_playlist_table",
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
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
		return scenario, { id = scenario, title = scenario, kind = "fixture" :: "fixture", module = scenario }
	end
	local name = if type(example) == "number" then EXAMPLES[example] else nil
	if name then
		return name,
			{
				id = name,
				title = if example == 0 then "Playlist" elseif example == 5 then "Word Guess" else name,
				kind = "example" :: "example",
				module = name,
			}
	end
	return demo or "garage", nil
end
return catalogue
