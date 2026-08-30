--!strict
-- ============================================================================
-- Example 3 of the Facet tutorial: a settings form that syncs to a server.
-- ============================================================================
--
-- WHAT THE PLAYER SEES  —  the client/server boundary, made watchable
--   Two read-outs, side by side and labelled, are the whole lesson:
--     "What you see now (your optimistic draft)"  — the UI's own state
--     "What the server has confirmed"             — authoritative truth
--   plus a status line, a one-line hint naming the next action, and a short
--   history of what happened.
--
--   Every state is reached from a control on the screen:
--     Music / – / +          send a change the server will ACCEPT
--     "Ask for volume 99"    send a change the server will REFUSE
--     "Deliver server reply" deliver the response — this is the moment the two
--                            read-outs reconcile, or the draft rolls back
--     "Reset demo"           return to the documented start state
--
-- WHAT IT TEACHES
--   * optimistic apply — the draft changes IMMEDIATELY, before the server has
--                        agreed, and the server read-out proves it has not
--   * validated mutation — the change travels as a request the server may
--                        accept or reject; pending NEVER means success
--   * reconcile        — on accept, draft and server converge on the new
--                        revision; on reject the draft ROLLS BACK to server
--                        truth and the refusal states its reason
--
-- The "server" here is an ordinary Lua table in this same file (a loopback),
-- exactly as a single-place gallery does. Its reply is queued and delivered by
-- the player, because *when the answer lands* is the thing this example is
-- about. In a real game you would send the mutation envelope over your
-- replication layer and deliver the response from your remote handler instead.
--
-- deps used: none directly (see 01's header for the shared module shape).

local example = {}
example.title = "Settings Sync"

local VOLUME_MIN = 0
local VOLUME_MAX = 10 -- the server's validation rule; the UI does not clamp
-- the documented start state, and what "Reset demo" restores
local START_MUSIC = false
local START_VOLUME = 10
-- a value the server is guaranteed to refuse, so the rejection path is one tap
local INVALID_VOLUME = 99
-- how many past events the screen shows (it has exactly this many rows)
local HISTORY_ROWS = 3

local function describeSettings(music: boolean, volume: number): string
	return `Music {if music then "on" else "off"}, volume {volume}`
end

function example.build(Facet: any, core: any, _deps: any)
	local UI = Facet.UI
	local replication = Facet.replication

	-- AUTHORITATIVE STATE (what the server has confirmed). A snapshot is the
	-- replicated truth; we start it at revision 1.
	local snapshot = replication.snapshot(core, 1, { music = START_MUSIC, volume = START_VOLUME })

	-- OPTIMISTIC DRAFT STATE (what the UI shows right now). These may run ahead
	-- of the server between send and confirm.
	local draftMusic = core:signal(snapshot.binding:get().music)
	local draftVolume = core:signal(snapshot.binding:get().volume)

	-- THE VISIBLE EVENT LOG, newest first and capped at the rows the screen has.
	-- A tutorial about a state machine has to show the transitions, not only the
	-- current state: a player who taps twice quickly needs to read what happened.
	local history = core:signal({ "Ready. Nothing sent yet." })
	local function log(line: string)
		local next = { line }
		for _, older in history:get() do
			if #next < HISTORY_ROWS then
				table.insert(next, older)
			end
		end
		history:set(next)
	end

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
	-- in-flight mutation) and answers it only when asked, the way a real server
	-- answers whenever it gets round to it: validate, and on success bump the
	-- revision + replicate the new snapshot before confirming; on failure,
	-- reject with a reason.
	--
	-- `deliver` is deliberately NOT called `flush`: the gallery host auto-flushes
	-- a `server.flush` every frame, which would answer before a player could ever
	-- watch a request be pending — and the pending state is the lesson.
	local server = {}
	server.queued = nil :: any
	function server.submit(envelope: any)
		server.queued = envelope
	end
	-- returns "accepted" | "rejected" | "empty"
	function server.deliver(): string
		local envelope = server.queued
		if envelope == nil then
			log("Nothing to deliver. Send a change first.")
			return "empty"
		end
		server.queued = nil
		local payload = envelope.payload
		if payload.volume >= VOLUME_MIN and payload.volume <= VOLUME_MAX then
			-- replicate the new authoritative state, THEN confirm — so the
			-- reconcile step reads the fresh truth
			snapshot.ingest(snapshot.revision() + 1, { music = payload.music, volume = payload.volume })
			mutation.confirm(envelope.requestId, "accepted")
			log(`Server accepted. Revision {snapshot.revision()}.`)
			return "accepted"
		end
		mutation.reject(envelope.requestId, `volume must be {VOLUME_MIN}..{VOLUME_MAX}`)
		log("Server rejected it. The draft rolled back.")
		return "rejected"
	end

	-- Send the current draft as a mutation. `send` runs optimistic.apply and
	-- moves the status to pending; we hand the envelope to the loopback server.
	--
	-- ONE REQUEST AT A TIME, REFUSED IN THE EXAMPLE. `mutation.send` THROWS while
	-- a request is in flight (that is the adapter's contract), and on a device
	-- that read as "I can toggle music on but not off" — the control worked once
	-- and then errored. A tutorial must not throw at a player for pressing a
	-- button twice, so the second press explains itself instead.
	local function requestChange(nextMusic: boolean, nextVolume: number, what: string)
		if mutation.status:get() == "pending" then
			log("Already waiting for a reply. Deliver it first.")
			return
		end
		local envelope = mutation.send({ music = nextMusic, volume = nextVolume }, snapshot.revision())
		server.submit(envelope)
		log(`Sent {what}. Waiting for the server.`)
	end

	-- APP SEMANTICS (settings mutation) as node handlers referenced below;
	-- activating a control commits the change, dispatched by the presenter with
	-- no consumer routing. The toggle's flip rides commit's apply.
	local function toggleMusic()
		local nextMusic = not draftMusic:get()
		requestChange(nextMusic, draftVolume:get(), `music {if nextMusic then "on" else "off"}`)
	end
	local function volDown()
		local nextVolume = draftVolume:get() - 1
		requestChange(draftMusic:get(), nextVolume, `volume {nextVolume}`)
	end
	local function volUp()
		local nextVolume = draftVolume:get() + 1
		requestChange(draftMusic:get(), nextVolume, `volume {nextVolume}`)
	end
	local function askInvalid()
		requestChange(draftMusic:get(), INVALID_VOLUME, `volume {INVALID_VOLUME}`)
	end
	local function deliverReply()
		server.deliver()
	end

	-- RESET. A revision only ever moves FORWARD (a snapshot refuses an older
	-- one), so the honest reset is the server writing the start values again at
	-- a new revision — not the client pretending the history never happened.
	-- `mutation.reset` is what abandons a request the server never answered, and
	-- it rolls that request's optimistic presentation back on the way out.
	local function resetDemo()
		server.queued = nil
		snapshot.ingest(snapshot.revision() + 1, { music = START_MUSIC, volume = START_VOLUME })
		mutation.reset()
		draftMusic:set(START_MUSIC)
		draftVolume:set(START_VOLUME)
		history:set({ `Reset. The server rewrote the start values. Revision {snapshot.revision()}.` })
	end

	-- BINDINGS for the read-outs. Each one is a memo over the state it reports,
	-- so the two halves of the lesson can never be drawn from the same source.
	local draftLabel = core:memo(function(use)
		return describeSettings(use(draftMusic), use(draftVolume))
	end)
	local serverLabel = core:memo(function(use)
		local truth = use(snapshot.binding)
		return `{describeSettings(truth.music, truth.volume)} (revision {snapshot.revision()})`
	end)
	local volumeLabel = core:memo(function(use)
		return `Volume: {use(draftVolume)}`
	end)
	local statusLabel = core:memo(function(use)
		local status = use(mutation.status)
		local result = use(mutation.lastResult)
		if status == "pending" then
			return "Status: pending (no reply yet)"
		elseif status == "confirmed" then
			return "Status: accepted"
		elseif status == "rejected" then
			return `Status: rejected ({tostring(result)})`
		end
		return "Status: idle"
	end)
	-- the status line says WHAT happened; this one says what to do next, which is
	-- what a player who has never read the source is missing
	local hintLabel = core:memo(function(use)
		local status = use(mutation.status)
		if status == "pending" then
			return 'Your screen already shows it. Press "Deliver server reply".'
		elseif status == "confirmed" then
			return "Draft and server agree."
		elseif status == "rejected" then
			return "The server refused it, so the draft rolled back."
		end
		return "Change a setting to send a request."
	end)
	-- STATE COLOUR IS SEMANTIC, never a literal: `danger` for a refusal, `accent`
	-- for an agreement, the resting content role otherwise.
	local statusTint = core:memo(function(use)
		local status = use(mutation.status)
		if status == "rejected" then
			return { role = "danger", blend = 1 }
		elseif status == "confirmed" then
			return { role = "accent", blend = 1 }
		end
		return { role = "content", blend = 1 }
	end)
	-- one memo per visible history row: a fixed row count keeps the panel's
	-- geometry still while the text inside it changes
	local function eventRow(index: number)
		return core:memo(function(use)
			return use(history)[index] or ""
		end)
	end

	-- The page scrolls: at the largest preferred-text setting on a compact phone
	-- this content is taller than the viewport, and a settings screen whose Reset
	-- button is off the bottom edge is not operable.
	local screen = UI.Screen({
		id = "Settings",
		surface = "base",
		padding = "m",
		children = {
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					-- EVERY LONG LINE ON THIS PAGE DECLARES ITS FULL-VALUE PATH (director
					-- ruling 5, 2026-08-13). On a 360px phone at the +14px preference
					-- under fantasy-parchment the theme's chrome leaves this box 294px
					-- and the word "Settings" alone measures 336px — so wrapping cannot
					-- succeed here (the engine would break the word) and the line
					-- ellipsizes instead. `disclose` is what the framework owes a reader
					-- when that happens; the compact-phone sweep re-proves it every run.
					UI.Text({ id = "Title", text = "Audio Settings", textSize = "title", disclose = true }),
					UI.Text({
						id = "Lesson",
						text = `The server accepts volume {VOLUME_MIN}..{VOLUME_MAX} only.`,
						textSize = "caption",
						role = "secondary",
					}),

					-- THE TWO STATES, ADJACENT AND NAMED. Everything else on this
					-- screen exists to move these two lines apart and back together.
					UI.VStack({
						id = "State",
						surface = "raised",
						padding = "m",
						gap = "xs",
						children = {
							UI.Text({
								id = "DraftHeading",
								text = "What you see now (your optimistic draft)",
								textSize = "caption",
								role = "secondary",
								disclose = true,
							}),
							UI.Text({ id = "Draft", text = draftLabel, textSize = "body" }),
							UI.Divider({ id = "StateRule" }),
							UI.Text({
								id = "ServerHeading",
								text = "What the server has confirmed",
								textSize = "caption",
								role = "secondary",
								disclose = true,
							}),
							UI.Text({ id = "Server", text = serverLabel, textSize = "body", disclose = true }),
						},
					}),

					UI.Text({ id = "Status", text = statusLabel, textSize = "label", tint = statusTint }),
					UI.Text({ id = "Hint", text = hintLabel, textSize = "caption", role = "secondary" }),

					-- A Toggle bound to the optimistic draft (see the node handlers
					-- above): it flips the instant you press it, and flips back if
					-- the server refuses.
					UI.Toggle({ id = "Music", label = "Music", value = draftMusic, onActivate = toggleMusic }),
					-- A +/- volume stepper; the server validates 0..10. `align`
					-- centres the read-out against the buttons — `alignV` is a
					-- ZStack-child property and is silently ignored here.
					UI.HStack({
						id = "VolumeRow",
						gap = "s",
						align = "center",
						-- THE ROW HAS TO CLAIM THE WIDTH BEFORE THE READ-OUT CAN FILL
						-- IT. Content-sized, the row was only as wide as its two
						-- buttons, so the `fill` read-out between them solved to 0x44
						-- and the volume was invisible — measured, not guessed.
						width = UI.fill(),
						children = {
							-- a one-glyph button is narrower than a finger: the floor
							-- is the theme's own minimum target, never a px literal
							UI.Button({
								id = "VolMinus",
								label = "–",
								width = { type = "minMax", min = "targetSizes.minimum" },
								onActivate = volDown,
							}),
							UI.Text({
								id = "VolValue",
								text = volumeLabel,
								textSize = "control",
								textAlign = "center",
								width = UI.fill(),
								disclose = true,
							}),
							UI.Button({
								id = "VolPlus",
								label = "+",
								width = { type = "minMax", min = "targetSizes.minimum" },
								onActivate = volUp,
							}),
						},
					}),
					-- the rejection path in ONE tap, so it needs no explaining: the
					-- Lesson line above already says which volumes the server takes
					UI.Button({ id = "AskInvalid", label = `Ask for volume {INVALID_VOLUME}`, onActivate = askInvalid }),
					UI.Button({ id = "Deliver", label = "Deliver server reply", onActivate = deliverReply }),
					UI.Button({ id = "Reset", label = "Reset demo", onActivate = resetDemo }),

					UI.VStack({
						id = "History",
						surface = "raised",
						padding = "m",
						gap = "xs",
						children = {
							UI.Text({
								id = "HistoryHeading",
								text = "What happened (newest first)",
								textSize = "caption",
								role = "secondary",
							}),
							UI.Text({ id = "Event1", text = eventRow(1), textSize = "caption" }),
							UI.Text({ id = "Event2", text = eventRow(2), textSize = "caption" }),
							UI.Text({ id = "Event3", text = eventRow(3), textSize = "caption" }),
						},
					}),
				},
			}),
		},
	})

	return {
		screen = screen,
		-- handles for the tutorial / tests. Every one of them is ALSO reachable
		-- from a control on the screen — none of them is the only route.
		snapshot = snapshot, -- authoritative (server-confirmed) state
		draftMusic = draftMusic, -- optimistic UI state
		draftVolume = draftVolume,
		mutation = mutation, -- .status is idle|pending|confirmed|rejected
		server = server, -- server.deliver() == the "Deliver server reply" button
		history = history, -- the visible event log, newest first
		reset = resetDemo, -- == the "Reset demo" button
	}
end

return example
