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
	-- the application the chrome mounts its bar and panel into
	app: any,
	-- the application's core, which `Facet.inputHint` derives its labels on
	core: any,
	env: any,
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
	local Facet, app = opts.Facet, opts.app
	local UI, Compose = app.controls, Facet.Compose
	local presenter = app.presenter
	-- This host model coordinates independently mounted bar and panel surfaces.
	-- View-only state and calculations belong to the components below.
	local COPY: any = opts.copy or showcase_chrome.COPY
	local kind = Compose.cell("demos")
	local open = Compose.cell(false)
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
		hintLabel[kindName] = Facet.inputHint(opts.core, opts.env, sectionAction[kindName])
	end
	local function when(id: string, condition: any, thenView: () -> any): any
		return UI.When(id)({
			Compose.show(condition, function()
				return UI.When("then")({ thenView() })
			end),
		})
	end
	local barHandle: any = nil
	local closeBar: (() -> ())? = nil
	local panelHandle = Compose.cell(nil :: any)
	local closePanelSurface: (() -> ())? = nil
	local closing = false
	local lastPanelFocus: string? = nil
	local PANEL_ROOT = `/{PANEL_ID}`
	local function isPanelPath(path: any): boolean
		if type(path) ~= "string" then
			return false
		end
		return path == PANEL_ROOT or string.sub(path, 1, #PANEL_ROOT + 1) == `{PANEL_ROOT}/`
	end
	local function closePanel()
		if panelHandle:peek() == nil then
			return
		end
		closing = true
		panelHandle:set(nil)
		local close = closePanelSurface
		closePanelSurface = nil
		if close ~= nil then
			close()
		end
		closing = false
		lastPanelFocus = nil
		open:set(false)
	end
	local function Bar()
		local input = opts.env:get("effectiveInput")
		local distanceProfile = opts.env:get("distanceProfile")
		local overscanInsets = opts.env:get("effectiveOverscanInsets")
		-- The chrome's watches live as long as the bar, which is the whole session.
		Compose.watch(function(use)
			local path = use(presenter.focus.focused)
			if isPanelPath(path) then
				lastPanelFocus = path
			end
		end)
		Compose.watch(function(use)
			local handle = use(panelHandle)
			if handle ~= nil and use(handle.responder) == "passive" and not closing then
				closePanel()
			end
		end)
		Compose.watch(function(use)
			local flag = use(open) and use(kind) == "demos"
			if opts.demos.open ~= nil and opts.demos.open:peek() ~= flag then
				opts.demos.open:set(flag)
			end
		end)
		local function gamepadActive(use)
			return use(input) == "Gamepad"
		end
		local function shoulderHint(kindName: string): any
			local text = hintLabel[kindName]
			return when(
				`{string.upper(string.sub(kindName, 1, 1))}{string.sub(kindName, 2)}Hint`,
				gamepadActive,
				function()
					return UI.Text("Glyph")({
						text = text,
						textSize = "caption",
						role = "secondary",
					})
				end
			)
		end
		local overscanPadding = Compose.formula(function(use)
			local profile = use(distanceProfile)
			local insets = use(overscanInsets)
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
			local function placement(use)
				local navigation = use(opts.navigationLayout)
				return if navigation then use(navigation.placement) else nil
			end
			return UI.When("NavigationChoice")({
				Compose.show(function(use)
					local current = placement(use)
					return use(distanceProfile) ~= "ten-foot" and (current == "sidebar" or current == "topBar")
				end, function()
					return UI.Button("ToggleSidebar")({
						label = function(use)
							return if placement(use) == "sidebar" then "Use top tabs" else "Use sidebar"
						end,
						onActivate = function()
							local navigation = opts.navigationLayout:peek()
							if navigation then
								navigation.toggle()
							end
							self.barHandle().resign()
						end,
					})
				end),
			})
		end
		return UI.Screen("ShowcaseChrome")({
			padding = "gutter",
			UI.Anchor("Dock")({
				padding = overscanPadding,
				width = UI.fill(),
				height = UI.fill(),
				UI.VStack("Bar")({
					anchor = "topLeft",
					offsetY = opts.coreTop,
					width = UI.fill(),
					UI.ViewThatFits("Chips")({
						width = UI.fill(),
						UI.HStack("Full")({
							gap = "s",
							width = NATURAL,
							shoulderHint("demos"),
							opts.demos.chip(),
							shoulderHint("settings"),
							layoutChoice(),
						}),
						UI.HStack("Icons")({
							gap = "s",
							width = NATURAL,
							shoulderHint("demos"),
							opts.demos.iconChip(),
							shoulderHint("settings"),
							layoutChoice(),
						}),
					}),
				}),
			}),
		})
	end
	local function Panel()
		return UI.Screen(PANEL_ID)({
			padding = "gutter",
			UI.Anchor("Dock")({
				width = UI.fill(),
				height = UI.fill(),
				UI.VStack("Column")({
					anchor = "topLeft",
					width = UI.fill(),
					height = UI.fill(),
					UI.ScrollView("Panel")({
						surface = "raised",
						padding = "s",
						gap = "s",
						width = UI.hug(),
						height = UI.hug(),
						UI.Picker("Section")({
							label = COPY.section,
							style = "segmented",
							options = {
								{ value = "demos", label = COPY.demos },
								{ value = "settings", label = COPY.settings },
							},
							selected = kind,
						}),
						when("DemosWhen", function(use)
							return use(kind) == "demos"
						end, opts.demos.rows),
						when("SettingsWhen", function(use)
							return use(kind) == "settings"
						end, function()
							local settings: { any } = { width = UI.fill(), gap = "m" }
							for _, section in opts.settings.sections do
								table.insert(settings, section())
							end
							return UI.VStack("Settings")(settings)
						end),
					}),
				}),
			}),
		})
	end
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
	local function openPanel()
		if panelHandle:peek() ~= nil then
			return
		end
		if barHandle ~= nil then
			barHandle.resign()
		end
		local close, _, handle = app.mount(Panel, {
			responder = "passive",
			initialFocus = "first",
		})
		closePanelSurface = close
		handle.engage()
		open:set(true)
		panelHandle:set(handle)
	end
	local function raisePanel(demoHandle: any?)
		local handle = panelHandle:peek()
		if handle == nil then
			return
		end
		if demoHandle == nil then
			return
		end
		local wantFocus = lastPanelFocus
		presenter.raise(handle)
		if wantFocus ~= nil then
			presenter.focus.focusOn(wantFocus)
		end
	end
	local unwatchRaise: (() -> ())? = nil
	if opts.demos ~= nil and opts.demos.watchRaise ~= nil then
		unwatchRaise = opts.demos.watchRaise(raisePanel)
	end
	local function apply(command: ToggleCommand)
		if command.action == "close" then
			closePanel()
			return
		end
		if kind:peek() ~= command.kind then
			kind:set(command.kind)
		end
		openPanel()
	end
	function self.request(want: string?)
		apply(showcase_chrome.toggle(open:peek(), kind:peek(), want))
	end
	function self.requestFromNavigation(want: string?)
		presenter.focus.setFocusOrigin("navigation")
		self.request(want)
	end
	local mountedClose, _, mountedHandle = app.mount(Bar, barOpts)
	closeBar, barHandle = mountedClose, mountedHandle
	self.open = open
	self.kind = kind
	function self.barHandle()
		return barHandle
	end
	function self.panelHandle()
		return panelHandle:peek()
	end
	function self.isOpen(): boolean
		return panelHandle:peek() ~= nil
	end
	function self.close()
		closePanel()
	end
	function self.dispose()
		closePanel()
		if unwatchRaise ~= nil then
			unwatchRaise()
		end
		if closeBar ~= nil then
			closeBar()
			closeBar, barHandle = nil, nil
		end
		toggleContext.destroy()
	end
	return self
end
return showcase_chrome
