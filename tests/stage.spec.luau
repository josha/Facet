--!strict
-- UI.Stage — the engine-content box (ViewportFrame adoption,
-- docs/research/2026-08-08-viewportframe-engine-facts.md).
--
-- Five contracts, all deterministic and engine-free:
--   (a) SCHEMA        strict authoring: unknown props refused with a
--                     did-you-mean, the eight-surface enum enforced, a valid
--                     spec constructs;
--   (b) MOUNT/DISPOSE it mounts as a leaf, dumps deterministically, and
--                     build/mount/dispose returns the core registry to baseline;
--   (c) THE SEAM      `controller.stageHost(path)` hands back a per-node handle
--                     whose whole boundary is engine-type-free tables; the
--                     headless twin RECORDS the calls and answers a content
--                     stub, and a call after dispose is a loud error;
--   (d) AUTHORITY     the Stage row exists, and the four ViewportFrame
--                     properties the seam owns are declared seam-owned so a
--                     bespoke explicit write is caught by a gate — the same
--                     protection NATIVE_SHEET_OWNED gives Image/ScrollBar paint;
--   (e) LAYOUT        a Stage measures 0x0 with no dims and solves to exactly
--                     the box it declares.
--
-- The ENGINE half (the ViewportFrame itself, its owned WorldModel/Camera, and a
-- rendered scene) is the live Studio slice; nothing here claims it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local adapter_source = require("./lib/adapter_source")

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local authority = require("../src/render/authority")
local target_contract = require("../src/render/target_contract")
local controlContract = require("../src/class_contract")
local fake_target = require("./lib/fake_target")

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

-- one mounted Stage, over the headless target
local function mountStage(spec: { [string]: any }?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local stageSpec: { [string]: any } = {
		id = "Stage",
		width = { type = "fixed", px = 200 },
		height = { type = "fixed", px = 120 },
	}
	for key, value in spec or {} do
		stageSpec[key] = value
	end
	local root = mountLib.mount(core, UI.Screen({ id = "S", padding = 0, gap = 0, children = { UI.Stage(stageSpec) } }))
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, root, adapter, controller
end

-- ===== (a) schema ==========================================================

describe("UI.Stage: strict authoring (a)", function()
	it("constructs from a valid spec and is a non-container leaf", function()
		local bp = UI.Stage({
			id = "Preview",
			width = { type = "fixed", px = 160 },
			height = { type = "fixed", px = 160 },
			surface = "raised",
			tint = { role = "accent", blend = 0.25 },
		})
		expect(bp.class).toBe("Stage")
		expect(bp.props.surface).toBe("raised")
		local schema = UI.schema.forClass("Stage") :: any
		expect(schema.container).toBe(false)
		expect(schema.structural).toBe(false)
		-- a leaf takes no children
		local err = fails(function()
			UI.Stage({ id = "Preview", children = { UI.Box({ id = "Inner" }) } } :: any)
		end)
		expect(contains(err, "does not take children")).toBe(true)
	end)

	it("refuses an unknown property with a did-you-mean", function()
		local err = fails(function()
			UI.Stage({ id = "Preview", surfce = "raised" } :: any)
		end)
		expect(contains(err, "UI.Stage")).toBe(true)
		expect(contains(err, "unknown property 'surfce'")).toBe(true)
		expect(contains(err, "Did you mean 'surface'?")).toBe(true)
	end)

	it("enforces the eight-surface vocabulary", function()
		for _, surface in { "base", "raised", "control", "chip", "badge", "accent", "scrim", "plain" } do
			local ok = pcall(function()
				UI.Stage({ id = "Preview", surface = surface })
			end)
			expect(`{surface}=accepted:{ok}`).toBe(`{surface}=accepted:true`)
		end
		local err = fails(function()
			UI.Stage({ id = "Preview", surface = "glass" })
		end)
		expect(contains(err, "UI.Stage.surface")).toBe(true)
		-- the refusal names the WHOLE legal set (constitution §4)
		expect(contains(err, "base | raised | control | chip | badge | accent | scrim | plain")).toBe(true)
	end)
end)

-- ===== (b) mount + dispose =================================================

describe("UI.Stage: mount, dump, dispose (b)", function()
	it("mounts as one node and dumps deterministically", function()
		local _, root, adapter, controller = mountStage()
		local node = adapter.node("/S/Stage")
		expect(node ~= nil).toBe(true)
		expect(node.class).toBe("Stage")
		local a = root.dump()
		local b = root.dump()
		local function render(dump: any): string
			local out: { string } = {}
			local function walk(n: any, depth: number)
				table.insert(out, `{string.rep(" ", depth)}{n.class}:{tostring(n.id)}`)
				for _, child in n.children or {} do
					walk(child, depth + 1)
				end
			end
			walk(dump.tree, 0)
			return table.concat(out, "\n")
		end
		expect(render(a)).toBe(render(b))
		expect(contains(render(a), "Stage:Stage")).toBe(true)
		controller.dispose()
		root.dispose()
	end)

	it("mount/render/dispose returns the core registry to baseline", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local baseline = core:counters()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Stage({
						id = "Stage",
						width = { type = "fixed", px = 100 },
						height = { type = "fixed", px = 100 },
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		controller.stageHost("/S/Stage")
		controller.dispose()
		root.dispose()
		local after = core:counters()
		for key, value in baseline do
			expect(`{key}={after[key]}`).toBe(`{key}={value}`)
		end
		expect(adapter.liveCount()).toBe(0)
	end)
end)

-- ===== (c) the content seam ================================================

describe("UI.Stage: the stageHost content seam (c)", function()
	it("is a DECLARED optional target method, so an adapter without it degrades by name", function()
		local declared = false
		for _, name in target_contract.OPTIONAL do
			if name == "stageHost" then
				declared = true
			end
		end
		expect(declared).toBe(true)
		-- the headless target implements it, so the fake still satisfies the whole seam
		expect(#target_contract.check(fake_target.new()).optionalAbsent).toBe(0)
		-- ...and the LIVE ScreenTarget grows it (its source is the contract:
		-- screen_target cannot load headless)
		local liveSource = fs.readFile("src/client/screen_target.luau")
		expect(contains(liveSource, "function adapter.stageHost(")).toBe(true)
		-- the billboard target explicitly does NOT offer it (no proven canvas story)
		local billboardSource = fs.readFile("src/client/billboard_target.luau")
		expect(contains(billboardSource, "adapter.stageHost = nil")).toBe(true)
	end)

	it("returns nil for an unknown path, a non-Stage node, and an adapter without the seam", function()
		local _, root, adapter, controller = mountStage()
		expect(controller.stageHost("/S/Nope")).toBe(nil)
		expect(controller.stageHost("/S")).toBe(nil)
		controller.dispose()
		root.dispose()

		-- an adapter that never grew the seam answers nil rather than erroring
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bareRoot = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Stage({
						id = "Stage",
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 40 },
					}),
				},
			})
		)
		local bare = fake_target.new()
		bare.stageHost = nil
		local bareController = rendererLib.attach(core, bareRoot, env, bare, { rootPolicy = "edgeToEdge" })
		bareController.initialRender()
		expect(bareController.stageHost("/S/Stage")).toBe(nil)
		bareController.dispose()
		bareRoot.dispose()
	end)

	it("hands back ONE cached handle per node", function()
		local _, root, _, controller = mountStage()
		local host = controller.stageHost("/S/Stage")
		expect(host ~= nil).toBe(true)
		expect(controller.stageHost("/S/Stage")).toBe(host)
		controller.dispose()
		root.dispose()
	end)

	it("setCamera records position/lookAt/fov in the exact table shape", function()
		local _, root, _, controller = mountStage()
		local host = controller.stageHost("/S/Stage") :: any
		host.setCamera({ position = { x = 0, y = 6, z = 12 }, lookAt = { x = 0, y = 1, z = 0 }, fov = 55 })
		expect(#host.calls).toBe(1)
		local call = host.calls[1]
		expect(call.method).toBe("setCamera")
		expect(call.spec.position.y).toBe(6)
		expect(call.spec.position.z).toBe(12)
		expect(call.spec.lookAt.y).toBe(1)
		expect(call.spec.fov).toBe(55)
		-- fov is optional
		host.setCamera({ position = { x = 1, y = 2, z = 3 }, lookAt = { x = 0, y = 0, z = 0 } })
		expect(#host.calls).toBe(2)
		expect(host.calls[2].spec.fov).toBe(nil)
		-- A DEGENERATE CAMERA IS REFUSED IN THE SHARED NORMALIZER (platform
		-- review M2): position == lookAt must throw on the HEADLESS twin too,
		-- and record nothing — pre-fix the twin recorded a camera the live
		-- adapter throws on, the exact headless-green/device-wrong split.
		local ok = pcall(function()
			host.setCamera({ position = { x = 2, y = 2, z = 2 }, lookAt = { x = 2, y = 2, z = 2 } })
		end)
		expect(ok).toBe(false)
		expect(#host.calls).toBe(2)
		controller.dispose()
		root.dispose()
	end)

	it("setLighting records ambient/lightColor/lightDirection as 0-1 rgb and a vector", function()
		local _, root, _, controller = mountStage()
		local host = controller.stageHost("/S/Stage") :: any
		host.setLighting({
			ambient = { r = 0.2, g = 0.2, b = 0.25 },
			lightColor = { r = 1, g = 0.95, b = 0.9 },
			lightDirection = { x = -1, y = -1, z = 0 },
		})
		expect(#host.calls).toBe(1)
		local call = host.calls[1]
		expect(call.method).toBe("setLighting")
		expect(call.spec.ambient.b).toBe(0.25)
		expect(call.spec.lightColor.g).toBe(0.95)
		expect(call.spec.lightDirection.x).toBe(-1)
		-- every field is optional: a partial lighting spec is legal
		host.setLighting({ ambient = { r = 0, g = 0, b = 0 } })
		expect(host.calls[2].spec.lightColor).toBe(nil)
		controller.dispose()
		root.dispose()
	end)

	it("refuses a malformed camera/lighting spec instead of writing nonsense", function()
		local _, root, _, controller = mountStage()
		local host = controller.stageHost("/S/Stage") :: any
		expect(contains(
			fails(function()
				host.setCamera({ position = { x = 0, y = 0, z = 0 } })
			end),
			"lookAt"
		)).toBe(true)
		expect(contains(
			fails(function()
				host.setCamera({ position = "here", lookAt = { x = 0, y = 0, z = 0 } } :: any)
			end),
			"position"
		)).toBe(true)
		expect(contains(
			fails(function()
				host.setLighting({ ambient = { r = 0, g = 0 } } :: any)
			end),
			"ambient"
		)).toBe(true)
		expect(contains(
			fails(function()
				host.setLighting({ tilt = 3 } :: any)
			end),
			"tilt"
		)).toBe(true)
		-- nothing malformed was recorded
		expect(#host.calls).toBe(0)
		controller.dispose()
		root.dispose()
	end)

	it("contentRoot answers the SAME content root every call (headless: a recording stub)", function()
		local _, root, _, controller = mountStage()
		local host = controller.stageHost("/S/Stage") :: any
		local content = host.contentRoot()
		expect(type(content)).toBe("table")
		expect((content :: any).kind).toBe("stage-content-stub")
		expect(host.contentRoot()).toBe(content)
		controller.dispose()
		root.dispose()
	end)

	it("a handle used after its node dies errors with a message naming the node", function()
		local _, root, _, controller = mountStage()
		local host = controller.stageHost("/S/Stage") :: any
		controller.dispose()
		root.dispose()
		for _, call in
			{
				function()
					host.setCamera({ position = { x = 0, y = 0, z = 0 }, lookAt = { x = 0, y = 0, z = 1 } })
				end,
				function()
					host.setLighting({ ambient = { r = 0, g = 0, b = 0 } })
				end,
				function()
					host.contentRoot()
				end,
			}
		do
			local err = fails(call)
			expect(contains(err, "/S/Stage")).toBe(true)
			expect(contains(err, "disposed")).toBe(true)
		end
	end)
end)

-- ===== (d) authority =======================================================

describe("UI.Stage: property authority (d)", function()
	it("declares its authored props: surface is style, tint is binding", function()
		expect(authority.authorityFor("Stage", "surface")).toBe("style")
		expect(authority.authorityFor("Stage", "tint")).toBe("binding")
		expect(authority.manifest().Stage ~= nil).toBe(true)
	end)

	it("the four ViewportFrame properties the SEAM owns are declared seam-owned", function()
		for _, prop in { "Ambient", "LightColor", "LightDirection", "CurrentCamera" } do
			expect(`{prop}={authority.seamOwned(prop)}`).toBe(`{prop}=true`)
			expect(#authority.seamOwnedSet()[prop] > 0).toBe(true)
		end
		-- and the set is CLOSED: an ordinary paint property is not seam-owned
		expect(authority.seamOwned("BackgroundColor3")).toBe(false)
	end)

	it("the gate catches a write that is not the stage seam's, and an undeclared property", function()
		-- the seam's own write passes
		authority.assertSeamWrite("Ambient", true)
		-- a bespoke write of a seam-owned property is a LOUD error, never a
		-- silent second authority over the frame
		local err = fails(function()
			authority.assertSeamWrite("LightDirection", false)
		end)
		expect(contains(err, "LightDirection")).toBe(true)
		expect(contains(err, "stageHost")).toBe(true)
		-- ...and a property nobody declared cannot be smuggled through the gate
		local undeclared = fails(function()
			authority.assertSeamWrite("Brightness", true)
		end)
		expect(contains(undeclared, "Brightness")).toBe(true)
	end)

	it("the live adapter makes NO bespoke write to a seam-owned property", function()
		-- The seam writes them through ONE indexed writer, so a literal
		-- `instance.Ambient = …` anywhere in the adapter is the defeating pattern
		-- this pin exists to catch (the same shape assertBespokePaint gives paint).
		-- ...and it reads the WHOLE adapter, not just its largest file: the indexed
		-- writer moved to `screen_vocabulary` with the rest of the module-level
		-- vocabulary (source-cap-ledger, 2026-08-22), and a pin that only reads
		-- `screen_target.luau` would have gone quietly half-blind on that move.
		local liveSource = adapter_source.live()
		for prop in authority.seamOwnedSet() do
			expect(`{prop}:{contains(liveSource, "." .. prop .. " =")}`).toBe(`{prop}:false`)
		end
		expect(contains(liveSource, "authority.assertSeamWrite(")).toBe(true)
	end)

	it("is registered as a NON-INTERACTIVE control with a leaf row", function()
		local c = controlContract.forClass("Stage") :: any
		expect(c ~= nil).toBe(true)
		expect(c.focusRole).toBe("none")
		expect(#c.actions).toBe(0)
		local registry = require("./conformance/controls_registry") :: { any }
		local row: any = nil
		for _, entry in registry do
			if entry.name == "Stage" then
				row = entry
			end
		end
		expect(row ~= nil).toBe(true)
		expect(row.kind).toBe("leaf")
		expect(row.inputProofs).toBe(false)
		expect(row.affordanceProofs).toBe(false)
	end)
end)

-- ===== (e) layout ==========================================================

describe("UI.Stage: layout (e)", function()
	it("solves to exactly the box it declares", function()
		local _, root, adapter, controller = mountStage()
		local rect = adapter.node("/S/Stage").rect
		expect(rect.w).toBe(200)
		expect(rect.h).toBe(120)
		controller.dispose()
		root.dispose()
	end)

	it("measures 0x0 without explicit dims (it has no intrinsic content) — like Box", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				align = "start",
				children = { UI.Stage({ id = "Bare" }), UI.Box({ id = "Ref" }) },
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local bare = adapter.node("/S/Bare").rect
		local ref = adapter.node("/S/Ref").rect
		expect(bare.h).toBe(0)
		expect(`{bare.w}x{bare.h}`).toBe(`{ref.w}x{ref.h}`)
		controller.dispose()
		root.dispose()
	end)

	it("paints through the ordinary style/binding channels (surface + tint)", function()
		local _, root, adapter, controller = mountStage({
			surface = "raised",
			tint = { role = "accent", blend = 1 },
		})
		local node = adapter.node("/S/Stage")
		expect(node.props.surface).toBe("raised")
		-- the tint CLAIMS the frame's own paint channel: a ViewportFrame's picture
		-- is its rendered scene, so the claim is ImageColor3 (as an Image's is)
		expect(node.paintClaims.ImageColor3).toBe(true)
		expect(node.tintColor ~= nil).toBe(true)
		controller.dispose()
		root.dispose()
	end)

	it("a Stage never classifies into a decoration slot (an ornate skin cannot cover the scene)", function()
		local chrome_slots = require("../src/tokens/chrome_slots") :: any
		-- the renderer pins the no-slot hint at creation; the classifier's own
		-- contract is that the hint wins outright
		expect(chrome_slots.classify({ class = "Stage", surface = "raised", hint = chrome_slots.NO_SLOT })).toBeNil()
	end)
end)
