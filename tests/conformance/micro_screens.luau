--!strict
-- Phase 0 micro-screens (design §17 Phase 0): three tiny production-shaped
-- state graphs run identically on every core. They prove, at core level:
-- factories run once per mount (UI-RUNTIME-001), structural changes stay
-- keyed and minimal (UI-RUNTIME-002), and churn is registry-neutral
-- (UI-LIFE-002). Same Check shape as suite.luau.

local contract = require("../../src/core/contract")
type Core = contract.Core

export type Check = {
	name: string,
	requirement: string,
	run: (core: Core) -> (boolean, string?),
}

local checks: { Check } = {
	{
		name = "micro-settings-row",
		requirement = "UI-RUNTIME-001",
		run = function(core)
			local scope = core:scope("SettingsRow")
			local factoryRuns = 0
			-- the "component": builds the row's state graph exactly once
			local function rowFactory()
				factoryRuns += 1
				local draft = scope:own(core:signal(false))
				local status = scope:own(core:signal("idle"))
				local label = scope:own(core:memo(function(use)
					return `music: {use(draft) and "on" or "off"} ({use(status)})`
				end))
				return { draft = draft, status = status, label = label }
			end
			local row = rowFactory()
			local renders = 0
			scope:own(core:observe(row.label, function()
				renders += 1
			end))
			-- non-structural updates: toggle five times, then a save mutation
			for _ = 1, 5 do
				row.draft:set(not row.draft:get())
			end
			core:transaction(function()
				row.status:set("pending")
			end)
			row.status:set("confirmed")
			if factoryRuns ~= 1 then
				return false, `factory reran: {factoryRuns} runs`
			end
			if renders ~= 7 then
				return false, `expected 7 label renders (5 toggles + 2 status), got {renders}`
			end
			scope:dispose()
			return true, nil
		end,
	},
	{
		name = "micro-live-hud-value",
		requirement = "UI-RUNTIME-001",
		run = function(core)
			local scope = core:scope("HudValue")
			local factoryRuns = 0
			local function hudFactory()
				factoryRuns += 1
				local speed = scope:own(core:signal(0))
				local shown = scope:own(core:memo(function(use)
					return `{math.floor(use(speed))} sps`
				end))
				return { speed = speed, shown = shown }
			end
			local hud = hudFactory()
			local renderWrites = 0
			scope:own(core:observe(hud.shown, function()
				renderWrites += 1
			end))
			for i = 1, 100 do
				hud.speed:set(i)
			end
			local individual = renderWrites
			core:transaction(function()
				for i = 101, 200 do
					hud.speed:set(i)
				end
			end)
			local afterBatch = renderWrites
			if factoryRuns ~= 1 then
				return false, `factory reran: {factoryRuns}`
			end
			if individual ~= 100 then
				return false, `expected 100 individual render writes, got {individual}`
			end
			if afterBatch ~= 101 then
				return false, `expected exactly 1 batched render write, got {afterBatch - individual}`
			end
			scope:dispose()
			return true, nil
		end,
	},
	{
		name = "micro-keyed-collection",
		requirement = "UI-RUNTIME-002",
		run = function(core)
			local baseline = core:counters()
			local root = core:scope("Collection")
			-- ForEach-at-core-scale: keyed item scopes; add/remove/move only.
			local items: { [string]: { scope: contract.Scope, runs: number } } = {}
			local factoryRuns: { [string]: number } = {}
			local function apply(keys: { string })
				local wanted: { [string]: boolean } = {}
				for _, k in keys do
					wanted[k] = true
				end
				for k, item in items do
					if not wanted[k] then
						item.scope:dispose()
						items[k] = nil
					end
				end
				for _, k in keys do
					if items[k] == nil then
						factoryRuns[k] = (factoryRuns[k] or 0) + 1
						local itemScope = root:child(k)
						itemScope:own(core:signal(k))
						items[k] = { scope = itemScope, runs = factoryRuns[k] }
					end
				end
			end
			apply({ "a", "b", "c" })
			apply({ "c", "a", "b" }) -- pure move: no factory runs
			apply({ "a", "c", "d" }) -- remove b, add d
			if factoryRuns.a ~= 1 or factoryRuns.b ~= 1 or factoryRuns.c ~= 1 or factoryRuns.d ~= 1 then
				return false, `factory runs a={factoryRuns.a} b={factoryRuns.b} c={factoryRuns.c} d={factoryRuns.d}`
			end
			if items.b ~= nil then
				return false, "removed key still mounted"
			end
			apply({})
			root:dispose()
			local after = core:counters()
			for k, v in baseline :: any do
				if (after :: any)[k] ~= v then
					return false, `counter {k} leaked: {v} -> {(after :: any)[k]}`
				end
			end
			return true, nil
		end,
	},
}

return checks
