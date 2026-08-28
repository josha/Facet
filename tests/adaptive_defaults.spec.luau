--!strict
--[[ ADAPT-1 — ADAPTATION ARRIVES BY ITSELF, OR THE CONTROL SAYS SO.

	The audit's spine finding (`artifacts/release-candidate-review/adapt-audit/
	matrix.md`, critical): every adaptive rung ran on facts the AUTHOR had to hand
	to the control, and a missing fact was SILENT — `picker.resolvePresentation(4,
	nil, 14)` answers "segmented", four long labels crammed onto a phone, where the
	same call with a size class answers "inline". The census made the consequence
	concrete: of seventeen `Picker` call sites in `examples/`, eight wired the
	fact, ten disabled the ladder outright, and ZERO relied on the adaptive
	default, so the touch->sheet rung had never fired in any shipped app.

	The fix is one channel and one rule. An environment publishes itself against
	the CORE it was built on (`src/env/surface_env.luau`), which is the same core
	every control on that surface is built with — so a control asks instead of
	being told. When there is nothing to ask, it refuses to construct, naming the
	host, in the shape `tab_view` has used since 2026-08-16.

	THE FILE IS THE STANDING GUARD for that contract: every case here fails if the
	channel is removed, and the refusal cases fail if the refusal is softened into
	a default. It also pins the two rules that keep the channel honest — a second
	environment on one core is refused rather than guessed at, and re-publishing
	the SAME environment is not ambiguity. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local host = require("../src/client/host")
local actionsLib = require("../src/input/actions")
local surfaceEnv = require("../src/env/surface_env")
local fake_target = require("./lib/fake_target")
local fs = require("@lune/fs")
local UI = Facet.UI

local TOUCH = { touch = true, mouse = false, keyboard = false, gamepad = false }

-- a surface: core, environment, presenter — in the order the world builds them,
-- and NOTHING is passed to any control below
local function surface(w: number, h: number, classes: any?, preferred: string?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	if classes ~= nil then
		env:set("capabilities", classes)
	end
	if preferred ~= nil then
		env:set("preferredInput", preferred)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, system = system, pres = pres }
end

local LONG_OPTIONS = {
	{ value = "a", label = "Alphabetical order" },
	{ value = "b", label = "Beta distribution" },
	{ value = "c", label = "Chronological" },
	{ value = "d", label = "Descending value" },
}

describe("ADAPT-1: the environment is discoverable from the core it was built on", function()
	it("publishes itself, and a control on that core finds it", function()
		local s = surface(390, 844)
		expect(surfaceEnv.find(s.core)).toBe(s.env)
	end)

	it("an unrelated core has nothing to find, and says which of the two reasons", function()
		local bare = Facet.newCore()
		local found, reason = surfaceEnv.find(bare)
		expect(found).toBeNil()
		expect(reason).toBe("none")
	end)

	it("TWO environments on one core are refused, never resolved by coin flip", function()
		local core = Facet.newCore()
		Facet.newEnvironment(core)
		Facet.newEnvironment(core)
		local found, reason = surfaceEnv.find(core)
		expect(found).toBeNil()
		expect(reason).toBe("ambiguous")
		-- and a control on that core says so, naming the way out
		local ok, err = pcall(function()
			return Facet.Controls.Picker(core, {
				id = "P",
				options = LONG_OPTIONS,
				selected = core:signal("a"),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "MORE THAN ONE environment", 1, true) ~= nil).toBe(true)
	end)

	it("re-publishing the SAME environment is not ambiguity", function()
		local s = surface(390, 844)
		surfaceEnv.publish(s.core, s.env)
		expect(surfaceEnv.find(s.core)).toBe(s.env)
	end)

	--[[ THE CORE'S LIFETIME IS THE FACT'S LIFETIME (re-review MEDIUM-3).

		The registry was a module table weak on BOTH halves, so an ordinary bootstrap
		— build a core, build an environment on it, build controls later — worked or
		hard-erred depending on when the collector ran, because nothing but that
		table held the environment.

		The obvious repair (strong value, weak key) is a trap in this VM and the
		probe below is why the registration moved onto the CORE instead: a
		weak-keyed table whose value references its own key does not behave like an
		ephemeron here, so "strong value" would have pinned every core and every
		environment for the process lifetime. Both halves are asserted — the fact
		survives collection, and the core does NOT.

		THE INSTRUMENT: Luau's `collectgarbage` accepts only `"count"`, so collection
		is forced the way the re-review forced it — churning enough short-lived
		tables through the allocator that a weakly-held object would certainly have
		gone. The control (`__mode = "kv"`) proves the churn really collects, so a
		green result here is the design's doing and not the collector's laziness. ]]
	--[[ CHURN, AND A CANARY THAT SAYS WHETHER IT WORKED. Luau's `collectgarbage`
		accepts only `"count"`, so collection is forced by allocation pressure — and
		whether that pressure actually collects depends on what else the VM is
		holding, which differs between this file alone and the whole suite (measured:
		these two cases collected standalone and did NOT under the full run). A probe
		that asserts a collection it cannot compel is a flaky test, so the canary is
		an entry that MUST die if anything died at all, and the case says so rather
		than pretending. ]]
	local function churnAndCanary(): boolean
		local canary: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
		canary[{}] = true -- the key is unreachable the instant it is written
		for _ = 1, 40 do
			local waste = table.create(20000)
			for i = 1, 20000 do
				waste[i] = { i }
			end
		end
		for _ in canary do
			return false
		end
		return true
	end

	it("MEDIUM-3: an environment nothing else holds is still findable from its core", function()
		local core = Facet.newCore()
		-- every reference to the environment is dropped with the frame that built
		-- it. A dead local still occupies its register until the frame goes, which
		-- is how a probe like this lies, so it is a FUNCTION and not a `do` block
		local function build()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		end
		build()
		churnAndCanary()

		-- UNCONDITIONAL, because the answer no longer depends on the collector at
		-- all: the registration is the core's own. Under the old weak-valued module
		-- table this went nil whenever the collector ran, which is the defect.
		local found, reason = surfaceEnv.find(core)
		expect(`the fact survived: {found ~= nil} ({tostring(reason)})`).toBe("the fact survived: true (nil)")
		-- ...and it is not merely findable, it still answers: a control builds
		local picker = Facet.Controls.Picker(core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = core:signal("a"),
		})
		expect(picker.dump().presentation).toBe("inline")
		expect(picker.dump().sizeClassFrom).toBe("core")
		picker.dispose()
	end)

	it("MEDIUM-3: a core nothing else holds is collected, registration and all", function()
		local probe: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
		local function build()
			local core = Facet.newCore()
			probe[core] = true
			Facet.newEnvironment(core)
		end
		build()
		local collected = churnAndCanary()
		local retained = 0
		for _ in probe do
			retained += 1
		end
		-- THE HONEST FORM: when nothing was collected at all this case has nothing
		-- to say, and says that instead of asserting a collection it did not get.
		-- When the collector did run, the registration must have gone with its core
		-- — which is the whole reason it lives there rather than in a module table.
		local verdict = if not collected then "the collector did not run" else `cores retained: {retained}`
		expect(verdict).toBe(if not collected then "the collector did not run" else "cores retained: 0")
	end)

	--[[ …AND THE MECHANISM, PINNED, because it is the reason the case above can
		pass at all: the registration is a field ON THE CORE rather than an entry in
		a module table, so there is no process-global store to leak and no weak-table
		semantics in the answer. A reader who moves it back into a module table
		reddens this. ]]
	it("MEDIUM-3: the registration lives on the core, not in a module-level store", function()
		local core = Facet.newCore()
		expect(rawget(core :: any, "__facetSurfaceEnv")).toBeNil()
		local env = Facet.newEnvironment(core)
		local live = rawget(core :: any, "__facetSurfaceEnv")
		expect(`the core holds its own registration: {type(live)}`).toBe("the core holds its own registration: table")
		expect((live :: any)[1]).toBe(env)
		surfaceEnv.unpublish(core, env)
		expect(rawget(core :: any, "__facetSurfaceEnv")).toBeNil()
	end)

	--[[ …AND AMBIGUITY IS A COUNT, NOT A LATCH (re-review LOW-4). The first
		version set a flag nothing could clear, so a core whose environment was
		rebuilt — a hot reload, an Edit-mode preview stood back up — was bricked for
		every adaptive control for the rest of the session, with a build error. ]]
	it("MEDIUM-3: unpublishing one of two environments restores the unambiguous answer", function()
		local core = Facet.newCore()
		local first = Facet.newEnvironment(core)
		first:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		local second = Facet.newEnvironment(core)
		second:set("viewportRect", { x = 0, y = 0, w = 1400, h = 900 })
		expect(select(2, surfaceEnv.find(core))).toBe("ambiguous")

		expect(surfaceEnv.unpublish(core, first)).toBe(true)
		expect(surfaceEnv.find(core)).toBe(second)
		-- releasing the same registration twice is a no-op, so an idempotent
		-- teardown may call it twice
		expect(surfaceEnv.unpublish(core, first)).toBe(false)

		local picker = Facet.Controls.Picker(core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = core:signal("a"),
		})
		expect(picker.dump().presentation).toBe("segmented") -- the SECOND environment's width
		picker.dispose()

		-- and releasing the survivor leaves nothing rather than a stale answer
		expect(surfaceEnv.unpublish(core, second)).toBe(true)
		local found, reason = surfaceEnv.find(core)
		expect(`{tostring(found)} / {tostring(reason)}`).toBe("nil / none")
	end)
end)

describe("ADAPT-1: the six adaptive controls take their facts from the surface", function()
	it("Picker: a compact surface collapses four long labels to the row list, unwired", function()
		local phone = surface(390, 844)
		local wide = surface(1400, 900)
		local onPhone = Facet.Controls.Picker(phone.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = phone.core:signal("a"),
		})
		local onDesktop = Facet.Controls.Picker(wide.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = wide.core:signal("a"),
		})
		-- FOUR options is the count the ladder still calls segmented; the WIDTH
		-- axis is the one that was dead, and it is the one this asserts
		expect(onPhone.dump().presentation).toBe("inline")
		expect(onPhone.dump().sizeClassFrom).toBe("core")
		expect(onDesktop.dump().presentation).toBe("segmented")
		onPhone.dispose()
		onDesktop.dispose()
	end)

	it("Picker: an authored size class still wins over the surface's", function()
		local wide = surface(1400, 900)
		local pinned = Facet.Controls.Picker(wide.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = wide.core:signal("a"),
			sizeClass = "compact",
		})
		expect(pinned.dump().presentation).toBe("inline")
		expect(pinned.dump().sizeClassFrom).toBe("spec")
		pinned.dispose()
	end)

	it("PopupButton: touch resolves the SHEET with nothing wired at all", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local popup = Facet.Controls.PopupButton(phone.core, {
			id = "Choice",
			value = phone.core:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
			},
		})
		expect(popup.presentation()).toBe("sheet")
		expect(popup.dump().factsFrom).toBe("core")
		popup.dispose()

		local desktop = surface(1400, 900)
		local pointer = Facet.Controls.PopupButton(desktop.core, {
			id = "Choice",
			value = desktop.core:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
			},
		})
		expect(pointer.presentation()).toBe("menu")
		pointer.dispose()
	end)

	it("Menu: the same rung, through the same recipe, unwired", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local menu = Facet.Controls.Menu(phone.core, {
			id = "M",
			trigger = UI.Button({ id = "T", label = "More" }),
			items = {
				{ id = "a", label = "Rename", onSelect = function() end },
				{ id = "b", label = "Duplicate", onSelect = function() end },
			},
		})
		expect(menu.presentation()).toBe("sheet")
		expect(menu.dump().factsFrom).toBe("core")
		menu.dispose()
	end)

	--[[ MEASURED, NOT DUMPED. The mark gap is a theme METRIC NAME inside the
		control, so the honest instrument is the solved geometry: mount the same
		five-mark run on two surfaces and read the space BETWEEN two marks. (The
		pitch is identical on both — the marks divide the offer — so a pitch
		comparison would have passed with the fix removed. The gap is the fact.) ]]
	it("LevelPicker: the touch run is wider than the pointer run, with no `env` key", function()
		local function markGap(s: any): number
			local picker = Facet.Controls.LevelPicker(s.core, { id = "L", value = s.core:signal(3), count = 5 })
			s.pres.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
			s.pres.refresh()
			local first = s.adapter.node("/S/L/Levels/Level1")
			local second = s.adapter.node("/S/L/Levels/Level2")
			expect(`first mark solved: {first ~= nil}`).toBe("first mark solved: true")
			expect(`second mark solved: {second ~= nil}`).toBe("second mark solved: true")
			return second.rect.x - (first.rect.x + first.rect.w)
		end
		local touchGap = markGap(surface(390, 844, TOUCH, "Touch"))
		local pointerGap = markGap(surface(390, 844))
		expect(touchGap > pointerGap).toBe(true)
	end)

	it("Table: a row on a touch surface clears the target floor with no `env` key (ADAPT-11)", function()
		--[[ THE AUDIT'S MEASUREMENT (matrix ADAPT-11, high): "Table row height
			defaults to 36px on every combo, including compact touch portrait, because
			`table.luau` returns `rowBoxFor(nil, ...)` when `spec.env` is absent, which
			makes `classes` nil and the paradigm `pointer`. The engine hit rect is still
			expanded to 44, so the tap survives — but adjacent 44px expanders then
			OVERLAP on a 38px pitch, the same class of defect measured in the menu
			plate." Wired, it was already correct: 44 on touch, 36 on pointer. The
			ladder was right and nobody was climbing it. ]]
		local function rowHeight(s: any): number
			local tbl = Facet.Controls.Table(s.core, {
				id = "T",
				rows = s.core:signal({ { id = "a", name = "Aria" }, { id = "b", name = "Bo" } }),
				key = function(item: any)
					return item.id
				end,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(item: any)
							return item.name
						end,
					},
				},
				selection = "single",
			})
			s.pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
			s.pres.refresh()
			local row = s.adapter.node("/S/T/Main/Body/Rows/[a@0]/Row")
			expect(`row solved: {row ~= nil}`).toBe("row solved: true")
			return row.rect.h
		end
		local touch = rowHeight(surface(390, 844, TOUCH, "Touch"))
		local pointer = rowHeight(surface(390, 844))
		-- the theme's own touch floor is `targetSizes.minimum`, which is 44 and is
		-- the number a fingertip is owed
		expect(touch >= 44).toBe(true)
		expect(touch > pointer).toBe(true)
	end)

	it("Table: an authored `env` still wins over the surface's, and a pinned height still wins over both", function()
		-- the two escapes, because a channel that cannot be overridden is a channel
		-- an author cannot reason about
		local phone = surface(390, 844, TOUCH, "Touch")
		local pinned = Facet.Controls.Table(phone.core, {
			id = "P",
			rows = phone.core:signal({ { id = "a", name = "Aria" } }),
			key = function(item: any)
				return item.id
			end,
			columns = {
				{
					id = "name",
					width = { type = "fill", weight = 1 },
					value = function(item: any)
						return item.name
					end,
				},
			},
			rowHeight = 52,
			selection = "single",
		})
		phone.pres.present(UI.Screen({ id = "S", children = { pinned.blueprint } }))
		phone.pres.refresh()
		expect(phone.adapter.node("/S/P/Main/Body/Rows/[a@0]/Row").rect.h).toBe(52)
	end)

	it("Table: the row box and the COLUMN RESERVATION read one environment (R1-I4)", function()
		--[[ REVIEW ROUND 1, ISSUE-4. ADAPT-11 adopted the implicit environment at
			ONE of seven read sites. The dangerous half was `cellSides`, which feeds
			`reserved` -> `room` in `table_columns.layout`: an unwired table took its
			ROW HEIGHT from the live theme and its COLUMN RESERVATION from the neutral
			snapshot. Before the collapse paradigm that mismatch cost a few pixels of
			override width; after it, it decides WHICH COLUMN IS REMOVED.

			THE OBSERVABLE IS THE COLLAPSE THRESHOLD, because that is where the
			reservation actually lands. `reserved` is the row card's own padding, and
			Pixel Quest carves a border on `selection` where the built-in neutral
			snapshot carves nothing — so on a carved surface a two-column table with
			100px floors runs out of room exactly that much EARLIER. Nothing here
			reaches into a private: the widest viewport at which a column disappears is
			a number the player could count.

			RE-MEASURED 2026-08-27 (task THEME, ADR-0059 Decision 5): carved 231 -> 215,
			flat unchanged at 199, difference 32 -> 16. Pixel Quest's `selection` recipe
			now reserves the TWO design pixels its art carves rather than the four its
			nine-slice border needs for the stretch rule, so it takes 8px a side where
			it used to take 16 — and this case's whole point is that the number it
			reserves and the number the table spends are ONE number, which is exactly
			what a halved reservation halving this threshold demonstrates. The property
			is untouched; only the package's own figure moved.

			MEASURED: carved 215, flat 199 — the 16px the package reserves, exactly. A
			table reading two environments answered 199 while its rows were sized for
			the carved package. ]]
		local pixelQuest = require("../examples/themes/pixel_quest")
		local function collapseThreshold(themed: boolean): number
			local s = surface(400, 600, TOUCH, "Touch")
			if themed then
				s.env:set("themeMetrics", Facet.themes.resolve(pixelQuest.build(Facet.themes), nil, {}))
			end
			local tbl = Facet.Controls.Table(s.core, {
				id = "T",
				rows = s.core:signal({ { id = "a", name = "Aria" } }),
				key = function(item: any)
					return item.id
				end,
				columns = {
					{
						id = "one",
						width = { type = "fill", weight = 1 },
						minWidth = 100,
						value = function(item: any)
							return item.name
						end,
					},
					{
						id = "two",
						width = { type = "fill", weight = 1 },
						minWidth = 100,
						value = function(item: any)
							return item.name
						end,
					},
				},
				selection = "single",
			})
			s.pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
			s.pres.refresh()
			for width = 400, 120, -1 do
				s.env:set("viewportRect", { x = 0, y = 0, w = width, h = 600 })
				for _ = 1, 3 do
					s.pres.tick(1 / 60)
					s.pres.refresh()
				end
				if #tbl.dump().hiddenColumns > 0 then
					return width
				end
			end
			return -1
		end
		local carved = collapseThreshold(true)
		local flat = collapseThreshold(false)
		expect(`carved {carved} vs flat {flat}`).toBe("carved 215 vs flat 199")
		-- ...and the difference IS the package's own reservation rather than a
		-- number that happens to differ
		expect(`difference: {carved - flat}`).toBe("difference: 16")
	end)

	it("TextInput: the field lifts itself off the keyboard with no `env` key", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local field = Facet.Controls.TextInput(phone.core, {
			id = "Name",
			value = phone.core:signal("hello"),
			actionSystem = phone.system,
		})
		phone.pres.present(UI.Screen({ id = "S", children = { field.blueprint } }), {
			sinkNavigation = true,
			onActivate = function(path, meta)
				field.api.handleActivate(path, meta)
			end,
			onGeometry = function(rectOf)
				field.api.syncGeometry(rectOf)
			end,
			keepVisibleOffset = field.api.keepVisibleOffset,
		})
		phone.pres.refresh()
		expect(field.dump().occlusionOffset).toBe(0)
		phone.adapter.tap("/S/Name/Field")
		phone.pres.refresh()
		expect(field.dump().editing).toBe(true)
		-- the on-screen keyboard arrives as an environment fact, over the field
		phone.env:set("keyboardOcclusionRect", { x = 0, y = 40, w = 390, h = 804 })
		phone.pres.refresh()
		expect(field.dump().occlusionOffset > 0).toBe(true)
		field.dispose()
	end)

	it("TabView: an automatic placement no longer needs the author to hand it anything", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local tabs = Facet.Controls.TabView(phone.core, {
			id = "TV",
			selection = phone.core:signal("a"),
			tabs = {
				{
					id = "a",
					label = "Alpha",
					content = function()
						return UI.Text({ id = "A", text = "a" })
					end,
				},
				{
					id = "b",
					label = "Beta",
					content = function()
						return UI.Text({ id = "B", text = "b" })
					end,
				},
			},
		})
		expect(tabs.dump().placement).toBe("bottomBar")
		expect(tabs.dump().placementSource).toBe("policy")
		tabs.dispose()
	end)
end)

describe("ADAPT-1: a control that cannot get its facts refuses, naming the host", function()
	local function refusal(build: (core: any) -> ()): string
		local core = Facet.newCore()
		local ok, err = pcall(function()
			build(core)
		end)
		expect(ok).toBe(false)
		return tostring(err)
	end

	it("Picker, PopupButton, Menu and TextInput each name the fix, not the symptom", function()
		local messages = {
			refusal(function(core)
				Facet.Controls.Picker(core, { id = "P", options = LONG_OPTIONS, selected = core:signal("a") })
			end),
			refusal(function(core)
				Facet.Controls.PopupButton(core, {
					id = "C",
					value = core:signal("one"),
					options = { { id = "one", label = "One" }, { id = "two", label = "Two" } },
				})
			end),
			refusal(function(core)
				Facet.Controls.Menu(core, {
					id = "M",
					trigger = UI.Button({ id = "T", label = "More" }),
					items = { { id = "a", label = "Rename", onSelect = function() end } },
				})
			end),
			refusal(function(core)
				Facet.Controls.TextInput(core, { id = "F", value = core:signal("") })
			end),
		}
		for _, message in messages do
			-- the refusal names the HOST (the thing that would have supplied the
			-- fact) and the explicit key (the thing the caller can do right now)
			expect(string.find(message, "Facet.client.host.new", 1, true) ~= nil).toBe(true)
			expect(string.find(message, "env", 1, true) ~= nil).toBe(true)
		end
	end)

	it("...and a DECLARED presentation consults no ladder, so it never refuses", function()
		local core = Facet.newCore()
		local declared = Facet.Controls.Picker(core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = core:signal("a"),
			presentation = "segmented",
		})
		expect(declared.dump().presentation).toBe("segmented")
		expect(declared.dump().sizeClassFrom).toBe("none")
		declared.dispose()
	end)
end)

describe("ADAPT-1: the client host is what makes this free on a real surface", function()
	--[[ A DISPOSED HOST IS A SURFACE THAT NO LONGER EXISTS (re-review LOW-4), so
		the registration goes with it — otherwise a core whose surface was torn down
		and stood back up would be permanently ambiguous, which is the bricking case
		the count-based registry exists to prevent. `dispose` releases what the host
		BUILT, and the environment was step two of what it built. ]]
	it("dispose releases the environment the host registered", function()
		local adapter = fake_target.new()
		local h = host.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core: any)
				return actionsLib.newSystem(core)
			end,
			bindEnv = function(env: any)
				env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
				return function() end
			end,
			connectFrame = function()
				return function() end
			end,
		})
		expect(surfaceEnv.find(h.core)).toBe(h.env)
		h.dispose()
		local found, reason = surfaceEnv.find(h.core)
		expect(`{tostring(found)} / {tostring(reason)}`).toBe("nil / none")
		-- ...so the same core can host a SECOND surface without being ambiguous
		local second = Facet.newEnvironment(h.core)
		second:set("viewportRect", { x = 0, y = 0, w = 1400, h = 900 })
		expect(surfaceEnv.find(h.core)).toBe(second)
	end)

	it("a hosted screen's controls adapt with zero authoring", function()
		local adapter = fake_target.new()
		local frames: { (dt: number) -> () } = {}
		local h = host.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core: any)
				return actionsLib.newSystem(core)
			end,
			bindEnv = function(env: any)
				-- the engine's own facts, as the real binder would deliver them
				env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
				env:set("capabilities", TOUCH)
				env:set("preferredInput", "Touch")
				return function() end
			end,
			connectFrame = function(fn)
				table.insert(frames, fn)
				return function() end
			end,
		})

		-- the author writes this and nothing else
		local picker = Facet.Controls.Picker(h.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = h.core:signal("a"),
		})
		local popup = Facet.Controls.PopupButton(h.core, {
			id = "C",
			value = h.core:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
			},
		})
		h.presenter.present(UI.Screen({ id = "S", children = { picker.blueprint, popup.blueprint } }))
		for _, fn in frames do
			fn(1 / 60)
		end
		expect(picker.dump().presentation).toBe("inline")
		expect(picker.dump().sizeClassFrom).toBe("core")
		expect(popup.presentation()).toBe("sheet")
		picker.dispose()
		popup.dispose()
		h.dispose()
	end)
end)

--[[ THE REFUSAL IS A BUILD ERROR, SO IT HAS TO BE WHERE THE READER IS.

	Re-review MEDIUM-1: `newTextInput` refuses UNCONDITIONALLY without an
	environment — it is the widest new build error this wave introduced, 26
	constructions in this repository alone — and it was the one refusal `api.md`
	was never updated for: the `env` bullet still read "when provided,
	keyboard-occlusion keep-visible is active", which is a promise of graceful
	degradation the control no longer keeps.

	This is the guard rather than a one-off correction, because the class is
	general: a control whose CONSTRUCTION can fail for want of the environment must
	say so in its own section of the reference, where somebody reading before they
	write is standing. It is the same shape as the deprecation-marking check in
	`api_surface.spec` — a mechanical read of the reference, scoped to the section
	the surface owns — and it reddens the moment a fifth control adopts the refusal
	without documenting it. ]]
describe("ADAPT-1: every control that can refuse for want of the environment says so in api.md", function()
	--[[ THE LIST IS DISCOVERED, NOT TYPED (re-review round 2, MEDIUM-1 residual).

		The first version of this guard enumerated four names by hand, which is the
		one thing a guard against "somebody forgot" must not do: it checked the four
		an author remembered and was blind to the fifth. `newTabView` had refused for
		want of an environment since `44a495f` — under the exact criterion this
		block's own title states — with an api.md section that named neither the
		refusal nor the environment, and the guard could not see it.

		So the input is the SOURCE. A control refuses for want of the environment in
		exactly one of two shapes today, and both are read out of `src/controls/`:

		  1. it calls the shared refusal helper, `surfaceEnv.resolve("newX", …)`,
		     whose message always names the environment and the host — the picker,
		     popup button, menu and text field;
		  2. it raises its own construction error in the framework's uniform
		     `Facet newX('<id>'): …` shape, with an environment named inside it —
		     `newTabView`, which predates the helper and keeps its own message
		     because it has three routes to report rather than two.

		Shape 2 is matched through a WINDOW of characters after the error prefix,
		the same technique `api_surface.spec`'s deprecation-marking check uses on
		lines: a construction error that refuses for want of a fact has to NAME that
		fact to be worth raising, so "an environment is mentioned inside the message"
		is the property, not a spelling. Measured across all 33 control modules the
		two predicates find exactly five controls and no false positives.

		Both halves have a bite-check below: a synthetic module that refuses is
		discovered, and a doc section removed from the text is reported. ]]
	local REFUSAL_WINDOW = 500

	-- the control names a single source refuses under, by the two shapes above
	local function refusalsIn(source: string): { [string]: boolean }
		local found: { [string]: boolean } = {}
		for name in string.gmatch(source, 'surfaceEnv%.resolve%(%s*"(new%w+)"') do
			found[name] = true
		end
		for at, name in string.gmatch(source, "()Facet (new%w+)%('") do
			local window = string.sub(source, math.max(1, at - 200), at + REFUSAL_WINDOW)
			if string.find(window, "environment", 1, true) ~= nil then
				found[name] = true
			end
		end
		return found
	end

	local function refusingControls(): { string }
		local names: { [string]: boolean } = {}
		for _, entry in fs.readDir("src/controls") do
			if string.match(entry, "%.luau$") == nil then
				continue
			end
			for name in refusalsIn(fs.readFile(`src/controls/{entry}`)) do
				names[name] = true
			end
		end
		local out: { string } = {}
		for name in names do
			table.insert(out, name)
		end
		table.sort(out)
		return out
	end

	-- api.md's `### \`newX\`` sections, each running to the next heading
	local function sectionsOf(apiText: string): { [string]: string }
		local sections: { [string]: string } = {}
		local order: { { name: string, at: number } } = {}
		for at, name in string.gmatch(apiText, "()### `(new%w+)`") do
			table.insert(order, { name = name, at = at })
		end
		for index, entry in order do
			local stop = if order[index + 1] ~= nil then order[index + 1].at - 1 else #apiText
			sections[entry.name] = string.sub(apiText, entry.at, stop)
		end
		return sections
	end

	-- the controls whose own section fails to name BOTH the refusal and the fact
	local function undocumented(apiText: string, names: { string }): { string }
		local sections = sectionsOf(apiText)
		local missing: { string } = {}
		for _, name in names do
			local section = sections[name]
			local body = if section ~= nil then string.lower(section) else ""
			if
				section == nil
				or string.find(body, "refus", 1, true) == nil
				or string.find(body, "environment", 1, true) == nil
			then
				table.insert(missing, name)
			end
		end
		return missing
	end

	it("the refusing controls are read out of the sources, and there are seven today", function()
		--[[ `newVirtualList` joined them in the CAROUSEL wave: `itemExtent = "cards"`
			with no authored `cards.perView` arranges the rail from the live
			interaction class and the space it got, so it refuses without an
			environment rather than silently taking the large-screen answer.

			`newVirtualGrid` joined on 2026-08-22 (ADR-0043) for a NARROWER reason, and
			it is worth naming because it is the first entry here that refuses only
			SOMETIMES. It adapts nothing; what it needs an environment for is a fact —
			the live theme snapshot a metric-name gutter resolves against, and the
			screen `viewportExtent = "auto"` seeds its first window from. So it
			refuses on an AMBIGUOUS core (more than one live environment: the
			framework would be guessing which surface this grid belongs to) and only
			when the build actually asks for one of those two facts. A plain numeric
			grid on the same core is built without complaint. ]]
		expect(table.concat(refusingControls(), " ")).toBe(
			"newMenu newPicker newPopupButton newTabView newTextInput newVirtualGrid newVirtualList"
		)
	end)

	--[[ BITE-CHECK ON THE DISCOVERY HALF: a module written in either shape is
		found. Without this, a scanner that had quietly stopped matching (a rename of
		the helper, a reformatting of the error prefix) would report an EMPTY list and
		the guard below would pass by having nothing to check. ]]
	it("a control that refuses in either shape is discovered by the scan itself", function()
		local viaHelper = [[
			local env = surfaceEnv.resolve("newSynthetic", id, core, spec.env, "it adapts")
		]]
		local viaOwnError = [[
			error(`Facet newOther('{id}'): an automatic thing reads a policy, so it needs an environment.`, 0)
		]]
		local silent = [[
			error(`Facet newQuiet('{id}'): \`options\` must be a non-empty array`, 0)
		]]
		expect(refusalsIn(viaHelper).newSynthetic).toBe(true)
		expect(refusalsIn(viaOwnError).newOther).toBe(true)
		-- ...and a construction error that is NOT about the environment is not one
		expect(refusalsIn(silent).newQuiet).toBeNil()
	end)

	it("each discovered control's own section names the refusal and the environment", function()
		local text = fs.readFile("docs/reference/api.md")
		local missing = undocumented(text, refusingControls())
		expect(`undocumented refusals in api.md: {table.concat(missing, ", ")}`).toBe(
			"undocumented refusals in api.md: "
		)
	end)

	--[[ BITE-CHECK ON THE DOCUMENTATION HALF, run against the REAL text with one
		section cut out of it in memory — so this cannot pass by the check having
		stopped looking, and no file is written to prove it. ]]
	it("removing a control's section from api.md is reported", function()
		local text = fs.readFile("docs/reference/api.md")
		local sections = sectionsOf(text)
		for _, name in refusingControls() do
			local section = sections[name]
			expect(`{name} has a section: {section ~= nil}`).toBe(`{name} has a section: true`)
			local without =
				string.gsub(text, string.gsub(section :: string, "[%%%[%]%(%)%.%+%-%*%?%^%$]", "%%%1"), "", 1)
			expect(`{name} removed is reported: {table.concat(undocumented(without, { name }), ",")}`).toBe(
				`{name} removed is reported: {name}`
			)
		end
	end)
end)
