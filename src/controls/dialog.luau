--!strict
--[[ Dialog — a modal panel whose presentation the caller owns: an optional hero,
	a title with a close button, one scrolling body between pinned regions, an
	optional action label and a pinned action group.

	THE FACT IS THE CALLER'S. `isPresented` is rendered, never written;
	`onPresentedChange(next)` is a proposal. Close, Cancel (ButtonB) and a tap on
	the backdrop each ask, and the surface closes only when the fact changes — a
	refusal keeps the same surface and focus. Actions never close by themselves:
	a false the caller accepts DURING an action's callback reports "action".
	`onDismiss(reason)` reports each actual closure once: "close" | "outside" |
	"cancel" (Cancel, your own false, owner disposal) | "action".

	CANCEL goes to an eligible `role = "cancel"` action first (enabled, not
	busy); with none, it proposes false. The one `role = "default"` action wears
	the Button's `dialogAction = "default"` (Return). Owner or app disposal always
	releases the surface.

	THE PANEL'S HEIGHT is the live room (viewport less the platform insets, the
	outer margin and any keyboard occlusion); the header, hero, action label and
	actions are pinned and the body gives height back. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local chromeSlots = require("../tokens/chrome_slots")
local focusMap = require("../present/focus_map")
local alert = require("./alert")
local overlayParts = require("./overlay_parts")

local dialog = {}

local specTypes = require("../spec_types/dialog")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"actionLabel",
	"actionLayout",
	"actions",
	"closeButton",
	"content",
	"contentSelectable",
	"env",
	"hero",
	"id",
	"isPresented",
	"onDismiss",
	"onPresentedChange",
	"title",
	"width",
})
local WIDTHS = overlayParts.WIDTHS
local LAYOUTS = { automatic = true, row = true, stacked = true }
local DUMP_SCHEMA = "facet-dialog-dump/1"

local function textish(v: any): boolean
	return v == nil or type(v) == "string" or type(v) == "function" or Compose.isReadable(v)
end

local function blank(v: any): boolean
	return type(v) ~= "string" or string.match(v, "%S") == nil
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Dialog", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Dialog"
	local where = `UI.Dialog('{id}')`

	-- ===== the contract, refused at construction ==========================
	if spec.isPresented == nil then
		error(`Facet {where}: \`isPresented\` is required — the caller's Bound<boolean> fact.`, 0)
	end
	for _, key in { "onPresentedChange", "onDismiss" } do
		if (spec :: any)[key] ~= nil and type((spec :: any)[key]) ~= "function" then
			error(`Facet {where}: \`{key}\` is a function.`, 0)
		end
	end
	if spec.closeButton ~= nil and type(spec.closeButton) ~= "boolean" then
		error(`Facet {where}: \`closeButton\` is true (default) or false.`, 0)
	end
	local closeButton = spec.closeButton ~= false
	if closeButton and spec.onPresentedChange == nil then
		error(
			`Facet {where}: the close button proposes a close, so it needs \`onPresentedChange\`. `
				.. "Without one, set `closeButton = false`: the backdrop and Cancel then only swallow.",
			0
		)
	end
	if spec.width ~= nil and WIDTHS[spec.width] == nil then
		error(`Facet {where}: \`width\` is automatic | narrow | wide.`, 0)
	end
	if spec.actionLayout ~= nil and LAYOUTS[spec.actionLayout] ~= true then
		error(`Facet {where}: \`actionLayout\` is automatic | row | stacked.`, 0)
	end
	if spec.contentSelectable ~= nil and type(spec.contentSelectable) ~= "boolean" then
		error(`Facet {where}: \`contentSelectable\` is true (default) or false.`, 0)
	end
	if spec.content ~= nil and type(spec.content) ~= "function" then
		error(`Facet {where}: \`content\` is a component factory — a function returning the body.`, 0)
	end
	if not textish(spec.title) or not textish(spec.actionLabel) then
		error(`Facet {where}: \`title\` and \`actionLabel\` are strings or bound strings.`, 0)
	end
	overlayParts.checkMedia(where, spec.hero)
	local actions: { any } = spec.actions or {}
	overlayParts.checkActions(where, spec.actions, math.huge)
	local defaultAction, cancelAction = nil, nil
	for _, action in actions do
		if string.find(action.id, "/", 1, true) then
			error(`Facet {where}: action id '{action.id}' may not contain '/'.`, 0)
		end
		if action.role == "default" then
			if defaultAction ~= nil then
				error(`Facet {where}: only one action may take role = "default".`, 0)
			end
			defaultAction = action
		elseif action.role == "cancel" then
			if cancelAction ~= nil then
				error(`Facet {where}: only one action may take role = "cancel".`, 0)
			end
			cancelAction = action
		end
	end
	-- an entirely empty STATIC composition shows nothing; the close is not content
	local function draws(v: any): boolean
		return v ~= nil and not (type(v) == "string" and blank(v))
	end
	if
		not draws(spec.title)
		and not draws(spec.actionLabel)
		and spec.hero == nil
		and spec.content == nil
		and #actions == 0
	then
		error(`Facet {where}: nothing to show. Give a title, content, hero, actionLabel or actions.`, 0)
	end

	local env = surfaceEnv.resolve("UI.Dialog", id, core, spec.env, "dialog sizing adapts to the screen")
	local themeMetrics, viewportRect, platformChrome =
		env:get("themeMetrics"), env:get("viewportRect"), env:get("platformChrome")
	local keyboard = env:get("keyboardOcclusionRect")

	-- ===== presentation state ============================================
	local wanted = ownedFormula(owner, function(use)
		return selection.read(spec.isPresented, use) == true
	end)
	local handle: any = nil
	local presenter = Facet.presenter
	local presentModalFn: any = nil
	local dismissFn: any = nil
	-- the owning surface's FIRST geometry feed runs while it is being built,
	-- before it joins the presenter's stack; a dialog opened there would sit
	-- beneath it (the Popover's rule)
	local ready = false
	local closingReason: string? = nil
	local disposed = false

	local function report(reason: string)
		if spec.onDismiss ~= nil then
			spec.onDismiss(reason)
		end
	end

	-- a proposal: true when the caller's fact now reads `next`
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

	local function available(action: any): boolean
		return action ~= nil and selection.read(action.enabled) ~= false and selection.read(action.busy) ~= true
	end

	-- an action decides presentation itself; a false it accepts DURING its
	-- callback is an "action" closure
	local function press(action: any)
		if not available(action) then
			return
		end
		closingReason = "action"
		overlayParts.call(action.onActivate, function()
			if wanted:peek() then
				closingReason = nil
			end
		end)
	end

	local function close(reason: string)
		local old = handle
		if old == nil then
			return
		end
		handle = nil
		closingReason = nil
		if dismissFn ~= nil then
			dismissFn(old)
		else
			presenter.dismiss(old)
		end
		report(reason)
	end

	-- ===== geometry facts ================================================
	local function outerMargin(metrics: any): number
		local margin = themeSnapshot.resolveNumber(metrics, "m") or 0
		local bleed = if type(metrics) == "table" then metrics.chromeBleed or 0 else 0
		return math.max(margin, bleed)
	end
	local function screenBox(use: any): (number, number)
		local vp = use(viewportRect)
		local chrome = use(platformChrome)
		local insets = if type(chrome) == "table" then (chrome :: any).insets else nil
		local w = (if type(vp) == "table" then vp.w else 0)
			- (if type(insets) == "table" then (insets.left or 0) + (insets.right or 0) else 0)
		local h = (if type(vp) == "table" then vp.h else 0)
			- (if type(insets) == "table" then (insets.top or 0) + (insets.bottom or 0) else 0)
		-- the keyboard takes the room below its top edge
		local occ = use(keyboard)
		if type(occ) == "table" and type(vp) == "table" and type(occ.y) == "number" then
			h = math.min(h, math.max(0, occ.y - vp.y - (if type(insets) == "table" then insets.top or 0 else 0)))
		end
		return math.max(0, w), math.max(0, h)
	end
	local function widthPx(use: any): number
		local metrics = use(themeMetrics)
		local w = screenBox(use)
		local cap = themeSnapshot.resolveNumber(metrics, WIDTHS[spec.width or "automatic"]) or math.huge
		return math.max(0, math.min(cap, w - 2 * outerMargin(metrics)))
	end
	local function roomPx(use: any): number
		local _, h = screenBox(use)
		return math.max(0, h - 2 * outerMargin(use(themeMetrics)))
	end

	--[[ THE SELECTABLE BODY (contentSelectable, default true). An overflowing body
		of plain copy has nothing a pad can land on, so the body host itself
		becomes ONE focus entry while it overflows; its descendants keep their own
		groups. With the ring on it, Up/Down scroll the body through the
		controller's own scroll position and yield to the next region at either
		end. When the overflow goes away, so does the entry. ]]
	local function selectable(body: any): any
		local node: any, controller: any, graph: any = nil, nil, nil
		local overflowing = false
		local function extents(): (any, any)
			if node == nil or controller == nil then
				return nil, nil
			end
			local child = if node.children ~= nil then node.children[1] else nil
			return controller.rectOf(node.path), if child ~= nil then controller.rectOf(child.path) else nil
		end
		return contribution.attach(body, {
			bindController = function(c: any)
				controller = c
			end,
			bindFocusGraph = function(g: any)
				graph = g
			end,
			syncGeometry = function(_rectOf: any, mounted: any?)
				node = mounted
				local box, inner = extents()
				overflowing = type(box) == "table" and type(inner) == "table" and inner.h > box.h + 1
			end,
			focusGroups = function(mounted: any): { any }
				local groups: { any } = {}
				if overflowing then
					table.insert(
						groups,
						{ name = `dialog-body-{id}`, axis = "vertical", entry = "first", order = { mounted.path } }
					)
				end
				for _, child in mounted.children or {} do
					for _, group in focusMap.autoGroups(child, nil, true) do
						table.insert(groups, group)
					end
				end
				return groups
			end,
			navigateIntercept = function(direction: string): boolean
				if
					not overflowing
					or node == nil
					or graph == nil
					or graph.focused:peek() ~= node.path
					or (direction ~= "up" and direction ~= "down")
				then
					return false
				end
				local box, inner = extents()
				if type(box) ~= "table" or type(inner) ~= "table" then
					return false
				end
				local pos = controller.scrollPosition(node.path) or { x = 0, y = 0 }
				local limit = math.max(0, inner.h - box.h)
				local step = math.max(1, box.h * 0.8)
				local target = if direction == "down" then math.min(limit, pos.y + step) else math.max(0, pos.y - step)
				if target == pos.y then
					return false -- at the end: the ring moves on
				end
				controller.scrollTo(node.path, { x = pos.x, y = target })
				return true
			end,
		})
	end

	-- ===== the panel =====================================================
	local function panel(): any
		local branchOwner = Compose.currentOwner() or owner
		local children: { any } = {}
		if spec.hero ~= nil then
			table.insert(children, overlayParts.media(UI, spec.hero, WIDTHS[spec.width or "automatic"]))
		end
		local header: { any } = {}
		if spec.title ~= nil then
			table.insert(
				header,
				UI.Text({
					id = "Title",
					text = spec.title,
					textSize = "heading",
					disclose = true,
					width = UI.fill(),
					-- a bound title may be empty now and fill in later
					hidden = if type(spec.title) ~= "string"
						then ownedFormula(branchOwner, function(use)
							return blank(selection.read(spec.title, use))
						end)
						else nil,
				})
			)
		end
		if closeButton then
			table.insert(
				header,
				Facet.nativeControls.Button({
					id = "Close",
					label = "Close",
					disclose = true,
					compactLabel = { icon = "close", prefer = true },
					height = { type = "minMax", min = "targetSizes.minimum" },
					onActivate = function()
						propose(false, "close")
					end,
				})
			)
		end
		if #header > 0 then
			table.insert(
				children,
				UI.HStack({ id = "Header", width = UI.fill(), gap = "s", align = "center", children = header })
			)
		end
		if spec.content ~= nil then
			local body = UI.ScrollView({
				id = "Body",
				axis = "y",
				width = UI.fill(),
				-- the one region that gives height back when the room is short
				shrinkWeight = 1,
				children = { spec.content() },
			})
			table.insert(children, if spec.contentSelectable == false then body else selectable(body))
		end
		if spec.actionLabel ~= nil then
			table.insert(
				children,
				UI.Text({
					id = "ActionLabel",
					text = spec.actionLabel,
					role = "secondary",
					width = UI.fill(),
					hidden = if type(spec.actionLabel) ~= "string"
						then ownedFormula(branchOwner, function(use)
							return blank(selection.read(spec.actionLabel, use))
						end)
						else nil,
				})
			)
		end
		if #actions > 0 then
			table.insert(
				children,
				alert.actionGroup(Facet, branchOwner, env, actions, spec.actionLayout or "automatic", widthPx, press)
			)
		end
		return chromeSlots.attachHint(
			UI.VStack({
				id = "Panel",
				surface = "raised",
				padding = "m",
				gap = "s",
				alignH = "center",
				alignV = "center",
				-- a ceiling, and a floor so a title-only panel has a line to wrap on
				width = function(use: any): any
					local ceiling = widthPx(use)
					local floor = themeSnapshot.resolveNumber(use(themeMetrics), WIDTHS.narrow) or ceiling
					return { type = "hug", min = math.min(floor, ceiling), max = ceiling }
				end,
				height = function(use: any): any
					return { type = "hug", max = roomPx(use) }
				end,
				children = children,
			}),
			{ slot = "panel" }
		)
	end

	local function buildScreen(): any
		return contribution.attach(
			UI.Screen({
				id = id,
				align = "center",
				distribute = "center",
				-- centred in the room ABOVE the keyboard, which is the room it was sized to
				padding = function(use: any): any
					local vp, occ = use(viewportRect), use(keyboard)
					local below = if type(vp) == "table"
							and type(occ) == "table"
							and type(occ.y) == "number"
						then math.max(0, vp.y + vp.h - occ.y)
						else 0
					return { top = 0, left = 0, right = 0, bottom = below }
				end,
				children = {
					UI.ZStack({
						id = "Center",
						canvasGroup = true,
						width = UI.hug(),
						height = UI.hug(),
						alignH = "center",
						alignV = "center",
						padding = ownedFormula(Compose.currentOwner() or owner, function(use)
							return outerMargin(use(themeMetrics))
						end),
						children = { panel() },
					}),
				},
			}),
			{
				-- Cancel: an eligible cancel action first, otherwise the root proposal
				handleCancel = function(): boolean
					if handle == nil then
						return false
					end
					if available(cancelAction) then
						press(cancelAction)
					else
						propose(false, "cancel")
					end
					return true
				end,
				requestDismiss = function(reason: string): boolean
					return propose(false, reason)
				end,
			}
		)
	end

	local function present()
		if handle ~= nil or disposed or not ready or presentModalFn == nil then
			return
		end
		local initial = if available(cancelAction) then cancelAction.id else nil
		if initial == nil then
			for _, action in actions do
				if action.role ~= "destructive" and available(action) then
					initial = action.id
					break
				end
			end
		end
		local opened = presentModalFn(buildScreen, {
			initialFocus = if initial ~= nil then { id = initial } else nil,
			outsideTapCancel = true,
			-- Cancel is this control's own (handleCancel above), never a bare dismiss
			cancelPolicy = "none",
		})
		handle = opened
		-- a teardown this control did not drive is still a closure, reported once
		opened.scope.own(function()
			if handle ~= opened then
				return
			end
			handle = nil
			local reason = closingReason
			closingReason = nil
			if wanted:peek() then
				propose(false, "cancel")
				closingReason = nil
				report("cancel")
			else
				report(reason or "cancel")
			end
		end)
	end

	local function sync()
		if disposed then
			return
		end
		if wanted:peek() then
			present()
		elseif handle ~= nil then
			close(closingReason or "cancel")
		end
	end
	owner.watchStatic(wanted, sync)
	owner.own(function()
		disposed = true
		close("cancel")
	end)

	local api = {}
	api.isPresented = wanted

	local function dump()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			presented = handle ~= nil,
			wanted = wanted:peek(),
			actionCount = #actions,
			width = spec.width or "automatic",
			closeButton = closeButton,
		}
	end

	-- the anchor node learns where the dialog lives and when it may present
	local anchor = contribution.attach(UI.ZStack({ id = id .. "Anchor" }), {
		bindPresent = function(presentModal: any, dismiss: any)
			presentModalFn = if Facet.surfaces then Facet.surfaces.modal else presentModal
			dismissFn = dismiss
			ready = false
		end,
		syncGeometry = function()
			if not ready then
				ready = true
				return
			end
			sync()
		end,
	})

	return {
		blueprint = anchor,
		api = api,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function dialog.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return dialog
