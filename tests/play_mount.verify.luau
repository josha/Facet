--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Mount = require("../tools/play/engine/mount")
local Play = require("../tools/play/host/play")

local function hud(): Mount.Snapshot
	return {
		root = { parent = "screen", path = "HUD", x = 0, y = 0, width = 400, height = 100 },
		fill = { parent = "root", path = "HUD.Fill", x = 0, y = 40, width = 10, height = 10 },
		text = { parent = "root", path = "HUD.Timer", x = 0, y = 0, width = 80, height = 20, text = "10" },
		neighbour = { parent = "root", path = "HUD.Shop", x = 80, y = 0, width = 80, height = 20, text = "Shop" },
	}
end

return function(harness: Verify.Harness)
	harness:case("a settle timeout cannot become a valid overhead score", function(t)
		local scores: { [string]: number } = {}
		local failedMount: { [string]: unknown } = {}
		failedMount.timedOut = true
		local completeMount: { [string]: unknown } = {}
		completeMount.timedOut = false
		local perf: { [string]: Play.DevicePerf } = {}
		perf.desktop = { screens = {} }
		perf.desktop.mountSeconds = 22
		perf.desktop.mount = failedMount
		perf["phone-portrait"] = { screens = {} }
		perf["phone-portrait"].mountSeconds = 3
		perf["phone-portrait"].mount = completeMount
		Play.perfScores(perf, scores)
		t:expect(scores["perf.desktop.mountSeconds"]):toBe(nil)
		t:expect(scores["perf.desktop.mountTimedOut"]):toBe(1)
		t:expect(scores["perf.phone-portrait.mountSeconds"]):toBe(3)
		t:expect(scores["perf.phone-portrait.mountTimedOut"]):toBe(0)
	end)
	harness:case("stable run restarts on structure and neighbour movement", function(t)
		local run = Mount.start(hud(), 0)
		Mount.step(run, hud(), 0.8, 1)
		t:expect(run.seconds):toBe(nil)
		local inserted = hud()
		inserted.corner = { parent = "fill", path = "HUD.Fill.Corner" }
		Mount.step(run, inserted, 0.9, 1)
		Mount.step(run, inserted, 1.8, 1)
		t:expect(run.seconds):toBe(nil)
		Mount.step(run, inserted, 2, 1)
		t:expect(run.seconds):toBe(0.9)
		local moving = Mount.start(hud(), 0)
		for frame = 1, 100 do
			local snapshot = hud()
			snapshot.text.text = tostring(frame)
			snapshot.text.width = 80 + frame
			snapshot.neighbour.x = 80 + frame
			Mount.step(moving, snapshot, frame / 10, 1)
			t:expect(moving.seconds):toBe(nil)
		end
	end)
	harness:case("live text and fill complete the same quiet run as a static HUD", function(t)
		for _, live in { false, true } do
			local run = Mount.start(hud(), 0)
			for frame = 1, 11 do
				local snapshot = hud()
				if live then
					snapshot.text.text = tostring(frame)
					snapshot.fill.width = 10 + frame
				end
				Mount.step(run, snapshot, frame / 10, 1)
			end
			t:expect(run.seconds):toBe(0)
		end
	end)
	harness:case("static HUD keeps a stable run", function(t)
		local changed, live = Mount.compare(hud(), hud())
		t:expect(changed):toBe(false)
		t:expect(#live):toBe(0)
	end)
	harness:case("growing progress fill does not restart a stable run", function(t)
		local before = hud()
		for width = 11, 100 do
			local after = hud()
			after.fill.width = width
			local changed, live = Mount.compare(before, after)
			t:expect(changed):toBe(false)
			t:expect(live[1].path):toBe("HUD.Fill")
			before = after
		end
	end)
	harness:case("ticking countdown excludes its text and own one-axis content sizing", function(t)
		local before, after = hud(), hud()
		after.text.text, after.text.width = "9", 70
		local changed, live = Mount.compare(before, after)
		t:expect(changed):toBe(false)
		t:expect(live[1].reason):toBe("text changed this frame")
		before = after
		after = hud()
		after.text.text, after.text.width = "9", 72
		t:expect((Mount.compare(before, after))):toBe(false)
		after.text.x = 1
		t:expect((Mount.compare(before, after))):toBe(true)
	end)
	harness:case("live counter moving a neighbour restarts the run", function(t)
		local before, after = hud(), hud()
		after.text.text, after.text.width, after.neighbour.x = "100", 100, 100
		local changed, live = Mount.compare(before, after)
		t:expect(changed):toBe(true)
		t:expect(#live):toBe(1)
	end)
	harness:case("structure additions removals replacements and reparenting restart", function(t)
		for _, mode in { "add", "remove", "replace", "reparent" } do
			local before, after = hud(), hud()
			if mode == "add" then
				after.corner = { parent = "fill", path = "HUD.Fill.Corner" }
			elseif mode == "remove" or mode == "replace" then
				local without: Mount.Snapshot = {}
				for key, node in after do
					if key ~= "fill" then
						without[key] = node
					end
				end
				if mode == "replace" then
					without.replacement = after.fill
				end
				after = without
			else
				after.fill.parent = "neighbour"
			end
			t:expect((Mount.compare(before, after))):toBe(true)
		end
	end)
	harness:case("parent reflow position motion and two-axis sizing still count", function(t)
		for _, mode in { "parent", "position", "both" } do
			local before, after = hud(), hud()
			if mode == "parent" then
				after.root.width = 410
			elseif mode == "position" then
				after.fill.x = 1
			else
				after.fill.width, after.fill.height = 11, 11
			end
			t:expect((Mount.compare(before, after))):toBe(true)
		end
		t:expect((Mount.compare({}, {}))):toBe(true)
	end)
end
