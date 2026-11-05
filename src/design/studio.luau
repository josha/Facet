--!strict

local Design = require("../vendor/compose/design")
local Editor = require("../vendor/compose/design-editor")
local Types = require("./types")

return function(open: () -> Editor.Workspace, options: Types.StudioOptions?): Types.StudioKit
	local samples: { [string]: Types.StudioSample } = {}
	local choices: { string } = {}
	for _, sample in if options then options.samples else {} do
		assert(options and options.registry[sample.design], "Unknown sample Design: " .. sample.design)
		assert(sample.name ~= "", "Sample requires a name")
		local choice = sample.design .. "/" .. sample.name
		assert(not samples[choice], "Duplicate Design sample: " .. choice)
		samples[choice] = sample
		table.insert(choices, choice)
	end
	if options then
		for _, theme in options.themes or { "Light", "Dark" } do
			assert(theme == "Light" or theme == "Dark", "Unknown workspace theme: " .. theme)
		end
		for _, textSize in options.textSizes or { "Medium", "Large", "Larger", "Largest" } do
			assert(
				table.find({ "Medium", "Large", "Larger", "Largest" }, textSize),
				"Unknown workspace text size: " .. textSize
			)
		end
		if options.stages then
			assert(#options.stages > 0, "Workspace requires at least one stage")
			local stages: { [string]: boolean } = {}
			for _, stage in options.stages do
				assert(stage.id ~= "" and not stages[stage.id], "Stage ids must be nonempty and unique")
				stages[stage.id] = true
			end
		end
		for name in options.registry do
			local found = false
			for _, sample in samples do
				found = found or sample.design == name
			end
			assert(found, "Design requires a sample: " .. name)
		end
		assert(#choices > 0, "Design workspace requires a registry and samples")
	end
	return {
		name = "Facet",
		edit = function(parent: unknown, name: string, link: Design.LinkStore?): Types.StudioEditor
			assert(type(parent) == "table" or type(parent) == "userdata", "Design editor requires a host parent")
			local initialChoice: string? = nil
			if options then
				for _, choice in choices do
					if samples[choice].design == name then
						initialChoice = choice
						break
					end
				end
				assert(initialChoice, "Unknown workspace Design: " .. name)
			end
			local workspace = open()
			local editor: Types.StudioEditor? = nil
			local disposeEditor: (() -> ())? = nil
			local released = false
			local function release()
				if released then
					return
				end
				released = true
				local disposed, failure = pcall(function()
					if disposeEditor then
						disposeEditor()
					end
				end)
				if workspace.dispose then
					workspace.dispose()
				end
				if not disposed then
					error(failure, 0)
				end
			end
			local ok, result = pcall(function(): Types.StudioEditor
				local function document(choice: string): Design.Document
					local sample = samples[choice]
					local value = Design.document.new(sample.design, workspace.library, sample.design)
					for field, literal in sample.props do
						value.root.props[field] = { literal = literal }
					end
					return Design.document.validate(value, workspace.library)
				end
				local initial = if initialChoice
					then document(initialChoice)
					else Design.document.new(name, workspace.library, workspace.root)
				for _, choice in choices do
					document(choice)
				end
				if link then
					local source = link.read()
					if string.match(source, "^%s*$") then
						link.write(source, Design.emit(initial, workspace.library))
					end
				end
				local previews = table.clone(workspace.previews or {})
				if initialChoice then
					table.insert(previews, {
						name = "Sample",
						choices = choices,
						initial = initialChoice,
						select = function(choice: string)
							if editor then
								local changed = editor.execute({ action = "Replace", document = document(choice) })
								assert(changed.ok, changed.problem)
							end
						end,
					})
				end
				return Editor.create(workspace.library, initial, parent, {
					runtime = workspace.runtime,
					environment = workspace.environment,
					devices = workspace.devices or Editor.devices.all,
					previews = previews,
					capture = if options then options.capture else nil,
					link = link,
					onClose = release,
				})
			end)
			if not ok then
				release()
				error(result, 0)
			end
			editor = result
			disposeEditor = result.dispose
			result.dispose = release
			return result
		end,
	}
end
