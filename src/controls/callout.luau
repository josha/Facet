--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local blueprint = require("../blueprint")

local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local overlayParts = require("./overlay_parts")

local callout = {}

local PLATE_ID = "Plate"
local DISMISS_ID = "Dismiss"
local CLOSE_ID = "Close"
local DUMP_SCHEMA = "facet-callout-dump/1"

-- THEME METRICS, never bare pixels. The dismiss row is a real
-- target, so its floor is the theme's own minimum rather than a number written
-- here — the same `targetSizes.minimum` the segmented rail's floor rides.
local DISMISS_HEIGHT = table.freeze({ type = "minMax", min = "targetSizes.minimum" })
local PLATE_PADDING = "s"
local PLATE_GAP = "s"

local CALLOUT_KEYS = specGuard.keySet({
	"actions",
	"afterSessions",
	"align",
	"anchor",
	"closeButton",
	"content",
	"dismissLabel",
	"edge",
	"featureUsed",
	"id",
	"isPresented",
	"media",
	"onHide",
	"onRetire",
	"onShow",
	"priority",
	"seen",
	"sessions",
	"steps",
	"tail",
	"title",
})
local MAX_ACTIONS = 2

local specTypes = require("../spec_types/callout")
export type Spec = specTypes.Spec

export type PlateOpts = {
	content: blueprint.Blueprint?,
	dismissLabel: string?,
	title: blueprint.Bound<string>?,
	media: specTypes.Media?,
	steps: { index: number, count: number }?,
	actions: { specTypes.Action }?,
	closeButton: boolean?,
}

local function dismissButton(UI: any, label: string?): any
	return UI.Button({
		id = DISMISS_ID,
		label = label or "Got it",
		width = { type = "fill", weight = 1 },
		height = DISMISS_HEIGHT,
	})
end

-- the rich plate: header (title and/or the top close), media, content, steps,
-- then the action row, or the legacy dismiss when there are no actions
local function richPlate(UI: any, opts: PlateOpts): any
	local children: { any } = {}
	if opts.title ~= nil or opts.closeButton == true then
		local header: { any } = {}
		if opts.title ~= nil then
			table.insert(
				header,
				UI.Text({ id = "Title", text = opts.title, textSize = "heading", disclose = true, width = UI.fill() })
			)
		end
		if opts.closeButton == true then
			table.insert(
				header,
				UI.Button({
					id = CLOSE_ID,
					disclose = true,
					label = "Close",
					compactLabel = { icon = "close", prefer = true },
					height = DISMISS_HEIGHT,
				})
			)
		end
		table.insert(
			children,
			UI.HStack({ id = "Header", gap = "s", align = "center", width = UI.fill(), children = header })
		)
	end
	if opts.media ~= nil then
		table.insert(children, overlayParts.media(UI, opts.media))
	end
	if opts.content ~= nil then
		table.insert(children, opts.content)
	end
	if opts.steps ~= nil then
		table.insert(
			children,
			UI.Text({
				id = "Steps",
				text = `{opts.steps.index} of {opts.steps.count}`,
				textSize = "caption",
				role = "secondary",
			})
		)
	end
	if opts.actions ~= nil and #opts.actions > 0 then
		table.insert(children, overlayParts.actionRow(UI, opts.actions, DISMISS_HEIGHT))
	else
		table.insert(children, dismissButton(UI, opts.dismissLabel))
	end
	return UI.VStack({
		id = PLATE_ID,
		surface = "raised",
		padding = PLATE_PADDING,
		gap = PLATE_GAP,
		width = { type = "hug" },
		children = children,
	})
end

function callout.plate(UI: any, opts: PlateOpts): any
	if
		opts.title ~= nil
		or opts.media ~= nil
		or opts.steps ~= nil
		or (opts.actions ~= nil and #opts.actions > 0)
		or opts.closeButton == true
	then
		return richPlate(UI, opts)
	end
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
	local where = `UI.Callout('{id}')`
	overlayParts.checkMedia(where, spec.media)
	local actionCount = overlayParts.checkActions(where, spec.actions, MAX_ACTIONS)
	if spec.closeButton ~= nil and type(spec.closeButton) ~= "boolean" then
		error(`Facet {where}: \`closeButton\` is true or false (default false).`, 0)
	end
	if
		spec.title ~= nil
		and type(spec.title) ~= "string"
		and not Compose.isReadable(spec.title)
		and type(spec.title) ~= "function"
	then
		error(`Facet {where}: \`title\` is a string or a bound string.`, 0)
	end
	local steps = spec.steps
	if steps ~= nil then
		local index, count =
			if type(steps) == "table" then steps.index else nil, if type(steps) == "table" then steps.count else nil
		local function whole(n: any): boolean
			return type(n) == "number" and n == math.floor(n) and n < math.huge
		end
		if not whole(index) or not whole(count) or index < 1 or index > count then
			error(`Facet {where}: \`steps\` is \{ index, count } with whole numbers 1 <= index <= count.`, 0)
		end
	end
	-- content is optional only when another authored part draws something; the
	-- close button and the dismiss are affordances, not content
	local drawsElsewhere = spec.title ~= nil or spec.media ~= nil or steps ~= nil or actionCount > 0
	if spec.content == nil and not drawsElsewhere then
		error(
			`Facet {where}: nothing to show. Give \`content\` (a blueprint) or at least one of \`title\`, `
				.. "`media`, `steps` or `actions`.",
			0
		)
	end
	if spec.content ~= nil and type(spec.content) ~= "table" and type(spec.content) ~= "function" then
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

	-- ===== the caller's facts, as tracked readables ========================
	-- A `(use) -> T` fact is a formula under this control's owner, so it is read
	-- and watched exactly like a Readable; a plain value stays plain.
	local function tracked(fact: any): any
		return if type(fact) == "function" then ownedFormula(owner, fact) else fact
	end
	local isPresentedFact = tracked(spec.isPresented)
	local seenFact = tracked(spec.seen)
	local sessionsFact = tracked(spec.sessions)
	local featureUsedFact = tracked(spec.featureUsed)

	-- ===== state ==========================================================
	local isShowing = Compose.cell(false)
	local retired = Compose.cell(false)
	local queued = Compose.cell(false)
	local reported = false
	local anchorPath: string? = nil
	local presentCalloutFn: ((any) -> number)? = nil
	local releaseCalloutFn: ((number, string?) -> boolean)? = nil
	local entryId: number? = nil
	-- which request is current. Every release bumps it, so a request whose
	-- synchronous onShow retired, rearmed or disposed this control is released
	-- the moment it returns, and a stale generation's callbacks do nothing.
	local generation = 0
	local releaseReason = "manual"

	local function releaseEntry(reason: string)
		generation += 1
		releaseReason = reason
		local entry = entryId
		entryId = nil
		if entry ~= nil and releaseCalloutFn ~= nil then
			releaseCalloutFn(entry, reason)
		end
	end

	local api = {} :: any

	function api.eligible(): boolean
		if retired:peek() then
			return false
		end
		if readFact(seenFact) == true then
			return false
		end
		if readFact(featureUsedFact) == true then
			return false
		end
		if spec.afterSessions ~= nil then
			local count = readFact(sessionsFact)
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
		releaseEntry(reason)
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
				title = spec.title,
				media = spec.media,
				steps = spec.steps,
				actions = spec.actions,
				closeButton = spec.closeButton,
			})
			local attached = contribution.attach(panel, {
				handleActivate = function(path: string, _meta: any?): boolean
					local action = overlayParts.actionAt(spec.actions, path)
					if action ~= nil then
						-- the presentation this press belongs to, captured before the
						-- caller runs: it retires once, and only if still current
						local pressed = generation
						overlayParts.call(action.onActivate, function()
							if pressed == generation then
								retire("action")
							end
						end)
						return true
					end
					if
						string.match(path, `/{PLATE_ID}/{DISMISS_ID}$`) == nil
						and string.match(path, `/{PLATE_ID}/Header/{CLOSE_ID}$`) == nil
					then
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
		generation += 1
		local mine = generation
		local requested = (presentCalloutFn :: any)({
			id = id,
			priority = spec.priority,
			build = buildPanel,
			onShow = function()
				if mine ~= generation then
					return
				end
				queued:set(false)
				isShowing:set(true)
				if spec.onShow ~= nil then
					pcall(spec.onShow)
				end
			end,
			onHide = function(reason: string)
				if mine ~= generation then
					return
				end
				isShowing:set(false)
				queued:set(false)
				if spec.onHide ~= nil then
					pcall(spec.onHide, reason)
				end
			end,
		})
		if mine ~= generation then
			-- released while the request was still being made (a synchronous onShow
			-- that dismissed, rearmed or disposed): give the slot straight back
			if releaseCalloutFn ~= nil then
				releaseCalloutFn(requested, releaseReason)
			end
			return true
		end
		entryId = requested
		return true
	end

	function api.dismiss(reason: string?)
		retire(reason or "dismissed")
	end

	function api.invalidate(reason: string?)
		retire(reason or "invalidated")
	end

	function api.rearm()
		releaseEntry("rearmed")
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

	if Compose.isReadable(featureUsedFact) then
		owner.watchStatic(featureUsedFact, function(used: any)
			if used == true then
				retire("featureUsed")
			end
		end)
	end
	if Compose.isReadable(seenFact) then
		owner.watchStatic(seenFact, function(value: any)
			if value == true then
				retire("seen")
			end
		end)
	end
	-- a callout the caller has already ruled out never enters the queue at all,
	-- and reports nothing: there is nothing new to persist about it
	if readFact(seenFact) == true or readFact(featureUsedFact) == true then
		reported = true
		retired:set(true)
	end

	local released = false
	local function syncPresentation()
		if released then
			return
		end
		if readFact(isPresentedFact) ~= false then
			api.present()
		elseif entryId ~= nil then
			releaseEntry("manual")
		end
	end
	if Compose.isReadable(isPresentedFact) then
		owner.watchStatic(isPresentedFact, syncPresentation)
	end
	owner.own(function()
		released = true
		releaseEntry("manual")
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
			sessions = readFact(sessionsFact),
			seen = readFact(seenFact) == true,
			featureUsed = readFact(featureUsedFact) == true,
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
			released = true
			releaseEntry("manual")
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
