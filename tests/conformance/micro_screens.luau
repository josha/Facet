--!strict
-- Phase 0 micro-screens (design §17 Phase 0): three tiny production-shaped
-- state graphs run identically on every core. They prove, at core level:
-- factories run once per mount (UI-RUNTIME-001), structural changes stay
-- keyed and minimal (UI-RUNTIME-002), and churn is registry-neutral
-- (UI-LIFE-002). Same Check shape as suite.luau.

local contract = require("../../src/core/contract")
local Compose = require("../../src/vendor/compose/core")
local observeChange = require("../../src/core/on_change")
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
			local scope = core.owner.createChild()
			local factoryRuns = 0
			-- the "component": builds the row's state graph exactly once
			local function rowFactory()
				factoryRuns += 1
				local draft = Compose.cell(false)
				local status = Compose.cell("idle")
				local label = Compose.withOwner(scope, function()
					return Compose.formula(function(use)
						return `music: {use(draft) and "on" or "off"} ({use(status)})`
					end)
				end)
				return { draft = draft, status = status, label = label }
			end
			local row = rowFactory()
			local renders = 0
			observeChange(scope, row.label, function()
				renders += 1
			end)
			-- non-structural updates: toggle five times, then a save mutation
			for _ = 1, 5 do
				row.draft:set(not row.draft:peek())
			end
			core.reactor:batch(function()
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
			local scope = core.owner.createChild()
			local factoryRuns = 0
			local function hudFactory()
				factoryRuns += 1
				local speed = Compose.cell(0)
				local shown = Compose.withOwner(scope, function()
					return Compose.formula(function(use)
						return `{math.floor(use(speed))} sps`
					end)
				end)
				return { speed = speed, shown = shown }
			end
			local hud = hudFactory()
			local renderWrites = 0
			observeChange(scope, hud.shown, function()
				renderWrites += 1
			end)
			for i = 1, 100 do
				hud.speed:set(i)
			end
			local individual = renderWrites
			core.reactor:batch(function()
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
			local baseline = core.owner.size()
			local root = core.owner.createChild()
			-- ForEach-at-core-scale: keyed item scopes; add/remove/move only.
			local items: { [string]: { scope: contract.Owner, runs: number } } = {}
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
						local itemScope = root.createChild()
						Compose.cell(k)
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
			-- a Compose owner's size is one number: what it still holds
			local after = core.owner.size()
			if after ~= baseline then
				return false, `owner leaked: {baseline} -> {after}`
			end
			return true, nil
		end,
	},
}

return checks
