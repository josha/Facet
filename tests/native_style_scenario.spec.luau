--!strict
-- Native-style scenario headless conformance (ledger NSS-A2/NSS-I2): the E3
-- fixture (examples/gallery/scenarios/native_style.luau) mounts through the
-- REAL presenter on the FakeTarget, and every classification INPUT the native
-- adapter tags from — surface hints, selected/enabled bindings, roles — is
-- emitted through the adapter contract even where paint is a no-op. This is
-- the headless half of the A/B: the Studio scenario proves the paint; this
-- proves the data survives without an engine.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local adapter_source = require("./lib/adapter_source")

local scenario = require("../examples/gallery/scenarios/native_style") :: any

local function makeCtx()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	-- stub the runner-owned engine seams: headless runs assert the CALLS, not paint
	local nativeCalls: { any } = {}
	local ctx = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		flags = {},
		nativeStyle = setmetatable({}, {
			__index = function(_, key)
				return function(...)
					table.insert(nativeCalls, { key = key, args = { ... } })
					return { stub = key }
				end
			end,
		}),
	}
	return ctx, adapter, presenter, core, nativeCalls
end

describe("native_style scenario (headless conformance)", function()
	it("mounts through the real presenter and emits every classification input", function()
		local ctx, adapter, presenter = makeCtx()
		local built = scenario.build(ctx)
		local handle = presenter.present(built.screen, built.present)
		presenter.refresh()
		expect(handle ~= nil).toBe(true)
		-- classification inputs visible through the adapter contract:
		local rowA = adapter.node("/NativeStyle/Body/Panel/RowA")
		expect(rowA ~= nil).toBe(true)
		expect(rowA.props.selected).toBe(true)
		local primary = adapter.node("/NativeStyle/Body/Panel/Primary")
		expect(primary.props.surface).toBe("accent")
		local panel = adapter.node("/NativeStyle/Body/Panel")
		expect(panel.props.surface).toBe("raised")
		local subtitle = adapter.node("/NativeStyle/Body/Subtitle")
		expect(subtitle.props.role).toBe("secondary")
	end)

	it("state steps flip the bindings the adapter classifies from", function()
		local ctx, adapter, presenter = makeCtx()
		local built = scenario.build(ctx)
		presenter.present(built.screen, built.present)
		presenter.refresh()
		built.steps.selectRowB()
		presenter.refresh()
		expect(adapter.node("/NativeStyle/Body/Panel/RowB").props.selected).toBe(true)
		built.steps.deselectRowB()
		presenter.refresh()
		expect(adapter.node("/NativeStyle/Body/Panel/RowB").props.selected).toBe(false)
		built.steps.disableRowB()
		presenter.refresh()
		expect(adapter.node("/NativeStyle/Body/Panel/RowB").props.enabled).toBe(false)
		built.steps.enableRowB()
		presenter.refresh()
		expect(adapter.node("/NativeStyle/Body/Panel/RowB").props.enabled).toBe(true)
	end)

	it("designer-edit and theme steps route through the runner-owned seams", function()
		local ctx, _, presenter, _, nativeCalls = makeCtx()
		local built = scenario.build(ctx)
		presenter.present(built.screen, built.present)
		built.steps.editTokenLive()
		built.steps.restoreToken()
		built.steps.editRuleLive()
		built.steps.restoreRule()
		built.steps.themeLight()
		built.steps.themeDark()
		built.steps.stripTransitions()
		built.steps.restoreTransitions()
		local keys = {}
		for _, call in nativeCalls do
			keys[call.key] = (keys[call.key] or 0) + 1
		end
		expect(keys.editToken).toBe(2)
		expect(keys.editRuleProperty).toBe(2)
		expect(keys.setTheme).toBe(2)
		expect(keys.setTransitionsEnabled).toBe(2)
	end)
end)

-- ===== REVIEW-FIX round: a theme token's engine TYPE (C21) ==================

describe("native_style: an enum can never be a theme-sheet attribute", function()
	local native_style = require("../src/client/native_style")

	it("refuses the enum kind by name instead of throwing from inside SetAttribute", function()
		local ok, err = pcall(function()
			native_style.tokenAttributeValue({ kind = "enum", enum = "ScaleType", item = "Slice" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "ScaleType", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "attribute", 1, true) ~= nil).toBe(true)
		-- and it points at where an enum DOES belong
		expect(string.find(tostring(err), "RULE", 1, true) ~= nil).toBe(true)
	end)

	it("no theme token the model builder emits is an enum (enums are rule props only)", function()
		local sheet_model = require("../src/tokens/sheet_model")
		local default_style = require("../src/tokens/default_style")
		local model = sheet_model.build({ themes = { { name = "Dark", style = default_style } } })
		for _, theme in model.themes do
			for name, value in theme.tokens do
				expect(value.kind ~= "enum").toBe(true)
				expect(#name > 0).toBe(true)
			end
		end
	end)
end)

-- ===== REVIEW-FIX round: chrome lifecycle in the client target (B13-B15) ====
--
-- These three live in `src/client/screen_target.luau` and operate on real
-- Instances, so the behavioural proof is the Studio scenario. What IS assertable
-- headlessly is that the code still SAYS what the review decided — each of these
-- was a silent leak or a silent visual defect under a fully green suite, and a
-- source contract is a cheaper guard than rediscovering them on a device.

describe("screen_target's chrome text lift: the source contract", function()
	-- the LIVE adapter as ONE text: three files since the 200k split
	local source = adapter_source.live()

	-- the chrome/decoration materializer was extracted to a sibling module when
	-- screen_target.luau reached Studio's 200_000-byte Source ceiling. Every
	-- anchor below is unchanged and keeps its strength — `section` looks in both
	-- halves of the adapter for the one that carries the anchor.
	local chromeSource = require("@lune/fs").readFile("src/client/screen_chrome.luau")

	local function section(fromNeedle: string, toNeedle: string): string
		local text = source
		local from = string.find(text, fromNeedle, 1, true)
		if from == nil then
			text = chromeSource
			from = string.find(text, fromNeedle, 1, true)
		end
		expect(from ~= nil).toBe(true)
		local to = string.find(text, toNeedle, from :: number, true)
		expect(to ~= nil).toBe(true)
		return string.sub(text, from :: number, to :: number)
	end

	it("adapter.remove destroys the lifted label (B13)", function()
		-- without this `census.textLifts` only ever grew across remounts and
		-- instancesByPath retained a destroyed label
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		expect(string.find(remove, "destroyChromeText(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("root teardown destroys every lifted label too (B13)", function()
		local destroyRoot = section("function adapter.destroyRoot(rootHandle: any)", "rootHandle.gui:Destroy()")
		expect(string.find(destroyRoot, "destroyChromeText(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("the fallback editing yield goes FULLY transparent (B14)", function()
		-- an opaque decoration child covers the parent TextBox's engine-drawn text
		-- and caret under Sibling z-behavior, which is what the yield must reveal
		local focused = section("(instance :: TextBox).Focused:Connect(function()", "FocusLost:Connect")
		-- v2: the yield generalized over a LAYER STACK, so the write
		-- runs per target rather than on one named decoration. The proposition is
		-- unchanged and still falsifiable — fully transparent, never repainted.
		expect(string.find(focused, "for _, child in yieldTargets(handle, deco) do", 1, true) ~= nil).toBe(true)
		expect(string.find(focused, "child.BackgroundTransparency = 1", 1, true) ~= nil).toBe(true)
		expect(string.find(focused, "BackgroundTransparency = 0", 1, true)).toBeNil()
		expect(string.find(focused, "child.ImageTransparency = 1", 1, true) ~= nil).toBe(true)
	end)

	it("text SHAPE is mirrored onto the lifted label, and TextScaled is documented out (B15)", function()
		expect(string.find(chromeSource, "label.RichText = (instance :: any).RichText", 1, true) ~= nil).toBe(true)
		expect(string.find(chromeSource, "label.LineHeight = (instance :: any).LineHeight", 1, true) ~= nil).toBe(true)
		-- both are watched, or the mirror only ever runs once at creation
		local watched = section("local WATCHED = {", "}")
		expect(string.find(watched, '"RichText"', 1, true) ~= nil).toBe(true)
		expect(string.find(watched, '"LineHeight"', 1, true) ~= nil).toBe(true)
		expect(string.find(chromeSource, "NOT SUPPORTED UNDER CHROME: `TextScaled`", 1, true) ~= nil).toBe(true)
	end)

	it("the theme sheet is relinked across EVERY live root, pruning destroyed ones (B12)", function()
		local relink = section("function adapter.relinkThemeSheet(sheet: StyleSheet?)", "\n\tend")
		expect(string.find(relink, "for _, gui in themeRoots do", 1, true) ~= nil).toBe(true)
		expect(string.find(relink, "gui.Parent ~= nil", 1, true) ~= nil).toBe(true)
		expect(string.find(relink, "native_style.linkAt(gui, effective)", 1, true) ~= nil).toBe(true)
		-- nil restores the target's own (legacy) sheet
		expect(string.find(relink, "sheet or legacyThemeSheet()", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== DIRECTOR FIX ROUND 2026-07-25: the adapter half ======================
-- The suppression writes, the skinned tag, the slot shadow and the decoration
-- hint all operate on real Instances, so their behavioural proof is the Studio
-- pass. What is assertable headlessly is that the code still SAYS what the fix
-- round decided — and each of these was a defect nobody could see under a fully
-- green suite.

describe("screen_target: the image IS the button (source contract)", function()
	-- the LIVE adapter as ONE text: three files since the 200k split
	local source = adapter_source.live()
	local renderer = require("@lune/fs").readFile("src/render/renderer.luau")

	-- the chrome/decoration materializer was extracted to a sibling module when
	-- screen_target.luau reached Studio's 200_000-byte Source ceiling. Every
	-- anchor below is unchanged and keeps its strength — `section` looks in both
	-- halves of the adapter for the one that carries the anchor.
	local chromeSource = require("@lune/fs").readFile("src/client/screen_chrome.luau")

	local function section(fromNeedle: string, toNeedle: string): string
		local text = source
		local from = string.find(text, fromNeedle, 1, true)
		if from == nil then
			text = chromeSource
			from = string.find(text, fromNeedle, 1, true)
		end
		expect(from ~= nil).toBe(true)
		local to = string.find(text, toNeedle, from :: number, true)
		expect(to ~= nil).toBe(true)
		return string.sub(text, from :: number, to :: number)
	end

	it("the skinned-slot tag rides the SAME desired set syncTags diffs against", function()
		-- syncTags removes every facet-* tag not in the desired set, so a tag added
		-- anywhere else would be stripped on the next classification pass
		local tags = section("local function syncTags(handle: any)", "local plan = tag_sync.diff(")
		expect(string.find(tags, "skinnedSlot = handle.chromeSlot", 1, true) ~= nil).toBe(true)
	end)

	it("fallback mode explicit-writes the same three suppressions the rules make", function()
		local suppress = section("local function applySkinnedSuppression", "\n\tend")
		expect(string.find(suppress, "if nativeMode then", 1, true) ~= nil).toBe(true)
		expect(string.find(suppress, "instance.BackgroundTransparency = 1", 1, true) ~= nil).toBe(true)
		expect(string.find(suppress, "CornerRadius = UDim.new(0, 0)", 1, true) ~= nil).toBe(true)
		expect(string.find(suppress, "Thickness = 0", 1, true) ~= nil).toBe(true)
		expect(string.find(suppress, "Transparency = 1", 1, true) ~= nil).toBe(true)
	end)

	it("it re-suppresses after applySurface, which repaints a plate on every branch", function()
		expect(
			string.find(
				source,
				"if handle ~= nil and handle.chrome ~= nil then\n\t\t\tapplySkinnedSuppression",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("bespoke interaction fills tint the DECORATION instead of the suppressed plate", function()
		local setFill = section("local function setFill(color: Color3", "if instant or isReducedMotion() then")
		expect(string.find(setFill, "if handle.chrome ~= nil then", 1, true) ~= nil).toBe(true)
		expect(string.find(setFill, "handle.chrome.ImageColor3", 1, true) ~= nil).toBe(true)
	end)

	it("the slot shadow names its authority and rides the capability probe", function()
		local shadow = section("local function syncChromeShadow", "live.Parent = host")
		expect(string.find(shadow, "not hasUIShadow", 1, true) ~= nil).toBe(true)
		expect(string.find(shadow, "styling.normalizeShadow", 1, true) ~= nil).toBe(true)
		-- the authority note: this is deliberately adapter-owned paint on a node
		-- the sheet does not shadow (::UIShadow rules are inert, m7)
		expect(string.find(chromeSource, "AUTHORITY NOTE, deliberately", 1, true) ~= nil).toBe(true)
		-- and it is torn down with the node, or the census could never fall
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		expect(string.find(remove, "dropChromeShadow(handle)", 1, true) ~= nil).toBe(true)
		-- ...and it is dropped when the DECORATION it hangs off is rebuilt too: a
		-- destroyed instance can never be re-parented, so a stale reference is a
		-- hard error rather than a leak
		local rebuild = section("if deco ~= nil and rebuild then", "if plan == nil then")
		expect(string.find(rebuild, "dropChromeShadow(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("the decoration HINT arrives through create, not through a later setter", function()
		-- a hint delivered after create() would build one decoration and churn it
		-- for another, because skinning is create()'s last act. `createOpts` joined
		-- the signature as a 5th argument (the fade group's
		-- engine class is another fact only create() can honour), so the contract is
		-- "the hint is a create ARGUMENT", not the exact argument list.
		expect(string.find(source, "function adapter.create(", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "decorationHint: any?,", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "handle.decorationHint = decorationHint", 1, true) ~= nil).toBe(true)
		-- The hint is READ from the blueprint and handed to `create` as its 4th
		-- argument. It used to be one literal call; instance recycling hoisted the
		-- read into a local because the same value also keys the recycle pool. The
		-- contract this guards is unchanged — construction-time, never a later setter
		-- — so both halves are asserted rather than one exact spelling.
		expect(string.find(renderer, "local hint = chrome_slots.readHint(node)", 1, true) ~= nil).toBe(true)
		expect(
			string.find(renderer, "adapter.create(rootHandle, node.path, node.class, hint, createOpts)", 1, true) ~= nil
		).toBe(true)
		-- and there is still no post-construction hint setter anywhere
		expect(string.find(renderer, "setDecorationHint", 1, true) == nil).toBe(true)
	end)

	it("a per-view override is explicit-written and never tagged", function()
		local create = section("if deco == nil then", "syncChromeText(handle, deco")
		expect(
			string.find(
				chromeSource,
				"local writesImage = (not nativeMode) or (plan ~= nil and plan.localOverride)",
				1,
				true
			) ~= nil
		).toBe(true)
		expect(string.find(create, "local writeImage = writesImage", 1, true) ~= nil).toBe(true)
		expect(string.find(create, "if plan.tag ~= nil then", 1, true) ~= nil).toBe(true)
		expect(string.find(create, "Enum.ScaleType.Stretch", 1, true) ~= nil).toBe(true)
	end)
end)

describe("screen_target: the focus treatment (source contract)", function()
	-- the LIVE adapter as ONE text: three files since the 200k split
	local source = adapter_source.live()
	local controller = require("@lune/fs").readFile("src/client/theme_controller.luau")

	local function section(fromNeedle: string, toNeedle: string): string
		local from = string.find(source, fromNeedle, 1, true)
		expect(from ~= nil).toBe(true)
		local to = string.find(source, toNeedle, from :: number, true)
		expect(to ~= nil).toBe(true)
		return string.sub(source, from :: number, to :: number)
	end

	it("the ring is no longer painted from a captured constant", function()
		-- THE THEME-BLINDNESS BUG: `stroke.Color = COLOR.accent` was a value
		-- captured at construction, so the ring stayed Studio-Neutral blue under
		-- every package. It is now the active theme's colour, in one place.
		expect(string.find(source, "stroke.Color = COLOR.accent", 1, true)).toBeNil()
		expect(string.find(source, "stroke.Color = focusColor()", 1, true) ~= nil).toBe(true)
		local resolve = section("local function focusColor(): Color3", "\n\tend")
		-- `focusTreatment` is READ THROUGH A CALL since the paint extraction: the
		-- host reassigns it in `setActiveTheme`, so screen_paint takes an accessor
		-- rather than a value it would freeze at construction. Same ruling, and the
		-- capture this pin exists to forbid is now impossible by construction.
		expect(string.find(resolve, "focusTreatment().color or COLOR.accent", 1, true) ~= nil).toBe(true)
	end)

	it("a live theme swap repaints whatever is focused RIGHT NOW", function()
		-- the theme name rides the same transaction the package does — and so
		-- does the SNAPSHOT (semantic icons size from `iconSizes`,
		-- so the metrics have to arrive with the package, not a frame later)
		expect(
			string.find(controller, "pcall(adapter.setThemePackage, activePackage, themeName, next_)", 1, true) ~= nil
		).toBe(true)
		-- ...the adapter recomputes the treatment from it...
		expect(string.find(source, "setActiveTheme(package, themeName)", 1, true) ~= nil).toBe(true)
		-- ...and repaints EVERY live adapter-owned visual rather than waiting for
		-- the next interaction: the focus ring/glow and the toggle's pill alike
		local set = section("function setActiveTheme(package: any?, themeName: string?)", "\n\tend")
		expect(string.find(set, "refreshFocusVisuals()", 1, true) ~= nil).toBe(true)
		expect(string.find(set, "refreshToggleVisuals()", 1, true) ~= nil).toBe(true)
		expect(string.find(set, "activeTheme = theme", 1, true) ~= nil).toBe(true)
		local refresh = section("function refreshFocusVisuals()", "\n\tend")
		expect(string.find(refresh, "adapter.setFocusVisual(handle, true, profile)", 1, true) ~= nil).toBe(true)
	end)

	it("the glow is a named UIShadow, capability-gated, and degrades to the ring", function()
		local focus = section("function adapter.setFocusVisual", "\n\tend\n")
		expect(string.find(focus, 'glow.Name = "FocusGlow"', 1, true) ~= nil).toBe(true)
		expect(string.find(focus, 'Instance.new("UIShadow" :: any)', 1, true) ~= nil).toBe(true)
		-- §8.4: focus is never optional, so an engine without UIShadow rings
		expect(string.find(focus, "and hasUIShadow", 1, true) ~= nil).toBe(true)
		expect(string.find(focus, "styling.normalizeShadow", 1, true) ~= nil).toBe(true)
		-- the two treatments are mutually exclusive: switching tears the other down
		expect(string.find(focus, "if ring ~= nil and (not on or wantGlow) then", 1, true) ~= nil).toBe(true)
		expect(string.find(focus, "if glow ~= nil and (not on or not wantGlow) then", 1, true) ~= nil).toBe(true)
		-- censused in both directions
		expect(string.find(focus, "chromeState.noteFocusGlow(true)", 1, true) ~= nil).toBe(true)
		expect(string.find(focus, "chromeState.noteFocusGlow(false)", 1, true) ~= nil).toBe(true)
		-- the Grip accent-fill branch is themed too, and otherwise untouched
		expect(string.find(focus, "instance.BackgroundColor3 = focusColor()", 1, true) ~= nil).toBe(true)
	end)

	it("blur removes the glow and forgets the handle, so nothing can stick", function()
		local focus = section("function adapter.setFocusVisual", "\n\tend\n")
		expect(string.find(focus, "focusedHandles[handle] = nil", 1, true) ~= nil).toBe(true)
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		expect(string.find(remove, "handle.focusGlow:Destroy()", 1, true) ~= nil).toBe(true)
		expect(string.find(remove, "focusedHandles[handle] = nil", 1, true) ~= nil).toBe(true)
		-- ...and a whole-root teardown, which never calls remove() per node
		local destroyRoot = section("function adapter.destroyRoot(rootHandle: any)", "rootHandle.gui:Destroy()")
		expect(string.find(destroyRoot, "focusedHandles[handle] = nil", 1, true) ~= nil).toBe(true)
		expect(string.find(destroyRoot, "chromeState.noteFocusGlow(false)", 1, true) ~= nil).toBe(true)
	end)

	it("the census exposes the live glow count independently of the ledger", function()
		local census = section("function adapter.chromeCensus", "return census")
		expect(string.find(census, "census.actualFocusGlows = actualFocusGlows", 1, true) ~= nil).toBe(true)
	end)
end)

describe("screen_target: a value control's own paint (source contract)", function()
	-- the LIVE adapter as ONE text: three files since the 200k split
	local source = adapter_source.live()

	-- the chrome/decoration materializer was extracted to a sibling module when
	-- screen_target.luau reached Studio's 200_000-byte Source ceiling. Every
	-- anchor below is unchanged and keeps its strength — `section` looks in both
	-- halves of the adapter for the one that carries the anchor.
	local chromeSource = require("@lune/fs").readFile("src/client/screen_chrome.luau")

	local function section(fromNeedle: string, toNeedle: string): string
		local text = source
		local from = string.find(text, fromNeedle, 1, true)
		if from == nil then
			text = chromeSource
			from = string.find(text, fromNeedle, 1, true)
		end
		expect(from ~= nil).toBe(true)
		local to = string.find(text, toNeedle, from :: number, true)
		expect(to ~= nil).toBe(true)
		return string.sub(text, from :: number, to :: number)
	end

	it("the slot identity tag rides the desired set, independent of skinning", function()
		local tags = section("local function syncTags(handle: any)", "local plan = tag_sync.diff(")
		expect(string.find(tags, "slotHint = if type(handle.decorationHint)", 1, true) ~= nil).toBe(true)
	end)

	it("fallback mode writes the same SOLID fill the rules paint", function()
		local paint = section("local function applySlotNativePaint", "\n\tend")
		expect(string.find(paint, "if nativeMode or not chrome_slots.hasOwnPaint(slot) then", 1, true) ~= nil).toBe(
			true
		)
		-- SOLID: the entire defect is this number
		expect(string.find(paint, "instance.BackgroundTransparency = 0", 1, true) ~= nil).toBe(true)
		-- from the same map sheet_model's SLOT_FILL_TOKEN mirrors
		expect(string.find(paint, "chromeFillOf[slot]", 1, true) ~= nil).toBe(true)
		expect(string.find(paint, "SLOT_ROUND_FALLBACK[slot]", 1, true) ~= nil).toBe(true)
		-- idempotent: syncChrome runs on every classification change
		expect(string.find(paint, "if handle.slotPainted == slot then", 1, true) ~= nil).toBe(true)
	end)

	it("the tag sync is NOT behind the decoration branch (the invisible-thumb bug)", function()
		-- LIVE REGRESSION 2026-07-25. `syncTags` has exactly two triggers for a
		-- node: `applySurface` (which needs a public `surface` prop) and
		-- decoration create/destroy. A hinted node has NO surface by design, so
		-- when the installed package declares no recipe for its slot the function
		-- returned at `plan == nil` before ever reaching the second one — the
		-- `facet-slot-*` tag never landed, nothing matched, and the Frame fell to
		-- `Frame default` transparency 1. Invisible thumb, invisible rail.
		--
		-- It passed under Parchment purely by accident (its recipes create a
		-- decoration, which dragged the tag sync in behind them), which is why
		-- every emission-shaped spec stayed green. This pins the ORDER.
		local sync = section("function syncChrome(handle: any)", "if deco == nil then")
		local tagAt = string.find(sync, "syncTags(handle)\n\t\tend", 1, true)
		local paintAt = string.find(sync, "applySlotNativePaint(instance, slot, handle)", 1, true)
		local earlyReturnAt = string.find(sync, "if plan == nil then", 1, true)
		expect(tagAt ~= nil and paintAt ~= nil and earlyReturnAt ~= nil).toBe(true)
		-- BOTH halves of a hinted node's identity happen before the branch that
		-- can return, or a package without a recipe for that slot loses them
		expect((tagAt :: number) < (earlyReturnAt :: number)).toBe(true)
		expect((paintAt :: number) < (earlyReturnAt :: number)).toBe(true)
		-- and the tag sync is reached from the HINT, never from the decoration
		expect(string.find(sync, "local hintedSlot = if type(handle.decorationHint)", 1, true) ~= nil).toBe(true)
	end)

	it("it paints BEFORE the skinned suppression, never after", function()
		local sync = section("function syncChrome(handle: any)", "syncChromeText(handle, deco")
		local paintAt = string.find(sync, "applySlotNativePaint(instance, slot, handle)", 1, true)
		local suppressAt = string.find(sync, "applySkinnedSuppression(instance, true, handle)", 1, true)
		expect(paintAt ~= nil and suppressAt ~= nil).toBe(true)
		expect((paintAt :: number) < (suppressAt :: number)).toBe(true)
	end)
end)

describe("screen_target: the toggle reads the live palette (source contract)", function()
	-- the LIVE adapter as ONE text: three files since the 200k split
	local source = adapter_source.live()

	local function section(fromNeedle: string, toNeedle: string): string
		local from = string.find(source, fromNeedle, 1, true)
		expect(from ~= nil).toBe(true)
		local to = string.find(source, toNeedle, from :: number, true)
		expect(to ~= nil).toBe(true)
		return string.sub(source, from :: number, to :: number)
	end

	it("BOTH write sites go through the resolver, and neither keeps a constant", function()
		-- APPLICATION, not export: a resolver nothing calls is exactly the shape
		-- of the invisible-thumb bug one round ago
		local apply = section("local function applyToggleValue(handle: any", "\n\tend")
		expect(string.find(apply, "local palette = togglePalette()", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "if on then palette.trackOn else palette.trackOff", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "if on then palette.knobOn else palette.knobOff", 1, true) ~= nil).toBe(true)
		-- the constants that produced the blue pill are GONE from this site
		expect(string.find(apply, "COLOR.accent", 1, true)).toBeNil()
		expect(string.find(apply, "COLOR.surface", 1, true)).toBeNil()
		expect(string.find(apply, "COLOR.content", 1, true)).toBeNil()
		-- and the construction site is born in the live palette too, so a toggle
		-- built under a package is never painted neutral for a frame
		local build = section("local function buildToggleVisual", "handle.knob = knob")
		expect(string.find(build, "track.BackgroundColor3 = togglePalette().trackOff", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "knob.BackgroundColor3 = togglePalette().knobOff", 1, true) ~= nil).toBe(true)
	end)

	it("the resolver falls back to today's constants when no package is installed", function()
		local resolve = section("local function togglePalette()", "\n\tend")
		-- read through a call for the same reason `focusTreatment` is: the host
		-- reassigns `activeTheme` on every swap
		expect(string.find(resolve, "if activeTheme() == nil then", 1, true) ~= nil).toBe(true)
		-- byte-identical to what shipped: accent / surface / content, content
		expect(
			string.find(
				resolve,
				"trackOn = COLOR.accent, trackOff = COLOR.surface, knobOn = COLOR.content, knobOff = COLOR.content",
				1,
				true
			) ~= nil
		).toBe(true)
		-- and it is declared BELOW the COLOR table it captures (the later-locals trap)
		local colorAt = string.find(source, "local COLOR = {", 1, true)
		local resolverAt = string.find(source, "local function togglePalette()", 1, true)
		expect((colorAt :: number) < (resolverAt :: number)).toBe(true)
		-- ...and inside screen_paint TOO, where the resolver actually lives now: the
		-- palette arrives as `ctx.palette` and the check above would still pass on a
		-- paint file that bound it after the resolver, which is the trap itself
		local paint = require("@lune/fs").readFile("src/client/screen_paint.luau")
		local bindAt = string.find(paint, "local COLOR = ctx.palette", 1, true)
		local paintResolverAt = string.find(paint, "local function togglePalette()", 1, true)
		expect(`palette bound: {bindAt ~= nil}`).toBe("palette bound: true")
		expect((bindAt :: number) < (paintResolverAt :: number)).toBe(true)
	end)

	it("a live swap repaints a mounted toggle without touching its value", function()
		local refresh = section("function refreshToggleVisuals()", "\n\tend")
		-- it repaints the state the handle is ALREADY in — it never sets a value
		expect(string.find(refresh, "applyToggleValue(handle, handle.toggleOn == true, true)", 1, true) ~= nil).toBe(
			true
		)
		-- and it is assigned after applyToggleValue, which it calls
		local applyAt = string.find(source, "local function applyToggleValue(handle: any", 1, true)
		local assignAt = string.find(source, "function refreshToggleVisuals()", 1, true)
		expect((applyAt :: number) < (assignAt :: number)).toBe(true)
	end)

	it("a recolour cancels the in-flight tween and snaps, so no stale target lands", function()
		local apply = section("local function applyToggleValue(handle: any", "\n\tend")
		-- a Tween keeps writing its own target until it completes, so a colour set
		-- underneath a running one is overwritten a frame later
		expect(string.find(apply, "handle.toggleTrackTween:Cancel()", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "handle.toggleTrackTween = tween", 1, true) ~= nil).toBe(true)
		-- a retheme snaps: the VALUE did not change, so there is nothing to animate
		expect(string.find(apply, "if retheme == true or isReducedMotion() then", 1, true) ~= nil).toBe(true)
		-- ...and a retheme must not re-run the knob's slide either
		expect(string.find(apply, "if retheme ~= true then", 1, true) ~= nil).toBe(true)
	end)
end)
