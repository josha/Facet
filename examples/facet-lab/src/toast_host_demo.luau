--!strict
local Types = require("./catalog_types")

return function(c: Types.Context): Frame
	local C, UI, Host = c.Compose, c.UI, c.Host
	local paused = C.cell(false)
	local narrow = C.cell(false)
	local notices = C.cell({} :: { number })
	local finished = C.cell(0)
	local readingNotice = C.cell(false)
	local page = C.cell(1)
	local nextId = 0
	local host = Host.Frame {
		Name = "ToastHostDemo",
		Size = function(use: Types.Use)
			return c.types.UDim2.new(if use(narrow) then 0.65 else 1, 0, 0, 112)
		end,
		BackgroundTransparency = 1,
	}
	local context = c.ctx
	local noticesUI = c.Facet.controls(c.app.runtime, {
		types = c.types,
		theme = if context then context.theme else nil,
		environment = if context then context.environment else nil,
		motionLevel = if context then context.motionPreference else nil,
		toastParent = host,
		toastMaxVisible = 1,
		toastQueueCapacity = math.huge,
		toastPaused = paused,
	})
	return UI.VStack {
		gap = "xs",
		UI.Text { text = "Custom host · one visible · all queued" },
		UI.Button "ToastHostBurst" {
			label = "Queue 18 notices",
			onActivate = function()
				local list = table.clone(notices:peek())
				for _ = 1, 18 do
					nextId += 1
					table.insert(list, nextId)
				end
				notices:set(list)
			end,
		},
		UI.Button "ToastHostPause" {
			label = function(use: Types.Use)
				return if use(paused) then "Resume notices" else "Pause notices"
			end,
			onActivate = function()
				paused:set(not paused:peek())
			end,
		},
		UI.Button "ToastHostResize" {
			label = "Resize host",
			onActivate = function()
				narrow:set(not narrow:peek())
			end,
		},
		UI.Button "ToastHostClear" {
			label = "Clear notices",
			onActivate = function()
				notices:set({})
				readingNotice:set(false)
				paused:set(false)
				finished:set(0)
			end,
		},
		UI.Button "ToastHostReading" {
			label = "Queue two-part notice",
			onActivate = function()
				page:set(1)
				readingNotice:set(true)
			end,
		},
		UI.Text {
			text = function(use: Types.Use)
				return `Delivered: {use(finished)}`
			end,
		},
		host,
		noticesUI.Toast {
			message = function(use: Types.Use)
				return `Part {use(page)} of 2 · {if use(narrow) then "narrow" else "wide"}`
			end,
			isPresented = readingNotice,
			reading = function(use: Types.Use)
				use(page)
				use(narrow)
				return { duration = 3, readFloor = 1 }
			end,
			onPresentedChange = function(value, reason)
				if reason == "timeout" and page:peek() == 1 then
					page:set(2)
				else
					readingNotice:set(value)
				end
			end,
			onDismiss = c.log("readingDismiss"),
		},
		C.keyed {
			from = notices,
			key = function(id: number): number
				return id
			end,
			render = function(id: Types.ReadOnlyValue<number>): GuiObject
				return noticesUI.Toast {
					message = `Notice {id:peek()}`,
					duration = 1.5,
					readFloor = 1,
					onDismiss = function(reason)
						if reason == "timeout" then
							finished:set(finished:peek() + 1)
						end
						c.log("hostDismiss")(id:peek(), reason)
					end,
				}
			end,
		},
	}
end
