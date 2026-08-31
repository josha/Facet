--!strict
--[[ A DECORATION IS COMPENSATED FOR THE PADDING ITS HOST ACTUALLY HAS.

	THE DEFECT (director device round 2026-08-13, `cutoff.png`): "with the compact
	pointer theme, the left side of the mark read button is cutoff in the same
	table". The tray plate's left border and both left corners are gone; its right
	border is intact.

	MEASURED LIVE (Studio, Facet-Showcase, Compact Pointer, `row-actions` Table
	surface, viewport 413x735). The plate's LAYOUT rect is flush — no rect
	assertion anywhere could have caught this — and what the engine paints is not:

	    button                       UIPadding   deco offset   overhang L / R
	    /MailActions/ModeBar/ModeList      12          -12          0 /  0
	    /TablePane/TableToolbar/EditToggle 12          -12          0 /  0
	    .../RowActions-m1/Content/Row/Hit  12          -12          0 /  0
	    .../TrayLeading/Action:read (plate)  8          -12         -4 / +4

	    plate  [10.0 .. 93.0]
	    deco   [ 6.0 .. 97.0]     4px outside its own host on EVERY side
	    Body   [10.0 ..403.0]  ClipsDescendants = true

	The tray plate is the ONE button in that tree carrying an authored `padding`
	prop, and it is the only one whose decoration is off. Its left edge sits
	EXACTLY on the Table body's clip edge (10.0), so the 4px to the left is cut and
	the 4px to the right lands in the 6px `rowGutter` and survives — which is
	precisely "the left side is cut off, the right side is not".

	THE MECHANISM. `screen_target`'s `create` gives a Button a default `UIPadding`
	of `style.space.s + 4` (= 12) and ends with `syncChrome`, which full-bleeds the
	decoration for THAT padding: `Position = (0, -12)`, `Size = (1, +24)`. The
	authored `padding` prop is written AFTERWARDS, by `applyProp`, which rewrites
	the `UIPadding` to 8/8 and re-runs nothing. `applyFullBleed` cancels a padding
	it read once; the padding then changed under it. The compensation is stale by

	    (style.space.s + 4) - authored     = 12 - 8 = 4 px a side

	and a stale full-bleed does not shrink the decoration, it MOVES and GROWS it:
	the decoration is laid out inside the host's padded CONTENT box, so it starts
	at `x + current` and is pushed back by `compensated`, and it ends at
	`x + w - current` grown by `compensated`.

	This is general, not compact-pointer's: any node whose authored padding differs
	from its class default paints its decoration outside its own box under any
	package that draws one. Compact Pointer is where it is VISIBLE — a hairline
	border to lose, and a plate that sits flush against a clipping ancestor.

	PROVED LIVE, same instrument, same frame: writing the compensation for the
	padding the plate actually carries moved the decoration from [6.0 .. 97.0] to
	[10.0 .. 93.0] — flush.

	THE FIX: the ONE authority that writes a host's `UIPadding` re-fits every
	full-bleed child it owns, in the same write. Same shape as `refitIconArt`,
	which exists because an icon's rect can arrive after the icon does.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local chrome_slots = require("../src/tokens/chrome_slots")

local chromeSource = fs.readFile("src/client/screen_chrome.luau")
-- the per-class `setProp` chain (every `elseif prop == "<name>" then` branch)
-- left screen_target.luau for src/client/screen_props.luau (source-cap-ledger,
-- 2026-08-28) — moved verbatim, same relative indentation
local targetSource = fs.readFile("src/client/screen_props.luau")

-- the source of ONE `elseif prop == "<name>" then` branch of `applyProp`, so an
-- assertion about where a call sits cannot be satisfied by that call appearing
-- anywhere else in a 4000-line file
local function propBranch(name: string): string
	local head = `elseif prop == "{name}" then`
	local from = string.find(targetSource, head, 1, true)
	assert(from ~= nil, `screen_props has no '{head}' branch`)
	local nextBranch = string.find(targetSource, "\n\t\telseif prop == ", from + #head, true)
	return string.sub(targetSource, from, if nextBranch ~= nil then nextBranch else #targetSource)
end

--[[ THE ENGINE RULE, from the live measurement above. A decoration sized
	`fromScale(1, 1)` resolves against the host's PADDED content box, so with a
	compensation computed for `compensated` while the host carries `current`, the
	painted box is:

	    x = hostX + current + fullBleedBox(compensated).x
	    w = (hostW - 2 * current) + fullBleedBox(compensated).w

	At `compensated == current` that is the identity — the host's own box. ]]
local function paintedBox(hostX: number, hostW: number, compensated: number, current: number)
	local box = chrome_slots.fullBleedBox(compensated, compensated, 0, 0)
	return { x = hostX + current + box.x, w = (hostW - 2 * current) + box.w }
end

describe("chrome full bleed: compensated for the padding the host ACTUALLY has", function()
	it(
		"the measured Compact Pointer tray plate: a stale 12 against a live 8 paints [6..97] for a [10..93] plate",
		function()
			-- the live numbers, verbatim (plate x=10 w=83, created at 12, authored 8)
			local stale = paintedBox(10, 83, 12, 8)
			expect(`stale deco [{stale.x}..{stale.x + stale.w}]`).toBe("stale deco [6..97]")
			-- ...and 4px of that is on the far side of the Table body's clip edge (10)
			expect(10 - stale.x).toBe(4)
		end
	)

	it("...and compensating for the padding it carries is the identity: [10..93]", function()
		local fresh = paintedBox(10, 83, 8, 8)
		expect(`fresh deco [{fresh.x}..{fresh.x + fresh.w}]`).toBe("fresh deco [10..93]")
	end)

	it("an unpadded host is untouched, so nothing that was already flush moves", function()
		local box = paintedBox(10, 83, 0, 0)
		expect(`deco [{box.x}..{box.x + box.w}]`).toBe("deco [10..93]")
	end)

	it(
		"screen_chrome exports refitFullBleed, and it covers the LAYER ladder as well as the single decoration",
		function()
			expect(string.find(chromeSource, "refitFullBleed = refitFullBleed", 1, true) ~= nil).toBe(true)
			local from = string.find(chromeSource, "local function refitFullBleed(", 1, true)
			expect(`refitFullBleed defined: {from ~= nil}`).toBe("refitFullBleed defined: true")
			local body = string.sub(chromeSource, from :: number, (from :: number) + 900)
			-- the single decoration...
			expect(string.find(body, "handle.chrome", 1, true) ~= nil).toBe(true)
			-- ...and every full-bleed layer of a LAYERED package, which is built once
			-- and never re-fitted by the per-sync path the single decoration uses
			expect(string.find(body, "chromeStack", 1, true) ~= nil).toBe(true)
			expect(string.find(body, "applyFullBleed(", 1, true) ~= nil).toBe(true)
		end
	)

	it("the padding WRITE re-fits the bleed — the Button path", function()
		--[[ BITES: delete the `refitFullBleed(handle)` call from the Button half of
			`elseif prop == "padding"` and this fails. The padding write is the one
			authority for a host's UIPadding, so it is the one place that can know
			the number every full-bleed compensation was derived from just changed. ]]
		local branch = propBranch("padding")
		local buttonHalf =
			string.sub(branch, 1, (string.find(branch, 'elseif handle.class == "Text"', 1, true) or #branch))
		expect(string.find(buttonHalf, "pad.PaddingLeft = UDim.new(0, left)", 1, true) ~= nil).toBe(true)
		expect(`Button padding write refits: {string.find(buttonHalf, "refitFullBleed(handle)", 1, true) ~= nil}`).toBe(
			"Button padding write refits: true"
		)
	end)

	it("...and the Text path, which writes a UIPadding on a node that can carry a decoration too", function()
		local branch = propBranch("padding")
		local textHalf = string.sub(branch, (string.find(branch, 'elseif handle.class == "Text"', 1, true) or 1))
		expect(string.find(textHalf, "pad.PaddingBottom = UDim.new(0, bottom)", 1, true) ~= nil).toBe(true)
		expect(`Text padding write refits: {string.find(textHalf, "refitFullBleed(handle)", 1, true) ~= nil}`).toBe(
			"Text padding write refits: true"
		)
	end)
end)
