--!strict
-- UI.Foreign — the bounded escape hatch to a Roblox GuiObject LuauUI does not
-- wrap (ADR-0034; docs/reference/react-lua-comparison.md §5 rank 1).
--
-- Six contracts, all deterministic and engine-free:
--   (a) SCHEMA        strict authoring, and the UNBOUNDED form refused BY NAME:
--                     `class`/`props`/`instance` are not typos, so they get an
--                     argument and the alternative rather than a did-you-mean;
--   (b) MOUNT/DISPOSE it mounts as a leaf, is NEVER elided, dumps
--                     deterministically, and returns the core to baseline;
--   (c) THE SEAM      `controller.foreignHost(path)` hands back a per-node handle
--                     with ONE verb, `adopt`, whose whole refusal ladder is pure
--                     and therefore provable headlessly; a call after dispose is
--                     a loud error;
--   (d) AUTHORITY     the reserved `host` authority is now LIVE and owns exactly
--                     one engine property — `Foreign.Parent`, the only property
--                     LuauUI ever writes on an instance it does not own — and
--                     the framework retains no reference to the adopted content,
--                     which is what makes "we write nothing else" structural;
--   (e) LAYOUT        it declares its box (0x0 without dims, like Box), clips to
--                     it, and is never a decoration surface;
--   (f) CONTAINMENT   it never recycles, never takes focus, and its box joins
--                     the cross-surface cover rect like any other leaf's.
--
-- The ENGINE half (a real VideoFrame drawing inside a real Frame) is the live
-- Studio slice; nothing here claims it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local authority = require("../src/render/authority")
local foreign_content = require("../src/render/foreign_content")
local target_contract = require("../src/render/target_contract")
local controlContract = require("../src/controls/contract")
local fake_target = require("./lib/fake_target")

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

-- a stand-in for a caller's engine instance. The fake target speaks this shape
-- because there are no Instances headless; the live adapter builds the same
-- five facts off a real one (foreign_content.Candidate).
local function stub(className: string, over: { [string]: any }?): any
	local s: any = {
		present = true,
		className = className,
		isGuiObject = true,
		isLayerCollector = false,
		alive = true,
	}
	for key, value in over or {} do
		s[key] = value
	end
	return s
end

-- one mounted Foreign, over the headless target
local function mountForeign(spec: { [string]: any }?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local foreignSpec: { [string]: any } = {
		id = "Foreign",
		width = { type = "fixed", px = 200 },
		height = { type = "fixed", px = 120 },
	}
	for key, value in spec or {} do
		foreignSpec[key] = value
	end
	local root =
		mountLib.mount(core, UI.Screen({ id = "S", padding = 0, gap = 0, children = { UI.Foreign(foreignSpec) } }))
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, root, adapter, controller
end

-- ===== (a) schema ==========================================================

describe("UI.Foreign: strict authoring (a)", function()
	it("constructs from a valid spec and is a non-container leaf", function()
		local bp = UI.Foreign({
			id = "Video",
			width = { type = "fixed", px = 320 },
			height = { type = "fixed", px = 180 },
			surface = "raised",
		})
		expect(bp.class).toBe("Foreign")
		expect(bp.props.surface).toBe("raised")
		local schema = UI.schema.forClass("Foreign") :: any
		expect(schema.container).toBe(false)
		expect(schema.structural).toBe(false)
		-- a leaf takes no children: the content is not a blueprint
		local err = fails(function()
			UI.Foreign({ id = "Video", children = { UI.Box({ id = "Inner" }) } } :: any)
		end)
		expect(contains(err, "does not take children")).toBe(true)
	end)

	it("refuses an unknown property with a did-you-mean", function()
		local err = fails(function()
			UI.Foreign({ id = "Video", surfce = "raised" } :: any)
		end)
		expect(contains(err, "UI.Foreign")).toBe(true)
		expect(contains(err, "unknown property 'surfce'")).toBe(true)
		expect(contains(err, "Did you mean 'surface'?")).toBe(true)
	end)

	--[[ THE REFUSAL THAT IS THE WHOLE DESIGN. The naive escape hatch —
		`UI.Foreign{ class = "VideoFrame", props = { Video = … } }` — is the form
		this class exists to NOT be, and answering it with "unknown property
		'class'" would read as a gap in the schema rather than a decision. ]]
	it("refuses the UNBOUNDED form by name, with the argument and the alternative", function()
		for _, key in { "class", "className", "props", "instance", "native" } do
			local err = fails(function()
				UI.Foreign({ id = "Video", [key] = "VideoFrame" } :: any)
			end)
			expect(`{key}:names-the-key:{contains(err, key)}`).toBe(`{key}:names-the-key:true`)
			expect(`{key}:names-the-seam:{contains(err, "controller.foreignHost")}`).toBe(`{key}:names-the-seam:true`)
			expect(`{key}:names-adopt:{contains(err, "adopt")}`).toBe(`{key}:names-adopt:true`)
			-- and it does NOT read as a typo
			expect(`{key}:not-a-typo:{contains(err, "Did you mean")}`).toBe(`{key}:not-a-typo:false`)
		end
	end)

	it("refuses `tint`, because LuauUI never paints the caller's content", function()
		local err = fails(function()
			UI.Foreign({ id = "Video", tint = { role = "accent", blend = 0.5 } } :: any)
		end)
		expect(contains(err, "UI.Foreign")).toBe(true)
		expect(contains(err, "tint")).toBe(true)
		expect(contains(err, "surface")).toBe(true)
		expect(contains(err, "Did you mean")).toBe(false)
	end)

	it("enforces the eight-surface vocabulary on the plate BEHIND the content", function()
		for _, surface in { "base", "raised", "control", "chip", "badge", "accent", "scrim", "plain" } do
			local ok = pcall(function()
				UI.Foreign({ id = "Video", surface = surface })
			end)
			expect(`{surface}=accepted:{ok}`).toBe(`{surface}=accepted:true`)
		end
		local err = fails(function()
			UI.Foreign({ id = "Video", surface = "glass" })
		end)
		expect(contains(err, "UI.Foreign.surface")).toBe(true)
		expect(contains(err, "base | raised | control | chip | badge | accent | scrim | plain")).toBe(true)
	end)
end)

-- ===== (b) mount + dispose =================================================

describe("UI.Foreign: mount, elision, dispose (b)", function()
	it("mounts as one node and dumps deterministically", function()
		local _, root, adapter, controller = mountForeign()
		local node = adapter.node("/S/Foreign")
		expect(node ~= nil).toBe(true)
		expect(node.class).toBe("Foreign")
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
		expect(render(root.dump())).toBe(render(root.dump()))
		expect(contains(render(root.dump()), "Foreign:Foreign")).toBe(true)
		controller.dispose()
		root.dispose()
	end)

	--[[ NEVER ELIDABLE, and it is not a preference. An elided node has no engine
		object at all (`create` answers a bare handle), and this class's entire
		purpose is that an instance exists for somebody else's content to live in.
		Both adapters' elision lists are ALLOW-lists, so the guarantee is
		structural — these two checks are what stops a future widening. ]]
	it("is NEVER elided, on either adapter, even bare", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		-- no surface, no handler, no dims: the most elidable-looking node possible
		local root = mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Foreign({ id = "Bare" }) } }))
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local node = adapter.node("/S/Bare")
		expect(node ~= nil).toBe(true)
		expect(node.elided).toBe(nil)
		controller.dispose()
		root.dispose()

		-- ...and the LIVE adapter's allow-list does not name it either
		local liveSource = fs.readFile("src/client/screen_target.luau")
		local list = string.match(liveSource, "local ELIDABLE_CLASSES: { %[string%]: boolean } = {(.-)}") :: string?
		expect(list ~= nil).toBe(true)
		expect(contains(list :: string, "Foreign")).toBe(false)
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
					UI.Foreign({
						id = "Foreign",
						width = { type = "fixed", px = 100 },
						height = { type = "fixed", px = 100 },
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local host = controller.foreignHost("/S/Foreign") :: any
		host.adopt(stub("VideoFrame"))
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

describe("UI.Foreign: the foreignHost content seam (c)", function()
	it("is a DECLARED optional target method, so an adapter without it degrades by name", function()
		local declared = false
		for _, name in target_contract.OPTIONAL do
			if name == "foreignHost" then
				declared = true
			end
		end
		expect(declared).toBe(true)
		expect(#target_contract.check(fake_target.new()).optionalAbsent).toBe(0)
		local liveSource = fs.readFile("src/client/screen_target.luau")
		expect(contains(liveSource, "function adapter.foreignHost(")).toBe(true)
		local billboardSource = fs.readFile("src/client/billboard_target.luau")
		expect(contains(billboardSource, "adapter.foreignHost = nil")).toBe(true)
	end)

	it("returns nil for an unknown path, a non-Foreign node, and an adapter without the seam", function()
		local _, root, _, controller = mountForeign()
		expect(controller.foreignHost("/S/Nope")).toBe(nil)
		expect(controller.foreignHost("/S")).toBe(nil)
		controller.dispose()
		root.dispose()

		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bareRoot = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Foreign({
						id = "Foreign",
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 40 },
					}),
				},
			})
		)
		local bare = fake_target.new()
		bare.foreignHost = nil
		local bareController = rendererLib.attach(core, bareRoot, env, bare, { rootPolicy = "edgeToEdge" })
		bareController.initialRender()
		expect(bareController.foreignHost("/S/Foreign")).toBe(nil)
		bareController.dispose()
		bareRoot.dispose()
	end)

	it("hands back ONE cached handle per node", function()
		local _, root, _, controller = mountForeign()
		local host = controller.foreignHost("/S/Foreign")
		expect(host ~= nil).toBe(true)
		expect(controller.foreignHost("/S/Foreign")).toBe(host)
		controller.dispose()
		root.dispose()
	end)

	it("adopt makes exactly ONE claim on the caller's instance: its Parent", function()
		local _, root, _, controller = mountForeign()
		local host = controller.foreignHost("/S/Foreign") :: any
		local video = stub("VideoFrame")
		host.adopt(video)
		expect(#host.calls).toBe(1)
		expect(host.calls[1].method).toBe("adopt")
		expect(host.calls[1].className).toBe("VideoFrame")
		expect(host.calls[1].property).toBe(foreign_content.CLAIMED_PROPERTY)
		-- more than one is legal: the caller owns how many things live in the box
		host.adopt(stub("EditableImage-surface"))
		expect(#host.calls).toBe(2)
		controller.dispose()
		root.dispose()
	end)

	--[[ THE REFUSAL LADDER, in the order a caller hits it. Each rung names the
		node, says what the candidate is, and — where there is one — names the
		alternative that DOES work, which is the standing pattern (ADR-0029). ]]
	it("refuses nothing, a LayerCollector, a non-GuiObject and a destroyed instance — each by name", function()
		local _, root, _, controller = mountForeign()
		local host = controller.foreignHost("/S/Foreign") :: any

		local none = fails(function()
			host.adopt(nil)
		end)
		expect(contains(none, "/S/Foreign")).toBe(true)
		expect(contains(none, "no instance was passed")).toBe(true)

		local collector = fails(function()
			host.adopt(stub("ScreenGui", { isLayerCollector = true }))
		end)
		expect(contains(collector, "ScreenGui")).toBe(true)
		expect(contains(collector, "LayerCollector")).toBe(true)

		-- the 3-D case is a DIFFERENT record's question and the message says so
		local part = fails(function()
			host.adopt(stub("Part", { isGuiObject = false }))
		end)
		expect(contains(part, "not a GuiObject")).toBe(true)
		expect(contains(part, "UI.Stage")).toBe(true)
		expect(contains(part, "ADR-0024")).toBe(true)

		local dead = fails(function()
			host.adopt(stub("VideoFrame", { alive = false }))
		end)
		expect(contains(dead, "already been destroyed")).toBe(true)
		expect(contains(dead, "VideoFrame")).toBe(true)

		-- NOTHING was adopted: a refusal runs before any write
		expect(#host.calls).toBe(0)
		controller.dispose()
		root.dispose()
	end)

	it("a handle used after its node dies errors with a message naming the node", function()
		local _, root, _, controller = mountForeign()
		local host = controller.foreignHost("/S/Foreign") :: any
		controller.dispose()
		root.dispose()
		local err = fails(function()
			host.adopt(stub("VideoFrame"))
		end)
		expect(contains(err, "/S/Foreign")).toBe(true)
		expect(contains(err, "disposed")).toBe(true)
	end)
end)

-- ===== (d) authority =======================================================

describe("UI.Foreign: property authority (d)", function()
	--[[ `host` HAS BEEN DECLARED AND UNUSED SINCE PHASE 3 (ARCH-F8, dispositioned
		in the Step 5.5 cleanup ledger: *"'host' appears exactly once in the whole
		repo, its own type-union member"*). It was reserved for UI-EXT-001, "escape
		hatch: mounts raw Instances under explicit contract" — this feature. It is
		now live, and it owns exactly one property. ]]
	it("makes the reserved `host` authority LIVE, owning exactly Foreign.Parent", function()
		expect(authority.authorityFor("Foreign", "Parent")).toBe("host")
		-- and it is the ONLY host-owned entry in the whole manifest: this authority
		-- means "a claim on an instance LuauUI does not own", and there is one
		local hostEntries: { string } = {}
		for class, props in authority.manifest() do
			for prop, owner in props do
				if owner == "host" then
					table.insert(hostEntries, `{class}.{prop}`)
				end
			end
		end
		expect(#hostEntries).toBe(1)
		expect(hostEntries[1]).toBe("Foreign.Parent")
	end)

	it("the gate catches a second writer for the one claimed property", function()
		authority.assertWrite("Foreign", "Parent", "host")
		local err = fails(function()
			authority.assertWrite("Foreign", "Parent", "style")
		end)
		expect(contains(err, "style tried to write Foreign.Parent")).toBe(true)
		expect(contains(err, "host")).toBe(true)
		-- `Parent` is claimed on THIS class only: no other class may write one
		expect(authority.authorityFor("Box", "Parent")).toBe(nil)
	end)

	it("claims NOTHING else: every other Foreign prop resolves through common", function()
		local classMap = authority.manifest().Foreign :: any
		local names: { string } = {}
		for prop in classMap do
			table.insert(names, prop)
		end
		expect(#names).toBe(1)
		-- the box props it does declare are the ordinary shared ones
		expect(authority.authorityFor("Foreign", "size")).toBe("layout")
		expect(authority.authorityFor("Foreign", "surface")).toBe("style")
		-- ...and the paint channels it does NOT offer are not silently owned either
		expect(authority.authorityFor("Foreign", "tint")).toBe(nil)
	end)

	it("the live adapter makes its ONE write through the gate", function()
		local liveSource = fs.readFile("src/client/screen_target.luau")
		expect(contains(liveSource, 'authority.assertWrite("Foreign", "Parent", "host")')).toBe(true)
	end)

	--[[ "LUAUUI WRITES NOTHING ELSE" IS STRUCTURAL, NOT A PROMISE. The framework
		cannot write a property of an instance it holds no reference to, so the
		seam parents and FORGETS. This walks the handle after an adoption and
		fails if the adopted content is reachable from it at all. ]]
	it("retains no reference to the adopted content, so it cannot write to it later", function()
		local _, root, adapter, controller = mountForeign()
		local host = controller.foreignHost("/S/Foreign") :: any
		local video = stub("VideoFrame")
		host.adopt(video)
		local handle = adapter.node("/S/Foreign")
		local function reachable(value: any, depth: number): boolean
			if value == video then
				return true
			end
			if type(value) ~= "table" or depth > 3 then
				return false
			end
			for _, inner in value :: any do
				if reachable(inner, depth + 1) then
					return true
				end
			end
			return false
		end
		expect(reachable(handle, 0)).toBe(false)
		controller.dispose()
		root.dispose()
	end)

	it("is registered as a NON-INTERACTIVE control with a leaf row", function()
		local c = controlContract.forClass("Foreign") :: any
		expect(c ~= nil).toBe(true)
		expect(c.focusRole).toBe("none")
		expect(#c.actions).toBe(0)
		local registry = require("./conformance/controls_registry") :: { any }
		local row: any = nil
		for _, entry in registry do
			if entry.name == "Foreign" then
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

describe("UI.Foreign: layout (e)", function()
	it("solves to exactly the box it declares", function()
		local _, root, adapter, controller = mountForeign()
		local rect = adapter.node("/S/Foreign").rect
		expect(rect.w).toBe(200)
		expect(rect.h).toBe(120)
		controller.dispose()
		root.dispose()
	end)

	--[[ NO INTRINSIC SIZE, and this is the measure-model half of the bounded
		form. An engine instance with `AutomaticSize` measures ITSELF, which the
		solver cannot see — so the box is DECLARED, never inferred, exactly as a
		Stage's and a Box's are. ]]
	it("measures 0x0 without explicit dims — like Box", function()
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
				children = { UI.Foreign({ id = "Bare" }), UI.Box({ id = "Ref" }) },
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

	--[[ THE BOX IS THE PROMISE. LuauUI reserves a rect and the caller fills it;
		what keeps that a CONTRACT rather than a hope is that the container clips,
		so no foreign instance can paint one pixel outside the rect the solver
		reserved — which is also what keeps the cross-surface cover rect (ADR-0028)
		honest about this node. ]]
	it("clips its content to the reserved box, on both adapters", function()
		local _, root, adapter, controller = mountForeign()
		expect(adapter.node("/S/Foreign").foreignClips).toBe(true)
		controller.dispose()
		root.dispose()
		-- THE PIN IS SCOPED TO THE FOREIGN BRANCH, not to the file. A bare
		-- `contains(source, "instance.ClipsDescendants = true")` passed with the
		-- branch deleted — the adapter writes that same literal for `clipChildren`
		-- elsewhere — which is a check that proves nothing (mutation M4, caught by
		-- running it). This reads the branch itself.
		local liveSource = fs.readFile("src/client/screen_target.luau")
		local branch = string.match(liveSource, 'if class == "Foreign" then(.-)\n\t\tend\n') :: string?
		expect(branch ~= nil).toBe(true)
		expect(contains(branch :: string, "instance.ClipsDescendants = true")).toBe(true)
		expect(contains(branch :: string, "handle.foreignBox = true")).toBe(true)
	end)

	--[[ AN ORNATE PACKAGE MUST NOT COVER THE CONTENT. This is the defect the
		reference-app matrix found on `UI.Stage` in 2026-08-08 (a whole-art `control`
		recipe painted its plate OVER the 3-D scene), and it is worse here: LuauUI
		does not even know what shape the covered thing was. The renderer pins the
		no-slot hint at CREATION and unconditionally, so no channel can override it
		— which is a fact about the create path, not about the classifier, so the
		classifier check alone would prove nothing. ]]
	--[[ THE SHEET REACHES CONTENT THE FRAMEWORK DOES NOT WRITE (ADR-0034 Decision 7,
		found live 2026-08-15). A native-mode surface links a theme StyleSheet whose
		class-default rules select the seven GuiObject classes LuauUI renders, and the
		engine decides "explicitly set" by VALUE: an adopted `Frame` born at
		`BackgroundTransparency = 0` — the class default — cannot hold that value
		against a `Frame { BackgroundTransparency = 1 }` rule, and the pane renders
		EMPTY (raw 0, GetStyled 1).

		Headless cannot see a StyleSheet, so what is pinned here is the CONSEQUENCE
		the shipped demo has to live with: the materializer must not leave a paint
		property it cares about at its class default. A regression here is a blank
		pane in the showcase that no headless assertion would otherwise catch. ]]
	it("the shipped materializer never leaves an adopted paint prop at its class default", function()
		local source = fs.readFile("examples/gallery/scenarios/foreign_instances.luau")
		local block = string.match(source, 'elseif content%.kind == "oversize" then(.-)elseif') :: string?
		expect(block ~= nil).toBe(true)
		local written = string.match(block :: string, "frame%.BackgroundTransparency = ([%d%.]+)") :: string?
		expect(written ~= nil).toBe(true)
		-- 0 is the Frame class default and therefore un-holdable against a rule
		expect(`written={written} isDefault={tonumber(written) == 0}`).toBe(`written={written} isDefault=false`)
		-- ...and it is still visually opaque
		expect((tonumber(written) :: number) < 0.1).toBe(true)
	end)

	it("is never a decoration surface: the create path pins NO_SLOT for it", function()
		local chrome_slots = require("../src/tokens/chrome_slots") :: any
		-- a `raised` surface on ANY ordinary leaf is exactly what an art package
		-- classifies into a covering slot — the control it must not do here
		expect(chrome_slots.classify({ class = "Box", surface = "raised" }) ~= nil).toBe(true)
		expect(chrome_slots.classify({ class = "Foreign", surface = "raised", hint = chrome_slots.NO_SLOT })).toBeNil()
		-- ...and the pin itself: the renderer's table, shared with Stage
		local rendererSource = fs.readFile("src/render/renderer.luau")
		local list =
			string.match(rendererSource, "local NO_DECORATION_CLASSES: { %[string%]: boolean } = {(.-)}") :: string?
		expect(list ~= nil).toBe(true)
		expect(contains(list :: string, "Foreign = true")).toBe(true)
		expect(contains(list :: string, "Stage = true")).toBe(true)
		expect(contains(rendererSource, "if NO_DECORATION_CLASSES[node.class] then")).toBe(true)
	end)
end)

-- ===== (f) containment =====================================================

describe("UI.Foreign: containment (f)", function()
	--[[ RECYCLING IS REFUSED, for the reason a Stage's is: the box holds content
		the CALLER parented there, so handing the instance a new identity would
		hand a new node somebody else's content. Refused on both adapters. ]]
	it("is never parked into the recycling pool", function()
		local _, root, adapter, controller = mountForeign()
		local handle = adapter.node("/S/Foreign")
		expect(adapter.park(handle)).toBe(false)
		controller.dispose()
		root.dispose()
		local liveSource = fs.readFile("src/client/screen_target.luau")
		expect(contains(liveSource, "handle.foreignBox ~= nil")).toBe(true)
	end)

	--[[ OUTSIDE THE FOCUS GRAPH, deliberately and on the record. The content is
		the caller's; its own engine input still works, but LuauUI's Tab/gamepad
		traversal cannot stop on something it has never seen. A consumer who needs
		a focus stop composes one AROUND the box, exactly as a Stage does. ]]
	it("takes no focus stop: inserting one does not change traversal order", function()
		local function orderOf(withForeign: boolean): string
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
			local system = LuauUI.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = LuauUI.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
			local children: { any } = { UI.Button({ id = "A", label = "A" }) }
			if withForeign then
				table.insert(
					children,
					UI.Foreign({
						id = "Box",
						width = { type = "fixed", px = 50 },
						height = { type = "fixed", px = 50 },
					})
				)
			end
			table.insert(children, UI.Button({ id = "B", label = "B" }))
			local handle = pres.present(UI.Screen({ id = "S", children = children }))
			local out: { string } = {}
			for _, entry in handle.focusOrder().traversal do
				table.insert(out, entry.path)
			end
			pres.dismiss(handle)
			return table.concat(out, " ")
		end
		expect(orderOf(true)).toBe(orderOf(false))
		expect(orderOf(true)).toBe("/S/A /S/B")
	end)

	--[[ ...BUT IT DOES COVER. A Foreign box paints (its plate) and holds content,
		so it joins the surface's cover rect like any other leaf — which is what
		lets the cross-surface alarm see a video pane covering a HUD. The clip
		above is what makes that rect the WHOLE truth. ]]
	it("contributes its box to the surface cover rect, like any other leaf", function()
		local _, root, _, controller = mountForeign({ surface = "raised" })
		local cover = controller.coverRect() :: any
		expect(cover ~= nil).toBe(true)
		expect(cover.w).toBe(200)
		expect(cover.h).toBe(120)
		controller.dispose()
		root.dispose()
	end)
end)
