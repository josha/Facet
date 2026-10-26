--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Effects = require("../src/ui/effect_types")
local Shared = require("../src/ui/types")
local Engine = require("../src/ui/engine_types")
local overlay = require("./lib/overlay_world")

local function session(intensity: number?, config: Shared.Config?)
	local C = Facet.Compose
	local initial: { GuiObject } = {}
	local targets = C.cell(initial)
	local effect: Effects.Sequence
	local first: GuiObject
	local second: GuiObject
	local world = overlay.new(function(UI, Host)
		first = Host.Frame { Name = "First", Rotation = 13 }
		second = Host.Frame { Name = "Second", Rotation = -7 }
		targets:set({ first, second, first })
		effect = UI.shake(targets, { intensity = intensity })
		local props: Engine.FrameNativeProps = { first, second }
		return Host.Frame(props)
	end, config)
	return {
		first = first,
		second = second,
		effect = effect,
		targets = targets,
		step = world.advance,
		dispose = world.stop,
		engine = world.engine,
		gui = world.gui,
	}
end

return function(harness: Verify.Harness)
	harness:case("shake restores transforms after completion and moves targets together", function(t)
		local s = session()
		t:defer(s.dispose)
		local position, size = s.first.Position, s.first.Size
		s.effect.play()
		s.step(0.025)
		t:expect(math.abs(s.first.Rotation - 13) > 0.1):toBe(true)
		t:expect(math.abs((s.first.Rotation - 13) - (s.second.Rotation + 7)) < 0.00001):toBe(true)
		t:expect(s.first.Position):toBe(position)
		t:expect(s.first.Size):toBe(size)
		s.step(1)
		t:expect(s.first.Rotation):toBe(13)
		t:expect(s.second.Rotation):toBe(-7)
		t:expect(s.effect.completed:peek()):toBe(true)
	end)
	harness:case("shake cancel restores transforms mid-shake and stops later writes", function(t)
		local s = session()
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.025)
		s.effect.cancel()
		t:expect(s.first.Rotation):toBe(13)
		t:expect(s.second.Rotation):toBe(-7)
		t:expect(s.effect.running:peek()):toBe(false)
		s.first.Rotation = 20
		s.step(1)
		t:expect(s.first.Rotation):toBe(20)
	end)
	harness:case("shake owner cleanup restores external targets and disables replay", function(t)
		local s = session()
		t:defer(s.dispose)
		local first: GuiObject = s.engine.new("Frame")
		t:defer(function()
			first:Destroy()
		end)
		first.Rotation = 21
		s.targets:set({ first })
		s.effect.play()
		s.step(0.025)
		t:expect(first.Rotation ~= 21):toBe(true)
		s.dispose()
		t:expect(first.Rotation):toBe(21)
		s.effect.play()
		t:expect(first.Rotation):toBe(21)
	end)
	harness:case("shake retrigger restores before it captures and restarts the phase", function(t)
		local s = session()
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.025)
		local rotation = s.first.Rotation
		s.effect.play()
		t:expect(s.first.Rotation):toBe(13)
		s.step(0.025)
		t:expect(math.abs(s.first.Rotation - rotation) < 0.00001):toBe(true)
		s.effect.finish()
		t:expect(s.first.Rotation):toBe(13)
		t:expect(s.effect.completed:peek()):toBe(true)
		s.first.Rotation = 30
		s.effect.play()
		s.effect.cancel()
		t:expect(s.first.Rotation):toBe(30)
	end)
	harness:case("shake restores the old targets when its readable changes", function(t)
		local s = session()
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.025)
		s.targets:set({ s.second })
		t:expect(s.first.Rotation):toBe(13)
		t:expect(s.second.Rotation):toBe(-7)
		t:expect(s.effect.running:peek()):toBe(false)
		s.effect.play()
		s.step(0.025)
		t:expect(s.first.Rotation):toBe(13)
		t:expect(s.second.Rotation ~= -7):toBe(true)
	end)
	harness:case("shake limited none and device reduced motion never move targets", function(t)
		local initial: Shared.MotionLevel = "limited"
		local level = Facet.Compose.cell(initial)
		local s = session(nil, { motionLevel = level })
		t:defer(s.dispose)
		local writes = 0
		local connection = s.first:GetPropertyChangedSignal("Rotation"):Connect(function()
			writes += 1
		end)
		t:defer(function()
			connection:Disconnect()
		end)
		local function checkReduced()
			s.effect.play()
			s.step(0.025)
			t:expect(s.first.Rotation):toBe(13)
			t:expect(s.effect.completed:peek()):toBe(true)
		end
		checkReduced()
		level:set("none")
		checkReduced()
		level:set("normal")
		s.engine.environment.poke(s.gui, "ReducedMotionEnabled", true)
		checkReduced()
		t:expect(writes):toBe(0)
	end)
	harness:case("shake restores immediately when motion is reduced during a run", function(t)
		local initial: Shared.MotionLevel = "normal"
		local level = Facet.Compose.cell(initial)
		local s = session(nil, { motionLevel = level })
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.025)
		level:set("none")
		t:expect(s.first.Rotation):toBe(13)
		t:expect(s.effect.completed:peek()):toBe(true)
	end)
	harness:case("shake intensity scales the theme angle", function(t)
		local normal, strong = session(), session(2)
		t:defer(normal.dispose)
		t:defer(strong.dispose)
		normal.effect.play()
		strong.effect.play()
		normal.step(0.025)
		strong.step(0.025)
		t:expect(math.abs((strong.first.Rotation - 13) - 2 * (normal.first.Rotation - 13)) < 0.00001):toBe(true)
	end)
	harness:case("shake target destruction restores surviving targets and cancels samples", function(t)
		local s = session()
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.025)
		s.first:Destroy()
		t:expect(s.second.Rotation):toBe(-7)
		t:expect(s.effect.running:peek()):toBe(false)
		s.step(1)
		t:expect(s.second.Rotation):toBe(-7)
	end)
	harness:case("shake reads duration easing angle and cycles from a validated theme", function(t)
		local definition: Facet.ThemeDefinition = {
			metrics = {
				motion = {
					durations = { shake = 0.6 },
					easing = { shake = "inQuad" },
					distances = { shakeAngle = 12 },
					materialize = { shakeCycles = 1 },
				},
			},
		}
		local package = Facet.themes.define(definition)
		local theme = assert(package)
		local s = session(nil, { theme = theme })
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.15)
		local phase = (0.15 / 0.6) ^ 2
		local expected = 13 + math.sin(phase * 2 * math.pi) * (1 - phase) * 12
		t:expect(math.abs(s.first.Rotation - expected) < 0.00001):toBe(true)
		s.step(0.2)
		t:expect(s.effect.running:peek()):toBe(true)
		s.step(0.3)
		t:expect(s.effect.completed:peek()):toBe(true)
		t:expect(s.first.Rotation):toBe(13)
	end)
	harness:case("shipped themes inherit shake tokens through the schema", function(t)
		local packages: { Facet.ThemePackage } = {
			assert((require("../examples/themes/classic_desktop").build(Facet.themes))),
			assert((require("../examples/themes/glossy_mobile").build(Facet.themes))),
			assert((require("../examples/themes/scifi_hud").build(Facet.themes))),
			assert((require("../examples/themes/fantasy_parchment").build(Facet.themes))),
			assert((require("../examples/themes/fantasy_ornate").build(Facet.themes))),
			assert((require("../examples/themes/pixel_quest").build(Facet.themes))),
			assert((require("../examples/themes/glossy_touch").build(Facet.themes))),
			assert((require("../examples/themes/compact_pointer").build(Facet.themes))),
			assert((require("../examples/facet-lab/themes/foundation").build(Facet.themes))),
		}
		for _, package in packages do
			local motion = package.metrics.motion
			t:expect(assert(motion.durations).shake):toBe(0.3)
			t:expect(assert(motion.easing).shake):toBe("linear")
			t:expect(assert(motion.distances).shakeAngle):toBe(6)
			t:expect(assert(motion.materialize).shakeCycles):toBe(3)
		end
	end)
	harness:case("shake retains its baseline when theme easing crosses the endpoint", function(t)
		local definition: Facet.ThemeDefinition = {
			metrics = { motion = { durations = { shake = 1 }, easing = { shake = "outElastic" } } },
		}
		local candidate = Facet.themes.define(definition)
		local s = session(nil, { theme = assert(candidate) })
		t:defer(s.dispose)
		s.effect.play()
		s.step(0.1)
		t:expect(s.first.Rotation):toBe(13)
		s.step(0.2)
		t:expect(math.abs(s.first.Rotation - 13) > 0.1):toBe(true)
		s.effect.cancel()
		t:expect(s.first.Rotation):toBe(13)
	end)
end
