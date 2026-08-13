--!strict
-- `compactLabel` — a Button says less when it has less room (director, 2026-07-27).
--
-- The ladder under test:
--     full label fits            -> the full label
--     full label does not fit    -> the compact form
--     no compact form declared   -> today's behaviour (a word ellipsizes, a
--                                   phrase wraps — director round 6)
--
-- The rule that makes it worth having: IF A COMPACT REPRESENTATION EXISTS, NEVER
-- ELLIPSIZE. The `…` is for a button with nothing better to say.
--
-- Measured, not asserted from source text: every case here mounts through the
-- real renderer against `fake_target` and reads the rect and the drawn string the
-- adapter actually received. The package sweep installs each reference package
-- the way the framework does at runtime -- `env:set("themeMetrics", ...)` -- because
-- Studio Neutral reserves nothing for chrome and hides this entire class of bug.
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
-- packages are BUILT through the public facade (`LuauUI.themes` carries
-- `neutralPackage`, which every reference package derives from); the bare package
-- module is the compiler and is what owns the glyph table.
local LuauUI = require("../src") :: any
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local standard_icons = require("../src/themes/standard_icons")
local fake_target = require("./lib/fake_target")

-- the eight shipped reference packages plus the flat theme = the nine
-- configurations every geometry claim in this repo is measured against
local PACKAGES = {
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"fantasy_ornate",
	"scifi_hud",
	"compact_pointer",
	"classic_desktop",
	"fantasy_parchment",
}

type Drawn = { label: any, w: number, h: number, compact: boolean }

-- mount ONE button at a fixed width and report what the adapter was told to draw
local function drawAt(spec: any, px: number, pkg: any?): Drawn
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if pkg ~= nil then
		env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
	end
	local adapter = fake_target.new()
	local props: any = table.clone(spec)
	props.id = "B"
	props.width = { type = "fixed", px = px }
	local root = mountLib.mount(core, UI.Screen({ id = "S", padding = 0, children = { UI.Button(props) } }))
	local controller = rendererLib.attach(core, root, env, adapter, {})
	controller.initialRender()
	local node = adapter.node("/S/B")
	local out: Drawn = {
		label = node.props.label,
		w = node.rect.w,
		h = node.rect.h,
		compact = node.props.label ~= spec.label,
	}
	controller.dispose()
	root.dispose()
	return out
end

-- the same mount, with BOTH axes pinned — the icon-button shape every spec writes
-- for a control at the touch floor (`width = height = targetSizes.minimum`)
local function drawSquare(spec: any, px: number): Drawn
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local props: any = table.clone(spec)
	props.id = "B"
	props.width = { type = "fixed", px = px }
	props.height = { type = "fixed", px = px }
	-- inside an Anchor, because that is where a size toggle / skip chip lives and
	-- it is the path that skipped the ladder
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			padding = 0,
			children = { UI.Anchor({ id = "A", children = { UI.Button(props) } }) },
		})
	)
	local controller = rendererLib.attach(core, root, env, adapter, {})
	controller.initialRender()
	local node = adapter.node("/S/A/B")
	local out: Drawn =
		{ label = node.props.label, w = node.rect.w, h = node.rect.h, compact = node.props.label ~= spec.label }
	controller.dispose()
	root.dispose()
	return out
end

describe("compactLabel: a node with BOTH dimensions fixed still runs the ladder", function()
	-- Found live 2026-07-30 (RascalRally's sponsor table): `content()` is lazy, and
	-- a node whose width AND height are both fixed never asks for its content size —
	-- so the compact verdict, which lives inside that measure, never ran. The shape
	-- that hit it is the one every spec writes for a 44px icon button, i.e. exactly
	-- the case `compactLabel` exists for.
	it("a 44px square button draws its GLYPH, not its ellipsized label", function()
		local pinned = drawSquare({ label = "Minimize", compactLabel = { text = "\u{2013}" } }, 44)
		expect(`{pinned.w}x{pinned.h}`).toBe("44x44")
		expect(pinned.label).toBe("\u{2013}")
		expect(pinned.compact).toBe(true)
	end)

	it("…and a square button with ROOM still draws the full label", function()
		local roomy = drawSquare({ label = "Ok", compactLabel = { text = "\u{2013}" } }, 200)
		expect(roomy.label).toBe("Ok")
		expect(roomy.compact).toBe(false)
	end)

	it("a square button with NO compact form is unchanged (no extra measure, no swap)", function()
		local plain = drawSquare({ label = "Minimize" }, 44)
		expect(plain.label).toBe("Minimize")
		expect(plain.compact).toBe(false)
	end)
end)

describe("compactLabel: the ladder", function()
	it("a label that FITS is drawn in full — nothing that fits today moves", function()
		local wide = drawAt({ label = "Edit item", compactLabel = "Ed" }, 400)
		expect(wide.label).toBe("Edit item")
		expect(wide.compact).toBe(false)
	end)

	it("a label that does NOT fit is replaced by the compact form", function()
		local tight = drawAt({ label = "Edit item", compactLabel = "Ed" }, 60)
		expect(tight.label).toBe("Ed")
	end)

	it("...and the compact form is ONE LINE, which is the whole point", function()
		-- the failure this feature exists to remove is a button growing a second
		-- line (or breaking a word) because its label did not fit. A compact form
		-- that wrapped would reproduce it exactly.
		local roomy = drawAt({ label = "Edit item", compactLabel = "Ed" }, 400)
		local tight = drawAt({ label = "Edit item", compactLabel = "Ed" }, 60)
		expect(tight.h).toBe(roomy.h)
	end)

	it("a PHRASE takes the compact form instead of wrapping", function()
		-- the honest fit question is the natural ONE-LINE width: a word overflows
		-- its box when it does not fit, but a phrase WRAPS, so its wrapped width is
		-- never wider than the box and comparing wrapped widths would have made a
		-- compact form unreachable for every multi-word label.
		local plain = drawAt({ label = "Save changes" }, 130)
		local compact = drawAt({ label = "Save changes", compactLabel = "Save" }, 130)
		expect(compact.label).toBe("Save")
		expect(compact.h < plain.h).toBe(true)
	end)

	it("with NO compact form, round 6's word/phrase rule is untouched", function()
		-- a word stays one line and ellipsizes; a phrase wraps. Both are the
		-- behaviour that shipped on 2026-07-27, and `compactLabel` sits on top of
		-- it rather than replacing it.
		local wordTight = drawAt({ label = "Extraordinarily" }, 130)
		local wordRoomy = drawAt({ label = "Extraordinarily" }, 400)
		expect(wordTight.h).toBe(wordRoomy.h)
		local phraseTight = drawAt({ label = "Save changes" }, 130)
		local phraseRoomy = drawAt({ label = "Save changes" }, 400)
		expect(phraseTight.h > phraseRoomy.h).toBe(true)
	end)

	it("an UNBOUNDED button never goes compact — a button free to grow says everything", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.HStack({
						id = "Row",
						children = { UI.Button({ id = "B", label = "Edit item", compactLabel = "Ed" }) },
					}),
				},
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/Row/B").props.label).toBe("Edit item")
		controller.dispose()
		root.dispose()
	end)
end)

describe("compactLabel: one decision, two seams", function()
	it("the box the solver RESERVED is the box the compact string needs, not the full label's", function()
		-- this is the invariant the whole design exists for. A box reserved for one
		-- string and drawn with another is the defect class this repo keeps meeting
		-- (docs/lessons/one-word-two-subsystems.md); measuring at paint time or
		-- choosing at arrange time would both produce it.
		local compact = drawAt({ label = "Edit item", compactLabel = "Ed" }, 60)
		local literal = drawAt({ label = "Ed" }, 60)
		expect(compact.h).toBe(literal.h)
	end)

	it("the SOLVER reports the verdict on the same channel as the rect it produced", function()
		local solver = require("../src/layout/solver")
		local out = solver.solve(
			{
				kind = "vstack",
				id = "/S",
				children = {
					{
						kind = "text",
						id = "/S/B",
						text = "Edit item",
						compactText = "Ed",
						width = { type = "fixed", px = 60 },
					},
				},
			} :: any,
			{ w = 800, h = 400 }
		)
		expect(out.rects["/S/B"].compact).toBe(true)
	end)

	it("the verdict is RE-DECIDED, never latched — a re-solve that makes room restores the label", function()
		-- a node is measured repeatedly at different widths within one solve, and
		-- again on every later solve. A flag that could only latch true would keep
		-- a pencil on a button that has had room for its word since the last resize.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 60, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Button({ id = "B", label = "Edit item", compactLabel = "Ed", width = { type = "fill" } }),
				},
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/B").props.label).toBe("Ed")
		local createsBefore = controller.stats().creates
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
		controller.refresh()
		expect(adapter.node("/S/B").props.label).toBe("Edit item")
		-- and it is a RE-SOLVE, not a rebuild: the button keeps its identity, which
		-- is exactly what a ViewThatFits wrapper could not have promised
		expect(controller.stats().creates).toBe(createsBefore)
		expect(controller.stats().removes).toBe(0)
		controller.dispose()
		root.dispose()
	end)

	it("a REMOUNTED button gets its verdict re-applied — the cache dies with the node", function()
		--[[ Found LIVE 2026-08-04, RascalRally production: the sponsor HUD's
			watch-cycle buttons painted "Previous racer" ellipsized to "…" — at
			EVERY preference — after a pose toggle, while a fresh mount painted the
			chevron correctly. `applyCompactLabel`'s minimal-write cache is keyed by
			PATH, and paths are REUSED across a structural remount (a `When` branch,
			a ForEach row): the re-created instance is born with its FULL label, and
			the surviving `true` said the swap was already applied, so the glyph was
			never written again. Every headless witness was green because every
			fixture mounted ONCE. The cache is now cleared in the same removal block
			every other per-path cache learned to die in (verifier finding V10's
			comment names the class). ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 60, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local shown = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.When({
						id = "R",
						condition = shown,
						thenView = function()
							return UI.Button({
								id = "B",
								label = "Edit item",
								compactLabel = "Ed",
								width = { type = "fill" },
							})
						end,
					}),
				},
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		local path = "/S/R/then/B"
		expect(adapter.node(path).props.label).toBe("Ed")
		-- the region leaves...
		shown:set(false)
		controller.refresh()
		expect(adapter.node(path) == nil).toBe(true)
		-- ...and returns: the SAME path, a NEW instance, the same verdict — and
		-- the drawn string must be the compact form again, not the born label
		shown:set(true)
		controller.refresh()
		expect(adapter.node(path).props.label).toBe("Ed")
		controller.dispose()
		root.dispose()
	end)

	it("a steady layout costs ZERO extra prop writes", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 60, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Button({ id = "B", label = "Edit item", compactLabel = "Ed", width = { type = "fill" } }),
				},
			})
		)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		adapter.takeOps()
		controller.refresh()
		local ops = adapter.takeOps()
		for _, op in ops do
			expect(string.find(op, ".label", 1, true) == nil).toBe(true)
		end
		controller.dispose()
		root.dispose()
	end)
end)

describe("compactLabel: the closed grammar", function()
	local function refused(compact: any): boolean
		return not (
			pcall(function()
				return UI.Button({ id = "B", label = "Edit item", compactLabel = compact })
			end)
		)
	end

	it("accepts the four legal spellings", function()
		expect(refused("Ed")).toBe(false)
		expect(refused({ text = "Ed" })).toBe(false)
		expect(refused({ icon = "edit" })).toBe(false)
		expect(refused({ image = "rbxassetid://1" })).toBe(false)
	end)

	it("refuses an unknown form — a value nothing validates is a UI that silently draws nothing", function()
		-- docs/lessons/enum-props-accept-any-string.md: this is the boundary, and
		-- there is no later one that would reject it.
		expect(refused({ glyph = "P" })).toBe(true)
		expect(refused({ pictur = "x" })).toBe(true)
	end)

	it("refuses TWO forms — that is two answers to one question", function()
		expect(refused({ text = "Ed", icon = "edit" })).toBe(true)
	end)

	it("refuses an empty table, an empty string and a non-string value", function()
		expect(refused({})).toBe(true)
		expect(refused("")).toBe(true)
		expect(refused({ text = "" })).toBe(true)
		expect(refused({ text = 4 })).toBe(true)
		expect(refused(7)).toBe(true)
	end)

	it("refuses whitespace in a compact string, naming the reason", function()
		expect(refused("Save it")).toBe(true)
		local ok, err = pcall(function()
			return UI.Button({ id = "B", label = "Save changes", compactLabel = "Save it" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "must be ONE word", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "legal break point", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an icon name the framework cannot resolve, listing the ones it knows", function()
		expect(refused({ icon = "pencil" })).toBe(true)
		local ok, err = pcall(function()
			return UI.Button({ id = "B", label = "Edit", compactLabel = { icon = "pencil" } })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "names no semantic icon", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "edit", 1, true) ~= nil).toBe(true)
		-- a namespaced name a package contributes is legal
		expect(refused({ icon = "ns:pencil" })).toBe(false)
	end)

	it("refuses a compact form on a CONTENT button, which draws no text to shorten", function()
		local ok, err = pcall(function()
			return UI.Button({
				id = "B",
				label = "Edit item",
				compactLabel = "Ed",
				children = { UI.Text({ id = "T", text = "hi" }) },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "CONTENT button", 1, true) ~= nil).toBe(true)
	end)

	it("is NOT reactive: a compact representation is what the control HAS", function()
		local core = customFactory.new()
		local ok = pcall(function()
			return UI.Button({ id = "B", label = "Edit item", compactLabel = core:signal("Ed") :: any })
		end)
		expect(ok).toBe(false)
	end)
end)

describe("compactLabel: the icon form degrades and the image form does not", function()
	it("an icon form draws the framework's ASCII glyph when no art resolves", function()
		-- the land-green property: nothing has to be uploaded for this to render.
		local tight = drawAt({ label = "Edit", compactLabel = { icon = "edit" } }, 30)
		expect(tight.label).toBe("/")
	end)

	it("...and that glyph is ASCII-safe, so it cannot be tofu under any font", function()
		expect(themes.isSafeGlyph(themes.iconGlyph("edit"))).toBe(true)
	end)

	it("an IMAGE form draws nothing textual — the picture IS the content", function()
		local tight = drawAt({ label = "Edit item", compactLabel = { image = "rbxassetid://1" } }, 30)
		expect(tight.label).toBe("")
	end)

	it("every framework icon name has BOTH an ASCII glyph and a standard-art entry", function()
		-- the set is only usable if the two halves agree: art to draw, and a
		-- character to fall back to when it has not resolved.
		for name in themes.ICON_FALLBACK_GLYPHS :: any do
			expect((standard_icons.ART :: any)[name] ~= nil).toBe(true)
		end
		for name in standard_icons.ART :: any do
			expect(themes.iconGlyph(name) ~= nil).toBe(true)
		end
	end)

	it("standard_icons.resolve() answers nil for unknown names, art for uploaded ones", function()
		-- pins resolve()'s two cases directly, below the control-level glyph
		-- fallback tested above: a name the set does not know at all (typo)
		-- is nil -- what sends the caller (package.resolveIcon) on to the
		-- ASCII glyph -- and a name with a content id resolves to its art.
		-- `trash`/`flag` shipped pre-upload (contentId = nil, ASCII floor
		-- "U"/"P") and were uploaded 2026-08-12; this test pinned the nil
		-- state then and pins the uploaded state now. The un-uploaded case
		-- stays covered by the synthetic-entry contract: resolve() reads
		-- contentId and nothing else, so a nil contentId IS the typo case's
		-- same nil return path (assets/icons/provenance.md).
		expect(standard_icons.resolve("not.a.real.icon.name")).toBeNil()
		local trashEntry = (standard_icons.ART :: any)["trash"]
		expect(trashEntry ~= nil).toBe(true)
		expect(trashEntry.contentId).toBe("rbxassetid://84398508341623")
		expect(standard_icons.resolve("trash").contentId).toBe("rbxassetid://84398508341623")
		expect(standard_icons.resolve("flag").contentId).toBe("rbxassetid://109067109704366")
		-- under THIS harness (no themeMetrics -> flat theme) the icon form
		-- still draws the ASCII floor even for uploaded art -- exactly as the
		-- "edit" test above draws "/" although edit has carried a content id
		-- since 2026-07-27. The glyph floor staying reachable is itself the
		-- pinned property; the art path is the package sweep's business.
		local tight = drawAt({ label = "Delete", compactLabel = { icon = "trash" } }, 30)
		-- the trash MARK, `\_/` -- an open tapered container. It was the letter
		-- "U" until the device bug round 2026-08-12 (finding A4) photographed it
		-- reading as exactly that letter on a real phone under Pixel Quest; see
		-- package.ICON_FALLBACK_GLYPHS for the rule the table now keeps.
		expect(tight.label).toBe("\\_/")
	end)
end)

describe("compactLabel: measured under every reference package", function()
	-- Studio Neutral reserves nothing for chrome, so a button measured only there
	-- has slack no shipped package gives it. Every claim above is re-driven here
	-- against the packages the director actually looks at.
	it("the ladder holds under the flat theme and all eight shipped packages", function()
		local function ladder(pkg: any?)
			-- 400px is comfortably wider than "Edit item" under every package's
			-- typography and chrome insets; 44px is narrower than it under all of them
			expect(drawAt({ label = "Edit item", compactLabel = "Ed" }, 400, pkg).label).toBe("Edit item")
			expect(drawAt({ label = "Edit item", compactLabel = "Ed" }, 44, pkg).label).toBe("Ed")
		end
		ladder(nil)
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(LuauUI.themes)
			ladder(pkg)
		end
	end)

	it("the compact form never costs a second line, under any package", function()
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(LuauUI.themes)
			local roomy = drawAt({ label = "Edit item", compactLabel = "Ed" }, 400, pkg)
			local tight = drawAt({ label = "Edit item", compactLabel = "Ed" }, 44, pkg)
			expect(tight.h).toBe(roomy.h)
		end
	end)
end)

describe("compactLabel: the table's Edit/Done toggle, its first consumer", function()
	-- THE TRAP THIS CONSUMER CARRIES. `table.luau` matches its own toggle by a
	-- `$`-anchored path suffix in TWO places -- its activate router and its
	-- focus-group builder -- and moving or wrapping the node silently breaks both:
	-- the button renders, focuses, and does nothing. That cost a round on
	-- 2026-07-27. `compactLabel` is a PROP on the existing node and moves nothing,
	-- and this is the test that says so out loud.
	local table_control = require("../src/controls/table")

	local TOGGLE = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"

	local function tableWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local rows = core:signal({ { id = "r1", name = "Ada", laps = 3 } })
		local tbl = table_control.build(LuauUI, core, {
			id = "Racers",
			columns = { { id = "name", title = "Racer", width = { type = "fill", weight = 1 } } },
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return UI.Text({ id = "Value", text = item.name, textSize = 16 })
			end,
			rowHeight = 40,
			header = true,
			reorderable = true,
			env = env,
		})
		pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
		pres.refresh()
		env:set("preferredInput", "Touch")
		pres.refresh()
		return core, adapter, pres, tbl
	end

	it("the toggle still sits at the path both of the table's own matchers anchor on", function()
		local _, adapter = tableWorld()
		expect(adapter.node(TOGGLE) ~= nil).toBe(true)
	end)

	it("its ACTIVATE router still matches — the button is not merely rendering", function()
		local _, adapter, pres, tbl = tableWorld()
		expect(adapter.node(TOGGLE).props.label).toBe("Edit")
		expect(tbl.api.handleActivate(TOGGLE, nil)).toBe(true)
		pres.refresh()
		expect(adapter.node(TOGGLE).props.label).toBe("Done")
	end)

	it("with room, it still says its word — the shipped look does not move", function()
		local _, adapter = tableWorld()
		expect(adapter.node(TOGGLE).props.label).toBe("Edit")
	end)

	it("and it declares a compact form, so it can never fall back to an ellipsis", function()
		expect(rendererLib.compactForm({ compactLabel = { icon = "edit" } }).kind).toBe("icon")
		local src = require("@lune/fs").readFile("src/controls/table.luau")
		expect(string.find(src, 'compactLabel = { icon = "edit" }', 1, true) ~= nil).toBe(true)
	end)
end)
