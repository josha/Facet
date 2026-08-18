--!strict
-- Input hint helper (ADR-0013 WP-4; ui_todo §0). A minimal, documented framework
-- affordance so a consumer surfaces the CORRECT affordance label for an action
-- ("Enter" on keyboard, "A" on gamepad, "Tap" on touch) with no hand-built memo.
--
-- inputHint(core, env, action, opts?) -> Readable<string>
--   opts.style = "key" (default, the bare label) | "phrase" ("Tap" / "Press Enter")
--   opts.scope = the scope that owns the returned memo (see the ownership note
--     at the foot of this comment)
--   Tracks env's effectiveInput fact and resolves the action's preferredBinding
--   for that input class (src/input/actions.luau). The label prefers the
--   binding's displayName, falling back to its keyCode / uiButton; when no
--   binding matches the current input class the hint is "" (nil-tolerant, per the
--   engine spike). It is a plain reactive memo — mount it as any Text's `text`
--   prop; a preferredInput flip re-labels with NO remount.
--
-- This never injects visible UI on its own. OWNERSHIP is the same idiom as this
-- helper's nearest sibling, `adaptive.conditions(core, env, opts?)`
-- (api-architecture-consistency F-33): pass `opts.scope` and the memo dies with
-- the scope; omit it and the caller owns the memo by hand (dispose it with the
-- rest of the screen's resources). One memo instead of twelve is a reason to
-- care less, not a reason for two calls that look identical to want two
-- different disposal disciplines.

local specGuard = require("../spec_guard")

local hint = {}

-- resolve a binding to a display label, preferring displayName
local function labelOf(binding: any): string
	if binding == nil then
		return ""
	end
	return binding.displayName or binding.keyCode or binding.uiButton or ""
end

-- `style = "phrase"`: the whole affordance, not just the key (director,
-- 2026-07-29 — "if we built the framework right, I'm not sure there would be any
-- uses of preferred input outside it"). The gallery was hand-rolling
-- "Tap Save to apply" / "Press A to apply" / "Press Enter to apply" from the raw
-- platform fact, which is a consumer branching on input class to write copy —
-- exactly the thing this repo forbids for layout and had no equivalent for in
-- text. A key label alone could not remove that branch, because touch does not
-- differ by KEY, it differs by VERB: you tap, you do not press Enter. So the
-- framework answers the verb too and the consumer writes one template.
export type Opts = {
	style: string?, -- "key" (default) | "phrase"
	scope: any?, -- owns the returned memo, like `adaptive.conditions`
}

-- CLOSED OPTS (constitution §4; ARCH-1): the unknown VALUE was already refused
-- loudly below; the unknown KEY was not, so `{ Style = "phrase" }` fell through
-- to the default with the same silence the value check exists to remove.
local HINT_OPTS_KEYS = specGuard.keySet({ "scope", "style" })

function hint.inputHint(core: any, env: any, action: any, opts: Opts?): any
	specGuard.assertKnownKeys("inputHint", opts, HINT_OPTS_KEYS, "opts")
	local style = if opts ~= nil and opts.style ~= nil then opts.style else "key"
	-- an unknown style is refused LOUDLY, the way `rootPolicy` / `cancelPolicy` /
	-- `responder` / `scrim` are: `style = "Phrase"` used to yield the bare key
	-- label, which is the silent-default failure this library does not have.
	if style ~= "key" and style ~= "phrase" then
		error(`Facet inputHint: unknown style '{tostring(style)}'. Valid: key, phrase.`, 0)
	end
	local memo = core:memo(function(use)
		-- the RESOLVED class, not the raw platform report: a phone nobody has
		-- touched yet still reports KeyboardAndMouse, and this label is exactly the
		-- kind of affordance that must not say "Enter" on a touchscreen
		local preferred = use(env:get("effectiveInput"))
		local binding = if action ~= nil then action.preferredBinding(preferred) else nil
		local label = labelOf(binding)
		if style ~= "phrase" then
			return label
		end
		if preferred == "Touch" then
			-- a touch affordance names the GESTURE, never a key; it stays a phrase
			-- even when the action declares no touch binding, because "tap it" is
			-- true of anything on screen
			return "Tap"
		end
		return if label ~= "" then `Press {label}` else ""
	end)
	if opts ~= nil and opts.scope ~= nil then
		return opts.scope:own(memo)
	end
	return memo
end

return hint
