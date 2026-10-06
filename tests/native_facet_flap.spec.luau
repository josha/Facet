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

		verifyHarness:case("collides with ceiling, ground and solid pipes without tunneling", {
			id = "native_facet_flap::native facet flap::collides with ceiling, ground and solid pipes without tunneling",
			run = function()
				for _, setup in
					{
						{ x = 0, y = 13, velocity = -310 },
						{ x = 0, y = 370, velocity = 900 },
						{ x = 395, y = 40, velocity = 0 },
					}
				do
					local game = flap.new(Compose)
					game.state:set({
						phase = "playing" :: "playing",
						x = setup.x,
						y = setup.y,
						velocity = setup.velocity,
						score = 0,
					})
					game.step(10)
					Verify.expect(game.state:peek().phase):toBe("over")
					local ended = game.state:peek()
					game.step(1)
					Verify.expect((game.state:peek())):toBe(ended)
					game.flap()
					Verify.expect(game.state:peek().phase):toBe("playing")
					Verify.expect(game.state:peek().x):toBe(0)
				end
			end,
		})

		verifyHarness:case("scores cleared pipes once, keeps best on retry and leaves gaps empty", {
			id = "native_facet_flap::native facet flap::scores cleared pipes once, keeps best on retry and leaves gaps empty",
			run = function()
				local game = flap.new(Compose)
				Verify.expect((flap.tileAt(18, 3))):toBe(nil)
				Verify.expect((flap.tileAt(18, 2))):toBe("cap")
				Verify.expect((flap.tileAt(18, 8))):toBe("cap")
				game.state:set({ phase = "playing" :: "playing", x = 491, y = 176, velocity = 0, score = 0 })
				game.step(0.01)
				Verify.expect(game.state:peek().phase):toBe("playing")
				Verify.expect(game.state:peek().score):toBe(1)
				game.step(0.01)
				Verify.expect(game.state:peek().score):toBe(1)
				Verify.expect((game.best:peek())):toBe(1)
				game.state:set({ phase = "over" :: "over", x = 500, y = 380, velocity = 0, score = 1 })
				game.flap()
				Verify.expect(game.state:peek().score):toBe(0)
				Verify.expect((game.best:peek())):toBe(1)
			end,
		})

		verifyHarness:case("is independent of frame subdivision and rejects invalid elapsed time", {
			id = "native_facet_flap::native facet flap::is independent of frame subdivision and rejects invalid elapsed time",
			run = function()
				local first, second = flap.new(Compose), flap.new(Compose)
				first.flap()
				second.flap()
				first.step(0.1)
				for _ = 1, 10 do
					second.step(0.01)
				end
				Verify.expect(math.abs(first.state:peek().y - second.state:peek().y) < 0.001):toBe(true)
				local state = first.state:peek()
				first.step(0 / 0)
				first.step(-1)
				Verify.expect((first.state:peek())):toBe(state)
			end,
		})
	end)

	return nil
end
