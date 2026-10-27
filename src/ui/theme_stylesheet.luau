--!strict
local ComposeTypes = require("../vendor/compose/core")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local adaptive = require("./adaptive")
local motionLevels = require("./motion")
local preferredInput = require("./preferred_input")
local support = require("./theme_support")
local RuleKit = require("./theme_rule_kit")

local read, typesFor, sameProperties = support.read, support.typesFor, support.sameProperties

type NativeRule = RuleKit.NativeRule

local compiledFor = setmetatable(
	{} :: { [Engine.RobloxTypes]: { [ThemeTypes.ThemePackage]: { [string]: { NativeRule } } } },
	{ __mode = "k" }
)
local internedFor =
	setmetatable({} :: { [Engine.RobloxTypes]: { [string]: ThemeTypes.RuleProperties } }, { __mode = "k" })

return function(
	neutral: ThemeTypes.ThemePackage,
	rulesFor: (ThemeTypes.ThemePackage, string?, Engine.RobloxTypes) -> { NativeRule },
	forDistance: (ThemeTypes.ThemePackage, string?) -> ThemeTypes.ThemePackage,
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	packageOrReadable: Engine.Input<ThemeTypes.ThemePackage>?,
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
			local chosen = read(source :: Engine.Input<("normal" | "limited" | "none")?>, use)
			if chosen ~= nil and motionLevels.resolve(chosen, false) == "none" then
				return true
			end
		end
		return false
	end
	local preferredTextSize = ((runtime :: unknown) :: { [string]: unknown }).FacetTextPreference
	local nativeTextSize: Engine.Input<unknown>? = nil
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
		local name = if typeof(value) == "EnumItem" then value.Name else value
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
	local hover: Engine.Input<boolean>? = nil
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
	local distant: Engine.Input<boolean>? = settings.tenFoot
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
	local hoverless = setmetatable({} :: { [{ NativeRule }]: { NativeRule } }, { __mode = "k" })
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
			return explicit
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
	local tagService: CollectionService? = settings.collectionService
	if tagService == nil then
		local globals = getfenv(0)
		tagService = globals.game and globals.game:GetService("CollectionService")
	end
	local present: { [string]: boolean } = {}
	local awaited: { [string]: RBXScriptConnection } = {}
	local arrivals = Compose.cell(0)
	local alternativesOf: { [string]: { { string } } } = {}
	local function classesIn(selector: string): { { string } }
		local cached = alternativesOf[selector]
		if cached then
			return cached
		end
		local alternatives: { { string } } = {}
		for _, part in string.split(selector, ",") do
			local classes: { string } = {}
			for class in string.gmatch(part, "%.([%w_%-]+)") do
				table.insert(classes, class)
			end
			table.insert(alternatives, classes)
		end
		alternativesOf[selector] = alternatives
		return alternatives
	end
	local function inUse(service: CollectionService, class: string): boolean
		if present[class] then
			return true
		end
		if not awaited[class] then
			if #service:GetTagged(class) > 0 then
				present[class] = true
				return true
			end
			awaited[class] = service:GetInstanceAddedSignal(class):Connect(function()
				local connection = awaited[class]
				if connection and not present[class] then
					present[class] = true
					connection:Disconnect()
					arrivals:set(arrivals:peek() + 1)
				end
			end)
		end
		return false
	end
	local function wanted(selector: string): boolean
		local service = tagService
		if service == nil then
			return true
		end
		for _, classes in classesIn(selector) do
			local complete = true
			for _, class in classes do
				if not inUse(service, class) then
					complete = false
					break
				end
			end
			if complete then
				return true
			end
		end
		return false
	end
	Compose.cleanup(function()
		for _, connection in awaited do
			connection:Disconnect()
		end
		table.clear(awaited)
	end)
	local definitions: { [string]: NativeRule } = {}
	local byIdOf = setmetatable({} :: { [{ NativeRule }]: { [string]: NativeRule } }, { __mode = "k" })
	type Changes = { [{ NativeRule }]: { number }? }
	local changesOf = setmetatable({} :: { [{ NativeRule }]: Changes }, { __mode = "k" })
	local function changesBetween(before: { NativeRule }, after: { NativeRule }): { number }?
		local known = changesOf[before]
		if known == nil then
			local fresh: Changes = {}
			support.weakKeys(fresh)
			known = fresh
			changesOf[before] = known
		end
		local cached = known[after]
		if cached ~= nil or #before ~= #after then
			return cached
		end
		local changed: { number } = {}
		for index, definition in after do
			local previous = before[index]
			if previous.id ~= definition.id or previous.selector ~= definition.selector then
				return nil
			end
			if previous.priority ~= definition.priority or previous.properties ~= definition.properties then
				table.insert(changed, index)
			end
		end
		known[after] = changed
		return changed
	end
	local function compiledRules(package: ThemeTypes.ThemePackage, palette: string?): { NativeRule }
		if not support.sealed(package) then
			return rulesFor(package, palette, types)
		end
		local byPackage = compiledFor[types]
		if byPackage == nil then
			local fresh: { [ThemeTypes.ThemePackage]: { [string]: { NativeRule } } } = {}
			support.weakKeys(fresh)
			byPackage = fresh
			compiledFor[types] = byPackage
		end
		local byPalette = byPackage[package]
		if byPalette == nil then
			byPalette = {}
			byPackage[package] = byPalette
		end
		local key = palette or ""
		local cached = byPalette[key]
		if cached then
			return cached
		end
		local result = rulesFor(package, palette, types)
		local interned = internedFor[types]
		if interned == nil then
			interned = {}
			internedFor[types] = interned
		end
		for _, definition in result do
			local previous = interned[definition.id]
			if previous and sameProperties(previous, definition.properties) then
				definition.properties = previous
			else
				interned[definition.id] = definition.properties
			end
		end
		byPalette[key] = result
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
		timing: string,
	}
	local mounted: { [string]: MountedRule } = {}
	type ByTiming = { [string]: { [string]: string } }
	local transitionTables = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [ThemeTypes.RuleProperties]: ByTiming }
	local function transitionsFor(properties: ThemeTypes.RuleProperties, timing: string): { [string]: string }
		local byTiming = transitionTables[properties]
		if byTiming == nil then
			local fresh = (setmetatable({}, { __mode = "k" }) :: unknown) :: ByTiming
			byTiming = fresh
			transitionTables[properties] = fresh
		end
		local transitions = byTiming[timing]
		if transitions == nil then
			local built: { [string]: string } = {}
			for property, value in properties do
				if
					typeof(value) == "Color3"
					or (type(value) == "string" and string.sub(value, 1, 12) == "$FacetColor_")
					or string.find(property, "Transparency$")
				then
					built[property] = "$" .. timing
				end
			end
			byTiming[timing] = built
			transitions = built
		end
		return transitions
	end
	type Known = { [ThemeTypes.RuleProperties]: boolean }
	local comparisons = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [ThemeTypes.RuleProperties]: Known }
	local function sameRuleProperties(left: ThemeTypes.RuleProperties, right: ThemeTypes.RuleProperties): boolean
		local known = comparisons[left]
		if known == nil then
			known = (setmetatable({}, { __mode = "k" }) :: unknown) :: Known
			comparisons[left] = known
		end
		local same = known[right]
		if same == nil then
			same = sameProperties(left, right)
			known[right] = same
		end
		return same
	end
	local function apply(record: MountedRule, definition: NativeRule)
		if record.priority ~= definition.priority then
			record.node.Priority = definition.priority
			record.priority = definition.priority
		end
		local properties = definition.properties
		local propertiesChanged = record.properties == nil
			or (record.properties ~= properties and not sameRuleProperties(record.properties, properties))
		if not propertiesChanged then
			return
		end
		local transitions = transitionsFor(properties, record.timing)
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
	end
	local written: { [string]: TweenInfo } = {}
	local colors: { [string]: Color3? } = {}
	local applied: { NativeRule }? = nil
	local appliedArrivals = 0
	local initialIds: { [string]: boolean }? = nil
	local sheet = Host.StyleSheet(settings.name or "FacetTheme")({
		Compose.keyed({
			from = ids,
			render = function(current: ComposeTypes.ReadOnlyValue<string>)
				local id = current:peek()
				local initial = definitions[id]
				local node = Host.StyleRule({
					Name = initial.id,
					Selector = initial.selector,
					Priority = initial.priority,
				})
				local record: MountedRule =
					{ node = node, priority = initial.priority, timing = TOKENS[stateOf(initial.selector)] }
				mounted[id] = record
				local known = initialIds
				if known ~= nil and not known[id] and task then
					node:SetProperties(initial.properties)
					task.defer(function()
						if mounted[id] == record then
							apply(record, definitions[id] or initial)
						end
					end)
				else
					apply(record, initial)
				end
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
		local colorTokens: { [string]: Color3? } = current[1].tokens or {}
		local hovering = read(settings.hover, use)
		if hovering == nil then
			hovering = read(hover, use)
		end
		if hovering == false then
			current = withoutHover(current)
		end
		for state, token in TOKENS do
			local timing = timingFor(package, state :: PaintState, use)
			if written[token] ~= timing then
				written[token] = timing
				sheet:SetAttribute(token, timing)
			end
		end
		for token, value in colorTokens do
			if colors[token] ~= value then
				colors[token] = value
				sheet:SetAttribute(token, value)
			end
		end
		local preference = preferenceFor(use)
		local typography = package.metrics.controls.typography or neutral.metrics.controls.typography
		local textChoice = read(preferredTextSize :: Engine.Input<Enum.PreferredTextSize | string>?, use)
		local textOffset = if textChoice ~= nil
			then (textRank(textChoice) - textRank(read(nativeTextSize, use))) * typography.preferredSizeStep
			else 0
		local arrived = use(arrivals)
		local plain = textOffset == 0 and preference >= 1
		local changes = if plain
				and applied ~= nil
				and arrived == appliedArrivals
			then changesBetween(applied, current)
			else nil
		if changes then
			for _, index in changes do
				local definition = current[index]
				local record = mounted[definition.id]
				if record then
					apply(record, definition)
				end
			end
			local byId = byIdOf[current]
			if byId == nil then
				byId = {}
				for _, definition in current do
					byId[definition.id] = definition
				end
				byIdOf[current] = byId
			end
			definitions = byId
			applied = current
			return
		end
		local previousIds = ids:peek()
		local nextIds: { string } = {}
		definitions = {}
		for _, compiledDefinition in current do
			local definition = if textOffset ~= 0
				then withTextSize(compiledDefinition, textOffset)
				else compiledDefinition
			if preference < 1 then
				definition = withPreference(definition, preference)
			end
			definitions[definition.id] = definition
			if wanted(definition.selector) then
				table.insert(nextIds, definition.id)
				local record = mounted[definition.id]
				if record then
					apply(record, definition)
				end
			end
		end
		local structureChanged = #previousIds ~= #nextIds
		if not structureChanged then
			for index, id in nextIds do
				if previousIds[index] ~= id then
					structureChanged = true
					break
				end
			end
		end
		if initialIds == nil then
			local first: { [string]: boolean } = {}
			for _, id in nextIds do
				first[id] = true
			end
			initialIds = first
		end
		if structureChanged then
			ids:set(nextIds)
		end
		applied = if plain then current else nil
		appliedArrivals = arrived
		if plain then
			byIdOf[current] = definitions
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
	local warmed = setmetatable({} :: { [ThemeTypes.ThemePackage]: boolean }, { __mode = "k" })
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
