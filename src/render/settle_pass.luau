--!strict
--[[ THE LAYOUT SETTLE PASS.

	A surface's geometry feeds back: it solves, publishes what it measured, and
	the publication can change what it must solve. That cycle has to reach a
	fixed point INSIDE the flush that started it, so a top-level `env:set`
	returns with the surface solved rather than one frame behind.

	Compose drains watches to quiescence but has no hook for UNTRACKED terminal
	work — `watchTerminal` re-runs on a dependency change, and these callbacks
	have no dependencies, they read flags that a drain just wrote. So this
	module installs the hook on the reactor Facet owns, decorating that
	instance's own `settle` and `batch` entry points; it never touches Compose.

	THE PASS. After a drain, run every registered callback in REGISTRATION
	order. A callback that writes ends the pass; propagation drains, and the
	pass RESTARTS from the first callback, so every callback observes every
	other one's publication. Passes repeat until one writes nothing. A callback
	MUST therefore be cheap and idempotent when it has nothing to do.

	"WROTE SOMETHING" is Compose's own write clock, which advances on exactly
	the cell writes that changed a value — a native binding or watch delivery
	that publishes geometry counts, one that publishes nothing does not.

	THE CAP. A measure -> publish cycle that will not converge is a loud error,
	never a hang and never a silent frame: at 100 passes the pass stops, the
	repeat offender is QUARANTINED until it is re-registered, and the failure
	goes to the reporter.
]]
local clock = require("../vendor/compose/core/reactive/clock")

local PASS_CAP = 100

export type Record = { fn: () -> (), label: string, disposed: boolean, quarantined: boolean }

export type Pass = {
	register: (fn: () -> (), label: string?) -> () -> (),
	--[[ A surface has TWO scheduling domains — the services reactor its own
		state and watches live on, and the UI runtime's, which drives mounted
		bindings — and one write reaches both. `attach` puts the same pass and
		the same containment on a second reactor, so whichever one a write
		settles, the surface settles once and a failure in either is contained. ]]
	attach: (reactor: any) -> (),
	run: () -> (),
	count: () -> number,
	--[[ Shut the pass down: no registered callback runs again, and the registry
		is emptied. The reactors stay decorated — a decoration cannot be lifted
		safely, because a sink COPIES `__enqueueSettleConsumer` when it is created
		and would keep calling the version it copied — so the flag is what makes
		the pass dead rather than the restoration. Idempotent. ]]
	dispose: () -> (),
}

--[[ THE VENDORED HOOKS THIS PASS IS BUILT ON, asserted at install rather than
	discovered at runtime. Three of the four are private to Compose's reactor
	(`src/vendor/compose/core/reactive/reactor.luau`), and the containment this
	module provides is INVISIBLE when one goes missing: the old code read
	`if inline ~= nil`, so an upstream rename turned the single-consumer entry —
	the shipped shape of a bound prop — into an undecorated hole, silently. A
	vendored dependency that moves under you must fail at construction, where the
	message can name the pin. ]]
local function assertHooks(reactor: any)
	local missing: { string } = {}
	for _, hook in { "settle", "batch", "__enqueueSettleConsumer" } do
		if type((reactor :: any)[hook]) ~= "function" then
			table.insert(missing, hook)
		end
	end
	if type(clock.state) ~= "table" or type(clock.state.now) ~= "number" then
		table.insert(missing, "reactive/clock.state.now")
	end
	if #missing == 0 then
		return
	end
	error(
		`Facet: the layout settle pass depends on Compose scheduling hooks this reactor does not have — {table.concat(
			missing,
			", "
		)}. `
			.. "The vendored runtime under src/vendor/compose is pinned by src/vendor/compose/UPSTREAM.lock; "
			.. "if that pin moved, re-check src/render/settle_pass.luau against reactive/reactor.luau.",
		0
	)
end

local function nameOf(fn: () -> (), label: string?): string
	if label ~= nil then
		return label
	end
	local source, line = debug.info(fn, "sl")
	return `settle@{string.match(source, "[^/]+$") or source}:{line}`
end

--[[ Decorate `reactor`'s settle and batch so the pass runs after each drain
	that Facet's own writes open, and answer the registry. `report` receives a
	callback's failure and the iteration-cap failure. ]]
local function install(reactor: any, report: (string) -> (), span: (<T>(string, () -> T) -> T)?): Pass
	local measure: any = span or function(_label: string, body: any)
		return body()
	end
	assertHooks(reactor)
	local records: { Record } = {}
	local running = false
	local depth = 0
	local flushing = false
	--[[ A DRAIN IS IN PROGRESS. Distinct from `flushing`, which spans a whole
		`react` phase: this is true only while vendored scheduling code is actually
		running watches, and it is what tells the single-consumer entry below that
		its `inline(watch)` QUEUED rather than ran. ]]
	local draining = false
	local attached: { { target: any, batch: any } } = {}
	local disposed = false
	local batch = reactor.batch

	--[[ ONE FLUSH IS ONE `react` PHASE, however many scheduling domains it
		drains. A surface has two — its services reactor and its UI runtime's —
		and one write reaches both, so an unguarded span would report two flushes
		for the round trip the settle phase exists to make cost one. ]]
	local function react(body: () -> ())
		if flushing then
			body()
			return
		end
		flushing = true
		local ok, err = pcall(measure, "react", body)
		flushing = false
		if not ok then
			error(err, 0)
		end
	end

	local function compact()
		local live = 0
		for _, record in records do
			if not record.disposed then
				live += 1
				records[live] = record
			end
		end
		for index = #records, live + 1, -1 do
			records[index] = nil
		end
	end

	local function run()
		if disposed or running or draining or depth > 0 or #records == 0 then
			return
		end
		running = true
		local passes = 0
		local writes: { [Record]: number } = {}
		while true do
			local writer: Record? = nil
			for _, record in records do
				if not record.disposed and not record.quarantined then
					local before = clock.state.now
					local ok, failure = pcall(batch, reactor, record.fn)
					if not ok then
						report(tostring(failure))
					end
					if clock.state.now ~= before then
						writer = record
						writes[record] = (writes[record] or 0) + 1
						break
					end
				end
			end
			if writer == nil then
				break
			end
			passes += 1
			if passes >= PASS_CAP then
				local offender = writer :: Record
				if writes[offender] > 1 then
					offender.quarantined = true
				end
				report(
					`Facet: the settle pass exceeded the {PASS_CAP}-round iteration cap — '{offender.label}' is QUARANTINED until it is re-registered`
				)
				break
			end
		end
		running = false
		compact()
	end

	--[[ A DRAIN THAT THROWS MUST NOT TAKE THE SURFACE DOWN. This is the flush a
		plain write opens, and the writer is ordinary application code that has no
		way to handle another node's failure: it is CONTAINED here and reported,
		exactly as the boundary contains a watch body. A batch is different — its
		caller asked for the work and gets the error back. ]]
	local function attach(target: any)
		assertHooks(target)
		local drain, targetBatch = target.settle, target.batch
		table.insert(attached, { target = target, batch = targetBatch })
		--[[ Run `body` as a DRAIN — vendored scheduling code that may run watches
			— and answer whether this call is the one that opened it. A nested call
			answers false, and the pass belongs to whoever answered true. ]]
		local function drained(body: () -> ()): boolean
			if draining then
				body()
				return false
			end
			draining = true
			local ok, err = pcall(body)
			draining = false
			if not ok then
				error(err, 0)
			end
			return true
		end
		--[[ THE THIRD ENTRY, and the one that is easy to miss. A cell with a single
			terminal consumer does not go through `settle` at all: the write runs
			that consumer INLINE and raises out of the assignment. That is the shipped
			shape of a bound prop, so without this a refused property value would
			unwind whoever set the cell. Decorated before any sink exists, because a
			sink copies this function when it is created. ]]
		local inline = target.__enqueueSettleConsumer
		--[[ AND IT IS ONLY SOMETIMES AN ENTRY. `inline(watch)` runs that consumer
			and drains — but ONLY when nothing is draining already; mid-drain it
			just appends to the queue the caller is walking and returns at once. The
			first version could not tell those apart and ran the whole pass either
			way, so a watch fanning one plain write out to twenty single-sink cells
			swept the pass twenty-one times, each sweep landing INSIDE the writing
			watch's body — the renderer's geometry re-solve re-entered before the
			watch that dirtied the geometry had finished, and before any sibling
			watch had run at all. The same write inside `runtime:batch` swept once,
			which is the number both shapes must cost. `drained` answers who owns
			the drain, and the pass runs when the OUTERMOST one ends. ]]
		target.__enqueueSettleConsumer = function(watch: any)
			local ok, err = pcall(react, function()
				if drained(function()
					inline(watch)
				end) then
					run()
				end
			end)
			if not ok then
				report(tostring(err))
			end
		end
		target.settle = function(self: any)
			local ok, err = pcall(react, function()
				if drained(function()
					drain(self)
				end) then
					run()
				end
			end)
			if not ok then
				report(tostring(err))
			end
		end
		target.batch = function(self: any, body: any): ...any
			local results: any = nil
			--[[ ONE BATCH, EVERY REACTOR. A core schedules on two reactors (its own and
				the UI runtime's), and a write settles the reactor of whoever READS the
				cell. A batch that opened only `self` left the other one draining inside
				the body: a control's write and its `onChange` stopped being one turn,
				and a selection the callback handed back still mounted its page. The
				outermost batch opens every attached reactor. ]]
			local whole = body
			if depth == 0 then
				for _, other in attached do
					if other.target ~= self then
						local inner = whole
						whole = function()
							return other.batch(other.target, inner)
						end
					end
				end
			end
			depth += 1
			local ok, err = pcall(measure, "mutate", function()
				results = table.pack(targetBatch(self, whole))
			end)
			depth -= 1
			--[[ The propagation a batch opens closes with the batch, and the settle
				pass runs after it — but only for the OUTERMOST one. A nested batch
				collapses into its parent, so counting a phase for it would report
				six flushes where a resize opened one. ]]
			if depth == 0 then
				react(run)
			end
			if not ok then
				error(err, 0)
			end
			return table.unpack(results, 1, results.n)
		end
	end
	attach(reactor)

	local pass: Pass
	pass = {
		register = function(fn: () -> (), label: string?): () -> ()
			local record: Record = { fn = fn, label = nameOf(fn, label), disposed = disposed, quarantined = false }
			table.insert(records, record)
			return function()
				if record.disposed then
					return
				end
				record.disposed = true
				if not running then
					compact()
				end
			end
		end,
		attach = attach,
		run = run,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			for _, record in records do
				record.disposed = true
			end
			if not running then
				compact()
			end
		end,
		count = function(): number
			local live = 0
			for _, record in records do
				if not record.disposed then
					live += 1
				end
			end
			return live
		end,
	}
	return pass
end

return { install = install, PASS_CAP = PASS_CAP }
