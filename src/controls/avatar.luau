--!strict
-- A caller-owned resource provider supplies pictures; a mounted owner holds one lease.
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local vocabulary = require("./control_vocabulary")
local contribution = require("../input/contribution")
local skeleton = require("./skeleton")
local statusIndicator = require("./status_indicator")
local types = require("../spec_types/avatar")
export type Spec = types.Spec
local avatar = {}
local KEYS = guard.keySet({
	"id",
	"name",
	"image",
	"userId",
	"key",
	"provider",
	"controlSize",
	"diameter",
	"presence",
	"presenceLabel",
	"presenceMark",
	"frame",
	"backplate",
	"form",
	"over",
	"onActivate",
})
local PRESENCES = guard.keySet({ "online", "away", "busy", "offline" })
local FILL = table.freeze({ type = "fill", weight = 1 })
local MARK_DIM = table.freeze({ type = "percent", fraction = 0.3 })
local MARKS = {
	online = { form = "dot", status = "success" },
	away = { form = "dash", status = "warning" },
	busy = { form = "square", status = "error" },
	offline = { form = "ring", status = "neutral" },
}
function avatar.headshotKey(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end
local function firstLetter(word: string): string
	local nextChar = utf8.offset(word, 2)
	return if nextChar then string.sub(word, 1, nextChar - 1) else word
end
function avatar.initialsOf(name: string): string
	local first, last
	local count = 0
	for word in string.gmatch(name, "%S+") do
		count += 1
		first = first or word
		last = word
	end
	return if not first then "" elseif count == 1 then firstLetter(first) else firstLetter(first) .. firstLetter(last)
end
-- Shared with AvatarGroup's pre-allocation list validation. Source identity is static.
function avatar.validate(spec: any)
	assert(type(spec.name) == "string" and spec.name ~= "", "Facet Avatar: name must be a nonempty string")
	local form = spec.form or "standard"
	assert(form == "standard" or form == "icon", "Facet Avatar: form must be standard | icon")
	local sources = 0
	for _, key in { "image", "userId", "key" } do
		if spec[key] ~= nil then
			sources += 1
		end
	end
	assert(sources <= 1, "Facet Avatar: supply image, userId or key, at most one source")
	assert(
		spec.userId == nil
			or (type(spec.userId) == "number" and spec.userId == spec.userId and math.abs(spec.userId) < math.huge),
		"Facet Avatar: userId must be finite"
	)
	assert(
		spec.key == nil or (type(spec.key) == "string" and spec.key ~= ""),
		"Facet Avatar: key must be a nonempty string"
	)
	assert(
		spec.image == nil or type(spec.image) == "string" or selection.isSource(spec.image),
		"Facet Avatar: image must be a content string or readable"
	)
	assert(
		(spec.key == nil and spec.userId == nil)
			or (type(spec.provider) == "table" and type(spec.provider.acquire) == "function"),
		"Facet Avatar: loading by userId/key needs the caller's provider"
	)
	assert(spec.diameter == nil or spec.controlSize == nil, "Facet Avatar: give diameter or controlSize, not both")
	assert(
		spec.diameter == nil
			or type(spec.diameter) == "string"
			or (type(spec.diameter) == "number" and spec.diameter > 0 and spec.diameter < math.huge),
		"Facet Avatar: diameter must be a positive finite number or metric"
	)
	assert(form ~= "icon" or spec.presence == nil, "Facet Avatar: icon form carries no presence mark")
	assert(spec.presenceLabel == nil or spec.presence ~= nil, "Facet Avatar: presenceLabel requires presence")
	assert(
		spec.presenceMark == nil or type(spec.presenceMark) == "boolean",
		"Facet Avatar: presenceMark must be boolean"
	)
	assert(spec.backplate == nil or type(spec.backplate) == "boolean", "Facet Avatar: backplate must be boolean")
	assert(spec.onActivate == nil or type(spec.onActivate) == "function", "Facet Avatar: onActivate must be a callback")
	vocabulary.assertSize("Avatar", spec.controlSize)
	vocabulary.assertOver("Avatar", spec.over)
end
function avatar.semantic(name, presence, label, use)
	assert(type(name) == "string" and name ~= "", "Facet Avatar: name must be a nonempty string")
	local state = selection.read(presence, use)
	assert(state == nil or PRESENCES[state], "Facet Avatar: presence must be online | away | busy | offline")
	local word = selection.read(label, use)
	assert(word == nil or type(word) == "string", "Facet Avatar: presenceLabel must be a string")
	return {
		name = name,
		presence = state,
		initials = avatar.initialsOf(name),
		label = if state == nil then name else `{name}, {word or state}`,
	}
end
local function build(library: any, core: any, spec: any, owner: any, current: any)
	guard.assertKnownKeys("UI.Avatar", spec, KEYS, "spec")
	avatar.validate(spec)
	local UI, id, form = library.UI, spec.id or "Avatar", spec.form or "standard"
	-- One validated derived answer feeds every paint and semantic reader. A failed
	-- evaluation retains its prior published value; the caller's cell is untouched.
	local facts = Compose.formula(function(use)
		local person = if current then use(current) else spec
		return avatar.semantic(person.name, person.presence, person.presenceLabel, use)
	end)
	facts:peek()
	local function field(key)
		return function(use)
			return use(facts)[key]
		end
	end
	local function rungDim(rung)
		return {
			type = "fixed",
			px = vocabulary.metricPath(rung or "regular", if form == "icon" then "iconSize" else "height"),
		}
	end
	local diameter = if spec.diameter ~= nil
		then { type = "fixed", px = spec.diameter }
		else vocabulary.deriveSize("Avatar", spec.controlSize, rungDim) or rungDim("regular")
	local key = spec.key or (if spec.userId ~= nil then avatar.headshotKey(spec.userId) else nil)
	local handle = if key then spec.provider.acquire(owner, key) else nil
	local plateRole, letterRole = "control", "content"
	if spec.over == "media" then
		plateRole, letterRole = "surfaceStrong", "contentStrong"
	elseif spec.backplate then
		plateRole, letterRole = "accent", "onAccent"
	end
	local children = {
		UI.Box({ id = "Plate", shape = "circle", tint = { role = plateRole, blend = 1 }, width = FILL }),
	}
	local function initialsView()
		return UI.Text({
			id = "Initials",
			text = field("initials"),
			textSize = { fit = { cap = "label" } },
			lineLimit = 1,
			disclose = true,
			textAlign = "center",
			tint = { role = letterRole, blend = 1 },
			width = FILL,
			height = FILL,
		})
	end
	local function pictureView()
		local image = if handle
			then function(use)
				return use(handle.value) or ""
			end
			else spec.image
		return UI.Image({ id = "Picture", shape = "circle", image = image, width = FILL })
	end
	if not handle then
		table.insert(children, if spec.image ~= nil then pictureView() else initialsView())
	else
		for _, state in { "failed", "ready", "pending" } do
			local factory = if state == "failed"
				then initialsView
				elseif state == "ready" then pictureView
				else function()
					-- Created only in this live branch; its owner, not Avatar's, holds shimmer.
					return skeleton.build(library, core, { id = "Placeholder", form = "circle", width = FILL }).blueprint
				end
			table.insert(
				children,
				UI.When({
					id = if state == "failed" then "Initials" elseif state == "ready" then "Picture" else "Pending",
					condition = function(use)
						return use(handle.state) == state
					end,
					thenView = factory,
				})
			)
		end
	end
	if form == "standard" then
		table.insert(
			children,
			UI.stroke(UI.Box({ id = "Rim", shape = "circle", width = FILL }), { color = "hairline" })
		)
	end
	if spec.frame then
		table.insert(children, spec.frame)
	end
	if (spec.presence ~= nil or current ~= nil) and spec.presenceMark ~= false then
		table.insert(
			children,
			UI.ZStack({
				id = "Presence",
				width = MARK_DIM,
				height = MARK_DIM,
				alignH = "end",
				alignV = "end",
				children = {
					UI.When({
						id = "Visible",
						condition = function(use)
							return use(facts).presence ~= nil
						end,
						thenView = function()
							local function markField(key)
								return function(use: Compose.Use): any
									local mark = MARKS[use(facts).presence]
									return if mark then mark[key] else nil
								end
							end
							return statusIndicator.build(library, core, {
								id = "Status",
								form = markField("form"),
								status = markField("status"),
								width = FILL,
								height = FILL,
								cutout = true,
							}).blueprint
						end,
					}),
				},
			})
		)
	end
	local blueprint
	if spec.onActivate then
		local plate = UI.Button({
			id = id,
			label = field("label"),
			shape = if form == "standard" then "circle" else nil,
			surface = "plain",
			padding = 0,
			width = diameter,
			height = if form == "icon" then diameter else nil,
			children = { UI.ZStack({ id = "Layers", width = FILL, height = FILL, children = children }) },
		})
		plate = contribution.attach(plate, {
			handleActivate = function()
				spec.onActivate()
				return true
			end,
		})
		blueprint = vocabulary.reserveTarget(UI, core, id, plate, nil)
	else
		blueprint = UI.ZStack({ id = id, width = diameter, height = diameter, children = children })
	end
	local function dump()
		local value = facts:peek()
		return {
			schema = "facet-avatar-dump/1",
			id = id,
			name = value.name,
			label = value.label,
			initials = value.initials,
			form = form,
			source = if spec.image ~= nil then "image" elseif key then "provider" else "initials",
			key = key,
			state = if handle then handle.state:peek() else nil,
			presence = value.presence,
			presenceMark = value.presence ~= nil and spec.presenceMark ~= false,
			backplate = spec.backplate == true,
			over = spec.over,
			controlSize = selection.read(spec.controlSize),
			interactive = spec.onActivate ~= nil,
		}
	end
	return { blueprint = blueprint, dump = dump, state = if handle then handle.state else nil, dispose = owner.dispose }
end
-- current is internal to AvatarGroup: retained rows read their current item.
function avatar.build(library: any, core: any, spec: Spec, current: any?)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else core.owner.createChild()
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(library, core, spec, owner, current)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return avatar
