--!strict
-- THE FRAMEWORK'S OWN ICON ART (compact-label stage, 2026-07-27).
--
-- Everything about art in this library was per-PACKAGE until now: a theme
-- declared `assets` and mapped `icons` at them, and a package that declared
-- nothing drew the ASCII character from `package.ICON_FALLBACK_GLYPHS`. That
-- floor exists so a control never depends on a resolution succeeding, and it is
-- not going away — this table sits BETWEEN the two:
--
--     package art  ->  framework art (here)  ->  ASCII glyph  ->  nil
--
-- so "this package ships no icon for that name" now means "draw the framework's
-- picture" instead of "draw the framework's character", and a package that
-- declares the name still wins outright. A package opts out of this rung with
-- `identity.standardIcons = false` (see `package.resolveIcon`), which is how the
-- two deliberate glyph demonstrations keep their point: glossy-touch's
-- controlled comparison against fantasy-ornate, and `pixel_quest.buildWithoutIcons`.
--
-- WHY ONE NEAR-WHITE SILHOUETTE AND NOT A LIGHT/DARK PAIR. `ImageColor3`
-- MULTIPLIES, so a white source reaches any colour a theme names and a black one
-- can only ever get darker. Measured across all 11 theme variants of the eight
-- reference packages, `tintRole = "content"` contrasts 3.31:1 to 15.62:1 against
-- the `control` plate the icon sits on -- dark in every light package, light in
-- every dark one. One silhouette is therefore correct everywhere and a second
-- version would be strictly worse. The art is #F0F0F2 on transparency so the
-- tint owns the colour completely; nothing is baked in.
--
-- WHY `content` FOR ALL ELEVEN, including the stepper's +/-. The shipped packages
-- tint their own stepper glyphs `accent` ("a stepper's +/- is an action"), which
-- is right for art a package authored against its own palette. Framework art is
-- painted under packages nobody checked it against, so it takes the ONE role that
-- was measured legible on every variant. A package that wants its +/- gilded
-- declares its own art, exactly as fantasy-ornate and pixel-quest already do.
--
-- A `contentId` of nil is a legal shipping state and not a defect: `resolveIcon`
-- only answers "asset" for a real content id, so an un-uploaded name falls all
-- the way through to the ASCII glyph and stays legible. That is what let the
-- whole feature land green before a single byte was uploaded.
--
-- The ids below are NOT hand-transcribed. `tools/upload_icons.py` writes them
-- here from `assets/icons/upload-manifest.json` after the upload, and
-- `tools/lune/check_docs` asserts the two agree — the manifest is the record of
-- what went up, this is the table the framework reads, and a typo in either is a
-- picture that silently never appears.
local standard_icons = {}

-- name -> the one asset that draws it. `assetName` is the PNG basename in
-- `assets/icons/` and the key in that folder's `upload-manifest.json`; the two
-- are cross-checked by `tools/lune/check_docs`.
standard_icons.ART = table.freeze({
	["chevron.leading"] = table.freeze({
		assetName = "luauui_icon_chevron_left",
		contentId = "rbxassetid://81739481512878",
		tintRole = "content",
	}),
	["chevron.trailing"] = table.freeze({
		assetName = "luauui_icon_chevron_right",
		contentId = "rbxassetid://121626475799702",
		tintRole = "content",
	}),
	["chevron.up"] = table.freeze({
		assetName = "luauui_icon_chevron_up",
		contentId = "rbxassetid://92798715826227",
		tintRole = "content",
	}),
	["chevron.down"] = table.freeze({
		assetName = "luauui_icon_chevron_down",
		contentId = "rbxassetid://90343755930598",
		tintRole = "content",
	}),
	["checkmark"] = table.freeze({
		assetName = "luauui_icon_check",
		contentId = "rbxassetid://108245103349446",
		tintRole = "content",
	}),
	["close"] = table.freeze({
		assetName = "luauui_icon_close",
		contentId = "rbxassetid://133198978089241",
		tintRole = "content",
	}),
	["increment"] = table.freeze({
		assetName = "luauui_icon_plus",
		contentId = "rbxassetid://128664097463435",
		tintRole = "content",
	}),
	["decrement"] = table.freeze({
		assetName = "luauui_icon_minus",
		contentId = "rbxassetid://115068690098353",
		tintRole = "content",
	}),
	["menu"] = table.freeze({
		assetName = "luauui_icon_menu",
		contentId = "rbxassetid://119066409501208",
		tintRole = "content",
	}),
	["more"] = table.freeze({
		assetName = "luauui_icon_more",
		contentId = "rbxassetid://117014407191998",
		tintRole = "content",
	}),
	["edit"] = table.freeze({
		assetName = "luauui_icon_edit",
		contentId = "rbxassetid://97349995335189",
		tintRole = "content",
	}),
	-- added row-actions stage, 2026-08-11: the Delete/Flag tray actions'
	-- `icon` names. Same recipe as the rest of the set (generate_icons.py,
	-- Open Cloud upload via tools/upload_icons.py) -- not new art paradigms.
	["trash"] = table.freeze({
		assetName = "luauui_icon_trash",
		contentId = nil,
		tintRole = "content",
	}),
	["flag"] = table.freeze({
		assetName = "luauui_icon_flag",
		contentId = nil,
		tintRole = "content",
	}),
})

-- resolve(name) -> the framework's art record for a name, or nil.
-- nil covers BOTH "the framework ships no art for that name" and "it ships art
-- that has not been uploaded yet", because the caller does the same thing in
-- either case: fall through to the ASCII glyph.
function standard_icons.resolve(name: string): any
	local entry = (standard_icons.ART :: any)[name]
	if entry == nil or type(entry.contentId) ~= "string" or entry.contentId == "" then
		return nil
	end
	return entry
end

return standard_icons
