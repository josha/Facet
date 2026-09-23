--!strict
local Compose = require("@self/vendor/compose/core")
local Roblox = require("@self/vendor/compose/roblox")
local ControlTypes = require("@self/ui/control_types")
local createControls: ControlTypes.Factory = require("@self/ui")
local InputTypes = require("@self/ui/input_types")
local NavigationTypes = require("@self/ui/navigation_types")
local CollectionTypes = require("@self/ui/collection_types")
local MediaTypes = require("@self/ui/media_types")
local ThemeTypes = require("@self/ui/theme_types")
export type ButtonProps = InputTypes.ButtonProps
export type ToggleProps = InputTypes.ToggleProps
export type TextInputProps = InputTypes.TextInputProps
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
export type Controls = ControlTypes.Controls
export type ControlOptions = ControlTypes.Config
export type ThemePackage = ThemeTypes.ThemePackage
export type Cell<T> = Compose.Cell<T>
export type Readable<T> = Compose.Readable<T>
export type Runtime = Compose.Runtime
export type Owner = Compose.Owner
export type Use = Compose.Use
return table.freeze({
	VERSION = "0.12.0",
	Compose = Compose,
	Roblox = Roblox,
	controls = createControls,
	themes = require("@self/ui/themes"),
})
