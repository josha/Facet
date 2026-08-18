--!strict
-- FULL-VALUE DISCLOSURE (decision LTN-4; the plan's overflow rung 3). A
-- `UI.Text{ disclose = true }` that truncated owes the reader the whole string,
-- and the PRESENTER pays that debt: engaging the label presents one STATIC plate
-- carrying the full value.
--
-- LTN-2 chose static over an engaged marquee, so there is nothing here to
-- animate: reduced-motion parity is structural, the moving-label count stays
-- zero, and nothing runs per frame while nothing is engaged. What is left to
-- prove is the contract — that each of the three input classes engages it, that
-- exactly one is ever live, that every disengagement removes it, and that it is
-- presentation chrome (never focusable, never in the focus order, above its
-- owner) rather than a surface.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("../tests/lib/fake_target")

local LONG_NAME = "Bartholomewwwwwwwwwwwwwwwwww" -- one word, far wider than a 120px cell
local PLATE = "/__disclose__/Layer/Plate"
local PLATE_LABEL = "/__disclose__/Layer/Plate/Full"

--[[ ONE SUBSTRATE (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants — the
	viewport is set before anything can solve, and one presenter per adapter. The
	tuple order here, `core, env, adapter, system, pres`, is the one
	`Facet.newPresenter` itself takes and is now the only one in the suite: twelve
	files used to swap positions three and four with the same five names, so a line
	copied between two neighbouring specs bound an action system to a variable
	called `adapter` and said nothing. ]]
local function makeWorld()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

-- a focusable row whose name cell is a disclosed, truncated label
local function row(id: string, text: any, disclose: boolean?): any
	local cellProps: any = {
		id = "Name",
		text = text,
		textSize = 16,
		disclose = if disclose == false then nil else true,
	}
	return UI.Button({
		id = id,
		label = "",
		width = { type = "fixed", px = 120 },
		height = { type = "fixed", px = 44 },
		children = { UI.Text(cellProps) },
	})
end

local function roster(children: { any }): any
	return UI.Screen({ id = "Roster", children = children })
end

-- the shipped default lands focus on the first focusable, which is itself one of
-- the three engagements; the pointer and touch cases need it out of the way
local NO_FOCUS = { initialFocus = "none" }

describe("LTN-4 disclosure: engagement by input class", function()
	it("focus entering the containing focusable presents the static full-value plate", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME), UI.Button({ id = "Other", label = "Other" }) }))
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.source).toBe("focus")
		expect(d.sourcePath).toBe("/Roster/RowA/Name")
		expect(d.text).toBe(LONG_NAME)
		expect(adapter.node(PLATE_LABEL).props.text).toBe(LONG_NAME)
	end)

	it("pointer hover presents the plate only after the dwell elapses", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		expect(pres.disclosure().present).toBe(false)
		pres._discloseHover("/Roster/RowA")
		expect(pres.disclosure().present).toBe(false) -- the pointer has not dwelt yet
		pres.tick(0.2)
		expect(pres.disclosure().present).toBe(false)
		pres.tick(0.3)
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.source).toBe("pointer")
		expect(d.sourcePath).toBe("/Roster/RowA/Name")
	end)

	it("touch long-press presents the plate immediately", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA/Name")
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.source).toBe("touch")
		expect(d.text).toBe(LONG_NAME)
	end)

	it("the plate appears identically under reduced motion (nothing about it moves)", function()
		local _, env, adapter, _, pres = makeWorld()
		env:set("reducedMotion", true)
		pres.present(roster({ row("RowA", LONG_NAME) }))
		expect(pres.disclosure().present).toBe(true)
		expect(adapter.node(PLATE_LABEL).props.text).toBe(LONG_NAME)
	end)

	it("a plate never appears for text that is not truncated", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(roster({ row("RowA", "Bo") }), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA")
		expect(pres.disclosure().present).toBe(false)
		pres._discloseHover("/Roster/RowA")
		pres.tick(1)
		expect(pres.disclosure().present).toBe(false)
	end)

	it("a plate never appears for truncated text that did not declare disclose", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME, false) }), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA")
		expect(pres.disclosure().present).toBe(false)
		pres._discloseHover("/Roster/RowA")
		pres.tick(1)
		expect(pres.disclosure().present).toBe(false)
	end)

	it("ticking with nothing engaged never presents a plate", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		for _ = 1, 20 do
			pres.tick(1)
		end
		expect(pres.disclosure().present).toBe(false)
	end)
end)

describe("LTN-4 disclosure: at most one plate, and it leaves when engagement does", function()
	local function twoRows(): any
		return roster({ row("RowA", LONG_NAME), row("RowB", LONG_NAME .. "ZZ") })
	end

	it("hovering a second disclosed label replaces the first plate rather than stacking", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(twoRows(), NO_FOCUS)
		pres._discloseHover("/Roster/RowA")
		pres.tick(0.5)
		expect(pres.disclosure().sourcePath).toBe("/Roster/RowA/Name")
		pres._discloseHover("/Roster/RowB")
		-- the old answer retires the moment the pointer leaves it; the new one
		-- still has to earn its dwell
		expect(pres.disclosure().present).toBe(false)
		pres.tick(0.5)
		expect(pres.disclosure().sourcePath).toBe("/Roster/RowB/Name")
		-- ONE plate: the layer is mounted once, so there is exactly one label node
		expect(adapter.node(PLATE_LABEL).props.text).toBe(LONG_NAME .. "ZZ")
	end)

	it("a refresh under a live pointer plate never swaps it for the focused row's", function()
		-- focus is re-synced on EVERY refresh; if focus could preempt a direct
		-- engagement, one frame of housekeeping would swap the reader's answer out
		-- from under them (and remount an identical plate on the same-label case)
		local _, _, _, _, pres = makeWorld()
		pres.present(twoRows()) -- focus lands on RowA
		expect(pres.disclosure().sourcePath).toBe("/Roster/RowA/Name")
		pres._discloseHover("/Roster/RowB")
		pres.tick(0.5)
		expect(pres.disclosure().source).toBe("pointer")
		expect(pres.disclosure().sourcePath).toBe("/Roster/RowB/Name")
		pres.refresh()
		expect(pres.disclosure().source).toBe("pointer")
		expect(pres.disclosure().sourcePath).toBe("/Roster/RowB/Name")
		-- ...and the pointer that raised it is the one that takes it down
		pres._discloseHover(nil)
		expect(pres.disclosure().present).toBe(false)
	end)

	it("the same label engaged twice keeps one plate rather than remounting it", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(twoRows()) -- focus-sourced plate on RowA
		expect(pres.disclosure().source).toBe("focus")
		local before = adapter.liveCount()
		pres._discloseLongPress("/Roster/RowA") -- the same question, another way
		expect(pres.disclosure().source).toBe("focus") -- first engagement still owns it
		expect(pres.disclosure().sourcePath).toBe("/Roster/RowA/Name")
		expect(adapter.liveCount()).toBe(before)
	end)

	it("pointer leave removes the plate", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(twoRows(), NO_FOCUS)
		pres._discloseHover("/Roster/RowA")
		pres.tick(0.5)
		expect(pres.disclosure().present).toBe(true)
		pres._discloseHover(nil)
		expect(pres.disclosure().present).toBe(false)
	end)

	it("long-press release removes the plate", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(twoRows(), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA")
		expect(pres.disclosure().present).toBe(true)
		pres._discloseLongPress(nil)
		expect(pres.disclosure().present).toBe(false)
	end)

	it("focus moving off the label removes the plate", function()
		local _, _, _, system, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME), UI.Button({ id = "Other", label = "Other" }) }))
		expect(pres.disclosure().source).toBe("focus")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Roster/Other")
		expect(pres.disclosure().present).toBe(false)
	end)

	it("a tap anywhere removes the plate", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(twoRows(), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA")
		expect(pres.disclosure().present).toBe(true)
		adapter.tap("/Roster/RowB")
		expect(pres.disclosure().present).toBe(false)
	end)

	it("dismissing the surface removes the plate", function()
		local _, _, adapter, _, pres = makeWorld()
		local handle = pres.present(twoRows(), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA")
		expect(pres.disclosure().present).toBe(true)
		pres.dismiss(handle)
		expect(pres.disclosure().present).toBe(false)
		expect(adapter.node(PLATE_LABEL)).toBeNil()
	end)

	it("unmounting the source node removes the plate on the next refresh", function()
		local core, _, _, _, pres = makeWorld()
		local showRow = core:signal(true)
		pres.present(
			roster({
				UI.When({
					id = "Gate",
					condition = showRow,
					thenView = function()
						return row("RowA", LONG_NAME)
					end,
				}),
			}),
			NO_FOCUS
		)
		pres._discloseLongPress("/Roster/Gate/then/RowA")
		expect(pres.disclosure().present).toBe(true)
		showRow:set(false)
		pres.refresh()
		expect(pres.disclosure().present).toBe(false)
	end)

	it("a re-solve that makes room for the label removes the plate", function()
		local core, _, _, _, pres = makeWorld()
		local name = core:signal(LONG_NAME)
		pres.present(roster({ row("RowA", name) }), NO_FOCUS)
		pres._discloseLongPress("/Roster/RowA")
		expect(pres.disclosure().present).toBe(true)
		name:set("Bo") -- it fits now: there is no debt left to pay
		pres.refresh()
		expect(pres.disclosure().present).toBe(false)
	end)
end)

describe("LTN-4 disclosure: the plate is presentation chrome, never a surface", function()
	it("the plate is outside every focus order and mounts nothing focusable", function()
		local _, _, adapter, _, pres = makeWorld()
		local handle = pres.present(roster({ row("RowA", LONG_NAME), UI.Button({ id = "Other", label = "Other" }) }))
		expect(pres.disclosure().present).toBe(true)
		-- not a presented surface: it pushes no focus scope and no input context
		expect(pres.depth()).toBe(1)
		for _, entry in handle.focusOrder().traversal do
			expect(string.find(entry.path, "__disclose__", 1, true)).toBeNil()
		end
		-- ...and there is nothing in it that COULD be focused
		for _, path in adapter.paths() do
			if string.find(path, "__disclose__", 1, true) ~= nil then
				local class = adapter.node(path).class
				expect(class == "Button" or class == "Toggle" or class == "TextField").toBe(false)
			end
		end
		-- Tab/arrow traversal walks the surface's own ring and never reaches it
		expect(pres.focus.focused:get()).toBe("/Roster/RowA")
	end)

	it("the plate paints above its owner and wears the theme's raised surface", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(roster({ row("RowA", LONG_NAME) }))
		local owner = adapter.rootDisplayOrder("Roster") :: number
		local plate = adapter.rootDisplayOrder("__disclose__") :: number
		expect(plate > owner).toBe(true)
		expect(adapter.node(PLATE).props.surface).toBe("raised")
	end)

	it("the plate is clamped into the safe viewport", function()
		local _, env, adapter, _, pres = makeWorld()
		env:set("coreSafeInsets", { top = 40, bottom = 34, left = 0, right = 0 })
		-- a label at the far right/bottom of a narrow screen: the plate may not run
		-- off the edge, and it may not sit under the inset
		pres.present(roster({
			UI.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }),
			row("RowA", LONG_NAME),
		}))
		expect(pres.disclosure().present).toBe(true)
		local r = adapter.node(PLATE).rect
		expect(r.x >= 0).toBe(true)
		expect(r.x + r.w <= 390).toBe(true)
		expect(r.y >= 40).toBe(true)
		expect(r.y + r.h <= 844 - 34).toBe(true)
	end)

	it("the clamp FOLLOWS a live plate — geometry that changes after mount re-places it", function()
		--[[ Found LIVE 2026-08-04 (RascalRally): a card caption's plate hung off
			the BOTTOM of the screen. On the live adapter the plate's text measure
			lands ASYNCHRONOUSLY, so a clamp computed once at mount used the
			placeholder height, chose "below fits", and the grown plate ran off the
			edge — while every synchronous headless witness stayed green. The clamp
			now re-runs on the presenter tick; this drives the same follow path by
			moving the box out from under a live plate and demands the plate is
			back inside on the next frame. ]]
		local _, env, adapter, _, pres = makeWorld()
		pres.present(roster({
			UI.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }),
			row("RowA", LONG_NAME),
		}))
		expect(pres.disclosure().present).toBe(true)
		local before = adapter.node(PLATE).rect
		expect(before.y + before.h <= 844).toBe(true)
		-- the world shrinks under the live plate (the same class of after-mount
		-- geometry change as a late text measure growing the plate)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 500 })
		pres.refresh()
		pres.tick(1 / 60)
		expect(pres.disclosure().present).toBe(true)
		local after = adapter.node(PLATE).rect
		expect(`inside={after.y >= 0 and after.y + after.h <= 500}`).toBe("inside=true")
	end)
end)

describe("LTN-4 disclosure: the live engagement wiring (renderer -> adapter zones)", function()
	-- the fake adapter grows the OPTIONAL capability for exactly this describe,
	-- so the renderer's wiring decisions are observable: which nodes got zones,
	-- and with which halves (pointer/touch) present
	local function wiredWorld(interaction: any?)
		local core, env, adapter, system, pres = makeWorld()
		if interaction ~= nil then
			env:set("capabilities", interaction.capabilities)
			env:set("preferredInput", interaction.preferredInput)
		end
		local zones: { [string]: any } = {}
		(adapter :: any).enableDisclosure = function(handle: any, callbacks: any)
			zones[handle.path] = callbacks
		end
		return core, env, adapter, system, pres, zones
	end

	it("a disclose Text gets a zone; ordinary text and controls get none", function()
		local _, _, _, _, pres, zones = wiredWorld()
		pres.present(
			roster({
				row("RowA", LONG_NAME),
				UI.Text({ id = "Plain", text = LONG_NAME, textSize = 16 }),
			}),
			NO_FOCUS
		)
		expect(zones["/Roster/RowA/Name"] ~= nil).toBe(true)
		expect(zones["/Roster/Plain"]).toBeNil()
		expect(zones["/Roster/RowA"]).toBeNil()
	end)

	it("a pointer world wires hover; a pure-touch world wires long-press instead", function()
		local _, _, _, _, presPointer, pointerZones = wiredWorld({
			capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
			preferredInput = "KeyboardAndMouse",
		})
		presPointer.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		local z = pointerZones["/Roster/RowA/Name"]
		expect(z ~= nil).toBe(true)
		expect(z.hover ~= nil).toBe(true)
		expect(z.longPress).toBeNil()

		local _, _, _, _, presTouch, touchZones = wiredWorld({
			capabilities = { keyboard = false, mouse = false, touch = true, gamepad = false },
			preferredInput = "Touch",
		})
		presTouch.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		local zt = touchZones["/Roster/RowA/Name"]
		expect(zt ~= nil).toBe(true)
		expect(zt.hover).toBeNil()
		expect(zt.longPress ~= nil).toBe(true)
	end)

	it("the zone's events drive the SAME plates the seams do, end to end", function()
		local _, _, adapter, _, pres, zones = wiredWorld()
		pres.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		local z = zones["/Roster/RowA/Name"]
		z.hover(true)
		pres.tick(0.5)
		expect(pres.disclosure().present).toBe(true)
		expect(adapter.node(PLATE_LABEL).props.text).toBe(LONG_NAME)
		z.hover(false)
		expect(pres.disclosure().present).toBe(false)
	end)
end)

describe("LT-G1: a Toggle's one-line label discloses its full value", function()
	local LONG_LABEL = "Geschwindigkeitsbegrenzungsanzeige aktivieren und merken"

	it("a truncated disclosing Toggle presents its LABEL through the same plate a Text does", function()
		local core, _, adapter, _, pres = makeWorld()
		pres.present(
			UI.Screen({
				id = "Roster",
				children = {
					UI.VStack({
						id = "Narrow",
						width = { type = "fixed", px = 160 },
						children = {
							UI.Toggle({ id = "Music", label = LONG_LABEL, value = core:signal(false), disclose = true }),
						},
					}),
				},
			}),
			NO_FOCUS
		)
		pres._discloseLongPress("/Roster/Narrow/Music")
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.text).toBe(LONG_LABEL)
		expect(adapter.node(PLATE_LABEL).props.text).toBe(LONG_LABEL)
		pres._discloseLongPress(nil)
		expect(pres.disclosure().present).toBe(false)
	end)

	it("an UNdisclosed Toggle stays plate-less — the declaration is the permission", function()
		local core, _, _, _, pres = makeWorld()
		pres.present(
			UI.Screen({
				id = "Roster",
				children = {
					UI.VStack({
						id = "Narrow",
						width = { type = "fixed", px = 160 },
						children = {
							UI.Toggle({ id = "Music", label = LONG_LABEL, value = core:signal(false) }),
						},
					}),
				},
			}),
			NO_FOCUS
		)
		pres._discloseLongPress("/Roster/Narrow/Music")
		expect(pres.disclosure().present).toBe(false)
	end)
end)

describe("fresh-review closures: the plate answers for the label as it IS", function()
	it(
		"a HIDDEN ViewThatFits candidate discloses nothing — its plate would show text that is not on screen",
		function()
			-- architecture review F-1: a losing candidate keeps its mount, rects and
			-- textFacts; only visibility knows it does not paint
			local core, _, _, _, pres = makeWorld()
			local screen = UI.Screen({
				id = "Roster",
				children = {
					UI.Button({
						id = "Row",
						label = "",
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 44 },
						children = {
							UI.ViewThatFits({
								id = "VTF",
								children = {
									UI.VStack({
										id = "Rich",
										width = { type = "fixed", px = 400 },
										children = { UI.Text({ id = "Long", text = LONG_NAME, disclose = true }) },
									}),
									UI.VStack({
										id = "Short",
										children = { UI.Text({ id = "Bo", text = "Bo" }) },
									}),
								},
							}),
						},
					}),
				},
			})
			local handle = pres.present(screen) -- focus lands on Row
			expect(handle.controller.hiddenRoots()["/Roster/Row/VTF/Rich"]).toBe(true)
			expect(pres.disclosure().present).toBe(false)
			-- the NEGATIVE CONTROL: the same shape with the rich candidate winning
			-- (enough width) must disclose — proving the gate is visibility, not
			-- some broader refusal
			local core2, _, _, _, pres2 = makeWorld()
			local wide = UI.Screen({
				id = "Roster",
				children = {
					UI.Button({
						id = "Row",
						label = "",
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 44 },
						children = { UI.Text({ id = "Name", text = LONG_NAME, disclose = true }) },
					}),
				},
			})
			pres2.present(wide)
			expect(pres2.disclosure().present).toBe(true)
		end
	)

	it("the pointer dwell RE-ASKS at expiry: a re-solve that made room presents nothing", function()
		-- architecture review F-2: the hover-time snapshot must never present
		local core, _, _, _, pres = makeWorld()
		local name = core:signal(LONG_NAME)
		pres.present(roster({ row("RowA", name) }), NO_FOCUS)
		pres._discloseHover("/Roster/RowA")
		pres.tick(0.2)
		name:set("Bo") -- it fits now; the debt is gone mid-dwell
		pres.refresh()
		pres.tick(0.4) -- dwell expires AFTER the room was made
		expect(pres.disclosure().present).toBe(false)
	end)

	it("...and a value that changed during the dwell discloses the CURRENT string, not the snapshot", function()
		local core, _, adapter, _, pres = makeWorld()
		local name = core:signal(LONG_NAME .. "-OLD")
		pres.present(roster({ row("RowA", name) }), NO_FOCUS)
		pres._discloseHover("/Roster/RowA")
		pres.tick(0.2)
		name:set(LONG_NAME .. "-NEW")
		pres.refresh()
		pres.tick(0.4)
		expect(pres.disclosure().present).toBe(true)
		expect(pres.disclosure().text).toBe(LONG_NAME .. "-NEW")
		expect(adapter.node(PLATE_LABEL).props.text).toBe(LONG_NAME .. "-NEW")
	end)

	it("a touch class arriving MID-SESSION retrofits the long-press half onto mounted labels", function()
		-- architecture review F-5: long-press is the ONLY full-value path on
		-- touch; the zone wiring must follow the live capability, not the
		-- mount-time snapshot
		local core, env, adapter, _, pres = makeWorld()
		env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
		env:set("preferredInput", "KeyboardAndMouse")
		pres.present(roster({ row("RowA", LONG_NAME) }), NO_FOCUS)
		local zone = adapter.node("/Roster/RowA/Name").discloseZone
		expect(zone ~= nil).toBe(true)
		expect(zone.hover ~= nil).toBe(true)
		expect(zone.longPress).toBeNil() -- no touch yet
		-- the hybrid gains a touch class (first tap on a touchscreen laptop)
		env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
		local after = adapter.node("/Roster/RowA/Name").discloseZone
		expect(after.longPress ~= nil).toBe(true)
		expect(after.hover ~= nil).toBe(true) -- the first half undisturbed
		-- and the retrofitted half drives the same plates end to end
		after.longPress(true)
		expect(pres.disclosure().present).toBe(true)
		after.longPress(false)
		expect(pres.disclosure().present).toBe(false)
	end)
end)
