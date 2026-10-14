--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function world()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local root = engine.new("ScreenGui")
		local gui = engine.new("GuiService")
		local UI = Facet.controls(runtime, {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui },
			inputParent = root,
			overlayParent = root,
			motionLevel = "none",
		})
		return engine, runtime, root, UI
	end

	local CORPUS = {
		{
			id = "german-compound",
			text = "Donaudampfschifffahrtselektrizitätenhauptbetriebswerkbauunterbeamtengesellschaft",
		},
		{ id = "japanese", text = "設定を保存しました" },
		{ id = "chinese", text = "保存更改并返回主菜单" },
		{ id = "korean", text = "설정을 저장했습니다" },
		{ id = "arabic", text = "حفظ الإعدادات" },
		{ id = "hebrew", text = "שמור את ההגדרות" },
		{ id = "bidi-mixed", text = "Level 5 — المستوى ٥ — שלב 5" },
		{ id = "thai", text = "บันทึกการตั้งค่า" },
		{ id = "devanagari", text = "सेटिंग्स सहेजें" },
		{ id = "combining-marks", text = "e\u{0301}le\u{0300}ve Z\u{0351}\u{036B}a\u{0310}l\u{0346}g\u{0352}o" },
		{ id = "emoji-zwj", text = "👩‍👩‍👧‍👦 Family 🏳️‍🌈 👋🏽" },
		{ id = "long-copy", text = string.rep("Translated copy grows longer. ", 24) },
		{ id = "surrounding-space", text = "  padded  " },
		{ id = "empty", text = "" },
	}

	verifyHarness:suite("native accessibility and localization corpus", function()
		verifyHarness:case("keeps multibyte text edits valid UTF-8 through TextInput editing and maxLength", {
			id = "native_a11y_l10n_corpus::native accessibility and localization corpus::keeps multibyte text edits valid UTF-8 through TextInput editing and maxLength",
			run = function()
				for _, entry in CORPUS do
					local engine, runtime, root, UI = world()
					local open, bounded = Compose.cell(""), Compose.cell("")
					local field, limited
					local stop = runtime.mount(function()
						field = UI.TextInput({ value = open }) :: TextBox
						limited = UI.TextInput({ value = bounded, maxLength = 3 }) :: TextBox
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
							field :: unknown,
							limited,
						})
					end, root)
					field:CaptureFocus()
					field.Text = entry.text
					assert(open:peek() == entry.text, `{entry.id}: edit changed the text to {open:peek()}`)
					assert(utf8.len(open:peek()) ~= nil, `{entry.id}: edit produced invalid UTF-8`)
					field:ReleaseFocus(true)
					assert(open:peek() == entry.text, `{entry.id}: commit changed the text`)
					limited:CaptureFocus()
					limited.Text = entry.text
					local kept = bounded:peek()
					local length = utf8.len(kept)
					assert(length ~= nil, `{entry.id}: maxLength split a character`)
					assert(length <= 3, `{entry.id}: maxLength kept {length} characters`)
					assert(string.sub(entry.text, 1, #kept) == kept, `{entry.id}: maxLength did not keep a prefix`)
					assert(limited.Text == kept, `{entry.id}: native Text differs from the bounded model`)
					local expected = math.min(3, utf8.len(entry.text) :: number)
					assert(length == expected, `{entry.id}: maxLength kept {length} of {expected} characters`)
					limited:ReleaseFocus(true)
					stop()
					runtime:dispose()
				end
			end,
		})
	end)
end
