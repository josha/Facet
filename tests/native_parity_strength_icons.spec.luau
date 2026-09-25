--!strict
local t = require("./lib/testkit")
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
	local runtime = Roblox.createRuntime(engine)
	local config: { [string]: any } = { types = engine.types }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = media(context(Compose, runtime, config :: any))
	return engine, runtime, UI
end

local function controlsFor(options: { [string]: any }?): (any, any, any)
	local engine: any = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
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

t.describe("async image states", function()
	t.it("preloads the retained ImageLabel itself and creates no temporary preload instance", function()
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
					PreloadAsync = function(_, list, callback)
						local before = #engine.made
						local liveBefore = engine.census().live
						table.insert(calls, { list = list, image = list[1].Image, count = #list })
						callback(list[1].Image, status)
						madeDuringPreload += #engine.made - before
						destroyedDuringPreload += liveBefore - engine.census().live
					end,
				},
			},
		}))
		local source, states = Compose.cell("rbxassetid://123"), {}
		local stop, root = runtime.mount(function()
			return UI.AsyncImage({
				source = source,
				onStatus = function(state)
					table.insert(states, state)
				end,
			})
		end, engine.new("Folder"))
		local image = root:FindFirstChild("Image")
		t.expect(states[#states]).toBe("loading")
		t.expect(image.Visible).toBe(false)
		t.expect(coroutine.resume(pending[1])).toBe(true)
		t.expect(#calls).toBe(1)
		t.expect(calls[1].count).toBe(1)
		t.expect(typeof(calls[1].list[1]) ~= "string").toBe(true)
		t.expect(calls[1].list[1]:IsA("ImageLabel")).toBe(true)
		t.expect(calls[1].list[1]).toBe(image)
		t.expect(calls[1].image).toBe("rbxassetid://123")
		t.expect(madeDuringPreload).toBe(0)
		t.expect(destroyedDuringPreload).toBe(0)
		t.expect(image.isDestroyed()).toBe(false)
		t.expect(image.Image).toBe("rbxassetid://123")
		t.expect(image.Visible).toBe(true)
		t.expect(states[#states]).toBe("ready")
		status = engine.types.Enum.AssetFetchStatus.Failure
		source:set("rbxassetid://456")
		t.expect(coroutine.resume(pending[2])).toBe(true)
		t.expect(calls[2].list[1]).toBe(image)
		t.expect(calls[2].image).toBe("rbxassetid://456")
		t.expect(states[#states]).toBe("failed")
		t.expect(image.Visible).toBe(false)
		t.expect(root:FindFirstChild("Placeholder").Visible).toBe(true)
		t.expect(#imageLabels(root)).toBe(1)
		stop()
		t.expect(image.isDestroyed()).toBe(true)
		environment.task = originalTask
		runtime:dispose()
	end)

	t.it("shows the placeholder and hides the image while the first request is pending", function()
		local engine, runtime, UI = setup()
		local states, requested = {}, {}
		local stop, root = runtime.mount(function()
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
		t.expect(requested).toEqual({ "rbxthumb://type=AvatarHeadShot&id=1" })
		t.expect(states).toEqual({ "loading" })
		local placeholder, image = root:FindFirstChild("Placeholder"), root:FindFirstChild("Image")
		t.expect(placeholder.Visible).toBe(true)
		t.expect(placeholder:HasTag("facet-skeleton")).toBe(true)
		t.expect(image.Visible).toBe(false)
		t.expect(#textLabels(root)).toBe(0)
		t.expect(#imageLabels(root)).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("keeps the placeholder and mounts no failure text when a failure has no failureLabel", function()
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
						PreloadAsync = function(_, list, callback)
							callback(list[1].Image, engine.types.Enum.AssetFetchStatus.Failure)
						end,
					},
				},
			}))
			local states, reasons = {}, {}
			local stop, root = runtime.mount(function()
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
			local placeholder, image = root:FindFirstChild("Placeholder"), root:FindFirstChild("Image")
			t.expect(states[#states]).toBe("failed")
			t.expect(reasons[#reasons] ~= nil).toBe(true)
			t.expect(placeholder.Visible).toBe(true)
			t.expect(placeholder:HasTag("facet-skeleton")).toBe(true)
			t.expect(image.Visible).toBe(false)
			t.expect(#textLabels(root)).toBe(0)
			t.expect(#imageLabels(root)).toBe(1)
			t.expect(#placeholder:GetChildren()).toBe(0)
			stop()
			environment.task = originalTask
			runtime:dispose()
		end
	end)

	t.it("renders a shared completion, dims the image and restores it, and releases with the owner", function()
		local engine, runtime, UI = setup()
		local acquired, released = 0, 0
		local state, value = Compose.cell("loading"), Compose.cell("")
		local resource = Compose.createSharedResource(function()
			acquired += 1
			return { state = state, value = value }, function()
				released += 1
			end
		end)
		local dimmed = Compose.cell(false)
		local first, one = runtime.mount(function()
			return UI.AsyncImage({ resource = resource, dimmed = dimmed })
		end, engine.new("Folder"))
		local second, two = runtime.mount(function()
			return UI.AsyncImage({ resource = resource })
		end, engine.new("Folder"))
		t.expect(acquired).toBe(1)
		local image = one:FindFirstChild("Image")
		t.expect(one:FindFirstChild("Placeholder").Visible).toBe(true)
		t.expect(image.Visible).toBe(false)
		value:set("rbxassetid://123")
		state:set("ready")
		t.expect(image.Image).toBe("rbxassetid://123")
		t.expect(image.Visible).toBe(true)
		t.expect(one:FindFirstChild("Placeholder").Visible).toBe(false)
		t.expect(two:FindFirstChild("Image").Image).toBe("rbxassetid://123")
		t.expect(image.ImageTransparency).toBe(0)
		dimmed:set(true)
		t.expect(image.ImageTransparency).toBe(0.35)
		t.expect(two:FindFirstChild("Image").ImageTransparency).toBe(0)
		dimmed:set(false)
		t.expect(image.ImageTransparency).toBe(0)
		first()
		t.expect(released).toBe(0)
		t.expect(image.isDestroyed()).toBe(true)
		second()
		t.expect(released).toBe(1)
		runtime:dispose()
	end)

	t.it("releases a shared resource on its last reference, cancels in-flight work and ignores late results", function()
		local engine = engineLib.new()
		local folder = engine.new("Folder")
		local baseline = engine.census()
		local runtime = Roblox.createRuntime(engine)
		local UI = media(context(Compose, runtime, { types = engine.types }))
		local acquired, released = 0, 0
		local resource = Compose.createSharedResource(function()
			acquired += 1
			return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://7") }, function()
				released += 1
			end
		end)
		local requests, cancellations, statuses = {}, 0, 0
		local stops = {}
		for _ = 1, 3 do
			table.insert(stops, (runtime.mount(function()
				return UI.AsyncImage({ resource = resource })
			end, folder)))
		end
		local pendingStop, pendingRoot = runtime.mount(function()
			return UI.AsyncImage({
				image = "rbxassetid://8",
				loader = function(content, resolve, reject)
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
		t.expect(acquired).toBe(1)
		stops[1]()
		stops[2]()
		t.expect(released).toBe(0)
		stops[3]()
		t.expect(released).toBe(1)
		local again = runtime.mount(function()
			return UI.AsyncImage({ resource = resource })
		end, folder)
		t.expect(acquired).toBe(2)
		again()
		t.expect(released).toBe(2)
		local image = pendingRoot:FindFirstChild("Image")
		t.expect(#requests).toBe(1)
		local observed = statuses
		pendingStop()
		t.expect(cancellations).toBe(1)
		requests[1].resolve("rbxassetid://late")
		requests[1].reject("late")
		t.expect(statuses).toBe(observed)
		t.expect(image.Visible).toBe(false)
		t.expect(cancellations).toBe(1)
		runtime:dispose()
		t.expect(engine.census().live).toBe(baseline.live)
		t.expect(engine.census().connections).toBe(baseline.connections)
		t.expect(acquired).toBe(released)
	end)
end)

t.describe("avatar faces", function()
	t.it("cuts UTF-8 first and last initials in authored case", function()
		local engine, runtime, UI = setup()
		local name = Compose.cell("Ada Quill")
		local stop, avatar = runtime.mount(function()
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
			t.expect(initials.Text).toBe(pair[2])
			t.expect(avatar:FindFirstChild("Initials")).toBe(initials)
		end
		stop()
		runtime:dispose()
	end)

	t.it("paints initials and passive semantics at the default regular diameter without a focus stop", function()
		local engine, runtime, UI = setup()
		local stop, avatar = runtime.mount(function()
			return UI.Avatar({ name = "Ada Quill" })
		end, engine.new("Folder"))
		t.expect(avatar:FindFirstChild("Initials").Text).toBe("AQ")
		t.expect(avatar:FindFirstChild("Initials").Visible).toBe(true)
		t.expect(avatar.Size).toBe(engine.types.UDim2.fromOffset(44, 44))
		t.expect(avatar:FindFirstChild("Initials").TextSize).toBe(18)
		t.expect(avatar:GetAttribute("AccessibleLabel")).toBe("Ada Quill")
		t.expect(avatar.Selectable).toBe(false)
		t.expect(avatar:HasTag("facet-avatar")).toBe(true)
		t.expect(avatar:FindFirstChild("Portrait")).toBe(nil)
		t.expect(avatar:FindFirstChild("Presence")).toBe(nil)
		stop()
		runtime:dispose()
	end)

	t.it("keeps one diameter through pending, ready and failed images and returns to initials on failure", function()
		for _, ready in { true, false } do
			local engine, runtime, UI = setup()
			local requests, statuses = {}, {}
			local stop, avatar = runtime.mount(function()
				return UI.Avatar({
					name = "Ada Quill",
					userId = 24813339,
					loader = function(content, resolve, reject)
						table.insert(requests, { content = content, resolve = resolve, reject = reject })
						return nil
					end,
					onStatus = function(state)
						table.insert(statuses, state)
					end,
				})
			end, engine.new("Folder"))
			t.expect(#requests).toBe(1)
			t.expect(requests[1].content).toBe("rbxthumb://type=AvatarHeadShot&id=24813339&w=150&h=150")
			local portrait = avatar:FindFirstChild("Portrait")
			local initials, image = avatar:FindFirstChild("Initials"), portrait:FindFirstChild("Image")
			t.expect(avatar.Size).toBe(engine.types.UDim2.fromOffset(44, 44))
			t.expect(portrait.Size).toBe(engine.types.UDim2.fromScale(1, 1))
			t.expect(initials.Visible).toBe(true)
			t.expect(image.Visible).toBe(false)
			t.expect(statuses[#statuses]).toBe("loading")
			if ready then
				requests[1].resolve("rbxassetid://75342910516929")
				t.expect(statuses[#statuses]).toBe("ready")
				t.expect(image.Image).toBe("rbxassetid://75342910516929")
				t.expect(image.Visible).toBe(true)
				t.expect(initials.Visible).toBe(false)
			else
				requests[1].reject("missing")
				t.expect(statuses[#statuses]).toBe("failed")
				t.expect(image.Visible).toBe(false)
				t.expect(initials.Visible).toBe(true)
				t.expect(initials.Text).toBe("AQ")
			end
			t.expect(avatar.Size).toBe(engine.types.UDim2.fromOffset(44, 44))
			stop()
			t.expect(image.isDestroyed()).toBe(true)
			runtime:dispose()
		end
	end)

	t.it("survives repeated resource state flips with one retained lease and rejects stale completions", function()
		local engine, runtime, UI = setup()
		local state, value = Compose.cell("loading"), Compose.cell("rbxassetid://1")
		local held, acquired = 0, 0
		local resource = Compose.createSharedResource(function()
			acquired += 1
			held += 1
			return { state = state, value = value }, function()
				held -= 1
			end
		end)
		local stop, avatar = runtime.mount(function()
			return UI.Avatar({ name = "Ada", resource = resource })
		end, engine.new("Folder"))
		local initials = avatar:FindFirstChild("Initials")
		local image = avatar:FindFirstChild("Portrait"):FindFirstChild("Image")
		for _ = 1, 8 do
			state:set("ready")
			t.expect(initials.Visible).toBe(false)
			t.expect(image.Visible).toBe(true)
			t.expect(avatar.Size.X.Offset).toBe(44)
			state:set("loading")
			t.expect(initials.Visible).toBe(true)
			t.expect(image.Visible).toBe(false)
			t.expect(held).toBe(1)
		end
		t.expect(acquired).toBe(1)
		state:set("failed")
		t.expect(initials.Visible).toBe(true)
		t.expect(avatar:FindFirstChild("Initials")).toBe(initials)
		stop()
		t.expect(held).toBe(0)
		local source, requests = Compose.cell("rbxassetid://first"), {}
		local stopSecond, second = runtime.mount(function()
			return UI.Avatar({
				name = "Bo",
				image = source,
				loader = function(content, resolve)
					requests[content] = resolve
					return nil
				end,
			})
		end, engine.new("Folder"))
		source:set("rbxassetid://second")
		requests["rbxassetid://first"]("rbxassetid://first")
		local secondImage = second:FindFirstChild("Portrait"):FindFirstChild("Image")
		t.expect(secondImage.Visible).toBe(false)
		t.expect(second:FindFirstChild("Initials").Visible).toBe(true)
		requests["rbxassetid://second"]("rbxassetid://second")
		t.expect(secondImage.Image).toBe("rbxassetid://second")
		t.expect(second:FindFirstChild("Initials").Visible).toBe(false)
		stopSecond()
		runtime:dispose()
	end)

	t.it("shares one caller resource between two standalone faces and frees it with the last one", function()
		local engine, runtime, UI = setup()
		local loaded, released = 0, 0
		local resource = Compose.createSharedResource(function()
			loaded += 1
			return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://21") }, function()
				released += 1
			end
		end)
		local stopA, a = runtime.mount(function()
			return UI.Avatar({ name = "A", resource = resource })
		end, engine.new("Folder"))
		local stopB, b = runtime.mount(function()
			return UI.Avatar({ name = "B", resource = resource })
		end, engine.new("Folder"))
		t.expect(loaded).toBe(1)
		for _, face in { a, b } do
			local image = face:FindFirstChild("Portrait"):FindFirstChild("Image")
			t.expect(image.Image).toBe("rbxassetid://21")
			t.expect(image.Visible).toBe(true)
			t.expect(face:FindFirstChild("Initials").Visible).toBe(false)
		end
		stopA()
		t.expect(released).toBe(0)
		t.expect(b:FindFirstChild("Portrait"):FindFirstChild("Image").Visible).toBe(true)
		stopB()
		t.expect(released).toBe(1)
		runtime:dispose()
	end)

	t.it("maps four presence states to four mark forms and follows a reactive presence label", function()
		local engine, runtime, UI = setup()
		local presence, label = Compose.cell("online"), Compose.cell("Available")
		local stop, avatar = runtime.mount(function()
			return UI.Avatar({
				name = "Ada",
				presence = presence,
				presenceLabel = label,
				onActivate = function() end,
			})
		end, engine.new("Folder"))
		local mark = avatar:FindFirstChild("Presence")
		local statuses = { online = "success", away = "warning", busy = "error", offline = "neutral" }
		for _, state in { "online", "away", "busy", "offline" } do
			presence:set(state)
			label:set("Local " .. state)
			t.expect(avatar:GetAttribute("AccessibleLabel")).toBe("Ada, Local " .. state)
			t.expect(avatar:FindFirstChild("Presence")).toBe(mark)
			t.expect(mark.Visible).toBe(true)
			t.expect(mark:HasTag("facet-status-" .. statuses[state])).toBe(true)
			for other, status in statuses do
				if other ~= state then
					t.expect(mark:HasTag("facet-status-" .. status)).toBe(false)
				end
			end
			local corner = mark:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale
			local ring = mark:FindFirstChild("Ring")
			if state == "online" then
				t.expect(corner).toBe(1)
				t.expect(ring).toBe(nil)
				t.expect(mark.Size.X.Offset).toBe(mark.Size.Y.Offset)
			elseif state == "away" then
				t.expect(corner).toBe(1)
				t.expect(ring).toBe(nil)
				t.expect(mark.Size.X.Offset > mark.Size.Y.Offset).toBe(true)
				t.expect(mark:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(3)
			elseif state == "busy" then
				t.expect(corner).toBe(0)
				t.expect(ring).toBe(nil)
				t.expect(mark.Size.X.Offset).toBe(mark.Size.Y.Offset)
			else
				t.expect(corner).toBe(1)
				t.expect(ring ~= nil).toBe(true)
				t.expect(ring.BorderStrokePosition).toBe(engine.types.Enum.BorderStrokePosition.Inner)
				t.expect(mark:HasTag("facet-status-hollow")).toBe(true)
				t.expect(mark.Size.X.Offset).toBe(mark.Size.Y.Offset)
			end
		end
		presence:set(nil)
		t.expect(avatar:GetAttribute("AccessibleLabel")).toBe("Ada")
		t.expect(mark.Visible).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("draws the presence mark on the avatar with a shared inner cutout stroke in the corner", function()
		local engine, runtime, UI = setup()
		local stop, avatar = runtime.mount(function()
			return UI.Avatar({ name = "Ada", presence = "online", onActivate = function() end })
		end, engine.new("Folder"))
		local mark = avatar:FindFirstChild("Presence")
		t.expect(mark.Parent).toBe(avatar)
		local cutout = mark:FindFirstChild("Cutout")
		t.expect(cutout.ClassName).toBe("UIStroke")
		t.expect(cutout:HasTag("facet-cutout")).toBe(true)
		t.expect(cutout.BorderStrokePosition).toBe(engine.types.Enum.BorderStrokePosition.Inner)
		t.expect(cutout.ApplyStrokeMode).toBe(engine.types.Enum.ApplyStrokeMode.Border)
		t.expect(cutout.Thickness).toBe(1)
		t.expect(mark.AnchorPoint).toBe(engine.types.Vector2.new(1, 1))
		t.expect(mark.Position).toBe(engine.types.UDim2.fromScale(1, 1))
		t.expect(mark.Size).toBe(engine.types.UDim2.fromOffset(12, 12))
		stop()
		runtime:dispose()
	end)

	t.it("refuses an invalid bound rung without moving geometry and recovers through a valid rung and nil", function()
		local engine, runtime, UI = setup()
		local rung = Compose.cell("compact")
		local stop, avatar = runtime.mount(function()
			return UI.Avatar({ name = "Ada", controlSize = rung })
		end, engine.new("Folder"))
		local initials = avatar:FindFirstChild("Initials")
		t.expect(avatar.Size.X.Offset).toBe(36)
		t.expect(avatar.Size.Y.Offset).toBe(36)
		t.expect(pcall(function()
			rung:set("bad")
		end)).toBe(false)
		t.expect(avatar.Size.X.Offset).toBe(36)
		t.expect(avatar.Size.Y.Offset).toBe(36)
		t.expect(initials.TextSize).toBe(14)
		rung:set("large")
		t.expect(avatar.Size.X.Offset).toBe(56)
		t.expect(avatar.Size.Y.Offset).toBe(56)
		t.expect(initials.TextSize).toBe(22)
		rung:set(nil)
		t.expect(avatar.Size.X.Offset).toBe(44)
		t.expect(avatar.Size.Y.Offset).toBe(44)
		t.expect(initials.TextSize).toBe(18)
		stop()
		runtime:dispose()
	end)
end)

t.describe("avatar groups", function()
	t.it("caps the caller order at four, reports the hidden count and keeps faces informational", function()
		local engine, runtime, UI = setup()
		local stop, group = runtime.mount(function()
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
		t.expect(#shown).toBe(4)
		for index, face in shown do
			t.expect(face.Name).toBe("p" .. index)
			t.expect(face.LayoutOrder).toBe(index)
			t.expect(face.Selectable).toBe(false)
			t.expect(face:GetAttribute("AccessibleLabel")).toBe("Player " .. index)
		end
		t.expect(group:FindFirstChild("p5")).toBe(nil)
		local overflow = group:FindFirstChild("Overflow")
		t.expect(overflow.Text).toBe("+2")
		t.expect(overflow.LayoutOrder).toBe(5)
		t.expect(overflow:GetAttribute("AccessibleLabel")).toBe("2 more players")
		t.expect(overflow.Selectable).toBe(false)
		t.expect(group:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(-10)
		stop()
		runtime:dispose()
	end)

	t.it("refuses bad members and malformed container policies and keeps an empty group informational", function()
		local refused = {
			function(UI)
				return UI.AvatarGroup({})
			end,
			function(UI)
				return UI.AvatarGroup({ items = false })
			end,
			function(UI)
				return UI.AvatarGroup({ items = { [2] = { id = "a", name = "A" } } })
			end,
			function(UI)
				return UI.AvatarGroup({ items = { { id = "a", name = "" } } })
			end,
			function(UI)
				return UI.AvatarGroup({ items = { { id = "", name = "A" } } })
			end,
			function(UI)
				return UI.AvatarGroup({ items = { { id = "a", name = "A", presence = "unknown" } } })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, max = 0 })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, max = math.huge })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, max = 1.5 })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, layout = "grid" })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, overflow = "more" })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, form = "photo" })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, onOverflow = true })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, controlSize = "huge" })
			end,
			function(UI)
				return UI.AvatarGroup({ items = {}, over = "photo" })
			end,
		}
		for index, build in refused do
			t.expect(`{index}: {rejects(build)}`).toBe(`{index}: true`)
		end
		local engine, runtime, UI = setup()
		local stop, group = runtime.mount(function()
			return UI.AvatarGroup({ items = {} })
		end, engine.new("Folder"))
		local faces = 0
		for _, child in group:GetChildren() do
			if child:IsA("GuiButton") then
				faces += 1
			end
		end
		t.expect(faces).toBe(0)
		t.expect(group:FindFirstChild("Overflow")).toBe(nil)
		t.expect(group:HasTag("facet-avatar-stack")).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it(
		"updates current initials while a stacked group keeps presence semantic and a spread group paints it",
		function()
			for _, layout in { "stacked", "spread" } do
				local engine, runtime, UI = setup()
				local items = Compose.cell({ { id = "a", name = "Ada", presence = "online" } })
				local stop, group = runtime.mount(function()
					return UI.AvatarGroup({ items = items, layout = layout })
				end, engine.new("Folder"))
				local face = group:FindFirstChild("a")
				t.expect(face:GetAttribute("AccessibleLabel")).toBe("Ada, online")
				items:set({ { id = "a", name = "Émile Noël", presence = "offline" } })
				t.expect(group:FindFirstChild("a")).toBe(face)
				t.expect(face:FindFirstChild("Initials").Text).toBe("ÉN")
				t.expect(face:GetAttribute("AccessibleLabel")).toBe("Émile Noël, offline")
				t.expect(face.Selectable).toBe(false)
				local mark = face:FindFirstChild("Presence")
				t.expect(mark ~= nil).toBe(layout == "spread")
				t.expect(group:HasTag("facet-avatar-stack")).toBe(layout == "stacked")
				if mark then
					t.expect(mark.Visible).toBe(true)
					t.expect(mark:HasTag("facet-status-neutral")).toBe(true)
					t.expect(mark:FindFirstChild("Ring") ~= nil).toBe(true)
				end
				t.expect(group:FindFirstChildWhichIsA("UIListLayout").Padding.Offset)
					.toBe(if layout == "spread" then 8 else -10)
				stop()
				runtime:dispose()
			end
		end
	)

	t.it("localizes overflow semantics reactively for the count and ellipsis forms", function()
		for _, form in { "count", "ellipsis" } do
			local engine, runtime, UI = setup()
			local phrase, items, calls = Compose.cell("Deux autres"), Compose.cell(people(3)), 0
			local stop, group = runtime.mount(function()
				return UI.AvatarGroup({
					items = items,
					max = 1,
					overflow = form,
					overflowLabel = phrase,
					onOverflow = function()
						calls += 1
					end,
				})
			end, engine.new("Folder"))
			local overflow = group:FindFirstChild("Overflow")
			t.expect(overflow:GetAttribute("AccessibleLabel")).toBe("Deux autres")
			t.expect(overflow.Text).toBe(if form == "count" then "+2" else "…")
			t.expect(overflow.Selectable).toBe(true)
			phrase:set("Encore deux")
			t.expect(overflow:GetAttribute("AccessibleLabel")).toBe("Encore deux")
			t.expect(pcall(function()
				phrase:set(42 :: any)
			end)).toBe(false)
			phrase:set(nil)
			t.expect(overflow:GetAttribute("AccessibleLabel")).toBe("2 more players")
			items:set(people(4))
			t.expect(overflow:GetAttribute("AccessibleLabel")).toBe("3 more players")
			t.expect(overflow.Text).toBe(if form == "count" then "+3" else "…")
			overflow.Activated.fire()
			t.expect(calls).toBe(1)
			items:set(people(1))
			t.expect(group:FindFirstChild("Overflow")).toBe(nil)
			stop()
			runtime:dispose()
		end
	end)

	t.it("keeps a bound nil presence valid through source replacement and a later presence", function()
		local engine, runtime, UI = setup()
		local function roster(image: string, presence: string?)
			return {
				{ id = "a", name = "Ada", image = image, presence = presence },
				{ id = "b", name = "Bo" },
			}
		end
		local items, activations = Compose.cell(roster("rbxassetid://1", nil)), 0
		local stop, group = runtime.mount(function()
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
		t.expect(face:GetAttribute("AccessibleLabel")).toBe("Ada")
		t.expect(mark.Visible).toBe(false)
		items:set(roster("rbxassetid://1", "online"))
		t.expect(group:FindFirstChild("a")).toBe(face)
		t.expect(face:GetAttribute("AccessibleLabel")).toBe("Ada, online")
		t.expect(mark.Visible).toBe(true)
		t.expect(mark:HasTag("facet-status-success")).toBe(true)
		t.expect(pcall(function()
			items:set(roster("rbxassetid://1", "invalid"))
		end)).toBe(false)
		items:set(roster("rbxassetid://1", nil))
		t.expect(face:GetAttribute("AccessibleLabel")).toBe("Ada")
		t.expect(mark.Visible).toBe(false)
		items:set(roster("rbxassetid://2", nil))
		t.expect(group:FindFirstChild("a")).toBe(face)
		t.expect(face:FindFirstChild("Portrait"):FindFirstChild("Image").Image).toBe("rbxassetid://2")
		t.expect(face:GetAttribute("AccessibleLabel")).toBe("Ada")
		t.expect(mark.Visible).toBe(false)
		items:set(roster("rbxassetid://2", "busy"))
		t.expect(face:GetAttribute("AccessibleLabel")).toBe("Ada, busy")
		t.expect(mark.Visible).toBe(true)
		t.expect(mark:HasTag("facet-status-error")).toBe(true)
		t.expect(mark:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale).toBe(0)
		local overflow = group:FindFirstChild("Overflow")
		overflow.Activated.fire()
		t.expect(activations).toBe(1)
		t.expect(overflow.Selectable).toBe(true)
		items:set({})
		t.expect(group:FindFirstChild("a")).toBe(nil)
		t.expect(face.isDestroyed()).toBe(true)
		t.expect(group:FindFirstChild("Overflow")).toBe(nil)
		stop()
		runtime:dispose()
	end)

	t.it("keeps distinct content identities and shares one request across repeated user ids", function()
		local engine, runtime, UI = setup()
		local loaded, released = 0, 0
		local shared = Compose.createSharedResource(function()
			loaded += 1
			return { state = Compose.cell("ready"), value = Compose.cell("rbxthumb://type=AvatarHeadShot&id=1") }, function()
				released += 1
			end
		end)
		local items = Compose.cell({
			{ id = "a", name = "Ada", image = "rbxassetid://123" },
			{ id = "b", name = "Bo", image = "rbxassetid://456" },
			{ id = "c", name = "Côte", userId = 1, resource = shared },
			{ id = "d", name = "Dan", userId = 1, resource = shared },
		})
		local stop, group = runtime.mount(function()
			return UI.AvatarGroup({ items = items })
		end, engine.new("Folder"))
		local function image(id: string): any
			return group:FindFirstChild(id):FindFirstChild("Portrait"):FindFirstChild("Image")
		end
		t.expect(loaded).toBe(1)
		t.expect(image("a").Image).toBe("rbxassetid://123")
		t.expect(image("b").Image).toBe("rbxassetid://456")
		t.expect(image("a") ~= image("b")).toBe(true)
		t.expect(image("c").Image).toBe("rbxthumb://type=AvatarHeadShot&id=1")
		t.expect(image("d").Image).toBe("rbxthumb://type=AvatarHeadShot&id=1")
		t.expect(image("c") ~= image("d")).toBe(true)
		local first = group:FindFirstChild("a")
		items:set({ { id = "a", name = "Ada", image = "rbxassetid://789" } })
		t.expect(image("a").Image).toBe("rbxassetid://789")
		t.expect(released).toBe(1)
		t.expect(group:FindFirstChild("a")).toBe(first)
		t.expect(group:FindFirstChild("c")).toBe(nil)
		stop()
		runtime:dispose()
	end)

	t.it("builds the thumbnail address from a member user id", function()
		local engine, runtime, UI = setup()
		local stop, group = runtime.mount(function()
			return UI.AvatarGroup({ items = { { id = "u", name = "User", userId = 24813339 } } })
		end, engine.new("Folder"))
		t.expect(group:FindFirstChild("u"):FindFirstChild("Portrait"):FindFirstChild("Image").Image)
			.toBe("rbxthumb://type=AvatarHeadShot&id=24813339&w=150&h=150")
		stop()
		runtime:dispose()
	end)
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
	package.assets.cross = { content = "rbxassetid://33" }
	package.assets.caretHot = { content = "rbxassetid://32" }
	package.assets.caret = { content = "rbxassetid://31" }
	package.icons = entries
	return assert(themes.define(package))
end

t.describe("semantic icons", function()
	t.it("resolves declared states and falls back to default art for an undeclared state", function()
		local package = iconPackage({ close = { default = "cross", hover = "caretHot" } })
		t.expect(themes.resolveIcon(package, "close")).toBe("rbxassetid://33")
		t.expect(themes.resolveIcon(package, "close", "default")).toBe("rbxassetid://33")
		t.expect(themes.resolveIcon(package, "close", "hover")).toBe("rbxassetid://32")
		for _, state in { "pressed", "selected", "disabled" } do
			t.expect(themes.resolveIcon(package, "close", state :: any)).toBe("rbxassetid://33")
		end
		local namespaced = iconPackage({ ["demo:gauge.needle"] = { default = "caret", pressed = "caretHot" } })
		t.expect(themes.resolveIcon(namespaced, "demo:gauge.needle")).toBe("rbxassetid://31")
		t.expect(themes.resolveIcon(namespaced, "demo:gauge.needle", "pressed")).toBe("rbxassetid://32")
		t.expect(themes.resolveIcon(namespaced, "demo:gauge.needle", "hover")).toBe("rbxassetid://31")
		local engine, runtime, UI = controlsFor({ theme = package })
		local selected, enabled = Compose.cell(false), Compose.cell(true)
		local stop, button = runtime.mount(function()
			return UI.Button({ icon = "close", label = "Close", selected = selected, enabled = enabled })
		end, engine.new("Folder"))
		local icon = find(button, "LeadingIcon")
		t.expect(icon.Image).toBe("rbxassetid://33")
		button.GuiState = engine.types.Enum.GuiState.Hover
		t.expect(icon.Image).toBe("rbxassetid://32")
		button.GuiState = engine.types.Enum.GuiState.Press
		t.expect(icon.Image).toBe("rbxassetid://33")
		button.GuiState = engine.types.Enum.GuiState.Idle
		selected:set(true)
		t.expect(icon.Image).toBe("rbxassetid://33")
		enabled:set(false)
		t.expect(icon.Image).toBe("rbxassetid://33")
		t.expect(find(button, "LeadingIcon")).toBe(icon)
		stop()
		runtime:dispose()
	end)

	t.it("resolves the settings gear to the archived asset with and without a package", function()
		t.expect(themes.resolveIcon({}, "settings")).toBe("rbxassetid://78513807849201")
		t.expect(themes.resolveIcon(themes.neutralPackage(), "settings")).toBe("rbxassetid://78513807849201")
		t.expect(themes.resolveIcon(assert(themes.define(themes.neutralPackage())), "settings"))
			.toBe("rbxassetid://78513807849201")
		t.expect(icons.ART.settings.contentId).toBe("rbxassetid://78513807849201")
		t.expect(icons.ART.settings.tintRole).toBe("content")
		local engine, runtime, UI = controlsFor()
		local stop, root = runtime.mount(function()
			return UI.Picker({
				selected = Compose.cell("a"),
				style = "segmented",
				iconOnly = true,
				options = { { value = "a", label = "Alpha", icon = "settings" } },
			})
		end, engine.new("Folder"))
		t.expect(find(find(root, "a"), "LeadingIcon").Image).toBe("rbxassetid://78513807849201")
		stop()
		runtime:dispose()
	end)

	t.it("returns the theme art per state or the exact framework art when the theme declares none", function()
		local neutral = themes.neutralPackage()
		for name, entry in icons.ART do
			t.expect(`{name} -> {themes.resolveIcon(neutral, name)}`).toBe(`{name} -> {entry.contentId}`)
			t.expect(string.match(entry.contentId, "^rbxassetid://%d+$") ~= nil).toBe(true)
			t.expect(entry.tintRole).toBe("content")
		end
		t.expect(themes.resolveIcon(neutral, "facet:search")).toBe("rbxassetid://85188541706347")
		local partial = iconPackage({ close = "cross", ["chevron.trailing"] = "caret" })
		t.expect(themes.resolveIcon(partial, "close")).toBe("rbxassetid://33")
		t.expect(themes.resolveIcon(partial, "chevron.trailing")).toBe("rbxassetid://31")
		t.expect(themes.resolveIcon(partial, "chevron.down")).toBe(icons.ART["chevron.down"].contentId)
		t.expect(themes.resolveIcon(partial, "menu")).toBe(icons.ART.menu.contentId)
		t.expect(themes.resolveIcon(partial, "not.a.name")).toBe(nil)
		t.expect(themes.resolveIcon(neutral, "not.a.name")).toBe(nil)
		t.expect(themes.resolveIcon({}, "not.a.name")).toBe(nil)
		t.expect(themes.resolveIcon({}, "close")).toBe(icons.ART.close.contentId)
	end)

	t.it("keeps the Pixel Quest package art and fills missing action icons from the framework", function()
		local pixel = require("../examples/themes/pixel_quest")
		local package = assert(pixel.build(themes))
		for _, name in { "menu", "flag", "facet:search", "close" } do
			local resolved = themes.resolveIcon(package, name)
			t.expect(`{name}: {type(resolved) == "string" and string.match(resolved, "^rbxassetid://%d+$") ~= nil}`)
				.toBe(`{name}: true`)
		end
		t.expect(themes.resolveIcon(package, "close")).toBe(package.assets.pixel_icon_cross.content)
		t.expect(themes.resolveIcon(package, "close") ~= icons.ART.close.contentId).toBe(true)
		t.expect(themes.resolveIcon(package, "menu")).toBe(package.assets.menu.content)
		t.expect(themes.resolveIcon(package, "flag")).toBe(package.assets.flag.content)
		t.expect(themes.resolveIcon(package, "trash")).toBe(icons.ART.trash.contentId)
		local bare = assert(pixel.buildWithoutIcons(themes))
		t.expect(themes.resolveIcon(bare, "menu")).toBe(icons.ART.menu.contentId)
		t.expect(themes.resolveIcon(bare, "close")).toBe(icons.ART.close.contentId)
	end)

	t.it("draws the standard magnifying glass across shipped themes and lets package art override it", function()
		local standard = "rbxassetid://85188541706347"
		t.expect(icons.ART["facet:search"].contentId).toBe(standard)
		t.expect(themes.resolveIcon(themes.neutralPackage(), "facet:search")).toBe(standard)
		for _, name in { "pixel_quest", "compact_pointer", "glossy_touch" } do
			local package = assert(require("../examples/themes/" .. name).build(themes))
			t.expect(`{name}: {themes.resolveIcon(package, "facet:search")}`).toBe(`{name}: {standard}`)
		end
		local custom = iconPackage({ ["facet:search"] = "caret" })
		t.expect(themes.resolveIcon(custom, "facet:search")).toBe("rbxassetid://31")
		local engine, runtime, UI = setup({ theme = custom })
		local stop, root = runtime.mount(function()
			return UI.Label({ text = "Find", icon = "facet:search" })
		end, engine.new("Folder"))
		t.expect(root:FindFirstChildWhichIsA("ImageLabel").Image).toBe("rbxassetid://31")
		stop()
		runtime:dispose()
	end)

	t.it("sizes icons from the theme rung metric, with defaults and a filled partial declaration", function()
		local rung = Compose.cell("regular")
		local selected = Compose.cell(themes.neutralPackage())
		local engine, runtime, UI = setup({ theme = selected, controlSize = rung })
		local stop, root = runtime.mount(function()
			return UI.Label({ text = "Find", icon = "facet:search" })
		end, engine.new("Folder"))
		local icon = root:FindFirstChildWhichIsA("ImageLabel")
		for name, size in { compact = 16, regular = 20, large = 24 } do
			rung:set(name)
			t.expect(`{name}: {icon.Size.X.Offset}x{icon.Size.Y.Offset}`).toBe(`{name}: {size}x{size}`)
		end
		local partial = themes.neutralPackage()
		partial.metrics.controlSizes = { large = { iconSize = 48 } } :: any
		local package = assert(themes.define(partial))
		t.expect(package.metrics.controlSizes.large.height).toBe(56)
		t.expect(package.metrics.controlSizes.compact.iconSize).toBe(16)
		selected:set(package)
		for name, size in { compact = 16, regular = 20, large = 48 } do
			rung:set(name)
			t.expect(`{name}: {icon.Size.X.Offset}x{icon.Size.Y.Offset}`).toBe(`{name}: {size}x{size}`)
		end
		t.expect(root:FindFirstChildWhichIsA("ImageLabel")).toBe(icon)
		stop()
		runtime:dispose()
	end)

	t.it("swaps the disclosure caret between trailing and down chevron art on the same icon", function()
		local engine, runtime, UI = controlsFor()
		local expanded = Compose.cell(false)
		local stop, disclosure = runtime.mount(function()
			return UI.DisclosureGroup({
				label = "Advanced",
				expanded = expanded,
				content = function()
					return UI.Label({ text = "Body" })
				end,
			})
		end, engine.new("Folder"))
		local header = disclosure:FindFirstChild("Header")
		local caret = find(header, "LeadingIcon")
		t.expect(caret.ClassName).toBe("ImageLabel")
		t.expect(caret:HasTag("facet-icon")).toBe(true)
		t.expect(caret.Image).toBe(icons.ART["chevron.trailing"].contentId)
		t.expect(#textLabels(header) > 0).toBe(true)
		for _, label in textLabels(header) do
			t.expect(string.find(label.Text, "\u{25B8}", 1, true)).toBe(nil)
			t.expect(string.find(label.Text, "\u{25BE}", 1, true)).toBe(nil)
		end
		expanded:set(true)
		t.expect(find(header, "LeadingIcon")).toBe(caret)
		t.expect(caret.Image).toBe(icons.ART["chevron.down"].contentId)
		expanded:set(false)
		t.expect(caret.Image).toBe(icons.ART["chevron.trailing"].contentId)
		stop()
		runtime:dispose()
	end)

	t.it("resolves, sizes, tags and pixel-samples an icon element that dies with its owner", function()
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local package = Compose.cell(themes.neutralPackage())
		local ctx = context(Compose, runtime, { types = engine.types, theme = package })
		local folder = engine.new("Folder")
		local baseline = engine.census()
		local name = Compose.cell("close")
		local stop, icon = runtime.mount(function()
			return ctx.icon(name)
		end, folder)
		t.expect(icon.ClassName).toBe("ImageLabel")
		t.expect(icon.Image).toBe(icons.ART.close.contentId)
		t.expect(icon.Size).toBe(engine.types.UDim2.fromOffset(20, 20))
		t.expect(icon.BackgroundTransparency).toBe(1)
		t.expect(icon:HasTag("facet-icon")).toBe(true)
		t.expect(icon.Active).toBe(false)
		t.expect(icon.ResampleMode).toBe(engine.types.Enum.ResamplerMode.Default)
		name:set("menu")
		t.expect(icon.Image).toBe(icons.ART.menu.contentId)
		local pixel = themes.neutralPackage()
		pixel.identity.rendering = "pixel"
		package:set(pixel)
		t.expect(icon.ResampleMode).toBe(engine.types.Enum.ResamplerMode.Pixelated)
		t.expect(pcall(function()
			name:set("not.an.icon")
		end)).toBe(false)
		stop()
		t.expect(icon.isDestroyed()).toBe(true)
		t.expect(icon.Parent).toBe(nil)
		runtime:dispose()
		t.expect(engine.census().live).toBe(baseline.live)
		t.expect(engine.census().connections).toBe(baseline.connections)
	end)

	t.it("re-renders mounted icons on content and declaration changes but not on palette or map order", function()
		local function variant(configure: (any) -> ()): any
			local package = themes.neutralPackage()
			package.assets.plus = { content = "rbxassetid://901" }
			package.assets.minus = { content = "rbxassetid://902" }
			package.icons = { increment = "plus", decrement = "minus" }
			configure(package)
			return assert(themes.define(package))
		end
		local base = variant(function() end)
		local selected = Compose.cell(base)
		local engine, runtime, UI = setup({ theme = selected })
		local stop, root = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Label "Up" { text = "Up", icon = "increment" },
				UI.Label "Down" { text = "Down", icon = "decrement" },
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
		t.expect(up.Image).toBe("rbxassetid://901")
		t.expect(down.Image).toBe("rbxassetid://902")
		selected:set(variant(function(package)
			package.style.themes[1].colors.accent = { r = 0.2, g = 0.4, b = 0.9 }
		end))
		selected:set(variant(function(package)
			package.icons = { decrement = "minus", increment = "plus" }
		end))
		t.expect(writes).toBe(0)
		selected:set(variant(function(package)
			package.assets.plus.content = "rbxassetid://903"
		end))
		t.expect(up.Image).toBe("rbxassetid://903")
		t.expect(writes).toBe(1)
		selected:set(variant(function(package)
			package.icons = { increment = { default = "plus", hover = "minus" }, decrement = "minus" }
		end))
		t.expect(up.Image).toBe("rbxassetid://901")
		selected:set(variant(function(package)
			package.icons = { increment = "plus" }
		end))
		t.expect(down.Image).toBe(icons.ART.decrement.contentId)
		selected:set(base)
		t.expect(down.Image).toBe("rbxassetid://902")
		t.expect(root:FindFirstChild("Up"):FindFirstChildWhichIsA("ImageLabel")).toBe(up)
		t.expect(root:FindFirstChild("Down"):FindFirstChildWhichIsA("ImageLabel")).toBe(down)
		stop()
		runtime:dispose()
	end)
end)

local SKIN_STATES = { "default", "hover", "pressed", "selected", "disabled" }

local function skinImages(package: any, slots: { string }?): (number, number, { string })
	local engine = engineLib.new()
	local runtime = Roblox.createRuntime(engine)
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
		local state = Compose.cell("default")
		local stop, root = runtime.mount(function()
			return themes.skin(runtime, package, slot, { types = engine.types, state = state })
		end, engine.new("Folder"))
		for _, name in SKIN_STATES do
			state:set(name)
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

t.describe("pixel rendering", function()
	t.it("stamps Pixelated on every Pixel Quest skin layer in every state", function()
		local package = assert(require("../examples/themes/pixel_quest").build(themes))
		t.expect(package.identity.rendering).toBe("pixel")
		local pixelated, other, offenders = skinImages(package)
		t.expect(pixelated >= 40).toBe(true)
		t.expect(table.concat(offenders, ", ")).toBe("")
		t.expect(other).toBe(0)
	end)

	t.it(
		"stamps every layer of a pixel stack, state-swapped art and icons, and a standard package stamps none",
		function()
			local function stack(rendering: string?): any
				local package = themes.neutralPackage()
				package.identity.rendering = rendering :: any
				package.assets.art = { content = "rbxassetid://10" }
				package.assets.hot = { content = "rbxassetid://11", sliceCenter = { x0 = 2, y0 = 2, x1 = 6, y1 = 6 } }
				package.icons = { close = { default = "art", pressed = "hot" } }
				package.chrome.control = {
					kind = "layered",
					layers = {
						{ kind = "fill", asset = { default = "art", pressed = "hot" } },
						{ kind = "tile", asset = "art", tileSize = { w = 8, h = 8 } },
						{ kind = "edges", asset = "art", thickness = 4 },
						{ kind = "corners", asset = "art", size = 8 },
						{ kind = "plaque", asset = { default = "art", hover = "hot" }, size = { w = 40, h = 12 } },
					},
				}
				return assert(themes.define(package))
			end
			for _, rendering in { "pixel", false } do
				local package = stack(if rendering then rendering else nil)
				local pixelated, other = skinImages(package, { "control" })
				local layers = 1 + 1 + 4 + 4 + 1
				if rendering then
					t.expect(pixelated).toBe(layers * #SKIN_STATES)
					t.expect(other).toBe(0)
				else
					t.expect(pixelated).toBe(0)
					t.expect(other).toBe(layers * #SKIN_STATES)
				end
				local engine = engineLib.new()
				local runtime = Roblox.createRuntime(engine)
				local ctx = context(Compose, runtime, { types = engine.types, theme = package })
				local state = Compose.cell("default")
				local stop, icon = runtime.mount(function()
					return ctx.icon("close", nil, state)
				end, engine.new("Folder"))
				local expected = if rendering
					then engine.types.Enum.ResamplerMode.Pixelated
					else engine.types.Enum.ResamplerMode.Default
				t.expect(icon.Image).toBe("rbxassetid://10")
				t.expect(icon.ResampleMode).toBe(expected)
				state:set("pressed")
				t.expect(icon.Image).toBe("rbxassetid://11")
				t.expect(icon.ResampleMode).toBe(expected)
				stop()
				runtime:dispose()
			end
		end
	)

	t.it("keeps shipped standard packages on Default resampling across every skin state", function()
		for _, name in { "fantasy_ornate", "fantasy_parchment", "glossy_touch", "compact_pointer" } do
			local package = assert(require("../examples/themes/" .. name).build(themes))
			local pixelated, other = skinImages(package)
			t.expect(`{name}: {pixelated} pixelated, some art {other > 0}`).toBe(`{name}: 0 pixelated, some art true`)
		end
	end)
end)

t.describe("reference package art", function()
	t.it("resolves Fantasy Ornate's six mapped icons and one namespaced icon to its own art", function()
		local package = assert(require("../examples/themes/fantasy_ornate").build(themes))
		local own = {
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
			t.expect(`{name}: {resolved}`).toBe(`{name}: {package.assets[asset].content}`)
			t.expect(string.match(resolved :: string, "^rbxassetid://%d+$") ~= nil).toBe(true)
			if icons.ART[name] then
				t.expect(resolved ~= icons.ART[name].contentId).toBe(true)
			end
		end
		t.expect(count).toBe(7)
		for name in package.icons do
			t.expect(own[name] ~= nil).toBe(true)
		end
		for _, name in { "menu", "more" } do
			t.expect(themes.resolveIcon(package, name)).toBe(icons.ART[name].contentId)
			for _, asset in package.assets do
				t.expect(asset.content == icons.ART[name].contentId).toBe(false)
			end
		end
	end)

	t.it("gives the platform pair one authored icon each and the framework art for the rest", function()
		for _, name in { "glossy_touch", "compact_pointer" } do
			local package = assert(require("../examples/themes/" .. name).build(themes))
			local count = 0
			for icon in package.icons do
				t.expect(icon).toBe("facet:search")
				count += 1
			end
			t.expect(count).toBe(1)
			t.expect(themes.resolveIcon(package, "facet:search")).toBe(package.assets.search.content)
			for _, icon in { "increment", "decrement", "chevron.trailing" } do
				t.expect(`{name} {icon}: {themes.resolveIcon(package, icon)}`)
					.toBe(`{name} {icon}: {icons.ART[icon].contentId}`)
			end
		end
	end)

	t.it("authors Fantasy Ornate art as content and resolves both spellings to the same image content", function()
		local source = fs.readFile("examples/themes/fantasy_ornate.luau")
		t.expect(string.find(source, 'content = "rbxassetid://', 1, true) ~= nil).toBe(true)
		t.expect(string.find(source, "contentId", 1, true)).toBe(nil)
		local package = assert(require("../examples/themes/fantasy_ornate").build(themes))
		local assets = 0
		for name, asset in package.assets do
			assets += 1
			t.expect(`{name}: {type(asset.content)}`).toBe(`{name}: string`)
			t.expect(`{name}: {asset.contentId}`).toBe(`{name}: nil`)
		end
		t.expect(assets > 10).toBe(true)
		t.expect(themes.resolveIcon(package, "close")).toBe(package.assets.ornate_icon_cross.content)
		local alias = require("../examples/themes/content_alias_test")
		local viaContent, viaContentId = assert(alias.build(themes)), assert(alias.buildAlias(themes))
		t.expect(themes.resolveIcon(viaContent, "increment")).toBe("rbxassetid://137937473154830")
		t.expect(themes.resolveIcon(viaContentId, "increment")).toBe("rbxassetid://137937473154830")
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local images = {}
		for _, package in { viaContent, viaContentId } do
			local stop, root = runtime.mount(function()
				return themes.skin(runtime, package, "control", { types = engine.types })
			end, engine.new("Folder"))
			local image = root:FindFirstChild("control1")
			table.insert(images, {
				image = image.Image,
				scale = image.ScaleType,
				center = image.SliceCenter,
			})
			stop()
		end
		t.expect(images[1].image).toBe("rbxassetid://70509734376718")
		t.expect(images[2].image).toBe(images[1].image)
		t.expect(images[2].scale).toBe(images[1].scale)
		t.expect(images[2].center).toBe(images[1].center)
		t.expect(images[1].center).toBe(engine.types.Rect.new(16, 16, 20, 20))
		runtime:dispose()
	end)
end)

t.describe("icon layout", function()
	t.it("places a Label icon leading or trailing beside its title with the themed art size and gap", function()
		local package = Compose.cell(themes.neutralPackage())
		local gap = Compose.cell(12)
		local engine, runtime, UI = setup({ theme = package })
		local stop, root = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.Label "Leading" { text = "Save", icon = "checkmark" },
				UI.Label "Trailing" { text = "Next", icon = "chevron.trailing", iconPosition = "trailing", gap = gap },
			})
		end, engine.new("Folder"))
		for name, expected in { Leading = { "icon", "text" }, Trailing = { "text", "icon" } } do
			local row = root:FindFirstChild(name)
			local icon, title = row:FindFirstChildWhichIsA("ImageLabel"), row:FindFirstChildWhichIsA("TextLabel")
			local layout = row:FindFirstChildWhichIsA("UIListLayout")
			t.expect(row.ClassName).toBe("Frame")
			t.expect(layout.FillDirection).toBe(engine.types.Enum.FillDirection.Horizontal)
			t.expect(layout.SortOrder).toBe(engine.types.Enum.SortOrder.LayoutOrder)
			t.expect(icon.Parent).toBe(row)
			t.expect(title.Parent).toBe(row)
			t.expect(icon:HasTag("facet-icon")).toBe(true)
			t.expect(icon.Size).toBe(engine.types.UDim2.fromOffset(20, 20))
			local order = if icon.LayoutOrder < title.LayoutOrder then { "icon", "text" } else { "text", "icon" }
			t.expect(`{name}: {order[1]} then {order[2]}`).toBe(`{name}: {expected[1]} then {expected[2]}`)
		end
		local leading = root:FindFirstChild("Leading")
		local trailing = root:FindFirstChild("Trailing")
		t.expect(leading:FindFirstChildWhichIsA("TextLabel").Text).toBe("Save")
		t.expect(leading:FindFirstChildWhichIsA("ImageLabel").Image).toBe(icons.ART.checkmark.contentId)
		t.expect(leading:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(8)
		local trailingLayout = trailing:FindFirstChildWhichIsA("UIListLayout")
		t.expect(trailingLayout.Padding.Offset).toBe(12)
		gap:set(4)
		t.expect(trailingLayout.Padding.Offset).toBe(4)
		local next = themes.neutralPackage()
		next.metrics.controlSizes.regular.iconSize = 32
		package:set(next)
		t.expect(leading:FindFirstChildWhichIsA("ImageLabel").Size).toBe(engine.types.UDim2.fromOffset(32, 32))
		t.expect(trailing:FindFirstChildWhichIsA("ImageLabel").Size).toBe(engine.types.UDim2.fromOffset(32, 32))
		stop()
		runtime:dispose()
	end)

	t.it("keeps a preferred hint glyph square at the theme icon size across a live theme swap", function()
		local package = Compose.cell(themes.neutralPackage())
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
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
		local stop, root = runtime.mount(function()
			return runtime.constructors.Frame({
				UI.ShortcutHint "Art" { action = action },
				UI.ShortcutHint "Keys" { keys = { { "Ctrl", "S" } } },
			})
		end, engine.new("Folder"))
		local art = find(root:FindFirstChild("Art"), "Glyph")
		local keys = root:FindFirstChild("Keys")
		t.expect(art.Image).toBe("rbxassetid://123")
		t.expect(art.Size).toBe(engine.types.UDim2.fromOffset(20, 20))
		t.expect(keys.Size.Y.Offset).toBe(28)
		for _, size in { 28, 16, 20 } do
			local next = themes.neutralPackage()
			next.metrics.controlSizes.regular.iconSize = size
			package:set(next)
			t.expect(find(root:FindFirstChild("Art"), "Glyph")).toBe(art)
			t.expect(art.Size).toBe(engine.types.UDim2.fromOffset(size, size))
			t.expect(keys.Size.Y.Offset).toBe(size + 8)
		end
		stop()
		runtime:dispose()
	end)
end)

t.describe("sliced and bar art", function()
	t.it("compiles slice art with or without declared source sizes and paints the exact slice values", function()
		local sized = themes.neutralPackage()
		sized.assets.plate = {
			content = "rbxassetid://51",
			sliceCenter = { x0 = 8, y0 = 6, x1 = 24, y1 = 26 },
			sliceScale = 2,
			width = 32,
			height = 32,
		} :: any
		sized.chrome.control = { kind = "nineSlice", asset = "plate" }
		local package, report = themes.define(sized)
		t.expect(report.ok).toBe(true)
		local compiled = assert(package).assets.plate :: any
		t.expect(compiled.width).toBe(32)
		t.expect(compiled.height).toBe(32)
		t.expect(compiled.sliceCenter.x0).toBe(8)
		t.expect(compiled.sliceCenter.y1).toBe(26)
		local bare = themes.neutralPackage()
		bare.assets.plate = { content = "rbxassetid://52", sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 } }
		bare.chrome.control = { kind = "nineSlice", asset = "plate" }
		local sizeless, sizelessReport = themes.define(bare)
		t.expect(sizelessReport.ok).toBe(true)
		t.expect((assert(sizeless).assets.plate :: any).width).toBe(nil)
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		for _, case in
			{
				{ package = assert(package), image = "rbxassetid://51", rect = { 8, 6, 24, 26 }, scale = 2 },
				{ package = assert(sizeless), image = "rbxassetid://52", rect = { 8, 8, 24, 24 }, scale = 1 },
			}
		do
			local stop, root = runtime.mount(function()
				return themes.skin(runtime, case.package, "control", { types = engine.types })
			end, engine.new("Folder"))
			local image = root:FindFirstChild("control1")
			t.expect(image.Image).toBe(case.image)
			t.expect(image.ScaleType).toBe(engine.types.Enum.ScaleType.Slice)
			t.expect(image.SliceCenter).toBe(engine.types.Rect.new(table.unpack(case.rect)))
			t.expect(image.SliceScale).toBe(case.scale)
			t.expect(image.Size).toBe(engine.types.UDim2.fromScale(1, 1))
			stop()
		end
		runtime:dispose()
	end)

	t.it("paints a nine-slice skin with the package's own image values and no sheet tint", function()
		local package = assert(require("../examples/themes/fantasy_parchment").build(themes))
		local asset = package.assets.parchment_panel
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local target, root, sheet
		local stop = runtime.mount(function()
			target = runtime.constructors.Frame({})
			root = themes.skin(runtime, package, "panel", { types = engine.types, target = target })
			sheet = themes.createStyleSheet(runtime, package, { types = engine.types })
			return runtime.constructors.Frame({ target, root, sheet })
		end, engine.new("Folder"))
		local image = root:FindFirstChild("panel1", true)
		t.expect(image.Image).toBe(asset.contentId)
		t.expect(image.Image).toBe("rbxassetid://78012779616687")
		t.expect(image.ScaleType).toBe(engine.types.Enum.ScaleType.Slice)
		t.expect(image.SliceCenter).toBe(engine.types.Rect.new(40, 40, 104, 104))
		t.expect(image.SliceScale).toBe(asset.sliceScale)
		t.expect(image.ImageColor3).toBe(engine.types.Color3.new(1, 1, 1))
		t.expect(image.ImageTransparency).toBe(0)
		t.expect(image.BackgroundTransparency).toBe(1)
		t.expect(#image:GetTags()).toBe(0)
		t.expect(target:HasTag("facet-skinned")).toBe(true)
		local skinned = false
		for _, rule in sheet:GetChildren() do
			local properties = rule:GetProperties()
			t.expect(
				`{rule.Selector}: {properties.ImageColor3 ~= nil and string.find(rule.Selector, "skin", 1, true) ~= nil}`
			)
				.toBe(`{rule.Selector}: false`)
			if rule.Selector == ".facet-skinned" then
				skinned = true
				t.expect(properties.BackgroundTransparency).toBe(1)
			end
		end
		t.expect(skinned).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("centres end caps on the track edge, centres the centrepiece and defaults the fill to ltr", function()
		local package = themes.neutralPackage()
		package.assets = {
			fill = { content = "rbxassetid://1" },
			start = { content = "rbxassetid://2" },
			finish = { content = "rbxassetid://3" },
			center = { content = "rbxassetid://4" },
			shared = { content = "rbxassetid://5" },
		}
		package.chrome.barFill = { kind = "nineSlice", asset = "fill" }
		package.chrome.barCap =
			{ kind = "nineSlice", startAsset = "start", endAsset = "finish", size = { w = 28, h = 36 } }
		package.chrome.barCenter = { kind = "nineSlice", asset = "center", size = { w = 36, h = 28 } }
		local selected = Compose.cell(package)
		local engine = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local UI = media(context(Compose, runtime, { types = engine.types, theme = selected }))
		local stop, root = runtime.mount(function()
			return UI.ProgressView({ value = 0.01 })
		end, engine.new("Folder"))
		local fill = root:FindFirstChild("Fill1", true)
		t.expect(fill.AnchorPoint).toBe(engine.types.Vector2.new(0, 0))
		t.expect(fill.Position).toBe(engine.types.UDim2.fromScale(0, 0))
		local skin = fill:FindFirstChild("Skin", true)
		t.expect(skin.AnchorPoint).toBe(engine.types.Vector2.new(0, 0))
		t.expect(skin.Size.X.Scale).toBe(100)
		t.expect(skin.Size.Y.Scale).toBe(1)
		local start, finish = root:FindFirstChild("barCap-start", true), root:FindFirstChild("barCap-end", true)
		for _, cap in { start, finish } do
			t.expect(cap.AnchorPoint).toBe(engine.types.Vector2.new(0.5, 0.5))
			t.expect(cap.Position.Y.Scale).toBe(0.5)
			t.expect(cap.Size).toBe(engine.types.UDim2.fromOffset(28, 36))
		end
		t.expect(start.Position.X.Scale).toBe(0)
		t.expect(finish.Position.X.Scale).toBe(1)
		t.expect(start.Image).toBe("rbxassetid://2")
		t.expect(finish.Image).toBe("rbxassetid://3")
		local center = root:FindFirstChild("barCenter", true)
		t.expect(center.AnchorPoint).toBe(engine.types.Vector2.new(0.5, 0.5))
		t.expect(center.Position).toBe(engine.types.UDim2.fromScale(0.5, 0.5))
		t.expect(center.Size).toBe(engine.types.UDim2.fromOffset(36, 28))
		for _, direction in { "ttb", "btt", "rtl" } do
			local next = table.clone(package)
			next.chrome = table.clone(package.chrome)
			next.chrome.barFill = { kind = "nineSlice", asset = "fill", direction = direction }
			selected:set(next)
			t.expect(center.Position).toBe(engine.types.UDim2.fromScale(0.5, 0.5))
			for _, cap in { start, finish } do
				t.expect(cap.AnchorPoint).toBe(engine.types.Vector2.new(0.5, 0.5))
			end
			if direction == "rtl" then
				t.expect(start.Position).toBe(engine.types.UDim2.fromScale(1, 0.5))
				t.expect(finish.Position).toBe(engine.types.UDim2.fromScale(0, 0.5))
			else
				t.expect(start.Position.X.Scale).toBe(0.5)
				t.expect(finish.Position.X.Scale).toBe(0.5)
				t.expect(start.Position.Y.Scale).toBe(if direction == "btt" then 1 else 0)
				t.expect(finish.Position.Y.Scale).toBe(if direction == "btt" then 0 else 1)
			end
		end
		local sharedCap = table.clone(package)
		sharedCap.chrome = table.clone(package.chrome)
		sharedCap.chrome.barCap = { kind = "nineSlice", asset = "shared", size = { w = 28, h = 36 } }
		selected:set(sharedCap)
		t.expect(start.Image).toBe("rbxassetid://5")
		t.expect(finish.Image).toBe("rbxassetid://5")
		stop()
		runtime:dispose()
	end)

	t.it("clips the fill window, hangs caps on the track and tears the whole bar assembly down", function()
		local package = themes.neutralPackage()
		package.assets = {
			track = { content = "rbxassetid://1" },
			fill = { content = "rbxassetid://2" },
			cap = { content = "rbxassetid://3" },
			center = { content = "rbxassetid://4" },
		}
		package.chrome.barTrack = { kind = "nineSlice", asset = "track" }
		package.chrome.barFill = { kind = "nineSlice", asset = "fill" }
		package.chrome.barCap = { kind = "nineSlice", asset = "cap", size = { w = 12, h = 12 } }
		package.chrome.barCenter = { kind = "nineSlice", asset = "center", size = { w = 16, h = 16 } }
		local engine = engineLib.new()
		local folder = engine.new("Folder")
		local baseline = engine.census()
		local runtime = Roblox.createRuntime(engine)
		local UI = media(context(Compose, runtime, { types = engine.types, theme = package }))
		local value = Compose.cell(0.4)
		local stop, root = runtime.mount(function()
			return UI.ProgressView({ value = value })
		end, folder)
		local track = root:FindFirstChild("Track", true)
		local clip = track:FindFirstChild("FillClip")
		t.expect(clip.ClipsDescendants).toBe(true)
		t.expect(clip.Size).toBe(engine.types.UDim2.fromScale(1, 1))
		t.expect(clip.BackgroundTransparency).toBe(1)
		t.expect(track.ClipsDescendants).toBe(false)
		local fill = clip:FindFirstChild("Fill1")
		t.expect(fill.Parent).toBe(clip)
		t.expect(fill.ClipsDescendants).toBe(true)
		t.expect(fill:FindFirstChild("barFill1", true).Image).toBe("rbxassetid://2")
		t.expect(track:FindFirstChild("barTrack1", true).Image).toBe("rbxassetid://1")
		for _, name in { "barCap-start", "barCap-end", "barCenter" } do
			local ornament = track:FindFirstChild(name, true)
			t.expect(ornament ~= nil).toBe(true)
			t.expect(ornament:IsDescendantOf(clip)).toBe(false)
			t.expect(ornament:IsDescendantOf(track)).toBe(true)
			local branch = ornament
			while branch.Parent ~= track do
				branch = branch.Parent
			end
			t.expect(branch ~= clip).toBe(true)
			t.expect(branch.ClipsDescendants).toBe(false)
		end
		local assembly = { track, clip, fill }
		for _, node in track:GetDescendants() do
			table.insert(assembly, node)
		end
		t.expect(#assembly > 8).toBe(true)
		value:set(0.9)
		t.expect(track:FindFirstChild("FillClip")).toBe(clip)
		stop()
		for _, node in assembly do
			t.expect(`{node.Name}: {node.isDestroyed()}`).toBe(`{node.Name}: true`)
		end
		runtime:dispose()
		t.expect(engine.census().live).toBe(baseline.live)
		t.expect(engine.census().connections).toBe(baseline.connections)
	end)
end)
