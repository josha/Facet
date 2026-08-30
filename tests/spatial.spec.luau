--!strict
-- The future spatial seam (roadmap Step 4, ADR-0021; ledger rows XP-D1..XP-D5).
--
-- These cases guard a promise and a boundary. The promise: adding spatial input
-- later must be an adapter change, not a rewrite — so a two-dimensional
-- callback written today has to keep working when the optional fields arrive.
-- The boundary: Facet does not support VR, and nothing in the shipped surface
-- may start saying it does.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src")
local spatial = require("../src/input/spatial")
local environment = require("../src/env/environment")
local custom = require("../src/core/custom")
local target_contract = require("../src/render/target_contract")
local fake_target = require("./lib/fake_target")
local mountLib = require("../src/mount")
local renderer = require("../src/render/renderer")

local RAY = {
	ray = { origin = { x = 0, y = 2, z = 0 }, direction = { x = 0, y = 0, z = -2 } },
	hit = { x = 0, y = 2, z = -5 },
	pose = { position = { x = 0, y = 2, z = 0 }, forward = { x = 0, y = 0, z = -1 } },
	handedness = "right",
	phase = "changed",
	target = "GarageSurface",
}

describe("presentation facts (XP-D1)", function()
	it("defaults to a flat screen and never names a device", function()
		local core = custom.new()
		local env = environment.new(core)
		expect(env:get("presentationSpace"):get()).toBe("screen")
		local profile = env:get("presentationProfile"):get()
		expect(profile.space).toBe("screen")
		expect(profile.flat).toBe(true)
		expect(profile.world).toBe(false)
	end)

	it("a billboard is still flat; only a world surface is not", function()
		local core = custom.new()
		local env = environment.new(core)
		env:set("presentationSpace", "billboard")
		expect(env:get("presentationProfile"):get().flat).toBe(true)
		expect(env:get("presentationProfile"):get().world).toBe(false)
		env:set("presentationSpace", "world")
		expect(env:get("presentationProfile"):get().flat).toBe(false)
		expect(env:get("presentationProfile"):get().world).toBe(true)
	end)

	it("clamps a malformed platform fact to screen rather than propagating it", function()
		local core = custom.new()
		local env = environment.new(core)
		env:set("presentationSpace", "holodeck")
		expect(env:get("presentationProfile"):get().space).toBe("screen")
		env:set("presentationSpace", 42)
		expect(env:get("presentationProfile"):get().space).toBe("screen")
	end)

	it("spatial pointing is a capability among others, never a replacement mode", function()
		local core = custom.new()
		local env = environment.new(core)
		-- the default: no spatial pointer anywhere
		expect(env:get("interactionClasses"):get().spatialPointer).toBe(false)
		-- a spatial session may have a ray AND a gamepad AND a keyboard at once;
		-- adding the ray must not remove any of them
		env:set(
			"capabilities",
			{ keyboard = true, mouse = false, touch = false, gamepad = true, spatialPointer = true }
		)
		env:set("preferredInput", "Gamepad")
		local classes = env:get("interactionClasses"):get()
		expect(classes.spatialPointer).toBe(true)
		expect(classes.gamepad).toBe(true)
		expect(classes.keyboard).toBe(true)
		expect(classes.primary).toBe("gamepad")
	end)
end)

describe("normalized spatial event data (XP-D2)", function()
	it("normalizes a full platform event and derives the distance from the geometry", function()
		local s = spatial.normalize(RAY)
		expect(s ~= nil).toBe(true)
		expect((s :: any).handedness).toBe("right")
		expect((s :: any).phase).toBe("changed")
		expect((s :: any).target).toBe("GarageSurface")
		-- the direction is unit-normalized, so a platform reporting a length-2
		-- vector cannot make every downstream ray march twice as fast
		expect((s :: any).ray.direction.z).toBe(-1)
		-- distance is DERIVED (pose 0,2,0 -> hit 0,2,-5), never taken on trust
		expect((s :: any).distance).toBe(5)
	end)

	it("clamps hostile platform data instead of erroring or propagating it", function()
		expect(spatial.normalize(nil)).toBe(nil)
		expect(spatial.normalize("nonsense")).toBe(nil)
		-- a zero-length direction is degenerate: the ray is dropped, not divided by zero
		local degenerate = spatial.normalize({
			ray = { origin = { x = 0, y = 0, z = 0 }, direction = { x = 0, y = 0, z = 0 } },
			hit = { x = 1, y = 1, z = 1 },
		})
		expect(degenerate ~= nil).toBe(true)
		expect((degenerate :: any).ray).toBe(nil)
		expect((degenerate :: any).hit.x).toBe(1)
		-- unknown vocabulary values fall back rather than leaking
		local odd = spatial.normalize({ hit = { x = 0, y = 0, z = 0 }, handedness = "tentacle", phase = "wobbling" })
		expect((odd :: any).handedness).toBe("unknown")
		expect((odd :: any).phase).toBe("none")
		-- NaN and infinity are not positions
		expect(spatial.normalize({ hit = { x = 0 / 0, y = 0, z = 0 } })).toBe(nil)
		expect(spatial.normalize({ hit = { x = math.huge, y = 0, z = 0 } })).toBe(nil)
	end)

	it("an event with no spatial content is not a spatial event", function()
		expect(spatial.normalize({ phase = "began", handedness = "left" })).toBe(nil)
		expect(spatial.normalize({})).toBe(nil)
	end)

	it("extending a 2D position leaves every 2D field exactly as it was", function()
		local pos = { x = 120, y = 44, pointerType = "mouse" }
		local extended = spatial.extend(pos, RAY)
		expect(extended.x).toBe(120)
		expect(extended.y).toBe(44)
		expect(extended.pointerType).toBe("mouse")
		expect(spatial.isFlat(extended)).toBe(false)
		expect((spatial.of(extended) :: any).target).toBe("GarageSurface")
		-- the original is untouched: extend returns a new value
		expect(pos.spatial).toBe(nil)
		-- and with nothing spatial to add, the position comes back unchanged
		expect(spatial.extend(pos, {})).toBe(pos)
	end)

	it("every event Facet produces today is flat", function()
		expect(spatial.isFlat({ x = 1, y = 2 })).toBe(true)
		expect(spatial.isFlat({ x = 1, y = 2, pointerType = "touch" })).toBe(true)
		expect(spatial.describe({ x = 1, y = 2 })).toBe("flat")
	end)

	it("a 2D pointer handler written before spatial existed still receives its drag", function()
		-- THE compatibility claim, exercised through the real renderer: a control
		-- reading pos.x/pos.y must not care that pos also carries a ray.
		local core = custom.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local seen: { any } = {}
		local bp = Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.Button({
					id = "Card",
					label = "Card",
					onPointerDown = function(_path, pos)
						-- the handler a consumer wrote in 2026: two fields, no guard
						table.insert(seen, { x = pos.x, y = pos.y })
						return true
					end,
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()

		-- flat, as today
		adapter.pointerDown("/S/Card", 10, 20, "mouse")
		adapter.pointerUp(10, 20)
		-- and again with spatial data riding along, exactly as a future adapter
		-- would deliver it
		local node = adapter.node("/S/Card")
		node.pointer.down(spatial.extend({ x = 30, y = 40, pointerType = "spatialRay" }, RAY))

		expect(#seen).toBe(2)
		expect(seen[1].x).toBe(10)
		expect(seen[2].x).toBe(30)
		expect(seen[2].y).toBe(40)
	end)
end)

--[[ XP-D3 WAS "declared, not implemented". IT SHIPPED (ADR-0061, 2026-08-29).

	The block it guards is the same block, and it stays where it was on purpose:
	the questions were the deliverable, and where the next implementer looks for
	them is where the ANSWERS belong. What these cases hold now is that the
	declaration keeps telling the truth in both directions — the answered half
	names what the spike settled, and the open half is still honestly open and
	still matched by a capability the adapter withholds. ]]
describe("the world render target is declared AND shipped (XP-D3)", function()
	it("declares SurfaceGui, names its adapter, and still carries both halves", function()
		local surface = target_contract.FUTURE.surface
		expect(surface.instance).toBe("SurfaceGui")
		expect(string.find(surface.status, "SHIPPED", 1, true) ~= nil).toBe(true)
		expect(string.find(surface.status, "surface_target.luau", 1, true) ~= nil).toBe(true)
		-- both halves are populated: a declaration that answered everything and a
		-- declaration that answered nothing are equally useless to the next reader
		expect(#surface.answered >= 6).toBe(true)
		expect(#surface.openQuestions >= 5).toBe(true)
		expect((target_contract :: any).FUTURE.surface.presentationSpace).toBe("world")
	end)

	it("the adapter exists and is required directly, never exported from the table", function()
		-- the blessed client modules are REQUIRED, not reached through `Facet` —
		-- the same rule screen_target and billboard_target live under
		expect((Facet :: any).newSurfaceTarget).toBe(nil)
		expect(fs.isFile("src/client/surface_target.luau")).toBe(true)
	end)

	it("every still-open question has a capability the adapter withholds", function()
		--[[ THE HALF THAT IS EASY TO LET ROT. An open question with the matching
			capability quietly shipped anyway is worse than no declaration at all:
			it reads as caution while the unproven path is live. So the adapter's
			source is read for the deletions that correspond to the open rows. ]]
		local source = fs.readFile("src/client/surface_target.luau")
		for _, withheld in
			{
				"adapter.setPointerHandlers = nil",
				"adapter.setTouchGestureHandlers = nil",
				"adapter.stageHost = nil",
				"adapter.foreignHost = nil",
			}
		do
			expect(string.find(source, withheld, 1, true) ~= nil).toBe(true)
		end
		-- ...and the two conservative flags the open rows name
		expect(string.find(source, "nativeStyle = false", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "forceScrollFallback = true", 1, true) ~= nil).toBe(true)
	end)

	it("AlwaysOnTop is pinned false and is not an option", function()
		--[[ MEASURED: with a wall between the camera and the console, activation
			read 0 with AlwaysOnTop false and 1 with it true. A terminal a player can
			operate through geometry is not a terminal, so this is not a flag. ]]
		local source = fs.readFile("src/client/surface_target.luau")
		expect(string.find(source, "gui.AlwaysOnTop = false", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "alwaysOnTop", 1, true)).toBeNil()
	end)
end)

describe("no VR support claim (XP-D5)", function()
	-- The one irreversible mistake in this section is a document that starts
	-- saying Facet supports VR. A grep is a crude instrument, so it is aimed
	-- narrowly: the shipped guide and API reference may DISCUSS the seam, but
	-- may not contain a support claim in any of the phrasings a reader would
	-- take as one.
	local CLAIM_PATTERNS = {
		"supports VR",
		"VR support",
		"VR%-ready",
		"VR ready",
		"works in VR",
		"Facet in VR",
		"spatial support",
	}
	-- the plan documents deliberately discuss what a VR claim WOULD require; the
	-- guarded set is the surface a consumer reads as current fact
	local GUARDED = {
		"docs/reference/api.md",
		"docs/guide/README.md",
		"docs/guide/01-concepts.md",
		"docs/guide/02-architecture.md",
		"docs/guide/07-input.md",
		"docs/extending/new-render-target.md",
		"src/input/spatial.luau",
		"src/render/target_contract.luau",
		"src/env/environment.luau",
		-- the two shipped documents that DISCUSS spatial UI are guarded too: a
		-- support claim is likeliest to appear exactly where the subject comes up
		"docs/extending/new-platform-mode.md",
		"docs/adr/ADR-0021-spatial-seam.md",
	}

	-- A DENIAL IS NOT A CLAIM. "Nothing here is spatial support" contains the
	-- phrase and means its opposite, so a blunt grep flags the very sentences
	-- that make the boundary explicit. The check is line-scoped and skips a line
	-- carrying a negation — which is why the guarded set can include the two
	-- documents whose whole subject is what Facet does NOT support.
	local NEGATORS = { "not ", "no ", "nothing", "none", "neither", "never", "without", "unearned", "cannot", "n't" }
	local function isDenial(line: string): boolean
		local lower = string.lower(line)
		for _, n in NEGATORS do
			if string.find(lower, n, 1, true) ~= nil then
				return true
			end
		end
		return false
	end

	it("no shipped document claims VR support", function()
		local offenders: { string } = {}
		local denials = 0
		for _, path in GUARDED do
			if fs.isFile(path) then
				for line in string.gmatch(fs.readFile(path), "[^\n]+") do
					for _, pattern in CLAIM_PATTERNS do
						if string.find(line, pattern) ~= nil then
							if isDenial(line) then
								denials += 1
							else
								table.insert(offenders, `{path}: '{pattern}' in: {line}`)
							end
						end
					end
				end
			end
		end
		expect(offenders).toEqual({})
		-- and the denials are real: the guarded set contains documents that say
		-- plainly there is no support, so this must not be zero
		expect(denials > 0).toBe(true)
	end)

	it("the platform playbook names the gates a claim would first have to pass", function()
		local text = fs.readFile("docs/extending/new-platform-mode.md")
		for _, gate in { "focus", "hover", "occlusion", "comfort", "cancellation", "performance" } do
			expect(string.find(string.lower(text), gate, 1, true) ~= nil).toBe(true)
		end
		-- and it says plainly that none of them has been run
		expect(string.find(text, "Facet does not currently support VR", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "PENDING_PHYSICAL", 1, true) ~= nil).toBe(true)
	end)

	it("the spatial module says so in its own header, where an implementer reads it", function()
		local text = fs.readFile("src/input/spatial.luau")
		expect(string.find(text, "Facet does not support VR", 1, true) ~= nil).toBe(true)
	end)
end)
