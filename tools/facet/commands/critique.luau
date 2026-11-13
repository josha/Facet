--!strict
local Verify = require("../../vendor/verify/src/core")

local json = require("@std/json")
local Cli = require("../lib/cli")
local Critique = require("../lib/critique")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Look = require("../lib/look")
local Raster = require("../lib/raster")

local USAGE = [[usage: lute run tools/facet critique [--device ID]... [--tap TEXT]... [--wait SECONDS]
                                     [--project FILE] [--brief FILE] [--out DIR] [--keep]
                                     [--target FILE --target-kind KIND] [--card FILE]
       lute run tools/facet critique --capture FILE [--dump FILE] [--device ID] [--label NAME]
                                     [--brief FILE] [--out DIR]
                                     [--target FILE --target-kind KIND] [--card FILE]
       lute run tools/facet critique cases --cases DIR [--out DIR]
       lute run tools/facet critique compare BEFORE AFTER [--out DIR]
       lute run tools/facet critique score --cases DIR --run DIR

Writes a critique packet: the evidence that a fresh reviewer needs to judge how
a screen looks. The critique-ui skill gives that reviewer to a separate agent,
which writes verdict.json in the packet folder.

For each screen the packet holds:

  capture.png    the screenshot
  squint.png     a small blurred gray copy: what leads when words do not read
  blocks.png     each text replaced by a block of its color: layout without words
  design.txt     the design rules (see lute run tools/facet docs Review) and a
                 text outline from the interface dump
  design.json    the rule findings

PACKET.md lists the screens, the brief and the rubric. A packet does not judge.

Without --capture, critique plays the place on each device like audit and
preview. The default checks all registered devices, including small and notched
phones in both orientations. Use --device to request a focused capture.

  --capture FILE  Use a saved PNG or JPEG instead of playing the place. Add
                  --dump for the rules and the blocks render. A Studio-only
                  author can save a capture and run Facet.review in the Client.
  --brief FILE    A short description of the game and the player's task.
  --target FILE   The image that the screen was built to: a reference, a chosen
                  concept or an inspiration. The packet then has a fidelity
                  part: the target beside the capture nearest to its aspect
                  ratio at one height (fidelity/pair.png), the same pair small
                  and blurred, the runtime's measures (the largest numeral as a
                  share of the screen, the plates and controls, the strongest
                  control and its place) and the evidence that is missing.
                  The reviewer judges fidelity apart from the rubric scores.
  --target-kind   specification (the user's precise reference: match it),
                  concept (the agent chose it: keep its composition, scale,
                  type, materials and control shapes) or inspiration (a
                  direction: no imitation is asked).
  --card FILE     The measured card: the author's reading of the target in
                  quantities. The packet shows it beside the measures.
  --out DIR       The packet folder. The default is artifacts/facet-critique.

cases builds one blind packet for each calibration case under DIR (each folder
holds case.json and its capture). The labels stay out of the packet. Add
--no-rules to leave out design.txt, so the score measures the reviewer's own eye.
compare writes side-by-side captures and the change in rule findings for each
screen that two packets share.
score compares the verdict.json in each case packet with the case labels and
prints verdict agreement, must-fix recall and the order of preferred pairs.]]

local function brief(invocation: Cli.Invocation): string?
	local path = Cli.flag(invocation, "brief")
	if path == nil then
		return nil
	end
	return (string.gsub(Files.text(path), "%s+$", ""))
end

local function report(packet: Critique.Packet): string
	local lines = { ("critique packet: %s"):format(Files.join(packet.out, "PACKET.md")) }
	for _, screen in packet.screens do
		table.insert(
			lines,
			("  %s: %s%s"):format(
				screen.id,
				if screen.design ~= nil
					then ("%d rule finding(s)"):format(screen.findings)
					else "no dump, rules not run",
				if screen.problem then "; " .. (screen.problem :: string) else ""
			)
		)
	end
	local fidelity = packet.fidelity
	if fidelity ~= nil then
		table.insert(
			lines,
			("  fidelity (%s): %s; %d item(s) of evidence missing"):format(
				fidelity.kind,
				if fidelity.pair then Files.join(packet.out, fidelity.pair :: string) else "no pair",
				#fidelity.missing
			)
		)
		for _, item in fidelity.missing do
			table.insert(lines, "    missing: " .. item)
		end
	end
	for _, problem in packet.problems do
		table.insert(lines, "  problem: " .. problem)
	end
	table.insert(lines, "Give PACKET.md to a fresh reviewer; it writes verdict.json in the packet folder.")
	return table.concat(lines, "\n")
end

local function slug(text: string): string
	return (string.gsub(string.lower(text), "[^%w]+", "-"))
end

local function cases(invocation: Cli.Invocation): number
	local root = Cli.flag(invocation, "cases")
	if root == nil or not Files.isDirectory(root) then
		print("facet critique cases: give --cases DIR with one folder for each case")
		return 2
	end
	local out = Cli.flag(invocation, "out") or "artifacts/facet-critique-cases"
	local lines: { string } = {}
	local failed = false
	for _, entry in Files.list(root) do
		local folder = Files.join(root, entry.name)
		local casePath = Files.join(folder, "case.json")
		if not Files.isFile(casePath) then
			continue
		end
		local decoded, case = pcall(Json.decode, Files.read(casePath))
		local id = if decoded then Json.stringField(case, "id") or entry.name else entry.name
		if not decoded or not Critique.safeId(id) then
			table.insert(
				lines,
				("critique cases: %s: skipped; case.json does not parse or its id is unsafe"):format(entry.name)
			)
			failed = true
			continue
		end
		local capture = Json.stringField(case, "capture")
		local dump = Json.stringField(case, "dump")
		local device = Json.stringField(case, "device") or "desktop"
		local packet = Critique.packet({
			out = Files.join(out, id),
			brief = Json.stringField(case, "brief"),
			rules = not Cli.switch(invocation, "no-rules"),
			screens = {
				{
					id = id,
					device = device,
					label = id,
					capture = if capture then Files.join(folder, capture) else nil,
					dump = if dump then Files.join(folder, dump) else nil,
				},
			},
		})
		failed = failed or #packet.problems > 0
		table.insert(lines, report(packet))
	end
	if #lines == 0 then
		print("facet critique cases: no case.json under " .. root)
		return 1
	end
	print(table.concat(lines, "\n\n"))
	return if failed then 1 else 0
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, {
		"device",
		"tap",
		"wait",
		"project",
		"out",
		"keep",
		"capture",
		"dump",
		"label",
		"brief",
		"cases",
		"run",
		"no-rules",
		"target",
		"target-kind",
		"card",
	})
	if unknown ~= nil then
		print("facet critique: unknown flags " .. unknown)
		print(USAGE)
		return 2
	end
	local mode = invocation.positional[1]
	if mode == "cases" then
		return cases(invocation)
	elseif mode == "compare" then
		local before, after = invocation.positional[2], invocation.positional[3]
		if before == nil or after == nil then
			print(USAGE)
			return 2
		end
		local out = Cli.flag(invocation, "out") or Files.join(after, "compare")
		local _, problems = Critique.compare(before, after, out)
		for _, problem in problems do
			print("facet critique compare: " .. problem)
		end
		print("compare: " .. Files.join(out, "COMPARE.md"))
		return if #problems > 0 then 1 else 0
	elseif mode == "score" then
		local root, packets = Cli.flag(invocation, "cases"), Cli.flag(invocation, "run")
		if root == nil or packets == nil then
			print(USAGE)
			return 2
		end
		local score = Critique.score(root, packets)
		Cli.emit(invocation, (score :: unknown) :: json.Value, Critique.scoreText(score))
		return if score.judged == 0 then 1 else 0
	elseif mode ~= nil then
		print(("facet critique: unknown mode %s"):format(mode))
		print(USAGE)
		return 2
	end
	local out = Cli.flag(invocation, "out") or "artifacts/facet-critique"
	local capture = Cli.flag(invocation, "capture")
	local screens: { Critique.Screen } = {}
	if capture ~= nil then
		local device = Cli.flag(invocation, "device") or "desktop"
		local label = Cli.flag(invocation, "label") or Files.stem(capture)
		table.insert(screens, {
			id = slug(device .. "-" .. label),
			device = device,
			label = label,
			capture = capture,
			dump = Cli.flag(invocation, "dump"),
		})
	else
		local devices: { string } = invocation.repeated.device or Look.DEVICES
		for _, device in devices do
			if table.find(Look.DEVICES, device) == nil then
				print(("facet critique: unknown device %s; use %s"):format(device, table.concat(Look.DEVICES, ", ")))
				return 2
			end
		end
		local result = Look.run({
			project = Cli.flag(invocation, "project") or "default.project.json",
			devices = devices,
			steps = Look.parseSteps(invocation.repeated.tap or {}, tonumber(Cli.flag(invocation, "wait") or "")),
			out = Files.join(out, "play"),
			keep = Cli.switch(invocation, "keep"),
		})
		if result.problem ~= nil then
			print("facet critique: " .. (result.problem :: string))
			return 1
		end
		for _, screen in result.screens do
			table.insert(screens, {
				id = slug(screen.device .. "-" .. screen.label),
				device = screen.device,
				label = screen.label,
				capture = screen.png,
				dump = screen.dump,
			})
		end
	end
	local targetPath, targetKind = Cli.flag(invocation, "target"), Cli.flag(invocation, "target-kind")
	local target: Critique.Target? = nil
	if targetPath ~= nil or targetKind ~= nil then
		if targetPath == nil or targetKind == nil or not Critique.targetKind(targetKind) then
			print("facet critique: give --target FILE with --target-kind specification, concept or inspiration")
			return 2
		end
		local cardPath = Cli.flag(invocation, "card")
		target = {
			path = targetPath,
			kind = targetKind,
			card = if cardPath then (string.gsub(Files.text(cardPath), "%s+$", "")) else nil,
		}
	end
	local packet = Critique.packet({ out = out, brief = brief(invocation), screens = screens, target = target })
	local value: json.Value = { out = packet.out, problems = packet.problems }
	Cli.emit(invocation, value, report(packet))
	return if #packet.problems > 0 then 1 else 0
end

local function fixture(directory: string): (string, string)
	local image = Raster.Image.new(192, 108, 3, { 20, 22, 30 })
	Raster.Draw.rectangle(image, { 66, 24, 126, 84 }, { 60, 70, 100 })
	local capture = Files.join(directory, "shot.png")
	Critique.save(capture, image)
	local dump = Files.join(directory, "shot.json")
	Files.write(dump, Look.sample(false))
	return capture, dump
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a packet holds the capture, both renders, the rules and the rubric", {
		id = prefix .. "a packet holds the capture, both renders, the rules and the rubric",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-critique-")
			local capture, dump = fixture(directory)
			local out = Files.join(directory, "packet")
			local packet = Critique.packet({
				out = out,
				brief = "A sword shop.",
				screens = {
					{ id = "desktop-shop", device = "desktop", label = "shop", capture = capture, dump = dump },
				},
			})
			for _, name in { "capture.png", "squint.png", "blocks.png", "design.txt", "design.json" } do
				Verify.expect(Files.isFile(Files.join(out, "screens", "desktop-shop", name)))
					:toBeTrueWith(name .. " is missing")
			end
			local text = Files.read(Files.join(out, "PACKET.md"))
			Verify.expect(string.find(text, "A sword shop.", 1, true) ~= nil):toBeTrueWith("the brief is missing")
			Verify.expect(string.find(text, "verdict.json", 1, true) ~= nil):toBeTrueWith("the output is not named")
			Verify.expect(#packet.problems):toBe(0)
			Files.remove(directory)
		end,
	})
	harness:case(prefix .. "a target adds the pair, the measures and the missing evidence, apart from the rubric", {
		id = prefix .. "a target adds the pair, the measures and the missing evidence, apart from the rubric",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-critique-")
			local capture, dump = fixture(directory)
			local concept = Raster.Image.new(384, 216, 3, { 12, 14, 40 })
			Raster.Draw.rectangle(concept, { 40, 40, 200, 180 }, { 240, 200, 40 })
			local target = Files.join(directory, "concept.png")
			Critique.save(target, concept)
			local out = Files.join(directory, "packet")
			local packet = Critique.packet({
				out = out,
				screens = {
					{ id = "desktop-shop", device = "desktop", label = "shop", capture = capture, dump = dump },
				},
				target = { path = target, kind = "concept", card = "Largest numeral: an eighth of the height." },
			})
			Verify.expect(#packet.problems):toBe(0)
			local fidelity = assert(packet.fidelity)
			Verify.expect(fidelity.screen):toBe("desktop-shop")
			Verify.expect(fidelity.measures ~= nil):toBeTrueWith("the runtime was not measured")
			for _, name in { "target.png", "pair.png", "pair-squint.png" } do
				Verify.expect(Files.isFile(Files.join(out, "fidelity", name))):toBeTrueWith(name .. " is missing")
			end
			local pair = Critique.load(Files.join(out, "fidelity", "pair.png"))
			Verify.expect(pair.height):toBe(720)
			Verify.expect(pair.width > 2 * 1280):toBeTrueWith("the two are not side by side at one height")
			Verify.expect(table.concat(fidelity.missing, "\n"))
				:toBe("a capture on a phone in portrait\na capture on a phone in landscape")
			local text = Files.read(Files.join(out, "PACKET.md"))
			local part = string.find(text, "## Fidelity to the target", 1, true)
			local rubricAt = string.find(text, "## Rubric", 1, true)
			Verify.expect(part ~= nil and rubricAt ~= nil and part < rubricAt)
				:toBeTrueWith("the fidelity part is not before the rubric")
			for _, needle in
				{
					"Kind: **concept**",
					"Judge fidelity apart from the scores",
					"Leading numeral and type scale",
					"Panel and control shapes",
					"Primary action: placement and emphasis",
					"Largest numeral: an eighth of the height.",
					"a capture on a phone in portrait",
				}
			do
				Verify.expect(string.find(text, needle, 1, true) ~= nil):toBeTrueWith(needle .. " is missing")
			end
			Verify.expect(Files.isFile(Files.join(out, "fidelity.json"))):toBeTrueWith("fidelity.json is missing")
			local tall = Raster.Image.new(108, 192, 3, { 20, 22, 30 })
			local phone = Files.join(directory, "phone.png")
			Critique.save(phone, tall)
			local loose = Critique.packet({
				out = Files.join(directory, "loose"),
				screens = { { id = "phone-shop", device = "phone", label = "shop", capture = phone } },
				target = { path = target, kind = "inspiration" },
			})
			local missing = table.concat(assert(loose.fidelity).missing, "\n")
			Verify.expect(string.find(missing, "at the aspect ratio of the target (1.78)", 1, true) ~= nil)
				:toBeTrueWith("the aspect gap is not named")
			Verify.expect(string.find(missing, "an interface dump of phone-shop", 1, true) ~= nil)
				:toBeTrueWith("the missing dump is not named")
			Verify.expect(string.find(missing, "the measured card", 1, true) ~= nil)
				:toBeTrueWith("the missing card is not named")
			Verify.expect(string.find(missing, "a capture on a phone", 1, true) == nil)
				:toBeTrueWith("an inspiration asked for phone captures")
			local wrong = Critique.packet({
				out = Files.join(directory, "wrong"),
				screens = { { id = "phone-shop", device = "phone", label = "shop", capture = phone } },
				target = { path = target, kind = "moodboard" },
			})
			Verify.expect(#wrong.problems):toBe(1)
			Files.remove(directory)
		end,
	})
	harness:case(prefix .. "a screen without a capture is a packet problem", {
		id = prefix .. "a screen without a capture is a packet problem",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-critique-")
			local packet = Critique.packet({
				out = Files.join(directory, "packet"),
				screens = { { id = "desktop-none", device = "desktop", label = "none" } },
			})
			Verify.expect(#packet.problems > 0):toBeTrueWith("a missing capture passed")
			Files.remove(directory)
		end,
	})
	harness:case(prefix .. "compare writes a side-by-side image and the rule change for shared screens", {
		id = prefix .. "compare writes a side-by-side image and the rule change for shared screens",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-critique-")
			local capture, dump = fixture(directory)
			for _, name in { "before", "after" } do
				Critique.packet({
					out = Files.join(directory, name),
					screens = {
						{ id = "desktop-shop", device = "desktop", label = "shop", capture = capture, dump = dump },
					},
				})
			end
			local out = Files.join(directory, "compare")
			local _, problems = Critique.compare(Files.join(directory, "before"), Files.join(directory, "after"), out)
			Verify.expect(#problems):toBe(0)
			Verify.expect(Files.isFile(Files.join(out, "desktop-shop.png"))):toBeTrueWith("the image is missing")
			local side = Critique.load(Files.join(out, "desktop-shop.png"))
			Verify.expect(side.width > 192):toBeTrueWith("the images are not side by side")
			Files.remove(directory)
		end,
	})
	harness:case(prefix .. "score reads tags, verdicts, score errors and preferred pairs", {
		id = prefix .. "score reads tags, verdicts, score errors and preferred pairs",
		run = function(test: Verify.Context)
			local directory = Files.temporaryDirectory("facet-critique-")
			local function case(id: string, verdict: string, must: { string }, betterThan: string?)
				local folder = Files.join(directory, "cases", id)
				Files.makeDirectory(folder)
				local label = { verdict = verdict, must = must, scores = { lead = 2, numbers = 2 } }
				Files.write(
					Files.join(folder, "case.json"),
					Json.encode({ schema = Critique.CASE_SCHEMA, id = id, label = label, betterThan = betterThan })
				)
			end
			local function judged(id: string, verdict: string, tags: { string }, score: number)
				local fixes = {}
				for rank, tag in tags do
					table.insert(fixes, { rank = rank, tag = tag, problem = "p", move = "m" })
				end
				local folder = Files.join(directory, "run", id)
				Files.makeDirectory(folder)
				Files.write(
					Files.join(folder, "verdict.json"),
					Json.encode({
						schema = Critique.SCHEMA,
						screens = {
							{
								id = id,
								verdict = verdict,
								scores = {
									lead = score,
									numbers = score,
									visuals = score,
									identity = score,
									economy = score,
								},
								fixes = fixes,
							},
						},
					})
				)
			end
			case("bland", "revise", { "joined-facts", "item-without-visual" })
			case("fixed", "pass", {}, "bland")
			case("unjudged", "revise", { "crowded" })
			judged("bland", "revise", { "joined-facts", "crowded" }, 2)
			judged("fixed", "revise", {}, 4)
			local score = Critique.score(Files.join(directory, "cases"), Files.join(directory, "run"))
			Verify.expect(score.judged):toBe(2)
			Verify.expect(score.verdictAgreement):toBe(0.5)
			Verify.expect(score.recall):toBe(0.5)
			Verify.expect(score.pairs):toBe(1)
			Verify.expect(score.pairAgreement):toBe(1)
			Verify.expect(score.scoreError):toBe(1)
			local text = Critique.scoreText(score)
			Verify.expect(string.find(text, "missed item-without-visual", 1, true) ~= nil)
				:toBeTrueWith("the missed tag is not named")
			Verify.expect(string.find(text, "unjudged: not judged", 1, true) ~= nil)
				:toBeTrueWith("an unjudged case is hidden")
			Files.remove(directory)
		end,
	})
end

local command: Cli.Command = {
	name = "critique",
	summary = "Write a critique packet (capture, squint and block renders, design rules) for a fresh reviewer.",
	usage = USAGE,
	values = {
		"device",
		"tap",
		"wait",
		"project",
		"out",
		"capture",
		"dump",
		"label",
		"brief",
		"cases",
		"run",
		"target",
		"target-kind",
		"card",
	},
	register = register,
	run = run,
}

return command
