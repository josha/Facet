--!strict
--[[ THE PLACEMENT AUDIT, SAID OUT LOUD.

	`placement_audit` has detected an inert placement prop since it was written,
	and `controller.diagnostics()` has carried the finding ever since — but a
	diagnostic nobody calls is a diagnostic nobody reads. Round 1 of the polish
	pass found SEVEN shipped instances in one showcase by calling it, which is
	seven authors who wrote a property, saw nothing move, and had no way to learn
	why. A property that is accepted must do something, or say that it did not.

	SO IT WARNS, ONCE PER SITE. `warn` is the channel this framework already
	announces a contained failure on (`core/services.report`, `solve_queue.report`),
	and the engine's output window is where an author is already looking.

	THREE PROPERTIES IT HAS TO HAVE, and each one is a constraint on where this
	code can live rather than a preference:

	  * ZERO COST WHEN THERE IS NOTHING TO SAY. A solve files no findings on the
	    overwhelming majority of frames, so the call site tests the list's length
	    and this module is not even entered. When it is, the dedupe key is built
	    only for a finding that is actually about an inert prop.

	  * ONCE, NOT ONCE PER FRAME. Layout re-solves whenever anything moves, and
	    the same static declaration would file the same finding every time — a
	    warning that repeats sixty times a second is noise, and noise is how a
	    real one gets missed. The key is the FILER, the named node and the prop:
	    the same triple `placement_audit` stamps its finding with, so two
	    different props on one node are two warnings and one prop on two nodes is
	    two warnings, while one prop on one node is one warning for the session.

	  * NOT IN A SHIPPED GAME. A player has no use for this and a live game
	    should spend nothing on it, so the switch defaults to OFF and the client
	    turns it on in Studio (`client/screen_target`). A host that wants it
	    elsewhere — a soak run, a QA build — calls `setEnabled(true)` itself.

	It is deliberately NOT in `render/renderer.luau`: that file stands ~800
	characters under the 200,000 at which Roblox refuses a script-driven `Source`
	assignment, so the call site there is one `if` and this is the rest. ]]

local placement_warnings = {}

-- OFF until a host says otherwise. The one default that cannot surprise anybody:
-- a shipped game prints nothing, and a headless spec run is silent unless it is
-- the spec that asked (`tests/inert_placement_warning.spec.luau`).
local enabled = false
local seen: { [string]: boolean } = {}

function placement_warnings.setEnabled(on: boolean)
	enabled = on == true
end

function placement_warnings.isEnabled(): boolean
	return enabled
end

--[[ WHERE THE SENTENCE GOES. Replaceable for the reason `solve_queue.report`'s
	is: a spec asserting this behaviour must read the message rather than print it
	through the suite, and the default is the engine's own `warn`. ]]
function placement_warnings.report(message: string)
	warn(message)
end

-- forget every deduped site (a spec's between-cases reset; never called by the
-- framework, which wants the memory to last the session)
function placement_warnings.reset()
	seen = {}
	enabled = false
end

--[[ THE ONE FINDING SHAPE THIS SPEAKS FOR. `placement_audit` files several kinds
	on the same list — overflow, containment, a collapsed content box — and only
	the inert-prop one is a declaration the author can fix by rewriting the prop.
	It is recognised by the three fields the audit stamps it with (`node`,
	`filedBy`, `issue`) plus the sentence's own opening, which the audit builds
	from the prop name: "`<prop>` is a placement prop this parent never reads".
	Reading the prop out of the sentence rather than re-deriving it keeps this
	module from carrying a second copy of the audit's own vocabulary. ]]
local function inertProp(finding: any): string?
	if type(finding) ~= "table" or type(finding.issue) ~= "string" or type(finding.filedBy) ~= "string" then
		return nil
	end
	return string.match(finding.issue, "^`([%w_]+)` is a placement prop this parent never reads")
end

--[[ notice(diagnostics) — say each NEW inert-prop finding once.

	Total and allocation-free on the common path: a list with nothing of this kind
	in it walks once and builds no strings. ]]
function placement_warnings.notice(diagnostics: { any }?)
	if not enabled or diagnostics == nil then
		return
	end
	for _, finding in diagnostics do
		local prop = inertProp(finding)
		if prop == nil then
			continue
		end
		local key = `{finding.filedBy}\0{tostring(finding.node)}\0{prop}`
		if seen[key] then
			continue
		end
		seen[key] = true
		placement_warnings.report(
			`Facet placement: '{tostring(finding.node)}' in '{finding.filedBy}' — {finding.issue}`
		)
	end
end

return placement_warnings
