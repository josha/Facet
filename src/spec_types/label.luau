--!strict
-- The `label` control's types, apart from its implementation: reading a type must
-- not load the control.
export type Spec = {
	id: string?,
	title: string, -- required: it IS the semantic text
	icon: string?, -- asset string; absent => title-only, no empty slot
	presentation: string?, -- "titleAndIcon" (default) | "titleOnly" | "iconOnly"
	-- each accepts a literal number (theme-independent) or a theme metric name
	iconSize: (number | string)?,
	textSize: (number | string)?,
	gap: (number | string)?,
}
return nil
