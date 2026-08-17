--!strict
--[[ THE INSTANCE-HOST REGISTRY (ADR-0032 step 1).

	`clipHosts` was named for the first of its three triggers and outlived the
	name: a `ScrollView`, an authored `clipChildren`, and a fade group all
	register the same record, and only the first of the three is about clipping.
	ADR-0032 Decision 1 renames it `instanceHosts` and makes one function —
	`registerHost` — the single place an entry is born, "while it still has three
	call sites' worth of meaning rather than three hundred".

	WHY THIS SPEC EXISTS AT ALL, AND WHY IT IS NOT A SOURCE GREP. Every other pin
	on this machinery reads the adapter as TEXT, because `screen_target.luau`
	reaches engine globals at load time and cannot be required under Lune. That
	is not true of `screen_presentation.luau`: it touches `UDim2` and
	`Path2DControlPoint` only INSIDE functions this spec never calls, so the
	registry — `registerHost` / `unregisterHost` / `hostAt` / `hostFor` — can be
	driven for real, headlessly, with plain tables standing in for instances.
	A behavioural instrument beats a substring, and the whole migration is
	measured against this one.

	THE THREE THINGS PINNED HERE:

	1. REGISTRATION IS CREATE-OR-REUSE. A node may declare itself a real parent
	   TWICE — a fade group registers at creation (its engine class decides it)
	   and an authored `clipChildren` registers at the prop write. The second
	   must not replace the first, or every child already re-based against the
	   entry stops being re-based (the guard that used to live inline at the
	   `clipChildren` branch, now `registerHost`'s own contract).

	2. `hostFor` IS A LONGEST-PATH-PREFIX MATCH, and the "path" half is
	   load-bearing: `A/B` must not capture `A/BC/D`, which shares its string
	   prefix and is not its descendant.

	3. `hostFor` DOES NOT SCAN THE REGISTRY. This is the one that decides whether
	   ADR-0032 is affordable. The shipped implementation iterated every
	   registered host on every `create`, which is free at three hosts and
	   quadratic at three hundred — and "register more hosts" IS the migration.
	   Pinned by cost, not by shape: the ancestor walk is bounded by the path's
	   own length, so thousands of unrelated hosts must not slow a lookup down.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local screen_presentation = require("../src/client/screen_presentation")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

-- the region under test, with the three collaborators it composes against
-- stubbed: none of them is reached by the registry half.
local function newRegistry()
	return screen_presentation.new({
		handlesByPath = {},
		refitIconArt = function() end,
		ensureScale = function()
			return nil
		end,
	})
end

-- a stand-in for a GuiObject. The registry stores the instance and never calls
-- it, which is exactly why this spec can run with no engine present.
local function fakeInstance(name: string): any
	return { Name = name }
end

describe("instanceHosts: registration is create-or-reuse, through one function", function()
	it("registerHost builds the record the parenting rule reads", function()
		local r = newRegistry()
		local gui = fakeInstance("Body")
		local entry = r.registerHost("/Root/Body", gui, { x = 4, y = 8, w = 100, h = 50 })

		expect(entry).never().toBeNil()
		expect(entry.instance).toBe(gui)
		expect(entry.path).toBe("/Root/Body")
		expect(entry.rect.x).toBe(4)
		expect(#entry.children).toBe(0)
	end)

	it("a second registration on the same path REUSES the entry, children intact", function()
		local r = newRegistry()
		local first = r.registerHost("/Root/Body", fakeInstance("Body"), nil)
		-- a child re-bases against this exact table, by reference
		table.insert(first.children, { path = "/Root/Body/Row" })

		-- ...and now the node declares itself a real parent a SECOND time, which
		-- is the fade-group-then-clipChildren order the adapter actually produces
		local second = r.registerHost("/Root/Body", fakeInstance("BodyAgain"), nil)

		expect(second).toBe(first)
		expect(#second.children).toBe(1)
		-- the winner is the FIRST instance: replacing it would strand every child
		-- already parented under it
		expect((second.instance :: any).Name).toBe("Body")
	end)

	it("unregisterHost removes it, and hostFor stops matching", function()
		local r = newRegistry()
		r.registerHost("/Root/Body", fakeInstance("Body"), nil)
		expect(r.hostFor("/Root/Body/Row")).never().toBeNil()

		r.unregisterHost("/Root/Body")
		expect(r.hostAt("/Root/Body")).toBeNil()
		expect(r.hostFor("/Root/Body/Row")).toBeNil()
	end)

	it("dropPath unregisters the host as well as the transform record", function()
		local r = newRegistry()
		r.registerHost("/Root/Body", fakeInstance("Body"), nil)
		r.dropPath("/Root/Body")
		expect(r.hostAt("/Root/Body")).toBeNil()
	end)

	it("hostAt is an EXACT lookup and hostFor is an ANCESTOR lookup", function()
		local r = newRegistry()
		r.registerHost("/Root/Body", fakeInstance("Body"), nil)
		-- exact: the host itself
		expect(r.hostAt("/Root/Body")).never().toBeNil()
		expect(r.hostAt("/Root/Body/Row")).toBeNil()
		-- ancestor: its descendant, but never the node itself
		expect(r.hostFor("/Root/Body")).toBeNil()
		expect((r.hostFor("/Root/Body/Row") :: any).path).toBe("/Root/Body")
	end)
end)

describe("hostFor: the deepest registered ancestor wins, and only a real ancestor", function()
	it("nested hosts resolve to the DEEPEST one", function()
		local r = newRegistry()
		r.registerHost("/Root", fakeInstance("Root"), nil)
		r.registerHost("/Root/Body", fakeInstance("Body"), nil)
		r.registerHost("/Root/Body/Scroll", fakeInstance("Scroll"), nil)

		expect((r.hostFor("/Root/Body/Scroll/Row/Label") :: any).path).toBe("/Root/Body/Scroll")
		expect((r.hostFor("/Root/Body/Heading") :: any).path).toBe("/Root/Body")
		expect((r.hostFor("/Root/Chrome") :: any).path).toBe("/Root")
	end)

	it("registration order does not decide the winner — depth does", function()
		local r = newRegistry()
		-- deepest registered FIRST, so a naive "last write wins" would answer /Root
		r.registerHost("/Root/Body/Scroll", fakeInstance("Scroll"), nil)
		r.registerHost("/Root", fakeInstance("Root"), nil)
		expect((r.hostFor("/Root/Body/Scroll/Row") :: any).path).toBe("/Root/Body/Scroll")
	end)

	it("a shared STRING prefix is not a path prefix — /A/B never captures /A/BC/D", function()
		local r = newRegistry()
		r.registerHost("/A/B", fakeInstance("B"), nil)
		expect(r.hostFor("/A/BC/D")).toBeNil()
		expect(r.hostFor("/A/Bee")).toBeNil()
		expect((r.hostFor("/A/B/C") :: any).path).toBe("/A/B")
	end)

	it("no hosts at all is nil, not an error", function()
		local r = newRegistry()
		expect(r.hostFor("/Root/Body/Row/Label")).toBeNil()
		expect(r.hostAt("/Root")).toBeNil()
	end)

	it("a path with no separator has no ancestor to find", function()
		local r = newRegistry()
		r.registerHost("Root", fakeInstance("Root"), nil)
		expect(r.hostFor("Root")).toBeNil()
		expect((r.hostFor("Root/Body") :: any).path).toBe("Root")
	end)
end)

describe("hostFor does not scan the registry, and that is what makes nesting affordable", function()
	--[[ THE COST PIN, AND WHY IT IS A CLOCK RATHER THAN A SHAPE.

		The shipped implementation was `for hostPath, entry in clipHosts do` — a
		full scan of every registered host, on every `create` and every `adopt`.
		At the three hosts a flat tree has, that is free. ADR-0032's whole
		content is "register more hosts", so the same loop becomes O(nodes x
		hosts) precisely as the migration proceeds — the cost arrives with the
		feature, which is the shape of defect this project keeps finding late.

		The replacement walks the candidate path's own separators, so its work is
		bounded by the path's LENGTH and is independent of how many hosts exist.
		The two implementations are indistinguishable by result — every test above
		passes under either — so the only honest instrument is the clock.

		THE MARGIN IS DELIBERATELY ENORMOUS so this is not a flaky test. The scan
		does 4,000 x 20,000 = 80 million string compares; the walk does 20,000
		walks of a 24-character path. That is three-to-four orders of magnitude,
		and the bound below is set two orders above the walk's own measured cost.
		A machine slow enough to fail this is slow enough to fail the suite.
	]]
	it("thousands of unrelated hosts do not slow a lookup", function()
		local r = newRegistry()
		-- 4,000 hosts, none of them an ancestor of the path we will look up
		for i = 1, 4000 do
			r.registerHost(`/Other{i}/Branch`, fakeInstance("x"), nil)
		end
		-- ...and one that is
		r.registerHost("/Root/Body", fakeInstance("Body"), nil)

		local probe = "/Root/Body/Scroll/Row/Label"
		local started = os.clock()
		local found: any = nil
		for _ = 1, 20000 do
			found = r.hostFor(probe)
		end
		local elapsed = os.clock() - started

		-- it still answers correctly, which the clock alone would not prove
		expect((found :: any).path).toBe("/Root/Body")
		expect(elapsed).toBeLessThan(2.0)
	end)
end)

describe("WHICH NODES ARE REAL PARENTS, through the renderer that decides it", function()
	--[[ The block above drives the registry directly. This one drives the whole
		stack — blueprint, renderer, adapter — and asks the question the migration
		is actually about: which declarations produce a real instance parent, and
		what does that cost.

		It runs against the FAKE target, whose host model was added for this: the
		live `parkEligible` refuses to recycle a registered host, and until the fake
		could answer "is this path a host" it had nothing to refuse on. So
		ADR-0032's sharpest trade — "every host registered is one node removed from
		the recycle pool" — was invisible to every headless recycling spec.
	]]
	local function render(screen: any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter, controller
	end

	it("the three shipped triggers each produce a host, and an ordinary container does not", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				-- (1) a ScrollView, a clip host BY CONSTRUCTION
				UI.ScrollView({ id = "Scroll", children = { UI.Box({ id = "Row", surface = "raised" }) } }),
				-- (2) an authored clipChildren on an ordinary container
				UI.VStack({
					id = "Clipped",
					clipChildren = true,
					children = { UI.Box({ id = "In", surface = "raised" }) },
				}),
				-- (3) a fade group
				UI.ZStack({
					id = "Group",
					canvasGroup = true,
					children = { UI.Box({ id = "Kid", surface = "raised" }) },
				}),
				-- ...and the case the whole design turns on: a container that is
				-- pure layout bookkeeping earns NOTHING
				UI.VStack({ id = "Plain", children = { UI.Box({ id = "Leaf", surface = "raised" }) } }),
			},
		}))

		expect(adapter.isHost("/S/Scroll")).toBe(true)
		expect(adapter.isHost("/S/Clipped")).toBe(true)
		expect(adapter.isHost("/S/Group")).toBe(true)
		-- THE ONE THAT KEEPS ELISION ALIVE. A VStack that only says "these are in a
		-- column" never moves independently and composites nothing, so it stays
		-- unregistered and stays elidable — ADR-0032 Decision 2, and the reason
		-- nesting is not "mirror the blueprint in Instances".
		expect(adapter.isHost("/S/Plain")).toBe(false)
		expect(adapter.hostCount()).toBe(3)
	end)

	it("a descendant parents under the NEAREST host, and a flat one under nothing", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.ScrollView({
					id = "Scroll",
					children = {
						UI.ZStack({
							id = "Group",
							canvasGroup = true,
							children = { UI.Box({ id = "Deep", surface = "raised" }) },
						}),
						UI.Box({ id = "Shallow", surface = "raised" }),
					},
				}),
				UI.Box({ id = "Outside", surface = "raised" }),
			},
		}))
		-- the deeper of two nested hosts wins
		expect((adapter.hostOf("/S/Scroll/Group/Deep") :: any).path).toBe("/S/Scroll/Group")
		-- ...and a sibling that is not inside it falls back to the outer one
		expect((adapter.hostOf("/S/Scroll/Shallow") :: any).path).toBe("/S/Scroll")
		-- the group itself parents under the scroll, not under itself
		expect((adapter.hostOf("/S/Scroll/Group") :: any).path).toBe("/S/Scroll")
		-- and everything outside stays flat under the root, which is still the
		-- overwhelming majority of the tree
		expect(adapter.hostOf("/S/Outside")).toBeNil()
	end)

	it("CROPS IS NOT clipChildren: a fade group crops too, because its buffer does", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.ZStack({
					id = "Group",
					canvasGroup = true,
					children = { UI.Box({ id = "Kid", surface = "raised" }) },
				}),
				UI.VStack({
					id = "Clipped",
					clipChildren = true,
					children = { UI.Box({ id = "In", surface = "raised" }) },
				}),
			},
		}))
		-- a CanvasGroup never sets ClipsDescendants, and still crops: it renders its
		-- subtree into a buffer its own size. The framework's real question is "can
		-- something drawn outside a child's box survive here", which is what the
		-- focus ring's float placement turns on — so both answer no, and a plain
		-- move boundary (added by a later step) will answer yes.
		expect((adapter.hostOf("/S/Group/Kid") :: any).crops).toBe(true)
		expect((adapter.hostOf("/S/Clipped/In") :: any).crops).toBe(true)
	end)

	it("THE TRADE: a registered host is refused by the recycle pool", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.VStack({
					id = "Clipped",
					clipChildren = true,
					children = { UI.Box({ id = "In", surface = "raised" }) },
				}),
				UI.VStack({ id = "Plain", children = { UI.Box({ id = "Leaf", surface = "raised" }) } }),
			},
		}))
		-- the host cannot be parked: its subtree lives inside it, so parking it
		-- would take a whole subtree out of the tree behind the renderer's back
		expect(adapter.park(adapter.node("/S/Clipped"))).toBe(false)
		-- ...while an ordinary node inside it recycles exactly as before, which is
		-- what bounds the cost: the refusal is per-host, not per-subtree
		expect(adapter.park(adapter.node("/S/Clipped/In"))).toBe(true)
	end)

	it("a removed host stops being one, or a new node parents into a corpse", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.VStack({
					id = "Clipped",
					clipChildren = true,
					children = { UI.Box({ id = "In", surface = "raised" }) },
				}),
			},
		}))
		expect(adapter.isHost("/S/Clipped")).toBe(true)
		adapter.remove(adapter.node("/S/Clipped"))
		expect(adapter.isHost("/S/Clipped")).toBe(false)
	end)
end)
