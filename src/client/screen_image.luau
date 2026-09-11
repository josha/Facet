--!strict
-- Opt-in source framing. The managed picture is always INSIDE the solved leaf;
-- crop the source texture, never enlarge a GUI beyond a border or focus box.
local framing = require("../render/image_framing")
local screen_image = {}

-- A plain property read is blind to native StyleSheet values (same contract as
-- screen_target's paint claims). Fall back for older engines and bespoke targets.
local function painted(instance: any, property: string): any
	local ok, value = pcall(function()
		return instance:GetStyled(property)
	end)
	return if ok then value else instance[property]
end

function screen_image.clear(handle: any)
	local state = handle.framedImage
	if state == nil then
		return
	end
	for _, connection in state.connections do
		connection:Disconnect()
	end
	state.image:Destroy()
	handle.framedImage = nil
	handle.instance.Image = handle.imageContent or ""
end

function screen_image.sync(handle: any)
	local spec = handle.imageFraming
	if spec == nil then
		screen_image.clear(handle)
		return
	end
	local ok, why = framing.check(spec)
	assert(ok, why)
	local host = handle.instance
	if not host:IsA("ImageLabel") then
		return
	end
	local state = handle.framedImage
	if state == nil then
		local picture = Instance.new("ImageLabel")
		picture.Name = "FacetFramedImage"
		picture.BackgroundTransparency = 1
		picture.BorderSizePixel = 0
		picture.Active = false
		picture.Selectable = false
		picture.ScaleType = Enum.ScaleType.Stretch
		picture.Parent = host
		state = { image = picture, connections = {} }
		handle.framedImage = state
		screen_image.syncModifiers(handle)
		-- Sheet-driven colour/alpha can change without a renderer prop write.
		-- Four local observers, only for framed images; no global/frame polling.
		for _, property in { "ImageColor3", "ImageTransparency", "ResampleMode", "ZIndex" } do
			local ok, signal = pcall(function()
				return host:GetStyledPropertyChangedSignal(property)
			end)
			table.insert(
				state.connections,
				(if ok then signal else host:GetPropertyChangedSignal(property)):Connect(function()
					(picture :: any)[property] = painted(host, property)
				end)
			)
		end
	end
	local picture = state.image
	host.Image = ""
	picture.Image = handle.imageContent or ""
	picture.ImageColor3 = painted(host, "ImageColor3")
	picture.ImageTransparency = painted(host, "ImageTransparency")
	picture.ResampleMode = painted(host, "ResampleMode")
	picture.ZIndex = painted(host, "ZIndex")
	-- A prop change can alter the crop at an unchanged size.
	state.width = nil
	screen_image.syncRect(handle)
end

-- Geometry commits must not read/rewrite sheet paint. Local style observers own
-- those updates; the full sync above owns image/spec changes and initial paint.
function screen_image.syncRect(handle: any)
	local state = handle.framedImage
	if state == nil then
		return
	end
	local picture = state.image
	local rect = handle.windowRect or { w = 0, h = 0 }
	if state.width == rect.w and state.height == rect.h then
		return
	end
	local plan = framing.resolve(handle.imageFraming, rect.w, rect.h)
	local source, destination = plan.source, plan.destination
	picture.ImageRectOffset = Vector2.new(source.x, source.y)
	picture.ImageRectSize = Vector2.new(source.w, source.h)
	picture.Position = UDim2.fromOffset(destination.x, destination.y)
	picture.Size = UDim2.fromOffset(destination.w, destination.h)
	state.width, state.height = rect.w, rect.h
end

function screen_image.syncModifiers(handle: any)
	if handle.framedImage == nil then
		return
	end
	local host, picture = handle.instance, handle.framedImage.image
	-- Preserve modifier identity during animated gradient/corner updates.
	for class, properties in
		{
			UIGradient = { "Color", "Transparency", "Rotation", "Offset", "Enabled" },
			UICorner = { "CornerRadius", "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" },
		}
	do
		local modifier = host:FindFirstChildOfClass(class)
		local old = picture:FindFirstChildOfClass(class)
		if modifier == nil then
			if old then
				old:Destroy()
			end
		elseif old == nil then
			modifier:Clone().Parent = picture
		else
			for _, property in properties do
				-- Per-corner properties are unavailable on older engine versions.
				pcall(function()
					(old :: any)[property] = painted(modifier, property)
				end)
			end
		end
	end
end
return screen_image
