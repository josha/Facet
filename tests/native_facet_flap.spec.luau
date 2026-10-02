--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local flap = require("../examples/virtual_monitors/flap_model")

t.describe("native facet flap", function()
	t.it("uses deterministic impulses and freezes paused or disposed games", function()
		local game = flap.new(Compose)
		t.expect(game.state:peek().phase).toBe("ready")
		game.flap()
		game.step(0.1)
		local state = game.state:peek()
		t.expect(math.abs(state.x - 15) < 0.001).toBe(true)
		t.expect(math.abs(state.y - 165.75) < 0.001).toBe(true)
		game.pause()
		state = game.state:peek()
		game.step(1)
		t.expect(game.state:peek()).toBe(state)
		game.togglePause()
		t.expect(game.state:peek().phase).toBe("playing")
		game.dispose()
		state = game.state:peek()
		game.flap()
		game.step(1)
		game.togglePause()
		t.expect(game.state:peek()).toBe(state)
	end)

	t.it("collides with ceiling, ground and solid pipes without tunneling", function()
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
			t.expect(game.state:peek().phase).toBe("over")
			local ended = game.state:peek()
			game.step(1)
			t.expect(game.state:peek()).toBe(ended)
			game.flap()
			t.expect(game.state:peek().phase).toBe("playing")
			t.expect(game.state:peek().x).toBe(0)
		end
	end)

	t.it("scores cleared pipes once, keeps best on retry and leaves gaps empty", function()
		local game = flap.new(Compose)
		t.expect(flap.tileAt(18, 3)).toBe(nil)
		t.expect(flap.tileAt(18, 2)).toBe("cap")
		t.expect(flap.tileAt(18, 8)).toBe("cap")
		game.state:set({ phase = "playing" :: "playing", x = 491, y = 176, velocity = 0, score = 0 })
		game.step(0.01)
		t.expect(game.state:peek().phase).toBe("playing")
		t.expect(game.state:peek().score).toBe(1)
		game.step(0.01)
		t.expect(game.state:peek().score).toBe(1)
		t.expect(game.best:peek()).toBe(1)
		game.state:set({ phase = "over" :: "over", x = 500, y = 380, velocity = 0, score = 1 })
		game.flap()
		t.expect(game.state:peek().score).toBe(0)
		t.expect(game.best:peek()).toBe(1)
	end)

	t.it("is independent of frame subdivision and rejects invalid elapsed time", function()
		local first, second = flap.new(Compose), flap.new(Compose)
		first.flap()
		second.flap()
		first.step(0.1)
		for _ = 1, 10 do
			second.step(0.01)
		end
		t.expect(math.abs(first.state:peek().y - second.state:peek().y) < 0.001).toBe(true)
		local state = first.state:peek()
		first.step(0 / 0)
		first.step(-1)
		t.expect(first.state:peek()).toBe(state)
	end)
end)

return t
