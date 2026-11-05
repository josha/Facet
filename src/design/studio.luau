--!strict

local Design = require("../vendor/compose/design")
local Editor = require("../vendor/compose/design-editor")
local Types = require("./types")
local Compose = require("../vendor/compose/core")
local ControlTypes = require("../ui/control_types")
local ThemeTypes = require("../ui/theme_types")

export type Workspace = Editor.Workspace & { UI: ControlTypes.Controls }
export type WorkspaceTheme = { name: string, theme: ThemeTypes.ReadOnlyThemePackage, palette: string }

return function(
	open: ({ WorkspaceTheme }) -> Workspace,
	options: Types.StudioOptions?,
	defaultTheme: ThemeTypes.ReadOnlyThemePackage
): Types.StudioKit
	local base = if options and options.theme then options.theme else defaultTheme
	local palettes: { [string]: boolean } = {}
	for _, palette in base.style.themes do
		assert(palette.name ~= "" and not palettes[palette.name], "Theme names must be nonempty and unique")
		palettes[palette.name] = true
	end
	local requested: { string | Types.StudioTheme } = {}
	if options and options.themes then
		requested = options.themes
	elseif options and options.theme then
		for _, palette in base.style.themes do
			table.insert(requested, palette.name)
		end
	else
		requested = { "Light", "Dark" }
	end
	assert(#requested > 0, "Workspace requires at least one theme")
	local workspaceThemes: { WorkspaceTheme } = {}
	local names: { [string]: boolean } = {}
	for _, choice in requested do
		local name = if type(choice) == "string" then choice else choice.name
		assert(name ~= "" and not names[name], "Theme names must be nonempty and unique")
		names[name] = true
		if type(choice) == "string" then
			assert(palettes[choice], "Unknown workspace theme: " .. choice)
			table.insert(workspaceThemes, { name = name, theme = base, palette = choice })
		else
			table.insert(
				workspaceThemes,
				{ name = name, theme = choice.theme, palette = choice.theme.style.defaultTheme }
			)
		end
	end
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
		if options.resolution then
			assert(not options.stages, "Use resolution or stages")
			for _, size in { options.resolution.X, options.resolution.Y } do
				assert(size > 0 and size < math.huge, "Resolution must be finite and positive")
			end
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
			local workspace = open(workspaceThemes)
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
					value.contract = assert(options).registry[sample.design].contract
					for _, input in value.contract.inputs do
						value.root.props[input.id] = { input = input.id }
					end
					return Design.document.validate(value, workspace.library)
				end
				local function validate(choice: string)
					local sample = samples[choice]
					local value = document(choice)
					for field, literal in sample.props do
						value.root.props[field] = { literal = literal }
					end
					Design.document.validate(value, workspace.library)
				end
				local initial = if initialChoice
					then document(initialChoice)
					else Design.document.new(name, workspace.library, workspace.root)
				for _, choice in choices do
					validate(choice)
				end
				if link then
					local source = link.read()
					if string.match(source, "^%s*$") then
						link.write(source, Design.emit(initial, workspace.library))
					end
				end
				local previews = table.clone(workspace.previews or {})
				local selected = Compose.cell(initialChoice or "")
				if initialChoice then
					table.insert(previews, {
						name = "Sample",
						choices = choices,
						initial = initialChoice,
						select = function(choice: string)
							selected:set(choice)
						end,
					})
				end
				return Editor.create(workspace.library, initial, parent, {
					frame = function(device: Editor.Device): Editor.FrameContext
						return {
							renderPreview = if initialChoice
								then function(
									value: Design.Document,
									_library: Design.Library,
									use: Compose.Use
								): (Design.Document, { [string]: Design.Resolved })
									local choice = use(selected)
									local sample = samples[choice]
									local preview = if sample.design == value.root.kind then value else document(choice)
									local bindings: { [string]: Design.Resolved } = {}
									for field, literal in sample.props do
										bindings[field] = { literal = literal }
									end
									if sample.bindings then
										for field, binding in sample.bindings(workspace.UI, device) do
											assert(
												Design.document.input(preview, field),
												"Unknown sample binding: " .. field
											)
											bindings[field] = binding
										end
									end
									return preview, bindings
								end
								else nil,
						}
					end,
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
			disposeEditor = result.dispose
			result.dispose = release
			return result
		end,
	}
end
