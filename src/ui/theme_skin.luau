--!strict
local ComposeTypes = require("../vendor/compose/core")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local decoration = require("./native_decoration")
local support = require("./theme_support")

local read, typesFor, deeplyFrozen, shadowPresets =
	support.read, support.typesFor, support.deeplyFrozen, support.shadowPresets

local function variantAsset(
	value: ThemeTypes.AssetSource?,
	state: ThemeTypes.SkinState,
	selected: boolean
): (string?, { rotation: number?, tint: ThemeTypes.RGB? })
	if type(value) == "string" then
		return value, {}
	end
	if type(value) ~= "table" then
		return nil, {}
	end
	local linked = ((value :: unknown) :: { asset: unknown }).asset
	if linked ~= nil then
		return linked :: string, value :: { asset: string, rotation: number?, tint: ThemeTypes.RGB? }
	end
	local variants = value :: ThemeTypes.AssetVariants
	local chosen = (
		if state == "hover"
			then variants.hover
			elseif state == "pressed" then variants.pressed
			elseif state == "selected" then variants.selected
			elseif state == "disabled" then variants.disabled
			else nil
	)
		or (if selected then variants.selected else nil)
		or variants.default
	if type(chosen) == "table" then
		return chosen.asset, chosen
	end
	return chosen, {}
end

type ImageLayer = {
	id: string,
	text: boolean?,
	textInsets: ThemeTypes.Insets?,
	Image: string,
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2,
	BackgroundTransparency: number,
	BorderSizePixel: number,
	ZIndex: number,
	ScaleType: Enum.ScaleType,
	TileSize: UDim2,
	SliceCenter: Rect,
	SliceScale: number,
	ResampleMode: Enum.ResamplerMode,
	Rotation: number,
	ImageColor3: Color3,
}

type MountedImage = {
	node: ImageLabel,
	properties: ImageLayer,
	caption: ComposeTypes.Cell<ImageLayer>?,
	visible: boolean,
}

local function grown(types: Engine.RobloxTypes, value: ImageLayer, fit: Vector2): UDim2
	local size = value.Size
	if not value.text or fit.X <= 0 then
		return size
	end
	local inset: ThemeTypes.Insets = value.textInsets or {}
	return types.UDim2.new(
		size.X.Scale,
		math.max(size.X.Offset, math.ceil(fit.X) + (inset.left or 0) + (inset.right or 0)),
		size.Y.Scale,
		math.max(size.Y.Offset, math.ceil(fit.Y) + (inset.top or 0) + (inset.bottom or 0))
	)
end

return function(
	neutral: ThemeTypes.ThemePackage,
	paint: support.Paint,
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
	slot: string,
	options: ThemeTypes.SkinOptions?
): Frame
	local color, white = paint.color, paint.white
	local settings: ThemeTypes.SkinOptions = options or {}
	local function shadowTransparency(base: number, use: ComposeTypes.Use): number
		local fade = math.clamp(read(settings.shadowTransparency, use) or 0, 0, 1)
		return if fade == 0 then base else 1 - (1 - base) * (1 - fade)
	end
	local types, Host = typesFor(settings), (runtime.constructors :: unknown) :: Engine.Host
	local D2, V2 = types.UDim2, types.Vector2
	local function axis(value: ThemeTypes.ShadowAxis?): (number, number)
		local resolved: ThemeTypes.ShadowAxis = value or {}
		return resolved.scale or 0, resolved.offset or 0
	end
	local function pair(value: ThemeTypes.ShadowPair?): UDim2
		local resolved: ThemeTypes.ShadowPair = value or {}
		local x, xo = axis(resolved.x)
		local y, yo = axis(resolved.y)
		return D2.new(x, xo, y, yo)
	end
	if not Compose.isReadable(packageOrReadable) and type(packageOrReadable) ~= "function" then
		local package = read(packageOrReadable) or neutral
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		if recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
			local root = Host.Frame "Skin" {
				Size = settings.Size or D2.fromScale(1, 1),
				AnchorPoint = settings.AnchorPoint or V2.new(0, 0),
				Position = settings.Position or D2.fromScale(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = settings.ZIndex or 0,
			}
			local declaredShadow = recipe and recipe.shadow
			local shadow: ThemeTypes.Shadow? = if type(declaredShadow) == "string"
				then (package.style.shadows or {})[declaredShadow] or shadowPresets[declaredShadow]
				else declaredShadow
			if type(declaredShadow) == "string" then
				assert(shadow ~= nil, "Facet theme unknown shadow preset")
			end
			if shadow then
				runtime.mount(function()
					return Host.UIShadow "ChromeShadow" {
						Color = color(types, shadow.color or { r = 0, g = 0, b = 0 }),
						Transparency = if settings.shadowTransparency == nil
							then shadow.transparency or 0.5
							else function(use: ComposeTypes.Use)
								return shadowTransparency(shadow.transparency or 0.5, use)
							end,
						ZIndex = shadow.zIndex or -1,
						Enabled = shadow.enabled ~= false,
						BlurRadius = types.UDim.new(axis(shadow.blurRadius)),
						Offset = pair(shadow.offset),
						Spread = pair(shadow.spread),
					}
				end, settings.target or root)
			end
			if settings.target ~= nil then
				root.Size = D2.fromOffset(0, 0)
				root.Visible = false
				return root
			end
			return root
		end
	end
	type CompiledLayers = {
		package: ThemeTypes.ThemePackage,
		state: ThemeTypes.SkinState,
		selected: boolean,
		direction: string?,
		fit: number?,
		layers: { ImageLayer },
	}
	local compiled: { CompiledLayers } = {}
	local overText = settings.target ~= nil and settings.target:IsA("TextBox")
	local function buildLayers(use: ComposeTypes.Use): { ImageLayer }
		local package = read(packageOrReadable, use) or neutral
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		if recipe == nil or recipe.kind == "native" or recipe.kind == "none" or overText then
			return {}
		end
		local state = (read(settings.state, use) or "default") :: ThemeTypes.SkinState
		local selected = read(settings.selected, use) == true
		local direction = if slot == "barCap" then read(settings.direction, use) or "ltr" else nil
		local fit = read(settings.fit, use)
		for _, cached in compiled do
			if
				cached.package == package
				and cached.state == state
				and cached.selected == selected
				and cached.direction == direction
				and cached.fit == fit
			then
				return cached.layers
			end
		end
		local output: { ImageLayer } = {}
		local function finish(): { ImageLayer }
			if deeplyFrozen(package, {}) then
				local snapshot: CompiledLayers = {
					package = package,
					state = state :: ThemeTypes.SkinState,
					selected = selected,
					direction = direction,
					fit = fit,
					layers = output,
				}
				table.insert(compiled, 1, snapshot)
				if #compiled > 2 then
					table.remove(compiled)
				end
			end
			return output
		end
		local function image(
			layer: ThemeTypes.SkinLayer,
			name: string,
			size: UDim2?,
			position: UDim2?,
			anchor: Vector2?,
			source: ThemeTypes.AssetSource?
		)
			local assetName, link = variantAsset(source or layer.asset, state :: ThemeTypes.SkinState, selected)
			local asset = assetName and (package.assets or {})[assetName]
			if not asset then
				return
			end
			local value: ImageLayer = {
				id = name,
				text = layer.text,
				textInsets = layer.textInsets,
				Image = asset.content or asset.contentId or "",
				Size = size or D2.fromScale(1, 1),
				Position = position or D2.fromOffset(0, 0),
				AnchorPoint = anchor or V2.new(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = settings.ZIndex or 0,
				ScaleType = types.Enum.ScaleType.Stretch,
				TileSize = D2.fromScale(1, 1),
				SliceCenter = types.Rect.new(0, 0, 0, 0),
				SliceScale = 1,
				ResampleMode = types.Enum.ResamplerMode.Default,
				Rotation = link.rotation or 0,
				ImageColor3 = color(types, link.tint) or white(types),
			}
			if layer.kind == "tile" or layer.tile then
				local tile = layer.tileSize or { w = layer.tile or 32, h = layer.tile or 32 }
				value.ScaleType = types.Enum.ScaleType.Tile
				value.TileSize = D2.fromOffset(tile.w, tile.h)
			elseif asset.sliceCenter and layer.sliced ~= false then
				local slice = asset.sliceCenter
				value.ScaleType = types.Enum.ScaleType.Slice
				value.SliceCenter = types.Rect.new(slice.x0, slice.y0, slice.x1, slice.y1)
				value.SliceScale = asset.sliceScale or 1
			end
			if asset.resample == "pixelated" or package.identity.rendering == "pixel" then
				value.ResampleMode = types.Enum.ResamplerMode.Pixelated
			end
			table.insert(output, value)
		end
		if slot == "barCap" or slot == "barCenter" then
			local size = if type(recipe.size) == "table" then recipe.size else { w = 16, h = 16 }
			local vertical = direction == "ttb" or direction == "btt"
			local scale = fit or 1
			if scale <= 0 then
				return finish()
			end
			local box = D2.fromOffset(math.round(size.w * scale), math.round(size.h * scale))
			if slot == "barCenter" then
				image(recipe, "barCenter", box, D2.fromScale(0.5, 0.5), V2.new(0.5, 0.5))
			else
				local reverse = direction == "rtl" or direction == "btt"
				for _, endpoint in { "start", "end" } do
					local position = if (endpoint == "end") ~= reverse then 1 else 0
					local at = V2.new(if vertical then 0.5 else position, if vertical then position else 0.5)
					image(
						recipe,
						"barCap-" .. endpoint,
						box,
						D2.fromScale(at.X, at.Y),
						at,
						(if endpoint == "start" then recipe.startAsset else recipe.endAsset) or recipe.asset
					)
				end
			end
			return finish()
		end
		local definitions: { ThemeTypes.SkinLayer } = if recipe.kind == "layered"
			then recipe.layers or {}
			else { recipe }
		for index, layer in definitions do
			local name = slot .. tostring(index)
			if layer.kind == "corners" then
				local size = if type(layer.size) == "number" then layer.size else 16
				for corner, point in
					{
						topLeft = V2.new(0, 0),
						topRight = V2.new(1, 0),
						bottomLeft = V2.new(0, 1),
						bottomRight = V2.new(1, 1),
					} :: { [string]: Vector2 }
				do
					local asset = ({
						topLeft = layer.topLeft,
						topRight = layer.topRight,
						bottomLeft = layer.bottomLeft,
						bottomRight = layer.bottomRight,
					} :: { [string]: ThemeTypes.AssetSource? })[corner]
					if asset or layer.asset then
						image(
							layer,
							name .. corner,
							D2.fromOffset(size, size),
							D2.fromScale(point.X, point.Y),
							point,
							asset
						)
					end
				end
			elseif layer.kind == "edges" then
				local thickness, margin = layer.thickness or 8, layer.margin or 0
				for _, edge in (layer.sides or { "top", "right", "bottom", "left" }) :: { string } do
					local horizontal = edge == "top" or edge == "bottom"
					local endPoint = edge == "bottom" or edge == "right"
					local size = if horizontal
						then D2.new(1, -margin * 2, 0, thickness)
						else D2.new(0, thickness, 1, -margin * 2)
					local position = if horizontal
						then D2.new(0, margin, if endPoint then 1 else 0, 0)
						else D2.new(if endPoint then 1 else 0, 0, 0, margin)
					local anchor = if horizontal
						then V2.new(0, if endPoint then 1 else 0)
						else V2.new(if endPoint then 1 else 0, 0)
					image(layer, name .. edge, size, position, anchor)
				end
			elseif layer.kind == "plaque" then
				local size = if type(layer.size) == "table" then layer.size else { w = 120, h = 30 }
				local edge = layer.edge or "top"
				local horizontal = edge == "top" or edge == "bottom"
				local endPoint = edge == "bottom" or edge == "right"
				local overhang = layer.overhang or 0
				local reach = (if horizontal then size.h else size.w) / 2 - overhang
				local offset = if endPoint then -reach else reach
				local position = if horizontal
					then D2.new(0.5, 0, if endPoint then 1 else 0, offset)
					else D2.new(if endPoint then 1 else 0, offset, 0.5, 0)
				image(layer, name, D2.fromOffset(size.w, size.h), position, V2.new(0.5, 0.5))
			else
				image(layer, name)
			end
		end
		return finish()
	end
	local target = settings.target
	local function labelled(use: ComposeTypes.Use?): boolean
		local label = settings.label
		return label ~= nil and (read(label, use) or "") ~= ""
	end
	local function createImage(initial: ImageLayer): MountedImage
		local shown = not initial.text or labelled()
		local properties: Engine.ImageLabelNativeProps = {
			Name = initial.id,
			Visible = shown,
			Image = initial.Image,
			Size = initial.Size,
			Position = initial.Position,
			AnchorPoint = initial.AnchorPoint,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = settings.ZIndex or 0,
			ScaleType = initial.ScaleType,
			TileSize = initial.TileSize,
			SliceCenter = initial.SliceCenter,
			SliceScale = initial.SliceScale,
			ResampleMode = initial.ResampleMode,
			Rotation = initial.Rotation,
			ImageColor3 = initial.ImageColor3,
		}
		local captionSource: ComposeTypes.Cell<ImageLayer>?
		local fit = Compose.cell(V2.new(0, 0))
		if settings.label then
			local current = Compose.cell(initial)
			captionSource = current
			properties[#properties + 1] = Compose.show(function(use: ComposeTypes.Use)
				return use(current).text == true and labelled(use)
			end, function()
				local padding: Engine.UIPaddingNativeProps = {
					PaddingLeft = function(use: ComposeTypes.Use)
						local inset: ThemeTypes.Insets = use(current).textInsets or {}
						return types.UDim.new(0, inset.left or 0)
					end,
					PaddingRight = function(use: ComposeTypes.Use)
						local inset: ThemeTypes.Insets = use(current).textInsets or {}
						return types.UDim.new(0, inset.right or 0)
					end,
					PaddingTop = function(use: ComposeTypes.Use)
						local inset: ThemeTypes.Insets = use(current).textInsets or {}
						return types.UDim.new(0, inset.top or 0)
					end,
					PaddingBottom = function(use: ComposeTypes.Use)
						local inset: ThemeTypes.Insets = use(current).textInsets or {}
						return types.UDim.new(0, inset.bottom or 0)
					end,
				}
				local label = Host.TextLabel "PlaqueCaption" {
					Text = settings.label,
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ZIndex = 1,
					TextXAlignment = types.Enum.TextXAlignment.Center,
					Host.UIPadding(padding),
				}
				label:AddTag("facet-skin-caption-text")
				local bounds =
					runtime.observe(label, "TextBounds", if getfenv(0).game then { frame = true, poll = true } else nil)
				Compose.watch(function(use: ComposeTypes.Use)
					fit:set(use(bounds) :: Vector2)
				end)
				Compose.cleanup(function()
					fit:set(V2.new(0, 0))
				end)
				return label
			end)
		end
		local node = Host.ImageLabel(properties)
		node:AddTag("facet-skin-art")
		node:AddTag("facet-skin-art-" .. slot)
		if captionSource then
			local current = captionSource
			Compose.watch(function(use: ComposeTypes.Use)
				local size = grown(types, use(current), use(fit))
				if node.Size ~= size then
					node.Size = size
				end
			end)
		end
		return { node = node, properties = initial, caption = captionSource, visible = shown }
	end
	local function applyImage(record: MountedImage, value: ImageLayer?, visible: boolean)
		local node, previous = record.node, record.properties
		if record.visible ~= visible then
			node.Visible = visible
			record.visible = visible
		end
		if value then
			if value.id ~= previous.id then
				node.Name = value.id
			end
			if value.Image ~= previous.Image then
				node.Image = value.Image
			end
			if value.Size ~= previous.Size then
				node.Size = value.Size
			end
			if value.Position ~= previous.Position then
				node.Position = value.Position
			end
			if value.AnchorPoint ~= previous.AnchorPoint then
				node.AnchorPoint = value.AnchorPoint
			end
			if value.ScaleType ~= previous.ScaleType then
				node.ScaleType = value.ScaleType
			end
			if value.TileSize ~= previous.TileSize then
				node.TileSize = value.TileSize
			end
			if value.SliceCenter ~= previous.SliceCenter then
				node.SliceCenter = value.SliceCenter
			end
			if value.SliceScale ~= previous.SliceScale then
				node.SliceScale = value.SliceScale
			end
			if value.ResampleMode ~= previous.ResampleMode then
				node.ResampleMode = value.ResampleMode
			end
			if value.Rotation ~= previous.Rotation then
				node.Rotation = value.Rotation
			end
			if value.ImageColor3 ~= previous.ImageColor3 then
				node.ImageColor3 = value.ImageColor3
			end
			local caption = record.caption
			if caption and value ~= previous then
				caption:set(value)
			end
			record.properties = value
		end
	end
	local activeLayers: { ImageLayer } = {}
	local drawn = Compose.cell(false)
	local slots: ComposeTypes.Cell<{ number }> = Compose.cell({})
	local mounted: { [number]: MountedImage } = {}
	local root = Host.Frame "Skin" {
		Size = settings.Size or D2.fromScale(1, 1),
		AnchorPoint = settings.AnchorPoint or V2.new(0, 0),
		Position = settings.Position or D2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = settings.ZIndex or 0,
		Compose.keyed({
			from = slots,
			render = function(current: ComposeTypes.Readable<number>)
				local index = current:peek()
				local record = createImage(activeLayers[index])
				mounted[index] = record
				Compose.cleanup(function()
					mounted[index] = nil
				end)
				return record.node
			end,
		}),
	}
	Compose.watch(function(use: ComposeTypes.Use)
		local active = buildLayers(use)
		activeLayers = active
		if drawn:peek() ~= (#active > 0) then
			drawn:set(#active > 0)
		end
		local previousSlots = slots:peek()
		local count = math.max(#active, math.min(#previousSlots, 16))
		if count ~= #previousSlots then
			local nextSlots: { number } = {}
			for index = 1, count do
				nextSlots[index] = index
			end
			slots:set(nextSlots)
		end
		local titled = labelled(use)
		for index, record in mounted do
			local layer = active[index]
			applyImage(record, layer, layer ~= nil and (not layer.text or titled))
		end
		local plaque = false
		for _, layer in active do
			if layer.text and titled then
				plaque = true
			end
		end
		if settings.onCaption then
			settings.onCaption(plaque)
		end
		if target then
			if #active > 0 then
				target:AddTag("facet-skinned")
			else
				target:RemoveTag("facet-skinned")
			end
			if plaque then
				target:AddTag("facet-skin-caption")
			else
				target:RemoveTag("facet-skin-caption")
			end
		end
	end)
	local shadow = Compose.formula(function(use: ComposeTypes.Use)
		local package = read(packageOrReadable, use) or neutral
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		local value = if recipe then recipe.shadow else nil
		if type(value) == "string" then
			value = (package.style.shadows or {})[value] or shadowPresets[value]
			assert(value ~= nil, "Facet theme unknown shadow preset")
		end
		return value
	end)
	local previousShadow: ThemeTypes.Shadow?
	local retainedShadow = Compose.formula(function(use: ComposeTypes.Use): ThemeTypes.Shadow?
		local current = use(shadow)
		if current then
			previousShadow = current :: ThemeTypes.Shadow
		end
		return previousShadow
	end)
	runtime.mountFragment(function()
		return {
			Compose.show(retainedShadow, function()
				local properties: Engine.UIShadowNativeProps = {
					Name = "ChromeShadow",
					Color = function(use: ComposeTypes.Use)
						return color(
								types,
								(use(retainedShadow) :: ThemeTypes.Shadow).color or { r = 0, g = 0, b = 0 }
							) :: Color3
					end,
					Transparency = function(use: ComposeTypes.Use)
						return shadowTransparency((use(retainedShadow) :: ThemeTypes.Shadow).transparency or 0.5, use)
					end,
					ZIndex = function(use: ComposeTypes.Use)
						return (use(retainedShadow) :: ThemeTypes.Shadow).zIndex or -1
					end,
					Enabled = function(use: ComposeTypes.Use)
						local current = use(shadow)
						return current ~= nil and (current :: ThemeTypes.Shadow).enabled ~= false
					end,
					BlurRadius = function(use: ComposeTypes.Use)
						return types.UDim.new(axis((use(retainedShadow) :: ThemeTypes.Shadow).blurRadius))
					end,
					Offset = function(use: ComposeTypes.Use)
						return pair((use(retainedShadow) :: ThemeTypes.Shadow).offset)
					end,
					Spread = function(use: ComposeTypes.Use)
						return pair((use(retainedShadow) :: ThemeTypes.Shadow).spread)
					end,
				}
				return Host.UIShadow(properties)
			end),
		}
	end, settings.target or root)
	return decoration(Compose, runtime, types, settings.target, root, { active = drawn }) :: Frame
end
