local demos = {
	{
		id = "garage",
		title = "Garage",
		blurb = "Customize a 3D ride, change its paint and save a preset",
		kind = "example",
		module = "08_garage",
	},
	{
		id = "sipworks",
		title = "Sipworks",
		blurb = "Explore tea recipes, scale ingredients and follow related blends",
		kind = "example",
		module = "14_sipworks",
	},
	{
		id = "hud",
		title = "Screen-anchored HUD",
		blurb = "Game HUD zones adapt to the screen and recover hidden commands",
		kind = "fixture",
		module = "hud",
	},
	{
		id = "ex02",
		title = "Playlist",
		blurb = "Sort, rate and reorder your next listening session",
		kind = "example",
		module = "02_playlist_table",
	},
	{
		id = "arcade",
		title = "Arcade",
		blurb = "Word Game, Crossword, Match 3 and the Outpost power puzzle",
		kind = "example",
		module = "13_arcade",
	},
}
local catalogue = {}
function catalogue.list()
	return table.clone(demos)
end
function catalogue.next(current, step)
	local selected = 1
	for index, demo in demos do
		if demo.id == current then
			selected = index
			break
		end
	end
	return demos[(selected - 1 + (step or 1)) % #demos + 1].id
end
local EXAMPLES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}
function catalogue.boot(demo, scenario, example)
	if type(scenario) == "string" and scenario ~= "" then
		return scenario, { id = scenario, title = scenario, kind = "fixture", module = scenario }
	end
	local name = if type(example) == "number" then EXAMPLES[example] else nil
	if name then
		return name, { id = name, title = name, kind = "example", module = name }
	end
	return demo or "garage", nil
end
return catalogue
