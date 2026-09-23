--!strict
--[[ Popover — content presented against a trigger or a source, as an anchored
	panel, or as a sheet on a compact touch screen.

	THE FACT IS THE CALLER'S. `isPresented` is a Bound<boolean> the popover renders
	and never writes; `onPresentedChange(next)` is a PROPOSAL. A trigger press,
	Cancel, an outside tap or a sheet's Close/drag asks, and the surface closes
	only when the caller's fact actually changed — a refused proposal leaves the
	same surface, focus and content exactly where they were. `onDismiss(reason)`
	reports an actual closure once, after its cleanup.

	REASONS: "cancel" (Cancel, a sheet's Close or drag, a caller-driven false,
	owner disposal), "outside" (a tap outside — an open popover is modal, so a
	press on its own trigger is one), "anchorLost" (the source node this
	presentation acquired was removed or replaced), and "trigger" for the
	proposal a trigger press makes.

	THE SOURCE IDENTITY IS THIS PRESENTATION'S. A path source is followed through
	its mounted node; when that node goes away or is replaced, the presentation is
	released at once, false is proposed and anchorLost reported — the caller's
	fact is left alone, and a still-true fact never reopens against a replacement
	until the caller starts a new false -> true request. A node that has not
	mounted YET is not a loss. A rect source is copied data with no tail.

	ONE CONTENT OWNER. Each presentation builds its content inside its own surface;
	a live switch between the panel and the sheet (the compact touch fact changed)
	is silent — no proposal, no onDismiss — disposes the old surface before building
	the new one, and puts focus back on the same content path when it exists. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local anchorPlacement = require("../layout/anchor_placement")
local focusMap = require("../present/focus_map")
local menuRecipe = require("./menu_recipe")
local themeSnapshot = require("../themes/snapshot")
local sheetLib = require("./sheet")
local overlayParts = require("./overlay_parts")

local popover = {}

local specTypes = require("../spec_types/popover")
export type Spec = specTypes.Spec

local KEYS = specGuard.keySet({
	"align",
	"compact",
	"content",
	"crossOffset",
	"edge",
	"env",
	"gap",
	"id",
	"isPresented",
	"maxHeight",
	"maxWidth",
	"onDismiss",
	"onPresentedChange",
	"source",
	"tail",
	"trigger",
})
local SOURCE_KEYS = specGuard.keySet({ "path", "rect" })
local DUMP_SCHEMA = "facet-popover-dump/1"
local PANEL_ID = "Panel"
local BODY_ID = "Body"

local function positive(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v < math.huge
end

-- the root of the mounted Facet tree a node belongs to (the scene's own root
-- above it carries no path)
local function rootOf(node: any): any
	local n = node
	while n ~= nil and n.parent ~= nil and n.parent.path ~= nil do
		n = n.parent
	end
	return n
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	specGuard.assertKnownKeys("UI.Popover", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Popover"
	local where = `UI.Popover('{id}')`

	-- ===== the contract, refused at construction ==========================
	if spec.isPresented == nil then
		error(`Facet {where}: \`isPresented\` is required — the caller's Bound<boolean> fact.`, 0)
	end
	if spec.onPresentedChange ~= nil and type(spec.onPresentedChange) ~= "function" then
		error(`Facet {where}: \`onPresentedChange(next)\` is a function.`, 0)
	end
	if spec.onDismiss ~= nil and type(spec.onDismiss) ~= "function" then
		error(`Facet {where}: \`onDismiss(reason)\` is a function.`, 0)
	end
	if type(spec.content) ~= "function" then
		error(`Facet {where}: \`content\` is a component factory — a function returning the content.`, 0)
	end
	if (spec.trigger == nil) == (spec.source == nil) then
		error(`Facet {where}: give exactly one of \`trigger\` (a blueprint) or \`source\` (\{ path } | \{ rect }).`, 0)
	end
	local source: any = spec.source
	local rect: any = nil
	if source ~= nil then
		if type(source) ~= "table" then
			error(`Facet {where}: \`source\` is \{ path = "…" } or \{ rect = \{ x, y, w, h } }.`, 0)
		end
		specGuard.assertKnownKeys("UI.Popover", source, SOURCE_KEYS, "source")
		local hasPath, hasRect = type(source.path) == "string", type(source.rect) == "table"
		if hasPath == hasRect then
			error(`Facet {where}: \`source\` names exactly one of \`path\` or \`rect\`.`, 0)
		end
		if hasRect then
			local r = source.rect
			for _, key in { "x", "y", "w", "h" } do
				if type(r[key]) ~= "number" or r[key] ~= r[key] or math.abs(r[key]) == math.huge then
					error(`Facet {where}: \`source.rect.{key}\` is a finite number.`, 0)
				end
			end
			-- construction-only: copied, never followed
			rect = { x = r.x, y = r.y, w = r.w, h = r.h }
		end
	end
	anchorPlacement.assertEdge(spec.edge, `{where} edge`)
	anchorPlacement.assertAlign(spec.align, `{where} align`)
	anchorPlacement.assertCrossOffset(spec.crossOffset, `{where}`)
	for _, key in { "maxWidth", "maxHeight" } do
		if (spec :: any)[key] ~= nil and not positive((spec :: any)[key]) then
			error(`Facet {where}: \`{key}\` is a positive finite number of px, chrome included.`, 0)
		end
	end
	if spec.tail ~= nil and type(spec.tail) ~= "boolean" then
		error(`Facet {where}: \`tail\` is true or false.`, 0)
	end
	local compact = spec.compact or "sheet"
	if compact ~= "sheet" and compact ~= "popover" then
		error(`Facet {where}: \`compact\` is "sheet" (default) or "popover".`, 0)
	end
	local facts = surfaceEnv.forSpec(core, spec.env)
	local env = if compact == "sheet" then facts else nil

	-- ===== the caller's fact and the route =================================
	local wanted = ownedFormula(owner, function(use)
		return selection.read(spec.isPresented, use) == true
	end)
	local route = ownedFormula(owner, function(use)
		if env == nil then
			return "popover"
		end
		local sizeClass = use(env:get("sizeClass"))
		local classes = use(env:get("interactionClasses"))
		return if sizeClass == "compact" and menuRecipe.touchPrimary(classes) then "sheet" else "popover"
	end)

	-- ===== presentation state ==============================================
	local live: any = nil -- { route, handle?, sheet?, identity, generation }
	local lost = false -- an acquired source went away; wait for false -> true
	local closingReason: string? = nil
	local disposed = false
	local generation = 0
	local presentAnchoredFn: any = nil
	local dismissFn: any = nil
	local graph: any = nil
	local selfNode: any = nil
	local triggerNode: any = nil
	-- the owning surface's FIRST geometry feed runs while it is being built, before
	-- it joins the presenter's stack; a popover opened there would sit beneath it
	local ready = false
	local surfaceId = `Popover-{id}`
	local warnedUnmounted = false

	local function report(reason: string)
		if spec.onDismiss ~= nil then
			spec.onDismiss(reason)
		end
	end

	-- the proposal: true when the caller's fact now reads `next`
	local function propose(next: boolean, reason: string): boolean
		if spec.onPresentedChange == nil then
			return false
		end
		if not next then
			closingReason = reason
		end
		local accepted = false
		overlayParts.call(spec.onPresentedChange, function()
			accepted = wanted:peek() == next
			if not accepted then
				closingReason = nil
			end
		end, next)
		return accepted
	end

	-- the node this presentation is anchored to right now, or nil when unmounted
	local function currentIdentity(): any
		if rect ~= nil then
			return rect
		end
		if spec.trigger ~= nil then
			return triggerNode
		end
		-- the path names a node from its own screen's root; a screen embedded in
		-- another (a gallery tab page) is found by that first id among the
		-- popover's own ancestors
		local first, rest = string.match(source.path, "^/([^/]+)(.*)$")
		local n = selfNode
		while n ~= nil do
			if n.id == first then
				return focusMap.nodeAt(rootOf(n), n.path .. rest)
			end
			n = n.parent
		end
		return nil
	end

	local function tearDown(state: any)
		if state.sheet ~= nil then
			state.sheet.dismiss()
			state.sheet.dispose()
		elseif state.handle ~= nil and dismissFn ~= nil then
			dismissFn(state.handle)
		end
	end

	-- physically release the live presentation; `reason` nil means silent
	local function close(reason: string?)
		local state = live
		if state == nil then
			return
		end
		live = nil
		closingReason = nil
		tearDown(state)
		if reason ~= nil then
			report(reason)
		end
	end

	-- the focused path's suffix under the content body, for a route switch
	local function contentSuffix(): string?
		local focused = if graph ~= nil then graph.focused:peek() else nil
		if type(focused) ~= "string" then
			return nil
		end
		-- plain finds: a surface id may carry pattern characters ("Popover-Tip")
		local prefix = `/{surfaceId}/`
		if string.sub(focused, 1, #prefix) ~= prefix then
			return nil
		end
		local at = string.find(focused, `/{BODY_ID}/`, #prefix, true)
		return if at ~= nil then string.sub(focused, at + #BODY_ID + 1) else nil
	end

	local function panel(): any
		--[[ THE BAR A SCROLLING BODY TAKES. The host reserves an overflowing body's
			scroll bar off its cross axis, which a hugging width cannot see; the
			renderer's measured gutter is fed back after each solve and paid on the
			panel's trailing padding with the body filling it — the gutter the
			picker's popover and the Table's header already pay. ]]
		local gutter = Compose.cell(0)
		local panelController: any = nil
		local body = UI.ScrollView({
			id = BODY_ID,
			axis = "y",
			width = UI.fill(),
			-- the SURFACE carries the author's caps; the body gives the height back
			shrinkWeight = 1,
			children = { spec.content() },
		})
		-- the fade group the materialize transition needs (the Menu's `Popup` shape)
		local plate = UI.ZStack({
			id = "Popup",
			canvasGroup = true,
			children = {
				UI.VStack({
					id = PANEL_ID,
					surface = "raised",
					padding = function(use: any): any
						local metrics = if facts ~= nil then use(facts:get("themeMetrics")) else nil
						local step = themeSnapshot.resolveNumber(metrics or themeSnapshot.neutral(), "s") or 8
						return { top = "s", bottom = "s", left = "s", right = step + use(gutter) }
					end,
					children = { body },
				}),
			},
		})
		return contribution.attach(plate, {
			handleCancel = function(): boolean
				if live ~= nil then
					propose(false, "cancel")
				end
				return true
			end,
			requestDismiss = function(reason: string): boolean
				return propose(false, reason)
			end,
			bindController = function(controller: any)
				panelController = controller
			end,
			syncGeometry = function(_rectOf: any, node: any?)
				if node == nil or panelController == nil or panelController.scrollBarInsetOf == nil then
					return
				end
				local inset = panelController.scrollBarInsetOf(`{node.path}/{PANEL_ID}/{BODY_ID}`)
				local px = if type(inset) == "table" then tonumber(inset.right) or 0 else 0
				if px ~= gutter:peek() then
					gutter:set(px)
				end
			end,
		})
	end

	-- a teardown this control did not drive (the surface was dismissed from
	-- outside) is still a closure: report it once, propose false. Both routes.
	local function watchTeardown(state: any, handle: any)
		if handle == nil or handle.scope == nil then
			return
		end
		handle.scope.own(function()
			if live ~= state then
				return
			end
			live = nil
			local reason = closingReason
			closingReason = nil
			if wanted:peek() then
				-- not a close the caller accepted: propose it, report cancel
				propose(false, "cancel")
				closingReason = nil
				report("cancel")
			else
				report(reason or "cancel")
			end
		end)
	end

	local function openRoute(which: string, identity: any)
		generation += 1
		local mine = generation
		local state: any = { route = which, identity = identity, generation = mine }
		live = state
		if which == "sheet" then
			local detent = Compose.cell("medium")
			state.sheet = sheetLib.buildRequesting(Facet, core, {
				id = surfaceId,
				title = "",
				detent = detent,
				env = env,
				content = function()
					return spec.content()
				end,
			}, function(reason: string): boolean
				return propose(false, if reason == "outside" then "outside" else "cancel")
			end)
			watchTeardown(state, state.sheet.present(Facet.presenter))
			return
		end
		local anchor: any = {
			source = if rect ~= nil then { rect = rect } else { path = identity.path },
			edge = spec.edge,
			align = spec.align,
			gap = spec.gap,
			crossOffset = spec.crossOffset,
			tail = if rect ~= nil then false else spec.tail,
			maxWidth = spec.maxWidth,
			maxHeight = spec.maxHeight,
		}
		state.handle = presentAnchoredFn(if Facet.surfaces then panel else panel(), {
			id = surfaceId,
			modal = true,
			scrim = "none",
			outsideTapCancel = true,
			cancelPolicy = "none",
			anchor = anchor,
			transition = { enter = "materialize", plate = "fades", scale = 1.015 },
		})
		watchTeardown(state, state.handle)
	end

	local function sync()
		if disposed then
			return
		end
		if not wanted:peek() then
			lost = false
			if live ~= nil then
				close(closingReason or "cancel")
			end
			return
		end
		if live ~= nil then
			-- the acquired source must still be the one it was
			if live.identity ~= currentIdentity() then
				lost = true
				close(nil)
				propose(false, "anchorLost")
				report("anchorLost")
				return
			end
			if live.route ~= route:peek() then
				local suffix = contentSuffix()
				local identity = live.identity
				close(nil)
				openRoute(route:peek(), identity)
				if suffix ~= nil and live ~= nil then
					local prefix = if live.route == "sheet"
						then `/{surfaceId}/Layer/Panel/Room/Column/{BODY_ID}`
						else `/{surfaceId}/Layer/Surface/Popup/{PANEL_ID}/{BODY_ID}`
					-- restored once the new surface's focus map holds the path
					live.pendingFocus = prefix .. suffix
				end
			end
			if live ~= nil and live.pendingFocus ~= nil and graph ~= nil and graph.focusOn(live.pendingFocus) then
				live.pendingFocus = nil
			end
			return
		end
		if lost or presentAnchoredFn == nil or not ready then
			return
		end
		local identity = currentIdentity()
		if identity == nil then
			-- not mounted yet: wait, this is not a loss — but say so, once
			if not warnedUnmounted and source ~= nil and source.path ~= nil then
				warnedUnmounted = true
				warn(`Facet {where}: source '{source.path}' is not mounted on this screen; the popover waits for it.`)
			end
			return
		end
		openRoute(route:peek(), identity)
	end

	owner.watchStatic(wanted, function()
		sync()
	end)
	owner.watchStatic(route, function()
		sync()
	end)
	owner.own(function()
		disposed = true
		if live ~= nil then
			close("cancel")
		end
	end)

	local api = {}
	api.isPresented = wanted
	api.route = route
	function api.propose(next: boolean): boolean
		return propose(next, if next then "trigger" else "cancel")
	end

	local bundle: any = {
		bindPresent = function(_presentModal: any, dismiss: any, presentAnchored: any)
			presentAnchoredFn = if Facet.surfaces then Facet.surfaces.anchored else presentAnchored
			dismissFn = dismiss
			ready = false
		end,
		bindFocusGraph = function(g: any)
			graph = g
		end,
		syncGeometry = function(_rectOf: any, rootNode: any?)
			selfNode = rootNode
			if spec.trigger ~= nil then
				triggerNode = rootNode
			end
			if not ready then
				ready = true
				return
			end
			sync()
		end,
	}
	if spec.trigger ~= nil then
		bundle.handleActivate = function(path: string): boolean
			if triggerNode == nil or path ~= triggerNode.path then
				return false
			end
			propose(not wanted:peek(), "trigger")
			return true
		end
	end
	local blueprint = contribution.attach(if spec.trigger ~= nil then spec.trigger else UI.ZStack({ id = id }), bundle)
	-- a trigger that declares its own effect (every app Button does) still asks
	-- first: the presenter runs a node's `onActivate` before any contribution, so
	-- the popover's route goes there and the trigger's effect runs when it declines
	-- (the Menu's own decoration)
	local ownActivate = if spec.trigger ~= nil and spec.trigger.props ~= nil then spec.trigger.props.onActivate else nil
	if type(ownActivate) == "function" then
		Facet.runtime.decorate(blueprint, {
			onActivate = function(path: string, meta: any?)
				if not bundle.handleActivate(path) then
					ownActivate(path, meta)
				end
			end,
		})
	end

	local function dump()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			presented = live ~= nil,
			route = if live ~= nil then live.route else route:peek(),
			wanted = wanted:peek(),
			anchorLost = lost,
			source = if rect ~= nil then "rect" elseif spec.trigger ~= nil then "trigger" else source.path,
		}
	end

	return {
		blueprint = blueprint,
		api = api,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function popover.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return popover
