--!strict
-- THEME CONTROLLER (ADR-0019 §3/§6/§7; CLIENT-ONLY — the ADR-0003 seam rule
-- applies, and check_boundary enforces that no non-client module requires this).
--
-- One controller owns one render TARGET. `install` materializes the package's
-- own StyleSheet, links it at that target's root, resolves the frozen
-- ThemeSnapshot and commits it as the `themeMetrics` environment fact. From
-- then on a theme change is ONE transaction — `SetDerives` for paint plus
-- `env:set("themeMetrics", …)` for geometry, in a single invocation — so new
-- paint and new geometry land in the same engine frame (feasibility m5) and
-- nothing is rebuilt: mount identity, focus, selection, scroll position, text
-- entry and resource ownership are untouched because the surface RE-SOLVES.
--
--   install(adapter, package, opts?) -> controller
--   controller.swap(themeName)          another theme of the same package
--   controller.swapPackage(pkg, theme?) another package entirely
--   controller.current()                the active theme name
--   controller.inspect()                package/theme/snapshot/fallback/sheet state
--   controller.onChange(fn) -> unsubscribe
--   controller.dumpTokens()             the typed dump `theme_sync` consumes
--   controller.uninstall()              restores the pre-install link + snapshot
--
-- PER-TARGET, NEVER PROCESS-GLOBAL (feasibility m1). Two independently hosted
-- roots hold different packages at once because each owns its sheet and its one
-- StyleLink; swapping one leaves the other byte-stable. A target that cannot
-- expose its root fails INSTALLATION with a capability error naming exactly what
-- is missing — it never silently restyles someone else's tree, and it never
-- half-installs: every capability check runs before the first mutation, so a
-- rejected install leaves both the target and the environment untouched.
--
-- LIVE AUTHORING (ADR-0019 §3, feasibility m4). Metric and font tokens are typed
-- attributes on the package's THEME sheets, which is where a runtime read of the
-- ACTIVE theme can see them — a read of the base sheet does not see a derive's
-- attributes. One `AttributeChanged` connection per install watches them; a
-- supported edit re-resolves the snapshot and commits, so a designer retunes
-- spacing or typography in the Style Editor and the running preview re-solves
-- with no Luau edit. An unknown attribute is ignored with one warn.
--
-- FALLBACK TARGETS. A target painting through the explicit-write path installs
-- too: it gets the whole metric half of the package (that is where every
-- layout-affecting value lives) and its compiled bespoke style is available from
-- `inspect().style` for `screen_target.new({ style = … })`. Runtime repaint of
-- an already-built fallback target is not possible through today's adapter
-- surface (ScreenTarget takes `style` at construction and exposes no setter);
-- see the stage report's decision packet.

local pkgLib = require("../themes/package")
local snapshotLib = require("../themes/snapshot")
local token_sync = require("../themes/token_sync")
local sheet_model = require("../tokens/sheet_model")
local chrome_slots = require("../tokens/chrome_slots")
local defaultStyle = require("../tokens/default_style")
local native_style_default = require("./native_style")
local text_premeasure = require("./text_premeasure")
local text_calibration = require("./text_calibration")

local theme_controller = {}

-- The capability vocabulary a package may require in `compatibility.capabilities`.
-- A closed set on purpose: an unknown requirement can never be satisfied, so it
-- is an authoring error to be reported at install rather than a flag to ignore.
theme_controller.CAPABILITIES = table.freeze({
	-- the metric half: the frozen snapshot on the `themeMetrics` fact. Always
	-- provided — it is pure Luau and needs no engine at all.
	themeMetrics = "the ThemeSnapshot metric authority (always available)",
	-- native StyleSheet paint: a per-package sheet linked at the target root
	nativeStyleSheets = "native StyleSheet paint on a target that owns its root",
	-- opt-in sheet property transitions (progressive enhancement, the native stylesheets work rider)
	styleTransitions = "native paint transitions (opt in per target)",
})

-- native_style's own bookkeeping attributes: present on every sheet, never a
-- theme token, and never worth a warn
local BOOKKEEPING: { [string]: boolean } =
	{ NativeSheetSchema = true, NativeSheetStamp = true, MirrorsAreReadOnlyReference = true }

-- ONE LIVE CONTROLLER PER ENVIRONMENT. The frozen snapshot rides `themeMetrics`,
-- and that is a SINGLE fact: two controllers on one environment take turns
-- overwriting it, and whichever uninstalls last restores its own stale
-- pre-install value over the other's live theme. Per-TARGET isolation is
-- unaffected — two independently hosted roots hold two environments, which is
-- what makes them independent in the first place. Weak keys, so a discarded
-- environment never pins its controller alive.
local liveControllers: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

-- Metric sections whose values are LENGTHS or DURATIONS. A negative one is not a
-- smaller value; it is a corrupt solve (a negative inset un-reserves space the
-- decoration is still painting over), so a sheet edit that produces one is
-- dropped rather than resolved.
local NON_NEGATIVE_SECTIONS: { [string]: boolean } = {
	insets = true,
	space = true,
	radii = true,
	strokes = true,
	motion = true,
	controlSizes = true,
	controls = true,
}

-- ===== package -> sheet model ==============================================

local function mergedExtra(theme: any): any
	-- a package theme's `extra` is optional and may be partial; the library's own
	-- values fill the rest so a package never has to restate interaction chrome
	-- it did not intend to change
	local out: any = {}
	for k, v in (defaultStyle :: any).extra do
		out[k] = v
	end
	if type(theme.extra) == "table" then
		for k, v in theme.extra do
			out[k] = v
		end
	end
	return out
end

-- the compiled-style shape the sheet model and the bespoke adapter both speak,
-- assembled from ONE theme of a package (its palette) plus the package's
-- package-level metrics
function theme_controller.styleFor(package: any, themeName: string?, displaySize: string?): any
	local name = themeName or package.style.defaultTheme
	local theme: any = nil
	for _, entry in package.style.themes do
		if entry.name == name then
			theme = entry
		end
	end
	assert(theme ~= nil, `theme_controller: package '{package.identity.id}' has no theme named '{tostring(name)}'`)
	-- the PAINT FAMILY at this display class (director ruling 2026-08-21): the
	-- bespoke path writes `radii`/`strokes` from this table, so it takes the same
	-- derivation the sheet's literals and the measured snapshot take
	local metrics = package.metrics
	local paint = snapshotLib.paintForDisplay(metrics, displaySize, pkgLib.pixelUnitOf(package))
	local typeSizes: { [string]: number } = {}
	for role, entry in metrics.typography do
		typeSizes[role] = entry.size
	end
	return {
		colors = theme.colors,
		extra = mergedExtra(theme),
		type = typeSizes,
		space = metrics.space,
		radii = paint.radii,
		strokes = paint.strokes,
		targetSizes = metrics.targetSizes,
		motion = metrics.motion,
		shadows = (defaultStyle :: any).shadows,
	}
end

-- sheetModelFor(package): the PURE sheet model for a package's palette. Exposed
-- rather than inlined so the chrome package and the Studio authoring tools build
-- the same model this controller materializes, from the same one function.
function theme_controller.sheetModelFor(package: any, displaySize: string?): any
	-- buildPackage, never the legacy build(): the package builder carries the
	-- package's own typography fonts, chrome/slot rules, gradients and the
	-- metric repaint map. The legacy builder's font is a BuilderSans constant —
	-- routing a package through it painted every themed screen in the wrong
	-- face while the solver measured the right one (found live, TP matrix
	-- 2026-07-25: exact-Fondamento boxes clipping BuilderSans glyphs).
	-- …and the display class rides along, because the corner a television paints
	-- is 1.5x the corner a phone paints and the sheet is where that literal lives
	return sheet_model.buildPackage(package, { displaySize = displaySize })
end

-- the per-package sheet name. NEVER "Facet": that is the library ModuleScript
-- tree's name under ReplicatedStorage, and a same-name lookup once found (and
-- the old replace path destroyed) the library itself.
function theme_controller.sheetNameFor(package: any): string
	return `FacetTheme {package.identity.id}`
end

-- ===== fonts ===============================================================

-- every distinct canonical descriptor the package declares, sorted
function theme_controller.fontDescriptors(package: any): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, entry in package.metrics.typography do
		local key = snapshotLib.fontKey(entry.font)
		if not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

-- ===== the dump the sync CLI consumes ======================================

function theme_controller.dumpFromRecords(package: any, themeName: string, records: { any }): any
	return {
		schema = token_sync.SCHEMA,
		package = {
			id = package.identity.id,
			displayName = package.identity.displayName,
			schemaVersion = package.identity.schemaVersion,
			version = package.identity.version,
		},
		theme = themeName,
		stamp = package.stamp,
		tokens = records,
	}
end

-- the committed package's own values, with no sheet involved: the baseline a
-- freshness check compares against and the fixture the CLI's tests use
function theme_controller.dumpFromPackage(package: any, themeName: string?): any
	return theme_controller.dumpFromRecords(
		package,
		themeName or package.style.defaultTheme,
		token_sync.records(package)
	)
end

-- ===== install =============================================================

export type Opts = {
	env: any, -- REQUIRED: the snapshot rides it as the `themeMetrics` fact
	theme: string?, -- initial theme; default package.style.defaultTheme
	facts: any?, -- explicit resolve facts; default read from the environment
	overrides: { [string]: any }?, -- deliberate per-screen metric opt-outs
	rootGui: Instance?, -- the target's root, when the adapter cannot say
	host: Instance?, -- explicit sheet host (else ADR-0018's host policy)
	sheetModel: any?, -- a prebuilt sheet model (else sheetModelFor)
	nativeStyle: any?, -- the materializer seam (tests and tools inject it)
	forceFallback: boolean?, -- exercise the fallback path deliberately
	transitions: boolean?, -- opt into native paint transitions
	-- PROFILE-CONDITIONAL SELECTION (ADR-0020 R7): { touch = pkg, pointer = pkg,
	-- gamepad = pkg }, keyed on the interaction classes ADR-0015 publishes. The
	-- positional `package` argument is the default for any unmapped profile.
	selectBy: { [string]: any }?,
	core: any?, -- REQUIRED with selectBy: the paradigm subscription needs a scope
	selectBySettleSeconds: number?, -- default SELECT_BY_SETTLE_SECONDS
	selectBySettle: ((seconds: number, fn: () -> ()) -> () -> ())?, -- test seam
	preflightFonts: boolean?, -- default true
	calibrate: ((keys: { string }) -> { [string]: number })?,
	fontFiles: { [string]: string }?, -- family -> engine font file
	warn: ((message: string) -> ())?,
}

-- ===== profile-conditional selection (ADR-0020 R7) =========================
--
-- The vocabulary IS the existing interaction-class set (ADR-0015). Nothing here
-- detects anything: the environment already decides, live and hybrid-aware,
-- which class is primary; `selectBy` only says which package each class wants.
theme_controller.SELECT_BY_CLASSES = table.freeze({ "touch", "pointer", "gamepad" })

-- How long a profile has to HOLD before it counts as settled. A hybrid device
-- flaps — a handheld with a pad attached reports touch and gamepad in the same
-- second, and the engine's own PreferredInput is known to lag reality — and a
-- package swap per flap would be a visible strobe of two whole skins. One swap
-- per settlement, spec-pinned.
theme_controller.SELECT_BY_SETTLE_SECONDS = 0.25

-- Which CAPABILITY fact each interaction class is backed by. `interactionClasses`
-- deliberately forces the preferred class live even when its capability
-- disagrees (a hybrid needs `primary` to be in the set), so the raw class set
-- cannot answer "does this device actually have a mouse".

-- profileOf(env, _warnFn?) -> "touch" | "pointer" | "gamepad" | nil. PURE apart
-- from the read: the classification is the environment's, this only names the
-- winner. `warnFn` is kept in the signature for its callers and is no longer
-- used — see the note in the body for why the tiebreaker it warned about moved.
function theme_controller.profileOf(env: any, _warnFn: ((string) -> ())?): string?
	local ok, classes = pcall(function()
		return env:get("interactionClasses"):get()
	end)
	if not ok or type(classes) ~= "table" then
		return nil
	end
	local named: string? = nil
	local primary = (classes :: any).primary
	for _, name in theme_controller.SELECT_BY_CLASSES do
		if primary == name then
			named = name
		end
	end
	if named == nil then
		return nil
	end
	-- THE CAPABILITY TIEBREAKER THAT USED TO LIVE HERE IS GONE (2026-07-29).
	-- platform-F3 found a touch-only phone installing the 22px compact-POINTER
	-- package because `PreferredInput` still read KeyboardAndMouse, and it was
	-- patched HERE — one consumer of a wrong fact correcting it for itself, with a
	-- warning, while every other consumer kept the wrong answer. The device report
	-- of 2026-07-29 was the same defect wearing a different symptom: the Table's row
	-- height took the pointer description, so a phone booted with 36px rows and
	-- reflowed to 48px on the first touch, taking the page's canvas and its
	-- scrollbar with it.
	--
	-- `interactionClasses` now resolves the primary from CAPABILITY when no
	-- preference has been expressed (see env/environment.luau), so the fact arrives
	-- correct and this compensation is unreachable. One rule, at the source.
	return named
end

-- the settle timer, injectable. Roblox has `task.delay`; a headless run has no
-- scheduler at all, so the specs hand in a fake one and drive the clock — which
-- is the only way the flap case is assertable without a real frame loop.
local function defaultSettleDelay(seconds: number, fn: () -> ()): () -> ()
	if task ~= nil and type((task :: any).delay) == "function" then
		local thread = (task :: any).delay(seconds, fn)
		return function()
			pcall(function()
				(task :: any).cancel(thread)
			end)
		end
	end
	-- no scheduler: settle immediately. A headless caller that wants to observe
	-- the debounce passes `opts.selectBySettle` instead of relying on this.
	fn()
	return function() end
end

local function defaultWarn(message: string)
	if type(warn) == "function" then
		(warn :: any)(message)
	else
		print(message)
	end
end

function theme_controller.install(adapter: any, package: any, opts: Opts?): any
	local o: any = opts or {}
	assert(type(adapter) == "table", "theme_controller.install: expected a render target adapter")
	assert(
		type(package) == "table" and package.schema == pkgLib.SCHEMA,
		"theme_controller.install: expected a package compiled by themes.define"
	)
	local env = o.env
	assert(
		type(env) == "table" and type(env.set) == "function" and type(env.get) == "function",
		"theme_controller.install: opts.env is required — the effective metrics ride the environment "
			.. 'as the "themeMetrics" fact, which is what makes a swap one atomic commit'
	)
	local warnFn: (string) -> () = o.warn or defaultWarn
	local nativeStyle: any = o.nativeStyle or native_style_default

	-- (0b) PROFILE-CONDITIONAL SELECTION (ADR-0020 R7). `selectBy` is a
	-- DECLARATION, not a new detector: its vocabulary is exactly the
	-- interaction-class names ADR-0015 already publishes, and the initial resolve
	-- happens HERE — before the mode, the root, the sheet or the snapshot are
	-- touched — so the package this controller installs is the profile's package
	-- from the first frame rather than the default package plus a swap.
	--
	-- The positional `package` argument stays the DEFAULT: a profile the map does
	-- not name gets it, which is what makes `selectBy = { touch = glossy }` a
	-- legal one-line authoring shape rather than a demand for three packages.
	local selectBy: any = o.selectBy
	local selectByProfile: string? = nil
	-- resolved pre-boundary (runtime-F4) so the observe below cannot be the first
	-- thing that fails after the install has already mutated
	local selectByClasses: any = nil
	-- the capability tiebreaker says its piece ONCE per controller (platform-F3)
	local tiebreakWarned = false
	-- the POSITIONAL argument, captured before the resolve below can replace it.
	-- `package` becomes the profile's package, and an unmapped profile arriving
	-- LATER has to fall back to what the caller actually passed — not to whichever
	-- mapped package happened to install first (live-found by the spec).
	local selectByDefault: any = package
	if selectBy ~= nil then
		assert(
			type(selectBy) == "table",
			"theme_controller.install: opts.selectBy must be a table keyed by interaction class — "
				.. `\{ {table.concat(theme_controller.SELECT_BY_CLASSES, " = <package>, ")} = <package> }`
		)
		for key, entry in selectBy do
			local known = false
			for _, name in theme_controller.SELECT_BY_CLASSES do
				known = known or name == key
			end
			assert(
				known,
				`theme_controller.install: opts.selectBy names '{tostring(key)}', which is not an interaction `
					.. `class — the vocabulary is exactly the classes the environment already publishes `
					.. `({table.concat(theme_controller.SELECT_BY_CLASSES, " | ")}); nothing new is detected`
			)
			assert(
				type(entry) == "table" and entry.schema == pkgLib.SCHEMA,
				`theme_controller.install: opts.selectBy.{tostring(key)} must be a package compiled by `
					.. "themes.define (the swap is the existing atomic swapPackage, so it takes the same input)"
			)
		end
		assert(
			type(o.core) == "table" and type(o.core.observe) == "function",
			"theme_controller.install: opts.selectBy needs opts.core — the rule subscribes to the environment's "
				.. "interaction-class fact, and the subscription has to live and die with this controller"
		)
		-- THE SUBSCRIPTION SEAM, RESOLVED BEFORE THE MUTATION BOUNDARY (runtime
		-- verifier F4). The observe call itself has to happen after the controller
		-- exists, but everything about it that can FAIL on caller data —
		-- the readable, its shape, the core's observe — is checked here, where
		-- "nothing was installed and the environment is unchanged" is still true.
		local okClasses, classes = pcall(function()
			return env:get("interactionClasses")
		end)
		assert(
			okClasses and type(classes) == "table" and type((classes :: any).get) == "function",
			"theme_controller.install: opts.selectBy needs the environment's 'interactionClasses' fact and this "
				.. "environment does not publish a readable one — nothing was installed"
		)
		selectByClasses = classes
		selectByProfile = theme_controller.profileOf(env, function(message: string)
			if not tiebreakWarned then
				tiebreakWarned = true
				warnFn(message)
			end
		end)
		local chosen = if selectByProfile ~= nil then selectBy[selectByProfile] else nil
		if chosen ~= nil then
			package = chosen
		end
	end

	-- (1) SCHEMA. Checked before anything is touched: a package built against a
	-- schema this build does not speak cannot be partially honored.
	local declared = package.identity.schemaVersion or package.compatibility.requiresSchema
	if declared ~= nil and declared ~= pkgLib.SCHEMA then
		error(
			`theme_controller.install: package '{package.identity.id}' declares schema '{tostring(declared)}' `
				.. `but this Facet speaks '{pkgLib.SCHEMA}' — republish the package against this schema`,
			0
		)
	end

	-- (2) MODE. Native paint needs the engine, a target that is not already
	-- painting bespoke, and a root this controller may link at.
	local mode = "native"
	local fallbackReason: string? = nil
	if o.forceFallback == true then
		mode, fallbackReason = "fallback", "opts.forceFallback"
	elseif type(nativeStyle.available) ~= "function" or not nativeStyle.available() then
		mode, fallbackReason = "fallback", "the engine has no StyleSheet support"
	else
		local info = if type(adapter.nativeStyleInfo) == "function" then adapter.nativeStyleInfo() else nil
		if type(info) ~= "table" then
			mode, fallbackReason =
				"fallback", "the adapter does not report native paint (no nativeStyleInfo on this target)"
		elseif info.active ~= true then
			mode, fallbackReason = "fallback", "the target renders through the explicit-write (bespoke) paint path"
		end
	end

	-- (3) ROOT. Per-target isolation is one sheet plus one StyleLink at the
	-- target's root (m1); without a root there is nothing to isolate, and
	-- installing anyway would restyle whatever tree happened to be linked.
	local rootGui: Instance? = o.rootGui
	if mode == "native" and rootGui == nil and type(adapter.themeRootGui) == "function" then
		rootGui = adapter.themeRootGui()
	end
	if mode == "native" and rootGui == nil then
		error(
			`theme_controller.install: package '{package.identity.id}' needs the target's root Gui and this `
				.. "target cannot expose one — pass opts.rootGui, or implement adapter.themeRootGui(). "
				.. "Per-target theming is one StyleSheet plus one StyleLink at the root (ADR-0019 §7); "
				.. "nothing was installed and the environment is unchanged",
			0
		)
	end

	-- (4) CAPABILITIES, against what this mode actually provides.
	local provided: { [string]: boolean } = {
		themeMetrics = true,
		nativeStyleSheets = mode == "native",
		-- transitions are PROGRESSIVE ENHANCEMENT and default OFF (their publish
		-- status is the open the native stylesheets work rider), so the engine merely being present is
		-- not provision: a target provides them only when it OPTED IN. Reporting
		-- them as provided on every native target meant a package that REQUIRES
		-- transitions installed happily onto a target that would never run one.
		styleTransitions = mode == "native" and o.transitions == true,
	}
	local required: { string } = if type(package.compatibility) == "table"
			and type(package.compatibility.capabilities) == "table"
		then package.compatibility.capabilities
		else {}
	for _, capability in required do
		if theme_controller.CAPABILITIES[capability] == nil then
			local known: { string } = {}
			for name in theme_controller.CAPABILITIES do
				table.insert(known, name)
			end
			table.sort(known)
			error(
				`theme_controller.install: package '{package.identity.id}' requires an unknown capability `
					.. `'{tostring(capability)}' — this build knows: {table.concat(known, ", ")}`,
				0
			)
		end
		if not provided[capability] then
			error(
				`theme_controller.install: package '{package.identity.id}' requires the capability `
					.. `'{capability}' ({theme_controller.CAPABILITIES[capability]}) and this target does not `
					.. `provide it ({tostring(fallbackReason)}) — nothing was installed and the environment `
					.. "is unchanged",
				0
			)
		end
	end

	-- (5) THE INITIAL THEME. Validated HERE, before the first mutation: a bad
	-- `opts.theme` used to reach the resolver only after the sheet had been
	-- materialized and the one StyleLink repointed, so a typo left a
	-- half-installed target behind — the exact failure every other check in this
	-- function is ordered to prevent.
	local initialTheme: string = o.theme or package.style.defaultTheme
	do
		local known = false
		local names: { string } = {}
		for _, entry in package.style.themes do
			table.insert(names, entry.name)
			known = known or entry.name == initialTheme
		end
		if not known then
			error(
				`theme_controller.install: package '{package.identity.id}' has no theme `
					.. `'{tostring(initialTheme)}' — declared themes: {table.concat(names, ", ")}. `
					.. "Nothing was installed and the environment is unchanged",
				0
			)
		end
	end

	-- (6) ONE LIVE CONTROLLER PER ENVIRONMENT (see `liveControllers` above).
	do
		local incumbent = liveControllers[env]
		if incumbent ~= nil then
			error(
				`theme_controller.install: this environment already has a live theme controller (package `
					.. `'{tostring(incumbent.packageId)}', theme '{tostring(incumbent.theme)}'), and the `
					.. "ThemeSnapshot rides the single 'themeMetrics' fact — the two would overwrite each other. "
					.. "Uninstall that controller first, or give this target its own environment. Nothing was "
					.. "installed and the environment is unchanged",
				0
			)
		end
	end

	-- ===== from here on the install MUTATES ================================

	for family, file in o.fontFiles or {} do
		text_premeasure.registerFontFamily(family, file)
	end

	local activePackage = package
	local activeTheme: string = initialTheme
	local handle: any = nil
	local link: any = nil
	local model: any = nil
	local packageRecords: { any } = token_sync.records(activePackage)
	local recordsByAttribute: { [string]: any } = token_sync.indexByAttribute(packageRecords)
	local ignored: { [string]: boolean } = {}
	local warned: { [string]: boolean } = {}
	local warnedRules: { [string]: boolean } = {}
	local warnedOverrides: { [string]: boolean } = {}
	local warnedListeners: { [any]: boolean } = {}
	local fontStates: { [string]: string } = {}
	local fontFlights: { [string]: boolean } = {}
	local listeners: { (any) -> () } = {}
	local unwatch: (() -> ())? = nil
	local connections = 0
	local swaps = 0
	local disposed = false
	local inCommit = false
	local snapshot: any = nil
	local sheetOverrideMap: { [string]: any } = {}
	-- the whole-target relink seam (screen_target.relinkThemeSheet): when the
	-- adapter has it, EVERY live root follows the package sheet — a root created
	-- after install, or a modal opened after a swap, would otherwise keep
	-- pointing at whatever sheet it inherited at birth
	local relinked = false

	-- the registry record the NEXT install would name in its refusal; kept
	-- current so the message names the theme actually running
	local registration = { packageId = package.identity.id, theme = initialTheme }
	liveControllers[env] = registration

	-- the state to put back on uninstall, captured BEFORE the first mutation
	local preInstallSnapshot = env:get("themeMetrics"):get()
	local preInstallLinkSheet: any = nil
	local createdLink = false

	local function rebuildIgnored()
		table.clear(ignored)
		for name in BOOKKEEPING do
			ignored[name] = true
		end
		if model ~= nil then
			-- Step 2's color tokens live on the same theme sheet and are the
			-- SHEET's own authored paint: an edit repaints natively with no Luau
			-- involvement, so it is deliberately ignored here rather than warned
			for _, theme in model.themes do
				for tokenName in theme.tokens do
					ignored[tokenName] = true
				end
			end
		end
	end

	--[[ THE DISPLAY CLASS, read the way every other fact this controller spends
		is read: the injected `facts` win (a headless caller states its own world),
		then the live environment, then nothing. Declared HERE rather than inside
		`factsForResolve` below because the SHEET needs it too — a television's
		corners are painted 1.5x from the same number the snapshot measures with —
		and `materializeFor` runs above that function.

		THE LIVE-ENVIRONMENT FALLBACK READS `effectiveDisplaySize`, NOT the raw
		fact (director item 5, ADR-0058): a PC handheld's engine-reported "Large"
		must not paint console-scaled corners. `o.facts` is left exactly as a
		caller states it — an explicit world (headless test, preview) is not the
		engine's own uncorroborated guess and is never second-guessed here. ]]
	local function displaySizeFact(): any
		if o.facts ~= nil then
			return (o.facts :: any).displaySize
		end
		local ok, value = pcall(function()
			return env:get("effectiveDisplaySize"):get()
		end)
		return if ok then value else nil
	end

	-- materializeFor(pkg, theme, records) -> (handle, model). Takes its inputs
	-- EXPLICITLY rather than reading the active-* locals, so `swapPackage` can
	-- prove a whole new package materializes before anything about this
	-- controller changes.
	local function materializeFor(pkg: any, themeName: string, records: { any }): (any, any)
		local built = o.sheetModel or theme_controller.sheetModelFor(pkg, displaySizeFact())
		local made = nativeStyle.ensure(built, {
			host = o.host,
			theme = themeName,
			sheetName = theme_controller.sheetNameFor(pkg),
			tokens = records,
			mirrors = false, -- retired for packages: the attributes ARE the source
			transitionsEnabled = o.transitions == true,
		})
		return made, built
	end

	local function factsForResolve(): any
		if o.facts ~= nil then
			return o.facts
		end
		local function fact(key: string): any
			local ok, value = pcall(function()
				return env:get(key):get()
			end)
			return if ok then value else nil
		end
		return {
			-- effectiveDisplaySize, not the raw fact — see displaySizeFact above
			displaySize = fact("effectiveDisplaySize"),
			preferredTextSize = fact("preferredTextSize"),
			preferredTextOffset = fact("preferredTextOffset"),
		}
	end

	-- SANITATION. A sheet attribute is a free-text field in the Style Editor, so
	-- a designer can type anything into it — and a NaN, an infinity or a negative
	-- length reaching the resolver corrupts every solve on the target with
	-- nothing naming the cause. A violation drops THAT override (the package's own
	-- value stands) and warns once, naming attribute and reason; the rest of the
	-- edit is honored, because one bad number should not discard a designer's
	-- whole session.
	local function sanitizeOverrides(raw: { [string]: any }, themeName: string): { [string]: any }
		local out: { [string]: any } = {}
		for path, value in raw do
			local reason: string? = nil
			if type(value) == "number" then
				if value ~= value then
					reason = "is not a number (NaN)"
				elseif value == math.huge or value == -math.huge then
					reason = "is infinite"
				elseif string.match(path, "^type%.[^%.]+%.size$") ~= nil then
					if value < 1 then
						reason = `is {value}: a type size below 1px can be neither measured nor drawn`
					end
				elseif string.match(path, "^type%.[^%.]+%.lineHeight$") ~= nil then
					if value <= 0 then
						reason = `is {value}: a line-height factor must be positive`
					end
				else
					local section = string.match(path, "^([^%.]+)")
					if section ~= nil and NON_NEGATIVE_SECTIONS[section] and value < 0 then
						reason = `is {value}: {section} values are lengths or durations and may never be negative`
					end
				end
			end
			if reason == nil then
				out[path] = value
			else
				local attribute = token_sync.attributeForPath(packageRecords, path)
				if not warnedOverrides[attribute] then
					warnedOverrides[attribute] = true
					warnFn(
						`Facet theme '{activePackage.identity.id}': attribute '{attribute}' on theme sheet `
							.. `'{themeName}' {reason} — the edit was DROPPED and the package's own value stands. `
							.. "Fix the attribute in the Style Editor and the edit applies on the next change."
					)
				end
			end
		end
		return out
	end

	-- the designer's edits, as snapshot override paths, read from the sheet of
	-- the theme being resolved TO. Reading the ACTIVE theme's sheet instead was a
	-- real defect: `swap("Light")` applied Dark's authored edits to Light, so a
	-- designer's Dark retune silently followed them into every other theme.
	-- Only tokens that DIFFER from the package's own value are emitted, so an
	-- untouched sheet resolves exactly as the committed package does and the
	-- resolver's composition (display policy, floors, chrome insets) stays intact.
	local function readSheetOverridesFor(pkg: any, themeName: string, h: any, records: { any }): { [string]: any }
		if h == nil or type(h.readTokens) ~= "function" then
			return {}
		end
		local read = h.readTokens(themeName, records)
		local overrides = sanitizeOverrides(token_sync.overridesFromRecords(read, records), themeName)
		-- a nineSlice slot's content insets are composed into the snapshot's
		-- inset BEFORE overrides run, so an edited inset (which states the
		-- AUTHORED number, the one the attribute was seeded with) must re-add
		-- them or the override would silently drop the recipe's reservation
		for path, value in overrides do
			local slot, side = string.match(path, "^insets%.([^%.]+)%.(.+)$")
			if slot ~= nil and type(value) == "number" then
				local recipe = (pkg.chrome :: any)[slot]
				if recipe ~= nil and recipe.kind == "nineSlice" and type(recipe.contentInsets) == "table" then
					overrides[path] = value + (recipe.contentInsets[side] or 0)
				end
			end
		end
		return overrides
	end

	-- resolveWith: the whole resolve against an EXPLICIT package/theme/handle, so
	-- a staged package swap can fail before it is published
	local function resolveWith(pkg: any, themeName: string, h: any, records: { any }): (any, { [string]: any })
		local overrides = readSheetOverridesFor(pkg, themeName, h, records)
		local merged: { [string]: any } = {}
		for path, value in overrides do
			merged[path] = value
		end
		-- an explicit local override is the screen's deliberate opt-out and wins
		-- over any authored value, sheet-edited or not (ADR-0019 §2 step 5)
		for path, value in o.overrides or {} do
			merged[path] = value
		end
		return snapshotLib.resolve(pkg, themeName, factsForResolve(), if next(merged) ~= nil then merged else nil),
			overrides
	end

	local function notify(reason: string)
		local event = {
			reason = reason,
			packageId = activePackage.identity.id,
			theme = activeTheme,
			snapshot = snapshot,
		}
		-- SNAPSHOT the list before iterating: the commonest listener shape is
		-- "react once, then unsubscribe", and removing an entry mid-iteration made
		-- the generalized `for` skip the NEXT listener entirely. And PCALL each: a
		-- listener is an observer, so one that throws must not abort the swap that
		-- already committed, nor rob its siblings of the event. Warned once per
		-- listener — a listener that throws usually throws every time.
		for _, listener in table.clone(listeners) do
			local ok, err = pcall(listener, event)
			if not ok and not warnedListeners[listener] then
				warnedListeners[listener] = true
				warnFn(
					`Facet theme '{activePackage.identity.id}': an onChange listener errored ({tostring(err)}). `
						.. "The theme change itself completed; this listener will not be reported again."
				)
			end
		end
	end

	local function stopWatching()
		if unwatch ~= nil then
			unwatch()
			unwatch = nil
			connections -= 1
		end
	end

	-- forward declarations: the token watcher preflights a newly authored font
	-- descriptor, and the preflight commits — so the two call each other
	local onAttributeChanged: (string) -> ()
	local preflightFonts: () -> ()
	local watchedHandle: any = nil
	local watchedTheme: string? = nil

	-- exactly one live connection, moved when (and only when) the sheet or the
	-- active theme changes: the tokens being authored are the ACTIVE theme's, and
	-- rebinding on every edit would churn a connection inside its own handler
	local function startWatching()
		if handle ~= nil and watchedHandle == handle and watchedTheme == activeTheme then
			return
		end
		stopWatching()
		watchedHandle, watchedTheme = nil, nil
		if handle == nil or type(handle.watchTokens) ~= "function" then
			return
		end
		unwatch = handle.watchTokens(activeTheme, function(attribute: string)
			onAttributeChanged(attribute)
		end)
		watchedHandle, watchedTheme = handle, activeTheme
		connections += 1
	end

	-- FONT materialization for a rule prop. Engine-gated: on a client this builds
	-- the real Font the rule needs; headless (Lune, the fake handle) it hands back
	-- the plain descriptor, which is also what the specs assert.
	local fontCtor: any = (function()
		local ok, ctor = pcall(function()
			return (Font :: any).new
		end)
		return if ok then ctor else nil
	end)()
	local enumRoot: any = (function()
		local ok, root = pcall(function()
			return Enum
		end)
		return if ok then root else nil
	end)()

	local function materializeFont(descriptor: any): any
		local family = tostring(descriptor.family)
		local file = text_premeasure.fontFileFor(family) or family
		if fontCtor == nil or enumRoot == nil then
			return { family = family, file = file, weight = descriptor.weight, style = descriptor.style }
		end
		local weight = if type(descriptor.weight) == "string"
			then (enumRoot :: any).FontWeight[descriptor.weight]
			else nil
		local style = if type(descriptor.style) == "string" then (enumRoot :: any).FontStyle[descriptor.style] else nil
		if weight ~= nil or style ~= nil then
			return fontCtor(
				file,
				weight or (enumRoot :: any).FontWeight.Regular,
				style or (enumRoot :: any).FontStyle.Normal
			)
		end
		return fontCtor(file)
	end

	local udimNew: any = (function()
		local ok, ctor = pcall(function()
			return (UDim :: any).new
		end)
		return if ok then ctor else nil
	end)()

	-- LIVE-EDIT REPAINT (ADR-0019 §3). Corner radii, stroke thickness and the
	-- typography FONT are baked into rules as literals (a number attribute cannot
	-- be a UDim `$Token`, and a Font is not a token type either), so a designer's
	-- sheet edit would re-solve geometry while the paint kept the seeded value.
	--
	-- This runs on a TOKEN EDIT and on nothing else. Running it on every commit
	-- re-pushed the generated value over whatever the designer had since typed
	-- into that rule in the Style Editor — a rule edit that silently reverted on
	-- the next swap, which is exactly the authoring surface this stage promises.
	--[[ …and it pushes the DISTANCE-ADAPTED snapshot (paint-family lockstep,
		2026-08-21). The rules it writes carry the paint family, which now scales at
		ten-foot: pushing the authored ladder here would answer a designer's edit by
		putting a phone's corner on a television, one edit after the sheet was built
		with the right one. `forDisplay` is the same function the environment's
		`themeMetrics` memo applies, so what repaints is what the solver measured. ]]
	local function pushMetricRuleProps(base_: any)
		local next_ = snapshotLib.forDisplay(base_, displaySizeFact())
		if handle == nil or type(handle.setRuleProperty) ~= "function" then
			return
		end
		if model == nil or model.metricRuleProps == nil then
			return
		end
		for _, entry in model.metricRuleProps do
			local value: any = next_
			for part in string.gmatch(entry.path, "[^%.]+") do
				value = if type(value) == "table" then value[part] else nil
			end
			local engineValue: any = nil
			if entry.form == "font" then
				engineValue = if type(value) == "table" then materializeFont(value) else nil
			elseif type(value) == "number" then
				engineValue = if entry.form == "udimOffset"
					then (if udimNew ~= nil then udimNew(0, value) else { scale = 0, offset = value })
					else value
			end
			if engineValue ~= nil then
				local ok = handle.setRuleProperty(entry.rule, entry.prop, engineValue)
				-- honor the boolean: a rule the designer renamed or deleted can
				-- never receive the value again, and silence about that means a
				-- theme whose geometry moves while its paint does not
				if not ok and not warnedRules[entry.rule] then
					warnedRules[entry.rule] = true
					warnFn(
						`Facet theme '{activePackage.identity.id}': rule '{entry.rule}' is not on the theme sheet, `
							.. `so the live edit to '{entry.path}' could not repaint '{entry.prop}'. Geometry follows `
							.. "the edit; paint does not. Restore the rule's name in the Style Editor."
					)
				end
			end
		end
	end

	-- THE SWAP TRANSACTION (ADR-0019 §7, feasibility m5). The snapshot is
	-- resolved FIRST so a bad theme name or a bad override throws before
	-- anything is committed; then the derive swap and the metric commit happen
	-- in ONE invocation with no yield between them, which is what makes new
	-- paint and new geometry land in the same engine frame. Geometry is never
	-- animated: `env:set` drives a solve, and only paint may ride a transition.
	local function commitBody(reason: string, themeName: string, staged: any?)
		local next_: any, overrides: { [string]: any }
		if staged ~= nil then
			next_, overrides = staged.snapshot, staged.overrides
		else
			next_, overrides = resolveWith(activePackage, themeName, handle, packageRecords)
		end
		-- EVERYTHING THIS COMMIT IS ABOUT TO REPLACE (runtime verifier F3). The
		-- decoration call below is the one step in this transaction that runs
		-- FOREIGN code, and a throw there used to leave the controller saying one
		-- package while the environment said another, permanently — every later
		-- swap re-entered the same throw with no path back.
		local prevTheme, prevSnapshot, prevOverrides = activeTheme, snapshot, sheetOverrideMap
		local prevRegPackage, prevRegTheme = registration.packageId, registration.theme
		sheetOverrideMap = overrides
		if handle ~= nil then
			handle.setTheme(themeName)
		end
		activeTheme = themeName
		snapshot = next_
		registration.packageId, registration.theme = activePackage.identity.id, themeName
		-- the DECORATION half of the package, inside the same transaction and
		-- BEFORE the metric commit: the chrome recipes and the geometry that
		-- reserves room for them have to land in one frame, or a skin appears a
		-- frame before the insets that clear its border (or the reverse).
		-- Feature-detected: a target with no decoration surface simply has none.
		if type(adapter.setThemePackage) == "function" then
			-- the THEME NAME rides along: the focus treatment's colour is a
			-- per-theme token ("$FocusGlow"), so the adapter needs both halves,
			-- and it gets them inside this one transaction rather than from two
			-- calls that could disagree for a frame
			-- ...and the SNAPSHOT as the third argument (ADR-0020 R4): semantic
			-- icons size from `iconSizes`, which is metric authority, and the
			-- adapter must not have to read it back out of the environment a
			-- moment later — a metric package that resizes icons would then paint
			-- one frame at the previous package's icon size.
			local okDeco, decoErr = pcall(adapter.setThemePackage, activePackage, themeName, next_)
			if not okDeco then
				-- PUT IT ALL BACK, then re-raise. `staged.rollback` is the caller's
				-- half (which package, which sheet, which handle — swapPackage
				-- moved those before it ever called commit); the rest is this
				-- function's own. Nothing has been published to the environment
				-- yet, so after this the controller, the env and the adapter all
				-- still describe the SAME previous package.
				sheetOverrideMap = prevOverrides
				snapshot = prevSnapshot
				activeTheme = prevTheme
				registration.packageId, registration.theme = prevRegPackage, prevRegTheme
				if staged ~= nil and type(staged.rollback) == "function" then
					staged.rollback()
				end
				if handle ~= nil then
					pcall(handle.setTheme, prevTheme)
				end
				startWatching() -- the restored handle keeps its live-edit seam
				error(decoErr, 0)
			end
		end
		env:set("themeMetrics", next_)
		startWatching() -- the tokens now being authored are the NEW theme's
		if reason == "tokenEdit" then
			pushMetricRuleProps(next_)
		end
		if type(adapter.setThemeStyle) == "function" then
			-- a fallback target that CAN take a new style at runtime gets one;
			-- today's ScreenTarget cannot (see the module header)
			adapter.setThemeStyle(theme_controller.styleFor(activePackage, themeName, displaySizeFact()))
		end
		notify(reason)
	end

	local function commit(reason: string, themeName: string, staged: any?)
		if inCommit then
			-- A listener OBSERVES a commit; it may not drive one. Re-entering here
			-- would recurse until the stack gave out, and the intermediate states
			-- an outer commit is halfway through publishing are not a thing any
			-- listener can reason about.
			error(
				`theme_controller: theme swap feedback loop — a change listener asked for another theme change `
					.. `('{reason}') while a commit was still running. Observe the commit and schedule the swap `
					.. "instead of driving it from the notification.",
				0
			)
		end
		inCommit = true
		local ok, err = pcall(commitBody, reason, themeName, staged)
		inCommit = false
		if not ok then
			error(err, 0)
		end
	end

	function onAttributeChanged(attribute: string)
		if disposed then
			return
		end
		local record = recordsByAttribute[attribute]
		if record ~= nil then
			commit("tokenEdit", activeTheme)
			if record.kind == "font" then
				-- the new descriptor is as unmeasured as any other: preflight it,
				-- or the estimator's conservative full-em path stands forever
				preflightFonts()
			end
			return
		end
		if ignored[attribute] or warned[attribute] then
			return
		end
		warned[attribute] = true
		local families: { [string]: boolean } = {}
		for name in recordsByAttribute do
			families[string.match(name, "^[^_]+_") or name] = true
		end
		local prefixes: { string } = {}
		for prefix in families do
			table.insert(prefixes, prefix)
		end
		table.sort(prefixes)
		warnFn(
			`Facet theme '{activePackage.identity.id}': '{attribute}' on theme sheet '{activeTheme}' is not a `
				.. `supported theme token and was ignored. The supported set is the {#packageRecords} metric/font `
				.. `token attributes this package seeded ({table.concat(prefixes, "")}…); `
				.. "controller.inspect().tokens lists every one"
		)
	end

	-- the descriptors actually in force. Read from the SNAPSHOT, not the package,
	-- so a designer's font-token edit preflights the face they just chose.
	local function currentFontDescriptors(): { string }
		if snapshot == nil or type(snapshot.type) ~= "table" then
			return theme_controller.fontDescriptors(activePackage)
		end
		local seen: { [string]: boolean } = {}
		local out: { string } = {}
		for _, entry in snapshot.type do
			local key = entry.fontKey or snapshotLib.fontKey(entry.font)
			if not seen[key] then
				seen[key] = true
				table.insert(out, key)
			end
		end
		table.sort(out)
		return out
	end

	function preflightFonts()
		local wanted: { string } = {}
		for _, key in currentFontDescriptors() do
			if fontStates[key] == nil then
				-- until a descriptor is measured the estimator's conservative
				-- full-em path stands: over-reserved, never clipped
				fontStates[key] = "pending"
			end
			-- "unavailable" is RETRIED on the next package swap: a family can be
			-- registered after the fact (opts.fontFiles is per install), so a
			-- one-shot refusal would strand the theme on the estimator forever.
			-- An IN-FLIGHT descriptor is never re-launched: two rapid swapPackage
			-- calls used to spawn two calibration runs for the same font.
			if fontStates[key] ~= "calibrated" and not fontFlights[key] then
				table.insert(wanted, key)
			end
		end
		if o.preflightFonts == false or #wanted == 0 then
			return
		end
		local calibrate = o.calibrate
		local scheduled = false
		if calibrate == nil then
			if type(task) ~= "table" then
				return -- no engine scheduler: the conservative path simply stands
			end
			calibrate = text_calibration.run
			scheduled = true
		end
		for _, key in wanted do
			fontFlights[key] = true
		end
		local function release()
			for _, key in wanted do
				fontFlights[key] = nil
			end
		end
		local function run()
			-- WARM FIRST, THEN MEASURE. Engine text bounds are wrong-but-STABLE in
			-- the session's boot window, so a calibration taken there is
			-- permanently wrong — the warm-up is what gets the engine past it, and
			-- it used to run AFTER calibration, which is no help at all.
			if disposed then
				return
			end
			pcall(text_premeasure.warmUp)
			if disposed then
				return -- resumption point: the controller died while we yielded
			end
			local ok, applied = pcall(calibrate :: any, wanted)
			release()
			if disposed then
				return -- resumption point: never write through a dead controller
			end
			if not ok then
				warnFn(
					`Facet theme '{activePackage.identity.id}': font calibration failed ({tostring(applied)}); `
						.. "the conservative estimator stands, so text is over-reserved rather than clipped"
				)
				return
			end
			local calibrated = false
			for _, key in wanted do
				if type(applied) == "table" and type(applied[key]) == "number" then
					fontStates[key] = "calibrated"
					calibrated = true
				else
					fontStates[key] = "unavailable"
				end
			end
			if calibrated then
				-- THE one bounded relayout. Measurement just changed underneath the
				-- solver and nothing else would ever ask it to look again, so the
				-- surface re-solves exactly once, here.
				commit("fontsCalibrated", activeTheme)
			end
		end
		if scheduled then
			(task :: any).spawn(run)
		else
			-- an injected calibrator is the caller's to schedule
			run()
		end
	end

	-- ===== go ==============================================================

	if mode == "native" then
		handle, model = materializeFor(activePackage, activeTheme, packageRecords)
		rebuildIgnored()
		if type(adapter.relinkThemeSheet) == "function" then
			-- whole-target relink: every root the adapter owns, including the ones
			-- it has not created yet
			adapter.relinkThemeSheet(handle.sheet)
			relinked = true
		else
			local made, previous, created = nativeStyle.linkAt(rootGui :: any, handle.sheet)
			link, preInstallLinkSheet, createdLink = made, previous, created
		end
	end
	-- ===== INSTALL-POLICY PRELOAD (ADR-0020 R2) ===========================
	--
	-- The ADR says a variant map's assets "join the package's existing
	-- install/lazy preload seam; PreloadAsync belt-and-braces by default". The
	-- package half of that shipped — `chrome_slots.assetsToPreload` is real and
	-- specced — but NOTHING ever asked for the list, so the shipped default was
	-- no preload at all and rich-skinning v2's preload numbers were list lengths (platform
	-- verifier F2).
	--
	-- It is an OPTS SEAM, not an unconditional fetch: this module is engine-free
	-- and the transport is the caller's (`roblox_resources.bind(provider)` on a
	-- real client, nothing at all in a headless run). With a provider, every
	-- install-policy content id is requested once; without one the step is
	-- lazily skipped and the framework claims nothing about warm caches.
	local preloadReleases: { () -> () } = {}
	local preloadScope = {
		own = function(_self: any, fn: () -> ())
			table.insert(preloadReleases, fn)
		end,
	}
	local function releasePreload()
		local queue = preloadReleases
		preloadReleases = {}
		for _, release in queue do
			pcall(release)
		end
	end
	local preloadCount = 0
	local function requestPreload(pkg: any)
		local provider: any = o.resources
		if type(provider) ~= "table" or type(provider.acquire) ~= "function" then
			return
		end
		releasePreload() -- the previous package's art is no longer this screen's
		preloadCount = 0
		-- ONE request per distinct CONTENT ID. `assetsToPreload` dedupes by asset
		-- NAME, and two names may legitimately point at the same upload (a shared
		-- plate reused by two slots) — asking the transport for it twice is a
		-- wasted round trip on a cold retail client, which is the whole case this
		-- exists for.
		local seen: { [string]: boolean } = {}
		for _, entry in chrome_slots.assetsToPreload(pkg, "install") do
			if not seen[entry.contentId] then
				seen[entry.contentId] = true
				preloadCount += 1
				-- the handle registers its own release on our scope shim
				pcall(provider.acquire, preloadScope, entry.contentId)
			end
		end
	end

	commit("install", activeTheme)
	requestPreload(activePackage)
	preflightFonts()

	local controller = {}
	-- the selectBy subscription and its inspectable state. Declared here so
	-- `uninstall` and `inspect` — both defined below — can see them whether or not
	-- the rule was installed at all (a later local is not an upvalue).
	local selectByUnsubscribe: (() -> ())? = nil
	local selectByState: (() -> any)? = nil
	-- cancels the settle timer in flight, if any (runtime verifier F6: a live
	-- `task.delay` closure keeps a disposed controller reachable for its window)
	local selectByCancelSettle: (() -> ())? = nil
	-- called by `swapPackageInternal` after a MANUAL swap has actually succeeded
	-- (runtime-F2). nil until selectBy is installed, so a controller without the
	-- rule pays nothing.
	local noteManualSwap: (() -> ())? = nil
	-- the deferred subscribe (runtime-F4), run as the last act of install
	local subscribeSelectBy: (() -> ())? = nil

	local function assertLive()
		assert(not disposed, "theme_controller: this controller was uninstalled")
	end

	function controller.current(): string
		return activeTheme
	end

	function controller.snapshot(): any
		return snapshot
	end

	function controller.swap(themeName: string)
		assertLive()
		local known = false
		for _, entry in activePackage.style.themes do
			known = known or entry.name == themeName
		end
		if not known then
			local names: { string } = {}
			for _, entry in activePackage.style.themes do
				table.insert(names, entry.name)
			end
			error(
				`theme_controller.swap: package '{activePackage.identity.id}' has no theme `
					.. `'{tostring(themeName)}' — declared themes: {table.concat(names, ", ")}`,
				0
			)
		end
		swaps += 1
		commit("swap", themeName)
	end

	-- THE ONE PACKAGE-SWAP PATH (platform verifier F9). `selectBy` used to
	-- monkey-patch `controller.swapPackage` and keep a reference to the original,
	-- which made "was this swap manual?" depend on WHICH function reference the
	-- caller happened to hold — latent today, a real trap for any future
	-- internal caller. It is now one function with an explicit origin.
	local function swapPackageInternal(nextPackage: any, themeName: string?, origin: string)
		assertLive()
		assert(
			type(nextPackage) == "table" and nextPackage.schema == pkgLib.SCHEMA,
			"theme_controller.swapPackage: expected a package compiled by themes.define"
		)
		local declaredNext = nextPackage.identity.schemaVersion or nextPackage.compatibility.requiresSchema
		if declaredNext ~= nil and declaredNext ~= pkgLib.SCHEMA then
			error(
				`theme_controller.swapPackage: package '{nextPackage.identity.id}' declares schema `
					.. `'{tostring(declaredNext)}' but this Facet speaks '{pkgLib.SCHEMA}'`,
				0
			)
		end
		for _, capability in
			(if type(nextPackage.compatibility) == "table"
					and type(nextPackage.compatibility.capabilities) == "table"
				then nextPackage.compatibility.capabilities
				else {}) :: { string }
		do
			if not provided[capability] then
				error(
					`theme_controller.swapPackage: package '{nextPackage.identity.id}' requires the capability `
						.. `'{tostring(capability)}' and this target does not provide it — the installed package `
						.. "is unchanged",
					0
				)
			end
		end
		-- THE THEME NAME, before any mutation. A name the new package does not
		-- declare used to flip `activePackage`/`activeTheme`, stop the watcher and
		-- materialize a sheet, and only THEN throw from the resolver — leaving a
		-- controller whose identity said one thing, whose sheet said another, and
		-- whose `inspect()` threw. Nothing below this point may fail on the
		-- package's own data.
		local nextTheme = themeName or nextPackage.style.defaultTheme
		do
			local known = false
			local names: { string } = {}
			for _, entry in nextPackage.style.themes do
				table.insert(names, entry.name)
				known = known or entry.name == nextTheme
			end
			if not known then
				error(
					`theme_controller.swapPackage: package '{nextPackage.identity.id}' has no theme `
						.. `'{tostring(nextTheme)}' — declared themes: {table.concat(names, ", ")}. `
						.. "The installed package is unchanged",
					0
				)
			end
		end
		-- STAGED. Everything that can throw runs against locals: the records, the
		-- sheet materialization, and the whole resolve. Only once all three have
		-- succeeded do the controller's identity fields move, and the watcher is
		-- never disarmed before that point — so a failure here leaves a fully
		-- working controller on the package it already had.
		local nextRecords = token_sync.records(nextPackage)
		local nextByAttribute = token_sync.indexByAttribute(nextRecords)
		local nextHandle, nextModel = handle, model
		if mode == "native" then
			nextHandle, nextModel = materializeFor(nextPackage, nextTheme, nextRecords)
		end
		local nextSnapshot, nextOverrides = resolveWith(nextPackage, nextTheme, nextHandle, nextRecords)

		-- ----- published; nothing below may fail on package data --------------
		-- ...except the adapter's decoration commit, which runs foreign code. The
		-- identity this swap is about to move is captured so that ONE step can be
		-- undone (runtime verifier F3); everything else here is our own data.
		local prevPackage, prevRecords, prevByAttribute = activePackage, packageRecords, recordsByAttribute
		local prevHandle, prevModel = handle, model
		if mode == "native" then
			stopWatching()
		end
		activePackage = nextPackage
		activeTheme = nextTheme
		packageRecords = nextRecords
		recordsByAttribute = nextByAttribute
		handle, model = nextHandle, nextModel
		table.clear(warned)
		table.clear(warnedRules)
		table.clear(warnedOverrides)
		local function relinkCurrent()
			if mode == "native" then
				rebuildIgnored()
				if relinked then
					adapter.relinkThemeSheet(handle.sheet)
				elseif link ~= nil then
					link.StyleSheet = handle.sheet
				end
			end
		end
		relinkCurrent()
		swaps += 1
		commit("swapPackage", nextTheme, {
			snapshot = nextSnapshot,
			overrides = nextOverrides,
			rollback = function()
				activePackage = prevPackage
				packageRecords = prevRecords
				recordsByAttribute = prevByAttribute
				handle, model = prevHandle, prevModel
				swaps -= 1
				relinkCurrent()
			end,
		})
		requestPreload(activePackage)
		preflightFonts()
		if origin == "manual" and noteManualSwap ~= nil then
			-- ONLY after the swap actually landed (runtime-F2): a rejected manual
			-- swap must not suppress selectBy, and must not spend the once-only
			-- warning the next valid caller needs.
			noteManualSwap()
		end
	end

	function controller.swapPackage(nextPackage: any, themeName: string?)
		swapPackageInternal(nextPackage, themeName, "manual")
	end

	-- ===== selectBy: the live half (ADR-0020 R7) ===========================
	--
	-- Everything above is unchanged machinery. This wraps it: one subscription to
	-- the environment's interaction-class fact, one debounce, and the EXISTING
	-- atomic `swapPackage` as the only way a package ever changes. Mount, focus
	-- and scroll identity are therefore held BY CONSTRUCTION — there is no second
	-- swap path that could tear where the first does not.
	if selectBy ~= nil then
		local settleSeconds = if type(o.selectBySettleSeconds) == "number"
			then o.selectBySettleSeconds
			else theme_controller.SELECT_BY_SETTLE_SECONDS
		local settle: (seconds: number, fn: () -> ()) -> () -> () = o.selectBySettle or defaultSettleDelay
		local applied: string? = selectByProfile
		local pendingGeneration = 0
		local cancelPending: (() -> ())? = nil
		local manualOverride = false
		local warnedManual = false
		local profileSwaps = 0

		-- A MANUAL swapPackage WINS until the next profile change, and says so
		-- once. Predictability over cleverness: a caller who swaps by hand while
		-- selectBy is installed has asked for something the rule cannot know
		-- about, and silently reverting it on the next flap would be a ghost.
		--
		-- Latched by `swapPackageInternal` AFTER the swap has landed (runtime-F2):
		-- a swap rejected pre-mutation (bad schema, missing theme, unprovided
		-- capability) changed nothing, so it must suppress nothing either.
		noteManualSwap = function()
			manualOverride = true
			if not warnedManual then
				warnedManual = true
				warnFn(
					"Facet theme_controller: swapPackage was called by hand while `selectBy` is active. The manual "
						.. "package stands until the input profile next changes, and then selectBy resumes. Remove "
						.. "`selectBy`, or drive the profile, if the manual package should be permanent."
				)
			end
		end

		local function applyProfile(profile: string?)
			applied = profile
			manualOverride = false
			local wanted = if profile ~= nil then selectBy[profile] else nil
			-- an unmapped profile falls back to the POSITIONAL default package,
			-- deterministically, rather than keeping whatever the last mapped
			-- profile happened to install
			local target = wanted or selectByDefault
			if target == activePackage then
				return
			end
			profileSwaps += 1
			swapPackageInternal(target, nil, "profile")
		end

		local function onProfileChanged()
			if disposed then
				return
			end
			pendingGeneration += 1
			local generation = pendingGeneration
			if cancelPending ~= nil then
				cancelPending()
				cancelPending = nil
			end
			cancelPending = settle(settleSeconds, function()
				if disposed or generation ~= pendingGeneration then
					return -- a later flap superseded this one: ONE swap per settlement
				end
				cancelPending = nil
				-- THE CLASSIFIED PROFILE, READ HERE (runtime verifier F1). The
				-- notification is not the fact: `interactionClasses` is a memo
				-- returning a fresh table per recompute under identity equality,
				-- so ANY capability write fires this observer — a pad connecting
				-- on a pointer-primary desktop, a keyboard fact arriving. What
				-- decides is whether the CLASS the profile resolves to actually
				-- moved, and reading it at settle time also means the value is the
				-- one that survived the debounce rather than the one that started
				-- it.
				local settled = theme_controller.profileOf(env, function(message: string)
					if not tiebreakWarned then
						tiebreakWarned = true
						warnFn(message)
					end
				end)
				if settled == applied then
					-- NOT a profile change. Critically this also leaves a manual
					-- override alone: revoking the operator's package because an
					-- unrelated capability flag moved is the exact ghost the
					-- manual-wins rule exists to prevent.
					return
				end
				applyProfile(settled)
			end)
		end

		selectByCancelSettle = function()
			if cancelPending ~= nil then
				cancelPending()
				cancelPending = nil
			end
		end

		-- The readable was resolved and validated pre-boundary (runtime-F4); this
		-- call is the only remaining post-boundary failure point. It is deferred
		-- to the very END of install — after `uninstall` exists — so a throw
		-- unwinds through the ordinary teardown instead of leaving a
		-- half-installed controller nobody holds a handle to.
		subscribeSelectBy = function()
			local okObserve, observeResult = pcall(function()
				return o.core:observe(selectByClasses, onProfileChanged)
			end)
			if not okObserve then
				controller.uninstall()
				error(
					`theme_controller.install: opts.selectBy could not subscribe to the environment's `
						.. `interaction-class fact ({tostring(observeResult)}) — the install was unwound and the `
						.. "environment is back where it started",
					0
				)
			end
			selectByUnsubscribe = observeResult :: any
		end
		selectByState = function(): any
			return {
				classes = theme_controller.SELECT_BY_CLASSES,
				mapped = (function()
					local out: { [string]: string } = {}
					for key, entry in selectBy do
						out[key] = entry.identity.id
					end
					return out
				end)(),
				defaultPackage = selectByDefault.identity.id,
				profile = applied,
				liveProfile = theme_controller.profileOf(env),
				manualOverride = manualOverride,
				settleSeconds = settleSeconds,
				swaps = profileSwaps,
				subscribed = selectByUnsubscribe ~= nil,
			}
		end
	end

	function controller.onChange(fn: (any) -> ()): () -> ()
		assertLive()
		assert(type(fn) == "function", "theme_controller.onChange: expected a function")
		table.insert(listeners, fn)
		return function()
			for index, entry in listeners do
				if entry == fn then
					table.remove(listeners, index)
					return
				end
			end
		end
	end

	-- the client-callable dump the theme-authoring scenario exposes and the
	-- `theme_sync` CLI consumes: the ACTIVE theme sheet's tokens, typed, in
	-- deterministic order (feasibility m6)
	function controller.dumpTokens(): any
		assertLive()
		local records = if handle ~= nil and type(handle.readTokens) == "function"
			then handle.readTokens(activeTheme, packageRecords)
			else packageRecords
		return theme_controller.dumpFromRecords(activePackage, activeTheme, records)
	end

	function controller.inspect(): any
		if disposed then
			-- A disposed controller reports its disposal rather than describing a
			-- target it no longer drives. Enough shape survives for a diagnostic
			-- reader (who it WAS, what it left behind) and nothing that would read
			-- as still-installed.
			return {
				disposed = true,
				mode = mode,
				fallback = mode ~= "native",
				package = { id = activePackage.identity.id, version = activePackage.identity.version },
				theme = activeTheme,
				themes = {},
				sheet = { present = false },
				link = { present = false },
				snapshot = snapshot,
				overrides = {},
				tokens = {},
				fonts = {},
				connections = connections,
				swaps = swaps,
			}
		end
		local themeNames: { string } = {}
		for _, entry in activePackage.style.themes do
			table.insert(themeNames, entry.name)
		end
		local tokenNames: { string } = {}
		for _, record in packageRecords do
			table.insert(tokenNames, record.attribute)
		end
		table.sort(tokenNames)
		local fonts: { any } = {}
		for _, key in currentFontDescriptors() do
			table.insert(fonts, { key = key, state = fontStates[key] or "pending" })
		end
		return {
			schema = activePackage.schema,
			supportedSchema = pkgLib.SCHEMA,
			package = {
				id = activePackage.identity.id,
				displayName = activePackage.identity.displayName,
				version = activePackage.identity.version,
				schemaVersion = activePackage.identity.schemaVersion,
				stamp = activePackage.stamp,
			},
			theme = activeTheme,
			themes = themeNames,
			mode = mode,
			fallback = mode ~= "native",
			fallbackReason = fallbackReason,
			capabilities = { provided = provided, required = required },
			sheet = {
				present = handle ~= nil,
				name = if handle ~= nil then handle.sheetName else nil,
				seeded = if handle ~= nil then handle.seeded else nil,
				migrated = if handle ~= nil then handle.migrated else nil,
				stamp = if handle ~= nil then handle.stamp else nil,
			},
			link = { present = relinked or link ~= nil, created = createdLink, whole = relinked },
			snapshot = snapshot,
			style = theme_controller.styleFor(activePackage, activeTheme),
			overrides = sheetOverrideMap,
			tokens = tokenNames,
			fonts = fonts,
			connections = connections,
			swaps = swaps,
			disposed = disposed,
			-- WHAT THE PRELOAD SEAM ACTUALLY DID (platform verifier F2). `requested`
			-- is the number of distinct content ids handed to the resource provider
			-- for THIS package — zero, and `driven = false`, when no provider was
			-- supplied. It is deliberately not the length of a list nobody read.
			preload = { driven = type(o.resources) == "table", requested = preloadCount },
			-- present only when the rule was installed, so "no selectBy" and "a
			-- selectBy that has done nothing" can never be confused (ADR-0020 R7)
			selectBy = if selectByState ~= nil then selectByState() else nil,
		}
	end

	function controller.uninstall()
		if disposed then
			return
		end
		disposed = true
		stopWatching()
		-- the selectBy subscription LIVES AND DIES WITH THIS CONTROLLER (R7). An
		-- observer left behind would keep a disposed controller reachable and
		-- would call swapPackage on it at the next dock/undock.
		if selectByUnsubscribe ~= nil then
			selectByUnsubscribe()
			selectByUnsubscribe = nil
		end
		-- ...and the settle already in flight (runtime verifier F6). The disposed
		-- flag makes the callback a no-op, but a live `task.delay` thread still
		-- holds the whole controller closure reachable for its window.
		if selectByCancelSettle ~= nil then
			selectByCancelSettle()
			selectByCancelSettle = nil
		end
		if liveControllers[env] == registration then
			liveControllers[env] = nil
		end
		if relinked then
			-- nil = put every live root back on the target's legacy sheet
			adapter.relinkThemeSheet(nil)
		elseif link ~= nil then
			-- the sheet itself is left alone: it holds the designer's authored
			-- tokens and seed-once means this controller never destroys them
			if createdLink then
				link:Destroy()
			else
				link.StyleSheet = preInstallLinkSheet
			end
			link = nil
		end
		if type(adapter.setThemePackage) == "function" then
			adapter.setThemePackage(nil)
		end
		-- Restore ONLY what we are still holding. If something else has since
		-- committed to `themeMetrics`, writing our pre-install value back would
		-- silently revert a live theme that has nothing to do with this
		-- controller — the last uninstall winning over the current truth.
		local ok, live = pcall(function()
			return env:get("themeMetrics"):get()
		end)
		if not ok or live == snapshot then
			env:set("themeMetrics", preInstallSnapshot)
		end
		snapshot = preInstallSnapshot
		releasePreload()
		notify("uninstall")
		table.clear(listeners)
	end

	-- THE LAST ACT OF INSTALL (runtime verifier F4). Everything above is either
	-- pre-boundary validation or a mutation this module knows how to undo; the
	-- selectBy subscription is the one step that calls into the caller's core,
	-- and it runs here so `controller.uninstall` is already the escape hatch.
	if subscribeSelectBy ~= nil then
		subscribeSelectBy()
	end

	return controller
end

return theme_controller
