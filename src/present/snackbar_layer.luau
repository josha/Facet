--!strict
--[[ THE SNACKBAR SERVICE: one per application, booted with it, owning one
	persistent bottom chrome host, the keyed rows inside it and every admitted
	entry's lifetime. `UI.Snackbar` and `app.presentSnackbar` are its only two
	doors and they share this one model.

	THE CALLER'S FACT DECIDES. `isPresented` is read, never written. Close,
	focused Cancel, a timeout and a supersession each PROPOSE false through
	`onPresentedChange(false)`; the row leaves only when the caller's value turns
	false. A refusal keeps the same row, its paint and its focus. An action runs
	its callback once and leaves the row mounted unless the caller closes it
	during that callback (reason "action"). `onDismiss(reason)` reports each
	accepted retirement once — action | close | timeout | superseded | cancel; a
	false the caller writes on its own is "close". Forced release (owner
	teardown, the returned release function, application disposal) never asks
	and never reports.

	ADMISSION. One active row, at most eight waiting, and a total of nine
	including rows still painting their exit. Past that a new admission is
	REFUSED before anything admitted moves: an error at construction, or through
	the reactive error boundary on a later false -> true, re-armed only by the
	next false -> true. A permanently refused timeout or supersession can starve
	the queue; that is the caller's choice, and it is documented, not overridden.

	SCHEDULING is `toast_schedule` in its controlled mode: descending priority,
	FIFO within a priority, supersession only by a strictly higher priority after
	the incumbent's 2.5 s readable floor, and a timeout at max(duration, 2.5 s)
	of READABLE time. Readable time runs only while the active row is mounted,
	not hovered, not focused and not blocked by another exclusive surface; queued
	time never counts. Timing rides `presenter.onTick`, subscribed only while a
	row is active.

	THE SERVICE boots with the application; its HOST is presented by the first
	registration and then kept for the application's life: `focusChrome =
	"bottom"`, passive, `initialFocus = "none"`, in its own display band above
	base screens and toasts and below the drag proxy and modals. It stays mounted
	while empty, reserves nothing while empty, and an empty chrome scope takes no
	part in navigation (`focus_graph.chromeLive`), so its presentation order
	relative to content does not matter. Screen apps only. ]]
local Compose = require("../vendor/compose/core")
local toastSchedule = require("./toast_schedule")
local selection = require("../selection_model")
local observeChange = require("../core/on_change")
local cleanup = require("../core/cleanup")
local contribution = require("../input/contribution")
local focusMap = require("./focus_map")

local snackbar_layer = {}

snackbar_layer.WAITING = 8
snackbar_layer.CAPACITY = 9
snackbar_layer.READ_FLOOR = 2.5
snackbar_layer.DISPLAY_BAND = 25000 -- above SURFACE_LAYER.toast, below dragProxy
snackbar_layer.HOST_ID = "FacetSnackbars"

local REASONS = { timeout = "timeout", preempt = "superseded" }

export type Ctx = {
	presenter: any,
	env: any,
	core: any,
	-- presents a component as an ordinary screen; returns (close, node, handle)
	present: (component: () -> any, options: any) -> (() -> (), any, any),
	-- builds the host screen: the live row list, the host contribution and the
	-- row behaviour (the application's controls build the rows)
	host: (rows: any, attach: (node: any) -> any, actions: any) -> any,
}

function snackbar_layer.new(ctx: Ctx): any
	local presenter, core = ctx.presenter, ctx.core
	local graph = presenter.focus
	local service = {}
	local disposed = false
	local clock = 0
	local serial = 0
	local admitted = 0 -- active + waiting + retiring
	local records: { [string]: any } = {}
	local rows = Compose.cell(table.freeze({}))
	local hostHandle: any = nil
	local tickOff: (() -> ())? = nil
	local reservation: any = nil
	local returnTo: string? = nil -- the content target focus left to enter a row
	local schedule: any
	local ensureHost: () -> ()

	local function listRows()
		local out = {}
		for _, rec in records do
			-- a retiring row leaves the list; the keyed region keeps its exit paint
			if rec.phase == "active" then
				table.insert(out, rec)
			end
		end
		table.sort(out, function(a, b)
			return a.serial < b.serial
		end)
		rows:set(table.freeze(out))
	end

	local function activeRec(): any
		for _, entry in schedule.visible() do
			return entry.data
		end
		return nil
	end

	local function rowPath(rec: any): string?
		return rec.path
	end

	local function focusInside(rec: any): boolean
		local path, focused = rowPath(rec), graph.focused:peek()
		return path ~= nil and focused ~= nil and string.sub(focused, 1, #path) == path
	end

	-- another exclusive surface (a modal, an engaged screen) covers the strip
	local function blocked(): boolean
		local exclusive = presenter.exclusiveSurfaceActive
		if exclusive == nil or not exclusive:peek() then
			return false
		end
		return hostHandle == nil or hostHandle.responder:peek() ~= "engaged"
	end

	local function readablePaused(rec: any): boolean
		return not rec.mounted or rec.hovered or focusInside(rec) or blocked()
	end

	local function stopTick()
		if tickOff ~= nil then
			tickOff()
			tickOff = nil
		end
	end
	local function ensureTick()
		if tickOff ~= nil or disposed then
			return
		end
		tickOff = presenter.onTick(function(dt: number)
			clock += dt
			local rec = activeRec()
			if rec == nil then
				stopTick()
				return
			end
			if not readablePaused(rec) then
				rec.readable += dt
			end
			schedule.update()
		end)
	end

	local function report(rec: any, reason: string)
		if rec.forced or rec.reported then
			return
		end
		rec.reported = true
		if rec.spec.onDismiss ~= nil then
			pcall(rec.spec.onDismiss, reason)
		end
	end

	-- the row finished painting its exit (or never painted): capacity returns
	local function finish(rec: any)
		if records[rec.key] ~= rec then
			return
		end
		records[rec.key] = nil
		admitted -= 1
		if rec.registration ~= nil and rec.registration.rec == rec then
			rec.registration.rec = nil
		end
	end

	-- a proposal: true when the caller's fact now reads false
	local function propose(rec: any, reason: string): boolean
		if rec.phase == "retiring" or rec.spec.onPresentedChange == nil then
			return false
		end
		rec.pending = reason
		pcall(rec.spec.onPresentedChange, false)
		local accepted = rec.phase == "retiring" or rec.registration.wanted:peek() == false
		if not accepted then
			rec.pending = nil
		end
		return accepted
	end

	schedule = toastSchedule.new({
		controlled = true,
		maxVisible = 1,
		queueCap = snackbar_layer.WAITING,
		readFloor = snackbar_layer.READ_FLOOR,
		now = function()
			return clock
		end,
		elapsed = function(entry: any): number
			return entry.data.readable
		end,
		request = function(entry: any, reason: string): boolean
			return propose(entry.data, REASONS[reason] or reason)
		end,
		onChange = function()
			local rec = activeRec()
			if rec ~= nil then
				rec.phase = "active"
				ensureTick()
			end
			listRows()
		end,
		onDismiss = function(entry: any, reason: string)
			local rec = entry.data
			local wasActive = rec.phase == "active"
			rec.phase = "retiring"
			report(rec, rec.pending or REASONS[reason] or reason)
			-- focus that stood on the row goes back to the content it came from
			if wasActive and focusInside(rec) and returnTo ~= nil then
				graph.focusOn(returnTo)
			end
			if not wasActive or not rec.painted then
				finish(rec)
			end
		end,
	})

	local function admit(registration: any, where: string)
		if admitted >= snackbar_layer.CAPACITY then
			error(
				`Facet {where}: the snackbar queue is full ({snackbar_layer.CAPACITY} shown, waiting or leaving). `
					.. "Hide one before showing another; this admission was refused and nothing else moved.",
				0
			)
		end
		serial += 1
		local rec = {
			key = `snack-{serial}`,
			serial = serial,
			spec = registration.spec,
			registration = registration,
			phase = "queued",
			readable = 0,
		}
		records[rec.key] = rec
		admitted += 1
		registration.rec = rec
		local ok, err = pcall(schedule.push, {
			id = rec.key,
			priority = registration.spec.priority or 0,
			duration = registration.spec.duration,
			data = rec,
		})
		if not ok then
			error(err, 0)
		end
	end

	local function remove(rec: any, reason: string)
		if rec.phase == "retiring" then
			return
		end
		schedule.dismiss(rec.key, reason)
	end

	--[[ ONE REGISTRATION per UI.Snackbar (or presentSnackbar call): it watches
		the caller's fact under `owner` and admits a fresh entry — a fresh
		generation, a fresh dwell — on every false -> true. ]]
	function service.register(spec: any, owner: any, where: string): any
		if disposed then
			error(`Facet {where}: the application is disposed.`, 0)
		end
		ensureHost()
		local registration: any = { spec = spec, rec = nil }
		registration.wanted = Compose.formula(function(use)
			return selection.read(spec.isPresented, use) == true
		end)
		local function sync(want: boolean)
			local rec = registration.rec
			if want and (rec == nil or rec.phase == "retiring") then
				admit(registration, where)
			elseif not want and rec ~= nil and rec.phase ~= "retiring" then
				remove(rec, rec.pending or "close")
			end
		end
		if registration.wanted:peek() then
			sync(true) -- refused here is a construction error
		end
		observeChange(owner, registration.wanted, sync)
		owner.own(function()
			local rec = registration.rec
			if rec ~= nil and rec.phase ~= "retiring" then
				rec.forced = true
				remove(rec, "forced")
			end
		end)
		function registration.dump(): any
			local rec = registration.rec
			return {
				admitted = rec ~= nil and rec.phase ~= "retiring",
				visible = rec ~= nil and rec.phase == "active",
				queued = rec ~= nil and rec.phase == "queued",
				readable = if rec ~= nil then rec.readable else 0,
			}
		end
		return registration
	end

	-- ===== row behaviour, handed to the row builder ========================
	local actions = {}
	function actions.close(rec: any)
		propose(rec, "close")
	end
	function actions.activate(rec: any)
		if rec.phase ~= "active" or rec.spec.action == nil then
			return
		end
		rec.pending = "action"
		pcall(rec.spec.action.onActivate)
		if rec.phase ~= "retiring" then
			rec.pending = nil
		end
		-- a pointer press engaged the passive host; give input back to the
		-- content unless the keyboard ring is on the row
		if
			hostHandle ~= nil
			and hostHandle.resign ~= nil
			and hostHandle.responder:peek() == "engaged"
			and graph.focusOrigin() ~= "navigation"
		then
			hostHandle.resign()
		end
	end
	function actions.cancel(rec: any): boolean
		local back = returnTo
		propose(rec, "cancel")
		if back ~= nil and graph.focused:peek() ~= back then
			graph.focusOn(back)
		end
		return true
	end
	function actions.mounted(rec: any, path: string)
		rec.path, rec.mounted, rec.painted = path, true, true
	end
	function actions.unmounted(rec: any)
		rec.mounted = false
		if rec.phase == "retiring" then
			finish(rec)
		end
	end
	function actions.hover(rec: any, on: boolean)
		rec.hovered = on
	end

	-- ===== the persistent host ===========================================
	local function attachHost(node: any): any
		return contribution.attach(node, {
			syncGeometry = function(_rectOf: any, mounted: any?)
				if mounted == nil or hostHandle == nil or presenter.reserveHud == nil then
					return
				end
				reservation = reservation
					or presenter.reserveHud({
						id = `facet-snackbar:{tostring(service)}`,
						edge = "bottom",
					})
				local ctrl = hostHandle.controller
				local union: any = nil
				for _, rec in rows:peek() do
					local r = if rec.path ~= nil and ctrl.screenRectOf ~= nil then ctrl.screenRectOf(rec.path) else nil
					if type(r) == "table" and r.w > 0 and r.h > 0 then
						if union == nil then
							union = { x = r.x, y = r.y, w = r.w, h = r.h }
						else
							local x1, y1 = math.min(union.x, r.x), math.min(union.y, r.y)
							local x2 = math.max(union.x + union.w, r.x + r.w)
							local y2 = math.max(union.y + union.h, r.y + r.h)
							union = { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
						end
					end
				end
				reservation.update(union)
			end,
		})
	end

	-- presented by the FIRST registration and then kept for the application's
	-- life, empty or not (an application that never shows a snackbar carries no
	-- extra surface, root or scope)
	local close: () -> () = function() end
	local focusOff: (() -> ())? = nil
	function ensureHost()
		if hostHandle ~= nil then
			return
		end
		-- remember where focus came from when it steps onto a row
		focusOff = observeChange(core.owner, graph.focused, function(path: any)
			local onRow = false
			for _, rec in records do
				local p = rec.path
				if p ~= nil and type(path) == "string" and string.sub(path, 1, #p) == p then
					onRow = true
					break
				end
			end
			if not onRow and type(path) == "string" then
				returnTo = path
			end
		end)
		-- under the APPLICATION's owner: the first registration may sit inside a
		-- component whose teardown must not take the persistent host with it
		Compose.withOwner(core.owner, function()
			close, _, hostHandle = ctx.present(function()
				return ctx.host(rows, attachHost, actions)
			end, {
				responder = "passive",
				focusChrome = "bottom",
				initialFocus = "none",
				navigationGroups = focusMap.autoGroups,
			})
		end)
		if hostHandle ~= nil and hostHandle.controller ~= nil and hostHandle.controller.setDisplayOrder ~= nil then
			hostHandle.displayOrder = snackbar_layer.DISPLAY_BAND
			hostHandle.controller.setDisplayOrder(snackbar_layer.DISPLAY_BAND)
		end
	end

	function service.counts(): any
		local c = schedule.counts()
		return { active = c.visible, waiting = c.queued, admitted = admitted }
	end

	-- submissions stop, ticks stop, every entry is released without asking,
	-- then the host goes; one throwing step does not skip the others
	function service.dispose()
		if disposed then
			return
		end
		disposed = true
		local steps: { () -> () } = { stopTick }
		if focusOff ~= nil then
			table.insert(steps, focusOff)
		end
		table.insert(steps, function()
			for _, rec in records do
				rec.forced = true
			end
			schedule.clear("forced")
		end)
		table.insert(steps, function()
			if reservation ~= nil then
				reservation.dispose()
			end
		end)
		table.insert(steps, function()
			close()
		end)
		cleanup(steps)
	end

	return service
end

return snackbar_layer
