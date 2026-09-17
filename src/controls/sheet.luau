--!strict
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
local publicEnv = require("../env/environment")

-- A modal with owner-held detents, a draggable header, and focus-based sizing.
local guard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local chromeSlots = require("../tokens/chrome_slots")
local sheet = {}
type StringSignal = publicCore.Signal<string>
type BooleanSignal = publicCore.Signal<boolean>
export type Spec<V = StringSignal, P = BooleanSignal> = {
	id: string?,
	title: publicBlueprint.Bound<string>,
	content: publicBlueprint.Blueprint,
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
function sheet.build(Facet, core, spec: Spec)
	guard.assertKnownKeys("Controls.Sheet", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Sheet"
	assert(type(id) == "string" and id ~= "", "Controls.Sheet.id must be a nonempty string")
	assert(type(spec.title) == "string" or UI.isReadable(spec.title), "Controls.Sheet.title must be text or a readable")
	assert(
		type(spec.content) == "table" and type(spec.content.class) == "string",
		"Controls.Sheet.content must be a blueprint"
	)
	assert(
		type(spec.detent) == "table" and spec.detent.kind == "signal",
		"Controls.Sheet.detent must be an owner-held Signal"
	)
	assert(
		spec.isPresented == nil or (type(spec.isPresented) == "table" and spec.isPresented.kind == "signal"),
		"Controls.Sheet.isPresented must be a Signal"
	)
	assert(spec.isPresented == nil or spec.presenter ~= nil, "Controls.Sheet.isPresented requires presenter")
	assert(
		spec.interactiveDismissDisabled == nil or type(spec.interactiveDismissDisabled) == "boolean",
		"Controls.Sheet.interactiveDismissDisabled must be boolean"
	)
	local indicator = spec.dragIndicator or "automatic"
	assert(
		indicator == "automatic" or indicator == "visible" or indicator == "hidden",
		"Controls.Sheet.dragIndicator must be automatic | visible | hidden"
	)
	local detents, byId = {}, {}
	assert(spec.detents == nil or type(spec.detents) == "table", "Controls.Sheet.detents must be an array")
	local entries = spec.detents or { "medium", "large" }
	for index, entry in entries do
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #entries,
			"Controls.Sheet.detents must be a dense array"
		)
		local d
		if type(entry) == "string" then
			assert(
				entry == "medium" or entry == "large",
				"Controls.Sheet.detents accepts medium, large, or {id, fraction|height}"
			)
			d = { id = entry, fraction = if entry == "medium" then 0.5 else 1 }
		else
			guard.assertKnownKeys(
				"Controls.Sheet.detents",
				entry,
				guard.keySet({ "id", "fraction", "height" }),
				"detent"
			)
			assert(
				type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "",
				"Controls.Sheet detent requires a nonempty id"
			)
			assert(
				(entry.fraction ~= nil) ~= (entry.height ~= nil),
				"Controls.Sheet detent requires exactly one of fraction or height"
			)
			local n = entry.fraction or entry.height
			assert(
				type(n) == "number" and n > 0 and n < math.huge and (entry.fraction == nil or n <= 1),
				"Controls.Sheet detent fraction must be in (0,1], height must be finite and positive"
			)
			d = table.clone(entry)
		end
		assert(not byId[d.id], "Controls.Sheet detent IDs must be unique")
		byId[d.id] = d
		table.insert(detents, d)
	end
	assert(#detents > 0, "Controls.Sheet.detents must not be empty")
	assert(byId[spec.detent:get()] ~= nil, "Controls.Sheet.detent must name a declared detent")
	local env = surfaceEnv.resolve("Sheet", id, core, spec.env, "sheet sizing requires an environment")
	local scope = core:scope("sheet-" .. id)
	local dragHeight = scope:own(core:signal(nil))
	local dragging = scope:own(core:signal(false))
	local presenter = spec.presenter
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
		return v:get()
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
		assert(byId[key] ~= nil, "Controls.Sheet.detent must name a declared detent")
		spec.detent:set(key)
		dragHeight:set(nil)
	end
	local function adjust(direction, wrap)
		local sorted = ordered()
		local index = table.find(sorted, byId[spec.detent:get()]) or 1
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
	scope:own(function()
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
		if not dragging:get() then
			return
		end
		dragging:set(false)
		local h = dragHeight:get() or startHeight
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
	scope:own(core:observe(classes, function(c)
		if dragging:get() and not c.pointer and not c.touch then
			cancelDrag()
		end
	end))
	scope:own(core:observe(spec.detent, function(key)
		assert(byId[key] ~= nil, "Controls.Sheet.detent must name a declared detent")
	end))
	local height = scope:own(core:memo(function(use)
		return math.min(available(use), use(dragHeight) or heightOf(byId[use(spec.detent)], use))
	end))
	local paintedHeight = scope:own(core:signal(height:get()))
	local heightMotion
	scope:own(core:observe(height, function(h)
		if heightMotion then
			if dragging:get() then
				heightMotion:snap(h)
			else
				heightMotion:setTarget(h)
			end
		else
			paintedHeight:set(h)
		end
	end))
	local sizeLabel = scope:own(core:memo(function(use)
		return "Size: " .. use(spec.detent)
	end))
	local direct = scope:own(core:memo(function(use)
		local c = use(classes)
		return indicator ~= "hidden" and (indicator == "visible" or c.pointer or c.touch)
	end))
	local panel = chromeSlots.attachHint(
		UI.ScrollView({
			axis = "y",
			id = "Panel",
			width = { type = "minMax", max = "controls.alert.maxWidth" },
			height = scope:own(core:memo(function(use)
				return { type = "fixed", px = use(paintedHeight) }
			end)),
			alignH = "center",
			alignV = scope:own(core:memo(function(use)
				return if use(distance) == "ten-foot" then "center" else "end"
			end)),
			surface = "raised",
			padding = "m",
			gap = "s",
			children = {
				UI.ZStack({
					id = "Drag",
					hidden = scope:own(core:memo(function(use)
						return not use(direct)
					end)),
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
								startHeight = paintedHeight:get()
								if heightMotion then
									heightMotion:snap(startHeight)
								end
								dragging:set(true)
								dragHeight:set(startHeight)
								return true
							end,
							onPointerMove = function(_, pos)
								if dragging:get() then
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
					children = { spec.content },
				}),
			},
		}),
		{ slot = "panel" }
	)
	local blueprint = Facet.contribution.attach(
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
			bindMotion = function(clock)
				if clock and not heightMotion then
					heightMotion = scope:own(clock:spring(paintedHeight:get(), "dismiss", { eps = 0.01 }))
					scope:own(core:observe(heightMotion, function()
						paintedHeight:set(heightMotion:get())
					end))
				end
			end,
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
	local function present(target)
		assert(not disposed, "Controls.Sheet is disposed")
		if handle then
			return handle
		end
		presenter = target or presenter
		assert(presenter and type(presenter.presentModal) == "function", "Controls.Sheet.present requires a presenter")
		handle = presenter.presentModal(blueprint, {
			outsideTapCancel = not spec.interactiveDismissDisabled,
			cancelPolicy = "none",
			transition = {
				enter = "slide-up",
				exit = "slide-down",
				distance = vp:get().h,
				class = "dismiss",
				exitClass = "dismiss",
			},
		})
		local opened = handle
		opened.scope:own(function()
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
		scope:own(core:observe(spec.isPresented, function(want)
			if not syncing and not disposed then
				if want then
					present()
				else
					dismiss()
				end
			end
		end))
		if spec.isPresented:get() then
			present()
		end
	end
	local function dump()
		return {
			schema = "facet-sheet-dump/1",
			id = id,
			detent = spec.detent:get(),
			height = height:get(),
			presented = handle ~= nil,
			dragging = dragging:get(),
			placement = if distance:get() == "ten-foot" then "center" else "bottom",
		}
	end
	return table.freeze({
		blueprint = blueprint,
		present = present,
		dismiss = dismiss,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	})
end
return sheet
