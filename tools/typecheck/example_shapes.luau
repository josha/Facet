--!strict
local Civil = require("../../src/ui/civil_date_types")
local Overlay = require("../../src/ui/overlay_types")
local Content = require("../../src/ui/content_types")
local Facet = require("../../src")
local Compose = require("../../src/vendor/compose/core")
local Shared = require("../../src/ui/types")
return {
	civilRangeCell = function(value: Facet.Cell<Civil.Range>): Facet.Cell<Civil.Range>
		return value
	end,
	civilRange = function(value: Civil.Range): Civil.Range
		return value
	end,
	voteCell = function(value: Facet.Cell<"up" | "down" | "none">): Facet.Cell<"up" | "down" | "none">
		return value
	end,
	unknownCell = function(value: Facet.Cell<unknown>): Facet.Cell<unknown>
		return value
	end,
	collectionStatusCell = function(
		value: Facet.Cell<Compose.OrderedCollectionStatus>
	): Facet.Cell<Compose.OrderedCollectionStatus>
		return value
	end,
	stringCell = function(value: Facet.Cell<string>): Facet.Cell<string>
		return value
	end,
	instanceCell = function(value: Facet.Cell<Instance?>): Facet.Cell<Instance?>
		return value
	end,
	centerCell = function(value: Facet.Cell<"empty" | "back">): Facet.Cell<"empty" | "back">
		return value
	end,
	dimCell = function(value: Facet.Cell<"none" | "dark" | "light">): Facet.Cell<"none" | "dark" | "light">
		return value
	end,
	destination = function(value: Facet.NavigationDestination<any>): Facet.NavigationDestination<any>
		return value
	end,
	imageModeCell = function(
		value: "fill" | "fit" | "stretch" | "slice" | "tile" | "crop"
	): Facet.Cell<"fill" | "fit" | "stretch" | "slice" | "tile" | "crop">
		return Facet.Compose.cell(value)
	end,
	vectorCell = function(value: Facet.Cell<Vector2>): Facet.Cell<Vector2>
		return value
	end,
	numberCell = function(value: Facet.Cell<number>): Facet.Cell<number>
		return value
	end,
	tab = function(value: Facet.Tab): Facet.Tab
		return value
	end,
	sideCell = function(value: ("leading" | "trailing")?): Facet.Cell<("leading" | "trailing")?>
		return Facet.Compose.cell(value)
	end,
	sortCell = function(
		value: { column: string, direction: "ascending" | "descending" }?
	): Facet.Cell<{ column: string, direction: "ascending" | "descending" }?>
		return Facet.Compose.cell(value)
	end,
	orderedControls = function(
		value: Compose.OrderedCollectionControls<string>
	): Compose.OrderedCollectionControls<string>
		return value
	end,
	optionalStringCell = function(value: string?): Facet.Cell<string?>
		return Facet.Compose.cell(value)
	end,
	sheetDetent = function(value: Facet.SheetDetent): Facet.SheetDetent
		return value
	end,
	rowAction = function(value: Facet.RowAction): Facet.RowAction
		return value
	end,
	controlSize = function(value: Facet.Cell<Shared.ControlSize?>): Facet.Cell<Shared.ControlSize?>
		return value
	end,
	optionalNumber = function(value: Facet.Cell<number?>): Facet.Cell<number?>
		return value
	end,
	TableColumn_any = function(value: Facet.TableColumn<any, any>): Facet.TableColumn<any, any>
		return value
	end,
	rowActionsSpec = function(props: Facet.RowActionsSpec): Facet.RowActionsSpec
		return props
	end,
	rowActions = function(props: Facet.RowActionsOptions): Facet.RowActionsOptions
		return props
	end,
	radialSpec = function(props: Facet.RadialMenuSpec<any>): Facet.RadialMenuSpec<any>
		return props
	end,
	regionZone = function(props: Facet.RegionProps)
		return props.zone
	end,
	motionLevel = function(
		value: Compose.Formula<"normal" | "limited" | "none">
	): Compose.Formula<"normal" | "limited" | "none">
		return value
	end,
	skinLayer = function(theme: Facet.ThemePackage)
		return assert(theme.chrome)["panel"]
	end,
	MenuItem_any = function(props: Facet.MenuItem<any>): Facet.MenuItem<any>
		return props
	end,
	RadialItem_any = function(props: Facet.RadialItem<any>): Facet.RadialItem<any>
		return props
	end,
	PickerOption_any = function(props: Facet.PickerOption<any>): Facet.PickerOption<any>
		return props
	end,
	PickerOption_string = function(props: Facet.PickerOption<string>): Facet.PickerOption<string>
		return props
	end,
	AlertAction_any = function(props: Facet.AlertAction<any>): Facet.AlertAction<any>
		return props
	end,
	DialogAction = function(props: Overlay.DialogAction): Overlay.DialogAction
		return props
	end,
	Step = function(props: Content.Step): Content.Step
		return props
	end,
	Action = function(props: Facet.OverlayAction): Facet.OverlayAction
		return props
	end,

	coordinatesCell = function(value: { number }?): Facet.Cell<{ number }?>
		return Facet.Compose.cell(value)
	end,
	cell = function<T>(_: string, value: T): Facet.Cell<T>
		return Facet.Compose.cell(value)
	end,
	edgePicker = function(props: Facet.PickerSpec<"top" | "bottom">): Facet.PickerSpec<"top" | "bottom">
		return props
	end,
	widthPicker = function(props: Facet.PickerSpec<"fill" | "hug">): Facet.PickerSpec<"fill" | "hug">
		return props
	end,
	text = function(props: Facet.TextProps): Facet.TextProps
		return props
	end,
}
