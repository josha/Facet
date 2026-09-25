--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")

local function scene(options: { lazy: boolean?, count: number? }?): any
	local o = options or {}
	local log = { builds = 0, writes = 0, lives = {} :: { any } }
	local w = overlay.new(function(UI, Host)
		local stages = {}
		for index = 1, o.count or 1 do
			table.insert(
				stages,
				UI.Stage({
					Name = "Stage" .. index,
					lazy = o.lazy,
					content = function(runtime, world, live)
						log.builds += 1
						table.insert(log.lives, live)
						local clock = runtime.timeline({ duration = 4, repeats = math.huge, autoplay = false })
						Compose.watch(function(use)
							if use(live) then
								clock:play()
							else
								clock:pause()
							end
						end)
						local part = Host.Part({
							Name = "Spinner",
							Transparency = function(use)
								return use(clock.progress)
							end,
						})
						part:GetPropertyChangedSignal("Transparency"):Connect(function()
							log.writes += 1
						end)
						part.Parent = world
						return nil
					end,
				})
			)
		end
		return Host.ScrollingFrame({ Name = "Feed", table.unpack(stages) })
	end)
	local V = w.Vector2
	local feed = w.find("Feed")
	feed.AbsolutePosition = V.new(0, 0)
	feed.AbsoluteWindowSize = V.new(400, 300)
	for index = 1, o.count or 1 do
		local stage = w.find("Stage" .. index)
		stage.AbsoluteSize = V.new(200, 100)
		stage.AbsolutePosition = V.new(0, (index - 1) * 110)
	end
	w.log = log
	return w
end

t.describe("native Stage presence", function()
	t.it("reports live on screen, not live while its scroller moves, and live again once it rests", function()
		local w = scene()
		local live = w.log.lives[1]
		t.expect(live:peek()).toBe(true)
		w.find("Feed").CanvasPosition = w.Vector2.new(0, 20)
		t.expect(live:peek()).toBe(false)
		w.advance(0.1, 6)
		t.expect(live:peek()).toBe(false)
		w.advance(0.1, 6)
		t.expect(live:peek()).toBe(true)
		t.expect(w.find("Stage1"):GetAttribute("FacetLive")).toBe(true)
		w.stop()
	end)

	t.it("is not live while less than half of it shows in the scroll window", function()
		local w = scene()
		local stage = w.find("Stage1")
		stage.AbsolutePosition = w.Vector2.new(0, 260)
		t.expect(w.log.lives[1]:peek()).toBe(false)
		stage.AbsolutePosition = w.Vector2.new(0, 220)
		t.expect(w.log.lives[1]:peek()).toBe(true)
		stage.AbsolutePosition = w.Vector2.new(0, 400)
		t.expect(w.log.lives[1]:peek()).toBe(false)
		w.stop()
	end)

	t.it("pauses scene animation while scrolling and off screen, so no frame writes the scene", function()
		local w = scene()
		w.advance(0.5, 30)
		local playing = w.log.writes
		t.expect(playing > 20).toBe(true)
		local feed = w.find("Feed")
		local before = w.log.writes
		for frame = 1, 30 do
			feed.CanvasPosition = w.Vector2.new(0, frame * 4)
			w.advance(1 / 60)
		end
		t.expect(w.log.writes - before <= 1).toBe(true)
		w.advance(0.3, 18)
		local rested = w.log.writes
		t.expect(rested > before + 1).toBe(true)
		w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 500)
		local hidden = w.log.writes
		w.advance(0.5, 30)
		t.expect(w.log.writes - hidden <= 1).toBe(true)
		w.stop()
	end)

	t.it("builds lazy content only once it is live, one stage per frame", function()
		local w = scene({ lazy = true, count = 3 })
		t.expect(w.log.builds).toBe(0)
		t.expect(w.find("Stage1"):GetAttribute("FacetBuilt")).toBe(false)
		w.advance(1 / 60)
		t.expect(w.log.builds).toBe(1)
		w.advance(1 / 60)
		t.expect(w.log.builds).toBe(2)
		w.advance(1 / 60)
		t.expect(w.log.builds).toBe(3)
		t.expect(w.find("Stage3"):GetAttribute("FacetBuilt")).toBe(true)
		w.stop()
	end)

	t.it("builds lazy content that shows while the scroller moves, and keeps its animation paused", function()
		local w = scene({ lazy = true })
		local feed = w.find("Feed")
		for frame = 1, 20 do
			feed.CanvasPosition = w.Vector2.new(0, frame * 3)
			w.advance(1 / 60)
		end
		t.expect(w.log.builds).toBe(1)
		t.expect(w.find("Stage1"):GetAttribute("FacetBuilt")).toBe(true)
		t.expect(w.log.lives[1]:peek()).toBe(false)
		w.advance(0.3, 18)
		t.expect(w.log.builds).toBe(1)
		t.expect(w.log.lives[1]:peek()).toBe(true)
		w.stop()
	end)

	t.it("builds lazy content ahead of the scroll window so a card never scrolls in blank", function()
		local w = scene({ lazy = true })
		w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 360)
		w.advance(1 / 60)
		t.expect(w.log.builds).toBe(1)
		t.expect(w.find("Stage1"):GetAttribute("FacetLive")).toBe(false)
		w.stop()
	end)

	t.it("does not build lazy content that stays out of the scroll window", function()
		local w = scene({ lazy = true })
		w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 500)
		w.advance(0.3, 18)
		t.expect(w.log.builds).toBe(0)
		w.find("Stage1").AbsolutePosition = w.Vector2.new(0, 100)
		w.advance(1 / 60)
		t.expect(w.log.builds).toBe(1)
		w.stop()
	end)

	t.it("drops a queued lazy build when its stage is removed before the frame runs", function()
		local gate = Compose.cell(true)
		local builds = 0
		local w = overlay.new(function(UI, Host)
			return Host.ScrollingFrame({
				Name = "Feed",
				Compose.show(gate, function()
					local stages = {}
					for index = 1, 3 do
						table.insert(
							stages,
							UI.Stage({
								Name = "Stage" .. index,
								lazy = true,
								content = function()
									builds += 1
									return nil
								end,
							})
						)
					end
					return Host.Frame({ Name = "Cards", table.unpack(stages) })
				end),
			})
		end)
		local V = w.Vector2
		local feed = w.find("Feed")
		feed.AbsolutePosition = V.new(0, 0)
		feed.AbsoluteWindowSize = V.new(400, 300)
		for index = 1, 3 do
			local stage = w.find("Stage" .. index)
			stage.AbsoluteSize = V.new(200, 100)
			stage.AbsolutePosition = V.new(0, (index - 1) * 110)
		end
		gate:set(false)
		local ok, problem = pcall(function()
			w.advance(1 / 60, 4)
		end)
		t.expect(problem).toBe(nil)
		t.expect(ok).toBe(true)
		t.expect(builds).toBe(0)
		w.stop()
	end)

	t.it("builds eager content at once and keeps it through scrolling", function()
		local w = scene({ count = 2 })
		t.expect(w.log.builds).toBe(2)
		w.find("Feed").CanvasPosition = w.Vector2.new(0, 30)
		w.advance(0.5, 30)
		t.expect(w.log.builds).toBe(2)
		w.stop()
	end)
end)

return nil
