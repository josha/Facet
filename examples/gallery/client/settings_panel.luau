--!strict
-- THE SHOWCASE SETTINGS SURFACE — the second (and, by ruling, LAST) target the
-- showcase chrome carries.
--
-- WHY IT EXISTS. `[SHOWCASE-CHROME]: CONCERNS 16` (adversarial review,
-- 2026-08-12) rejected a third chip and scoped this replacement, and its
-- reasoning stands on its own arithmetic:
--
--   * A THIRD CHIP DOES NOT FIT. At 320 px the chrome has ~304 px of inner
--     width; two chips plus the gap already spend ~284 of it. Twenty pixels of
--     slack, and a chip needs ninety.
--   * "ONE CHIP PER AXIS" HAS NO TERMINATING CONDITION. Locale, `nativeStyle`
--     and `forceScrollFallback` are all queued behind motion and theme.
--   * THE HIERARCHY IS WRONG EITHER WAY. "Which demo" is a verb used constantly;
--     theme and motion are settings set once.
--
-- So the chrome carries exactly TWO targets forever — *which demo*, and
-- *settings* — and everything that is a SETTING lives in here: motion today,
-- theme today, whatever is queued tomorrow, at the cost of one more section in a
-- card that already scrolls.
--
-- TWO HALVES, like both pickers beside it:
--   1. the MODEL below is pure — the mode vocabulary, the mapping onto the one
--      environment fact, and what a choice asks the host to do. It requires
--      nothing and touches no engine API at module scope;
--      tests/gallery_chrome.spec.luau asserts it;
--   2. `mount()` builds the sections. Their proof is the chrome spec's solved
--      geometry and the live device pass.
--
-- === THE MOTION CONTROL IS "Full | Reduced", AND NEVER "on/off" ===
--
-- The environment fact is binary (`src/env/environment.luau:47`); the EFFECT is
-- not. `src/motion/motion.luau:31-42` is the authority: DECORATIVE motion snaps
-- (the exact layout already carries every fact, so deleting the travel deletes
-- nothing), while INFORMATIONAL motion KEEPS RUNNING to the same wall-clock
-- terminus and quantizes its output to 250 ms steps. A control labelled
-- "Motion: Off" teaches the opposite of the framework's proudest accessibility
-- claim, so the two words are peers here and the caption under them says what
-- the second one actually does.

local settings_panel = {}

-- the workspace attribute that hides the whole surface, matching the two pickers
settings_panel.ATTRIBUTE = "Facet_SettingsPanel"

-- THE TWO MODES, as a closed vocabulary rather than a boolean. `full` and
-- `reduced` are the two words the accessibility claim is about; nothing here
-- ever spells them "on" and "off".
settings_panel.MODES = table.freeze({ "full", "reduced" })

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED, for the same reason
	`with_animation.luau` and `card_rail.luau` export theirs: the pseudo-localization
	case in tests/gallery_chrome.spec.luau re-solves this surface with all of them
	expanded ~1.4x, and a check that cannot reach the strings cannot make that claim.
	Everything here is `policy = "none"` text: it must fit, wrapping where it has to,
	and never clip. ]]
settings_panel.COPY = table.freeze({
	preview = "Preview as",
	automatic = "Automatic",
	desktop = "Desktop",
	phone = "Phone",
	tablet = "Tablet",
	tv = "TV / 10-foot",
	orientation = "Orientation",
	portrait = "Portrait",
	landscape = "Landscape",
	input = "Input",
	pointer = "Mouse & keyboard",
	touch = "Touch",
	gamepad = "Gamepad",
	previewNote = "Phone and tablet layouts fit within this window. Automatic input follows the preview device, or your current device in Automatic preview.",
	viewingDistance = "Viewing distance",
	automaticDistance = "Automatic",
	nearDistance = "Nearby screen",
	tvDistance = "Distant TV",
	distanceNote = "Choose how far away you play. Controller input works with every screen size.",
	motion = "Motion",
	full = "Full",
	reduced = "Reduced",
	-- the caption is the teaching, not decoration: it is what stops "Reduced"
	-- being read as "off"
	motionNote = "Reduced removes decorative travel. Informational motion keeps running, in 250 ms steps.",
})

-- modeOf(reducedFact) -> the mode word for the environment fact.
function settings_panel.modeOf(reduced: any): string
	return if reduced == true then "reduced" else "full"
end

-- reducedOf(mode) -> the environment fact for a mode word. Anything that is not
-- the reduced word is full: an unknown mode must never silently REDUCE motion,
-- because that is the direction a player did not ask for.
function settings_panel.reducedOf(mode: any): boolean
	return mode == "reduced"
end

export type Command = { action: string, mode: string }

-- choose(current, mode) -> what the host should do. Choosing the mode already
-- live is a NO-OP rather than a redundant write: `reducedMotion` is a live fact
-- every motion consumer re-reads, and re-publishing it churns them for nothing.
-- An unknown word changes nothing at all.
function settings_panel.choose(current: string, mode: string): Command
	if mode ~= "full" and mode ~= "reduced" then
		return { action = "none", mode = current }
	end
	if mode == current then
		return { action = "none", mode = current }
	end
	return { action = "apply", mode = mode }
end

-- ===== the surface ==========================================================
-- Everything below needs a live Facet; nothing above does.

export type MountOpts = {
	Facet: any,
	core: any,
	env: any,
	-- the theme picker's own two sections (`theme_picker.mount(...).sections`),
	-- or nil when no packages replicated. Settings composes them rather than
	-- rebuilding them: one card, one scroller, one place a setting lives.
	themeSections: { any }?,
	preview: any?, -- client.environment_preview handle, supplied by the live host
	-- WHICH BUILD IS THIS. Passed in rather than read here, so this module stays
	-- engine-free like every other example surface; `init.client.luau` reads the
	-- Workspace attribute the place builder stamped.
	--
	-- It earns its pixels: on 2026-08-16 a device session reported "the playlist
	-- columns do not resize" against a place built 5h41m before the commit that
	-- added the resize. The report was correct and the build was stale, and
	-- nothing on screen could distinguish the two. A tester can now read the
	-- stamp and compare it against `git log -1 --format=%h`.
	buildStamp: string?,
	-- OVERRIDE THE COPY, for the pseudo-localization case only. Every fixture in
	-- this repo that exports its strings does so for the same reason (`card_rail`,
	-- `with_animation`): a check that cannot reach the strings cannot claim they
	-- survive ~1.4x expansion. Absent, the shipped table is used.
	copy: { [string]: string }?,
}

--[[ mount(opts) -> { sections, mode, setting, apply, dispose }

	THE PLACE-WIDE FACT, AND WHY THERE ARE TWO SIGNALS FOR IT.

	`setting` is the player's PREFERENCE — written only by a press on this
	control. `mode` is what is LIVE right now, mirrored from the environment fact
	so this control never contradicts the screen behind it.

	They differ exactly when a demo drives the fact itself, which one shipped
	demo deliberately does: `scenarios/with_animation.luau` writes
	`reducedMotion` from its own inline segmented control and restores whatever
	it found on dispose. That inline control is the demo teaching its own
	subject and stays; what changes is that the two now COMPOSE:

	  * flipping THIS control moves the live fact and the preference together, and
	    the demo's inline control follows it in the same frame (it reads the fact);
	  * flipping the DEMO's control moves only the live fact — a local override
	    for as long as that demo is on screen — and this control follows it, so
	    the settings card can never show "Full" over a reduced screen;
	  * the host calls `apply()` after every demo mount and teardown, so leaving
	    a demo returns the place to the PREFERENCE whichever control was touched
	    last. That is what makes this a setting rather than a demo's side effect.
]]
function settings_panel.mount(opts: MountOpts): any
	local Facet = opts.Facet
	local UI = Facet.View
	local core = opts.core
	local env = opts.env
	-- Preferences outlive each opening of the settings panel. The model is
	-- host-owned; UI.Picker creates and disposes its own mounted control.
	local scope = core:scope("gallery-settings-panel")
	local COPY: any = opts.copy or settings_panel.COPY

	local reducedFact = env:get("reducedMotion")
	local initial = settings_panel.modeOf(reducedFact:get())
	-- the preference (a press on this control is its only writer)
	local setting = scope:own(core:signal(initial))
	-- what is live (mirrors the fact, and is what the picker shows)
	local mode = scope:own(core:memo(function(use)
		return settings_panel.modeOf(use(reducedFact))
	end))

	local function applyMode(value: string)
		local command = settings_panel.choose(settings_panel.modeOf(reducedFact:get()), value)
		if command.action == "none" then
			return
		end
		-- `motionPolicy` is DERIVED from this fact and refuses a direct write,
		-- which is the right refusal: there is one source of truth and this is it.
		env:set("reducedMotion", settings_panel.reducedOf(command.mode))
	end

	-- The preference outlives the card; its view and subscriptions do not.
	local MotionSettings = Facet.component(function(ui)
		local View = Facet.View
		return View.VStack({
			id = "Motion",
			width = View.fill(),
			gap = "xs",
			View.Picker({
				id = "MotionMode",
				label = COPY.motion,
				style = "segmented",
				options = {
					{ value = "full", label = COPY.full },
					{ value = "reduced", label = COPY.reduced },
				},
				selected = ui.read(mode),
				onChange = function(value)
					setting:set(value)
					applyMode(value)
				end,
			}),
			View.Text({
				id = "Note",
				text = COPY.motionNote,
				textSize = "caption",
				role = "secondary",
				width = View.fill(),
			}),
		})
	end)
	local motionSection = MotionSettings({})

	local previewProfile = scope:own(core:signal("automatic"))
	local previewOrientation = scope:own(core:signal("portrait"))
	local previewInput = scope:own(core:signal("automatic"))
	local distanceSetting = scope:own(core:signal(env:get("viewingDistance"):get()))
	local function setDistance(value: string): boolean
		if value ~= "automatic" and value ~= "near" and value ~= "ten-foot" then
			return false
		end
		distanceSetting:set(value)
		if opts.preview ~= nil then
			opts.preview.setProfile("automatic")
			previewProfile:set("automatic")
			opts.preview.source:set("viewingDistance", value)
		else
			env:set("viewingDistance", value)
		end
		return true
	end
	local distancePicker = UI.Picker({
		id = "ViewingDistance",
		label = COPY.viewingDistance,
		env = env,
		selected = distanceSetting,
		options = {
			{ value = "automatic", label = COPY.automaticDistance },
			{ value = "near", label = COPY.nearDistance },
			{ value = "ten-foot", label = COPY.tvDistance },
		},
		onChange = function(value)
			setDistance(value)
		end,
	})
	local sections: { any } = {
		UI.VStack({
			id = "Distance",
			width = UI.fill(),
			gap = "xs",

			distancePicker,
			UI.Text({
				id = "Note",
				text = COPY.distanceNote,
				width = UI.fill(),
				textSize = "caption",
				role = "secondary",
			}),
		}),
		motionSection,
	}
	local function setPreview(value: string): boolean
		if opts.preview == nil or not opts.preview.setProfile(value) then
			return false
		end
		previewProfile:set(value)
		-- The profile owns distance; clear the independent legacy override.
		distanceSetting:set("automatic")
		return true
	end
	local function setOrientation(value: string): boolean
		if opts.preview == nil or not opts.preview.setOrientation(value) then
			return false
		end
		previewOrientation:set(value)
		return true
	end
	local function setInput(value: string): boolean
		if opts.preview == nil or not opts.preview.setInput(value) then
			return false
		end
		previewInput:set(value)
		return true
	end
	if opts.preview ~= nil then
		local function picker(id, label, selected, values, onChange, enabled)
			local options = {}
			for _, value in values do
				table.insert(options, { value = value, label = COPY[value] })
			end
			return UI.Picker({
				id = id,
				label = label,
				valueAlignment = "start",
				env = env,
				selected = selected,
				options = options,
				onChange = onChange,
				enabled = enabled,
			})
		end
		-- Display presets replace the distance-only surface in the showcase.
		local Display = Facet.component(function(ui)
			local profile = ui.read(previewProfile)
			return UI.VStack({
				id = "Display",
				width = UI.fill(),
				gap = "s",

				picker(
					"Preview",
					COPY.preview,
					previewProfile,
					{ "automatic", "desktop", "phone", "tablet", "tv" },
					setPreview,
					true
				),
				picker(
					"Orientation",
					COPY.orientation,
					previewOrientation,
					{ "portrait", "landscape" },
					setOrientation,
					function()
						local value = profile()
						return value == "phone" or value == "tablet"
					end
				),
				picker(
					"Input",
					COPY.input,
					previewInput,
					{ "automatic", "pointer", "touch", "gamepad" },
					setInput,
					true
				),
				UI.Text({
					id = "Note",
					text = COPY.previewNote,
					width = UI.fill(),
					textSize = "caption",
					role = "secondary",
				}),
			})
		end)
		sections[1] = Display({})
	end
	if opts.buildStamp ~= nil and opts.buildStamp ~= "" then
		table.insert(
			sections,
			UI.VStack({
				id = "Build",
				width = UI.fill(),
				gap = "xs",

				UI.Text({
					id = "Stamp",
					text = `build {opts.buildStamp}`,
					textSize = "caption",
					role = "secondary",
					-- WRAPS, never clips: a sha plus a timestamp is long, and this
					-- is the one line whose whole job is being read exactly.
					width = UI.fill(),
				}),
			})
		)
	end
	for _, section in opts.themeSections or {} do
		table.insert(sections, section)
	end

	--[[ THE DEDICATED CHIP IS RETIRED (stabilization B3, 2026-09-07). This surface
		used to build its own `chip`/`iconChip` pair for the chrome's strip — a
		second, always-visible button whose only job was opening straight to this
		section. `showcase_chrome.luau` no longer reads them: Settings is reached
		through the panel's own "Section" switch (Demos/Settings), which is already
		how a keyboard or a pad player gets here (Tab/d-pad onto the switch, or the
		`SECTION_GAMEPAD` shoulder), and a mouse/touch player now takes the same
		route rather than a shortcut a second widget existed only to offer. Nothing
		here builds a `Button` or a `UI.Button`-shaped chip any more; `COPY.chip`
		and the `onChip` option went with it — see git history for the removed
		shape if a future surface needs it back. ]]

	return {
		sections = sections,
		previewProfile = previewProfile,
		previewOrientation = previewOrientation,
		previewInput = previewInput,
		setPreview = setPreview,
		setOrientation = setOrientation,
		setInput = setInput,
		viewingDistance = distanceSetting,
		setViewingDistance = setDistance,
		-- the live fact's mirror (what the picker shows)
		mode = mode,
		-- the preference (only a press on this control writes it)
		setting = setting,
		-- re-assert the preference onto the fact. The host calls this after every
		-- demo mount and teardown; see the header for why that is what makes this
		-- a setting rather than a demo's side effect.
		apply = function()
			applyMode(setting:get())
			if opts.preview ~= nil then
				opts.preview.apply()
			end
			if opts.preview == nil or distanceSetting:get() ~= "automatic" then
				env:set("viewingDistance", distanceSetting:get())
			end
		end,
		-- the scriptable route a pointer-free drive takes, and the SAME call the
		-- picker press makes rather than a parallel one that can rot on its own
		setMode = function(value: string): boolean
			local command = settings_panel.choose(mode:get(), value)
			if command.action == "none" then
				return false
			end
			setting:set(command.mode)
			applyMode(command.mode)
			return true
		end,
		dispose = function()
			scope:dispose()
		end,
	}
end

return settings_panel
