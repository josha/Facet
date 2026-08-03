--!strict
-- THE TYPOGRAPHY WEIGHT CHANNEL (F2, racer-sort parity, 2026-08-02).
--
-- `strong` and `numeral` are typography ROLES, not a `weight` prop, and the
-- reason is the whole point of this file: a role flows through MEASUREMENT and
-- PAINT together. `UI.Text.font` — the deprecated authored-font prop — reached
-- the text-metrics measure seam and no paint seam at all, so an authored face
-- silently made the reserved box and the drawn glyphs disagree; its deprecation
-- entry says exactly that. A weight prop would have rebuilt the same split.
--
-- What is proved here, in the order the defect would appear:
--   * the ramp answers all eight roles, and the two new ones carry their own
--     faces while the six that shipped are byte-identical;
--   * a `strong` label MEASURES with its own descriptor — read off the real
--     premeasure request queue, not re-derived — and PAINTS the same string;
--   * an unknown role is refused at construction, naming the set;
--   * a package may author the weight faces, and an unauthored one derives from
--     the package's OWN family;
--   * both native seams (the tag and the rule) carry that same descriptor.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local text_metrics = require("../src/layout/text_metrics")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local tokens = require("../src/tokens/tokens")
local defaultStyle = require("../src/tokens/default_style")
local fake_target = require("../tests/lib/fake_target")

local function world(build: () -> any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local root = mountLib.mount(core, build())
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return core, env, adapter, controller
end

local function derive(id: string, metrics: any): any
	local pkg, report = themes.define({
		base = snapshot.neutralPackage(),
		identity = { id = id, displayName = id, schemaVersion = themes.SCHEMA, version = "1.0.0" },
		metrics = metrics,
	})
	assert(pkg ~= nil, "derive failed: " .. (if report.errors[1] then report.errors[1].message else "?"))
	return pkg
end

describe("the ramp grows two WEIGHT roles and moves nothing else", function()
	it("Studio Neutral answers all eight roles", function()
		local snap = snapshot.neutral()
		for _, role in themes.TYPE_ROLES do
			expect(`{role}: {type(snap.type[role])}`).toBe(`{role}: table`)
		end
		expect(#themes.TYPE_ROLES).toBe(8)
	end)

	it("the six roles that shipped are byte-identical: every one still BuilderSans Regular", function()
		-- the compatibility bar. `check_flat_baseline` proves the same thing across
		-- 1140 rendered nodes; this states it at the source so a face change can
		-- never be "explained" by a regenerated dump.
		local snap = snapshot.neutral()
		for _, role in themes.REQUIRED_TYPE_ROLES do
			expect(`{role}={snap.type[role].fontKey}`).toBe(`{role}=BuilderSans#Regular#Normal`)
		end
	end)

	it("strong is body's size in the family's SemiBold face; numeral is control's size in Bold", function()
		local snap = snapshot.neutral()
		expect(snap.type.strong.size).toBe(snap.type.body.size)
		expect(snap.type.strong.fontKey).toBe("BuilderSans#SemiBold#Normal")
		expect(snap.type.numeral.size).toBe(snap.type.control.size)
		expect(snap.type.numeral.fontKey).toBe("BuilderSans#Bold#Normal")
		-- the ladder those sizes come from is the one table, not a literal here
		expect(snap.type.body.size).toBe(defaultStyle.type.body)
		expect(snap.type.control.size).toBe(defaultStyle.type.control)
	end)

	it("both are legal typography-role names and an invented one is not", function()
		expect(snapshot.isTypeRole("strong")).toBe(true)
		expect(snapshot.isTypeRole("numeral")).toBe(true)
		expect(snapshot.isTypeRole("bolder")).toBe(false)
	end)
end)

describe("one role, both seams: measured and painted read the same descriptor", function()
	it("a strong label measures with its OWN descriptor and paints that same string", function()
		-- the descriptors are read off the real premeasure request queue — the
		-- thing the engine would be asked to measure — rather than re-derived, so
		-- this cannot pass by asking the same function the renderer asked.
		text_metrics.resetMeasured()
		local _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Text({ id = "Strong", text = "Zzqwx", textSize = "strong" }),
					UI.Text({ id = "Plain", text = "Yyplk", textSize = "body" }),
				},
			})
		end)
		local requested: { [string]: string } = {}
		for _, request in adapter.pendingTextRequests() do
			requested[request.word] = request.font
		end
		local snap = snapshot.neutral()
		-- MEASURE: the strong word was queued under the SemiBold descriptor, the
		-- body word under Regular. A `weight` prop that only reached paint would
		-- leave both of these on Regular.
		expect(requested.Zzqwx).toBe(snap.type.strong.fontKey)
		expect(requested.Yyplk).toBe(snap.type.body.fontKey)
		expect(requested.Zzqwx ~= requested.Yyplk).toBe(true)
		-- PAINT: the adapter is handed the same descriptor string, plus the role
		-- name the native seam tags with
		expect(adapter.node("/S/Strong").props.textFont.fontKey).toBe(snap.type.strong.fontKey)
		expect(adapter.node("/S/Strong").props.textFont.role).toBe("strong")
		expect(adapter.node("/S/Strong").props.textFont.weight).toBe("SemiBold")
		expect(adapter.node("/S/Plain").props.textFont.fontKey).toBe(snap.type.body.fontKey)
		-- THE INVARIANT, stated as one comparison: what was measured IS what is
		-- painted, for this node, in this solve.
		expect(adapter.node("/S/Strong").props.textFont.fontKey).toBe(requested.Zzqwx)
	end)

	it("the size travels with the face, so a numeral is 18px Bold and not 16px Bold", function()
		local _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Text({ id = "Pos", text = "1", textSize = "numeral" }) },
			})
		end)
		local snap = snapshot.neutral()
		expect(adapter.node("/S/Pos").props.textSize).toBe(snap.type.numeral.size)
		expect(adapter.node("/S/Pos").props.textFont.fontKey).toBe(snap.type.numeral.fontKey)
	end)

	it("an INTRINSIC role paints its face too — a Button wears `control`, not `body`", function()
		-- the half of the seam that was silently wrong before F2: `textOf` handed
		-- the measurer `nil` for an unauthored size and the solver fell back to
		-- `body`, while the class's intrinsic role is `control`. Invisible under a
		-- one-face ramp; a measured-versus-painted split under any other.
		local _, _, adapter = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Text({ id = "T", text = "Hi" }),
					UI.Button({ id = "B", label = "Play" }),
					UI.Box({ id = "Plain", width = { type = "fixed", px = 10 }, height = { type = "fixed", px = 10 } }),
				},
			})
		end)
		expect(adapter.node("/S/T").props.textFont.role).toBe("body")
		expect(adapter.node("/S/B").props.textFont.role).toBe("control")
		-- a node that draws no text is handed no face
		expect(adapter.node("/S/Plain").props.textFont).toBeNil()
	end)

	it("a role swap re-solves and repaints the face without a rebuild", function()
		local pkg = derive("weight-swap", {
			typography = {
				strong = { font = { family = "GothamSSm", weight = "Bold" }, size = 18, lineHeight = 1.2 },
			},
		})
		local _, env, adapter, controller = world(function()
			return UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Text({ id = "N", text = "Razz", textSize = "strong" }) },
			})
		end)
		expect(adapter.node("/S/N").props.textFont.fontKey).toBe("BuilderSans#SemiBold#Normal")
		env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
		controller.refresh()
		expect(adapter.node("/S/N").props.textFont.fontKey).toBe("GothamSSm#Bold#Normal")
		expect(adapter.node("/S/N").props.textSize).toBe(18)
	end)
end)

describe("construction refuses an unknown role, naming the eight", function()
	it("UI.Text{ textSize = 'bolder' } errors", function()
		expect(function()
			UI.Text({ id = "T", text = "x", textSize = "bolder" })
		end).toThrow()
	end)

	it("...and the refusal names every legal role, including the two new ones", function()
		local ok, err = pcall(function()
			UI.Text({ id = "T", text = "x", textSize = "bolder" })
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		for _, role in themes.TYPE_ROLES do
			expect(`{role} named: {string.find(message, role, 1, true) ~= nil}`).toBe(`{role} named: true`)
		end
	end)

	it("a theme package refuses an unknown typography role the same way", function()
		local pkg, report = themes.define({
			base = snapshot.neutralPackage(),
			identity = { id = "bad-role", displayName = "bad", schemaVersion = themes.SCHEMA, version = "1.0.0" },
			metrics = {
				typography = { bolder = { font = { family = "BuilderSans" }, size = 16, lineHeight = 1.2 } },
			},
		})
		expect(pkg).toBeNil()
		local found = false
		for _, entry in report.errors do
			if string.find(entry.message, "bolder", 1, true) ~= nil then
				found = true
				expect(string.find(entry.fix, "numeral", 1, true) ~= nil).toBe(true)
				expect(string.find(entry.fix, "strong", 1, true) ~= nil).toBe(true)
			end
		end
		expect(found).toBe(true)
	end)
end)

describe("a package owns its weight faces", function()
	it("an AUTHORED weight role beats the derivation", function()
		local snap = snapshot.resolve(
			derive("authored-weight", {
				typography = {
					numeral = { font = { family = "GothamSSm", weight = "Heavy" }, size = 22, lineHeight = 1.1 },
				},
			}),
			nil,
			{}
		)
		expect(snap.type.numeral.fontKey).toBe("GothamSSm#Heavy#Normal")
		expect(snap.type.numeral.size).toBe(22)
		-- ...and the role it would have derived from is untouched
		expect(snap.type.control.fontKey).toBe("BuilderSans#Regular#Normal")
	end)

	it("an UNAUTHORED one derives from the package's OWN family and style", function()
		local snap = snapshot.resolve(
			derive("display-family", {
				typography = {
					body = {
						font = { family = "GothamSSm", weight = "Light", style = "Italic" },
						size = 15,
						lineHeight = 1.3,
					},
				},
			}),
			nil,
			{}
		)
		-- family and style follow the base role; only the WEIGHT is the derivation's
		expect(snap.type.strong.fontKey).toBe("GothamSSm#SemiBold#Italic")
		expect(snap.type.strong.size).toBe(15)
		expect(snap.type.strong.lineHeight).toBe(1.3)
	end)

	it("the two shipped reference packages keep a coherent ramp", function()
		-- a real package, not a fixture: sci-fi runs a display face, so its derived
		-- weight roles must be that face rather than the framework's default
		local pkg = require("../examples/themes/scifi_hud").build({
			define = themes.define,
			neutralPackage = snapshot.neutralPackage,
			SCHEMA = themes.SCHEMA,
		})
		local snap = snapshot.resolve(pkg, nil, {})
		expect(string.find(snap.type.strong.fontKey, snap.type.body.font.family, 1, true)).toBe(1)
		expect(string.find(snap.type.strong.fontKey, "#SemiBold#", 1, true) ~= nil).toBe(true)
	end)

	it("no package's content STAMP moved: the roles are derived at resolve, never authored", function()
		-- the constraint the `iconSizes` note in snapshot.resolve records. A derived
		-- package's stamp is a hash of its AUTHORED metrics, so adding the roles to
		-- the neutral definition would have invalidated every stored capture.
		local neutral = snapshot.neutralPackage()
		expect(neutral.metrics.typography.strong).toBeNil()
		expect(neutral.metrics.typography.numeral).toBeNil()
		expect(snapshot.neutral().type.strong ~= nil).toBe(true)
	end)
end)

describe("tokens.compile derives the two sizes", function()
	-- `tokens.compile` deep-freezes what it is handed, so the schema is built
	-- fresh here rather than borrowed from the (already frozen) default style
	local function rgb(r: number, g: number, b: number): any
		return { r = r, g = g, b = b }
	end
	local function schema(typeRamp: any): any
		return {
			colors = {
				surface = rgb(0, 0, 0),
				content = rgb(1, 1, 1),
				surfaceStrong = rgb(0.05, 0.05, 0.05),
				contentStrong = rgb(1, 1, 1),
				accent = rgb(0.1, 0.3, 0.8),
				onAccent = rgb(1, 1, 1),
			},
			type = typeRamp,
			space = { xs = 4, s = 8, m = 16, l = 24, xl = 40 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.12, normal = 0.2 },
		}
	end

	it("a game schema that omits them still answers both", function()
		local compiled = tokens.compile(schema({ caption = 10, label = 12, body = 14, heading = 18, title = 22 }))
		expect(compiled.type.strong).toBe(14) -- body
		expect(compiled.type.numeral).toBe(18) -- no control role -> heading
	end)

	it("`control` is preferred over `heading` for numeral, matching the theme derivation", function()
		local compiled =
			tokens.compile(schema({ caption = 10, label = 12, body = 14, heading = 18, title = 22, control = 16 }))
		expect(compiled.type.numeral).toBe(16)
		-- the built-in style takes the same route, so the two derivations agree
		expect(defaultStyle.type.numeral).toBe(defaultStyle.type.control)
		expect(defaultStyle.type.strong).toBe(defaultStyle.type.body)
	end)

	it("an authored size wins", function()
		local compiled = tokens.compile(schema({
			caption = 10,
			label = 12,
			body = 14,
			heading = 18,
			title = 22,
			strong = 15,
			numeral = 30,
		}))
		expect(compiled.type.strong).toBe(15)
		expect(compiled.type.numeral).toBe(30)
	end)
end)

describe("native paint carries the same face through a tag and a rule", function()
	it("a node's role becomes a luau-type-<role> tag", function()
		local tags = sheet_model.classifyTags({ typeRole = "numeral" })
		expect(tags["luau-type-numeral"]).toBe(true)
		-- ...and it is NOT the content-colour emphasis tag, which means something else
		expect(tags["luau-role-strong"]).toBeNil()
		expect(sheet_model.classifyTags({})["luau-type-body"]).toBeNil()
	end)

	it("buildPackage emits one FontFace rule per role, from type.<role>.font", function()
		local pkg = snapshot.neutralPackage()
		local snap = snapshot.resolve(pkg, nil, {})
		local model = sheet_model.buildPackage(pkg)
		local byName: { [string]: any } = {}
		for _, rule in model.rules do
			byName[rule.name] = rule
		end
		for _, role in themes.TYPE_ROLES do
			local rule = byName[`Type — {role}`]
			expect(`{role} rule: {rule ~= nil}`).toBe(`{role} rule: true`)
			expect(rule.selector).toBe(`.luau-type-{role}`)
			-- THE ONE SOURCE: the rule's face is the snapshot's face for that role,
			-- which is the face the solver measured with
			expect(`{role}: {rule.props.FontFace.weight}`).toBe(`{role}: {snap.type[role].font.weight}`)
			expect(`{role}: {rule.props.FontFace.family}`).toBe(`{role}: {snap.type[role].font.family}`)
		end
	end)

	it("the package-less built-in model states the same two weight faces", function()
		local model = sheet_model.build({ themes = { { name = "Dark", style = defaultStyle } } })
		local byName: { [string]: any } = {}
		for _, rule in model.rules do
			byName[rule.name] = rule
		end
		local neutral = snapshot.neutral()
		expect(byName["Type — strong"].props.FontFace.weight).toBe(neutral.type.strong.font.weight)
		expect(byName["Type — numeral"].props.FontFace.weight).toBe(neutral.type.numeral.font.weight)
	end)
end)
