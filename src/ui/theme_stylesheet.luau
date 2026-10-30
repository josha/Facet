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
type Tokens = { [string]: Color3? }

local tokenDiffs: { [Tokens]: { [Tokens]: { string } } } = {}
support.weakKeys(tokenDiffs)

local function tokenChanges(before: Tokens, after: Tokens): { string }
	local known = tokenDiffs[before]
	if known == nil then
		local fresh: { [Tokens]: { string } } = {}
		support.weakKeys(fresh)
		known = fresh
		tokenDiffs[before] = fresh
	end
	local cached = known[after]
	if cached == nil then
		local changed: { string } = {}
		for token, value in after do
			if before[token] ~= value then
				table.insert(changed, token)
			end
		end
		known[after] = changed
		cached = changed
	end
	return cached
end

type Changes = { [{ NativeRule }]: { number }? }
local byIdOf: { [{ NativeRule }]: { [string]: NativeRule } } = {}
support.weakKeys(byIdOf)
local changesOf: { [{ NativeRule }]: Changes } = {}
support.weakKeys(changesOf)

local function changesFor(list: { NativeRule }): Changes
	local known = changesOf[list]
	if known == nil then
		local fresh: Changes = {}
		support.weakKeys(fresh)
		known = fresh
		changesOf[list] = fresh
	end
	return known
end

local function changesBetween(before: { NativeRule }, after: { NativeRule }): { number }?
	local known = changesFor(before)
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
	changesFor(after)[before] = changed
	return changed
end

local function indexById(list: { NativeRule }): { [string]: NativeRule }
	local byId = byIdOf[list]
	if byId == nil then
		local made: { [string]: NativeRule } = {}
		for _, definition in list do
			made[definition.id] = definition
		end
		byIdOf[list] = made
		byId = made
	end
	return byId
end

local lastCompiled: { [Engine.RobloxTypes]: { NativeRule } } = {}
support.weakKeys(lastCompiled)

local EASING_STYLES: { [string]: string } = {
	Quad = "Quad",
	Cubic = "Cubic",
	Quart = "Quart",
	Quint = "Quint",
	Sine = "Sine",
	Expo = "Exponential",
	Circ = "Circular",
	Back = "Back",
	Elastic = "Elastic",
	Bounce = "Bounce",
}

local function easingStyle(name: string): (string, string)
	if name == "linear" then
		return "Linear", "Out"
	end
	local direction, rest = "Out", name
	if string.sub(name, 1, 5) == "inOut" then
		direction, rest = "InOut", string.sub(name, 6)
	elseif string.sub(name, 1, 3) == "out" then
		direction, rest = "Out", string.sub(name, 4)
	elseif string.sub(name, 1, 2) == "in" then
		direction, rest = "In", string.sub(name, 3)
	end
	return EASING_STYLES[rest] or "Quad", direction
end

local textRules = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [NativeRule]: { [number]: NativeRule } }
local sizedProperties = (
	setmetatable({}, { __mode = "k" }) :: unknown
) :: { [ThemeTypes.RuleProperties]: { [number]: ThemeTypes.RuleProperties } }
local sizedRules = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [{ NativeRule }]: { number } }
type ByTiming = { [string]: { [string]: string } }
local transitionTables = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [ThemeTypes.RuleProperties]: ByTiming }
type Known = { [ThemeTypes.RuleProperties]: boolean }
local comparisons = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [ThemeTypes.RuleProperties]: Known }
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
	local function withTextSize(definition: NativeRule, offset: number): NativeRule
		local size = definition.properties.TextSize
		if offset == 0 or type(size) ~= "number" then
			return definition
		end
		local byOffset = textRules[definition]
		if byOffset == nil then
			local fresh: { [number]: NativeRule } = {}
			byOffset = fresh
			textRules[definition] = fresh
		end
		local known = assert(byOffset)
		local cached = known[offset]
		if cached then
			return cached
		end
		local base = definition.properties
		local bySize = sizedProperties[base]
		if bySize == nil then
			local fresh: { [number]: ThemeTypes.RuleProperties } = {}
			bySize = fresh
			sizedProperties[base] = fresh
		end
		local resized = assert(bySize)
		local properties = resized[offset]
		if properties == nil then
			local made = table.clone(base)
			made.TextSize = math.max(1, size + offset)
			resized[offset] = made
			properties = made
		end
		local rule = table.clone(definition)
		rule.properties = assert(properties)
		known[offset] = rule
		return rule
	end
	local function sizedIn(rules: { NativeRule }): { number }
		local cached = sizedRules[rules]
		if cached then
			return cached
		end
		local indexes: { number } = {}
		for index, definition in rules do
			if type(definition.properties.TextSize) == "number" then
				table.insert(indexes, index)
			end
		end
		sizedRules[rules] = indexes
		return indexes
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
	type PaintState = "normal" | "press" | "hover" | "pop" | "instant"
	local function timingFor(package: ThemeTypes.ThemePackage, role: PaintState, use: ComposeTypes.Use): TweenInfo
		local explicit = read(settings.transition, use)
		local motion = ((package.metrics or {}) :: { motion: ThemeTypes.MotionMetrics? }).motion
		local normal = if motion and motion.normal then motion.normal else neutral.metrics.motion.normal
		local seconds
		local style = (motion and motion.styles and motion.styles.paint)
			or (neutral.metrics.motion.styles :: { [string]: string }).paint
		local direction = "Out"
		if role == "instant" or snaps(use) or explicit == false then
			seconds = 0
		elseif role == "pop" then
			local durations: { [string]: number } = (motion and motion.durations) or {}
			seconds = durations.regionPop or (neutral.metrics.motion.durations :: { [string]: number }).regionPop
			local easing: { [string]: string } = (motion and motion.easing) or {}
			style, direction =
				easingStyle(easing.present or (neutral.metrics.motion.easing :: { [string]: string }).present)
		elseif explicit ~= nil then
			return explicit
		elseif role == "normal" then
			seconds = normal
		else
			local authored = if motion then motion[role] else nil
			seconds = math.min(authored or neutral.metrics.motion[role], normal)
		end
		local key = `{seconds}|{style}|{direction}`
		local cached: TweenInfo? = defaultTimings[key]
		if cached then
			return cached
		end
		local timing = types.TweenInfo.new(
			seconds,
			((types.Enum.EasingStyle :: unknown) :: { [string]: Enum.EasingStyle })[style],
			((types.Enum.EasingDirection :: unknown) :: { [string]: Enum.EasingDirection })[direction]
		)
		defaultTimings[key] = timing
		return timing
	end
	local function stateOf(selector: string): PaintState
		return if string.find(selector, ".facet-region-pop#Rest", 1, true)
			then "instant"
			elseif string.find(selector, ".facet-region-pop", 1, true) then "pop"
			elseif string.find(selector, ":Press", 1, true) then "press"
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
		indexById(result)
		local previous = lastCompiled[types]
		if previous ~= nil then
			changesBetween(previous, result)
			local before, after = previous[1] and previous[1].tokens, result[1] and result[1].tokens
			if before and after then
				tokenChanges(before, after)
				tokenChanges(after, before)
			end
		end
		lastCompiled[types] = result
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
	local TOKENS: { [PaintState]: string } = {
		normal = "FacetMotionNormal",
		press = "FacetMotionPress",
		hover = "FacetMotionHover",
		pop = "FacetMotionRegionPop",
		instant = "FacetMotionInstant",
	}
	type MountedRule = {
		node: StyleRule,
		priority: number,
		properties: ThemeTypes.RuleProperties?,
		transitions: { [string]: string }?,
		timing: string,
	}
	local mounted: { [string]: MountedRule } = {}
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
			local scales = timing == "FacetMotionRegionPop" or timing == "FacetMotionInstant"
			for property, value in properties do
				if
					typeof(value) == "Color3"
					or (type(value) == "string" and string.sub(value, 1, 12) == "$FacetColor_")
					or string.find(property, "Transparency$")
					or (scales and property == "Scale")
				then
					built[property] = "$" .. timing
				end
			end
			byTiming[timing] = built
			transitions = built
		end
		return transitions
	end
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
	local writtenTokens: { [string]: Color3? }? = nil
	type TimingMemo = { live: { [string]: TweenInfo }?, snapped: { [string]: TweenInfo }? }
	local timingMemo: { [ThemeTypes.ThemePackage]: TimingMemo } = {}
	support.weakKeys(timingMemo)
	local applied: { NativeRule }? = nil
	local appliedArrivals = 0
	local appliedBase: { NativeRule }? = nil
	local appliedOffset = 0
	local appliedPreference = 1
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
	local compiled = Compose.formula(function(use: ComposeTypes.Use)
		local package = forDistance(
			read(packageOrReadable, use) or neutral,
			if read(distant, use) == true then "ten-foot" else "near"
		)
		return { package = package, rules = compiledRules(package, read(settings.theme, use)) }
	end)
	Compose.watch(function(use: ComposeTypes.Use)
		local built = use(compiled)
		local package = built.package
		local current = built.rules
		local colorTokens: { [string]: Color3? } = current[1].tokens or {}
		local hovering = read(settings.hover, use)
		if hovering == nil then
			hovering = read(hover, use)
		end
		if hovering == false then
			current = withoutHover(current)
		end
		local explicit = read(settings.transition, use)
		local snapped = snaps(use)
		local memo = if explicit == nil then timingMemo[package] else nil
		local timings: { [string]: TweenInfo }? = if memo then (if snapped then memo.snapped else memo.live) else nil
		if timings == nil then
			local made: { [string]: TweenInfo } = {}
			for state, token in TOKENS do
				made[token] = timingFor(package, state :: PaintState, use)
			end
			timings = made
			if explicit == nil then
				local entry: TimingMemo = memo or {}
				if snapped then
					entry.snapped = made
				else
					entry.live = made
				end
				timingMemo[package] = entry
			end
		end
		local resolved: { [string]: TweenInfo } = assert(timings)
		for token, timing in resolved do
			if written[token] ~= timing then
				written[token] = timing
				sheet:SetAttribute(token, timing)
			end
		end
		local previousTokens = writtenTokens
		if previousTokens == nil then
			for token, value in colorTokens do
				sheet:SetAttribute(token, value)
			end
		elseif previousTokens ~= colorTokens then
			for _, token in tokenChanges(previousTokens, colorTokens) do
				sheet:SetAttribute(token, colorTokens[token])
			end
		end
		writtenTokens = colorTokens
		local preference = preferenceFor(use)
		local typography = package.metrics.controls.typography or neutral.metrics.controls.typography
		local textChoice = read(preferredTextSize :: Engine.Input<Enum.PreferredTextSize | string>?, use)
		local textOffset = if textChoice ~= nil
			then (textRank(textChoice) - textRank(read(nativeTextSize, use))) * typography.preferredSizeStep
			else 0
		local arrived = use(arrivals)
		local plain = textOffset == 0 and preference >= 1
		if
			appliedBase == current
			and arrived == appliedArrivals
			and preference == appliedPreference
			and textOffset ~= appliedOffset
		then
			local resized = table.clone(definitions)
			for _, index in sizedIn(current) do
				local definition = withTextSize(current[index], textOffset)
				if preference < 1 then
					definition = withPreference(definition, preference)
				end
				resized[definition.id] = definition
				local record = mounted[definition.id]
				if record then
					apply(record, definition)
				end
			end
			definitions = resized
			appliedOffset = textOffset
			applied = if plain then current else nil
			if plain then
				byIdOf[current] = definitions
			end
			return
		end
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
			definitions = indexById(current)
			applied = current
			appliedBase, appliedOffset, appliedPreference = current, textOffset, preference
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
		appliedBase, appliedOffset, appliedPreference = current, textOffset, preference
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
