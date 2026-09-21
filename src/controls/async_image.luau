--!strict
-- A resource-backed image. The mounted owner releases the lease and bindings.
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local specGuard = require("../spec_guard")

local async_image = {}

-- 35 % toward the surface [25–45] (ratified: avatar_badges §1.3 "Dimmed")
local DIM_BLEND = 0.35
local DIM_TINT = table.freeze({ role = "surface", blend = DIM_BLEND })
local PLAIN_TINT = table.freeze({ role = "surface", blend = 0 })

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local ASYNC_IMAGE_KEYS = specGuard.keySet({
	"dimmed",
	"failureLabel",
	"height",
	"id",
	"key",
	"provider",
	"retry",
	"scaleMode",
	"tileSize",
	"sliceCenter",
	"sliceScale",
	"resample",
	"width",
})

local function build(Facet: any, core: any, spec: any, owner: any)
	specGuard.assertKnownKeys("UI.AsyncImage", spec, ASYNC_IMAGE_KEYS, "spec")
	local UI = Facet.UI
	assert(type(spec) == "table" and type(spec.id) == "string", "UI.AsyncImage: spec.id required")
	assert(spec.provider ~= nil, "AsyncImage: provider required")
	assert(type(spec.key) == "string" and spec.key ~= "", "UI.AsyncImage: key must be a content string")

	-- the default square is a theme metric, so an icon-scale change reaches every
	-- async image without a consumer edit
	local width = spec.width or { type = "fixed", px = "controls.image.defaultSize" }
	local height = spec.height or { type = "fixed", px = "controls.image.defaultSize" }

	-- retry counts and spacing are a CALL-SITE decision: an avatar in a
	-- results list can afford two spaced attempts; a decorative badge cannot.
	local handle = spec.provider.acquire(owner, spec.key, if spec.retry ~= nil then { retry = spec.retry } else nil)

	-- The image owner holds both the lease and the derived bindings.
	local imageContent = Compose.formula(function(use)
		return if use(handle.state) == "ready" then use(handle.value) or "" else ""
	end)
	local showPlaceholder = Compose.formula(function(use)
		return use(handle.state) ~= "ready"
	end)
	-- FAILURE IS SILENT unless the CALLER opts into a mark (P5-F2): the default
	-- failed state is the placeholder persisting — a complete, presentable state,
	-- never a spinner or broken-image glyph. `failureLabel` is the deliberate
	-- exception a call site makes for itself.
	local showFailure = if spec.failureLabel == nil
		then nil
		else Compose.formula(function(use)
			return use(handle.state) == "failed"
		end)
	local dimmed = spec.dimmed
	local tint: any = nil
	if dimmed ~= nil then
		if Facet.UI.isReadable(dimmed) then
			tint = Compose.formula(function(use)
				return if use(dimmed) == true then DIM_TINT else PLAIN_TINT
			end)
		else
			tint = if dimmed == true then DIM_TINT else PLAIN_TINT
		end
	end

	local children: { any } = {
		UI.When({
			id = "Placeholder",
			condition = showPlaceholder,
			thenView = function()
				return UI.Box({ id = "Fill", surface = "control", width = width, height = height })
			end,
		}),
		-- the picture options ride through verbatim; the leaf's own construction
		-- rules (a tile mode needs its `tileSize`, a slice its `slice`) then refuse
		-- an inconsistent pair here exactly as they would on a hand-built Image
		UI.Image({
			id = "Content",
			image = imageContent,
			width = width,
			height = height,
			tint = tint,
			scaleMode = spec.scaleMode,
			tileSize = spec.tileSize,
			sliceCenter = spec.sliceCenter,
			sliceScale = spec.sliceScale,
			resample = spec.resample,
		}),
	}
	if showFailure ~= nil then
		table.insert(
			children,
			UI.When({
				id = "Failure",
				condition = showFailure,
				thenView = function()
					return UI.Text({
						id = "Mark",
						text = spec.failureLabel,
						textSize = "control",
						role = "secondary",
					})
				end,
			})
		)
	end

	local blueprint = UI.ZStack({
		id = spec.id,
		width = width,
		height = height,
		children = children,
	})

	return {
		blueprint = blueprint,
		state = handle.state,
		handle = handle,
		dispose = owner.dispose,
	}
end

function async_image.build(Facet: any, core: any, spec: any)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return async_image
