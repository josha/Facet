--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

local catalog = require("./catalog")
local loader = require("./loader")
local profiles = require("./profiles")
local session = require("./session")
local chrome = require("./chrome")

local workbench = {}

function workbench.mount(Facet: any, widget: Instance, dependencies: any): any
	local Compose: ComposeModule = Facet.Compose
	local defaults = {
		device = "Phone",
		input = "Automatic",
		comparison = "Single",
		zoom = "Fit",
		palette = "Dark",
		textSize = "Medium",
		motionLevel = "normal",
		rotated = false,
		live = true,
		inspect = false,
		selected = nil :: ModuleScript?,
		state = "",
		states = {},
		entries = {},
		error = "",
		status = "Select a component. Built-in examples are ready to explore.",
	}
	if not dependencies.editor then
		defaults.live = false
	end
	local model = Compose.cell(table.clone(defaults))
	local choices = {
		device = { "Phone", "Tablet", "Desktop", "Television" },
		input = { "Automatic", "KeyboardAndMouse", "Touch", "Gamepad" },
		comparison = { "Single", "Devices", "States", "Palettes" },
		zoom = { "Width", "Fit", "50%", "75%", "100%", "150%" },
		palette = { "Dark", "Light" },
		textSize = { "Medium", "Large", "Larger", "Largest" },
		motionLevel = { "normal", "limited", "none" },
	}
	local shell: any
	local active: any
	local loaded: any
	local definition: any
	local pendingSnapshot: any
	local pendingGroup: any
	local disposed, epoch, debounce = false, 0, 0
	local refreshJob: thread?
	local query = ""
	local function patch(values: any)
		model:update(function(previous)
			local nextValue = table.clone(previous)
			for key, value in values do
				nextValue[key] = value
			end
			return nextValue
		end)
	end
	local function close(group: any)
		if not group then
			return
		end
		for _, dispose in group.disposers do
			dispose()
		end
		group.stop()
	end
	local function config(profile: any): any
		local value = model:peek()
		return {
			width = if value.rotated then profile.height else profile.width,
			height = if value.rotated then profile.width else profile.height,
			input = if value.input == "Automatic" then profile.input else value.input,
			display = profile.display,
			distance = profile.distance,
			textSize = value.textSize,
			palette = value.palette,
			motionLevel = value.motionLevel,
		}
	end
	local function arrange()
		if not active then
			return
		end
		local value = model:peek()
		local available = math.max(160, shell.canvas.AbsoluteWindowSize.X - 48 - shell.canvas.ScrollBarThickness)
		local cardWidth = if value.comparison == "Single" then available else math.min(420, available)
		if dependencies.canvasOnly and value.comparison == "Single" then
			active.root.Size = UDim2.fromOffset(available, 0)
		end
		for _, card in active.cards do
			local settings = config(card.profile)
			if card.palette then
				settings.palette = card.palette
			end
			local scale = if value.zoom == "Fit"
				then math.min(
					1,
					(cardWidth - 24) / settings.width,
					math.max(180, shell.canvas.AbsoluteWindowSize.Y - 108 - shell.canvas.ScrollBarThickness)
						/ settings.height
				)
				elseif value.zoom == "Width" then math.min(1, (cardWidth - 24) / settings.width)
				else assert(tonumber(string.sub(value.zoom, 1, -2))) / 100
			card.scale.Scale = scale
			card.node.Size = UDim2.fromOffset(
				if dependencies.canvasOnly
					then settings.width * scale + 24
					else math.max(cardWidth, settings.width * scale + 24),
				settings.height * scale + 60
			)
			card.label.Text = `{card.preview.name}  ·  {card.profile.name}  ·  {settings.width} × {settings.height}`
			card.session.update(settings)
			card.outline.Enabled = value.inspect
		end
	end
	local function build(nextDefinition: any)
		local value = model:peek()
		local preview = nextDefinition.previews[1]
		for _, entry in nextDefinition.previews do
			if entry.name == value.state then
				preview = entry
			end
		end
		local profile = profiles[1]
		for _, entry in profiles do
			if entry.name == value.device then
				profile = entry
			end
		end
		local requests = {}
		if value.comparison == "Devices" then
			for _, item in profiles do
				table.insert(requests, { profile = item, preview = preview })
			end
		elseif value.comparison == "Palettes" then
			for _, palette in { "Light", "Dark" } do
				table.insert(requests, { profile = profile, preview = preview, palette = palette })
			end
		elseif value.comparison == "States" then
			for _, item in nextDefinition.previews do
				table.insert(requests, { profile = profile, preview = item })
			end
		else
			table.insert(requests, { profile = profile, preview = preview })
		end
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime()
		local owner = Compose.createOwner(runtime.reactor)
		local group = {
			cards = {},
			sessions = {},
			disposers = {},
			stop = function()
				owner.dispose()
				runtime:dispose()
			end,
		}
		pendingGroup = group
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local ok, err = xpcall(function()
			local _, root = Compose.withOwner(owner, function()
				return runtime.mount(function()
					local children: { Instance } = {
						Host.UIListLayout {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 16),
							SortOrder = Enum.SortOrder.LayoutOrder,
							HorizontalAlignment = if dependencies.canvasOnly and value.comparison == "Single"
								then Enum.HorizontalAlignment.Center
								else Enum.HorizontalAlignment.Left,
						},
					}
					for index, request in requests do
						local canvas = Host.Frame "DeviceViewport" {
							Position = UDim2.fromOffset(12, 42),
							BackgroundTransparency = 1,
							Size = UDim2.fromOffset(1, 1),
						}
						local scale = Host.UIScale { Scale = 1 }
						local label = Host.TextLabel "DeviceLabel" {
							Position = UDim2.fromOffset(12, 10),
							Size = UDim2.new(1, -24, 0, 22),
							BackgroundTransparency = 1,
							Text = request.profile.name .. (if request.palette then " · " .. request.palette else ""),
							TextColor3 = if dependencies.canvasOnly
								then Color3.fromRGB(110, 122, 142)
								else Color3.fromRGB(173, 188, 213),
							Font = Enum.Font.GothamMedium,
							TextSize = 11,
							TextXAlignment = Enum.TextXAlignment.Left,
						}
						local outline = Host.UIStroke {
							Color = Color3.fromRGB(103, 169, 255),
							Thickness = 1,
							Enabled = value.inspect,
						}
						local node = Host.Frame("PreviewCard" .. index) {
							LayoutOrder = index,
							Size = UDim2.fromOffset(400, 640),
							BackgroundColor3 = if dependencies.canvasOnly
								then Color3.fromRGB(255, 255, 255)
								else Color3.fromRGB(27, 32, 43),
							BorderSizePixel = 0,
							Host.UICorner { CornerRadius = UDim.new(0, 10) } :: unknown,
							outline,
							label,
							canvas,
						}
						local previewFacet = if dependencies.resolveFacet
							then dependencies.resolveFacet(value.selected)
							else Facet
						local mounted = session.mount(previewFacet, canvas, request.preview, {
							config = (function()
								local value = config(request.profile)
								if request.palette then
									value.palette = request.palette
								end
								return value
							end)(),
							register = function(dispose)
								table.insert(group.disposers, dispose)
							end,
							inputParent = dependencies.inputParent or widget,
							keyboardNavigation = dependencies.keyboardNavigation == true,
							onError = function(errorValue)
								patch({
									error = tostring(errorValue),
									status = "Preview error. Open source to repair it.",
								})
							end,
						})
						scale.Parent = mounted.root
						table.insert(group.sessions, mounted)
						table.insert(group.cards, {
							node = node,
							label = label,
							scale = scale,
							outline = outline,
							profile = request.profile,
							palette = request.palette,
							preview = request.preview,
							session = mounted,
						})
						table.insert(children, node)
					end
					return Host.Frame "PreviewGroup" {
						Size = if dependencies.canvasOnly and value.comparison == "Single"
							then UDim2.new(1, -48, 0, 0)
							else UDim2.new(),
						AutomaticSize = Enum.AutomaticSize.XY,
						BackgroundTransparency = 1,
						Visible = false,
						table.unpack((children :: unknown) :: { unknown }),
					}
				end, shell.canvas)
			end)
			group.root = root
		end, function(errorValue)
			return debug.traceback(tostring(errorValue), 2)
		end)
		if not ok then
			close(group)
			pendingGroup = nil
			error(err, 0)
		end
		pendingGroup = nil
		return group
	end
	local function install(nextDefinition: any): boolean
		local ok, result = pcall(build, nextDefinition)
		local group: any = result
		if not ok then
			patch({ error = tostring(group), status = "Refresh failed. The last working preview is retained." })
			return false
		end
		local old = active
		active = group
		arrange()
		group.root.Visible = true
		close(old)
		definition = nextDefinition
		local states = {}
		for _, preview in definition.previews do
			table.insert(states, preview.name)
		end
		local state = model:peek().state
		if not table.find(states, state) then
			state = states[1]
		end
		patch({
			states = states,
			state = state,
			error = "",
			status = `{definition.name}  ·  {#group.cards} live canvas(es)  ·  Input and text settings preview presentation; use Play for device validation.`,
		})
		return true
	end
	local function discover()
		local entries = {}
		for _, module in catalog.discover(dependencies.roots) do
			if string.find(string.lower(module.Name), string.lower(query), 1, true) then
				table.insert(entries, { module = module, name = string.gsub(module.Name, "%.preview$", "") })
			end
		end
		patch({ entries = entries })
	end
	local function cancelRefresh()
		if refreshJob and coroutine.status(refreshJob) ~= "dead" then
			task.cancel(refreshJob)
		end
		refreshJob = nil
		if pendingSnapshot then
			pendingSnapshot.dispose()
			pendingSnapshot = nil
		end
		if pendingGroup then
			close(pendingGroup)
			pendingGroup = nil
		end
	end
	local function refresh()
		if disposed or not model:peek().selected then
			return
		end
		epoch += 1
		cancelRefresh()
		local mine = epoch
		local selected = model:peek().selected
		patch({ status = "Refreshing from editor source…" })
		refreshJob = task.defer(function()
			local ok, result = xpcall(function()
				pendingSnapshot = if dependencies.load
					then dependencies.load(selected)
					else loader.prepare(assert(selected), dependencies.editor)
				local snapshot = pendingSnapshot
				local nextDefinition = snapshot.evaluate()
				if disposed or mine ~= epoch then
					snapshot.dispose()
					return false
				end
				if install(nextDefinition) then
					if loaded then
						loaded.dispose()
					end
					loaded = snapshot
				else
					snapshot.dispose()
				end
				pendingSnapshot = nil
				return true
			end, function(err)
				return debug.traceback(tostring(err), 2)
			end)
			if not ok and mine == epoch and not disposed then
				if pendingSnapshot then
					pendingSnapshot.dispose()
					pendingSnapshot = nil
				end
				patch({
					error = tostring(result),
					status = "Source could not load. The last working preview is retained.",
				})
			end
		end)
		task.delay(15, function()
			if not disposed and mine == epoch and refreshJob and coroutine.status(refreshJob) ~= "dead" then
				epoch += 1
				cancelRefresh()
				patch({
					error = "Preview timed out after 15 seconds. Remove waits for live game services from the sample factory.",
					status = "Refresh timed out. The last working preview is retained.",
				})
			end
		end)
	end
	local actions = {
		design = function(value)
			cancelRefresh()
			epoch += 1
			return install(value)
		end,
		setting = function(key, value)
			assert(table.find(choices[key], value), "Unsupported preview setting")
			patch({ [key] = value })
			if key == "comparison" or key == "device" then
				if definition then
					install(definition)
				end
			else
				arrange()
			end
		end,
		refresh = refresh,
		search = function(value)
			query = value
			discover()
		end,
		select = function(module)
			patch({ selected = module, state = "" })
			refresh()
		end,
		state = function(name)
			patch({ state = name })
			if definition then
				install(definition)
			end
		end,
		rotate = function()
			patch({ rotated = not model:peek().rotated })
			arrange()
		end,
		inspect = function()
			patch({ inspect = not model:peek().inspect })
			arrange()
		end,
		toggleLive = function()
			if dependencies.editor then
				patch({ live = not model:peek().live })
			else
				patch({ status = "Play previews use the running source. Stop and Play again after a source edit." })
			end
		end,
		reset = function()
			if definition then
				install(definition)
			end
		end,
		openSource = function()
			local selected = model:peek().selected
			if selected and dependencies.editor then
				dependencies.editor:OpenScriptDocumentAsync(selected)
			else
				patch({ status = "Open this preview module in Studio edit mode." })
			end
		end,
		cycle = function(key)
			local values = choices[key]
			local index = table.find(values, model:peek()[key]) or 1
			patch({ [key] = values[index % #values + 1] })
			if key == "comparison" or key == "device" then
				if definition then
					install(definition)
				end
			else
				arrange()
			end
		end,
	}
	shell = if dependencies.canvasOnly
		then chrome.canvas(Facet, widget)
		else chrome.mount(Facet, widget, model, actions)
	local connections = { shell.canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(arrange) }
	local function sourceChanged(module: Instance?)
		if disposed or not module or not model:peek().live or not model:peek().selected then
			return
		end
		local scope = assert(catalog.scope(assert(model:peek().selected)))
		if module ~= scope and not module:IsDescendantOf(scope) then
			return
		end
		debounce += 1
		local mine = debounce
		task.delay(0.35, function()
			if not disposed and mine == debounce then
				refresh()
			end
		end)
	end
	table.insert(
		connections,
		dependencies.editor
				and dependencies.editor.TextDocumentDidChange:Connect(function(document)
					sourceChanged(document:GetScript())
				end)
			or { Disconnect = function() end }
	)
	local sourceConnections = {}
	local function watchSource(node: Instance)
		if dependencies.editor and node:IsA("ModuleScript") and not sourceConnections[node] then
			sourceConnections[node] = node:GetPropertyChangedSignal("Source"):Connect(function()
				sourceChanged(node)
			end)
		end
	end

	for _, root in dependencies.roots do
		for _, node in root:GetDescendants() do
			watchSource(node)
		end
		table.insert(
			connections,
			root.DescendantAdded:Connect(function(node)
				watchSource(node)
				discover()
			end)
		)
		table.insert(
			connections,
			root.DescendantRemoving:Connect(function()
				task.defer(function()
					if not disposed then
						discover()
					end
				end)
			end)
		)
	end
	if dependencies.selection then
		table.insert(
			connections,
			dependencies.selection.SelectionChanged:Connect(function()
				for _, node in dependencies.selection:Get() do
					if catalog.isPreview(node) then
						actions.select(node)
						return
					end
				end
			end)
		)
	end
	discover()
	if not dependencies.canvasOnly and #model:peek().entries > 0 then
		actions.select(model:peek().entries[1].module)
	end
	return {
		model = model,
		shell = shell,
		actions = actions,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			cancelRefresh()
			epoch += 1
			debounce += 1
			for _, connection in connections do
				connection:Disconnect()
			end
			for _, connection in sourceConnections do
				connection:Disconnect()
			end
			close(active)
			if loaded then
				loaded.dispose()
			end
			shell.dispose()
		end,
	}
end

return workbench
