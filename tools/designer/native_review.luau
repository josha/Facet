--!strict

type FacetModule = typeof(require("@repo/src"))
local requireDynamic = require :: (any) -> any
local s = assert(_G.FacetDesignSmoke)
local m = s.modules
local Facet = (requireDynamic(game:GetService("ReplicatedStorage"):WaitForChild("Facet")) :: unknown) :: FacetModule
local document, library = requireDynamic(m.document), requireDynamic(m.library)
local session, render = requireDynamic(m.session), requireDynamic(m.design_render)
local probe = { presets = 0, structured = 0, matrix = 0, fields = 0, failures = {}, done = false }
_G.FacetDesignGapProbe = probe

task.spawn(function()
	local function mount(value, config, label)
		local ok, err = pcall(function()
			local mounted = session.mount(
				Facet,
				s.widget,
				render.definition(value).previews[1],
				{ config = config, inputParent = s.widget }
			)
			task.wait(0.01)
			mounted.dispose()
		end)
		if not ok then
			table.insert(probe.failures, { case = label, error = string.match(tostring(err), "[^\n]+") })
		end
	end
	local config = {
		width = 390,
		height = 844,
		input = "Touch",
		display = "Small",
		distance = "near",
		palette = "Light",
		textSize = "Medium",
		motionLevel = "none",
	}
	for _, kind in library.names() do
		local value, id
		if kind == "Screen" then
			value, id = document.new(), "n1"
		else
			value, id = document.insert(document.new(), "n1", kind)
		end
		for _, field in library.definitions[kind].fields do
			probe.fields += 1
			if field.kind == "choice" or field.kind == "boolean" then
				for _, option in (if field.kind == "boolean" then { false, true } else field.options) do
					probe.presets += 1
					mount(
						document.change(value, id, field.key, option),
						config,
						kind .. "." .. field.key .. "=" .. tostring(option)
					)
				end
			elseif field.kind == "json" and field.exemplar then
				probe.structured += 1
				mount(document.change(value, id, field.key, field.exemplar), config, kind .. "." .. field.key)
			elseif field.kind == "color" then
				probe.structured += 1
				mount(document.change(value, id, field.key, "#143357"), config, kind .. "." .. field.key)
			end
		end
	end
	for _, template in requireDynamic(m.templates) do
		local edited =
			document.change(template, template.root.id, "padding", { top = "m", right = 20, bottom = "l", left = 20 })
		for _, profile in requireDynamic(m.profiles) do
			for _, palette in { "Light", "Dark" } do
				for _, textSize in { "Medium", "Largest" } do
					local c = table.clone(profile)
					c.palette, c.textSize, c.motionLevel = palette, textSize, "none"
					probe.matrix += 1
					mount(edited, c, template.name .. "/" .. profile.name .. "/" .. palette .. "/" .. textSize)
				end
			end
		end
	end
	probe.done = true
end)
return "Native review started"
