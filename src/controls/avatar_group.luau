--!strict
-- A keyed roster of passive faces; only an actionable overflow count takes focus.
local Compose = require("../vendor/compose/core")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local snapshot = require("../themes/snapshot")
local vocabulary = require("./control_vocabulary")
local contribution = require("../input/contribution")
local avatar = require("./avatar")
local types = require("../spec_types/avatar_group")
export type Spec = types.Spec
local avatar_group = {}
local KEYS = guard.keySet({
	"id",
	"items",
	"layout",
	"max",
	"overflow",
	"form",
	"controlSize",
	"over",
	"onOverflow",
	"overflowLabel",
	"provider",
})
local ITEM_KEYS = guard.keySet({ "id", "name", "image", "userId", "key", "presence", "presenceLabel" })
local FILL = table.freeze({ type = "fill", weight = 1 })
local function sourceKey(member)
	if member.image ~= nil then
		return "image:" .. tostring(member.image)
	end
	if member.userId ~= nil then
		return "user:" .. tostring(member.userId)
	end
	return if member.key ~= nil then "key:" .. member.key else "initials"
end
local function build(library: any, core: any, spec: any, owner: any)
	guard.assertKnownKeys("UI.AvatarGroup", spec, KEYS, "spec")
	local UI, id = library.UI, spec.id or "AvatarGroup"
	local layout, form = spec.layout or "stacked", spec.form or "standard"
	local overflow, max = spec.overflow or "count", spec.max or 4
	assert(layout == "stacked" or layout == "spread", "Facet AvatarGroup: layout must be stacked | spread")
	assert(form == "standard" or form == "icon", "Facet AvatarGroup: form must be standard | icon")
	assert(overflow == "count" or overflow == "ellipsis", "Facet AvatarGroup: overflow must be count | ellipsis")
	assert(
		type(max) == "number" and max >= 1 and max % 1 == 0,
		"Facet AvatarGroup: max must be a positive whole number"
	)
	assert(
		spec.onOverflow == nil or type(spec.onOverflow) == "function",
		"Facet AvatarGroup: onOverflow must be a callback"
	)
	vocabulary.assertSize("AvatarGroup", spec.controlSize)
	vocabulary.assertOver("AvatarGroup", spec.over)
	-- Validate the whole roster before any row acquires a resource. The formula's
	-- last published answer is also the dump's answer after a refused update.
	local members = Compose.formula(function(use)
		local list = selection.read(spec.items, use)
		assert(type(list) == "table", "Facet AvatarGroup: items must be an array of members")
		local count, largest = 0, 0
		for index in list do
			assert(
				type(index) == "number" and index >= 1 and index % 1 == 0,
				"Facet AvatarGroup: items must be a dense array"
			)
			count += 1
			largest = math.max(largest, index)
		end
		assert(count == largest, "Facet AvatarGroup: items must be a dense array")
		local seen = {}
		local out: { any } = {}
		for index = 1, count do
			local member = list[index]
			assert(type(member) == "table", "Facet AvatarGroup: every member must be a table")
			guard.assertKnownKeys("UI.AvatarGroup member", member, ITEM_KEYS, "member")
			assert(
				type(member.id) == "string" and member.id ~= "",
				"Facet AvatarGroup: every member needs a nonempty id"
			)
			assert(not seen[member.id], "Facet AvatarGroup: duplicate member id " .. member.id)
			seen[member.id] = true
			local checked = table.clone(member)
			checked.form, checked.provider = form, spec.provider
			avatar.validate(checked)
			local facts = avatar.semantic(member.name, member.presence, member.presenceLabel, use)
			checked.presence = facts.presence
			checked.presenceLabel = selection.read(member.presenceLabel, use)
			table.insert(out, checked)
		end
		return out
	end)
	members:peek()
	local field = if form == "icon" then "iconSize" else "height"
	local function rungPath(rung)
		return vocabulary.metricPath(rung or "regular", field)
	end
	local checkedPath = vocabulary.deriveSize("AvatarGroup", spec.controlSize, rungPath) or rungPath("regular")
	local size = vocabulary.deriveSize("AvatarGroup", spec.controlSize, function(rung)
		return { type = "fixed", px = rungPath(rung) }
	end) or { type = "fixed", px = rungPath("regular") }
	local env = surfaceEnv.find(core)
	local metrics = if env then env:get("themeMetrics") else nil
	local gap = if layout == "spread"
		then "s"
		else function(use)
			local theme = if metrics then use(metrics) else snapshot.neutral()
			local diameter = assert(
				snapshot.resolveNumber(theme, selection.read(checkedPath, use)),
				"Facet AvatarGroup: missing theme size metric"
			)
			return -math.floor(diameter / 3)
		end
	local visible = Compose.formula(function(use)
		local out = {}
		for index, member in use(members) do
			if index > max then
				break
			end
			table.insert(out, member)
		end
		return out
	end)
	local hidden = Compose.formula(function(use)
		return math.max(0, #use(members) - max)
	end)
	local chipLabel = Compose.formula(function(use)
		local phrase = selection.read(spec.overflowLabel, use)
		return if type(phrase) == "string" and phrase ~= "" then phrase else `{use(hidden)} more`
	end)
	local chipText = Compose.formula(function(use)
		return if overflow == "count" then `+{use(hidden)}` else "…"
	end)
	local function face()
		return UI.ZStack({
			id = "Face",
			width = FILL,
			height = FILL,
			children = {
				UI.Box({
					id = "Plate",
					shape = "circle",
					width = FILL,
					tint = { role = if spec.over == "media" then "surfaceStrong" else "control", blend = 1 },
				}),
				UI.Text({
					id = "Count",
					text = chipText,
					textSize = { fit = { cap = "label" } },
					lineLimit = 1,
					disclose = true,
					textAlign = "center",
					width = FILL,
					height = FILL,
					tint = { role = if spec.over == "media" then "contentStrong" else "content", blend = 1 },
				}),
			},
		})
	end
	local function chip()
		if not spec.onOverflow then
			return UI.ZStack({ id = "More", width = size, height = size, lineAlign = "center", children = { face() } })
		end
		local plate = contribution.attach(
			UI.Button({
				id = "More",
				label = chipLabel,
				shape = "circle",
				surface = "plain",
				padding = 0,
				width = size,
				children = { face() },
			}),
			{
				handleActivate = function()
					spec.onOverflow()
					return true
				end,
			}
		)
		local target = vocabulary.reserveTarget(UI, core, "More", plate, nil)
		library.runtime.decorate(target, { lineAlign = "center" })
		return target
	end
	local blueprint = UI.HStack({
		id = id,
		gap = gap,
		overflow = if layout == "stacked" then "intentionalOverlap" else nil,
		children = {
			UI.ForEach({
				id = "Members",
				items = visible,
				key = "id",
				row = function(member, _, current)
					return UI.ZStack({
						id = member.id,
						lineAlign = "center",
						children = {
							-- The outer id owns row identity; a source replacement alone renews the lease.
							UI.ForEach({
								id = "Source",
								items = function(use)
									return { use(current) }
								end,
								key = sourceKey,
								row = function(person, __, latest)
									return avatar.build(library, core, {
										id = "Face",
										name = person.name,
										image = person.image,
										userId = person.userId,
										key = person.key,
										provider = spec.provider,
										presence = person.presence,
										presenceLabel = person.presenceLabel,
										presenceMark = layout ~= "stacked",
										form = form,
										controlSize = spec.controlSize,
										over = spec.over,
									}, latest).blueprint
								end,
							}),
						},
					})
				end,
			}),
			UI.When({
				id = "Overflow",
				condition = function(use)
					return use(hidden) > 0
				end,
				thenView = chip,
			}),
		},
	})
	local function dump()
		local ids = {}
		for index, member in members:peek() do
			if index > max then
				break
			end
			table.insert(ids, member.id)
		end
		return {
			schema = "facet-avatar-group-dump/1",
			id = id,
			layout = layout,
			max = max,
			overflow = overflow,
			form = form,
			presenceMark = layout ~= "stacked",
			shown = ids,
			hidden = hidden:peek(),
			chipLabel = if hidden:peek() > 0 then chipLabel:peek() else nil,
			chipText = if hidden:peek() > 0 then chipText:peek() else nil,
			interactive = spec.onOverflow ~= nil,
			controlSize = selection.read(spec.controlSize),
			over = spec.over,
		}
	end
	return { blueprint = blueprint, dump = dump, dispose = owner.dispose }
end
function avatar_group.build(library: any, core: any, spec: Spec)
	local parent = Compose.currentOwner()
	local owner = if parent then parent.createChild() else Compose.createOwner(core.scene.reactor)
	local ok, result = pcall(Compose.withOwner, owner, function()
		return build(library, core, spec, owner)
	end)
	if not ok then
		owner.dispose()
		error(result, 0)
	end
	return result
end
return avatar_group
