--!strict
-- AUTHORED PAINT ESCAPES (ADR-0022 Decision 6; acceptance rows SF-P1..SF-P4).
--
-- Four narrow escapes from the finite-selector model, each with a declared
-- authority: the continuous colour channel (`tint`), an Image's `scaleMode`, the
-- authored border (`UI.stroke`), and the `zIndex` paint-order override. The
-- boundary is the point — everything a closed set CAN express stays tokens + tags
-- + native-sheet rules (ADR-0018), so each of these has to say what it claims and
-- from whom.
--
-- Structure: the authoring boundary (construction errors), the emission (renderer
-- channels + authority), the APPLICATION (the fake adapter's structural mirrors,
-- which share the live adapter's own pure resolvers), and the live adapter's
-- source contracts for the parts an engine-free suite cannot execute.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local schema = require("../src/blueprint_schema")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local authority = require("../src/render/authority")
local styling = require("../src/tokens/styling")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local fake_target = require("./lib/fake_target")

local adapterSource = fs.readFile("src/client/screen_target.luau")
local rendererSource = fs.readFile("src/render/renderer.luau")
local runnerSource = fs.readFile("examples/gallery/scenarios/runner.luau")

local NEUTRAL_THEME = { colors = default_style.colors, extra = default_style.extra }

local function render(screen: any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, core
end

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

local function section(source: string, from: string, length: number): string
	local at = string.find(source, from, 1, true)
	expect(at ~= nil).toBe(true)
	return string.sub(source, at :: number, (at :: number) + length)
end

-- ===== tint: the continuous colour channel (SF-P1/SF-P2) ====================

describe("tint: the authoring boundary", function()
	it("accepts both declared value forms", function()
		UI.Box({ id = "B", tint = { role = "accent", blend = 0.5 } })
		UI.Box({ id = "B", tint = { role = "accent", blend = 0.5, from = "control" } })
		UI.Box({ id = "B", tint = { direct = "#ff8800" } })
		UI.Box({ id = "B", tint = { direct = { r = 1, g = 0.5, b = 0 } } })
		UI.Text({ id = "T", text = "x", tint = { role = "danger", blend = 1 } })
		UI.Image({ id = "I", tint = { role = "accent", blend = 0.2 } })
		UI.Path({ id = "P", points = {}, tint = { direct = "#00ff00" } })
	end)

	it("refuses a role outside the closed palette vocabulary", function()
		local err = fails(function()
			UI.Box({ id = "B", tint = { role = "sponsorBlue", blend = 1 } })
		end)
		expect(contains(err, "unknown tint role 'sponsorBlue'")).toBe(true)
		-- the message lists the vocabulary, because a name nothing validates is a
		-- tint that silently paints nothing
		expect(contains(err, "controlSelected")).toBe(true)
	end)

	it("refuses a blend outside 0..1, and a missing one", function()
		expect(contains(
			fails(function()
				UI.Box({ id = "B", tint = { role = "accent", blend = 1.5 } })
			end),
			"blend must be a number within 0..1"
		)).toBe(true)
		expect(contains(
			fails(function()
				UI.Box({ id = "B", tint = { role = "accent" } })
			end),
			"blend must be a number"
		)).toBe(true)
	end)

	it("refuses both forms at once, an unknown field, and a malformed hex", function()
		expect(contains(
			fails(function()
				UI.Box({ id = "B", tint = { role = "accent", blend = 1, direct = "#ffffff" } })
			end),
			"exactly ONE form"
		)).toBe(true)
		expect(contains(
			fails(function()
				UI.Box({ id = "B", tint = { hue = 0.5 } })
			end),
			"unknown tint field 'hue'"
		)).toBe(true)
		expect(contains(
			fails(function()
				UI.Box({ id = "B", tint = { direct = "#12345" } })
			end),
			'"#rrggbb"'
		)).toBe(true)
	end)

	it("is offered on FOUR classes only: a control paints from its role and states", function()
		for _, class in { "Box", "Text", "Image", "Path" } do
			expect((schema.forClass(class) :: any).props.tint ~= nil).toBe(true)
		end
		for _, class in { "Button", "Toggle", "TextField", "VStack", "Screen", "Grip" } do
			expect((schema.forClass(class) :: any).props.tint).toBeNil()
		end
		expect(contains(
			fails(function()
				UI.Button({ id = "B", label = "Go", tint = { role = "accent", blend = 1 } })
			end),
			"unknown property 'tint'"
		)).toBe(true)
	end)

	it("the direct form is the LOUD word: the docs call it theming-exempt", function()
		local api = fs.readFile("docs/reference/api.md")
		expect(contains(api, "theming-exempt")).toBe(true)
		-- ...and the closed-set rule is stated, because no checker can catch it
		expect(contains(api, "A value from a closed set is a state, not a tint")).toBe(true)
	end)
end)

describe("tint: resolution (the ONE pure resolver both adapters use)", function()
	it("blend = 0 is the class's identity base and blend = 1 is the role", function()
		local base = sheet_model.tintColor(NEUTRAL_THEME, { role = "accent", blend = 0 }, "Box")
		expect(base.r).toBeCloseTo(default_style.colors.surface.r, 1e-6)
		local full = sheet_model.tintColor(NEUTRAL_THEME, { role = "accent", blend = 1 }, "Box")
		expect(full.r).toBeCloseTo(default_style.colors.accent.r, 1e-6)
	end)

	it("an Image's identity base is WHITE (the picture as authored)", function()
		local base = sheet_model.tintColor(NEUTRAL_THEME, { role = "accent", blend = 0 }, "Image")
		expect(base.r).toBe(1)
		expect(base.g).toBe(1)
		expect(base.b).toBe(1)
		expect((sheet_model.TINT_IDENTITY :: any).Text).toBe("content")
		expect((sheet_model.TINT_IDENTITY :: any).Path).toBe("content")
	end)

	it("`from` names the base explicitly: control -> accent is the ratified shape", function()
		local half = sheet_model.tintColor(NEUTRAL_THEME, { role = "accent", blend = 0.5, from = "control" }, "Box")
		local control = sheet_model.paletteColor(NEUTRAL_THEME, "control")
		local accent = sheet_model.paletteColor(NEUTRAL_THEME, "accent")
		expect(half.r).toBeCloseTo((control.r + accent.r) / 2, 1e-6)
		expect(half.b).toBeCloseTo((control.b + accent.b) / 2, 1e-6)
	end)

	it("the direct form is exactly the colour it names, in both spellings", function()
		local hex = sheet_model.tintColor(NEUTRAL_THEME, { direct = "#ff8000" }, "Box")
		expect(hex.r).toBe(1)
		expect(hex.g).toBeCloseTo(128 / 255, 1e-6)
		local table_ = sheet_model.tintColor(NEUTRAL_THEME, { direct = { r = 0.25, g = 0.5, b = 0.75 } }, "Text")
		expect(table_.g).toBe(0.5)
	end)

	it("a REACTIVE value is validated at the write site, loudly", function()
		-- a bound tint is read long after construction, so this is the only place a
		-- malformed one can be caught — and a silent no-op would be the
		-- accepted-and-ignored failure this framework keeps closing
		local err = fails(function()
			sheet_model.tintColor(NEUTRAL_THEME, { role = "nope", blend = 1 }, "Box")
		end)
		expect(contains(err, "LuauUI tint on a Box")).toBe(true)
	end)

	it("the schema and the resolver share ONE role vocabulary", function()
		expect(#styling.TINT_ROLES > 0).toBe(true)
		expect(sheet_model.TINT_ROLES).toBe(styling.TINT_ROLES)
		for _, role in styling.TINT_ROLES do
			local rgb = sheet_model.paletteColor(NEUTRAL_THEME, role)
			expect(type(rgb.r)).toBe("number")
		end
	end)
end)

describe("tint: emission and application", function()
	it("rides the BINDING channel with the authority declared per class", function()
		expect(rendererLib.BINDING_PROPS.tint).toBe(true)
		for _, class in { "Box", "Text", "Image", "Path" } do
			expect(authority.authorityFor(class, "tint")).toBe("binding")
		end
		-- and NOT granted to a class that cannot declare it
		expect(authority.authorityFor("Button", "tint")).toBeNil()
	end)

	it("the adapter applies the RESOLVED colour and records the claimed properties", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.Box({ id = "Wash", surface = "control", tint = { role = "accent", blend = 1 } }),
				UI.Text({ id = "Hot", text = "Hot", tint = { direct = "#ff0000" } }),
			},
		}))
		local wash = adapter.node("/S/Wash")
		expect(wash.tintColor.r).toBeCloseTo(default_style.colors.accent.r, 1e-6)
		-- a tinted Box owns its OPACITY too, or the fill would be invisible
		expect(wash.paintClaims.BackgroundColor3).toBe(true)
		expect(wash.paintClaims.BackgroundTransparency).toBe(true)
		local hot = adapter.node("/S/Hot")
		expect(hot.tintColor.r).toBe(1)
		expect(hot.paintClaims.TextColor3).toBe(true)
		-- ...and a Text keeps TextTransparency, so the disabled state still dims
		expect(hot.paintClaims.TextTransparency).toBeNil()
	end)

	it("is the LAST paint write at creation, so a surface cannot overwrite it", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = { UI.Box({ id = "Wash", surface = "control", tint = { role = "accent", blend = 1 } }) },
		}))
		local ops = adapter.takeOps()
		local surfaceAt, tintAt = nil, nil
		for index, op in ops do
			if op == "prop /S/Wash.surface=control" then
				surfaceAt = index
			elseif string.sub(op, 1, #"prop /S/Wash.tint=") == "prop /S/Wash.tint=" then
				tintAt = index
			end
		end
		expect(surfaceAt ~= nil and tintAt ~= nil).toBe(true)
		expect((tintAt :: number) > (surfaceAt :: number)).toBe(true)
		-- the renderer says why, at the seam
		expect(contains(rendererSource, 'if BINDING_PROPS[prop] and prop ~= "tint" then')).toBe(true)
	end)

	--[[ THE TINT'S OWN ALPHA (2026-07-31). The channel exists for the one thing a
		composite cannot express — a translucent plate over a backdrop nobody can
		know (a scrim over a live 3D scene, a pill over a canvas that draws its own
		content). Every case below pins the two halves that make it real: the value
		reaches the engine PROPERTY (not just the resolver), and a tint that does not
		declare one is byte-identical to what shipped before. ]]
	it("a Box tint paints at its declared transparency, and defaults to opaque", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.Box({ id = "Scrim", tint = { direct = "#000000", transparency = 0.35 } }),
				UI.Box({ id = "Solid", tint = { direct = "#000000" } }),
			},
		}))
		expect(adapter.node("/S/Scrim").tintTransparency).toBe(0.35)
		-- the UNCHANGED default: every tint authored before the channel existed
		expect(adapter.node("/S/Solid").tintTransparency).toBe(0)
		-- ...and it rides the claim a tinted Box ALREADY held, so no new authority
		expect(adapter.node("/S/Scrim").paintClaims.BackgroundTransparency).toBe(true)
	end)

	it("Text and Image claim a transparency ONLY when the tint declares one", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.Text({ id = "Ghost", text = "Ghost", tint = { direct = "#ffffff", transparency = 0.5 } }),
				UI.Text({ id = "Plain", text = "Plain", tint = { direct = "#ffffff" } }),
			},
		}))
		expect(adapter.node("/S/Ghost").paintClaims.TextTransparency).toBe(true)
		expect(adapter.node("/S/Ghost").tintTransparency).toBe(0.5)
		-- the control: an undeclared alpha leaves TextTransparency to the disabled
		-- state, exactly as it did before the channel existed
		expect(adapter.node("/S/Plain").paintClaims.TextTransparency).toBeNil()
	end)

	it("the live adapter writes the alpha onto the engine property, all three classes", function()
		-- an engine-free suite cannot execute applyTint, so the write sites are
		-- pinned at the source: emission proved above, APPLICATION proved here
		expect(contains(adapterSource, "instance.BackgroundTransparency = alpha")).toBe(true)
		expect(contains(adapterSource, "instance.TextTransparency = alpha")).toBe(true)
		expect(contains(adapterSource, "instance.ImageTransparency = alpha")).toBe(true)
		-- ...and releasing a tint restores every property it claimed
		expect(contains(adapterSource, '"ImageTransparency",')).toBe(true)
		expect(contains(adapterSource, '"TextTransparency",')).toBe(true)
	end)

	it("a Path REFUSES an alpha rather than accepting and dropping it", function()
		-- Path2D carries a colour and a thickness and no transparency at all, so an
		-- accepted-and-ignored value would be the exact failure class this framework
		-- keeps closing (F3, the colour-emoji tint)
		local err = fails(function()
			sheet_model.tintTransparency({ direct = "#ffffff", transparency = 0.4 }, "Path")
		end)
		expect(contains(err, "LuauUI tint on a Path")).toBe(true)
		expect(contains(err, "canvasGroup")).toBe(true)
		-- a Path with NO alpha is untouched
		expect(sheet_model.tintTransparency({ direct = "#ffffff" }, "Path")).toBe(0)
	end)

	it("the schema refuses an out-of-range alpha, at construction and at the write site", function()
		local ok, detail = styling.checkTint({ direct = "#000000", transparency = 1.5 })
		expect(ok).toBe(false)
		expect(contains(tostring(detail), "0..1")).toBe(true)
		expect(styling.checkTint({ role = "accent", blend = 0.5, transparency = 0.2 })).toBe(true)
		local err = fails(function()
			UI.Box({ id = "Bad", tint = { direct = "#000000", transparency = -1 } })
		end)
		expect(contains(err, "transparency")).toBe(true)
		-- the reference documents the polarity, because 0-is-opaque is the trap
		expect(contains(fs.readFile("docs/reference/api.md"), "`0` = opaque")).toBe(true)
	end)

	it("a reactive tint re-applies through the ordinary refresh loop", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local energy = core:signal({ role = "accent", blend = 0 } :: any)
		local root = mountLib.mount(
			core,
			UI.Screen({ id = "S", children = { UI.Box({ id = "Wash", surface = "control", tint = energy }) } })
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Wash").tintColor.r).toBeCloseTo(default_style.colors.surface.r, 1e-6)
		energy:set({ role = "accent", blend = 1 })
		controller.refresh()
		expect(adapter.node("/S/Wash").tintColor.r).toBeCloseTo(default_style.colors.accent.r, 1e-6)
		-- releasing it clears the applied colour
		energy:set(nil :: any)
		controller.refresh()
		expect(adapter.node("/S/Wash").tintColor).toBeNil()
	end)
end)

describe("tint: the native-sheet claim mechanism (source contract)", function()
	it("the central gate CONSULTS the claims instead of erroring on them", function()
		local body = section(adapterSource, "local function assertBespokePaint(engineProp: string, handle: any?)", 700)
		expect(contains(body, "handle.paintClaims[engineProp] == true")).toBe(true)
		expect(contains(body, "bespoke write to sheet-owned")).toBe(true)
	end)

	it("a claim records the pre-claim value through GetStyled and publishes it", function()
		local body = section(adapterSource, "local function claimPaint(handle: any, engineProp: string)", 900)
		expect(contains(body, "handle.paintRestore[engineProp] = styledValue(handle.instance, engineProp)")).toBe(true)
		expect(contains(body, "SetAttribute(CLAIM_ATTRIBUTE")).toBe(true)
		-- GetStyled is the instrument: a plain read is blind to a rule-owned value
		expect(contains(section(adapterSource, "local function styledValue(", 500), "GetStyled(engineProp)")).toBe(true)
	end)

	it("the claim does NOT strip the node's tags, and the file says why", function()
		local block = section(adapterSource, "===== PAINT CLAIMS (ADR-0022 Decision 6)", 2600)
		expect(contains(block, "THE CLAIM DOES NOT STRIP THE NODE'S TAGS")).toBe(true)
		-- the reason is CONCRETE: a surface tag carries more than one property, so
		-- removing it to hand over a colour would take away unnamed chrome
		expect(contains(block, "phantom ::UICorner radius")).toBe(true)
		expect(contains(block, "::UIStroke hairline")).toBe(true)
		-- ...and nothing in the tint path removes a tag
		local tint = section(adapterSource, "local function applyTint(handle: any)", 2600)
		expect(contains(tint, "RemoveTag")).toBe(false)
	end)

	it("every claimed write goes claim-then-assert, per class", function()
		local tint = section(adapterSource, "local function applyTint(handle: any)", 2600)
		expect(contains(tint, 'claimPaint(handle, "ImageColor3")')).toBe(true)
		expect(contains(tint, 'claimPaint(handle, "TextColor3")')).toBe(true)
		expect(contains(tint, 'claimPaint(handle, "BackgroundColor3")')).toBe(true)
		expect(contains(tint, 'claimPaint(handle, "BackgroundTransparency")')).toBe(true)
		expect(contains(tint, 'assertBespokePaint("BackgroundColor3", handle)')).toBe(true)
		-- the Path2D needs no claim: nothing can style one
		expect(contains(tint, "handle.path2d.Color3 = color")).toBe(true)
	end)

	it("a repaint of a claimed property re-applies the tint (declared as a set)", function()
		expect(contains(adapterSource, "local TINT_REPAINTING_PROPS: { [string]: boolean } =")).toBe(true)
		expect(contains(adapterSource, "if handle.tint ~= nil and TINT_REPAINTING_PROPS[prop] then")).toBe(true)
	end)

	it("the claim reaches the node dump, beside the GetStyled reading it explains", function()
		expect(contains(runnerSource, 'inst:GetAttribute("LuauUI_PaintClaims")')).toBe(true)
		expect(contains(runnerSource, "d.paintClaims = claims")).toBe(true)
	end)

	it("the four claimable properties are the sheet-owned ones (that is why they claim)", function()
		for _, prop in { "BackgroundColor3", "BackgroundTransparency", "TextColor3", "ImageColor3", "ScaleType" } do
			expect(authority.nativeSheetOwned(prop)).toBe(true)
		end
	end)
end)

-- ===== scaleMode (SF-P2) ===================================================

describe("Image scaleMode", function()
	it("is a closed set, and an unknown value is a construction error", function()
		UI.Image({ id = "I", scaleMode = "fit" })
		UI.Image({ id = "I", scaleMode = "fill" })
		UI.Image({ id = "I", scaleMode = "crop" })
		UI.Image({ id = "I", scaleMode = "stretch" })
		local err = fails(function()
			UI.Image({ id = "I", scaleMode = "cover" })
		end)
		expect(contains(err, "fit | fill | crop | stretch")).toBe(true)
		-- slice stays theme-owned chrome
		expect(contains(err, "slice")).toBe(false)
	end)

	it("rides the STYLE channel and applies at creation and reactively", function()
		expect(rendererLib.STYLE_PROPS.scaleMode).toBe(true)
		expect(authority.authorityFor("Image", "scaleMode")).toBe("style")
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local mode = core:signal("fit")
		local root = mountLib.mount(
			core,
			UI.Screen({ id = "S", children = { UI.Image({ id = "Face", image = "rbxassetid://1", scaleMode = mode }) } })
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Face").appliedScaleType).toBe("Fit")
		mode:set("fill")
		controller.refresh()
		expect(adapter.node("/S/Face").appliedScaleType).toBe("Crop")
		expect(adapter.node("/S/Face").paintClaims.ScaleType).toBe(true)
	end)

	it("fill and crop are DELIBERATE synonyms for the engine's Crop, in both adapters", function()
		expect(fake_target.SCALE_MODE_ENGINE_NAME.fill).toBe("Crop")
		expect(fake_target.SCALE_MODE_ENGINE_NAME.crop).toBe("Crop")
		expect(contains(adapterSource, "fill = Enum.ScaleType.Crop")).toBe(true)
		expect(contains(adapterSource, "crop = Enum.ScaleType.Crop")).toBe(true)
		expect(contains(adapterSource, "stretch = Enum.ScaleType.Stretch")).toBe(true)
		expect(contains(adapterSource, "fit = Enum.ScaleType.Fit")).toBe(true)
	end)

	it("the live write claims ScaleType and restores it when the declaration goes", function()
		local body = section(adapterSource, 'elseif prop == "scaleMode" then', 900)
		expect(contains(body, 'claimPaint(handle, "ScaleType")')).toBe(true)
		expect(contains(body, 'assertBespokePaint("ScaleType", handle)')).toBe(true)
		expect(contains(body, 'restorePaint(handle, "ScaleType")')).toBe(true)
	end)
end)

-- ===== UI.stroke (SF-P3) ===================================================

describe("UI.stroke: the authored border", function()
	it("defaults to the theme's hairline and normalizes its three fields", function()
		local bp = UI.stroke(UI.Box({ id = "Row" }), {})
		expect(bp.props.stroke.thickness).toBe(default_style.strokes.hairline)
		expect(bp.props.stroke.transparency).toBe(default_style.extra.hairlineOpacity)
		expect(bp.props.stroke.color.r).toBe(default_style.extra.hairline.r)
		local tuned = UI.stroke(UI.Box({ id = "Row" }), { thickness = 2, color = "accent", transparency = 0.25 })
		expect(tuned.props.stroke.thickness).toBe(2)
		expect(tuned.props.stroke.color.r).toBeCloseTo(default_style.colors.accent.r, 1e-6)
		expect(tuned.props.stroke.transparency).toBe(0.25)
		-- a hex literal is legal here too (the same declared escape the tint has)
		expect(UI.strokeData({ color = "#00ff00" }).color.g).toBe(1)
	end)

	it("rejects an unknown field and a Signal inside the spec, naming the pulse idiom", function()
		expect(contains(
			fails(function()
				UI.stroke(UI.Box({ id = "R" }), { thicknes = 2 })
			end),
			"unknown stroke field 'thicknes'"
		)).toBe(true)
		local core = customFactory.new()
		local err = fails(function()
			UI.stroke(UI.Box({ id = "R" }), { thickness = core:signal(2) })
		end)
		expect(contains(err, "cannot be a Signal/Memo")).toBe(true)
		expect(contains(err, "UI.strokeData")).toBe(true)
	end)

	it("returns a NEW blueprint (blueprints are frozen) and rides the style authority", function()
		local base = UI.Box({ id = "Row" })
		local stroked = UI.stroke(base, { thickness = 2 })
		expect(base.props.stroke).toBeNil()
		expect(stroked.props.stroke ~= nil).toBe(true)
		expect(rendererLib.STYLE_PROPS.stroke).toBe(true)
		expect(authority.authorityFor("Box", "stroke")).toBe("style")
		expect(authority.authorityFor("Button", "stroke")).toBe("style")
	end)

	it("materializes ONE instance and REUSES it, so a pulse cannot stack borders", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local pulse = core:signal(UI.strokeData({ thickness = 1 }) :: any)
		local root = mountLib.mount(
			core,
			UI.Screen({ id = "S", children = { UI.Box({ id = "Row", surface = "control", stroke = pulse }) } })
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local live = adapter.node("/S/Row").strokeInstance
		expect(live.name).toBe(authority.INSTANCE_NAMES.stroke)
		expect(live.thickness).toBe(1)
		expect(live.applyStrokeMode).toBe("Border")
		pulse:set(UI.strokeData({ thickness = 3, transparency = 0.1 }))
		controller.refresh()
		local after = adapter.node("/S/Row").strokeInstance
		expect(after).toBe(live) -- the SAME instance
		expect(after.thickness).toBe(3)
		expect(after.creations).toBe(2) -- two writes, one instance
		pulse:set(nil :: any)
		controller.refresh()
		expect(adapter.node("/S/Row").strokeInstance).toBeNil()
	end)

	it("is a declared bespoke family, named from the manifest's own constant", function()
		expect(authority.INSTANCE_NAMES.stroke).toBe("LuauUIStroke")
		expect(authority.bespokeInstances()[authority.INSTANCE_NAMES.stroke] ~= nil).toBe(true)
		local body =
			section(adapterSource, "local function applyStroke(instance: Instance, stroke: any, handle: any)", 1200)
		expect(contains(body, "live.Name = authority.INSTANCE_NAMES.stroke")).toBe(true)
		expect(contains(body, "Enum.ApplyStrokeMode.Border")).toBe(true)
		expect(contains(body, "handle.strokeInstance:Destroy()")).toBe(true)
	end)

	it("COEXISTS with theme chrome: it neither asserts against the sheet nor removes a hairline", function()
		local body =
			section(adapterSource, "local function applyStroke(instance: Instance, stroke: any, handle: any)", 1200)
		-- an authored override is sanctioned (the standing UI.corners/UI.shadow have),
		-- so it does not route through the native gate...
		expect(contains(body, "assertBespokePaint")).toBe(false)
		-- ...and it never touches the adapter's own hairline child or a theme's rule
		expect(contains(body, "Hairline")).toBe(false)
		expect(contains(body, "RemoveTag")).toBe(false)
		-- the reason is on the record in the manifest and the reference
		expect(contains(authority.bespokeInstances()[authority.INSTANCE_NAMES.stroke], "additive")).toBe(true)
		expect(contains(fs.readFile("docs/reference/api.md"), "additive, not a replacement")).toBe(true)
	end)

	it("...and the theme's own chrome stroke is untouched: both mechanisms still exist", function()
		-- the OTHER half of coexistence, from the sheet's side: a theme's border is a
		-- phantom `::UIStroke` MODIFIER RULE with no child instance, so the authored
		-- child and the rule are different mechanisms on different objects and neither
		-- can suppress the other (the engine renders both — ADR-0020 R8). If this
		-- family of rules ever disappeared, an authored stroke would look like it had
		-- replaced the theme's, which is exactly the confusion to keep pinned.
		local model = sheet_model.build({ themes = { { name = "Dark", style = default_style } } })
		local phantomStrokes = 0
		for _, rule in model.rules do
			if string.find(rule.selector, "::UIStroke", 1, true) ~= nil then
				phantomStrokes += 1
				expect(rule.props.Thickness ~= nil).toBe(true)
			end
		end
		expect(phantomStrokes > 0).toBe(true)
		-- ...and no rule in the sheet targets the authored child by name
		for _, rule in model.rules do
			expect(contains(rule.selector, authority.INSTANCE_NAMES.stroke)).toBe(false)
		end
	end)
end)

-- ===== zIndex (SF-P4) ======================================================

describe("zIndex: paint order within the parent's stacking scope", function()
	local function zScreen(ghostZ: number?)
		return UI.Screen({
			id = "S",
			children = {
				UI.Box({ id = "A" }),
				UI.Box({ id = "Ghost", zIndex = ghostZ }),
				UI.Box({ id = "C" }),
			},
		})
	end

	it("without a zIndex the order is tree order (nothing moves)", function()
		local adapter = render(zScreen(nil))
		expect(adapter.node("/S/A").z < adapter.node("/S/Ghost").z).toBe(true)
		expect(adapter.node("/S/Ghost").z < adapter.node("/S/C").z).toBe(true)
	end)

	it("a lifted sibling paints above the siblings it was declared before", function()
		local adapter = render(zScreen(5))
		local ghost = adapter.node("/S/Ghost").z
		expect(ghost > adapter.node("/S/A").z).toBe(true)
		expect(ghost > adapter.node("/S/C").z).toBe(true)
	end)

	it("a NEGATIVE zIndex sinks below its zero-index siblings", function()
		local adapter = render(zScreen(-1))
		local ghost = adapter.node("/S/Ghost").z
		expect(ghost < adapter.node("/S/A").z).toBe(true)
		expect(ghost < adapter.node("/S/C").z).toBe(true)
	end)

	it("a node's whole SUBTREE travels with it", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.VStack({ id = "List", children = { UI.Text({ id = "Row", text = "Row" }) } }),
				UI.VStack({ id = "Lift", zIndex = 10, children = { UI.Text({ id = "Chip", text = "Chip" }) } }),
			},
		}))
		expect(adapter.node("/S/Lift").z > adapter.node("/S/List/Row").z).toBe(true)
		expect(adapter.node("/S/Lift/Chip").z > adapter.node("/S/Lift").z).toBe(true)
	end)

	it("a child is ALWAYS above its own parent: lifting across scopes stays structural", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Scope",
					children = { UI.Box({ id = "Sunk", zIndex = -50 }) },
				}),
			},
		}))
		expect(adapter.node("/S/Scope/Sunk").z > adapter.node("/S/Scope").z).toBe(true)
		expect(adapter.node("/S/Scope").z > adapter.node("/S").z).toBe(true)
	end)

	it("the order is DETERMINISTIC across re-solves and structural syncs", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(core, zScreen(5))
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local first = {
			a = adapter.node("/S/A").z,
			ghost = adapter.node("/S/Ghost").z,
			c = adapter.node("/S/C").z,
		}
		env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
		controller.refresh()
		expect(adapter.node("/S/A").z).toBe(first.a)
		expect(adapter.node("/S/Ghost").z).toBe(first.ghost)
		expect(adapter.node("/S/C").z).toBe(first.c)
	end)

	it("is read once at mount and rejects a Signal, like every `what a node IS` prop", function()
		local core = customFactory.new()
		local err = fails(function()
			UI.Box({ id = "B", zIndex = core:signal(3) })
		end)
		expect(contains(err, "does not accept a Signal/Memo")).toBe(true)
		expect(authority.authorityFor("common", "zIndex")).toBe("layout")
	end)

	it("ties are broken by declaration order rather than by an unstable sort", function()
		local adapter = render(UI.Screen({
			id = "S",
			children = {
				UI.Box({ id = "One", zIndex = 2 }),
				UI.Box({ id = "Two", zIndex = 2 }),
				UI.Box({ id = "Three", zIndex = 2 }),
			},
		}))
		expect(adapter.node("/S/One").z < adapter.node("/S/Two").z).toBe(true)
		expect(adapter.node("/S/Two").z < adapter.node("/S/Three").z).toBe(true)
		expect(contains(rendererSource, "return a.index < b.index")).toBe(true)
	end)
end)
