--!strict
-- ENGINE TEXT PREMEASUREMENT (text-measurement milestone, 2026-07-24;
-- CLIENT-ONLY). The engine end of the seam whose layout end is
-- src/layout/text_metrics: measures the WORDS a solve could not size exactly
-- with TextService:GetTextBoundsAsync and hands the widths back.
--
-- Why words and not laid-out strings: wrapping is greedy over words, so exact
-- word widths plus an exact space width reproduce the engine's own break
-- points at ANY width. Measuring `font/size/maxWidth/text` instead would miss
-- the cache on every resize and every device profile, turning a
-- per-vocabulary cost into a per-layout one. A word is measured once and stays
-- correct for the life of the session.
--
-- Yields (GetTextBoundsAsync), so the whole batch runs in its own task: the
-- renderer calls this at the END of a solve, having already painted that frame
-- from the conservative estimate, and takes the exact geometry one re-solve
-- later. Nothing waits on the engine to draw a first frame.
--
-- Reservation is never made unsafe by this module:
--   * a word the engine cannot measure comes back with width = nil and keeps
--     the estimator's conservative bound;
--   * measurements are re-validated at the text_metrics seam (NaN, infinite,
--     negative, and zero-for-a-non-empty-word are refused there);
--   * GetTextBoundsAsync does NOT include the player's PreferredTextSize — it
--     answers for the literal requested size at every preference (measured
--     2026-08-03, Step 8.5 probe artifact; this REFUTES the 2026-07-23
--     grounding that it honours the preference). The engine paints at
--     TextSize + a per-preference constant offset, and the solver asks this
--     module at `size + preferredTextOffset` — so the widths returned here are
--     exactly the glyph widths the engine draws. The preference is applied
--     ONCE, at the solver's measure seam; a preference change re-requests
--     naturally because the effective size key changes.

-- Services are resolved LAZILY, never at module scope: this module is required
-- by the theme controller, whose lifecycle the headless suite exercises, and a
-- module-scope `game:GetService` would make the require itself engine-only. Every
-- function below already runs client-side or not at all.
local function textService(): any
	return game:GetService("TextService")
end
local function contentProvider(): any
	return game:GetService("ContentProvider")
end

local text_premeasure = {}

-- the fonts Facet names, mapped to their engine font files. Shared with
-- src/client/text_calibration (the per-font average seam) so one list defines
-- what "BuilderSans" means to the engine.
text_premeasure.FONT_FILES = {
	BuilderSans = "rbxasset://fonts/families/BuilderSans.json",
	GothamSSm = "rbxasset://fonts/families/GothamSSm.json",
	SourceSans = "rbxasset://fonts/families/SourceSansPro.json",
} :: { [string]: string }

-- FONT DESCRIPTORS (ADR-0019 §6). Measurement keys on the EFFECTIVE font
-- "family#weight#style", never a short family name — two weights of one family
-- measure differently, and a theme is free to declare either. Everything below
-- turns a descriptor (or a bare family, which means Regular/Normal) into the
-- `Font` the bounds API needs.
--
-- A theme may name a family this list has never heard of. Three ways it
-- resolves, in order: a family registered by the game
-- (`registerFontFamily("Parchment", "rbxasset://fonts/families/Balthazar.json")`),
-- a family that IS a content URI already, or the built-in table. An
-- unresolvable family measures through the estimator's conservative full-em
-- path — over-reserved, never clipped.
local registeredFamilies: { [string]: string } = {}

function text_premeasure.registerFontFamily(family: string, file: string)
	if type(family) == "string" and family ~= "" and type(file) == "string" and file ~= "" then
		registeredFamilies[family] = file
	end
end

function text_premeasure.fontFileFor(family: string): string?
	if type(family) ~= "string" or family == "" then
		return nil
	end
	local registered = registeredFamilies[family]
	if registered ~= nil then
		return registered
	end
	local builtIn = text_premeasure.FONT_FILES[family]
	if builtIn ~= nil then
		return builtIn
	end
	if string.match(family, "^rbxasset") ~= nil then
		return family -- already a content URI
	end
	return nil
end

-- the inverse, for reading a Font attribute back into a Facet family name
function text_premeasure.familyForFile(file: string): string?
	for family, mapped in text_premeasure.FONT_FILES do
		if mapped == file then
			return family
		end
	end
	for family, mapped in registeredFamilies do
		if mapped == file then
			return family
		end
	end
	return nil
end

-- "family#weight#style" | "family" -> (family, weight, style)
function text_premeasure.parseDescriptor(key: string): (string, string, string)
	local family, weight, style = string.match(key, "^([^#]+)#([^#]+)#([^#]+)$")
	if family ~= nil then
		return family, weight :: string, style :: string
	end
	return key, "Regular", "Normal"
end

local fontCache: { [string]: Font | false } = {}

-- fontFor(key): the engine `Font` for a descriptor or a bare family name, or
-- nil when the family cannot be resolved. Cached per key — Font construction is
-- cheap but this runs per premeasure request.
function text_premeasure.fontFor(key: string): Font?
	local cached = fontCache[key]
	if cached ~= nil then
		return if cached == false then nil else cached :: Font
	end
	local family, weight, style = text_premeasure.parseDescriptor(key)
	local file = text_premeasure.fontFileFor(family)
	local made: Font? = nil
	if file ~= nil then
		local ok, result = pcall(function()
			return Font.new(file, (Enum :: any).FontWeight[weight], (Enum :: any).FontStyle[style])
		end)
		if not ok or result == nil then
			-- an unknown weight/style name must not cost the whole measurement:
			-- fall back to the family's regular face rather than nothing
			ok, result = pcall(function()
				return Font.new(file)
			end)
		end
		made = if ok then result else nil
	end
	fontCache[key] = made or false
	return made
end

-- unwrapped: a single line's true advance width
local UNWRAPPED = 100000

--[[ ONE PARAMS INSTANCE PER BATCH, DESTROYED WITH IT (2026-08-17).

	`GetTextBoundsParams` is an INSTANCE, and this allocated a fresh one per
	measured word and never destroyed any of them. A batch is the whole tree's
	text vocabulary — hundreds of words on a real screen, several batches per
	session, two calls per SPACE probe — so the transport's own measurement pass
	was the largest instance churn in the framework, all of it garbage the moment
	it was read. The object is a plain parameter carrier with no identity: every
	field is overwritten before each read, so one per batch is exactly as correct
	as one per word.

	The factory is a module field rather than an inline `Instance.new` so the
	headless suite can count the allocations — the claim being made here is a
	COUNT, and a count with no instrument is a comment. ]]
function text_premeasure.newBoundsParams(): any?
	local ok, params = pcall(function()
		return Instance.new("GetTextBoundsParams")
	end)
	return if ok then params else nil
end

local function boundsWidth(params: any, font: Font, size: number, text: string): number?
	if params == nil then
		return nil
	end
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = UNWRAPPED
	local ok, bounds = pcall(function()
		return textService():GetTextBoundsAsync(params)
	end)
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return nil
end

-- The space is the one "word" the bounds API cannot answer directly: trailing
-- and lone whitespace does not survive into TextBounds. Take it as the
-- DIFFERENCE between a spaced and an unspaced pair, which is exactly the
-- advance the engine inserts between two words.
local SPACE_PROBE_SPACED = "x x"
local SPACE_PROBE_TIGHT = "xx"
local function spaceWidth(params: any, font: Font, size: number): number?
	local spaced = boundsWidth(params, font, size, SPACE_PROBE_SPACED)
	local tight = boundsWidth(params, font, size, SPACE_PROBE_TIGHT)
	if spaced == nil or tight == nil then
		return nil
	end
	local width = spaced - tight
	if width ~= width or width <= 0 then
		return nil
	end
	return width
end

-- BOOT-WINDOW CORRECTION — load-bearing, found live 2026-07-24, do not remove.
--
-- `GetTextBoundsAsync` gives DIFFERENT answers during the first moments of a
-- session than it gives once the session has settled, and it gives them
-- without complaint. The first premeasure batch runs on the very first solve,
-- which is exactly the worst moment, so the whole vocabulary was measured
-- wrong — and because a measured word is cached for the session and never
-- re-requested, those wrong widths were permanent.
--
-- Live proof (stamp a92c0266, adaptive_controls): the store held
-- `Volume@16 = 47`, `Brightness@16 = 65`, `Download@14 = 54` while the SAME
-- call through this SAME module moments later returned 45, 62.5 and 51. It is
-- not the command VM disagreeing with the client VM (both were checked, both
-- return 45), it is not the font failing to load (a never-used font measures
-- identically on its first and its hundredth read), and it is not a weight
-- fallback (the boot values do not match Regular, Medium, SemiBold or Bold).
-- The boot answer is simply wrong, and it is STABLE while it is wrong — which
-- is why no "wait until it stops changing" gate can catch it. That was tried
-- first and passed straight through the bad window.
--
-- The only reliable test for "is this answer the real one?" is to ask again
-- later and compare. So every batch is re-measured once the session has
-- settled, and any width that moved is corrected. Correcting a width is
-- cheap — it re-solves the surface, which is the same one-frame reflow the
-- design already accepts — and the first frame was never at risk either way,
-- because it is painted from the conservative estimator before any of this
-- runs.
--
-- The direction of the boot error here was over-reservation, which is the safe
-- direction, but nothing guarantees that: a narrower wrong answer would have
-- clipped every label in the UI. This correction is what makes the exactness
-- claim true rather than lucky.
local STABILITY_PROBE = "Mg Wl 0123"
local warmed: { [string]: boolean } = {}

-- PreloadAsync on a TextLabel carrying the face is the documented way to
-- preload a FontFace. It is not sufficient on its own (see above), but it is
-- free and it removes one variable.
local function warmFont(fontName: string, font: Font)
	if warmed[fontName] then
		return
	end
	warmed[fontName] = true
	pcall(function()
		local probe = Instance.new("TextLabel")
		probe.FontFace = font
		probe.Text = STABILITY_PROBE
		contentProvider():PreloadAsync({ probe })
		probe:Destroy()
	end)
end

-- SESSION WARM-UP. The boot window belongs to the SESSION, not to any one
-- batch, so burn it once — during loading, before a player is looking at
-- anything — instead of re-verifying every batch forever. `screen_target.new`
-- starts this, so a game gets it by building its adapter early; the cost is a
-- handful of bounds calls on a throwaway string.
--
-- The test is "ask again and compare", because there is no readiness signal and
-- the wrong answer is stable while it is wrong. Two agreeing reads a settle
-- interval apart AND a minimum elapsed time, because two reads could in
-- principle both land inside a long enough window.
text_premeasure.SETTLE_INTERVAL = 1.5
text_premeasure.SETTLE_MIN_ELAPSED = 3
text_premeasure.SETTLE_MAX_ATTEMPTS = 8
-- corrections made, kept for the evidence artifact: an exactness claim has to
-- be able to show the correction that made it true
text_premeasure.corrections = {} :: { { font: string, size: number, word: string, from: any, to: any } }

local settled = false
local warming = false

--[[ SCHEDULER SEAM, the `src/client/preferred_text.luau` idiom. `task` is a
	Roblox global, and this module otherwise loads fine under Lune — its services
	are resolved lazily — so routing the two background bodies through one
	replaceable field is the whole difference between a transport that can be
	DRIVEN headlessly and one that can only be read as text. It is what proves
	PLAT-12's disposal token (queue the body, cancel, then run it: zero calls) and
	PLAT-20's allocation count. Default is exactly what it was. ]]
function text_premeasure.spawn(f: () -> ())
	task.spawn(f)
end

-- idempotent; safe to call from anywhere, returns immediately
function text_premeasure.warmUp()
	if settled or warming then
		return
	end
	warming = true
	text_premeasure.spawn(function()
		local font = text_premeasure.fontFor("BuilderSans")
		if font == nil then
			settled = true -- nothing to settle against; batches keep verifying
			return
		end
		warmFont("BuilderSans", font)
		local started = os.clock()
		local previous: number? = nil
		-- one params instance for the whole stability probe, like a batch
		local params = text_premeasure.newBoundsParams()
		for _ = 1, text_premeasure.SETTLE_MAX_ATTEMPTS do
			local width = boundsWidth(params, font, 100, STABILITY_PROBE)
			local agrees = width ~= nil and previous ~= nil and math.abs(width - previous) < 0.01
			if agrees and (os.clock() - started) >= text_premeasure.SETTLE_MIN_ELAPSED then
				break
			end
			previous = width
			task.wait(text_premeasure.SETTLE_INTERVAL)
		end
		if params ~= nil then
			pcall(function()
				params:Destroy()
			end)
		end
		settled = true
	end)
end

-- wait for the session to settle, bounded. Returns true if it settled.
local function awaitSettled(): boolean
	if settled then
		return true
	end
	text_premeasure.warmUp()
	local deadline = os.clock() + text_premeasure.SETTLE_INTERVAL * text_premeasure.SETTLE_MAX_ATTEMPTS
	while not settled and os.clock() < deadline do
		task.wait()
	end
	return settled
end

local function measureBatch(requests: { any }): { any }
	local results: { any } = {}
	local params = text_premeasure.newBoundsParams()
	for _, request in requests do
		-- `request.font` is the canonical descriptor the solver measured with
		-- (ADR-0019 §6), so the engine measures the same face the theme declared
		-- rather than the family's Regular
		local font = text_premeasure.fontFor(request.font)
		local width: number? = nil
		if font ~= nil then
			warmFont(request.font, font)
			if request.word == " " then
				width = spaceWidth(params, font, request.size)
			else
				width = boundsWidth(params, font, request.size, request.word)
			end
		end
		table.insert(results, { font = request.font, size = request.size, word = request.word, width = width })
	end
	if params ~= nil then
		pcall(function()
			params:Destroy()
		end)
	end
	return results
end

-- measure(requests, done): the RenderTargetAdapter `measureTextWidths` seam.
-- requests = { { font, size, word } }; done receives the same rows with a
-- `width` field, nil where the engine had no answer. Never yields the caller.
--
-- `done` may be called MORE THAN ONCE for the same batch: once with the
-- immediate measurement, and again with corrections if the settled re-read
-- disagrees. The renderer treats a repeat call as an ordinary update (it
-- re-solves only when a width actually changed), which is what makes the
-- correction free to the caller.
--
-- RETURNS A CANCEL FUNCTION (2026-08-17). The second `done` of a
-- boot-window batch can arrive up to `SETTLE_INTERVAL * SETTLE_MAX_ATTEMPTS`
-- later — ~12 s — and a renderer disposed in between was still called back,
-- with an `env:set` and a `solveAndApply` on a controller that had torn its
-- surface down. There is no cancelling an engine read that is already in
-- flight, and nothing here pretends otherwise: what the token cancels is the
-- DELIVERY. Calling it is idempotent and safe at any point; ignoring the return
-- keeps the previous behaviour, which is what the `measureTextWidths` contract
-- still promises an adapter that does not care.
function text_premeasure.measure(requests: { any }, done: (results: { any }, final: boolean?) -> ()): () -> ()
	local cancelled = false
	local function deliver(results: { any }, final: boolean?)
		if cancelled then
			return
		end
		done(results, final)
	end
	text_premeasure.spawn(function()
		-- the steady state, and the one a game should be in by the time any UI
		-- is shown: the session has settled, so one measurement is the answer
		if settled then
			deliver(measureBatch(requests))
			return
		end

		-- otherwise this batch is racing the boot window. Answer NOW with what
		-- the engine says, marked NOT FINAL — the geometry improves immediately
		-- and a surface gated on exact text knows to keep waiting — then answer
		-- again for real once the session settles.
		local early = measureBatch(requests)
		deliver(early, false)
		awaitSettled()
		if cancelled then
			return -- torn down while we waited: not even the re-measure is owed
		end
		local final = measureBatch(requests)
		for i, entry in final do
			local before = early[i]
			if before ~= nil and before.width ~= entry.width then
				table.insert(text_premeasure.corrections, {
					font = entry.font,
					size = entry.size,
					word = entry.word,
					from = before.width,
					to = entry.width,
				})
			end
		end
		deliver(final)
	end)
	return function()
		cancelled = true
	end
end

return text_premeasure
