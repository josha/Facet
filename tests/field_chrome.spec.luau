--!strict
--[[ THE SHARED FIELD CHROME — label, notation, hint, error, accessories and the
	local vocabulary — proved on the first control that adopts it, through the
	public `app.controls` constructors. Every claim is about the SCREEN: where a
	part solved, whether the adapter was told to show it, what the plate was
	painted as, and which paths the traversal ring stops on. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local world = require("./lib/world")
local snapshot = require("../src/themes/snapshot")
local sheetModel = require("../src/tokens/sheet_model")
local defaultStyle = require("../src/tokens/default_style")

local NEUTRAL = snapshot.neutral()
local FLOOR = NEUTRAL.targetSizes.minimum
local ICON_SMALL = NEUTRAL.iconSizes.small

-- one TextInput "Name" under screen "S"; `spec.initial` seeds the text cell
local function fieldWorld(spec: any?, opts: any?): any
	local w = world.new(opts or { viewport = { x = 0, y = 0, w = 600, h = 400 } })
	local UI, Compose = w.UI, w.Compose
	local value = Compose.cell((spec and spec.initial) or "")
	local merged: any = { value = value }
	for key, entry in spec or {} do
		if key ~= "initial" then
			merged[key] = entry
		end
	end
	w.present(function()
		return UI.Screen("S")({ UI.TextInput("Name")(merged) })
	end, { sinkNavigation = true })
	w.value = value
	w.control = w.record("Name")
	return w
end

local function rectOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.rect else nil
end

local function propsOf(w: any, path: string): any
	local node = w.adapter.node(path)
	return if node ~= nil then node.props else nil
end

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function contains(outer: any, inner: any): boolean
	return inner.x >= outer.x
		and inner.y >= outer.y
		and inner.x + inner.w <= outer.x + outer.w
		and inner.y + inner.h <= outer.y + outer.h
end

local function stops(w: any): { string }
	local out: { string } = {}
	for _, entry in w.handle.focusOrder().traversal do
		table.insert(out, tostring(entry.path))
	end
	return out
end

describe("field chrome: absent means today", function()
	it("a field with no chrome keys mounts the exact tree it always did", function()
		local w = fieldWorld({ placeholder = "Your name" })
		expect(w.adapter.node("/S/Name/Field") ~= nil).toBe(true)
		expect(propsOf(w, "/S/Name").surface).toBe("chip")
		expect(w.adapter.node("/S/Name/Label")).toBeNil()
		expect(w.adapter.node("/S/Name/Message")).toBeNil()
		expect(w.adapter.node("/S/Name/Row")).toBeNil()
	end)
end)

describe("field chrome: the label", function()
	it("the label sits above its field, and a tap or a finger on it puts the caret in the field", function()
		for _, input in { "pointer", "touch" } do
			local w = fieldWorld({ label = "Display name" })
			local label, field = rectOf(w, "/S/Name/Label"), rectOf(w, "/S/Name/Input")
			expect(label.y + label.h <= field.y).toBe(true)
			expect(propsOf(w, "/S/Name/Input/Field").editing).toBe(false)
			if input == "pointer" then
				w.adapter.tap("/S/Name/Label")
			else
				w.adapter.touchTap("/S/Name/Label")
			end
			w.pres.refresh()
			expect(`{input}: {propsOf(w, "/S/Name/Input/Field").editing}`).toBe(`{input}: true`)
		end
	end)

	it("a disabled field's label follows it: no press or hover affordance, live both ways", function()
		local enabled = require("../src/vendor/compose/core").cell(false)
		local w = fieldWorld({ label = "Display name", enabled = enabled })
		expect(propsOf(w, "/S/Name/Label").enabled).toBe(false)
		enabled:set(true)
		w.pres.refresh()
		expect(propsOf(w, "/S/Name/Label").enabled).toBe(true)
	end)

	it("the label adds no focus stop, and its target never reaches the field's", function()
		local plain = fieldWorld({})
		local labelled = fieldWorld({ label = "Display name" })
		expect(table.concat(stops(labelled), " ")).toBe("/S/Name/Input/Field")
		expect(#stops(labelled)).toBe(#stops(plain))
		-- the floor is reserved in the label's own footprint, so nothing expands
		expect(labelled.adapter.hitRectOf("/S/Name/Label")).toBeNil()
		local label = rectOf(labelled, "/S/Name/Label")
		expect(label.h >= FLOOR).toBe(true)
		local editor = labelled.adapter.hitRectOf("/S/Name/Input/Field") or rectOf(labelled, "/S/Name/Input/Field")
		expect(overlaps(label, editor)).toBe(false)
	end)

	it("the required mark is part of the label's words, bound or static; `optional` paints no word", function()
		local required = fieldWorld({ label = "Display name", requiredMark = "required" })
		expect(propsOf(required, "/S/Name/Label/Title").text).toBe("Display name *")
		expect(required.adapter.node("/S/Name/Label/RequiredMark")).toBeNil()

		local w = world.new()
		local words = w.Compose.cell("Display name")
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.TextInput("Name")({
					value = w.Compose.cell(""),
					label = function(use)
						return use(words)
					end,
					requiredMark = "required",
				}),
			})
		end)
		expect(propsOf(w, "/S/Name/Label/Title").text).toBe("Display name *")
		words:set("Anzeigename")
		w.settle()
		expect(propsOf(w, "/S/Name/Label/Title").text).toBe("Anzeigename *")

		local narrow = fieldWorld({
			label = "Display name shown above your kart to every other racer",
			requiredMark = "required",
		}, { viewport = { x = 0, y = 0, w = 320, h = 800 } })
		local wrapped, row = rectOf(narrow, "/S/Name/Label/Title"), rectOf(narrow, "/S/Name/Label")
		expect(wrapped.x + wrapped.w <= row.x + row.w).toBe(true)
		expect(wrapped.h > rectOf(required, "/S/Name/Label/Title").h).toBe(true)

		local optional = fieldWorld({ label = "Display name", requiredMark = "optional" })
		expect(propsOf(optional, "/S/Name/Label/Title").text).toBe("Display name")
		expect(optional.control.dump().requiredMark).toBe("optional")
	end)
end)

describe("field chrome: one message line", function()
	local MARK = "/S/Name/Message/MarkWhen/then/MessageMark"
	local LINE = "/S/Name/Message/Validation"

	it("an error replaces the hint, in the danger role, beside a mark, and the field holds still", function()
		local w = world.new()
		local failure = w.Compose.cell("")
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.TextInput("Name")({
					value = w.Compose.cell(""),
					hint = "Shown to other players",
					errorText = failure,
				}),
			})
		end)
		expect(propsOf(w, LINE).text).toBe("Shown to other players")
		expect(w.adapter.node(MARK)).toBeNil()
		-- at rest the hint is in line with the plate above it: no hidden mark indent
		expect(rectOf(w, LINE).x).toBe(rectOf(w, "/S/Name/Input").x)
		local before = rectOf(w, "/S/Name/Input")

		failure:set("That name is taken.")
		w.settle()
		expect(propsOf(w, LINE).text).toBe("That name is taken.")
		expect(w.adapter.visibleOf(MARK)).toBe(true)
		expect(propsOf(w, LINE).tint.role).toBe("danger")
		local after = rectOf(w, "/S/Name/Input")
		expect(`{after.y} {after.h}`).toBe(`{before.y} {before.h}`)
		-- an error paints and speaks and shakes nothing
		expect(propsOf(w, "/S/Name/Input").offset).toBeNil()

		failure:set("")
		w.settle()
		expect(propsOf(w, LINE).text).toBe("Shown to other players")
		expect(w.adapter.node(MARK)).toBeNil()
		expect(rectOf(w, LINE).x).toBe(rectOf(w, "/S/Name/Input").x)
	end)

	it("the error mark is floored at the icon rung, as tall as its line, and painted the message's colour", function()
		local w = fieldWorld({ hint = "Shown to other players", errorText = "That name is taken." })
		local mark, words = rectOf(w, MARK), rectOf(w, LINE)
		expect(`height {mark.h} vs line {words.h}`).toBe(`height {words.h} vs line {words.h}`)
		expect(`floored: {mark.w >= ICON_SMALL}`).toBe("floored: true")
		expect(w.adapter.node(MARK).decorationHint.iconSize).toBe("small")
		expect(propsOf(w, MARK).tint.role).toBe("danger")
		local tags = table.concat(w.adapter.tagsOf(MARK), " ")
		expect(string.find(tags, "facet-letters-danger", 1, true) ~= nil).toBe(true)
		local model = sheetModel.build({ themes = { { name = "Facet Neutral", style = defaultStyle } } })
		local painted: string? = nil
		for _, rule in model.rules do
			if rule.selector == ".facet-letters-danger > .facet-chrome-icon" then
				painted = tostring(rule.props.ImageColor3)
			end
		end
		expect(painted).toBe("$Danger")
	end)

	it("the caller's error outranks the numeric field's own rejection line", function()
		local w = world.new()
		local failure = w.Compose.cell("")
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.TextInput("Laps")({
					value = w.Compose.cell("3"),
					numericValue = w.Compose.cell(3),
					presentation = "number",
					min = 1,
					max = 9,
					errorText = failure,
				}),
			})
		end, { sinkNavigation = true })
		w.adapter.tap("/S/Laps/Input/Field")
		w.adapter.pasteText("/S/Laps/Input/Field", "1.2.3")
		w.adapter.commitText("/S/Laps/Input/Field")
		w.settle()
		expect(propsOf(w, "/S/Laps/Message/Validation").text ~= "").toBe(true)
		failure:set("The server refused that number.")
		w.settle()
		expect(propsOf(w, "/S/Laps/Message/Validation").text).toBe("The server refused that number.")
	end)
end)

describe("field chrome: accessories inside the plate", function()
	local ROW = "/S/Name/Input/Row"
	local function accessoryWorld(): any
		local pasted = { count = 0 }
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local UI = w.UI
		w.value = w.Compose.cell("Ada")
		w.present(function()
			return UI.Screen("S")({
				UI.TextInput("Name")({
					value = w.value,
					clearButtonMode = "always",
					leading = UI.Text("Mark")({ text = "@", textSize = "control", width = UI.hug(), height = UI.hug() }),
					trailing = UI.Button("Paste")({
						label = "Paste",
						onActivate = function()
							pasted.count += 1
						end,
					}),
				}),
			})
		end, { sinkNavigation = true })
		w.pasted = pasted
		return w
	end

	it("both accessories solve inside the plate, and the clear keeps its room between them", function()
		local w = accessoryWorld()
		local plate = rectOf(w, "/S/Name/Input")
		local leading, trailing = rectOf(w, ROW .. "/Leading"), rectOf(w, ROW .. "/Trailing")
		local editor, clear = rectOf(w, ROW .. "/Field"), rectOf(w, ROW .. "/Clear")
		expect(contains(plate, leading) and contains(plate, trailing)).toBe(true)
		expect(leading.x + leading.w <= editor.x).toBe(true)
		expect(editor.x + editor.w <= clear.x).toBe(true)
		expect(clear.x + clear.w <= trailing.x).toBe(true)
	end)

	it("a static leading mark is not a stop; the clear and the trailing action are, in that order", function()
		local w = accessoryWorld()
		expect(table.concat(stops(w), " ")).toBe(`{ROW}/Field {ROW}/Clear {ROW}/Trailing/Paste`)
	end)

	it("the trailing action fires on pointer, touch, keyboard and gamepad", function()
		local w = accessoryWorld()
		local PASTE = ROW .. "/Trailing/Paste"
		w.adapter.tap(PASTE)
		w.adapter.touchTap(PASTE)
		for _, key in { "Return", "ButtonA" } do
			w.pres.focus.focusOn(PASTE)
			w.pres.refresh()
			w.press(key)
		end
		expect(w.pasted.count).toBe(4)
		expect(w.value:peek()).toBe("Ada")
	end)

	it("the clear affordance is reachable on pointer, touch, keyboard and gamepad", function()
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			local w = fieldWorld({ initial = "Ada", clearButtonMode = "always" })
			local CLEAR = "/S/Name/Clear"
			expect(table.concat(stops(w), " ")).toBe(`/S/Name/Field {CLEAR}`)
			if input == "pointer" then
				w.adapter.tap(CLEAR)
			elseif input == "touch" then
				w.adapter.touchTap(CLEAR)
			else
				w.pres.focus.focusOn(CLEAR)
				w.pres.refresh()
				w.press(if input == "keyboard" then "Return" else "ButtonA")
			end
			expect(`{input}: {w.value:peek()}`).toBe(`{input}: `)
		end
	end)

	it("a search field keeps its leading mark beside a trailing action, and refuses a second one", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.TextInput("Find")({
					value = w.Compose.cell("rally"),
					presentation = "search",
					trailing = UI.Button("Filter")({ label = "Filter", onActivate = function() end }),
				}),
			})
		end, { sinkNavigation = true })
		local glyph = rectOf(w, "/S/Find/Input/Row/SearchIcon")
		expect(w.adapter.visibleOf("/S/Find/Input/Row/SearchIcon")).toBe(true)
		expect(w.adapter.node("/S/Find/Input/Row/SearchIcon").decorationHint.icon).toBe("facet:search")
		expect(glyph.x + glyph.w <= rectOf(w, "/S/Find/Input/Row/Field").x).toBe(true)
		expect(contains(rectOf(w, "/S/Find/Input"), glyph)).toBe(true)
		-- the pinned form's inset does not survive as an empty margin in the row
		expect(glyph.x - rectOf(w, "/S/Find/Input").x < NEUTRAL.space.xl).toBe(true)

		local ok, err = pcall(function()
			w.scoped(function()
				return UI.TextInput("Twice")({
					value = w.Compose.cell(""),
					presentation = "search",
					leading = UI.Text("Mark")({ text = "@" }),
				})
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "already leads", 1, true) ~= nil).toBe(true)
	end)
end)

describe("field chrome: the local vocabulary on a field", function()
	it("appearance paints the plate a published surface; a bound word repaints in place", function()
		for word, surface in { standard = "chip", contrast = "control", utility = "plain" } do
			expect(`{word}: {propsOf(fieldWorld({ appearance = word }), "/S/Name").surface}`).toBe(`{word}: {surface}`)
		end
		local w = world.new()
		local word = w.Compose.cell("standard")
		local other = w.Compose.cell("before")
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.TextInput("Name")({ value = w.Compose.cell(""), appearance = word }),
				w.UI.Text("Other")({ text = other }),
			})
		end)
		local runs = w.handle.root.counters().factoryRuns
		word:set("contrast")
		w.settle()
		expect(propsOf(w, "/S/Name").surface).toBe("control")
		word:set("utility")
		w.settle()
		expect(propsOf(w, "/S/Name").surface).toBe("plain")
		expect(w.handle.root.counters().factoryRuns).toBe(runs)
		-- a word this family does not have is refused, keeping the last legal paint
		local ok, err = pcall(function()
			word:set("emphasis")
			w.settle()
		end)
		local refusal = if ok then tostring(w.core:lastError()) else tostring(err)
		expect(string.find(refusal, "standard | contrast | utility", 1, true) ~= nil).toBe(true)
		expect(propsOf(w, "/S/Name").surface).toBe("plain")
		other:set("after")
		w.settle()
		expect(propsOf(w, "/S/Other").text).toBe("after")
	end)

	it("corners ride the shipped modifier, and square is a radius of zero", function()
		expect(propsOf(fieldWorld({ corners = "pill" }), "/S/Name").corners.tokens.radius).toBe("pill")
		expect(propsOf(fieldWorld({ corners = "square" }), "/S/Name").corners.radius).toBe(0)
		expect(propsOf(fieldWorld({}), "/S/Name").corners).toBeNil()
	end)

	it("a named rung shrinks the plate, reserves a whole target, and yields to an authored height", function()
		local w = fieldWorld({ controlSize = "compact" })
		local plate, reserved = rectOf(w, "/S/Name+target/Name"), rectOf(w, "/S/Name+target")
		expect(plate.h < FLOOR).toBe(true)
		expect(reserved.h >= FLOOR).toBe(true)
		w.adapter.tap("/S/Name+target/Name/Field")
		w.pres.refresh()
		expect(propsOf(w, "/S/Name+target/Name/Field").editing).toBe(true)
		local tall = fieldWorld({ controlSize = "compact", height = { type = "fixed", px = 72 } })
		expect(rectOf(tall, "/S/Name+target/Name").h).toBe(72)
		-- with furniture the reserved plate sits inside the stack under its label
		local labelled = fieldWorld({ controlSize = "compact", label = "Name" })
		labelled.adapter.tap("/S/Name/Label")
		labelled.pres.refresh()
		expect(propsOf(labelled, "/S/Name/Input+target/Input/Field").editing).toBe(true)
	end)

	it("an unknown chrome word is a build error that names the key", function()
		local w = world.new()
		for key, bad in { appearance = "emphasis", corners = "rounded", requiredMark = "maybe", hint = 4 } do
			local ok, err = pcall(function()
				w.scoped(function()
					local spec: any = { value = w.Compose.cell("") }
					spec[key] = bad
					return w.UI.TextInput("Name")(spec)
				end)
			end)
			expect(`{key}: {ok}`).toBe(`{key}: false`)
			expect(string.find(tostring(err), key, 1, true) ~= nil).toBe(true)
		end
	end)

	it("closing the screen leaves no field node behind", function()
		local w = fieldWorld({ label = "Name", hint = "Hint", errorText = "Wrong", controlSize = "compact" })
		w.close()
		expect(w.adapter.liveCount()).toBe(0)
		expect(w.core.lastError()).toBeNil()
	end)
end)
