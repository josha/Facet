--!strict
-- The `sheet` control's types, apart from its implementation: reading a type must
-- not load the control.
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
local publicEnv = require("../env/environment")
local overlayParts = require("./overlay_parts")
export type Action = overlayParts.Action
export type Hero = overlayParts.Hero
export type StringCell = publicCore.Cell<string>
export type BooleanCell = publicCore.Cell<boolean>
export type Spec<V = StringCell, P = BooleanCell> = {
	id: string?,
	title: publicBlueprint.Bound<string>,
	content: publicBlueprint.Blueprint | (() -> publicBlueprint.Blueprint),
	detent: V,
	-- "hug" fits the whole body plus pinned regions, re-measured live
	detents: { "medium" | "large" | "hug" | { id: string, fraction: number?, height: number? } }?,
	env: publicEnv.Env?,
	presenter: any?,
	isPresented: P?,
	interactiveDismissDisabled: boolean?,
	dragIndicator: ("automatic" | "visible" | "hidden")?,
	-- construction-only; automatic: centred at ten-foot, otherwise bottom
	placement: ("automatic" | "bottom" | "side" | "center")?,
	edge: ("left" | "right")?, -- side only; default right
	width: ("automatic" | "narrow" | "wide")?, -- the Dialog width presets
	closeButton: boolean?, -- default true; independent of interactiveDismissDisabled
	-- construction-only: absent renders `title`; a blueprint replaces that
	-- region; false removes it (Size and Close stay, over the hero if any)
	header: (publicBlueprint.Blueprint | false)?,
	hero: Hero?, -- construction-only
	actions: { Action }?, -- pinned below the body; they never close the sheet
	actionLayout: ("automatic" | "row" | "stacked")?,
	contentInset: ("standard" | "none")?, -- the body's own padding only
	-- construction-only. always (default): the body scrolls at every height and
	-- never hands its pan to the sheet. atLargestDetent: below the tallest
	-- detent a body pan resizes the sheet; at it, only a downward pan from the
	-- top does
	scrollPolicy: ("always" | "atLargestDetent")?,
}
return nil
