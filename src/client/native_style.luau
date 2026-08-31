--!strict
-- Native StyleSheet materializer (native-stylesheets stage; CLIENT-ONLY, the
-- client-seam rule applies — no non-client code may require this). Turns the
-- PURE sheet model (src/tokens/sheet_model.luau) into DataModel instances:
--
--   <host>.Facet                (StyleSheet — rules as ordered children,
--                                 mirrors + stamp as attributes)
--   <host>.Facet["Theme <name>"] (one StyleSheet per theme; ALL color tokens
--                                 live here — a base-sheet attribute would
--                                 defeat every derive, spike m5/m7)
--
-- SEED-ONCE: if a sheet with this schema
-- already exists, its RULES and THEME TOKENS are left untouched — Style
-- Editor paint edits are the designer's and persist in the place file. Only
-- the layout-reference mirrors and the stamp are refreshed (generator-owned,
-- labeled read-only in the styling guide). A missing sheet is built fresh.
--
-- Transitions (spike m8): declared per state rule from model.rules[].transitions;
-- setTransitionsEnabled(false) strips them via SetPropertyTransitions({}) —
-- the proven instant-change path Facet's reducedMotion policy drives.
--
-- THEME PACKAGES: `ensure`
-- is parameterized so a theme PACKAGE materializes its own sheet
-- ("FacetTheme <id>") beside — never on top of — the shared legacy sheet, with
-- per-target isolation (feasibility m1). Two package-only additions:
--   * `tokens`: metric/font tokens land as TYPED ATTRIBUTES on the THEME sheets
--     (m4). Runtime reads must target the ACTIVE theme sheet — `GetAttribute` on
--     the base sheet does not see a derive's attributes.
--   * `mirrors = false`: the reference-only layout mirrors are RETIRED for
--     packages. The attributes above ARE the authored source, so a read-only
--     mirror beside them would be a second, lying copy. The legacy shared sheet
--     keeps its mirrors untouched.
-- Every default reproduces the legacy path byte for byte.

local sheet_model = require("../tokens/sheet_model")
local chrome_props = require("../tokens/chrome_props")
local text_premeasure = require("./text_premeasure")

local native_style = {}

--[[ THE LIBRARY DEFAULT PAINT PATH. When a target passes NO `nativeStyle` opt,
	this is the answer it gets.

	FLIPPED TO `true` ON 2026-08-21 by the game director's ruling, recorded as
	a changelog row (the record is what makes a behaviour change legal on an
	unreleased version). It was `false` for the whole native-stylesheets stage,
	where sheet paint was opt-in per target while the promotion rows closed
	(artifacts/native-stylesheets/promotion-readiness.json).

	WHAT DOES NOT CHANGE. The per-target escape hatch is still an explicit
	`nativeStyle = false`, and it still wins — `resolveOpt` below is the one place
	that decides, so the explicit-write path stays a first-class path with one
	branch rather than a corpse. Billboard targets and the Studio edit preview
	pass their own explicit choice and are unaffected by this flag either way.
]]
native_style.DEFAULT_ENABLED = true

--[[ The `nativeStyle` opt a target was constructed with -> the opt it acts on.
	PURE, and the only reader of `DEFAULT_ENABLED` there is.

	It exists because `screen_target.new` needs a LocalPlayer and a DataModel, so
	a default decided inside it has no headless witness at all — which is how the
	library's most consequential boolean came to have no spec. Three answers:

	  * `nil` (no opt)      -> the library default;
	  * `false`             -> `false`, the per-target escape hatch, untouched;
	  * anything else       -> ITSELF, by identity — `true`, or the config table
	                           whose `handle`/`model`/`host`/`theme`/`transitions`
	                           the caller reads back off the object it passed.

	It never answers `nil`, so the caller's whole condition is `~= false`.
]]
function native_style.resolveOpt(opt: any): any
	if opt == nil then
		return native_style.DEFAULT_ENABLED
	end
	return opt
end

--[[ THE WHOLE PAINT DECISION, as a value a target OBEYS.

	WHY IT IS NOT JUST `resolveOpt`. A fresh-context reviewer broke the first
	version of this seam in one edit: `screen_target` called `resolveOpt`, threw
	the answer away, and re-derived the pre-flip rule underneath — and the entire
	suite stayed green while a bare `screen_target.new({})` painted explicit-write
	again. The spec could see that the adapter MENTIONED the seam; nothing could
	see whether it OBEYED one, because `screen_target.luau` opens with
	`game:GetService("Players")` at module scope and cannot be required headlessly
	by any spec that will ever exist.

	So the decision left the closure entirely. Everything here used to be a branch
	inside `screen_target.new` with no witness:

	  * the DEFAULT — an absent opt is `DEFAULT_ENABLED`;
	  * the ESCAPE HATCH — an explicit `false` refuses, and wins over everything;
	  * the CAPABILITY GATE — an engine without StyleSheets refuses too, even for
	    a caller who asked out loud;
	  * the TRANSITIONS SEED — opt-in per target, with reduced motion overriding
	    the opt, asked for lazily so a target that opted out never calls a
	    consumer's deprecated motion closure at all.

	PURE, because the two engine facts are PARAMETERS. `available` defaults to the
	real probe so the shipped call site stays two arguments; a spec states it,
	which is the only reason the accepting half of every branch above is testable
	(the probe answers `false` off-engine).

	WHAT IT DELIBERATELY DOES NOT CARRY: `handle` and `model`. Those are the
	caller's own objects rather than decisions, and the target reads them off
	`plan.opt` where it builds the sheet, beside the style and display facts only
	it has. A plan field no production line reads is a surface kept alive for a
	test, which is the defect shape this same round found on the consumer side.

	`opt` is the RESOLVED opt, and it is why the pre-flip rule cannot be rebuilt
	from a plan: an absent opt and an explicit `true` are the same value by the
	time a target sees one.

	IT TAKES THE TARGET'S WHOLE `opts` TABLE, not the paint opt, and that is the
	load-bearing part of the signature rather than a convenience. Handed a VALUE, a
	seam can always be handed a DIFFERENT one — a re-review reverted the product
	default in one line by substituting the pre-flip answer into this function's own
	argument (`paintPlan(if raw == nil then false else raw, …)`), with every shape
	pin on the caller satisfied and the whole suite green. Reading the field HERE
	leaves the adapter nothing to substitute: it never holds the opt in any
	spelling, which is a fact a spec can state as a count of zero.
]]
export type PaintPlan = {
	native: boolean, -- take the sheet path at all
	opt: any, -- the resolved opt: `true`, `false`, or the caller's config table
	host: any?, -- where the sheet is seeded
	theme: string?, -- which theme sheet is active at construction
	transitions: boolean, -- the seed for `transitionsEnabled`
}

function native_style.paintPlan(opts: any, isReducedMotion: (() -> boolean)?, available: boolean?): PaintPlan
	local resolved = native_style.resolveOpt(if opts == nil then nil else opts.nativeStyle)
	-- REFUSE BEFORE PROBING. The two-clause gate this replaced short-circuited, so
	-- an opted-out target never ran `Instance.new("StyleSheet")`; computing
	-- `capable` first quietly spent that on every opt-out — the edit preview, every
	-- billboard, every place carrying the rollback. Order is the whole fix.
	if resolved == false then
		return { native = false, opt = resolved, transitions = false }
	end
	local capable = if available == nil then native_style.available() else available == true
	if not capable then
		return { native = false, opt = resolved, transitions = false }
	end
	local config: any = if type(resolved) == "table" then resolved else nil
	local transitions = config ~= nil and config.transitions == true
	if transitions and isReducedMotion ~= nil and isReducedMotion() == true then
		transitions = false
	end
	return {
		native = true,
		opt = resolved,
		host = if config ~= nil then config.host else nil,
		theme = if config ~= nil then config.theme else nil,
		transitions = transitions,
	}
end

-- distinct from the library ModuleScript tree (also commonly named "Facet"
-- under ReplicatedStorage — live find 2026-07-24: a same-name lookup found the
-- LIBRARY and the old replace path would have destroyed it)
local SHEET_NAME = "FacetStyle"
local ATTR_SCHEMA = "NativeSheetSchema"
local ATTR_STAMP = "NativeSheetStamp"
local ATTR_MIRROR_NOTE = "MirrorsAreReadOnlyReference"

function native_style.available(): boolean
	return (pcall(function()
		local probe = Instance.new("StyleSheet")
		probe:Destroy()
	end))
end

local function toColor3(v: any): Color3
	return Color3.new(v.r, v.g, v.b)
end

-- one Font builder for rule props AND typed attributes: a theme's typography
-- token carries weight/style, and dropping them would paint Regular while the
-- solver measured SemiBold
local function toFont(v: any): Font
	local family = tostring(v.family)
	local file = text_premeasure.fontFileFor(family) or family
	local weight: any = nil
	local style: any = nil
	if type(v.weight) == "string" then
		weight = (Enum :: any).FontWeight[v.weight]
	end
	if type(v.style) == "string" then
		style = (Enum :: any).FontStyle[v.style]
	end
	if weight ~= nil or style ~= nil then
		return Font.new(file, weight or Enum.FontWeight.Regular, style or Enum.FontStyle.Normal)
	end
	return Font.new(file)
end

local function materializeProp(v: any): any
	if type(v) == "string" then
		return v -- "$Token" reference (or plain string)
	end
	if v.kind == "color" then
		return toColor3(v)
	elseif v.kind == "udim" then
		return UDim.new(v.scale, v.offset)
	elseif v.kind == "number" then
		return v.value
	elseif v.kind == "font" then
		return toFont(v)
	elseif v.kind == "enum" then
		return (Enum :: any)[v.enum][v.item]
	end
	-- chrome kinds (rect / colorseq / numseq — package rules for nine-slice and
	-- gradient chrome). materialize is engine-gated: on a client it returns the
	-- real datatype; the nil-engine case cannot be reached here because this
	-- module is client-only by the client-seam rule.
	local handled, value = chrome_props.materialize(v)
	if handled then
		return value
	end
	error(`native_style: unknown prop kind '{tostring(v.kind)}'`)
end

-- a theme-sheet PAINT token value -> the engine attribute value. Step 2's model
-- carried only colors here; theme packages add gradient sequences (colorseq /
-- numseq are supported attribute types), and materializeProp covers every
-- remaining kind. "$" strings are rule-side references, never token values.
-- exported (as `native_style.tokenAttributeValue`) so the type refusal below is
-- assertable with no engine attached — the refusal is the whole point of it
local function toTokenAttr(v: any): any
	if v.kind == "color" then
		return toColor3(v)
	end
	if v.kind == "enum" then
		-- SetAttribute does not accept an EnumItem. `materializeProp` would happily
		-- build one (rules DO take enums) and the write would throw from deep
		-- inside the seeder with nothing naming the token — so the refusal is here,
		-- where the token is still identifiable.
		error(
			`native_style: a theme token may not be an enum ('{tostring(v.enum)}.{tostring(v.item)}') — `
				.. "EnumItem is not a supported attribute type. Attributes carry number/bool/string/Color3/UDim/"
				.. "Font/ColorSequence/NumberSequence; an enum belongs in a RULE property, not a theme token",
			0
		)
	end
	return materializeProp(v)
end

native_style.tokenAttributeValue = toTokenAttr

-- a typed token RECORD (src/themes/token_sync) -> the engine value that carries
-- it on a theme sheet. The six kinds are exactly the ones feasibility m6 proved
-- round-trip value-exact.
local function materializeToken(record: any): any
	local kind = record.kind
	if kind == "number" then
		return record.value
	elseif kind == "bool" then
		return record.value == true
	elseif kind == "string" then
		return tostring(record.value)
	elseif kind == "color" then
		return Color3.fromHex(record.hex)
	elseif kind == "udim" then
		return UDim.new(record.scale or 0, record.offset or 0)
	elseif kind == "font" then
		return toFont(record)
	end
	error(`native_style: unknown token kind '{tostring(kind)}'`)
end

-- the inverse: an engine attribute value read back into a typed record, keeping
-- the record's identity (path/attribute/kind) so a dump is directly comparable
-- with the committed package's records
local function readToken(record: any, value: any): any?
	local kind = record.kind
	local out: any = { path = record.path, attribute = record.attribute, kind = kind }
	if kind == "number" then
		if type(value) ~= "number" then
			return nil
		end
		out.value = value
	elseif kind == "bool" then
		if type(value) ~= "boolean" then
			return nil
		end
		out.value = value
	elseif kind == "string" then
		if type(value) ~= "string" then
			return nil
		end
		out.value = value
	elseif kind == "color" then
		if typeof(value) ~= "Color3" then
			return nil
		end
		out.hex = value:ToHex()
	elseif kind == "udim" then
		if typeof(value) ~= "UDim" then
			return nil
		end
		out.scale, out.offset = value.Scale, value.Offset
	elseif kind == "font" then
		if typeof(value) ~= "Font" then
			return nil
		end
		out.family = text_premeasure.familyForFile(value.Family) or value.Family
		out.weight = value.Weight.Name
		out.weightValue = value.Weight.Value
		out.style = value.Style.Name
	else
		return nil
	end
	return out
end

export type Handle = {
	sheet: StyleSheet,
	sheetName: string,
	themes: { [string]: StyleSheet },
	stamp: string,
	seeded: boolean, -- true = this call CREATED the sheet; false = reused existing
	migrated: boolean, -- true = model stamp changed and rules were regenerated
	activeTheme: string,
	setTheme: (name: string) -> (),
	setTransitionsEnabled: (on: boolean) -> (),
	resolveToken: (theme: string, name: string) -> Color3?,
	-- theme packages: typed metric/font tokens on the ACTIVE theme
	-- sheet, and the live-authoring signal that observes designer edits to them
	readTokens: (theme: string, wanted: { any }) -> { any },
	watchTokens: (theme: string, fn: (attribute: string) -> ()) -> () -> (),
	-- merge-write ONE prop on a named live rule (metric live-edit repaint)
	setRuleProperty: (ruleName: string, prop: string, value: any) -> boolean,
}

export type EnsureOpts = {
	host: Instance?, -- explicit override of both lookup and creation host
	-- transitions are PROGRESSIVE ENHANCEMENT and default OFF (platform
	-- verifier 2026-07-24: publish status is the open the native stylesheets work rider; the
	-- instant-change path is today's look). Opt in explicitly per target.
	transitionsEnabled: boolean?,
	theme: string?, -- initial theme; default model.defaultTheme
	-- theme packages: the per-package sheet name ("FacetTheme <id>"). NEVER
	-- "Facet" — that is the library ModuleScript tree's name and a same-name
	-- lookup found (and the old replace path destroyed) the library itself.
	sheetName: string?,
	-- typed metric/font token records written onto EVERY theme sheet, seed-once
	-- (a designer's edit is never overwritten) and backfilled when missing
	tokens: { any }?,
	-- reference-only layout mirrors: on for the legacy shared sheet, RETIRED for
	-- packages (their token attributes are the authored source, not a mirror)
	mirrors: boolean?,
}

local function findSheet(host: Instance, schema: string, sheetName: string): (StyleSheet?, StyleSheet?)
	-- class-checked lookup: NEVER touch a non-StyleSheet that happens to share
	-- the name (live find 2026-07-24: the library ModuleScript tree shares the
	-- host and a name-only lookup destroyed it)
	local existing: StyleSheet? = nil
	local stale: StyleSheet? = nil
	for _, child in host:GetChildren() do
		if child:IsA("StyleSheet") and child.Name == sheetName then
			if child:GetAttribute(ATTR_SCHEMA) == schema then
				existing = child
			else
				stale = child
			end
		end
	end
	return existing, stale
end

function native_style.ensure(model: any, opts: EnsureOpts?): Handle
	-- Host policy (platform verifier 2026-07-24, replication correctness):
	--   * LOOKUP prefers an explicit opts.host, else the designer-seeded sheet
	--     under ReplicatedStorage (Edit-seeded with the place, server-owned,
	--     replicated to every client — the Style Editor workflow home).
	--   * RUNTIME CREATION (no designer sheet found) goes CLIENT-LOCAL —
	--     PlayerGui — never ReplicatedStorage: a client-created instance
	--     there is client-local anyway (FilteringEnabled) and invites name
	--     collisions with replicated content. In Edit (no LocalPlayer) the
	--     seed goes to ReplicatedStorage so it persists with the place.
	-- Per-client mutations (SetDerives theme, attribute edits) on a replicated
	-- designer sheet are client-local under FilteringEnabled — each client may
	-- hold its own theme without cross-client bleed.
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local localPlayer = Players.LocalPlayer
	local playerGui = if localPlayer ~= nil then localPlayer:FindFirstChildOfClass("PlayerGui") else nil
	local sheetName = (opts and opts.sheetName) or SHEET_NAME
	local tokens: { any } = (opts and opts.tokens) or {}
	local mirrorsEnabled = (opts and opts.mirrors) ~= false

	--[[ EVERY WRONG-SCHEMA SHEET FOUND IS DESTROYED, NOT JUST THE LAST ONE
		(2026-08-17). The host search can look in TWO containers, and
		`stale` was a single slot that the second lookup overwrote: a pre-schema
		artifact sitting in ReplicatedStorage survived whenever the PlayerGui
		lookup answered, keeping a sheet with this exact name and the wrong schema
		alive next to the real one — the precise thing the schema check exists to
		clear. Collected instead of assigned, and cleared once the host is
		resolved, in BOTH lookup orders. ]]
	local staleSheets: { StyleSheet } = {}
	local function lookup(container: Instance): StyleSheet?
		local found, staleOne = findSheet(container, model.schema, sheetName)
		if staleOne ~= nil then
			table.insert(staleSheets, staleOne)
		end
		return found
	end

	local host: Instance
	local existing: StyleSheet?
	if opts and opts.host then
		host = opts.host
		existing = lookup(host)
	else
		existing = lookup(ReplicatedStorage)
		if existing ~= nil then
			host = ReplicatedStorage
		elseif playerGui ~= nil then
			host = playerGui
			existing = lookup(playerGui)
		else
			host = ReplicatedStorage
		end
	end
	for _, artifact in staleSheets do
		artifact:Destroy() -- pre-schema artifact (a StyleSheet, class-checked)
	end
	local sheet: StyleSheet
	local seeded = false
	local migrated = false

	-- Cascade is pinned with EXPLICIT Priority (director live find 2026-07-24:
	-- child/creation order does NOT survive the Edit->Play DataModel copy —
	-- a migrated sheet came back with scrambled GetStyleRules order and the
	-- Frame-default rule beat the later Toggle-chrome rule). Priority is the
	-- engine's only serialization-proof cascade mechanism (spike m6: Priority
	-- beats order). Spaced by 10 so a designer can slot custom rules between.
	local function priorityFor(index: number): number
		return index * 10
	end

	local function buildRules(target: StyleSheet)
		for index, rule in model.rules do
			local r = Instance.new("StyleRule")
			r.Name = rule.name
			r.Selector = rule.selector
			r.Priority = priorityFor(index)
			local props = {}
			for k, v in rule.props do
				props[k] = materializeProp(v)
			end
			r:SetProperties(props)
			if r.SelectorError ~= "" then
				error(`native_style: rule '{rule.name}' selector error: {r.SelectorError}`)
			end
			r.Parent = target
		end
	end

	-- generator-owned cascade repair on EVERY apply (like the mirrors): rules
	-- created before this fix carry Priority 0, and designer copies must keep
	-- a deterministic cascade regardless of how the DataModel ordered them
	local function syncPriorities(target: StyleSheet)
		local byName: { [string]: StyleRule } = {}
		for _, child in target:GetChildren() do
			if child:IsA("StyleRule") then
				byName[child.Name] = child
			end
		end
		for index, rule in model.rules do
			local r = byName[rule.name]
			if r ~= nil and r.Priority ~= priorityFor(index) then
				r.Priority = priorityFor(index)
			end
		end
	end

	if existing ~= nil then
		-- SEED-ONCE for designer paint: theme-sheet TOKEN edits are always
		-- preserved. Rules are seed-once only while the framework model is
		-- unchanged — a STAMP mismatch means the model evolved (new/changed
		-- rules), and rules are generator-owned on upgrade: they regenerate
		-- (per-rule designer edits are lost, with a warn), while every theme
		-- sheet is kept and only MISSING tokens are backfilled.
		sheet = existing
		if sheet:GetAttribute(ATTR_STAMP) ~= model.stamp then
			migrated = true
			warn(
				`Facet native-style: model stamp changed ({tostring(sheet:GetAttribute(ATTR_STAMP))} -> {model.stamp}); regenerating rules (theme token edits preserved)`
			)
			for _, child in sheet:GetChildren() do
				if child:IsA("StyleRule") then
					child:Destroy()
				end
			end
			buildRules(sheet)
		end
		--[[ THE THEME CHILDREN ARE ENSURED ON EVERY EXISTING-SHEET PATH
			(2026-08-17). This loop used to live INSIDE the stamp-mismatch branch, so
			it only ran when the model had evolved. A designer who deleted one
			`Theme <name>` child from a sheet whose stamp still matched left the
			sheet looking healthy and `setTheme` asserting `unknown theme '<name>'`
			— a HARD ERROR out of mount, on a place that opens fine in Edit. A
			missing theme child is a hole to fill, not a reason to refuse: recreate
			it and backfill its tokens, which is seed-once either way (a token the
			designer set is authored data and is never overwritten). ]]
		for _, theme in model.themes do
			local ts: StyleSheet? = nil
			for _, child in sheet:GetChildren() do
				if child:IsA("StyleSheet") and child.Name == "Theme " .. theme.name then
					ts = child
				end
			end
			if ts == nil then
				local created = Instance.new("StyleSheet")
				created.Name = "Theme " .. theme.name
				created.Parent = sheet
				ts = created
			end
			for tokenName, v in theme.tokens do
				if (ts :: StyleSheet):GetAttribute(tokenName) == nil then
					(ts :: StyleSheet):SetAttribute(tokenName, toTokenAttr(v))
				end
			end
		end
	else
		seeded = true
		sheet = Instance.new("StyleSheet")
		sheet.Name = sheetName
		sheet:SetAttribute(ATTR_SCHEMA, model.schema)
		-- theme sheets first (tokens), then rules referencing $tokens
		for _, theme in model.themes do
			local ts = Instance.new("StyleSheet")
			ts.Name = "Theme " .. theme.name
			for tokenName, v in theme.tokens do
				ts:SetAttribute(tokenName, toTokenAttr(v))
			end
			ts.Parent = sheet
		end
		buildRules(sheet)
		sheet.Parent = host
	end

	-- generator-owned refresh (every apply): cascade priorities + mirrors +
	-- stamp + note
	syncPriorities(sheet)
	if mirrorsEnabled then
		for _, m in model.mirrors do
			sheet:SetAttribute(m.name, m.value)
		end
		sheet:SetAttribute(ATTR_MIRROR_NOTE, true)
	end
	sheet:SetAttribute(ATTR_STAMP, model.stamp)

	local themes: { [string]: StyleSheet } = {}
	for _, child in sheet:GetChildren() do
		if child:IsA("StyleSheet") then
			local themeName = string.match(child.Name, "^Theme (.+)$")
			if themeName ~= nil then
				themes[themeName] = child
			end
		end
	end

	-- typed metric/font tokens. BACKFILL ONLY, on
	-- every apply: a token the designer has set is authored data and is never
	-- overwritten (seed-once), while a token this build added to the vocabulary
	-- appears immediately instead of reading back nil until the next stamp
	-- change. They live on the THEME sheets because that is where a runtime read
	-- of the ACTIVE theme can see them — the base sheet does not see derives.
	for _, ts in themes do
		for _, record in tokens do
			if ts:GetAttribute(record.attribute) == nil then
				ts:SetAttribute(record.attribute, materializeToken(record))
			end
		end
	end

	local handle: Handle
	local function setTheme(name: string)
		local ts = themes[name]
		assert(ts ~= nil, `native_style: unknown theme '{name}'`)
		sheet:SetDerives({ ts })
		handle.activeTheme = name
	end

	-- transitions: declared from the model so strip/restore is total either way
	local rulesByName: { [string]: StyleRule } = {}
	for _, child in sheet:GetChildren() do
		if child:IsA("StyleRule") then
			rulesByName[child.Name] = child
		end
	end
	-- transitionsOptedIn latches the per-target enhancement opt-in; the LIVE
	-- reducedMotion wiring (renderer) calls setTransitionsEnabled(true) when
	-- RM turns off, which must NOT enable transitions on a target that never
	-- opted in. Calls are pcall-guarded: SetPropertyTransitions publishability
	-- is the native stylesheets work rider, and a missing/errored method must degrade to the
	-- instant path, never fail the mount.
	local transitionsOptedIn = (opts and opts.transitionsEnabled) == true
	local function setTransitionsEnabled(on: boolean)
		local effective = on and transitionsOptedIn
		for _, rule in model.rules do
			if rule.transitions ~= nil then
				local r = rulesByName[rule.name]
				if r ~= nil then
					pcall(function()
						if effective then
							local map = {}
							for prop, motionToken in rule.transitions do
								map[prop] = TweenInfo.new(
									model.motion[motionToken] or model.motion.fast,
									Enum.EasingStyle.Quad,
									Enum.EasingDirection.Out
								)
							end
							(r :: any):SetPropertyTransitions(map)
						else
							(r :: any):SetPropertyTransitions({})
						end
					end)
				end
			end
		end
	end

	handle = {
		sheet = sheet,
		sheetName = sheetName,
		themes = themes,
		stamp = model.stamp,
		seeded = seeded,
		migrated = migrated,
		activeTheme = "",
		setTheme = setTheme,
		setTransitionsEnabled = setTransitionsEnabled,
		-- generator-side single-prop rule update: how a LIVE metric edit reaches
		-- the rules that baked that metric as a literal (model.metricRuleProps).
		-- THIS handle's own sheet; `native_style.setRuleProperty` below is the same
		-- verb on any sheet, which is what a whole-target relink needs.
		setRuleProperty = function(ruleName: string, prop: string, value: any): boolean
			return native_style.setRuleProperty(sheet, ruleName, prop, value)
		end,
		resolveToken = function(theme: string, name: string): Color3?
			local ts = themes[theme]
			if ts == nil then
				return nil
			end
			local v = ts:GetAttribute(name)
			return if typeof(v) == "Color3" then v else nil
		end,
		-- read the wanted tokens off the ACTIVE theme sheet (m4: a read of the
		-- base sheet cannot see them). A token the sheet does not carry, or
		-- carries at the wrong type, falls back to the record it was asked with —
		-- a designer who deletes or retypes an attribute gets the package's value
		-- back, never nil geometry.
		readTokens = function(theme: string, wanted: { any }): { any }
			local ts = themes[theme]
			local out: { any } = {}
			for _, record in wanted do
				local decoded = if ts ~= nil then readToken(record, ts:GetAttribute(record.attribute)) else nil
				table.insert(out, decoded or record)
			end
			return out
		end,
		-- ONE connection per install, not one per token: `AttributeChanged` names
		-- the attribute that changed, which is also the only way to notice an
		-- edit to an attribute nobody subscribed to (GetAttributeChangedSignal
		-- structurally cannot report an UNKNOWN token). Returns its disconnector.
		watchTokens = function(theme: string, fn: (attribute: string) -> ()): () -> ()
			local ts = themes[theme]
			if ts == nil then
				return function() end
			end
			local conn = ts.AttributeChanged:Connect(fn)
			return function()
				conn:Disconnect()
			end
		end,
	} :: Handle

	setTheme((opts and opts.theme) or model.defaultTheme)
	setTransitionsEnabled(transitionsOptedIn)
	return handle
end

--[[ GENERATOR-SIDE RULE-PROP ACCESS, ON A SHEET RATHER THAN ON A HANDLE.

	`handle.setRuleProperty` above is the same verb bound to the handle's own
	sheet, and it is enough for the metric-edit path, where the editor and the
	model are the same object. It is NOT enough for a live PLAYER PREFERENCE: a theme controller relinks the whole target onto a package sheet it
	built itself, so the target's own handle points at a sheet nothing is wearing
	any more, and a patch through it would land on a dead rule and change nothing
	visible. The preference patches `activeSheetFor()` instead — whichever sheet is
	linked right now.

	`ruleProperty` is the READ half, and it exists so the composition never reads
	back its own output: the base a preference composes against is taken from a
	freshly-installed sheet, once, before anything has written to it (a
	composition that reads back its own output is what that rule defends
	against). ]]
function native_style.ruleProperty(sheet: StyleSheet?, ruleName: string, prop: string): any?
	if sheet == nil then
		return nil
	end
	for _, child in sheet:GetChildren() do
		if child:IsA("StyleRule") and child.Name == ruleName then
			local ok, value = pcall(function()
				return (child :: StyleRule):GetProperties()[prop]
			end)
			return if ok then value else nil
		end
	end
	return nil
end

-- Merge-writes, so a designer's OTHER props on the same rule survive.
function native_style.setRuleProperty(sheet: StyleSheet?, ruleName: string, prop: string, value: any): boolean
	if sheet == nil then
		return false
	end
	for _, child in sheet:GetChildren() do
		if child:IsA("StyleRule") and child.Name == ruleName then
			return (
				pcall(function()
					local props = (child :: StyleRule):GetProperties()
					props[prop] = value;
					(child :: StyleRule):SetProperties(props :: any)
				end)
			)
		end
	end
	return false
end

-- One StyleLink per Facet root (plan §6: single application point per tree)
function native_style.link(rootGui: Instance, sheet: StyleSheet): StyleLink
	local link = Instance.new("StyleLink")
	link.Name = "FacetStyleLink"
	link.StyleSheet = sheet
	link.Parent = rootGui
	return link
end

-- linkAt(rootGui, sheet) -> (link, previousSheet, created). Installing a theme
-- package must not ADD a second link beside the shared one: two links means two
-- sheets apply to the same tree and the cascade winner depends on load order.
-- So an existing Facet link is REPOINTED at the package sheet and its previous
-- sheet handed back, which is exactly what `uninstall` needs to put the target
-- back the way it found it.
function native_style.linkAt(rootGui: Instance, sheet: StyleSheet): (StyleLink, StyleSheet?, boolean)
	for _, child in rootGui:GetChildren() do
		if child:IsA("StyleLink") and child.Name == "FacetStyleLink" then
			local previous = child.StyleSheet
			child.StyleSheet = sheet
			return child, previous, false
		end
	end
	return native_style.link(rootGui, sheet), nil, true
end

return native_style
