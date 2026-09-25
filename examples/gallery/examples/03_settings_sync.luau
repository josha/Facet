--!strict
local example = { title = "Settings Sync" }
function example.build(ctx: any)
	local UI, Compose = ctx.UI, ctx.Compose
	local server = Compose.cell({ music = false, volume = 10, revision = 1 })
	local draft = Compose.cell({ music = false, volume = 10 })
	local status = Compose.cell("idle")
	local history = Compose.cell({ "Ready. Nothing sent yet." })
	local pending: { music: boolean, volume: number }? = nil
	local function log(message)
		local lines = { message }
		for _, old in history:peek() do
			if #lines < 3 then
				table.insert(lines, old)
			end
		end
		history:set(lines)
	end
	local function request(music, volume)
		if pending then
			log("Already waiting for a reply. Deliver it first.")
			return
		end
		pending = { music = music, volume = volume }
		draft:set(pending)
		status:set("pending")
		log("Sent settings. Waiting for the server.")
	end
	local function deliver()
		if not pending then
			log("Nothing to deliver. Send a change first.")
			return "empty"
		end
		local proposed = pending
		pending = nil
		if proposed.volume >= 0 and proposed.volume <= 10 then
			server:set({ music = proposed.music, volume = proposed.volume, revision = server:peek().revision + 1 })
			status:set("confirmed")
			log("Server accepted. Both readouts agree.")
		else
			status:set("rejected")
			log("Server rejected volume outside 0..10. The draft rolled back.")
		end
		local truth = server:peek()
		draft:set({ music = truth.music, volume = truth.volume })
		return status:peek()
	end
	local function reset()
		pending = nil
		server:set({ music = false, volume = 10, revision = server:peek().revision + 1 })
		draft:set({ music = false, volume = 10 })
		status:set("idle")
		history:set({ "Reset. Nothing sent yet." })
	end
	local function text(name, value, role)
		return UI.Label(name)({ text = value, textRole = role, TextWrapped = true })
	end
	return {
		screen = function()
			return UI.ScrollView "SettingsSync" {
				gap = 12,
				padding = "m",
				align = "stretch",
				text("Title", "Settings sync", "title"),
				text(
					"Explanation",
					"Send a change, inspect the optimistic draft, then deliver the server reply.",
					"caption"
				),
				text("Draft", function(use)
					local value = use(draft)
					return `What you see now: music {if value.music then "on" else "off"}, volume {value.volume}`
				end),
				text("Confirmed", function(use)
					local value = use(server)
					return `Server confirmed: music {if value.music then "on" else "off"}, volume {value.volume} (revision {value.revision})`
				end),
				UI.Toggle "Music" {
					label = "Music",
					indicatorPosition = "trailing",
					value = function(use)
						return use(draft).music
					end,
					onChange = function(value)
						request(value, draft:peek().volume)
					end,
				},
				UI.Stepper "Volume" {
					label = "Volume",
					min = 0,
					max = 10,
					value = function(use)
						return use(draft).volume
					end,
					onChange = function(value)
						request(draft:peek().music, value)
					end,
				},
				UI.Button "Invalid" {
					label = "Ask for volume 99",
					onActivate = function()
						request(draft:peek().music, 99)
					end,
				},
				UI.Button "Deliver" { label = "Deliver server reply", appearance = "emphasis", onActivate = deliver },
				UI.Button "Reset" { label = "Reset demo", appearance = "link", onActivate = reset },
				text("Status", status, "caption"),
				text("History", function(use)
					return table.concat(use(history), "\n")
				end, "caption"),
			}
		end,
		request = request,
		deliver = deliver,
		reset = reset,
		report = function()
			return { draft = draft:peek(), server = server:peek(), status = status:peek(), history = history:peek() }
		end,
	}
end
return example
