--!strict
-- Render fixture registry (design §16.1 "render", §7.5 dumps): deterministic
-- layout dump fixtures from the Phase 0 layout spike. The registry_runner
-- runs each fixture twice and fails on any output difference, so every
-- fixture here is also a determinism proof. These dumps are the headless
-- side of the Studio differential comparison (engine-fidelity-fixtures).

local runner = require("../../tools/lune/registry_runner")
local dump = require("../../src/layout/dump")
local solver = require("../../src/layout/solver")

local function fixed(px: number): solver.Dim
	return { type = "fixed", px = px }
end
local function fill(weight: number?): solver.Dim
	return { type = "fill", weight = weight or 1 }
end

-- the same settings-shaped blueprint rendered on two devices: the Phase 0
-- "two clients, device-appropriate layouts" evidence at dump level
local function settingsScreen(): solver.Node
	return {
		kind = "vstack",
		id = "Settings",
		width = fill(1),
		height = fill(1),
		padding = 16,
		gap = 8,
		children = {
			{ kind = "text", id = "Title", text = "Settings", textSize = 24 },
			{
				kind = "text",
				id = "Help",
				text = "Tune music, effects and controls. Changes save to your profile when you press save.",
				textSize = 16,
			},
			{
				kind = "hstack",
				id = "MusicRow",
				width = fill(1),
				gap = 8,
				children = {
					{ kind = "text", id = "MusicLabel", text = "Music", textSize = 18 },
					{ kind = "spacer", id = "MusicGap", width = fill(1) },
					{ kind = "box", id = "MusicToggle", width = fixed(56), height = fixed(28) },
				},
			},
			{ kind = "spacer", id = "BottomGap", height = fill(1) },
			{ kind = "box", id = "SaveButton", width = fixed(140), height = fixed(44) },
		},
	}
end

local fixtures: { runner.Fixture } = {
	{
		name = "settings-phone-portrait",
		requirement = "UI-ADAPT-001",
		run = function()
			return dump.fromSolve(settingsScreen(), { w = 390, h = 844 }, {
				safeInsets = { top = 59, bottom = 34, left = 0, right = 0 },
				rootPolicy = "coreSafeContent",
			})
		end,
	},
	{
		name = "settings-desktop-1080p",
		requirement = "UI-ADAPT-001",
		run = function()
			return dump.fromSolve(settingsScreen(), { w = 1920, h = 1080 }, {
				safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
				rootPolicy = "coreSafeContent",
			})
		end,
	},
	{
		name = "scroll-overflow-list",
		requirement = "UI-LAYOUT-001",
		run = function()
			local rows = {}
			for i = 1, 12 do
				table.insert(
					rows,
					{ kind = "box", id = `Row{i}`, width = fixed(200), height = fixed(40) } :: solver.Node
				)
			end
			return dump.fromSolve(
				{ kind = "scroll", id = "List", width = fixed(240), height = fixed(320), axis = "y", children = rows },
				{ w = 800, h = 600 },
				{ rootPolicy = "edgeToEdge" }
			)
		end,
	},
	{
		name = "wrapped-text-narrow-vs-wide",
		requirement = "UI-LAYOUT-001",
		run = function()
			local para = "the quick brown fox jumps over the lazy dog while the settings help text keeps wrapping"
			local function screenAt(width: number, id: string): any
				return dump.fromSolve({
					kind = "vstack",
					id = id,
					children = {
						{ kind = "text", id = id .. "Para", text = para, textSize = 16 },
					},
				}, { w = width, h = 600 }, { rootPolicy = "edgeToEdge" })
			end
			return { narrow = screenAt(160, "Narrow"), wide = screenAt(640, "Wide") }
		end,
	},
}

return fixtures
