--!strict
-- A radial command surface composed from Anchor, Path, Button and ScrollView.
-- One logical path survives ring fitting/replacement; all input commits here.
local blueprintLib = require("../blueprint")
local guard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local snapshot = require("../themes/snapshot")
local textMetrics = require("../layout/text_metrics")
local geometry = require("./radial_geometry")
local chrome = require("../tokens/chrome_slots")
local themePackage = require("../themes/package")
local aperture = require("../render/input_aperture")
local radialInput = require("../input/radial_input")
local radial = {}
local function fixed(px: any): any
	return { type = "fixed", px = px }
end
export type Item = {
	id: string,
	label: any,
	icon: string?,
	compactLabel: any?,
	labelStyle: string?,
	slot: string?,
	enabled: any?,
	hidden: any?,
	description: any?,
	children: any?,
	navigation: string?,
	expansion: string?,
	completion: string?,
	checked: any?,
	selected: any?,
	value: any?,
	dismiss: boolean?,
	onSelect: (() -> ())?,
	onChange: ((any) -> ())?,
	role: string?,
	decoration: any?,
	buttonSurface: string?,
}
export type Spec = {
	id: string?,
	items: any,
	env: any?,
	label: string?,
	launcher: boolean?,
	icon: string?,
	preset: string?,
	appearance: string?,
	buttonSurface: string?,
	distribution: string?,
	navigation: string?,
	expansion: string?,
	center: string?,
	centerLabel: string?,
	centerContent: any?,
	centerPassThrough: boolean?,
	completion: string?,
	anchor: any?,
	follow: string?,
	clearance: any?,
	ringWidth: any?,
	contentFit: string?,
	gestureSelection: string?,
	enabled: any?,
	width: any?,
	height: any?,
	holdAction: any?,
	skin: any?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}
local KEYS = guard.keySet({
	"id",
	"items",
	"env",
	"label",
	"launcher",
	"icon",
	"preset",
	"appearance",
	"buttonSurface",
	"distribution",
	"navigation",
	"expansion",
	"center",
	"centerLabel",
	"centerContent",
	"centerPassThrough",
	"completion",
	"anchor",
	"follow",
	"clearance",
	"ringWidth",
	"contentFit",
	"gestureSelection",
	"enabled",
	"width",
	"height",
	"holdAction",
	"skin",
	"onOpen",
	"onClose",
})
local ITEM_KEYS = guard.keySet({
	"id",
	"label",
	"icon",
	"compactLabel",
	"labelStyle",
	"slot",
	"enabled",
	"hidden",
	"description",
	"children",
	"navigation",
	"expansion",
	"completion",
	"checked",
	"selected",
	"value",
	"dismiss",
	"onSelect",
	"onChange",
	"role",
	"decoration",
	"buttonSurface",
})
local function read(v: any): any
	return if type(v) == "table" and v.kind then v:get() else v
end
local function choice(v: any, default: string, values: { string }, name: string): string
	v = v or default
	assert(
		type(v) == "string" and table.find(values, v),
		"Controls.RadialMenu: " .. name .. " must be " .. table.concat(values, ", ")
	)
	return v
end
local function validate(items: any, distribution: string, ancestors: any?)
	assert(type(items) == "table" and #items > 0, "Controls.RadialMenu: items must be a nonempty array")
	local seen, stack = {}, ancestors or {}
	assert(not stack[items], "Controls.RadialMenu: children must not contain a cycle")
	stack[items] = true
	for _, item in items do
		guard.assertKnownKeys("Controls.RadialMenu item", item, ITEM_KEYS, "item")
		assert(
			type(item.id) == "string" and item.id ~= "" and item.id ~= "$navigation" and not item.id:find("/", 1, true),
			"Controls.RadialMenu: item id must be nonempty, contain no slash, and not be $navigation"
		)
		assert(not seen[item.id], "Controls.RadialMenu: duplicate item id " .. item.id)
		seen[item.id] = true
		assert(
			type(read(item.label)) == "string" and read(item.label) ~= "",
			"Controls.RadialMenu: every item needs an accessible label"
		)
		for _, key in { "enabled", "hidden" } do
			assert(
				item[key] == nil or type(read(item[key])) == "boolean",
				"Controls.RadialMenu: " .. key .. " must be boolean or Readable<boolean>"
			)
		end
		choice(item.navigation, "replace", { "replace", "expand" }, "item.navigation")
		choice(item.expansion, "fan", { "fan", "ring" }, "item.expansion")
		choice(item.completion, "close", { "stay", "back", "root", "close" }, "item.completion")
		choice(item.buttonSurface, "native", { "native", "none" }, "item.buttonSurface")
		choice(item.labelStyle, "text", { "text", "icon", "both" }, "item.labelStyle")
		blueprintLib.Button({
			label = item.label,
			compactLabel = item.compactLabel or (if item.icon then { icon = item.icon } else nil),
		})
		assert(item.labelStyle ~= "icon" or item.icon ~= nil, "Controls.RadialMenu: icon labelStyle requires icon")
		local state = item.checked or item.selected
		assert(not (item.checked and item.selected), "Controls.RadialMenu: use checked or selected, not both")
		if state then
			assert(
				state.kind == "signal",
				"Controls.RadialMenu: checked/selected must be caller-owned settable Signals"
			)
			assert(
				not item.children and not item.onSelect,
				"Controls.RadialMenu: a state item uses onChange, not children/onSelect"
			)
			assert(
				item.checked == nil or type(state:get()) == "boolean",
				"Controls.RadialMenu: checked must hold boolean"
			)
			assert(item.selected == nil or item.value ~= nil, "Controls.RadialMenu: selected requires value")
		end
		assert(
			item.onChange == nil or (state and type(item.onChange) == "function"),
			"Controls.RadialMenu: onChange requires a state item"
		)
		assert(
			item.onSelect == nil or type(item.onSelect) == "function",
			"Controls.RadialMenu: onSelect must be a function"
		)
		assert(item.dismiss == nil or type(item.dismiss) == "boolean", "Controls.RadialMenu: dismiss must be boolean")
		assert(not (item.children and item.onSelect), "Controls.RadialMenu: use children or onSelect, not both")
		if item.children then
			validate(read(item.children), "even", stack)
		end
	end
	if distribution == "compass" then
		geometry.sectors(items, 0, 360, distribution, 1, 2)
	end
	stack[items] = nil
end
function radial.build(Facet: any, core: any, spec: Spec)
	guard.assertKnownKeys("Controls.RadialMenu", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "RadialMenu"
	local preset = choice(
		spec.preset,
		"donut",
		{ "circle", "donut", "top-left", "top-right", "bottom-left", "bottom-right" },
		"preset"
	)
	local appearance = choice(spec.appearance, "wedges", { "wedges", "buttons" }, "appearance")
	local buttonSurface = choice(spec.buttonSurface, "native", { "native", "none" }, "buttonSurface")
	local contentFit = choice(spec.contentFit, "both", { "both", "radial", "angular", "none" }, "contentFit")
	local gestureSelection = choice(spec.gestureSelection, "bounded", { "bounded", "direction" }, "gestureSelection")
	local distribution = choice(spec.distribution, "even", { "even", "compass" }, "distribution")
	local navigation = choice(spec.navigation, "replace", { "replace", "expand" }, "navigation")
	local expansion = choice(spec.expansion, "fan", { "fan", "ring" }, "expansion")
	local center = choice(spec.center, "back", { "back", "root", "close", "content", "empty" }, "center")
	local follow = choice(spec.follow, "idle", { "idle", "always", "fixed" }, "follow")
	assert(spec.launcher == nil or type(spec.launcher) == "boolean", "Controls.RadialMenu: launcher must be boolean")
	choice(spec.completion, "close", { "stay", "back", "root", "close" }, "completion")
	validate(read(spec.items), distribution)
	for _, key in { "onOpen", "onClose" } do
		assert(
			spec[key] == nil or type(spec[key]) == "function",
			"Controls.RadialMenu: " .. key .. " must be a function"
		)
	end
	assert(
		spec.centerPassThrough == nil or type(spec.centerPassThrough) == "boolean",
		"Controls.RadialMenu: centerPassThrough must be boolean"
	)
	if spec.skin then
		guard.assertKnownKeys(
			"Controls.RadialMenu skin",
			spec.skin,
			guard.keySet({ "item", "launcher", "center", "background" }),
			"skin"
		)
		for _, value in spec.skin do
			if type(value) ~= "string" then
				local _, errors = themePackage.normalizeVariant(value, "RadialMenu skin")
				assert(#errors == 0, "Controls.RadialMenu: invalid image skin")
			end
		end
	end
	local env =
		surfaceEnv.resolve("Controls.RadialMenu", id, core, spec.env, "radial fitting needs the surface environment")
	local scope = core:scope("radial-" .. id)
	local function signal(v: any): any
		return scope:own(core:signal(v))
	end
	local function switch(name: string, condition: any, yes: any, no: any, owner: any?, height: any?): any
		owner = owner or scope
		return UI.ZStack({
			id = name,
			width = UI.fill(),
			height = height or UI.fill(),
			children = {
				UI.When({ id = "Yes", condition = condition, thenView = yes }),
				UI.When({
					id = "No",
					condition = owner:own(core:memo(function(use)
						return not use(condition)
					end)),
					thenView = no,
				}),
			},
		})
	end
	local function memo(fn: any): any
		return scope:own(core:memo(fn))
	end
	local function skin(bp: any, value: any, slot: string): any
		if value == nil then
			return bp
		end
		if type(value) == "string" then
			return chrome.attachHint(bp, { slot = slot, image = value })
		end
		local variant, errors = themePackage.normalizeVariant(value, "RadialMenu skin")
		assert(#errors == 0, "Controls.RadialMenu: invalid image state skin")
		return chrome.attachHint(bp, { slot = slot, imageVariants = variant })
	end
	local holding = signal(false)
	local retiring = signal({})
	local opened, visible, path, candidate = signal(false), signal(false), signal({}), signal(nil)
	local layout =
		signal({ sectors = {}, levels = {}, mode = "radial", cx = 0, cy = 0, inner = 0, outer = 0, target = 44 })
	local navLabel = memo(function(use)
		return if #use(path) > 0 then "Back" else "Close"
	end)
	local navigationItem = { id = "$navigation", label = navLabel }
	local ringNavigation = (center == "empty" or center == "content" or center == "root" or center == "close")
		and not preset:find("left")
		and not preset:find("right")
	local alpha = signal(0)
	local graph, rootNode, rect, delivery, clock, fade = nil, nil, nil, nil, nil, nil
	local focusPaintAllowed = nil
	local gesture, analog, disposed = false, false, false
	local capture, focusPaths, pendingFocus = nil, {}, nil
	local focusRects, axisUpdate = {}, nil
	local controller, previewPath, detachPreview = nil, nil, nil
	local followX, followY, followRadius = nil, nil, nil
	local fixedClearance = nil
	local callbacksError = nil
	local api = {} :: any
	local refreshing = false
	local sourceItems = read(spec.items)
	local function notify(fn: any, ...: any)
		if fn then
			local ok, err = pcall(fn, ...)
			if not ok then
				callbacksError = tostring(err)
			end
		end
	end
	local function itemAt(chain: { string }, itemId: string?): any
		local list = sourceItems
		for _, hop in chain do
			local found
			for _, item in list do
				if item.id == hop then
					found = item
					break
				end
			end
			if not found or not found.children or read(found.enabled) == false or read(found.hidden) == true then
				return nil
			end
			list = read(found.children)
		end
		if itemId == nil then
			return list
		end
		for _, item in list do
			if item.id == itemId then
				return item
			end
		end
		return nil
	end
	local function available(): boolean
		return not disposed
			and read(spec.enabled) ~= false
			and rootNode ~= nil
			and (delivery == nil or delivery.available(rootNode.path))
	end
	local function aim(value: number)
		if fade then
			fade:setTarget(value)
		else
			alpha:set(value)
			if value == 0 then
				visible:set(false)
			end
		end
	end
	function api.close()
		if disposed or not opened:get() then
			return
		end
		capture = nil
		gesture = false
		analog = false
		candidate:set(nil)
		opened:set(false)
		holding:set(false)
		-- Keep the displayed page intact while its complete visual retires.
		aim(0)
		pendingFocus = if spec.launcher ~= false then "Launcher" else nil
		notify(spec.onClose)
	end
	local function setCandidate(s: any)
		if s and (read(s.item.enabled) == false or read(s.item.hidden) == true) then
			s = nil
		end
		candidate:set(s and s.key or nil)
		if s and graph and focusPaths[s.key] then
			graph.focusOn(focusPaths[s.key])
		end
	end
	local transitionOrigin = nil
	local function refresh()
		if refreshing or disposed or not rect then
			return
		end
		if visible:get() and not opened:get() then
			return
		end
		local focal = read(spec.anchor)
		if
			spec.anchor
			and (
				not focal
				or focal.visible == false
				or type(focal.x) ~= "number"
				or type(focal.y) ~= "number"
				or focal.x < rect.x
				or focal.x > rect.x + rect.w
				or focal.y < rect.y
				or focal.y > rect.y + rect.h
			)
		then
			api.close()
			return
		end
		if (gesture or analog) and follow ~= "always" then
			return
		end
		refreshing = true
		local metrics = env:get("themeMetrics"):get() or snapshot.neutral()
		local target = math.max(
			snapshot.resolveNumber(metrics, "targetSizes.minimum") or 44,
			snapshot.resolveNumber(metrics, "controlSizes.regular.height") or 44
		)
		local textScale = env:get("preferredTextSize"):get() or 1
		target = math.max(target, target * textScale + (env:get("preferredTextOffset"):get() or 0))
		local gap = snapshot.resolveNumber(metrics, "s") or 8
		local requestedBand = snapshot.resolveNumber(metrics, read(spec.ringWidth))
		local band = if requestedBand
			then math.max(target * 1.4, requestedBand * textScale + (env:get("preferredTextOffset"):get() or 0) * 1.9)
			else math.min(96, math.max(target * 1.9, 76))
		local labelHeight = if requestedBand then math.min(target, band * 0.45) else target
		local start, sweep = geometry.arc(preset)
		local minimumClearance = snapshot.resolveNumber(metrics, read(spec.clearance))
		if focal and type(focal.clearance) == "number" and focal.clearance >= 0 and focal.clearance < math.huge then
			local measured = math.max(minimumClearance or 0, focal.clearance)
			if follow == "fixed" then
				if not opened:get() then
					fixedClearance = measured
				end
				measured = fixedClearance or measured
			elseif clock then
				if not followRadius then
					followRadius = scope:own(clock:spring(measured, "object"))
				end
				if not opened:get() then
					followRadius:snap(measured)
				end
				followRadius:setTarget(measured)
				measured = math.max(minimumClearance or 0, followRadius:get())
			end
			minimumClearance = measured
		end
		local inner = math.max(
			if preset == "circle" then target * 0.6 else target,
			minimumClearance or (if preset == "circle" then target * 0.6 else target * 1.5)
		)
		local count = #sourceItems
		local radius = math.max(
			inner + band / 2,
			(target + 6)
				* 1.55
				/ math.max(
					0.15,
					2 * math.sin(math.rad(math.min(180, sweep / (if distribution == "compass" then 8 else count)) / 2))
				)
				/ 0.86
		)
		inner = math.max(inner, radius - band / 2)
		local outer = inner + band
		local pad = target / 2 + gap
		local cx, cy = rect.w / 2, rect.h / 2
		if sweep == 90 then
			cx = if preset:find("left") then pad else rect.w - pad
			cy = if preset:find("top") then pad else rect.h - pad
		end
		local anchor = focal
		if anchor then
			if
				anchor.visible == false
				or type(anchor.x) ~= "number"
				or type(anchor.y) ~= "number"
				or anchor.x < rect.x
				or anchor.x > rect.x + rect.w
				or anchor.y < rect.y
				or anchor.y > rect.y + rect.h
			then
				refreshing = false
				api.close()
				return
			end
			if follow ~= "fixed" or not opened:get() then
				cx, cy = anchor.x - rect.x, anchor.y - rect.y
			else
				cx, cy = layout:get().cx, layout:get().cy
			end
		end
		if anchor and follow ~= "fixed" and clock then
			if not followX then
				followX = scope:own(clock:spring(cx, "object"))
				followY = scope:own(clock:spring(cy, "object"))
			end
			if not opened:get() then
				followX:snap(cx)
				followY:snap(cy)
			end
			followX:setTarget(cx)
			followY:setTarget(cy)
			cx, cy = followX:get(), followY:get()
		end
		local previewRole = snapshot.roleOf(metrics, "body")
		local previewSize =
			textMetrics.reservedSize(previewRole.size, textScale, env:get("preferredTextOffset"):get() or 0)
		local previewHeight =
			Facet.text.measure("Mg", previewRole.fontKey, previewSize, math.huge, previewRole.lineHeight).height
		local verticalReserve = math.max(32, previewHeight) + gap
		local function fits(r: number): boolean
			if sweep == 360 then
				return cx - r >= gap
					and cy - r >= verticalReserve
					and cx + r <= rect.w - gap
					and cy + r <= rect.h - verticalReserve
			end
			return rect.w - pad - gap >= r and rect.h - pad - gap >= r
		end
		-- Spend decorative spacing before switching to a list. Compact geometry
		-- still owns full-size touch targets and preserves authored center clearance.
		if not fits(outer) then
			local room = if sweep == 360
				then math.min(cx - gap, cy - verticalReserve, rect.w - gap - cx, rect.h - verticalReserve - cy)
				else math.min(rect.w - pad - gap, rect.h - pad - gap)
			local ratio = math.clamp(room / outer, 0, 1)
			local compactInner =
				math.max(inner * ratio, minimumClearance or (if preset == "circle" then target * 0.6 else target))
			local compactBand = math.min(band * ratio, room - compactInner)
			if compactBand >= target and fits(compactInner + compactBand) then
				inner, band = compactInner, compactBand
				outer = inner + band
			end
		end
		local mode = if gestureSelection == "direction" or (fits(outer) and band >= target) then "radial" else "list"
		local all, levels = {}, {}
		local chain = path:get()
		local list = sourceItems
		local prefix = {}
		local inheritedNav, inheritedExpansion = navigation, expansion
		local function append(depth: number, a: number, sw: number, ri: number, ro: number, dist: string)
			local entries = list
			local nav = ringNavigation and depth == #chain
			if nav then
				entries = table.clone(list)
				local entry = navigationItem
				entry.slot = nil
				if dist == "compass" then
					local used = {}
					for _, item in list do
						used[item.slot] = true
					end
					for _, slot in { "SW", "S", "SE", "NW", "W", "E", "NE", "N" } do
						if not used[slot] then
							entry.slot = slot
							break
						end
					end
					nav = entry.slot ~= nil
				elseif sw == 360 then
					a = 225 - #list * 360 / (#list + 1)
				end
				if nav then
					table.insert(entries, entry)
				end
			end
			local sectors = geometry.sectors(entries, a, sw, dist, ri, ro)
			for _, s in sectors do
				s.navigation = s.id == "$navigation"
				s.labelBox = geometry.labelBounds(s, labelHeight)
				s.gap = math.max(1, (snapshot.resolveNumber(metrics, "xs") or 4) / 2)
				if
					gestureSelection ~= "direction"
					and (
						(appearance == "wedges" and s.labelBox.w < target)
						or (appearance == "buttons" and s.size < target)
					)
				then
					mode = "list"
				end
				local contentWidth, contentHeight = s.labelBox.w, s.labelBox.h
				if contentFit ~= "none" and appearance == "wedges" then
					local role = snapshot.roleOf(metrics, "control")
					local size =
						textMetrics.reservedSize(role.size, textScale, env:get("preferredTextOffset"):get() or 0)
					local function measure(text)
						return Facet.text.measure(text, role.fontKey, size, math.huge, role.lineHeight)
					end
					local m = table.clone(measure(if s.navigation then "x" else read(s.item.label)))
					local padding = snapshot.buttonPadding(metrics, {})
					local available = math.max(1, s.labelBox.w - padding * 2)
					local compact = s.item.compactLabel
						or (if s.item.icon then { icon = s.item.icon, prefer = s.item.labelStyle == "icon" } else nil)
					local iconSize = snapshot.resolveNumber(metrics, "iconSizes.medium") or size
					local imageContent = s.navigation
					if s.navigation then
						-- Navigation paints a themed image, not the narrow ASCII floor.
						m.width, m.height = iconSize, iconSize
					elseif s.item.labelStyle == "both" and s.item.icon then
						m.height = math.max(m.height, iconSize)
						m.width += iconSize + (snapshot.resolveNumber(metrics, "xs") or 4)
						if m.width > available then
							m.width = iconSize
						end
					elseif compact and (m.width > available or (type(compact) == "table" and compact.prefer)) then
						if type(compact) == "string" then
							m = measure(compact)
						elseif compact.text then
							m = measure(compact.text)
						elseif compact.image then
							m.width, m.height = iconSize, iconSize
							imageContent = true
						else
							m.width = math.max(size, iconSize)
							m.height = math.max(m.height, iconSize)
						end
					end
					contentWidth, contentHeight = math.min(available, m.width), math.min(s.labelBox.h, m.height)
					-- Button still owns its compact representation and theme padding.
					-- Preserve a theme spacing step for native glyph rounding at device scale.
					s.labelBox.w = math.min(
						s.labelBox.w,
						math.ceil(contentWidth + padding * 2 + (snapshot.resolveNumber(metrics, "xs") or 4) * 2)
					)
					if imageContent then
						-- Images and navigation share the fitted content box with their renderer.
						-- Give paint and fitting the same rectangle, independent of label text.
						s.labelBox.w, s.labelBox.h = contentWidth, contentHeight
					end
				end
				s.paint = geometry.fitContent(
					s,
					contentWidth,
					contentHeight,
					(snapshot.resolveNumber(metrics, "xs") or 4)
						+ (snapshot.resolveNumber(metrics, "strokes.hairline") or 1) / 2,
					contentFit
				)
				s.depth = depth
				s.chain = table.clone(prefix)
				s.key = table.concat(prefix, "/") .. ":" .. s.id
				table.insert(all, s)
			end
			if contentFit == "radial" then
				local near, far = ro, ri
				for _, s in sectors do
					near, far = math.min(near, s.paint.inner), math.max(far, s.paint.outer)
				end
				for _, s in sectors do
					s.paint.inner, s.paint.outer = near, far
				end
			end
			table.insert(levels, { depth = depth, inner = ri, outer = ro, start = a, sweep = sw })
		end
		append(0, start, sweep, inner, outer, distribution)
		for depth, hop in chain do
			local parent
			for _, s in all do
				if s.depth == depth - 1 and s.id == hop then
					parent = s
				end
			end
			local entry = itemAt(prefix, hop)
			if not entry then
				break
			end
			inheritedNav = entry.navigation or inheritedNav
			inheritedExpansion = entry.expansion or inheritedExpansion
			table.insert(prefix, hop)
			list = read(entry.children)
			local ri, ro = outer + gap, outer + gap + band
			local a, sw = start, sweep
			if inheritedExpansion == "fan" and parent then
				sw = math.min(sweep, math.max(parent.span, #list * 32))
				a = parent.angle - sw / 2
				if sweep < 360 then
					a = math.clamp(a, start, start + sweep - sw)
				end
			end
			if inheritedNav == "replace" or not fits(ro) or mode == "list" then
				all = {}
				levels = {}
				ri, ro = inner, inner + band
				a, sw = start, sweep
			end
			append(depth, a, sw, ri, ro, "even")
			outer = ro
		end
		local old = layout:get()
		local same = old.cx == cx
			and old.cy == cy
			and old.target == target
			and old.mode == mode
			and #old.sectors == #all
		if same then
			for i, v in all do
				local o = old.sectors[i]
				if
					o.key ~= v.key
					or o.item ~= v.item
					or o.inner ~= v.inner
					or o.outer ~= v.outer
					or o.angle ~= v.angle
					or o.span ~= v.span
					or o.labelBox.w ~= v.labelBox.w
					or o.paint.inner ~= v.paint.inner
					or o.paint.outer ~= v.paint.outer
					or o.paint.span ~= v.paint.span
				then
					same = false
					break
				end
			end
		end
		if not same then
			if opened:get() and clock and mode ~= "list" then
				local nextKeys, previous = {}, table.clone(retiring:get())
				local prior = {}
				for _, v in old.sectors do
					prior[v.key] = v
				end
				for _, v in previous do
					prior[v.key] = v
				end
				for _, v in all do
					local before = prior[v.key]
					v.origin = if before then before.origin else transitionOrigin
				end
				for _, v in all do
					nextKeys[v.key] = true
				end
				local seen = {}
				for _, v in previous do
					seen[v.key] = true
				end
				for _, v in old.sectors do
					if not nextKeys[v.key] and not seen[v.key] then
						table.insert(previous, v)
					end
				end
				local pending = {}
				for _, v in previous do
					if not nextKeys[v.key] then
						table.insert(pending, v)
					end
				end
				retiring:set(pending)
			elseif mode == "list" then
				retiring:set({})
			end
			layout:set({
				sectors = all,
				levels = levels,
				mode = mode,
				cx = cx,
				cy = cy,
				inner = inner,
				outer = outer,
				target = target,
				gap = gap,
			})
		end
		refreshing = false
	end
	function api.open(): boolean
		if
			not available()
			or opened:get()
			or (spec.anchor and (not read(spec.anchor) or read(spec.anchor).visible == false))
		then
			return false
		end
		path:set({})
		refresh()
		opened:set(true)
		visible:set(true)
		aim(1)
		notify(spec.onOpen)
		return true
	end
	function api.back()
		if #path:get() == 0 then
			api.close()
			return
		end
		capture = nil
		gesture = false
		analog = false
		local chain = table.clone(path:get())
		local last = table.remove(chain)
		pendingFocus = table.concat(chain, "/") .. ":" .. last
		path:set(chain)
		candidate:set(nil)
		refresh()
	end
	function api.root()
		capture = nil
		gesture = false
		analog = false
		path:set({})
		candidate:set(nil)
		refresh()
	end
	function api.toggle()
		if opened:get() then
			api.close()
		else
			api.open()
		end
	end
	local function commit(s: any): boolean
		if not opened:get() or not available() or not s then
			return false
		end
		if s.navigation then
			api.back()
			return true
		end
		local item = itemAt(s.chain, s.id)
		if not item or read(item.enabled) == false or read(item.hidden) == true then
			setCandidate(nil)
			return false
		end
		capture = nil
		gesture = false
		analog = false
		if item.children then
			transitionOrigin = { x = s.x, y = s.y, angle = s.angle, inner = s.paint.inner, outer = s.paint.outer }
			local chain = table.clone(s.chain)
			table.insert(chain, item.id)
			path:set(chain)
			candidate:set(nil)
			refresh()
			transitionOrigin = nil
			pendingFocus = "first"
			return true
		end
		-- Completion precedes callbacks; gameplay never waits on exit animation.
		local state = item.checked or item.selected
		local policy = item.completion
			or (if item.dismiss ~= nil then (if item.dismiss then "close" else "stay") else spec.completion)
			or (if state then "stay" else "close")
		if policy == "close" then
			api.close()
		elseif policy == "back" then
			api.back()
		elseif policy == "root" then
			api.root()
		end
		if state then
			local value = if item.checked then not state:get() else item.value
			if state:get() ~= value then
				state:set(value)
				notify(item.onChange, value)
			end
		else
			notify(item.onSelect)
		end
		return true
	end
	local function candidateSector(): any
		for _, s in layout:get().sectors do
			if s.key == candidate:get() then
				return s
			end
		end
		return nil
	end
	function api.select(itemId: string): boolean
		for _, s in layout:get().sectors do
			if s.id == itemId and s.depth == #path:get() then
				return commit(s)
			end
		end
		return false
	end
	local function hit(pos: any, drag: boolean): any
		local l = layout:get()
		if l.mode == "list" then
			return nil
		end
		if drag and gestureSelection == "direction" then
			local dx, dy = pos.x - rect.x - l.cx, pos.y - rect.y - l.cy
			local magnitude = math.sqrt(dx * dx + dy * dy)
			if magnitude < l.target * 0.6 then
				return nil
			end
			local level = l.levels[#l.levels]
			local radius = (level.inner + level.outer) / 2
			return geometry.hit(
				l.sectors,
				dx / magnitude * radius,
				dy / magnitude * radius,
				"wedges",
				0,
				candidateSector()
			)
		end
		return geometry.hit(
			l.sectors,
			pos.x - rect.x - l.cx,
			pos.y - rect.y - l.cy,
			appearance,
			if drag then l.target else nil,
			candidateSector()
		)
	end
	local function cancel()
		local was = capture
		holding:set(false)
		capture = nil
		gesture = false
		analog = false
		setCandidate(nil)
		if was and was.opened then
			api.close()
		else
			refresh()
		end
	end
	local function down(_p: string, pos: any): boolean
		if not available() or capture then
			return false
		end
		refresh()
		local wasClosed = not opened:get()
		holding:set(wasClosed)
		if wasClosed then
			api.open()
		end
		local l = layout:get()
		local dx, dy = pos.x - rect.x - l.cx, pos.y - rect.y - l.cy
		if
			not wasClosed
			and dx * dx + dy * dy < l.inner * l.inner
			and spec.centerPassThrough
			and (center == "empty" or center == "content")
		then
			return false
		end
		capture = { x = pos.x, y = pos.y, opened = wasClosed, moved = false }
		gesture = true
		if followX and follow ~= "always" then
			followX:snap(l.cx)
			followY:snap(l.cy)
			if followRadius then
				followRadius:snap(followRadius:get())
			end
		end
		if not wasClosed then
			setCandidate(hit(pos, false))
		end
		return true
	end
	local function move(_p: string, pos: any)
		if not capture then
			return
		end
		local dx, dy = pos.x - capture.x, pos.y - capture.y
		if dx * dx + dy * dy >= 64 then
			capture.moved = true
		end
		if capture.moved then
			setCandidate(hit(pos, true))
		end
	end
	local function centerAction()
		if center == "root" then
			api.root()
		elseif center == "close" then
			api.close()
		elseif center == "back" then
			api.back()
		end
	end
	local function up(_p: string, pos: any)
		if not capture then
			return
		end
		local was = capture
		holding:set(false)
		capture = nil
		gesture = false
		local s = hit(pos, was.moved)
		if s then
			commit(s)
		elseif was.moved then
			if was.opened then
				api.close()
			else
				setCandidate(nil)
				refresh()
			end
		elseif not was.opened then
			local l = layout:get()
			local dx, dy = pos.x - rect.x - l.cx, pos.y - rect.y - l.cy
			if dx * dx + dy * dy < l.inner * l.inner then
				centerAction()
			else
				api.close()
			end
		end
	end
	local content = memo(function(use)
		if not use(visible) then
			return {}
		end
		local rows, keys = {}, {}
		for _, v in use(layout).sectors do
			keys[v.key] = true
			if use(layout).mode ~= "list" or not v.navigation then
				table.insert(rows, v)
			end
		end
		for _, v in use(retiring) do
			if use(layout).mode ~= "list" and not keys[v.key] then
				table.insert(rows, v)
			end
		end
		return rows
	end)
	local function navigationGlyph(icon: any, owner: any): any
		return UI.ZStack({
			id = "GlyphBox",
			width = UI.fill(),
			height = UI.fill(),
			alignH = "center",
			alignV = "center",
			children = {
				UI.ForEach({
					id = "GlyphVariants",
					items = owner:own(core:memo(function(use)
						return { use(icon) }
					end)),
					key = function(name)
						return name
					end,
					row = function(name)
						return chrome.attachHint(
							UI.Text({
								id = "Glyph",
								text = themePackage.iconGlyph(name) or "?",
								width = UI.fill(),
								height = UI.fill(),
								textAlign = "center",
							}),
							{ icon = name }
						)
					end,
				}),
			},
		})
	end
	-- One opening transform keeps neighboring wedge seams in the same native
	-- coordinate space. Row transforms are reserved for branch transitions.
	local openingScale = memo(function(use)
		return if use(env:get("reducedMotion")) then 1 else 0.12 + 0.88 * math.clamp(use(alpha), 0, 1)
	end)
	local ringDiameter = memo(function(use)
		local l = use(layout)
		return math.ceil(l.outer + l.target) * 2
	end)
	local function row(s: any, rs: any)
		rs = rs or scope
		local item = s.item
		local current = rs:own(core:memo(function(use)
			for _, v in use(layout).sectors do
				if v.key == s.key then
					return v
				end
			end
			for _, v in use(retiring) do
				if v.key == s.key then
					return v
				end
			end
			return s
		end))
		local function rm(fn)
			return rs:own(core:memo(fn))
		end
		local progress = if clock then rs:own(clock:spring(0, "object")) else nil
		if progress then
			rs:own(core:effect(function(use)
				local active = false
				for _, v in use(layout).sectors do
					if v.key == s.key then
						active = true
						break
					end
				end
				progress:setTarget(if active then 1 else 0)
				if not active and progress:get() < 0.015 then
					local pending = {}
					for _, v in retiring:get() do
						if v.key ~= s.key then
							table.insert(pending, v)
						end
					end
					if #pending ~= #retiring:get() then
						retiring:set(pending)
					end
				end
			end))
			rs:own(core:observe(progress, function(value)
				if value < 0.015 and progress:getTarget() == 0 then
					local pending = {}
					for _, v in retiring:get() do
						if v.key ~= s.key then
							table.insert(pending, v)
						end
					end
					retiring:set(pending)
				end
			end))
		end
		local opacity = rm(function(use)
			return if progress then math.clamp(use(progress), 0, 1) else 1
		end)
		local contraction = rm(function(use)
			if use(env:get("reducedMotion")) then
				return 1
			end
			return if appearance == "wedges"
				then 1
				else 0.82 + 0.18 * (if progress then math.clamp(use(progress), 0, 1) else 1)
		end)
		local displayed = rm(function(use)
			local v = use(current)
			if appearance ~= "wedges" or not s.origin or use(env:get("reducedMotion")) then
				return v
			end
			local p = if progress then math.clamp(use(progress), 0, 1) else 1
			local origin = s.origin
			local factor = 0.25 + 0.75 * p
			local painted = table.clone(v.paint)
			painted.angle = origin.angle + geometry.delta(v.paint.angle, origin.angle) * factor
			painted.span *= factor
			painted.inner = origin.inner + (painted.inner - origin.inner) * p
			painted.outer = origin.outer + (painted.outer - origin.outer) * p
			local result = table.clone(v)
			result.paint = painted
			local originRadius = (origin.inner + origin.outer) / 2
			local radius = originRadius + (math.sqrt(v.x * v.x + v.y * v.y) - originRadius) * p
			result.x = math.sin(math.rad(painted.angle)) * radius
			result.y = -math.cos(math.rad(painted.angle)) * radius
			return result
		end)
		local travel = rm(function(use)
			if appearance == "wedges" or use(env:get("reducedMotion")) then
				return { x = 0, y = 0 }
			end
			local v = use(current)
			local origin = s.origin or { x = 0, y = 0 }
			local amount = 0.3 * (1 - (if progress then math.clamp(use(progress), 0, 1) else 1))
			return { x = (origin.x - v.x) * amount, y = (origin.y - v.y) * amount }
		end)
		local active = rm(function(use)
			for _, v in use(layout).sectors do
				if v.key == s.key then
					return true
				end
			end
			return false
		end)
		local eligible = rm(function(use)
			local v = use(current).item
			return (if UI.isReadable(v.enabled) then use(v.enabled) else v.enabled) ~= false
				and (if UI.isReadable(v.hidden) then use(v.hidden) else v.hidden) ~= true
		end)
		local enabled = rm(function(use)
			return use(opened) and use(active) and use(eligible)
		end)

		local selected = rm(function(use)
			local v = use(current).item
			return use(candidate) == s.key
				or (graph ~= nil and use(graph.focused) == focusPaths[s.key] and (focusPaintAllowed == nil or use(
					focusPaintAllowed
				)))
				or use(path)[s.depth + 1] == s.id
				or (v.checked and use(v.checked) == true)
				or (v.selected and use(v.selected) == v.value)
				or false
		end)
		local isList = rm(function(use)
			return use(layout).mode == "list"
		end)

		-- Roblox rounds offset sizes to whole pixels. Match the disc's parity so
		-- its center and the label's center resolve to the same native pixel.
		local function buttonLabelSize(size, wanted)
			local n = math.floor(wanted)
			return n - (n - math.floor(size)) % 2
		end
		local labelWidth = rm(function(use)
			local v = use(current)
			return fixed(if appearance == "wedges" then v.labelBox.w else buttonLabelSize(v.size, v.size * 0.72))
		end)
		local labelHeight = rm(function(use)
			local v = use(current)
			return fixed(if appearance == "wedges" then v.labelBox.h else buttonLabelSize(v.size, use(layout).target))
		end)

		local label = item.label
		local compact = item.compactLabel
			or (if item.icon then { icon = item.icon, prefer = item.labelStyle == "icon" } else nil)
		local button = UI.Button({
			id = "Item",
			label = label,
			compactLabel = compact,
			padding = if type(compact) == "table" and compact.image then 0 else nil,
			enabled = eligible,
			focusable = enabled,
			focusVisual = if appearance == "buttons" and (item.buttonSurface or buttonSurface) == "none"
				then "default"
				else "none",
			selected = selected,
			surface = "plain",
			role = item.role or "default",
			width = labelWidth,
			height = labelHeight,
			help = item.description,
			onPointerDown = function(p, pos)
				return enabled:get() and down(p, pos)
			end,
			onPointerMove = move,
			onPointerUp = up,
			onPointerCancel = function()
				cancel()
			end,
		})
		if item.labelStyle == "both" and item.icon then
			local function iconNode(name)
				return chrome.attachHint(
					UI.Text({
						id = name,
						text = themePackage.iconGlyph(item.icon) or "?",
						textSize = "control",
						width = if name == "Compact" then UI.fill() else nil,
						height = if name == "Compact" then UI.fill() else nil,
					}),
					{ icon = item.icon }
				)
			end
			button = UI.Button({
				id = "Item",
				label = label,
				enabled = eligible,
				focusable = enabled,
				focusVisual = if appearance == "buttons" and (item.buttonSurface or buttonSurface) == "none"
					then "default"
					else "none",
				selected = selected,
				surface = "plain",
				role = item.role or "default",
				width = labelWidth,
				height = labelHeight,
				padding = 0,
				help = item.description,
				onPointerDown = function(p, pos)
					return enabled:get() and down(p, pos)
				end,
				onPointerMove = move,
				onPointerUp = up,
				onPointerCancel = cancel,
				children = {
					UI.ViewThatFits({
						id = "Representation",
						width = UI.fill(),
						height = UI.fill(),
						children = {
							UI.ZStack({
								id = "FullBox",
								width = UI.fill(),
								height = UI.fill(),
								alignH = "center",
								alignV = "center",
								children = {
									UI.HStack({
										id = "Full",
										gap = "xs",
										children = {
											iconNode("Icon"),
											UI.Text({ id = "Text", text = label, textSize = "control" }),
										},
									}),
								},
							}),
							UI.ZStack({
								id = "CompactBox",
								width = UI.fill(),
								height = UI.fill(),
								alignH = "center",
								alignV = "center",
								children = { iconNode("Compact") },
							}),
						},
					}),
				},
			})
		end
		if s.navigation then
			button = UI.Button({
				id = "Item",
				label = navLabel,
				enabled = eligible,
				focusable = enabled,
				focusVisual = if appearance == "buttons" and (item.buttonSurface or buttonSurface) == "none"
					then "default"
					else "none",
				surface = "plain",
				width = labelWidth,
				height = labelHeight,
				padding = 0,
				onPointerDown = function(p, pos)
					return enabled:get() and down(p, pos)
				end,
				onPointerMove = move,
				onPointerUp = up,
				onPointerCancel = cancel,
				children = {
					navigationGlyph(
						rm(function(use)
							return if #use(path) > 0 then "chevron.leading" else "close"
						end),
						rs
					),
				},
			})
		end
		button = chrome.attachHint(button, { slot = "none" })
		-- Surface, outline and content share ONE compositor and transform. Path2D's
		-- gradient alpha is not reliable on all clients; fade its containing group.
		local paint = rm(function(use)
			return geometry.paint(use(displayed).paint)
		end)
		local edge = rm(function(use)
			return snapshot.resolveNumber(use(env:get("themeMetrics")) or snapshot.neutral(), "strokes.hairline") or 1
		end)
		local bounds = rm(function(use)
			local v = use(displayed)
			local pad = use(edge) * 2
			if appearance == "buttons" then
				return {
					x = v.x - v.size / 2 - pad,
					y = v.y - v.size / 2 - pad,
					w = v.size + pad * 2,
					h = v.size + pad * 2,
				}
			end
			local p = use(paint)
			local x = math.min(p.x - pad, v.x - v.labelBox.w / 2)
			local y = math.min(p.y - pad, v.y - v.labelBox.h / 2)
			return {
				x = x,
				y = y,
				w = math.max(p.x + p.w + pad, v.x + v.labelBox.w / 2) - x,
				h = math.max(p.y + p.h + pad, v.y + v.labelBox.h / 2) - y,
			}
		end)
		local painted = {}
		if appearance == "wedges" then
			for _, outline in { false, true } do
				table.insert(
					painted,
					UI.Path({
						id = if outline then "Outline" else "Sector",
						width = rm(function(use)
							return fixed(use(paint).w)
						end),
						height = rm(function(use)
							return fixed(use(paint).h)
						end),
						offsetX = rm(function(use)
							return use(paint).x - use(bounds).x
						end),
						offsetY = rm(function(use)
							return use(paint).y - use(bounds).y
						end),
						points = rm(function(use)
							return if outline then use(paint).outline else use(paint).points
						end),
						closed = outline,
						thickness = rm(function(use)
							local v = use(displayed).paint
							-- Path2D stroke pixels do not inherit the compositor UIScale.
							return (if outline then use(edge) else v.outer - v.inner)
								* use(contraction)
								* use(openingScale)
						end),
						tint = rm(function(use)
							return {
								role = if outline
									then "contentSecondary"
									elseif use(selected) then "accent"
									else "control",
								blend = 1,
							}
						end),
					})
				)
			end
		else
			local nativeSurface = (item.buttonSurface or buttonSurface) == "native"
			table.insert(
				painted,
				skin(
					UI.Box({
						id = "Disc",
						corners = UI.cornersData("pill"),
						height = rm(function(use)
							return fixed(use(displayed).size)
						end),
						width = rm(function(use)
							return fixed(use(displayed).size)
						end),
						offsetX = rm(function(use)
							return use(edge) * 2
						end),
						offsetY = rm(function(use)
							return use(edge) * 2
						end),
						tint = if not nativeSurface
							then nil
							else rm(function(use)
								return {
									role = if use(selected) then "accent" else "control",
									blend = 1,
									transparency = 0.22 * (use(env:get("effectiveTransparency")) or 1),
								}
							end),
						stroke = if not nativeSurface
							then nil
							else UI.strokeData({
								color = "contentSecondary",
								thickness = "hairline",
								transparency = 0.35,
							}),
					}),
					item.decoration or (spec.skin and spec.skin.item),
					"control"
				)
			)
		end
		table.insert(
			painted,
			UI.ZStack({
				id = "Label",
				alignH = "center",
				alignV = "center",
				width = labelWidth,
				height = labelHeight,
				offsetX = rm(function(use)
					local v = use(displayed)
					return v.x - use(bounds).x - use(labelWidth).px / 2
				end),
				offsetY = rm(function(use)
					local v = use(displayed)
					return v.y - use(bounds).y - use(labelHeight).px / 2
				end),
				children = { button },
			})
		)
		local visual = UI.ZStack({
			id = "Visual",
			width = rm(function(use)
				return fixed(use(bounds).w)
			end),
			height = rm(function(use)
				return fixed(use(bounds).h)
			end),
			offsetX = rm(function(use)
				local b = use(bounds)
				return use(ringDiameter) / 2 + b.x - (b.x + b.w / 2) * (1 - use(contraction)) + use(travel).x
			end),
			offsetY = rm(function(use)
				local b = use(bounds)
				return use(ringDiameter) / 2 + b.y - (b.y + b.h / 2) * (1 - use(contraction)) + use(travel).y
			end),
			opacity = opacity,
			scale = contraction,
			children = { UI.Anchor({ id = "Content", width = UI.fill(), height = UI.fill(), children = painted }) },
		})

		local form = switch(
			"Form",
			isList,
			function()
				return UI.Button({
					id = "Item",
					label = label,
					enabled = enabled,
					selected = selected,
					width = UI.fill(),
					height = fixed("controlSizes.large.height"),
					help = item.description,
				})
			end,
			function()
				return UI.Anchor({ id = "SectorHost", width = UI.fill(), height = UI.fill(), children = { visual } })
			end,
			rs,
			rm(function(use)
				return if use(isList) then fixed("controlSizes.large.height") else UI.fill()
			end)
		)
		return form
	end
	local launchDim = memo(function(use)
		return fixed(use(layout).target)
	end)
	local launcherPadding = memo(function(use)
		return (snapshot.resolveNumber(use(env:get("themeMetrics")) or snapshot.neutral(), "strokes.hairline") or 1) * 2
	end)
	local launcherBounds = memo(function(use)
		return fixed(use(layout).target + use(launcherPadding) * 2)
	end)
	local isCorner = preset:find("left") ~= nil or preset:find("right") ~= nil
	-- One exit clock owns both sides of the handoff. Lists clear their paint
	-- first so the returning launcher never appears on top of a retiring row.
	local listOpacity = memo(function(use)
		local a = math.clamp(use(alpha), 0, 1)
		return if not use(opened) and spec.launcher ~= false and not isCorner then math.clamp(a * 2 - 1, 0, 1) else a
	end)
	local launcherOpacity = memo(function(use)
		-- A newly mounted scene has no solved origin yet.
		if use(layout).outer == 0 then
			return 0
		end
		if not use(visible) then
			return 1
		end
		if use(opened) or isCorner then
			return 0
		end
		local a = math.clamp(use(alpha), 0, 1)
		return if use(layout).mode == "list" then math.clamp(1 - a * 2, 0, 1) else 1 - a
	end)
	local navigationSize = memo(function(use)
		return if isCorner
			then math.floor(32 + (use(layout).target - 32) * (1 - math.clamp(use(alpha), 0, 1)) + 0.5)
			else 32
	end)
	local lx = memo(function(use)
		return use(layout).cx - use(layout).target / 2
	end)
	local ly = memo(function(use)
		return use(layout).cy - use(layout).target / 2
	end)
	local function roundButton(props: any): any
		props.surface = nil
		props.padding = 0
		-- Compact native discs do not inherit rectangular panel-art insets.
		-- Explicit skin.launcher/center is still applied by the caller below.
		return chrome.attachHint(UI.Button(props), { slot = "none" })
	end
	local launcher = roundButton({
		id = "Launcher",

		label = spec.label or "Quick actions",
		icon = spec.icon or "more",
		surface = "plain",
		shape = "circle",
		width = launchDim,
		enabled = memo(function(use)
			local e = spec.enabled
			return (if UI.isReadable(e) then use(e) else e) ~= false
		end),
		onPointerDown = down,
		onPointerMove = move,
		onPointerUp = up,
		onPointerCancel = function()
			cancel()
		end,
	})

	local status = memo(function(use)
		local key = use(candidate)
		for _, s in use(layout).sectors do
			if s.key == key then
				local v = s.item.label
				return if UI.isReadable(v) then use(v) else v
			end
		end
		local chain, labels = {}, {}
		for _, hop in use(path) do
			local item = itemAt(chain, hop)
			if item then
				table.insert(labels, if UI.isReadable(item.label) then use(item.label) else item.label)
			end
			table.insert(chain, hop)
		end
		return if #labels > 0 then table.concat(labels, " › ") else spec.label or "Quick actions"
	end)
	local radialRows = UI.ForEach({
		id = "Items",
		items = content,
		key = function(s)
			return s.key
		end,
		row = row,
	})
	local body = switch(
		"Presentation",
		memo(function(use)
			return use(layout).mode == "list"
		end),
		function()
			return UI.ZStack({
				id = "ListArea",
				width = UI.fill(),
				height = UI.fill(),
				opacity = listOpacity,
				children = {
					UI.Anchor({
						id = "Content",
						width = UI.fill(),
						height = UI.fill(),
						children = {
							UI.ScrollView({
								id = "List",
								axis = "y",
								width = UI.fill(),
								height = memo(function(use)
									local metrics = use(env:get("themeMetrics")) or snapshot.neutral()
									local gap = snapshot.resolveNumber(metrics, "s") or 8
									local rowHeight = snapshot.resolveNumber(metrics, "controlSizes.large.height") or 56
									local count = #use(content)
									local natural = count * rowHeight + math.max(0, count - 1) * gap + gap * 2
									return fixed(
										math.max(1, math.min(natural, (rect and rect.h or 0) - use(layout).target * 2))
									)
								end),
								offsetY = memo(function(use)
									return use(layout).target
								end),
								padding = "s",
								gap = "s",
								surface = "raised",
								children = { radialRows },
							}),
						},
					}),
				},
			})
		end,
		function()
			local children = { radialRows }
			if spec.skin and spec.skin.background then
				table.insert(
					children,
					1,
					skin(
						UI.Box({
							id = "Artwork",
							surface = "plain",
							width = memo(function(use)
								return fixed(use(layout).outer * 2)
							end),
							height = memo(function(use)
								return fixed(use(layout).outer * 2)
							end),
							offsetX = memo(function(use)
								return use(ringDiameter) / 2 - use(layout).outer
							end),
							offsetY = memo(function(use)
								return use(ringDiameter) / 2 - use(layout).outer
							end),
						}),
						spec.skin.background,
						"control"
					)
				)
			end
			-- Place a stable, even-sized compositor around the focal point. Animating
			-- a compensating offset on a viewport-sized group truncates to integer
			-- UDim offsets and can move the entire ring one pixel at scale == 1.
			return UI.Anchor({
				id = "RingArea",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					UI.ZStack({
						id = "Rings",
						width = memo(function(use)
							return fixed(use(ringDiameter))
						end),
						height = memo(function(use)
							return fixed(use(ringDiameter))
						end),
						opacity = alpha,
						scale = openingScale,
						offsetX = memo(function(use)
							return use(layout).cx - use(ringDiameter) / 2
						end),
						offsetY = memo(function(use)
							return use(layout).cy - use(ringDiameter) / 2
						end),
						children = {
							UI.Anchor({
								id = "Content",
								width = UI.fill(),
								height = UI.fill(),
								children = children,
							}),
						},
					}),
				},
			})
		end
	)
	-- The central square is wholly inside the transparent circle: no painted
	-- sector leaks scene input. Four native rectangles also cut the catcher.
	local hole = if spec.centerPassThrough and (center == "empty" or center == "content")
		then memo(function(use)
			local l = use(layout)
			local half = l.inner / math.sqrt(2)
			return {
				x = (rect and rect.x or 0) + l.cx - half,
				y = (rect and rect.y or 0) + l.cy - half,
				w = half * 2,
				h = half * 2,
			}
		end)
		else nil
	local captureRegions = memo(function(use)
		local l = use(layout)
		local h = if hole then use(hole) else nil
		return aperture.rects(
			{ x = 0, y = 0, w = rect and rect.w or 0, h = rect and rect.h or 0 },
			if h then { x = h.x - (rect and rect.x or 0), y = h.y - (rect and rect.y or 0), w = h.w, h = h.h } else nil
		)
	end)
	local blueprint = UI.Anchor({
		id = id,
		width = spec.width or UI.fill(),
		height = spec.height or UI.fill(),
		children = {
			UI.When({
				id = "Visible",
				condition = visible,
				thenView = function()
					return body
				end,
			}),
			UI.When({
				id = "Capture",
				condition = memo(function(use)
					return use(opened) and use(layout).mode == "radial"
				end),
				thenView = function()
					return UI.ForEach({
						id = "Planes",
						items = captureRegions,
						key = function(r)
							return r.id
						end,
						row = function(r, rs)
							local function property(key)
								return rs:own(core:memo(function(use)
									for _, v in use(captureRegions) do
										if v.id == r.id then
											return v[key]
										end
									end
									return 0
								end))
							end
							local width, height = property("w"), property("h")
							return UI.Grip({
								id = "Plane",
								focusVisual = "none",
								width = rs:own(core:memo(function(use)
									return fixed(use(width))
								end)),
								height = rs:own(core:memo(function(use)
									return fixed(use(height))
								end)),
								offsetX = property("x"),
								offsetY = property("y"),
								onPointerDown = down,
								onPointerMove = move,
								onPointerUp = up,
								onPointerCancel = cancel,
							})
						end,
					})
				end,
			}),
			UI.When({
				id = "Trigger",
				condition = memo(function(use)
					return spec.launcher ~= false and (use(launcherOpacity) > 0 or use(holding))
				end),
				thenView = function()
					return UI.ZStack({
						id = "LauncherVisual",
						width = launcherBounds,
						height = launcherBounds,
						padding = launcherPadding,
						offsetX = memo(function(use)
							return use(lx) - use(launcherPadding)
						end),
						offsetY = memo(function(use)
							return use(ly) - use(launcherPadding)
						end),
						opacity = launcherOpacity,
						children = { skin(launcher, spec.skin and spec.skin.launcher, "control") },
					})
				end,
			}),
			UI.When({
				id = "Navigation",
				condition = memo(function(use)
					return use(visible)
				end),
				thenView = function()
					local children = {
						UI.When({
							id = "BackAffordance",
							condition = memo(function(use)
								if use(layout).mode == "list" or preset:find("left") or preset:find("right") then
									return true
								end
								if not ringNavigation then
									return false
								end
								for _, s in use(layout).sectors do
									if s.navigation then
										return false
									end
								end
								return true
							end),
							thenView = function()
								return roundButton({
									id = "Back",
									label = memo(function(use)
										return if isCorner and not use(opened)
											then spec.label or "Quick actions"
											else use(navLabel)
									end),
									surface = "plain",
									shape = "circle",
									width = memo(function(use)
										return fixed(use(navigationSize))
									end),
									children = {
										UI.ZStack({
											width = UI.fill(),
											height = UI.fill(),
											children = {
												UI.ZStack({
													id = "NavigationIcon",
													width = UI.fill(),
													height = UI.fill(),
													opacity = if isCorner then alpha else 1,
													children = {
														navigationGlyph(
															memo(function(use)
																return if #use(path) > 0
																	then "chevron.leading"
																	else "close"
															end),
															scope
														),
													},
												}),
												if isCorner
													then UI.ZStack({
														id = "LauncherIcon",
														width = UI.fill(),
														height = UI.fill(),
														opacity = memo(function(use)
															return 1 - math.clamp(use(alpha), 0, 1)
														end),
														children = {
															navigationGlyph(
																memo(function()
																	return spec.icon or "more"
																end),
																scope
															),
														},
													})
													else nil,
											},
										}),
									},
									anchor = memo(function(use)
										return if use(layout).mode == "list"
												and not preset:find("left")
												and not preset:find("right")
											then "topRight"
											else "topLeft"
									end),
									offsetX = memo(function(use)
										return if use(layout).mode == "list"
												and not preset:find("left")
												and not preset:find("right")
											then 0
											else use(layout).cx - use(navigationSize) / 2
									end),
									offsetY = memo(function(use)
										return if use(layout).mode == "list"
												and not preset:find("left")
												and not preset:find("right")
											then 0
											else use(layout).cy - use(navigationSize) / 2
									end),
									onActivate = function()
										if isCorner and not opened:get() then
											api.open()
										else
											api.back()
										end
									end,
								})
							end,
						}),
						UI.Text({
							id = "Candidate",
							text = status,
							disclose = true,
							width = memo(function(use)
								return fixed(math.max(0, (rect and rect.w or 0) - use(layout).target * 1.5))
							end),
							anchor = if preset:find("bottom") then "topLeft" else "bottom",
							textSize = "body",
						}),
					}
					local centerChildren = {}
					if
						center ~= "empty"
						and center ~= "content"
						and not preset:find("left")
						and not preset:find("right")
					then
						table.insert(
							centerChildren,
							skin(
								roundButton({
									id = "Center",
									label = if center == "back"
										then navLabel
										else (spec.centerLabel or (if center == "root" then "Home" else "Close")),
									shape = "circle",
									width = fixed(32),
									offsetX = memo(function(use)
										return use(layout).cx - 16
									end),
									offsetY = memo(function(use)
										return use(layout).cy - 16
									end),
									surface = "plain",
									children = {
										navigationGlyph(
											memo(function(use)
												return if center == "root"
													then "chevron.up"
													elseif center == "back" and #use(path) > 0 then "chevron.leading"
													else "close"
											end),
											scope
										),
									},
									onActivate = function()
										centerAction()
									end,
								}),
								spec.skin and spec.skin.center,
								"control"
							)
						)
					elseif center == "content" and spec.centerContent then
						table.insert(
							centerChildren,
							UI.Anchor({
								id = "Context",
								width = launchDim,
								height = launchDim,
								offsetX = lx,
								offsetY = ly,
								children = { spec.centerContent },
							})
						)
					end
					table.insert(
						children,
						UI.When({
							id = "RadialCenter",
							condition = memo(function(use)
								return use(layout).mode ~= "list"
							end),
							thenView = function()
								return UI.Anchor({
									id = "CenterHost",
									width = UI.fill(),
									height = UI.fill(),
									children = centerChildren,
								})
							end,
						})
					)
					return UI.ZStack({
						id = "Chrome",
						width = UI.fill(),
						height = UI.fill(),
						enabled = if isCorner then nil else opened,
						opacity = memo(function(use)
							if isCorner or use(opened) then
								return 1
							end
							return if use(layout).mode == "list" then use(listOpacity) else math.clamp(use(alpha), 0, 1)
						end),
						children = {
							UI.Anchor({ id = "Content", width = UI.fill(), height = UI.fill(), children = children }),
						},
					})
				end,
			}),
		},
	})
	local function walk(node: any)
		if node.id == "Item" then
			for _, s in layout:get().sectors do
				-- ForEach keys are single path segments; inspect the row's ancestor identity.
				if node.path:find("/[" .. s.key .. "]/", 1, true) then
					focusPaths[s.key] = node.path
				end
			end
		elseif node.id == "Launcher" then
			focusPaths.Launcher = node.path
		end
		for _, child in node.children or {} do
			walk(child)
		end
	end
	blueprint = Facet.contribution.attach(blueprint, {
		bindController = function(c)
			controller = c
		end,
		transientScope = { active = opened },
		outsideDismiss = { active = opened, dismiss = api.close, consume = true, passThroughRect = hole },
		bindFocusGraph = function(g, allowed)
			graph = g
			focusPaintAllowed = allowed
		end,
		bindMotion = function(c)
			if fade then
				return
			end
			clock = c
			fade = scope:own(c:spring(alpha:get(), "object"))
			scope:own(core:observe(fade, function()
				alpha:set(fade:get())
			end))
			scope:own(fade:onSettle(function()
				if not opened:get() then
					visible:set(false)
					retiring:set({})
				end
			end))
		end,
		bindInputScope = function(s)
			if delivery == s then
				return
			end
			delivery = s
			scope:own(s.onTick(function()
				if disposed then
					return
				end
				if not available() and opened:get() then
					cancel()
					api.close()
				end
				if pendingFocus and graph then
					local dest = focusPaths[pendingFocus]
					if pendingFocus == "first" then
						for _, v in layout:get().sectors do
							if v.depth == #path:get() then
								dest = focusPaths[v.key]
								break
							end
						end
					end
					if dest then
						graph.focusOn(dest)
						pendingFocus = nil
					end
				end
				if axisUpdate then
					axisUpdate()
				end
				refresh()
			end))
			s.onDispose(function()
				cancel()
				api.close()
				if delivery == s then
					delivery = nil
					rootNode = nil
				end
			end)
		end,
		bindActionSystem = function(system)
			if axisUpdate then
				return
			end
			axisUpdate = radialInput.bind(core, scope, system, opened, function()
				return available() and opened:get()
			end, function(x, y)
				if gesture then
					return
				end
				local magnitude = math.sqrt(x * x + y * y)
				if magnitude < 0.25 then
					analog = false
					refresh()
					return
				end
				if magnitude < 0.35 and not analog then
					return
				end
				local entering = not analog
				analog = true
				local l = layout:get()
				if entering and followX and follow ~= "always" then
					followX:snap(l.cx)
					followY:snap(l.cy)
					if followRadius then
						followRadius:snap(followRadius:get())
					end
				end
				local level = l.levels[#l.levels]
				if not level then
					return
				end
				local r = (level.inner + level.outer) / 2
				setCandidate(
					geometry.hit(l.sectors, x / magnitude * r, y / magnitude * r, "wedges", l.target, candidateSector())
				)
			end)
		end,
		syncGeometry = function(rectOf, node)
			rootNode = node
			if not node then
				cancel()
				api.close()
				return
			end
			local nextRect = rectOf(node.path)
			if rect and nextRect and (rect.w ~= nextRect.w or rect.h ~= nextRect.h) and gesture then
				cancel()
			end
			rect = nextRect
			if controller and previewPath ~= node.path then
				if detachPreview then
					detachPreview()
				end
				previewPath = node.path
				detachPreview = controller.attachContextGestures(node.path, {
					onHover = function(pos)
						if opened:get() and not gesture and not analog and available() then
							setCandidate(hit(pos, false))
						end
					end,
				})
			end
			focusPaths = {}
			walk(node)
			focusRects = {}
			local function census(n)
				if
					n.class == "Button"
					and read(n.props.focusable) ~= false
					and read(n.props.enabled) ~= false
					and read(n.props.hidden) ~= true
				then
					focusRects[n.path] = rectOf(n.path)
				end
				for _, v in n.children or {} do
					census(v)
				end
			end
			census(node)
			refresh()
		end,
		focusMoved = function(p)
			for key, dest in focusPaths do
				if p == dest and key ~= "Launcher" then
					candidate:set(key)
					return
				end
			end
		end,
		focusGroups = function(node)
			local order = {}
			local function visit(n)
				if n.class == "Button" and read(n.props.focusable) ~= false and read(n.props.enabled) ~= false then
					table.insert(order, n.path)
				end
				for _, c in n.children or {} do
					visit(c)
				end
			end
			visit(node)
			return { { name = "radial-" .. id, axis = "horizontal", entry = "first", order = order } }
		end,
		handleActivate = function(p, meta)
			if
				(p == focusPaths.Launcher or (layout:get().mode == "radial" and p:match("/Item$")))
				and meta
				and (meta.pointer or meta.pointerType or meta.kind == "pointer")
			then
				-- The captured pointer release owns commits, never GuiButton.Activated.
				return true
			end
			if p == focusPaths.Launcher then
				api.toggle()
				return true
			end
			for _, s in layout:get().sectors do
				if focusPaths[s.key] == p then
					return commit(s)
				end
			end
			return false
		end,
		navigateIntercept = function(direction)
			-- Linear fallback uses the presenter's standard navigation and
			-- scroll-to-visible path; only radial geometry needs this intercept.
			if not opened:get() or not graph or layout:get().mode == "list" then
				return false
			end
			local from = focusRects[graph.focused:get()]
			if not from then
				return false
			end
			local vectors = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }
			local v = vectors[direction]
			if not v then
				return false
			end
			local best, score = nil, math.huge
			for p, r in focusRects do
				if r and p ~= graph.focused:get() then
					local dx, dy = r.x + r.w / 2 - from.x - from.w / 2, r.y + r.h / 2 - from.y - from.h / 2
					local along = dx * v[1] + dy * v[2]
					local cross = math.abs(dx * v[2] - dy * v[1])
					local cost = along + cross * 3
					if along > 1 and cost < score then
						best, score = p, cost
					end
				end
			end
			if best then
				graph.focusOn(best)
				return true
			end
			return false
		end,
		handleCancel = function()
			if opened:get() then
				api.back()
				return true
			end
			return false
		end,
	})
	-- Validate reactive item/ancestor changes and restore the nearest legal context.
	local facts = memo(function(use)
		local items = if UI.isReadable(spec.items) then use(spec.items) else spec.items
		local function track(list)
			for _, item in list do
				for _, key in { "enabled", "hidden", "label" } do
					if UI.isReadable(item[key]) then
						use(item[key])
					end
				end
				if item.children then
					local children = if UI.isReadable(item.children) then use(item.children) else item.children
					track(children)
				end
			end
		end
		track(items)
		if UI.isReadable(spec.enabled) then
			use(spec.enabled)
		end
		return { items = items }
	end)
	scope:own(core:observe(facts, function(value)
		local ok, err = pcall(validate, value.items, distribution)
		if not ok then
			callbacksError = tostring(err)
			cancel()
			api.close()
			return
		end
		sourceItems = value.items
		local chain = {}
		for _, hop in path:get() do
			if
				not itemAt(chain, hop)
				or not itemAt(chain, hop).children
				or read(itemAt(chain, hop).enabled) == false
				or read(itemAt(chain, hop).hidden) == true
			then
				break
			end
			table.insert(chain, hop)
		end
		if #chain ~= #path:get() then
			cancel()
			path:set(chain)
		end
		if read(spec.enabled) == false then
			cancel()
			api.close()
		end
		if candidate:get() then
			local s = candidateSector()
			if not s or not itemAt(s.chain, s.id) or read(itemAt(s.chain, s.id).enabled) == false then
				setCandidate(nil)
			end
		end
		refresh()
	end))
	if spec.holdAction then
		assert(
			type(spec.holdAction.onPressed) == "function" and type(spec.holdAction.onReleased) == "function",
			"Controls.RadialMenu: holdAction must be a semantic Bool action"
		)
		scope:own(spec.holdAction.onPressed(function()
			api.open()
		end))
		scope:own(spec.holdAction.onReleased(function()
			if analog then
				commit(candidateSector())
			else
				cancel()
			end
		end))
	end
	scope:own(function()
		disposed = true
		if detachPreview then
			detachPreview()
			detachPreview = nil
		end
		capture = nil
		gesture = false
		analog = false
	end)
	api.isOpen = opened
	api.isVisible = visible
	api.openPath = path
	local function dump()
		local l = layout:get()
		local sectors = {}
		for _, s in l.sectors do
			table.insert(sectors, {
				id = s.id,
				key = s.key,
				depth = s.depth,
				angle = s.angle,
				span = s.span,
				inner = s.inner,
				outer = s.outer,
				paintInner = s.paint.inner,
				paintOuter = s.paint.outer,
				paintSpan = s.paint.span,
				x = l.cx + s.x,
				y = l.cy + s.y,
				size = s.size,
				path = focusPaths[s.key],
			})
		end
		return {
			schema = "facet-radial_menu-dump/1",
			id = id,
			open = opened:get(),
			visible = visible:get(),
			openPath = table.clone(path:get()),
			presentation = l.mode,
			preset = preset,
			appearance = appearance,
			buttonSurface = buttonSurface,
			contentFit = contentFit,
			center = center,
			centerPassThrough = spec.centerPassThrough == true,
			windowRect = rect,
			centerX = l.cx,
			centerY = l.cy,
			candidate = candidate:get(),
			captured = gesture,
			analog = analog,
			sectors = sectors,
			opacity = alpha:get(),
			lastError = callbacksError,
		}
	end
	return table.freeze({
		blueprint = blueprint,
		api = table.freeze(api),
		dump = dump,
		dispose = function()
			if not disposed then
				api.close()
				scope:dispose()
			end
		end,
	})
end
return radial
