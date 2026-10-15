--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Audit = require("../../tools/vendor/verify/src/roblox/ui-audit")
local Rules = require("../../eval/tasks/racing-hub/starter/src/shared/RaceRules")
local RaceSpace = require("../../eval/tasks/racing-hub/hidden/race-space")
local Scenarios = {
	require("../../eval/tasks/hub-livery-editor/hidden/scenario"),
	require("../../eval/tasks/hub-track-vote/hidden/scenario"),
	require("../../eval/tasks/hub-quick-chat/hidden/scenario"),
	require("../../eval/tasks/hub-upgrades/hidden/scenario"),
	require("../../eval/tasks/hub-party-invite/hidden/scenario"),
	require("../../eval/tasks/hub-first-time-tutorial/hidden/scenario"),
}
local Added = {
	{ "livery-preview-save", "livery-discard-cancel" },
	{ "track-vote-change-live", "track-vote-lock-winner" },
	{ "quick-chat-open-send", "quick-chat-cooldown" },
	{ "upgrades-insufficient", "upgrades-confirm-cancel-purchase" },
	{ "party-search-clear", "party-invite-outcomes" },
	{ "tutorial-dock", "tutorial-shop-back", "tutorial-queue-skip" },
}

return function(harness: Verify.Harness)
	harness:case("race progress requires ordered checkpoints and a forward finish crossing", function(t)
		local racer = { checkpoint = 0, lap = 0, progress = 0 }
		t:expect(Rules.advance(racer, 0.8, true, 16)):toBe(false)
		t:expect(racer.checkpoint):toBe(0)
		t:expect(Rules.advance(racer, 1 / 16, false, 16)):toBe(false)
		t:expect(racer.checkpoint):toBe(0)
		for lap = 1, 3 do
			for checkpoint = 1, 15 do
				t:expect(Rules.advance(racer, checkpoint / 16 + 0.001, true, 16)):toBe(false)
			end
			t:expect(Rules.advance(racer, 0.001, true, 16)):toBe(true)
			t:expect(racer.lap):toBe(lap)
			t:expect(Rules.advance(racer, 0, true, 16)):toBe(false)
		end
	end)
	harness:case("race standings prefer finish order then checkpoint progress and put OUT last", function(t)
		local first = { name = "First", progress = 3, finish = 1, out = false }
		local second = { name = "Second", progress = 3.1, finish = 2, out = false }
		local behind = { name = "Behind", progress = 2.9, finish = math.huge, out = false }
		local out = { name = "Out", progress = 3.2, finish = math.huge, out = true }
		local order = { out, behind, second, first }
		table.sort(order, Rules.ahead)
		t:expect(order[1].name):toBe("First")
		t:expect(order[2].name):toBe("Second")
		t:expect(order[3].name):toBe("Behind")
		t:expect(order[4].name):toBe("Out")
	end)
	harness:case("race safety geometry accepts edge HUDs and rejects center paint and thumbstick actions", function(t)
		local dump: Audit.Dump = {
			schemaVersion = 1,
			screen = {
				width = 390,
				height = 844,
				scale = 1,
				guiInset = { left = 0, top = 0, right = 0, bottom = 0 },
				input = { "touch" },
			},
			roots = {},
			elements = {},
			instances = 1,
			truncated = false,
		}
		local element: Audit.Element = {
			index = 1,
			root = 1,
			class = "TextLabel",
			path = "HUD",
			rect = { x = 140, y = 10, width = 100, height = 40 },
			rotation = 0,
			visible = true,
			zIndex = 1,
			order = 1,
			interactive = false,
			selectable = false,
			active = false,
			interactable = true,
			next = {},
			selectionGroup = false,
			stops = {},
			background = { color = { r = 0, g = 0, b = 0 }, transparency = 0 },
		}
		dump.elements[1] = element
		t:expect(RaceSpace.centerClear(dump)):toBe(true)
		element.rect.y = 410
		t:expect(RaceSpace.centerClear(dump)):toBe(false)
		element.rect = { x = 20, y = 650, width = 100, height = 44 }
		t:expect(RaceSpace.thumbstickClear(dump)):toBe(true)
		element.interactive = true
		t:expect(RaceSpace.thumbstickClear(dump)):toBe(false)
		element.interactive = false
		element.active = true
		t:expect(RaceSpace.thumbstickClear(dump)):toBe(false)
		element.scrollClip = { x = 200, y = 650, width = 100, height = 44 }
		t:expect(RaceSpace.thumbstickClear(dump)):toBe(true)
		element.scrollClip = nil
		element.visible = false
		t:expect(RaceSpace.thumbstickClear(dump)):toBe(true)
	end)
	harness:case("each extended turn retains earlier player cases on all five devices", function(t)
		local previous: { [string]: { [string]: boolean } } = {}
		for index, scenario in Scenarios do
			t:expect(#scenario.sessions):toBe(5)
			for _, session in scenario.sessions do
				local seen: { [string]: boolean } = {}
				for _, case in session.cases do
					t:expect(seen[case.id] == nil):toBeTrueWith("case runs once: " .. case.id)
					seen[case.id] = true
				end
				local inherited: { [string]: boolean } = previous[session.device] or {}
				for id in inherited do
					t:expect(seen[id]):toBe(true)
				end
				for _, id in Added[index] do
					t:expect(seen[id]):toBe(true)
				end
				for _, id in { "categories", "garage-search", "settings-reset-save", "race-scoreboard" } do
					t:expect(seen[id]):toBe(true)
				end
				previous[session.device] = seen
			end
		end
	end)
end
