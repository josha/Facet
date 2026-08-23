--!strict
-- TabView ACCESSORY SLOTS (framework-gaps-phase2 §6) — the chrome a nav bar
-- carries beside its tabs, homed by the placement the control already resolved.
--
-- WHY THIS FILE EXISTS. `Facet.Controls.TabView` shipped to kill the four-`When`
-- nav wheel, and one reference app could adopt it: the only one whose chrome
-- never moves. `p1_glade` puts a wordmark at the rail's HEAD; `p3_sipworks` puts
-- a search field on the top band's TRAILING edge and directly ABOVE the thumb-zone
-- dock. Neither is expressible, so both still carry a hand-built shell and the
-- examples directory teaches the same thing two contradictory ways.
--
-- FOUR CLAIMS CARRY IT, and each is written so the obvious wrong implementation
-- fails it:
--
--   * THE MATRIX IS A FACT ABOUT PLACEMENTS, NOT A GUESS. A slot has a declared
--     set of hosting placements, exported pure, and the mounted tree agrees with
--     it at every one of the four homes.
--   * A SLOT THE PLACEMENT CANNOT HOST REFUSES — when the placement is KNOWN at
--     construction (declared, or nested, which always resolves `topBar`). It is
--     the one moment the mistake is provable, and silence there is how a wordmark
--     never appears and nobody can say why.
--   * AN ACCESSORY MUST NOT MOVE THE STRIP. The centred bands are a shipped
--     contract (ADAPT-4, B-12): a trailing accessory OVERLAYS the band, so the
--     measured `leftGap == rightGap` still holds with it mounted. Asserted as a
--     measured gap, never as a property in a dump.
--   * THE NO-ACCESSORY PATH IS BYTE-IDENTICAL. `p4_foyer` adopted the construct
--     whole and pins the four home paths; a wrapper that appears unconditionally
--     would re-home every one of them. Declaring nothing mounts nothing.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local tab_view = require("../src/controls/tab_view")
-- the shared headless world (REUSE-88 / R12): this file was the next one to add a
-- builder, so it is the next one migrated rather than the 79th to hand-roll six
-- pieces in the order `Facet.newPresenter` happens to take
local worldLib = require("./lib/world")

local UI = Facet.UI

-- the same four shapes tab_view.spec uses, and for the same reason: a placement
-- is decided by viewport and input facts and by nothing else
local PHONE = { w = 320, h = 640 } -- compact width          -> bottomBar
local LANDSCAPE = { w = 800, h = 400 } -- short height       -> bottomBarCompact
local TABLET = { w = 900, h = 900 } -- touch + Medium display -> topBar
local DESKTOP = { w = 1200, h = 900 } -- pointer primary     -> sidebar

local function body(name: string)
	return function(_scope: any)
		return UI.Text({ id = name .. "Body", text = name })
	end
end

local function tabsOf(names: { string })
	local out = {}
	for _, name in names do
		table.insert(
			out,
			{ id = name, label = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2), content = body(name) }
		)
	end
	return out
end

local function world(opts: any?)
	local options = opts or {}
	local view = options.viewport or DESKTOP
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = view.w, h = view.h },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		capabilities = options.capabilities,
		-- the headless default is a pointer desktop, which is what makes DESKTOP
		-- resolve `sidebar` without a case having to say so
		preferredInput = options.preferredInput or "KeyboardAndMouse",
		displaySize = options.displaySize,
	})
	local selection = w.core:signal(options.initial or "home")
	local built: any = {
		id = "Tabs",
		selection = selection,
		env = w.env,
		tabs = options.tabs or tabsOf({ "home", "feed", "me" }),
	}
	for _, key in { "placement", "accessories", "sizing", "indicator" } do
		if (options :: any)[key] ~= nil then
			built[key] = (options :: any)[key]
		end
	end
	local tv = Facet.Controls.TabView(w.core, built)
	local handle = w.present(UI.Screen({ id = "S", children = { tv.blueprint } }), { sinkNavigation = true })
	return {
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		pres = w.pres,
		handle = handle,
		tv = tv,
		selection = selection,
	}
end

-- the accessory a test hands in: a leaf with a known id, so the assertion is
-- about WHERE THE AUTHOR'S OWN BLUEPRINT LANDED and not about a framework node
local function leaf(id: string, opts: any?)
	return function(_placement: string, _scope: any)
		local props: any = { id = id, text = id }
		if opts ~= nil and opts.height ~= nil then
			props.height = opts.height
		end
		return UI.Text(props)
	end
end

local function find(w: any, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

local function rect(w: any, suffix: string): any
	local path = find(w, suffix)
	expect(`mounted {suffix}: {path ~= nil}`).toBe(`mounted {suffix}: true`)
	return w.adapter.node(path :: string).rect
end

-- the refusal MESSAGE, lowercased: every one of these assertions is about the
-- words a reader gets, not about their capitalisation
local function refuses(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(`it refused: {not ok}`).toBe("it refused: true")
	return string.lower(tostring(err))
end

describe("§6 the matrix: which placement hosts which slot, as strings", function()
	--[[ PURE AND EXPORTED, for the same reason `resolvePlacement` is: the rule a
		refusal message quotes and the rule the mount obeys must be ONE rule, and a
		test over strings is the only way to say so without mounting anything. ]]
	it("each slot names the placements that host it, and an unknown slot names none", function()
		expect(table.concat(tab_view.accessoryPlacements("head") :: any, ",")).toBe("sidebar")
		expect(table.concat(tab_view.accessoryPlacements("foot") :: any, ",")).toBe("sidebar")
		expect(table.concat(tab_view.accessoryPlacements("trailing") :: any, ",")).toBe("topBar")
		expect(table.concat(tab_view.accessoryPlacements("aboveBar") :: any, ",")).toBe("bottomBar,bottomBarCompact")
		expect(tab_view.accessoryPlacements("leading")).toBeNil()
		expect(tab_view.accessoryPlacements("belowBar")).toBeNil()
	end)

	it("the returned list is a COPY, so a caller cannot edit the framework's rule", function()
		local first = tab_view.accessoryPlacements("aboveBar") :: any
		table.remove(first, 1)
		expect(#(tab_view.accessoryPlacements("aboveBar") :: any)).toBe(2)
	end)
end)

describe("§6 the rail's two ends: head above the strip, foot pinned to the bottom", function()
	it("the head sits ABOVE the strip and inside the rail", function()
		local w = world({ viewport = DESKTOP, accessories = { head = leaf("Wordmark") } })
		expect(w.tv.dump().placement).toBe("sidebar")
		local head = rect(w, "/HeadSlot/Wordmark")
		local strip = rect(w, "/Rail/Strip")
		local root = w.adapter.node("/S/Tabs").rect
		expect(head.y + head.h <= strip.y + 1).toBe(true)
		expect(head.y >= root.y - 1).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ THE POCKET SHAPE. A rail's foot is not "after the strip" — it is the
		BOTTOM OF THE RAIL, which is what a three-tab strip on a 900px-tall screen
		makes visible: the naive implementation puts the foot 100px down, directly
		under the last tab, and reads identically in a dump. ]]
	it("the foot is pinned to the rail's BOTTOM, not merely after the last tab", function()
		local w = world({ viewport = DESKTOP, accessories = { foot = leaf("Pocket") } })
		local foot = rect(w, "/FootSlot/Pocket")
		local strip = rect(w, "/Rail/Strip")
		local root = w.adapter.node("/S/Tabs").rect
		expect(foot.y > strip.y + strip.h - 1).toBe(true)
		expect(math.abs((foot.y + foot.h) - (root.y + root.h)) <= 1).toBe(true)
		expect(foot.y - (strip.y + strip.h) > 100).toBe(true) -- the slack really is spent
	end)

	it("both ends together keep the strip between them", function()
		local w = world({ viewport = DESKTOP, accessories = { head = leaf("Wordmark"), foot = leaf("Pocket") } })
		local head = rect(w, "/HeadSlot/Wordmark")
		local strip = rect(w, "/Rail/Strip")
		local foot = rect(w, "/FootSlot/Pocket")
		expect(head.y + head.h <= strip.y + 1).toBe(true)
		expect(strip.y + strip.h <= foot.y + 1).toBe(true)
		expect(table.concat(w.tv.dump().accessories.mounted, ",")).toBe("foot,head")
	end)

	it("the factory is told WHICH placement asked, so one function can serve several", function()
		local seen: { string } = {}
		local w = world({
			viewport = DESKTOP,
			accessories = {
				head = function(placement: string, _scope: any)
					table.insert(seen, placement)
					return UI.Text({ id = "Wordmark", text = placement })
				end,
			},
		})
		expect(table.concat(seen, ",")).toBe("sidebar")
		expect(w.adapter.node(find(w, "/HeadSlot/Wordmark") :: string).props.text).toBe("sidebar")
	end)
end)

describe("§6 the top band's trailing edge — and the centring that must survive it", function()
	local function tabletWorld(accessories: any, extra: any?)
		local o = extra or {}
		return world({
			viewport = o.viewport or TABLET,
			preferredInput = "Touch",
			displaySize = "Medium",
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			accessories = accessories,
			tabs = o.tabs,
		})
	end

	it("the trailing accessory sits at the band's trailing edge", function()
		local w = tabletWorld({ trailing = leaf("Search") })
		expect(w.tv.dump().placement).toBe("topBar")
		local search = rect(w, "/TrailingSlot/Search")
		local root = w.adapter.node("/S/Tabs").rect
		local strip = rect(w, "/TopBand/Strip")
		expect(math.abs((search.x + search.w) - (root.x + root.w)) <= 1).toBe(true)
		expect(search.x > strip.x + strip.w - 1).toBe(true)
	end)

	--[[ I-6: THE OVERFLOWING STRIP, which the three-tab cases could not see. A
		hugging band takes the WHOLE offer once its tabs no longer fit, so the strip's
		trailing edge and the band's are the same edge — and an accessory parked on
		that edge sits ON the last tab. Measured before the fix: 60px of the last tab
		under the search field, its taps going to the accessory, and scrolling could
		never uncover it because the scroller's content ends exactly where the
		accessory begins.

		THE ASSERTION IS A RECT NON-INTERSECTION, not a gap: "they do not overlap" is
		the property, and it has to hold in BOTH states — the hugging cluster that
		fits with room to spare, and the overflowing strip that does not. ]]
	it("the accessory never sits ON a tab, even when the strip overflows its band", function()
		local w = tabletWorld({ trailing = leaf("Search") }, {
			tabs = tabsOf({
				"avatars",
				"bodywork",
				"clothing",
				"accessories",
				"backgrounds",
				"expressions",
				"voices",
				"emotes",
			}),
			viewport = { w = 700, h = 900 },
		})
		expect(w.tv.dump().placement).toBe("topBar")
		local strip = rect(w, "/TopBand/Strip")
		local band = rect(w, "/TopBand")
		local search = rect(w, "/TrailingSlot/Search")
		-- the premise: this strip really does overflow the band it scrolls in
		expect(strip.w > band.w).toBe(true)
		-- ...and the accessory is clear of it, so no tab is ever under it
		expect(`overlap: {search.x < band.x + band.w}`).toBe("overlap: false")
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)

	--[[ THE HALF THAT MAKES IT SAFE (ADAPT-4 / ADR-0040 B-12). The naive fix puts
		the accessory in the band's own STACK, which pushes the hugging strip off
		centre by exactly the accessory's width and reads "centered" in every dump.
		The strip is centred in THE BOX THE TABS HAVE — the band minus what the
		accessory reserved — and that is the claim at every tab count, where
		"centred on the whole band" is only true until the strip grows. ]]
	it("...and the strip is centred in the box the tabs have, with the accessory clear of it", function()
		local w = tabletWorld({ trailing = leaf("Search") })
		local strip = rect(w, "/TopBand/Strip")
		local box = rect(w, "/TopBandBox")
		local search = rect(w, "/TrailingSlot/Search")
		local left, right = strip.x - box.x, (box.x + box.w) - (strip.x + strip.w)
		expect(strip.w < box.w).toBe(true) -- it HUGS, which is what makes a gap exist
		expect(math.abs(left - right) <= 1).toBe(true)
		expect(left > 0).toBe(true)
		-- the accessory took real width out of the band, and none of the strip's
		expect(`overlap: {search.x < box.x + box.w}`).toBe("overlap: false")
		local root = w.adapter.node("/S/Tabs").rect
		expect(box.w < root.w).toBe(true)
	end)

	--[[ ...AND DECLARING NONE STILL CENTRES ON THE WHOLE BAND, which is the shape
		that shipped: no reservation, no row, no `TopBandBox`. ]]
	it("a band with no trailing accessory is centred on the WHOLE band, in the shipped shape", function()
		local bare = tabletWorld(nil)
		local strip = rect(bare, "/TopBand/Strip")
		local root = bare.adapter.node("/S/Tabs").rect
		local left, right = strip.x - root.x, (root.x + root.w) - (strip.x + strip.w)
		expect(math.abs(left - right) <= 1).toBe(true)
		expect(left > 0).toBe(true)
		expect(bare.adapter.node("/S/Tabs/TopHome/then/TopBandCenter/TopBand/Strip") ~= nil).toBe(true)
		expect(find(bare, "/TopBandBox")).toBeNil()
	end)
end)

describe("§6 the dock: an accessory directly above the thumb-zone band", function()
	it("on a portrait phone it sits between the content and the band", function()
		local w = world({
			viewport = PHONE,
			preferredInput = "Touch",
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			accessories = { aboveBar = leaf("Search") },
		})
		expect(w.tv.dump().placement).toBe("bottomBar")
		local content = w.adapter.node("/S/Tabs/Content").rect
		local search = rect(w, "/AboveBarSlot/Search")
		local band = rect(w, "/BottomBand/Strip")
		expect(search.y >= content.y + content.h - 1).toBe(true)
		expect(band.y >= search.y + search.h - 1).toBe(true)
	end)

	--[[ M-4: THE DOCK ADDS NO SPACING OF ITS OWN, pinned as a RECT rather than as
		the absence of a `gap` prop. The construct declares no padding and no gap
		anywhere in its scaffold (a landscape phone offers ~320px of height and the
		first app migrated onto this control lost 8 of them to a band inset it never
		asked for), so the only space between an accessory and the tabs is the space
		the ACCESSORY ITSELF declares. The hand-built dock this replaced had a
		`gap = "xs"` on top of its accessory's own padding; that step is gone, and
		this is the case that makes its absence deliberate. ]]
	it("the dock adds NO spacing of its own: the accessory's box meets the band's", function()
		local w = world({
			viewport = PHONE,
			preferredInput = "Touch",
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			accessories = { aboveBar = leaf("Search") },
		})
		local slot = rect(w, "/AboveBarSlot")
		local band = rect(w, "/BottomBand")
		expect(`gap: {band.y - (slot.y + slot.h)}`).toBe("gap: 0")
		-- ...and the slot is exactly its child's box, so an author who wants
		-- breathing room pads the blueprint they hand in
		local search = rect(w, "/AboveBarSlot/Search")
		expect(`slot height: {slot.h - search.h}`).toBe("slot height: 0")
	end)

	it("the landscape phone's inline dock hosts it too, and its band stays centred", function()
		local w = world({
			viewport = LANDSCAPE,
			preferredInput = "Touch",
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			accessories = { aboveBar = leaf("Search") },
		})
		expect(w.tv.dump().placement).toBe("bottomBarCompact")
		local search = rect(w, "/AboveBarSlot/Search")
		local strip = rect(w, "/CompactBand/Strip")
		local root = w.adapter.node("/S/Tabs").rect
		expect(strip.y >= search.y + search.h - 1).toBe(true)
		expect(math.abs((strip.x - root.x) - ((root.x + root.w) - (strip.x + strip.w))) <= 1).toBe(true)
	end)
end)

describe("§6 the slots follow the placement — mounted where hosted, absent everywhere else", function()
	it("one TabView carrying all four slots mounts exactly the ones its home hosts", function()
		local all: any = {
			head = leaf("Wordmark"),
			foot = leaf("Pocket"),
			trailing = leaf("Search"),
			aboveBar = leaf("Dock"),
		}
		local w = world({ viewport = DESKTOP, accessories = all })
		expect(table.concat(w.tv.dump().accessories.declared, ",")).toBe("aboveBar,foot,head,trailing")
		expect(table.concat(w.tv.dump().accessories.mounted, ",")).toBe("foot,head")

		-- a rotation to the thumb zone: the rail's two ends go away, the dock arrives
		w.env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		w.env:set("preferredInput", "Touch")
		w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		w.pres.refresh()
		expect(w.tv.dump().placement).toBe("bottomBar")
		expect(table.concat(w.tv.dump().accessories.mounted, ",")).toBe("aboveBar")
		expect(find(w, "/HeadSlot/Wordmark")).toBeNil()
		expect(find(w, "/FootSlot/Pocket")).toBeNil()
		expect(find(w, "/TrailingSlot/Search")).toBeNil()

		-- ...and back again, with nothing left behind
		w.env:set("viewportRect", { x = 0, y = 0, w = DESKTOP.w, h = DESKTOP.h })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = false })
		w.pres.refresh()
		expect(table.concat(w.tv.dump().accessories.mounted, ",")).toBe("foot,head")
		expect(find(w, "/AboveBarSlot/Dock")).toBeNil()
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ I-1: THE TWO-HOME SLOT, RE-HOMED BETWEEN ITS OWN TWO HOMES. `aboveBar` is
		the only slot two placements host, so it is the only one whose new branch is
		BUILT WHILE THE OLD ONE IS STILL ALIVE — `mount.luau` mounts the arriving
		`When` and disposes the departing one after. A bookkeeping cell keyed by slot
		name alone is therefore written by the newcomer and then cleared by the
		leaver, and the dump goes on claiming the slot is absent while the node is on
		screen. It re-lies on every cycle, which is what makes it a bug report nobody
		can use rather than a one-frame blink. ]]
	it("a slot re-homed between its OWN two homes stays reported as mounted", function()
		local dockOnly: any = { aboveBar = leaf("Search") }
		local w = world({
			viewport = PHONE,
			preferredInput = "Touch",
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			accessories = dockOnly,
		})
		expect(w.tv.dump().placement).toBe("bottomBar")
		expect(table.concat(w.tv.dump().accessories.mounted, ",")).toBe("aboveBar")

		-- ...to the landscape phone, which hosts the SAME slot...
		w.env:set("viewportRect", { x = 0, y = 0, w = LANDSCAPE.w, h = LANDSCAPE.h })
		w.pres.refresh()
		expect(w.tv.dump().placement).toBe("bottomBarCompact")
		expect(find(w, "/AboveBarSlot/Search") ~= nil).toBe(true)
		expect(table.concat(w.tv.dump().accessories.mounted, ",")).toBe("aboveBar")

		-- ...and back. The node is on screen at every step, so the dump must say so
		-- at every step — and it must not decay on the second cycle either.
		for _ = 1, 2 do
			w.env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
			w.pres.refresh()
			expect(`portrait: {table.concat(w.tv.dump().accessories.mounted, ",")}`).toBe("portrait: aboveBar")
			expect(find(w, "/AboveBarSlot/Search") ~= nil).toBe(true)
			w.env:set("viewportRect", { x = 0, y = 0, w = LANDSCAPE.w, h = LANDSCAPE.h })
			w.pres.refresh()
			expect(`landscape: {table.concat(w.tv.dump().accessories.mounted, ",")}`).toBe("landscape: aboveBar")
		end
		-- and leaving BOTH of its homes still clears it
		w.env:set("viewportRect", { x = 0, y = 0, w = DESKTOP.w, h = DESKTOP.h })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = false })
		w.pres.refresh()
		expect(w.tv.dump().placement).toBe("sidebar")
		expect(#w.tv.dump().accessories.mounted).toBe(0)
		expect(find(w, "/AboveBarSlot/Search")).toBeNil()
		expect(w.core:lastError()).toBeNil()
	end)

	--[[ A FACTORY MAY DECLINE. The slot is declared once for every placement that
		hosts it, and `aboveBar` hosts two — so returning nothing for one of them is
		the honest way to say "not on this shape", and it must leave NO wrapper node
		behind (an empty box still takes the dock's gap). ]]
	it("a factory that returns nothing mounts nothing at all", function()
		local w = world({
			viewport = LANDSCAPE,
			preferredInput = "Touch",
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			accessories = {
				aboveBar = function(placement: string, _scope: any)
					if placement == "bottomBarCompact" then
						return nil
					end
					return UI.Text({ id = "Dock", text = "dock" })
				end,
			},
		})
		expect(w.tv.dump().placement).toBe("bottomBarCompact")
		expect(#w.tv.dump().accessories.mounted).toBe(0)
		expect(find(w, "/AboveBarSlot")).toBeNil()
		expect(find(w, "/CompactDock")).toBeNil()
	end)
end)

describe("§6 declaring nothing changes nothing — the shipped home paths are untouched", function()
	it("every one of the four homes keeps the exact path p4_foyer pins", function()
		local cases = {
			{
				opts = { viewport = DESKTOP },
				path = "/S/Tabs/RailHome/then/Rail/Strip",
			},
			{
				opts = {
					viewport = TABLET,
					preferredInput = "Touch",
					displaySize = "Medium",
					capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
				},
				path = "/S/Tabs/TopHome/then/TopBandCenter/TopBand/Strip",
			},
			{
				opts = {
					viewport = PHONE,
					preferredInput = "Touch",
					capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
				},
				path = "/S/Tabs/BottomHome/then/BottomBand/Strip",
			},
			{
				opts = {
					viewport = LANDSCAPE,
					preferredInput = "Touch",
					capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
				},
				path = "/S/Tabs/CompactHome/then/CompactBandCenter/CompactBand/Strip",
			},
		}
		for _, case in cases do
			local w = world(case.opts)
			expect(`{case.path}: {w.adapter.node(case.path) ~= nil}`).toBe(`{case.path}: true`)
			expect(#w.tv.dump().accessories.declared).toBe(0)
		end
	end)
end)

describe("§6 refuse, don't guess: a slot the placement cannot host is an authoring mistake", function()
	it("an unknown slot names the four that exist", function()
		local message = refuses(function()
			world({ viewport = DESKTOP, accessories = { leading = leaf("X") } })
		end)
		expect(string.find(message, "leading", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "abovebar", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "head", 1, true) ~= nil).toBe(true)
	end)

	--[[ M-2: TWO BAD SLOTS NAME THE SAME ONE EVERY TIME. The guard walked the
		caller's table, whose iteration order is a hash order — so an author with two
		mistakes got a different one named per run, and fixing the named one could
		surface the other or the same again. Sorted, for the reason `declaredSlots`
		and the dump are sorted: a refusal a reader can reproduce is a refusal they
		can act on. ]]
	it("with two bad slots, the refusal names the FIRST in sorted order, every time", function()
		local seen: { string } = {}
		for _ = 1, 12 do
			local message = refuses(function()
				world({ viewport = DESKTOP, accessories = { zenith = leaf("X"), leading = leaf("Y") } })
			end)
			-- the message quotes exactly one slot name; which one must not be a
			-- coin flip across runs of the same authoring mistake
			local named = if string.find(message, "'leading'", 1, true) ~= nil then "leading" else "zenith"
			table.insert(seen, named)
		end
		local first = seen[1]
		for _, name in seen do
			expect(`{name} == {first}`).toBe(`{first} == {first}`)
		end
		expect(first).toBe("leading")
	end)

	it("a slot must be a FACTORY, because the placement is its argument", function()
		local message = refuses(function()
			world({ viewport = DESKTOP, accessories = { head = UI.Text({ id = "X", text = "x" }) } })
		end)
		expect(string.find(message, "head", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "function", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE ONE MOMENT THE MISTAKE IS PROVABLE. Under `placement = "automatic"`
		every home is still reachable, so nothing can be refused — but a DECLARED
		placement is the caller saying the policy will never be consulted, and a
		wordmark declared for a rail that will never exist is a bug with a silent
		symptom. ]]
	it("a DECLARED placement that cannot host the slot refuses, and says which can", function()
		local message = refuses(function()
			world({ viewport = DESKTOP, placement = "bottomBar", accessories = { head = leaf("Wordmark") } })
		end)
		expect(string.find(message, "head", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "bottombar", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "sidebar", 1, true) ~= nil).toBe(true)
	end)

	it("an automatic placement refuses nothing, because every home is still reachable", function()
		local w = world({ viewport = PHONE, accessories = { head = leaf("Wordmark") } })
		expect(w.core:lastError()).toBeNil()
		expect(#w.tv.dump().accessories.mounted).toBe(0)
	end)

	--[[ NESTING IS A DECLARED PLACEMENT BY ANOTHER ROUTE: an inner TabView always
		resolves `topBar`, so a rail slot on one can never mount either. ]]
	it("a NESTED TabView refuses a rail slot, because nesting always resolves topBar", function()
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = PHONE.w, h = PHONE.h },
			safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		})
		local core, env = w.core, w.env
		local outerSelection = core:signal("page")
		local innerSelection = core:signal("one")
		local innerError: string? = nil
		local outer = Facet.Controls.TabView(core, {
			id = "App",
			selection = outerSelection,
			env = env,
			tabs = {
				{
					id = "page",
					label = "Page",
					content = function(_scope: any)
						local ok, err = pcall(function()
							return Facet.Controls.TabView(core, {
								id = "Page",
								selection = innerSelection,
								env = env,
								tabs = tabsOf({ "one", "two" }),
								accessories = { head = leaf("Wordmark") },
							})
						end)
						if not ok then
							innerError = tostring(err)
						end
						return UI.Text({ id = "PageBody", text = "page" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { outer.blueprint } }), { sinkNavigation = true })
		expect(`the inner refused: {innerError ~= nil}`).toBe("the inner refused: true")
		expect(string.find(string.lower(innerError :: string), "nested", 1, true) ~= nil).toBe(true)
		expect(string.find(string.lower(innerError :: string), "sidebar", 1, true) ~= nil).toBe(true)
	end)

	it("`accessories` itself must be a table of slots", function()
		local message = refuses(function()
			world({ viewport = DESKTOP, accessories = leaf("X") })
		end)
		-- naming the word `table` is what separates THIS refusal from the closed
		-- spec's "unknown key", which fires for the same input before the slot
		-- guard exists at all
		expect(string.find(message, "accessories", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "table", 1, true) ~= nil).toBe(true)
	end)
end)

describe("§6 the slots are owned, not leaked", function()
	it("re-homing disposes the accessory's scope with its branch", function()
		local disposals = 0
		local w = world({
			viewport = DESKTOP,
			accessories = {
				head = function(_placement: string, scope: any)
					scope:own({
						dispose = function()
							disposals += 1
						end,
					})
					return UI.Text({ id = "Wordmark", text = "glade" })
				end,
			},
		})
		expect(disposals).toBe(0)
		w.env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		w.env:set("preferredInput", "Touch")
		w.env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		w.pres.refresh()
		expect(disposals).toBe(1)
		expect(w.core:lastError()).toBeNil()
	end)
end)
