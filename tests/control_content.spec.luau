--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local sheet = require("../src/tokens/sheet_model")
local slots = require("../src/tokens/chrome_slots")
local Facet = require("../src") :: any
local describe, it, expect = t.describe, t.it, t.expect

describe("generated control content owns its plate's semantic paint", function()
	it("marks only generated primary content, preserving authored accessory roles", function()
		local w = world.new()
		w.present(function()
			local UI = w.UI
			return UI.Screen("S")({
				UI.Button("Delete")({ label = "Delete", icon = "trash", appearance = "utility", role = "destructive" }),
				UI.Button("Close")({
					shape = "circle",
					icon = "close",
					name = "Close",
					appearance = "utility",
					role = "destructive",
				}),
				UI.Chip("Chip")({
					label = "Rain",
					selected = w.Compose.cell(true),
					leading = UI.Text("Accessory")({ text = "3", role = "secondary" }),
				}),
			})
		end)
		expect(
			w.adapter.node("/S/Close").decorationHint and w.adapter.node("/S/Close").decorationHint.contentOwnerDepth
		).toBe(0)
		expect(w.adapter.node("/S/Delete/Label").decorationHint.contentOwnerDepth).toBe(1)
		expect(w.adapter.node("/S/Delete/Icon").decorationHint.contentOwnerDepth).toBe(1)
		expect(w.adapter.node("/S/Chip+target/Chip/Content/Label").decorationHint.contentOwnerDepth).toBe(2)
		-- (its hint carries only the plate it sits on, never an owner)
		expect(w.adapter.node("/S/Chip+target/Chip/Content/Accessory").decorationHint.contentOwnerDepth).toBe(nil)
	end)
	it("emits content text and image colors from each existing vocabulary color rule", function()
		for _, model in
			{
				sheet.build({ themes = { { name = "Dark", style = require("../src/tokens/default_style") } } }),
				sheet.buildPackage(require("../examples/themes/pixel_quest").build(Facet.themes)),
			}
		do
			local named = {}
			for _, rule in model.rules do
				named[rule.name] = rule
			end
			for _, name in { "Emphasis control", "Destructive utility" } do
				local original = named[name]
				expect(original ~= nil).toBe(true)
				expect(named["Control content text — " .. name] ~= nil).toBe(true)
				expect(named["Control content text — " .. name].props.TextColor3).toEqual(original.props.TextColor3)
				expect(named["Control content icon — " .. name].props.ImageColor3).toEqual(original.props.TextColor3)
			end
		end
	end)
end)

-- Executes the production native bridge with a small CollectionService/GuiState
-- fixture. It proves tag ownership and teardown, not GPU or physical input.
local function nativeFixture()
	local bridge = require("../src/client/screen_control_content")
	local allTags, handles = {}, {}
	local live, made = 0, 0
	local service = {}
	function service:GetTags(instance)
		local out = {}
		for tag in allTags[instance] or {} do
			table.insert(out, tag)
		end
		return out
	end
	function service:HasTag(instance, tag)
		return (allTags[instance] or {})[tag] == true
	end
	function service:AddTag(instance, tag)
		allTags[instance] = allTags[instance] or {}
		allTags[instance][tag] = true
	end
	function service:RemoveTag(instance, tag)
		(allTags[instance] or {})[tag] = nil
	end
	local root = {}
	local function handle(path, class, depth)
		local callbacks = {}
		local instance = { GuiState = "Enum.GuiState.Idle" }
		function instance:GetPropertyChangedSignal(property)
			expect(property).toBe("GuiState")
			return {
				Connect = function(_, callback)
					live += 1
					made += 1
					callbacks[callback] = true
					return {
						Disconnect = function()
							if callbacks[callback] then
								live -= 1
								callbacks[callback] = nil
							end
						end,
					}
				end,
			}
		end
		local h = {
			path = path,
			class = class,
			rootHandle = root,
			instance = instance,
			decorationHint = if depth then { contentOwnerDepth = depth } else nil,
		}
		handles[path] = h
		return h,
			function(state)
				instance.GuiState = "Enum.GuiState." .. state
				for callback in callbacks do
					callback()
				end
			end
	end
	local api = bridge.new(service, handles)
	local function classify(h, tags)
		local desired = {}
		for _, tag in tags do
			desired[tag] = true
		end
		api.augment(h, desired)
		allTags[h.instance] = desired
		api.changed(h)
	end
	return {
		api = api,
		service = service,
		handle = handle,
		classify = classify,
		handles = handles,
		live = function()
			return live
		end,
		made = function()
			return made
		end,
	}
end

local function resolved(model, class, tags, state, property)
	local value = nil
	local set = {}
	for _, tag in tags do
		set[tag] = true
	end
	for _, rule in model.rules do
		if rule.props[property] == nil or string.find(rule.selector, "[>%s,]") then
			continue
		end
		local selector = rule.selector
		local requiredClass = string.match(selector, "^([%w]+)")
		if requiredClass and requiredClass ~= class then
			continue
		end
		local requiredState = string.match(selector, ":(%a+)")
		if requiredState and requiredState ~= state then
			continue
		end
		local matches = true
		for tag in string.gmatch(selector, "%.([%w%-]+)") do
			if not set[tag] then
				matches = false
			end
		end
		if matches then
			value = rule.props[property]
		end
	end
	return value
end

local function resolvedLift(model, tags, state, property)
	local value = resolved(model, "TextLabel", { slots.TAGS.text }, "Idle", property)
	local suffix = " > ." .. slots.TAGS.text
	for _, rule in model.rules do
		if string.sub(rule.selector, -#suffix) == suffix then
			local ownerRule = table.clone(rule)
			ownerRule.selector = string.sub(rule.selector, 1, -#suffix - 1)
			local candidate = resolved({ rules = { ownerRule } }, "TextButton", tags, state, property)
			if candidate ~= nil then
				value = candidate
			end
		end
	end
	return value
end

describe("native primary-content paint bridge", function()
	it("follows role, appearance, selection and gated pointer state with sheet-owned text and art", function()
		local f = nativeFixture()
		local owner, state = f.handle("/S/Action", "Button")
		local label = f.handle("/S/Action/Label", "Text", 1)
		local icon = f.handle("/S/Action/Icon", "Text", 1)
		icon.iconInstance, icon.iconContentPaint = {}, true
		f.api.bind(label)
		f.api.bind(icon)
		expect(f.live()).toBe(1)
		local models =
			{ sheet.build({ themes = { { name = "Dark", style = require("../src/tokens/default_style") } } }) }
		for _, theme in { "pixel_quest", "fantasy_ornate" } do
			table.insert(models, sheet.buildPackage(require("../examples/themes/" .. theme).build(Facet.themes)))
		end
		for _, model in models do
			for _, appearance in { "standard", "emphasis", "soft", "utility", "link" } do
				for _, role in { "normal", "destructive", "cancel" } do
					for _, selected in { false, true } do
						for _, guiState in { "Idle", "Hover", "Press", "NonInteractable" } do
							local tags = {}
							for tag in
								sheet.classifyTags({
									surface = "control",
									interactive = true,
									pointerLive = true,
									appearance = appearance,
									selected = selected,
									buttonRole = if role == "normal" then nil else role,
									disabled = guiState == "NonInteractable",
								})
							do
								table.insert(tags, tag)
							end
							f.classify(owner, tags)
							state(guiState)
							f.classify(label, { "facet-type-control" }) -- ordinary prop/tag passes preserve the owner projection
							local expected =
								resolved(model, "TextButton", f.service:GetTags(owner.instance), guiState, "TextColor3")
							expect(expected ~= nil).toBe(true)
							expect(
								resolved(model, "TextLabel", f.service:GetTags(label.instance), "Idle", "TextColor3")
							).toEqual(expected)
							expect(
								resolved(
									model,
									"ImageLabel",
									f.service:GetTags(icon.iconInstance),
									"Idle",
									"ImageColor3"
								)
							).toEqual(expected)
						end
					end
				end
			end
		end
		f.classify(owner, { "facet-role-destructive", "facet-appearance-utility", "facet-pointer-live" })
		state("Hover")
		expect(resolved(models[1], "TextLabel", f.service:GetTags(label.instance), "Idle", "TextColor3")).toBe(
			"$DangerHover"
		)
		f.classify(owner, { "facet-role-destructive", "facet-appearance-utility" })
		expect(resolved(models[1], "TextLabel", f.service:GetTags(label.instance), "Idle", "TextColor3")).toBe(
			"$Danger"
		)
		-- Explicit semantic art tints (danger/status/etc.) are still the package's own.
		icon.iconContentPaint = false
		f.api.changed(icon)
		expect(f.service:HasTag(icon.iconInstance, sheet.CONTENT_ICON_TAG)).toBe(false)
		expect(f.service:HasTag(label.instance, sheet.CONTENT_TEXT_TAG)).toBe(true)
		f.api.clear(owner)
		expect(f.live()).toBe(0)
		expect(f.service:HasTag(label.instance, sheet.CONTENT_TEXT_TAG)).toBe(false)
	end)
	it("explicit plate lettering wins on managed art without changing content alpha or glyph suppression", function()
		local f = nativeFixture()
		local owner, state = f.handle("/S/Action", "Button")
		local icon = f.handle("/S/Action/Icon", "Text", 1)
		icon.iconInstance, icon.iconContentPaint = {}, true
		f.service:AddTag(icon.iconInstance, slots.ICON_PICTURE_TAG)
		f.api.bind(icon)
		for _, model in
			{
				sheet.build({ themes = { { name = "Dark", style = require("../src/tokens/default_style") } } }),
				sheet.buildPackage(require("../src/themes/snapshot").neutralPackage()),
			}
		do
			for _, disabled in { false, true } do
				f.classify(owner, {
					"facet-role-destructive",
					"facet-appearance-utility",
					if disabled then slots.TAGS.stateDisabled else "facet-pointer-live",
				})
				state(if disabled then "NonInteractable" else "Idle")
				for _, role in { "onAccent", "onSuccess", "onWarning", "onDanger", "contentStrong", "content" } do
					f.classify(icon, { slots.TAGS.iconArt, "facet-letters-" .. role })
					local actual, inherited = nil, nil
					for _, rule in model.rules do
						local suffix = " > ." .. slots.ICON_PICTURE_TAG
						local candidate
						if string.sub(rule.selector, -#suffix) == suffix then
							local parentRule = table.clone(rule)
							parentRule.selector = string.sub(rule.selector, 1, -#suffix - 1)
							candidate = resolved(
								{ rules = { parentRule } },
								"TextLabel",
								f.service:GetTags(icon.instance),
								"Idle",
								"ImageColor3"
							)
						else
							candidate = resolved(
								{ rules = { rule } },
								"ImageLabel",
								f.service:GetTags(icon.iconInstance),
								"Idle",
								"ImageColor3"
							)
							if candidate ~= nil then
								inherited = candidate
							end
						end
						if candidate ~= nil then
							actual = candidate
						end
					end
					expect(inherited ~= nil).toBe(true) -- the competing P1a rules really match
					expect(actual).toBe(
						if role == "content" then inherited else "$" .. role:sub(1, 1):upper() .. role:sub(2)
					)
					expect(
						resolved(model, "ImageLabel", f.service:GetTags(icon.iconInstance), "Idle", "ImageTransparency")
							or { kind = "number", value = 0 }
					).toEqual({ kind = "number", value = if disabled then 0.4 else 0 })
					expect(resolved(model, "TextLabel", f.service:GetTags(icon.instance), "Idle", "TextTransparency")).toEqual({
						kind = "number",
						value = 1,
					})
				end
			end
		end
		f.api.clear(owner)
		expect(f.live()).toBe(0)
	end)

	it("dims actual managed art, retracts alpha, and never reveals its suppressed glyph", function()
		local f = nativeFixture()
		local owner, state = f.handle("/S/Action", "Button")
		local icon = f.handle("/S/Action/Icon", "Text", 1)
		icon.iconInstance, icon.iconContentPaint = {}, true
		f.api.bind(icon)
		for _, theme in { "neutral", "pixel_quest", "fantasy_ornate" } do
			local model = if theme == "neutral"
				then sheet.build({ themes = { { name = "Dark", style = require("../src/tokens/default_style") } } })
				else sheet.buildPackage(require("../examples/themes/" .. theme).build(Facet.themes))
			for _, semanticTint in { false, true } do
				icon.iconContentPaint = not semanticTint -- explicit package tint changes no alpha policy
				for _, disabled in { true, false, true } do
					local guiState = if disabled then "NonInteractable" else "Idle"
					f.classify(owner, if disabled then { slots.TAGS.stateDisabled } else {})
					state(guiState)
					f.classify(
						icon,
						if disabled then { slots.TAGS.stateDisabled, slots.TAGS.iconArt } else { slots.TAGS.iconArt }
					)
					local expected = resolved(
						model,
						"TextButton",
						f.service:GetTags(owner.instance),
						guiState,
						"TextTransparency"
					) or { kind = "number", value = 0 }
					local actual = resolved(
						model,
						"ImageLabel",
						f.service:GetTags(icon.iconInstance),
						"Idle",
						"ImageTransparency"
					) or { kind = "number", value = 0 }
					expect(actual).toEqual(expected)
					expect(resolved(model, "TextLabel", f.service:GetTags(icon.instance), "Idle", "TextTransparency")).toEqual({
						kind = "number",
						value = 1,
					})
				end
			end
			-- A no-art theme removes suppression; the original disabled text rule owns the fallback.
			f.classify(icon, { slots.TAGS.stateDisabled })
			expect(resolved(model, "TextLabel", f.service:GetTags(icon.instance), "Idle", "TextTransparency")).toEqual(
				resolved(model, "TextButton", f.service:GetTags(owner.instance), "NonInteractable", "TextTransparency")
			)
		end
		f.api.clear(owner)
		expect(f.live()).toBe(0)
	end)
	it("self-owned circle art follows roles and retraction without projecting tags onto its owner", function()
		local f = nativeFixture()
		local circle, state = f.handle("/S/Close", "Button", 0)
		circle.iconInstance, circle.iconContentPaint = {}, true
		local model = sheet.build({ themes = { { name = "Dark", style = require("../src/tokens/default_style") } } })
		for _ = 1, 4 do
			f.api.bind(circle)
			for _, appearance in { "utility", "emphasis", "standard" } do
				f.classify(
					circle,
					{ "facet-role-destructive", "facet-appearance-" .. appearance, "facet-pointer-live" }
				)
				for _, guiState in { "Idle", "Hover", "Press", "NonInteractable" } do
					state(guiState)
					expect(resolved(model, "ImageLabel", f.service:GetTags(circle.iconInstance), "Idle", "ImageColor3")).toEqual(
						resolved(model, "TextButton", f.service:GetTags(circle.instance), guiState, "TextColor3")
					)
					expect(f.service:HasTag(circle.instance, sheet.CONTENT_TEXT_TAG)).toBe(false)
				end
			end
			f.api.clear(circle)
			expect(f.live()).toBe(0)
		end
	end)
	it("keeps lifted primary Button text on the same role, appearance, selection and state rules", function()
		local LIFT_TOKEN = {
			["$OnAccent"] = "$OnAccentChrome",
			["$Content"] = "$OnControlChrome",
			["$ContentStrong"] = "$OnControlChromeStrong",
			["$ContentSecondary"] = "$OnControlChromeSecondary",
			["$OnDanger"] = "$OnDangerChrome",
		}
		for _, theme in { "pixel_quest", "fantasy_ornate" } do
			local model = sheet.buildPackage(require("../examples/themes/" .. theme).build(Facet.themes))
			for _, appearance in { "standard", "emphasis", "soft", "utility", "link" } do
				for _, role in { "normal", "destructive", "cancel" } do
					for _, selected in { false, true } do
						for _, guiState in { "Idle", "Hover", "Press", "NonInteractable" } do
							local tags = {}
							for tag in
								sheet.classifyTags({
									surface = "control",
									interactive = true,
									pointerLive = true,
									appearance = appearance,
									selected = selected,
									buttonRole = if role == "normal" then nil else role,
								})
							do
								table.insert(tags, tag)
							end
							-- ...except that a lifted label sits on the control's ART, so each
							-- role's colour is the one picked against that art
							local want = resolved(model, "TextButton", tags, guiState, "TextColor3")
							want = if want == "$ContentSecondary" and role == "cancel"
								then "$OnCancelChrome"
								elseif
									string.sub(want, 1, 7) == "$Danger" and role == "destructive"
								then "$OnDangerChrome"
								elseif
									want == "$OnSelected"
									and appearance == "soft"
									and not selected
								then "$OnSoftChrome"
								else LIFT_TOKEN[want] or want
							expect(resolvedLift(model, tags, guiState, "TextColor3")).toEqual(want)
							if guiState == "NonInteractable" then
								expect(resolvedLift(model, tags, guiState, "TextTransparency")).toEqual(
									resolved(model, "TextButton", tags, guiState, "TextTransparency")
								)
							end
						end
					end
				end
			end
		end
	end)
	it("rebinds pooled content to its new owner and releases every observer", function()
		local f = nativeFixture()
		local a, as = f.handle("/S/A", "Button")
		local b, bs = f.handle("/S/B", "Button")
		local label = f.handle("/S/A/Label", "Text", 1)
		f.classify(a, { "facet-appearance-emphasis" })
		f.classify(b, { "facet-role-destructive", "facet-appearance-utility" })
		for _ = 1, 8 do
			label.path = "/S/A/Label"
			f.api.bind(label)
			as("Hover")
			expect(f.live()).toBe(1)
			expect(f.service:HasTag(label.instance, sheet.CONTENT_OWNER_PREFIX .. "facet-appearance-emphasis")).toBe(
				true
			)
			f.api.clear(label) -- park
			expect(f.live()).toBe(0)
			label.path = "/S/B/Label"
			f.api.bind(label)
			bs("Press")
			expect(f.service:HasTag(label.instance, sheet.CONTENT_OWNER_PREFIX .. "facet-appearance-emphasis")).toBe(
				false
			)
			expect(f.service:HasTag(label.instance, sheet.CONTENT_OWNER_PREFIX .. "facet-role-destructive")).toBe(true)
			expect(f.service:HasTag(label.instance, sheet.CONTENT_OWNER_PREFIX .. "state-Press")).toBe(true)
			f.api.clear(b)
			f.api.clear(label) -- owner-first teardown is idempotent
			expect(f.live()).toBe(0)
		end
		expect(f.made()).toBe(16)
		label.rootHandle = {}
		expect(pcall(function()
			f.api.bind(label)
		end)).toBe(false)
	end)
	it("keeps hint keys equal by content and separates different logical owners", function()
		expect(slots.hintKey({ contentOwnerDepth = 1 })).toBe(slots.hintKey({ contentOwnerDepth = 1 }))
		expect(slots.hintKey({ contentOwnerDepth = 1 }) == slots.hintKey({ contentOwnerDepth = 2 })).toBe(false)
		expect(slots.hintKey({ contentOwnerDepth = 1 }) == slots.hintKey({})).toBe(false)
	end)
end)
