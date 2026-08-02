--!strict
-- ============================================================================
-- Example 3 of the LuauUI tutorial: a settings form that syncs to a server.
-- ============================================================================
--
-- WHAT THIS TEACHES  —  the client/server boundary in practice
--   * optimistic apply — a change shows in the UI IMMEDIATELY, before the
--                        server has agreed
--   * validated mutation — the change is sent as a request the server can
--                        accept or reject
--   * reconcile        — on accept the UI keeps the change and syncs to the
--                        new authoritative state; on reject it ROLLS BACK to
--                        server truth
--
-- The "server" here is an ordinary Lua table in this same file (a loopback),
-- exactly as a single-place gallery does. In a real game you would send the
-- mutation envelope over your replication layer instead of to this table.
--
-- deps used: none directly (see 01's header for the shared module shape).

local example = {}
example.title = "Settings Sync"

local VOLUME_MIN = 0
local VOLUME_MAX = 10 -- the server's validation rule; the UI does not clamp

function example.build(LuauUI: any, core: any, _deps: any)
	local UI = LuauUI.UI
	local replication = LuauUI.replication

	-- AUTHORITATIVE STATE (what the server has confirmed). A snapshot is the
	-- replicated truth; we start it at revision 1.
	local snapshot = replication.snapshot(core, 1, { music = false, volume = VOLUME_MAX })

	-- OPTIMISTIC DRAFT STATE (what the UI shows right now). These may run ahead
	-- of the server between send and confirm.
	local draftMusic = core:signal(snapshot.binding:get().music)
	local draftVolume = core:signal(snapshot.binding:get().volume)

	-- THE MUTATION: a validated request with a lifecycle idle -> pending ->
	-- confirmed | rejected. `optimistic.apply` runs the moment we send (so the
	-- UI updates instantly); `optimistic.restore` re-syncs the draft to server
	-- truth on either confirm (reconcile) or reject (roll back).
	local mutation = replication.mutation(core, {
		optimistic = {
			apply = function(payload)
				draftMusic:set(payload.music)
				draftVolume:set(payload.volume)
			end,
			restore = function()
				local truth = snapshot.binding:get()
				draftMusic:set(truth.music)
				draftVolume:set(truth.volume)
			end,
		},
	})

	-- THE LOOPBACK "SERVER". It holds one queued request (matching the single
	-- in-flight mutation), and `flush()` processes it the way a server would:
	-- validate, and on success bump the revision + replicate the new snapshot
	-- before confirming; on failure, reject with a reason.
	local server = {}
	server.pending = nil :: any
	function server.submit(envelope: any)
		server.pending = envelope
	end
	function server.flush()
		local envelope = server.pending
		if envelope == nil then
			return
		end
		server.pending = nil
		local payload = envelope.payload
		local valid = payload.volume >= VOLUME_MIN and payload.volume <= VOLUME_MAX
		if valid then
			-- replicate the new authoritative state, THEN confirm — so the
			-- reconcile step reads the fresh truth
			snapshot.ingest(snapshot.revision() + 1, { music = payload.music, volume = payload.volume })
			mutation.confirm(envelope.requestId, "ok")
		else
			mutation.reject(envelope.requestId, `volume must be {VOLUME_MIN}..{VOLUME_MAX}`)
		end
	end

	-- Send the current draft as a mutation. `send` runs optimistic.apply and
	-- moves the status to pending; we hand the envelope to the loopback server.
	local function commit(nextMusic: boolean, nextVolume: number)
		local envelope = mutation.send({ music = nextMusic, volume = nextVolume }, snapshot.revision())
		server.submit(envelope)
	end

	-- APP SEMANTICS (settings mutation) as node handlers referenced below;
	-- activating a control commits the change, dispatched by the presenter with
	-- no consumer routing (ADR-0013). The toggle's flip rides commit's apply.
	local function toggleMusic()
		commit(not draftMusic:get(), draftVolume:get())
	end
	local function volDown()
		commit(draftMusic:get(), draftVolume:get() - 1)
	end
	local function volUp()
		commit(draftMusic:get(), draftVolume:get() + 1)
	end

	-- BINDINGS for the read-outs.
	local volumeLabel = core:memo(function(use)
		return `Volume: {use(draftVolume)}`
	end)
	local statusLabel = core:memo(function(use)
		return `Status: {use(mutation.status)}`
	end)

	local screen = UI.Screen({
		id = "Settings",
		padding = 16,
		gap = 8,
		children = {
			UI.Text({ id = "Title", text = "Audio Settings", textSize = 24 }),
			-- A Toggle bound to the optimistic draft (see the node handlers above).
			UI.Toggle({ id = "Music", label = "Music", value = draftMusic, onActivate = toggleMusic }),
			-- A +/- volume stepper; the server validates 0..10.
			UI.HStack({
				id = "VolumeRow",
				gap = 8,
				children = {
					UI.Button({ id = "VolMinus", label = "–", onActivate = volDown }),
					UI.Text({ id = "VolValue", text = volumeLabel, textSize = 16 }),
					UI.Button({ id = "VolPlus", label = "+", onActivate = volUp }),
				},
			}),
			UI.Text({ id = "Status", text = statusLabel, textSize = 14 }),
		},
	})

	return {
		screen = screen,
		-- handles for the tutorial / tests:
		snapshot = snapshot, -- authoritative (server-confirmed) state
		draftMusic = draftMusic, -- optimistic UI state
		draftVolume = draftVolume,
		mutation = mutation, -- .status is idle|pending|confirmed|rejected
		server = server, -- call server.flush() to deliver the response
	}
end

return example
