--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Theme = require("./theme_types")

return function(
	ctx: Shared.Context,
	config: Shared.Config,
	services: Shared.Services,
	themes: Theme.Themes,
	observeStyled: (Instance, string) -> ComposeTypes.Cell<unknown>
)
	local Compose, runtime, types, Host = ctx.Compose, ctx.runtime, ctx.types, ctx.Host
	local Enum = types.Enum
	local read = ctx.read
	local hapticWaves: { [string]: { number } } = {
		warning = { 0, 0, 10, 0.7, 40, 0, 90, 0.7, 130, 0 },
		error = { 0, 0, 8, 1, 40, 0, 80, 1, 112, 0, 152, 1, 190, 0 },
	}
	local hapticPresets: { [string]: string } =
		{ selection = "UIClick", impact = "GameplayCollision", success = "UINotification" }
	local hapticPool: { [string]: HapticEffect } = {}
	ctx.haptic = function(kind: unknown): HapticEffect?
		if kind == true then
			kind = config.pressHaptic
		end
		if kind == nil or kind == false then
			return nil
		end
		if type(kind) ~= "string" then
			return kind :: HapticEffect
		end
		local pooled = hapticPool[kind]
		if pooled then
			return pooled
		end
		local wave = hapticWaves[kind]
		assert(
			wave or hapticPresets[kind],
			`Facet haptic: unknown feedback kind '{kind}'. Use selection, impact, success, warning or error`
		)
		local effect = runtime.host.render.createNode("HapticEffect") :: HapticEffect
		effect.Name = `FacetHaptic_{kind}`
		if wave then
			effect.Type = Enum.HapticEffectType.Custom
			local keys = {}
			for index = 1, #wave, 2 do
				table.insert(
					keys,
					types.FloatCurveKey.new(wave[index], wave[index + 1], Enum.KeyInterpolationMode.Linear)
				)
			end
			effect:SetWaveformKeys(keys)
		else
			effect.Type = ((Enum.HapticEffectType :: unknown) :: { [string]: Enum.HapticEffectType })[hapticPresets[kind]]
		end
		effect.Parent = services.Workspace
		hapticPool[kind] = effect
		return effect
	end
	function ctx.playWhileShown(timeline: Shared.Playback, node: Instance)
		local ancestry = Compose.cell(0)
		runtime.connect(node, "AncestryChanged", function()
			ancestry:set(ancestry:peek() + 1)
		end)
		Compose.watch(function(use)
			use(ancestry)
			local sources: { ComposeTypes.Readable<boolean> } = {}
			local at: Instance? = node
			while at do
				if at:IsA("GuiObject") then
					table.insert(sources, ctx.observe.Visible(at))
				elseif at:IsA("LayerCollector") then
					table.insert(sources, ctx.observe.Enabled(at))
					break
				end
				at = at.Parent
			end
			Compose.watch(function(use: ComposeTypes.Use)
				for _, source in sources do
					if not use(source) then
						timeline:pause()
						return
					end
				end
				timeline:play()
			end)
		end)
	end
	local fades = (setmetatable({}, { __mode = "k" }) :: unknown) :: {
		[Instance]: { source: ComposeTypes.Cell<{ Shared.Value<number> }>, transparency: (ComposeTypes.Use) -> number },
	}
	function ctx.fadeTo(node: Instance, value: Shared.Value<number>): ()
		assert(fades[node], "Facet: fadeTo needs a node made by ctx.fade").source:set({ value })
	end
	function ctx.fade(properties: Shared.CanvasGroupNativeProps, persistent: boolean?, chrome: boolean?): Frame
		local fields = (properties :: unknown) :: { [unknown]: unknown }
		local source = Compose.cell({ (fields.GroupTransparency or 0) :: Shared.Value<number> })
		fields.GroupTransparency = nil
		local node = Host.Frame((properties :: unknown) :: Shared.FrameNativeProps)
		local function amount(use: ComposeTypes.Use): number
			return read(use(source)[1] :: Shared.Value<number>, use) or 0
		end
		local shown = ctx.observe.Visible(node)
		local warming = Compose.cell(false)
		local frames = services.RunService
		local function transparency(use: ComposeTypes.Use): number
			return if use(warming) then 1 else amount(use)
		end
		fades[node] = { source = source, transparency = transparency }
		local function paint(use: ComposeTypes.Use): NumberSequence
			return types.NumberSequence.new(transparency(use))
		end
		local latched = Compose.cell(true)
		local stop = runtime.mountFragment(function()
			return {
				Compose.show(function(use: ComposeTypes.Use)
					return chrome ~= false and use(shown) and transparency(use) > 0
				end, function()
					node:AddTag("facet-fading")
					Compose.cleanup(function()
						node:RemoveTag("facet-fading")
					end)
					return Compose.fragment(function()
						return {
							Host.UIGradient "FadePaint" { Transparency = paint },
							ctx.styled(
								Host.UIStroke "FadeStroke" {
									Host.UIGradient "FadePaint" {
										Transparency = function(use: ComposeTypes.Use): NumberSequence
											return if use(latched) then types.NumberSequence.new(1) else paint(use)
										end,
									},
								},
								"fade-stroke"
							),
						}
					end)
				end),
				Compose.show(function(use: ComposeTypes.Use)
					return use(shown) and (persistent == true or amount(use) > 0)
				end, function()
					local automatic = ctx.observe.AutomaticSize(node)
					local leaving = frames ~= nil and (read(source:peek()[1] :: Shared.Value<number>) or 0) < 0.5
					local gather: (() -> ())? = nil
					if frames then
						warming:set(not leaving)
						local connection: RBXScriptConnection? = nil
						connection = frames.Heartbeat:Connect(function()
							if connection then
								connection:Disconnect()
								connection = nil
							end
							warming:set(false)
							if gather then
								gather()
							end
						end)
						Compose.cleanup(function()
							if connection then
								connection:Disconnect()
							end
							warming:set(false)
						end)
					end
					local group = Host.CanvasGroup "Fade" {
						BackgroundTransparency = 1,
						Visible = false,
						Size = function(use: ComposeTypes.Use)
							local mode = use(automatic)
							local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
							local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
							return types.UDim2.fromScale(if freeX then 0 else 1, if freeY then 0 else 1)
						end,
						AutomaticSize = automatic,
						GroupTransparency = function(use: ComposeTypes.Use)
							return transparency(use)
						end,
					}
					local gui = config.guiService
					local function keepSelection(move: () -> ())
						local held = if gui then gui.SelectedObject else nil
						move()
						if gui and held and gui.SelectedObject ~= held and held:IsDescendantOf(node) then
							gui.SelectedObject = held
						end
					end
					group.Parent = node
					local function carried(child: Instance): boolean
						return child ~= group
							and (
								child:IsA("GuiBase2d")
								or child:IsA("Path2D")
								or child:IsA("Folder")
								or child:IsA("UIGridStyleLayout")
							)
					end
					gather = function()
						gather = nil
						keepSelection(function()
							for _, child: Instance in node:GetChildren() do
								if carried(child) then
									(child :: Instance).Parent = group
								end
							end
							group.Visible = true
						end)
					end
					assert(gather)()
					local collecting = true
					local delayed = if task == nil and frames == nil then runtime.scheduler() else nil
					runtime.connect(
						node,
						"ChildAdded",
						Compose.bindOwner(function(child: Instance)
							if collecting and carried(child) then
								local function collect()
									if collecting and child.Parent == node then
										keepSelection(function()
											child.Parent = group
										end)
									end
								end
								if delayed then
									delayed.after(0, collect)
								elseif task == nil and frames then
									local stop: (() -> ())? = nil
									stop = runtime.connect(frames, "Heartbeat", function()
										if stop then
											stop()
											stop = nil
										end
										collect()
									end)
								else
									local release: (() -> ())? = nil
									local work: thread? = nil
									work = task.defer(function()
										work = nil
										if release then
											release()
										end
										collect()
									end)
									release = Compose.cleanup(function()
										if work then
											task.cancel(work)
										end
									end)
								end
							end
						end)
					)
					Compose.cleanup(function()
						collecting = false
						keepSelection(function()
							for _, child in group:GetChildren() do
								child.Parent = node
							end
						end)
					end)
					latched:set(false)
					return Compose.fragment(function()
						return {}
					end)
				end),
			}
		end, node)
		Compose.cleanup(stop)
		return node
	end
	function ctx.skin(
		node: GuiObject,
		slot: string,
		skinOptions: Shared.SkinStateOptions?
	): (ComposeTypes.Dispose?, GuiObject?)
		if config.theme == nil then
			return nil, nil
		end
		local function hasSkin(use: ComposeTypes.Use?): boolean
			local package = ctx.read(config.theme, use) :: Theme.ThemePackage?
			local recipe = package and (package.chrome or {})[slot]
			return recipe ~= nil and (recipe.kind ~= "native" and recipe.kind ~= "none" or recipe.shadow ~= nil)
		end
		if not Compose.isReadable(config.theme) and type(config.theme) ~= "function" then
			if not hasSkin() then
				return nil, nil
			end
		end
		local stateOptions: Shared.SkinStateOptions = skinOptions or {}
		local function createSkin(): Frame
			local state = ctx.observe.GuiState(node)
			local background = observeStyled(node, "BackgroundTransparency")
			return themes.skin(runtime, config.theme, slot, {
				types = types,
				target = node,
				shadowTransparency = function(use: ComposeTypes.Use)
					local package = ctx.read(config.theme, use) :: Theme.ThemePackage?
					local recipe = package and (package.chrome or {})[slot]
					local fill = if recipe and recipe.kind == "native"
						then math.clamp(use(background) :: number, 0, 1)
						else 0
					local fade = if fades[node] then fades[node].transparency(use) else 0
					return 1 - (1 - fill) * (1 - fade)
				end,
				label = if stateOptions.label ~= nil
					then stateOptions.label
					elseif node:IsA("TextButton") or node:IsA("TextLabel") then ctx.observe.Text(node)
					else nil,
				onCaption = stateOptions.onCaption,
				state = function(use: ComposeTypes.Use)
					if ctx.read(stateOptions.disabled, use) == true then
						return "disabled"
					end
					local value = use(state)
					if value == Enum.GuiState.Press then
						return "pressed"
					end
					if value == Enum.GuiState.Hover then
						return "hover"
					end
					if ctx.read(stateOptions.selected, use) == true then
						return "selected"
					end
					return "default"
				end,
				selected = function(use: ComposeTypes.Use)
					return ctx.read(stateOptions.selected, use) == true
				end,
				ZIndex = 0,
			})
		end
		local dispose, art = runtime.mount(function()
			if hasSkin() then
				return createSkin()
			end
			local needed = false
			return Host.Frame "SkinHost" {
				Size = types.UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 0,
				Compose.show(function(use: ComposeTypes.Use): boolean
					needed = needed or hasSkin(use)
					return needed
				end, createSkin),
			}
		end, node)
		if art and node:FindFirstChildWhichIsA("UIGridStyleLayout") then
			local _, chrome = runtime.mount(function()
				return Host.Folder "Chrome" {}
			end, node);
			(art :: GuiObject).Parent = chrome :: Instance
		end
		return dispose, art :: GuiObject?
	end
end
