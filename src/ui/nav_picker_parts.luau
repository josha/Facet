--!strict
local ThemeTypes = require("./theme_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")

export type Choice<V> = {
	isSelected: (value: V, use: ComposeTypes.Use?) -> boolean,
	select: (value: V) -> (),
	options: ComposeTypes.ReadOnlyValue<{ Nav.PickerOption<V> }>,
}
export type Parts = {
	keys: { string },
	appearanceFor: (style: Nav.PickerStyle, word: unknown) -> string?,
	derive: <T>(compute: (ComposeTypes.Use?) -> T, ...unknown) -> Types.Input<T>,
	layoutWidth: (node: GuiObject) -> (ComposeTypes.ReadOnlyValue<number>, Frame),
	wrapWhenLong: (
		label: TextLabel | TextButton,
		space: (ComposeTypes.Use) -> string,
		container: GuiObject,
		truncates: boolean
	) -> (),
	sideChrome: (controlSize: Types.Input<Types.ControlSize?>?, use: ComposeTypes.Use?, glyph: boolean?) -> number,
	wrapCaptions: (
		button: GuiObject,
		controlSize: Types.Input<Types.ControlSize?>?,
		across: (ComposeTypes.Use) -> number,
		peers: ((ComposeTypes.Use) -> number)?
	) -> (),
	liveIcon: <V>(source: ComposeTypes.ReadOnlyValue<Nav.PickerOption<V>>) -> Types.Input<string>?,
}

return function(ctx: Types.Context, surfaces: Nav.Surfaces): Parts
	local Host, Compose, read = ctx.Host, ctx.Compose, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local function derive<T>(compute: (ComposeTypes.Use?) -> T, ...: unknown): Types.Input<T>
		for index = 1, select("#", ...) do
			local source = select(index, ...)
			if Compose.isValue(source) or type(source) == "function" then
				return compute
			end
		end
		return compute(nil)
	end
	local function layoutWidth(node: GuiObject): (ComposeTypes.ReadOnlyValue<number>, Frame)
		local extent = ctx.observe.AbsoluteSize(node)
		local probe: Frame? = nil
		ctx.runtime.mount(function()
			probe = Host.Frame "Unit" { Size = D2.fromOffset(1, 1), Visible = false }
			return probe
		end, node)
		local pixel = ctx.observe.AbsoluteSize(assert(probe))
		return Compose.formula(function(use: ComposeTypes.Use): number
			local unit = use(pixel).X
			local width = use(extent).X / (if unit > 0 then unit else 1)
			return if width > 0 then width else math.huge
		end),
			assert(probe)
	end

	local function wrapWhenLong(
		label: TextLabel | TextButton,
		space: (ComposeTypes.Use) -> string,
		container: GuiObject,
		truncates: boolean
	)
		local text = label
		local words, points, face =
			ctx.observe.Text(label), ctx.observeStyled.TextSize(label), ctx.observeStyled.FontFace(label)
		local fits, extent = ctx.observe.TextFits(label), ctx.observe.AbsoluteSize(container)
		local owner = assert(Compose.currentOwner(), "Facet UI.Picker wraps captions inside a Compose owner")
		local probe: TextLabel? = nil
		local restore: Enum.TextTruncate? = nil
		local boundFor, boundWidth = "", 0
		local pending: thread? = nil
		local function widestWord(): number
			if ComposeTypes.owner.isDisposed(owner) then
				return 0
			end
			if probe == nil then
				Compose.withOwner(owner, function()
					ctx.runtime.mount(function()
						probe = Host.TextLabel "WidestWord" {
							Size = D2.fromOffset(0, 0),
							BackgroundTransparency = 1,
							TextTransparency = 1,
							Interactable = false,
							AutoLocalize = false,
							Text = "",
						}
						return ctx.Host.Folder "WordMeasure" {
							probe,
						}
					end, container)
				end)
			end
			local measuring = assert(probe)
			measuring.FontFace, measuring.TextSize = face:peek(), points:peek()
			measuring.Text = string.gsub(text.Text, "%s+", "\n")
			local widest = measuring.TextBounds.X
			measuring.Text = ""
			return widest
		end
		local function cancel()
			if pending and coroutine.status(pending) == "suspended" then
				task.cancel(pending)
			end
			pending = nil
		end
		local function checkWords(key: string)
			if boundFor == key and text.TextWrapped and text.TextBounds.X < widestWord() - 0.5 then
				restore = text.TextTruncate
				text.TextWrapped = false
				text.TextTruncate = E.TextTruncate.AtEnd
			end
		end
		local function recheck(key: string)
			cancel()
			if not task then
				return
			end
			local thread: thread
			thread = task.spawn(function()
				for _ = 1, 10 do
					task.wait()
					if boundFor ~= key or not text.TextWrapped then
						break
					end
					checkWords(key)
				end
				if pending == thread then
					pending = nil
				end
			end)
			if coroutine.status(thread) ~= "dead" then
				pending = thread
			end
		end
		Compose.cleanup(cancel)
		Compose.watch(function(use: ComposeTypes.Use)
			use(fits)
			local width = use(extent).X
			local inputs = `{space(use)}|{use(words)}|{use(points)}|{use(face)}`
			if text.TextWrapped or restore ~= nil then
				if inputs == boundFor and width <= boundWidth then
					if truncates then
						checkWords(inputs)
					end
					return
				end
				text.TextWrapped = false
				if restore ~= nil then
					text.TextTruncate = restore
					restore = nil
				end
			end
			if not text.TextFits then
				text.TextWrapped = true
				boundFor, boundWidth = inputs, width
				if truncates then
					recheck(inputs)
				end
			end
		end)
	end

	local function sideChrome(
		controlSize: Types.Input<Types.ControlSize?>?,
		use: ComposeTypes.Use?,
		glyph: boolean?
	): number
		local package = ctx.read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use)
		local recipe = if package and package.chrome then package.chrome.control else nil
		local insets = if recipe then recipe.contentInsets else nil
		local side = if glyph then 0 else ctx.controlSize(controlSize, "paddingX", use)
		return math.max(side, if insets then insets.left or 0 else 0)
			+ math.max(side, if insets then insets.right or 0 else 0)
	end

	local function wrapCaptions(
		button: GuiObject,
		controlSize: Types.Input<Types.ControlSize?>?,
		across: (ComposeTypes.Use) -> number,
		peers: ((ComposeTypes.Use) -> number)?
	)
		local glyph = button:FindFirstChild("LeadingIcon", true) ~= nil
		local function room(use: ComposeTypes.Use): Vector2
			local chrome = sideChrome(controlSize, use)
				+ if glyph then ctx.controlSize(controlSize, "iconSize", use) + 8 else 0
			return V2.new(math.max(0, across(use) - chrome), math.huge)
		end
		for _, name in { "Title", "Description" } do
			local caption = button:FindFirstChild(name, true)
			if caption and caption:IsA("TextLabel") then
				surfaces.attach(caption, { Host.UISizeConstraint { MaxSize = room } })
				wrapWhenLong(caption, function(use: ComposeTypes.Use): string
					return `{room(use).X}|{if peers then peers(use) else 0}`
				end, button, peers ~= nil)
			end
		end
	end
	local pickerKeys = {
		"selected",
		"options",
		"style",
		"query",
		"placeholder",
		"label",
		"required",
		"multiple",
		"onChanging",
		"onChange",
		"enabled",
		"indicator",
		"axis",
		"sizing",
		"iconOnly",
		"textSize",
		"isPresented",
		"requiredMark",
		"hint",
		"errorText",
		"controlSize",
		"appearance",
		"corners",
		"maxHeight",
		"indicatorPosition",
		"valueAlignment",
	}
	local MENU_WORDS: { [string]: string } = { standard = "standard", contrast = "contrast", utility = "utility" }
	local STRIP_WORDS: { [string]: string } = { filled = "filled", stroke = "stroke", utility = "utility" }
	local function liveIcon<V>(source: ComposeTypes.ReadOnlyValue<Nav.PickerOption<V>>): Types.Input<string>?
		if source:peek().icon == nil then
			return nil
		end
		return function(use: ComposeTypes.Use): string
			return read<<string?>>(use(source).icon, use) or ""
		end
	end
	local function appearanceFor(style: Nav.PickerStyle, word: unknown): string?
		if word == nil then
			return nil
		end
		if style == "menu" or style == "navigationLink" then
			if type(word) ~= "string" or MENU_WORDS[word] == nil then
				error(
					`Facet UI.Picker: a {style} appearance is standard | contrast | utility (got {tostring(word)})`,
					0
				)
			end
		elseif style == "segmented" then
			if type(word) ~= "string" or STRIP_WORDS[word] == nil then
				error(`Facet UI.Picker: a segmented appearance is filled | stroke | utility (got {tostring(word)})`, 0)
			end
		elseif style == "automatic" then
			if type(word) ~= "string" or (MENU_WORDS[word] == nil and STRIP_WORDS[word] == nil) then
				error(
					"Facet UI.Picker: appearance is standard | contrast | utility | filled | stroke "
						.. `(got {tostring(word)})`,
					0
				)
			end
		else
			error(`Facet UI.Picker: a {style} picker takes no appearance`, 0)
		end
		assert(type(word) == "string")
		return word
	end
	return {
		keys = pickerKeys,
		appearanceFor = appearanceFor,
		derive = derive,
		layoutWidth = layoutWidth,
		wrapWhenLong = wrapWhenLong,
		sideChrome = sideChrome,
		wrapCaptions = wrapCaptions,
		liveIcon = liveIcon,
	}
end
