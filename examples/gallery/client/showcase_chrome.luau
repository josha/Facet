--!strict
local showcase_chrome = {}
showcase_chrome.KINDS = table.freeze({ "demos", "settings" })
showcase_chrome.COPY = table.freeze({
	section = "Section",
	demos = "Demos",
	settings = "Settings",
})
showcase_chrome.TOGGLE_KEYBOARD = "Backquote"
showcase_chrome.SECTION_GAMEPAD = table.freeze({ demos = "ButtonL1", settings = "ButtonR1" })
showcase_chrome.SECTION_GLYPH = table.freeze({ demos = "LB", settings = "RB" })
showcase_chrome.PANEL_ID = "ShowcasePanel"
function showcase_chrome.overscanEdge(distanceProfile: any, insets: any, edge: string): number
	if distanceProfile ~= "ten-foot" then
		return 0
	end
	local v = if type(insets) == "table" then (insets :: any)[edge] else nil
	return if type(v) == "number" and v == v and v > 0 then v else 0
end
function showcase_chrome.otherKind(current: string): string
	return if current == "settings" then "demos" else "settings"
end
export type ToggleCommand = { action: string, kind: string }
function showcase_chrome.toggle(open: boolean, current: string, want: string?): ToggleCommand
	if want == nil then
		return if open then { action = "close", kind = current } else { action = "open", kind = current }
	end
	if open and current == want then
		return { action = "close", kind = current }
	end
	return { action = "open", kind = want }
end
export type MountOpts = {
	Facet: any,
	core: any,
	env: any,
	presenter: any,
	actionSystem: any,
	demos: any,
	settings: any,
	coreTop: any,
	navigationLayout: any?,
	onChipsBottom: ((number) -> ())?,
	onChipsRect: ((any) -> ())?,
	copy: { [string]: string }?,
}
function showcase_chrome.mount(opts: MountOpts): any
	local Facet = opts.Facet
	local UI = Facet.View
	local core = opts.core
	local presenter = opts.presenter
	-- This host model coordinates independently mounted bar and panel surfaces.
	-- View-only state and calculations belong to the components below.
	local scope = core:scope("showcase-chrome")
	local COPY: any = opts.copy or showcase_chrome.COPY
	local kind = scope:own(core:signal("demos"))
	local open = scope:own(core:signal(false))
	local self: any = {}
	local PANEL_ID = showcase_chrome.PANEL_ID
	local toggleContext = opts.actionSystem.createContext({
		name = "ShowcaseChromeToggle",
		priority = presenter.APP_CHROME_PRIORITY,
		sink = true,
	})
	local toggleAction = toggleContext.createAction("Activate", "Bool")
	toggleAction.bind({ keyCode = showcase_chrome.TOGGLE_KEYBOARD })
	toggleAction.onPressed(function()
		self.requestFromNavigation(nil)
	end)
	local sectionAction: { [string]: any } = {}
	for _, kindName in showcase_chrome.KINDS do
		local action = toggleContext.createAction(`Activate{kindName}`, "Bool")
		action.bind({
			keyCode = showcase_chrome.SECTION_GAMEPAD[kindName],
			displayName = showcase_chrome.SECTION_GLYPH[kindName],
		})
		action.onPressed(function()
			self.requestFromNavigation(kindName)
		end)
		sectionAction[kindName] = action
	end
	local hintLabel: { [string]: any } = {}
	for _, kindName in showcase_chrome.KINDS do
		hintLabel[kindName] = Facet.inputHint(core, opts.env, sectionAction[kindName], { scope = scope })
	end
	local Bar = Facet.component(function(ui)
		local input = ui.env("effectiveInput")
		local distanceProfile, overscanInsets = ui.env("distanceProfile"), ui.env("effectiveOverscanInsets")
		local gamepadActive = function()
			return input() == "Gamepad"
		end
		local function shoulderHint(kindName: string): any
			local text = hintLabel[kindName]
			return UI.When({
				id = `{string.upper(string.sub(kindName, 1, 1))}{string.sub(kindName, 2)}Hint`,
				condition = gamepadActive,
				thenView = function()
					return UI.Text({
						id = "Glyph",
						text = text,
						textSize = "caption",
						role = "secondary",
					})
				end,
			})
		end
		local overscanPadding = ui.memo(function()
			local profile = distanceProfile()
			local insets = overscanInsets()
			return {
				top = showcase_chrome.overscanEdge(profile, insets, "top"),
				bottom = showcase_chrome.overscanEdge(profile, insets, "bottom"),
				left = showcase_chrome.overscanEdge(profile, insets, "left"),
				right = showcase_chrome.overscanEdge(profile, insets, "right"),
			}
		end)
		local NATURAL = { type = "content" }
		local function layoutChoice()
			if opts.navigationLayout == nil then
				return nil
			end
			local navigationNow = ui.read(opts.navigationLayout)
			local function placement()
				local navigation = navigationNow()
				return if navigation then ui.read(navigation.placement)() else nil
			end
			return UI.When({
				id = "NavigationChoice",
				condition = function()
					local current = placement()
					return distanceProfile() ~= "ten-foot" and (current == "sidebar" or current == "topBar")
				end,
				UI.Button({
					id = "ToggleSidebar",
					label = function()
						return if placement() == "sidebar" then "Use top tabs" else "Use sidebar"
					end,
					onActivate = function()
						local navigation = navigationNow()
						if navigation then
							navigation.toggle()
						end
						self.barHandle().resign()
					end,
				}),
			})
		end
		local chipRow = UI.ViewThatFits({
			id = "Chips",
			width = UI.fill(),
			UI.HStack({
				id = "Full",
				gap = "s",
				width = NATURAL,
				shoulderHint("demos"),
				opts.demos.chip,
				shoulderHint("settings"),
				layoutChoice(),
			}),
			UI.HStack({
				id = "Icons",
				gap = "s",
				width = NATURAL,
				shoulderHint("demos"),
				opts.demos.iconChip,
				shoulderHint("settings"),
				layoutChoice(),
			}),
		})
		return UI.Screen({
			id = "ShowcaseChrome",
			padding = "gutter",
			UI.Anchor({
				id = "Dock",
				padding = overscanPadding,
				width = UI.fill(),
				height = UI.fill(),
				UI.VStack({
					id = "Bar",
					anchor = "topLeft",
					offsetY = opts.coreTop,
					width = UI.fill(),
					chipRow,
				}),
			}),
		})
	end)
	local barScreen = Bar({})
	local Panel = Facet.component(function(ui)
		local section = ui.read(kind)
		local sectionPicker = UI.Picker({
			id = "Section",
			label = COPY.section,
			style = "segmented",
			options = {
				{ value = "demos", label = COPY.demos },
				{ value = "settings", label = COPY.settings },
			},
			selected = kind,
		})
		return UI.Screen({
			id = PANEL_ID,
			padding = "gutter",
			UI.Anchor({
				id = "Dock",
				width = UI.fill(),
				height = UI.fill(),
				UI.VStack({
					id = "Column",
					anchor = "topLeft",
					width = UI.fill(),
					height = UI.fill(),
					UI.ScrollView({
						id = "Panel",
						surface = "raised",
						padding = "s",
						gap = "s",
						width = UI.hug(),
						height = UI.hug(),
						sectionPicker,
						UI.When({
							id = "DemosWhen",
							condition = function()
								return section() == "demos"
							end,
							thenView = function()
								return opts.demos.rows
							end,
						}),
						UI.When({
							id = "SettingsWhen",
							condition = function()
								return section() == "settings"
							end,
							thenView = function()
								return UI.VStack({
									id = "Settings",
									width = UI.fill(),
									gap = "m",
									children = opts.settings.sections,
								})
							end,
						}),
					}),
				}),
			}),
		})
	end)
	local panelScreen = Panel({})
	local barHandle: any = nil
	local panelHandle: any = nil
	local panelWatch: (() -> ())? = nil
	local closing = false
	local barOpts = {
		responder = "passive",
		focusChrome = "top",
		rootPolicy = "edgeToEdge",
		onGeometry = function(rectOf: (string) -> any)
			local r = rectOf("/ShowcaseChrome/Dock/Bar/Chips")
			if type(r) ~= "table" or type(r.y) ~= "number" or type(r.h) ~= "number" then
				return
			end
			if opts.onChipsBottom ~= nil then
				opts.onChipsBottom(r.y + r.h)
			end
			if opts.onChipsRect ~= nil then
				local best: any = nil
				for _, rung in { "Full", "Icons" } do
					local c = rectOf(`/ShowcaseChrome/Dock/Bar/Chips/{rung}`)
					if type(c) == "table" and type(c.w) == "number" and c.w > 0 and c.h > 0 then
						if best == nil or c.w > best.w then
							best = c
						end
					end
				end
				opts.onChipsRect(best or r)
			end
		end,
	}
	local lastPanelFocus: string? = nil
	local PANEL_ROOT = `/{PANEL_ID}`
	local function isPanelPath(path: any): boolean
		if type(path) ~= "string" then
			return false
		end
		return path == PANEL_ROOT or string.sub(path, 1, #PANEL_ROOT + 1) == `{PANEL_ROOT}/`
	end
	scope:own(core:observe(presenter.focus.focused, function(path: any)
		if isPanelPath(path) then
			lastPanelFocus = path
		end
	end))
	local function closePanel()
		if panelHandle == nil then
			return
		end
		closing = true
		if panelWatch ~= nil then
			panelWatch()
			panelWatch = nil
		end
		presenter.dismiss(panelHandle)
		panelHandle = nil
		closing = false
		lastPanelFocus = nil
		open:set(false)
	end
	local function openPanel()
		if panelHandle ~= nil then
			return
		end
		if barHandle ~= nil then
			barHandle.resign()
		end
		panelHandle = presenter.present(panelScreen, {
			responder = "passive",
			initialFocus = "first",
		})
		panelHandle.engage()
		open:set(true)
		panelWatch = core:observe(panelHandle.responder, function(state: any)
			if state == "passive" and not closing then
				closePanel()
			end
		end)
	end
	local function raisePanel(demoHandle: any?)
		if panelHandle == nil then
			return
		end
		if demoHandle == nil then
			return
		end
		local wantFocus = lastPanelFocus
		presenter.raise(panelHandle)
		if wantFocus ~= nil then
			presenter.focus.focusOn(wantFocus)
		end
	end
	if opts.demos ~= nil and opts.demos.watchRaise ~= nil then
		scope:own(opts.demos.watchRaise(raisePanel))
	end
	local function apply(command: ToggleCommand)
		if command.action == "close" then
			closePanel()
			return
		end
		if kind:get() ~= command.kind then
			kind:set(command.kind)
		end
		openPanel()
	end
	function self.request(want: string?)
		apply(showcase_chrome.toggle(open:get(), kind:get(), want))
	end
	function self.requestFromNavigation(want: string?)
		presenter.focus.setFocusOrigin("navigation")
		self.request(want)
	end
	local function syncDemoOpen()
		local flag = open:get() and kind:get() == "demos"
		if opts.demos.open ~= nil and opts.demos.open:get() ~= flag then
			opts.demos.open:set(flag)
		end
	end
	scope:own(core:observe(open, syncDemoOpen))
	scope:own(core:observe(kind, syncDemoOpen))
	syncDemoOpen()
	barHandle = presenter.present(barScreen, barOpts)
	self.open = open
	self.kind = kind
	self.barScreen = barScreen
	self.panelScreen = panelScreen
	function self.barHandle()
		return barHandle
	end
	function self.panelHandle()
		return panelHandle
	end
	function self.isOpen(): boolean
		return panelHandle ~= nil
	end
	function self.close()
		closePanel()
	end
	function self.dispose()
		closePanel()
		if barHandle ~= nil then
			presenter.dismiss(barHandle)
			barHandle = nil
		end
		toggleContext.destroy()
		scope:dispose()
	end
	return self
end
return showcase_chrome
