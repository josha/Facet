--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")
local Lute = require("../../../../tools/vendor/verify/src/lute")
local Check = require("../../../../tools/play/host/check")
local QA = require("../../../../tools/play/host/qa")
local Core = require("../../../../tools/vendor/verify/src/core")

type Values = { [string]: boolean }
type Palette = { [string]: Values }
local palettes: { [string]: Palette } = {}
local scores: { [string]: number } = {}
type Extent = { minX: number, maxX: number, minY: number, maxY: number }
local returns: { [string]: Extent } = {}
local bounds: { [string]: number } =
	{ fonts = 6, textSizes = 24, textColors = 48, spacing = 32, buttonColors = 32, buttonStyles = 64 }

local function argument(name: string): string?
	for index, word in process.args do
		if word == "--" .. name then
			return process.args[index + 1]
		end
	end
	return nil
end

local function color(value: Audit.Color): string
	return ("%.2f/%.2f/%.2f"):format(value.r, value.g, value.b)
end

local function observe(device: string, screen: string)
	local output = argument("outputs")
	if output == nil then
		return
	end
	local dump =
		Audit.decode(Lute.parse(fs.readFileToString(output .. "/dumps/" .. device .. "/" .. screen .. ".json")))
	local palette = palettes[device]
		or { fonts = {}, textSizes = {}, textColors = {}, spacing = {}, buttonColors = {}, buttonStyles = {} }
	palettes[device] = palette
	for _, element in dump.elements do
		if not element.visible then
			continue
		end
		local text = element.text
		if text ~= nil and text.content ~= "" then
			palette.fonts[text.font or "default"] = true
			palette.textSizes[tostring(math.floor(text.size + 0.5))] = true
			palette.textColors[color(text.color)] = true
		end
		local padding = element.padding
		if padding ~= nil then
			for _, value in { padding.left, padding.top, padding.right, padding.bottom } do
				palette.spacing[tostring(math.floor(value + 0.5))] = true
			end
		end
		local layout = element.layout
		if layout ~= nil and layout.padding ~= nil then
			palette.spacing[tostring(math.floor(layout.padding + 0.5))] = true
		end
		if element.class == "TextButton" or element.class == "ImageButton" then
			local fill = color(element.background.color)
			palette.buttonColors[fill] = true
			palette.buttonStyles[fill .. "/" .. tostring(element.background.transparency) .. "/" .. (if text ~= nil
				then color(text.color) .. "/" .. tostring(text.size) .. "/" .. tostring(text.bold)
				else "image")] =
				true
		end
	end
end

local function returnControl(qa: QA.QA, context: Core.Context)
	local control =
		Check.visible(qa, context, { role = "button", exact = "close" }, "the panel has one visible return control")
	local x = (control.rect.x + control.rect.width) / math.max(1, qa.viewport.width)
	local y = control.rect.y / math.max(1, qa.viewport.height)
	local extent: Extent = returns[qa.device.id] or { minX = x, maxX = x, minY = y, maxY = y }
	returns[qa.device.id] = extent
	extent.minX = math.min(extent.minX, x)
	extent.maxX = math.max(extent.maxX, x)
	extent.minY = math.min(extent.minY, y)
	extent.maxY = math.max(extent.maxY, y)
	Check.that(context, #qa:find({ role = "button", exact = "close" }) == 1, "the panel has one visible Close")
end

local function check(device: string, context: Core.Context)
	local palette = palettes[device]
	Check.that(context, palette ~= nil, "the screen dumps contain a visible interface")
	for name in bounds do
		local count = 0
		for _ in (palette :: Palette)[name] do
			count += 1
		end
		scores["coherence." .. device .. ".distinct" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)] =
			count
	end
	local extent = returns[device]
	if extent ~= nil then
		scores["coherence." .. device .. ".returnControlSpreadX"] = extent.maxX - extent.minX
		scores["coherence." .. device .. ".returnControlSpreadY"] = extent.maxY - extent.minY
	end
	local output = argument("outputs")
	if output ~= nil then
		fs.writeStringToFile(output .. "/coherence.json", Lute.encode(scores))
	end
	context:attach("coherence-scores", "application/json", Lute.encode(scores))
	for name, bound in bounds do
		local key = "coherence." .. device .. ".distinct" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
		local count = scores[key]
		Check.that(
			context,
			count > 0 and count <= bound,
			("%s has %d distinct %s; the bound is %d"):format(device, count, name, bound)
		)
	end
	Check.that(
		context,
		extent ~= nil and extent.maxX - extent.minX <= 0.4 and extent.maxY - extent.minY <= 0.25,
		"return controls stay in a consistent screen region"
	)
end

local function writeScores()
	local path = argument("scores")
	if path == nil or not fs.exists(path) then
		return
	end
	local raw = Lute.parse(fs.readFileToString(path))
	assert(type(raw) == "table", "scores must be a table")
	local combined = raw :: { [string]: unknown }
	for name, value in scores do
		combined[name] = value
	end
	fs.writeStringToFile(path, Lute.encode(combined))
end

return { observe = observe, returnControl = returnControl, check = check, writeScores = writeScores }
