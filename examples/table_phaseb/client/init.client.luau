--!strict
-- Table Phase B demo (ADR-0007 B / ADR-0008): the live-verification screen for
-- grip column-resize (preview + commit), row drag-and-drop (drop indicator +
-- reorder), modifier multi-select, and focus+Adjust gamepad resize.
-- Studio verification reads workspace attributes LuauUI_TB_* each frame.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LuauUI = require(ReplicatedStorage:WaitForChild("LuauUI")) :: any
local screen_target = require(ReplicatedStorage.LuauUI.client.screen_target) :: any
local roblox_env = require(ReplicatedStorage.LuauUI.client.roblox_env) :: any
local roblox_input = require(ReplicatedStorage.LuauUI.client.roblox_input) :: any
local table_control = require(ReplicatedStorage.LuauUI.controls["table"]) :: any

local UI = LuauUI.UI
local core = LuauUI.newCore()
local env = LuauUI.newEnvironment(core)
local unbindEnv = roblox_env.bind(env)
local adapter = screen_target.new()
local system = roblox_input.newSystem(core)
local pres = LuauUI.newPresenter(core, env, adapter, system)

local rows = core:signal({
	{ id = "razz", name = "Razz Raccoon", laps = 3 },
	{ id = "bolt", name = "Bunny Bolt", laps = 3 },
	{ id = "josh", name = "Josh", laps = 2 },
	{ id = "peppy", name = "Peppy", laps = 2 },
	{ id = "dusty", name = "Dusty", laps = 1 },
})
local reorderCount = 0

-- SwiftUI-shaped sort binding (director round 5): the OWNER holds the order
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
	workspace:SetAttribute("LuauUI_TB_Sort", `{order.column}:{if order.ascending then "asc" else "desc"}`)
end)

local tbl = table_control.build(LuauUI, core, {
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
		workspace:SetAttribute("LuauUI_TB_Reorders", reorderCount)
		workspace:SetAttribute("LuauUI_TB_LastReorder", `{table.concat(keys, "+")}->{toIndex}`)
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

local heartbeat = RunService.Heartbeat:Connect(function()
	pres.refresh()
	local order = {}
	for _, item in rows:get() do
		table.insert(order, item.id)
	end
	workspace:SetAttribute("LuauUI_TB_Order", table.concat(order, ","))
	local selected = {}
	for key in tbl.api.selectedKeys:get() do
		table.insert(selected, key)
	end
	table.sort(selected)
	workspace:SetAttribute("LuauUI_TB_Selected", table.concat(selected, ","))
	local overrides = tbl.api.columnWidthOverrides()
	workspace:SetAttribute("LuauUI_TB_NameOverride", overrides.name or 0)
	workspace:SetAttribute("LuauUI_TB_Focused", pres.focus.focused:get() or "")
end)

workspace:SetAttribute("LuauUI_TB_Ready", true)
print(`[LuauUI TablePhaseB] running {LuauUI.VERSION}`)

local _keep = { unbindEnv, heartbeat, tbl }
