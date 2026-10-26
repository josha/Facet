### State

<!-- aliases: State | state | Compose.show -->

Readables and `function(use)` bodies bind reactive properties. The caller owns
the state. An input value control writes a writable cell when the related
callback is absent. If you supply `onChange` or `onToggle`, the callback is a
request. Update the model in the callback to accept it. Navigation controls
document their own write-then-notify behavior below.

Use `Compose.show(isOpen, Details)` to mount the Details component while a
readable boolean is true. Compose owns the branch and cleans it up when false.
Use `Facet.Compose` from the same Facet root as the app.

A content factory constructs children; it is not a reactive property callback.
Reading `page:peek()` there chooses only the initial page. For changing content,
put a Compose branch inside the container:

```luau
local page = Compose.cell("Garage")
local function Garage() return UI.Text { text = "Garage" } end
local function Shop() return UI.Text { text = "Shop" } end
UI.VStack {
    Compose.show(function(use: Facet.Use) return use(page) == "Garage" end, Garage),
    Compose.show(function(use: Facet.Use) return use(page) == "Shop" end, Shop),
}
```

Keep `page` in the model. Closing and reopening a surface changes presentation,
not its child structure. Use navigation controls for a page stack with Back.

In strict Luau, `Facet.Value<T>` types a writable cell, `Facet.ReadOnlyValue<T>`
types a value that a `use` call reads, and `Facet.Use` types the `use`
parameter, `<T>(Facet.ReadOnlyValue<T>) -> T`. When the type checker cannot infer a
`function(use)` body, for example a body that reads cells of two types, give
the parameter the type: `function(use: Facet.Use)`. A collection `render`
receives `current: Facet.ReadOnlyValue<Item>`.

```luau
local coins: Facet.Value<number> = Compose.cell(0)
local name: Facet.Value<string> = Compose.cell("Ann")
local label = UI.Text "Coins" {
    text = function(use: Facet.Use) return use(name) .. ": " .. use(coins) end,
}
```
