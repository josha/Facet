--!strict
--[[ THE FACET SERVICE BAG. It holds NO reactive API: state is `Compose.cell`,
	derivation is `Compose.formula`, observation is `Compose.watch` /
	`owner.watchStatic`, lifetime is a Compose owner and batching is the
	reactor's. What is here is what Compose has no verb for and one surface
	needs exactly once: the ERROR BOUNDARY that keeps a throwing binding from
	taking a surface down, the LAYOUT SETTLE pass that drives geometry feedback
	to a fixed point inside the flush, and the reactor and root owner the rest
	of the library hangs its own owners off.

	The reactor is Compose's own, taken directly. A surface's nodes mount into
	the UI runtime `render/compose_scene.luau` builds, and the application hands
	that runtime to `adopt` below so one settle pass and one boundary cover both
	scheduling domains.
]]
local Compose = require("../vendor/compose/core")
local profile = require("./profile")
local settle_pass = require("../render/settle_pass")

local services = {}

--[[ HOW LONG ONE MESSAGE STAYS QUIET. A binding that refuses its value refuses
	it again on the next frame and the next, so announcing every occurrence turns
	the output window into a wall — but the first version answered that by
	announcing a message ONCE PER CORE, forever, and a failure that came back an
	hour later was silent. Neither is a diagnostic. A repeat is announced again
	once the window has passed, carrying the count it swallowed, so "this is
	still happening" and "this happened again" are both readable and neither
	costs sixty lines a second. ]]
local REPORT_REPEAT_WINDOW_S = 5

--[[ `opts.warn` is where a contained failure is announced — real `warn()` by
	default, injectable so a spec asserting containment need not print past the
	suite's own PASS/FAIL lines. `opts.now` is the wall clock the repeat window
	rides, injectable for the same reason: a spec must be able to reach the far
	side of the window without sleeping. ]]
function services.new(opts: { warn: ((string) -> ())?, now: (() -> number)? }?): any
	local emitWarn = if opts and opts.warn then opts.warn else warn
	local now = if opts and opts.now then opts.now else os.clock
	local reactor = Compose.reactor()
	local lastError: string? = nil
	local announced: string? = nil
	local announcedAt = 0
	local suppressed = 0

	--[[ CONTAINMENT. `lastError` is STICKY: nil until the first contained
		failure and never cleared, so it reports "something was contained at some
		point in this core's life", not "this core is unhealthy now". The
		ANNOUNCEMENT is separate from it and is rate-limited per message. ]]
	local function report(failure: unknown)
		local message = tostring(failure)
		lastError = message
		if message == announced and now() - announcedAt < REPORT_REPEAT_WINDOW_S then
			suppressed += 1
			return
		end
		local tail = if message == announced and suppressed > 0 then ` (and {suppressed} more since)` else ""
		emitWarn(`Facet: quarantined - {message}{tail}`)
		announced = message
		announcedAt = now()
		suppressed = 0
	end
	local boundary = { report = report }

	local owner = Compose.createOwner(reactor)
	owner.guardWith(boundary)

	local pass = settle_pass.install(reactor, report, profile.span)

	local core: any = {
		-- the runtime this application is on, so a control written outside this
		-- repository reaches cells and formulas through the core it is handed
		-- rather than by requiring around it
		Compose = Compose,
		reactor = reactor,
		owner = owner,
		--[[ Any owner Facet did not create as a child of `owner` — a mount root,
			a control's detached owner — takes the same boundary through this, so
			one surface has one place a failure is reported. ]]
		boundary = boundary,
		guard = function(other: any)
			other.guardWith(boundary)
			return other
		end,
		report = report,
		lastError = function(): string?
			return lastError
		end,
		settlePass = pass,
		--[[ The UI runtime is built after the core is (the presenter has to exist
			before it), and it schedules on a reactor of its own. This puts the same
			settle pass and the same containment on it, so a write that reaches the
			mounted bindings settles the surface and cannot escape as a throw into
			whatever wrote. ]]
		adopt = function(runtime: any)
			pass.attach(runtime.reactor)
			return runtime
		end,
	}
	return core
end

services.REPORT_REPEAT_WINDOW_S = REPORT_REPEAT_WINDOW_S

return services
