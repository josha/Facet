--!strict
local Compose = require("../vendor/compose/core")
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
local publicEnv = require("../env/environment")

-- A modal with owner-held detents, a draggable header, and focus-based sizing.
local guard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local chromeSlots = require("../tokens/chrome_slots")
local sheet = {}
type StringCell = publicCore.Cell<string>
type BooleanCell = publicCore.Cell<boolean>
export type Spec<V = StringCell, P = BooleanCell> = {
	id: string?,
	title: publicBlueprint.Bound<string>,
	content: publicBlueprint.Blueprint | (() -> publicBlueprint.Blueprint),
	detent: V,
	detents: { "medium" | "large" | { id: string, fraction: number?, height: number? } }?,
	env: publicEnv.Env?,
	presenter: any?,
	isPresented: P?,
	interactiveDismissDisabled: boolean?,
	dragIndicator: ("automatic" | "visible" | "hidden")?,
}
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
})
local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.Sheet", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Sheet"
	assert(type(id) == "string" and id ~= "", "UI.Sheet.id must be a nonempty string")
	assert(type(spec.title) == "string" or UI.isReadable(spec.title), "UI.Sheet.title must be text or a readable")
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
	local function available(use)
		local v, c = use(vp), use(chrome)
		return math.max(1, v.h - c.insets.top - c.insets.bottom)
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
	local function interactiveClose()
		if not spec.interactiveDismissDisabled then
			dismiss()
		end
		return true
	end
	local function finishDrag()
		if not dragging:peek() then
			return
		end
		dragging:set(false)
		local h = dragHeight:peek() or startHeight
		local sorted = ordered()
		if h < heightOf(sorted[1], read) * 0.7 and not spec.interactiveDismissDisabled then
			dismiss()
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
	local function buildScreen()
		local panel = chromeSlots.attachHint(
			UI.ScrollView({
				axis = "y",
				id = "Panel",
				width = { type = "minMax", max = "controls.alert.maxWidth" },
				height = Compose.formula(function(use)
					return { type = "fixed", px = use(paintedHeight) }
				end),
				alignH = "center",
				alignV = Compose.formula(function(use)
					return if use(distance) == "ten-foot" then "center" else "end"
				end),
				surface = "raised",
				padding = "m",
				gap = "s",
				children = {
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
					UI.Text({ id = "Title", text = spec.title, disclose = true }),
					UI.HStack({
						id = "Header",
						width = UI.fill(),
						gap = "s",
						children = {
							UI.Button({
								id = "Size",
								label = sizeLabel,
								disclose = true,
								enabled = #detents > 1,
								width = UI.fill(),
								height = { type = "minMax", min = "targetSizes.minimum" },
								onActivate = function()
									adjust(1, true)
								end,
							}),
							UI.Button({
								id = "Close",
								disclose = true,
								label = "Close",
								compactLabel = { icon = "chevron.down", prefer = true },
								width = { type = "fixed", px = "targetSizes.minimum" },
								height = { type = "minMax", min = "targetSizes.minimum" },
								onActivate = dismiss,
							}),
						},
					}),
					UI.VStack({
						id = "Body",
						padding = "s",
						width = UI.fill(),
						children = { if type(spec.content) == "function" then spec.content() else spec.content },
					}),
				},
			}),
			{ slot = "panel" }
		)
		local blueprint = require("../input/contribution").attach(
			UI.Screen({
				id = id,
				children = {
					UI.ZStack({ id = "Layer", width = UI.fill(), height = UI.fill(), children = {
						panel,
					} }),
				},
			}),
			{
				handleCancel = interactiveClose,
				adjustAxis = "horizontal",
				adjustTargets = function(root)
					return { [root.path .. "/Layer/Panel/Header/Size"] = true }
				end,
				handleAdjust = function(path, direction)
					if path ~= "/" .. id .. "/Layer/Panel/Header/Size" then
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
			transition = {
				enter = "slide-up",
				exit = "slide-down",
				distance = vp:peek().h,
				class = "dismiss",
				exitClass = "dismiss",
			},
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
			placement = if distance:peek() == "ten-foot" then "center" else "bottom",
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
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else Compose.createOwner(core.scene.reactor)
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(Facet, core, spec, owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return sheet
