--!strict
-- MicroProfiler phase scopes (roadmap Step 9, acceptance PL-8).
--
-- WHY THESE CASES EXIST. An unbalanced `debug.profilebegin` does not lose one
-- measurement — it leaves the engine's scope stack open, so every later frame in
-- the capture is attributed to the wrong scope. That failure is invisible on the
-- host that runs this suite, because Lune has no `debug.profilebegin` at all and
-- the instrumented branch never executes. So every case here installs a RECORDING
-- hook pair through `profile.setHooks`, which runs the real instrumented path
-- (same branch, same pcall, same counters) against an observable sink.
--
-- The cardinality bound is asserted here too. "Do not create a label per row, key,
-- or node" is the plan's rule; a closed set plus a maximum is how it stops being a
-- comment someone can drift past one call site at a time.

local testkit = require("./lib/testkit")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local LuauUI = require("../src")
local profile = require("../src/core/profile")
local fake_target = require("./lib/fake_target")

-- a recording engine: every begin/end lands in one ordered log, so BALANCE is a
-- property of the log rather than a claim about the code
-- Scopes ship OFF (the production default), so a recorder has to turn them on as well
-- as install the sink — and put both back afterwards, or one case leaks instrumentation
-- into the next.
local function withRecorder<T>(fn: (log: { string }) -> T): T
	local log: { string } = {}
	profile.resetCounters()
	profile.setEnabled(true)
	profile.setHooks(function(label: string)
		table.insert(log, "+" .. label)
	end, function()
		table.insert(log, "-")
	end)
	local ok, result = pcall(fn, log)
	profile.setHooks(nil, nil)
	profile.setEnabled(false)
	profile.resetCounters()
	if not ok then
		error(result, 0)
	end
	return result :: T
end

local function depthOf(log: { string }): (number, number)
	local depth, worst = 0, 0
	for _, entry in log do
		if string.sub(entry, 1, 1) == "+" then
			depth += 1
			if depth > worst then
				worst = depth
			end
		else
			depth -= 1
		end
		-- a negative depth means an end arrived with nothing open: the corrupting
		-- shape, and it must be impossible rather than merely unobserved
		assert(depth >= 0, "profile scope stack underflowed")
	end
	return depth, worst
end

describe("profile scopes are a closed, bounded set", function()
	it("every declared label is prefixed so LibMP can select exactly this set", function()
		local n = 0
		for key, label in profile.SCOPES do
			n += 1
			expect(string.sub(label, 1, 7)).toBe("LuauUI/")
			-- the label is derived from the key, so a capture's bar name and the
			-- call-site vocabulary can never drift apart
			expect(label).toBe("LuauUI/" .. key)
		end
		expect(n > 0).toBe(true)
		expect(n <= profile.MAX_SCOPES).toBe(true)
	end)

	it("an undeclared scope name is refused at the call, naming the offender", function()
		local ok, err = pcall(function()
			profile.span("row-17", function()
				return 1
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "row%-17") ~= nil).toBe(true)
		expect(string.find(tostring(err), "closed set") ~= nil).toBe(true)
	end)

	it("refusing an undeclared name opens no scope at all", function()
		withRecorder(function(log)
			pcall(function()
				profile.span("per/node/label", function()
					return 1
				end)
			end)
			expect(#log).toBe(0)
			expect(profile.counters().opens).toBe(0)
			return true
		end)
	end)
end)

describe("a span is balanced on every exit path", function()
	it("a normal return closes the scope and returns the body's value", function()
		withRecorder(function(log)
			local value = profile.span("scenario", function()
				return 42
			end)
			expect(value).toBe(42)
			expect(log[1]).toBe("+LuauUI/scenario")
			expect(log[2]).toBe("-")
			local depth = depthOf(log)
			expect(depth).toBe(0)
			expect(profile.counters().balanced).toBe(true)
			return true
		end)
	end)

	it("an ERRORING body still closes the scope, and the error value is unchanged", function()
		withRecorder(function(log)
			local ok, err = pcall(function()
				profile.span("mutate", function(): number
					error("boom-42", 0)
				end)
			end)
			expect(ok).toBe(false)
			-- level 0 on both raise sites: the message a caller matches on is the
			-- one the body wrote, with no extra position prefix bolted on
			expect(err).toBe("boom-42")
			expect(log[1]).toBe("+LuauUI/mutate")
			expect(log[2]).toBe("-")
			expect(profile.counters().balanced).toBe(true)
			return true
		end)
	end)

	it("a non-string error value survives the span unchanged", function()
		withRecorder(function()
			local sentinel = { code = "E_STALE" }
			local ok, err = pcall(function()
				profile.span("resource", function(): number
					error(sentinel)
				end)
			end)
			expect(ok).toBe(false)
			expect(err).toBe(sentinel)
			expect(profile.counters().balanced).toBe(true)
			return true
		end)
	end)

	it("nested spans unwind in order when the INNER one throws", function()
		withRecorder(function(log)
			local ok = pcall(function()
				profile.span("mount", function()
					profile.span("commit", function(): number
						error("inner", 0)
					end)
					return 1
				end)
			end)
			expect(ok).toBe(false)
			expect(log[1]).toBe("+LuauUI/mount")
			expect(log[2]).toBe("+LuauUI/commit")
			expect(log[3]).toBe("-")
			expect(log[4]).toBe("-")
			local depth, worst = depthOf(log)
			expect(depth).toBe(0)
			expect(worst).toBe(2)
			expect(profile.counters().balanced).toBe(true)
			return true
		end)
	end)

	it("a THROWING hook cannot strand the counters or the caller (RR-1/RR-2)", function()
		-- `setHooks` takes an arbitrary pair, and an exception escaping the OPEN hook
		-- used to leave depth at 1 and opens > closes permanently — and, one layer up,
		-- to escape `flush`'s react span before `flushing = false` could run, killing
		-- the core for the rest of the session with nothing recorded.
		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function()
			error("instrument exploded", 0)
		end, function()
			error("instrument exploded on close too", 0)
		end)
		local ran = false
		local value = profile.span("react", function()
			ran = true
			return "body still ran"
		end)
		expect(ran).toBe(true)
		expect(value).toBe("body still ran")
		local c = profile.counters()
		expect(c.opens).toBe(c.closes)
		expect(c.depth).toBe(0)
		expect(c.balanced).toBe(true)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
	end)

	it("the counters see the same opens and closes the recorder does", function()
		withRecorder(function(log)
			for _ = 1, 5 do
				profile.span("react", function()
					return true
				end)
			end
			local c = profile.counters()
			expect(c.opens).toBe(5)
			expect(c.closes).toBe(5)
			expect(c.byScope.react).toBe(5)
			expect(c.depth).toBe(0)
			expect(#log).toBe(10)
			return true
		end)
	end)
end)

describe("scopes stay out of the way when the host cannot profile", function()
	it("with no engine hooks the body runs, unwrapped, and no counter moves", function()
		profile.setHooks(nil, nil)
		profile.resetCounters()
		local ran = false
		local value = profile.span("arrange", function()
			ran = true
			return "v"
		end)
		expect(ran).toBe(true)
		expect(value).toBe("v")
		-- Lune has no debug.profilebegin, so this is the real headless path
		expect(profile.available()).toBe(false)
		expect(profile.counters().opens).toBe(0)
	end)

	it("scopes are OFF by default: production pays no pcall and keeps its tracebacks", function()
		-- THE PRODUCT DECISION, PINNED (platform review MAJOR-2). With the default at
		-- `true`, every LuauUI phase on the engine ran under a pcall and re-raised at
		-- level 0 — so an error inside a solve reached a game's console with the stack
		-- below the boundary gone, permanently, to instrument a session nobody reads.
		-- Lune could never catch it, because `active` is false here and the suite
		-- always took the un-instrumented path. This case is the guard.
		expect(profile.enabled()).toBe(false)
	end)

	it("setEnabled(false) suppresses instrumentation even where the engine exists", function()
		withRecorder(function(log)
			profile.setEnabled(false)
			profile.span("measure", function()
				return 1
			end)
			expect(#log).toBe(0)
			profile.setEnabled(true)
			profile.span("measure", function()
				return 1
			end)
			expect(#log).toBe(2)
			return true
		end)
		profile.setEnabled(false)
	end)

	it("an error raised while scopes are OFF keeps its ordinary position prefix", function()
		profile.setHooks(nil, nil)
		local ok, err = pcall(function()
			profile.span("commit", function(): number
				error("plain")
			end)
		end)
		expect(ok).toBe(false)
		-- error(msg) with the default level adds `file:line:`; the uninstrumented
		-- path must not have rewritten that, because it is what the rest of the
		-- framework's error handling already reads
		expect(string.find(tostring(err), "plain") ~= nil).toBe(true)
		expect(string.find(tostring(err), ":%d+: ") ~= nil).toBe(true)
	end)
end)

describe("a real render pass emits the phase set and stays balanced", function()
	it("mount -> solve -> commit produces only declared labels, and closes them all", function()
		withRecorder(function(log)
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
			local adapter = fake_target.new()
			local system = LuauUI.newActionSystem(core)
			local pres = LuauUI.newPresenter(core, env, adapter, system)
			local n = core:signal(0)
			local label = core:memo(function(use)
				return `n={use(n)}`
			end)
			local handle = pres.present(LuauUI.UI.Screen({
				id = "S",
				children = {
					LuauUI.UI.Text({ id = "T", text = label }),
					LuauUI.UI.Button({ id = "B", label = "go" }),
				},
			}))
			core:transaction(function()
				n:set(1)
			end)
			pres.refresh()
			pres.dismiss(handle)

			-- EVERY emitted label is a declared one. This is the mechanical form of
			-- "no label per row, key or node": if any call site ever interpolated a
			-- path into a scope name, an undeclared label would appear here (and
			-- `span` would have refused it first).
			local declared: { [string]: boolean } = {}
			for _, l in profile.SCOPES do
				declared[l] = true
			end
			local seen: { [string]: boolean } = {}
			for _, entry in log do
				if string.sub(entry, 1, 1) == "+" then
					local l = string.sub(entry, 2)
					expect(declared[l]).toBe(true)
					seen[l] = true
				end
			end
			local depth = depthOf(log)
			expect(depth).toBe(0)
			expect(profile.counters().balanced).toBe(true)
			-- the phases a render pass must be able to show
			expect(seen["LuauUI/mount"]).toBe(true)
			expect(seen["LuauUI/measure"]).toBe(true)
			expect(seen["LuauUI/arrange"]).toBe(true)
			expect(seen["LuauUI/react"]).toBe(true)
			expect(seen["LuauUI/mutate"]).toBe(true)
			return true
		end)
	end)

	it("the number of scopes a frame opens does NOT scale with the row count", function()
		-- the cardinality rule stated as behaviour rather than as a name check: a
		-- tree with ten times the nodes must not open ten times the scopes, or the
		-- capture is a per-node log wearing a closed set's clothes
		local function opensFor(rows: number): number
			return withRecorder(function(log)
				local core = LuauUI.newCore()
				local env = LuauUI.newEnvironment(core)
				env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
				local adapter = fake_target.new()
				local system = LuauUI.newActionSystem(core)
				local pres = LuauUI.newPresenter(core, env, adapter, system)
				local children = {}
				for i = 1, rows do
					table.insert(children, LuauUI.UI.Text({ id = `T{i}`, text = `row {i}` }))
				end
				pres.present(LuauUI.UI.Screen({ id = "S", children = children }))
				pres.refresh()
				local n = 0
				for _, entry in log do
					if string.sub(entry, 1, 1) == "+" then
						n += 1
					end
				end
				return n
			end)
		end
		local small = opensFor(4)
		local large = opensFor(40)
		expect(large).toBe(small)
	end)
end)
