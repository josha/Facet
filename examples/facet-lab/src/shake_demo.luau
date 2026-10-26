--!strict
local CatalogTypes = require("./catalog_types")
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
type StackProps = typeof(require("@repo/tools/typecheck/aliases").StackProps)

local function make(UI: Controls, Host: Host, C: Compose, intensity: number): Frame
	local faces: { GuiObject } = {}
	local slots: { Instance } = {}
	for index, letter in { "D", "R", "A", "F", "T" } do
		local label = UI.Text { text = letter, textRole = "strong" }
		local faceProps: StackProps = {
			Name = `DraftFace{index}`,
			Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.None,
			surface = "panel",
			padding = 0,
			align = "center",
			distribute = "center",
			label,
		}
		local face = UI.VStack(faceProps)
		faces[index] = face
		local props: FrameProps = {
			Name = `DraftSlot{index}`,
			Size = UDim2.fromOffset(44, 52),
			BackgroundTransparency = 1,
			face,
		}
		slots[index] = Host.Frame(props)
	end
	local targets = C.cell(faces)
	local shake = UI.shake(targets, { intensity = intensity })
	local status = C.cell("Place the draft to test the match rule.")
	local row: StackProps = { gap = "s", slots }
	local commands: StackProps = {
		gap = "s",
		UI.Button {
			label = "Cancel feedback",
			onActivate = function(_input: InputObject?, _count: number?)
				shake.cancel()
			end,
		},
		UI.Button {
			label = "Finish feedback",
			onActivate = function(_input: InputObject?, _count: number?)
				shake.finish()
			end,
		},
	}
	local props: StackProps = {
		gap = "s",
		UI.Text { text = "Draft placement" },
		UI.HStack(row),
		UI.Button {
			label = "Place invalid draft",
			onActivate = function()
				status:set("Invalid placement. Move the draft to an empty lane.")
				shake.play()
			end,
		},
		UI.HStack(commands),
		UI.Text { text = status },
	}
	return UI.VStack(props)
end

local page: CatalogTypes.PageDefinition = {
	family = "media",
	purpose = "Reject a draft placement and shake only its tile faces.",
	alternatives = "Use Flash for a transient paint cue. Keep the rejection reason visible.",
	snippet = "local shake = UI.shake(faces, { intensity = 1 }); shake.play()",
	demonstrates = { "targets", "intensity" },
	base = function()
		return { intensity = 1 }
	end,
	axes = { { key = "intensity", values = { 0, 1, 2 } } },
	states = {
		{ name = "normal feedback", props = {} },
		{ name = "strong feedback", props = { intensity = 2 } },
		{ name = "no movement", props = { intensity = 0 } },
	},
	make = function(UI: Controls, p: { intensity: number? }, c: CatalogTypes.Context): Instance
		return make(UI, c.Host, c.Compose, p.intensity or 1)
	end,
}
return page
