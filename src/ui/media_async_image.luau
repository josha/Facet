--!strict
local Engine = require("./engine_types")
local Types = require("./types")
local Media = require("./media_types")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local types, read = ctx.types, ctx.read
	local E, D2 = types.Enum, types.UDim2
	local bind = shared.bind
	UI.AsyncImage = ctx.construct("AsyncImage", function(spec: MediaProps.AsyncImageProps): Frame
		local state: ComposeTypes.Value<Media.ImageState> = Compose.cell("loading" :: Media.ImageState)
		local loaded = Compose.cell("")
		local failure = Compose.cell(nil :: unknown)
		local root = Host.Frame(ctx.props(spec, {
			"image",
			"source",
			"resource",
			"loader",
			"onStatus",
			"failureLabel",
			"placeholder",
			"dimmed",
			"imageProperties",
		}, { BackgroundTransparency = 1, Size = D2.fromOffset(48, 48) }))
		local imageProperties: Engine.ImageLabelProps = spec.imageProperties or {}
		local imageOptions: Engine.ImageLabelProps = ctx.props(imageProperties, {}, {
			Name = "Image",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = loaded,
			ImageTransparency = function(use: ComposeTypes.Use)
				return if read(spec.dimmed, use) then 0.35 else 0
			end,
			Visible = function(use: ComposeTypes.Use)
				return use(state) == "ready"
			end,
		})
		local image = Host.ImageLabel(imageOptions)
		runtime.mount(function()
			return image
		end, root)
		runtime.mount(function()
			local placeholder: Engine.FrameNativeProps = {
				Name = "Placeholder",
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = if spec.placeholder then 1 else 0,
				Visible = function(use: ComposeTypes.Use)
					return use(state) ~= "ready"
				end,
			}
			local custom = spec.placeholder
			if custom then
				placeholder[#placeholder + 1] = Compose.show(function(use: ComposeTypes.Use)
					return use(state) ~= "ready"
				end, function()
					return custom(state)
				end)
			end
			if spec.failureLabel ~= nil then
				placeholder[#placeholder + 1] = Compose.show(function(use: ComposeTypes.Use)
					return use(state) == "failed"
				end, function()
					return ctx.text({ Text = bind(spec.failureLabel, ""), Size = D2.fromScale(1, 1) })
				end)
			end
			local node = Host.Frame(placeholder)
			return if spec.placeholder then node else ctx.styled(node, "skeleton")
		end, root)
		local generation, cancel: (() -> ())? = 0, nil
		Compose.cleanup(function()
			generation += 1
			if cancel then
				cancel()
			end
		end)
		if spec.resource then
			local resource = spec.resource()
			Compose.watch(function(use: ComposeTypes.Use)
				state:set(read(resource.state or resource.status, use) :: Media.ImageState)
				loaded:set(read(resource.value, use) or "")
			end)
		else
			Compose.watch(function(use: ComposeTypes.Use)
				local source = read(spec.source or spec.image, use) or ""
				generation += 1
				local ticket = generation
				if cancel then
					cancel()
					cancel = nil
				end
				state:set("loading")
				failure:set(nil)
				loaded:set(source)
				local function resolve(value: string?)
					if ticket == generation then
						loaded:set(value or source)
						state:set("ready")
					end
				end
				local function reject(reason: unknown)
					if ticket == generation then
						failure:set(reason)
						state:set("failed")
					end
				end
				if source == "" then
					reject("empty content")
				elseif spec.loader then
					local ok, teardown = pcall(spec.loader, source, resolve, reject)
					if ok then
						cancel = teardown
					elseif ticket == generation then
						reject(teardown)
					end
				elseif ctx.config.services and ctx.config.services.ContentProvider and task then
					local contentProvider = ctx.config.services.ContentProvider
					local thread = task.defer(function()
						local succeeded, reason = pcall(function()
							contentProvider:PreloadAsync({ image }, function(_, fetchStatus)
								if fetchStatus == E.AssetFetchStatus.Success then
									resolve(source)
								else
									reject(tostring(fetchStatus))
								end
							end)
						end)
						if not succeeded then
							reject(reason)
						end
					end)
					cancel = function()
						if coroutine.status(thread) ~= "dead" then
							task.cancel(thread)
						end
					end
				else
					resolve(source)
				end
			end)
		end
		if spec.onStatus then
			Compose.watch(function(use: ComposeTypes.Use)
				spec.onStatus(use(state) :: Media.ImageState, use(failure))
			end)
		end
		return root
	end)
end
