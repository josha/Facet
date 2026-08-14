--!strict
--[[ THE LARGE-TEXT CONTROL MATRIX (acceptance LT-8; policy LT-6).

	The plan's verification matrix says: "Headlessly sweep every public
	control/layout and representative composed screens at all four preference
	values, both reference themes, representative short and long locales, long
	unbroken names, mixed scripts, and reduced motion."

	This file is the CONTROL half of that sweep. Every row of
	tests/conformance/controls_registry — the same registry the extension checker
	enforces — is either mounted here in a compact 390x844 phone screen and swept
	at { 0, 4, 10, 14 } x { Studio Neutral, Fantasy Parchment }, or carries a
	declared reason why it cannot be. Enumerated from the registry rather than
	hand-picked, so the day a new control lands, the coverage case fails until
	someone decides what its large-text story is.

	WHAT EACH ROW ASSERTS, and why each is the honest shape of the claim:

	  overlaps  — ZERO, always, no allowlist. Nothing clips a stack, so two
	              painted siblings colliding is a control drawing on its
	              neighbour. Every intentional overlap in the shipped controls
	              (a Slider's fill over its rail, a Rating's Grip over its stars,
	              a list Row's hit surface over its cells) is already DECLARED as
	              a ZStack/Anchor, which is why this needs no exceptions.

	  clippedEssential — findings must be a SUBSET of the row's declared
	              allowlist, and every allowlist entry must be a real truncation
	              at Largest (dead entries are a separate failure). The allowlist
	              is not "these are fine": each entry cites a framework gap in
	              `LT_GAPS` (tests/lib/large_text_fixtures.luau), because
	              `disclose` — the only full-value path the framework has
	              (LTN-4) — exists on UI.Text alone, so a control that owns its
	              own label has nothing to declare. The failing repro for each
	              gap lives in tests/large_text_open_defects.luau, which is
	              deliberately NOT registered in tests/run.luau.

	The fixtures themselves (what is mounted per registry row, and every declared
	allowlist entry with its reason) live in tests/lib/large_text_fixtures.luau:
	data there, assertions here.

	  hitFloor  — the finding set at 4/10/14 must be a SUBSET of the set at
	              Medium, per theme. Not "zero": shipped controls DO paint below
	              the 44px floor (a PopupButton's 40px trigger, a Rating's
	              invisible drag strip) because the renderer expands their HIT
	              rect instead of their painted box (B-BTN3), so pinning zero
	              would mean allowlisting a baseline that has nothing to do with
	              large text. The claim that IS about large text is that raising
	              the preference never pushes a NEW control under the floor — and
	              in practice the set shrinks, because rows grow.

	Long-label variants come from tests/fixtures/a11y_l10n_fixtures: the shipping
	pseudo-localizer (~1.35x expansion, the German/Finnish-class risk) and the
	`german-compound` entry (one unbroken word with no legal break anywhere).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local registry = require("./conformance/controls_registry") :: { any }
local lt = require("./lib/large_text")
-- the fixture table (one mountable screen per registry row) and the declared
-- gaps its allowlists cite; see tests/lib/large_text_fixtures.luau
local fixtureLib = require("./lib/large_text_fixtures")
local FIXTURES = fixtureLib.FIXTURES
local UNSWEEPABLE = fixtureLib.UNSWEEPABLE

local PSEUDO = lt.PSEUDO
local GERMAN = lt.GERMAN_COMPOUND

-- ── the sweep ───────────────────────────────────────────────────────────────

local function mountFixture(fixture: fixtureLib.Fixture, preference: lt.Preference, theme: lt.Theme): any
	local w = lt.world({ offset = preference.offset, theme = theme, input = "touch" })
	local blueprint = fixture.build(w.core, w)
	w.present(UI.Screen({ id = "S", children = { blueprint } }))
	return w
end

local function allowed(fixture: fixtureLib.Fixture, path: string): boolean
	for _, prefix in fixture.allowClipped or {} do
		if path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/" then
			return true
		end
	end
	return false
end

local function row(fixture: fixtureLib.Fixture, preference: lt.Preference, theme: lt.Theme): string
	return `{fixture.id} @{preference.name}(+{preference.offset}) {theme.id}`
end

describe("LT-8 control matrix: every registry row at four preferences x two themes", function()
	for _, fixture in FIXTURES do
		it(
			`LT8-CTL {fixture.id}: no sibling overlap, no undisclosed clip beyond its declared allowlist, `
				.. `and no NEW sub-floor control at 0/4/10/14 px x both reference themes`,
			function()
				for _, theme in lt.THEMES do
					-- the Medium row is the BASELINE the hit-floor claim is relative
					-- to: three shipped controls paint under the floor at every
					-- preference by design, and the large-text claim is that the
					-- preference adds none.
					local baselineFloor: { string } = {}
					for index, preference in lt.PREFERENCES do
						local w = mountFixture(fixture, preference, theme)
						local found = lt.sweep(w)
						local label = row(fixture, preference, theme)

						if #found.overlaps > 0 then
							error(`painted siblings overlap:\n{lt.describeFindings(label, found.overlaps)}`, 0)
						end

						for _, finding in found.clipped do
							if not allowed(fixture, finding.node) then
								error(
									`essential text truncated with no full-value path:\n`
										.. `{lt.describeFindings(label, { finding })}\n`
										.. "  (declare disclose = true on the UI.Text, reflow, or add the path to "
										.. "the fixture's allowClipped with a gap citation)",
									0
								)
							end
						end

						local floorPaths = lt.pathsOf(found.hitFloor)
						if index == 1 then
							baselineFloor = floorPaths
						else
							for _, path in floorPaths do
								if not lt.contains(baselineFloor, path) then
									error(
										`the preference pushed a control under its target floor:\n`
											.. `{lt.describeFindings(label, found.hitFloor)}\n`
											.. `  ({path} met the floor at Medium)`,
										0
									)
								end
							end
						end
					end
				end
				expect(true).toBe(true)
			end
		)
	end
end)

describe("LT-8 control matrix: the sweep's own coverage and mirrors", function()
	it("LT8-COVER every controls_registry row is swept or carries a declared reason", function()
		local covered: { [string]: boolean } = {}
		for _, fixture in FIXTURES do
			covered[fixture.class] = true
		end
		local missing: { string } = {}
		for _, entry in registry do
			if covered[entry.name] == nil and UNSWEEPABLE[entry.name] == nil then
				table.insert(missing, entry.name)
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(
				`controls_registry rows with no large-text fixture and no declared reason: `
					.. `{table.concat(missing, ", ")}`,
				0
			)
		end
		-- ...and the reverse: a fixture may not claim a class the registry does
		-- not have (a renamed control would otherwise leave a fixture pointing at
		-- nothing and the coverage case still green)
		local known: { [string]: boolean } = {}
		for _, entry in registry do
			known[entry.name] = true
		end
		for _, fixture in FIXTURES do
			expect(known[fixture.class]).toBe(true)
		end
		for name in UNSWEEPABLE do
			expect(known[name]).toBe(true)
		end
	end)

	it("LT8-ALIVE every declared clip allowlist entry is a REAL truncation at Largest", function()
		-- an allowlist that outlives the defect it was written for is how a sweep
		-- stops meaning anything. Each entry must still catch something.
		for _, fixture in FIXTURES do
			if fixture.allowClipped == nil then
				continue
			end
			local hits: { [string]: boolean } = {}
			for _, theme in lt.THEMES do
				local w = mountFixture(fixture, { name = "Largest", offset = lt.LARGEST }, theme)
				for _, finding in lt.sweep(w).clipped do
					for _, prefix in fixture.allowClipped do
						if finding.node == prefix or string.sub(finding.node, 1, #prefix + 1) == prefix .. "/" then
							hits[prefix] = true
						end
					end
				end
			end
			for _, prefix in fixture.allowClipped do
				if hits[prefix] ~= true then
					error(
						`{fixture.id}: allowClipped '{prefix}' caught nothing at Largest in either theme — `
							.. `the gap it cites ({tostring(fixture.why)}) may be closed; delete the entry`,
						0
					)
				end
			end
		end
	end)

	it("LT8-MIRROR the audit's target-floor mirror equals the renderer's own hit expander", function()
		-- `hitFloorOf` re-derives what the solve carries as `entry.hitFloor`
		-- (contract-declared, theme-clamped) because the renderer does not publish
		-- the entry. The renderer DOES publish the consequence: it expands a
		-- sub-floor control's hit rect to exactly that floor. So every expander is
		-- a witness for the mirror.
		local checked = 0
		for _, theme in lt.THEMES do
			for _, preference in lt.PREFERENCES do
				local w = lt.world({ offset = preference.offset, theme = theme })
				w.present(UI.Screen({
					id = "S",
					children = {
						UI.Toggle({ id = "Row", label = PSEUDO, value = w.core:signal(false) }),
						UI.Button({
							id = "Tiny",
							label = "x",
							width = { type = "fixed", px = 20 },
							height = { type = "fixed", px = 20 },
						}),
					},
				}))
				local metrics = w.metrics()
				for path, entry in lt.auditRects(w) do
					local expander = w.adapter.hitRectOf(path)
					if expander == nil then
						continue
					end
					local floor = lt.hitFloorOf(entry.class, metrics)
					expect(floor).never().toBeNil()
					expect(math.max(expander.w, expander.h)).toBeGreaterThanOrEqual(floor :: number)
					expect(math.min(expander.w, expander.h)).toBe(floor :: number)
					checked += 1
				end
			end
		end
		expect(checked).toBeGreaterThan(0)
	end)
end)

describe("LT-6 policy: reflow before truncation on the controls that can reflow", function()
	it(
		"LT6-ACTION a Button's action label wraps and grows WHILE wrapping can succeed, and never breaks a word",
		function()
			-- rung 1 of the overflow order, on the surface the plan protects hardest:
			-- "an action ... must not disappear behind an ellipsis".
			--
			-- REWRITTEN FOR THE WRAP RULE (director ruling 5, 2026-08-13). This used to
			-- assert `policy == "wrap"` at EVERY preference, which is a claim the engine
			-- cannot honour: wrapping into a column narrower than the label's longest
			-- WORD does not produce more lines of that word, it BREAKS the word — and
			-- the solver's own wrap model breaks only at whitespace, so it reserves a
			-- box for a shape the engine will not draw. Measured on this exact fixture
			-- (150px fixed Button, `lt.PSEUDO_ACTION`):
			--
			--   studio-neutral    +0 / +4 / +10  longest word 79/96/122px  -> 3 lines
			--   studio-neutral    +14            longest word 139px        -> 1 line
			--   fantasy-parchment +0 .. +14      longest word 119..217px   -> 1 line
			--
			-- So the honest invariant is the RULE, not one of its arms: while wrapping
			-- can succeed the action reflows and the box grows; once it cannot, the
			-- action takes ONE line with an ellipsis rather than a broken word. The
			-- declared way to keep the action's meaning past that point is the compact
			-- form, which LT6-COMPACT below proves on the same control.
			local sawWrap, sawOneLine = false, false
			for _, theme in lt.THEMES do
				local lastWrappedHeight = 0
				for _, preference in lt.PREFERENCES do
					local w = lt.world({ offset = preference.offset, theme = theme })
					w.present(UI.Screen({
						id = "S",
						children = {
							UI.Button({ id = "Go", label = lt.PSEUDO_ACTION, width = { type = "fixed", px = 150 } }),
						},
					}))
					local facts = w.controller.textAt("/S/Go")
					local height = w.adapter.node("/S/Go").rect.h
					local label = `{theme.id} @+{preference.offset}`
					if facts.wraps then
						-- the reflow arm: nothing is cut, and the box grows with the text
						sawWrap = true
						expect(`{label} policy={facts.policy} truncated={facts.truncated}`).toBe(
							`{label} policy=wrap truncated=false`
						)
						expect(height).toBeGreaterThanOrEqual(lastWrappedHeight)
						lastWrappedHeight = height
					else
						-- the honest-degradation arm: ONE line, never a broken word
						sawOneLine = true
						expect(`{label} lines={facts.lines}`).toBe(`{label} lines=1`)
					end
				end
			end
			-- neither arm may be vacuous, or this test passes by never reaching the case
			-- it is about (the two-sided discipline docs/lessons/the-solver-already-told-
			-- you.md asks of every sweep)
			expect(`wrapped={sawWrap} oneLine={sawOneLine}`).toBe("wrapped=true oneLine=true")
		end
	)

	it("LT6-COMPACT a bounded Button draws its declared compact form rather than cutting the full label", function()
		-- rung 1 again, by the other declared route: `compactLabel` is measured in
		-- the same pass as the full label, so the narrow box swaps the STRING
		-- instead of ellipsizing it. Read off the adapter — the drawn label is
		-- what the player sees, and asserting the prop was merely declared would
		-- be emission-not-application again.
		for _, theme in lt.THEMES do
			for _, preference in lt.PREFERENCES do
				local w = lt.world({ offset = preference.offset, theme = theme })
				w.present(UI.Screen({
					id = "S",
					children = {
						UI.Button({
							id = "Save",
							label = lt.PSEUDO_ACTION,
							compactLabel = "OK",
							width = { type = "fixed", px = 150 },
						}),
					},
				}))
				expect(w.adapter.node("/S/Save").props.label).toBe("OK")
				expect(w.controller.textAt("/S/Save").truncated).toBe(false)
			end
		end
	end)

	it("LT6-FIXEDPX an authored px width that fits the compact form at Medium clips it at Larger (pinned)", function()
		--[[ CHARACTERIZATION, not an endorsement. `width = { fixed, px = 88 }` is
			enough for the compact form "OK" under Fantasy Parchment at Medium, and
			is not at any preference above it: the package's control inset and
			button padding are fixed, the glyphs are not, so the content box loses
			the race. The ladder has no rung below "compact form", so the engine
			ellipsizes an ACTION label — the one outcome the plan's rung 3 forbids.

			Pinned because it is the boundary an author needs to know: a px width
			chosen against Medium is a large-text defect waiting for a player who
			steps the preference up. The framework-side reading is in the report
			(there is no diagnostic for it: the solve reports `truncated`, and
			nothing fails a gate unless someone runs the audit). ]]
		local parchment = lt.THEMES[2]
		expect(parchment.id).toBe("fantasy-parchment")
		local truncatedAt: { string } = {}
		for _, preference in lt.PREFERENCES do
			local w = lt.world({ offset = preference.offset, theme = parchment })
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.Button({
						id = "Save",
						label = lt.PSEUDO_ACTION,
						compactLabel = "OK",
						width = { type = "fixed", px = 88 },
					}),
				},
			}))
			-- the compact form IS what is drawn: the swap happened, and the cut is
			-- of the last rung rather than of the full label
			expect(w.adapter.node("/S/Save").props.label).toBe("OK")
			if w.controller.textAt("/S/Save").truncated == true then
				table.insert(truncatedAt, preference.name)
			end
		end
		expect(table.concat(truncatedAt, ",")).toBe("Large,Larger,Largest")
	end)

	it("LT6-DISCLOSE an unbroken identity name truncates WITH a full-value path and files no finding", function()
		-- rung 3, done legally: no wrap can help one unbroken word, so the box
		-- cuts it — and `disclose` is what makes that legal rather than a defect
		for _, theme in lt.THEMES do
			local w = lt.world({ offset = lt.LARGEST, theme = theme })
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Cell",
						width = { type = "fixed", px = 140 },
						children = { UI.Text({ id = "Name", text = GERMAN, disclose = true }) },
					}),
				},
			}))
			local facts = w.controller.textAt("/S/Cell/Name")
			expect(facts.truncated).toBe(true)
			expect(facts.policy).toBe("truncate+disclose")
			expect(#lt.sweep(w).clipped).toBe(0)
			-- ...and the same cell WITHOUT the declaration is a finding: the check
			-- is not passing because it cannot fire
			local bare = lt.world({ offset = lt.LARGEST, theme = theme })
			bare.present(UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Cell",
						width = { type = "fixed", px = 140 },
						children = { UI.Text({ id = "Name", text = GERMAN }) },
					}),
				},
			}))
			expect(#lt.sweep(bare).clipped).toBe(1)
		end
	end)
end)

describe("LT-8 mixed scripts: CJK, emoji and latin at every preference", function()
	it("LT8-SCRIPTS a mixed CJK + emoji + latin line files no overlap or clip finding at any preference", function()
		for _, theme in lt.THEMES do
			for _, preference in lt.PREFERENCES do
				local w = lt.world({ offset = preference.offset, theme = theme })
				w.present(UI.Screen({
					id = "S",
					children = {
						UI.Text({ id = "Cjk", text = lt.CJK }),
						UI.Text({ id = "Emoji", text = lt.EMOJI }),
						UI.Text({ id = "Mixed", text = lt.MIXED }),
					},
				}))
				local found = lt.sweep(w)
				local label = `mixed-scripts @{preference.name} {theme.id}`
				if #found.overlaps > 0 then
					error(lt.describeFindings(label, found.overlaps), 0)
				end
				if #found.clipped > 0 then
					error(lt.describeFindings(label, found.clipped), 0)
				end
			end
		end
	end)

	it("LT8-MONOTONE every mixed-script line's box grows monotonically with the preference", function()
		-- the preference is ADDITIVE px on the glyph size, so a line box may not
		-- shrink when it rises; a shrink means something re-wrapped in the wrong
		-- direction or a cached measurement leaked across the change
		for _, theme in lt.THEMES do
			local previous: { [string]: number } = {}
			for _, preference in lt.PREFERENCES do
				local w = lt.world({ offset = preference.offset, theme = theme })
				w.present(UI.Screen({
					id = "S",
					children = {
						UI.Text({ id = "Cjk", text = lt.CJK }),
						UI.Text({ id = "Emoji", text = lt.EMOJI }),
						UI.Text({ id = "Mixed", text = lt.MIXED }),
					},
				}))
				for _, id in { "Cjk", "Emoji", "Mixed" } do
					local path = `/S/{id}`
					local h = w.adapter.node(path).rect.h
					local before = previous[path]
					if before ~= nil and h < before then
						error(`{id} shrank from {before}px to {h}px going to {preference.name} under {theme.id}`, 0)
					end
					previous[path] = h
				end
			end
			-- and the whole sweep actually moved: a matrix where nothing grows
			-- would satisfy "monotone" while proving the offset was never applied
			expect(previous["/S/Mixed"]).toBeGreaterThan(0)
		end
	end)

	it("LT8-GROWTH the Largest preference reserves a strictly taller box than Medium for the same string", function()
		for _, theme in lt.THEMES do
			local heights: { number } = {}
			for _, offset in { 0, lt.LARGEST } do
				local w = lt.world({ offset = offset, theme = theme })
				w.present(UI.Screen({
					id = "S",
					children = { UI.Text({ id = "Line", text = lt.MIXED, width = { type = "fixed", px = 300 } }) },
				}))
				table.insert(heights, w.adapter.node("/S/Line").rect.h)
			end
			expect(heights[2]).toBeGreaterThan(heights[1])
		end
	end)
end)
