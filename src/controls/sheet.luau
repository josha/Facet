--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")

-- A modal with owner-held detents, a draggable header, and focus-based sizing.
local guard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local chromeSlots = require("../tokens/chrome_slots")
local overlayParts = require("./overlay_parts")
local alert = require("./alert")
local sheet = {}
local specTypes = require("../spec_types/sheet")
type StringCell = specTypes.StringCell
type BooleanCell = specTypes.BooleanCell
export type Spec<V = StringCell, P = BooleanCell> = specTypes.Spec<V, P>
local KEYS = guard.keySet({
	"id",
	"title",
	"content",
	"detent",
	"detents",
	"env",
	"presenter",
	"isPresented",
	"interactiveDismissDisabled",
	"dragIndicator",
	"placement",
	"edge",
	"width",
	"closeButton",
	"header",
	"hero",
	"actions",
	"actionLayout",
	"contentInset",
})
local PLACEMENTS = { automatic = true, bottom = true, side = true, center = true }
-- `request(reason) -> boolean` is the private close-request seam: asked BEFORE
-- the Close button, Cancel, a dismissing drag or an outside tap tears the sheet
-- down ("close" | "cancel" | "drag" | "outside"); false keeps the surface, its
-- focus and the accepted detent. Absent, every route closes as it always has.
local function build(Facet: any, core: any, spec: Spec, owner: any, request: ((string) -> boolean)?)
	guard.assertKnownKeys("UI.Sheet", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Sheet"
	assert(type(id) == "string" and id ~= "", "UI.Sheet.id must be a nonempty string")
	assert(
		type(spec.title) == "string" or type(spec.title) == "function" or UI.isReadable(spec.title),
		"UI.Sheet.title must be text, a readable or a function"
	)
	assert(
		(type(spec.content) == "table" and type(spec.content.class) == "string") or type(spec.content) == "function",
		"UI.Sheet.content must be a content builder or UI node"
	)
	assert(
		require("../selection_model").isWritable(spec.detent),
		"UI.Sheet.detent must be a writable Compose cell the caller owns"
	)
	assert(
		spec.isPresented == nil or (require("../selection_model").isWritable(spec.isPresented)),
		"UI.Sheet.isPresented must be a writable Compose cell"
	)
	assert(
		spec.isPresented == nil or spec.presenter ~= nil or Facet.surfaces ~= nil,
		"UI.Sheet.isPresented requires presenter"
	)
	assert(
		spec.interactiveDismissDisabled == nil or type(spec.interactiveDismissDisabled) == "boolean",
		"UI.Sheet.interactiveDismissDisabled must be boolean"
	)
	local indicator = spec.dragIndicator or "automatic"
	assert(
		indicator == "automatic" or indicator == "visible" or indicator == "hidden",
		"UI.Sheet.dragIndicator must be automatic | visible | hidden"
	)
	local placement = spec.placement or "automatic"
	assert(PLACEMENTS[placement] == true, "UI.Sheet.placement must be automatic | bottom | side | center")
	assert(
		spec.edge == nil or (placement == "side" and (spec.edge == "left" or spec.edge == "right")),
		"UI.Sheet.edge is left | right, and only with placement = side"
	)
	local edge = spec.edge or "right"
	assert(
		spec.width == nil or overlayParts.WIDTHS[spec.width] ~= nil,
		"UI.Sheet.width must be automatic | narrow | wide"
	)
	assert(spec.closeButton == nil or type(spec.closeButton) == "boolean", "UI.Sheet.closeButton must be boolean")
	assert(
		spec.header == nil
			or spec.header == false
			or (type(spec.header) == "table" and type(spec.header.class) == "string"),
		"UI.Sheet.header is a blueprint or false"
	)
	assert(
		spec.contentInset == nil or spec.contentInset == "standard" or spec.contentInset == "none",
		"UI.Sheet.contentInset must be standard | none"
	)
	assert(
		spec.actionLayout == nil
			or spec.actionLayout == "automatic"
			or spec.actionLayout == "row"
			or spec.actionLayout == "stacked",
		"UI.Sheet.actionLayout must be automatic | row | stacked"
	)
	local where = `UI.Sheet('{id}')`
	overlayParts.checkHero(where, spec.hero)
	local hero: any = spec.hero
	local sticky = hero ~= nil and hero.sticky == true
	local overHero = spec.header == false and hero ~= nil
	local sizePath = if overHero then "/Layer/Panel/Stage/Header/Size" else "/Layer/Panel/Header/Size"
	local actions: { any } = spec.actions or {}
	overlayParts.checkActions(where, spec.actions, math.huge)
	local cancelAction, defaults = nil, 0
	for _, action in actions do
		assert(not string.find(action.id, "/", 1, true), `{where}: action ids may not contain '/'`)
		if action.role == "default" then
			defaults += 1
		elseif action.role == "cancel" then
			assert(cancelAction == nil, `{where}: only one action may take role = "cancel"`)
			cancelAction = action
		end
	end
	assert(defaults <= 1, `{where}: only one action may take role = "default"`)
	local utilityHeight = Compose.cell(nil)
	local detents, byId = {}, {}
	assert(spec.detents == nil or type(spec.detents) == "table", "UI.Sheet.detents must be an array")
	local entries = spec.detents or { "medium", "large" }
	for index, entry in entries do
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #entries,
			"UI.Sheet.detents must be a dense array"
		)
		local d
		if type(entry) == "string" then
			assert(
				entry == "medium" or entry == "large",
				"UI.Sheet.detents accepts medium, large, or {id, fraction|height}"
			)
			d = { id = entry, fraction = if entry == "medium" then 0.5 else 1 }
		else
			guard.assertKnownKeys("UI.Sheet.detents", entry, guard.keySet({ "id", "fraction", "height" }), "detent")
			assert(
				type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "",
				"UI.Sheet detent requires a nonempty id"
			)
			assert(
				(entry.fraction ~= nil) ~= (entry.height ~= nil),
				"UI.Sheet detent requires exactly one of fraction or height"
			)
			local n = entry.fraction or entry.height
			assert(
				type(n) == "number" and n > 0 and n < math.huge and (entry.fraction == nil or n <= 1),
				"UI.Sheet detent fraction must be in (0,1], height must be finite and positive"
			)
			d = table.clone(entry)
		end
		assert(not byId[d.id], "UI.Sheet detent IDs must be unique")
		byId[d.id] = d
		table.insert(detents, d)
	end
	assert(#detents > 0, "UI.Sheet.detents must not be empty")
	assert(byId[spec.detent:peek()] ~= nil, "UI.Sheet.detent must name a declared detent")
	local env = surfaceEnv.resolve("Sheet", id, core, spec.env, "sheet sizing requires an environment")
	local dragHeight = Compose.cell(nil)
	local dragging = Compose.cell(false)
	local presenter = spec.presenter or Facet.presenter
	local handle, disposed, syncing = nil, false, false
	local startY, startHeight = 0, 0
	local vp = env:get("viewportRect")
	local chrome = env:get("platformChrome")
	local distance = env:get("distanceProfile")
	local classes = env:get("interactionClasses")
	local metrics = env:get("themeMetrics")
	local keyboard = env:get("keyboardOcclusionRect")
	-- the room the keyboard covers above the safe bottom edge
	local function keyboardBelow(use): number
		local v, c, occ = use(vp), use(chrome), use(keyboard)
		if type(occ) ~= "table" or type(occ.y) ~= "number" then
			return 0
		end
		return math.max(0, v.y + v.h - c.insets.bottom - occ.y)
	end
	-- ONE safe rectangle: the viewport less the platform insets and the keyboard
	local function available(use)
		local v, c = use(vp), use(chrome)
		return math.max(1, v.h - c.insets.top - c.insets.bottom - keyboardBelow(use))
	end
	local function read(v)
		return v:peek()
	end
	local function heightOf(d, use)
		local h = available(use)
		local m = use(metrics)
		local minimum = (themeSnapshot.resolveNumber(m, "targetSizes.minimum") or 44) * 4
			+ (themeSnapshot.resolveNumber(m, "m") or 16) * 2
		return math.min(h, math.max(minimum, if d.fraction then h * d.fraction else d.height))
	end
	local function ordered()
		local out = table.clone(detents)
		table.sort(out, function(a, b)
			return heightOf(a, read) < heightOf(b, read)
		end)
		return out
	end
	local function select(key)
		assert(byId[key] ~= nil, "UI.Sheet.detent must name a declared detent")
		spec.detent:set(key)
		dragHeight:set(nil)
	end
	local function adjust(direction, wrap)
		local sorted = ordered()
		local index = table.find(sorted, byId[spec.detent:peek()]) or 1
		local nextIndex = if wrap then index % #sorted + 1 else math.clamp(index + direction, 1, #sorted)
		if nextIndex == index then
			return false
		end
		select(sorted[nextIndex].id)
		return true
	end
	local function cancelDrag()
		dragging:set(false)
		dragHeight:set(nil)
	end
	local function dismiss()
		cancelDrag()
		if spec.isPresented then
			syncing = true
			spec.isPresented:set(false)
			syncing = false
		end
		if handle then
			local old = handle
			handle = nil
			presenter.dismiss(old)
		end
	end
	owner.own(function()
		disposed = true
		dismiss()
	end)
	local function allowed(reason: string): boolean
		return request == nil or request(reason) ~= false
	end
	local function interactiveClose()
		if not spec.interactiveDismissDisabled and allowed("cancel") then
			dismiss()
		end
		return true
	end
	local function usable(action: any): boolean
		local selection = require("../selection_model")
		return action ~= nil and selection.read(action.enabled) ~= false and selection.read(action.busy) ~= true
	end
	-- actions never close the sheet; the caller does, through its own cells
	local function press(action: any)
		if usable(action) then
			pcall(action.onActivate)
		end
	end
	local function finishDrag()
		if not dragging:peek() then
			return
		end
		dragging:set(false)
		local h = dragHeight:peek() or startHeight
		local sorted = ordered()
		if h < heightOf(sorted[1], read) * 0.7 and not spec.interactiveDismissDisabled then
			if allowed("drag") then
				dismiss()
			else
				-- refused: back to the detent the caller still holds
				select(spec.detent:peek())
			end
			return
		end
		local nearest = sorted[1]
		for _, d in sorted do
			if math.abs(heightOf(d, read) - h) < math.abs(heightOf(nearest, read) - h) then
				nearest = d
			end
		end
		select(nearest.id)
	end
	owner.watchStatic(classes, function(c)
		if dragging:peek() and not c.pointer and not c.touch then
			cancelDrag()
		end
	end)
	owner.watchStatic(spec.detent, function(key)
		assert(byId[key] ~= nil, "UI.Sheet.detent must name a declared detent")
	end)
	local height = Compose.formula(function(use)
		return math.min(available(use), use(dragHeight) or heightOf(byId[use(spec.detent)], use))
	end)
	local paintedHeight = Compose.cell(height:peek())
	do
		local motionOwner, target
		owner.watch(function(use)
			local h = use(height)
			local immediate = use(dragging) or use(env:get("motionPolicy")) == "reduced"
			if immediate then
				if motionOwner then
					motionOwner.dispose()
					motionOwner = nil
				end
				paintedHeight:set(h)
				return
			end
			if not motionOwner then
				motionOwner = owner.createChild()
				target = Compose.cell(paintedHeight:peek())
				Compose.withOwner(motionOwner, function()
					local animated = Facet.runtime.spring(function(use)
						return use(target)
					end, { period = 0.28, damping = 1, tolerance = 0.01 })
					motionOwner.watchStatic(animated, function(value)
						paintedHeight:set(value)
					end)
				end)
			end
			target:set(h)
		end)
	end
	local sizeLabel = Compose.formula(function(use)
		return "Size: " .. use(spec.detent)
	end)
	local direct = Compose.formula(function(use)
		local c = use(classes)
		return indicator ~= "hidden" and (indicator == "visible" or c.pointer or c.touch)
	end)
	-- automatic stays the distance default: ten-foot centred, otherwise bottom
	local function placed(use): string
		if placement ~= "automatic" then
			return placement
		end
		return if use(distance) == "ten-foot" then "center" else "bottom"
	end
	local function transition()
		if placement == "side" then
			local toward = if edge == "left" then "slide-left" else "slide-right"
			local from = if edge == "left" then "slide-right" else "slide-left"
			return { enter = from, exit = toward, distance = vp:peek().w }
		end
		return { enter = "slide-up", exit = "slide-down", distance = vp:peek().h }
	end
	local function actionWidth(use): number
		local v, c, m = use(vp), use(chrome), use(metrics)
		local cap = themeSnapshot.resolveNumber(m, overlayParts.WIDTHS[spec.width or "automatic"]) or math.huge
		local room = v.w - (c.insets.left or 0) - (c.insets.right or 0)
		return math.max(0, math.min(cap, room) - 2 * (themeSnapshot.resolveNumber(m, "m") or 16))
	end
	-- the utility controls: Size, and Close unless closeButton = false. Laid over
	-- a hero (header = false) they hug the top-right corner.
	local function utilities(over: boolean)
		return UI.HStack({
			id = "Header",
			width = if over then UI.hug() else UI.fill(),
			alignH = if over then "end" else nil,
			alignV = if over then "start" else nil,
			gap = "s",
			children = {
				UI.Button({
					id = "Size",
					label = sizeLabel,
					disclose = true,
					enabled = #detents > 1,
					width = if over then nil else UI.fill(),
					height = { type = "minMax", min = "targetSizes.minimum" },
					onActivate = function()
						adjust(1, true)
					end,
				}),
				if spec.closeButton == false
					then nil
					else UI.Button({
						id = "Close",
						disclose = true,
						label = "Close",
						compactLabel = { icon = "chevron.down", prefer = true },
						width = { type = "fixed", px = "targetSizes.minimum" },
						height = { type = "minMax", min = "targetSizes.minimum" },
						onActivate = function()
							if allowed("close") then
								dismiss()
							end
						end,
					}) :: any,
			},
		})
	end
	local function buildScreen()
		local content = if type(spec.content) == "function" then spec.content() else spec.content
		local pad = if spec.contentInset == "none" then 0 else "s"
		-- the band authored hero content keeps clear for the controls over it
		local strip = if overHero and hero.content ~= nil
			then Compose.formula(function(use)
				return { type = "fixed", px = use(utilityHeight) or "targetSizes.minimum" }
			end)
			else nil
		local bodyChildren = { content }
		if hero ~= nil and not sticky then
			bodyChildren = {
				overlayParts.hero(UI, hero, strip),
				UI.VStack({ id = "Inset", width = UI.fill(), padding = pad, children = { content } }),
			}
		end
		local body = UI.ScrollView({
			id = "Body",
			axis = "y",
			width = UI.fill(),
			height = UI.fill(),
			padding = if hero ~= nil and not sticky then nil else pad,
			children = bodyChildren,
		})
		local children: { any } = {
			UI.ZStack({
				id = "Drag",
				hidden = Compose.formula(function(use)
					return not use(direct)
				end),
				width = UI.fill(),
				height = { type = "fixed", px = "targetSizes.minimum" },
				children = {
					UI.corners(
						UI.Box({
							id = "Indicator",
							width = { type = "fixed", px = "targetSizes.minimum" },
							height = { type = "fixed", px = "space.xs" },
							tint = { role = "contentSecondary", blend = 1 },
							alignH = "center",
							alignV = "center",
						}),
						"pill"
					),
					UI.Grip({
						id = "Handle",
						width = UI.fill(),
						height = UI.fill(),
						onPointerDown = function(_, pos)
							startY = pos.y
							startHeight = paintedHeight:peek()
							dragging:set(true)
							dragHeight:set(startHeight)
							return true
						end,
						onPointerMove = function(_, pos)
							if dragging:peek() then
								dragHeight:set(math.clamp(startHeight + startY - pos.y, 1, available(read)))
							end
						end,
						onPointerUp = finishDrag,
						onPointerCancel = cancelDrag,
					}),
				},
			}),
		}
		if overHero then
			-- no header strip: the utilities lie over the hero, pinned to the panel
			-- top whether the hero is pinned or scrolls with the body
			local column = if sticky
				then UI.VStack({
					id = "Column",
					width = UI.fill(),
					height = UI.fill(),
					gap = "s",
					children = { overlayParts.hero(UI, hero, strip), body },
				})
				else body
			table.insert(
				children,
				UI.ZStack({
					id = "Stage",
					width = UI.fill(),
					height = UI.fill(),
					children = { column, utilities(true) },
				})
			)
		else
			if sticky then
				table.insert(children, overlayParts.hero(UI, hero))
			end
			if spec.header == nil then
				table.insert(children, UI.Text({ id = "Title", text = spec.title, disclose = true }))
			elseif spec.header ~= false then
				table.insert(children, spec.header)
			end
			table.insert(children, utilities(false))
			table.insert(children, body)
		end
		if #actions > 0 then
			table.insert(
				children,
				alert.actionGroup(
					Facet,
					Compose.currentOwner() or owner,
					env,
					actions,
					spec.actionLayout or "automatic",
					actionWidth,
					press
				)
			)
		end
		local panel = chromeSlots.attachHint(
			UI.VStack({
				id = "Panel",
				width = { type = "minMax", max = overlayParts.WIDTHS[spec.width or "automatic"] },
				height = Compose.formula(function(use)
					return { type = "fixed", px = use(paintedHeight) }
				end),
				alignH = if placement ~= "side" then "center" elseif edge == "left" then "start" else "end",
				alignV = Compose.formula(function(use)
					return if placed(use) == "center" then "center" else "end"
				end),
				surface = "raised",
				padding = "m",
				gap = "s",
				children = children,
			}),
			{ slot = "panel" }
		)
		local utilityPath = if overHero then "/Layer/Panel/Stage/Header" else nil
		local blueprint = require("../input/contribution").attach(
			UI.Screen({
				id = id,
				children = {
					UI.ZStack({
						id = "Layer",
						width = UI.fill(),
						height = UI.fill(),
						-- the keyboard takes the room below its top edge
						padding = Compose.formula(function(use)
							return { top = 0, left = 0, right = 0, bottom = keyboardBelow(use) }
						end),
						children = { panel },
					}),
				},
			}),
			{
				handleCancel = function(): boolean
					if usable(cancelAction) then
						press(cancelAction)
						return true
					end
					return interactiveClose()
				end,
				requestDismiss = function(): boolean
					return allowed("outside")
				end,
				syncGeometry = if utilityPath ~= nil
					then function(rectOf: any, node: any?)
						local r = if node ~= nil then rectOf(node.path .. utilityPath) else nil
						if type(r) == "table" and r.h > 0 and r.h ~= utilityHeight:peek() then
							utilityHeight:set(r.h)
						end
					end
					else nil,
				adjustAxis = "horizontal",
				adjustTargets = function(root)
					return { [root.path .. sizePath] = true }
				end,
				handleAdjust = function(path, direction)
					if path ~= "/" .. id .. sizePath then
						return false
					end
					return adjust(direction, false)
				end,
			}
		)
		return blueprint
	end
	local blueprint = UI.ZStack({ id = id .. "Anchor" })
	local function present(target)
		assert(not disposed, "UI.Sheet is disposed")
		if handle then
			return handle
		end
		presenter = target or presenter
		assert(presenter and type(presenter.presentModal) == "function", "UI.Sheet.present requires a presenter")
		local presentModal = if Facet.surfaces then Facet.surfaces.modal else presenter.presentModal
		handle = presentModal(if Facet.surfaces then buildScreen else blueprint, {
			outsideTapCancel = not spec.interactiveDismissDisabled,
			cancelPolicy = "none",
			transition = (function()
				local motion: any = transition()
				motion.class = "dismiss"
				motion.exitClass = "dismiss"
				return motion
			end)(),
		})
		local opened = handle
		opened.scope.own(function()
			if handle == opened then
				handle = nil
				if spec.isPresented then
					syncing = true
					spec.isPresented:set(false)
					syncing = false
				end
			end
		end)
		if spec.isPresented then
			syncing = true
			spec.isPresented:set(true)
			syncing = false
		end
		return handle
	end
	if spec.isPresented then
		owner.watchStatic(spec.isPresented, function(want)
			if not syncing and not disposed then
				if want then
					present()
				else
					dismiss()
				end
			end
		end)
		if spec.isPresented:peek() then
			present()
		end
	end
	local function dump()
		return {
			schema = "facet-sheet-dump/1",
			id = id,
			detent = spec.detent:peek(),
			height = height:peek(),
			presented = handle ~= nil,
			dragging = dragging:peek(),
			placement = placed(read),
			edge = if placement == "side" then edge else nil,
			transition = (function()
				local motion = transition()
				return { enter = motion.enter, exit = motion.exit }
			end)(),
		}
	end
	return table.freeze({
		blueprint = blueprint,
		present = present,
		dismiss = dismiss,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	})
end
function sheet.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
-- the same sheet with the private close-request seam (see `build`); not a
-- public constructor — the Popover's compact form presents through it
function sheet.buildRequesting(Facet: any, core: any, spec: Spec, request: (string) -> boolean)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner, request)
	end)
end
return sheet
