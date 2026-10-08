--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FolderConstructor = typeof(require("@repo/tools/typecheck/aliases").FolderConstructor)

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local engineLib = require("./lib/native_engine")

	local function newContext(): (any, () -> ())
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local ctx: any
		local stop = runtime.mount(function()
			ctx = context(Compose, runtime, { types = engine.types, services = {} })
			return ((runtime.constructors.Folder :: unknown) :: FolderConstructor)({})
		end, engine.new("Folder"))
		return ctx, function()
			stop()
			runtime:dispose()
		end
	end

	verifyHarness:suite("motion values live in the theme", function()
		verifyHarness:case(
			"each motion reader returns exactly one value, so a call in last position adds no argument",
			{
				id = "motion_tokens::motion values live in the theme::each motion reader returns exactly one value, so a call in last position adds no argument",
				run = function()
					local ctx, stop = newContext()
					Verify.expect((select("#", ctx.metric("motion.normal")))):toBe(1)
					Verify.expect((select("#", ctx.motionEase("present")))):toBe(1)
					Verify.expect((select("#", ctx.motionStyle("paint")))):toBe(1)
					stop()
				end,
			}
		)
	end)
end
