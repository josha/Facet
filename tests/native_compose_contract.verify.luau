--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	verifyHarness:suite("native Compose integration contract", function()
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
	end)
end
