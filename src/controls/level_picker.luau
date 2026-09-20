--!strict
-- Discrete marks share one value, focus stop, and scrub target.
-- Compose owns derived state; Facet owns geometry, theming, and semantic input.
local Compose = require("../vendor/compose/core")
local read = require("../selection_model").read
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local selectionShape = require("./selection_indicator")

local level_picker = {}

local SEGMENTS: { [string]: boolean } = table.freeze({ bar = true, glyph = true, image = true })
local SEGMENT_LIST = '"bar" | "glyph" | "image"'
level_picker.DEFAULT_SEGMENT = "bar"

level_picker.GLYPH_FILLED = "★"
level_picker.GLYPH_EMPTY = "☆"

local DEFAULT_SIZE_ROLE = "small"
local SIZE_ROLES: { [string]: boolean } = table.freeze({ small = true, medium = true, large = true })

local DEFAULT_BAR_TINT = table.freeze({
	filled = table.freeze({ role = "accent", blend = 1 }),
	empty = table.freeze({ role = "control", blend = 1 }),
})

level_picker.HIGH_COUNT = 11

type NumberCell = coreContract.Cell<number>
export type Spec<V = NumberCell> = {
	id: string?,
	value: V, -- the caller's writable cell of a number
	count: number?, -- how many levels; default 5
	allowZero: boolean?,
	segment: ("bar" | "glyph" | "image")?,
	glyphs: { filled: string, empty: string }?,
	images: { filled: string, empty: string }?,
	tint: { filled: any?, empty: any? }?,
	enabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	readOnly: boolean?,
	segmentSize: ("small" | "medium" | "large")?,
	env: any?,
	onChange: ((value: number) -> ())?,
}

local LEVEL_PICKER_KEYS = specGuard.keySet({
	"allowZero",
	"count",
	"enabled",
	"env",
	"glyphs",
	"id",
	"images",
	"onChange",
	"readOnly",
	"segment",
	"segmentSize",
	"tint",
	"value",
})

export type Config = {
	constructor: string,
	names: { run: string, mark: string },
	id: string,
	value: V,
	count: number,
	minValue: number,
	segment: string,
	sizeRole: string,
	glyphs: { filled: string, empty: string }?,
	images: { filled: string, empty: string }?,
	tint: { filled: any?, empty: any? },
	targetFloor: boolean,
	readOnly: boolean,
	enabled: blueprint.Bound<boolean>?,
	env: any?,
	onChange: ((value: number) -> ())?,
	diagnostics: { string },
}

local function validate(constructor: string, id: string, value: V, count: any)
	if not (Compose.isReadable(value) and type(value.set) == "function") then
		error(
			`Facet {constructor}('{id}'): \`value\` must be a writable Compose cell holding a number, owned by the caller `
				.. `(the control never creates it, because the value must outlive the control)`,
			0
		)
	end
	if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
		error(`Facet {constructor}('{id}'): \`count\` must be a whole number >= 1 (got {tostring(count)})`, 0)
	end
end

local function sizeRole(constructor: string, id: string, key: string, requested: any): string
	local role = requested or DEFAULT_SIZE_ROLE
	if not SIZE_ROLES[role] then
		error(`Facet {constructor}('{id}'): {key} must be small | medium | large (got '{tostring(requested)}')`, 0)
	end
	return role
end

local function diagnoseCount(constructor: string, id: string, count: number, notes: { string })
	if count <= level_picker.HIGH_COUNT then
		return
	end
	table.insert(
		notes,
		`Facet {constructor}('{id}'): count = {count} is above {level_picker.HIGH_COUNT}, the largest run every `
			.. "shipped theme package still draws as a distinct segment on the narrowest viewport this framework "
			.. "sweeps. The standing guidance for this shape says the same: a large value range can make the "
			.. "segments of a discrete capacity indicator too small to be useful. This is a diagnostic and not "
			.. "a refusal — you may have more room than a phone; check the strip on the narrowest screen you ship."
	)
end

function level_picker.compose(Facet: any, core: any, cfg: Config)
	local UI = Facet.UI
	local id = cfg.id
	local disposed = false
	local value = cfg.value
	local count = cfg.count
	local minValue = cfg.minValue
	local readOnly = cfg.readOnly

	local markSize = `iconSizes.{cfg.sizeRole}`

	local markEnv = if cfg.env ~= nil then cfg.env else surfaceEnv.find(core)
	-- Text paint applies display scaling; remove metric scaling to avoid doubling it.
	local markTextSize: any = if markEnv ~= nil
		then Compose.formula(function(use)
			local metrics = use(markEnv:get("themeMetrics"))
			local px = themeSnapshot.resolveNumber(metrics, markSize)
			if type(px) ~= "number" then
				return markSize
			end
			local factor = themeSnapshot.metricScale(use(markEnv:get("displaySize")))
			return if type(factor) == "number" and factor > 0 then px / factor else px
		end)
		else markSize

	local envForDensity = if cfg.env ~= nil then cfg.env else (surfaceEnv.find(core))
	-- Wider touch spacing preserves individual mark reach without rebuilding the run.
	local markGap = if envForDensity ~= nil
		then Compose.formula(function(use)
			local classes = use(envForDensity:get("interactionClasses"))
			return `iconRunGap.{cfg.sizeRole}.{if classes.touch == true then "touch" else "pointer"}`
		end)
		else `iconRunGap.{cfg.sizeRole}.pointer`

	local function isEnabled(): boolean
		return not disposed and not readOnly and controlContract.enabledNow(cfg.enabled)
	end

	local function apply(next_: number): boolean
		if not isEnabled() then
			return false
		end
		local resolved = math.clamp(math.floor(next_ + 0.5), minValue, count)
		if resolved == read(value) then
			return false
		end
		value:set(resolved)
		if cfg.onChange ~= nil then
			cfg.onChange(resolved)
		end
		return true
	end

	local scrubFrom: number? = nil
	local function setFromPoint(path: string, pos: any, rectOf: (string) -> any): boolean
		local rect = rectOf(path)
		if rect == nil or rect.w <= 0 then
			return false
		end
		local ratio = (pos.x - rect.x) / rect.w
		return apply(math.clamp(math.ceil(ratio * count), minValue, count))
	end

	local hasTint = cfg.tint.filled ~= nil or cfg.tint.empty ~= nil
	local marks = {}
	for i = 1, count do
		local index = i
		local function filledAt(use: any): boolean
			return read(value, use) >= index
		end
		-- An omitted tint half clears local paint so the theme remains authoritative.
		local tint = if hasTint
			then function(use)
				return if filledAt(use) then cfg.tint.filled else cfg.tint.empty
			end
			else nil
		local markId = `{cfg.names.mark}{index}`

		if cfg.segment == "bar" then
			marks[i] = UI.Box({
				id = markId,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				tint = tint,

				corners = selectionShape.segmentShape(UI, index, count, "x"),
			})
		elseif cfg.segment == "image" then
			local images = cfg.images :: { filled: string, empty: string }
			marks[i] = UI.Image({
				id = markId,
				image = function(use)
					return if filledAt(use) then images.filled else images.empty
				end,
				scaleMode = "fit",
				width = { type = "fixed", px = markSize },
				height = { type = "fixed", px = markSize },
				tint = tint,
			})
		else
			local glyphs = cfg.glyphs :: { filled: string, empty: string }
			marks[i] = UI.Text({
				id = markId,
				text = function(use)
					return if filledAt(use) then glyphs.filled else glyphs.empty
				end,
				textSize = markTextSize,
				textAlign = "center",
				width = { type = "hug" },
				tint = tint,
			})
		end
	end

	local runFills = cfg.segment == "bar"
	local run = UI.Grid({
		id = cfg.names.run,
		columns = count,
		itemSizing = "uniform",
		gap = markGap,
		width = if runFills then { type = "fill", weight = 1 } else { type = "hug" },
		height = if runFills then { type = "fill", weight = 1 } else nil,
		alignH = if runFills then nil else "center",
		children = marks,
	})

	local track = if cfg.segment == "bar"
		then UI.Box({
			id = "Track",
			surface = "control",
			corners = UI.cornersData(selectionShape.DEFAULT_CORNER),
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
		})
		else nil

	local rootChildren: { any } = {}
	if track ~= nil then
		table.insert(rootChildren, track)
	end
	table.insert(rootChildren, run)
	table.insert(
		rootChildren,
		UI.Grip({
			id = "Strip",
			focusable = not readOnly,
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				scrubFrom = read(value)
				setFromPoint(path, pos, rectOf)
			end,
			onPointerMove = function(path: string, pos: any, rectOf: (string) -> any)
				setFromPoint(path, pos, rectOf)
			end,
			onPointerUp = function()
				scrubFrom = nil
			end,
			onPointerCancel = function()
				if scrubFrom ~= nil then
					apply(scrubFrom)
					scrubFrom = nil
				end
			end,
		})
	)

	local root = UI.ZStack({
		id = id,
		width = { type = "fill", weight = 1 },
		height = if cfg.targetFloor then { type = "minMax", min = "targetSizes.minimum" } else nil,
		children = rootChildren,
	})

	local rootPath: string? = nil

	local built = contribution.attach(root, {
		adjustRepeat = true,
		adjustTargets = function(rootNode: any): { [string]: boolean }
			rootPath = rootNode.path
			local out: { [string]: boolean } = {}
			if readOnly then
				return out
			end
			local function walk(node: any)
				if node.class == "Grip" then
					out[node.path] = true
				end
				for _, child in node.children or {} do
					walk(child)
				end
			end
			walk(rootNode)
			return out
		end,
		adjustAxis = "horizontal",
		handleAdjust = function(_path: string, direction: number): boolean
			return apply(read(value) + direction)
		end,
	})

	local api = {}
	api.blueprint = built

	-- Losing the active input class cancels an unfinished scrub.
	function api.onInteractionClassLost(class: string)
		if (class == "pointer" or class == "touch") and scrubFrom ~= nil then
			apply(scrubFrom)
			scrubFrom = nil
		end
	end

	-- Bar and image marks need a textual value for assistive readers.
	api.semanticText = Compose.formula(function(use)
		return `{read(value, use)} of {count}`
	end)

	function api.diagnostics(): { string }
		return table.clone(cfg.diagnostics)
	end

	local function facts()
		return {
			id = id,
			segment = cfg.segment,
			value = read(value),
			count = count,
			min = minValue,
			readOnly = readOnly,
			enabled = isEnabled(),
			semanticText = api.semanticText:peek(),
			diagnostics = table.clone(cfg.diagnostics),
			rootPath = rootPath,
		}
	end

	function api.dispose()
		if disposed then
			return
		end
		disposed = true
		if Compose.isReadable(markTextSize) then
			markTextSize:dispose()
		end
		if Compose.isReadable(markGap) then
			markGap:dispose()
		end
		api.semanticText:dispose()
	end

	return api, facts
end

function level_picker.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("UI.LevelPicker", spec, LEVEL_PICKER_KEYS, "spec")
	local id = spec.id or "LevelPicker"
	local count = if spec.count ~= nil then spec.count else 5
	validate("UI.LevelPicker", id, spec.value, count)

	local segment = spec.segment or level_picker.DEFAULT_SEGMENT
	if not SEGMENTS[segment] then
		error(
			`Facet UI.LevelPicker('{id}'): unknown segment '{tostring(spec.segment)}' — use one of `
				.. `{SEGMENT_LIST} ("bar" is the default and needs no assets).`,
			0
		)
	end

	if spec.glyphs ~= nil and segment ~= "glyph" then
		error(
			`Facet UI.LevelPicker('{id}'): \`glyphs\` describes a glyph segment, and this picker is a `
				.. `"{segment}" — it would be accepted and ignored. Drop it, or use \`segment = "glyph"\`.`,
			0
		)
	end
	if spec.images ~= nil and segment ~= "image" then
		error(
			`Facet UI.LevelPicker('{id}'): \`images\` describes an image segment, and this picker is a `
				.. `"{segment}" — it would be accepted and ignored. Drop it, or use \`segment = "image"\`.`,
			0
		)
	end
	if segment == "image" and spec.images == nil then
		error(
			`Facet UI.LevelPicker('{id}'): \`segment = "image"\` needs \`images = \{ filled, empty }\` — this `
				.. "control never names an asset of its own, so there is no default to fall back to. Use "
				.. '`segment = "bar"` (no assets at all) or `segment = "glyph"`.',
			0
		)
	end

	local diagnostics: { string } = {}
	diagnoseCount("UI.LevelPicker", id, count, diagnostics)

	local api, facts = level_picker.compose(Facet, core, {
		constructor = "UI.LevelPicker",
		names = { run = "Levels", mark = "Level" },
		id = id,
		value = spec.value,
		count = count,
		minValue = if spec.allowZero == false then 1 else 0,
		segment = segment,
		sizeRole = sizeRole("UI.LevelPicker", id, "segmentSize", spec.segmentSize),
		glyphs = if segment == "glyph"
			then spec.glyphs or { filled = level_picker.GLYPH_FILLED, empty = level_picker.GLYPH_EMPTY }
			else nil,
		images = spec.images,
		tint = if segment == "bar"
			then {
				filled = if spec.tint ~= nil and spec.tint.filled ~= nil
					then spec.tint.filled
					else DEFAULT_BAR_TINT.filled,
				empty = if spec.tint ~= nil and spec.tint.empty ~= nil then spec.tint.empty else DEFAULT_BAR_TINT.empty,
			}
			else {
				filled = if spec.tint ~= nil then spec.tint.filled else nil,
				empty = if spec.tint ~= nil then spec.tint.empty else nil,
			},
		targetFloor = true,
		readOnly = spec.readOnly == true,
		enabled = spec.enabled,
		env = spec.env,
		onChange = spec.onChange,
		diagnostics = diagnostics,
	})

	function api.dump()
		local out = facts()
		out.schema = "facet-level-picker-dump/1"
		return out
	end

	return api
end

level_picker.validate = validate
level_picker.sizeRole = sizeRole
level_picker.diagnoseCount = diagnoseCount

return level_picker
