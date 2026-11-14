--!strict
local Audit = require("../../vendor/verify/src/roblox/ui-audit")
local Files = require("./files")
local Json = require("./json")
local Look = require("./look")
local Raster = require("./raster")
local DesignReview = require("./design_review")
local Jpeg = require("./raster/jpeg")

export type Screen = { id: string, device: string, label: string, capture: string?, dump: string? }
export type Target = { path: string, kind: string, card: string? }
export type PacketOptions = {
	out: string,
	brief: string?,
	screens: { Screen },
	rubric: string?,
	rules: boolean?,
	target: Target?,
}
export type Fidelity = {
	kind: string,
	target: string?,
	screen: string?,
	pair: string?,
	squint: string?,
	targetAspect: number?,
	runtimeAspect: number?,
	measures: DesignReview.Report?,
	missing: { string },
}
export type PacketScreen = {
	id: string,
	device: string,
	label: string,
	capture: string?,
	squint: string?,
	blocks: string?,
	design: string?,
	findings: number,
	problem: string?,
}
export type Packet = { out: string, screens: { PacketScreen }, problems: { string }, fidelity: Fidelity? }
export type CaseScore = {
	id: string,
	judged: boolean,
	verdictAgrees: boolean?,
	recall: number?,
	missed: { string },
	extra: { string },
	scoreError: number?,
}
export type Score = {
	cases: { CaseScore },
	judged: number,
	verdictAgreement: number?,
	recall: number?,
	scoreError: number?,
	pairs: number,
	pairAgreement: number?,
	problems: { string },
}

local Critique = {}

Critique.SCHEMA = "facet-critique/1"
Critique.CASE_SCHEMA = "facet-critic-case/1"
Critique.DIMENSIONS = table.freeze({ "lead", "numbers", "visuals", "identity", "economy" })
Critique.TAGS = table.freeze({
	"lead-unclear",
	"competing-leads",
	"numbers-buried",
	"joined-facts",
	"item-without-visual",
	"stat-without-visual",
	"progress-as-text",
	"generic-identity",
	"boxed-everything",
	"stranded-space",
	"zero-wall",
	"commit-unclear",
	"low-contrast",
	"crowded",
	"repeated-facts",
})
Critique.RUBRIC_PATHS = table.freeze({
	"skills/critique-ui/references/rubric.md",
	".agents/skills/critique-ui/references/rubric.md",
})

local TARGET_KINDS: { [string]: string } = {
	specification = "A precise specification: a screenshot, a mock or a concept that the user chose. The runtime matches it. A departure needs the user's word, so name each one.",
	concept = "A concept that the agent chose. It is the committed target: the runtime keeps its composition, its relative scale, its type hierarchy, its materials and the shapes of its controls. A limited, stated improvement is allowed.",
	inspiration = "Directional inspiration: a mood, a genre, a named game or a rough sketch. It calibrates the direction and the craft, and it asks for no imitation. Report what the runtime kept of what makes the reference recognizable; a difference alone is not a fault.",
}
Critique.TARGET_KINDS = table.freeze(TARGET_KINDS)

function Critique.targetKind(kind: string): boolean
	return TARGET_KINDS[kind] ~= nil
end

local SQUINT_WIDTH = 480
local BLOCKS_WIDTH = 960
local PAIR_HEIGHT = 720
local ASPECT_TOLERANCE = 0.05

function Critique.load(path: string): Raster.Image
	local data = buffer.fromstring(Files.read(path))
	local extension = string.lower(Files.extension(path))
	local image = if extension == ".jpg" or extension == ".jpeg" then Jpeg.decode(data) else Raster.Png.decode(data)
	return if image.channels == 3 then image else Raster.Image.convert(image, 3)
end

function Critique.save(path: string, image: Raster.Image)
	Files.makeDirectory(Files.parent(path))
	Files.write(path, buffer.tostring(Raster.Png.encode(image)))
end

local function scaled(image: Raster.Image, width: number): Raster.Image
	if image.width <= width then
		return image
	end
	local height = math.max(1, math.floor(image.height * width / image.width + 0.5))
	return Raster.Resample.resize(image, width, height, "box")
end

function Critique.squint(image: Raster.Image): Raster.Image
	local small = Raster.Image.convert(scaled(image, SQUINT_WIDTH), 1)
	return Raster.Blur.gaussian(small, math.max(2, small.width / 160))
end

function Critique.blocks(image: Raster.Image, dump: Audit.Dump): Raster.Image
	local canvas = Raster.Image.copy(scaled(image, BLOCKS_WIDTH))
	local factor = canvas.width / math.max(1, dump.screen.width)
	for _, element in dump.elements do
		local text = element.text
		if not element.visible or text == nil or text.transparency >= 0.95 then
			continue
		end
		if string.gsub(text.content, "%s+", "") == "" then
			continue
		end
		local rect = element.rect
		local width = math.min(text.bounds.width, rect.width)
		local height = math.min(text.bounds.height, rect.height)
		if width <= 0 or height <= 0 then
			continue
		end
		local x = rect.x
		if text.xAlignment == "Center" then
			x += (rect.width - width) / 2
		elseif text.xAlignment == "Right" then
			x += rect.width - width
		end
		local y = rect.y
		if text.yAlignment == "Center" or text.yAlignment == nil then
			y += (rect.height - height) / 2
		elseif text.yAlignment == "Bottom" then
			y += rect.height - height
		end
		local ink = {
			math.floor(text.color.r * 255 + 0.5),
			math.floor(text.color.g * 255 + 0.5),
			math.floor(text.color.b * 255 + 0.5),
		}
		Raster.Draw.rectangle(canvas, {
			math.floor(x * factor),
			math.floor((y + height * 0.06) * factor),
			math.floor((x + width) * factor),
			math.floor((y + height * 0.96) * factor),
		}, ink)
	end
	return canvas
end

local function beside(left: Raster.Image, right: Raster.Image, height: number): Raster.Image
	local function fit(image: Raster.Image): Raster.Image
		local width = math.max(1, math.floor(image.width * height / image.height + 0.5))
		return Raster.Resample.resize(image, width, height, "box")
	end
	local a, b = fit(left), fit(right)
	local gap = math.max(4, math.floor(height / 30))
	local canvas = Raster.Image.new(
		a.width + b.width + gap,
		height,
		left.channels,
		if left.channels == 1 then { 32 } else { 32, 32, 36 }
	)
	Raster.Image.paste(canvas, a, 0, 0)
	Raster.Image.paste(canvas, b, a.width + gap, 0)
	return canvas
end

type Loaded = { id: string, image: Raster.Image, dump: Audit.Dump? }

local function fidelity(out: string, target: Target, loaded: { Loaded }): (Fidelity, { string })
	local problems: { string } = {}
	local result: Fidelity = { kind = target.kind, missing = {} }
	if TARGET_KINDS[target.kind] == nil then
		table.insert(problems, ("the target kind %s is not specification, concept or inspiration"):format(target.kind))
		return result, problems
	end
	local ok, image = pcall(Critique.load, target.path)
	if not ok then
		table.insert(problems, "the target does not load: " .. tostring(image))
		table.insert(result.missing, "the target image")
		return result, problems
	end
	local folder = Files.join(out, "fidelity")
	Files.makeDirectory(folder)
	local saved = Files.join(folder, "target.png")
	Critique.save(saved, scaled(image, 1600))
	result.target = Files.relative(saved, out)
	local wanted = image.width / image.height
	result.targetAspect = wanted
	local best: Loaded? = nil
	local portrait, short = false, false
	for _, screen in loaded do
		local aspect = screen.image.width / screen.image.height
		portrait = portrait or aspect < 1
		short = short or aspect >= 1.9
		if best == nil or math.abs(aspect - wanted) < math.abs(best.image.width / best.image.height - wanted) then
			best = screen
		end
	end
	if best == nil then
		table.insert(result.missing, "a runtime capture")
		return result, problems
	end
	result.screen = best.id
	local got = best.image.width / best.image.height
	result.runtimeAspect = got
	local pair = Files.join(folder, "pair.png")
	Critique.save(pair, beside(image, best.image, PAIR_HEIGHT))
	result.pair = Files.relative(pair, out)
	local squint = Files.join(folder, "pair-squint.png")
	Critique.save(squint, beside(Critique.squint(image), Critique.squint(best.image), PAIR_HEIGHT / 3))
	result.squint = Files.relative(squint, out)
	if math.abs(got - wanted) > ASPECT_TOLERANCE * wanted then
		table.insert(
			result.missing,
			("a runtime capture at the aspect ratio of the target (%.2f); the nearest is %s at %.2f, so the pair compares parts, not the composition"):format(
				wanted,
				best.id,
				got
			)
		)
	end
	if best.dump ~= nil then
		result.measures = DesignReview.analyze(best.dump)
	else
		table.insert(result.missing, ("an interface dump of %s, so its measures are not computed"):format(best.id))
	end
	if target.card == nil then
		table.insert(result.missing, "the measured card: the author's reading of the target in quantities")
	end
	if target.kind ~= "inspiration" then
		if not portrait then
			table.insert(result.missing, "a capture on a phone in portrait")
		end
		if not short then
			table.insert(result.missing, "a capture on a phone in landscape")
		end
	end
	return result, problems
end

local function fidelityMarkdown(result: Fidelity, card: string?): { string }
	local lines = {
		"## Fidelity to the target",
		"",
		("Kind: **%s**. %s"):format(result.kind, TARGET_KINDS[result.kind] or "Unknown kind."),
		"",
		"Judge fidelity apart from the scores. A coherent screen can have left its target, and a",
		"faithful screen can still fail the rubric. Write the `fidelity` part of verdict.json.",
		"",
	}
	if result.target ~= nil then
		table.insert(lines, ("- Target: `%s`, aspect ratio %.2f"):format(result.target, result.targetAspect or 0))
	end
	if result.pair ~= nil then
		table.insert(
			lines,
			("- Pair at one height, target on the left and `%s` on the right: `%s`"):format(
				result.screen or "?",
				result.pair :: string
			)
		)
		table.insert(lines, ("- The same pair, small and blurred, for what leads: `%s`"):format(result.squint or "?"))
		table.insert(lines, ("- Runtime aspect ratio: %.2f"):format(result.runtimeAspect or 0))
	end
	table.insert(lines, "")
	local report = result.measures
	local measures = if report then report.measures else nil
	local numeral = if measures then measures.numeral else nil
	local control = if measures then measures.control else nil
	local action = if measures then measures.action else nil
	local body = if measures then measures.body else nil
	local scale = if numeral
		then ("Largest numeral %q at %g px, %.1f%% of the screen height%s."):format(
			numeral.content,
			numeral.size,
			numeral.share * 100,
			if body then ("; most text is %g px, a ratio of %.1f"):format(body, numeral.size / body) else ""
		)
		elseif body then ("No numeral. Most text is %g px."):format(body)
		else "Not measured."
	local shapes = if measures
		then ("%d plates%s. The dump has no corner or edge: compare them in the pair."):format(
			measures.plates,
			if control
				then ("; a typical control is %g px high and %.1f times as wide"):format(
					math.floor(control.height + 0.5),
					control.aspect
				)
				else ""
		)
		else "Not measured."
	local lead = if action
		then ("The strongest control is %q at %d%% across and %d%% down, %d%% by %d%% of the screen, %.1f times a typical control, contrast %.1f to the others."):format(
			action.label,
			math.floor(action.x * 100 + 0.5),
			math.floor(action.y * 100 + 0.5),
			math.floor(action.width * 100 + 0.5),
			math.floor(action.height * 100 + 0.5),
			action.scale,
			action.contrast
		)
		else "Not measured."
	for _, line in
		{
			"| Compare | Runtime, measured | Target, read from the pair and the card |",
			"|---|---|---|",
			("| Leading numeral and type scale | %s | The height of its largest numeral as a share of the image height, and that numeral against the reading text. |"):format(
				scale
			),
			("| Panel and control shapes | %s | The number of plates, their corners and edges, and the proportions of a control. |"):format(
				shapes
			),
			("| Primary action: placement and emphasis | %s | Where the main action sits, its share of the screen and what makes it lead. Is the runtime's strongest control that action? |"):format(
				lead
			),
			"",
			"Measured card (the author's reading of the target):",
			"",
		}
	do
		table.insert(lines, line)
	end
	table.insert(lines, card or "(none supplied)")
	table.insert(lines, "")
	table.insert(lines, "Missing evidence:")
	table.insert(lines, "")
	if #result.missing == 0 then
		table.insert(lines, "- none found by the packet; name any state or size that you could not see")
	end
	for _, item in result.missing do
		table.insert(lines, "- " .. item)
	end
	table.insert(lines, "")
	return lines
end

local function rubric(given: string?): (string?, string?)
	local candidates: { string } = if given ~= nil then { given } else table.clone(Critique.RUBRIC_PATHS)
	for _, candidate in candidates do
		if Files.isFile(candidate) then
			return Files.text(candidate), candidate
		end
	end
	return nil, nil
end

local function screenMarkdown(screen: PacketScreen): { string }
	local lines = { ("### %s"):format(screen.id), "" }
	if screen.problem ~= nil then
		table.insert(lines, "Problem: " .. (screen.problem :: string))
		table.insert(lines, "")
	end
	local entries: { { label: string, path: string? } } = {
		{ label = "Capture", path = screen.capture },
		{ label = "Squint render (hierarchy without words)", path = screen.squint },
		{ label = "Text blocks (layout without words)", path = screen.blocks },
		{ label = "Design rules and text outline", path = screen.design },
	}
	for _, entry in entries do
		local path = entry.path
		if path ~= nil then
			table.insert(lines, ("- %s: `%s`"):format(entry.label, path))
		end
	end
	if screen.design ~= nil then
		table.insert(lines, ("- Rule findings: %d"):format(screen.findings))
	else
		table.insert(lines, "- Rule findings: none run (no interface dump); judge from the capture")
	end
	table.insert(lines, "")
	return lines
end

function Critique.packet(options: PacketOptions): Packet
	local out = options.out
	Files.makeDirectory(out)
	local problems: { string } = {}
	local screens: { PacketScreen } = {}
	local loaded: { Loaded } = {}
	for _, screen in options.screens do
		local folder = Files.join(out, "screens", screen.id)
		Files.makeDirectory(folder)
		local entry: PacketScreen = { id = screen.id, device = screen.device, label = screen.label, findings = 0 }
		local dump: Audit.Dump? = nil
		if screen.dump ~= nil then
			local ok, loaded = pcall(Look.load, screen.dump :: string)
			if ok then
				dump = loaded
			else
				entry.problem = "the dump does not load: " .. tostring(loaded)
			end
		end
		if dump ~= nil and options.rules ~= false then
			local report = require("./design_review").analyze(dump)
			entry.findings = #report.findings
			local lines = { report.text, "", "Text outline, top to bottom:" }
			for _, line in Look.outline(dump, 60) do
				table.insert(lines, "  " .. line)
			end
			local design = Files.join(folder, "design.txt")
			Files.write(design, table.concat(lines, "\n") .. "\n")
			Files.write(Files.join(folder, "design.json"), Json.encode(report.findings, { indent = 2 }) .. "\n")
			entry.design = Files.relative(design, out)
		end
		if screen.capture ~= nil then
			local ok, image = pcall(Critique.load, screen.capture :: string)
			if not ok then
				entry.problem = "the capture does not load: " .. tostring(image)
			else
				table.insert(loaded, { id = screen.id, image = image, dump = dump })
				local capture = Files.join(folder, "capture.png")
				Critique.save(capture, scaled(image, 1600))
				entry.capture = Files.relative(capture, out)
				local squint = Files.join(folder, "squint.png")
				Critique.save(squint, Critique.squint(image))
				entry.squint = Files.relative(squint, out)
				if dump ~= nil then
					local blocks = Files.join(folder, "blocks.png")
					Critique.save(blocks, Critique.blocks(image, dump))
					entry.blocks = Files.relative(blocks, out)
				end
			end
		end
		if entry.capture == nil and entry.problem == nil then
			entry.problem = "no capture; the critic cannot judge this screen"
		end
		if entry.problem ~= nil then
			table.insert(problems, ("%s: %s"):format(screen.id, entry.problem :: string))
		end
		table.insert(screens, entry)
	end
	local rubricText, rubricPath = rubric(options.rubric)
	if rubricText == nil then
		table.insert(problems, "the rubric is missing; install the critique-ui skill")
	end
	local target = options.target
	local faithful: Fidelity? = nil
	if target ~= nil then
		local result, found = fidelity(out, target, loaded)
		faithful = result
		for _, problem in found do
			table.insert(problems, problem)
		end
	end
	local lines = {
		"# Critique packet",
		"",
		"You are a fresh reviewer. Judge only what this packet shows. Do not read the",
		"game's code. Write `verdict.json` in this folder in the form the rubric gives.",
		"",
		"## Brief",
		"",
		options.brief or "(no brief given: judge the screens as a game interface)",
		"",
		"## Screens",
		"",
	}
	for _, screen in screens do
		for _, line in screenMarkdown(screen) do
			table.insert(lines, line)
		end
	end
	if faithful ~= nil and target ~= nil then
		for _, line in fidelityMarkdown(faithful, target.card) do
			table.insert(lines, line)
		end
	end
	table.insert(lines, "## Rubric")
	table.insert(lines, "")
	table.insert(lines, rubricText or "(missing)")
	if rubricPath ~= nil then
		table.insert(lines, "")
		table.insert(lines, ("Source: `%s`"):format(rubricPath :: string))
	end
	Files.write(Files.join(out, "PACKET.md"), table.concat(lines, "\n") .. "\n")
	Files.write(
		Files.join(out, "packet.json"),
		Json.encode({ schema = Critique.SCHEMA, brief = options.brief, screens = screens }, { indent = 2 }) .. "\n"
	)
	if faithful ~= nil then
		local report = faithful.measures
		Files.write(Files.join(out, "fidelity.json"), Json.encode({
			schema = Critique.SCHEMA,
			kind = faithful.kind,
			target = faithful.target,
			screen = faithful.screen,
			pair = faithful.pair,
			squint = faithful.squint,
			targetAspect = faithful.targetAspect,
			runtimeAspect = faithful.runtimeAspect,
			measures = if report then report.measures else nil,
			missing = faithful.missing,
		}, { indent = 2 }) .. "\n")
	end
	return { out = out, screens = screens, problems = problems, fidelity = faithful }
end

local function rules(path: string): { [string]: number }
	local counts: { [string]: number } = {}
	if not Files.isFile(path) then
		return counts
	end
	local decoded: Json.Array = Json.asArray(Json.decode(Files.read(path))) or {}
	for _, finding in decoded do
		local rule = Json.stringField(finding, "rule")
		if rule ~= nil then
			counts[rule] = (counts[rule] or 0) + 1
		end
	end
	return counts
end

function Critique.compare(before: string, after: string, out: string): ({ string }, { string })
	Files.makeDirectory(out)
	local lines = { "# Before and after", "" }
	local problems: { string } = {}
	local beforeScreens = Files.join(before, "screens")
	local afterScreens = Files.join(after, "screens")
	if not Files.isDirectory(beforeScreens) or not Files.isDirectory(afterScreens) then
		return { "both folders must be critique packets" }, { "both folders must be critique packets" }
	end
	local shared = 0
	for _, entry in Files.list(beforeScreens) do
		local id = entry.name
		local left = Files.join(beforeScreens, id, "capture.png")
		local right = Files.join(afterScreens, id, "capture.png")
		if not Files.isFile(left) or not Files.isFile(right) then
			continue
		end
		shared += 1
		local a, b = Critique.load(left), Critique.load(right)
		local height = math.min(720, math.max(a.height, b.height))
		local function fit(image: Raster.Image): Raster.Image
			local width = math.max(1, math.floor(image.width * height / image.height + 0.5))
			return Raster.Resample.resize(image, width, height, "box")
		end
		local fa, fb = fit(a), fit(b)
		local gap = 24
		local canvas = Raster.Image.new(fa.width + fb.width + gap, height, 3, { 32, 32, 36 })
		Raster.Image.paste(canvas, fa, 0, 0)
		Raster.Image.paste(canvas, fb, fa.width + gap, 0)
		local path = Files.join(out, id .. ".png")
		Critique.save(path, canvas)
		local was = rules(Files.join(beforeScreens, id, "design.json"))
		local now = rules(Files.join(afterScreens, id, "design.json"))
		local names: { string } = {}
		for name in was do
			table.insert(names, name)
		end
		for name in now do
			if was[name] == nil then
				table.insert(names, name)
			end
		end
		table.sort(names)
		table.insert(lines, ("## %s"):format(id))
		table.insert(lines, "")
		table.insert(lines, ("`%s` (before left, after right)"):format(Files.relative(path, out)))
		table.insert(lines, "")
		if #names == 0 then
			table.insert(lines, "No rule findings before or after.")
		else
			table.insert(lines, "| Rule | Before | After |")
			table.insert(lines, "|---|---|---|")
			for _, name in names do
				table.insert(lines, ("| %s | %d | %d |"):format(name, was[name] or 0, now[name] or 0))
			end
		end
		table.insert(lines, "")
	end
	if shared == 0 then
		table.insert(problems, "the packets share no screen id with a capture")
	end
	Files.write(Files.join(out, "COMPARE.md"), table.concat(lines, "\n") .. "\n")
	return lines, problems
end

local function stringSet(value: unknown): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local items: Json.Array = Json.asArray(value) or {}
	for _, item in items do
		local text = Json.asString(item)
		if text ~= nil then
			set[text] = true
		end
	end
	return set
end

local function criticTags(screen: unknown): { [string]: boolean }
	local tags: { [string]: boolean } = {}
	local fixes: Json.Array = Json.arrayField(screen, "fixes") or {}
	for _, fix in fixes do
		local tag = Json.stringField(fix, "tag")
		if tag ~= nil then
			tags[tag] = true
		end
	end
	return tags
end

local function firstScreen(verdict: unknown): unknown
	local screens = Json.arrayField(verdict, "screens")
	return if screens ~= nil then screens[1] else nil
end

local function overall(screen: unknown): number?
	local scores = Json.objectField(screen, "scores")
	if scores == nil then
		return nil
	end
	local sum = 0
	for _, dimension in Critique.DIMENSIONS do
		local value = Json.numberField(scores, dimension)
		if value == nil then
			return nil
		end
		sum += value
	end
	return sum / #Critique.DIMENSIONS
end

function Critique.safeId(id: string): boolean
	return string.match(id, "^[%w][%w%-_%.]*$") ~= nil and string.find(id, "..", 1, true) == nil
end

function Critique.score(cases: string, run: string): Score
	local result: Score = { cases = {}, judged = 0, pairs = 0, problems = {} }
	if not Files.isDirectory(cases) then
		table.insert(result.problems, cases .. " is not a directory")
		return result
	end
	local agreements, recallSum, recallCount, errorSum, errorCount = 0, 0, 0, 0, 0
	local overalls: { [string]: number } = {}
	local seenIds: { [string]: boolean } = {}
	local preferences: { { better: string, worse: string } } = {}
	for _, entry in Files.list(cases) do
		local folder = Files.join(cases, entry.name)
		local casePath = Files.join(folder, "case.json")
		if not Files.isFile(casePath) then
			continue
		end
		local decoded, case = pcall(Json.decode, Files.read(casePath))
		if not decoded then
			table.insert(result.problems, entry.name .. ": case.json does not parse")
			continue
		end
		local id = Json.stringField(case, "id") or entry.name
		if not Critique.safeId(id) or seenIds[id] then
			table.insert(result.problems, id .. ": the case id is unsafe or repeated")
			continue
		end
		seenIds[id] = true
		local label = Json.objectField(case, "label")
		local worse = Json.stringField(case, "betterThan")
		if worse ~= nil then
			table.insert(preferences, { better = id, worse = worse })
		end
		local scored: CaseScore = { id = id, judged = false, missed = {}, extra = {} }
		local verdictPath = Files.join(run, id, "verdict.json")
		if not Files.isFile(verdictPath) then
			table.insert(result.cases, scored)
			continue
		end
		local ok, verdict = pcall(Json.decode, Files.read(verdictPath))
		local screen = if ok then firstScreen(verdict) else nil
		if screen == nil then
			table.insert(result.problems, id .. ": verdict.json has no screen")
			table.insert(result.cases, scored)
			continue
		end
		scored.judged = true
		result.judged += 1
		local expected = Json.stringField(label, "verdict")
		local given = Json.stringField(screen, "verdict")
		if expected ~= nil and given ~= nil then
			scored.verdictAgrees = expected == given
			if expected == given then
				agreements += 1
			end
		end
		local must = stringSet(Json.field(label, "must"))
		local found = criticTags(screen)
		local hits, total = 0, 0
		for tag in must do
			total += 1
			if found[tag] then
				hits += 1
			else
				table.insert(scored.missed, tag)
			end
		end
		local should = stringSet(Json.field(label, "should"))
		for tag in found do
			if not must[tag] and not should[tag] then
				table.insert(scored.extra, tag)
			end
		end
		table.sort(scored.missed)
		table.sort(scored.extra)
		if total > 0 then
			scored.recall = hits / total
			recallSum += hits / total
			recallCount += 1
		end
		local labelScores = Json.objectField(label, "scores")
		local criticScores = Json.objectField(screen, "scores")
		if labelScores ~= nil and criticScores ~= nil then
			local sum, count = 0, 0
			for _, dimension in Critique.DIMENSIONS do
				local a, b = Json.numberField(labelScores, dimension), Json.numberField(criticScores, dimension)
				if a ~= nil and b ~= nil then
					sum += math.abs(a - b)
					count += 1
				end
			end
			if count > 0 then
				scored.scoreError = sum / count
				errorSum += sum / count
				errorCount += 1
			end
		end
		local value = overall(screen)
		if value ~= nil then
			overalls[id] = value
		end
		table.insert(result.cases, scored)
	end
	table.sort(result.cases, function(a: CaseScore, b: CaseScore): boolean
		return a.id < b.id
	end)
	local withVerdict = 0
	for _, case in result.cases do
		if case.verdictAgrees ~= nil then
			withVerdict += 1
		end
	end
	result.verdictAgreement = if withVerdict > 0 then agreements / withVerdict else nil
	result.recall = if recallCount > 0 then recallSum / recallCount else nil
	result.scoreError = if errorCount > 0 then errorSum / errorCount else nil
	local ordered = 0
	for _, pair in preferences do
		local better, worse = overalls[pair.better], overalls[pair.worse]
		if better ~= nil and worse ~= nil then
			result.pairs += 1
			if better > worse then
				ordered += 1
			elseif better == worse then
				ordered += 0.5
			end
		end
	end
	result.pairAgreement = if result.pairs > 0 then ordered / result.pairs else nil
	return result
end

function Critique.scoreText(score: Score): string
	local function percent(value: number?): string
		return if value == nil then "n/a" else ("%d%%"):format(math.floor(value * 100 + 0.5))
	end
	local lines = {
		("critic calibration: %d of %d case(s) judged"):format(score.judged, #score.cases),
		("  verdict agreement %s, must-fix recall %s, mean score error %s, preferred pairs %s of %d"):format(
			percent(score.verdictAgreement),
			percent(score.recall),
			if score.scoreError == nil then "n/a" else ("%.2f"):format(score.scoreError :: number),
			percent(score.pairAgreement),
			score.pairs
		),
	}
	for _, case in score.cases do
		if not case.judged then
			table.insert(lines, ("  %s: not judged"):format(case.id))
			continue
		end
		local parts = {
			("verdict %s"):format(
				if case.verdictAgrees == nil then "n/a" elseif case.verdictAgrees then "agrees" else "DISAGREES"
			),
			("recall %s"):format(percent(case.recall)),
		}
		if #case.missed > 0 then
			table.insert(parts, "missed " .. table.concat(case.missed, ", "))
		end
		if #case.extra > 0 then
			table.insert(parts, "also raised " .. table.concat(case.extra, ", "))
		end
		table.insert(lines, ("  %s: %s"):format(case.id, table.concat(parts, "; ")))
	end
	for _, problem in score.problems do
		table.insert(lines, "  problem: " .. problem)
	end
	return table.concat(lines, "\n")
end

return table.freeze(Critique)
