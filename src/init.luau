--!strict
local Compose = require("@self/vendor/compose/core")
local Roblox = require("@self/vendor/compose/roblox")
local ControlTypes = require("@self/ui/control_types")
local createControls: ControlTypes.Factory = require("@self/ui")
local bindThemes = require("@self/ui/themes")
local InputTypes = require("@self/ui/input_types")
local NavigationTypes = require("@self/ui/navigation_types")
local RadialTypes = require("@self/ui/radial_types")
local CollectionTypes = require("@self/ui/collection_types")
local MediaTypes = require("@self/ui/media_types")
local ContentTypes = require("@self/ui/content_types")
local ThemeTypes = require("@self/ui/theme_types")
local LayoutTypes = require("@self/ui/layout_types")
local createApp = require("@self/ui/app")
local OverlayTypes = require("@self/ui/overlay_types")
local civilDate = require("@self/ui/civil_date")
local CivilTypes = require("@self/ui/civil_date_types")
local DateTimePickerTypes = require("@self/ui/date_time_picker_types")
local ColorPickerTypes = require("@self/ui/color_picker_types")
local arithmetic = require("@self/ui/arithmetic")
local adaptive = require("@self/ui/adaptive")
local EnvironmentTypes = require("@self/ui/environment_types")
export type ButtonProps = InputTypes.ButtonProps
export type ToggleProps = InputTypes.ToggleProps
export type TextInputProps = InputTypes.TextInputProps
export type NumberInputProps = InputTypes.NumberInputProps
export type StepperProps = InputTypes.StepperProps
export type SliderProps = InputTypes.SliderProps
export type RatingProps = InputTypes.RatingProps
export type LevelPickerProps = InputTypes.LevelPickerProps
export type ChipProps = InputTypes.ChipProps
export type ShortcutHintProps = InputTypes.ShortcutHintProps
export type MenuItem<V = string> = NavigationTypes.MenuItem<V>
export type MenuSpec<V = string> = NavigationTypes.MenuSpec<V>
export type PickerOption<V = string> = NavigationTypes.PickerOption<V>
export type PickerSpec<V = string> = NavigationTypes.PickerSpec<V>
export type SplitButtonSpec<V = string> = NavigationTypes.SplitButtonSpec<V>
export type ComboBoxSpec = NavigationTypes.ComboBoxSpec
export type DisclosureGroupSpec = NavigationTypes.DisclosureGroupSpec
export type CollapsibleViewSpec = NavigationTypes.CollapsibleViewSpec
export type AlertAction<P = unknown> = NavigationTypes.AlertAction<P>
export type AlertSpec<P = unknown> = NavigationTypes.AlertSpec<P>
export type SheetSpec = NavigationTypes.SheetSpec
export type CalloutSpec = NavigationTypes.CalloutSpec
export type Tab = NavigationTypes.Tab
export type TabViewSpec = NavigationTypes.TabViewSpec
export type NavigationEntry<P = unknown> = NavigationTypes.NavigationEntry<P>
export type NavigationDestination<P = unknown> = NavigationTypes.NavigationDestination<P>
export type NavigationStackSpec<P = unknown> = NavigationTypes.NavigationStackSpec<P>
export type PageViewSpec = NavigationTypes.PageViewSpec
export type RadialItem<V = string> = RadialTypes.RadialItem<V>
export type RadialMenuSpec<V = string> = RadialTypes.RadialMenuSpec<V>
export type KeyedCollectionSpec<V, K> = CollectionTypes.KeyedCollectionSpec<V, K>
export type IdentityCollectionSpec<V> = CollectionTypes.IdentityCollectionSpec<V>
export type CollectionSpec<V, K> = CollectionTypes.CollectionSpec<V, K>
export type RowAction = CollectionTypes.RowAction
export type RowActionsSpec = CollectionTypes.RowActionsSpec
export type TableColumn<V, K> = CollectionTypes.TableColumn<V, K>
export type KeyedTableSpec<V, K> = CollectionTypes.KeyedTableSpec<V, K>
export type IdentityTableSpec<V> = CollectionTypes.IdentityTableSpec<V>
export type TableSpec<V, K> = CollectionTypes.TableSpec<V, K>
export type LabelProps = MediaTypes.LabelProps
export type BadgeProps = MediaTypes.BadgeProps
export type StatusIndicatorProps = MediaTypes.StatusIndicatorProps
export type ProgressViewProps = MediaTypes.ProgressViewProps
export type SkeletonProps = MediaTypes.SkeletonProps
export type ImageResource = MediaTypes.ImageResource
export type AsyncImageProps = MediaTypes.AsyncImageProps
export type AvatarProps = MediaTypes.AvatarProps
export type AvatarMember = MediaTypes.AvatarMember
export type AvatarGroupProps = MediaTypes.AvatarGroupProps
export type StageProps = MediaTypes.StageProps
export type PaginationSpec = ContentTypes.PaginationSpec
export type StepIndicatorSpec = ContentTypes.StepIndicatorSpec
export type Step = ContentTypes.Step
export type VoteSpec = ContentTypes.VoteSpec
export type CardSpec = ContentTypes.CardSpec
export type CardControls = ContentTypes.CardControls
export type BadgeValue = ContentTypes.BadgeValue
export type Space = LayoutTypes.Space
export type Padding = LayoutTypes.Padding
export type Extent = LayoutTypes.Extent
export type StackProps = LayoutTypes.StackProps
export type ScreenProps = LayoutTypes.ScreenProps
export type ZStackProps = LayoutTypes.ZStackProps
export type ScrollViewProps = LayoutTypes.ScrollViewProps
export type GridProps = LayoutTypes.GridProps
export type ErrorBoundaryProps = LayoutTypes.ErrorBoundaryProps
export type OverlayAction = OverlayTypes.Action
export type OverlayMedia = OverlayTypes.Media
export type OverlayHero = OverlayTypes.Hero
export type DialogSpec = OverlayTypes.DialogSpec
export type PopoverSpec = OverlayTypes.PopoverSpec
export type NoticeSpec = OverlayTypes.NoticeSpec
export type NavBarSpec = OverlayTypes.NavBarSpec
export type SnackbarSpec = OverlayTypes.SnackbarSpec
export type DateTimePickerProps = DateTimePickerTypes.DateTimePickerProps
export type ColorPickerProps = ColorPickerTypes.ColorPickerProps
export type Controls = ControlTypes.Controls
export type Environment = EnvironmentTypes.Environment
export type InteractionClasses = EnvironmentTypes.InteractionClasses
export type SafeInsets = EnvironmentTypes.SafeInsets
export type WorldAnchorOptions = EnvironmentTypes.WorldAnchorOptions
export type WorldAnchor = EnvironmentTypes.WorldAnchor
export type ScrollOptions = EnvironmentTypes.ScrollOptions
export type Adaptive = adaptive.Adaptive
export type App = createApp.App
export type AppOptions = createApp.AppOptions
export type Component = createApp.Component
export type ControlOptions = ControlTypes.Config
export type ThemePackage = ThemeTypes.ThemePackage
export type CivilDate = CivilTypes.CivilDate
export type CivilRange = CivilTypes.Range
export type CivilLocale = CivilTypes.Locale
export type CivilDateModule = CivilTypes.Module
export type Cell<T> = Compose.Cell<T>
export type Readable<T> = Compose.Readable<T>
export type Runtime = Compose.Runtime
export type Owner = Compose.Owner
export type Use = Compose.Use
export type ComposeModule = typeof(Compose)
export type ComposeRobloxModule = typeof(Roblox)
export type Facet = {
	VERSION: string,
	COMPOSE_COMMIT: string,
	Compose: ComposeModule,
	Roblox: ComposeRobloxModule,
	controls: (Runtime, ControlOptions?) -> Controls,
	app: (AppOptions?) -> App,
	themes: ThemeTypes.Themes,
	civilDate: CivilTypes.Module,
	adaptive: adaptive.Adaptive,
	recipes: { arithmetic: { parse: (unknown) -> number? } },
	bind: (ComposeModule, ComposeRobloxModule) -> Facet,
}

local VERSION = "0.12.0"
local COMPOSE_COMMIT = "869d26020a304ff8c3e5e18ff0eaf803b875a083"
local USED = {
	"boundary",
	"cell",
	"cleanup",
	"createFocusScope",
	"createPool",
	"createSharedResource",
	"currentOwner",
	"formula",
	"fragment",
	"isReadable",
	"keyed",
	"portal",
	"presence",
	"sharedCell",
	"show",
	"static",
	"switch",
	"watch",
	"withOwner",
}

local recipes: { arithmetic: { parse: (unknown) -> number? } } =
	table.freeze({ arithmetic = table.freeze({ parse = arithmetic.parse }) })

local function bind(core: ComposeModule, roblox: ComposeRobloxModule): Facet
	local fields = (core :: unknown) :: { [string]: unknown }
	for _, name in USED do
		if type(fields[name]) ~= "function" then
			error(
				`Facet.bind: this Compose has no function '{name}'. Facet {VERSION} supports Compose `
					.. `{string.sub(COMPOSE_COMMIT, 1, 7)} and later commits that keep the functions Facet uses.`,
				2
			)
		end
	end
	if type(roblox) ~= "table" or type(roblox.createRuntime) ~= "function" then
		error("Facet.bind: pass the Compose Roblox module from the same Compose copy as the second argument", 2)
	end
	local themes = bindThemes(core)
	local surface: Facet
	surface = table.freeze({
		VERSION = VERSION,
		COMPOSE_COMMIT = COMPOSE_COMMIT,
		Compose = core,
		Roblox = roblox,
		controls = function(runtime: Runtime, options: ControlOptions?): Controls
			return createControls(core, runtime, options)
		end,
		app = function(options: AppOptions?): App
			return createApp(core, roblox, createControls, themes, options)
		end,
		themes = themes,
		civilDate = civilDate,
		adaptive = adaptive,
		recipes = recipes,
		bind = bind,
	})
	return surface
end

return bind(Compose, Roblox)
