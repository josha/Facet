--!strict
--[[
	TABVIEW'S PAGE TRANSITION MEANS WHAT IT SAYS.

	`UI.TabView`'s refusal has always read "`transition` must be a TABLE — the
	same { enter?, exit?, class? } `UI.When` takes". The construct then keyed on
	`transition.fade == true` and on nothing else, so the two halves of the same
	control disagreed about the same field:

	  · `transition = { enter = "fade" }` — the spelling the refusal names, the
	    spelling `UI.When` takes, and the spelling both reference shells write —
	    was ACCEPTED AND SILENTLY DROPPED. The pages hard-cut, no diagnostic
	    fired, and the author's only clue was that the fade they declared never
	    played;
	  · `{ fade = true }` worked, and is not a legal `UI.When` transition at all
	    (`fade` is a modifier, `enter` is the form, and the schema requires one).

	Silently ignoring a declared transition is the accepted-and-ignored failure
	this framework keeps closing. So the declaration now goes through
	`transitions.resolve` — the exact validator `UI.When` runs — and a form a
	TabView cannot play is REFUSED rather than dropped: its pages occupy the same
	box, so a slide has nothing to slide against and the only structural motion
	between two co-located layers is a crossfade.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Compose = require("../src/vendor/compose/core")
local nativeWorld = require("./lib/world")

local function world(transition: any)
	local w = nativeWorld.new({
		viewport = { x = 0, y = 0, w = 320, h = 640 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
	})
	local function plate(name: string)
		return function(_owner: any)
			return w.UI.ZStack(name .. "Plate")({
				canvasGroup = true,
				w.UI.Text(name .. "Body")({ text = name }),
			})
		end
	end
	local selection = Compose.cell("home")
	w.present(function()
		return w.UI.Screen("S")({
			w.UI.TabView("Tabs")({
				selection = selection,
				placement = "bottomBar",
				transition = transition,
				tabs = {
					{ id = "home", label = "Home", content = plate("home") },
					{ id = "me", label = "Me", content = plate("me") },
				},
			}),
		})
	end)
	w.selection = selection
	return w
end

-- the MOUNTED node: a transition is a fact written on the branch, and the
-- adapter never sees it (tests/tab_view.spec.luau §6 established this reader)
local function nodeAt(w: any, path: string): any
	local found: any = nil
	local function walk(node: any)
		if node == nil then
			return
		end
		if node.path == path then
			found = node
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	walk(w.handle.root.node)
	return found
end

local function crossfades(w: any): boolean
	--[[ The crossfade's signature, and the one a hard cut cannot fake: the page
		carries its own opacity, and the DEPARTING page stays mounted (without
		input) until its fade ends. ]]
	local page = nodeAt(w, "/S/Tabs/Content/Tab-home")
	if page == nil or type(page.props.opacity) ~= "number" then
		return false
	end
	w.selection:set("me")
	w.settle(1)
	local departing = nodeAt(w, "/S/Tabs/Content/Tab-home")
	return departing ~= nil and departing.props.enabled == false
end

local function fails(build: () -> ()): string
	local ok, err = pcall(build)
	expect(ok).toBe(false)
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

describe("TabView honours the transition spec UI.When takes", function()
	it('`{ enter = "fade" }` crossfades — it was silently dropped before', function()
		expect(crossfades(world({ enter = "fade" }))).toBe(true)
	end)

	it("`{ fade = true }`, the spelling this control shipped with, still crossfades", function()
		expect(crossfades(world({ fade = true }))).toBe(true)
	end)

	it('`{ enter = "fade", exit = "fade" }` is the same declaration written out', function()
		expect(crossfades(world({ enter = "fade", exit = "fade" }))).toBe(true)
	end)

	it("declaring none leaves the branch with none", function()
		local w = world(nil)
		expect(nodeAt(w, "/S/Tabs/Content/Tab-home").props.opacity).toBeNil()
	end)

	it('`{ enter = "instant" }` is a legal, explicit hard cut', function()
		local w = world({ enter = "instant" })
		expect(#w.controller.diagnostics()).toBe(0)
		expect(nodeAt(w, "/S/Tabs/Content/Tab-home").props.opacity).toBeNil()
	end)
end)

describe("TabView refuses the forms it cannot play, instead of ignoring them", function()
	it("refuses a well-formed `transform`, which the schema alone would accept", function()
		local message = fails(function()
			world({ enter = "transform", fromRect = { x = 0, y = 0, w = 10, h = 10 } })
		end)
		expect(contains(message, "UI.TabView")).toBe(true)
		expect(contains(message, "transform")).toBe(true)
		expect(contains(message, "SAME box")).toBe(true)
	end)

	for _, form in { "slide-up", "slide-left", "materialize", "reveal" } do
		it(`refuses \`enter = "{form}"\` and says why`, function()
			local message = fails(function()
				world({ enter = form })
			end)
			expect(contains(message, "UI.TabView")).toBe(true)
			expect(contains(message, form)).toBe(true)
			-- the reason, not just the refusal: the pages share one box
			expect(contains(message, "SAME box")).toBe(true)
			-- ...and the line that works
			expect(contains(message, 'enter = "fade"')).toBe(true)
		end)
	end

	it("refuses an asymmetric exit it cannot play", function()
		local message = fails(function()
			world({ enter = "fade", exit = "slide-down" })
		end)
		expect(contains(message, "slide-down")).toBe(true)
	end)

	it("refuses a declaration with no form at all, in the schema's own words", function()
		local message = fails(function()
			world({ class = "brisk" })
		end)
		expect(contains(message, "UI.TabView")).toBe(true)
		expect(contains(message, "enter")).toBe(true)
	end)

	it("refuses an unknown transition field, exactly as UI.When does", function()
		local message = fails(function()
			world({ enter = "fade", wobble = 3 })
		end)
		expect(contains(message, "UI.TabView")).toBe(true)
		expect(contains(message, "wobble")).toBe(true)
	end)

	it("refuses an unknown FORM by the schema's list", function()
		local message = fails(function()
			world({ enter = "dissolve" })
		end)
		expect(contains(message, "dissolve")).toBe(true)
	end)

	it("still refuses the name of a transition rather than a table", function()
		local message = fails(function()
			world("fade")
		end)
		expect(contains(message, "transition")).toBe(true)
		expect(contains(string.lower(message), "table")).toBe(true)
	end)
end)
