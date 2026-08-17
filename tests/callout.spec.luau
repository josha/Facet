--!strict
--[[ D3b — `Callout`: THE APP-PUSHED COACH MARK (navigation-and-menus brief §2 D3,
	director ruling 2026-08-16 §6.2).

	`docs/plans/reference-media/2026-08-16-roblox-app-navigation/f1-avatar-editor.jpeg`
	— the "Post Avatars to Marketplace" plate with an arrow tail pointing up at a
	top-right `+`. It is NOT a tooltip. Apple's own separation, read 2026-08-16:
	`.help(_:)` is player-pulled, pointer-only and invisible on touch, while
	TipKit's `popoverTip(_:arrowEdge:action:)` "presents a popover tip on the
	modified view… WHEN THE TIP BECOMES ELIGIBLE FOR DISPLAY". The app decides,
	from rules; it appears on every input class; it retires permanently. (Both
	plates carry D1's tail since the 2026-08-16 device review — the stem says
	which control the words are about, and never was the differentiator.)

	Apple's warning ships with it, verbatim: *"Use tips sparingly… Don't use tips
	to guide people through your app, or for advertising and promotion purposes."*

	FOUR CLAIMS THIS FILE EXISTS TO FAIL ON:

	  1. PERSISTENCE IS THE CALLER'S. LuauUI has no save layer and must not grow
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

local LuauUI = require("../src") :: any
local calloutLib = require("../src/controls/callout")
local fake_target = require("../tests/lib/fake_target")

local UI = LuauUI.UI

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
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.w or 390, h = options.h or 844 })
	if options.capabilities ~= nil then
		env:set("capabilities", options.capabilities)
		env:set("preferredInput", options.preferredInput)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
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
	return calloutLib.build(LuauUI, w.core, merged)
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
		expect(control.api.present()).toBe(true)
		w.pres.refresh()
		expect(control.api.state()).toBe("showing")
		expect(control.api.isShowing:get()).toBe(true)
		expect(w.adapter.node(BODY).props.text).toBe(TIP)
		expect(w.pres.callouts().showing).toBe("Callout")
	end)

	it("`seen` is the caller's record, and a seen callout is never eligible", function()
		local w = world()
		local seen = w.core:signal(true)
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
		local sessions = w.core:signal(1)
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
		local used = w.core:signal(true)
		local control = build(w, { id = "Callout", featureUsed = used })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(control.api.eligible()).toBe(false)
		expect(control.api.state()).toBe("retired")
	end)
end)

describe("D3b Callout: invalidation, and the persistence boundary", function()
	it("using the feature while it is showing takes it down and retires it FOREVER", function()
		local w = world()
		local used = w.core:signal(false)
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
		local seen = w.core:signal(false)
		local writes = 0
		w.core:observe(seen, function()
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
		expect(seen:get()).toBe(false) -- NOT written
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
				LuauUI,
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
				LuauUI,
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
		expect(first.api.present()).toBe(true)
		expect(second.api.present()).toBe(true)
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
		local before = w.pres.focus.focused:get()
		expect(before).toBe("/Editor/Bar/Plus")
		control.api.present()
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe(before)
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
		(docs/lessons/…, measured 2026-08-13) — so the one fact that decides whether
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
		expect(w.pres.focus.focused:get()).toBe("/Editor/Bar/Plus")
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
		expect(w.pres.focus.focused:get()).toBe("/Editor/Bar/Plus")
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(DISMISS)
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
		local sessions = w.core:signal(4)
		local control = build(w, { id = "Callout", sessions = sessions, afterSessions = 2, priority = 3 })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		local closed = control.dump()
		expect(closed.schema).toBe("luauui-callout-dump/1")
		expect(closed.id).toBe("Callout")
		expect(closed.state).toBe("waiting")
		expect(closed.eligible).toBe(true)
		expect(closed.priority).toBe(3)
		expect(string.find(closed.text, "waiting", 1, true) ~= nil).toBe(true)
		control.api.present()
		w.pres.refresh()
		expect(control.dump().state).toBe("showing")
	end)

	it("the queue's own dump names what is on screen and what is waiting", function()
		local w = world()
		local control = build(w, { id = "Callout" })
		w.pres.present(screenWith(control), { initialFocus = "none" })
		expect(w.pres.callouts().schema).toBe("luauui-callout-queue-dump/1")
		expect(w.pres.callouts().showing).toBeNil()
		control.api.present()
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

	it("Apple's own warning ships with the documentation", function()
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
