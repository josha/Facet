local demos = {
	{
		id = "all-controls",
		title = "All controls",
		blurb = "Inputs, actions, indicators and navigation in nested tabs",
		kind = "fixture",
		module = "all_controls",
	},
	{
		id = "collections",
		title = "Collections",
		blurb = "Lists, tables, grids and row actions with large data sets",
		kind = "fixture",
		module = "collections",
	},
	{
		id = "motion-layout",
		title = "Motion and layout",
		blurb = "Compare animation, wrapping, transparency and adaptive layouts",
		kind = "fixture",
		module = "motion_layout",
	},
	{
		id = "hud",
		title = "Screen-anchored HUD",
		blurb = "Game HUD zones adapt to the screen and recover hidden commands",
		kind = "fixture",
		module = "hud",
	},
	{
		id = "radial-menu",
		title = "Quick actions",
		blurb = "Contextual commands around a launcher or a world object",
		kind = "fixture",
		module = "radial_menu",
	},
	{
		id = "ex02",
		title = "Playlist table",
		blurb = "Organize a playlist: sort, edit, reorder and resize columns",
		kind = "example",
		module = "02_playlist_table",
	},
	{
		id = "ex03",
		title = "Settings sync",
		blurb = "Try instant changes, delayed saves and rejected changes that roll back",
		kind = "example",
		module = "03_settings_sync",
	},
	{
		id = "ex05",
		title = "Word game",
		blurb = "Play a word puzzle with keyboard, touch or gamepad",
		kind = "example",
		module = "05_word_game",
	},
	{
		id = "ex06",
		title = "Crossword",
		blurb = "Build crossing words on an interactive board",
		kind = "example",
		module = "06_tile_game",
	},
	{
		id = "ex07",
		title = "Match 3",
		blurb = "Swap tiles, make matches and follow the score",
		kind = "example",
		module = "07_match3",
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
	return demo or "all-controls", nil
end
return catalogue
