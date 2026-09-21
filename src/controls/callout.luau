--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local blueprint = require("../blueprint")

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")

local callout = {}

local PLATE_ID = "Plate"
local DISMISS_ID = "Dismiss"
local DUMP_SCHEMA = "facet-callout-dump/1"

-- THEME METRICS, never bare pixels. The dismiss row is a real
-- target, so its floor is the theme's own minimum rather than a number written
-- here — the same `targetSizes.minimum` the segmented rail's floor rides.
local DISMISS_HEIGHT = table.freeze({ type = "minMax", min = "targetSizes.minimum" })
local PLATE_PADDING = "s"
local PLATE_GAP = "s"

local CALLOUT_KEYS = specGuard.keySet({
	"afterSessions",
	"align",
	"anchor",
	"content",
	"dismissLabel",
	"edge",
	"featureUsed",
	"id",
	"isPresented",
	"onHide",
	"onRetire",
	"onShow",
	"priority",
	"seen",
	"sessions",
	"tail",
})

local specTypes = require("../spec_types/callout")
export type Spec = specTypes.Spec

function callout.plate(UI: any, opts: { content: blueprint.Blueprint, dismissLabel: string? }): any
	return UI.VStack({
		id = PLATE_ID,
		-- the panel treatment, so the plate is themed by the ACTIVE snapshot
		surface = "raised",
		padding = PLATE_PADDING,
		gap = PLATE_GAP,
		-- HUGS ITS OWN CONTENT: a short tip gets a short plate, and a ~1.4x
		-- localized one grows rather than clipping. The safe-box clamp is D1's, so
		-- there is no ceiling to restate here.
		width = { type = "hug" },
		children = {
			opts.content,
			UI.Button({
				id = DISMISS_ID,
				label = opts.dismissLabel or "Got it",
				width = { type = "fill", weight = 1 },
				height = DISMISS_HEIGHT,
			}),
		},
	})
end

local function readFact(fact: any): any
	if Compose.isReadable(fact) then
		return (fact :: any):peek()
	end
	return fact
end

local function build(Facet: any, core: any, spec: Spec, owner: any)
	specGuard.assertKnownKeys("UI.Callout", spec, CALLOUT_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Callout"

	if type(spec.anchor) ~= "table" then
		error(
			`Facet UI.Callout('{id}'): \`anchor\` is the blueprint the plate points at — ANY node. The `
				.. "contribution rides it; its layout is untouched.",
			0
		)
	end
	if type(spec.content) ~= "table" and type(spec.content) ~= "function" then
		error(
			`Facet UI.Callout('{id}'): \`content\` is a BLUEPRINT, not a string. The reference plate is styled `
				.. "and holds more than one line, and a string-only tip could not express it.",
			0
		)
	end
	if type(spec.onRetire) ~= "function" then
		error(
			`Facet UI.Callout('{id}'): \`onRetire(reason)\` is REQUIRED. Facet has no save layer and will `
				.. "not grow one: this construct reads your `seen`/`sessions`/`featureUsed` Readables and reports "
				.. "back exactly once when the tip should never be shown again. Persisting that is yours.",
			0
		)
	end

	-- ===== state ==========================================================
	local isShowing = Compose.cell(false)
	local retired = Compose.cell(false)
	local queued = Compose.cell(false)
	local reported = false
	local anchorPath: string? = nil
	local presentCalloutFn: ((any) -> number)? = nil
	local releaseCalloutFn: ((number, string?) -> boolean)? = nil
	local entryId: number? = nil

	local api = {} :: any

	function api.eligible(): boolean
		if retired:peek() then
			return false
		end
		if readFact(spec.seen) == true then
			return false
		end
		if readFact(spec.featureUsed) == true then
			return false
		end
		if spec.afterSessions ~= nil then
			local count = readFact(spec.sessions)
			if type(count) ~= "number" or count < spec.afterSessions then
				return false
			end
		end
		return true
	end

	local function retire(reason: string)
		if reported then
			return
		end
		reported = true
		retired:set(true)
		queued:set(false)
		isShowing:set(false)
		if entryId ~= nil and releaseCalloutFn ~= nil then
			local id2 = entryId
			entryId = nil
			releaseCalloutFn(id2, reason)
		end
		entryId = nil
		-- THE ONE REPORT. Quarantined, because a caller's save path throwing must
		-- not leave this control believing it is still on screen.
		pcall(spec.onRetire, reason)
	end

	local function buildPanel(): (any?, any?)
		if anchorPath == nil then
			return nil, nil
		end
		local function buildAttached()
			local panel = callout.plate(UI, {
				content = if type(spec.content) == "function" then spec.content() else spec.content,
				dismissLabel = spec.dismissLabel,
			})
			local attached = contribution.attach(panel, {
				handleActivate = function(path: string, _meta: any?): boolean
					if string.match(path, `/{PLATE_ID}/{DISMISS_ID}$`) == nil then
						return false
					end
					api.dismiss()
					return true
				end,
				outsideDismiss = {
					active = isShowing,
					dismiss = function()
						api.dismiss()
					end,
					consume = false,
				},
				handleCancel = function(_focusedPath: string?): boolean
					if not isShowing:peek() then
						return false
					end
					api.dismiss()
					return true
				end,
			})
			return attached
		end
		return buildAttached,
			{
				source = { path = anchorPath },
				edge = spec.edge or "bottom",
				align = spec.align or "center",
				-- A COACH MARK POINTS — and so, since the 2026-08-16 device review, does
				-- the player-pulled help plate. Both stems come from this one seam; what
				-- tells the two constructs apart is who raises them, never the arrow.
				tail = spec.tail ~= false,
			}
	end

	function api.present(): boolean
		if not api.eligible() or isShowing:peek() or queued:peek() then
			return false
		end
		if presentCalloutFn == nil or anchorPath == nil then
			return false -- no presenter, or not mounted yet: nothing to present onto
		end
		queued:set(true)
		entryId = presentCalloutFn({
			id = id,
			priority = spec.priority,
			build = buildPanel,
			onShow = function()
				queued:set(false)
				isShowing:set(true)
				if spec.onShow ~= nil then
					pcall(spec.onShow)
				end
			end,
			onHide = function(reason: string)
				isShowing:set(false)
				queued:set(false)
				if spec.onHide ~= nil then
					pcall(spec.onHide, reason)
				end
			end,
		})
		return true
	end

	function api.dismiss(reason: string?)
		retire(reason or "dismissed")
	end

	function api.invalidate(reason: string?)
		retire(reason or "invalidated")
	end

	function api.rearm()
		if entryId ~= nil and releaseCalloutFn ~= nil then
			local id2 = entryId
			entryId = nil
			releaseCalloutFn(id2, "rearmed")
		end
		entryId = nil
		reported = false
		retired:set(false)
		queued:set(false)
		isShowing:set(false)
	end

	function api.state(): string
		if retired:peek() then
			return "retired"
		elseif isShowing:peek() then
			return "showing"
		elseif queued:peek() then
			return "queued"
		end
		return "waiting"
	end

	api.isShowing = isShowing
	api.retired = retired

	if spec.featureUsed ~= nil and type(spec.featureUsed) == "table" then
		owner.watchStatic(spec.featureUsed, function(used: any)
			if used == true then
				retire("featureUsed")
			end
		end)
	end
	if spec.seen ~= nil and type(spec.seen) == "table" then
		owner.watchStatic(spec.seen, function(value: any)
			if value == true then
				retire("seen")
			end
		end)
	end
	-- a callout the caller has already ruled out never enters the queue at all,
	-- and reports nothing: there is nothing new to persist about it
	if readFact(spec.seen) == true or readFact(spec.featureUsed) == true then
		reported = true
		retired:set(true)
	end

	local released = false
	local function syncPresentation()
		if released then
			return
		end
		if readFact(spec.isPresented) ~= false then
			api.present()
		elseif entryId ~= nil and releaseCalloutFn then
			local entry = entryId
			entryId = nil
			releaseCalloutFn(entry, "manual")
		end
	end
	if Compose.isReadable(spec.isPresented) then
		owner.watchStatic(spec.isPresented, syncPresentation)
	end
	owner.own(function()
		released = true
		if entryId ~= nil and releaseCalloutFn then
			local entry = entryId
			entryId = nil
			releaseCalloutFn(entry, "manual")
		end
	end)
	local blueprint = contribution.attach(spec.anchor, {
		syncGeometry = function(_rectOf: (string) -> any, rootNode: any?)
			if rootNode ~= nil and anchorPath == nil then
				anchorPath = rootNode.path
			end
			syncPresentation()
		end,
		bindPresent = function(_presentModal: any, _dismiss: any, _presentAnchored: any, present: any, release: any)
			presentCalloutFn = if Facet.surfaces then Facet.surfaces.callout else present
			releaseCalloutFn = release
			syncPresentation()
		end,
	})

	local function dump()
		local state = api.state()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			state = state,
			eligible = api.eligible(),
			showing = isShowing:peek(),
			retired = retired:peek(),
			reported = reported,
			priority = spec.priority or 0,
			edge = spec.edge or "bottom",
			align = spec.align or "center",
			tail = spec.tail ~= false,
			anchorPath = anchorPath,
			afterSessions = spec.afterSessions,
			sessions = readFact(spec.sessions),
			seen = readFact(spec.seen) == true,
			featureUsed = readFact(spec.featureUsed) == true,
			text = `callout '{id}': {state}` .. (if state == "retired"
				then " (reported to the caller, never shown again)"
				else "") .. `, anchored {spec.edge or "bottom"}/{spec.align or "center"} of {tostring(anchorPath)}`,
		}
	end

	return {
		blueprint = blueprint,
		api = api,
		dump = dump,
		dispose = function()
			if entryId ~= nil and releaseCalloutFn ~= nil then
				local id2 = entryId
				entryId = nil
				releaseCalloutFn(id2, "manual")
			end
			owner.dispose()
		end,
	}
end

function callout.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end
return callout
