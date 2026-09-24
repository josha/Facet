--!strict
--[[ UI.StepIndicator — one current authority, only permitted steps as Buttons,
	and a measured fall to a summary with a Popover list (phase6 P6b). ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local ROOT = "/S/Page/Steps"

local function mount(spec: any, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = o.w or 900, h = 600 },
		reducedMotion = o.reduced ~= false,
		capabilities = { mouse = true, keyboard = true, gamepad = true },
		hostOpts = { keyboardNavigation = true },
	})
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({
			UI.VStack("Page")({
				width = if o.hug then nil else UI.fill(),
				gap = "s",
				UI.StepIndicator("Steps")(spec),
			}),
		})
	end)
	w.settle(3)
	return w
end

local function workflow(): { any }
	return {
		{ id = "cart", label = "Cart", state = "complete", navigable = true },
		{ id = "ship", label = "Shipping", description = "Address and speed", navigable = true },
		{ id = "pay", label = "Payment", navigable = true },
		{ id = "done", label = "Review" },
	}
end

local function find(w: any, suffix: string): string?
	for _, p in w.adapter.paths() do
		if string.sub(p, 1, #ROOT) == ROOT and string.sub(p, -#suffix) == suffix then
			return p
		end
	end
	return nil
end

local function dump(w: any): any
	return w.record("Steps").dump()
end

describe("StepIndicator: the row", function()
	it("only navigable, enabled steps with onSelect are Buttons; the rest are content", function()
		local w = mount({ steps = workflow(), current = "ship", onSelect = function() end })
		local ship = find(w, "/Step-ship")
		local review = find(w, "/Step-done")
		expect(ship ~= nil and review ~= nil).toBe(true)
		expect(w.adapter.node(ship :: string).onActivate ~= nil).toBe(true)
		expect(w.adapter.node(review :: string).onActivate).toBeNil()
		expect(w.pres.focus.focusOn(review :: string)).toBe(false)
		-- without onSelect nothing is a Button
		local plain = mount({ steps = workflow(), current = "ship" })
		expect(plain.adapter.node(find(plain, "/Step-ship") :: string).onActivate).toBeNil()
	end)

	it("current alone moves the underline and the summary; a refused selection changes nothing", function()
		local current = Compose.cell("ship")
		local asked: { string } = {}
		local accept = true
		local w = mount({
			steps = workflow(),
			current = current,
			onSelect = function(id: string)
				table.insert(asked, id)
				if accept then
					current:set(id)
				end
			end,
		})
		local function bar(): any
			return w.adapter.node(find(w, "/Underline/Layer/Bar") :: string).rect
		end
		local function under(stepId: string): boolean
			local step = w.adapter.node(find(w, `/Step-{stepId}`) :: string).rect
			local b = bar()
			return math.abs(b.x - step.x) <= 1 and math.abs(b.w - step.w) <= 1
		end
		expect(under("ship")).toBe(true)
		expect(dump(w).summary).toBe("Step 2 of 4 — Shipping")
		accept = false
		w.adapter.tap(find(w, "/Step-pay") :: string)
		w.settle(2)
		expect(table.concat(asked, ",")).toBe("pay")
		expect(dump(w).current).toBe("ship")
		expect(under("ship")).toBe(true)
		accept = true
		w.adapter.tap(find(w, "/Step-pay") :: string)
		w.settle(3)
		expect(dump(w).current).toBe("pay")
		expect(dump(w).summary).toBe("Step 3 of 4 — Payment")
		expect(under("pay")).toBe(true)
		-- the current step itself proposes nothing
		w.adapter.tap(find(w, "/Step-pay") :: string)
		expect(#asked).toBe(2)
	end)

	it("the row's cells share one height and a top edge, so the underline stays on one line (owner)", function()
		local current = Compose.cell("ship")
		local w = mount({
			steps = workflow(),
			current = current,
			onSelect = function(id: string)
				current:set(id)
			end,
		})
		local ids = { "cart", "ship", "pay", "done" }
		local first = w.adapter.node(find(w, "/Step-cart") :: string).rect
		local label = w.adapter.node((find(w, "/Step-cart") :: string) .. "/Copy/Label").rect
		for _, stepId in ids do
			local path = find(w, `/Step-{stepId}`) :: string
			local r = w.adapter.node(path).rect
			local l = w.adapter.node(path .. "/Copy/Label").rect
			expect(`{stepId} {r.y} {r.h} {l.y}`).toBe(`{stepId} {first.y} {first.h} {label.y}`)
		end
		local bar0 = w.adapter.node(find(w, "/Underline/Layer/Bar") :: string).rect
		for _, stepId in { "cart", "pay", "ship" } do
			current:set(stepId)
			w.settle(3)
			local b = w.adapter.node(find(w, "/Underline/Layer/Bar") :: string).rect
			expect(`{stepId} {b.y} {b.h}`).toBe(`{stepId} {bar0.y} {bar0.h}`)
		end
	end)

	it("an errored or completed current step keeps its own cue and state word", function()
		local steps = workflow()
		steps[2].state = "error"
		local w = mount({ steps = steps, current = "ship" })
		local ship = find(w, "/Step-ship") :: string
		expect(w.adapter.node(ship .. "/Cue/Error").decorationHint.icon).toBe("status.error")
		expect(w.adapter.visibleOf(ship .. "/Cue/Error") ~= false).toBe(true)
		expect(w.adapter.visibleOf(ship .. "/Cue/Check")).toBe(false)
		expect(w.adapter.node(ship .. "/Copy/State").props.text).toBe("Error")
		local cart = find(w, "/Step-cart") :: string
		expect(w.adapter.node(cart .. "/Cue/Check").decorationHint.icon).toBe("checkmark")
		expect(w.adapter.visibleOf(cart .. "/Cue/Check") ~= false).toBe(true)
		expect(w.adapter.node(cart .. "/Copy/State").props.text).toBe("Complete")
		local pay = find(w, "/Step-pay") :: string
		expect(w.adapter.node(pay .. "/Cue/Circle/Number").props.text).toBe("3")
		expect(w.adapter.node(pay .. "/Copy/State").props.text).toBe("Upcoming")
	end)

	it("the number marker stays a circle at the largest text size", function()
		local w = mount({ steps = workflow(), current = "ship" }, { w = 1600 })
		w.env:set("preferredTextOffset", 14)
		w.settle(4)
		local cue = w.adapter.node((find(w, "/Step-pay") :: string) .. "/Cue").rect
		expect(cue.w).toBe(cue.h)
		expect(cue.h > 24).toBe(true)
	end)

	it("a missing current is unavailable, never guessed; empty and repopulated lists rebuild cleanly", function()
		local steps = Compose.cell(workflow())
		local current = Compose.cell("gone" :: string?)
		local w = mount({ steps = steps, current = current })
		expect(dump(w).current).toBeNil()
		expect(dump(w).summary).toBe("No current step")
		for _ = 1, 2 do
			steps:set({})
			w.settle(2)
			expect(dump(w).summary).toBe("No steps")
			-- nothing to list: no button that opens an empty list
			local show = find(w, "/ShowSteps")
			expect(show == nil or w.pres.focus.focusOn(show) == false).toBe(true)
			expect(find(w, "/Step-cart")).toBeNil()
			steps:set(workflow())
			current:set("pay")
			w.settle(3)
			expect(dump(w).summary).toBe("Step 3 of 4 — Payment")
			expect(find(w, "/Step-pay") ~= nil).toBe(true)
		end
	end)

	it("a reorder keeps each step's node and the underline follows the current step's solved rect", function()
		local steps = Compose.cell(workflow())
		local w = mount({ steps = steps, current = "pay", onSelect = function() end })
		local payNode = w.adapter.node(find(w, "/Step-pay") :: string)
		local reversed = {}
		for i = 4, 1, -1 do
			table.insert(reversed, workflow()[i])
		end
		steps:set(reversed)
		w.settle(3)
		local pay = find(w, "/Step-pay") :: string
		expect(w.adapter.node(pay)).toBe(payNode)
		expect(w.adapter.node(pay .. "/Cue/Circle/Number").props.text).toBe("2")
		local bar = w.adapter.node(find(w, "/Underline/Layer/Bar") :: string).rect
		expect(math.abs(bar.x - w.adapter.node(pay).rect.x) <= 1).toBe(true)
		expect(dump(w).summary).toBe("Step 2 of 4 — Payment")
	end)

	it("refuses conflicts at construction and keeps the last legal snapshot later", function()
		local w = world.new()
		local UI = w.UI
		local bad = {
			{ steps = { { id = "a", label = "A", state = "current" } }, current = "b" },
			{ steps = { { id = "a", label = "A" }, { id = "a", label = "B" } }, current = "a" },
			{ steps = { { id = "", label = "A" } } },
			{ steps = { { id = "a", label = "" } } },
			{ steps = { { id = "a", label = "A", state = "done" } } },
			{ steps = { { id = "a", label = "A", extra = 1 } } },
			{ steps = {}, sizing = "wide" },
		}
		for _, spec in bad do
			expect(pcall(function()
				w.scoped(function()
					return UI.StepIndicator(spec)
				end)
			end)).toBe(false)
		end
		-- repeated labels are legal; identity is the id
		expect(pcall(function()
			w.scoped(function()
				return UI.StepIndicator({
					steps = { { id = "r1", label = "Review" }, { id = "r2", label = "Review" } },
					current = "r1",
				})
			end)
		end)).toBe(true)
		local steps = Compose.cell(workflow())
		local m = mount({ steps = steps, current = "ship" })
		local broken = workflow()
		broken[1].state = "current"
		steps:set(broken)
		m.settle(2)
		expect(dump(m).current).toBe("ship")
		expect(#m.record("Steps").api.diagnostics()).toBe(1)
	end)
end)

describe("StepIndicator: the summary", function()
	it("a narrow width shows Step n of m and a list that selects through the same path", function()
		local current = Compose.cell("ship")
		local asked: { string } = {}
		local refuse = false
		local w = mount({
			steps = workflow(),
			current = current,
			onSelect = function(id: string)
				if refuse then
					return
				end
				table.insert(asked, id)
				current:set(id)
			end,
		}, { w = 300 })
		expect(dump(w).form).toBe("summary")
		expect(w.adapter.node(find(w, "/Summary") :: string).props.text).toBe("Step 2 of 4 — Shipping")
		w.adapter.tap(find(w, "/ShowSteps") :: string)
		w.settle(3)
		expect(dump(w).listOpen).toBe(true)
		-- opening changed nothing
		expect(#asked).toBe(0)
		-- a refused selection changes nothing: the list stays open
		refuse = true
		for _, p in w.adapter.paths() do
			if string.sub(p, -10) == "/Item-cart" then
				w.adapter.tap(p)
			end
		end
		w.settle(3)
		expect(dump(w).listOpen).toBe(true)
		refuse = false
		local pay: string? = nil
		for _, p in w.adapter.paths() do
			if string.sub(p, -9) == "/Item-pay" then
				pay = p
			end
		end
		expect(pay ~= nil).toBe(true)
		w.adapter.tap(pay :: string)
		w.settle(3)
		expect(table.concat(asked, ",")).toBe("pay")
		expect(dump(w).listOpen).toBe(false)
		expect(w.adapter.node(find(w, "/Summary") :: string).props.text).toBe("Step 3 of 4 — Payment")
	end)

	it("hug sizing follows its offer both ways: narrow to the summary and wide back to the row", function()
		local room = Compose.cell(150)
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1000, h = 600 },
			reducedMotion = true,
			capabilities = { mouse = true, keyboard = true },
		})
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.VStack("Page")({
					width = function(use)
						return { type = "fixed", px = use(room) }
					end,
					w.UI.StepIndicator("Steps")({ steps = workflow(), current = "ship", sizing = "hug" }),
				}),
			})
		end)
		w.settle(3)
		expect(dump(w).form).toBe("summary")
		room:set(950)
		w.settle(4)
		expect(dump(w).form).toBe("row")
	end)

	-- G2: a hugging parent's width is the form the control drew, not an offer
	it("a hugging parent settles on the same form a filling one shows at that width", function()
		for _, w in { 900, 300 } do
			local filled = dump(mount({ steps = workflow(), current = "ship" }, { w = w })).form
			local hugged = dump(mount({ steps = workflow(), current = "ship" }, { w = w, hug = true })).form
			expect(`{w}:{hugged}`).toBe(`{w}:{filled}`)
		end
	end)

	it("a callback that removes the control leaves nothing open", function()
		local show = Compose.cell(true)
		local w = world.new({ viewport = { x = 0, y = 0, w = 900, h = 600 }, reducedMotion = true })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.When("Gate")({
					condition = show,
					thenView = function()
						return UI.StepIndicator("Steps")({
							steps = workflow(),
							current = "ship",
							onSelect = function()
								show:set(false)
							end,
						})
					end,
				}),
			})
		end)
		w.settle(3)
		local pay: string? = nil
		for _, p in w.adapter.paths() do
			if string.sub(p, -9) == "/Step-pay" then
				pay = p
			end
		end
		w.adapter.tap(pay :: string)
		w.settle(3)
		expect(w.adapter.node("/S/Gate/then/Steps")).toBeNil()
	end)
end)

describe("StepIndicator: the gallery tab", function()
	it("the Steps scenario: a row selection moves the narrow summary too; refusing changes neither", function()
		local scenario = require("../examples/gallery/scenarios/steps") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 }, reducedMotion = true })
		local built =
			scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose, app = w.app, core = w.core, env = w.env })
		w.present(built.screen)
		w.settle(3)
		local function at(suffix: string): string
			for _, p in w.adapter.paths() do
				if string.sub(p, -#suffix) == suffix then
					return p
				end
			end
			error(suffix)
		end
		local summary = at("/Compact/Form/else/Compact/Summary")
		expect(w.adapter.node(summary).props.text).toBe("Step 2 of 4 — Shipping")
		w.adapter.tap(at("/Checkout/Form/then/Underline/Strip/Steps/[pay:bd]/Step-pay"))
		w.settle(3)
		expect(w.adapter.node(summary).props.text).toBe("Step 3 of 4 — Payment")
		w.adapter.tap(at("/Steps/Refuse"))
		w.settle(2)
		w.adapter.tap(at("/Checkout/Form/then/Underline/Strip/Steps/[cart:b]/Step-cart"))
		w.settle(3)
		expect(w.adapter.node(summary).props.text).toBe("Step 3 of 4 — Payment")
	end)
end)

return nil
