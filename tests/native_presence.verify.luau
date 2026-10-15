--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	local function dialog(shown: any, options: any?, unsized: boolean?): any
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			return UI.Dialog "D" {
				isPresented = shown,
				onPresentedChange = function(value: boolean)
					shown:set(value)
				end,
				title = "Quit race?",
				content = function(): Instance
					return Host.TextLabel "Body" { Text = "Progress is lost." }
				end,
			}
		end, options)
		local panel = w.find("Panel")
		if panel and not unsized then
			panel.AbsoluteSize = w.Vector2.new(560, 441)
		end
		return w
	end

	verifyHarness:suite("presence: opacity leads travel", function()
		verifyHarness:case(
			"a stationary dialog is opaque at 60 percent of its entrance and clear at half of its exit",
			{
				id = "native_presence::presence: opacity leads travel::a stationary dialog is opaque at 60 percent of its entrance and clear at half of its exit",
				run = function()
					local shown = Compose.cell(true)
					local w = dialog(shown)
					local panel = w.find("Panel")
					local scale = materialize.of(panel)
					local sawOpaqueEarly = false
					for _ = 1, 30 do
						w.advance(1 / 60)
						if fadeKit.of(panel) == 0 and scale.Scale == 1 then
							sawOpaqueEarly = true
						end
					end
					Verify.expect(sawOpaqueEarly):toBe(true)
					shown:set(false)
					local sawClearEarly = false
					for _ = 1, 30 do
						w.advance(1 / 60)
						if panel.Parent and fadeKit.of(panel) == 1 and scale.Scale > 0.94 then
							sawClearEarly = true
						end
					end
					Verify.expect(sawClearEarly):toBe(true)
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("presence: the fades take their share of the time, not of the eased travel", function()
		verifyHarness:case("a dialog fades in over several frames without changing its content scale", {
			id = "native_presence::presence: the fades take their share of the time, not of the eased travel::a dialog fades in over several frames without changing its content scale",
			run = function()
				local shown = Compose.cell(true)
				local w = dialog(shown)
				local panel = w.find("Panel")
				local scale = materialize.of(panel)
				local partial, elapsed = 0, 0
				while fadeKit.of(panel) > 0 and elapsed < 1 do
					w.advance(1 / 120)
					elapsed += 1 / 120
					if fadeKit.of(panel) > 0 and fadeKit.of(panel) < 1 then
						partial += 1
					end
				end
				Verify.expect(partial >= 10):toBe(true)
				Verify.expect(scale.Scale):toBe(1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("presence: motion level limited cross-fades", function()
		verifyHarness:case("under limited a sheet never slides and its panel fades in over motion.reducedFade", {
			id = "native_presence::presence: motion level limited cross-fades::under limited a sheet never slides and its panel fades in over motion.reducedFade",
			run = function()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet "S" {
						isPresented = shown,
						detent = Compose.cell("medium"),
						title = "Race details",
						content = function(): Instance
							return Host.TextLabel "Copy" { Text = "Lap times" }
						end,
					}
				end, { motionLevel = "limited" })
				w.find("Modal").AbsoluteSize = w.Vector2.new(800, 600)
				local panel = w.find("SheetPanel")
				local at = nil
				local sawFading = false
				for _ = 1, 12 do
					w.advance(1 / 60)
					local fade = fadeKit.of(panel)
					if fade < 1 then
						at = at or panel.Position
						Verify.expect(panel.Position):toBe(at)
					end
					sawFading = sawFading or (fade > 0 and fade < 1)
				end
				Verify.expect(at and at.Y.Offset):toBe(0)
				Verify.expect(sawFading):toBe(true)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("presence: limited cross-fades the toast, tabs, stack and disclosure", function()
		local LIMITED = { motionLevel = "limited" }

		local function fadesOver(w: any, node: any, from: number, to: number): number
			local frames = 0
			while fadeKit.of(node) ~= to and frames < 30 do
				w.advance(1 / 60)
				frames += 1
				local value = fadeKit.of(node)
				Verify.expect(if from > to then value <= from else value >= from):toBe(true)
			end
			Verify.expect((fadeKit.of(node))):toBe(to)
			return frames
		end

		verifyHarness:case("a DisclosureGroup's height lands at once and its content fades over reducedFade", {
			id = "native_presence::presence: limited cross-fades the toast, tabs, stack and disclosure::a DisclosureGroup's height lands at once and its content fades over reducedFade",
			run = function()
				local expanded = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls)
					return UI.DisclosureGroup "Settings" {
						label = "Appearance",
						expanded = expanded,
						content = function(): Instance
							return UI.Button "Palette" { label = "Palette" }
						end,
					}
				end, LIMITED)
				expanded:set(true)
				local reveal, fade = w.find("Reveal"), w.find("RevealFade")
				fade.AbsoluteSize = w.Vector2.new(300, 120)
				w.advance(1 / 60)
				Verify.expect(reveal.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				local frames = fadesOver(w, fade, 1, 0)
				Verify.expect(frames >= 5 and frames <= 12):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("presence: a Dialog is measured at rest", function()
		for _, level in { "normal", "none" } do
			verifyHarness:case(`a Dialog waits for its size to hold, then never grows after it shows ({level})`, {
				id = "native_presence::"
					.. "presence: a Dialog is measured at rest"
					.. "::"
					.. `a Dialog waits for its size to hold, then never grows after it shows ({level})`,
				run = function()
					local shown = Compose.cell(true)
					local w = dialog(shown, { motionLevel = level }, true)
					local panel = w.find("Panel")
					local scale = materialize.of(panel)
					panel.AbsoluteSize = w.Vector2.new(560, 420)
					w.advance(1 / 60)
					Verify.expect((fadeKit.of(panel))):toBe(1)
					Verify.expect(scale.Scale):toBe(1)
					panel.AbsoluteSize = w.Vector2.new(560, 441)
					w.advance(1 / 60)
					Verify.expect((fadeKit.of(panel))):toBe(1)
					local seen = false
					for _ = 1, 30 do
						w.advance(1 / 60)
						if fadeKit.of(panel) < 1 then
							seen = true
							if scale.Scale < 1 then
								Verify.expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
								Verify.expect(panel.Size.Y.Offset):toBe(441)
								Verify.expect(w.find("PresentationPaint").Size.Y.Offset):toBe(441)
								Verify.expect(w.find("PresentationScale").Scale):toBe(scale.Scale)
							end
						end
					end
					Verify.expect(seen):toBe(true)
					Verify.expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
					w.stop()
				end,
			})
		end
	end)
end
