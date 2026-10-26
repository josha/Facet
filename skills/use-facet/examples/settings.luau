--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)

export type Effects = "Full" | "Reduced"
export type Values = { musicVolume: number, captions: boolean, visualEffects: Effects }
export type Completion = (accepted: boolean, message: string) -> ()
export type Callbacks = {
	save: (draft: Values, complete: Completion) -> (),
	onClose: () -> (),
}

local function copy(values: Values): Values
	return { musicVolume = values.musicVolume, captions = values.captions, visualEffects = values.visualEffects }
end

return {
	build = function(app: Facet.App, initial: Values, callbacks: Callbacks): Frame
		local C, UI = Facet.Compose, app.UI
		local Host = Facet.host(app.runtime)
		local env = UI.environment()
		local accepted: Facet.Value<Values> = C.cell(copy(initial))
		local volume = C.cell(math.clamp(initial.musicVolume, 0, 1))
		local captions = C.cell(initial.captions)
		local effects: Facet.Value<Effects> = C.cell(initial.visualEffects)
		local open, confirm = C.cell(true), C.cell(false)
		local pending, result = C.cell(false), C.cell("ready")
		local message = C.cell("")
		local alive, closed, request = true, false, 0
		C.cleanup(function()
			alive = false
			request += 1
		end)
		local function draft(): Values
			return { musicVolume = volume:peek(), captions = captions:peek(), visualEffects = effects:peek() }
		end
		local dirty = C.formula(function(use: Facet.Use): boolean
			local saved = use(accepted)
			return use(volume) ~= saved.musicVolume
				or use(captions) ~= saved.captions
				or use(effects) ~= saved.visualEffects
		end)
		local editable = C.formula(function(use: Facet.Use): boolean
			return not use(pending) and not use(confirm)
		end)
		local function changed()
			result:set("ready")
			message:set("")
		end
		local function finishClose()
			if closed then
				return
			end
			closed = true
			request += 1
			confirm:set(false)
			open:set(false)
			callbacks.onClose()
		end
		local function requestClose(nextOpen: boolean)
			if nextOpen or closed then
				return
			end
			if pending:peek() then
				return
			end
			if dirty:peek() then
				confirm:set(true)
			else
				finishClose()
			end
		end
		local function apply()
			if pending:peek() or confirm:peek() or closed or not dirty:peek() then
				return
			end
			local submitted = draft()
			request += 1
			local id = request
			local completed = false
			pending:set(true)
			result:set("pending")
			message:set("")
			local function complete(ok: boolean, detail: string)
				if completed or not alive or closed or id ~= request then
					return
				end
				completed = true
				if ok then
					accepted:set(copy(submitted))
					result:set("accepted")
				else
					result:set("rejected")
				end
				message:set(detail)
				pending:set(false)
			end
			local ok = pcall(function()
				callbacks.save(copy(submitted), complete)
			end)
			if not ok then
				complete(false, "Could not apply settings. Please try again.")
			end
		end
		local options: { Facet.PickerOption<Effects> } = {
			{ value = "Full", label = "Full" },
			{ value = "Reduced", label = "Reduced" },
		}
		local actions: { Facet.OverlayAction } = {
			{
				id = "ApplySettings",
				label = function(use: Facet.Use): string
					return if use(result) == "rejected" then "Retry Apply" else "Apply"
				end,
				role = "default",
				busy = pending,
				enabled = function(use: Facet.Use): boolean
					return use(dirty) and not use(pending) and not use(confirm)
				end,
				onActivate = apply,
			},
		}
		local detent = C.cell("hug")
		local detents: { Facet.SheetDetent } = { "hug", { id = "room", fraction = 0.95 } }
		C.watch(function(use: Facet.Use)
			detent:set(if use(env.isShort) then "room" else "hug")
		end)
		local bodyInset: Facet.Sides = { top = "s", bottom = "s", left = "m", right = "m" }
		local settings = UI.Sheet "ExplorationSettings" {
			isPresented = open,
			onPresentedChange = requestClose,
			title = "Settings",
			placement = "adaptive",
			width = "narrow",
			contentInset = "none",
			closeButton = "Close",
			detents = detents,
			detent = detent,
			initialFocus = "MusicVolume",
			actions = actions,
			content = function()
				return UI.VStack "SettingsBody" {
					width = "fill",
					align = "stretch",
					gap = "s",
					padding = bodyInset,
					UI.VStack "Sound" {
						width = "fill",
						align = "stretch",
						gap = "s",
						UI.Slider "MusicVolume" {
							label = "Music volume",
							value = volume,
							min = 0,
							max = 1,
							step = 0.05,
							enabled = editable,
							format = function(value: number): string
								return `{math.round(value * 100)}%`
							end,
							onChange = function(value: number)
								volume:set(value)
								changed()
							end,
						},
					},
					UI.VStack "Readability" {
						width = "fill",
						align = "stretch",
						gap = "s",
						UI.Toggle "Captions" {
							label = "Captions",
							value = captions,
							presentation = "switch",
							enabled = editable,
							onChange = function(value: boolean)
								captions:set(value)
								changed()
							end,
						},
						UI.Picker "VisualEffects" {
							label = "Visual effects",
							selected = effects,
							options = options,
							style = "automatic",
							enabled = editable,
							onChange = function(_value: Effects)
								changed()
							end,
						},
					},
					UI.Text "SaveStatus" {
						wrap = true,
						text = function(use: Facet.Use): string
							local state, detail = use(result), use(message)
							if state == "pending" then
								return "Applying settings… Please wait."
							end
							if state == "rejected" then
								return "Settings were not applied. Your changes are kept. " .. detail
							end
							if state == "accepted" then
								return "Settings applied. " .. detail
							end
							return if use(dirty) then "Unapplied changes" else "Current settings applied"
						end,
					},
				}
			end,
		}
		local discardActions: { Facet.OverlayAction } = {
			{
				id = "KeepEditing",
				label = "Keep editing",
				role = "cancel",
				onActivate = function()
					confirm:set(false)
				end,
			},
			{
				id = "DiscardChanges",
				label = "Discard changes",
				role = "destructive",
				onActivate = function()
					volume:set(accepted:peek().musicVolume)
					captions:set(accepted:peek().captions)
					effects:set(accepted:peek().visualEffects)
					finishClose()
				end,
			},
		}
		local resolutionDetents: { Facet.SheetDetent } = { "hug" }
		local resolution = UI.Sheet "ResolveDraft" {
			isPresented = confirm,
			title = "Leave without applying?",
			placement = "center",
			width = "narrow",
			detents = resolutionDetents,
			initialFocus = "KeepEditing",
			actionLayout = "stacked",
			actions = discardActions,
			content = function()
				return UI.Text {
					text = "Your changes have not been applied. Keep editing, or discard them and return to exploring.",
					wrap = true,
				}
			end,
		}
		return Host.Frame "Settings" { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), settings, resolution }
	end,
}
