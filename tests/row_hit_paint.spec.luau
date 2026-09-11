--!strict
--[[ A ROW'S HIT TARGET IS NOT A CONTROL PLATE.

	WHAT WAS REPORTED. The swipe-actions gallery fixture's virtualized surface,
	under Glossy Mobile on a phone: "a crowded list that's overlapping" — every
	row a large glossy rounded card whose bottom overlapped the next card's top,
	each card's background doubled into a lighter band across its middle, and the
	row content crowded against the card's edges.

	WHAT IT ACTUALLY WAS. Nothing in the solved geometry: the rows measure
	themselves and sit back to back with no overlap at all. It was PAINT. Every
	`newVirtualList` row carries a full-bleed `Hit` — a label-less, icon-less
	`UI.Button` that exists only to give the row a focus stop, an activate and a
	pointer surface — and a `UI.Button` that declares no `surface` takes the class
	default `control` at create (`src/client/screen_target.luau`, the
	`class == "Button"` branch: `handle.nativeSurface = "control"`). So the hit
	wore the installed package's whole control recipe:

	  * the opaque `Control` fill and the `radii.control` corner, which is what
	    turned a mail row into a rounded card;
	  * the package's control GRADIENT — Glossy Mobile's gloss ramp steps hard at
	    half the node's height, which on a 52px button is a highlight and on an
	    81px row is the "doubled" band the report describes;
	  * and, whenever the row carries no selection state so
	    `chrome_slots.classify` falls through to the `control` slot, the
	    package's control SHADOW. Glossy Mobile's reaches `chromeBleed` px
	    outside the box it belongs to, and list rows are laid back to back, so
	    every row's glow painted that far into the rows above and below. That is
	    the overlap.

	The framework's own instruments already said the hit paints nothing —
	`tests/lib/overflow_guard.luau`'s `paints()` ("A TRANSPARENT HIT TARGET PAINTS
	NOTHING … a `Hit` Button carries no surface and no label and covers nothing a
	player can see") and `tools/lune/triage_overflow_waivers.luau` before it — and
	`controls/row_actions_root.luau` builds the identical full-bleed hit as a
	`UI.Grip`, which never classifies at all. The claim was true of everything
	except the two virtualized collections that build theirs as a Button.

	WHAT IS PINNED HERE, and why each half is needed:

	  1. THE PREMISE IS MEASURED, not recalled: Glossy Mobile's `control` slot
	     really does declare a shadow, its reach really is non-zero, and the
	     list's rows really are contiguous. A pin on the fix alone would keep
	     passing the day the premise stopped being true, and would then be
	     forbidding something for no reason.
	  2. A row hit that paints no selection carries NO `facet-surface-*` tag and
	     classifies into NO decoration slot — so no fill, no corner, no gradient
	     and no shadow can reach it under any package.
	  3. A SELECTABLE list is unchanged, byte for byte. A package's `Selected row`
	     rule names a colour and no transparency, and the rule that supplies the
	     transparency is the one a plain surface removes — driven live under
	     Glossy Mobile, a plain hit's styled `BackgroundTransparency` is 1 — so a
	     plain selected row would paint a colour nobody can see. The hit keeps its
	     surface for exactly as long as selection is drawn on it.
	  4. `newVirtualGrid`'s cell hit is the same node with the same job, and it
	     never carries selection at all, so it is always plain.

	ONE THING THIS FILE'S ADAPTER CANNOT SEE, stated so a reader does not conclude
	more from it than it proves: `tests/lib/fake_target.luau` drops
	`facet-interactive` for a `plain` surface, and the live adapter does not — it
	passes `nativeSurface = nil` rather than the string `"plain"`, so
	`classifyTags`'s own `suppressed` branch never fires there. Measured live
	2026-09-11: a plain row hit keeps `facet-interactive` and `facet-pointer-live`.
	The cases below assert only the `facet-surface-*` tag, which both adapters
	agree on, and which is the one the plate, the corner, the gradient and the
	shadow all hang off.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local virtual_grid = require("../src/controls/virtual_grid")
local chrome_slots = require("../src/tokens/chrome_slots")
local glossy_mobile = require("../examples/themes/glossy_mobile")

local SURFACE_CONTROL = "facet-surface-control"

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

local function listWorld(spec: any?)
	local options = spec or {}
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	local rows = w.core:signal(makeRows(20))
	local list = virtual_list.build(Facet, w.core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		viewportHeight = 400,
		overscan = 2,
		selection = options.selection,
		selectionPaint = options.selectionPaint,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
	local handle = w.pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
	w.pres.refresh()
	return w, list, handle
end

local function hasTag(adapter: any, path: string, tag: string): boolean
	for _, live in adapter.tagsOf(path) do
		if live == tag then
			return true
		end
	end
	return false
end

-- the decoration slot the renderer would classify this mounted node into: the
-- same three inputs `render/layout_node.luau` and the live adapter read.
local function slotOf(adapter: any, path: string): string?
	local node = adapter.node(path)
	assert(node ~= nil, `no mounted node at {path}`)
	local props = node.props or {}
	return chrome_slots.classify({
		class = node.class,
		surface = props.surface,
		hasSelection = props.selected ~= nil,
	})
end

describe("row hit paint: the premise the fix answers", function()
	it("Glossy Mobile's control slot declares a shadow that reaches outside its own box", function()
		local package, report = glossy_mobile.build(Facet.themes)
		assert(package ~= nil, `glossy_mobile failed its own package gate: {report and report.errors[1]}`)
		expect(chrome_slots.shadowFor(package, "control") ~= nil).toBe(true)
		local snapshot = Facet.themes.resolve(package, nil, {})
		expect(snapshot.chromeBleed > 0).toBe(true)
	end)

	it("list rows are laid back to back, so a row's chrome has nowhere to bleed but its neighbours", function()
		local w = listWorld()
		local first = w.adapter.node("/S/VL/Canvas/W/[r1]/Row").rect
		local second = w.adapter.node("/S/VL/Canvas/W/[r2]/Row").rect
		expect(second.y).toBe(first.y + first.h)
	end)
end)

describe("row hit paint: a hit target that paints no selection is plain", function()
	it("wears no package surface tag", function()
		local w = listWorld()
		expect(hasTag(w.adapter, "/S/VL/Canvas/W/[r1]/Row/Hit", SURFACE_CONTROL)).toBe(false)
	end)

	it("classifies into no decoration slot, so no package shadow can reach it", function()
		local w = listWorld()
		expect(slotOf(w.adapter, "/S/VL/Canvas/W/[r1]/Row/Hit")).toBe(nil)
	end)

	it('is plain for `selectionPaint = "none"` too — the row is not where chosen is shown', function()
		local w = listWorld({ selection = "single", selectionPaint = "none" })
		expect(hasTag(w.adapter, "/S/VL/Canvas/W/[r1]/Row/Hit", SURFACE_CONTROL)).toBe(false)
	end)

	it("a virtual grid's cell hit is the same node with the same job", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local items = w.core:signal(makeRows(40))
		local grid = virtual_grid.build(Facet, w.core, {
			id = "VG",
			items = items,
			key = function(item: any)
				return item.id
			end,
			columns = 4,
			itemExtent = 40,
			viewportExtent = 400,
			width = { type = "fixed", px = 320 },
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		w.pres.present(Facet.UI.Screen({ id = "S", children = { grid.blueprint } }))
		w.pres.refresh()
		expect(hasTag(w.adapter, "/S/VG/Canvas/Band/W/[r1]/Cell/Hit", SURFACE_CONTROL)).toBe(false)
		expect(slotOf(w.adapter, "/S/VG/Canvas/Band/W/[r1]/Cell/Hit")).toBe(nil)
	end)
end)

describe("row hit paint: a selectable row keeps the paint selection is drawn with", function()
	it("keeps its surface tag", function()
		local w = listWorld({ selection = "single" })
		expect(hasTag(w.adapter, "/S/VL/Canvas/W/[r1]/Row/Hit", SURFACE_CONTROL)).toBe(true)
	end)

	it("classifies into the selection slot, which is where a package paints a chosen row", function()
		local w = listWorld({ selection = "single" })
		expect(slotOf(w.adapter, "/S/VL/Canvas/W/[r1]/Row/Hit")).toBe("selection")
	end)
end)
