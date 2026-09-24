--!strict
local harness = require("./lib/harness")
--[[ D3b — `Callout`: THE APP-PUSHED COACH MARK (navigation-and-menus brief §2 D3,
	director ruling 2026-08-16 §6.2).

	`docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg`
	— the "Post Avatars to Marketplace" plate with an arrow tail pointing up at a
	top-right `+`. It is NOT a tooltip. the standard separation, read 2026-08-16:
	`.help(_:)` is player-pulled, pointer-only and invisible on touch, while
	the coach-mark construct "presents a popover tip on the
	modified view… WHEN THE TIP BECOMES ELIGIBLE FOR DISPLAY". The app decides,
	from rules; it appears on every input class; it retires permanently. (Both
	plates carry D1's tail since the 2026-08-16 device review — the stem says
	which control the words are about, and never was the differentiator.)

	the standing warning ships with it, verbatim: *"Use tips sparingly… Don't use tips
	to guide people through your app, or for advertising and promotion purposes."*

	FOUR CLAIMS THIS FILE EXISTS TO FAIL ON:

	  1. PERSISTENCE IS THE CALLER'S. Facet has no save layer and must not grow
	     one. The construct READS a "has this been seen" Readable and REPORTS when
	     it should be retired; it never writes player state. The case that would
	     catch a framework that quietly did is here by name.
	  2. IT NEVER BLOCKS. Not a modal, no focus trap, and the control it points at
	     stays operable underneath — driven with a real tap on that control, not
	     asserted from the presence of a flag.
	  3. AT MOST ONE ON SCREEN. A queue, not a pile, and it is `toast_schedule`'s
	     queue rather than a second scheduler.
	  4. A RETIRED CALLOUT IS RETIRED. Dismiss it and it does not come back inside
	     this session whatever anybody asks for.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local calloutLib = require("../src/controls/callout")
local fake_target = require("../tests/lib/fake_target")
local Compose = require("../src/vendor/compose/core")
local observeChange = require("../src/core/on_change")

local UI = harness.UI

local TIP = "Post Avatars to Marketplace"
local SURFACE = "/Callout/Layer/Surface"
local PLATE = `{SURFACE}/Plate`
local BODY = `{PLATE}/Content/Body`
local DISMISS = `{PLATE}/Dismiss`
local TAIL = "/Callout/Layer/Tail"

-- the plate's body: a BLUEPRINT, not a string — the f1 plate is styled and holds
-- more than one line
local function plateContent(text: string?): any
	return UI.VStack({
		id = "Content",
		gap = "xs",
		children = {
			UI.Text({ id = "Body", text = text or TIP, textSize = "body" }),
			UI.Text({ id = "Sub", text = "Anyone can wear it", textSize = "caption", role = "secondary" }),
		},
	})
end

--[[ headless world. The `+` is a top-right 44px button on an ordinary screen —
	the f1 geometry — and every interaction below goes through a REAL path
	(adapter.tap, system.deviceKey), never by calling a callback directly. ]]
local function world(opts: any?)
	local options: any = opts or {}
	local core = harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.w or 390, h = options.h or 844 })
	if options.capabilities ~= nil then
		env:set("capabilities", options.capabilities)
		env:set("preferredInput", options.preferredInput)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = harness.newPresenter(core, env, adapter, system)
	return { core = core, env = env, system = system, adapter = adapter, pres = pres }
end

local function plusScreen(onPlus: (() -> ())?): any
	return UI.Screen({
		id = "Editor",
		children = {
			UI.Anchor({
				id = "Bar",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Button({
						id = "Plus",
						label = "+",
						anchor = "topRight",
						width = { type = "fixed", px = 44 },
						height = { type = "fixed", px = 44 },
						onActivate = function()
							if onPlus ~= nil then
								onPlus()
							end
						end,
					}),
				},
			}),
		},
	})
end

local function build(w: any, spec: any): any
	local merged: any = {
		anchor = UI.Button({
			id = "Plus",
			label = "+",
			anchor = "topRight",
			width = { type = "fixed", px = 44 },
			height = { type = "fixed", px = 44 },
		}),
		content = plateContent(),
		onRetire = function() end,
	}
	for key, value in spec do
		merged[key] = value
	end
	-- `content = false` asks for no content at all (a rich-part-only callout)
	if merged.content == false then
		merged.content = nil
	end
	return calloutLib.build(Facet, w.core, merged)
end

-- a screen whose `+` IS the callout's anchor blueprint
local function screenWith(control: any): any
	return UI.Screen({
		id = "Editor",
		children = {
			UI.Anchor({
				id = "Bar",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = { control.blueprint },
			}),
		},
	})
end

describe("D3b Callout: eligibility is the app's rule, and the caller's state", function()
	it("a callout nobody has seen is eligible, presents, and reports itself showing", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(control.api.eligible()).toBe(true)
		-- mounted and eligible, it has asked for the screen itself; asking twice is refused
		expect(control.api.present()).toBe(false)
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
		expect(control.api.isShowing:peek()).toBe(true)
		expect(w.adapter.node(BODY).props.text).toBe(TIP)
		expect(w.pres.callouts().showing).toBe("Callout")
	end)

	it("`seen` is the caller's record, and a seen callout is never eligible", function()
		local w = world()
		local seen = Compose.cell(true)
		local control = build(w, { id = "Callout", seen = seen })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(control.api.eligible()).toBe(false)
		expect(control.api.present()).toBe(false)
		expect(control.api.state()).toBe("retired")
		expect(w.pres.callouts().showing).toBeNil()
		expect(w.adapter.node(PLATE)).toBeNil()
	end)

	it("`afterSessions` holds it back until the session count reaches it", function()
		local w = world()
		local sessions = Compose.cell(1)
		local control = build(w, { id = "Callout", sessions = sessions, afterSessions = 3 })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(control.api.eligible()).toBe(false)
		expect(control.api.present()).toBe(false)
		sessions:set(3)
		expect(control.api.eligible()).toBe(true)
		expect(control.api.present()).toBe(true)
	end)

	it("a feature already used is never coached about", function()
		local w = world()
		local used = Compose.cell(true)
		local control = build(w, { id = "Callout", featureUsed = used })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(control.api.eligible()).toBe(false)
		expect(control.api.state()).toBe("retired")
	end)
end)

describe("D3b Callout: invalidation, and the persistence boundary", function()
	it("using the feature while it is showing takes it down and retires it FOREVER", function()
		local w = world()
		local used = Compose.cell(false)
		local reasons: { string } = {}
		local control = build(w, {
			id = "Callout",
			featureUsed = used,
			onRetire = function(reason: string)
				table.insert(reasons, reason)
			end,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
		used:set(true)
		expect(control.api.state()).toBe("retired")
		expect(w.adapter.node(PLATE)).toBeNil()
		expect(table.concat(reasons, ",")).toBe("featureUsed")
		-- ...and it does not come back, whatever anybody asks for
		expect(control.api.present()).toBe(false)
		expect(w.pres.callouts().showing).toBeNil()
	end)

	it("a player dismissal retires it once, with a reason, and never twice", function()
		local w = world()
		local reasons: { string } = {}
		local control = build(w, {
			id = "Callout",
			onRetire = function(reason: string)
				table.insert(reasons, reason)
			end,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		control.api.dismiss()
		expect(control.api.state()).toBe("retired")
		expect(table.concat(reasons, ",")).toBe("dismissed")
		control.api.dismiss()
		control.api.invalidate()
		expect(table.concat(reasons, ",")).toBe("dismissed") -- ONE report, ever
		--[[ AND RETIREMENT ITSELF IS THE REFUSAL, with nothing else standing in for
			it. This callout declares no `seen` and no `featureUsed`, so if
			`eligible()` stopped consulting `retired` there would be nothing left to
			say no — which is exactly what a mutation of that clause found, silently,
			against the `featureUsed` case above. ]]
		expect(control.api.eligible()).toBe(false)
		expect(control.api.present()).toBe(false)
		expect(w.pres.callouts().showing).toBeNil()
	end)

	it("THE FRAMEWORK WRITES NO PLAYER STATE: `seen` is untouched, the report is the whole contract", function()
		--[[ THE HARD BOUNDARY (brief §2 D3b). A framework that quietly persists
			player state is a different product, and this is the case that fails the
			day one starts. The construct READ `seen` and REPORTED a retirement; the
			signal it read is exactly as the caller left it, and whether anything is
			written is a decision that happens outside this file. ]]
		local w = world()
		local seen = Compose.cell(false)
		local writes = 0
		observeChange(w.core.owner, seen, function()
			writes += 1
		end)
		local reported: string? = nil
		local control = build(w, {
			id = "Callout",
			seen = seen,
			onRetire = function(reason: string)
				reported = reason
			end,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		control.api.dismiss()
		expect(seen:peek()).toBe(false) -- NOT written
		expect(writes).toBe(0)
		expect(reported).toBe("dismissed")
		-- and the caller doing what the report asks retires it for the next session
		seen:set(true)
		expect(control.api.eligible()).toBe(false)
	end)

	it("a callout with no way to report a retirement is an authoring error", function()
		local w = world()
		local ok, err = pcall(function()
			return calloutLib.build(
				Facet,
				w.core,
				{
					id = "Callout",
					anchor = UI.Button({ id = "Plus", label = "+" }),
					content = plateContent(),
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "onRetire", 1, true) ~= nil).toBe(true)
	end)

	it("the spec is CLOSED: an invented key is refused rather than ignored", function()
		local w = world()
		local ok, err = pcall(function()
			return calloutLib.build(
				Facet,
				w.core,
				{
					id = "Callout",
					anchor = UI.Button({ id = "Plus", label = "+" }),
					content = plateContent(),
					onRetire = function() end,
					persist = true,
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "persist", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D3b Callout: at most one on screen — a queue, not a pile", function()
	it("a second callout WAITS rather than stacking beside the first", function()
		local w = world()
		local first = build(w, { id = "Callout" })
		local second = build(w, {
			id = "Second",
			anchor = UI.Button({
				id = "Share",
				label = "Share",
				width = { type = "fixed", px = 60 },
				height = { type = "fixed", px = 44 },
			}),
		})
		w.pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.Anchor({
						id = "Bar",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { first.blueprint, second.blueprint },
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		-- both asked for the screen as they mounted
		w.pres.refresh()
		local q = w.pres.callouts()
		expect(q.showing).toBe("Callout")
		expect(q.visible).toBe(1)
		expect(q.queued).toBe(1)
		expect(first.api.state()).toBe("showing")
		expect(second.api.state()).toBe("queued")
		expect(w.adapter.node("/Second/Layer/Surface/Plate")).toBeNil()
	end)

	it("...and takes its turn the moment the first retires", function()
		local w = world()
		local first = build(w, { id = "Callout" })
		local second = build(w, {
			id = "Second",
			anchor = UI.Button({
				id = "Share",
				label = "Share",
				width = { type = "fixed", px = 60 },
				height = { type = "fixed", px = 44 },
			}),
		})
		w.pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.Anchor({
						id = "Bar",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { first.blueprint, second.blueprint },
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		first.api.present()
		second.api.present()
		w.pres.refresh()
		first.api.dismiss()
		w.pres.refresh()
		expect(w.pres.callouts().showing).toBe("Second")
		expect(second.api.state()).toBe("showing")
		expect(first.api.state()).toBe("retired")
	end)

	it("priority orders the queue without ever showing two", function()
		local w = world()
		local low = build(w, { id = "Callout", priority = 0 })
		local mid = build(w, {
			id = "Second",
			priority = 5,
			anchor = UI.Button({
				id = "Share",
				label = "Share",
				width = { type = "fixed", px = 60 },
				height = { type = "fixed", px = 44 },
			}),
		})
		local high = build(w, {
			id = "Third",
			priority = 9,
			anchor = UI.Button({
				id = "More",
				label = "More",
				width = { type = "fixed", px = 60 },
				height = { type = "fixed", px = 44 },
			}),
		})
		w.pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.Anchor({
						id = "Bar",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = { low.blueprint, mid.blueprint, high.blueprint },
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		low.api.present()
		mid.api.present()
		high.api.present()
		w.pres.refresh()
		expect(w.pres.callouts().visible).toBe(1)
		expect(w.pres.callouts().showing).toBe("Callout")
		low.api.dismiss()
		w.pres.refresh()
		-- the most urgent waiting one goes next, never the oldest
		expect(w.pres.callouts().showing).toBe("Third")
	end)
end)

describe("D3b Callout: it never blocks", function()
	it("presenting one does not move the focus ring", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control))
		local before = w.pres.focus.focused:peek()
		expect(before).toBe("/Editor/Bar/Plus")
		control.api.present()
		w.pres.refresh()
		expect(w.pres.focus.focused:peek()).toBe(before)
	end)

	it("THE CONTROL IT POINTS AT STAYS OPERABLE: a tap on it still activates it", function()
		--[[ DRIVEN, NOT ASSERTED (brief §2 D3b). The plate's tap-away catcher runs
			in the presenter's NON-CONSUMING mode, so a tap outside the plate both
			retires the coach mark and reaches whatever was underneath. Counting the
			activation is the only way to tell that from a catcher that swallowed it. ]]
		local w = world()
		local presses = 0
		local control = build(w, {
			id = "Callout",
			anchor = UI.Button({
				id = "Plus",
				label = "+",
				anchor = "topRight",
				width = { type = "fixed", px = 44 },
				height = { type = "fixed", px = 44 },
				onActivate = function()
					presses += 1
				end,
			}),
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
		w.adapter.tap("/Editor/Bar/Plus")
		w.pres.refresh()
		expect(presses).toBe(1)
		--[[ ...AND THE PLATE IS STILL UP, which is the reference behaviour rather
			than an oversight: in `r3-segmented-control.mov` the coach mark is visible
			and unchanged across the whole clip while the player works the controls
			beneath it. What retires it is the APP noticing the feature was used —
			`featureUsed`, below — not the framework guessing from a tap. ]]
		expect(control.api.state()).toBe("showing")
	end)

	--[[ THE SAME CLAIM, MEASURED IN Z RATHER THAN DRIVEN (device review
		2026-08-16, F2). The case above is the strongest thing a path-addressed tap
		can say, and it is not strong enough: `adapter.tap(path)` looks the node up
		by name and calls its handler, so it has no hit test and no z-order at all.
		On a real engine input goes to the TOPMOST object and a `GuiButton` SINKS it
		(measured 2026-08-13) — so the one fact that decides whether
		the control underneath is reachable is the one the driven case cannot see.

		The tap-away catcher is a full-viewport `Button`, and it was mounted at
		`owner.displayOrder - 50`. That is correct for every consumer this catcher
		was written for, because there `owner` IS the base screen. A coach mark is
		the first `outsideDismiss` owner that is itself a surface ABOVE the base
		screen, and `- 50` off a surface at base+100 lands the catcher at base+50 —
		on top of every control it was supposed to sit under. The whole screen
		became one dismiss target: the director's next press went to the catcher
		instead of the button he aimed at, retired the plate permanently, and the
		coach marks "stopped appearing".

		So the invariant is stated where it can be checked: the catcher is BELOW
		everything the player can still press, which is every live surface. ]]
	it("its tap-away catcher sits BELOW the screen it points at, not over it", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		local base = w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")

		local catcher = w.adapter.rootDisplayOrder("__popupcatcher__")
		expect(`catcher mounted? {catcher ~= nil}`).toBe("catcher mounted? true")
		local baseOrder = w.adapter.rootDisplayOrder("Editor")
		expect(`catcher {catcher} vs base screen {baseOrder}: over the screen? {(catcher :: number) > baseOrder}`).toBe(
			`catcher {catcher} vs base screen {baseOrder}: over the screen? false`
		)
		-- ...and below the plate's own surface too, which it always was
		expect((catcher :: number) < base.displayOrder).toBe(true)
	end)

	it("a tap in empty space retires it through the presenter's own non-consuming catcher", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		local catcher = w.pres.topPopupCatcherPath()
		expect(catcher).never().toBeNil()
		w.adapter.tap(catcher :: string, { x = 8, y = 800 })
		w.pres.refresh()
		expect(control.api.state()).toBe("retired")
		expect(w.pres.callouts().showing).toBeNil()
	end)

	it("it is NOT a modal: the screen underneath keeps its own focus scope", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		local handle = w.pres.present(screenWith(control))
		control.api.present()
		w.pres.refresh()
		-- the base screen's ring is where it was, and its own order is intact
		expect(w.pres.focus.focused:peek()).toBe("/Editor/Bar/Plus")
		local order = handle.focusOrder().traversal
		expect(#order > 0).toBe(true)
		for _, entry in order do
			expect(string.find(entry.path, "/Callout", 1, true)).toBeNil()
		end
	end)
end)

describe("D3b Callout: every input class can retire it", function()
	local function showing(w: any, control: any)
		control.api.present()
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
	end

	it("pointer: a click on the dismiss affordance retires it", function()
		local w = world({
			capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
			preferredInput = "KeyboardAndMouse",
		})
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		showing(w, control)
		w.adapter.tap(DISMISS)
		w.pres.refresh()
		expect(control.api.state()).toBe("retired")
	end)

	it("touch: a tap on the dismiss affordance retires it, and it meets the 44px floor", function()
		local w = world({
			capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
			preferredInput = "Touch",
		})
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		showing(w, control)
		local rect = w.adapter.node(DISMISS).rect
		expect(rect.h >= 44).toBe(true)
		w.adapter.tap(DISMISS)
		w.pres.refresh()
		expect(control.api.state()).toBe("retired")
	end)

	it("keyboard: Return on the focused dismiss affordance retires it", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		showing(w, control)
		expect(w.pres.focus.focusOn(DISMISS)).toBe(true)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(control.api.state()).toBe("retired")
	end)

	it("gamepad: ButtonA on the focused dismiss affordance retires it", function()
		local w = world({
			capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
			preferredInput = "Gamepad",
		})
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		showing(w, control)
		expect(w.pres.focus.focusOn(DISMISS)).toBe(true)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(control.api.state()).toBe("retired")
	end)

	it("...and one arrow press reaches it, so a pad player is never stuck with a plate", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control))
		showing(w, control)
		expect(w.pres.focus.focused:peek()).toBe("/Editor/Bar/Plus")
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:peek()).toBe(DISMISS)
	end)
end)

describe("D3b Callout: the f1 fixture", function()
	it("f1: a plate under a top-right +, arrow up at it, body shifted left", function()
		--[[ The reference image reproduced at 390x844. Every fact is a placement
			decision D1 already owns; what this proves is that the CONSTRUCT asks for
			the right ones — below the `+`, tailed, and still on screen. ]]
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		local plus = w.adapter.node("/Editor/Bar/Plus").rect
		local panel = w.adapter.node(SURFACE).rect
		local dump = w.pres.anchoredSurfaces().surfaces[1]
		expect(dump.edge).toBe("bottom")
		expect(dump.flipped).toBe(false)
		expect(panel.y > plus.y + plus.h).toBe(true)
		expect(panel.x + panel.w <= 390).toBe(true)
		expect(dump.shift < 0).toBe(true)
		expect(dump.tailSuppressed).toBe(false)
		expect(dump.tailX >= plus.x and dump.tailX <= plus.x + plus.w).toBe(true)
		expect(w.adapter.visibleOf(TAIL)).toBe(true)
	end)

	it("the content is a BLUEPRINT, not a string: the plate carries the tree it was given", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		expect(w.adapter.node(BODY).props.text).toBe(TIP)
		expect(w.adapter.node(`{PLATE}/Content/Sub`).props.text).toBe("Anyone can wear it")
	end)

	it("player copy survives ~1.4x pseudo-localization by wrapping, never clipping", function()
		local w = world()
		local long = string.rep(TIP .. " ", 3)
		local control = build(w, { id = "Callout", content = plateContent(long) })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		local rect = w.adapter.node(PLATE).rect
		expect(rect.x >= 0).toBe(true)
		expect(rect.x + rect.w <= 390).toBe(true)
		local facts = w.pres.anchoredSurfaces().surfaces[1]
		expect(facts.fits).toBe(true)
	end)
end)

describe("D3b Callout: the dump, and the teardown", function()
	it("the dump carries the schema, the state and the eligibility it resolved", function()
		local w = world()
		local sessions = Compose.cell(4)
		local presented = Compose.cell(false)
		local control = build(w, {
			id = "Callout",
			sessions = sessions,
			afterSessions = 2,
			priority = 3,
			isPresented = presented,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		local closed = control.dump()
		expect(closed.schema).toBe("facet-callout-dump/1")
		expect(closed.id).toBe("Callout")
		expect(closed.state).toBe("waiting")
		expect(closed.eligible).toBe(true)
		expect(closed.priority).toBe(3)
		expect(string.find(closed.text, "waiting", 1, true) ~= nil).toBe(true)
		presented:set(true)
		w.pres.refresh()
		expect(control.dump().state).toBe("showing")
	end)

	it("the queue's own dump names what is on screen and what is waiting", function()
		local w = world()
		local presented = Compose.cell(false)
		local control = build(w, { id = "Callout", isPresented = presented })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(w.pres.callouts().schema).toBe("facet-callout-queue-dump/1")
		expect(w.pres.callouts().showing).toBeNil()
		presented:set(true)
		w.pres.refresh()
		expect(w.pres.callouts().showing).toBe("Callout")
		expect(string.find(w.pres.callouts().text, "on screen", 1, true) ~= nil).toBe(true)
	end)

	it("dispose takes the plate down and gives the queue slot back", function()
		local w = world()
		local first = build(w, { id = "Callout" })
		w.pres.present(screenWith(first), { initialFocus = "none" })
		first.api.present()
		w.pres.refresh()
		expect(w.pres.callouts().showing).toBe("Callout")
		first.dispose()
		w.pres.refresh()
		expect(w.pres.callouts().showing).toBeNil()
		expect(w.adapter.node(PLATE)).toBeNil()
	end)

	it("dismissing the surface underneath takes the callout with it", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		local handle = w.pres.present(screenWith(control), { initialFocus = "none" })
		control.api.present()
		w.pres.refresh()
		w.pres.dismiss(handle)
		w.pres.refresh()
		expect(w.adapter.node(PLATE)).toBeNil()
		expect(w.pres.callouts().showing).toBeNil()
	end)

	it("NO DEVICE BRANCH: the construct names no platform", function()
		local fs = require("@lune/fs")
		local text = string.lower(fs.readFile("src/controls/callout.luau"))
		for _, name in { "iphone", "ipad", "android", "xbox", "playstation", "nintendo", "macos", "windows" } do
			expect(string.find(text, name, 1, true)).toBeNil()
		end
	end)

	it("the standing warning ships with the documentation", function()
		--[[ *"Use tips sparingly… Don't use tips to guide people through your app,
			or for advertising and promotion purposes."* The brief asks for it
			VERBATIM in the docs, which makes it a thing a check can hold. ]]
		local fs = require("@lune/fs")
		local api = fs.readFile("docs/reference/api.md")
		expect(string.find(api, "Use tips sparingly", 1, true) ~= nil).toBe(true)
		expect(string.find(api, "Don't use tips to guide people through your app, or for advertising", 1, true) ~= nil).toBe(
			true
		)
	end)
end)

describe("Callout: bound facts are read as tracked values", function()
	it("a function isPresented is evaluated and followed, not treated as a request", function()
		local w = world()
		local wanted = Compose.cell(false)
		local control = build(w, {
			id = "Callout",
			isPresented = function(use: any)
				return use(wanted)
			end,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		w.pres.refresh()
		expect(control.api.state()).toBe("waiting")
		expect(w.adapter.node(PLATE)).toBeNil()
		wanted:set(true)
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
		wanted:set(false)
		w.pres.refresh()
		expect(w.adapter.node(PLATE)).toBeNil()
	end)

	it("a function seen / featureUsed rules the callout out, and a later true retires it once", function()
		local w = world()
		local seen = Compose.cell(true)
		local ruledOut = build(w, {
			id = "Callout",
			seen = function(use: any)
				return use(seen)
			end,
		})
		expect(ruledOut.api.eligible()).toBe(false)
		expect(ruledOut.api.state()).toBe("retired")
		local used = Compose.cell(false)
		local reports: { string } = {}
		local w2 = world()
		local live = build(w2, {
			id = "Callout",
			featureUsed = function(use: any)
				return use(used)
			end,
			onRetire = function(reason: string)
				table.insert(reports, reason)
			end,
		})
		w2.pres.present(screenWith(live), { initialFocus = "none" })
		w2.pres.refresh()
		expect(live.api.state()).toBe("showing")
		used:set(true)
		w2.pres.refresh()
		expect(live.api.state()).toBe("retired")
		expect(table.concat(reports, ",")).toBe("featureUsed")
		expect(w2.adapter.node(PLATE)).toBeNil()
	end)
end)

describe("Callout: callbacks during a synchronous show never strand or double-close a plate", function()
	-- present once the source is already mounted, so the queue shows synchronously
	local function armed(onShow: (control: any) -> ()): (any, any, { string })
		local w = world()
		local wanted = Compose.cell(false)
		local reports: { string } = {}
		local control: any
		control = build(w, {
			id = "Callout",
			isPresented = wanted,
			onShow = function()
				onShow(control)
			end,
			onRetire = function(reason: string)
				table.insert(reports, reason)
			end,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		w.pres.refresh()
		wanted:set(true)
		w.pres.refresh()
		return w, control, reports
	end

	it("dismiss inside onShow retires once and takes the plate down", function()
		local w, control, reports = armed(function(c)
			c.api.dismiss()
		end)
		expect(control.api.state()).toBe("retired")
		expect(table.concat(reports, ",")).toBe("dismissed")
		expect(w.adapter.node(PLATE)).toBeNil()
		expect(w.pres.callouts().showing).toBeNil()
	end)

	it("dispose inside onShow releases the queue slot", function()
		local w, _, _ = armed(function(c)
			c.dispose()
		end)
		w.pres.refresh()
		expect(w.adapter.node(PLATE)).toBeNil()
		expect(w.pres.callouts().showing).toBeNil()
	end)

	it(
		"rearm inside onShow (even when it then throws) leaves no stranded plate, and a later show is its own",
		function()
			local count = 0
			local w, control, reports = armed(function(c)
				count += 1
				if count == 1 then
					c.api.rearm()
					error("caller bug after rearm")
				end
			end)
			expect(w.adapter.node(PLATE) == nil or control.api.state() == "showing").toBe(true)
			-- the next geometry pass presents a NEW generation, and only one plate exists
			w.pres.refresh()
			expect(control.api.state()).toBe("showing")
			expect(w.pres.callouts().showing).toBe("Callout")
			control.api.dismiss()
			w.pres.refresh()
			expect(w.adapter.node(PLATE)).toBeNil()
			expect(table.concat(reports, ",")).toBe("dismissed")
		end
	)

	it("an ordinary throw in onShow still shows the plate and keeps the slot accounting", function()
		local w, control, _ = armed(function()
			error("caller bug")
		end)
		expect(control.api.state()).toBe("showing")
		control.api.dismiss()
		w.pres.refresh()
		expect(w.adapter.node(PLATE)).toBeNil()
		expect(w.pres.callouts().showing).toBeNil()
	end)
end)

describe("Callout: two hosts and a recycled source keep their own resources", function()
	it("disposing one app's callout never touches another app's", function()
		local a, b = world(), world()
		local ca, cb = build(a, { id = "Callout" }), build(b, { id = "Callout" })
		a.pres.present(screenWith(ca), { initialFocus = "none" })
		b.pres.present(screenWith(cb), { initialFocus = "none" })
		a.pres.refresh()
		b.pres.refresh()
		expect(a.adapter.node(PLATE) ~= nil and b.adapter.node(PLATE) ~= nil).toBe(true)
		ca.dispose()
		a.pres.refresh()
		b.pres.refresh()
		expect(a.adapter.node(PLATE)).toBeNil()
		expect(b.pres.callouts().showing).toBe("Callout")
		expect(b.adapter.node(PLATE) ~= nil).toBe(true)
	end)

	it("a callout rebuilt at the same path by a branch cycle is a new control with one plate", function()
		local w = world()
		local show = Compose.cell(true)
		local built = 0
		w.pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.When({
						id = "Gate",
						condition = show,
						thenView = function()
							built += 1
							return calloutLib.build(Facet, w.core, {
								id = "Callout",
								anchor = UI.Button({ id = "Plus", label = "+" }),
								content = plateContent(),
								onRetire = function() end,
							}).blueprint
						end,
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		w.pres.refresh()
		expect(w.pres.callouts().showing).toBe("Callout")
		show:set(false)
		w.pres.refresh()
		expect(w.adapter.node(PLATE)).toBeNil()
		expect(w.pres.callouts().showing).toBeNil()
		show:set(true)
		w.pres.refresh()
		expect(built).toBe(2)
		expect(w.pres.callouts().showing).toBe("Callout")
		expect(w.pres.callouts().queued).toBe(0)
	end)
end)

describe("Callout: rich parts — title, media, steps, actions and a close button", function()
	local HEADER = `{PLATE}/Header`
	local ACTIONS = `{PLATE}/Actions`

	local function shown(spec: any): (any, any)
		local w = world()
		local control = build(w, spec)
		w.pres.present(screenWith(control), { initialFocus = "none" })
		w.pres.refresh()
		return w, control
	end

	local function buttonsUnder(w: any, prefix: string): { string }
		local out: { string } = {}
		for _, path in w.adapter.paths() do
			if string.sub(path, 1, #prefix) == prefix and w.adapter.node(path).class == "Button" then
				table.insert(out, string.sub(path, #prefix + 2))
			end
		end
		table.sort(out)
		return out
	end

	it("the full composition paints every part, and one or two actions replace the bottom dismiss", function()
		local pressed: { string } = {}
		local w, control = shown({
			id = "Callout",
			title = "Try the editor",
			media = { image = "rbxassetid://1", aspectRatio = 2 },
			steps = { index = 2, count = 3 },
			closeButton = true,
			actions = {
				{
					id = "Later",
					label = "Later",
					onActivate = function()
						table.insert(pressed, "Later")
					end,
				},
				{
					id = "Go",
					label = "Show me",
					role = "default",
					onActivate = function()
						table.insert(pressed, "Go")
					end,
				},
			},
		})
		expect(control.api.state()).toBe("showing")
		expect(w.adapter.node(`{HEADER}/Title`).props.text).toBe("Try the editor")
		local media = w.adapter.node(`{PLATE}/Media`).rect
		expect(media.w > 0 and math.abs(media.w / media.h - 2) < 0.01).toBe(true)
		expect(w.adapter.node(`{PLATE}/Steps`).props.text).toBe("2 of 3")
		expect(w.adapter.node(BODY).props.text).toBe(TIP)
		expect(table.concat(buttonsUnder(w, PLATE), ",")).toBe("Actions/Go,Actions/Later,Header/Close")
		expect(w.adapter.node(DISMISS)).toBeNil()
		w.adapter.tap(`{ACTIONS}/Go`)
		w.pres.refresh()
		expect(table.concat(pressed, ",")).toBe("Go")
		expect(control.api.state()).toBe("retired")
		expect(w.adapter.node(PLATE)).toBeNil()
	end)

	it("an action retires its own generation once, and never a newer one it presented", function()
		local reports: { string } = {}
		local control: any
		local w = world()
		control = build(w, {
			id = "Callout",
			actions = {
				{
					id = "Again",
					label = "Again",
					onActivate = function()
						control.api.rearm()
						control.api.present()
						error("caller bug after rearm")
					end,
				},
			},
			onRetire = function(reason: string)
				table.insert(reports, reason)
			end,
		})
		w.pres.present(screenWith(control), { initialFocus = "none" })
		w.pres.refresh()
		expect((pcall(w.adapter.tap, `{ACTIONS}/Again`))).toBe(false) -- raised, not swallowed
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
		expect(#reports).toBe(0)
		expect(w.pres.callouts().showing).toBe("Callout")
	end)

	it("a throwing action still retires the presentation it belonged to, exactly once", function()
		local reports: { string } = {}
		local w, control = shown({
			id = "Callout",
			actions = {
				{
					id = "Boom",
					label = "Boom",
					onActivate = function()
						error("caller bug")
					end,
				},
			},
			onRetire = function(reason: string)
				table.insert(reports, reason)
			end,
		})
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focusOn(`{ACTIONS}/Boom`)).toBe(true)
		expect((pcall(w.system.deviceKey, "Return", true))).toBe(false) -- raised, not swallowed
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(control.api.state()).toBe("retired")
		expect(table.concat(reports, ",")).toBe("action")
	end)

	it("a disabled action cannot fire", function()
		local fired = false
		local w, control = shown({
			id = "Callout",
			actions = {
				{
					id = "Nope",
					label = "Nope",
					enabled = false,
					onActivate = function()
						fired = true
					end,
				},
			},
		})
		w.adapter.tap(`{ACTIONS}/Nope`)
		w.pres.refresh()
		expect(fired).toBe(false)
		expect(control.api.state()).toBe("showing")
	end)

	it("closeButton adds a top close and keeps the legacy bottom dismiss when there are no actions", function()
		local w, control = shown({ id = "Callout", closeButton = true })
		expect(table.concat(buttonsUnder(w, PLATE), ",")).toBe("Dismiss,Header/Close")
		local close = w.adapter.node(`{HEADER}/Close`).rect
		expect(close.w >= 44 and close.h >= 44).toBe(true)
		w.adapter.tap(`{HEADER}/Close`)
		w.pres.refresh()
		expect(control.api.state()).toBe("retired")
	end)

	it("the legacy content-only plate is unchanged: content then the dismiss button, nothing else", function()
		local w = shown({ id = "Callout" })
		expect(table.concat(buttonsUnder(w, PLATE), ",")).toBe("Dismiss")
		expect(w.adapter.node(HEADER)).toBeNil()
		expect(w.adapter.node(`{PLATE}/Media`)).toBeNil()
		local children = w.adapter.node(PLATE).children or {}
		expect(#children == 0 or #children == 2).toBe(true)
	end)

	it("title-only, media-only, steps-only and actions-only compositions need no content", function()
		for _, spec in
			{
				{ title = "Title only" },
				{ media = { image = "rbxassetid://1", height = 80 } },
				{ steps = { index = 1, count = 2 } },
				{ actions = { { id = "Ok", label = "Ok", onActivate = function() end } } },
			}
		do
			spec.id = "Callout"
			spec.content = false
			local w, control = shown(spec)
			expect(control.api.state()).toBe("showing")
			expect(w.adapter.node(PLATE) ~= nil).toBe(true)
		end
	end)

	it("an empty composition and malformed parts are refused by name", function()
		local w = world()
		for _, bad in
			{
				{ content = false },
				{ content = false, closeButton = true },
				{ media = { image = "x", aspectRatio = 1, height = 20 } },
				{ media = { image = "x" } },
				{ media = { image = "x", aspectRatio = -1 } },
				{ media = { image = "x", height = 10, scaleMode = "tile" } },
				{ media = { image = "x", height = 10, extra = 1 } },
				{ steps = { index = 0, count = 2 } },
				{ steps = { index = 3, count = 2 } },
				{ steps = { index = 1.5, count = 2 } },
				{
					actions = {
						{ id = "A", label = "A", onActivate = print },
						{ id = "B", label = "B", onActivate = print },
						{ id = "C", label = "C", onActivate = print },
					},
				},
				{
					actions = {
						{ id = "A", label = "A", onActivate = print },
						{ id = "A", label = "B", onActivate = print },
					},
				},
				{ actions = { { id = "A", label = "A" } } },
				{ actions = { { id = "A", label = "A", onActivate = print, role = "primary" } } },
				{ closeButton = "yes" },
				{ title = 4 },
			}
		do
			local spec: any = { id = "Callout" }
			for key, value in bad :: any do
				spec[key] = if value == false then nil else value
			end
			if (bad :: any).content == false then
				spec.content = nil
			end
			local ok = pcall(build, w, spec)
			if (bad :: any).content == false then
				-- `build` merges a default content; remove it for the empty cases
				local merged: any =
					{ id = "Callout", anchor = UI.Button({ id = "Plus", label = "+" }), onRetire = print }
				for key, value in spec do
					merged[key] = value
				end
				merged.content = nil
				ok = pcall(calloutLib.build, Facet, w.core, merged)
			end
			expect(ok).toBe(false)
		end
	end)
end)
