--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native NavigationStack", function()
	t.it("mounts routes, restores Back, and releases page-owned resources", function()
		local app, adapter, advance, core = world()
		local UI, path = app.controls, Compose.cell({})
		local live = 0
		local function page(_, entry)
			live += 1
			Compose.cleanup(function()
				live -= 1
			end)
			return UI.Button("Next")({
				label = if entry then "Continue" else "Start",
				onActivate = function()
					local nextPath = table.clone(path:peek())
					table.insert(nextPath, { id = "detail", value = #nextPath + 1 })
					path:set(nextPath)
				end,
			})
		end
		local close = app.mount(function()
			local before = core.owner.size()
			local result = UI.NavigationStack("Nav")({
				path = path,
				root = { title = "Home", content = page },
				destinations = { detail = { title = "Detail", content = page } },
				backLabel = "Back",
			})
			t.expect(core.owner.size()).toBe(before)
			return UI.Screen("S")({ result })
		end)
		local function activate(suffix)
			for _, p in adapter.paths() do
				if p:sub(-#suffix) == suffix then
					adapter.driveActivate(p)
					return
				end
			end
			error("missing " .. suffix .. " in " .. table.concat(adapter.paths(), ","))
		end
		advance(0.1)
		t.expect(live).toBe(1)
		for _ = 1, 3 do
			activate("/Next")
			advance(0.1)
			t.expect(#path:peek()).toBe(1)
			t.expect(live).toBe(1)
			activate("/NavBar/Back")
			advance(0.1)
			t.expect(#path:peek()).toBe(0)
			t.expect(live).toBe(1)
		end
		close()
		advance(0.1)
		t.expect(live).toBe(0)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
	t.it("keeps only the top route mounted across deep pushes and path replacement", function()
		local app, adapter, advance = world()
		local UI, path = app.controls, Compose.cell({})
		local live, built, released = 0, 0, 0
		local function page(owner, entry)
			t.expect(owner).toBe(Compose.currentOwner())
			live += 1
			built += 1
			Compose.cleanup(function()
				live -= 1
				released += 1
			end)
			return UI.Text("Route")({ text = if entry then tostring(entry.value) else "Home" })
		end
		local close = app.mount(function()
			return UI.Screen("S")({
				UI.NavigationStack("Nav")({
					path = path,
					root = { content = page },
					destinations = { detail = { content = page } },
					backLabel = "Back",
				}),
			})
		end)
		local function routes(values)
			local nextPath = {}
			for _, value in values do
				table.insert(nextPath, { id = "detail", value = value })
			end
			path:set(nextPath)
			advance(0.02)
			t.expect(live).toBe(1)
		end
		advance(0.02)
		routes({ 1, 2, 3 })
		t.expect(built).toBe(2)
		routes({ 1, 2, 3 }) -- An equal route path preserves the current owner.
		t.expect(built).toBe(2)
		routes({ 1 })
		t.expect(built).toBe(3)
		routes({ 9, 10 })
		t.expect(built).toBe(4)
		routes({})
		t.expect(built).toBe(5)
		close()
		advance(0.02)
		t.expect(live).toBe(0)
		t.expect(released).toBe(built)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
	local function motionWorld(transition, reduced)
		local app, adapter, advance, core = world()
		app.environment:set("reducedMotion", reduced == true)
		local UI, path = app.controls, Compose.cell({})
		local w = { app = app, adapter = adapter, advance = advance, path = path, live = 0, built = {} }
		local function page(_, entry)
			local name = if entry then "detail" .. tostring(entry.value) else "root"
			w.live += 1
			w.built[name] = (w.built[name] or 0) + 1
			Compose.cleanup(function()
				w.live -= 1
			end)
			return UI.Button("Next")({ label = name, onActivate = function() end })
		end
		w.close = app.mount(function()
			local before = core.owner.size()
			local nav = UI.NavigationStack("Nav")({
				path = path,
				root = { title = "Home", content = page },
				destinations = { detail = { title = "Detail", content = page } },
				backLabel = "Back",
				transition = transition,
			})
			t.expect(core.owner.size()).toBe(before)
			return UI.Screen("S")({ nav })
		end)
		function w.routes(values)
			local nextPath = {}
			for _, value in values do
				table.insert(nextPath, { id = "detail", value = value })
			end
			path:set(nextPath)
		end
		function w.slot(key)
			return adapter.node("/S/Nav/Pages/[" .. key .. "]/PageMotion")
		end
		-- The slot's enabled state reaches the adapter through its controls.
		function w.interactive(key)
			return adapter.node("/S/Nav/Pages/[" .. key .. "]/PageMotion/Page/BodyHost/Content/Next").props.enabled
				~= false
		end
		function w.opacity(key)
			return 1 - (w.slot(key).props.transparency or 0)
		end
		function w.x(key)
			return w.slot(key).presentationOffset.x
		end
		function w.finish()
			w.close()
			advance(0.1)
			t.expect(w.live).toBe(0)
			t.expect(adapter.rootCount()).toBe(0)
			app.dispose()
		end
		advance(0.1)
		return w
	end
	local SLIDE = { enter = "slide-left", exit = "slide-right" }
	t.it("slides both pages together by the stack width and reverses on Back", function()
		local w = motionWorld(SLIDE)
		local width = w.adapter.node("/S/Nav").rect.w
		t.expect(width > 0).toBe(true)
		for _, back in { false, true } do
			if back then
				w.routes({})
			else
				w.routes({ 1 })
			end
			local lastRoot, lastPage = nil, nil
			for _ = 1, 8 do
				w.advance(1 / 60)
				local rootX, pageX = w.x("Page0"), w.x("Page1")
				t.expect(w.live).toBe(2)
				t.expect(math.abs((pageX - rootX) - width) < 0.01).toBe(true)
				t.expect(rootX < 0 and pageX > 0).toBe(true)
				if lastRoot then
					t.expect(if back then rootX > lastRoot else rootX < lastRoot).toBe(true)
					t.expect(if back then pageX > lastPage else pageX < lastPage).toBe(true)
				end
				lastRoot, lastPage = rootX, pageX
			end
			t.expect(w.interactive(if back then "Page1" else "Page0")).toBe(false)
			t.expect(w.interactive(if back then "Page0" else "Page1")).toBe(true)
			w.advance(1)
			t.expect(w.live).toBe(1)
			t.expect(w.slot(if back then "Page1" else "Page0")).toBe(nil)
			t.expect(w.x(if back then "Page0" else "Page1")).toBe(0)
		end
		t.expect(w.built.root).toBe(2)
		w.finish()
	end)
	t.it("reclaims an interrupted page from its painted position", function()
		local w = motionWorld(SLIDE)
		w.routes({ 1 })
		w.advance(4 / 60)
		local before = w.x("Page0")
		t.expect(before < 0).toBe(true)
		w.routes({})
		w.advance(1 / 60)
		local after = w.x("Page0")
		t.expect(after > before and after < 0).toBe(true)
		t.expect(after - before < 60).toBe(true)
		t.expect(w.interactive("Page0")).toBe(true)
		t.expect(w.interactive("Page1")).toBe(false)
		w.advance(1)
		t.expect(w.built.root).toBe(1)
		t.expect(w.built.detail1).toBe(1)
		t.expect(w.live).toBe(1)
		t.expect(w.x("Page0")).toBe(0)
		t.expect(w.slot("Page1")).toBe(nil)
		w.finish()
	end)
	t.it("settles rapid push, push, pop on exactly one page", function()
		local w = motionWorld(SLIDE)
		w.routes({ 1 })
		w.advance(2 / 60)
		w.routes({ 1, 2 })
		w.advance(2 / 60)
		t.expect(w.live).toBe(3)
		w.routes({ 1 })
		w.advance(2 / 60)
		t.expect(w.interactive("Page1")).toBe(true)
		w.advance(1)
		t.expect(w.live).toBe(1)
		t.expect(w.built.detail1).toBe(1)
		t.expect(w.interactive("Page1")).toBe(true)
		t.expect(w.slot("Page0")).toBe(nil)
		t.expect(w.slot("Page2")).toBe(nil)
		-- A route withdrawn in the same frame leaves no page behind.
		w.routes({ 1, 3 })
		w.routes({ 1 })
		w.advance(1)
		t.expect(w.live).toBe(1)
		t.expect(w.interactive("Page1")).toBe(true)
		w.finish()
	end)
	t.it("crossfades without travel", function()
		local w = motionWorld({ enter = "fade" })
		w.routes({ 1 })
		local lastIn, lastOut = nil, nil
		for _ = 1, 5 do
			w.advance(1 / 60)
			t.expect(w.live).toBe(2)
			t.expect(w.x("Page1")).toBe(0)
			local a, b = w.opacity("Page1"), w.opacity("Page0")
			t.expect(a > 0 and a < 1 and b > 0 and b < 1).toBe(true)
			if lastIn then
				t.expect(a > lastIn and b < lastOut).toBe(true)
			end
			lastIn, lastOut = a, b
		end
		w.advance(1)
		t.expect(w.live).toBe(1)
		t.expect(w.opacity("Page1")).toBe(1)
		t.expect(w.slot("Page0")).toBe(nil)
		w.finish()
	end)
	t.it("swaps in place under reduced motion", function()
		local w = motionWorld(SLIDE, true)
		w.routes({ 1 })
		w.advance(1 / 60)
		t.expect(w.live).toBe(1)
		t.expect(w.slot("Page0")).toBe(nil)
		t.expect(w.x("Page1")).toBe(0)
		w.routes({})
		w.advance(1 / 60)
		t.expect(w.live).toBe(1)
		t.expect(w.slot("Page1")).toBe(nil)
		t.expect(w.x("Page0")).toBe(0)
		w.finish()
	end)
	t.it("materialize scales the arriving page and dips the leaving one", function()
		do
			local w = motionWorld({ enter = "materialize" })
			w.routes({ 1 })
			local function scaleOf(key)
				local transform = w.slot(key).props.transform
				return if transform then transform.scale else nil
			end
			local grew, faded = false, false
			local last = nil
			for _ = 1, 6 do
				w.advance(1 / 60)
				t.expect(w.live).toBe(2)
				local arriving, leaving = scaleOf("Page1"), scaleOf("Page0")
				t.expect(arriving ~= nil and arriving < 1 and arriving >= 0.96).toBe(true)
				t.expect(leaving ~= nil and leaving < 1 and leaving >= 0.96).toBe(true)
				grew = grew or (last ~= nil and arriving > last)
				faded = faded or w.slot("Page1").canvasGroupInstance.groupTransparency > 0
				last = arriving
			end
			t.expect(grew and faded).toBe(true)
			t.expect(w.interactive("Page0")).toBe(false)
			t.expect(w.interactive("Page1")).toBe(true)
			-- Back mid-flight reclaims the leaving page where it is painted
			w.routes({})
			w.advance(1 / 60)
			t.expect(w.built.root).toBe(1)
			t.expect(w.interactive("Page0")).toBe(true)
			w.advance(1)
			t.expect(w.live).toBe(1)
			t.expect(w.slot("Page1")).toBe(nil)
			t.expect(scaleOf("Page0")).toBe(nil)
			w.finish()
		end
	end)
	t.it("transform grows the arriving page out of its source rect", function()
		local w = motionWorld({ enter = "transform", fromRect = { x = 100, y = 100, w = 40, h = 40 } })
		w.routes({ 1 })
		local last = 0
		for _ = 1, 6 do
			w.advance(1 / 60)
			local slot = w.slot("Page1")
			t.expect(slot.presentedSize.w > last and slot.presentedSize.w < slot.rect.w).toBe(true)
			last = slot.presentedSize.w
		end
		w.advance(1)
		t.expect(w.live).toBe(1)
		t.expect(w.slot("Page1").presentedSize.w).toBe(w.slot("Page1").rect.w)
		w.finish()
	end)
	t.it("reveal clips the arriving page open without fading it", function()
		local w = motionWorld({ enter = "reveal" })
		w.routes({ 1 })
		local last = 0
		for _ = 1, 6 do
			w.advance(1 / 60)
			local slot = w.slot("Page1")
			t.expect(slot.canvasGroupInstance).toBe(nil)
			t.expect(slot.presentedSize.h > last and slot.presentedSize.h < slot.rect.h).toBe(true)
			last = slot.presentedSize.h
		end
		w.advance(1)
		t.expect(w.live).toBe(1)
		t.expect(w.slot("Page0")).toBe(nil)
		t.expect(w.slot("Page1").presentedSize.h).toBe(w.slot("Page1").rect.h)
		w.finish()
	end)
	t.it("coordinated forms swap in place under reduced motion and release mid-flight", function()
		local w = motionWorld({ enter = "materialize" }, true)
		w.routes({ 1 })
		w.advance(1 / 60)
		t.expect(w.live).toBe(1)
		t.expect(w.slot("Page0")).toBe(nil)
		w.finish()
		local moving = motionWorld({ enter = "materialize" })
		moving.routes({ 1 })
		moving.advance(2 / 60)
		t.expect(moving.live).toBe(2)
		moving.finish()
	end)
	t.it("releases every page when disposed mid-flight", function()
		local w = motionWorld(SLIDE)
		w.routes({ 1 })
		w.advance(2 / 60)
		w.routes({ 1, 2 })
		w.advance(2 / 60)
		t.expect(w.live).toBe(3)
		w.finish()
	end)
end)
