--!strict
--[[ A CONTROL'S TEXT SITS ON ITS BOX CENTRE (user feedback item 9, 2026-09-12:
	"in Pixel Quest the text is not vertically centred in the Advanced button, or in
	the three popup rows Performance / Balanced / Fidelity").

	THE MEASUREMENT, AND WHY IT IS THE RIGHT ONE. A Facet stack aligns its line to
	`start` unless its author says otherwise, and `render/layout_node`'s icon block
	GROWS an icon-hinted Text node to the installed package's `iconSizes` square —
	a picture, not a line of type. So a control row holding a glyph and a word is as
	tall as the PICTURE while the word keeps its line box, and the word rides at the
	top of the line. Measured on the eight shipped packages at
	`preferredTextOffset = 0` before the fix, as `label centre - box centre`:

	    pixel_quest        -6.0   (32px glyph, 20px control line)
	    fantasy_ornate     -4.5   (32 / 23)
	    glossy_touch       -2.5   (28 / 23)
	    classic_desktop    -2.5   (20 / 15)
	    fantasy_parchment  -1.5   (row only)
	    glossy_mobile      -2.0   (row only)
	    scifi_hud          -0.5   (row only)
	    compact_pointer     0.0

	— on BOTH shapes the report names: `DisclosureGroup`'s "Advanced" header (a
	`UI.Button` holding a caret and a label) and the picker menu's popup rows.
	Nothing a theme declared moved that text: every shipped package's `control`
	`contentInsets` are symmetric top-to-bottom, and `chrome_slots.spendInset`
	hands a side back only in PAIRS. The framework's own reservation moved it.

	THREE SHAPES, THREE SEAMS, because a Button draws its text in three different
	places and only one of them is a node in the solved tree:

	  1. A LABEL-ONLY BUTTON mounts no text node at all — the engine draws the
	     label, and under a skinned package `screen_chrome` LIFTS it into a box
	     `chrome_slots.liftGeometry` computes from the recipe's own
	     `contentInsets`. That box's centre against the host's is
	     `(top - bottom) / 2` at every host height, so the package's insets ARE the
	     measurement. Asserted through `liftGeometry` itself rather than re-derived,
	     and with a negative control that makes it bite.
	  2. AN ICON + LABEL BUTTON puts its text in a child node, which is where the
	     defect lives; measured off the solved rects.
	  3. A MENU ROW is the same shape one container deeper — the row's content
	     `HStack` inside the row Button — which is why the rule is bounded by the
	     CONTROL and not by the Button's own content stack.

	AND THE BOUND IS PINNED TOO. The library-wide default is still `start`: the
	last case builds the identical mixed-height line OUTSIDE a Button and requires
	it to stay top-aligned, so "the framework centres everything now" fails here
	rather than in a consumer's layout.

	TOLERANCE IS 1px AND IT IS NOT SLACK: `placement.alignOffset` floors the half,
	so an odd difference between the glyph box and the line box lands the text half
	a pixel high by construction. Anything larger is a real miss. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local lt = require("./lib/large_text")
local snapshot = require("../src/themes/snapshot")
local chrome_slots = require("../src/tokens/chrome_slots")

local UI = Facet.UI

-- every package the library ships as a reference, in the order `theme_sweep`
-- and `chrome_inset_yield` already name them
local PACKAGES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}
local OFFSETS = { 0, 4, 10, 14 }
local PHONE = { x = 0, y = 0, w = 390, h = 844 }
local TOLERANCE = 1

local built: { [string]: any } = {}
local function packageOf(name: string): any
	if built[name] == nil then
		built[name] = (require)(`../examples/themes/{name}`).build(Facet.themes)
	end
	return built[name]
end

local snaps: { [string]: any } = {}
local function metricsOf(name: string): any
	if snaps[name] == nil then
		snaps[name] = snapshot.resolve(packageOf(name), nil, {})
	end
	return snaps[name]
end

local function centreY(rect: any): number
	return rect.y + rect.h / 2
end

-- `label centre - box centre`, rounded to the tenth so the message reads as a
-- number rather than as a float tail
local function offsetOf(box: any, label: any): number
	return math.floor((centreY(label) - centreY(box)) * 10 + 0.5) / 10
end

local function centred(label: string, box: any, text: any)
	local delta = offsetOf(box, text)
	expect(`{label} text on the box centre: {math.abs(delta) <= TOLERANCE} (off by {delta}px)`).toBe(
		`{label} text on the box centre: true (off by {delta}px)`
	)
end

--[[ ONE WORLD PER (package, preference), holding all three shapes plus the
	bound's negative control. One mount rather than four keeps every case measured
	under the same solve, which is what makes the four numbers comparable. ]]
local function world(name: string, offset: number)
	local w = lt.world({ viewport = PHONE, offset = offset, theme = { id = name, metrics = metricsOf(name) } })
	local disclosure = Facet.Controls.DisclosureGroup(w.core, {
		id = "Advanced",
		label = "Advanced",
		expanded = w.core:signal(false),
		content = function()
			return UI.Text({ id = "Body", text = "body" })
		end,
	})
	local picker = Facet.Controls.Picker(w.core, {
		id = "Quality",
		label = "Quality",
		selected = w.core:signal("b"),
		options = {
			{ value = "a", label = "Performance" },
			{ value = "b", label = "Balanced" },
			{ value = "c", label = "Fidelity" },
		},
	})
	-- THE TALL MARK IS A `Box`, NOT AN ICON, in both the Button case and its
	-- negative control: the two arms must differ in exactly ONE way (inside a
	-- control or not), and an icon-hinted Text is reserved at a size that varies
	-- per package, which would make them differ in two.
	local function mark()
		return UI.Box({ id = "Mark", width = { type = "fixed", px = 32 }, height = { type = "fixed", px = 32 } })
	end
	local function word()
		return UI.Text({ id = "Word", text = "Advanced" })
	end
	w.present(UI.Screen({
		id = "S",
		padding = "m",
		children = {
			UI.VStack({
				id = "V",
				width = UI.fill(),
				gap = "m",
				children = {
					UI.Button({ id = "Plain", label = "Advanced", width = UI.fill() }),
					UI.Button({ id = "Iconed", label = "Advanced", width = UI.fill(), children = { mark(), word() } }),
					UI.HStack({ id = "Loose", width = UI.fill(), children = { mark(), word() } }),
					disclosure.blueprint,
					picker.blueprint,
				},
			}),
		},
	}))
	w.pres.refresh()
	return w, picker, disclosure
end

describe("Button text centring: three control shapes x eight packages x four preferences", function()
	it("an icon + label Button centres its label on its box, in every package at every preference", function()
		local cells = 0
		for _, name in PACKAGES do
			for _, offset in OFFSETS do
				local label = `[{name} +{offset}]`
				local w, picker, disclosure = world(name, offset)
				cells += 1
				centred(
					`{label} icon+label Button`,
					w.adapter.node("/S/V/Iconed").rect,
					w.adapter.node("/S/V/Iconed/Word").rect
				)
				-- ...and the SHIPPED one the report named: DisclosureGroup's header is
				-- a `UI.Button` holding a caret glyph beside its title
				local header = w.adapter.node("/S/V/Advanced/Header")
				local title = w.adapter.node("/S/V/Advanced/Header/Label")
				expect(`{label} the disclosure header and its title are mounted: {header ~= nil and title ~= nil}`).toBe(
					`{label} the disclosure header and its title are mounted: true`
				)
				centred(`{label} "Advanced" header`, header.rect, title.rect)
				picker.dispose()
				disclosure.dispose()
				w.pres.dismiss(w.handle)
			end
		end
		expect(cells).toBe(#PACKAGES * #OFFSETS)
	end)

	it("a menu row centres its label on the row, in every package at every preference", function()
		local rows = 0
		for _, name in PACKAGES do
			for _, offset in OFFSETS do
				local label = `[{name} +{offset}]`
				local w, picker, disclosure = world(name, offset)
				picker.api.open()
				w.pres.refresh()
				w.pres.refresh() -- the measured list budget lands one solve later
				local seen = 0
				for _, path in w.adapter.paths() do
					if string.match(path, "/Opt%-%w+$") == nil then
						continue
					end
					local row = w.adapter.node(path)
					if row == nil or row.class ~= "Button" then
						continue
					end
					local textPath: string? = nil
					for _, inner in w.adapter.paths() do
						if string.sub(inner, 1, #path + 1) == path .. "/" and string.sub(inner, -6) == "/Label" then
							textPath = inner
						end
					end
					expect(`{label} {path} has a label node: {textPath ~= nil}`).toBe(
						`{label} {path} has a label node: true`
					)
					centred(`{label} menu row {path}`, row.rect, w.adapter.node(textPath :: string).rect)
					seen += 1
					rows += 1
				end
				expect(`{label} three option rows measured: {seen}`).toBe(`{label} three option rows measured: 3`)
				picker.dispose()
				disclosure.dispose()
				w.pres.dismiss(w.handle)
			end
		end
		expect(rows).toBe(#PACKAGES * #OFFSETS * 3)
	end)

	--[[ THE LABEL-ONLY BUTTON. There is no text node to measure — the engine draws
		the label, and a skinned package's lift replaces it with a copy inset by the
		recipe's own `contentInsets`. `liftGeometry`'s vertical centre sits
		`(top - bottom) / 2` off the host's at EVERY host height, so the shipped
		packages' own numbers are the whole claim, read through the same function the
		paint seam reads. ]]
	it("a label-only Button's drawn text is centred by every shipped package's own control recipe", function()
		local skinned = 0
		for _, name in PACKAGES do
			-- A FLAT PACKAGE SKINS NO CONTROL, so there is no lift at all and the
			-- engine centres the label in the node's own padded box. Counted rather
			-- than skipped, so "every package turned out to be flat" cannot pass this
			-- case in silence.
			local recipe = chrome_slots.planFor(packageOf(name), "control")
				or chrome_slots.layerPlanFor(packageOf(name), "control")
			if recipe ~= nil then
				skinned += 1
				local box = chrome_slots.liftGeometry(recipe)
				local delta = box.position.yOffset + box.size.yOffset / 2
				expect(`[{name}] the lifted label is centred: {math.abs(delta) <= TOLERANCE} (off by {delta}px)`).toBe(
					`[{name}] the lifted label is centred: true (off by {delta}px)`
				)
			end
			-- ...and the node that lift replaces is a Button with NO content node, so
			-- its own box is what the engine centres in — the shape this case is about
			local w = world(name, 0)
			local content = 0
			for _, path in w.adapter.paths() do
				if string.sub(path, 1, #"/S/V/Plain/") == "/S/V/Plain/" then
					content += 1
				end
			end
			expect(`[{name}] the label-only Button mounts no content node: {content}`).toBe(
				`[{name}] the label-only Button mounts no content node: 0`
			)
			w.pres.dismiss(w.handle)
		end
		expect(`skinned control recipes measured: {skinned}`).toBe("skinned control recipes measured: 5")
	end)

	it("NEGATIVE CONTROL: an asymmetric control recipe is caught, and a loose row still starts", function()
		--[[ THE LIFT PIN BITES. A package whose `control` frame reaches 16px from the
			top and 4px from the bottom puts the drawn label 6px above the box centre,
			and the case above must say so. Built through the public compiler, so it is
			a package a theme author could really ship. ]]
		local skewed, report = Facet.themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "skewed-control",
				displayName = "Skewed Control",
				schemaVersion = Facet.themes.SCHEMA,
				version = "1.0.0",
			},
			assets = {
				plate = {
					content = "rbxassetid://1",
					sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
					sliceScale = 1,
					preload = "install",
				},
			},
			chrome = {
				control = {
					kind = "nineSlice",
					asset = "plate",
					fallback = "native",
					contentInsets = { top = 16, right = 8, bottom = 4, left = 8 },
				},
			},
		})
		expect(`the skewed package compiles: {report.ok}`).toBe("the skewed package compiles: true")
		local box = chrome_slots.liftGeometry(chrome_slots.planFor(skewed, "control"))
		local delta = box.position.yOffset + box.size.yOffset / 2
		expect(`a 16/4 control frame is caught: {math.abs(delta) > TOLERANCE} (off by {delta}px)`).toBe(
			`a 16/4 control frame is caught: true (off by {delta}px)`
		)

		--[[ AND THE RULE IS BOUNDED BY THE CONTROL. The identical mixed-height line
			outside a Button keeps the library's documented `start` default, so this
			case fails the day the centring stops being a control's own affair. The two
			arms differ in ONE way — `Iconed` is a Button, `Loose` is a bare HStack —
			and both hold a 32px Box beside one line of type. ]]
		for _, name in { "pixel_quest", "glossy_touch" } do
			local w = world(name, 0)
			local loose = w.adapter.node("/S/V/Loose")
			local word = w.adapter.node("/S/V/Loose/Word")
			expect(`[{name}] the loose row is taller than its word: {loose.rect.h > word.rect.h}`).toBe(
				`[{name}] the loose row is taller than its word: true`
			)
			expect(`[{name}] a loose row still starts its line: {word.rect.y == loose.rect.y}`).toBe(
				`[{name}] a loose row still starts its line: true`
			)
			-- the same two boxes inside a Button, centred
			centred(
				`[{name}] the controlled row`,
				w.adapter.node("/S/V/Iconed").rect,
				w.adapter.node("/S/V/Iconed/Word").rect
			)
			w.pres.dismiss(w.handle)
		end
	end)
end)
