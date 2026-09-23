# Control families

Create controls with `local UI = Facet.controls(runtime)`. Controls return native Instances, accept native properties, and use Compose readables for data. [The API reference](../reference/api.md) lists required fields and callbacks.

| Family | Controls |
|---|---|
| Actions | Button, SplitButton, Menu, RadialMenu |
| Input | TextInput, Toggle, Slider, Stepper, Rating, LevelPicker, Chip |
| Choices | Picker, ComboBox |
| Navigation | TabView, NavigationStack, PageView |
| Presentation | Alert, Sheet, DisclosureGroup, CollapsibleView, Callout |
| Data | VirtualList, VirtualGrid, Table, RowActions |
| Information | Label, Badge, StatusIndicator, ProgressView, Skeleton, ShortcutHint |
| Media | AsyncImage, Avatar, AvatarGroup, Stage |

The screen owns domain values. Input callbacks request changes; a provided callback must update the model to accept a request. Picker and other navigation selections update their writable model and then notify. Use the specific control contract rather than assuming every callback has identical semantics.

Native layout composition uses Host classes. Reactive ownership and structure use Compose. Those mechanisms are not duplicated as another control family.

Choose controls by task, [as described here](14-choosing-controls.md), and test the actual input paths and accessibility behavior in the gallery.
