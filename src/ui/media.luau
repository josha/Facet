--!strict
local Types = require("./types")
local ControlTypes = require("./control_types")
local mediaShared = require("./media_shared")
local registerText = require("./media_text")
local registerImage = require("./media_image")
local registerBadge = require("./media_badge")
local registerPath = require("./media_path")
local registerProgress = require("./media_progress")
local registerSkeleton = require("./media_skeleton")
local registerAsyncImage = require("./media_async_image")
local registerAvatar = require("./media_avatar")
local registerStage = require("./media_stage")
export type MediaControls = ControlTypes.Controls

return function(ctx: Types.Context, controls: ControlTypes.Controls?): ControlTypes.Controls
	local UI: ControlTypes.Controls = controls or ({} :: ControlTypes.Controls)
	local shared = mediaShared(ctx)
	registerText(ctx, UI, shared)
	registerImage(ctx, UI, shared)
	registerBadge(ctx, UI, shared)
	registerPath(ctx, UI)
	registerProgress(ctx, UI, shared)
	registerSkeleton(ctx, UI)
	registerAsyncImage(ctx, UI, shared)
	registerAvatar(ctx, UI)
	registerStage(ctx, UI, shared)
	return UI
end
