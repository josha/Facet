--!strict

local Verify = require("../../tools/vendor/verify/src/core")
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
