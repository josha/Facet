--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local requireDynamic = require :: (any) -> any

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local Vector2 = require("@lune/roblox").Vector2

	local function scenario(name: string, options: any?): (any, any)
		local built: any
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, _, runtime)
			local ctx = { UI = UI, Host = Host, Compose = Compose, types = engine.types, runtime = runtime }
			built = requireDynamic("../examples/gallery/scenarios/" .. name).build(ctx)
			return built.screen()
		end, options)
		return w, built
	end

	verifyHarness:suite("native gallery: the Overlays tab", function()
		verifyHarness:case("opens the about and source popovers from its steps, shows the rich tour, and resets", {
			id = "native_overlays_gallery::native gallery: the Overlays tab::opens the about and source popovers from its steps, shows the rich tour, and resets",
			run = function()
				local w, built = scenario("overlays", { motionLevel = "none" })
				Verify.expect(w.find("Header") ~= nil and w.find("Search") ~= nil):toBe(true)
				built.steps.openAbout()
				Verify.expect(w.find("AboutModal") ~= nil):toBe(true)
				Verify.expect(overlay.find(w.find("AboutModal"), "Body").ClassName):toBe("ScrollingFrame")
				w.find("ModalBack").Pressed:Fire()
				Verify.expect(built.report().about):toBe(false)
				Verify.expect(built.report().status):toBe("Last: about closed (cancel)")
				built.steps.openSource()
				Verify.expect(w.find("SourceModal") ~= nil):toBe(true)
				w.find("SourceRow").AbsolutePosition = Vector2.new(16, 300)
				w.find("SourceRow").AbsoluteSize = Vector2.new(400, 20)
				w.find("Panel").AbsoluteSize = Vector2.new(200, 60)
				Verify.expect(w.find("Tail").Visible):toBe(true)
				w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(790, 590) })
				Verify.expect(built.report().source):toBe(false)
				built.steps.tour()
				local plate = w.find("CalloutPanel")
				Verify.expect(overlay.find(plate, "Steps").Text):toBe("1 of 3")
				overlay.find(plate, "Go").Activated:Fire()
				Verify.expect(built.report().step):toBe(2)
				Verify.expect(overlay.find(w.find("CalloutPanel"), "Steps").Text):toBe("2 of 3")
				overlay.find(w.find("CalloutPanel"), "Later").Activated:Fire()
				Verify.expect((w.find("CalloutPanel"))):toBeNil()
				built.steps.openDialog()
				Verify.expect(w.find("DialogModal") ~= nil):toBe(true)
				Verify.expect(w.find("Hero") ~= nil):toBe(true)
				overlay.find(w.find("Actions"), "Stay").Activated:Fire()
				Verify.expect(built.report().dialog):toBe(false)
				built.steps.reset()
				Verify.expect(built.report().status):toBe("Last: nothing yet")
				Verify.expect(built.report().step):toBe(1)
				built.steps.tour()
				Verify.expect(overlay.find(w.find("CalloutPanel"), "Steps").Text):toBe("1 of 3")
				w.stop()
			end,
		})

		verifyHarness:case("the locked popover and the terms dialog refuse their close until the screen allows it", {
			id = "native_overlays_gallery::native gallery: the Overlays tab::the locked popover and the terms dialog refuse their close until the screen allows it",
			run = function()
				local w, built = scenario("overlays", { motionLevel = "none" })
				w.find("LockedButton").Activated:Fire()
				Verify.expect(built.report().locked):toBe(true)
				w.find("ModalBack").Pressed:Fire()
				Verify.expect(built.report().locked):toBe(true)
				Verify.expect(built.report().status):toBe("Last: close refused")
				w.find("Allow").Activated:Fire()
				w.find("ModalBack").Pressed:Fire()
				Verify.expect(built.report().locked):toBe(false)
				w.find("TermsButton").Activated:Fire()
				w.find("Close").Activated:Fire()
				Verify.expect(built.report().terms):toBe(true)
				w.find("Read").Activated:Fire()
				w.find("Close").Activated:Fire()
				Verify.expect(built.report().terms):toBe(false)
				Verify.expect(built.report().status):toBe("Last: terms closed (close)")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native gallery: the Status tab notices and toasts", function()
		verifyHarness:case("the banner pins to the tab's top and its content moves out of the way, then back", {
			id = "native_overlays_gallery::native gallery: the Status tab notices and toasts::the banner pins to the tab's top and its content moves out of the way, then back",
			run = function()
				local w, built = scenario("status_family", { motionLevel = "none" })
				local frame = w.find("StatusFamily")
				local padding = frame:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingTop.Offset):toBe(16)
				built.notices.banner:set(true)
				local banner = w.find("Offline")
				Verify.expect((banner:IsDescendantOf(frame))):toBe(false)
				banner.AbsolutePosition = Vector2.new(0, 0)
				banner.AbsoluteSize = Vector2.new(800, 48)
				Verify.expect(padding.PaddingTop.Offset):toBe(16 + 48)
				built.notices.banner:set(false)
				Verify.expect(padding.PaddingTop.Offset):toBe(16)
				w.stop()
			end,
		})

		verifyHarness:case(
			"the showcase buttons present through one schedule; a burst is capped, never dropped silently",
			{
				id = "native_overlays_gallery::native gallery: the Status tab notices and toasts::the showcase buttons present through one schedule; a burst is capped, never dropped silently",
				run = function()
					local w, built = scenario("status_family", { motionLevel = "none" })
					w.find("SnackMessage").Activated:Fire()
					Verify.expect(#w.findAll("ToastRow")):toBe(1)
					Verify.expect(overlay.find(w.find("ToastRow"), "Message").Text):toBe("Saved to your garage.")
					w.find("SnackAction").Activated:Fire()
					Verify.expect(#w.findAll("Snack")):toBe(1)
					w.find("SnackBurst").Activated:Fire()
					Verify.expect((built.notices.last:peek())):toBe("Last: toast capacity")
					Verify.expect(#w.findAll("ToastRow")):toBe(3)
					w.advance(4.2, 42)
					Verify.expect((built.notices.last:peek())):toBe("Last: toast timeout")
					built.steps.reset()
					Verify.expect(#w.findAll("Snack")):toBe(0)
					Verify.expect(#w.findAll("ToastRow")):toBe(0)
					w.stop()
				end,
			}
		)
	end)
end
