--!strict

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local world = require("./lib/world")
local vocabulary = require("../src/controls/control_vocabulary")
local sheetModel = require("../src/tokens/sheet_model")
local snapshot = require("../src/themes/snapshot")

local NEUTRAL = snapshot.neutral()
local FLOOR = NEUTRAL.targetSizes.minimum

local function authored(control: any): any
	local bp = control.blueprint
	if bp.id ~= nil and string.sub(bp.id, -7) == "+target" then
		bp = bp.children[1]
	end
	return bp.props
end

local function propsOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.props else nil
end

local function tagsOf(w: any, path: string): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, tag in w.adapter.tagsOf(path) do
		set[tag] = true
	end
	return set
end

local function rectOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.rect else nil
end

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function pathOf(w: any, id: string): string
	for _, path in w.adapter.paths() do
		if string.sub(path, -#id - 1) == "/" .. id then
			return path
		end
	end
	error(`no mounted node ends in '/{id}'`, 0)
end

local function targetOf(w: any, id: string): any
	local path = pathOf(w, id)
	local node = w.adapter.node(path)
	return w.adapter.hitRectOf(path) or node.rect
end

describe("the local size vocabulary resolves the theme ladder by NAME", function()
	it("names the three rungs and nothing else", function()
		expect(table.concat(vocabulary.SIZES, ",")).toBe("compact,regular,large")
	end)

	it("a rung becomes the ladder's metric PATHS, never a resolved number", function()
		expect(vocabulary.heightFor("compact").min).toBe("controlSizes.compact.height")
		expect(vocabulary.heightFor("large").min).toBe("controlSizes.large.height")
		expect(vocabulary.paddingFor("compact").left).toBe("controlSizes.compact.paddingX")
		expect(vocabulary.paddingFor("compact").right).toBe("controlSizes.compact.paddingX")
		expect(vocabulary.iconSizeFor("regular")).toBe("controlSizes.regular.iconSize")
	end)

	it("an absent rung asks for nothing at all", function()
		expect(vocabulary.heightFor(nil)).toBe(nil)
		expect(vocabulary.paddingFor(nil)).toBe(nil)
		expect(vocabulary.iconSizeFor(nil)).toBe(nil)
	end)

	it("an unknown word is refused at build, naming the legal set", function()
		local ok, err = pcall(function()
			vocabulary.assertSize("Controls.Button", "tiny")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "compact | regular | large", 1, true) ~= nil).toBe(true)
	end)

	it("`corners` is the CORNER treatment, and square is a radius of zero", function()
		expect(vocabulary.cornerRadiusFor("pill")).toBe("pill")
		expect(vocabulary.cornerRadiusFor("square")).toBe(0)
		expect(vocabulary.cornerRadiusFor(nil)).toBe(nil)
	end)
end)

describe("the vocabulary tags", function()
	it("sheet_model declares the two new prefixes and the over-media tag", function()
		expect(sheetModel.TAGS.sizePrefix).toBe("facet-size-")
		expect(sheetModel.TAGS.appearancePrefix).toBe("facet-appearance-")
		expect(sheetModel.TAGS.overMedia).toBe("facet-over-media")
	end)

	it("classifyTags mints one tag per authored word, and none for an absent one", function()
		local tags = sheetModel.classifyTags({ controlSize = "compact", appearance = "emphasis", over = "media" })
		expect(tags["facet-size-compact"]).toBe(true)
		expect(tags["facet-appearance-emphasis"]).toBe(true)
		expect(tags["facet-over-media"]).toBe(true)
		local bare = sheetModel.classifyTags({})
		expect(bare["facet-size-regular"]).toBe(nil)
		expect(bare["facet-appearance-standard"]).toBe(nil)
		expect(bare["facet-over-media"]).toBe(nil)
	end)

	it("standard appearance earns no tag; every explicit rung earns one", function()
		expect(sheetModel.classifyTags({ appearance = "standard" })["facet-appearance-standard"]).toBe(nil)
		expect(sheetModel.classifyTags({ controlSize = "regular" })["facet-size-regular"]).toBe(true)
	end)

	local function indexed(model: any): { [string]: number }
		local out: { [string]: number } = {}
		for i, rule in model.rules do
			out[rule.name] = i
		end
		return out
	end
	local function models(): { { name: string, model: any } }
		local neutral =
			sheetModel.build({ themes = { { name = "Dark", style = require("../src/tokens/default_style") } } })
		local out = { { name = "Facet Neutral", model = neutral } }
		for _, name in { "pixel_quest", "fantasy_ornate" } do
			local pkg = require("../examples/themes/" .. name).build(Facet.themes)
			table.insert(out, { name = name, model = sheetModel.buildPackage(pkg) })
		end
		return out
	end
	local function ruleNamed(model: any, name: string): any
		for _, rule in model.rules do
			if rule.name == name then
				return rule
			end
		end
		return nil
	end

	it("every builder paints every tag the vocabulary mints", function()
		for _, entry in models() do
			local seen: { [string]: boolean } = {}
			for _, rule in entry.model.rules do
				for tag in string.gmatch(rule.selector, "%.(facet%-[%w%-]+)") do
					seen[tag] = true
				end
			end
			for _, rung in vocabulary.SIZES do
				expect(`{entry.name} facet-size-{rung}:{tostring(seen["facet-size-" .. rung] == true)}`).toBe(
					`{entry.name} facet-size-{rung}:true`
				)
			end
			for _, word in { "emphasis", "soft", "utility", "link" } do
				expect(`{entry.name} facet-appearance-{word}:{tostring(seen["facet-appearance-" .. word] == true)}`).toBe(
					`{entry.name} facet-appearance-{word}:true`
				)
			end
			expect(`{entry.name} over:{tostring(seen["facet-over-media"] == true)}`).toBe(`{entry.name} over:true`)
		end
	end)

	it("the vocabulary rules carry PALETTE TOKENS, so every package wears its own", function()
		for _, entry in models() do
			for _, name in
				{
					"Emphasis control",
					"Soft emphasis control",
					"Utility control",
					"Link control",
					"Control over media",
				}
			do
				local rule = ruleNamed(entry.model, name)
				expect(`{entry.name}/{name} exists:{tostring(rule ~= nil)}`).toBe(`{entry.name}/{name} exists:true`)
				local literal = false
				for prop, value in rule.props do
					if (prop == "BackgroundColor3" or prop == "TextColor3") and type(value) ~= "string" then
						literal = true
					end
				end
				expect(`{entry.name}/{name} literal colour:{tostring(literal)}`).toBe(
					`{entry.name}/{name} literal colour:false`
				)
			end
		end
	end)

	it("role and appearance compose in paint, in both builders", function()
		for _, entry in models() do
			local at = indexed(entry.model)
			for _, word in { "standard", "emphasis" } do
				local fill = if word == "emphasis" then at["Emphasis control"] else at["Control fill"]
				expect(`{entry.name}/{word} role wins the plate:{tostring(at["Destructive button"] > fill)}`).toBe(
					`{entry.name}/{word} role wins the plate:true`
				)
			end
			for word, ruleName in
				{ utility = "Destructive utility", link = "Destructive link", soft = "Destructive soft" }
			do
				local compound = at[ruleName]
				expect(`{entry.name}/{word} compound exists:{tostring(compound ~= nil)}`).toBe(
					`{entry.name}/{word} compound exists:true`
				)
				expect(`{entry.name}/{word} beats the role:{tostring(compound > at["Destructive button"])}`).toBe(
					`{entry.name}/{word} beats the role:true`
				)
				local rule = ruleNamed(entry.model, ruleName)
				expect(`{entry.name}/{word} content:{tostring(rule.props.TextColor3)}`).toBe(
					`{entry.name}/{word} content:$Danger`
				)
			end
			expect(tostring(ruleNamed(entry.model, "Destructive utility").props.BackgroundColor3)).toBe("$Surface")
			expect(ruleNamed(entry.model, "Destructive link").props.BackgroundColor3).toBe(nil)
		end
	end)

	it("the role survives hover and press, in every builder", function()
		for _, entry in models() do
			local at = indexed(entry.model)
			for _, word in { "Emphasis", "Soft", "Utility", "Link" } do
				for _, state in { "hover", "pressed" } do
					local compound = at[`Destructive {string.lower(word)} — {state}`]
					local rule = ruleNamed(entry.model, `Destructive {string.lower(word)} — {state}`)
					expect(rule.props.BackgroundTransparency).toBe(nil)
					for prop in rule.transitions or {} do
						expect(rule.props[prop] ~= nil).toBe(true)
					end
					expect(`{entry.name}/{word} {state} compound exists:{tostring(compound ~= nil)}`).toBe(
						`{entry.name}/{word} {state} compound exists:true`
					)
					expect(`{entry.name}/{word} {state} beats the word:{tostring(compound > at[`{word} — {state}`])}`).toBe(
						`{entry.name}/{word} {state} beats the word:true`
					)
					expect(
						`{entry.name}/{word} {state} beats the role:{tostring(compound > at[`Destructive — {state}`])}`
					).toBe(`{entry.name}/{word} {state} beats the role:true`)
				end
			end
			expect(tostring(ruleNamed(entry.model, "Destructive emphasis — hover").props.BackgroundColor3)).toBe(
				"$DangerHover"
			)
			expect(tostring(ruleNamed(entry.model, "Destructive utility — hover").props.TextColor3)).toBe(
				"$DangerHover"
			)
			expect(tostring(ruleNamed(entry.model, "Destructive link — pressed").props.TextColor3)).toBe(
				"$DangerPressed"
			)
			for _, name in
				{
					"Destructive link — hover",
					"Destructive link — pressed",
					"Destructive utility — hover",
					"Destructive soft — pressed",
				}
			do
				expect(
					`{entry.name}/{name} transparency:{tostring(
						ruleNamed(entry.model, name).props.BackgroundTransparency
					)}`
				).toBe(`{entry.name}/{name} transparency:nil`)
			end
		end
	end)

	it("every appearance word's interaction states beat the control ramp, in both builders", function()
		for _, entry in models() do
			local at = indexed(entry.model)
			for _, word in { "Emphasis", "Soft", "Utility", "Link", "Over media" } do
				for state, generic in { hover = "Control — hover", pressed = "Control — pressed" } do
					local own = at[`{word} — {state}`]
					local rule = ruleNamed(entry.model, `{word} — {state}`)
					expect(rule.props.BackgroundTransparency).toBe(nil)
					for prop in rule.transitions or {} do
						expect(rule.props[prop] ~= nil).toBe(true)
					end
					expect(`{entry.name}/{word} {state} exists:{tostring(own ~= nil)}`).toBe(
						`{entry.name}/{word} {state} exists:true`
					)
					expect(`{entry.name}/{word} {state} beats generic:{tostring(own > at[generic])}`).toBe(
						`{entry.name}/{word} {state} beats generic:true`
					)
				end
			end
		end
	end)
end)

describe("Button adopts the vocabulary through app.controls", function()
	it("omitted vocabulary preserves authored defaults and theme padding", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({ UI.Button("Plain")({ label = "Go" }) })
		end)
		local props = authored(w.record("Plain"))
		for _, key in { "height", "padding", "controlSize", "appearance", "corners" } do
			expect(props[key]).toBe(nil)
		end
		expect(propsOf(w, "/S/Plain").padding).toBe(12)
		expect(tagsOf(w, "/S/Plain")["facet-size-regular"]).toBe(nil)
	end)

	it("rungs author metric names and authored height still wins", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Rows")({
					UI.Button("Small")({ label = "Go", controlSize = "compact" }),
					UI.Button("Tall")({ label = "Go", controlSize = "compact", height = { type = "fixed", px = 72 } }),
				}),
			})
		end)
		local props = authored(w.record("Small"))
		expect(props.height.min).toBe("controlSizes.compact.height")
		expect(props.padding.left).toBe("controlSizes.compact.paddingX")
		expect(props.padding.right).toBe("controlSizes.compact.paddingX")
		expect(tagsOf(w, pathOf(w, "Small"))["facet-size-compact"]).toBe(true)
		expect(authored(w.record("Tall")).height.px).toBe(72)
		expect(rectOf(w, pathOf(w, "Tall")).h).toBe(72)
	end)

	it("compact paint is centered inside exactly its reserved hit footprint", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({ UI.Button("Small")({ label = "Go", controlSize = "compact" }) })
		end)
		local rect, hit, reserved = rectOf(w, pathOf(w, "Small")), targetOf(w, "Small"), rectOf(w, "/S/Small+target")
		expect(rect.h).toBe(NEUTRAL.controlSizes.compact.height)
		expect(rect.h < FLOOR).toBe(true)
		expect(hit.h >= FLOOR).toBe(true)
		expect(hit.y + hit.h / 2).toBe(rect.y + rect.h / 2)
		expect(`{hit.x},{hit.y},{hit.w},{hit.h}`).toBe(`{reserved.x},{reserved.y},{reserved.w},{reserved.h}`)
	end)

	for _, gap in { 0, "xs", "s", "m" } do
		it(`stacked compact Buttons have disjoint targets at gap {gap}`, function()
			local w = world.new()
			local UI = w.UI
			w.present(function()
				return UI.Screen("S")({
					UI.VStack("Rows")({
						gap = gap,
						UI.Button("A")({ label = "One", controlSize = "compact" }),
						UI.Button("B")({ label = "Two", controlSize = "compact" }),
					}),
				})
			end)
			expect(rectOf(w, pathOf(w, "A")).h).toBe(NEUTRAL.controlSizes.compact.height)
			expect(overlaps(targetOf(w, "A"), targetOf(w, "B"))).toBe(false)
			expect(targetOf(w, "A").h >= FLOOR).toBe(true)
		end)
	end

	for _, minimum in { 20, 44, 60 } do
		it(`adjacent icon plates reserve the effective floor with theme minimum {minimum}`, function()
			local w = world.new()
			local UI = w.UI
			local metrics = table.clone(NEUTRAL)
			metrics.targetSizes = table.clone(NEUTRAL.targetSizes)
			metrics.targetSizes.minimum = minimum
			w.env:set("themeMetrics", metrics)
			w.present(function()
				return UI.Screen("S")({
					UI.HStack("Bar")({
						gap = 0,
						UI.Button("A")({
							icon = "close",
							name = "Close",
							controlSize = "compact",
							width = { type = "fixed", px = 32 },
						}),
						UI.Button("B")({
							icon = "increment",
							name = "Add",
							controlSize = "compact",
							width = { type = "fixed", px = 32 },
						}),
					}),
				})
			end)
			expect(overlaps(targetOf(w, "A"), targetOf(w, "B"))).toBe(false)
			expect(targetOf(w, "A").w >= math.max(44, minimum)).toBe(true)
			expect(targetOf(w, "A").h >= math.max(44, minimum)).toBe(true)
			expect(rectOf(w, pathOf(w, "A")).w).toBe(32)
		end)
	end

	it("an explicit fill still fills its parent offer", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Box")({
					width = { type = "fixed", px = 240 },
					UI.Button("Fill")({ label = "Go", controlSize = "compact", width = { type = "fill" } }),
				}),
			})
		end)
		expect(rectOf(w, pathOf(w, "Fill")).w).toBe(240)
	end)

	it("appearance is paint only, role composes, and over-media and corners remain independent", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Rows")({
					UI.Button("Danger")({ label = "Delete", appearance = "emphasis", role = "destructive" }),
					UI.Button("Over")({ label = "Play", over = "media", corners = "pill" }),
					UI.Button("Square")({ label = "Go", corners = "square" }),
				}),
			})
		end)
		local tags = tagsOf(w, pathOf(w, "Danger"))
		expect(tags["facet-appearance-emphasis"]).toBe(true)
		expect(tags["facet-role-destructive"]).toBe(true)
		expect(authored(w.record("Danger")).height).toBe(nil)
		expect(tagsOf(w, pathOf(w, "Over"))["facet-over-media"]).toBe(true)
		expect(propsOf(w, pathOf(w, "Over")).corners.tokens.radius).toBe("pill")
		expect(propsOf(w, pathOf(w, "Square")).corners.radius).toBe(0)
	end)

	for _, case in
		{
			{ spec = { icon = "close" }, message = "name" },
			{ spec = { label = "Close", name = "Close" }, message = "NO visible label" },
			{ spec = { label = "Go", icon = "rbxassetid://1" }, message = "semantic icon" },
			{
				spec = {
					label = "Go",
					trailingIcon = function()
						return "close"
					end,
				},
				message = "CONSTRUCTION-TIME",
			},
			{ spec = { label = "Go", controlSize = "tiny" }, message = "compact | regular | large" },
			{ spec = { label = "Go", appearance = "bright" }, message = "standard | emphasis | soft | utility | link" },
			{ spec = { label = "Go", corners = "round" }, message = "pill | square" },
			{ spec = { label = "+", shape = "circle", trailingIcon = "close" }, message = "trailingIcon" },
			{ spec = { label = "Go", over = "panel" }, message = "media" },
		}
	do
		it(`refuses invalid authoring: {case.message}`, function()
			local w = world.new()
			local ok, err = pcall(function()
				w.scoped(function()
					return w.UI.Button("Invalid")(case.spec)
				end)
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), case.message, 1, true) ~= nil).toBe(true)
		end)
	end

	it("named icon-only and leading/trailing icons draw with rung-sized icon floors", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Rows")({
					UI.Button("Close")({ icon = "close", name = "Close" }),
					UI.Button("Both")({
						label = "Race",
						icon = "facet:search",
						trailingIcon = "chevron.trailing",
						controlSize = "large",
					}),
					UI.Button("Small")({ label = "Race", icon = "close", controlSize = "compact" }),
				}),
			})
		end)
		expect(w.adapter.node(pathOf(w, "Close") .. "/Icon") ~= nil).toBe(true)
		expect(w.record("Close").dump().name).toBe("Close")
		for _, id in { "Icon", "TrailingIcon" } do
			local rect = rectOf(w, pathOf(w, "Both") .. "/" .. id)
			expect(rect.w >= NEUTRAL.controlSizes.large.iconSize).toBe(true)
			expect(rect.h >= NEUTRAL.controlSizes.large.iconSize).toBe(true)
		end
		expect(rectOf(w, pathOf(w, "Small") .. "/Icon").w).toBe(NEUTRAL.controlSizes.compact.iconSize)
	end)

	for _, binding in { "function(use)", "cell" } do
		it(`{binding} updates size and appearance without rebuilding or losing focus, then retracts nil`, function()
			local w = world.new()
			local UI = w.UI
			local rung, look = w.Compose.cell("large"), w.Compose.cell("standard")
			local builds = 0
			local handle = w.present(function()
				builds += 1
				return UI.Screen("S")({
					UI.VStack("Rows")({
						UI.Button("Other")({ label = "Other" }),
						UI.Button("Live")({
							label = "Go",
							controlSize = if binding == "cell"
								then rung
								else function(use)
									return use(rung)
								end,
							appearance = if binding == "cell"
								then look
								else function(use)
									return use(look)
								end,
						}),
					}),
				})
			end)
			local live = pathOf(w, "Live")
			local factoryRuns = handle.root.counters().factoryRuns
			expect(w.pres.focus.focusOn(pathOf(w, "Other"))).toBe(true)
			expect(w.pres.focus.focusOn(live)).toBe(true)
			expect(w.pres.focus.focused:peek()).toBe(live)
			expect(rectOf(w, live).h).toBe(NEUTRAL.controlSizes.large.height)
			rung:set("compact")
			look:set("emphasis")
			w.settle()
			expect(rectOf(w, live).h).toBe(NEUTRAL.controlSizes.compact.height)
			expect(tagsOf(w, live)["facet-appearance-emphasis"]).toBe(true)
			expect(tagsOf(w, live)["facet-size-compact"]).toBe(true)
			expect(builds).toBe(1)
			expect(handle.root.counters().factoryRuns).toBe(factoryRuns)
			expect(#w.records("Live")).toBe(1)
			expect(w.pres.focus.focused:peek()).toBe(live)
			rung:set(nil)
			look:set(nil)
			w.settle()
			expect(tagsOf(w, live)["facet-appearance-emphasis"]).toBe(nil)
			expect(tagsOf(w, live)["facet-size-compact"]).toBe(nil)
			expect(propsOf(w, live).padding).toBe(12)
			expect(w.pres.focus.focused:peek()).toBe(live)
			expect(builds).toBe(1)
			expect(handle.root.counters().factoryRuns).toBe(factoryRuns)
		end)
	end

	it("theme swaps re-resolve the metric names without replacing the mounted control", function()
		local w = world.new()
		local UI = w.UI
		local count = 0
		w.present(function()
			return UI.Screen("S")({
				UI.Button("Swap")({
					label = "Go",
					controlSize = "compact",
					onActivate = function()
						count += 1
					end,
				}),
			})
		end)
		local heights = { neutral = rectOf(w, pathOf(w, "Swap")).h }
		expect(heights.neutral).toBe(NEUTRAL.controlSizes.compact.height)
		for _, name in { "pixel_quest", "fantasy_ornate" } do
			local resolved = Facet.themes.resolve(require("../examples/themes/" .. name).build(Facet.themes), nil, {})
			w.env:set("themeMetrics", resolved)
			w.settle()
			local solved = rectOf(w, pathOf(w, "Swap")).h
			heights[name] = solved
			expect(`{name}:{solved >= resolved.controlSizes.compact.height}`).toBe(`{name}:true`)
			expect(tagsOf(w, pathOf(w, "Swap"))["facet-size-compact"]).toBe(true)
			w.adapter.tap(pathOf(w, "Swap"))
		end
		expect(heights.neutral == heights.pixel_quest and heights.neutral == heights.fantasy_ornate).toBe(false)
		expect(w.record("Swap").dump().controlSize).toBe("compact")
		expect(#w.records("Swap")).toBe(1)
		expect(count).toBe(2)
	end)
end)

describe("Chip adopts the vocabulary through app.controls", function()
	it("omitting vocabulary keeps the default pill, height, and label shape", function()
		local w = world.new()
		local UI = w.UI
		local selected = w.Compose.cell(false)
		w.present(function()
			return UI.Screen("S")({ UI.Chip("Rain")({ label = "Rain", selected = selected }) })
		end)
		local props = authored(w.record("Rain"))
		expect(props.corners.tokens.radius).toBe("pill")
		expect(props.height.min).toBe("targetSizes.minimum")
		expect(props.children).toBe(nil)
		expect(props.controlSize).toBe(nil)
		expect(propsOf(w, "/S/Rain").label).toBe("Rain")
	end)

	it("compact siblings have smaller paint and disjoint targets at zero gap", function()
		local w = world.new()
		local UI = w.UI
		local a, b = w.Compose.cell(false), w.Compose.cell(false)
		w.present(function()
			return UI.Screen("S")({
				UI.HStack("Bar")({
					gap = 0,
					UI.Chip("A")({ label = "Dry", selected = a, controlSize = "compact" }),
					UI.Chip("B")({ label = "Wet", selected = b, controlSize = "compact" }),
				}),
			})
		end)
		expect(rectOf(w, pathOf(w, "A")).h).toBe(NEUTRAL.controlSizes.compact.height)
		expect(overlaps(targetOf(w, "A"), targetOf(w, "B"))).toBe(false)
		expect(targetOf(w, "A").h >= FLOOR).toBe(true)
		w.adapter.tap(pathOf(w, "A"))
		expect(a:peek()).toBe(true)
		expect(b:peek()).toBe(false)
	end)

	it("refuses appearance words outside the Chip family", function()
		local w = world.new()
		local ok, err = pcall(function()
			w.scoped(function()
				return w.UI.Chip("C")({ label = "C", selected = w.Compose.cell(false), appearance = "link" })
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "standard | utility", 1, true) ~= nil).toBe(true)
	end)

	it("accessories draw beside the label and activation flips once across input routes", function()
		local w = world.new()
		local UI = w.UI
		local selected = w.Compose.cell(false)
		local changes = 0
		w.present(function()
			return UI.Screen("S")({
				UI.Chip("Rain")({
					label = "Rain",
					selected = selected,
					leading = UI.Text("Dot")({ text = "*" }),
					trailing = UI.Text("Count")({ text = "3" }),
					onToggle = function()
						changes += 1
					end,
				}),
			})
		end)
		expect(w.adapter.node("/S/Rain/Content/Dot") ~= nil).toBe(true)
		expect(w.adapter.node("/S/Rain/Content/Count") ~= nil).toBe(true)
		w.adapter.tap("/S/Rain")
		expect(selected:peek()).toBe(true)
		expect(w.pres.focus.focusOn("/S/Rain")).toBe(true)
		w.adapter.tap("/S/Rain", { source = "pointer", pointer = "touch" })
		for _, key in { "Return", "ButtonA" } do
			w.press(key)
		end
		expect(changes).toBe(4)
		expect(selected:peek()).toBe(false)
	end)
end)

describe("sized control ownership", function()
	it("remounting a bound Button and Chip releases branch resources and keeps caller state", function()
		local w = world.new()
		local UI, Compose = w.UI, w.Compose
		local show, rung, look, selected =
			Compose.cell(true), Compose.cell("compact"), Compose.cell("utility"), Compose.cell(false)
		local owner
		w.present(function()
			owner = Compose.currentOwner()
			return UI.Screen("S")({
				UI.When("Shown")({
					condition = show,
					thenView = function()
						return UI.VStack("Rows")({
							UI.Button("B")({ label = "Go", controlSize = rung, appearance = look }),
							UI.Chip("C")({
								label = "Rain",
								selected = selected,
								controlSize = function(use)
									return use(rung)
								end,
								appearance = look,
							}),
						})
					end,
				}),
			})
		end)
		local baseline = owner.size()
		w.adapter.tap(pathOf(w, "C"))
		for _ = 1, 8 do
			show:set(false)
			w.settle()
			rung:set("large")
			show:set(true)
			w.settle()
			expect(rectOf(w, pathOf(w, "C")).h).toBe(NEUTRAL.controlSizes.large.height)
			expect(tagsOf(w, pathOf(w, "C"))["facet-appearance-utility"]).toBe(true)
			expect(propsOf(w, pathOf(w, "C")).selected).toBe(true)
			rung:set("compact")
			w.settle()
			expect(owner.size()).toBe(baseline)
		end
		w.close()
		expect(#w.adapter.paths()).toBe(0)
		rung:set("regular")
		selected:set(false)
		expect(selected:peek()).toBe(false)
	end)
end)

describe("sized circles and constrained fill targets", function()
	for _, axis in { "width", "height", "neither" } do
		it(`a compact circle preserves its authored {axis} axis`, function()
			local w = world.new()
			local UI = w.UI
			w.present(function()
				local spec = { label = "Close", icon = "close", shape = "circle", controlSize = "compact" }
				if axis ~= "neither" then
					spec[axis] = { type = "fixed", px = if axis == "width" then 32 else 72 }
				end
				return UI.Screen("S")({ UI.Button("Close")(spec) })
			end)
			local rect = rectOf(w, pathOf(w, "Close"))
			local props = authored(w.record("Close"))
			if axis ~= "neither" then
				expect(props[axis].px).toBe(if axis == "width" then 32 else 72)
				expect(props[if axis == "width" then "height" else "width"]).toBe(nil)
			end
			-- A 32px icon disc retains the existing icon-plus-padding floor (36 here).
			expect(rect.w).toBe(if axis == "height" then 72 else NEUTRAL.controlSizes.compact.height)
			expect(rect.h).toBe(rect.w)
			expect(targetOf(w, "Close").w >= FLOOR).toBe(true)
			expect(targetOf(w, "Close").h >= FLOOR).toBe(true)
		end)
	end

	for _, axis in { "width", "height" } do
		it(`a bound compact circle keeps its authored {axis} through rung changes`, function()
			local w = world.new()
			local UI = w.UI
			local rung = w.Compose.cell("compact")
			local axisSize = w.Compose.cell({ type = "fixed", px = 72 })
			w.present(function()
				local spec = {
					label = "Close",
					icon = "close",
					shape = "circle",
					controlSize = function(use)
						return use(rung)
					end,
				}
				spec[axis] = axisSize
				if axis == "width" then
					spec.id = "Close"
					return UI.Screen("S")({ UI.Button(spec) })
				end
				return UI.Screen("S")({ UI.Button("Close")(spec) })
			end)
			for _, size in { "large", "regular", "compact" } do
				rung:set(size)
				w.settle()
				local rect = rectOf(w, pathOf(w, "Close"))
				expect(rect.w).toBe(72)
				expect(rect.h).toBe(72)
			end
			rung:set(nil)
			w.settle()
			expect(rectOf(w, pathOf(w, "Close")).w).toBe(72)
			axisSize:set({ type = "fixed", px = 88 })
			w.settle()
			expect(rectOf(w, pathOf(w, "Close")).w).toBe(88)
			expect(rectOf(w, pathOf(w, "Close")).h).toBe(88)
			expect(#w.records("Close")).toBe(1)
		end)
	end

	for _, minimum in { 44, 60 } do
		it(`an 80px fill row reserves disjoint {minimum}px targets and reports its shortage`, function()
			local w = world.new({
				overflowGuardOff = "The authored 80px row is deliberately narrower than its two required hit floors; this case asserts that shortage and disjoint targets.",
			})
			local UI = w.UI
			local metrics = table.clone(NEUTRAL)
			metrics.targetSizes = table.clone(NEUTRAL.targetSizes)
			metrics.targetSizes.minimum = minimum
			w.env:set("themeMetrics", metrics)
			w.present(function()
				return UI.Screen("S")({
					UI.HStack("Narrow")({
						gap = 0,
						width = { type = "fixed", px = 80 },
						UI.Button("A")({ label = "A", controlSize = "compact", width = UI.fill() }),
						UI.Button("B")({ label = "B", controlSize = "compact", width = UI.fill() }),
					}),
				})
			end)
			local a, b = targetOf(w, "A"), targetOf(w, "B")
			expect(overlaps(a, b)).toBe(false)
			for _, id in { "A", "B" } do
				local reserved = rectOf(w, `/S/Narrow/{id}+target`)
				expect(reserved.w >= minimum).toBe(true)
				expect(reserved.h >= minimum).toBe(true)
			end
			expect(#w.controller.diagnostics() > 0).toBe(true)
		end)
	end
end)

describe("sized fill minima remain live and caller-owned", function()
	it("resolves metric sums before the target floor and matches fresh layout after every edit", function()
		local original = { type = "fill", weight = 1, min = { "targetSizes.minimum", 20 } }
		local function fixture(full: boolean)
			local w = world.new({ viewport = { x = 0, y = 0, w = 320, h = 160 } })
			local width = w.Compose.cell(original)
			w.present(function()
				local UI = w.UI
				return UI.Screen("S")({
					UI.HStack("Row")({
						width = UI.fill(),
						gap = 0,
						UI.Button("A")({ label = "A", controlSize = "compact", width = width }),
						UI.Button("B")({ label = "B", controlSize = "compact", width = UI.fill(3) }),
					}),
				})
			end, { structuralReuse = not full, measureReuse = not full, incrementalLayout = not full })
			return w, width
		end
		local a, aw = fixture(false)
		local b, bw = fixture(true)
		local function agree()
			for _, id in { "A", "B", "A+target", "B+target" } do
				expect(rectOf(a, pathOf(a, id))).toEqual(rectOf(b, pathOf(b, id)))
			end
			expect(a.controller.diagnostics()).toEqual(b.controller.diagnostics())
			expect(overlaps(targetOf(a, "A"), targetOf(a, "B"))).toBe(false)
			expect(#a.records("A")).toBe(1)
		end
		agree()
		expect(rectOf(a, pathOf(a, "A+target")).w).toBe(80)
		for _, minimum in { 70, 80 } do
			local metrics = table.clone(snapshot.neutral())
			metrics.targetSizes = table.clone(metrics.targetSizes)
			metrics.targetSizes.minimum = minimum
			a.env:set("themeMetrics", metrics)
			b.env:set("themeMetrics", metrics)
			a.settle()
			b.settle()
			agree()
			expect(rectOf(a, pathOf(a, "A+target")).w).toBe(minimum + 20)
		end
		for _, nextWidth in
			{
				{ type = "fill", min = 110, weight = 1 },
				{ type = "fill", weight = 2 },
				{ type = "fixed", px = 110 },
				original,
			}
		do
			aw:set(nextWidth)
			bw:set(nextWidth)
			a.settle()
			b.settle()
			agree()
		end
		a.env:set("viewportRect", { x = 0, y = 0, w = 400, h = 160 })
		b.env:set("viewportRect", { x = 0, y = 0, w = 400, h = 160 })
		a.settle()
		b.settle()
		agree()
		expect(original.min).toEqual({ "targetSizes.minimum", 20 })
		expect(original.weight).toBe(1)
	end)
end)

describe("composed Button content keeps its own inset", function()
	it("keeps theme vertical padding for sized children and honors explicit padding", function()
		local w = world.new({ env = { preferredTextOffset = 14 } })
		local UI, size = w.UI, w.Compose.cell("compact")
		w.present(function()
			local function card(id, padding)
				return UI.Button(id)({
					controlSize = size,
					padding = padding,
					UI.VStack(id .. "Lines")({
						gap = 0,
						UI.Text({ text = "one" }),
						UI.Text({ text = "two" }),
						UI.Text({ text = "three" }),
					}),
				})
			end
			return UI.Screen("S")({ UI.VStack({ card("Theme", nil), card("Explicit", 5) }) })
		end)
		local function check()
			for id, padding in { Theme = 12, Explicit = 5 } do
				local plate, inner = rectOf(w, pathOf(w, id)), rectOf(w, pathOf(w, id .. "Lines"))
				expect(inner.y - plate.y).toBe(padding)
				expect(plate.y + plate.h - inner.y - inner.h).toBe(padding)
			end
		end
		check()
		expect(authored(w.record("Theme")).padding).toBeNil()
		size:set(nil)
		w.settle()
		check()
		expect(#w.records("Theme")).toBe(1)
	end)

	it("refuses empty and name-only content before mounting, while an empty bound label can recover", function()
		local w = world.new()
		local UI = w.UI
		for _, spec in { {}, { name = "Blank" }, { label = "", name = "Blank" }, { children = {} } } do
			local ok, err = pcall(function()
				w.present(function()
					return UI.Screen("S")({ UI.Button("Blank")(spec) })
				end)
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "nothing to draw", 1, true) ~= nil).toBe(true)
			expect(w.adapter.liveCount()).toBe(0)
		end
		local label = w.Compose.cell("")
		w.present(function()
			return UI.Screen("S")({ UI.Button("Live")({ label = label, controlSize = "compact" }) })
		end)
		label:set("Ready")
		w.settle()
		expect(propsOf(w, pathOf(w, "Live")).label).toBe("Ready")
		w.close()
		expect(w.adapter.liveCount()).toBe(0)
		label:set("Borrowed")
		expect(label:peek()).toBe("Borrowed")
	end)
end)

describe("live control vocabulary keeps the last legal publication", function()
	for _, sourceKind in { "cell", "formula", "getter" } do
		for _, kind in { "Button", "Chip", "ShortcutHint" } do
			it(kind .. " checks every " .. sourceKind .. " rung and recovers", function()
				local w = world.new()
				local UI, Compose = w.UI, w.Compose
				local size, other = Compose.cell("compact"), Compose.cell("before")
				w.present(function()
					local source = if sourceKind == "formula"
						then Compose.formula(function(use)
							return use(size)
						end)
						elseif sourceKind == "getter" then function(use)
							return use(size)
						end
						else size
					local props =
						{ controlSize = source, selected = if kind == "Chip" then Compose.cell(false) else nil }
					if kind == "ShortcutHint" then
						props.keys = { { "K" } }
					else
						props.label = "Ready"
					end
					return UI.Screen("S")({
						UI.VStack({ UI[kind]("Subject")(props), UI.Text("Other")({ text = other }) }),
					})
				end)
				local id = if kind == "ShortcutHint" then "Key1" else "Subject"
				local path = pathOf(w, id)
				local legal = table.clone(rectOf(w, path))
				local ok, err = pcall(function()
					size:set("huge")
					w.settle()
				end)
				local refusal = if ok then tostring(w.core:lastError()) else tostring(err)
				expect(string.find(refusal, "compact | regular | large", 1, true) ~= nil).toBe(true)
				expect(rectOf(w, path)).toEqual(legal)
				other:set("after")
				w.settle()
				expect(propsOf(w, pathOf(w, "Other")).text).toBe("after")
				size:set("large")
				w.settle()
				expect(rectOf(w, path).h > legal.h).toBe(true)
				size:set(nil)
				w.settle()
				expect(rectOf(w, path).h < 56).toBe(true)
				if kind ~= "ShortcutHint" then
					expect(tagsOf(w, path)["facet-size-large"]).toBe(nil)
					expect(pathOf(w, "Subject+target") ~= nil).toBe(true)
				end
				w.close()
				expect(w.adapter.liveCount()).toBe(0)
				size:set("regular")
				expect(size:peek()).toBe("regular")
			end)
		end
		for _, kind in { "Button", "Chip" } do
			it(kind .. " checks its own " .. sourceKind .. " appearance family", function()
				local w = world.new()
				local UI, Compose = w.UI, w.Compose
				local appearance = Compose.cell("utility")
				w.present(function()
					local source = if sourceKind == "formula"
						then Compose.formula(function(use)
							return use(appearance)
						end)
						elseif sourceKind == "getter" then function(use)
							return use(appearance)
						end
						else appearance
					return UI.Screen("S")({
						UI[kind]("Subject")({
							label = "Ready",
							appearance = source,
							selected = if kind == "Chip" then Compose.cell(false) else nil,
						}),
					})
				end)
				local path = pathOf(w, "Subject")
				local ok, err = pcall(function()
					appearance:set(if kind == "Chip" then "link" else "unknown")
					w.settle()
				end)
				local refusal = if ok then tostring(w.core:lastError()) else tostring(err)
				expect(string.find(refusal, "appearance", 1, true) ~= nil).toBe(true)
				expect(propsOf(w, path).appearance).toBe("utility")
				expect(tagsOf(w, path)["facet-appearance-utility"]).toBe(true)
				expect(tagsOf(w, path)["facet-appearance-link"]).toBe(nil)
				appearance:set("standard")
				w.settle()
				expect(propsOf(w, path).appearance).toBe("standard")
				appearance:set(nil)
				w.settle()
				expect(propsOf(w, path).appearance).toBe(nil)
				expect(tagsOf(w, path)["facet-appearance-utility"]).toBe(nil)
				w.close()
				appearance:set("utility")
				expect(appearance:peek()).toBe("utility")
			end)
		end
	end
end)
