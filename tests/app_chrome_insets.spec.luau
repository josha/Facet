--!strict
--[[ THE HOST'S OWN RESERVED BAND IS A SEPARATE FACT FROM THE DEVICE SAFE AREA,
	AND A MODAL HONOURS ONLY THE DEVICE (owner ruling, 2026-09-13).

	ONE FACT CARRIED TWO MEANINGS. `coreSafeInsets` is the platform's reservation —
	the notch, the CoreGui topbar — and it was also the only vocabulary a HOST APP
	had for a band of its own: the showcase folded its demo/settings chip row into
	`coreSafeInsets.top` and every surface below it was laid out clear of both. That
	is right for CONTENT and wrong for a MODAL. An alert is not part of the host's
	page; it takes the screen. Folded into one fact, the showcase's alerts centred
	in the space BELOW the chip row — visibly high-shouldered against a backdrop
	that covers the whole window.

	So the fact is split. `coreSafeInsets` means the device safe area again, and
	`appChromeInsets` is the app's own reservation — the four-edge bounding box of
	what the host draws over its own content, the sibling of `appChromeRects`
	(which says WHERE that chrome is, for per-column exclusions; this says HOW MUCH
	content must clear). Content policies compose the two; a modal reserves the
	device's edges and nothing else.

	WHAT THIS FILE PINS, and why each case is here:
	  · the composition, on a base screen (device + host, additively)
	  · the REFUSAL, on a modal presented into the same environment
	  · the Alert card's centre, which is the defect the ruling came from
	  · the control: a host that declares nothing moves nothing, which is what
	    makes this split invisible to every consumer that never sets the fact
	  · the fact is LIVE on a content surface and inert on a modal (the geometry
	    key list is the other half of "honours" — a surface deaf to the fact would
	    pass every static case above and never re-solve on a device)
	  · the showcase host writes the new fact and no longer writes the old one
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
local geometry_facts = require("../src/render/geometry_facts")

local VIEWPORT = { x = 0, y = 0, w = 390, h = 844 }
-- `world.new`'s `safeInsets` writes `coreSafeInsets`, the CoreGui reservation —
-- NOT the notch fact `deviceSafeInsets` beside it. Named for the fact it is, so
-- the "device safe area" the ruling is about (the per-edge MAX of the two) is
-- never confused with one half of it; the notch case below drives the other.
local CORE = { top = 36, bottom = 0, left = 0, right = 0 }
local HOST = { top = 80, bottom = 0, left = 0, right = 0 }

local function page(id: string): any
	return UI.Screen({
		id = id,
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {},
	})
end

-- one world, one base screen and one modal presented into it, so both readings
-- come from the SAME environment: a case that built two worlds could differ for
-- a reason no consumer would ever hit
local function bothRects(o: any): (any, any)
	local w = world.new(o)
	w.present(page("Page"))
	local modal = w.pres.presentModal(page("Sheet"))
	w.settle(2)
	local base = w.adapter.node("/Page").rect
	local sheet = w.adapter.node("/Sheet").rect
	w.pres.dismiss(modal)
	return base, sheet
end

local function rectStr(r: any): string
	return `{r.x},{r.y} {r.w}x{r.h}`
end

describe("appChromeInsets: the host's band is content's, never a modal's", function()
	it("a base screen clears the device safe area AND the host's band", function()
		local base = bothRects({
			viewport = VIEWPORT,
			safeInsets = CORE,
			env = { appChromeInsets = HOST },
		})
		-- 36 of platform + 80 of host, which is exactly what the one folded fact
		-- used to say in a single number
		expect(rectStr(base)).toBe(`0,116 390x{844 - 116}`)
	end)

	it("a modal presented into that same host spans the DEVICE safe area alone", function()
		local _, sheet = bothRects({
			viewport = VIEWPORT,
			safeInsets = CORE,
			env = { appChromeInsets = HOST },
		})
		expect(rectStr(sheet)).toBe(`0,36 390x{844 - 36}`)
	end)

	it("the device's own edges still apply to both — the split took nothing away", function()
		local device = { top = 36, bottom = 21, left = 12, right = 12 }
		local base, sheet = bothRects({
			viewport = VIEWPORT,
			safeInsets = device,
			env = { appChromeInsets = HOST },
		})
		expect(rectStr(sheet)).toBe(`12,36 {390 - 24}x{844 - 36 - 21}`)
		-- ...and the host's band composes ON TOP of them rather than replacing any
		expect(rectStr(base)).toBe(`12,116 {390 - 24}x{844 - 116 - 21}`)
	end)

	it("CONTROL: a host that declares no band leaves a modal and a screen identical", function()
		local base, sheet = bothRects({ viewport = VIEWPORT, safeInsets = CORE })
		expect(rectStr(base)).toBe(rectStr(sheet))
		expect(rectStr(base)).toBe(`0,36 390x{844 - 36}`)
	end)

	it("the Alert card centres on the whole screen, not on the space under the host's chrome", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1280, h = 800 },
			env = { appChromeInsets = { top = 80, bottom = 0, left = 0, right = 0 } },
		})
		local alert = Facet.Controls.Alert(w.core, {
			id = "Confirm",
			title = "Start the race?",
			message = "Everyone is waiting.",
			actions = {
				{ id = "Go", label = "Start", onActivate = function() end },
				{ id = "Cancel", label = "Cancel", role = "cancel", onActivate = function() end },
			},
		})
		w.present(page("Page"))
		alert.present(w.pres)
		w.settle(4)
		local card = w.adapter.node("/Confirm/Center/Card").rect
		-- the viewport's own centre, to the pixel: 400, NOT 440 (the centre of what
		-- is left under an 80px host band)
		expect(math.abs(card.y + card.h / 2 - 400) < 1).toBe(true)
		expect(math.abs(card.x + card.w / 2 - 640) < 1).toBe(true)
		alert.dispose()
	end)

	it("a modal under `deviceSafeContent` clears the notch and not the band", function()
		--[[ THE TWO HALVES OF "THE DEVICE SAFE AREA", DRIVEN SEPARATELY. Every case
			above moves `coreSafeInsets` only, which cannot tell "a modal reserves the
			device safe area" from "a modal reserves `coreSafeInsets`". A notch is the
			other half and it reaches a surface through the OTHER policy. ]]
		local w = world.new({
			viewport = VIEWPORT,
			safeInsets = CORE,
			env = {
				deviceSafeInsets = { top = 59, bottom = 34, left = 0, right = 0 },
				appChromeInsets = HOST,
			},
		})
		w.present(page("Page"))
		local modal = w.pres.presentModal(page("Sheet"), { rootPolicy = "deviceSafeContent" })
		w.settle(2)
		-- max(core 36, notch 59) and the home indicator, and NOT the host's 80
		expect(rectStr(w.adapter.node("/Sheet").rect)).toBe(`0,59 390x{844 - 59 - 34}`)
		w.pres.dismiss(modal)
	end)

	it("a `presentCritical` screen takes the screen too — the host has already failed", function()
		local w = world.new({ viewport = VIEWPORT, safeInsets = CORE, env = { appChromeInsets = HOST } })
		w.present(page("Page"))
		local handle = w.pres.presentCritical(function()
			return page("Critical")
		end, {
			fallbackScreen = function()
				return page("Fallback")
			end,
		})
		w.settle(2)
		expect(rectStr(w.adapter.node("/Critical").rect)).toBe(`0,36 390x{844 - 36}`)
		w.pres.dismiss(handle)
		-- ...and so does the stand-in it presents when the factory itself throws
		local broken = w.pres.presentCritical(function()
			error("the host is gone")
		end, {
			fallbackScreen = function()
				return page("Fallback")
			end,
		})
		w.settle(2)
		expect(rectStr(w.adapter.node("/Fallback").rect)).toBe(`0,36 390x{844 - 36}`)
		w.pres.dismiss(broken)
	end)

	it("a band-riding surface takes the app's chrome as RECTS, never as this box", function()
		--[[ `bandSafeContent` exists so a surface can sit LEVEL with the platform's
			own controls; a bounding box would push it off the strip it asked for,
			which is the defect `appChromeRects` was added to remove. It is exempt
			here and consumes the same declaration through `platformChrome.rects`. ]]
		local w = world.new({ viewport = VIEWPORT, safeInsets = CORE, env = { appChromeInsets = HOST } })
		local handle = w.pres.present(page("Hud"), { rootPolicy = "bandSafeContent" })
		w.settle(2)
		expect(rectStr(w.adapter.node("/Hud").rect)).toBe(`8,36 {390 - 16}x{844 - 36 - 8}`)
		w.pres.dismiss(handle)
	end)

	it("the fact is LIVE for content and inert for a modal", function()
		local w = world.new({ viewport = VIEWPORT, safeInsets = CORE })
		w.present(page("Page"))
		local modal = w.pres.presentModal(page("Sheet"))
		w.settle(2)
		expect(w.adapter.node("/Page").rect.y).toBe(36)
		w.env:set("appChromeInsets", HOST)
		w.settle(2)
		-- a surface that never re-solved would still read 36 here, which is the
		-- half a static fixture cannot see
		expect(w.adapter.node("/Page").rect.y).toBe(116)
		expect(w.adapter.node("/Sheet").rect.y).toBe(36)
		w.pres.dismiss(modal)
	end)
end)

--[[ A PLATE BELONGS TO THE SURFACE IT POINTS AT (review item 3).

	`safeBox` is the box every window-space thing the presenter raises is clamped
	into — an anchored popover, the disclosure plate, the help plate. It used to add
	the host's band unconditionally, so a plate raised INSIDE a modal was clamped by
	a band the modal itself does not yield to.

	THE SOURCE IS PINNED TO THE BOTTOM OF ITS OWN SURFACE, which is what makes both
	arms mean something. The plate cannot fit below it, so the placement flips
	ABOVE — and a safe box that wrongly ended 400px early would CLAMP it instead of
	flipping it. Measured with the gate removed, the modal's plate lands at y=400
	rather than 772, so this case fails when the fix is reverted rather than passing
	under every hypothesis. ]]
describe("appChromeInsets: a plate takes its OWNER surface's answer", function()
	local LONG = "Bartholomewwwwwwwwwwwwwwwwww" -- one word, far wider than a 120px cell
	local PLATE = "/__disclose__/Layer/Plate"
	local BOTTOM_BAND = { top = 0, bottom = 400, left = 0, right = 0 }

	-- a screen whose only focusable is a disclosed, truncated label held against
	-- the BOTTOM of whatever box the surface was given
	local function labelAtBottom(id: string): any
		return UI.Screen({
			id = id,
			children = {
				UI.Box({
					id = "Spacer",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				}),
				UI.Button({
					id = "Row",
					label = "",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 44 },
					children = { UI.Text({ id = "Name", text = LONG, textSize = 16, disclose = true }) },
				}),
			},
		})
	end

	-- focus lands on the row, which is one of the three disclosure engagements
	local function plateY(modal: boolean, band: boolean): number
		local w = world.new({
			viewport = VIEWPORT,
			safeInsets = CORE,
			env = if band then { appChromeInsets = BOTTOM_BAND } else nil,
		})
		if modal then
			w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "B", label = "b" }) } }))
			w.pres.presentModal(labelAtBottom("Sheet"))
		else
			w.present(labelAtBottom("Sheet"))
		end
		w.settle(3)
		expect(w.pres.disclosure().present).toBe(true)
		return w.adapter.node(PLATE).rect.y
	end

	it("a plate raised inside a modal is clamped as if the host had no band", function()
		expect(plateY(true, true)).toBe(plateY(true, false))
		expect(plateY(true, true)).toBe(772)
	end)

	it("...and the same plate on a content screen yields the band", function()
		-- the content surface's own box ends 400px early, so both the label it
		-- points at and the box it is clamped into move with it
		expect(plateY(false, true)).toBe(372)
		expect(plateY(false, false)).toBe(772)
	end)
end)

describe("appChromeInsets: the geometry-key half of honouring it", function()
	local function has(list: { string }, key: string): boolean
		return table.find(list, key) ~= nil
	end

	it("the content policies consume it; the two narrowed policies do not", function()
		expect(has(geometry_facts.keysFor("coreSafeContent"), "appChromeInsets")).toBe(true)
		expect(has(geometry_facts.keysFor("deviceSafeContent"), "appChromeInsets")).toBe(true)
		-- a decoration layer is defined not to be inset at all, and a band-riding
		-- surface consumes the app's chrome through `platformChrome`'s rects
		expect(has(geometry_facts.keysFor("edgeToEdge"), "appChromeInsets")).toBe(false)
		expect(has(geometry_facts.keysFor("bandSafeContent"), "appChromeInsets")).toBe(false)
	end)

	it("a host that declares nothing gets its own inset table back, unallocated", function()
		--[[ THE DEFAULT IS A TABLE OF FOUR ZEROES, so a composition that allocated
			unconditionally allocated on every content solve of every surface in every
			session that never had a host band. Identity is the observable form of
			"nothing moved": pinned here rather than left to a reviewer's eye. ]]
		local insets = { top = 12, bottom = 0, left = 0, right = 0 }
		expect(geometry_facts.withAppChrome(insets, "coreSafeContent", { top = 0, bottom = 0, left = 0, right = 0 })).toBe(
			insets
		)
		expect(geometry_facts.withAppChrome(insets, "coreSafeContent", nil)).toBe(insets)
		-- a negative or a NaN edge reserves nothing, and takes the same path
		expect(geometry_facts.withAppChrome(insets, "coreSafeContent", { top = -40, bottom = 0 / 0 })).toBe(insets)
		-- ...and a real band is a NEW table, never a write into the caller's
		local grown = geometry_facts.withAppChrome(insets, "coreSafeContent", { top = 80 })
		expect(grown).never().toBe(insets)
		expect(`{grown.top}|{insets.top}`).toBe("92|12")
		-- one NaN edge cannot poison the three real ones
		local mixed = geometry_facts.withAppChrome(insets, "coreSafeContent", { top = 0 / 0, bottom = 10 })
		expect(`{mixed.top}|{mixed.bottom}`).toBe("12|10")
	end)

	it("a surface that does not reserve the host's chrome is not woken by it", function()
		expect(has(geometry_facts.keysFor("coreSafeContent", false), "appChromeInsets")).toBe(false)
		-- ...and the rest of the list is untouched by that narrowing
		expect(has(geometry_facts.keysFor("coreSafeContent", false), "coreSafeInsets")).toBe(true)
		expect(has(geometry_facts.keysFor("coreSafeContent", true), "appChromeInsets")).toBe(true)
	end)
end)

describe("the showcase host declares its chip row as its OWN reservation", function()
	local SOURCE = "examples/gallery/client/init.client.luau"

	it("it writes the host fact and no longer writes the platform's", function()
		local source = fs.readFile(SOURCE)
		expect(string.find(source, 'env:set("appChromeInsets"', 1, true) ~= nil).toBe(true)
		-- the adapter is the only author of `coreSafeInsets` again — the whole
		-- four-edge carry-through trap the old write needed goes with it
		expect(string.find(source, 'env:set("coreSafeInsets"', 1, true)).toBe(nil)
	end)
end)
