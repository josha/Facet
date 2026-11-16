--!strict
local Types = require("../../src/ui/types")
local Nav = require("../../src/ui/navigation_types")
local ControlTypes = require("../../src/ui/control_types")
local textField = require("../../src/ui/text_field")
local inputKit = require("../../src/ui/input_kit")
local inputButton = require("../../src/ui/input_button")
local inputToggle = require("../../src/ui/input_toggle")
local inputStepper = require("../../src/ui/input_stepper")
local inputActions = require("../../src/ui/input_actions")
local slider = require("../../src/ui/slider")
local inputLevel = require("../../src/ui/input_level")
local inputChip = require("../../src/ui/input_chip")
local inputShortcutHint = require("../../src/ui/input_shortcut_hint")
local inputButtonGuide = require("../../src/ui/input_button_guide")
local mediaShared = require("../../src/ui/media_shared")
local mediaText = require("../../src/ui/media_text")
local mediaImage = require("../../src/ui/media_image")
local mediaBadge = require("../../src/ui/media_badge")
local mediaPath = require("../../src/ui/media_path")
local mediaProgress = require("../../src/ui/media_progress")
local mediaSkeleton = require("../../src/ui/media_skeleton")
local mediaAsyncImage = require("../../src/ui/media_async_image")
local mediaAvatar = require("../../src/ui/media_avatar")
local mediaStage = require("../../src/ui/media_stage")
local pageLayers = require("../../src/ui/nav_page_layers")
local tabView = require("../../src/ui/nav_tab_view")
local navigationStack = require("../../src/ui/nav_stack")
local pageView = require("../../src/ui/nav_page_view")
local surfaceParts = require("../../src/ui/nav_surface_parts")
local disclosure = require("../../src/ui/nav_disclosure")
local collapsible = require("../../src/ui/nav_collapsible")
local alert = require("../../src/ui/nav_alert")
local callout = require("../../src/ui/nav_callout")

local families = {}

function families.inputs(ctx: Types.Context, UI: ControlTypes.Controls): ()
	local kit = inputKit(ctx)
	inputButton(ctx, UI, kit)
	inputToggle(ctx, UI, kit)
	textField(ctx, UI)
	inputStepper(ctx, UI, kit)
	inputActions(ctx, UI, kit)
	slider(ctx, UI, kit)
	inputLevel(ctx, UI, kit)
	inputChip(ctx, UI, kit)
	inputShortcutHint(ctx, UI, kit)
	inputButtonGuide(ctx, UI, kit)
end

function families.media(ctx: Types.Context): ControlTypes.Controls
	local UI: ControlTypes.Controls = {} :: ControlTypes.Controls
	local shared = mediaShared(ctx)
	mediaText(ctx, UI, shared)
	mediaImage(ctx, UI, shared)
	mediaBadge(ctx, UI, shared)
	mediaPath(ctx, UI)
	mediaProgress(ctx, UI, shared)
	mediaSkeleton(ctx, UI)
	mediaAsyncImage(ctx, UI, shared)
	mediaAvatar(ctx, UI)
	mediaStage(ctx, UI, shared)
	return UI
end

function families.pages(ctx: Types.Context, UI: ControlTypes.Controls, surfaces: Nav.Surfaces): ()
	local layers = pageLayers(ctx)
	tabView(ctx, UI, surfaces, layers)
	navigationStack(ctx, UI, surfaces, layers)
	pageView(ctx, UI, surfaces, layers)
end

function families.surfaces(ctx: Types.Context, UI: ControlTypes.Controls, surfaces: Nav.Surfaces): ()
	local kit = surfaceParts(ctx)
	disclosure(ctx, UI, surfaces, kit)
	collapsible(ctx, UI, surfaces, kit)
	alert(ctx, UI, surfaces, kit)
	callout(ctx, UI, surfaces, kit)
end

return families
