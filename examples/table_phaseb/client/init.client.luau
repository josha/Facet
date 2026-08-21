--!strict
-- Table Phase B demo (ADR-0007 B / ADR-0008): the live-verification screen for
-- grip column-resize (preview + commit), row drag-and-drop (drop indicator +
-- reorder), modifier multi-select, and focus+Adjust gamepad resize.
-- Studio verification reads workspace attributes Facet_TB_* each frame.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Facet = require(ReplicatedStorage:WaitForChild("Facet")) :: any
--[[ THE BLESSED BOOTSTRAP (REUSE-109, 0.10.0). This file used to hand-roll the
	six steps and then drive `pres.refresh()` alone on `Heartbeat` — so its motion
	clock never advanced and every transition, toast and spring on this demo was
	frozen, which is exactly the defect the audit found in three shipped game
	surfaces. The host is one call and drives both halves on PreRender. ]]
local host = require(ReplicatedStorage.Facet.client.host) :: any

local UI = Facet.UI
local h = host.new()
local core, env, pres = h.core, h.env, h.presenter

local rows = core:signal({
	{ id = "razz", name = "Razz Raccoon", laps = 3 },
	{ id = "bolt", name = "Bunny Bolt", laps = 3 },
	{ id = "josh", name = "Josh", laps = 2 },
	{ id = "peppy", name = "Peppy", laps = 2 },
	{ id = "dusty", name = "Dusty", laps = 1 },
})
local reorderCount = 0

-- Owner-held sort binding (director round 5): the OWNER holds the order
-- and applies it — the table only cycles the signal from header taps
local sortOrder = core:signal(nil :: any)
core:observe(sortOrder, function(order)
	if order == nil then
		return
	end
	local sorted = table.clone(rows:get())
	table.sort(sorted, function(a, b)
		if order.ascending then
			return a.laps < b.laps
		end
		return a.laps > b.laps
	end)
	rows:set(sorted)
	workspace:SetAttribute("Facet_TB_Sort", `{order.column}:{if order.ascending then "asc" else "desc"}`)
end)

-- the PUBLIC export, not an instance-path reach into src/controls (ADR-0011:
-- a consumer goes through the Facet root plus the blessed client entry points;
-- check_boundary now enforces it)
local tbl = Facet.Controls.Table(core, {
	id = "Racers",
	columns = {
		{
			id = "name",
			title = "Racer",
			width = { type = "fill", weight = 1 },
			minWidth = 80,
			resizable = true,
			cell = function(item)
				return UI.Text({ id = "Value", text = item.name, textSize = 16 })
			end,
		},
		{
			id = "laps",
			title = "Laps",
			width = 96, -- width sugar: a bare number is fixed px
			alignment = { h = "trailing" }, -- numeric column reads right-aligned
			value = function(item)
				return tostring(item.laps)
			end,
		},
	},
	rows = rows,
	key = function(item)
		return item.id
	end,
	sortOrder = sortOrder,
	rowHeight = 44,
	header = true,
	selection = "multi",
	reorderable = true,
	dragLabel = function(item: any)
		return item.name
	end,
	-- post-removal slot semantics (ADR-0008): keys arrive in document order;
	-- remove them all, then insert the block at slot + 1 — no adjustment
	onReorder = function(keys: { string }, toIndex: number)
		local moving: { [string]: boolean } = {}
		for _, key in keys do
			moving[key] = true
		end
		local remaining = {}
		local block = {}
		for _, item in rows:get() do
			if moving[item.id] then
				table.insert(block, item)
			else
				table.insert(remaining, item)
			end
		end
		for offset, item in block do
			table.insert(remaining, math.clamp(toIndex + offset, 1, #remaining + 1), item)
		end
		rows:set(remaining)
		reorderCount += 1
		workspace:SetAttribute("Facet_TB_Reorders", reorderCount)
		workspace:SetAttribute("Facet_TB_LastReorder", `{table.concat(keys, "+")}->{toIndex}`)
	end,
})

local screen = UI.Screen({
	id = "TB",
	padding = 24,
	gap = 8,
	children = {
		UI.Text({ id = "Title", text = "Table Phase B — resize / drag / select", textSize = 22 }),
		tbl.blueprint,
	},
})

pres.present(screen, {
	-- a focus-driven full-screen list: sink nav keys so arrows never reach
	-- the character controls (director hand-test 2026-07-20)
	sinkNavigation = true,
	onActivate = function(path: string, meta: any?)
		tbl.api.handleActivate(path, meta)
	end,
	onAdjust = function(path: string, dir: number, rectOf: any)
		tbl.api.handleAdjust(path, dir, rectOf)
	end,
	onReorderNav = function(path: string, dir: number)
		return tbl.api.handleReorderNav(path, dir)
	end,
	onFocusNav = function(path: string)
		tbl.api.handleFocusMoved(path)
	end,
})

--[[ THE PER-FRAME PROBE RIDES THE PRESENTER'S OWN CLOCK. `onTick` is the
	sanctioned frame source for consumer work — it runs inside the host's single
	PreRender, after the motion step and before the refresh, so these attributes
	report this frame's settled values rather than the previous frame's. ]]
local unsubscribeProbe = pres.onTick(function()
	local order = {}
	for _, item in rows:get() do
		table.insert(order, item.id)
	end
	workspace:SetAttribute("Facet_TB_Order", table.concat(order, ","))
	local selected = {}
	for key in tbl.api.selectedKeys:get() do
		table.insert(selected, key)
	end
	table.sort(selected)
	workspace:SetAttribute("Facet_TB_Selected", table.concat(selected, ","))
	-- a Readable since 2026-08-14 (it was a zero-arg getter): a pointer drag
	-- commits inside the control and fires no consumer callback, so the widths
	-- had to become subscribable — see src/controls/table.luau's own note
	local overrides = tbl.api.columnWidthOverrides:get()
	workspace:SetAttribute("Facet_TB_NameOverride", overrides.name or 0)
	workspace:SetAttribute("Facet_TB_Focused", pres.focus.focused:get() or "")
end)

workspace:SetAttribute("Facet_TB_Ready", true)
print(`[Facet TablePhaseB] running {Facet.VERSION}`)

local _keep = { h, unsubscribeProbe, tbl }
