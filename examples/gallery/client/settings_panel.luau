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
	-- the chip, and therefore the word the whole surface is named by
	chip = "Settings",
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
	-- what this surface's chip press means. The showcase chrome owns panel
	-- PRESENCE (showcase_chrome.luau §2), so the chip asks rather than toggling
	-- state of its own.
	onChip: (() -> ())?,
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

--[[ mount(opts) -> { chip, iconChip, sections, mode, setting, apply, dispose }

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
	local UI = Facet.UI
	local core = opts.core
	local env = opts.env
	local scope = core:scope("gallery-settings-panel")
	local COPY: any = opts.copy or settings_panel.COPY

	local reducedFact = env:get("reducedMotion")
	local initial = settings_panel.modeOf(reducedFact:get())
	-- the preference (a press on this control is its only writer)
	local setting = scope:own(core:signal(initial))
	-- what is live (mirrors the fact, and is what the picker shows)
	local mode = scope:own(core:signal(initial))

	local function applyMode(value: string)
		local command = settings_panel.choose(settings_panel.modeOf(reducedFact:get()), value)
		if command.action == "none" then
			return
		end
		-- `motionPolicy` is DERIVED from this fact and refuses a direct write,
		-- which is the right refusal: there is one source of truth and this is it.
		env:set("reducedMotion", settings_panel.reducedOf(command.mode))
	end

	-- FOLLOW THE FACT. A demo that drives `reducedMotion` itself moves this
	-- control with it; without this the card could show "Full" while the screen
	-- behind it was running reduced, which is a settings surface lying.
	scope:own(core:observe(reducedFact, function(value: any)
		local live = settings_panel.modeOf(value)
		if mode:get() ~= live then
			mode:set(live)
		end
	end))

	local motionPicker = Facet.Controls.Picker(core, {
		id = "MotionMode",
		label = COPY.motion,
		-- SEGMENTED, declared rather than adaptive: two short labels side by side
		-- ARE the teaching — "Full" and "Reduced" as peers, neither an off switch.
		presentation = "segmented",
		options = {
			{ value = "full", label = COPY.full },
			{ value = "reduced", label = COPY.reduced },
		},
		selected = mode,
		-- `onChange` fires ONLY on a press (`picker.choose`), never on the
		-- programmatic writes the observe above makes — which is exactly the
		-- split this needs: a press is the one thing that moves the PREFERENCE.
		onChange = function(value: any)
			local word = tostring(value)
			setting:set(word)
			applyMode(word)
		end,
	})

	local motionSection = UI.VStack({
		id = "Motion",
		width = UI.fill(),
		gap = "xs",
		children = {
			motionPicker.blueprint,
			-- WRAPS, never clips: this sentence is the difference between
			-- "Reduced" and "Off" and it has to survive ~1.4x pseudo-localization
			-- on a 320 px phone.
			UI.Text({
				id = "Note",
				text = COPY.motionNote,
				textSize = "caption",
				role = "secondary",
				width = UI.fill(),
			}),
		},
	})

	local sections: { any } = { motionSection }
	if opts.buildStamp ~= nil and opts.buildStamp ~= "" then
		table.insert(
			sections,
			UI.VStack({
				id = "Build",
				width = UI.fill(),
				gap = "xs",
				children = {
					UI.Text({
						id = "Stamp",
						text = `build {opts.buildStamp}`,
						textSize = "caption",
						role = "secondary",
						-- WRAPS, never clips: a sha plus a timestamp is long, and this
						-- is the one line whose whole job is being read exactly.
						width = UI.fill(),
					}),
				},
			})
		)
	end
	for _, section in opts.themeSections or {} do
		table.insert(sections, section)
	end

	-- THE CHIP, in both forms the chrome's ViewThatFits ladder needs. A chip is
	-- built here rather than by the host for the same reason the pickers build
	-- theirs: the label is this surface's word, not the chrome's.
	local function pressChip()
		if opts.onChip ~= nil then
			opts.onChip()
		end
	end
	local function chipOf(id: string, icon: string?): any
		if icon == nil then
			return UI.Button({ id = id, label = COPY.chip, surface = "chip", onActivate = pressChip })
		end
		-- `label` STAYS and is not drawn (blueprint_schema: "label stays the
		-- semantic name and is not drawn"), so the icon-only rung is still a
		-- control with an accessible name.
		return UI.Button({
			id = id,
			label = COPY.chip,
			surface = "chip",
			shape = "circle",
			icon = icon,
			onActivate = pressChip,
		})
	end

	return {
		chip = chipOf("SettingsToggle"),
		-- "more" is the framework's own ellipsis mark (src/themes/standard_icons):
		-- the standard set ships no gear, and inventing one would mean new art and
		-- an upload rather than a chrome restructure.
		iconChip = chipOf("SettingsToggleIcon", "more"),
		sections = sections,
		-- the live fact's mirror (what the picker shows)
		mode = mode,
		-- the preference (only a press on this control writes it)
		setting = setting,
		-- re-assert the preference onto the fact. The host calls this after every
		-- demo mount and teardown; see the header for why that is what makes this
		-- a setting rather than a demo's side effect.
		apply = function()
			applyMode(setting:get())
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
			motionPicker.dispose()
			scope:dispose()
		end,
	}
end

return settings_panel
