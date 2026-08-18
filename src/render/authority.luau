--!strict
-- Property-authority manifest (design §7.3, UI-STYLE-001): exactly one
-- authority per engine render property per class. The Studio spike proved the
-- engine will NOT police this (an explicit write silently defeats StyleRules
-- and fires no signals), so the renderer asserts it at the ONLY write site.
-- Authorities: layout (rects), style (token paint), binding (data-driven),
-- presentation (transient transform/opacity), host (a custom control's claims).
--
-- THIS FILE HAS ZERO REQUIRES, AND THAT IS WHY `themes/` MAY CONSULT IT
-- (ARCH-19, answered 0.10.0). The review read `src/themes/package.luau`'s
-- require of this module as a layering inversion — the pure theme compiler
-- reaching into the render layer. It is not one, for the same reason
-- `src/spec_guard.luau` and `src/class_contract.luau` are legal from anywhere: a
-- module with no requires has no direction to get wrong, so depending on it
-- couples a caller to nothing.
--
-- What matters is WHICH WAY the traffic goes, and it is one-way by construction.
-- `themes/package` only ever READS this manifest, and only to REFUSE: a theme
-- package that tries to author a property the renderer owns is rejected at
-- compile time with the authority named (`package.luau`'s `lintProperty`). The
-- alternative is a theme that silently loses to the renderer at run time on a
-- device, which is the exact failure the Studio spike above proved the engine
-- will not report. Nothing in `themes/` writes here, and nothing here knows
-- `themes/` exists.
--
-- `host` WENT LIVE WITH `UI.Foreign` (ADR-0034, 2026-08-15) and owns exactly one
-- entry: `Foreign.Parent`. It had been declared and unused since phase 3 —
-- architecture verifier ARCH-F8 confirmed the string appeared once in the whole
-- repo, its own type-union member — reserved for the custom-control escape hatch
-- (UI-EXT-001, "mounts raw Instances under explicit contract") that had never
-- shipped a blueprint class. It has now. The other four authorities answer "which
-- Facet writer owns this property of a Facet instance"; `host` answers "what
-- does the framework claim over an instance it does NOT own", and the whole point
-- of the bounded escape hatch is that the answer is one property.

local authority = {}

export type Authority = "layout" | "style" | "binding" | "presentation" | "host"

-- per class: engine-property-ish name -> authority
local MANIFEST: { [string]: { [string]: Authority } } = {
	common = {
		surface = "style",
		role = "style",
		active = "binding",
		position = "layout",
		size = "layout",
		padding = "layout",
		clipChildren = "layout",
		zIndex = "layout",
		-- native scroll host (NS-A2, verifier F2): the canvas EXTENT is layout-
		-- derived render geometry (solver contentSize+padding) with exactly one
		-- writer (renderer scroll-region push). CanvasPosition is deliberately
		-- NOT in the manifest: the ENGINE co-authors it (user scrolling) and the
		-- framework's scrollTo is a request, not an owned property — same reason
		-- GuiService.SelectedObject (engine-co-authored selection) stays out.
		canvasSize = "layout",
		anchorPoint = "layout",
		backgroundColor = "style",
		cornerRadius = "style",
		-- §17 Phase 4 engine styling: normalized modifier data (UIShadow
		-- params; one-form corner spec). The adapter materializes instances;
		-- the four per-corner engine props share this single authority entry.
		shadow = "style",
		-- the per-view gradient modifier: normalized UIGradient data. The
		-- adapter materializes ONE bespoke child; the theme's own gradients are
		-- phantom ::UIGradient RULES, and a real child is what makes the view
		-- win on this node (ADR-0020 R8 composition).
		gradient = "style",
		corners = "style",
		-- the AUTHORED stroke modifier (ADR-0022 Decision 6): normalized UIStroke
		-- data, exactly the shape and authority `shadow`/`gradient`/`corners` carry.
		-- The adapter materializes ONE bespoke child; a theme's own chrome stroke is
		-- a phantom ::UIStroke RULE and the engine renders both, so the authored one
		-- is additive rather than a replacement (ADR-0020 R8).
		stroke = "style",
		strokeColor = "style",
		transparency = "presentation",
		transform = "presentation",
		-- THE HELD DRAG SOURCE (director round five): registry-driven state the
		-- renderer writes while a live session carries this node's payload; the
		-- adapter empties the label via the `facet-drag-held` tag rule (native)
		-- or a direct text write (bespoke). Never authored — a consumer cannot
		-- set it, which is what makes the guarantee universal.
		dragHeld = "presentation",
	},
	-- Box is the one container-shaped leaf that can wear a continuous fill
	-- (ADR-0022 Decision 6). `tint` is BINDING authority on purpose: the value is
	-- data (a blend driven by a signal, an identity hue), which is exactly what the
	-- style authority cannot express — a rule cannot see a value. In native mode the
	-- write CLAIMS the engine property from the sheet; the claim is recorded and
	-- dumped so defeat detection audits the hand-off instead of tripping on it.
	Box = { tint = "binding" },
	Text = {
		text = "binding",
		textColor = "style",
		textSize = "layout",
		textAlign = "style",
		font = "style",
		tint = "binding",
		-- THE TYPOGRAPHY ROLE'S FACE (F2, 2026-08-02). LAYOUT authority, beside
		-- `textSize`, because it is the same fact: a role resolves to a size AND a
		-- font descriptor, the solver measures with that descriptor, and a second
		-- writer for the face would be the measure/paint split `Text.font` was
		-- deprecated for. (`font` above is that deprecated authored prop; it is
		-- STYLE authority and diagnosed-not-preserved.)
		textFont = "layout",
		-- THE WRAP RULE'S VERDICT (director ruling 5, 2026-08-13). LAYOUT authority,
		-- beside `textSize`/`textFont`, because it is the same kind of fact: the
		-- solver decided it while reserving the box, and a second writer for it
		-- would be the measure/paint split the rule exists to close.
		textWrapped = "layout",
	},
	Button = {
		text = "binding",
		enabled = "binding",
		selected = "binding",
		textColor = "style",
		textSize = "layout",
		font = "style",
		textFont = "layout", -- the role's face; see the Text entry above
		-- the circle Button (feature round 2026-07-26). `shape` is STYLE authority
		-- even though it also decides geometry: the geometry half is the solver
		-- reading a prop (no engine write at all), and the only thing written to an
		-- engine object is the disc's chrome — a tag in native mode, the real
		-- UICorner's radius in fallback mode. `icon` is style for the same reason:
		-- it selects the theme-owned picture over the node's own glyph.
		shape = "style",
		icon = "style",
		-- `compactLabel` is STYLE for the same reason `icon` is, and the reasoning
		-- matters because it also decides TEXT. The declaration selects which
		-- representation the node wears (and, in its icon form, which theme-owned
		-- picture); the resulting engine `Text` write still goes through the
		-- BINDING authority above, on the one label seam, so there is no second
		-- writer for the drawn string.
		compactLabel = "style",
		textWrapped = "layout", -- the wrap verdict; see the Text entry above
	},
	-- textSize joined for the ten-foot/measure-paint agreement (verifier F1):
	-- an explicit Toggle textSize scales at both seams like every text node
	Toggle = {
		text = "binding",
		value = "binding",
		enabled = "binding",
		textSize = "layout",
		textFont = "layout", -- the role's face; see the Text entry above
	},
	-- TextField (§17 Phase 5): all data-driven props ride the binding authority
	-- so the engine adapter maps them onto the TextBox (editing -> Capture/
	-- ReleaseFocus, text/placeholder -> Text/PlaceholderText, maxLength/
	-- keyboardType -> best-effort engine hints). Layout/style props inherit
	-- `common`; the presentation transform (keep-visible) is common.transform.
	TextField = {
		text = "binding",
		placeholder = "binding",
		editing = "binding",
		enabled = "binding",
		maxLength = "binding",
		keyboardType = "binding",
		-- textSize joined for the same measure-paint agreement Toggle's did
		-- (director fix round 2026-07-25): a field's intrinsic `control` role now
		-- reaches paint, so a package that moves that role moves the drawn text
		-- instead of only the reserved box
		textSize = "layout",
		textFont = "layout", -- the role's face; see the Text entry above
	},
	-- `scaleMode` is STYLE even though it decides geometry INSIDE the box, for the
	-- same reason `shape` is: nothing about the node's solved rect moves, and the
	-- single engine write is how the picture fills a box the solver already sized.
	Image = { image = "binding", tint = "binding", scaleMode = "style" },
	Grip = { cursorHint = "binding" },
	-- Path (native-substrate NS-A7): reactive stroke geometry/config are
	-- binding-authored; stroke color rides the style role hint — or, for a value a
	-- finite role cannot express, the continuous `tint` channel
	Path = { points = "binding", thickness = "binding", closed = "binding", tint = "binding" },
	-- Stage (ViewportFrame adoption 2026-08-08): the AUTHORED half is ordinary —
	-- the plate behind the scene is style, and the continuous channel is binding
	-- for exactly the reason Box's and Image's are (a rule cannot see a value).
	-- The four ENGINE properties a stage also has — Ambient, LightColor,
	-- LightDirection, CurrentCamera — are not authored at all and are declared in
	-- SEAM_OWNED below.
	Stage = { tint = "binding" },
	--[[ THE FOREIGN BOX, AND THE ONE CLAIM THAT MAKES `host` LIVE (ADR-0034).

		`Parent` is not an authored prop — no `UI.Foreign{ parent = … }` exists and
		no consumer can ask for this. It is the ONE engine property Facet ever
		writes on an instance IT DOES NOT OWN: the caller creates the GuiObject,
		`controller.foreignHost(path).adopt(instance)` puts it in the box, and from
		that write onward the framework touches nothing about it — not its size, not
		its paint, not its lifetime beyond dying with the container.

		THAT IS WHY THE AUTHORITY IS `host` AND NOT `layout`. The four live
		authorities all answer "which Facet writer owns this property of a Facet
		instance". This one answers a different question — "what does the framework
		claim over content it has disclaimed" — and the answer is: exactly one
		thing, declared here by name, so the disclaimer is auditable rather than
		asserted. `host` has been declared and unused since phase 3, reserved for
		UI-EXT-001 ("escape hatch: mounts raw Instances under explicit contract")
		and dispositioned as dead in the Step 5.5 cleanup ledger (ARCH-F8). This is
		that seam, and the reservation turns out to need exactly one entry. ]]
	Foreign = { Parent = "host" },
}

-- authorityFor(class, prop) -> Authority (class table wins over common)
function authority.authorityFor(class: string, prop: string): Authority?
	local classMap = MANIFEST[class]
	if classMap and classMap[prop] then
		return classMap[prop]
	end
	return MANIFEST.common[prop]
end

-- assertWrite: the renderer calls this before every engine write; a writer
-- claiming a property it does not own is a debug error, not a silent win.
function authority.assertWrite(class: string, prop: string, writer: Authority)
	local owner = authority.authorityFor(class, prop)
	if owner == nil then
		error(`Facet authority: no declared authority for {class}.{prop} (declare it in the manifest)`, 0)
	end
	if owner ~= writer then
		error(`Facet authority: {writer} tried to write {class}.{prop} owned by {owner}`, 0)
	end
end

function authority.manifest()
	return MANIFEST
end

-- Native-stylesheet ownership (native-stylesheets stage, ledger NSS-I2): when
-- a target opts into native paint (screen_target `nativeStyle`), these ENGINE
-- properties transfer from adapter explicit-writes to the DataModel sheet.
-- The adapter must not write them in native mode — an explicit write silently
-- and permanently defeats the rule (spike 2026-07-19, reconfirmed 2026-07-24)
-- — and the verification surface proves the hand-off per property at runtime:
-- GetStyled(prop) must equal the sheet-resolved value (defeat detection,
-- feasibility m10). Declared intended real-child overrides (the Toggle
-- knob-track assembly's transparency/fills; explicit UI.corners/UI.shadow
-- modifier instances) are the ONLY sanctioned exceptions and stay bespoke.
local NATIVE_SHEET_OWNED: { [string]: boolean } = {
	BackgroundColor3 = true,
	BackgroundTransparency = true,
	TextColor3 = true,
	TextTransparency = true, -- disabled state (:NonInteractable rules)
	PlaceholderColor3 = true,
	FontFace = true,
	ScrollBarImageColor3 = true,
	-- phantom modifier chrome (rules CREATE these; the adapter must not
	-- materialize UICorner/UIStroke instances for handed-off surfaces)
	CornerRadius = true,
	StrokeColor = true,
	StrokeTransparency = true,
	StrokeThickness = true,
	-- IMAGE PAINT (rich-skinning-v2; platform verifier F4). Every one of these is
	-- written by a generated rule for a skinned slot, a layer, a bar part, a
	-- toggle part or an icon — so this stage's whole visual surface was outside
	-- the gate that exists to catch a defeating explicit write. `Image` carries
	-- ONE sanctioned exception: the managed semantic-icon picture, because no
	-- rule can pick a content id per node (see BESPOKE_INSTANCES).
	Image = true,
	ImageColor3 = true,
	ImageTransparency = true,
	ScaleType = true,
	SliceCenter = true,
	SliceScale = true,
	TileSize = true,
	ResampleMode = true,
}

-- ADAPTER-OWNED INSTANCE FAMILIES (rich-skinning-v2; architecture verifier F4).
--
-- The comment above says "declared intended real-child overrides ... are the
-- ONLY sanctioned exceptions", and until this stage that meant two families. v2
-- added six more, every one of them an instance the ADAPTER creates and no rule
-- can create for it (a rule cannot pick a content id, cannot decide how many
-- ornaments a corners layer needs, cannot size a clip window from a solved rect).
--
-- Frozen and asserted against `chrome_slots`'s own name constants, so adding an
-- adapter-owned family without declaring it here is a failing test rather than a
-- silently widening exception. Paint on these instances is still RULE-owned from
-- birth wherever a rule can reach it (rs-m2's defeat refinement) — being on this
-- list buys the right to EXIST, not the right to paint.
-- The two families this stage added are NOT chrome, so their names live here
-- rather than in `chrome_slots`: one is presentation (the motion scale), one is an
-- authored style override (the stroke). Same anti-drift rule as the chrome
-- constants, one module up — the adapter reads the name from here, and the
-- manifest below is keyed by it, so a rename cannot leave the two disagreeing.
local INSTANCE_NAMES = table.freeze({
	motionScale = "FacetMotionScale",
	stroke = "FacetStroke",
})
authority.INSTANCE_NAMES = INSTANCE_NAMES

local BESPOKE_INSTANCES: { [string]: string } = {
	[INSTANCE_NAMES.motionScale] = "the presentation channel's transient UIScale (ADR-0022 Decision 2): a motion "
		.. "scale is not paint and no rule can express one, and it exists only while a motion runs. On a node that "
		.. "already owns a UIScale for its press dip the presentation write REUSES that instance — the engine honours "
		.. "one UIScale per object, so two would make the winner unpredictable",
	[INSTANCE_NAMES.stroke] = "the authored UI.stroke border (ADR-0022 Decision 6) — the same sanctioned-override "
		.. "standing UI.corners/UI.shadow have. A theme's own chrome stroke is a phantom ::UIStroke rule and the "
		.. "engine renders both, so this one is additive and never suppresses the theme's",
	FacetChrome = "the single-asset slot decoration (nineSlice recipes)",
	FacetChromeText = "the chrome text lift: the node's own glyphs, above the decoration",
	FacetChromeL = "the layered decoration ladder (one child per layer, plus per-corner ornaments, plus the "
		.. "`FacetChromeL<n>Mask` CanvasGroup a masked full-bleed layer is wrapped in — a SILHOUETTE, not "
		.. "paint: untagged, Active=false, with the layer's tagged art still inside it; probe rs-m9)",
	FacetIcon = "the managed semantic-icon picture — the ONE sanctioned `Image` write",
	FacetBarWindow = "the bar fill's ClipsDescendants window (percent = one Size write)",
	FacetBarFill = "the full-track sliced fill art inside that window",
	FacetBarCenter = "the bar's whole-image centre ornament",
	FacetBarCapStart = "the bar's start cap, which must survive every percent",
	FacetBarCapEnd = "the bar's end cap, which must survive every percent",
	Track = "the toggle switch's track art (a direct child, so `:Hover > ` can reach it)",
	Knob = "the toggle switch's travelling knob art (solver-owned travel, rule-owned paint)",
}

-- ADAPTER-SEAM-OWNED ENGINE PROPERTIES (UI.Stage; research
-- docs/research/2026-08-08-viewportframe-engine-facts.md §1).
--
-- A ViewportFrame carries its scene's lighting and its camera as PLAIN PROPERTIES
-- ON THE FRAME ITSELF — the instance Facet created and owns. So "the content
-- owner sets the lighting" would mean a consumer writing properties on a
-- framework-owned Instance, which is the authority violation the manifest above
-- exists to prevent; and no `style`/`binding`/`layout`/`presentation` channel fits
-- either, because none of them is an authored prop at all.
--
-- They are therefore declared here as SEAM-owned: written by exactly one caller
-- (the adapter's `stageHost` handle) through `assertSeamWrite`, so a bespoke
-- explicit write from anywhere else is a LOUD error — the same protection
-- NATIVE_SHEET_OWNED + assertBespokePaint give Image/ScrollBar paint. Each entry
-- says who writes it and through which verb, so the exemption is a decision on the
-- record rather than a hole.
local SEAM_OWNED: { [string]: string } = {
	Ambient = "the stage scene's ambient light — written by stageHost's setLighting{ ambient }",
	LightColor = "the stage scene's key-light colour — written by stageHost's setLighting{ lightColor }",
	LightDirection = "the stage scene's key-light direction — written by stageHost's setLighting{ lightDirection }",
	CurrentCamera = "the adapter-owned Camera assigned at node creation; re-aimed by stageHost's setCamera. "
		.. "A render needs a camera, so the adapter creates and owns one instead of handing the raw instance out",
	-- the two properties setCamera writes ON that owned Camera instance
	-- (platform review N1: they are seam writes on an adapter-owned Instance,
	-- so leaving them undeclared left the no-bespoke-write pin blind to them)
	CFrame = "the owned stage Camera's transform — written only by stageHost's setCamera (CFrame.lookAt)",
	FieldOfView = "the owned stage Camera's field of view — written only by stageHost's setCamera{ fov }",
}

function authority.seamOwned(engineProp: string): boolean
	return SEAM_OWNED[engineProp] ~= nil
end

function authority.seamOwnedSet(): { [string]: string }
	return SEAM_OWNED
end

-- assertSeamWrite: the ONE gate every write to a seam-owned engine property goes
-- through. `bySeam` is true only inside the adapter's stage seam; everything else
-- is refused by name, because a second writer for a frame's lighting or camera is
-- exactly the silent dual authority the manifest above exists to prevent.
function authority.assertSeamWrite(engineProp: string, bySeam: boolean)
	if SEAM_OWNED[engineProp] == nil then
		error(
			`Facet authority: '{engineProp}' is not a declared seam-owned engine property `
				.. "(declare it in render/authority.luau's SEAM_OWNED, with who writes it)",
			0
		)
	end
	if not bySeam then
		error(
			`Facet authority: {engineProp} is owned by the Stage content seam (adapter.stageHost) — `
				.. "a bespoke write would be a second authority over the frame",
			0
		)
	end
end

function authority.nativeSheetOwned(engineProp: string): boolean
	return NATIVE_SHEET_OWNED[engineProp] == true
end

function authority.nativeSheetOwnedSet(): { [string]: boolean }
	return NATIVE_SHEET_OWNED
end

function authority.bespokeInstances(): { [string]: string }
	return BESPOKE_INSTANCES
end

return authority
