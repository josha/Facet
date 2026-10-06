--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	local function levelWorld(options: any?): (any, any)
		local env: any = nil
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			env = UI.environment()
			return Host.Frame "Screen" {}
		end, options)
		return w, env
	end

	local function alertWorld(options: any?): (any, any)
		local shown = Compose.cell(false)
		local w = overlay.new(function(UI: FacetControls)
			return UI.Alert {
				isPresented = shown,
				title = "Leave?",
				actions = {
					{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
				},
			}
		end, options)
		return w, shown
	end

	verifyHarness:suite("motion levels", function()
		verifyHarness:case("follows the device: normal, and limited under the engine's Reduce Motion", {
			id = "native_motion_level::motion levels::follows the device: normal, and limited under the engine's Reduce Motion",
			run = function()
				local w, env = levelWorld()
				Verify.expect((env.motionLevel:peek())):toBe("normal")
				Verify.expect((env.reducedMotion:peek())):toBe(false)
				w.gui.ReducedMotionEnabled = true
				Verify.expect((env.motionLevel:peek())):toBe("limited")
				Verify.expect((env.reducedMotion:peek())):toBe(true)
				w.gui.ReducedMotionEnabled = false
				Verify.expect((env.motionLevel:peek())):toBe("normal")
				w.stop()
			end,
		})

		verifyHarness:case(
			"the stronger of the game's level and the device's wins; a game adds reduction, never removes it",
			{
				id = "native_motion_level::motion levels::the stronger of the game's level and the device's wins; a game adds reduction, never removes it",
				run = function()
					local w, env = levelWorld({ motionLevel = "none" })
					Verify.expect((env.motionLevel:peek())):toBe("none")
					w.gui.ReducedMotionEnabled = true
					Verify.expect((env.motionLevel:peek())):toBe("none")
					w.stop()
					local chosen = Compose.cell("normal")
					local w2, env2 = levelWorld({ motionLevel = chosen })
					Verify.expect((env2.motionLevel:peek())):toBe("normal")
					w2.gui.ReducedMotionEnabled = true
					Verify.expect((env2.motionLevel:peek())):toBe("limited")
					Verify.expect((env2.reducedMotion:peek())):toBe(true)
					chosen:set("none")
					Verify.expect((env2.motionLevel:peek())):toBe("none")
					w2.gui.ReducedMotionEnabled = false
					chosen:set("limited")
					Verify.expect((env2.motionLevel:peek())):toBe("limited")
					w2.stop()
				end,
			}
		)

		verifyHarness:case("a live unknown level falls back to the device's with one warning instead of throwing", {
			id = "native_motion_level::motion levels::a live unknown level falls back to the device's with one warning instead of throwing",
			run = function()
				local chosen = Compose.cell("normal")
				local w, env = levelWorld({ motionLevel = chosen })
				local warnings = {}
				local previous = warn
				getfenv(0).warn = function(...)
					table.insert(warnings, table.concat({ ... }, " "))
				end
				local ok = pcall(function()
					chosen:set("slow-mo" :: any)
				end)
				Verify.expect(ok):toBe(true)
				Verify.expect((env.motionLevel:peek())):toBe("normal")
				w.gui.ReducedMotionEnabled = true
				Verify.expect((env.motionLevel:peek())):toBe("limited")
				env.motionLevel:peek()
				getfenv(0).warn = previous
				Verify.expect(#warnings):toBe(1)
				Verify.expect(string.find(warnings[1], "motionLevel", 1, true) ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a theme sheet on the same runtime zeroes paint under the controls' none, even beside controls with no level",
			{
				id = "native_motion_level::motion levels::a theme sheet on the same runtime zeroes paint under the controls' none, even beside controls with no level",
				run = function()
					local themes = require("../src").themes
					local transition = require("./lib/transition")
					local sheet
					local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, _, runtime)
						require("../src").controls(runtime, { types = engine.types } :: any)
						sheet = themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
						return Host.Frame({ sheet :: unknown })
					end, { motionLevel = "none" })
					local rule
					for _, child in sheet:GetChildren() do
						if child.ClassName == "StyleRule" and (child :: StyleRule).Selector == ".facet-text" then
							rule = child
						end
					end
					Verify.expect(transition(rule, "TextColor3").Time):toBe(0)
					w.stop()
				end,
			}
		)

		verifyHarness:case("refuses the removed reducedMotion option and an unknown level", {
			id = "native_motion_level::motion levels::refuses the removed reducedMotion option and an unknown level",
			run = function()
				local ok, message = pcall(levelWorld, { reducedMotion = true })
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(message), "motionLevel", 1, true) ~= nil):toBe(true)
				local bad, why = pcall(levelWorld, { motionLevel = "reduced" })
				Verify.expect(bad):toBe(false)
				Verify.expect(string.find(tostring(why), "motionLevel", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case(
			"an alert is whole once it has rested under none and grows without scaling text under normal",
			{
				id = "native_motion_level::motion levels::an alert is whole once it has rested under none and grows without scaling text under normal",
				run = function()
					local w, shown = alertWorld({ motionLevel = "none" })
					shown:set(true)
					local panel = w.find("AlertPanel")
					w.find("AlertContent").Parent.AbsoluteSize = w.Vector2.new(300, 60)
					w.advance(1 / 60, 2)
					Verify.expect((panel:FindFirstChild("PresentationContent", true))):toBeNil()
					Verify.expect((fadeKit.of(panel))):toBe(0)
					w.stop()
					local w2, shown2 = alertWorld({ motionLevel = "normal" })
					shown2:set(true)
					local panel2 = w2.find("AlertPanel")
					panel2.AbsoluteSize = w2.Vector2.new(440, 176)
					w2.find("AlertContent").Parent.AbsoluteSize = w2.Vector2.new(300, 60)
					w2.advance(1 / 60, 3)
					Verify.expect(panel2.Size.X.Offset < 440):toBe(true)
					Verify.expect(panel2:FindFirstChild("PresentationContent", true) ~= nil):toBe(true)
					w2.stop()
				end,
			}
		)
	end)
end
