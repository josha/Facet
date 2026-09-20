--!strict
local guard = require("../spec_guard")
local geometry = require("../layout/hud_insets")
local rect = require("../rect")
local Compose = require("../vendor/compose/core")
local KEYS = guard.keySet({ "id", "edge", "scope" })
local hud = {}

function hud.new(core: any): any
	local entries = {}
	local changed = Compose.cell(table.freeze({}))
	local function publish()
		local rows = {}
		for id, entry in entries do
			if entry.rect then
				table.insert(rows, table.freeze({ id = id, edge = entry.edge, rect = entry.rect }))
			end
		end
		table.sort(rows, function(a, b)
			return a.id < b.id
		end)
		changed:set(table.freeze(rows))
	end
	local function reserve(spec: any): any
		guard.assertKnownKeys("presenter.reserveHud", spec, KEYS, "spec")
		assert(type(spec.id) == "string" and #spec.id > 0, "presenter.reserveHud.id must be a nonempty string")
		assert(entries[spec.id] == nil, "presenter.reserveHud.id is already reserved")
		assert(
			spec.edge == "top" or spec.edge == "bottom" or spec.edge == "left" or spec.edge == "right",
			"presenter.reserveHud.edge must be top, bottom, left, or right"
		)
		--[[ A DISPOSED OWNER IS REFUSED, LOUDLY. Compose releases into a dead owner
			immediately and answers a no-op, so a reservation handed one would take
			the ID, release itself, and leave the caller holding a handle that never
			reserves anything. The refusal keeps the ID free for the next caller. ]]
		assert(
			spec.scope == nil
				or (
					type(spec.scope) == "table"
					and type(spec.scope.own) == "function"
					and type(spec.scope.isDisposed) == "function"
					and not spec.scope.isDisposed()
				),
			"presenter.reserveHud.scope must be a live owner"
		)
		local entry = { edge = spec.edge, rect = nil }
		local disposed = false
		local handle = {}
		function handle.update(value: any?)
			assert(not disposed, "Cannot update a disposed HUD reservation")
			if value then
				geometry.validateRect(value)
			end
			if rect.equal(entry.rect, value) then
				return
			end
			entry.rect = if value then table.freeze({ x = value.x, y = value.y, w = value.w, h = value.h }) else nil
			publish()
		end
		function handle.dispose()
			if disposed then
				return
			end
			disposed = true
			entries[spec.id] = nil
			if entry.rect then
				publish()
			end
		end
		if spec.scope then
			spec.scope.own(handle.dispose)
		end
		entries[spec.id] = entry
		return table.freeze(handle)
	end
	-- The consumer receives a Readable, never the writable signal authority.
	return { reserve = reserve, reservations = Compose.formula(function(use)
		return use(changed)
	end) }
end

return hud
