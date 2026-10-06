--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureMediaTypes = require("../src/ui/media_types")
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local requireDynamic = require :: (any) -> any
	local FixtureThemeTypes = require("../src/ui/theme_types")

	local fs = require("@lune/fs")
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local media = require("../src/ui/media")
	local themes = require("../src/ui/themes")(Compose)
	local icons = require("../src/ui/icons")
	local engineLib = require("./lib/native_engine")

	local function setup(options: { [string]: any }?): (any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local config: { [string]: any } = { types = engine.types }
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = media(context(Compose, runtime, config :: any))
		return engine, runtime, UI
	end

	local function controlsFor(options: { [string]: any }?): (any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local config: { [string]: any } =
			{ types = engine.types, services = { GuiService = gui, UserInputService = input } }
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = require("../src").controls(runtime, config :: any)
		return engine, runtime, UI
	end

	local function textLabels(root: any): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:IsA("TextLabel") then
				table.insert(found, node)
			end
		end
		return found
	end

	local function imageLabels(root: any): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:IsA("ImageLabel") then
				table.insert(found, node)
			end
		end
		return found
	end

	local function rejects(build: (any, any, any) -> any): boolean
		local engine, runtime, UI = setup()
		local ok = pcall(function()
			runtime.mount(function()
				return build(UI, engine, runtime)
			end, engine.new("Folder"))
		end)
		runtime:dispose()
		return not ok
	end

	local function people(count: number): { any }
		local out = {}
		for index = 1, count do
			table.insert(out, { id = "p" .. index, name = "Player " .. index })
		end
		return out
	end

	verifyHarness:suite("async image states", function()
		verifyHarness:case("preloads the retained ImageLabel itself and creates no temporary preload instance", {
			id = "native_parity_strength_icons::async image states::preloads the retained ImageLabel itself and creates no temporary preload instance",
			run = function()
				local engine, runtime = setup()
				local environment = getfenv(media)
				local originalTask = environment.task
				local pending = {}
				environment.task = {
					defer = function(callback)
						local thread = coroutine.create(callback)
						table.insert(pending, thread)
						return thread
					end,
					cancel = function(thread)
						coroutine.close(thread)
					end,
				}
				local calls, madeDuringPreload, destroyedDuringPreload = {}, 0, 0
				local status = engine.types.Enum.AssetFetchStatus.Success
				local UI = media(context(Compose, runtime, {
					types = engine.types,
					services = {
						ContentProvider = {
							PreloadAsync = function(_, list: { any }, callback: (string, any) -> ())
								local before = #engine.made
								local liveBefore = engine.census().live
								table.insert(calls, { list = list, image = list[1].Image, count = #list })
								callback(list[1].Image, status)
								madeDuringPreload += #engine.made - before
								destroyedDuringPreload += liveBefore - engine.census().live
							end,
						} :: any,
					},
				}))
				local source, states = Compose.cell("rbxassetid://123" :: string?), {}
				local stop, root: any = runtime.mount(function()
					return UI.AsyncImage({
						source = source,
						onStatus = function(state)
							table.insert(states, state)
						end,
					})
				end, engine.new("Folder"))
				local image: any = root:FindFirstChild("Image")
				Verify.expect(states[#states]):toBe("loading")
				Verify.expect(image.Visible):toBe(false)
				Verify.expect((coroutine.resume(pending[1]))):toBe(true)
				Verify.expect(#calls):toBe(1)
				Verify.expect(calls[1].count):toBe(1)
				Verify.expect(typeof(calls[1].list[1]) ~= "string"):toBe(true)
				Verify.expect((calls[1].list[1]:IsA("ImageLabel"))):toBe(true)
				Verify.expect(calls[1].list[1]):toBe(image)
				Verify.expect(calls[1].image):toBe("rbxassetid://123")
				Verify.expect(madeDuringPreload):toBe(0)
				Verify.expect(destroyedDuringPreload):toBe(0)
				Verify.expect((image.isDestroyed())):toBe(false)
				Verify.expect(image.Image):toBe("rbxassetid://123")
				Verify.expect(image.Visible):toBe(true)
				Verify.expect(states[#states]):toBe("ready")
				status = engine.types.Enum.AssetFetchStatus.Failure
				source:set("rbxassetid://456")
				Verify.expect((coroutine.resume(pending[2]))):toBe(true)
				Verify.expect(calls[2].list[1]):toBe(image)
				Verify.expect(calls[2].image):toBe("rbxassetid://456")
				Verify.expect(states[#states]):toBe("failed")
				Verify.expect(image.Visible):toBe(false)
				Verify.expect(root:FindFirstChild("Placeholder").Visible):toBe(true)
				Verify.expect(#imageLabels(root)):toBe(1)
				stop()
				Verify.expect((image.isDestroyed())):toBe(true)
				environment.task = originalTask
				runtime:dispose()
			end,
		})

		verifyHarness:case("shows the placeholder and hides the image while the first request is pending", {
			id = "native_parity_strength_icons::async image states::shows the placeholder and hides the image while the first request is pending",
			run = function()
				local engine, runtime, UI = setup()
				local states, requested = {}, {}
				local stop, root: any = runtime.mount(function()
					return UI.AsyncImage({
						image = "rbxthumb://type=AvatarHeadShot&id=1",
						loader = function(content)
							table.insert(requested, content)
							return nil
						end,
						onStatus = function(state)
							table.insert(states, state)
						end,
					})
				end, engine.new("Folder"))
				Verify.expect(requested):toEqual({ "rbxthumb://type=AvatarHeadShot&id=1" })
				Verify.expect(states):toEqual({ "loading" })
				local placeholder, image: any = root:FindFirstChild("Placeholder"), root:FindFirstChild("Image")
				Verify.expect(placeholder.Visible):toBe(true)
				Verify.expect((placeholder:HasTag("facet-skeleton"))):toBe(true)
				Verify.expect(image.Visible):toBe(false)
				Verify.expect(#textLabels(root)):toBe(0)
				Verify.expect(#imageLabels(root)):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps the placeholder and mounts no failure text when a failure has no failureLabel", {
			id = "native_parity_strength_icons::async image states::keeps the placeholder and mounts no failure text when a failure has no failureLabel",
			run = function()
				for _, path in { "loader", "preload" } do
					local engine, runtime = setup()
					local environment = getfenv(media)
					local originalTask = environment.task
					environment.task = {
						defer = function(callback)
							callback()
							return coroutine.create(function() end)
						end,
						cancel = function() end,
					}
					local UI = media(context(Compose, runtime, {
						types = engine.types,
						services = {
							ContentProvider = {
								PreloadAsync = function(_, list: { any }, callback: (string, any) -> ())
									callback(list[1].Image, engine.types.Enum.AssetFetchStatus.Failure)
								end,
							} :: any,
						},
					}))
					local states, reasons = {}, {}
					local stop, root: any = runtime.mount(function()
						return UI.AsyncImage({
							image = "rbxassetid://999999999999999",
							loader = if path == "loader"
								then function(_, _, reject)
									reject("missing")
									return nil
								end
								else nil,
							onStatus = function(state, reason)
								table.insert(states, state)
								table.insert(reasons, reason)
							end,
						})
					end, engine.new("Folder"))
					local placeholder, image: any = root:FindFirstChild("Placeholder"), root:FindFirstChild("Image")
					Verify.expect(states[#states]):toBe("failed")
					Verify.expect(reasons[#reasons] ~= nil):toBe(true)
					Verify.expect(placeholder.Visible):toBe(true)
					Verify.expect((placeholder:HasTag("facet-skeleton"))):toBe(true)
					Verify.expect(image.Visible):toBe(false)
					Verify.expect(#textLabels(root)):toBe(0)
					Verify.expect(#imageLabels(root)):toBe(1)
					Verify.expect(#placeholder:GetChildren()):toBe(0)
					stop()
					environment.task = originalTask
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("renders a shared completion, dims the image and restores it, and releases with the owner", {
			id = "native_parity_strength_icons::async image states::renders a shared completion, dims the image and restores it, and releases with the owner",
			run = function()
				local engine, runtime, UI = setup()
				local acquired, released = 0, 0
				local state: FixtureComposeTypes.Cell<"loading" | "ready" | "failed">, value =
					Compose.cell("loading" :: "loading" | "ready" | "failed"), Compose.cell("")
				local resource = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					acquired += 1
					return { state = state, value = value }, function()
						released += 1
					end
				end)
				local dimmed = Compose.cell(false)
				local first, one: any = runtime.mount(function()
					return UI.AsyncImage({
						resource = function()
							return resource()
						end,
						dimmed = dimmed,
					})
				end, engine.new("Folder"))
				local second, two: any = runtime.mount(function()
					return UI.AsyncImage({
						resource = function()
							return resource()
						end,
					})
				end, engine.new("Folder"))
				Verify.expect(acquired):toBe(1)
				local image: any = one:FindFirstChild("Image")
				Verify.expect(one:FindFirstChild("Placeholder").Visible):toBe(true)
				Verify.expect(image.Visible):toBe(false)
				value:set("rbxassetid://123")
				state:set("ready")
				Verify.expect(image.Image):toBe("rbxassetid://123")
				Verify.expect(image.Visible):toBe(true)
				Verify.expect(one:FindFirstChild("Placeholder").Visible):toBe(false)
				Verify.expect(two:FindFirstChild("Image").Image):toBe("rbxassetid://123")
				Verify.expect(image.ImageTransparency):toBe(0)
				dimmed:set(true)
				Verify.expect(image.ImageTransparency):toBe(0.35)
				Verify.expect(two:FindFirstChild("Image").ImageTransparency):toBe(0)
				dimmed:set(false)
				Verify.expect(image.ImageTransparency):toBe(0)
				first()
				Verify.expect(released):toBe(0)
				Verify.expect((image.isDestroyed())):toBe(true)
				second()
				Verify.expect(released):toBe(1)
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"releases a shared resource on its last reference, cancels in-flight work and ignores late results",
			{
				id = "native_parity_strength_icons::async image states::releases a shared resource on its last reference, cancels in-flight work and ignores late results",
				run = function()
					local engine = engineLib.new()
					local folder = engine.new("Folder")
					local baseline = engine.census()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local UI = media(context(Compose, runtime, { types = engine.types }))
					local acquired, released = 0, 0
					local resource = Compose.createSharedResource(
						function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
							acquired += 1
							return {
								state = Compose.cell("ready" :: FixtureMediaTypes.ImageState),
								value = Compose.cell("rbxassetid://7"),
							}, function()
								released += 1
							end
						end
					)
					local requests, cancellations, statuses = {}, 0, 0
					local stops = {}
					for _ = 1, 3 do
						table.insert(stops, (runtime.mount(function()
							return UI.AsyncImage({
								resource = function()
									return resource()
								end,
							})
						end, folder)))
					end
					local pendingStop, pendingRoot: any = runtime.mount(function()
						return UI.AsyncImage({
							image = "rbxassetid://8",
							loader = function(content: string, resolve: (string?) -> (), reject: (unknown) -> ())
								table.insert(requests, { content = content, resolve = resolve, reject = reject })
								return function()
									cancellations += 1
								end
							end,
							onStatus = function()
								statuses += 1
							end,
						})
					end, folder)
					Verify.expect(acquired):toBe(1)
					stops[1]()
					stops[2]()
					Verify.expect(released):toBe(0)
					stops[3]()
					Verify.expect(released):toBe(1)
					local again = runtime.mount(function()
						return UI.AsyncImage({
							resource = function()
								return resource()
							end,
						})
					end, folder)
					Verify.expect(acquired):toBe(2)
					again()
					Verify.expect(released):toBe(2)
					local image: any = pendingRoot:FindFirstChild("Image")
					Verify.expect(#requests):toBe(1)
					local observed = statuses
					pendingStop()
					Verify.expect(cancellations):toBe(1)
					requests[1].resolve("rbxassetid://late")
					requests[1].reject("late")
					Verify.expect(statuses):toBe(observed)
					Verify.expect(image.Visible):toBe(false)
					Verify.expect(cancellations):toBe(1)
					runtime:dispose()
					Verify.expect(engine.census().live):toBe(baseline.live)
					Verify.expect(engine.census().connections):toBe(baseline.connections)
					Verify.expect(acquired):toBe(released)
				end,
			}
		)
	end)

	verifyHarness:suite("avatar faces", function()
		verifyHarness:case("cuts UTF-8 first and last initials in authored case", {
			id = "native_parity_strength_icons::avatar faces::cuts UTF-8 first and last initials in authored case",
			run = function()
				local engine, runtime, UI = setup()
				local name = Compose.cell("Ada Quill")
				local stop, avatar: any = runtime.mount(function()
					return UI.Avatar({ name = name })
				end, engine.new("Folder"))
				local initials = avatar:FindFirstChild("Initials")
				for _, pair in
					{
						{ "Ada Quill", "AQ" },
						{ "Cyrus", "C" },
						{ "Bo van der Marchetti", "BM" },
						{ "Ада Квилл", "АК" },
						{ "Émile Noël", "ÉN" },
						{ "ada ada", "aa" },
						{ "   ", "" },
					}
				do
					name:set(pair[1])
					Verify.expect(initials.Text):toBe(pair[2])
					Verify.expect((avatar:FindFirstChild("Initials"))):toBe(initials)
				end
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"paints initials and passive semantics at the default regular diameter without a focus stop",
			{
				id = "native_parity_strength_icons::avatar faces::paints initials and passive semantics at the default regular diameter without a focus stop",
				run = function()
					local engine, runtime, UI = setup()
					local stop, avatar: any = runtime.mount(function()
						return UI.Avatar({ name = "Ada Quill" })
					end, engine.new("Folder"))
					Verify.expect(avatar:FindFirstChild("Initials").Text):toBe("AQ")
					Verify.expect(avatar:FindFirstChild("Initials").Visible):toBe(true)
					Verify.expect(avatar.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
					Verify.expect(
						avatar:FindFirstChild("Initials"):FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize
					)
						:toBe(18)
					Verify.expect(avatar:FindFirstChild("Initials").TextScaled):toBe(true)
					Verify.expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Ada Quill")
					Verify.expect(avatar.Selectable):toBe(false)
					Verify.expect((avatar:HasTag("facet-avatar"))):toBe(true)
					Verify.expect((avatar:FindFirstChild("Portrait"))):toBe(nil)
					Verify.expect((avatar:FindFirstChild("Presence"))):toBe(nil)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"keeps one diameter through pending, ready and failed images and returns to initials on failure",
			{
				id = "native_parity_strength_icons::avatar faces::keeps one diameter through pending, ready and failed images and returns to initials on failure",
				run = function()
					for _, ready in { true, false } do
						local engine, runtime, UI = setup()
						local requests, statuses = {}, {}
						local stop, avatar: any = runtime.mount(function()
							return UI.Avatar({
								name = "Ada Quill",
								userId = 24813339,
								loader = function(content: string, resolve: (string?) -> (), reject: (unknown) -> ())
									table.insert(requests, { content = content, resolve = resolve, reject = reject })
									return nil
								end,
								onStatus = function(state)
									table.insert(statuses, state)
								end,
							})
						end, engine.new("Folder"))
						Verify.expect(#requests):toBe(1)
						Verify.expect(requests[1].content)
							:toBe("rbxthumb://type=AvatarHeadShot&id=24813339&w=150&h=150")
						local portrait = avatar:FindFirstChild("Portrait")
						local initials, image: any = avatar:FindFirstChild("Initials"), portrait:FindFirstChild("Image")
						Verify.expect(avatar.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
						Verify.expect(portrait.Size):toBe(engine.types.UDim2.fromScale(1, 1))
						Verify.expect(initials.Visible):toBe(true)
						Verify.expect(image.Visible):toBe(false)
						Verify.expect(statuses[#statuses]):toBe("loading")
						if ready then
							requests[1].resolve("rbxassetid://75342910516929")
							Verify.expect(statuses[#statuses]):toBe("ready")
							Verify.expect(image.Image):toBe("rbxassetid://75342910516929")
							Verify.expect(image.Visible):toBe(true)
							Verify.expect(initials.Visible):toBe(false)
						else
							requests[1].reject("missing")
							Verify.expect(statuses[#statuses]):toBe("failed")
							Verify.expect(image.Visible):toBe(false)
							Verify.expect(initials.Visible):toBe(true)
							Verify.expect(initials.Text):toBe("AQ")
						end
						Verify.expect(avatar.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
						stop()
						Verify.expect((image.isDestroyed())):toBe(true)
						runtime:dispose()
					end
				end,
			}
		)

		verifyHarness:case(
			"survives repeated resource state flips with one retained lease and rejects stale completions",
			{
				id = "native_parity_strength_icons::avatar faces::survives repeated resource state flips with one retained lease and rejects stale completions",
				run = function()
					local engine, runtime, UI = setup()
					local state: FixtureComposeTypes.Cell<"loading" | "ready" | "failed">, value =
						Compose.cell("loading" :: "loading" | "ready" | "failed"), Compose.cell("rbxassetid://1")
					local held, acquired = 0, 0
					local resource = Compose.createSharedResource(
						function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
							acquired += 1
							held += 1
							return { state = state, value = value }, function()
								held -= 1
							end
						end
					)
					local stop, avatar: any = runtime.mount(function()
						return UI.Avatar({
							name = "Ada",
							resource = function()
								return resource()
							end,
						})
					end, engine.new("Folder"))
					local initials = avatar:FindFirstChild("Initials")
					local image: any = avatar:FindFirstChild("Portrait"):FindFirstChild("Image")
					for _ = 1, 8 do
						state:set("ready")
						Verify.expect(initials.Visible):toBe(false)
						Verify.expect(image.Visible):toBe(true)
						Verify.expect(avatar.Size.X.Offset):toBe(44)
						state:set("loading")
						Verify.expect(initials.Visible):toBe(true)
						Verify.expect(image.Visible):toBe(false)
						Verify.expect(held):toBe(1)
					end
					Verify.expect(acquired):toBe(1)
					state:set("failed")
					Verify.expect(initials.Visible):toBe(true)
					Verify.expect((avatar:FindFirstChild("Initials"))):toBe(initials)
					stop()
					Verify.expect(held):toBe(0)
					local source, requests = Compose.cell("rbxassetid://first" :: string?), {}
					local stopSecond, second: any = runtime.mount(function()
						return UI.Avatar({
							name = "Bo",
							image = source,
							loader = function(content: string, resolve: (string?) -> ())
								requests[content] = resolve
								return nil
							end,
						})
					end, engine.new("Folder"))
					source:set("rbxassetid://second")
					requests["rbxassetid://first"]("rbxassetid://first")
					local secondImage = second:FindFirstChild("Portrait"):FindFirstChild("Image")
					Verify.expect(secondImage.Visible):toBe(false)
					Verify.expect(second:FindFirstChild("Initials").Visible):toBe(true)
					requests["rbxassetid://second"]("rbxassetid://second")
					Verify.expect(secondImage.Image):toBe("rbxassetid://second")
					Verify.expect(second:FindFirstChild("Initials").Visible):toBe(false)
					stopSecond()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("shares one caller resource between two standalone faces and frees it with the last one", {
			id = "native_parity_strength_icons::avatar faces::shares one caller resource between two standalone faces and frees it with the last one",
			run = function()
				local engine, runtime, UI = setup()
				local loaded, released = 0, 0
				local resource = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					loaded += 1
					return {
						state = Compose.cell("ready" :: FixtureMediaTypes.ImageState),
						value = Compose.cell("rbxassetid://21"),
					}, function()
						released += 1
					end
				end)
				local stopA, a: any = runtime.mount(function()
					return UI.Avatar({
						name = "A",
						resource = function()
							return resource()
						end,
					})
				end, engine.new("Folder"))
				local stopB, b: any = runtime.mount(function()
					return UI.Avatar({
						name = "B",
						resource = function()
							return resource()
						end,
					})
				end, engine.new("Folder"))
				Verify.expect(loaded):toBe(1)
				for _, face in { a, b } do
					local image: any = face:FindFirstChild("Portrait"):FindFirstChild("Image")
					Verify.expect(image.Image):toBe("rbxassetid://21")
					Verify.expect(image.Visible):toBe(true)
					Verify.expect(face:FindFirstChild("Initials").Visible):toBe(false)
				end
				stopA()
				Verify.expect(released):toBe(0)
				Verify.expect(b:FindFirstChild("Portrait"):FindFirstChild("Image").Visible):toBe(true)
				stopB()
				Verify.expect(released):toBe(1)
				runtime:dispose()
			end,
		})

		verifyHarness:case("maps four presence states to four mark forms and follows a reactive presence label", {
			id = "native_parity_strength_icons::avatar faces::maps four presence states to four mark forms and follows a reactive presence label",
			run = function()
				local engine, runtime, UI = setup()
				local presence, label = Compose.cell("online" :: string?), Compose.cell("Available")
				local stop, avatar: any = runtime.mount(function()
					return UI.Avatar({
						name = "Ada",
						presence = presence,
						presenceLabel = label,
						onActivate = function() end,
					})
				end, engine.new("Folder"))
				local mark = avatar:FindFirstChild("Presence")
				local statuses: { [string]: string } =
					{ online = "success", away = "warning", busy = "error", offline = "neutral" }
				for _, state in { "online", "away", "busy", "offline" } do
					presence:set(state)
					label:set("Local " .. state)
					Verify.expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Ada, Local " .. state)
					Verify.expect((avatar:FindFirstChild("Presence"))):toBe(mark)
					Verify.expect(mark.Visible):toBe(true)
					Verify.expect((mark:HasTag("facet-status-" .. statuses[state]))):toBe(true)
					for other, status in statuses do
						if other ~= state then
							Verify.expect((mark:HasTag("facet-status-" .. status))):toBe(false)
						end
					end
					local corner = mark:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale
					local ring = mark:FindFirstChild("Ring")
					if state == "online" then
						Verify.expect(corner):toBe(1)
						Verify.expect(ring):toBe(nil)
						Verify.expect(mark.Size.X.Offset):toBe(mark.Size.Y.Offset)
					elseif state == "away" then
						Verify.expect(corner):toBe(1)
						Verify.expect(ring):toBe(nil)
						Verify.expect(mark.Size.X.Offset > mark.Size.Y.Offset):toBe(true)
						Verify.expect(mark:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(3)
					elseif state == "busy" then
						Verify.expect(corner):toBe(0)
						Verify.expect(ring):toBe(nil)
						Verify.expect(mark.Size.X.Offset):toBe(mark.Size.Y.Offset)
					else
						Verify.expect(corner):toBe(1)
						Verify.expect(ring ~= nil):toBe(true)
						Verify.expect(ring.BorderStrokePosition):toBe(engine.types.Enum.BorderStrokePosition.Inner)
						Verify.expect((mark:HasTag("facet-status-hollow"))):toBe(true)
						Verify.expect(mark.Size.X.Offset):toBe(mark.Size.Y.Offset)
					end
				end
				presence:set(nil)
				Verify.expect((avatar:GetAttribute("AccessibleLabel"))):toBe("Ada")
				Verify.expect(mark.Visible):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("draws the presence mark on the avatar with a shared inner cutout stroke in the corner", {
			id = "native_parity_strength_icons::avatar faces::draws the presence mark on the avatar with a shared inner cutout stroke in the corner",
			run = function()
				local engine, runtime, UI = setup()
				local stop, avatar: any = runtime.mount(function()
					return UI.Avatar({ name = "Ada", presence = "online", onActivate = function() end })
				end, engine.new("Folder"))
				local mark = avatar:FindFirstChild("Presence")
				Verify.expect(mark.Parent):toBe(avatar)
				local cutout = mark:FindFirstChild("Cutout")
				Verify.expect(cutout.ClassName):toBe("UIStroke")
				Verify.expect((cutout:HasTag("facet-cutout"))):toBe(true)
				Verify.expect(cutout.BorderStrokePosition):toBe(engine.types.Enum.BorderStrokePosition.Inner)
				Verify.expect(cutout.ApplyStrokeMode):toBe(engine.types.Enum.ApplyStrokeMode.Border)
				Verify.expect(cutout.Thickness):toBe(1)
				Verify.expect(mark.AnchorPoint):toBe(engine.types.Vector2.new(1, 1))
				Verify.expect(mark.Position):toBe(engine.types.UDim2.fromScale(1, 1))
				Verify.expect(mark.Size):toBe(engine.types.UDim2.fromOffset(12, 12))
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"refuses an invalid bound rung without moving geometry and recovers through a valid rung and nil",
			{
				id = "native_parity_strength_icons::avatar faces::refuses an invalid bound rung without moving geometry and recovers through a valid rung and nil",
				run = function()
					local engine, runtime, UI = setup()
					local rung = Compose.cell("compact" :: string?)
					local stop, avatar: any = runtime.mount(function()
						return UI.Avatar({ name = "Ada", controlSize = rung })
					end, engine.new("Folder"))
					local initials = avatar:FindFirstChild("Initials")
					Verify.expect(avatar.Size.X.Offset):toBe(36)
					Verify.expect(avatar.Size.Y.Offset):toBe(36)
					Verify.expect((pcall(function()
						rung:set("bad")
					end))):toBe(false)
					Verify.expect(avatar.Size.X.Offset):toBe(36)
					Verify.expect(avatar.Size.Y.Offset):toBe(36)
					Verify.expect(initials:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize):toBe(14)
					rung:set("large")
					Verify.expect(avatar.Size.X.Offset):toBe(56)
					Verify.expect(avatar.Size.Y.Offset):toBe(56)
					Verify.expect(initials:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize):toBe(22)
					rung:set(nil)
					Verify.expect(avatar.Size.X.Offset):toBe(44)
					Verify.expect(avatar.Size.Y.Offset):toBe(44)
					Verify.expect(initials:FindFirstChildWhichIsA("UITextSizeConstraint").MaxTextSize):toBe(18)
					stop()
					runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("avatar groups", function()
		verifyHarness:case("caps the caller order at four, reports the hidden count and keeps faces informational", {
			id = "native_parity_strength_icons::avatar groups::caps the caller order at four, reports the hidden count and keeps faces informational",
			run = function()
				local engine, runtime, UI = setup()
				local stop, group: any = runtime.mount(function()
					return UI.AvatarGroup({ items = people(6) })
				end, engine.new("Folder"))
				local shown = {}
				for _, child in group:GetChildren() do
					if child:IsA("TextButton") and child.Name ~= "Overflow" then
						table.insert(shown, child)
					end
				end
				table.sort(shown, function(a, b)
					return a.LayoutOrder < b.LayoutOrder
				end)
				Verify.expect(#shown):toBe(4)
				for index, face in shown do
					Verify.expect(face.Name):toBe("p" .. index)
					Verify.expect(face.LayoutOrder):toBe(index)
					Verify.expect(face.Selectable):toBe(false)
					Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Player " .. index)
				end
				Verify.expect((group:FindFirstChild("p5"))):toBe(nil)
				local overflow = group:FindFirstChild("Overflow")
				Verify.expect(overflow.Text):toBe("+2")
				Verify.expect(overflow.LayoutOrder):toBe(6)
				Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("2 more players")
				Verify.expect(overflow.Selectable):toBe(false)
				Verify.expect(group:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(-10)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"refuses bad members and malformed container policies and keeps an empty group informational",
			{
				id = "native_parity_strength_icons::avatar groups::refuses bad members and malformed container policies and keeps an empty group informational",
				run = function()
					local refused = {
						function(UI: FacetControls)
							return UI.AvatarGroup({} :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = false } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = { [2] = { id = "a", name = "A" } } })
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({
								items = { { id = "a", name = "" } :: FixtureMediaTypes.AvatarMember },
							})
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({
								items = { { id = "", name = "A" } :: FixtureMediaTypes.AvatarMember },
							})
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = { { id = "a", name = "A", presence = "unknown" } } } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, max = 0 })
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, max = math.huge })
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, max = 1.5 })
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, layout = "grid" } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, overflow = "more" } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, form = "photo" } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, onOverflow = true } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, controlSize = "huge" } :: any)
						end,
						function(UI: FacetControls)
							return UI.AvatarGroup({ items = {}, over = "photo" })
						end,
					}
					for index, build in refused do
						Verify.expect(`{index}: {rejects(build)}`):toBe(`{index}: true`)
					end
					local engine, runtime, UI = setup()
					local stop, group: any = runtime.mount(function()
						return UI.AvatarGroup({ items = {} })
					end, engine.new("Folder"))
					local faces = 0
					for _, child in group:GetChildren() do
						if child:IsA("GuiButton") then
							faces += 1
						end
					end
					Verify.expect(faces):toBe(0)
					Verify.expect((group:FindFirstChild("Overflow"))):toBe(nil)
					Verify.expect((group:HasTag("facet-avatar-stack"))):toBe(true)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"updates current initials while a stacked group keeps presence semantic and a spread group paints it",
			{
				id = "native_parity_strength_icons::avatar groups::updates current initials while a stacked group keeps presence semantic and a spread group paints it",
				run = function()
					for _, layout in { "stacked", "spread" } do
						local engine, runtime, UI = setup()
						local items = Compose.cell({
							{ id = "a", name = "Ada", presence = "online" } :: FixtureMediaTypes.AvatarMember,
						})
						local stop, group: any = runtime.mount(function()
							return UI.AvatarGroup({ items = items, layout = layout })
						end, engine.new("Folder"))
						local face = group:FindFirstChild("a")
						Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Ada, online")
						items:set({
							{ id = "a", name = "Émile Noël", presence = "offline" } :: FixtureMediaTypes.AvatarMember,
						})
						Verify.expect((group:FindFirstChild("a"))):toBe(face)
						Verify.expect(face:FindFirstChild("Initials").Text):toBe("ÉN")
						Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Émile Noël, offline")
						Verify.expect(face.Selectable):toBe(false)
						local mark = face:FindFirstChild("Presence")
						Verify.expect(mark ~= nil):toBe(layout == "spread")
						Verify.expect((group:HasTag("facet-avatar-stack"))):toBe(layout == "stacked")
						if mark then
							Verify.expect(mark.Visible):toBe(true)
							Verify.expect((mark:HasTag("facet-status-neutral"))):toBe(true)
							Verify.expect(mark:FindFirstChild("Ring") ~= nil):toBe(true)
						end
						Verify.expect(group:FindFirstChildWhichIsA("UIListLayout").Padding.Offset)
							:toBe(if layout == "spread" then 8 else -10)
						stop()
						runtime:dispose()
					end
				end,
			}
		)

		verifyHarness:case("localizes overflow semantics reactively for the count and ellipsis forms", {
			id = "native_parity_strength_icons::avatar groups::localizes overflow semantics reactively for the count and ellipsis forms",
			run = function()
				for _, form in { "count", "ellipsis" } :: { "count" | "ellipsis" } do
					local engine, runtime, UI = setup()
					local phrase, items, calls = Compose.cell("Deux autres" :: string?), Compose.cell(people(3)), 0
					local stop, group: any = runtime.mount(function()
						return UI.AvatarGroup({
							items = items,
							max = 1,
							overflow = form :: "count" | "ellipsis",
							overflowLabel = phrase,
							onOverflow = function()
								calls += 1
							end,
						})
					end, engine.new("Folder"))
					local overflow = group:FindFirstChild("Overflow")
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("Deux autres")
					Verify.expect(overflow.Text):toBe(if form == "count" then "+2" else "…")
					Verify.expect(overflow.Selectable):toBe(true)
					phrase:set("Encore deux")
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("Encore deux")
					Verify.expect((pcall(function()
						phrase:set(42 :: any)
					end))):toBe(false)
					phrase:set(nil)
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("2 more players")
					items:set(people(4))
					Verify.expect((overflow:GetAttribute("AccessibleLabel"))):toBe("3 more players")
					Verify.expect(overflow.Text):toBe(if form == "count" then "+3" else "…")
					overflow.Activated.fire()
					Verify.expect(calls):toBe(1)
					items:set(people(1))
					Verify.expect((group:FindFirstChild("Overflow"))):toBe(nil)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("keeps a bound nil presence valid through source replacement and a later presence", {
			id = "native_parity_strength_icons::avatar groups::keeps a bound nil presence valid through source replacement and a later presence",
			run = function()
				local engine, runtime, UI = setup()
				local function roster(image: string, presence: FixtureMediaTypes.Presence?)
					return {
						{ id = "a", name = "Ada", image = image, presence = presence } :: FixtureMediaTypes.AvatarMember,
						{ id = "b", name = "Bo" } :: FixtureMediaTypes.AvatarMember,
					}
				end
				local items, activations = Compose.cell(roster("rbxassetid://1", nil)), 0
				local stop, group: any = runtime.mount(function()
					return UI.AvatarGroup({
						items = items,
						max = 1,
						layout = "spread",
						onOverflow = function()
							activations += 1
						end,
					})
				end, engine.new("Folder"))
				local face = group:FindFirstChild("a")
				local mark = face:FindFirstChild("Presence")
				Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Ada")
				Verify.expect(mark.Visible):toBe(false)
				items:set(roster("rbxassetid://1", "online"))
				Verify.expect((group:FindFirstChild("a"))):toBe(face)
				Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Ada, online")
				Verify.expect(mark.Visible):toBe(true)
				Verify.expect((mark:HasTag("facet-status-success"))):toBe(true)
				Verify.expect((pcall(function()
					items:set(roster("rbxassetid://1", "invalid" :: any))
				end))):toBe(false)
				items:set(roster("rbxassetid://1", nil))
				Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Ada")
				Verify.expect(mark.Visible):toBe(false)
				items:set(roster("rbxassetid://2", nil))
				Verify.expect((group:FindFirstChild("a"))):toBe(face)
				Verify.expect(face:FindFirstChild("Portrait"):FindFirstChild("Image").Image):toBe("rbxassetid://2")
				Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Ada")
				Verify.expect(mark.Visible):toBe(false)
				items:set(roster("rbxassetid://2", "busy"))
				Verify.expect((face:GetAttribute("AccessibleLabel"))):toBe("Ada, busy")
				Verify.expect(mark.Visible):toBe(true)
				Verify.expect((mark:HasTag("facet-status-error"))):toBe(true)
				Verify.expect(mark:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale):toBe(0)
				local overflow = group:FindFirstChild("Overflow")
				overflow.Activated.fire()
				Verify.expect(activations):toBe(1)
				Verify.expect(overflow.Selectable):toBe(true)
				items:set({})
				Verify.expect((group:FindFirstChild("a"))):toBe(nil)
				Verify.expect((face.isDestroyed())):toBe(true)
				Verify.expect((group:FindFirstChild("Overflow"))):toBe(nil)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps distinct content identities and shares one request across repeated user ids", {
			id = "native_parity_strength_icons::avatar groups::keeps distinct content identities and shares one request across repeated user ids",
			run = function()
				local engine, runtime, UI = setup()
				local loaded, released = 0, 0
				local shared = Compose.createSharedResource(function(): (FixtureMediaTypes.ImageResource, (() -> ())?)
					loaded += 1
					return {
						state = Compose.cell("ready" :: FixtureMediaTypes.ImageState),
						value = Compose.cell("rbxthumb://type=AvatarHeadShot&id=1"),
					}, function()
						released += 1
					end
				end)
				local items = Compose.cell({
					{ id = "a", name = "Ada", image = "rbxassetid://123" } :: FixtureMediaTypes.AvatarMember,
					{ id = "b", name = "Bo", image = "rbxassetid://456" } :: FixtureMediaTypes.AvatarMember,
					{
						id = "c",
						name = "Côte",
						userId = 1,
						resource = function()
							return shared()
						end,
					} :: FixtureMediaTypes.AvatarMember,
					{
						id = "d",
						name = "Dan",
						userId = 1,
						resource = function()
							return shared()
						end,
					} :: FixtureMediaTypes.AvatarMember,
				})
				local stop, group: any = runtime.mount(function()
					return UI.AvatarGroup({ items = items })
				end, engine.new("Folder"))
				local function image(id: string): any
					return group:FindFirstChild(id):FindFirstChild("Portrait"):FindFirstChild("Image")
				end
				Verify.expect(loaded):toBe(1)
				Verify.expect(image("a").Image):toBe("rbxassetid://123")
				Verify.expect(image("b").Image):toBe("rbxassetid://456")
				Verify.expect(image("a") ~= image("b")):toBe(true)
				Verify.expect(image("c").Image):toBe("rbxthumb://type=AvatarHeadShot&id=1")
				Verify.expect(image("d").Image):toBe("rbxthumb://type=AvatarHeadShot&id=1")
				Verify.expect(image("c") ~= image("d")):toBe(true)
				local first = group:FindFirstChild("a")
				items:set({ { id = "a", name = "Ada", image = "rbxassetid://789" } :: FixtureMediaTypes.AvatarMember })
				Verify.expect(image("a").Image):toBe("rbxassetid://789")
				Verify.expect(released):toBe(1)
				Verify.expect((group:FindFirstChild("a"))):toBe(first)
				Verify.expect((group:FindFirstChild("c"))):toBe(nil)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("builds the thumbnail address from a member user id", {
			id = "native_parity_strength_icons::avatar groups::builds the thumbnail address from a member user id",
			run = function()
				local engine, runtime, UI = setup()
				local stop, group: any = runtime.mount(function()
					return UI.AvatarGroup({
						items = { { id = "u", name = "User", userId = 24813339 } :: FixtureMediaTypes.AvatarMember },
					})
				end, engine.new("Folder"))
				Verify.expect(group:FindFirstChild("u"):FindFirstChild("Portrait"):FindFirstChild("Image").Image)
					:toBe("rbxthumb://type=AvatarHeadShot&id=24813339&w=150&h=150")
				stop()
				runtime:dispose()
			end,
		})
	end)

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function iconPackage(entries: { [string]: any }): any
		local package = themes.neutralPackage()
		assert(package.assets).cross = { content = "rbxassetid://33" }
		assert(package.assets).caretHot = { content = "rbxassetid://32" }
		assert(package.assets).caret = { content = "rbxassetid://31" }
		package.icons = entries
		return assert(themes.define(package))
	end

	verifyHarness:suite("semantic icons", function()
		verifyHarness:case("resolves declared states and falls back to default art for an undeclared state", {
			id = "native_parity_strength_icons::semantic icons::resolves declared states and falls back to default art for an undeclared state",
			run = function()
				local package = iconPackage({ close = { default = "cross", hover = "caretHot" } })
				Verify.expect((themes.resolveIcon(package, "close"))):toBe("rbxassetid://33")
				Verify.expect((themes.resolveIcon(package, "close", "default"))):toBe("rbxassetid://33")
				Verify.expect((themes.resolveIcon(package, "close", "hover"))):toBe("rbxassetid://32")
				for _, state in { "pressed", "selected", "disabled" } do
					Verify.expect((themes.resolveIcon(package, "close", state :: any))):toBe("rbxassetid://33")
				end
				local namespaced = iconPackage({ ["demo:gauge.needle"] = { default = "caret", pressed = "caretHot" } })
				Verify.expect((themes.resolveIcon(namespaced, "demo:gauge.needle"))):toBe("rbxassetid://31")
				Verify.expect((themes.resolveIcon(namespaced, "demo:gauge.needle", "pressed"))):toBe("rbxassetid://32")
				Verify.expect((themes.resolveIcon(namespaced, "demo:gauge.needle", "hover"))):toBe("rbxassetid://31")
				local engine, runtime, UI = controlsFor({ theme = package })
				local selected, enabled = Compose.cell(false), Compose.cell(true)
				local stop, button: any = runtime.mount(function()
					return UI.Button({ icon = "close", label = "Close", selected = selected, enabled = enabled })
				end, engine.new("Folder"))
				local icon = find(button, "LeadingIcon")
				Verify.expect(icon.Image):toBe("rbxassetid://33")
				button.GuiState = engine.types.Enum.GuiState.Hover
				Verify.expect(icon.Image):toBe("rbxassetid://32")
				button.GuiState = engine.types.Enum.GuiState.Press
				Verify.expect(icon.Image):toBe("rbxassetid://33")
				button.GuiState = engine.types.Enum.GuiState.Idle
				selected:set(true)
				Verify.expect(icon.Image):toBe("rbxassetid://33")
				enabled:set(false)
				Verify.expect(icon.Image):toBe("rbxassetid://33")
				Verify.expect((find(button, "LeadingIcon"))):toBe(icon)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("resolves the settings gear to the archived asset with and without a package", {
			id = "native_parity_strength_icons::semantic icons::resolves the settings gear to the archived asset with and without a package",
			run = function()
				Verify.expect((themes.resolveIcon({}, "settings"))):toBe("rbxassetid://78513807849201")
				Verify.expect((themes.resolveIcon(themes.neutralPackage(), "settings")))
					:toBe("rbxassetid://78513807849201")
				Verify.expect((themes.resolveIcon(assert(themes.define(themes.neutralPackage())), "settings")))
					:toBe("rbxassetid://78513807849201")
				Verify.expect(icons.ART.settings.contentId):toBe("rbxassetid://78513807849201")
				Verify.expect(icons.ART.settings.tintRole):toBe("content")
				local engine, runtime, UI = controlsFor()
				local stop, root: any = runtime.mount(function()
					return UI.Picker({
						selected = Compose.cell("a"),
						style = "segmented" :: "segmented",
						iconOnly = true,
						options = {
							{ value = "a", label = "Alpha", icon = "settings" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end, engine.new("Folder"))
				Verify.expect(find(find(root, "a"), "LeadingIcon").Image):toBe("rbxassetid://78513807849201")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("returns the theme art per state or the exact framework art when the theme declares none", {
			id = "native_parity_strength_icons::semantic icons::returns the theme art per state or the exact framework art when the theme declares none",
			run = function()
				local neutral = themes.neutralPackage()
				for name, entry in icons.ART do
					Verify.expect(`{name} -> {themes.resolveIcon(neutral, name)}`):toBe(`{name} -> {entry.contentId}`)
					Verify.expect(string.match(entry.contentId, "^rbxassetid://%d+$") ~= nil):toBe(true)
					Verify.expect(entry.tintRole):toBe("content")
				end
				Verify.expect((themes.resolveIcon(neutral, "facet:search"))):toBe("rbxassetid://85188541706347")
				local partial = iconPackage({ close = "cross", ["chevron.trailing"] = "caret" })
				Verify.expect((themes.resolveIcon(partial, "close"))):toBe("rbxassetid://33")
				Verify.expect((themes.resolveIcon(partial, "chevron.trailing"))):toBe("rbxassetid://31")
				Verify.expect((themes.resolveIcon(partial, "chevron.down"))):toBe(icons.ART["chevron.down"].contentId)
				Verify.expect((themes.resolveIcon(partial, "menu"))):toBe(icons.ART.menu.contentId)
				Verify.expect((themes.resolveIcon(partial, "not.a.name"))):toBe(nil)
				Verify.expect((themes.resolveIcon(neutral, "not.a.name"))):toBe(nil)
				Verify.expect((themes.resolveIcon({}, "not.a.name"))):toBe(nil)
				Verify.expect((themes.resolveIcon({}, "close"))):toBe(icons.ART.close.contentId)
			end,
		})

		verifyHarness:case("keeps the Pixel Quest package art and fills missing action icons from the framework", {
			id = "native_parity_strength_icons::semantic icons::keeps the Pixel Quest package art and fills missing action icons from the framework",
			run = function()
				local pixel = require("../examples/themes/pixel_quest")
				local package = assert(pixel.build(themes))
				for _, name in { "menu", "flag", "facet:search", "close" } do
					local resolved = themes.resolveIcon(package, name)
					Verify.expect(
						`{name}: {type(resolved) == "string" and string.match(resolved, "^rbxassetid://%d+$") ~= nil}`
					)
						:toBe(`{name}: true`)
				end
				Verify.expect((themes.resolveIcon(package, "close"))):toBe(package.assets.pixel_icon_cross.content)
				Verify.expect(themes.resolveIcon(package, "close") ~= icons.ART.close.contentId):toBe(true)
				Verify.expect((themes.resolveIcon(package, "menu"))):toBe(package.assets.menu.content)
				Verify.expect((themes.resolveIcon(package, "flag"))):toBe(package.assets.flag.content)
				Verify.expect((themes.resolveIcon(package, "trash"))):toBe(icons.ART.trash.contentId)
				local bare = assert(pixel.buildWithoutIcons(themes))
				Verify.expect((themes.resolveIcon(bare, "menu"))):toBe(icons.ART.menu.contentId)
				Verify.expect((themes.resolveIcon(bare, "close"))):toBe(icons.ART.close.contentId)
			end,
		})

		verifyHarness:case(
			"draws the standard magnifying glass across shipped themes and lets package art override it",
			{
				id = "native_parity_strength_icons::semantic icons::draws the standard magnifying glass across shipped themes and lets package art override it",
				run = function()
					local standard = "rbxassetid://85188541706347"
					Verify.expect(icons.ART["facet:search"].contentId):toBe(standard)
					Verify.expect((themes.resolveIcon(themes.neutralPackage(), "facet:search"))):toBe(standard)
					for _, name in { "pixel_quest", "compact_pointer", "glossy_touch" } do
						local package = assert(requireDynamic("../examples/themes/" .. name).build(themes))
						Verify.expect(`{name}: {themes.resolveIcon(package, "facet:search")}`)
							:toBe(`{name}: {standard}`)
					end
					local custom = iconPackage({ ["facet:search"] = "caret" })
					Verify.expect((themes.resolveIcon(custom, "facet:search"))):toBe("rbxassetid://31")
					local engine, runtime, UI = setup({ theme = custom })
					local stop, root: any = runtime.mount(function()
						return UI.Label({ title = "Find", icon = "facet:search" })
					end, engine.new("Folder"))
					Verify.expect(root:FindFirstChildWhichIsA("ImageLabel").Image):toBe("rbxassetid://31")
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("sizes icons from the theme rung metric, with defaults and a filled partial declaration", {
			id = "native_parity_strength_icons::semantic icons::sizes icons from the theme rung metric, with defaults and a filled partial declaration",
			run = function()
				local rung = Compose.cell("regular" :: "compact" | "regular" | "large")
				local selected = Compose.cell(themes.neutralPackage())
				local engine, runtime, UI = setup({ theme = selected, controlSize = rung })
				local stop, root: any = runtime.mount(function()
					return UI.Label({ title = "Find", icon = "facet:search" })
				end, engine.new("Folder"))
				local icon = root:FindFirstChildWhichIsA("ImageLabel")
				for name, size in { compact = 16, regular = 20, large = 24 } do
					rung:set(name :: "compact" | "regular" | "large")
					Verify.expect(`{name}: {icon.Size.X.Offset}x{icon.Size.Y.Offset}`):toBe(`{name}: {size}x{size}`)
				end
				local partial = themes.neutralPackage()
				partial.metrics.controlSizes = { large = { iconSize = 48 } } :: any
				local package = assert(themes.define(partial))
				Verify.expect(package.metrics.controlSizes.large.height):toBe(56)
				Verify.expect(package.metrics.controlSizes.compact.iconSize):toBe(16)
				selected:set(package)
				for name, size in { compact = 16, regular = 20, large = 48 } do
					rung:set(name :: "compact" | "regular" | "large")
					Verify.expect(`{name}: {icon.Size.X.Offset}x{icon.Size.Y.Offset}`):toBe(`{name}: {size}x{size}`)
				end
				Verify.expect((root:FindFirstChildWhichIsA("ImageLabel"))):toBe(icon)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("swaps the disclosure caret between trailing and down chevron art on the same icon", {
			id = "native_parity_strength_icons::semantic icons::swaps the disclosure caret between trailing and down chevron art on the same icon",
			run = function()
				local engine, runtime, UI = controlsFor()
				local expanded = Compose.cell(false)
				local stop, disclosure: any = runtime.mount(function()
					return UI.DisclosureGroup({
						label = "Advanced",
						expanded = expanded,
						content = function(): Instance
							return UI.Text({ text = "Body" })
						end,
					})
				end, engine.new("Folder"))
				local header = disclosure:FindFirstChild("Header")
				local caret = find(header, "LeadingIcon")
				Verify.expect(caret.ClassName):toBe("ImageLabel")
				Verify.expect((caret:HasTag("facet-icon"))):toBe(true)
				Verify.expect(caret.Image):toBe(icons.ART["chevron.trailing"].contentId)
				Verify.expect(#textLabels(header) > 0):toBe(true)
				for _, label in textLabels(header) do
					Verify.expect((string.find(label.Text, "\u{25B8}", 1, true))):toBe(nil)
					Verify.expect((string.find(label.Text, "\u{25BE}", 1, true))):toBe(nil)
				end
				expanded:set(true)
				Verify.expect((find(header, "LeadingIcon"))):toBe(caret)
				Verify.expect(caret.Image):toBe(icons.ART["chevron.down"].contentId)
				expanded:set(false)
				Verify.expect(caret.Image):toBe(icons.ART["chevron.trailing"].contentId)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("resolves, sizes, tags and pixel-samples an icon element that dies with its owner", {
			id = "native_parity_strength_icons::semantic icons::resolves, sizes, tags and pixel-samples an icon element that dies with its owner",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local package = Compose.cell(themes.neutralPackage())
				local ctx = context(Compose, runtime, { types = engine.types, theme = package })
				local folder = engine.new("Folder")
				local baseline = engine.census()
				local name = Compose.cell("close")
				local stop, icon: any = runtime.mount(function()
					return ctx.icon(name)
				end, folder)
				Verify.expect(icon.ClassName):toBe("ImageLabel")
				Verify.expect(icon.Image):toBe(icons.ART.close.contentId)
				Verify.expect(icon.Size):toBe(engine.types.UDim2.fromOffset(20, 20))
				Verify.expect(icon.BackgroundTransparency):toBe(1)
				Verify.expect((icon:HasTag("facet-icon"))):toBe(true)
				Verify.expect(icon.Active):toBe(false)
				Verify.expect(icon.ResampleMode):toBe(engine.types.Enum.ResamplerMode.Default)
				name:set("menu")
				Verify.expect(icon.Image):toBe(icons.ART.menu.contentId)
				local pixel = themes.neutralPackage()
				pixel.identity.rendering = "pixel"
				package:set(pixel)
				Verify.expect(icon.ResampleMode):toBe(engine.types.Enum.ResamplerMode.Pixelated)
				Verify.expect((pcall(function()
					name:set("not.an.icon")
				end))):toBe(false)
				stop()
				Verify.expect((icon.isDestroyed())):toBe(true)
				Verify.expect(icon.Parent):toBe(nil)
				runtime:dispose()
				Verify.expect(engine.census().live):toBe(baseline.live)
				Verify.expect(engine.census().connections):toBe(baseline.connections)
			end,
		})

		verifyHarness:case(
			"re-renders mounted icons on content and declaration changes but not on palette or map order",
			{
				id = "native_parity_strength_icons::semantic icons::re-renders mounted icons on content and declaration changes but not on palette or map order",
				run = function()
					local function variant(configure: (any) -> ()): any
						local package = themes.neutralPackage()
						assert(package.assets).plus = { content = "rbxassetid://901" }
						assert(package.assets).minus = { content = "rbxassetid://902" }
						package.icons =
							{ increment = "plus", decrement = "minus" } :: { [string]: FixtureThemeTypes.IconEntry }
						configure(package)
						return assert(themes.define(package))
					end
					local base = variant(function() end)
					local selected = Compose.cell(base)
					local engine, runtime, UI = setup({ theme = selected })
					local stop, root: any = runtime.mount(function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Label "Up" { title = "Up", icon = "increment" } :: unknown,
							UI.Label "Down" { title = "Down", icon = "decrement" },
						})
					end, engine.new("Folder"))
					local up = root:FindFirstChild("Up"):FindFirstChildWhichIsA("ImageLabel")
					local down = root:FindFirstChild("Down"):FindFirstChildWhichIsA("ImageLabel")
					local writes = 0
					up:GetPropertyChangedSignal("Image"):Connect(function()
						writes += 1
					end)
					down:GetPropertyChangedSignal("Image"):Connect(function()
						writes += 1
					end)
					Verify.expect(up.Image):toBe("rbxassetid://901")
					Verify.expect(down.Image):toBe("rbxassetid://902")
					selected:set(variant(function(package)
						package.style.themes[1].colors.accent = { r = 0.2, g = 0.4, b = 0.9 }
					end))
					selected:set(variant(function(package)
						package.icons = { decrement = "minus", increment = "plus" }
					end))
					Verify.expect(writes):toBe(0)
					selected:set(variant(function(package)
						package.assets.plus.content = "rbxassetid://903"
					end))
					Verify.expect(up.Image):toBe("rbxassetid://903")
					Verify.expect(writes):toBe(1)
					selected:set(variant(function(package)
						package.icons = { increment = { default = "plus", hover = "minus" }, decrement = "minus" }
					end))
					Verify.expect(up.Image):toBe("rbxassetid://901")
					selected:set(variant(function(package)
						package.icons = { increment = "plus" }
					end))
					Verify.expect(down.Image):toBe(icons.ART.decrement.contentId)
					selected:set(base)
					Verify.expect(down.Image):toBe("rbxassetid://902")
					Verify.expect((root:FindFirstChild("Up"):FindFirstChildWhichIsA("ImageLabel"))):toBe(up)
					Verify.expect((root:FindFirstChild("Down"):FindFirstChildWhichIsA("ImageLabel"))):toBe(down)
					stop()
					runtime:dispose()
				end,
			}
		)
	end)

	local SKIN_STATES = { "default", "hover", "pressed", "selected", "disabled" }

	local function skinImages(package: any, slots: { string }?): (number, number, { string })
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local pixelated, other, offenders = 0, 0, {}
		local names = slots
		if names == nil then
			local collected = {}
			for slot, recipe in package.chrome do
				if recipe.kind ~= "native" and recipe.kind ~= "none" then
					table.insert(collected, slot)
				end
			end
			table.sort(collected)
			names = collected
		end
		for _, slot in names :: { string } do
			local state: FixtureComposeTypes.Cell<"default" | "disabled" | "hover" | "pressed" | "selected"> =
				Compose.cell("default" :: FixtureThemeTypes.SkinState)
			local stop, root: any = runtime.mount(function()
				return themes.skin(runtime, package, slot, { types = engine.types, state = state })
			end, engine.new("Folder"))
			for _, name in SKIN_STATES do
				state:set(name :: FixtureThemeTypes.SkinState)
				for _, image in imageLabels(root) do
					if image.Visible then
						if image.ResampleMode == engine.types.Enum.ResamplerMode.Pixelated then
							pixelated += 1
						else
							other += 1
							table.insert(offenders, `{slot}/{name}/{image.Name}`)
						end
					end
				end
			end
			stop()
		end
		runtime:dispose()
		return pixelated, other, offenders
	end

	verifyHarness:suite("pixel rendering", function()
		verifyHarness:case("stamps Pixelated on every Pixel Quest skin layer in every state", {
			id = "native_parity_strength_icons::pixel rendering::stamps Pixelated on every Pixel Quest skin layer in every state",
			run = function()
				local package = assert(require("../examples/themes/pixel_quest").build(themes))
				Verify.expect(package.identity.rendering):toBe("pixel")
				local pixelated, other, offenders = skinImages(package)
				Verify.expect(pixelated >= 40):toBe(true)
				Verify.expect((table.concat(offenders, ", "))):toBe("")
				Verify.expect(other):toBe(0)
			end,
		})

		verifyHarness:case(
			"stamps every layer of a pixel stack, state-swapped art and icons, and a standard package stamps none",
			{
				id = "native_parity_strength_icons::pixel rendering::stamps every layer of a pixel stack, state-swapped art and icons, and a standard package stamps none",
				run = function()
					local function stack(rendering: (string | boolean)?): any
						local package = themes.neutralPackage()
						package.identity.rendering = rendering :: any
						assert(package.assets).art = { content = "rbxassetid://10" }
						assert(package.assets).hot =
							{ content = "rbxassetid://11", sliceCenter = { x0 = 2, y0 = 2, x1 = 6, y1 = 6 } }
						package.icons =
							{ close = { default = "art", pressed = "hot" } } :: { [string]: FixtureThemeTypes.IconEntry }
						assert(package.chrome).control = {
							kind = "layered" :: "layered",
							layers = {
								{ kind = "fill" :: "fill", asset = { default = "art", pressed = "hot" } } :: FixtureThemeTypes.SkinLayer,
								{ kind = "tile" :: "tile", asset = "art", tileSize = { w = 8, h = 8 } } :: FixtureThemeTypes.SkinLayer,
								{ kind = "edges" :: "edges", asset = "art", thickness = 4 } :: FixtureThemeTypes.SkinLayer,
								{ kind = "corners" :: "corners", asset = "art", size = 8 } :: FixtureThemeTypes.SkinLayer,
								{
									kind = "plaque" :: "plaque",
									asset = { default = "art", hover = "hot" },
									size = { w = 40, h = 12 },
								} :: FixtureThemeTypes.SkinLayer,
							},
						}
						return assert(themes.define(package))
					end
					for _, rendering in { "pixel", false } :: { string | boolean } do
						local package = stack(if rendering then "pixel" else nil)
						local pixelated, other = skinImages(package, { "control" })
						local layers = 1 + 1 + 4 + 4 + 1
						if rendering then
							Verify.expect(pixelated):toBe(layers * #SKIN_STATES)
							Verify.expect(other):toBe(0)
						else
							Verify.expect(pixelated):toBe(0)
							Verify.expect(other):toBe(layers * #SKIN_STATES)
						end
						local engine = engineLib.new()
						local runtime: ComposeRuntime = Roblox.createRuntime(engine)
						local ctx = context(Compose, runtime, { types = engine.types, theme = package })
						local state: FixtureComposeTypes.Cell<"default" | "disabled" | "hover" | "pressed" | "selected"> =
							Compose.cell("default" :: FixtureThemeTypes.SkinState)
						local stop, icon: any = runtime.mount(function()
							return ctx.icon("close", nil, state)
						end, engine.new("Folder"))
						local expected = if rendering
							then engine.types.Enum.ResamplerMode.Pixelated
							else engine.types.Enum.ResamplerMode.Default
						Verify.expect(icon.Image):toBe("rbxassetid://10")
						Verify.expect(icon.ResampleMode):toBe(expected)
						state:set("pressed")
						Verify.expect(icon.Image):toBe("rbxassetid://11")
						Verify.expect(icon.ResampleMode):toBe(expected)
						stop()
						runtime:dispose()
					end
				end,
			}
		)

		verifyHarness:case("keeps shipped standard packages on Default resampling across every skin state", {
			id = "native_parity_strength_icons::pixel rendering::keeps shipped standard packages on Default resampling across every skin state",
			run = function()
				for _, name in { "fantasy_ornate", "fantasy_parchment", "glossy_touch", "compact_pointer" } do
					local package = assert(requireDynamic("../examples/themes/" .. name).build(themes))
					local pixelated, other = skinImages(package)
					Verify.expect(`{name}: {pixelated} pixelated, some art {other > 0}`)
						:toBe(`{name}: 0 pixelated, some art true`)
				end
			end,
		})
	end)

	verifyHarness:suite("reference package art", function()
		verifyHarness:case("resolves Fantasy Ornate's six mapped icons and one namespaced icon to its own art", {
			id = "native_parity_strength_icons::reference package art::resolves Fantasy Ornate's six mapped icons and one namespaced icon to its own art",
			run = function()
				local package = assert(require("../examples/themes/fantasy_ornate").build(themes))
				local own: { [string]: string } = {
					increment = "ornate_icon_plus",
					decrement = "ornate_icon_minus",
					["chevron.trailing"] = "ornate_icon_chevron_right",
					["chevron.down"] = "ornate_icon_chevron_down",
					checkmark = "ornate_icon_check",
					close = "ornate_icon_cross",
					["ornate:settings"] = "ornate_icon_gear",
				}
				local count = 0
				for name, asset in own do
					count += 1
					local resolved = themes.resolveIcon(package, name)
					Verify.expect(`{name}: {resolved}`):toBe(`{name}: {assert(package.assets)[asset].content}`)
					Verify.expect(string.match(resolved :: string, "^rbxassetid://%d+$") ~= nil):toBe(true)
					if icons.ART[name] then
						Verify.expect(resolved ~= icons.ART[name].contentId):toBe(true)
					end
				end
				Verify.expect(count):toBe(7)
				for name in package.icons do
					Verify.expect(own[name] ~= nil):toBe(true)
				end
				for _, name in { "menu", "more" } do
					Verify.expect((themes.resolveIcon(package, name))):toBe(icons.ART[name].contentId)
					for _, asset in package.assets do
						Verify.expect(asset.content == icons.ART[name].contentId):toBe(false)
					end
				end
			end,
		})

		verifyHarness:case("gives the platform pair one authored icon each and the framework art for the rest", {
			id = "native_parity_strength_icons::reference package art::gives the platform pair one authored icon each and the framework art for the rest",
			run = function()
				for _, name in { "glossy_touch", "compact_pointer" } do
					local package = assert(requireDynamic("../examples/themes/" .. name).build(themes))
					local count = 0
					for icon in package.icons do
						Verify.expect(icon):toBe("facet:search")
						count += 1
					end
					Verify.expect(count):toBe(1)
					Verify.expect((themes.resolveIcon(package, "facet:search"))):toBe(package.assets.search.content)
					for _, icon in { "increment", "decrement", "chevron.trailing" } do
						Verify.expect(`{name} {icon}: {themes.resolveIcon(package, icon)}`)
							:toBe(`{name} {icon}: {icons.ART[icon].contentId}`)
					end
				end
			end,
		})

		verifyHarness:case(
			"authors Fantasy Ornate art as content and resolves both spellings to the same image content",
			{
				id = "native_parity_strength_icons::reference package art::authors Fantasy Ornate art as content and resolves both spellings to the same image content",
				run = function()
					local source = fs.readFile("examples/themes/fantasy_ornate.luau")
					Verify.expect(string.find(source, 'content = "rbxassetid://', 1, true) ~= nil):toBe(true)
					Verify.expect((string.find(source, "contentId", 1, true))):toBe(nil)
					local package = assert(require("../examples/themes/fantasy_ornate").build(themes))
					local assets = 0
					for name, asset in package.assets do
						assets += 1
						Verify.expect(`{name}: {type(asset.content)}`):toBe(`{name}: string`)
						Verify.expect(`{name}: {asset.contentId}`):toBe(`{name}: nil`)
					end
					Verify.expect(assets > 10):toBe(true)
					Verify.expect((themes.resolveIcon(package, "close"))):toBe(package.assets.ornate_icon_cross.content)
					local alias = require("../examples/themes/content_alias_test")
					local viaContent, viaContentId = assert(alias.build(themes)), assert(alias.buildAlias(themes))
					Verify.expect((themes.resolveIcon(viaContent, "increment"))):toBe("rbxassetid://137937473154830")
					Verify.expect((themes.resolveIcon(viaContentId, "increment"))):toBe("rbxassetid://137937473154830")
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local images = {}
					for _, package in { viaContent, viaContentId } do
						local stop, root: any = runtime.mount(function()
							return themes.skin(runtime, package, "control", { types = engine.types })
						end, engine.new("Folder"))
						local image: any = root:FindFirstChild("control1")
						table.insert(images, {
							image = image.Image,
							scale = image.ScaleType,
							center = image.SliceCenter,
						})
						stop()
					end
					Verify.expect(images[1].image):toBe("rbxassetid://70509734376718")
					Verify.expect(images[2].image):toBe(images[1].image)
					Verify.expect(images[2].scale):toBe(images[1].scale)
					Verify.expect(images[2].center):toBe(images[1].center)
					Verify.expect(images[1].center):toBe(engine.types.Rect.new(16, 16, 20, 20))
					runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("icon layout", function()
		verifyHarness:case(
			"places a Label icon leading or trailing beside its title with the themed art size and gap",
			{
				id = "native_parity_strength_icons::icon layout::places a Label icon leading or trailing beside its title with the themed art size and gap",
				run = function()
					local package = Compose.cell(themes.neutralPackage())
					local gap = Compose.cell(12)
					local engine, runtime, UI = setup({ theme = package })
					local stop, root: any = runtime.mount(function()
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							UI.Label "Leading" { title = "Save", icon = "checkmark" } :: unknown,
							UI.Label "Trailing" {
								title = "Next",
								icon = "chevron.trailing",
								iconPosition = "trailing",
								gap = gap,
							},
						})
					end, engine.new("Folder"))
					for name, expected in
						{ Leading = { "icon", "text" }, Trailing = { "text", "icon" } } :: { [string]: { string } }
					do
						local row = root:FindFirstChild(name)
						local icon, title =
							row:FindFirstChildWhichIsA("ImageLabel"), row:FindFirstChildWhichIsA("TextLabel")
						local layout = row:FindFirstChildWhichIsA("UIListLayout")
						Verify.expect(row.ClassName):toBe("Frame")
						Verify.expect(layout.FillDirection):toBe(engine.types.Enum.FillDirection.Horizontal)
						Verify.expect(layout.SortOrder):toBe(engine.types.Enum.SortOrder.LayoutOrder)
						Verify.expect(icon.Parent):toBe(row)
						Verify.expect(title.Parent):toBe(row)
						Verify.expect((icon:HasTag("facet-icon"))):toBe(true)
						Verify.expect(icon.Size):toBe(engine.types.UDim2.fromOffset(20, 20))
						local order = if icon.LayoutOrder < title.LayoutOrder
							then { "icon", "text" }
							else { "text", "icon" }
						Verify.expect(`{name}: {order[1]} then {order[2]}`)
							:toBe(`{name}: {expected[1]} then {expected[2]}`)
					end
					local leading = root:FindFirstChild("Leading")
					local trailing = root:FindFirstChild("Trailing")
					Verify.expect(leading:FindFirstChildWhichIsA("TextLabel").Text):toBe("Save")
					Verify.expect(leading:FindFirstChildWhichIsA("ImageLabel").Image)
						:toBe(icons.ART.checkmark.contentId)
					Verify.expect(leading:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(8)
					local trailingLayout = trailing:FindFirstChildWhichIsA("UIListLayout")
					Verify.expect(trailingLayout.Padding.Offset):toBe(12)
					gap:set(4)
					Verify.expect(trailingLayout.Padding.Offset):toBe(4)
					local next = themes.neutralPackage()
					next.metrics.controlSizes.regular.iconSize = 32
					package:set(next)
					Verify.expect(leading:FindFirstChildWhichIsA("ImageLabel").Size)
						:toBe(engine.types.UDim2.fromOffset(32, 32))
					Verify.expect(trailing:FindFirstChildWhichIsA("ImageLabel").Size)
						:toBe(engine.types.UDim2.fromOffset(32, 32))
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("keeps a preferred hint glyph square at the theme icon size across a live theme swap", {
			id = "native_parity_strength_icons::icon layout::keeps a preferred hint glyph square at the theme icon size across a live theme swap",
			run = function()
				local package = Compose.cell(themes.neutralPackage())
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local input = engine.new("UserInputService")
				input.GetFocusedTextBox = function()
					return nil
				end
				input.GetImageForKeyCode = function()
					return "rbxassetid://123"
				end
				local UI = require("../src").controls(
					runtime,
					{
						types = engine.types,
						theme = package,
						services = { GuiService = engine.new("GuiService"), UserInputService = input },
					} :: any
				)
				local action = engine.new("InputAction")
				local binding = engine.new("InputBinding")
				binding.KeyCode = engine.types.Enum.KeyCode.ButtonX
				action.PreferredBinding = binding
				local stop, root: any = runtime.mount(function()
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						UI.ShortcutHint "Art" { action = action } :: unknown,
						UI.ShortcutHint "Keys" { keys = { { "Ctrl", "S" } } },
					})
				end, engine.new("Folder"))
				local art = find(root:FindFirstChild("Art"), "Glyph")
				local keys = root:FindFirstChild("Keys")
				Verify.expect(art.Image):toBe("rbxassetid://123")
				Verify.expect(art.Size):toBe(engine.types.UDim2.fromOffset(20, 20))
				Verify.expect(keys.Size.Y.Offset):toBe(28)
				for _, size in { 28, 16, 20 } do
					local next = themes.neutralPackage()
					next.metrics.controlSizes.regular.iconSize = size
					package:set(next)
					Verify.expect((find(root:FindFirstChild("Art"), "Glyph"))):toBe(art)
					Verify.expect(art.Size):toBe(engine.types.UDim2.fromOffset(size, size))
					Verify.expect(keys.Size.Y.Offset):toBe(size + 8)
				end
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("sliced and bar art", function()
		verifyHarness:case(
			"compiles slice art with or without declared source sizes and paints the exact slice values",
			{
				id = "native_parity_strength_icons::sliced and bar art::compiles slice art with or without declared source sizes and paints the exact slice values",
				run = function()
					local sized = themes.neutralPackage()
					assert(sized.assets).plate = {
						content = "rbxassetid://51",
						sliceCenter = { x0 = 8, y0 = 6, x1 = 24, y1 = 26 },
						sliceScale = 2,
						width = 32,
						height = 32,
					} :: any
					assert(sized.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "plate" }
					local package, report = themes.define(sized)
					Verify.expect(report.ok):toBe(true)
					local compiled = assert(assert(package).assets).plate :: any
					Verify.expect(compiled.width):toBe(32)
					Verify.expect(compiled.height):toBe(32)
					Verify.expect(compiled.sliceCenter.x0):toBe(8)
					Verify.expect(compiled.sliceCenter.y1):toBe(26)
					local bare = themes.neutralPackage()
					assert(bare.assets).plate =
						{ content = "rbxassetid://52", sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 } }
					assert(bare.chrome).control = { kind = "nineSlice" :: "nineSlice", asset = "plate" }
					local sizeless, sizelessReport = themes.define(bare)
					Verify.expect(sizelessReport.ok):toBe(true)
					Verify.expect((assert(assert(sizeless).assets).plate :: any).width):toBe(nil)
					local engine = engineLib.new()
					local runtime = Roblox.createRuntime(engine)
					for _, case in
						{
							{
								package = assert(package),
								image = "rbxassetid://51",
								rect = { 8, 6, 24, 26 },
								scale = 2,
							},
							{
								package = assert(sizeless),
								image = "rbxassetid://52",
								rect = { 8, 8, 24, 24 },
								scale = 1,
							},
						}
					do
						local stop, root: any = runtime.mount(function()
							return themes.skin(runtime, case.package, "control", { types = engine.types })
						end, engine.new("Folder"))
						local image: any = root:FindFirstChild("control1")
						Verify.expect(image.Image):toBe(case.image)
						Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Slice)
						Verify.expect(image.SliceCenter):toBe(engine.types.Rect.new(table.unpack(case.rect)))
						Verify.expect(image.SliceScale):toBe(case.scale)
						Verify.expect(image.Size):toBe(engine.types.UDim2.fromScale(1, 1))
						stop()
					end
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"paints a nine-slice skin with the package's own image values and only the role and palette art tints",
			{
				id = "native_parity_strength_icons::sliced and bar art::paints a nine-slice skin with the package's own image values and only the role and palette art tints",
				run = function()
					local package = assert(require("../examples/themes/fantasy_parchment").build(themes))
					local asset = package.assets.parchment_panel
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local target, root, sheet
					local stop = runtime.mount(function()
						target = ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
						root = themes.skin(
							runtime,
							package,
							"panel",
							{ types = engine.types, target = target :: GuiObject }
						)
						sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							target :: unknown,
							root,
							sheet,
						})
					end, engine.new("Folder"))
					local image: any = root:FindFirstChild("panel1", true)
					Verify.expect(image.Image):toBe(asset.contentId)
					Verify.expect(image.Image):toBe("rbxassetid://78012779616687")
					Verify.expect(image.ScaleType):toBe(engine.types.Enum.ScaleType.Slice)
					Verify.expect(image.SliceCenter):toBe(engine.types.Rect.new(40, 40, 104, 104))
					Verify.expect(image.SliceScale):toBe(asset.sliceScale)
					Verify.expect(image.ImageColor3):toBe(engine.types.Color3.new(1, 1, 1))
					Verify.expect(image.ImageTransparency):toBe(0)
					Verify.expect(image.BackgroundTransparency):toBe(1)
					Verify.expect((table.concat(image:GetTags(), ","))):toBe("facet-skin-art,facet-skin-art-panel")
					Verify.expect((target:HasTag("facet-skinned"))):toBe(true)
					local skinned = false
					for _, rule in (sheet:GetChildren() :: unknown) :: { StyleRule } do
						local properties = rule:GetProperties()
						local roleTint = rule.Selector == ".facet-role-destructive > #SkinBoundary >> .facet-skin-art"
							or rule.Selector == ".facet-accent > #SkinBoundary >> .facet-skin-art"
							or rule.Selector == ".facet-skinned.facet-selected > #SkinBoundary >> .facet-skin-art"
							or string.match(
								rule.Selector,
								"^%.facet%-badge[%.%-][%a%.%-]+ > #SkinBoundary >> %.facet%-skin%-art$"
							) ~= nil
							or (
								string.match(rule.Selector, "^%.facet%-skin%-art%-%a+$") ~= nil
								and properties.ImageColor3 ~= nil
							)
						Verify.expect(
							`{rule.Selector}: {properties.ImageColor3 ~= nil and string.find(
								rule.Selector,
								"skin-art",
								1,
								true
							) ~= nil}`
						):toBe(`{rule.Selector}: {roleTint}`)
						if rule.Selector == ".facet-skinned" then
							skinned = true
							Verify.expect(properties.BackgroundTransparency):toBe(1)
						end
					end
					Verify.expect(skinned):toBe(true)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"fits end caps inside the track ends, centres the centrepiece and defaults the fill to ltr",
			{
				id = "native_parity_strength_icons::sliced and bar art::fits end caps inside the track ends, centres the centrepiece and defaults the fill to ltr",
				run = function()
					local package = themes.neutralPackage()
					package.assets = {
						fill = { content = "rbxassetid://1" },
						start = { content = "rbxassetid://2" },
						finish = { content = "rbxassetid://3" },
						center = { content = "rbxassetid://4" },
						shared = { content = "rbxassetid://5" },
					}
					assert(package.chrome).barFill = { kind = "nineSlice" :: "nineSlice", asset = "fill" }
					assert(package.chrome).barCap = {
						kind = "nineSlice" :: "nineSlice",
						startAsset = "start",
						endAsset = "finish",
						size = { w = 28, h = 36 },
					}
					assert(package.chrome).barCenter =
						{ kind = "nineSlice" :: "nineSlice", asset = "center", size = { w = 36, h = 28 } }
					local selected = Compose.cell(package)
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
					local UI = media(context(Compose, runtime, { types = engine.types, theme = selected }))
					local thickness = Compose.cell(18)
					local stop, root: any = runtime.mount(function()
						return UI.ProgressView({ value = 0.01, thickness = thickness })
					end, engine.new("Folder"))
					local fill = root:FindFirstChild("Fill1", true)
					Verify.expect(fill.AnchorPoint):toBe(engine.types.Vector2.new(0, 0))
					Verify.expect(fill.Position):toBe(engine.types.UDim2.fromScale(0, 0))
					local skin = fill:FindFirstChild("Skin", true)
					Verify.expect(skin.AnchorPoint):toBe(engine.types.Vector2.new(0, 0))
					Verify.expect(skin.Size.X.Scale):toBe(100)
					Verify.expect(skin.Size.Y.Scale):toBe(1)
					local start, finish =
						root:FindFirstChild("barCap-start", true), root:FindFirstChild("barCap-end", true)

					for _, cap in { start, finish } do
						Verify.expect(cap.Position.Y.Scale):toBe(0.5)
						Verify.expect(cap.Size):toBe(engine.types.UDim2.fromOffset(14, 18))
					end
					Verify.expect(start.AnchorPoint):toBe(engine.types.Vector2.new(0, 0.5))
					Verify.expect(finish.AnchorPoint):toBe(engine.types.Vector2.new(1, 0.5))
					Verify.expect(start.Position.X.Scale):toBe(0)
					Verify.expect(finish.Position.X.Scale):toBe(1)
					Verify.expect(start.Image):toBe("rbxassetid://2")
					Verify.expect(finish.Image):toBe("rbxassetid://3")
					local center = root:FindFirstChild("barCenter", true)
					Verify.expect(center.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0.5))
					Verify.expect(center.Position):toBe(engine.types.UDim2.fromScale(0.5, 0.5))
					Verify.expect(center.Size):toBe(engine.types.UDim2.fromOffset(23, 18))
					for _, direction in { "ttb", "btt", "rtl" } :: { "btt" | "rtl" | "ttb" } do
						local next = table.clone(package)
						next.chrome = table.clone(package.chrome)
						assert(next.chrome).barFill = {
							kind = "nineSlice" :: "nineSlice",
							asset = "fill",
							direction = direction :: "btt" | "rtl" | "ttb",
						}
						selected:set(next)
						Verify.expect(center.Position):toBe(engine.types.UDim2.fromScale(0.5, 0.5))
						for _, cap in { start, finish } do
							Verify.expect(cap.AnchorPoint)
								:toBe(engine.types.Vector2.new(cap.Position.X.Scale, cap.Position.Y.Scale))
						end
						if direction == "rtl" then
							Verify.expect(start.Position):toBe(engine.types.UDim2.fromScale(1, 0.5))
							Verify.expect(finish.Position):toBe(engine.types.UDim2.fromScale(0, 0.5))
						else
							Verify.expect(start.Position.X.Scale):toBe(0.5)
							Verify.expect(finish.Position.X.Scale):toBe(0.5)
							Verify.expect(start.Position.Y.Scale):toBe(if direction == "btt" then 1 else 0)
							Verify.expect(finish.Position.Y.Scale):toBe(if direction == "btt" then 0 else 1)
						end
					end
					local sharedCap = table.clone(package)
					sharedCap.chrome = table.clone(package.chrome)
					assert(sharedCap.chrome).barCap =
						{ kind = "nineSlice" :: "nineSlice", asset = "shared", size = { w = 28, h = 36 } }
					selected:set(sharedCap)
					Verify.expect(start.Image):toBe("rbxassetid://5")
					Verify.expect(finish.Image):toBe("rbxassetid://5")

					thickness:set(36)
					root:FindFirstChild("Track", true).AbsoluteSize = engine.types.Vector2.new(200, 72)
					Verify.expect(start.Size):toBe(engine.types.UDim2.fromOffset(25, 32))
					Verify.expect(root:FindFirstChild("FillClip", true).Size):toBe(engine.types.UDim2.new(1, -50, 1, 0))
					thickness:set(8)
					Verify.expect(start.Visible or finish.Visible or center.Visible):toBe(false)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("clips the fill window, hangs caps on the track and tears the whole bar assembly down", {
			id = "native_parity_strength_icons::sliced and bar art::clips the fill window, hangs caps on the track and tears the whole bar assembly down",
			run = function()
				local package = themes.neutralPackage()
				package.assets = {
					track = { content = "rbxassetid://1" },
					fill = { content = "rbxassetid://2" },
					cap = { content = "rbxassetid://3" },
					center = { content = "rbxassetid://4" },
				}
				assert(package.chrome).barTrack = { kind = "nineSlice" :: "nineSlice", asset = "track" }
				assert(package.chrome).barFill = { kind = "nineSlice" :: "nineSlice", asset = "fill" }
				assert(package.chrome).barCap =
					{ kind = "nineSlice" :: "nineSlice", asset = "cap", size = { w = 12, h = 12 } }
				assert(package.chrome).barCenter =
					{ kind = "nineSlice" :: "nineSlice", asset = "center", size = { w = 12, h = 12 } }
				local engine = engineLib.new()
				local folder = engine.new("Folder")
				local baseline = engine.census()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local UI = media(context(Compose, runtime, { types = engine.types, theme = package }))
				local value = Compose.cell(0.4)
				local stop, root: any = runtime.mount(function()
					return UI.ProgressView({ value = value })
				end, folder)
				local track = root:FindFirstChild("Track", true)
				local clip = track:FindFirstChild("FillClip")
				Verify.expect(clip.ClipsDescendants):toBe(true)

				Verify.expect(clip.Size):toBe(engine.types.UDim2.new(1, -12, 1, 0))
				Verify.expect(clip.Position):toBe(engine.types.UDim2.fromOffset(6, 0))
				Verify.expect(clip.BackgroundTransparency):toBe(1)
				Verify.expect(track.ClipsDescendants):toBe(false)
				local fill = clip:FindFirstChild("Fill1")
				Verify.expect(fill.Parent):toBe(clip)
				Verify.expect(fill.ClipsDescendants):toBe(true)
				Verify.expect(fill:FindFirstChild("barFill1", true).Image):toBe("rbxassetid://2")
				Verify.expect(track:FindFirstChild("barTrack1", true).Image):toBe("rbxassetid://1")
				for _, name in { "barCap-start", "barCap-end", "barCenter" } do
					local ornament = track:FindFirstChild(name, true)
					Verify.expect(ornament ~= nil):toBe(true)
					Verify.expect((ornament:IsDescendantOf(clip))):toBe(false)
					Verify.expect((ornament:IsDescendantOf(track))):toBe(true)
					local branch = ornament
					while branch.Parent ~= track do
						branch = branch.Parent
					end
					Verify.expect(branch ~= clip):toBe(true)
					Verify.expect(branch.ClipsDescendants):toBe(false)
					Verify.expect(branch.ZIndex > clip.ZIndex):toBe(true)
				end
				local assembly = { track, clip, fill }
				for _, node in track:GetDescendants() do
					table.insert(assembly, node)
				end
				Verify.expect(#assembly > 8):toBe(true)
				value:set(0.9)
				Verify.expect((track:FindFirstChild("FillClip"))):toBe(clip)
				stop()
				for _, node in assembly do
					Verify.expect(`{node.Name}: {node.isDestroyed()}`):toBe(`{node.Name}: true`)
				end
				runtime:dispose()
				Verify.expect(engine.census().live):toBe(baseline.live)
				Verify.expect(engine.census().connections):toBe(baseline.connections)
			end,
		})
	end)
end
