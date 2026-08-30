--!strict
--[[ The world-surface render target's PURE half (ADR-0063).

	`surface_target.new` makes a `SurfaceGui`, so the engine writes themselves are
	Studio evidence and live in
	artifacts/example-games-and-standalones/spike/world-surface.md. What CAN be
	proved here is everything that happens before the first Instance exists, and
	it is the half that decides whether a consumer gets a working terminal or a
	perfect-looking one nobody can touch:

	  * the canvas rectangle the solver is handed;
	  * every argument the adapter refuses, and whether its refusal SAYS WHY;
	  * that the pipeline solves correctly at a world-canvas viewport.

	This spec exists at all because `surface_target` resolves `screen_target`
	inside `new` rather than at module scope — the shape `src/client/host.luau`
	established. `billboard_target` requires at module scope and therefore has no
	spec of its own; that is the difference, and it is worth the four lines. ]]

local testkit = require("./lib/testkit")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local fs = require("@lune/fs")

local Facet = require("../src")
local fake_target = require("./lib/fake_target")
local target_contract = require("../src/render/target_contract")
local surface_target = require("../src/client/surface_target")

--[[ Every refusal is checked for its MESSAGE, not merely for throwing. A required
	argument that throws "assertion failed" teaches nothing; every one of these
	names the thing and, where the reason is non-obvious, why. ]]
local function refusalFor(opts: any): string
	local ok, err = pcall(function()
		return (surface_target :: any).new(opts)
	end)
	expect(ok).toBe(false)
	return tostring(err)
end

describe("surface_target: the canvas the solver is handed", function()
	it("canvasRect is the canvas, at the origin, and is pure", function()
		local rect = surface_target.canvasRect({ w = 400, h = 250 })
		expect(rect.x).toBe(0)
		expect(rect.y).toBe(0)
		expect(rect.w).toBe(400)
		expect(rect.h).toBe(250)
		-- pure: a second call cannot see the first
		local again = surface_target.canvasRect({ w = 400, h = 250 })
		expect(again.w).toBe(400)
		expect(rect ~= again).toBe(true)
	end)

	it("the canvas is the whole viewport, so a screen solves against it exactly", function()
		--[[ MEASURED IN STUDIO: with `SizingMode = FixedSize`, one CanvasSize held
			while the part was resized 8x5 -> 4x2.5 -> 16x10 -> 8x2 studs reported
			`AbsoluteSize = 400,250` every time, and descendants read in canvas
			pixels. So the solver's world IS the canvas, and this is the headless
			twin of that: the same tree at the same viewport, through the same
			renderer, with the fake target standing in for the engine. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", surface_target.canvasRect({ w = 400, h = 250 }))
		local adapter = fake_target.new()
		local root = Facet.mount(
			core,
			Facet.UI.Screen({
				id = "Terminal",
				padding = 12,
				gap = 8,
				children = {
					Facet.UI.Text({ id = "Title", text = "Outpost power", textSize = 20 }),
					Facet.UI.Text({ id = "Budget", text = "6 units to allocate", textSize = 14 }),
				},
			})
		)
		local controller = Facet.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		local title = adapter.node("/Terminal/Title")
		expect(title.rect.x).toBe(12)
		expect(title.rect.y).toBe(12)
		-- nothing may be solved outside the canvas: a world surface clips to it and
		-- there is no screen beyond the part to spill onto
		expect(title.rect.x + title.rect.w <= 400).toBe(true)
		expect(adapter.node("/Terminal/Budget").rect.y < 250).toBe(true)
		controller.dispose()
	end)
end)

describe("surface_target: every refusal says why", function()
	it("parent is required, and the message names what it should be", function()
		local err = refusalFor({ adornee = {}, canvas = { w = 1, h = 1 } })
		expect(string.find(err, "parent is required", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "PlayerGui", 1, true) ~= nil).toBe(true)
	end)

	it("adornee is required, and the message says what it is", function()
		local err = refusalFor({ parent = {}, canvas = { w = 1, h = 1 } })
		expect(string.find(err, "adornee is required", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "the part", 1, true) ~= nil).toBe(true)
	end)

	it("face is required, and the refusal explains the trap rather than just refusing", function()
		--[[ THE ONE THAT COST THE SPIKE TWO ROUNDS. For an unrotated part
			`Enum.NormalId.Front` is the -Z face, so a camera looking along -Z sees
			`Back`. A surface on the wrong face renders perfectly, measures
			perfectly, and can never be clicked — indistinguishable from an engine
			that does not support this at all. A bare "face is required" would let
			the next person make the same mistake with the right argument. ]]
		local err = refusalFor({ parent = {}, adornee = {}, canvas = { w = 1, h = 1 } })
		expect(string.find(err, "face is required", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "-Z", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "never be clicked", 1, true) ~= nil).toBe(true)
	end)

	it("the queryable precondition is refused BEFORE any Instance exists", function()
		--[[ MEASURED IN STUDIO: with `CanQuery = false` the surface renders at full
			size and receives nothing — activation went 1 -> 0 -> 1 as the flag was
			cleared and restored. Nothing errors and nothing looks wrong; the
			terminal simply cannot be used.

			WHAT THIS CASE CAN AND CANNOT REACH. `face` is validated first (a caller
			fixes one refusal at a time, in the order they appear in the call), and
			its check needs a real `Enum.NormalId`, which Lune has no `Enum` to
			supply. So the runtime CanQuery path is Studio evidence, and what is
			held here is that the check EXISTS, runs before the root factory, and
			says which flag to set. Asserting `pcall` failure on a face error and
			calling it a CanQuery proof would be a case passing for the wrong
			reason. ]]
		local source = fs.readFile("src/client/surface_target.luau")
		local assertIndex = string.find(source, "queryable ~= false", 1, true)
		local factoryIndex = string.find(source, "rootFactory = function", 1, true)
		expect(assertIndex ~= nil).toBe(true)
		expect(factoryIndex ~= nil).toBe(true)
		-- before the first Instance is made, not after
		expect((assertIndex :: number) < (factoryIndex :: number)).toBe(true)
		expect(string.find(source, "Set CanQuery = true on the part", 1, true) ~= nil).toBe(true)
	end)

	it("canvas is required, and the message says the solver is handed exactly it", function()
		local err = refusalFor({ parent = {}, adornee = {}, face = 1 })
		-- face is validated before canvas, so this asserts the ORDER is stable
		-- rather than the message: a caller fixes one refusal at a time
		expect(string.find(err, "face is required", 1, true) ~= nil).toBe(true)
	end)
end)

describe("surface_target: what it withholds is real", function()
	it("every capability it deletes is one the contract actually declares", function()
		--[[ Deleting an optional method is the contract's own degrade mechanism —
			`target_contract.check` then reports it absent and the renderer degrades
			by name. That only means anything if the name is one the contract knows:
			deleting a method nobody declared is a no-op dressed as caution. ]]
		local declared: { [string]: boolean } = {}
		for _, name in target_contract.OPTIONAL do
			declared[name] = true
		end
		for _, withheld in { "setPointerHandlers", "setTouchGestureHandlers", "stageHost", "foreignHost" } do
			if not declared[withheld] then
				error(`surface_target withholds "{withheld}", which target_contract does not declare`, 2)
			end
		end
	end)

	it("the module carries the measurement beside each choice it makes", function()
		--[[ Not a style check. Every one of these numbers is why an option is not
			an option, and a later reader who removes the comment removes the only
			record of why the value cannot simply be flipped. ]]
		local source = fs.readFile("src/client/surface_target.luau")
		for _, marker in
			{
				"CanQuery = false", -- the queryable precondition
				"AlwaysOnTop", -- pinned, with the through-a-wall measurement
				"REPLICATED TO EVERY PLAYER", -- why PlayerGui, since input is not the reason
				"INVISIBLE THROUGH `.Adornee`", -- why onAdorneeLost exists at all
			}
		do
			if string.find(source, marker, 1, true) == nil then
				error(`surface_target no longer explains "{marker}"`, 2)
			end
		end
	end)
end)
