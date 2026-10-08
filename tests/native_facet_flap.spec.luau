--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Compose = require("../src/vendor/compose/core")
	local flap = require("../examples/virtual_monitors/flap_model")

	verifyHarness:suite("native facet flap", function()
		verifyHarness:case("uses deterministic impulses and freezes paused or disposed games", {
			id = "native_facet_flap::native facet flap::uses deterministic impulses and freezes paused or disposed games",
			run = function()
				local game = flap.new(Compose)
				Verify.expect(game.state:peek().phase):toBe("ready")
				game.flap()
				game.step(0.1)
				local state = game.state:peek()
				Verify.expect(math.abs(state.x - 15) < 0.001):toBe(true)
				Verify.expect(math.abs(state.y - 165.75) < 0.001):toBe(true)
				game.pause()
				state = game.state:peek()
				game.step(1)
				Verify.expect((game.state:peek())):toBe(state)
				game.togglePause()
				Verify.expect(game.state:peek().phase):toBe("playing")
				game.dispose()
				state = game.state:peek()
				game.flap()
				game.step(1)
				game.togglePause()
				Verify.expect((game.state:peek())):toBe(state)
			end,
		})
	end)

	return nil
end
