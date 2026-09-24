--!strict
-- The shared parts of Facet's non-modal and modal overlays (Callout now, Dialog
-- next): a construction-only media block and the richer action shape. Types only,
-- so reading one never loads a control.
local blueprint = require("../blueprint")

-- Exactly one of `aspectRatio` (width / height) or `height` (px or metric).
-- `scaleMode` is the Image fit/crop/stretch vocabulary (absent: the Image
-- default); `background` is a Box `tint` value painted behind the image.
export type Media = {
	image: string,
	aspectRatio: number?,
	height: (number | string)?,
	scaleMode: ("fit" | "crop" | "stretch")?,
	background: any?,
}

-- the Sheet's hero: exactly one of `image` or arbitrary blueprint `content`,
-- exactly one of `aspectRatio` or `height`; `scaleMode` is image-only.
-- `sticky` pins it above the body (default false: it scrolls with it).
export type Hero = {
	image: string?,
	content: blueprint.Blueprint?,
	aspectRatio: number?,
	height: (number | string)?,
	scaleMode: ("fit" | "crop" | "stretch")?,
	background: any?,
	sticky: boolean?,
}

export type Action = {
	id: string,
	label: blueprint.Bound<string>,
	role: ("default" | "cancel" | "destructive")?,
	enabled: blueprint.Bound<boolean>?,
	busy: blueprint.Bound<boolean>?,
	onActivate: () -> (),
}

return nil
