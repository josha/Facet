--!strict
local Verify = require("@verify/src/core")
local Lute = require("@verify/src/lute")

type Root = { dispose: () -> () }
type Compose = { createRootOwner: (() -> ()) -> Root }
type Context = { afterLayout: (() -> ()) -> () -> () }
type Install = ({ [string]: unknown }, { [string]: unknown }, { [string]: unknown }) -> ()

return function(harness: Verify.Harness)
	harness:case("disposing queued layout work stops its frame subscription", function()
		local loader = Lute.loader.new({ globals = { game = { Name = "Game" } } })
		local Compose = loader.require("src/vendor/compose/core") :: Compose
		local install = loader.require("src/ui/context_observe.luau") :: Install
		local subscribed = 0
		local ran = 0
		local frames = {
			onFrame = function(_step: () -> ()): () -> ()
				subscribed += 1
				local stopped = false
				return function()
					if not stopped then
						stopped = true
						subscribed -= 1
					end
				end
			end,
		}
		local ctx: { [string]: unknown } = {
			Compose = Compose,
			runtime = { host = { frames = frames } },
			types = { Enum = {} },
			config = {},
		}
		install(ctx, {}, { RunService = {} })
		local layout = ctx :: Context
		local schedule: () -> () = function() end
		local root = Compose.createRootOwner(function()
			schedule = layout.afterLayout(function()
				ran += 1
			end)
		end)
		schedule()
		Verify.expect(subscribed):toBe(1)
		root.dispose()
		Verify.expect(subscribed):toBe(0)
		Verify.expect(ran):toBe(0)
	end)
end
