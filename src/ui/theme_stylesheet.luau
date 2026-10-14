--!strict
local ComposeTypes = require("../vendor/compose/core")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local adaptive = require("./adaptive")
local motionLevels = require("./motion")
local preferredInput = require("./preferred_input")
local support = require("./theme_support")
local RuleKit = require("./theme_rule_kit")

local read, typesFor, deeplyFrozen, sameProperties =
	support.read, support.typesFor, support.deeplyFrozen, support.sameProperties

type NativeRule = RuleKit.NativeRule

return function(
	neutral: ThemeTypes.ThemePackage,
	rulesFor: (ThemeTypes.ThemePackage, string?, Engine.RobloxTypes) -> { NativeRule },
	forDistance: (ThemeTypes.ThemePackage, string?) -> ThemeTypes.ThemePackage,
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
	options: ThemeTypes.ThemeOptions?
): StyleSheet
	local settings: ThemeTypes.ThemeOptions = options or {}
	local types = typesFor(settings)
	local Host = (runtime.constructors :: unknown) :: Engine.Host
	assert(
		((settings :: unknown) :: { [string]: unknown }).reducedMotion == nil,
		'Facet createStyleSheet: the reducedMotion option is gone; set motionLevel = "normal", "limited" or "none"'
	)
	local function snaps(use: ComposeTypes.Use): boolean
		local sources: { unknown } = if settings.motionLevel ~= nil
			then { settings.motionLevel }
			else motionLevels.published(runtime)
		for _, source in sources do
			local chosen = read(source :: Engine.Value<"normal" | "limited" | "none">, use)
			if chosen ~= nil and motionLevels.resolve(chosen, false) == "none" then
				return true
			end
		end
		return false
	end
	local preferredTextSize = ((runtime :: unknown) :: { [string]: unknown }).FacetTextPreference
	local nativeTextSize: Engine.Value<unknown>? = nil
	if preferredTextSize ~= nil then
		local globals = getfenv(0)
		local gui = globals.game and globals.game:GetService("GuiService")
		if gui then
			local source = Compose.cell(gui.PreferredTextSize)
			nativeTextSize = source
			local connection = gui:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
				source:set(gui.PreferredTextSize)
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
	end
	local function textRank(value: unknown): number
		local name = if typeof(value) == "EnumItem" then (value :: EnumItem).Name else value
		return ({ Medium = 0, Large = 1, Larger = 2, Largest = 3 } :: { [unknown]: number })[name] or 0
	end
	local textRules = (
		setmetatable({}, { __mode = "k" }) :: unknown
	) :: { [NativeRule]: { offset: number, rule: NativeRule } }
	local function withTextSize(definition: NativeRule, offset: number): NativeRule
		local size = definition.properties.TextSize
		if offset == 0 or type(size) ~= "number" then
			return definition
		end
		local cached = textRules[definition]
		if cached and cached.offset == offset then
			return cached.rule
		end
		local rule = table.clone(definition)
		rule.properties = table.clone(definition.properties)
		rule.properties.TextSize = math.max(1, size + offset)
		textRules[definition] = { offset = offset, rule = rule }
		return rule
	end
	local preferredTransparency = settings.preferredTransparency
	if preferredTransparency == nil then
		local globals = getfenv(0)
		local gui = globals.game and globals.game:GetService("GuiService")
		if gui then
			local source = Compose.cell(gui.PreferredTransparency)
			preferredTransparency = source
			local connection = gui:GetPropertyChangedSignal("PreferredTransparency"):Connect(function()
				source:set(gui.PreferredTransparency)
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
	end
	local hover: Engine.Value<boolean>? = nil
	do
		local globals = getfenv(0)
		local input = globals.game and globals.game:GetService("UserInputService")
		if input then
			local held = input.PreferredInput
			local stopNudges: (() -> ())? = nil
			local refresh: () -> ()
			local function pointing(): boolean
				local current = input.PreferredInput
				if preferredInput.withheld(input, current, types.Enum.PreferredInput.KeyboardAndMouse) then
					stopNudges = stopNudges or preferredInput.nudges(input, types.Enum, refresh)
				else
					held = current
					if stopNudges then
						stopNudges()
						stopNudges = nil
					end
				end
				return held ~= types.Enum.PreferredInput.Touch
			end
			local source = Compose.cell(false)
			hover = source
			refresh = function()
				source:set(pointing())
			end
			refresh()
			local connection = input:GetPropertyChangedSignal("PreferredInput"):Connect(refresh)
			Compose.cleanup(function()
				connection:Disconnect()
				if stopNudges then
					stopNudges()
				end
			end)
		end
	end
	local distant: Engine.Value<boolean>? = settings.tenFoot
	if distant == nil then
		local globals = getfenv(0)
		local gui = globals.game and globals.game:GetService("GuiService")
		local input = globals.game and globals.game:GetService("UserInputService")
		if gui and input then
			local interface = false
			pcall(function()
				interface = gui:IsTenFootInterface()
			end)
			local function sample(): boolean
				return adaptive.isTenFoot({
					tenFootInterface = interface,
					displaySize = if typeof(gui.ViewportDisplaySize) == "EnumItem"
						then gui.ViewportDisplaySize.Name
						else nil,
					mouse = input.MouseEnabled,
					touch = input.TouchEnabled,
				})
			end
			local source = Compose.cell(sample())
			distant = source
			local connections = {
				gui:GetPropertyChangedSignal("ViewportDisplaySize"):Connect(function()
					source:set(sample())
				end),
				input:GetPropertyChangedSignal("MouseEnabled"):Connect(function()
					source:set(sample())
				end),
				input:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
					source:set(sample())
				end),
			}
			Compose.cleanup(function()
				for _, connection in connections do
					connection:Disconnect()
				end
			end)
		end
	end
	local hoverless = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [{ NativeRule }]: { NativeRule } }
	local function withoutHover(rules: { NativeRule }): { NativeRule }
		local cached = hoverless[rules]
		if cached then
			return cached
		end
		local kept: { NativeRule } = {}
		for _, definition in rules do
			if not string.find(definition.selector, ":Hover", 1, true) then
				table.insert(kept, definition)
			end
		end
		hoverless[rules] = kept
		return kept
	end
	local function preferenceFor(use: ComposeTypes.Use): number
		local value = read(preferredTransparency, use)
		return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
	end
	local defaultTimings: { [string]: TweenInfo } = {}
	type PaintState = "normal" | "press" | "hover"
	local function timingFor(package: ThemeTypes.ThemePackage, role: PaintState, use: ComposeTypes.Use): TweenInfo
		local explicit = read(settings.transition, use)
		local motion = ((package.metrics or {}) :: { motion: ThemeTypes.MotionMetrics? }).motion
		local normal = if motion and motion.normal then motion.normal else neutral.metrics.motion.normal
		local seconds
		if snaps(use) or explicit == false then
			seconds = 0
		elseif explicit ~= nil then
			return explicit :: TweenInfo
		elseif role == "normal" then
			seconds = normal
		else
			local authored = if motion then motion[role] else nil
			seconds = math.min(authored or neutral.metrics.motion[role], normal)
		end
		local style = (motion and motion.styles and motion.styles.paint)
			or (neutral.metrics.motion.styles :: { [string]: string }).paint
		local key = `{seconds}|{style}`
		local cached: TweenInfo? = defaultTimings[key]
		if cached then
			return cached
		end
		local timing = types.TweenInfo.new(
			seconds,
			((types.Enum.EasingStyle :: unknown) :: { [string]: Enum.EasingStyle })[style],
			types.Enum.EasingDirection.Out
		)
		defaultTimings[key] = timing
		return timing
	end
	local function stateOf(selector: string): PaintState
		return if string.find(selector, ":Press", 1, true)
			then "press"
			elseif string.find(selector, ":Hover", 1, true) then "hover"
			else "normal"
	end
	local definitions: { [string]: NativeRule } = {}
	type CompiledRules = {
		package: ThemeTypes.ThemePackage,
		palette: string?,
		rules: { NativeRule },
	}
	local compiled: { CompiledRules } = {}
	local function compiledRules(package: ThemeTypes.ThemePackage, palette: string?): { NativeRule }
		for index, cached in compiled do
			if cached.package == package and cached.palette == palette then
				if index > 1 then
					table.remove(compiled, index)
					table.insert(compiled, 1, cached)
				end
				return cached.rules
			end
		end
		local result = rulesFor(package, palette, types)
		if deeplyFrozen(package, {}) then
			for _, definition in result do
				local previous = definitions[definition.id]
				if previous and sameProperties(previous.properties, definition.properties) then
					definition.properties = previous.properties
				end
			end
			table.insert(compiled, 1, { package = package, palette = palette, rules = result })
			if #compiled > 2 then
				table.remove(compiled)
			end
		end
		return result
	end
	local scaled = setmetatable(
		{} :: { [NativeRule]: { preference: number, properties: ThemeTypes.RuleProperties } },
		{ __mode = "k" }
	)
	local function withPreference(definition: NativeRule, preference: number): NativeRule
		local translucent = definition.properties.BackgroundTransparency
		if
			preference >= 1
			or (definition.selector ~= ".facet-scrim" and definition.selector ~= ".facet-scrim.facet-radial-scrim")
			or type(translucent) ~= "number"
			or translucent <= 0
			or translucent >= 1
		then
			return definition
		end
		local cached = scaled[definition]
		if cached == nil or cached.preference ~= preference then
			local properties = table.clone(definition.properties)
			properties.BackgroundTransparency = translucent * preference
			cached = { preference = preference, properties = properties }
			scaled[definition] = cached
		end
		return {
			id = definition.id,
			selector = definition.selector,
			priority = definition.priority,
			properties = cached.properties,
		}
	end
	local ids = Compose.cell({} :: { string })
	local TOKENS: { [PaintState]: string } =
		{ normal = "FacetMotionNormal", press = "FacetMotionPress", hover = "FacetMotionHover" }
	type MountedRule = {
		node: StyleRule,
		priority: number,
		properties: ThemeTypes.RuleProperties?,
		transitions: { [string]: string }?,
		timing: string?,
	}
	local mounted: { [string]: MountedRule } = {}
	type ByTiming = { [string]: { [string]: string } }
	local transitionTables = (
		setmetatable({} :: { [ThemeTypes.RuleProperties]: ByTiming }, { __mode = "k" }) :: unknown
	) :: { [ThemeTypes.RuleProperties]: ByTiming }
	local function transitionsFor(properties: ThemeTypes.RuleProperties, timing: string): { [string]: string }
		local byTiming = transitionTables[properties]
		if byTiming == nil then
			local fresh = (setmetatable({} :: ByTiming, { __mode = "k" }) :: unknown) :: ByTiming
			byTiming = fresh
			transitionTables[properties] = fresh
		end
		local transitions = byTiming[timing]
		if transitions == nil then
			local built: { [string]: string } = {}
			for property, value in properties do
				if typeof(value) == "Color3" or string.find(property, "Transparency$") then
					built[property] = "$" .. timing
				end
			end
			byTiming[timing] = built
			transitions = built
		end
		return transitions :: { [string]: string }
	end
	type Known = { [ThemeTypes.RuleProperties]: boolean }
	local comparisons = (
		setmetatable({} :: { [ThemeTypes.RuleProperties]: Known }, { __mode = "k" }) :: unknown
	) :: { [ThemeTypes.RuleProperties]: Known }
	local function sameRuleProperties(left: ThemeTypes.RuleProperties, right: ThemeTypes.RuleProperties): boolean
		local known = comparisons[left]
		if known == nil then
			known = (setmetatable({} :: Known, { __mode = "k" }) :: unknown) :: Known
			comparisons[left] = known
		end
		local same = known[right]
		if same == nil then
			same = sameProperties(left, right)
			known[right] = same
		end
		return same :: boolean
	end
	local function apply(record: MountedRule, definition: NativeRule, timing: string)
		if record.priority ~= definition.priority then
			record.node.Priority = definition.priority
			record.priority = definition.priority
		end
		local properties = definition.properties
		local propertiesChanged = record.properties == nil
			or (record.properties ~= properties and not sameRuleProperties(record.properties, properties))
		if not propertiesChanged and record.timing == timing then
			return
		end
		local transitions = transitionsFor(properties, timing)
		local previous = record.transitions
		local timingChanged = previous ~= transitions and (previous == nil or not sameProperties(previous, transitions))
		if timingChanged then
			record.node:SetPropertyTransitions(transitions)
			record.transitions = transitions
		end
		if propertiesChanged or timingChanged then
			record.node:SetProperties(properties)
			record.properties = properties
		end
		record.timing = timing
	end
	local written: { [string]: TweenInfo } = {}
	local sheet = Host.StyleSheet(settings.name or "FacetTheme")({
		Compose.keyed({
			from = ids,
			render = function(current: ComposeTypes.Readable<string>)
				local id = current:peek()
				local initial = definitions[id]
				local node = Host.StyleRule({
					Name = initial.id,
					Selector = initial.selector,
					Priority = initial.priority,
				})
				local record: MountedRule = { node = node, priority = initial.priority }
				mounted[id] = record
				apply(record, initial, TOKENS[stateOf(initial.selector)])
				Compose.cleanup(function()
					if mounted[id] == record then
						mounted[id] = nil
					end
				end)
				return node
			end,
		}),
	})
	Compose.watch(function(use: ComposeTypes.Use)
		local package = forDistance(
			read(packageOrReadable, use) or neutral,
			if read(distant, use) == true then "ten-foot" else "near"
		)
		local current = compiledRules(package, read(settings.theme, use))
		local hovering = read(settings.hover, use)
		if hovering == nil then
			hovering = read(hover, use)
		end
		if hovering == false then
			current = withoutHover(current)
		end
		for state, token in TOKENS do
			local timing = timingFor(package, state :: PaintState, use)
			written[token] = timing
			sheet:SetAttribute(token, timing)
		end
		local preference = preferenceFor(use)
		local typography = package.metrics.controls.typography or neutral.metrics.controls.typography
		local textChoice = read(preferredTextSize :: Engine.Value<Enum.PreferredTextSize | string>?, use)
		local textOffset = if textChoice ~= nil
			then (textRank(textChoice) - textRank(read(nativeTextSize, use))) * typography.preferredSizeStep
			else 0
		local previousIds = ids:peek()
		local structureChanged = #previousIds ~= #current
		table.clear(definitions)
		for index, compiledDefinition in current do
			local definition = withPreference(withTextSize(compiledDefinition, textOffset), preference)
			definitions[definition.id] = definition
			if previousIds[index] ~= definition.id then
				structureChanged = true
			end
			local record = mounted[definition.id]
			if record then
				apply(record, definition, TOKENS[stateOf(definition.selector)])
			end
		end
		if structureChanged then
			local nextIds = {}
			for _, definition in current do
				table.insert(nextIds, definition.id)
			end
			ids:set(nextIds)
		end
	end)
	for _, token in TOKENS do
		local connection = sheet:GetAttributeChangedSignal(token):Connect(function()
			local timing: unknown = written[token]
			if timing ~= nil and sheet:GetAttribute(token) ~= timing then
				sheet:SetAttribute(token, timing)
			end
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	local warmed = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [ThemeTypes.ThemePackage]: boolean }
	Compose.watch(function(use: ComposeTypes.Use)
		local package = read(packageOrReadable, use)
		if package == nil or warmed[package] then
			return
		end
		warmed[package] = true
		local content: { string } = {}
		for _, asset in pairs(package.assets or {}) do
			local id = asset.content or asset.contentId
			if type(id) == "string" and id ~= "" and asset.preload ~= "lazy" then
				table.insert(content, id)
			end
		end
		local provider: ContentProvider? = settings.contentProvider
		if provider == nil and #content > 0 then
			local globals = getfenv(0)
			provider = globals.game and globals.game:GetService("ContentProvider")
		end
		if provider and #content > 0 then
			if task then
				task.spawn(provider.PreloadAsync, provider, content)
			else
				provider:PreloadAsync(content)
			end
		end
	end)
	return sheet
end
