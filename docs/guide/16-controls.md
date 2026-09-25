# Control families

Make controls with `local UI = Facet.controls(runtime)`. Controls return native
Instances and accept native properties. They use Compose readables for data.
[The API reference](../reference/api.md) lists the required fields and
callbacks.

| Family | Controls |
|---|---|
| Actions | Button, SplitButton, Menu, RadialMenu |
| Input | TextInput, Toggle, Slider, Stepper, Rating, LevelPicker, Chip, Vote |
| Choices | Picker, ComboBox |
| Navigation | TabView, NavigationStack, PageView, Pagination, StepIndicator |
| Presentation | Alert, Sheet, DisclosureGroup, CollapsibleView, Callout |
| Data | VirtualList, VirtualGrid, Table, RowActions, Card |
| Navigation | TabView, NavigationStack, PageView, NavBar |
| Presentation | Alert, Dialog, Sheet, Popover, DisclosureGroup, CollapsibleView, Callout |
| Feedback | Notice, Snackbar |
| Data | VirtualList, VirtualGrid, Table, RowActions |
| Information | Label, Badge, StatusIndicator, ProgressView, Skeleton, ShortcutHint |
| Media | AsyncImage, Avatar, AvatarGroup, Stage |

## Callbacks

The screen owns the domain values. Input callbacks request changes. If you
supply a callback, it must update the model to accept the request. Picker and
the other navigation controls update their writable model first, and then
notify. Callbacks do not all have the same semantics. Read the contract of each
control.

## What is not a control family

Native layout composition uses Host classes. Reactive ownership and structure
use Compose. Facet does not duplicate those mechanisms as a control family.

Choose controls by task, as [Choosing controls](14-choosing-controls.md)
describes. Test the actual input paths and the accessibility behavior in the
gallery.
