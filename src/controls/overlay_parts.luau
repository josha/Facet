--!strict
--[[ The shared overlay parts: construction-only media and the action row.
	Validation is closed and happens at construction, so a malformed part is a
	spec error rather than a half-painted plate. Rendering reuses the ordinary
	Image, Box and Button vocabulary; the caller decides what a press means. ]]
local specGuard = require("../spec_guard")
local Compose = require("../vendor/compose/core")

local overlay_parts = {}

-- the modal panels' theme-resolved maximum widths (Dialog and Sheet), each
-- bounded by the safe room it is offered
overlay_parts.WIDTHS = table.freeze({
	automatic = "controls.alert.maxWidth",
	narrow = "controls.popup.panelWidth",
	wide = "controls.dialog.wideWidth",
})

local MEDIA_KEYS = specGuard.keySet({ "aspectRatio", "background", "height", "image", "scaleMode" })
local HERO_KEYS = specGuard.keySet({ "aspectRatio", "background", "content", "height", "image", "scaleMode", "sticky" })
local ACTION_KEYS = specGuard.keySet({ "busy", "enabled", "id", "label", "onActivate", "role" })
local SCALE_MODES = { fit = true, crop = true, stretch = true }
local ROLES = { default = true, cancel = true, destructive = true }

-- a Bound<T>: the value itself, a Compose readable or a tracked function
local function bound(v: any, kind: string): boolean
	return type(v) == kind or type(v) == "function" or Compose.isReadable(v)
end

local function positive(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v < math.huge
end

local function checkShape(where: string, media: any, name: string)
	local ratio, height = media.aspectRatio, media.height
	if (ratio == nil) == (height == nil) then
		error(`Facet {where}: \`{name}\` takes exactly one of \`aspectRatio\` or \`height\`.`, 0)
	end
	if ratio ~= nil and not positive(ratio) then
		error(`Facet {where}: \`{name}.aspectRatio\` is a positive finite number.`, 0)
	end
	if height ~= nil and not positive(height) and not (type(height) == "string" and height ~= "") then
		error(`Facet {where}: \`{name}.height\` is a positive finite px or a theme metric name.`, 0)
	end
	if media.scaleMode ~= nil and SCALE_MODES[media.scaleMode] ~= true then
		error(`Facet {where}: \`{name}.scaleMode\` is fit | crop | stretch.`, 0)
	end
end

function overlay_parts.checkMedia(where: string, media: any)
	if media == nil then
		return
	end
	if type(media) ~= "table" then
		error(`Facet {where}: \`media\` is \{ image, aspectRatio | height, scaleMode?, background? }.`, 0)
	end
	specGuard.assertKnownKeys(where, media, MEDIA_KEYS, "media")
	if type(media.image) ~= "string" or media.image == "" then
		error(`Facet {where}: \`media.image\` is an image source string.`, 0)
	end
	checkShape(where, media, "media")
end

-- the Sheet's hero: the media shape plus `sticky`, with arbitrary blueprint
-- `content` as the alternative to `image` (scaleMode is image-only)
function overlay_parts.checkHero(where: string, hero: any)
	if hero == nil then
		return
	end
	if type(hero) ~= "table" then
		error(`Facet {where}: \`hero\` is \{ image | content, aspectRatio | height, sticky?, ... }.`, 0)
	end
	specGuard.assertKnownKeys(where, hero, HERO_KEYS, "hero")
	if (hero.image == nil) == (hero.content == nil) then
		error(`Facet {where}: \`hero\` takes exactly one of \`image\` or \`content\`.`, 0)
	end
	if hero.image ~= nil and (type(hero.image) ~= "string" or hero.image == "") then
		error(`Facet {where}: \`hero.image\` is an image source string.`, 0)
	end
	if hero.content ~= nil then
		if type(hero.content) ~= "table" or type(hero.content.class) ~= "string" then
			error(`Facet {where}: \`hero.content\` is a blueprint.`, 0)
		end
		if hero.scaleMode ~= nil then
			error(`Facet {where}: \`hero.scaleMode\` applies to an image only.`, 0)
		end
	end
	if hero.sticky ~= nil and type(hero.sticky) ~= "boolean" then
		error(`Facet {where}: \`hero.sticky\` is true or false (default).`, 0)
	end
	checkShape(where, hero, "hero")
end

-- returns the number of actions (0 for absent or empty); `reserved` ids name the
-- surface's own sibling buttons
function overlay_parts.checkActions(where: string, actions: any, max: number, reserved: { string }?): number
	if actions == nil then
		return 0
	end
	if type(actions) ~= "table" or #actions > max then
		error(`Facet {where}: \`actions\` is a list of at most {max} actions.`, 0)
	end
	local seen: { [string]: boolean } = {}
	for _, action in actions do
		if type(action) ~= "table" then
			error(`Facet {where}: each action is \{ id, label, role?, enabled?, busy?, onActivate }.`, 0)
		end
		specGuard.assertKnownKeys(where, action, ACTION_KEYS, "action")
		if type(action.id) ~= "string" or action.id == "" or seen[action.id] then
			error(`Facet {where}: every action needs a unique string \`id\`.`, 0)
		end
		if reserved ~= nil and table.find(reserved, action.id) then
			error(`Facet {where}: action id '{action.id}' is reserved for the built-in button.`, 0)
		end
		seen[action.id] = true
		if not bound(action.label, "string") then
			error(`Facet {where}: action '{action.id}' needs a string \`label\` (or a bound one).`, 0)
		end
		for _, key in { "enabled", "busy" } do
			if action[key] ~= nil and not bound(action[key], "boolean") then
				error(`Facet {where}: action '{action.id}' \`{key}\` is a boolean (or a bound one).`, 0)
			end
		end
		if action.role ~= nil and ROLES[action.role] ~= true then
			error(`Facet {where}: action '{action.id}' role is default | cancel | destructive.`, 0)
		end
		if type(action.onActivate) ~= "function" then
			error(`Facet {where}: action '{action.id}' needs an \`onActivate\` function.`, 0)
		end
	end
	return #actions
end

-- full-width media: the natural width is `preferred` (default the theme's popup
-- panel width), which a narrower parent clamps; the height follows the ratio or
-- the declared height. A hugging parent measures an aspect height at the
-- PREFERRED width, so a panel that knows its live width passes it as
-- `preferred(use)` and the ratio never reserves height for a wider hero.
function overlay_parts.media(UI: any, media: any, preferred: any?): any
	local width: any = { type = "minMax", preferred = preferred or "controls.popup.panelWidth" }
	if type(preferred) == "function" then
		width = function(use: any): any
			return { type = "minMax", preferred = preferred(use) }
		end
	end
	local height = if media.aspectRatio ~= nil
		then { type = "aspect", ratio = media.aspectRatio }
		else { type = "fixed", px = media.height }
	local image = UI.Image({
		id = "Image",
		image = media.image,
		scaleMode = media.scaleMode,
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
	})
	if media.background == nil then
		return UI.ZStack({ id = "Media", width = width, height = height, children = { image } })
	end
	return UI.ZStack({
		id = "Media",
		width = width,
		height = height,
		children = {
			UI.Box({
				id = "Background",
				tint = media.background,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
			}),
			image,
		},
	})
end

-- the hero spans the width it is given; `strip` (a height dimension) reserves
-- a top band inside authored content for controls laid over it, and `over` is
-- that overlay, painted last
function overlay_parts.hero(UI: any, hero: any, strip: any?, over: any?): any
	local children: { any } = {}
	if hero.background ~= nil then
		table.insert(
			children,
			UI.Box({ id = "Background", tint = hero.background, width = UI.fill(), height = UI.fill() })
		)
	end
	if hero.image ~= nil then
		table.insert(
			children,
			UI.Image({
				id = "Image",
				image = hero.image,
				scaleMode = hero.scaleMode,
				width = UI.fill(),
				height = UI.fill(),
			})
		)
	else
		local stack: { any } = {}
		if strip ~= nil then
			table.insert(stack, UI.Box({ id = "Strip", width = UI.fill(), height = strip }))
		end
		table.insert(stack, hero.content)
		table.insert(children, UI.VStack({ id = "Content", width = UI.fill(), height = UI.fill(), children = stack }))
	end
	if over ~= nil then
		table.insert(children, over)
	end
	return UI.ZStack({
		id = "Hero",
		width = UI.fill(),
		height = if hero.aspectRatio ~= nil
			then { type = "aspect", ratio = hero.aspectRatio }
			else { type = "fixed", px = hero.height },
		children = children,
	})
end

-- one row of action Buttons under `Actions/<id>`; activation is the caller's
-- contribution, matched by `overlay_parts.actionAt`
function overlay_parts.actionRow(UI: any, actions: { any }, height: any): any
	local buttons: { any } = {}
	for _, action in actions do
		table.insert(
			buttons,
			UI.Button({
				id = action.id,
				label = action.label,
				role = action.role,
				enabled = action.enabled,
				busy = action.busy,
				-- two actions share one row: a word too long for its half still has
				-- its full-value path (the Sheet header's buttons do the same)
				disclose = true,
				width = { type = "fill", weight = 1 },
				height = height,
			})
		)
	end
	return UI.HStack({ id = "Actions", gap = "s", width = { type = "fill", weight = 1 }, children = buttons })
end

--[[ THE TINY ROOM (Dialog and Sheet). A panel pins its header,
	hero and actions around one scrolling `Body` while they and a minimum body
	fit. When they do not, every region unpins into ONE scrolling column, so each
	action stays reachable by pointer and focus.

	`panelMax(use)` is the most the PANEL may be tall; the panel's own chrome
	(padding, a drag strip) is measured once and taken off it. `fill` fixes the
	column to that room (a panel with a fixed height) instead of hugging under
	it. `tight` is the cell the fact is written to, so regions built first can
	read it. ]]
function overlay_parts.room(
	UI: any,
	owner: any,
	children: { any },
	panelMax: (use: any) -> number,
	fill: boolean,
	tight: any
): any
	local contribution = require("../input/contribution")
	local chrome = Compose.cell(nil :: number?)
	local column = UI.VStack({
		id = "Column",
		width = UI.fill(),
		gap = "s",
		height = Compose.withOwner(owner, function()
			return Compose.formula(function(use): any
				local outside = use(chrome)
				if use(tight) or outside == nil then
					return { type = "hug" }
				end
				local max = math.max(0, panelMax(use) - outside)
				return if fill then { type = "fixed", px = max } else { type = "hug", max = max }
			end)
		end),
		children = children,
	})
	local function peek(r: any): any
		return r:peek()
	end
	-- a definite viewport on a fixed panel, so the measure pays the scroll bar
	local roomHeight = if fill
		then Compose.withOwner(owner, function()
			return Compose.formula(function(use): any
				local outside = use(chrome)
				return if outside == nil
					then UI.fill()
					else { type = "fixed", px = math.max(0, panelMax(use) - outside) }
			end)
		end)
		else nil
	local minimum = 44 -- one target-sized line of body
	return contribution.attach(
		UI.ScrollView({
			id = "Room",
			axis = "y",
			width = UI.fill(),
			height = roomHeight,
			shrinkWeight = 1,
			chromeReserve = "none",
			scrollEnabled = tight,
			children = { column },
		}),
		{
			syncGeometry = function(rectOf: any, mounted: any?)
				local col = if mounted ~= nil and mounted.children ~= nil then mounted.children[1] else nil
				local roomRect = if mounted ~= nil then rectOf(mounted.path) else nil
				local panelPath = if mounted ~= nil then string.match(mounted.path, "^(.*)/[^/]+$") else nil
				local panelRect = if panelPath ~= nil then rectOf(panelPath) else nil
				if col == nil or type(roomRect) ~= "table" or type(panelRect) ~= "table" then
					return
				end
				-- the panel's own chrome does not depend on the column
				local outside = panelRect.h - roomRect.h
				if chrome:peek() == nil or math.abs(chrome:peek() - outside) > 0.5 then
					chrome:set(outside)
				end
				-- the regions' extent: pinned parts never shrink, the body does
				local top, bottom = math.huge, -math.huge
				for _, child in col.children or {} do
					local r = rectOf(child.path)
					if type(r) == "table" and r.h > 0 then
						top, bottom = math.min(top, r.y), math.max(bottom, r.y + r.h)
					end
				end
				if top == math.huge then
					return
				end
				local function find(n: any): any
					if n.id == "Body" and n.class == "ScrollView" then
						return n
					end
					for _, child in n.children or {} do
						local hit = find(child)
						if hit ~= nil then
							return hit
						end
					end
					return nil
				end
				local bodyNode = find(col)
				local bodyRect = if bodyNode ~= nil then rectOf(bodyNode.path) else nil
				local body, natural = 0, 0
				if type(bodyRect) == "table" then
					-- its content's extent, which the body clips when squeezed
					local lo, hi = math.huge, -math.huge
					for _, child in bodyNode.children or {} do
						local r = rectOf(child.path)
						if type(r) == "table" then
							lo, hi = math.min(lo, r.y), math.max(hi, r.y + r.h)
						end
					end
					body, natural = bodyRect.h, if lo < hi then hi - lo else bodyRect.h
				end
				local need = (bottom - top) - body + math.min(minimum, natural)
				local next = need > panelMax(peek) - outside + 0.5
				if next ~= tight:peek() then
					tight:set(next)
				end
			end,
		}
	)
end

--[[ A CALLER'S CALLBACK NEVER FAILS SILENTLY (Alert's contract). `settle` runs
	first, whether or not the callback threw, so the surface's own state is
	consistent; then the caller's error is raised as it was thrown. ]]
function overlay_parts.call(fn: any, settle: (() -> ())?, ...: any): any
	local ok, result = pcall(fn, ...)
	if settle ~= nil then
		settle()
	end
	if not ok then
		error(result, 0)
	end
	return result
end

-- the action a path activates, if it is one of the row's buttons
function overlay_parts.actionAt(actions: { any }?, path: string): any
	local id = string.match(path, "/Actions/([^/]+)$")
	if id == nil or actions == nil then
		return nil
	end
	for _, action in actions do
		if action.id == id then
			return action
		end
	end
	return nil
end

return overlay_parts
