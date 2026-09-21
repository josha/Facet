--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src")
local Compose = Facet.Compose
local avatar = require("../src/controls/avatar")
local skeleton = require("../src/controls/skeleton")
local FACE = "rbxassetid://75342910516929"
local function node(w, path)
	return assert(w.adapter.node(path), path)
end
local function mountedLabel(w, path)
	local actual = assert(require("../src/paths").nodeAt(w.handle.root.node, path))
	t.expect(node(w, path).props.label).toBe("") -- custom child content paints; raw node label is semantic only
	return actual.props.label
end
local function presencePart(w, base, name)
	for path, value in w.adapter.liveNodes() do
		if
			string.sub(path, 1, #base + #"/Layers/Presence/") == base .. "/Layers/Presence/"
			and string.sub(path, -#name - 1) == "/" .. name
			and w.adapter.visibleOf(path)
		then
			return value
		end
	end
	return nil
end

local function mount(w, spec)
	local record
	spec = table.clone(spec)
	spec.ref = function(value)
		record = value
	end
	w.present(function()
		return w.UI.Screen("S")({ w.UI.Avatar("Face")(spec) })
	end)
	return record
end
local function finish(provider, ready)
	for _, request in provider.pendingRequests() do
		if ready then
			provider.complete(request.key, request.generation, FACE)
		else
			provider.fail(request.key, request.generation, "missing")
		end
	end
end
t.afterEach(function()
	t.expect(skeleton.liveDrivers()).toBe(0)
end)
t.describe("Avatar", function()
	t.it("cuts UTF-8 first and last initials in authored case", function()
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
			t.expect(avatar.initialsOf(pair[1])).toBe(pair[2])
		end
	end)
	t.it("paints initials and passive semantic facts without a focus stop", function()
		local w = world.new()
		local record = mount(w, { name = "Ada Quill" })
		t.expect(node(w, "/S/Face/Initials").props.text).toBe("AQ")
		t.expect(node(w, "/S/Face").rect.w).toBe(44)
		t.expect(node(w, "/S/Face").rect.h).toBe(44)
		t.expect(node(w, "/S/Face/Plate").props.surface).toBeNil()
		t.expect(record.dump().label).toBe("Ada Quill")
		t.expect(#w.handle.focusOrder().traversal).toBe(0)
	end)
	t.it("keeps pending ready failed and unsourced faces at the same diameter", function()
		for _, ready in { true, false } do
			local w = world.new()
			local provider = w.app.newResourceProvider({ bind = false })
			local record = mount(w, { name = "Ada Quill", userId = 24813339, provider = provider })
			t.expect(provider.pendingRequests()[1].key).toBe("rbxthumb://type=AvatarHeadShot&id=24813339&w=150&h=150")
			t.expect(node(w, "/S/Face/Pending/then/Placeholder").rect.w).toBe(44)
			t.expect(skeleton.liveDrivers()).toBe(1)
			finish(provider, ready)
			w.pres.refresh()
			t.expect(node(w, "/S/Face").rect.h).toBe(44)
			t.expect(record.dump().state).toBe(if ready then "ready" else "failed")
			if ready then
				t.expect(node(w, "/S/Face/Picture/then/Picture").props.image).toBe(FACE)
			else
				t.expect(node(w, "/S/Face/Initials/then/Initials").props.text).toBe("AQ")
			end
			t.expect(skeleton.liveDrivers()).toBe(0)
			t.expect(w.pres.motionClock:activeCount()).toBe(0)
			w.close()
			t.expect(provider.counters().handles).toBe(0)
		end
	end)
	t.it("releases each pending branch while one Avatar survives repeated provider state changes", function()
		local w = world.new()
		local state, value = Compose.cell("pending"), Compose.cell(FACE)
		local held = 0
		local provider = {
			acquire = function(owner, _key)
				held += 1
				owner.own(function()
					held -= 1
				end)
				return { state = state, value = value }
			end,
		}
		mount(w, { name = "Ada", key = "same", provider = provider })
		local created = w.controller.stats().creates
		for _ = 1, 8 do
			state:set("ready")
			w.pres.refresh()
			t.expect(skeleton.liveDrivers()).toBe(0)
			t.expect(w.pres.motionClock:activeCount()).toBe(0)
			state:set("pending")
			w.pres.refresh()
			t.expect(skeleton.liveDrivers()).toBe(1)
			t.expect(held).toBe(1)
		end
		t.expect(w.controller.stats().creates > created).toBe(true) -- real branch remounts, one retained lease
		state:set("ready")
		w.pres.refresh()
		w.close()
		t.expect(held).toBe(0)
		t.expect(state:peek()).toBe("ready")
	end)
	t.it("releases only its lease and rejects stale transport completion after removal", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		mount(w, { name = "Ada", key = "portrait", provider = provider })
		local request = provider.pendingRequests()[1]
		w.close()
		t.expect(provider.counters().handles).toBe(0)
		t.expect(provider.complete(request.key, request.generation, FACE)).toBe("stale")
		mount(w, { name = "Bo", key = "next", provider = provider })
		t.expect(provider.pendingRequests()[1].key).toBe("next")
	end)
	t.it("shares one provider request between same-key faces and frees every handle", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.Avatar("A")({ name = "A", key = "same", provider = provider }),
				UI.Avatar("B")({ name = "B", key = "same", provider = provider }),
			})
		end)
		t.expect(provider.counters().handles).toBe(2)
		t.expect(#provider.pendingRequests()).toBe(1)
		t.expect(w.pres.motionClock:activeCount()).toBe(1)
		finish(provider, true)
		w.pres.refresh()
		t.expect(skeleton.liveDrivers()).toBe(0)
		w.close()
		t.expect(provider.counters().handles).toBe(0)
	end)
	t.it("keeps every image layer over the same face in both forms and all rungs", function()
		for _, interactive in { false, true } do
			for _, form in { "standard", "icon" } do
				for _, rung in { "compact", "regular", "large" } do
					local w = world.new()
					mount(w, {
						name = "Ada",
						image = FACE,
						form = form,
						controlSize = rung,
						onActivate = if interactive then function() end else nil,
					})
					local path = if interactive then "/S/Face+target/Face" else "/S/Face"
					local face = node(w, path).rect
					local base = path .. (if interactive then "/Layers" else "")
					for _, part in { "Plate", "Picture" } do
						t.expect(node(w, base .. "/" .. part).rect).toEqual(face)
					end
					if form == "standard" then
						t.expect(node(w, base .. "/Rim").rect).toEqual(face)
					else
						t.expect(w.adapter.node(base .. "/Rim")).toBeNil()
					end
					w.close()
				end
			end
		end
	end)
	t.it("publishes four presence shapes and the same localized mounted Button label", function()
		local w = world.new()
		local presence = Compose.cell("online")
		local label = Compose.cell("Available")
		local record =
			mount(w, { name = "Ada", presence = presence, presenceLabel = label, onActivate = function() end })
		local base = "/S/Face+target/Face"
		local roles = { online = "success", away = "warning", busy = "danger", offline = "contentSecondary" }
		for _, state in { "online", "away", "busy", "offline" } do
			presence:set(state)
			label:set("Local " .. state)
			w.pres.refresh()
			t.expect(mountedLabel(w, base)).toBe("Ada, Local " .. state)
			t.expect(record.dump().label).toBe(mountedLabel(w, base))
			local mark, detail = presencePart(w, base, "Mark"), presencePart(w, base, "Detail")
			t.expect(mark.props.tint.role).toBe(roles[state])
			t.expect(detail.props.tint.transparency).toBe(if state == "away" or state == "offline" then 0 else 1)
			if state == "away" then
				t.expect(detail.rect.w > detail.rect.h).toBe(true)
			elseif state == "offline" then
				t.expect(detail.rect.w).toBe(detail.rect.h)
			end
		end
	end)
	t.it("uses a shared status cutout inside the reserved presence corner", function()
		local w = world.new()
		mount(w, { name = "Ada", presence = "online", onActivate = function() end })
		local base = "/S/Face+target/Face"
		local cutout, mark = presencePart(w, base, "Cutout"), presencePart(w, base, "Mark")
		t.expect(cutout.props.tint.role).toBe("surface")
		t.expect(cutout.props.surface).toBeNil()
		t.expect(cutout.rect.w).toBe(13)
		t.expect(mark.rect.w).toBe(cutout.rect.w - 2)
		t.expect(mark.rect.x).toBe(cutout.rect.x + 1)
	end)
	t.it("quarantines invalid presence coherently and recovers through valid and nil", function()
		local w = world.new()
		local presence = Compose.cell("online")
		local record = mount(w, {
			name = "Ada",
			presence = function(use)
				return use(presence)
			end,
			onActivate = function() end,
		})
		local base = "/S/Face+target/Face"
		presence:set("illegal")
		w.pres.refresh()
		t.expect(mountedLabel(w, base)).toBe("Ada, online")
		t.expect(record.dump().presence).toBe("online")
		t.expect(record.dump().label).toBe("Ada, online")
		t.expect(presencePart(w, base, "Mark").props.tint.role).toBe("success")
		presence:set("busy")
		w.pres.refresh()
		t.expect(record.dump().label).toBe("Ada, busy")
		presence:set(nil)
		w.pres.refresh()
		t.expect(record.dump().presence).toBeNil()
		t.expect(record.dump().presenceMark).toBe(false)
		t.expect(mountedLabel(w, base)).toBe("Ada")
		t.expect(presencePart(w, base, "Mark")).toBeNil() -- nil presence owns no shared mark
		t.expect(presence:peek()).toBeNil()
	end)
	t.it("recovers the mounted presence branch and circle classification after a refused value", function()
		local w = world.new()
		local presence = Compose.cell("offline")
		local provider = w.app.newResourceProvider({ bind = false, maxConcurrent = 2 })
		local record = mount(w, {
			name = "Ada",
			key = "demo://native-avatar",
			provider = provider,
			presence = presence,
			presenceLabel = function(use)
				local state = use(presence)
				return if state then "Currently " .. state else nil
			end,
			controlSize = Compose.cell("regular"),
			onActivate = function() end,
		})
		local base = "/S/Face+target/Face"
		local sheet = require("../src/tokens/sheet_model")
		local function check(state, shape, role)
			local mark = presencePart(w, base, "Mark")
			local tags = sheet.classifyTags({ shape = mark.props.shape })
			t.expect(record.dump().presence).toBe(state)
			t.expect(mountedLabel(w, base)).toBe("Ada, Currently " .. state)
			t.expect(mark.props.shape).toBe(shape)
			t.expect(mark.props.tint.role).toBe(role)
			t.expect(tags[sheet.TAGS.shapePrefix .. "circle"] == true).toBe(shape == "circle")
		end
		check("offline", "circle", "contentSecondary")
		presence:set("invalidPresence")
		w.pres.refresh()
		check("offline", "circle", "contentSecondary")
		presence:set("busy")
		w.pres.refresh()
		check("busy", "rect", "danger")
		presence:set("offline")
		w.pres.refresh()
		check("offline", "circle", "contentSecondary")
		t.expect(presencePart(w, base, "Detail").props.shape).toBe("circle")
	end)
	t.it("suppresses marks without deleting their semantic state", function()
		local w = world.new()
		local record = mount(w, { name = "Ada", presence = "away", presenceMark = false, onActivate = function() end })
		t.expect(w.adapter.node("/S/Face+target/Face/Layers/Presence")).toBeNil()
		t.expect(mountedLabel(w, "/S/Face+target/Face")).toBe("Ada, away")
		t.expect(record.dump().presence).toBe("away")
	end)
	t.it("validates every bound rung before publishing either axis", function()
		local w = world.new()
		local rung = Compose.cell("compact")
		local size
		w.present(function()
			size = Compose.formula(function(use)
				return use(rung)
			end)
			return w.UI.Screen("S")({ w.UI.Avatar("Face")({ name = "Ada", controlSize = size }) })
		end)
		t.expect(node(w, "/S/Face").rect.h).toBe(36)
		rung:set("bad")
		w.pres.refresh()
		t.expect(node(w, "/S/Face").rect.h).toBe(36)
		rung:set("large")
		w.pres.refresh()
		t.expect(node(w, "/S/Face").rect.h).toBe(56)
		rung:set(nil)
		w.pres.refresh()
		t.expect(node(w, "/S/Face").rect.h).toBe(44)
	end)
	t.it("refuses invalid sources forms and presence before acquiring a lease", function()
		local w = world.new()
		local provider = w.app.newResourceProvider({ bind = false })
		for _, spec in
			{
				{},
				{ name = "" },
				{ name = "A", userId = 1 },
				{ name = "A", key = "" },
				{ name = "A", image = FACE, userId = 1, provider = provider },
				{ name = "A", form = "icon", presence = "online" },
				{ name = "A", presence = "wrong" },
				{ name = "A", diameter = 36, controlSize = "compact" },
				{ name = "A", presenceLabel = "Away" },
				{ name = "A", unexpected = true },
			}
		do
			t.expect(pcall(function()
				w.scoped(function()
					w.UI.Avatar(spec)
				end)
			end)).toBe(false)
		end
		t.expect(provider.counters().handles).toBe(0)
		t.expect(skeleton.liveDrivers()).toBe(0)
	end)
end)

t.describe("Avatar circle paint", function()
	t.it("keeps authored frame input separate and applies the ordinary activated Button restriction", function()
		local w = world.new()
		local tapped, record = 0, nil
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.Avatar("Face")({
					name = "Ada",
					frame = w.UI.Button("Frame")({
						label = "Badge",
						onActivate = function()
							tapped += 1
						end,
					}),
					ref = function(value)
						record = value
					end,
				}),
			})
		end)
		t.expect(record.dump().interactive).toBe(false)
		t.expect(#w.handle.focusOrder().traversal).toBe(1)
		w.adapter.tap("/S/Face/Frame")
		t.expect(tapped).toBe(1)
		w.close()
		t.expect(pcall(function()
			w.scoped(function()
				w.UI.Avatar({ name = "Ada", onActivate = function() end, frame = w.UI.Button({ label = "Bad" }) })
			end)
		end)).toBe(false)
		for _, active in { false, true } do
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Avatar("Face")({
						name = "Ada",
						frame = w.UI.Box("Frame")({
							width = w.UI.fill(),
							height = w.UI.fill(),
							tint = {
								role = "accent",
								blend = 1,
							},
						}),
						onActivate = if active then function() end else nil,
					}),
				})
			end)
			t.expect(#w.handle.focusOrder().traversal).toBe(if active then 1 else 0)
			w.close()
		end
	end)
	t.it("keeps an interactive icon square and reachable without circle-rim classification", function()
		local w = world.new()
		local rung = Compose.cell("compact")
		local taps = 0
		mount(w, {
			name = "Ada",
			form = "icon",
			controlSize = rung,
			onActivate = function()
				taps += 1
			end,
		})
		local path = "/S/Face+target/Face"
		local sheet = require("../src/tokens/sheet_model")
		for _, size in { "compact", "regular", "large" } do
			rung:set(size)
			w.pres.refresh()
			local face = node(w, path)
			local tags = sheet.classifyTags({ shape = face.props.shape, surface = face.props.surface })
			t.expect(tags[sheet.TAGS.circleRim]).toBeNil()
			t.expect(face.rect.w).toBe(face.rect.h)
			t.expect(node(w, path .. "/Layers/Plate").props.shape).toBe("circle")
			t.expect(w.adapter.node(path .. "/Layers/Rim")).toBeNil()
			t.expect(node(w, "/S/Face+target").rect.w >= 44).toBe(true)
			t.expect(node(w, "/S/Face+target").rect.h >= 44).toBe(true)
		end
		w.pres.focus.focusOn(path)
		w.press("Return")
		t.expect(taps).toBe(1)
		t.expect(#w.handle.focusOrder().traversal).toBe(1)
	end)
	t.it("uses true circle paint for faces and round presence at explicit large diameters", function()
		local w = world.new()
		local presence = Compose.cell("online")
		mount(w, { name = "Ada", image = FACE, diameter = 200, presence = presence, onActivate = function() end })
		local base = "/S/Face+target/Face"
		for _, part in { "Plate", "Picture", "Rim" } do
			t.expect(node(w, base .. "/Layers/" .. part).props.shape).toBe("circle")
		end
		for _, state in { "online", "away", "busy", "offline" } do
			presence:set(state)
			w.pres.refresh()
			local mark, detail = presencePart(w, base, "Mark"), presencePart(w, base, "Detail")
			t.expect(mark.props.shape).toBe(if state == "busy" then "rect" else "circle")
			if state == "offline" then
				t.expect(detail.props.shape).toBe("circle")
			end
			t.expect(mark.rect.w).toBe(mark.rect.h)
		end
	end)
end)

t.describe("Avatar inputs", function()
	for _, case in
		{
			{ device = "pointer", name = "Avatar pointer: activation reaches one mounted surface" },
			{ device = "touch", name = "Avatar touch: activation reaches one mounted surface" },
			{ device = "keyboard", name = "Avatar keyboard: activation reaches one mounted surface" },
			{ device = "gamepad", name = "Avatar gamepad: activation reaches one mounted surface" },
		}
	do
		local device = case.device
		t.it(case.name, function()
			local class = if device == "touch"
				then "Touch"
				elseif device == "gamepad" then "Gamepad"
				else "KeyboardAndMouse"
			local w = world.new({
				preferredInput = class,
				capabilities = { keyboard = true, mouse = true, touch = true, gamepad = true },
			})
			local taps = 0
			mount(w, {
				name = "Ada",
				onActivate = function()
					taps += 1
				end,
			})
			local path = "/S/Face+target/Face"
			if device == "pointer" then
				w.adapter.tap(path)
			elseif device == "touch" then
				w.adapter.touchTap(path)
			else
				w.pres.focus.focusOn(path)
				w.press(if device == "keyboard" then "Return" else "ButtonA")
			end
			t.expect(taps).toBe(1)
			t.expect(#w.handle.focusOrder().traversal).toBe(1)
		end)
	end
	t.it("Avatar pointer affordance: hover and all painted layers share one surface", function()
		local w = world.new()
		mount(w, { name = "Ada", presence = "online", onActivate = function() end })
		local path = "/S/Face+target/Face"
		t.expect(node(w, path).hoverEnabled).toBe(true)
		for _, part in { "Plate", "Initials", "Rim", "Presence" } do
			t.expect(w.adapter.node(path .. "/Layers/" .. part) ~= nil).toBe(true)
		end
	end)
	t.it("Avatar touch affordance: compact plates reserve disjoint whole targets", function()
		local w = world.new({ preferredInput = "Touch", capabilities = { touch = true } })
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.HStack("Row")({
					gap = 0,
					w.UI.Avatar("A")({ name = "A", controlSize = "compact", onActivate = function() end }),
					w.UI.Avatar("B")({ name = "B", controlSize = "compact", onActivate = function() end }),
				}),
			})
		end)
		local a, b = node(w, "/S/Row/A+target").rect, node(w, "/S/Row/B+target").rect
		t.expect(a.w).toBe(44)
		t.expect(a.h).toBe(44)
		t.expect(a.x + a.w <= b.x).toBe(true)
		t.expect(node(w, "/S/Row/A+target/A").rect.w).toBe(36)
	end)
	t.it("Avatar keyboard affordance: one Tab rank with an ordinary focus ring", function()
		local w = world.new()
		mount(w, { name = "Ada", onActivate = function() end })
		local path = w.handle.focusOrder().traversal[1].path
		t.expect(path).toBe("/S/Face+target/Face")
		t.expect(node(w, path).props.focusVisual).toBeNil()
		w.pres.focus.focusOn(path)
		t.expect(w.pres.focus.focused:peek()).toBe(path)
	end)
	t.it("Avatar gamepad affordance: A activates and Cancel remains the screen's", function()
		local w = world.new({ preferredInput = "Gamepad", capabilities = { gamepad = true } })
		local taps = 0
		mount(w, {
			name = "Ada",
			onActivate = function()
				taps += 1
			end,
		})
		w.pres.focus.focusOn("/S/Face+target/Face")
		w.press("ButtonA")
		w.press("ButtonB")
		t.expect(taps).toBe(1)
		t.expect(w.pres.focus.focused:peek()).toBe("/S/Face+target/Face")
	end)
end)

t.describe("Avatar mounted gallery recipe", function()
	t.it("loads at rest, drives pending and failure, and releases each pending branch on the same screen", function()
		local scenarioCtx = require("./lib/scenario_ctx")
		local w = world.new()
		local scenario = require("../examples/gallery/scenarios/avatar").build(scenarioCtx.of(w))
		t.expect(scenario.report()).toBeNil()
		w.present(scenario.screen)
		w.pres.tick(0.05)
		local first = scenario.report()
		t.expect(first.portrait.state).toBe("ready")
		t.expect(first.imageMounted).toBe(true)
		local rect = first.rect
		for _ = 1, 8 do
			t.expect(scenario.steps.pending().portrait.state).toBe("pending")
			t.expect(skeleton.liveDrivers()).toBe(1)
			t.expect(scenario.steps.ready().imageMounted).toBe(true)
			t.expect(skeleton.liveDrivers()).toBe(0)
			t.expect(w.pres.motionClock:activeCount()).toBe(0)
			t.expect(scenario.report().rect).toEqual(rect)
		end
		t.expect(scenario.steps.fail().portrait.initials).toBe("AQ")
		t.expect(scenario.report().imageMounted).toBe(false)
		t.expect(scenario.steps.presence().portrait.presence).toBe("away")
		t.expect(scenario.steps.compact().rect.w).toBe(36)
		t.expect(scenario.steps.large().rect.w).toBe(56)
		w.close()
		t.expect(scenario.report()).toBeNil()
		scenario.dispose()
	end)
end)
