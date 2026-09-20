--!strict
-- Presenter-private toast scheduling and rendering. Rows share one layout
-- animation group; plain slides preserve native text rendering. Explicit fades
-- use a CanvasGroup. Each toast's body is a component that its row owns.

local blueprintLib = require("../blueprint")
local renderer = require("../render/renderer")
local transitionsLib = require("../render/transitions")
local specGuard = require("../spec_guard")
local toast_schedule = require("./toast_schedule")
local focusMap = require("./focus_map")
local Compose = require("../vendor/compose/core")
local nodeAt = focusMap.nodeAt

local cleanup = require("../core/cleanup")
local toast_layer = {}

-- presentToast options (ui-designer spec §3.1)
export type ToastOpts = {
	key: string?, -- same-key supersede ("subject" in the spec)
	priority: number?, -- default 0; higher runs first in the queue
	duration: number?, -- seconds visible, default 4
	readFloor: number?, -- minimum dwell before anything may replace it, default 2.5
	position: ("top" | "bottom")?, -- the edge it docks to; default top
	width: blueprintLib.Dim?, -- default fill; hug fits content within the safe width
	transition: any?, -- default: slide in from its own edge; fading is explicit
	context: any?, -- carried on the toast's dismiss event, untouched
}

local TOAST_OPTS_KEYS = specGuard.keySet({
	"context",
	"duration",
	"key",
	"position",
	"priority",
	"readFloor",
	"transition",
	"width",
})

export type Ctx = {
	reserveHud: ((any) -> any)?,
	core: any,
	env: any,
	adapter: any,
	motionClock: any,
	metricsNow: () -> any,
	emitFeedback: (any) -> (),
	toastDisplayOrder: number,
	-- mounts a component, given the internal UI, into the UI runtime
	mountComponent: ((UI: any) -> any) -> any,
}

function toast_layer.new(ctx: Ctx)
	local core = ctx.core
	local env = ctx.env
	local adapter = ctx.adapter
	local motionClock = ctx.motionClock
	local metricsNow = ctx.metricsNow
	local emitFeedback = ctx.emitFeedback
	local toastDisplayOrder = ctx.toastDisplayOrder

	-- ===== TOASTS =======================================
	--
	-- A toast surface is PRESENTER-PRIVATE, exactly like the scrim and the popup
	-- catcher: it is not in `stack`, pushes no focus scope, creates no input
	-- context and wires no tap handler. That is what "input-transparent" is —
	-- not a property the layer politely observes, but a surface that has nothing
	-- to observe it with. Nothing here can reach `SelectedObject`, the responder
	-- chain, or the outside-tap policy, because none of that is built.
	--
	-- ONE layer holds every visible toast, as a keyed `UI.ForEach` carrying the
	-- transition — so a toast's enter/exit is the SAME retire model a `UI.When`
	-- gets, proven by the same tests, rather than a second animation path.
	--
	-- The scheduler (`toast_schedule`) owns priority, the queue cap, read floors
	-- and supersede; this driver owns pixels. Under reduced motion the transition
	-- places instantly and the schedule is untouched: every toast that would have
	-- been shown is still shown, for the same time.
	local toastTime = 0
	local toastPosition = "top"
	local toastTransition: any = nil
	local toastFadeGroup = false
	local toastLayer: any = nil
	local reservation: any = nil
	local toastSchedule: any = nil
	local syncToastLayer: () -> ()

	-- A fading toast is its own plate. Preserve an explicit caller policy,
	-- including readable transitions, when adding that acknowledgement.
	local function defaultToastTransition(position: string): any
		return {
			-- A plain slide keeps text in native glyph rendering. A CanvasGroup
			-- permanently rasterizes it into a quality-dependent texture.
			enter = if position == "bottom" then "slide-up" else "slide-down",
			plate = "fades",
		}
	end
	local function mergeToastPlate(value: any): any
		if type(value) ~= "table" or value.plate ~= nil then
			return value
		end
		local merged = table.clone(value)
		merged.plate = "fades"
		return merged
	end
	local function acknowledgeToastPlate(_coreRef: any, scope: any, declared: any, position: string): any
		if declared == nil or declared == false then
			return defaultToastTransition(position)
		end
		if Compose.isReadable(declared) then
			return Compose.withOwner(scope, function()
				return Compose.formula(function(use)
					local value = use(declared)
					if value == nil or value == false then
						return defaultToastTransition(position)
					end
					return mergeToastPlate(value)
				end)
			end)
		end
		return mergeToastPlate(declared)
	end

	-- The row is the toast's owner: its body component runs inside the row's
	-- render, so the body's cells and watches are released with the toast.
	local function toastRow(UI: any, entry: any): any
		-- Explicit fades still get the group they need; ordinary slides do not.
		return UI.ZStack({
			id = "Toast",
			width = entry.data.width or blueprintLib.fill(),
			height = { type = "content" },
			canvasGroup = if toastFadeGroup then true else nil,
			children = { entry.data.component() },
		})
	end

	local function disposeToastLayer()
		if toastLayer == nil then
			return
		end
		local layer = toastLayer
		if reservation then
			reservation.dispose()
			reservation = nil
		end
		toastLayer = nil
		cleanup({
			layer.coordinator.dispose,
			layer.controller.dispose,
			function()
				layer.scope:dispose()
			end,
		})
	end

	local function ensureToastSchedule()
		if toastSchedule ~= nil then
			return
		end
		toastSchedule = toast_schedule.new({
			now = function()
				return toastTime
			end,
			onChange = function()
				if toastLayer then
					toastLayer.items:set(toastSchedule.visible())
				end
			end,
			onDismiss = function(entry: any, reason: string)
				-- every retirement is traceable, including the queued one dropped at
				-- the cap (disposition F3) — nothing vanishes without a reason code.
				-- REPLACEMENT IS ITS OWN VERB (ui-designer review R2-F1 ruling): a
				-- superseded toast emits exactly one `supersede`; `dismiss` means the
				-- surface actually retired on its own terms (timeout/capacity/manual/
				-- preempt). One causal moment, one event.
				emitFeedback({
					type = if reason == "supersede" then "supersede" else "dismiss",
					path = `/__toast__/Items/[{entry.id}]`,
					reason = if reason == "supersede" then nil else reason,
					context = { key = entry.key, priority = entry.priority, context = entry.data.context },
				})
			end,
		})
	end

	local function ensureToastLayer(options: any)
		if toastLayer ~= nil then
			return
		end
		-- the first toast fixes the layer's edge and transition for its lifetime:
		-- one layer, one stacking direction, so a burst cannot make the strip hop
		-- from one edge to the other mid-read
		toastPosition = if options.position == "bottom" then "bottom" else "top"
		local sc = core.owner.createChild()
		toastTransition = acknowledgeToastPlate(core, sc, options.transition, toastPosition)
		local transition = transitionsLib.resolve(toastTransition)
		local fading = blueprintLib.schema.TRANSITION_FADES
		toastFadeGroup = Compose.isReadable(toastTransition)
			or transition.fade
			or fading[transition.enter] == true
			or fading[transition.exit] == true
		-- scope-owned, so a layer that comes and goes twenty times leaves the core's
		-- counters exactly where it found them
		local items = Compose.cell({})
		local function layer(UI: any): any
			local children: { any } = {}
			if toastPosition == "bottom" then
				-- the strip is pushed to the far edge; nothing else in the layer paints,
				-- so the spacer costs one transparent frame
				table.insert(children, UI.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }))
			end
			table.insert(
				children,
				UI.ForEach({
					id = "Items",
					items = items,
					key = function(entry: any): string
						return tostring(entry.id)
					end,
					row = function(entry: any)
						return toastRow(UI, entry)
					end,
					transition = toastTransition,
				})
			)
			-- padding lifts the strip off the surface edges: rows hugging the exact
			-- edge collide with content pinned there and read as a debug bar
			return UI.Screen({
				id = "__toast__",
				animation = { layout = "container" },
				align = "center",
				gap = "s",
				padding = "m",
				children = children,
			})
		end
		local surfaceRef: any = nil
		local coordinator = transitionsLib.new({
			core = core,
			clock = motionClock,
			metrics = metricsNow,
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local root = ctx.mountComponent(layer)
		sc.own(root.dispose)
		-- the rows' structural transitions reach this strip's coordinator
		transitionsLib.bind(root.node, coordinator)
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = "coreSafeContent",
			clock = motionClock,
		})
		controller.initialRender()
		coordinator.bindController(controller)
		if ctx.reserveHud then
			reservation = ctx.reserveHud({ id = "__facet_toasts", edge = toastPosition })
		end
		if controller.setDisplayOrder ~= nil then
			-- above every base screen, below every modal (ui-designer §6.3)
			controller.setDisplayOrder(toastDisplayOrder)
		end
		toastLayer = {
			scope = sc,
			controller = controller,
			root = root,
			items = items,
			coordinator = coordinator,
			itemsNode = nodeAt(root.node, "/__toast__/Items"),
		}
		surfaceRef = toastLayer
	end

	syncToastLayer = function()
		if toastLayer == nil then
			return
		end
		toastLayer.controller.refresh()
		if reservation then
			local bounds: any = nil
			for _, row in toastLayer.itemsNode.children do
				local r = toastLayer.controller.rectOf(row.path)
				if r and r.w > 0 and r.h > 0 then
					if bounds then
						local x, y = math.min(bounds.x, r.x), math.min(bounds.y, r.y)
						bounds = {
							x = x,
							y = y,
							w = math.max(bounds.x + bounds.w, r.x + r.w) - x,
							h = math.max(bounds.y + bounds.h, r.y + r.h) - y,
						}
					else
						bounds = table.clone(r)
					end
				end
			end
			reservation.update(bounds)
		end
		-- the refresh is what CREATED the new row's handles; re-assert the enter's
		-- seeded values onto them so a toast never paints one frame at rest
		toastLayer.coordinator.flush()
		-- the layer retires when nothing is showing, nothing is waiting, and no row
		-- is still playing its exit — a retiring row is still mounted, so the
		-- mounted child count is the honest test
		local itemsNode = toastLayer.itemsNode
		local pending = if itemsNode ~= nil then #itemsNode.children else 0
		if toastSchedule.isEmpty() and pending == 0 then
			disposeToastLayer()
		end
	end

	local function presentToast(component: any, opts: ToastOpts?)
		assert(
			type(component) == "function",
			"presenter.presentToast takes a component (a function that returns the toast's node) and an options table"
		)
		specGuard.assertKnownKeys("presenter.presentToast", opts, TOAST_OPTS_KEYS, "opts")
		local options: any = opts or {}
		assert(
			options.position == nil or options.position == "top" or options.position == "bottom",
			"Facet presentToast.position must be top or bottom"
		)
		local width = nil
		if options.width ~= nil then
			local valid, why =
				blueprintLib.schema.checkValue(blueprintLib.schema.forClass("ZStack").props.width, options.width)
			assert(
				valid and type(options.width) == "table" and options.width.kind == nil,
				`Facet presentToast.width must be a static dimension: {why or "use UI.fill() or UI.hug()"}`
			)
			width = table.freeze(table.clone(options.width))
		end
		ensureToastSchedule()
		ensureToastLayer(options)
		local id = toastSchedule.push({
			key = options.key,
			priority = options.priority,
			duration = options.duration,
			readFloor = options.readFloor,
			data = { component = component, context = options.context, width = width },
		})
		syncToastLayer()
		return {
			id = id,
			dismiss = function()
				if toastSchedule == nil then
					return false
				end
				local removed = toastSchedule.dismiss(id, "manual")
				syncToastLayer()
				return removed
			end,
		}
	end

	local function toastCounts()
		if toastSchedule == nil then
			return { visible = 0, queued = 0, sequence = 0 }
		end
		return toastSchedule.counts()
	end

	-- ONE FRAME of toast time, called by the presenter's tick body — the same
	-- shape `helpPlate.tick`, `anchoredSurfaces.sync`, `stepReveal` and
	-- `calloutQueue.update` already have there. `step` arrives clamped at zero,
	-- which is where the clamp was when this ran inline.
	local function tick(step: number)
		if toastSchedule ~= nil then
			toastTime += step
			toastSchedule.update()
			syncToastLayer()
		end
	end

	return {
		presentToast = presentToast,
		toastCounts = toastCounts,
		tick = tick,
		dispose = function()
			cleanup({
				function()
					if toastSchedule then
						toastSchedule.clear("manual")
					end
				end,
				disposeToastLayer,
			})
		end,
	}
end

return toast_layer
