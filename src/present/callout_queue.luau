--!strict
--[[ THE CALLOUT QUEUE — "at most one on screen; a queue, not a pile"
	(navigation-and-menus brief §2 D3b).

	A coach mark that pops itself is only ever welcome one at a time. Two plates
	over one screen, each pointing somewhere with an arrow, is not twice the
	guidance — it is a screen a player has to dismantle before they can use it.
	Apple says the same thing about the mechanism this reproduces: *"Use tips
	sparingly… Don't use tips to guide people through your app, or for advertising
	and promotion purposes."*

	THIS IS A DRIVER, NOT A SECOND SCHEDULER. `src/present/toast_schedule.luau`
	already owns priority ordering, the queue cap, FIFO within a priority, the
	read floor that priority may never truncate, and a reason code on every
	retirement. Every one of those rules is exactly what a callout queue needs, so
	this module configures that model with `maxVisible = 1` and drives the mount.
	Writing a second scheduler here would have produced a second, subtly different
	answer to "what happens when two things want the screen at once".

	TWO CONFIGURATION CHOICES, BOTH DELIBERATE:

	  * `maxVisible = 1`. The whole rule, in one number.
	  * A DURATION NO SESSION REACHES. A toast is a message that has been read
	    after four seconds; a coach mark waits for the player. `toast_schedule`
	    measures duration in seconds against an injected clock, so "never times
	    out" is spelled as a number no session gets to — not as `math.huge`, which
	    the model's own `isFinite` guard would reject and silently replace with the
	    four-second toast default.

	The READ FLOOR is left at the model's own: a more urgent callout arriving
	mid-sentence waits for the one on screen to have been readable before it takes
	its place. That is the same rule, seen from the other side, and it is why this
	module steps the clock from the presenter's tick rather than not at all.

	WHAT IT DOES NOT OWN. The surface is `presenter.presentAnchored`'s (D1) — the
	placement, the edge flip, the safe-area shift and the arrow tail are the
	shipped ones — and the ELIGIBILITY and INVALIDATION rules belong to
	`src/controls/callout.luau`, which decides whether a request is ever made.
	Nothing here reads or writes player state.
]]

local specGuard = require("../spec_guard")
local toastSchedule = require("./toast_schedule")

local callout_queue = {}

local DUMP_SCHEMA = "facet-callout-queue-dump/1"
-- ~31 years in seconds. See the header: a coach mark waits for the player, and
-- the scheduler wants a finite number.
local NEVER_TIMES_OUT = 1e9
-- a queue of guidance nobody asked for is worse than a queue of messages. Four
-- is generous for a mechanism Apple asks you to use sparingly.
local QUEUE_CAP = 4

local REQUEST_KEYS = specGuard.keySet({ "build", "id", "key", "onHide", "onShow", "priority" })

--[[ ctx:
	  presenter  `presentAnchored` / `dismiss` — the only way a surface exists
	  stack      the presented handles, read live, so a surface torn down by any
	             other route releases its queue slot instead of stalling it
]]
function callout_queue.new(ctx: any)
	local presenter = ctx.presenter
	local stack = ctx.stack
	local handleByPath = ctx.handleByPath

	local clock = 0
	-- entry id -> { data, handle } for the ONE mounted callout
	local mounted: any = nil

	local schedule
	local api = {}

	local function tearDown(reason: string)
		if mounted == nil then
			return
		end
		local record = mounted
		mounted = nil
		if table.find(stack, record.handle) ~= nil then
			presenter.dismiss(record.handle)
		end
		if record.data.onHide ~= nil then
			pcall(record.data.onHide, reason)
		end
	end

	--[[ MOUNT WHATEVER IS VISIBLE, DISMISS WHATEVER LEFT. `toast_schedule` is a
		pure model — it decides WHICH entry may be on screen and never mounts
		anything — so this is the whole of the driver. It runs on the model's own
		`onChange`, which fires once at the end of a resolve rather than once per
		mutation, so a push that displaces something costs one teardown and one mount
		instead of a flicker of both. ]]
	local function syncBody()
		local visible = schedule.visible()
		local entry = visible[1]
		if entry == nil then
			tearDown("preempt")
			return
		end
		if mounted ~= nil and mounted.id == entry.id then
			return
		end
		tearDown("preempt")
		local data = entry.data
		local panel, anchor = data.build()
		if panel == nil then
			-- a request whose source went away before its turn came: retire it rather
			-- than leaving the one slot occupied by nothing
			schedule.dismiss(entry.id, "capacity")
			return
		end
		local ok, handle = pcall(presenter.presentAnchored, panel, {
			id = data.id,
			--[[ NEVER A MODAL, AND NEVER THE FOCUS RING. `presentAnchored` routes
				through `present` rather than `presentModal` unless it is told otherwise,
				so there is no focus trap; `initialFocus = "none"` leaves the ring exactly
				where the player put it. A coach mark that captured focus would be a
				dialog wearing an arrow. ]]
			initialFocus = "none",
			anchor = anchor,
		})
		if not ok or type(handle) ~= "table" then
			schedule.dismiss(entry.id, "capacity")
			return
		end
		mounted = {
			id = entry.id,
			data = data,
			handle = handle,
			-- the SOURCE this plate points at, kept so `prune` can ask whether the
			-- surface holding it is still up (see below)
			sourcePath = if type(anchor) == "table" and type(anchor.source) == "table" then anchor.source.path else nil,
		}
		if data.onShow ~= nil then
			pcall(data.onShow)
		end
	end

	--[[ RE-ENTRANT BY CONSTRUCTION, so it is guarded. `presenter.dismiss` calls
		`prune()`, which can retire an entry, which resolves the schedule, which
		calls this again — and a mount running inside a teardown is how one surface
		ends up owned by two records. The OUTER call is the one that settles: the
		model is synchronous, so the visible set is final by the time it returns, and
		the outer pass re-reads it. ]]
	local syncing = false
	local pending = false
	local function sync()
		if syncing then
			-- a nested resolve moved the visible set out from under the pass in
			-- flight; the outer one runs again rather than settling on a stale read
			pending = true
			return
		end
		syncing = true
		local ok, err = pcall(function()
			local guard = 0
			repeat
				pending = false
				syncBody()
				guard += 1
			until not pending or guard >= QUEUE_CAP + 2
		end)
		syncing = false
		if not ok then
			error(err, 0)
		end
	end

	schedule = toastSchedule.new({
		maxVisible = 1,
		queueCap = QUEUE_CAP,
		duration = NEVER_TIMES_OUT,
		now = function(): number
			return clock
		end,
		onDismiss = function(entry: any, reason: string)
			-- EVERY RETIREMENT IS TRACEABLE, including the one dropped at the cap:
			-- a coach mark that vanished without a reason code is a coach mark
			-- whose caller cannot know whether to persist anything
			if mounted ~= nil and mounted.id == entry.id then
				tearDown(reason)
			elseif entry.data ~= nil and entry.data.onHide ~= nil then
				pcall(entry.data.onHide, reason)
			end
		end,
		onChange = sync,
	})

	--[[ ASK FOR THE SCREEN. Returns the entry id; `release(id, reason)` gives it
		back. A request that cannot be shown yet WAITS — it is not dropped and it is
		not shown beside the one that is up. ]]
	function api.request(spec: any): number
		specGuard.assertKnownKeys("presenter.presentCallout", spec, REQUEST_KEYS, "spec")
		if type(spec) ~= "table" or type(spec.build) ~= "function" or type(spec.id) ~= "string" then
			error(
				"Facet presenter.presentCallout: `id` (the surface id) and `build` (a function returning the "
					.. "panel blueprint and its anchor table) are both required. The queue mounts; the caller builds.",
				0
			)
		end
		return schedule.push({
			key = spec.key,
			priority = spec.priority,
			duration = NEVER_TIMES_OUT,
			data = spec,
		})
	end

	function api.release(id: number, reason: string?): boolean
		return schedule.dismiss(id, reason or "manual")
	end

	--[[ A SURFACE TORN DOWN BY ANY OTHER ROUTE RELEASES ITS SLOT. Without this a
		presenter-driven dismissal — an outside tap, a screen closing under it —
		would leave the queue believing a callout is still on screen, and the next
		one in line would wait forever for a plate nobody can see. ]]
	function api.prune()
		if mounted == nil then
			return
		end
		--[[ TWO WAYS A LIVE CALLOUT STOPS BEING ONE, and both have to release the
			slot or the next in line waits forever for a plate nobody can see:

			  * ITS OWN surface was torn down by another route — an outside tap, a
			    screen closing over it;
			  * THE SURFACE IT POINTS AT went away. A coach mark whose subject is
			    gone is an arrow pointing at nothing, and it must not outlive it. ]]
		local gone = table.find(stack, mounted.handle) == nil
		if not gone and mounted.sourcePath ~= nil and handleByPath ~= nil then
			gone = handleByPath(mounted.sourcePath) == nil
		end
		if not gone then
			return
		end
		--[[ CLEAR THE RECORD FIRST, THEN TEAR DOWN, THEN RELEASE THE SLOT — in that
			order, because this runs INSIDE `presenter.dismiss` and every step is
			re-entrant. Nilling `mounted` before dismissing keeps the nested
			`prune()` from finding the same record twice; doing the dismissal HERE
			rather than leaving it to `onDismiss` is the part that was wrong first
			time round — with `mounted` already nil, `onDismiss` takes its
			"not the mounted one" branch and reports without tearing anything down,
			which left a live plate over a screen that no longer existed. ]]
		local record = mounted
		mounted = nil
		if table.find(stack, record.handle) ~= nil then
			presenter.dismiss(record.handle)
		end
		schedule.dismiss(record.id, "manual")
	end

	-- advance the model's clock so a read floor can elapse. Idempotent, and it
	-- costs nothing while the queue is empty.
	function api.update(dt: number)
		if schedule.isEmpty() then
			return
		end
		clock += math.max(dt, 0)
		schedule.update()
	end

	function api.dump(): any
		local counts = schedule.counts()
		local queued: { any } = {}
		for _, entry in schedule.queued() do
			table.insert(queued, { id = entry.data.id, priority = entry.priority })
		end
		local showing = if mounted ~= nil then mounted.data.id else nil
		return table.freeze({
			schema = DUMP_SCHEMA,
			showing = showing,
			visible = counts.visible,
			queued = counts.queued,
			waiting = table.freeze(queued),
			text = if showing == nil
				then `no callout on screen, {counts.queued} waiting`
				else `callout '{showing}' on screen, {counts.queued} waiting`,
		})
	end

	return api
end

return callout_queue
