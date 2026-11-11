--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local overlayPresence = require("./nav_overlay_presence")
local regionPresence = require("./region_presence")
local fontReadiness = require("./font_readiness")
local textMeasure = require("./text_measure")
local geometrySignature = require("./geometry_signature")
local arrival = require("./overlay_arrival")
local transitions = require("./transition")

export type Portal = {
	available: (GuiObject) -> ComposeTypes.ReadOnlyValue<boolean>,
	parent: (Instance) -> GuiBase2d?,
	overlay: (GuiObject, Types.Input<boolean>, (Nav.PresencePhase?) -> Instance, Nav.OverlayOptions?) -> Types.Child,
}

local function nearestLink(node: Instance): Instance?
	local at: Instance? = node
	while at do
		local link = at:FindFirstChildWhichIsA("StyleLink")
		if link then
			return link
		end
		at = at.Parent
	end
	return nil
end

return function(ctx: Types.Context, presence: overlayPresence.Presence): Portal
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local departure = presence.departure
	local function available(anchor: GuiObject, changed: (() -> ())?): ComposeTypes.ReadOnlyValue<boolean>
		local owner = assert(Compose.currentOwner())
		local value = Compose.cell(false)
		local ancestryOwner: ComposeTypes.Owner?
		local function locate()
			if ComposeTypes.owner.isDisposed(owner) then
				return
			end
			if ancestryOwner then
				ComposeTypes.owner.dispose(ancestryOwner)
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
			local nextOwner = ComposeTypes.owner.createChild(owner)
			ancestryOwner = nextOwner
			Compose.withOwner(nextOwner, function()
				local sources: { ComposeTypes.ReadOnlyValue<boolean> } = {}
				local at: Instance? = anchor
				local attached = false
				while at do
					if at:IsA("GuiObject") then
						if at ~= anchor or anchor:GetAttribute("FacetOverlayPlaceholder") ~= true then
							table.insert(sources, regionPresence[at] or ctx.observe.Visible(at))
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

	local function arrive(
		build: () -> Instance,
		arrived: ComposeTypes.Value<boolean>,
		phase: Nav.PresencePhase
	): Instance
		local frames = ctx.config.services and ctx.config.services.RunService
		local built: Instance? = nil
		local wrapper: Frame? = nil
		if frames and frames.PreRender then
			wrapper = ctx.fade({
				Name = "OverlayArrival",
				BackgroundTransparency = 1,
				Size = ctx.types.UDim2.fromScale(1, 1),
				GroupTransparency = function(use: ComposeTypes.Use): number
					return if use(arrived) then 0 else 1
				end,
				Interactable = arrived,
				Compose.fragment(function(): { Instance }
					local node = build()
					built = node
					return { node }
				end),
			}, false, false)
		else
			built = build()
		end
		local node = assert(built)
		if frames == nil then
			arrived:set(true)
			return node
		end
		local surfaces: { GuiObject } = {}
		local parts: { Instance } = if node:IsA("GuiObject") then { node } else node:GetChildren()
		for _, part in parts do
			if part:IsA("GuiObject") and part.Visible then
				table.insert(surfaces, part)
			end
		end
		if #surfaces == 0 then
			arrived:set(true)
			return node
		end
		if frames.PreRender == nil then
			arrived:set(true)
			for _, surface in surfaces do
				surface.Visible = false
			end
			local connection: RBXScriptConnection? = nil
			connection = frames.Heartbeat:Connect(function()
				if connection then
					connection:Disconnect()
					connection = nil
				end
				for _, surface in surfaces do
					surface.Visible = true
				end
			end)
			Compose.cleanup(function()
				if connection then
					connection:Disconnect()
				end
			end)
			return node
		end
		local fontsReady = fontReadiness(ctx, surfaces)
		local signature = geometrySignature()
		local snapshot, complete = 0, false
		local allowed: boolean? = nil
		local ready = arrival.prepared(phase)
			or ctx.runtime.settled {
				sample = function(): number
					return snapshot
				end,
				ready = function(): boolean
					local filled = false
					local measured = true
					for _, surface in surfaces do
						local descendants = surface:GetDescendants()
						table.insert(descendants, surface)
						filled = filled or (surface.AbsoluteSize.X > 0 and surface.AbsoluteSize.Y > 0)
						for _, child in descendants do
							measured = measured and not textMeasure.pending(child)
							if child:IsA("GuiObject") then
								filled = filled
									or (child.Visible and child.AbsoluteSize.X > 0 and child.AbsoluteSize.Y > 0)
								signature.push(child.AbsolutePosition)
								signature.push(child.AbsoluteSize)
								signature.push(child.Visible)
								if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
									signature.push(child.TextBounds)
								end
							end
						end
					end
					snapshot, complete, allowed = signature.finish(), filled, fontsReady() and measured
					return allowed ~= false
				end,
				equals = function(a: number, b: number): boolean
					return complete and a == b
				end,
			}
		Compose.watch(function(use: ComposeTypes.Use)
			if use(ready) then
				arrived:set(true)
			end
		end)
		if node:GetAttribute("FacetArrivalGroup") == true then
			return node
		end
		local depths: { ComposeTypes.ReadOnlyValue<number> } = {}
		for _, surface in surfaces do
			local depth = Compose.cell(surface.ZIndex)
			Compose.cleanup(assert(runtime.host.observation).observeProperty(surface, "ZIndex", function()
				depth:set(surface.ZIndex)
			end))
			table.insert(depths, depth)
		end
		local group = assert(wrapper)
		runtime.decorate(group, {
			ZIndex = function(use: ComposeTypes.Use): number
				local highest = 1
				for _, depth in depths do
					highest = math.max(highest, use(depth))
				end
				return highest
			end,
		})
		return group
	end
	local function parent(anchor: Instance): GuiBase2d?
		local layer = (ctx.config.overlayParent or anchor:FindFirstAncestorWhichIsA("LayerCollector")) :: GuiBase2d?
		local host = if layer then ctx.overlayHosts[layer] else nil
		if host and host:IsA("LayerCollector") then
			layer = host :: GuiBase2d
		end
		if layer and layer:IsA("SurfaceGui") and not layer.ClipsDescendants then
			layer.ClipsDescendants = true
		end
		return layer
	end
	local function overlay(
		anchor: GuiObject,
		presented: Types.Input<boolean>,
		build: (Nav.PresencePhase?) -> Instance,
		options: Nav.OverlayOptions?
	): Types.Child
		local owner = assert(Compose.currentOwner())
		local destination = Compose.cell<<Instance?>>(nil)
		destination:set(if options and options.parent then options.parent() else ctx.config.overlayParent)
		local function locate()
			if ComposeTypes.owner.isDisposed(owner) then
				return
			end
			if options and options.parent then
				destination:set(options.parent() or parent(anchor))
				return
			end
			if ctx.config.overlayParent then
				return
			end
			destination:set(parent(anchor))
		end
		local enabled = available(anchor, locate)
		local condition = function(use: ComposeTypes.Use): boolean
			return use(enabled) and ctx.read<<boolean>>(presented, use)
		end
		return Compose.switch(destination, {}, function()
			local target = destination:peek()
			if target == nil then
				return Compose.fragment(function()
					return {}
				end)
			end
			local age: ComposeTypes.ReadOnlyValue<number>? = nil
			local activePhase: Nav.PresencePhase? = nil
			local function render(phase: Nav.PresencePhase?): Instance
				if phase and options and options.motion then
					age = runtime.timeline({ duration = 0.001 }).elapsed
				end
				local function themed(): Instance
					local services = ctx.config.services.RunService
					local arrived = Compose.cell(services == nil or services.PreRender == nil)
					local entering: Nav.PresencePhase = phase or { exiting = Compose.cell(false) }
					activePhase = entering
					arrival.bind(entering, arrived)
					return arrive(function()
						local node = build(entering)
						local scope: Instance? = anchor
						while scope and scope ~= target do
							local link = scope:FindFirstChildWhichIsA("StyleLink")
							if link and nearestLink(target) == link then
								break
							end
							if link then
								if link:IsA("StyleLink") then
									local sheet = runtime.observe(link, "StyleSheet")
									runtime.mountFragment(function()
										return {
											Host.StyleLink {
												StyleSheet = function(use: ComposeTypes.Use): StyleSheet?
													local value = use(sheet)
													return if typeof(value) == "Instance"
															and value:IsA("StyleSheet")
														then value
														else nil
												end,
											},
										}
									end, node)
								end
								break
							end
							scope = scope.Parent
						end
						return node
					end, arrived, entering)
				end
				local failureHandler = options and options.failure
				if failureHandler then
					return Host.Folder {
						Compose.boundary(function()
							return themed()
						end, function(failure, _retry)
							return failureHandler(failure)
						end),
					}
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
			if presence then
				local fallback = presence.exit
				presence = {
					exit = function(nodes)
						local phase = activePhase
						local completed = if phase then transitions.completions[phase] else nil
						return if completed then { completed = completed } else fallback(nodes)
					end,
				}
			end
			local function presentation(): Types.Child
				return if presence
					then Compose.presence(condition, render, presence)
					else Compose.show(condition, function()
						return render(nil)
					end)
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
	return {
		available = function(anchor)
			return available(anchor, nil)
		end,
		parent = parent,
		overlay = overlay,
	}
end
