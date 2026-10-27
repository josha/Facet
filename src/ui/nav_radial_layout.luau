--!strict
local geometry = require("./nav_radial_geometry")
local Types = require("./types")
local Radial = require("./radial_types")
local RadialProps = require("./radial_props")
local ComposeTypes = require("../vendor/compose/core")
local MenuTypes = require("./nav_radial_menu")

export type Arrangement<V> = {
	viewport: ComposeTypes.Value<Vector2>,
	origin: ComposeTypes.Value<Vector2>,
	launcher: Instance?,
	anchorSize: ComposeTypes.Value<Vector2>?,
	centerTarget: ComposeTypes.Value<Vector2>,
	following: ComposeTypes.Value<boolean>,
	center: ComposeTypes.Value<Vector2>,
	captionPadding: (use: ComposeTypes.Use) -> number,
	wordWidths: ComposeTypes.Value<{ [string]: number }>,
	layout: ComposeTypes.Value<Radial.Layout<V>>,
	sectors: ComposeTypes.Value<{ Radial.Sector<V> }>,
	fallback: ComposeTypes.Value<boolean>,
}

return function<V>(ctx: Types.Context, menu: MenuTypes.Menu<V>, root: Frame): Arrangement<V>
	local Compose, runtime, read = ctx.Compose, ctx.runtime, ctx.read
	local typeOf: (unknown) -> string = runtime.host.typeNameOf or typeof
	local V2 = ctx.types.Vector2
	local spec: RadialProps.RadialMenuSpec<V> = menu.spec
	local session = menu.session
	local corner: boolean = menu.corner
	local ringWidth: (use: ComposeTypes.Use?) -> number? = menu.ringWidth
	local follow: string = menu.follow
	local reduced: (use: ComposeTypes.Use?) -> boolean = menu.reduced
	local glyphOnly: (item: Radial.RadialItemBase<V>) -> boolean = menu.glyphOnly
	local appearance: string = menu.appearance
	local contentFit: Radial.ContentFit = menu.contentFit
	local gestureSelection: string = menu.gestureSelection
	local interacting: ComposeTypes.Value<boolean> = menu.interacting
	local path: ComposeTypes.Value<{ string }> = menu.path
	local candidate: ComposeTypes.Value<string?> = menu.candidate
	local layer = ctx.config.overlayParent :: GuiBase2d?
		or root:FindFirstAncestorWhichIsA("LayerCollector") :: GuiBase2d?
	local measured = layer ~= nil and layer.AbsoluteSize.X > 0 and layer.AbsoluteSize.Y > 0
	local viewport = Compose.cell(if measured then (layer :: GuiBase2d).AbsoluteSize else V2.new(640, 480))
	local origin = Compose.cell(if measured then (layer :: GuiBase2d).AbsolutePosition else V2.zero)
	local anchor = read(spec.anchor)
	local launcher = if anchor == nil then root:FindFirstChild("Launcher") else nil
	local focal = anchor or launcher
	local nativeAnchor = focal and (typeof(focal) == "Instance" or (type(focal) == "table" and focal.IsA))
	local anchorPosition = if nativeAnchor then ctx.observe.AbsolutePosition(focal :: GuiObject) else nil
	local anchorSize = if nativeAnchor then ctx.observe.AbsoluteSize(focal :: GuiObject) else nil
	if nativeAnchor and anchorPosition and anchorSize then
		anchorPosition:set((focal :: GuiObject).AbsolutePosition)
		anchorSize:set((focal :: GuiObject).AbsoluteSize)
	end
	local shelves: { { position: ComposeTypes.ReadOnlyValue<Vector2>, size: ComposeTypes.ReadOnlyValue<Vector2> } } = {}
	local shelf = if nativeAnchor and not corner then (focal :: Instance).Parent else nil
	while shelf and shelf ~= layer and shelf:IsA("GuiObject") do
		table.insert(shelves, {
			position = ctx.observe.AbsolutePosition(shelf :: GuiObject),
			size = ctx.observe.AbsoluteSize(shelf :: GuiObject),
		})
		shelf = shelf.Parent
	end
	local rawInner = Compose.formula(function(use: ComposeTypes.Use): number
		local inner =
			math.max(24, if type(read(spec.clearance, use)) == "number" then read(spec.clearance, use) else 40)
		local focal = read(spec.anchor, use)
		if typeOf(focal) ~= "Instance" and type(focal) == "table" and type(focal.clearance) == "number" then
			inner = math.max(inner, focal.clearance)
		end
		if anchorSize then
			local extent = use(anchorSize)
			inner = math.max(inner, math.max(extent.X, extent.Y) / 2)
		end
		return inner
	end)
	local rawCenter = Compose.formula(function(use: ComposeTypes.Use)
		local size = use(viewport)
		local live = read(spec.anchor, use)
		local preset = spec.preset or "donut"
		local at = V2.new(
			if string.find(preset, "left") then 16 elseif string.find(preset, "right") then size.X - 16 else size.X / 2,
			if string.find(preset, "top") then 16 elseif string.find(preset, "bottom") then size.Y - 16 else size.Y / 2
		)
		if anchorPosition and anchorSize and (launcher == nil or use(anchorSize).X > 0) then
			at = use(anchorPosition) + use(anchorSize) / 2 - use(origin)
		elseif live and live.x and live.y then
			at = V2.new(live.x, live.y) - use(origin)
		end
		local _, sweep = geometry.arc(preset)
		if sweep < 360 then
			return at
		end
		local reach = use(rawInner) + (ringWidth(use) or 44)
		return V2.new(
			math.clamp(at.X, reach + 12, math.max(reach + 12, size.X - reach - 12)),
			math.clamp(at.Y, reach + 20, math.max(reach + 20, size.Y - reach - 20))
		)
	end)
	local centerTarget = Compose.cell(rawCenter:peek())
	local innerTarget = Compose.cell(rawInner:peek())
	Compose.watch(function(use: ComposeTypes.Use)
		local at, inner = use(rawCenter), use(rawInner)
		if follow ~= "fixed" and (follow == "always" or not use(interacting)) then
			centerTarget:set(at)
			innerTarget:set(inner)
		end
	end)
	local frozenCenter = Compose.cell(centerTarget:peek())
	local centerSpring = ctx.motionSpring("quick")
	local movingCenter = runtime.spring(function(use: ComposeTypes.Use)
		return use(centerTarget)
	end, { period = centerSpring.period, damping = centerSpring.damping })
	local following = Compose.cell(false)
	local center = Compose.formula(function(use: ComposeTypes.Use)
		if use(interacting) and follow ~= "always" then
			return use(frozenCenter)
		end
		return if reduced(use) or not use(following) then use(centerTarget) else use(movingCenter)
	end)
	session.freezeCenter = function()
		frozenCenter:set(center:peek())
	end
	local function captionPadding(use: ComposeTypes.Use): number
		local package = read(ctx.config.theme, use)
		local skin = package and package.chrome and package.chrome.control
		local insets = skin and skin.contentInsets
		return 2 * ctx.controlSize(nil, "paddingX", use)
			+ (if insets then insets.left or 0 else 0)
			+ (if insets then insets.right or 0 else 0)
	end

	local wordWidths: ComposeTypes.Value<{ [string]: number }> = Compose.cell({})
	Compose.watch(function(use: ComposeTypes.Use)
		local captions: { [string]: boolean } = {}
		local function visit(items: { Radial.RadialItem<V> }, prefix: string)
			for _, item in items do
				local key = prefix .. "/" .. item.id
				captions[key] = true
				if item.children then
					visit(read(item.children, use), if prefix == "" then item.id else key)
				end
			end
		end
		visit(read(spec.items, use), "")
		local retained: { [string]: number } = {}
		local changed = false
		for key, width in wordWidths:peek() do
			if captions[key] then
				retained[key] = width
			else
				changed = true
			end
		end
		if changed then
			wordWidths:set(retained)
		end
	end)
	local function solve(use: ComposeTypes.Use, flatten: boolean): Radial.Layout<V>
		local size, at, inner = use(viewport), use(centerTarget), use(innerTarget)
		local start, sweep = geometry.arc(spec.preset or "donut")
		local room = if sweep == 360
			then math.min(at.X - 12, size.X - at.X - 12, at.Y - 20, size.Y - at.Y - 20)
			else math.min(size.X - 28, size.Y - 28)
		local minimum = ctx.metric("targetSizes.minimum", use)
		for _, space in shelves do
			local position, extent = use(space.position) - use(origin), use(space.size)
			local fit = math.min(
				at.X - position.X,
				position.X + extent.X - at.X,
				at.Y - position.Y,
				position.Y + extent.Y - at.Y
			)
			if fit >= inner + minimum then
				room = math.min(room, fit)
				break
			end
		end
		local radius = math.max(inner + 1, math.min(240, room))
		local band = math.max(minimum, radius - inner)
		local floor = math.min(band, math.max(minimum, ringWidth(use) or 0))
		local items = read(spec.items, use)
		local prefix: { string } = {}
		local levels: { { Radial.Sector<V> } } = {}
		local ring = inner
		local padding = ctx.metric("space.s", use)
		local textSize = ctx.metric("typography.control.size", use)
		local iconSize = ctx.controlSize(nil, "iconSize", use)
		local function estimate(item: Radial.RadialItemBase<V>): (number, number)
			if glyphOnly(item) then
				return iconSize, iconSize
			end
			local label = read(item.label, use) or ""
			return (utf8.len(label) or #label) * textSize * 0.6 + captionPadding(use), textSize
		end
		local navigation, expansion = spec.navigation or "replace", spec.expansion or "fan"
		local currentStart, currentSweep = start, sweep
		local replaced = 0
		local function append(): { Radial.Sector<V> }
			local shown: { Radial.RadialItem<V> } = {}
			local seen: { [string]: boolean } = {}
			for _, item in items do
				assert(type(item.id) == "string" and not seen[item.id], "RadialMenu items require unique ids per level")
				seen[item.id] = true
				assert(not (item.checked and item.selected), "RadialMenu state items require checked or selected")
				assert(
					not ((item.checked or item.selected) and (item.children or item.onSelect)),
					"RadialMenu state items use onChange"
				)
				if read(item.hidden, use) ~= true then
					table.insert(shown, item)
				end
			end
			if spec.center and spec.center ~= "back" and not corner and #prefix == #use(path) then
				local navigationItem: Radial.RadialItemBase<V> & { checked: nil?, selected: nil?, value: nil?, onChange: nil? } =
					{
						id = "$navigation",
						label = if #prefix > 0 then "Back" else "Close",
						icon = if #prefix > 0 then "chevron.leading" else "close",
						labelStyle = "icon" :: "icon",
					}
				if #prefix == 0 and spec.distribution == "compass" then
					local slots: { [string]: boolean } = {}
					for _, item in shown do
						if item.slot then
							slots[item.slot] = true
						end
					end
					local compassSlots: { Radial.CompassSlot } = { "SW", "S", "SE", "NW", "W", "E", "NE", "N" }
					for _, slot in compassSlots do
						if not slots[slot] then
							navigationItem.slot = slot :: Radial.CompassSlot
							break
						end
					end
					if navigationItem.slot then
						table.insert(shown, navigationItem)
					end
				else
					table.insert(shown, navigationItem)
				end
			end
			local ri = ring
			local distribution = if #prefix == 0 then spec.distribution or "even" else "even"
			local levelStart = currentStart
			local last = shown[#shown]
			if last and last.id == "$navigation" and distribution == "even" and currentSweep == 360 then
				levelStart = 225 - (#shown - 1) * 360 / #shown
			end
			local levelBand = band
			do
				local extent, target = 0, 0
				for _, probe in geometry.sectors(shown, levelStart, currentSweep, distribution, ri, ri + 1) do
					local width, height = estimate((probe.item :: unknown) :: Radial.RadialItemBase<V>)
					local ux, uy = math.sin(math.rad(probe.angle)), -math.cos(math.rad(probe.angle))
					local hw, hh = width / 2 + padding, height / 2 + padding
					local middle = ri + math.abs(hw * ux) + math.abs(hh * uy)
					for _, dx in { -hw, hw } do
						for _, dy in { -hh, hh } do
							local x, y = middle * ux + dx, middle * uy + dy
							extent = math.max(extent, math.sqrt(x * x + y * y) - ri)
						end
					end
					local chord = 2 * math.sin(math.rad(math.min(probe.span, 180) / 2)) * 0.86
					target = math.max(target, 2 * (math.max(minimum, width, height) / chord - ri))
				end
				local wanted = 2 * math.ceil(math.max(extent, target) / 2)
				levelBand = math.clamp(math.max(wanted, replaced), floor, band)
			end
			ring = ri + levelBand + 4
			local sectors = geometry.sectors(shown, levelStart, currentSweep, distribution, ri, ri + levelBand)
			for _, sector in sectors do
				sector.path = table.clone(prefix)
				sector.key = table.concat(prefix, "/") .. "/" .. sector.id
			end
			table.insert(levels, sectors)
			return sectors
		end
		local current = append()
		for _, id in use(path) do
			local parent: Radial.Sector<V>?
			for sectorIndex = 1, #current do
				local sector = current[sectorIndex]
				if sector.id == id and read(sector.item.enabled, use) ~= false then
					parent = sector
					break
				end
			end
			if not parent or not parent.item.children then
				break
			end
			navigation = if flatten then "replace" else parent.item.navigation or navigation
			expansion = parent.item.expansion or expansion
			table.insert(prefix, id)
			items = read(parent.item.children, use)
			replaced = if navigation == "replace" then parent.outer - parent.inner else 0
			if navigation == "replace" then
				levels, ring = {}, inner
				currentStart, currentSweep = start, sweep
			elseif expansion == "fan" then
				currentSweep = math.min(sweep, math.max(parent.span, #items * 32))
				currentStart = parent.angle - currentSweep / 2
				if sweep < 360 then
					currentStart = math.clamp(currentStart, start, start + sweep - currentSweep)
				end
			else
				currentStart, currentSweep = start, sweep
			end
			current = append()
		end
		local result: { Radial.Sector<V> } = {}
		local list = room < inner + band or band < minimum
		for levelIndex = 1, #levels do
			local level = levels[levelIndex]
			for sectorIndex = 1, #level do
				local sector = level[sectorIndex]
				list = list or sector.size < 44 or sector.outer > room
				if
					appearance == "wedges"
					and not sector.item.icon
					and not glyphOnly(sector.item)
					and contentFit ~= "none"
				then
					local width, height = estimate(sector.item)
					local bounds = geometry.labelBounds(sector, height)
					local captionReady = (use(wordWidths)[sector.key] or 0) > 0
					list = list or room - inner < width or (captionReady and (bounds.w < width or bounds.h < height))
				end
				table.insert(result, sector)
			end
		end
		list = list and gestureSelection ~= "direction"
		if list then
			result = {}
			for _, sector in current do
				if sector.id ~= "$navigation" then
					table.insert(result, sector)
				end
			end
		end
		for index, sector in result do
			sector.index, sector.list = index, list
		end
		return { sectors = result, list = list, inner = inner, path = prefix }
	end
	local layout = Compose.formula(function(use: ComposeTypes.Use): Radial.Layout<V>
		local stacked = solve(use, false)
		if not stacked.list or #use(path) == 0 then
			return stacked
		end
		local flat = solve(use, true)
		return if flat.list then stacked else flat
	end)
	local sectors = Compose.formula(function(use: ComposeTypes.Use)
		return use(layout).sectors
	end)
	local fallback = Compose.formula(function(use: ComposeTypes.Use)
		return use(layout).list
	end)
	session.candidateSector = function()
		local entries = sectors:peek()
		for sectorIndex = 1, #entries do
			local sector = entries[sectorIndex]
			if sector.key == candidate:peek() then
				return sector
			end
		end
		return nil
	end
	return {
		viewport = viewport,
		origin = origin,
		launcher = launcher,
		anchorSize = anchorSize,
		centerTarget = centerTarget,
		following = following,
		center = center,
		captionPadding = captionPadding,
		wordWidths = wordWidths,
		layout = layout,
		sectors = sectors,
		fallback = fallback,
	}
end
