--!strict
-- RowActions control spec (Task 3: composite skeleton, static reveal). Mirrors
-- tests/chip.spec.luau's presenterWorld/renderWorld idioms. This file proves:
--   1. the spec/ActionSpec authoring contract (unknown keys, empty-list refusal);
--   2. the true inert passthrough when neither edge has actions;
--   3. the lazy tray structure (Action:<id> buttons, destructive role);
--   4. long-label survival at the theme's buttonMinWidth floor;
--   5. the static _open/_close/dump seam (Tasks 4-6 build motion on it);
--   6. registry neutrality on dispose;
-- and, because the tray buttons are reached through the composite's OWN
-- input contribution (contribution.attach + a routed handleActivate — see
-- src/controls/row_actions.luau), the four-input REACHABILITY and PARADIGM
-- proofs the extension checker requires of every interactive control
-- (ui_todo §0; UI-PARADIGM-001), exercised through the standard tap/
-- deviceKey device-true paths, same as tests/chip.spec.luau.
--
-- RowActions owns NO in-flight gesture state as of this task (no pointer
-- handling — Step 3 of the plan): hotSwitch = false in the registry row is
-- accurate for what ships here, and Tasks 5-8 (drag/touch/keyboard-adjust)
-- must revisit it once a mid-gesture class flip has something to carry.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local fake_target = require("../tests/lib/fake_target")
local lt = require("./lib/large_text")

-- renderer-level modules for the headless mount->attach->render axis (hover,
-- ten-foot focus), mirroring tests/chip.spec.luau's renderWorld
local mountLib = require("../src/mount")
local renderer = require("../src/render/renderer")
-- the solver's OWN headless text measurement (src/layout/text_metrics), used
-- to independently verify the "no clipping" claim against the button's REAL
-- font/size (read off controller.textAt), not a guessed one.
local text_metrics = require("../src/layout/text_metrics")
-- Task 9: independently derives what a `shape = "circle"` + `icon` Button
-- actually PAINTS (`renderer.drawnButtonText`: the icon's ASCII glyph, not the
-- semantic `label` — see `tests/button_shape.spec.luau`'s own "label survives
-- past icon" case, which is about the BLUEPRINT prop, not the rendered one).
local theme_package = require("../src/themes/package")
-- the SAME resolver the control itself uses, so a theme-metric leg asserts the
-- theme's number rather than a literal that silently drifts from it
local themeSnapshot = require("../src/themes/snapshot")

local ROW = "/S/Row"
local TRAILING_TRAY = ROW .. "/TrayTrailingWhen/then/TrayTrailing"
local DELETE_PATH = TRAILING_TRAY .. "/Action:delete"
local LEADING_TRAY = ROW .. "/TrayLeadingWhen/then/TrayLeading"
local EDIT_AFFORDANCE_PATH = ROW .. "/EditAffordanceWhen/then/EditAffordance"

-- a REALISTIC row height (a List/Table row is never text-line-tall) — the
-- tray Buttons fill it, so a too-short fixture would blame the composite for
-- what is really an unrealistic caller-provided row box.
local function content(id: string?)
	return Facet.UI.Text({ id = id or "Body", text = "Row content", height = { type = "fixed", px = 48 } })
end

-- Task 4: `_open`/`_close` now ANIMATE through a presenter's real motion
-- clock (delivered via the new `bindMotion` contribution seam), so a test
-- that wants the FULLY REVEALED/CLOSED state after calling them must step
-- frames first — `pres.tick(dt)` takes an EXPLICIT dt (src/present/
-- presenter.luau tickBody: "the headless suite passes a scripted dt"), so
-- this is deterministic regardless of wall-clock time; no scripted clock
-- injection needed (contrast tests/drag_public.spec.luau's `Facet.motion.
-- newClock`, which exists to override a DIFFERENT clock — the drag
-- registry's, wired through `controller.setDragCollaborators` — not the
-- presenter's own `self.motionClock` this composite now rides). 90 frames
-- (1.5s) comfortably settles an "object"-class spring (response 0.28s).
local FRAME = 1 / 60
local SETTLE_FRAMES = 90
local function settle(pres: any, frames: number?)
	for _ = 1, frames or SETTLE_FRAMES do
		pres.tick(FRAME)
	end
end

-- presenter harness: the four-input auto-composition path (chip.spec's house
-- style). `build` receives `core` and returns the row_actions instance.
local function presenterWorld(build: (core: any) -> any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local ra = build(core)
	local screen = Facet.UI.Screen({ id = "S", children = { ra.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	return { core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
end

-- a world whose trailing tray is ALREADY revealed before the first present —
-- the honest way to reach a lazily-mounted tray button's device-true story
-- without this spec depending on Tasks 5-8's drag/touch gesture machinery
-- (hard rule: prove reachability through the standard Button path, or stop).
local function openTrailingWorld(actions: { any }?)
	local fired: { string } = {}
	local w = presenterWorld(function(core)
		return row_actions.build(Facet, core, {
			id = "Row",
			content = content(),
			trailing = actions or {
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
	end)
	-- ^ presenterWorld already called present()+refresh() with the tray
	-- CLOSED; open it now and refresh again so the buttons exist to focus.
	w.ra._open("trailing")
	w.pres.refresh()
	return {
		core = w.core,
		env = w.env,
		system = w.system,
		adapter = w.adapter,
		pres = w.pres,
		ra = w.ra,
		fired = fired,
	}
end

-- renderer harness: mount a row_actions (trailing tray pre-opened) and attach
-- the renderer directly, mirroring chip.spec.luau's renderWorld.
local function renderWorldOpen(envSetup: ((any) -> ())?, actions: { any }?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if envSetup then
		envSetup(env)
	end
	local ra = row_actions.build(Facet, core, {
		id = "Row",
		content = content(),
		trailing = actions or { { id = "delete", label = "Delete", onAction = function() end } },
	})
	ra._open("trailing")
	local root = mountLib.mount(core, Facet.UI.Screen({ id = "S", children = { ra.blueprint } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller, ra = ra }
end

describe("RowActions control", function()
	-- 1. AUTHORING CONTRACT (constitution §4; ARCH-1) ------------------------
	it("validates unknown spec keys", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return row_actions.build(Facet, core, { contnet = content() } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "you mean", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an empty action list", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return row_actions.build(Facet, core, { content = content(), leading = {} })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "nil", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an unknown ActionSpec key", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return row_actions.build(Facet, core, {
				content = content(),
				trailing = { { label = "Delete", onAction = function() end, oaction = function() end } :: any },
			})
		end)
		expect(ok).toBe(false)
		-- "onAction" is a 2-edit neighbor of "oaction" (drop 'n', case-fold 'A')
		expect(string.find(tostring(err), "you mean", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an ActionSpec with an unknown role", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return row_actions.build(Facet, core, {
				content = content(),
				trailing = { { label = "Delete", role = "scary", onAction = function() end } :: any },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "normal, destructive", 1, true) ~= nil).toBe(true)
	end)

	-- REDTEAM ITEM 16 (LOW; director ruling — constitution strictness).
	-- `id` defaults to the literal "RowActions" when absent — a standalone
	-- caller sharing ONE coordinator across several rows (a VStack/
	-- ScrollView list built by hand, not through Table, which always
	-- supplies its own unique `"RowActions-" .. rowKey`) without an
	-- explicit `id` per row would have every one of them collide on that
	-- same literal, corrupting the presenter's own path-keyed bookkeeping
	-- the instant a second such row mounts. Refused loudly at build time.
	it("rejects a coordinator-sharing row with no explicit id", function()
		local core = Facet.newCore()
		local coordinator = row_actions.newCoordinator(core)
		local ok, err = pcall(function()
			return row_actions.build(Facet, core, {
				content = content(),
				trailing = { { label = "Delete", onAction = function() end } },
				coordinator = coordinator,
				-- no `id` — the mistake this validation exists to catch
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unique ids", 1, true) ~= nil).toBe(true)
	end)

	it("a coordinator-sharing row WITH an explicit id builds normally", function()
		local core = Facet.newCore()
		local coordinator = row_actions.newCoordinator(core)
		local ok = pcall(function()
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content(),
				trailing = { { label = "Delete", onAction = function() end } },
				coordinator = coordinator,
			})
		end)
		expect(ok).toBe(true)
	end)

	-- 2. INERT PASSTHROUGH (perf directive) -----------------------------------
	it("is an inert passthrough with no actions", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, { id = "Row", content = content("Body") })
		end)
		expect(w.adapter.node("/S/Body") ~= nil).toBe(true) -- content mounted, unwrapped
		expect(w.adapter.node(ROW) == nil).toBe(true) -- no RowActions wrapper node at all
		expect(w.ra.dump().phase).toBe("closed")
		expect(w.ra._isOpen()).toBe(false)
	end)

	-- 3. LAZY TRAY STRUCTURE ---------------------------------------------------
	it("mounts trailing tray buttons with ids Action:<id> only once revealed", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		-- CLOSED: zero tray GuiObjects (the perf directive's lazy mount)
		expect(w.adapter.node(DELETE_PATH) == nil).toBe(true)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.adapter.node(DELETE_PATH) ~= nil).toBe(true)
		expect(w.adapter.node(DELETE_PATH).props.label).toBe("Delete")
	end)

	it("destructive action paints danger tokens; normal action paints the default role", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{ id = "delete", label = "Delete", role = "destructive", onAction = function() end },
					{ id = "flag", label = "Flag", onAction = function() end },
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:delete").props.role).toBe("destructive")
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:flag").props.role).toBe("default")
	end)

	-- 4. LOCALIZATION SAFETY ----------------------------------------------------
	-- A tray Button with no children solves through the SOLVER'S OWN text-
	-- measure branch (src/layout/solver.luau: `class == "Button"` with no
	-- children -> `kind = "text"`), so `controller.textAt(path)` publishes the
	-- SAME per-text facts tests/text_audit.spec.luau reads for a plain UI.Text
	-- (font, size, lines, naturalLines, truncated) — the real measured-
	-- against-the-real-box facts, not a guess.
	--
	-- A prior version of this test asserted `rect.w >= buttonMinWidth`
	-- (hardcoded floor, true even for a button PINNED at exactly 64px) and
	-- `props.label` equality (always true — this control never mutates the
	-- string); neither could ever fail. Code review (mutating the tray
	-- button's width to `{ type = "fixed", px = 64 }`) caught that the old
	-- test kept passing.
	--
	-- Investigating that mutation live (a throwaway headless repro) found
	-- `textFacts.truncated` can NEVER be true here regardless: `lt.PSEUDO`
	-- (like every string `pseudoLocalize` produces) is always two "words" —
	-- the source text plus a space-separated dot-padding suffix
	-- (tests/fixtures/a11y_l10n_fixtures.luau `pseudoLocalize`) — so
	-- `isSingleWord` (src/render/renderer.luau) is always false for it, the
	-- Button never takes the single-line/clip path, and a too-narrow box
	-- makes it WRAP instead (measured live: the 64px-pinned mutation wraps
	-- the label to 5 lines and balloons the row from 48px to 108px tall,
	-- `truncated` stays `false` throughout — wrapping, unlike a line-capped
	-- ellipsis, is never "truncated"). So the fact that actually distinguishes
	-- "grew wide enough" from "clipped/reflowed" is `lines == 1`: this
	-- composite's contract (`buttonMinWidth` is a floor a button WIDENS past,
	-- Task 2/docs/reference/api.md `newRowActions`) promises a tray action
	-- reads as ONE line, never wraps — the platform pattern this control follows
	-- never reflows an action label. Backed by an independent measurement
	-- (the solver's own `text_metrics.measure`, at the button's REAL font/
	-- size) proving the box is wide enough for the natural one-line width.
	it("labels survive 1.4x pseudo-loc without clipping (button never narrower than buttonMinWidth)", function()
		-- ICON-FIRST (director device round 2026-08-12) changed what this test can
		-- ask of the ICON row. An action that declares an icon no longer draws
		-- its label at any width — the icon IS its representation — so the
		-- localization-safety subject is the LABEL-ONLY action, which is exactly
		-- where the risk lives: a German-class expansion can only clip a word
		-- that is drawn. The icon row is still built alongside it, and asserted
		-- against the NEW contract below (glyph drawn, floor honoured, one line).
		local function build(icon: string?)
			return presenterWorld(function(core)
				return row_actions.build(Facet, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = lt.PSEUDO, icon = icon, onAction = function() end } },
				})
			end)
		end
		local ref = build(nil)
		ref.ra._open("trailing")
		ref.pres.refresh()
		settle(ref.pres)
		ref.pres.refresh()
		local node = ref.adapter.node(DELETE_PATH)
		expect(node ~= nil).toBe(true)
		expect(node.props.label).toBe(lt.PSEUDO) -- a label-only action draws its word
		expect(node.rect.w >= 64).toBe(true) -- the theme's buttonMinWidth floor (Task 2)

		local facts = ref.handle.controller.textAt(DELETE_PATH)
		expect(facts ~= nil).toBe(true)
		expect(facts.truncated).toBe(false)
		expect(facts.lines).toBe(1) -- never wraps: the button widens instead of reflowing

		-- independent proof, not just the solver's own verdict: the box the
		-- button actually solved to is wide enough for the label's real
		-- natural (single-line) width at its real font/size, plus its padding.
		local natural = text_metrics.measure(lt.PSEUDO, facts.font, facts.size, math.huge)
		local buttonPad = 8 -- controls.rowActions.buttonPad (Task 2 default = style.space.s)
		expect(node.rect.w >= natural.width + 2 * buttonPad).toBe(true)

		-- THE ICON ROW — the l10n ARGUMENT for icon-first: the same pseudo-localized
		-- label, now neither drawn NOR reserved for.
		--
		-- WHICH LEVER EACH LEG BITES, stated because the two are separable and one
		-- of them cannot be tested here. Icon-first is two changes: `prefer` (what
		-- the button DRAWS) and `deriveNaturals` measuring the glyph (what the
		-- button is SIZED for). A pseudo-localized label is ~9x the glyph, so it
		-- fails the fit test at any sane plate width — meaning the drawn form is
		-- "U" with or without `prefer`, and no leg here can bite the `prefer`
		-- lever. That bite lives in "an icon action wears its icon at EVERY width",
		-- whose short-label ("Do") leg is specifically built to fit and therefore
		-- to distinguish preferred from merely-did-not-fit.
		--
		-- What these legs DO bite is the sizing lever: measure `action.label`
		-- instead of the glyph and the plate balloons to the pseudo width, which is
		-- exactly the clipping-risk surface this test is named for.
		local w = build("trash")
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local iconNode = w.adapter.node(DELETE_PATH)
		expect(iconNode.props.label).toBe("\\_/") -- standard_icons trash ASCII floor, at the SETTLED width
		-- the floor comes from the THEME, not a literal — the same reason the
		-- label-only legs above measure rather than pin a pixel number.
		local minWidth = themeSnapshot.resolveNumber(themeSnapshot.neutral(), "controls.rowActions.buttonMinWidth")
		expect(iconNode.rect.w).toBe(minWidth)
		-- ...and, the point of the whole leg: the expansion bought no width at all.
		expect(iconNode.rect.w < node.rect.w).toBe(true)
		local iconFacts = w.handle.controller.textAt(DELETE_PATH)
		expect(iconFacts.truncated).toBe(false)
		expect(iconFacts.lines).toBe(1)
	end)

	-- 5. THE REVEAL SEAM (Task 4 builds spring motion on this) -----------------
	it("_open slides content by tray width; _close returns it; dump reflects openEdge", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra.dump().openEdge).toBe(nil)

		-- `openEdge`/`phase`/`_isOpen()` flip INSTANTLY (Task 4 never delayed
		-- those — only the pixel `offset` itself animates); the spring needs
		-- settling before `offset` reaches the tray width.
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.ra.dump().openEdge).toBe("trailing")
		expect(w.ra.dump().phase).toBe("open")
		expect(w.ra._isOpen()).toBe(true)
		settle(w.pres)
		w.pres.refresh()
		local trayRect = w.adapter.node(TRAILING_TRAY).rect
		expect(w.ra.dump().offset).toBeCloseTo(-trayRect.w, 0.5)

		w.ra._close()
		expect(w.ra.dump().openEdge).toBe(nil)
		expect(w.ra.dump().phase).toBe("closed")
		expect(w.ra._isOpen()).toBe(false)
		settle(w.pres)
		expect(w.ra.dump().offset).toBe(0) -- settle SNAPS exactly onto the target
	end)

	-- 5b. SPRING MOTION (Task 4) ------------------------------------------------
	it("_open animates offset toward tray width over stepped frames", function()
		local function build()
			return presenterWorld(function(core)
				return row_actions.build(Facet, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				})
			end)
		end
		-- learn the settled tray width from a throwaway world (same spec, so
		-- the same measured width), rather than reaching into internals
		local ref = build()
		ref.ra._open("trailing")
		ref.pres.refresh()
		settle(ref.pres)
		local trayWidth = -ref.ra.dump().offset
		expect(trayWidth > 0).toBe(true)

		local w = build()
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.ra.dump().offset).toBe(0) -- nothing has animated yet

		w.pres.tick(FRAME)
		local afterOne = w.ra.dump().offset
		expect(afterOne < 0).toBe(true) -- moving toward the (negative) trailing target
		expect(afterOne > -trayWidth).toBe(true) -- not there yet

		for _ = 1, 59 do
			w.pres.tick(FRAME)
		end
		expect(-w.ra.dump().offset).toBeCloseTo(trayWidth, 0.5) -- 60 frames: settled
	end)

	it("buttons grow proportionally with offset", function()
		local function build()
			return presenterWorld(function(core)
				return row_actions.build(Facet, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				})
			end)
		end
		local ref = build()
		ref.ra._open("trailing")
		ref.pres.refresh()
		settle(ref.pres)
		ref.pres.refresh()
		local fullWidth = ref.adapter.node(DELETE_PATH).rect.w
		local trayWidth = -ref.ra.dump().offset
		expect(fullWidth > 0).toBe(true)

		local w = build()
		w.ra._open("trailing")
		w.pres.refresh()
		-- a handful of frames in: neither at rest nor fully revealed
		for _ = 1, 8 do
			w.pres.tick(FRAME)
		end
		w.pres.refresh()
		local frac = math.abs(w.ra.dump().offset) / trayWidth
		expect(frac > 0.05 and frac < 0.95).toBe(true) -- genuinely mid-flight
		local midWidth = w.adapter.node(DELETE_PATH).rect.w
		expect(midWidth).toBeCloseTo(fullWidth * frac, 1) -- SAME observed value, no second spring
	end)

	-- ICON-FIRST (director device round 2026-08-12; api.md ActionSpec.icon). An
	-- action that declares an icon wears it at EVERY width — settled and
	-- mid-swipe alike — and `label` stays the semantic name (announced, and the
	-- drawn text of the presentModal menu row for the same action). This used to
	-- assert the opposite (full label settled, glyph mid-swipe): the compact
	-- ladder's own per-button fit test, which cannot make a tray agree with
	-- itself — at a width that fits "Flag" and not "Delete", one plate wore a
	-- glyph and its neighbour a word. `trash` has no uploaded content id yet
	-- (assets/icons/provenance.md "Pending upload"), so the icon form is today's
	-- ASCII floor, `U` — proving the fallback renders through a real caller,
	-- live, not just in standard_icons' own unit tests.
	it("an icon action wears its icon at EVERY width — settled and mid-swipe (icon-first)", function()
		local function build()
			return presenterWorld(function(core)
				return row_actions.build(Facet, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = "Delete", icon = "trash", onAction = function() end } },
				})
			end)
		end

		local settled = build()
		settled.ra._open("trailing")
		settled.pres.refresh()
		settle(settled.pres)
		settled.pres.refresh()
		-- standard_icons trash fallback (package.luau ICON_FALLBACK_GLYPHS)
		expect(settled.adapter.node(DELETE_PATH).props.label).toBe("\\_/")

		local w = build()
		w.ra._open("trailing")
		w.pres.refresh()
		for _ = 1, 8 do
			w.pres.tick(FRAME)
		end
		w.pres.refresh()
		expect(w.adapter.node(DELETE_PATH).props.label).toBe("\\_/") -- and the same mark mid-flight: no swap to chase

		-- ...and a label SHORT enough to fit the settled plate with room to spare
		-- still wears the icon. Without this the case is green by accident: the
		-- old ladder degrades a long word at this width too, so only a label that
		-- FITS can tell "preferred" apart from "did not fit".
		local short = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Do", icon = "trash", onAction = function() end } },
			})
		end)
		short.ra._open("trailing")
		short.pres.refresh()
		settle(short.pres)
		short.pres.refresh()
		local shortNode = short.adapter.node(DELETE_PATH)
		local shortFacts = short.handle.controller.textAt(DELETE_PATH)
		-- the plate really does have room for the word it is not drawing
		local wordWidth = text_metrics.measure("Do", shortFacts.font, shortFacts.size, math.huge).width
		expect(shortNode.rect.w - 16 > wordWidth).toBe(true) -- 16 = 2 * buttonPad
		expect(shortNode.props.label).toBe("\\_/")
	end)

	-- ...and the OTHER half of the ruling: an action with no icon has nothing to
	-- prefer, so it keeps its word at every width. Without this, "icon-first"
	-- could be implemented as "never draw a label" and the suite would not notice
	-- (the scenario's own "Mark Read" is exactly this case).
	it("a label-only action keeps its word — icon-first is a default, not a ban on text", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		expect(w.adapter.node(DELETE_PATH).props.label).toBe("Delete")
	end)

	it("reduced motion snaps the reveal in one frame", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("reducedMotion", true) -- derives env:get("motionPolicy") == "reduced"
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local ra = row_actions.build(Facet, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { ra.blueprint } }))
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		pres.tick(FRAME) -- one step: decorative motion under reduced policy snaps
		pres.refresh()
		local trayRect = adapter.node(TRAILING_TRAY).rect
		expect(ra.dump().offset).toBe(-trayRect.w)
	end)

	it("dispose mid-flight leaks nothing", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(Facet, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		local screen = Facet.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		for _ = 1, 3 do
			pres.tick(FRAME)
		end
		local mid = ra.dump().offset
		expect(mid < 0).toBe(true) -- in flight: neither 0 nor settled

		pres.dismiss(handle)
		ra.dispose()

		for _ = 1, 10 do
			pres.tick(FRAME)
		end
		expect(ra.dump().offset).toBe(mid) -- disposed: further steps change nothing

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	it("_settleTo retargets the spring at the verdict (Task 5 wires the gesture that produces one)", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		local trayWidth = -w.ra.dump().offset

		w.ra._settleTo({ target = 0, edge = nil, commit = false })
		settle(w.pres)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra.dump().openEdge).toBe(nil)

		w.ra._settleTo({ target = -trayWidth, edge = "trailing", commit = false })
		settle(w.pres)
		expect(w.ra.dump().offset).toBe(-trayWidth)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	-- code review (2026-08-10): the first version of this reveal froze each
	-- button's natural width the first time it measured it, which fixed the
	-- feedback-loop bug but also froze against a LEGITIMATE live environment
	-- change — the reviewer proved it empirically (preferredTextSize after
	-- first open never moved the reserved width, even across close/reopen).
	-- The fix derives natural width from an UNCONSTRAINED text measurement
	-- (never solved geometry) every sync instead, so it re-derives live. This
	-- is that proof, mirroring tests/large_text_hot_swap.spec.luau's own
	-- "live preference swing" idiom (`env:set("preferredTextOffset", ...)`
	-- then `pres.refresh()` on an ALREADY-presented, already-open screen).
	it("tray button width re-derives when preferredTextSize changes (not frozen)", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local ra = row_actions.build(Facet, core, {
			id = "Row",
			content = content("Body"),
			env = env,
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { ra.blueprint } }))
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		settle(pres)
		pres.refresh()
		local before = adapter.node(DELETE_PATH).rect.w
		expect(before >= 64).toBe(true) -- the theme's buttonMinWidth floor (Task 2)

		-- THE LIVE SWING, on the SAME open row (no close/reopen) — the exact
		-- shape the reviewer's repro used ("across close/reopen" was the other
		-- half of the same finding; covered implicitly since this signal is
		-- never reset between opens either).
		env:set("preferredTextOffset", lt.LARGEST)
		pres.refresh()
		settle(pres)
		pres.refresh()
		local after = adapter.node(DELETE_PATH).rect.w
		expect(after > before).toBe(true) -- re-derived: bigger reserved text -> wider button
		expect(after >= 64).toBe(true) -- never narrower than the floor

		local facts = handle.controller.textAt(DELETE_PATH)
		expect(facts ~= nil).toBe(true)
		expect(facts.lines).toBe(1) -- still one line, never wraps (Task 3's own contract)
	end)

	it("_open on an edge with no actions is a no-op", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		w.ra._open("leading") -- no leading actions declared
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)

	-- 6. DISPOSAL / REGISTRY NEUTRALITY ------------------------------------------
	it("dispose unmounts and releases the scope", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(Facet, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		local screen = Facet.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		adapter.tap(DELETE_PATH)

		pres.dismiss(handle)
		ra.dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	-- 7. FOUR-INPUT REACHABILITY (ui_todo §0) — device-true, all four classes.
	-- Proven through the standard UI.Button path a revealed tray action IS
	-- (hard rule: honest reachability through what this task actually built,
	-- not a fabricated proof of the swipe gesture itself — that is Tasks 5-8).
	it("RowActions pointer: a tap on a revealed tray action activates it (device-true)", function()
		local w = openTrailingWorld()
		expect(#w.fired).toBe(0)
		w.adapter.tap(DELETE_PATH)
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions touch: a touch tap on a revealed tray action activates it (device-true)", function()
		local w = openTrailingWorld()
		w.adapter.tap(DELETE_PATH, { source = "pointer", pointer = "touch" })
		expect(w.fired[1]).toBe("delete")
	end)

	-- REDTEAM ITEM 3 (MAJOR): a direct tap/Activate on a revealed (non-swipe,
	-- non-menu) tray action used to call `onAction` bare — an uncaught throw
	-- escaped straight through the presenter's own Activate dispatch — and
	-- never closed the tray afterward even on success, leaving a fired
	-- action's tray stranded open.
	it("a throwing tray action is contained (not a bare call) and still closes the tray", function()
		local calls = 0
		local w = openTrailingWorld({
			{
				id = "boom",
				label = "Boom",
				onAction = function()
					calls += 1
					error("kaboom")
				end,
			},
		})
		expect(w.ra._isOpen()).toBe(true)
		local ok = pcall(function()
			w.adapter.tap(TRAILING_TRAY .. "/Action:boom")
		end)
		expect(ok).toBe(true) -- the throw never escaped Activate dispatch
		expect(calls).toBe(1)
		expect(w.ra._isOpen()).toBe(false) -- closed even though the callback threw
	end)

	it("a successful (non-destructive) tray action fires exactly once and closes the tray", function()
		local w = openTrailingWorld()
		expect(w.ra._isOpen()).toBe(true)
		w.adapter.tap(DELETE_PATH)
		expect(w.fired).toEqual({ "delete" })
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("RowActions keyboard: focus + Return activates a revealed tray action", function()
		local w = openTrailingWorld()
		expect(w.pres.focus.focused:get()).toBe(DELETE_PATH)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions gamepad: focus + ButtonA activates a revealed tray action", function()
		local w = openTrailingWorld()
		expect(w.pres.focus.focused:get()).toBe(DELETE_PATH)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.fired[1]).toBe("delete")
	end)

	-- 8. PARADIGM AXIS (UI-PARADIGM-001) — the STRUCTURAL IDIOM per class. Every
	-- tray action IS a standard UI.Button, so it inherits the Button contract's
	-- own affordances; these cases prove the composite does not defeat them.
	it("RowActions pointer affordance: the pointer structural idiom (hover on a revealed tray action)", function()
		local w = renderWorldOpen(function(env)
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			env:set("preferredInput", "KeyboardAndMouse")
		end)
		expect(w.adapter.node(DELETE_PATH).hoverEnabled).toBe(true)
		w.adapter.hover(DELETE_PATH)
		expect(w.adapter.node(DELETE_PATH).hovered).toBe(true)
		w.adapter.unhover(DELETE_PATH)
		expect(w.adapter.node(DELETE_PATH).hovered).toBe(false)
	end)

	it("RowActions touch affordance: the touch structural idiom (44px floor on a revealed tray action)", function()
		local w = renderWorldOpen(function(env)
			env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
			env:set("preferredInput", "Touch")
		end)
		expect(w.adapter.node(DELETE_PATH).rect.h >= 44).toBe(true)
	end)

	it("RowActions keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate)", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local fired: { string } = {}
		local ra = row_actions.build(Facet, core, {
			id = "Row",
			content = content("Body"),
			trailing = {
				{
					id = "flag",
					label = "Flag",
					onAction = function()
						table.insert(fired, "flag")
					end,
				},
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
		ra._open("trailing")
		local screen = Facet.UI.Screen({ id = "S", children = { ra.blueprint } })
		pres.present(screen)
		pres.refresh()
		local flagPath = TRAILING_TRAY .. "/Action:flag"
		local deletePath = TRAILING_TRAY .. "/Action:delete"
		expect(pres.focus.focused:get()).toBe(flagPath) -- Navigate order: leftmost tray button first
		expect(adapter.node(flagPath).focused).toBe(true)
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		expect(pres.focus.focused:get()).toBe(deletePath) -- Navigate moved the ring
		expect(adapter.node(deletePath).focused).toBe(true)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(fired[1]).toBe("delete") -- Activate hit the focused action only
	end)

	it(
		"RowActions gamepad affordance: the gamepad structural idiom (ten-foot focus on a revealed tray action)",
		function()
			local big = renderWorldOpen(function(env)
				env:set("displaySize", "Large")
			end)
			big.controller.setFocusPath(DELETE_PATH)
			local near = renderWorldOpen(function(env)
				env:set("displaySize", "Medium")
			end)
			near.controller.setFocusPath(DELETE_PATH)
			expect(big.adapter.node(DELETE_PATH).focusProfile).toBe("ten-foot")
			expect(near.adapter.node(DELETE_PATH).focusProfile).toBe("near")
		end
	)

	-- 9. TASK 9: EDIT-MODE DELETE AFFORDANCE (leading minus) --------------
	it("rejects an editing value that is not a Readable", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return row_actions.build(Facet, core, {
				content = content(),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = true :: any,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Readable", 1, true) ~= nil).toBe(true)
	end)

	it("the minus is absent while not editing", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(false)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = editing,
			})
		end)
		expect(w.adapter.node(EDIT_AFFORDANCE_PATH) == nil).toBe(true)
	end)

	it("the minus is absent when the row has no destructive action, even while editing", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "flag", label = "Flag", onAction = function() end } }, -- normal, not destructive
				editing = core:signal(true),
			})
		end)
		expect(w.adapter.node(EDIT_AFFORDANCE_PATH) == nil).toBe(true)
	end)

	it("the minus is absent when the caller never wires `editing` (nil, not false)", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				-- no `editing` key at all
			})
		end)
		expect(w.adapter.node(EDIT_AFFORDANCE_PATH) == nil).toBe(true)
		-- structural, not just closed: an uninvolved consumer pays NOTHING for
		-- this task — no `EditAffordanceWhen` node exists at all (contrast a
		-- wired-but-not-editing row, which mounts one closed `UI.When` Frame;
		-- see the instance-count case below).
		expect(w.adapter.node(ROW .. "/EditAffordanceWhen") == nil).toBe(true)
	end)

	-- RE-DECIDED 2026-08-13 (game-director ruling, round 3 item C), NOT
	-- re-baselined. This case and the leading-only one below previously
	-- asserted the OPPOSITE — that the minus reveals the tray and fires
	-- nothing — and they asserted it as CORRECT, citing "the platform pattern".
	--
	-- Two things changed the ruling. (1) The device report: a player in edit
	-- mode taps the minus and expects the row to go. (2) The justification did
	-- not survive checking — the documented rules cover the control's APPEARANCE
	-- (the documented delete affordance, "a red circle enclosing a minus
	-- sign") and documents that edit mode "provides controls to delete or move
	-- list items", but documents NO behaviour for tapping it. The source
	-- comment's "the platform pattern" was an uncited recollection, and round 2 was
	-- wrong three times that way.
	--
	-- What made the report legitimate rather than a misunderstanding: the
	-- minus deliberately borrows the destructive action's own accessible label
	-- (typically "Delete"), so it ANNOUNCED itself as Delete and then did not
	-- delete. The fix makes the label true.
	--
	-- The mechanism is deliberately not new: the minus becomes a THIRD caller
	-- of `commitDestructive()`, the same funnel keyboard Delete/Backspace
	-- (`tests/row_actions_input.spec.luau`, "Delete on a focused row fires the
	-- first destructive action") and the action menu's destructive item
	-- already use. That is what buys the full slide-off + height-collapse
	-- sequence — including round 2's C8a fix, where nothing stands painted
	-- once the row is carried clear — instead of a bare callback.
	it("editing shows the minus; tapping it DELETES the row directly (one funnel: commitDestructive)", function()
		local fired: { string } = {}
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				editing = editing,
			})
		end)
		local node = w.adapter.node(EDIT_AFFORDANCE_PATH)
		expect(node ~= nil).toBe(true)
		expect(node.props.role).toBe("destructive")
		expect(w.ra.dump().phase).toBe("closed")

		w.adapter.tap(EDIT_AFFORDANCE_PATH)
		w.pres.refresh()
		settle(w.pres)
		-- the action fires, exactly once...
		expect(fired).toEqual({ "delete" })
		-- ...and the commit ends closed, the same terminal state the keyboard
		-- Delete path asserts. A minus that fired but left a tray standing
		-- would be the C8a defect in a new costume.
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
	end)

	-- The tray-revealing behaviour still EXISTS and is still reachable — by
	-- the swipe, which is the gesture that means "show me this row's actions".
	-- Pinned here so the ruling above cannot be over-applied into deleting the
	-- reveal itself.
	it("the ruling is about the MINUS only — a swipe still reveals the trailing tray and fires nothing", function()
		local fired: { string } = {}
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				editing = editing,
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		expect(w.ra.dump().openEdge).toBe("trailing")
		expect(#fired).toBe(0)
	end)

	-- The minus still WEARS the destructive action's accessible name — that is
	-- what makes it announce correctly to a screen reader, and after the
	-- ruling above the name is finally honest. The DRAWN content is the icon's
	-- glyph (a circle's content is one mark — `blueprint.luau`'s `assertShape`);
	-- the semantic `label` is authored and never painted, same as every other
	-- `shape = "circle"` + `icon` button (`tests/button_shape.spec.luau`).
	it("the minus wears the destructive action's own accessible name, and now that name is true", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function() end,
					},
				},
				editing = editing,
			})
		end)
		local node = w.adapter.node(EDIT_AFFORDANCE_PATH)
		expect(node.props.label).toBe(theme_package.iconGlyph("decrement"))
	end)

	-- REDTEAM ITEM 6 (MAJOR): `handleActivate`'s edit-mode minus used to
	-- hard-code `open("trailing")` — dead for a row whose ONLY destructive
	-- action sits on the LEADING edge (`hasDestructive`/`hasEditAffordance`
	-- scan both edges, so this shape is reachable). A leading-only
	-- destructive row's minus must open the LEADING tray, not silently
	-- no-op (`openEdge:get() ~= "trailing"` was already true — "trailing" —
	-- so the old code's own no-op guard never even fired; `open("trailing")`
	-- itself was simply a no-op because this row has no trailing actions at
	-- all, see `hasActions`).
	it("editing (leading-only destructive): tapping the minus opens the LEADING tray, not trailing", function()
		local fired: { string } = {}
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				leading = {
					{
						id = "archive",
						label = "Archive",
						role = "destructive",
						onAction = function()
							table.insert(fired, "archive")
						end,
					},
				},
				editing = editing,
			})
		end)
		expect(w.ra.dump().phase).toBe("closed")
		w.adapter.tap(EDIT_AFFORDANCE_PATH)
		w.pres.refresh()
		settle(w.pres)
		-- RE-DECIDED with the case above: the minus commits rather than
		-- reveals. What this case still guards is the half of REDTEAM item 6
		-- that has nothing to do with the ruling — `firstDestructiveEntry`
		-- searching BOTH edges. A row whose only destructive action sits on
		-- the LEADING edge must still delete; the old hard-coded
		-- `open("trailing")` was silently dead here, and a hard-coded
		-- `commit(trailing)` would be dead in exactly the same way.
		expect(fired).toEqual({ "archive" })
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
	end)

	-- Task 9 four-input reachability: the minus is a normal focusable Button
	-- routed through the SAME `handleActivate` dispatch every tray button
	-- above already proves reachable (tests/row_actions.spec.luau:598-619's
	-- own idiom) — content("Body") is a plain UI.Text (no focusable children),
	-- so the minus is the tree's only focus stop and Navigate lands on it first.
	-- RE-DECIDED 2026-08-13, and these two were the dangerous pair: after the
	-- minus-deletes ruling they kept PASSING while asserting a behaviour that
	-- no longer happens. `doCommitAction` sets `openEdge` to the committing
	-- edge for the duration of the flight, so `dump().openEdge == "trailing"`
	-- reads true mid-commit — the assertion survived, the name became a lie,
	-- and the four-input proof it carries silently stopped proving anything.
	-- That is the vacuous-test class this file already knows (see the
	-- claim-count spy below): a green assertion satisfied by a transient state
	-- rather than by the outcome. Both now assert the OUTCOME, after a settle.
	it("RowActions keyboard: focus + Return activates the minus, which DELETES the row", function()
		local fired: { string } = {}
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				editing = editing,
			})
		end)
		expect(w.pres.focus.focused:get()).toBe(EDIT_AFFORDANCE_PATH)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		settle(w.pres)
		expect(fired).toEqual({ "delete" })
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("RowActions gamepad: focus + ButtonA activates the minus, which DELETES the row", function()
		local fired: { string } = {}
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				editing = editing,
			})
		end)
		expect(w.pres.focus.focused:get()).toBe(EDIT_AFFORDANCE_PATH)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		settle(w.pres)
		expect(fired).toEqual({ "delete" })
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("two activations of the minus DELETE EXACTLY ONCE (two independent guards, both required)", function()
		-- RE-DECIDED 2026-08-13 with the director's minus-deletes ruling.
		-- This case used to prove "activating the minus while the tray is
		-- already open is a no-op", because the minus opened a tray. It
		-- commits now, so that guarantee no longer exists — but the
		-- SAFETY question underneath it got sharper, not weaker: an
		-- accidental double-tap on a destructive control must not delete
		-- twice.
		--
		-- WHAT PROTECTS IT, ESTABLISHED BY MUTATION RATHER THAN BY
		-- READING. The first draft of this comment credited
		-- `doCommitAction`'s `committed` latch, which is what the code
		-- reads like. That was wrong: disabling the latch alone leaves the
		-- whole suite green AND leaves this row deleting exactly once,
		-- because the commit fires at the END of the slide-off and a
		-- second `commitEpoch` generation check (`:1563`, `:1612`) guards
		-- the settle chain independently. The two guards are deliberate
		-- defence in depth — the epoch's own comment calls itself "belt,
		-- on top of the `committed`/`disposed` guards".
		--
		-- So the honest statement is: this property has TWO independent
		-- owners, and it takes breaking BOTH to produce a double delete.
		-- Verified: with `committed` neutered and the epoch compare
		-- reduced to `if disposed then`, a probe fires the destructive
		-- action TWICE and this case reddens. With either guard alone
		-- restored, it fires once. Anyone who "simplifies" one of the two
		-- away will not be caught by this test — that is a known and
		-- accepted limit of it, written down rather than discovered.
		--
		-- THE ORIGINAL'S INSTRUMENT DISCIPLINE IS KEPT, because it is the
		-- reason this case is worth anything. `dump().openEdge` could not
		-- see the old guard (a second `open("trailing")` is a no-op in its
		-- own right — `retarget` re-aims a spring at the value it already
		-- holds, and `openEdge:set` is equality-diffed by the core), so a
		-- mutation deleting the guard left the assertion green. The
		-- claim-count spy was added to make it bite. The same trap applies
		-- here: `#fired` is the observable that actually distinguishes one
		-- commit from two, so that is what is counted — and the spy stays,
		-- because a commit that re-claimed the coordinator would be a
		-- second defect the fire count alone cannot see.
		-- `dump().openEdge` alone cannot prove this: `open("trailing")` called a
		-- SECOND time on an already-"trailing" row is a no-op in its OWN right
		-- (`retarget` re-aims the SAME persistent spring at the value it is
		-- already at; `openEdge:set("trailing")` is equality-diffed by the core
		-- and never refires a subscriber) — so `dump().openEdge` reads
		-- "trailing" identically whether row_actions.luau's own no-op guard
		-- exists or not, and a mutation deleting that guard leaves this
		-- assertion green (the exact vacuous-test class this file's own
		-- localization test comment already warns about). The one thing that
		-- DOES differ is whether `open()` runs its BODY at all: wrap the real
		-- coordinator's `claim` in a counting spy (a coordinator is a plain
		-- table of closures — `row_actions.newCoordinator`'s own return shape
		-- — so wrapping one field is ordinary Lua, no framework hook needed)
		-- and assert it is called exactly ONCE for two activations.
		local coordinator = row_actions.newCoordinator(Facet.newCore())
		local claimCount = 0
		local realClaim = coordinator.claim
		coordinator.claim = function(...)
			claimCount += 1
			return realClaim(...)
		end
		local fired: { string } = {}
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				editing = editing,
				coordinator = coordinator,
			})
		end)
		-- two activations with NO settle between them — the accidental
		-- double-tap, landing while the first commit is still in flight,
		-- which is precisely where the `committed` latch has to hold.
		w.adapter.tap(EDIT_AFFORDANCE_PATH)
		w.adapter.tap(EDIT_AFFORDANCE_PATH)
		w.pres.refresh()
		settle(w.pres)
		expect(fired).toEqual({ "delete" }) -- ONCE. Two would be a destroyed row's worth of defect.
		expect(w.ra._isOpen()).toBe(false)
		-- ZERO, and the zero is the interesting part. The old minus opened
		-- a tray, so it claimed the one-open-at-a-time coordinator; a
		-- commit reveals nothing, so it claims nothing. The spy therefore
		-- proves the behaviour CHANGE as well as its idempotence — if a
		-- future edit reintroduced a reveal before the commit, this count
		-- would go to 1 and say so. Kept for that, not out of habit.
		expect(claimCount).toBe(0)
	end)

	it(
		"a full trailing reveal EXPOSES the same tray with or without editing (the gutter is an inset, never a lost reveal)",
		function()
			-- WHAT THIS TEST IS FOR, restated for the padding form (director
			-- device round 2026-08-12, finding 2). The danger the old
			-- `contentOffsetX` branch was defending against is real and still
			-- guarded here: a gutter folded into a NEGATIVE offset would
			-- permanently under-expose the trailing tray by the gutter width for
			-- as long as it stayed open. The invariant that says so is the
			-- CONTENT'S RIGHT EDGE — how much of the tray behind it is uncovered —
			-- which must be the identical pixel with and without `editing`.
			--
			-- Its LEFT edge is deliberately NOT that invariant any more: the
			-- gutter is Content's own left padding now, so an editing row's
			-- content is inset by exactly `editAffordance` at every offset,
			-- including this one. The old assertion pinned the left edge and
			-- therefore pinned the defect — the row slid a full gutter left over
			-- its own minus for the whole gesture and snapped back in one frame
			-- at `offset == 0` (frames f022-f034). Both halves are asserted below,
			-- so neither can regress into the other.
			-- A FIXED-WIDTH ROW, on purpose. The default fixture root is content-
			-- sized, and a padding participates in measure — so a hug row genuinely
			-- grows by the gutter and its Content box's right edge is NOT comparable
			-- across the two worlds. Production rows are `fill` (Table hands its own
			-- `width = { type = "fill", weight = 1 }` straight through), which is
			-- the shape this invariant is about, and a fixed width is the
			-- deterministic stand-in for it.
			local ROW_W = 400
			local function openTrailing(withEditing: boolean): any
				local w = presenterWorld(function(core)
					local spec: any = {
						id = "Row",
						width = { type = "fixed", px = ROW_W },
						content = content("Body"),
						trailing = {
							{ id = "delete", label = "Delete", role = "destructive", onAction = function() end },
						},
					}
					if withEditing then
						spec.editing = core:signal(true)
					end
					return row_actions.build(Facet, core, spec)
				end)
				-- `_open` then an IMMEDIATE refresh, before `settle` — the same
				-- two-step the "labels survive pseudo-loc" test above uses
				-- (line ~274): the trailing tray mounts lazily, so its button
				-- naturals (and therefore `trailingWidth`, and therefore the
				-- spring's own retarget) are not measured until a sync happens
				-- AFTER the tray exists. Skipping this step opens toward a
				-- transient `trailingWidth == 0` and only self-corrects once
				-- `syncGeometry` re-aims on the next sync — this test wants the
				-- FINAL settled geometry, so it earns that correction first.
				w.ra._open("trailing")
				w.pres.refresh()
				settle(w.pres)
				w.pres.refresh()
				local box = w.adapter.node(ROW .. "/Content").rect
				return {
					offset = w.ra.dump().offset,
					rightEdge = box.x + box.w,
					bodyX = w.adapter.node(ROW .. "/Content/Body").rect.x,
				}
			end
			local edit, plain = openTrailing(true), openTrailing(false)
			expect(edit.offset < 0).toBe(true) -- it really opened (no vacuous pass)
			-- THE REVEAL: the content's right edge is where the uncovered tray
			-- begins, so this IS "the same amount of tray exposed". Written as the
			-- edge rather than as `offset == offset`, which two identically-specced
			-- rows satisfy by construction and would pass even if the gutter ate
			-- the reveal.
			expect(edit.rightEdge).toBe(plain.rightEdge)
			expect(edit.rightEdge).toBe(ROW_W + edit.offset) -- ...and it is the travel, not a coincidence
			-- ...and the gutter is an INSET, present at this offset like every other
			-- controls.rowActions.editAffordance (28) + controls.rowActions.rowGutter
			-- (8). The gutter joined the strip in the device bug round 2026-08-12
			-- (finding A2): a strip exactly one diameter wide left the minus
			-- touching the row it is meant to sit outside of.
			expect(edit.bodyX - plain.bodyX).toBe(36)
		end
	)

	it("toggling editing off does not force-close an already-open tray (documented behavior)", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = editing,
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.ra.dump().openEdge).toBe("trailing")
		editing:set(false)
		w.pres.refresh()
		-- the minus itself is gone...
		expect(w.adapter.node(EDIT_AFFORDANCE_PATH) == nil).toBe(true)
		-- ...but the tray this row's own open/close machinery is managing stays
		-- exactly as the player left it (`editing` only ever gates the minus and
		-- the leading-side gutter, never the tray's own open state)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	it("editing shifts Content right by the editAffordance gutter (geometry)", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(false)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = editing,
			})
		end)
		local restX = w.adapter.node(ROW .. "/Content/Body").rect.x
		editing:set(true)
		w.pres.refresh()
		local editX = w.adapter.node(ROW .. "/Content/Body").rect.x
		-- controls.rowActions.editAffordance (28, Task 2 default) + the row-facing
		-- controls.rowActions.rowGutter (8, device bug round 2026-08-12 finding A2)
		expect(editX - restX).toBe(36)
	end)

	it("leading actions + editing compose: the minus sits outside (before) the leading tray's reveal", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				leading = { { id = "flag", label = "Flag", onAction = function() end } },
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = editing,
			})
		end)
		w.ra._open("leading")
		w.pres.refresh()
		local minusRect = w.adapter.node(EDIT_AFFORDANCE_PATH).rect
		local trayRect = w.adapter.node(LEADING_TRAY).rect
		expect(minusRect ~= nil).toBe(true)
		expect(trayRect ~= nil).toBe(true)
		-- the minus's own gutter strip ends exactly where the (also gutter-
		-- shifted) leading tray begins — adjacent, never overlapping
		expect(minusRect.x + minusRect.w <= trayRect.x).toBe(true)
	end)

	it("the minus's own hit target floors at 44px despite its 28px visual diameter", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = editing,
			})
		end)
		local node = w.adapter.node(EDIT_AFFORDANCE_PATH)
		expect(node.rect.w).toBe(28) -- the PAINTED size stays the theme's editAffordance metric...
		expect(node.hitRect ~= nil).toBe(true)
		expect(node.hitRect.w >= 44).toBe(true) -- ...while the ENGINE HIT RECT floors at targetSizes.minimum
		expect(node.hitRect.h >= 44).toBe(true)
	end)

	-- ===== DIRECTOR DEVICE ROUND 2026-08-12 =================================
	-- Three findings filmed on the row_actions scenario's TABLE surface. Each
	-- gets a pin here, in the shared blueprint path both standalone and Table
	-- run through, because that is where all three actually live.

	-- FINDING 1 — "text pop at close settle". Measured off the filmed frames the
	-- close flight is already a RIGID TRANSLATION that decelerates onto rest
	-- (row right edge 810 -> 872 -> 895 -> 903 -> 907 across tp04..tp08, the row
	-- box never changing width), so what the director read as a jump is two
	-- sampled frames with a third between them. That makes this a PIN, not a
	-- fix: the two properties that would turn it into a real pop — a box that
	-- re-solves mid-flight, or a terminal step larger than the one before it —
	-- are asserted frame by frame so neither can appear later.
	it(
		"the close flight is a rigid translation that decelerates onto the settled geometry (no terminal step)",
		function()
			local w = presenterWorld(function(core)
				return row_actions.build(Facet, core, {
					id = "Row",
					content = content("Body"),
					trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				})
			end)
			local restX = w.adapter.node(ROW .. "/Content/Body").rect.x
			local restW = w.adapter.node(ROW .. "/Content/Body").rect.w
			w.ra._open("trailing")
			w.pres.refresh()
			settle(w.pres)
			w.pres.refresh()
			expect(w.adapter.node(ROW .. "/Content/Body").rect.x < restX).toBe(true) -- genuinely open

			w.ra._close()
			local xs: { number } = {}
			for _ = 1, SETTLE_FRAMES do
				w.pres.tick(FRAME)
				w.pres.refresh()
				local rect = w.adapter.node(ROW .. "/Content/Body").rect
				-- RIGID: the row's own box never re-solves while it slides. A width
				-- that moved mid-flight would be a re-layout — the shape the director
				-- suspected, and the one that WOULD pop.
				expect(rect.w).toBe(restW)
				table.insert(xs, rect.x)
			end
			-- lands exactly on the rest geometry, not near it
			expect(xs[#xs]).toBe(restX)
			local biggest, last = 0, 0
			for i = 2, #xs do
				local step = xs[i] - xs[i - 1]
				expect(step >= 0).toBe(true) -- monotone: never overshoots past rest and back
				biggest = math.max(biggest, step)
				if step > 0 then
					last = step
				end
			end
			expect(biggest > 0).toBe(true) -- the flight really flew (guards a vacuous pass)
			-- THE ANTI-POP. This assertion IS finding 1's whole disposition (it
			-- shipped as a pin, not a fix), so it has to be tight enough to catch
			-- the thing the director reported. `last < biggest` was NOT: the
			-- largest step of this flight is ~11.7px, so a 5px terminal pop —
			-- exactly the shape of the defect — sailed through it (review round,
			-- injected and confirmed green). The real terminal step is 6.1e-5px,
			-- so both caps below hold with four orders of magnitude of headroom
			-- while a pop of even one pixel fails.
			expect(last <= 0.5).toBe(true) -- SUB-PIXEL: a step nobody could see
			expect(last <= 0.05 * biggest).toBe(true) -- ...and vanishing against the flight itself
		end
	)

	-- FINDING 2 — "the edit minus collapses during a swipe and pops in after".
	-- Root cause was the old `contentOffsetX` branch: a step of exactly
	-- `editAffordance` at `offset == 0`. The gutter is Content's own left
	-- PADDING now, so it is present at every offset of every sign. Asserted as
	-- an invariant over a whole trailing gesture rather than at two sampled
	-- points, because a two-point test is what let the step ship.
	it("the edit gutter never collapses: the minus stays mounted and the inset holds at EVERY offset", function()
		local editing
		local w = presenterWorld(function(core)
			editing = core:signal(true)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = editing,
			})
		end)
		local function checkFrame()
			-- the affordance is still a live node...
			expect(w.adapter.node(EDIT_AFFORDANCE_PATH) ~= nil).toBe(true)
			-- ...and the row content is still inset past it by the full gutter,
			-- whatever the offset's sign. A padding is spent before `offsetFill`
			-- ever runs, so this identity holds at EVERY sample — which is exactly
			-- what the branch it replaced could not say (it held only for offset
			-- >= 0 and stepped by the whole gutter at the crossing).
			local body = w.adapter.node(ROW .. "/Content/Body").rect
			-- testkit's second argument is an ABSOLUTE tolerance, so the `6` this
			-- was written with meant ±6px — wide enough for a 5px gutter collapse
			-- to pass (review round, injected and confirmed green). The identity is
			-- exact arithmetic on the same double; 1e-6 is float noise only.
			expect(body.x - w.ra.dump().offset).toBeCloseTo(36, 1e-6) -- editAffordance + rowGutter
		end
		checkFrame()
		w.ra._open("trailing")
		w.pres.refresh()
		local sawNegative = false
		for _ = 1, SETTLE_FRAMES do
			w.pres.tick(FRAME)
			w.pres.refresh()
			sawNegative = sawNegative or w.ra.dump().offset < 0
			checkFrame()
		end
		expect(sawNegative).toBe(true) -- the gesture really went negative
		w.ra._close()
		for _ = 1, SETTLE_FRAMES do
			w.pres.tick(FRAME)
			w.pres.refresh()
			checkFrame()
		end
		expect(w.ra.dump().offset).toBe(0) -- home, with the gutter still there
	end)

	-- ...and the half of finding 2 geometry cannot express: the minus is only
	-- VISIBLE under a row that has slid into its gutter if it paints ON TOP.
	-- Array order is paint order, so this is a structural fact of the blueprint.
	it("the minus paints OVER Content — the director's 'stays pinned during a swipe'", function()
		local built
		local w = presenterWorld(function(core)
			built = row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = core:signal(true),
			})
			return built
		end)
		expect(w.adapter.node(EDIT_AFFORDANCE_PATH) ~= nil).toBe(true)
		local contentAt, minusAt = nil, nil
		for i, child in built.blueprint.children do
			if child.id == "Content" then
				contentAt = i
			elseif child.id == "EditAffordanceWhen" then
				minusAt = i
			end
		end
		expect(contentAt ~= nil).toBe(true)
		expect(minusAt ~= nil).toBe(true)
		expect(minusAt > contentAt).toBe(true)
	end)

	-- FINDING 3a — the tray gutter. Two rounded plates drawn flush read as one
	-- merged slab (hi05: Delete 645-777, Flag 780-905). The gap is a THEME
	-- metric, and the travel distance has to include it or the last button parks
	-- half off the row — both asserted, because fixing only the first is the
	-- easy half.
	it("adjacent tray buttons carry the theme's trayGap, and the travel distance includes it", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{ id = "delete", label = "Delete", role = "destructive", onAction = function() end },
					{ id = "flag", label = "Flag", onAction = function() end },
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local del = w.adapter.node(TRAILING_TRAY .. "/Action:delete").rect
		local flag = w.adapter.node(TRAILING_TRAY .. "/Action:flag").rect
		local gap = flag.x - (del.x + del.w)
		expect(gap).toBe(4) -- controls.rowActions.trayGap, filled from style.space.xs
		-- ...and the band's ROW-FACING gutter, a separate metric on the same scale
		-- (device bug round 2026-08-12, finding A1a): the plate used to butt
		-- straight against the row. It is the band's own padding, so it is inside
		-- the tray's rect, in front of the first plate.
		local gutter = themeSnapshot.resolveNumber(themeSnapshot.neutral(), "controls.rowActions.rowGutter")
		expect(gutter).toBe(8) -- filled from style.space.s
		expect(del.x - w.adapter.node(TRAILING_TRAY).rect.x).toBe(gutter)
		-- the tray really is that much wider than its plates...
		expect(w.adapter.node(TRAILING_TRAY).rect.w).toBe(gutter + del.w + gap + flag.w)
		-- ...and the row slid far enough to uncover the gutter as well as the two
		-- plates. Fixing only the gap would park the far plate half off the row.
		expect(-w.ra.dump().offset).toBe(gutter + del.w + gap + flag.w)
	end)

	-- FINDING 3b — the machinery, at its own seam. `prefer` is the ONE thing the
	-- compact grammar gained; if it stopped reaching the solver the tray would
	-- quietly fall back to labels and only a pixel test would notice.
	it("the compact grammar carries `prefer`, and its absence still means degrade-only", function()
		expect(renderer.compactForm({ compactLabel = { icon = "trash", prefer = true } }).prefer).toBe(true)
		expect(renderer.compactForm({ compactLabel = { icon = "trash" } }).prefer).toBe(false)
		expect(renderer.compactForm({ compactLabel = "Ed" }).prefer).toBe(false)
		-- the drawn mark the tray's natural width is measured against
		expect(theme_package.iconGlyph("trash")).toBe("\\_/")
		-- and the grammar still refuses what it always refused: `prefer` names no
		-- form, so a table holding only it is still formless.
		local ok = pcall(function()
			return Facet.UI.Button({ id = "B", label = "x", compactLabel = { prefer = true } })
		end)
		expect(ok).toBe(false)
		local badType = pcall(function()
			return Facet.UI.Button({ id = "B", label = "x", compactLabel = { icon = "trash", prefer = "yes" } })
		end)
		expect(badType).toBe(false)
	end)
end)

--[[ ===== DEVICE BUG ROUND 2026-08-12, GROUP A ================================
	Four findings the director photographed on a real phone
	(docs/plans/device-bug-round-2026-08-12.md, `UntitledRacingGame/bugs/`), every
	one of them past a green 4160-case suite. What let all four through is the
	same omission each check below repairs: the suite asked what the tray was
	SIZED at and never what it had to be sized FOR — the room a package's frame
	takes out of a plate, the space between the plate and the row it is acting
	on, the width of the row the whole band has to fit inside, and the fact that
	the character in an icon's place is read by a human being.

	A3 and A1b are swept across every shipped package rather than pinned to the
	one the photograph happened to be taken under: the parchment package is not
	special, it is simply the one the director opened. ]]
local PACKAGES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}
local function packageOf(name: string): any
	return (require)(`../examples/themes/{name}`).build(Facet.themes)
end
-- the theme's own numbers, never a literal restated here
local function metricOf(snap: any, path: string): number
	return themeSnapshot.resolveNumber(snap, path) or 0
end

-- presenterWorld's shape with ONE addition: the row is handed the environment,
-- which is what every real caller does (Table and VirtualList both pass their
-- own `env` straight through) and what makes the theme's metrics reach the
-- control at all. Without it the composite degrades to the neutral snapshot and
-- a themed sweep would measure the wrong package on purpose.
local function themedWorld(snap: any?, spec: (core: any, env: any) -> any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if snap ~= nil then
		env:set("themeMetrics", snap)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local ra = row_actions.build(Facet, core, spec(core, env))
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { ra.blueprint } }))
	pres.refresh()
	return { core = core, env = env, adapter = adapter, pres = pres, ra = ra, handle = handle }
end

describe("device bug round 2026-08-12 — the tray's negative space (findings A1a, A2)", function()
	it("a trailing plate never touches the row: the band carries the theme's rowGutter", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				width = { type = "fill", weight = 1 },
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						icon = "trash",
						onAction = function() end,
					},
					{ id = "flag", label = "Flag", icon = "flag", onAction = function() end },
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local gutter = metricOf(themeSnapshot.neutral(), "controls.rowActions.rowGutter")
		expect(gutter > 0).toBe(true) -- a zero here would make every leg below vacuous
		local contentBox = w.adapter.node(ROW .. "/Content").rect
		local firstPlate = w.adapter.node(TRAILING_TRAY .. "/Action:delete").rect
		-- THE PHOTOGRAPH (IMG_3679): the row's sliding edge and the first plate's
		-- left edge were the same x. The row travels to uncover the band, and the
		-- band's first thing is its gutter.
		expect(firstPlate.x - (contentBox.x + contentBox.w)).toBe(gutter)
		-- ...and the far plate still lands exactly on the row's own right edge:
		-- the gutter is spent INSIDE the band, never past its outer edge
		local rowBox = w.adapter.node(ROW).rect
		local farPlate = w.adapter.node(TRAILING_TRAY .. "/Action:flag").rect
		expect(farPlate.x + farPlate.w).toBe(rowBox.x + rowBox.w)
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)

	it("...and neither does a leading one, on the mirrored edge", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				width = { type = "fill", weight = 1 },
				leading = { { id = "read", label = "Mark Read", onAction = function() end } },
			})
		end)
		w.ra._open("leading")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local gutter = metricOf(themeSnapshot.neutral(), "controls.rowActions.rowGutter")
		local contentBox = w.adapter.node(ROW .. "/Content").rect
		local plate = w.adapter.node(LEADING_TRAY .. "/Action:read").rect
		expect(contentBox.x - (plate.x + plate.w)).toBe(gutter)
		-- ...and the outer edge is still flush with the row's own left edge: the
		-- gutter is spent on the ROW-FACING side of the band, never the outside
		local rowBox = w.adapter.node(ROW).rect
		expect(plate.x).toBe(rowBox.x)
	end)

	it("the edit-mode minus sits in the same negative space, not against the row (A2)", function()
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				width = { type = "fill", weight = 1 },
				editing = core:signal(true),
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
			})
		end)
		local gutter = metricOf(themeSnapshot.neutral(), "controls.rowActions.rowGutter")
		local minus = w.adapter.node(EDIT_AFFORDANCE_PATH).rect
		local body = w.adapter.node(ROW .. "/Content/Body").rect
		-- IMG_3683: the red disc's right edge and the row's left edge were the
		-- same x. The strip the disc lives in is a diameter PLUS the same gutter
		-- the tray band keeps.
		expect(body.x - (minus.x + minus.w)).toBe(gutter)
	end)
end)

describe("device bug round 2026-08-12 — a tray label fits the package's frame (finding A3)", function()
	it("every shipped package leaves a tray label the room it measured for it", function()
		--[[ IMG_3685: "Mark Read" cut off under Fantasy Parchment. The plate's
			width is decided by `deriveNaturals` — `fixed px`, so nothing downstream
			can grow it — and it was decided as text + 2 * buttonPad, which is the
			whole sum only on a package with no frame. Every package that paints one
			reserves `chromeInsets.control` out of that same box at paint time, so
			the label lost exactly the frame.

			MEASURE THE REQUIREMENT, NOT THE RENDER: the requirement is the label at
			UNLIMITED width, from the framework's own oracle at the button's own live
			font/size; the render (`TextBounds`, `TextFits`) already has the
			truncation baked into it. ]]
		local LABEL = "Mark Read"
		for _, name in PACKAGES do
			local pkg = packageOf(name)
			local snap = themeSnapshot.resolve(pkg, nil, {})
			local w = themedWorld(snap, function(_core, env)
				return {
					id = "Row",
					content = content("Body"),
					width = { type = "fill", weight = 1 },
					env = env,
					leading = { { id = "read", label = LABEL, onAction = function() end } },
				}
			end)
			w.ra._open("leading")
			w.pres.refresh()
			settle(w.pres)
			w.pres.refresh()
			local path = LEADING_TRAY .. "/Action:read"
			local plate = w.adapter.node(path)
			local facts = w.handle.controller.textAt(path)
			expect(`{name}: facts`).toBe(if facts ~= nil then `{name}: facts` else `{name}: NONE`)
			local required = text_metrics.measure(LABEL, facts.font, facts.size, math.huge).width
			local insets = (snap.chromeInsets :: any).control or { left = 0, right = 0 }
			local pad = metricOf(snap, "controls.rowActions.buttonPad")
			local room = plate.rect.w - 2 * pad - (insets.left or 0) - (insets.right or 0)
			expect(`{name}: room {room} >= required {required}`).toBe(`{name}: room {room} >= required {required}`)
			expect(`{name}: fits={room >= required}`).toBe(`{name}: fits=true`)
		end
	end)

	it("...and a package with no frame is untouched to the pixel", function()
		-- the fix must be inert wherever it was already right, or it is a geometry
		-- change to every flat theme rather than a repair of the framed ones
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				width = { type = "fill", weight = 1 },
				leading = { { id = "read", label = "Mark Read", onAction = function() end } },
			})
		end)
		w.ra._open("leading")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local neutral = themeSnapshot.neutral()
		local path = LEADING_TRAY .. "/Action:read"
		local facts = w.handle.controller.textAt(path)
		local required = text_metrics.measure("Mark Read", facts.font, facts.size, math.huge).width
		local pad = metricOf(neutral, "controls.rowActions.buttonPad")
		-- flat: the plate is exactly the label plus its own padding, no frame term
		expect(w.adapter.node(path).rect.w).toBe(
			math.max(metricOf(neutral, "controls.rowActions.buttonMinWidth"), required + 2 * pad)
		)
	end)
end)

describe("device bug round 2026-08-12 — actions that cannot fit the row (finding A1b)", function()
	it("a band wider than the row shares out the row instead of hanging off its edge", function()
		--[[ Measured before the fix, on this exact fixture: a 160px row with four
			actions put the band at 268px, its first plate at x = -108 — 108px
			outside the row, unreachable, and `controller.diagnostics()` empty. An
			action a player cannot touch is a silent wrong result. ]]
		local ROW_PX = 160
		local w = presenterWorld(function(core)
			return row_actions.build(Facet, core, {
				id = "Row",
				content = content("Body"),
				width = { type = "fixed", px = ROW_PX },
				trailing = {
					{ id = "a", label = "Delete", icon = "trash", onAction = function() end },
					{ id = "b", label = "Flag", icon = "flag", onAction = function() end },
					{ id = "c", label = "More", icon = "more", onAction = function() end },
					{ id = "d", label = "Edit", icon = "edit", onAction = function() end },
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local rowBox = w.adapter.node(ROW).rect
		local tray = w.adapter.node(TRAILING_TRAY).rect
		expect(tray.w <= rowBox.w).toBe(true)
		expect(tray.x >= rowBox.x).toBe(true)
		for _, id in { "a", "b", "c", "d" } do
			local plate = w.adapter.node(TRAILING_TRAY .. "/Action:" .. id).rect
			-- every plate inside the row's own box, on both edges
			expect(`{id}: x {plate.x} >= {rowBox.x}`).toBe(`{id}: x {plate.x} >= {rowBox.x}`)
			expect(plate.x >= rowBox.x).toBe(true)
			expect(plate.x + plate.w <= rowBox.x + rowBox.w).toBe(true)
			expect(plate.w > 0).toBe(true)
		end
		-- and the row travels no further than its own width: a slide past that is
		-- a row that has left the screen with its actions still coming
		expect(-w.ra.dump().offset <= ROW_PX).toBe(true)
	end)

	it("a row with no cage is never clamped to its own stale width (the ratchet)", function()
		--[[ THE HAZARD THE `clampable` GUARD EXISTS FOR, as a live sequence rather
			than an argument. A HUG row's solved width is DERIVED from the band an
			Anchor hugs, so "clamp the band to the row" would be the band clamped to
			ITSELF — and one frame of staleness makes that a one-way ratchet: the
			naturals grow (here, a theme swap raising the per-button floor to 200),
			the row is still the width it had before they did, the clamp writes the
			smaller number, the row re-solves to THAT, and the band never recovers.
			Measured with the guard removed: the plate settles at 102px and stays
			there. With it, the row grows for its band, which is what a row with no
			cage is allowed to do. ]]
		local w = themedWorld(nil, function(_core, env)
			return {
				id = "Row",
				content = content("Body"), -- no `width`: this row HUGS
				env = env,
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			}
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		local FLOOR = 200
		local base = themeSnapshot.neutral()
		local controls: any = table.clone(base.controls)
		local family: any = table.clone(controls.rowActions)
		family.buttonMinWidth = FLOOR
		controls.rowActions = family
		local swapped: any = table.clone(base)
		swapped.controls = controls
		local before = w.adapter.node(TRAILING_TRAY .. "/Action:delete").rect.w
		expect(before < FLOOR).toBe(true) -- a real differential, not a no-op swap
		w.env:set("themeMetrics", swapped)
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:delete").rect.w).toBe(FLOOR)
	end)
end)

describe("device bug round 2026-08-12 — a letter is not an icon (finding A4)", function()
	it("no framework fallback glyph contains an uppercase letter", function()
		--[[ IMG_3686: the delete and flag plates drew "U" and "P" under Pixel
			Quest, which declines the framework art rung and so renders the ASCII
			floor. They were authored as pictures ("a bin's silhouette", "a pole
			with a pennant") and read as initials, because that is what a capital
			letter is. A lowercase mark can be a stroke the eye reads as a shape —
			`v` is a tick, `x` is a cross — but a capital in an icon's place is a
			caption, and a caption nobody wrote is a silent wrong result. ]]
		local offenders: { string } = {}
		for name, glyph in theme_package.ICON_FALLBACK_GLYPHS :: any do
			if string.match(glyph, "%u") ~= nil then
				table.insert(offenders, `{name}={glyph}`)
			end
		end
		table.sort(offenders)
		expect(`offenders: {table.concat(offenders, ", ")}`).toBe("offenders: ")
	end)

	it("a tray plate under a package that declines framework art draws the mark, never a letter", function()
		-- the end-to-end the rule above exists for: Pixel Quest is a SHIPPED
		-- package with `identity.standardIcons = false`, so this is the path the
		-- photograph was taken on, not a synthetic one.
		local pkg = packageOf("pixel_quest")
		expect((pkg.identity :: any).standardIcons).toBe(false)
		local w = themedWorld(themeSnapshot.resolve(pkg, nil, {}), function(_core, env)
			return {
				id = "Row",
				content = content("Body"),
				width = { type = "fill", weight = 1 },
				env = env,
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						icon = "trash",
						onAction = function() end,
					},
					{ id = "flag", label = "Flag", icon = "flag", onAction = function() end },
				},
			}
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		settle(w.pres)
		w.pres.refresh()
		for _, id in { "delete", "flag" } do
			local drawn = w.adapter.node(TRAILING_TRAY .. `/Action:{id}`).props.label
			expect(`{id} drawn={drawn}`).toBe(
				`{id} drawn={theme_package.resolveIcon(pkg, if id == "delete" then "trash" else "flag").glyph}`
			)
			expect(`{id} letters={string.match(tostring(drawn), "%a") ~= nil}`).toBe(`{id} letters=false`)
		end
	end)
end)
