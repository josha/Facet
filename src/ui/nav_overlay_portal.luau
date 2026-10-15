--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local overlayPresence = require("./nav_overlay_presence")

export type Portal = {
	available: (GuiObject) -> ComposeTypes.Readable<boolean>,
	parent: (Instance) -> GuiBase2d?,
	overlay: (GuiObject, Types.Value<boolean>, (Nav.PresencePhase?) -> Instance, Nav.OverlayOptions?) -> Types.Child,
}

return function(ctx: Types.Context, presence: overlayPresence.Presence): Portal
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local departure = presence.departure
	local function available(anchor: GuiObject, changed: (() -> ())?): ComposeTypes.Readable<boolean>
		local owner = assert(Compose.currentOwner())
		local value = Compose.cell(false)
		local ancestryOwner: ComposeTypes.Owner?
		local function locate()
			if owner.isDisposed() then
				return
			end
			if ancestryOwner then
				ancestryOwner.dispose()
				ancestryOwner = nil
			end
			local root: Instance? = anchor
			while root and not root:IsA("LayerCollector") do
				root = root.Parent
			end
			if root == nil then
				value:set(false)
				return
			end
			local nextOwner = owner.createChild()
			ancestryOwner = nextOwner
			Compose.withOwner(nextOwner, function()
				local sources: { ComposeTypes.Readable<boolean> } = {}
				local at: Instance? = anchor
				local attached = false
				while at do
					if at:IsA("GuiObject") then
						if at ~= anchor or anchor:GetAttribute("FacetOverlayPlaceholder") ~= true then
							table.insert(sources, ctx.observe.Visible(at))
						end
						table.insert(sources, ctx.observe.Interactable(at))
					end
					if at:IsA("LayerCollector") then
						attached = true
						table.insert(sources, ctx.observe.Enabled(at))
						break
					end
					at = at.Parent
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local enabled = attached
					for _, source in sources do
						if not use(source) then
							enabled = false
						end
					end
					value:set(enabled)
				end)
			end)
		end
		local function refresh()
			locate()
			if changed then
				changed()
			end
		end
		runtime.connect(anchor, "AncestryChanged", refresh)
		refresh()
		return value
	end

	local function arrive(node: Instance): Instance
		local frames = ctx.config.services and ctx.config.services.RunService
		if frames == nil then
			return node
		end
		local surfaces: { GuiObject } = {}
		local parts: { Instance } = if node:IsA("GuiObject") then { node } else node:GetChildren()
		for _, part in parts do
			if part:IsA("GuiObject") and part.Visible then
				part.Visible = false
				table.insert(surfaces, part)
			end
		end
		if #surfaces == 0 then
			return node
		end
		local connection: RBXScriptConnection? = nil
		connection = frames.Heartbeat:Connect(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			for _, surface in surfaces do
				if not surface.Visible then
					surface.Visible = true
				end
			end
		end)
		Compose.cleanup(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end)
		return node
	end
	local function parent(anchor: Instance): GuiBase2d?
		local layer = (ctx.config.overlayParent or anchor:FindFirstAncestorWhichIsA("LayerCollector")) :: GuiBase2d?
		if layer and layer:IsA("SurfaceGui") and not layer.ClipsDescendants then
			layer.ClipsDescendants = true
		end
		return layer
	end
	local function overlay(
		anchor: GuiObject,
		presented: Types.Value<boolean>,
		build: (Nav.PresencePhase?) -> Instance,
		options: Nav.OverlayOptions?
	): Types.Child
		local owner = assert(Compose.currentOwner())
		local destination = Compose.cell(nil :: Instance?)
		destination:set(ctx.config.overlayParent)
		local function locate()
			if owner.isDisposed() then
				return
			end
			if ctx.config.overlayParent then
				return
			end
			destination:set(parent(anchor))
		end
		local enabled = available(anchor, locate)
		local condition = function(use: ComposeTypes.Use): boolean
			return use(enabled) and ctx.read(presented, use)
		end
		return Compose.switch(destination, {}, function()
			local target = destination:peek()
			if target == nil then
				return Compose.fragment(function()
					return {}
				end)
			end
			local age: ComposeTypes.Readable<number>? = nil
			local function render(phase: Nav.PresencePhase?): Instance
				if phase then
					age = runtime.timeline({ duration = 0.001 }).elapsed
				end
				local function themed(): Instance
					local node = build(phase)
					local scope: Instance? = anchor
					while scope and scope ~= target do
						local link = scope:FindFirstChildWhichIsA("StyleLink")
						if link then
							local observe = (
								ctx.observe :: unknown
							) :: { StyleSheet: (StyleLink) -> ComposeTypes.Cell<StyleSheet?> }
							local sheet = observe.StyleSheet(link :: StyleLink)
							local Links = (Host :: unknown) :: { StyleLink: ({ StyleSheet: unknown }) -> Instance }
							runtime.mountFragment(function()
								return { Links.StyleLink { StyleSheet = sheet } }
							end, node)
							break
						end
						scope = scope.Parent
					end
					return arrive(node)
				end
				if options and options.failure then
					return Host.Folder({
						Compose.boundary(function()
							return themed()
						end, options.failure),
					})
				end
				return themed()
			end
			local presence = if options and options.presence
				then options.presence
				elseif options and options.motion then departure(options.motion, anchor, function(): boolean
					local elapsed = age
					return elapsed ~= nil and elapsed:peek() > 0
				end)
				else nil
			local function presentation(): Types.Child
				return if presence
					then Compose.presence(condition, render, presence)
					else Compose.show(condition, render)
			end
			local identity = options and options.identity
			runtime.mountFragment(function()
				return {
					if identity then Compose.switch(identity, {}, presentation) else presentation(),
				}
			end, target)
			return Compose.fragment(function()
				return {}
			end)
		end)
	end
	return { available = available, parent = parent, overlay = overlay }
end
