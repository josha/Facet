--!strict
-- AsyncImage composite (native-substrate NS-A14): an Image whose content
-- arrives through the async resource provider — placeholder while pending,
-- the fetched content when ready, and a visible failure state when the
-- transport reports failure. Engine-free: the provider supplies state/value
-- signals; the Roblox transport (src/client/roblox_resources.luau) or a test
-- harness answers them. Stale completions never resurrect a released image
-- (provider generations; corrections addendum §12 honesty rule).
--
-- newAsyncImage(Facet, core, spec) -> { blueprint, state, handle }
--   spec = {
--     id: string,
--     scope: Scope,            -- owns the provider handle (release-on-dispose)
--     provider: Provider,       -- src/async/resources.luau provider
--     key: string,              -- content id (rbxassetid://, rbxthumb://...)
--     width/height: Dim?,       -- passed to every layer (default: the theme's image size)
--     failureLabel: string?,    -- OPT-IN failure text; absent = failure stays silent (SF-A1)
--     retry: { count, delaySeconds, giveUp? }?,  -- per-call-site retry (SF-A2)
--     dimmed: Bound<boolean>?,  -- the dim treatment (SF-A1/SF-P2), see below
--   }
-- state is the provider's Readable: "pending" | "ready" | "failed".
--
-- THE DIM TREATMENT (ui-designer spec §6.5; rows SF-A1/SF-P2). "Dimmed" is a real
-- presentation state an avatar needs — a racer who left, an entry that is not
-- eligible — and it rides the AUTHORED tint channel rather than a bespoke
-- transparency write: the image blends 35 % toward the `surface` role it sits on,
-- which is themable, contrast-checkable at both ends, and leaves the native sheet
-- uncontested. The undimmed value is the same tint at blend 0 (the identity
-- blend), so turning the state on and off never adds or removes a paint claim
-- mid-life — the node's authority is the same in both states.
--
-- FAILURE STAYS SILENT (SF-A1). A failed image keeps its placeholder; there is no
-- spinner and no broken-image glyph, and `retry` does not change that — it only
-- decides how many times the transport is asked before the key is given up for
-- the session.

local specGuard = require("../spec_guard")

local async_image = {}

-- 35 % toward the surface [25–45] (ratified: avatar_badges §1.3 "Dimmed")
local DIM_BLEND = 0.35
local DIM_TINT = table.freeze({ role = "surface", blend = DIM_BLEND })
local PLAIN_TINT = table.freeze({ role = "surface", blend = 0 })

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local ASYNC_IMAGE_KEYS = specGuard.keySet({
	"dimmed",
	"failureLabel",
	"height",
	"id",
	"key",
	"provider",
	"retry",
	"scope",
	"width",
})

function async_image.build(Facet: any, core: any, spec: any)
	specGuard.assertKnownKeys("newAsyncImage", spec, ASYNC_IMAGE_KEYS, "spec")
	local UI = Facet.UI
	assert(type(spec) == "table" and type(spec.id) == "string", "newAsyncImage: spec.id required")
	assert(spec.provider ~= nil and spec.scope ~= nil, "newAsyncImage: provider and scope required")
	assert(type(spec.key) == "string" and spec.key ~= "", "newAsyncImage: key must be a content string")

	-- the default square is a theme metric, so an icon-scale change reaches every
	-- async image without a consumer edit
	local width = spec.width or { type = "fixed", px = "controls.image.defaultSize" }
	local height = spec.height or { type = "fixed", px = "controls.image.defaultSize" }

	-- retry counts and spacing are a CALL-SITE decision (RL-19): an avatar in a
	-- results list can afford two spaced attempts; a decorative badge cannot.
	local handle =
		spec.provider.acquire(spec.scope, spec.key, if spec.retry ~= nil then { retry = spec.retry } else nil)

	-- ALL FOUR MEMOS ARE SCOPE-OWNED (found by the round-2 runtime verifier:
	-- an avatar grid churning composites leaked every memo per cycle — the same
	-- ownership class adaptive.conditions had). spec.scope is already required;
	-- the memos die with the composite exactly like the provider handle does.
	local imageContent = spec.scope:own(core:memo(function(use)
		return if use(handle.state) == "ready" then use(handle.value) or "" else ""
	end))
	local showPlaceholder = spec.scope:own(core:memo(function(use)
		return use(handle.state) ~= "ready"
	end))
	-- FAILURE IS SILENT unless the CALLER opts into a mark (P5-F2): the default
	-- failed state is the placeholder persisting — a complete, presentable state,
	-- never a spinner or broken-image glyph. `failureLabel` is the deliberate
	-- exception a call site makes for itself.
	local showFailure = if spec.failureLabel == nil
		then nil
		else spec.scope:own(core:memo(function(use)
			return use(handle.state) == "failed"
		end))
	local dimmed = spec.dimmed
	local tint: any = nil
	if dimmed ~= nil then
		if Facet.UI.isReadable(dimmed) then
			tint = spec.scope:own(core:memo(function(use)
				return if use(dimmed) == true then DIM_TINT else PLAIN_TINT
			end))
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
		UI.Image({ id = "Content", image = imageContent, width = width, height = height, tint = tint }),
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
	}
end

return async_image
