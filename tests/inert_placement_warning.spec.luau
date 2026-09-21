--!strict
--[[ AN INERT PLACEMENT PROP IS SAID OUT LOUD, ONCE.

	`placement_audit` has detected these since it was written and
	`controller.diagnostics()` has carried them ever since — and round 1 of this
	polish pass still found seven shipped instances, because a diagnostic nobody
	calls is a diagnostic nobody reads. What is held here is the announcement, and
	the three properties that make it usable rather than noise: it is OFF unless a
	host turns it on, it fires once per site however many times the tree re-solves,
	and a clean tree says nothing at all. ]]
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local warnings = require("../src/layout/placement_warnings")
local UI = harness.UI

-- capture the sentences instead of printing them through the suite (the seam
-- `solve_queue.report` has, for the same reason)
local function capture()
	local said: { string } = {}
	local realReport = warnings.report
	warnings.reset()
	warnings.setEnabled(true)
	warnings.report = function(message: string)
		table.insert(said, message)
	end
	return said, function()
		warnings.report = realReport
		warnings.reset()
	end
end

-- `alignH` is a ZStack parent's word; under an HStack it is accepted and ignored
local function inertTree()
	return UI.Screen({
		id = "S",
		children = {
			UI.HStack({
				id = "Row",
				width = UI.fill(),
				children = {
					UI.Box({
						id = "Marooned",
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 20 },
						alignH = "center",
					}),
				},
			}),
		},
	})
end

t.describe("inert placement props announce themselves", function()
	t.it("warns once per site, naming the node, the parent and the working spelling", function()
		local said, restore = capture()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 300 } })
		w.present(inertTree())
		w.settle(6)
		t.expect(`warnings: {#said}`).toBe("warnings: 1")
		local message = said[1]
		for _, fragment in { "Marooned", "Row", "alignH", "lineAlign" } do
			t.expect(`names {fragment}: {string.find(message, fragment, 1, true) ~= nil}`)
				.toBe(`names {fragment}: true`)
		end
		-- ...and re-solving does not say it again. Layout re-solves whenever
		-- anything moves, so a per-frame repeat is how a real warning gets missed.
		w.settle(30)
		w.env:set("viewportRect", { x = 0, y = 0, w = 360, h = 300 })
		w.settle(30)
		t.expect(`still: {#said}`).toBe("still: 1")
		w.pres.dismiss(w.handle)
		restore()
	end)

	t.it("says nothing at all when the tree is clean", function()
		local said, restore = capture()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 300 } })
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					width = UI.fill(),
					children = {
						UI.Box({
							id = "Fine",
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 20 },
							lineAlign = "center",
						}),
					},
				}),
			},
		}))
		w.settle(10)
		t.expect(`warnings: {#said}`).toBe("warnings: 0")
		w.pres.dismiss(w.handle)
		restore()
	end)

	t.it("is silent until a host enables it — a shipped game spends nothing", function()
		local said: { string } = {}
		local realReport = warnings.report
		warnings.reset() -- reset() also clears the switch: this is the default state
		warnings.report = function(message: string)
			table.insert(said, message)
		end
		t.expect(warnings.isEnabled()).toBe(false)
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 300 } })
		w.present(inertTree())
		w.settle(10)
		-- the finding is still FILED — the diagnostic surface is unchanged — and
		-- only the announcement is gated
		local filed = false
		for _, finding in w.controller.diagnostics() do
			if string.find(tostring(finding.issue), "placement prop this parent never reads", 1, true) then
				filed = true
			end
		end
		t.expect(`filed: {filed}, said: {#said}`).toBe("filed: true, said: 0")
		w.pres.dismiss(w.handle)
		warnings.report = realReport
		warnings.reset()
	end)
end)
