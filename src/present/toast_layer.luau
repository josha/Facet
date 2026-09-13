--!strict
--[[ ToastLayer — the toast SURFACE driver, extracted verbatim from
	src/present/presenter.luau for Studio's 200,000-character `Source` WRITE cap:
	over it a module silently stops live-syncing into an open session, so a live
	check against it tests the built place rather than the edits on disk.

	THE CAP WAS 5,431 CHARACTERS AWAY WHEN THIS MOVED. `presenter.luau` stood at
	194,569, having been left at 179,055 by the 2026-08-14 split with the note
	that "192,454 passes this check and is NOT a margin". It grew back twice.
	This is the sixth extraction from that file and it is the same recipe.

	WHY THIS IS THE SEAM, AND WHY THE LEDGER'S OWN RANKING WAS WRONG. The
	source-cap row for `presenter.luau` ranked the toast region BEHIND the
	disclosure plate and priced it as the dearer of the two: "the TOAST region is
	smaller (~7 KB) and costs MORE: six reassigned scalars (`toastTime`,
	`toastPosition`, `toastTransition`, `toastLayer`, `toastSchedule`,
	`syncToastLayer`), which is a record with six fields rather than one."
	Re-run mechanically against the live file rather than re-read, that is
	backwards. All six are DECLARED in this region, and after the one change
	below nothing outside it reads or writes any of them — so the state left with
	the code and the record is a record of nothing. That is the same score
	`catchers` and `text_reveal` came out on, and it is a BETTER score than
	`surface_lifecycle`'s, which really did have to pay one (`displayLayer`).

	THE ONE CHANGE, AND IT IS NOT A CONCESSION TO THE SPLIT. `tickBody` used to
	carry four inline lines of toast time:

	    if toastSchedule ~= nil then
	        toastTime += math.max(step, 0)
	        toastSchedule.update()
	        syncToastLayer()
	    end

	which is the only reader of `toastTime`/`syncToastLayer` outside this region
	and the reason the row called them shared. It is now `toasts.tick(step)` —
	the shape the SAME tick body already uses for five other siblings
	(`helpPlate.tick`, `anchoredSurfaces.sync`, `stepReveal`,
	`calloutQueue.update`, `motionClock:step`). The toast was the one feature
	still inlining its own frame slice; moving it in makes the tick body more
	uniform, not less, which is why it counts as the seam paying for itself
	rather than as a price.

	WHAT IT READS FROM THE PRESENTER, all of it immutable — none of these names is
	ever reassigned in `presenter.new`, confirmed by the mechanised scan over that
	closure's 71 locals (12 reassigned, none of them here):

	  `core`, `env`, `adapter`  the reactive core and the render target, by
	                            reference — `presenter.new`'s own parameters
	  `motionClock`             declared once from `presenterOpts.clock`
	  `metricsNow`              a `local function`, never reassigned
	  `emitFeedback`            a `local function`, never reassigned
	  `toastDisplayOrder`       ONE NUMBER (`SURFACE_LAYER.toast`), not the band
	                            table — the same shape `anchored.luau` takes as
	                            `baseDisplayOrder`

	`ToastOpts` and `TOAST_OPTS_KEYS` came too, because this region was their only
	reader: the public type is re-exported from `presenter.luau` under its
	original spelling, so `presenter.ToastOpts` still names it and no consumer
	moved.

	`new(ctx)` returns the three names `presenter.new` binds — `presentToast` and
	`toastCounts` onto `self` under their original names, `tick` into the tick
	body — so not one call site changed.
]]

local blueprintLib = require("../blueprint")
local mountLib = require("../mount")
local renderer = require("../render/renderer")
local transitionsLib = require("../render/transitions")
local specGuard = require("../spec_guard")
local toast_schedule = require("./toast_schedule")
local focusMap = require("./focus_map")
local nodeAt = focusMap.nodeAt

local toast_layer = {}

-- presentToast options (ui-designer spec §3.1)
export type ToastOpts = {
	key: string?, -- same-key supersede ("subject" in the spec)
	priority: number?, -- default 0; higher runs first in the queue
	duration: number?, -- seconds visible, default 4
	readFloor: number?, -- minimum dwell before anything may replace it, default 1.5
	position: string?, -- "top" (default) | "bottom" — the edge it docks to
	transition: any?, -- default: slide in from its own edge, with a fade
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
})

export type Ctx = {
	core: any,
	env: any,
	adapter: any,
	motionClock: any,
	metricsNow: () -> any,
	emitFeedback: (any) -> (),
	toastDisplayOrder: number,
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
	local toastLayer: any = nil
	local toastSchedule: any = nil
	local syncToastLayer: () -> ()

	local function toastRowBlueprint(entry: any): any
		-- the fade GROUP the transition needs, wrapped by the presenter so a caller
		-- never has to know that a fade is a CanvasGroup fact
		return blueprintLib.ZStack({
			id = "Toast",
			width = { type = "fill", weight = 1 },
			height = { type = "content" },
			canvasGroup = true,
			children = { entry.data.blueprint },
		})
	end

	local function disposeToastLayer()
		if toastLayer == nil then
			return
		end
		local layer = toastLayer
		toastLayer = nil
		layer.coordinator.dispose()
		layer.controller.dispose()
		layer.scope:dispose()
	end

	local function ensureToastSchedule()
		if toastSchedule ~= nil then
			return
		end
		toastSchedule = toast_schedule.new({
			now = function()
				return toastTime
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
		toastTransition = options.transition
			or {
				-- a toast comes from the edge it docks to, and fades with it
				enter = if toastPosition == "bottom" then "slide-up" else "slide-down",
				fade = true,
			}
		local sc = core:scope("present-toast")
		-- scope-owned, so a layer that comes and goes twenty times leaves the core's
		-- counters exactly where it found them
		local items = sc:own(core:signal({}))
		local rows = blueprintLib.ForEach({
			id = "Items",
			items = items,
			key = function(entry: any): string
				return tostring(entry.id)
			end,
			row = toastRowBlueprint,
			transition = toastTransition,
		})
		local children: { any } = {}
		if toastPosition == "bottom" then
			-- the strip is pushed to the far edge; nothing else in the layer paints,
			-- so the spacer costs one transparent frame
			table.insert(children, blueprintLib.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }))
		end
		table.insert(children, rows)
		-- padding lifts the strip off the surface edges (director, sensory-feedback
		-- round: rows
		-- hugging the exact top edge collided with content pinned there, and
		-- edge-to-edge rows read as a debug bar rather than a toast)
		local bp = blueprintLib.Screen({
			id = "__toast__",
			align = "center",
			gap = "s",
			padding = "m",
			children = children,
		})
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
		local root = mountLib.mount(core, bp, {
			scope = sc:child("mount"),
			transitions = coordinator,
			-- the toast strip carries CONSUMER-authored rows, so a
			-- `UI.sensoryFeedback` declared on one has the same seam a screen's does
			feedback = function(event: any)
				event.surface = surfaceRef
				emitFeedback(event)
			end,
		})
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
		controller.initialRender()
		coordinator.bindController(controller)
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
		toastLayer.items:set(toastSchedule.visible())
		toastLayer.controller.refresh()
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

	local function presentToast(blueprint: any, opts: ToastOpts?)
		assert(
			type(blueprint) == "table" and type(blueprint.class) == "string",
			"presenter.presentToast takes a blueprint (UI.*) and an options table"
		)
		specGuard.assertKnownKeys("presenter.presentToast", opts, TOAST_OPTS_KEYS, "opts")
		local options: any = opts or {}
		ensureToastSchedule()
		ensureToastLayer(options)
		local id = toastSchedule.push({
			key = options.key,
			priority = options.priority,
			duration = options.duration,
			readFloor = options.readFloor,
			data = { blueprint = blueprint, context = options.context },
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
	}
end

return toast_layer
