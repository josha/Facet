--!strict
--[[ THE ADAPTER'S ENGINE VOCABULARY — the module-level, one-way half of
	`screen_target` (SOURCE_CAP_LEDGER, taken 2026-08-22).

	WHAT IS IN HERE AND WHY IT COULD LEAVE. Everything below is declared BEFORE
	`screen_target.new` exists, so it reads no upvalue of that closure: the
	authored-word -> engine-value maps (`CLASS_TO_INSTANCE`, `TEXT_ALIGN_MAP`,
	`SCALE_MODE_ENGINE`), the repaint set the tint channel consults, the two pure
	converters (`toColor3`, `fontFaceFor`), the two names the stage seam's
	instances wear, and the three stage/foreign helpers that write a seam-owned
	property or mark a handle dead. That is the ledger's own "one-way" test — a
	block that reads no mutable upvalue of its host cannot create a require back
	— and it is why this file requires `screen_target` nowhere and never may.

	WHY IT LEFT AT ALL. Roblox refuses a `Script.Source` write at 200,000
	characters, so a module past that line silently stops live-syncing into an
	open Studio session and every live check against it tests the place file
	instead of the edits on disk (`docs/lessons/the-200k-source-cap-is-on-writing-
	not-loading.md`). `screen_target.luau` sat 205 characters from its ledger
	trigger with this extraction recorded as OWED; the next change of any size to
	that file had to be PRECEDED by it. This is that extraction. Its siblings are
	`screen_chrome`, `screen_scroll_indicators`, `screen_paint`,
	`screen_presentation` and `screen_pointer`, taken for the same ceiling.

	READ AS TEXT, NOT ONLY LOADED. `tests/lib/adapter_source.luau` lists this file
	as a PART, because the live adapter cannot be required headlessly (engine
	globals at module scope) and a large family of pins reads it as text instead.
	A pin that names one of the declarations below is looking at this file now.

	depends on: ../render/authority (the seam-owned write gate), ./text_premeasure
	(the one font resolver the measure batch and the draw share).
]]

local authority = require("../render/authority")
local text_premeasure = require("./text_premeasure")

local screen_vocabulary = {}

--[[ THE CLASSIFICATION-TAG PREFIX, AND THE ONLY TEST FOR IT (ADR-0038).

	`sheet_model.classifyTags` MINTS every `facet-*` tag and the adapter's
	`syncTags` is the only thing that takes one off, so the two have to agree
	about what "one of ours" means. They stopped agreeing the day ADR-0038
	renamed the tags `luau-*` -> `facet-*`: the sweep rewrote 395 literals and
	left every LENGTH, and `"luau-"` is five characters where `"facet-"` is six.
	`string.sub(tag, 1, 5)` is `"facet"`, which is never `"facet-"`, so the
	removal half of `syncTags` became DEAD CODE and every classification tag a
	node ever wore stayed on it for life — a picker segment set to
	`surface = "plain"` kept `facet-surface-control` and the sheet painted an
	opaque plate over the tab indicator behind it.

	So the length is READ OFF THE LITERAL and both live here, spelled once. A
	future rename can change the string and cannot desynchronise the number,
	which is the same idiom `screen_chrome`'s icon-tag loop uses for
	`chrome_slots.ICON_TAG_PREFIX`. `tests/prefix_tests.spec.luau` scans the whole
	repository for the shape and carries the negative control that proves the
	scan bites. ]]
local TAG_PREFIX = "facet-"

local function ownsTag(tag: string): boolean
	return string.sub(tag, 1, #TAG_PREFIX) == TAG_PREFIX
end

-- `textAlign` (director review 2026-07-24). Absent means Left, which is what the
-- adapter hard-coded before the prop existed, so every existing screen is
-- unchanged.
local TEXT_ALIGN_MAP: { [string]: Enum.TextXAlignment } = {
	start = Enum.TextXAlignment.Left,
	center = Enum.TextXAlignment.Center,
	["end"] = Enum.TextXAlignment.Right,
}

-- THE ENGINE FACE FOR A TYPOGRAPHY-ROLE DESCRIPTOR (F2, 2026-08-02).
--
-- `text_premeasure.fontFor` is the SAME resolver the premeasure batch hands to
-- `GetTextBoundsAsync`, keyed on the same canonical "family#weight#style"
-- descriptor (ADR-0019 §6). So the face the engine DRAWS and the face the engine
-- was asked to MEASURE are one cached lookup, not two parallel mappings that can
-- drift — which is the failure `Text.font` was deprecated for. An unresolvable
-- family returns nil and the node keeps the face it already has.
local function fontFaceFor(descriptor: any): Font?
	if type(descriptor) ~= "table" or type(descriptor.fontKey) ~= "string" then
		return nil
	end
	return text_premeasure.fontFor(descriptor.fontKey)
end

-- authored `scaleMode` -> engine ScaleType (ADR-0022 Decision 6).
--
-- `fill` and `crop` BOTH map to Crop, and that is deliberate rather than a
-- collision: Roblox's `Crop` IS the cover behaviour every other UI vocabulary
-- calls "fill" (preserve the aspect ratio, let the overflow be cropped), and an
-- author arriving from either vocabulary should not have to look it up. `slice`
-- is absent because nine-slice geometry is theme-owned chrome.
--
-- Mirrored headlessly by tests/lib/fake_target's SCALE_MODE_ENGINE_NAME so the
-- mapping is provable without an engine — keep the two in lockstep, exactly as
-- KEYBOARD_TYPE_ENGINE_NAME is.
local SCALE_MODE_ENGINE: { [string]: Enum.ScaleType } = {
	fit = Enum.ScaleType.Fit,
	fill = Enum.ScaleType.Crop,
	crop = Enum.ScaleType.Crop,
	stretch = Enum.ScaleType.Stretch,
}

-- props whose own write repaints a property the `tint` channel may have claimed
-- (see the tail of setProp)
local TINT_REPAINTING_PROPS: { [string]: boolean } =
	{ surface = true, role = true, selected = true, enabled = true, value = true }

local CLASS_TO_INSTANCE: { [string]: string } = {
	Text = "TextLabel",
	Button = "TextButton",
	Toggle = "TextButton",
	Image = "ImageLabel",
	TextField = "TextBox", -- §17 Phase 5 (UI.TextInput): the only engine text-entry instance
	ScrollView = "ScrollingFrame", -- native scroll host; opts.forceScrollFallback keeps a Frame
	-- the engine-content box (ViewportFrame adoption 2026-08-08): a GuiObject that
	-- renders its own scene. The adapter also creates and owns the WorldModel the
	-- content lives in and the Camera the frame renders through — see buildHandle.
	Stage = "ViewportFrame",
	-- Path renders as a transparent Frame holder + child Path2D
	-- containers and everything else render as Frames
}

-- the instances the stage seam owns, named from one place so the adapter and any
-- probe reading the Explorer agree
local STAGE_WORLD_NAME = "FacetStageWorld"
local STAGE_CAMERA_NAME = "FacetStageCamera"

-- THE ONE WRITER for a seam-owned engine property (render/authority.luau's
-- SEAM_OWNED: Ambient, LightColor, LightDirection, CurrentCamera). It writes by
-- INDEX rather than by field name, so a dotted assignment to any of the four
-- appears NOWHERE in this adapter — which turns "a bespoke write defeated the
-- seam" into a literal tests/stage.spec.luau pins at zero, the same way the paint
-- gate turns a sheet-defeating write into a loud error. Every call site is inside
-- the stage seam, so `bySeam` is true here and false everywhere the gate is asked
-- from outside it.
local function writeStageProp(instance: Instance, engineProp: string, value: any)
	authority.assertSeamWrite(engineProp, true);
	(instance :: any)[engineProp] = value
end

-- a stage node's seam going dead, spelled once because two teardown paths need it
-- (`remove` and `destroyRoot`). The instances themselves are children of the frame
-- and die with it; this is what makes a handle a consumer still holds REFUSE
-- instead of writing into the corpse.
local function markStageDisposed(handle: any)
	if handle == nil or handle.stageWorld == nil then
		return
	end
	handle.stageDisposed = true
	handle.stageWorld = nil
	handle.stageCamera = nil
	handle.stageApi = nil
end

-- ...and the same thing for a FOREIGN box (ADR-0034). There is nothing to tear
-- down — whatever the caller adopted is a child of the container and dies with
-- it, exactly as they were told it would — so this is purely the HANDLE going
-- dead, which is what turns a consumer's stale `adopt` from a write into a
-- destroyed instance (silent) into a refusal that names the node (loud).
local function markForeignDisposed(handle: any)
	if handle == nil or handle.foreignBox == nil then
		return
	end
	handle.foreignDisposed = true
	handle.foreignApi = nil
end

local function toColor3(c: any): Color3
	return Color3.new(c.r, c.g, c.b)
end

screen_vocabulary.TAG_PREFIX = TAG_PREFIX
screen_vocabulary.ownsTag = ownsTag
screen_vocabulary.CLASS_TO_INSTANCE = CLASS_TO_INSTANCE
screen_vocabulary.TEXT_ALIGN_MAP = TEXT_ALIGN_MAP
screen_vocabulary.SCALE_MODE_ENGINE = SCALE_MODE_ENGINE
screen_vocabulary.TINT_REPAINTING_PROPS = TINT_REPAINTING_PROPS
screen_vocabulary.STAGE_WORLD_NAME = STAGE_WORLD_NAME
screen_vocabulary.STAGE_CAMERA_NAME = STAGE_CAMERA_NAME
screen_vocabulary.fontFaceFor = fontFaceFor
screen_vocabulary.toColor3 = toColor3
screen_vocabulary.writeStageProp = writeStageProp
screen_vocabulary.markStageDisposed = markStageDisposed
screen_vocabulary.markForeignDisposed = markForeignDisposed

return screen_vocabulary
