--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	verifyHarness:suite("native Compose integration contract", function()
		verifyHarness:case("keeps diamonds glitch free and batches one delivery through mounted control bindings", {
			id = "native_compose_contract::native Compose integration contract::keeps diamonds glitch free and batches one delivery through mounted control bindings",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(runtime, { types = engine.types })
				local value, observations = Compose.cell(1), {}
				local stop, node: any = runtime.mount(function()
					local left = Compose.formula(function(use: Use)
						return use(value) + 1
					end)
					local right = Compose.formula(function(use: Use)
						return use(value) * 10
					end)
					local joined = Compose.formula(function(use: Use)
						return { left = use(left), right = use(right) }
					end)
					Compose.watch(function(use: Use)
						local result = use(joined)
						assert((result.left - 1) * 10 == result.right, "diamond exposed a partial update")
						table.insert(observations, result)
					end)
					return UI.Text({
						text = function(use: Use)
							return tostring(use(joined).right)
						end,
					})
				end, engine.new("ScreenGui"))
				for iteration = 1, 400 do
					local prior = #observations
					runtime:batch(function()
						for write = 1, 20 do
							value:set(iteration * 20 + write)
						end
					end)
					assert(#observations == prior + 1, `batch {iteration} delivered more than once`)
					assert(node.Text == tostring((iteration * 20 + 20) * 10))
				end
				stop()
				local prior = #observations
				value:set(0)
				assert(#observations == prior, "disposed binding remained subscribed")
				runtime:dispose()
			end,
		})

		verifyHarness:case("does not recompute equal writes and shares a formula across independent readers", {
			id = "native_compose_contract::native Compose integration contract::does not recompute equal writes and shares a formula across independent readers",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local value, runs, deliveries = Compose.cell(7), 0, 0
				local stop = runtime.mount(function()
					local shared = Compose.formula(function(use: Use)
						runs += 1
						return use(value) * 2
					end)
					for _ = 1, 3 do
						Compose.watch(function(use: Use)
							use(shared)
							deliveries += 1
						end)
					end
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
				end, engine.new("ScreenGui"))
				local initialRuns, initialDeliveries = runs, deliveries
				value:set(7)
				assert(runs == initialRuns and deliveries == initialDeliveries, "equal write propagated")
				value:set(8)
				assert(
					runs == initialRuns + 1 and deliveries == initialDeliveries + 3,
					"shared formula recomputed per reader"
				)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("disposes child watches with their parent and tolerates repeated disposal", {
			id = "native_compose_contract::native Compose integration contract::disposes child watches with their parent and tolerates repeated disposal",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local source, calls, cleanups = Compose.cell(0), 0, 0
				local child, unwatch
				local stop = runtime.mount(function()
					child = assert(Compose.currentOwner()).createChild()
					unwatch = child.watch(function(use: Use)
						use(source)
						calls += 1
					end)
					Compose.withOwner(child, function()
						Compose.cleanup(function()
							cleanups += 1
						end)
					end)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
				end, engine.new("ScreenGui"))
				source:set(1)
				assert(calls == 2)
				stop()
				stop()
				unwatch()
				unwatch()
				child.dispose()
				assert(child.isDisposed() and cleanups == 1, "cleanup was skipped or repeated")
				source:set(2)
				assert(calls == 2, "child watch survived parent")
				runtime:dispose()
			end,
		})

		verifyHarness:case("recovers a failed formula after its newly reached dependency changes", {
			id = "native_compose_contract::native Compose integration contract::recovers a failed formula after its newly reached dependency changes",
			run = function()
				local choose, first, second = Compose.cell(false), Compose.cell(1), Compose.cell(10)
				local broken = false
				local formula = Compose.formula(function(use: Use)
					local value = use(if use(choose) then second else first)
					if broken then
						error("injected formula failure")
					end
					return value
				end)
				assert(formula:peek() == 1)
				broken = true
				choose:set(true)
				assert(not pcall(function()
					formula:peek()
				end), "failure was hidden")
				broken = false
				second:set(20)
				assert(formula:peek() == 20, "failed read detached its new dependencies")
				formula:dispose()
			end,
		})
	end)
end
