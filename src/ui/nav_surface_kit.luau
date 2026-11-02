--!strict
local ThemeTypes = require("./theme_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")

export type Attach = Nav.Attach
export type Kit = {
	gui: GuiService?,
	input: UserInputService?,
	service: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
	selecting: () -> (ComposeTypes.Use) -> boolean,
	preference: () -> (ComposeTypes.Use) -> number,
	keep: (...unknown) -> (),
	within: (Instance?, Instance) -> boolean,
	displayed: (Instance) -> boolean,
	firstSelectable: (Instance, string?, ((Instance) -> boolean)?) -> GuiObject?,
	attach: Attach,
	inset: (number, string, string?, ComposeTypes.Use?) -> number,
	skin: (GuiObject, string?, Nav.PanelSkin?) -> GuiObject,
	centered: (GuiObject, number) -> GuiObject,
}

return function(ctx: Types.Context, attach: Attach): Kit
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local services: Types.Services = ctx.config.services or {}
	local function service(name: "GuiService" | "UserInputService"): (GuiService | UserInputService)?
		if name == "GuiService" then
			return services.GuiService or (if game then game:GetService("GuiService") else nil)
		end
		return services.UserInputService or (if game then game:GetService("UserInputService") else nil)
	end
	local gui = service("GuiService") :: GuiService?
	local input = service("UserInputService") :: UserInputService?

	local function selecting(): (ComposeTypes.Use) -> boolean
		local active = gui ~= nil and gui.SelectedObject ~= nil
		local last: ComposeTypes.Value<Enum.UserInputType>? = nil
		if input and input.GetLastInputType then
			local source = Compose.cell(input:GetLastInputType())
			last = source
			runtime.connect(input, "LastInputTypeChanged", function(value: Enum.UserInputType)
				source:set(value)
			end)
		end
		local preferred = if input and input.GetPropertyChangedSignal then ctx.observe.PreferredInput(input) else nil
		return function(use: ComposeTypes.Use): boolean
			local preference = if preferred then use(preferred) else nil
			if preference == E.PreferredInput.Touch then
				return false
			end
			if preference == E.PreferredInput.Gamepad then
				return true
			end
			local value = if last then use(last) else nil
			return active
				and (value == nil or value == E.UserInputType.Keyboard or string.find(value.Name, "^Gamepad") ~= nil)
		end
	end

	local function preference(): (ComposeTypes.Use) -> number
		local source = if gui and gui.GetPropertyChangedSignal then ctx.observe.PreferredTransparency(gui) else nil
		return function(use: ComposeTypes.Use): number
			local value = if source then use(source) else 1
			return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
		end
	end
	local function keep(...: unknown): ()
		for index = 1, select("#", ...) do
			local content = select(index, ...)
			if content and type(content) ~= "function" then
				local node = content :: Instance
				local parent = node.Parent
				if parent then
					runtime.mount(function()
						return runtime.borrow(node)
					end, parent)
				end
				Compose.cleanup(function()
					if node.Parent ~= nil then
						node.Parent = nil
					end
				end)
			end
		end
	end
	local function within(node: Instance?, ancestor: Instance): boolean
		return node ~= nil and (node == ancestor or node:IsDescendantOf(ancestor))
	end
	local function displayed(node: Instance): boolean
		local at: Instance? = node
		while at and not at:IsA("LayerCollector") do
			if at:IsA("GuiObject") and not at.Visible then
				return false
			end
			at = at.Parent
		end
		return at ~= nil
	end
	local function firstSelectable(node: Instance, preferred: string?, skip: ((Instance) -> boolean)?): GuiObject?
		if skip and skip(node) then
			return nil
		end
		local scrolling: ScrollingFrame? = nil
		if node:IsA("GuiObject") then
			if not node.Visible or not node.Interactable then
				return nil
			end
			if (preferred == nil or node.Name == preferred) and node.Selectable then
				if not node:IsA("ScrollingFrame") or node:GetAttribute("FacetSelectionOwner") == true then
					return node
				end
				scrolling = node
			end
		end
		for _, child in node:GetChildren() do
			local found = firstSelectable(child, preferred, skip)
			if found then
				return found
			end
		end
		return scrolling
	end
	local function inset(authored: number, side: string, slot: string?, use: ComposeTypes.Use?): number
		local package = ctx.read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use)
		local recipe = if package and package.chrome then package.chrome[slot or "panel"] else nil
		local carve = if recipe then recipe.contentInsets else nil
		if carve == nil then
			return authored
		end
		local value = if side == "top"
			then carve.top
			elseif side == "bottom" then carve.bottom
			elseif side == "left" then carve.left
			else carve.right
		return math.max(authored, value or 0)
	end
	local function skin(panel: GuiObject, slot: string?, options: Nav.PanelSkin?): GuiObject
		local settings: Nav.PanelSkin = options or {}
		local extra = settings.reserve
		local _, artwork = ctx.skin(panel, slot or "panel", { label = settings.title, onCaption = settings.onCaption })
		if artwork then
			artwork.ZIndex = -1
		end
		local padding = if settings.padding == false
			then nil
			else settings.padding or panel:FindFirstChildWhichIsA("UIPadding")
		if padding and (ctx.config.theme ~= nil or extra) then
			local function side(name: string, authored: UDim): (ComposeTypes.Use) -> UDim
				return function(use: ComposeTypes.Use): UDim
					return ctx.types.UDim.new(
						0,
						inset(
							if authored.Scale == 0
									and authored.Offset == 0
									and extra == nil
									and (slot == nil or slot == "panel")
								then ctx.metric("space.m", use)
								else authored.Offset,
							name,
							slot,
							use
						) + (if extra then extra(name, use) else 0)
					)
				end
			end
			runtime.decorate(padding, {
				PaddingTop = side("top", padding.PaddingTop),
				PaddingBottom = side("bottom", padding.PaddingBottom),
				PaddingLeft = side("left", padding.PaddingLeft),
				PaddingRight = side("right", padding.PaddingRight),
			})
		end
		return panel
	end
	local function centered(panel: GuiObject, width: number): GuiObject
		runtime.decorate(panel, {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			Size = D2.new(1, -32, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		attach(panel, { Host.UISizeConstraint { MaxSize = V2.new(width or 440, math.huge) } })
		return panel
	end
	return {
		gui = gui,
		input = input,
		service = service :: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
		selecting = selecting,
		preference = preference,
		keep = keep,
		within = within,
		displayed = displayed,
		firstSelectable = firstSelectable,
		attach = attach,
		inset = inset,
		skin = skin,
		centered = centered,
	}
end
