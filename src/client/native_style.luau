--!strict
-- Native StyleSheet materializer (native-stylesheets stage; CLIENT-ONLY, the
-- ADR-0003 seam rule applies — no non-client code may require this). Turns the
-- PURE sheet model (src/tokens/sheet_model.luau) into DataModel instances:
--
--   <host>.LuauUI                (StyleSheet — rules as ordered children,
--                                 mirrors + stamp as attributes)
--   <host>.LuauUI["Theme <name>"] (one StyleSheet per theme; ALL color tokens
--                                 live here — a base-sheet attribute would
--                                 defeat every derive, spike m5/m7)
--
-- SEED-ONCE (§6.9 Fallback B, ledger NSS-A9): if a sheet with this schema
-- already exists, its RULES and THEME TOKENS are left untouched — Style
-- Editor paint edits are the designer's and persist in the place file. Only
-- the layout-reference mirrors and the stamp are refreshed (generator-owned,
-- labeled read-only in the styling guide). A missing sheet is built fresh.
--
-- Transitions (spike m8): declared per state rule from model.rules[].transitions;
-- setTransitionsEnabled(false) strips them via SetPropertyTransitions({}) —
-- the proven instant-change path LuauUI's reducedMotion policy drives.
--
-- THEME PACKAGES (ADR-0019 §3/§7, stage theme-packages-and-skinning): `ensure`
-- is parameterized so a theme PACKAGE materializes its own sheet
-- ("LuauUITheme <id>") beside — never on top of — the shared legacy sheet, with
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

-- THE default-flip toggle (promotion plan, artifacts/native-stylesheets/
-- promotion-readiness.json): when a target passes NO `nativeStyle` opt,
-- screen_target consults this. Flip to `true` to make native paint the
-- default for every screen target once the retail-publish + Team-Test +
-- device rows close; per-target escape hatch stays `nativeStyle = false`.
-- Billboard targets and the edit preview pass their own explicit choice and
-- are unaffected by this flag.
native_style.DEFAULT_ENABLED = false

-- distinct from the library ModuleScript tree (also commonly named "LuauUI"
-- under ReplicatedStorage — live find 2026-07-24: a same-name lookup found the
-- LIBRARY and the old replace path would have destroyed it)
local SHEET_NAME = "LuauUIStyle"
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
-- solver measured SemiBold (ADR-0019 §6 keys measurement on the full descriptor)
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
	-- module is client-only by the ADR-0003 seam rule.
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
	-- theme packages (ADR-0019 §3): typed metric/font tokens on the ACTIVE theme
	-- sheet, and the live-authoring signal that observes designer edits to them
	readTokens: (theme: string, wanted: { any }) -> { any },
	watchTokens: (theme: string, fn: (attribute: string) -> ()) -> () -> (),
	-- merge-write ONE prop on a named live rule (metric live-edit repaint)
	setRuleProperty: (ruleName: string, prop: string, value: any) -> boolean,
}

export type EnsureOpts = {
	host: Instance?, -- explicit override of both lookup and creation host
	-- transitions are PROGRESSIVE ENHANCEMENT and default OFF (platform
	-- verifier 2026-07-24: publish status is the open NSS-P3 rider; the
	-- instant-change path is today's look). Opt in explicitly per target.
	transitionsEnabled: boolean?,
	theme: string?, -- initial theme; default model.defaultTheme
	-- theme packages: the per-package sheet name ("LuauUITheme <id>"). NEVER
	-- "LuauUI" — that is the library ModuleScript tree's name and a same-name
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
	--     PlayerGui — never ReplicatedStorage: a LocalScript-created instance
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

	local host: Instance
	local existing: StyleSheet?
	local stale: StyleSheet? = nil
	if opts and opts.host then
		host = opts.host
		existing, stale = findSheet(host, model.schema, sheetName)
	else
		existing, stale = findSheet(ReplicatedStorage, model.schema, sheetName)
		if existing ~= nil then
			host = ReplicatedStorage
		elseif playerGui ~= nil then
			host = playerGui
			existing, stale = findSheet(playerGui, model.schema, sheetName)
		else
			host = ReplicatedStorage
		end
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
				`LuauUI native-style: model stamp changed ({tostring(sheet:GetAttribute(ATTR_STAMP))} -> {model.stamp}); regenerating rules (theme token edits preserved)`
			)
			for _, child in sheet:GetChildren() do
				if child:IsA("StyleRule") then
					child:Destroy()
				end
			end
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
			buildRules(sheet)
		end
	else
		if stale ~= nil then
			stale:Destroy() -- pre-schema artifact (a StyleSheet, class-checked)
		end
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

	-- typed metric/font tokens (ADR-0019 §3, feasibility m4). BACKFILL ONLY, on
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
	-- is the NSS-P3 rider, and a missing/errored method must degrade to the
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
		-- Merge-writes so a designer's OTHER props on the same rule survive.
		setRuleProperty = function(ruleName: string, prop: string, value: any): boolean
			local r: StyleRule? = nil
			for _, child in sheet:GetChildren() do
				if child:IsA("StyleRule") and child.Name == ruleName then
					r = child
				end
			end
			if r == nil then
				return false
			end
			local ok = pcall(function()
				local props = (r :: StyleRule):GetProperties()
				props[prop] = value;
				(r :: StyleRule):SetProperties(props :: any)
			end)
			return ok
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

-- One StyleLink per LuauUI root (plan §6: single application point per tree)
function native_style.link(rootGui: Instance, sheet: StyleSheet): StyleLink
	local link = Instance.new("StyleLink")
	link.Name = "LuauUIStyleLink"
	link.StyleSheet = sheet
	link.Parent = rootGui
	return link
end

-- linkAt(rootGui, sheet) -> (link, previousSheet, created). Installing a theme
-- package must not ADD a second link beside the shared one: two links means two
-- sheets apply to the same tree and the cascade winner depends on load order.
-- So an existing LuauUI link is REPOINTED at the package sheet and its previous
-- sheet handed back, which is exactly what `uninstall` needs to put the target
-- back the way it found it (ADR-0019 §7 per-target isolation, feasibility m1).
function native_style.linkAt(rootGui: Instance, sheet: StyleSheet): (StyleLink, StyleSheet?, boolean)
	for _, child in rootGui:GetChildren() do
		if child:IsA("StyleLink") and child.Name == "LuauUIStyleLink" then
			local previous = child.StyleSheet
			child.StyleSheet = sheet
			return child, previous, false
		end
	end
	return native_style.link(rootGui, sheet), nil, true
end

return native_style
