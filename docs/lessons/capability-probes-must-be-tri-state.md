# A boolean capability probe will eventually publish a false platform fact

**Learned:** 2026-07-26, the hard way, twice in one stage.

Indexing a member that does not exist on a Roblox instance **throws**; it does
not return `nil`. So every capability probe has to catch. The obvious shape is:

```lua
local function hasMethod(instance, member): boolean
    local ok, value = pcall(function() return instance[member] end)
    return ok and type(value) == "function"
end
```

This is wrong, and it is wrong in a way that produces confident, published,
false statements about the platform. `false` collapses two completely different
situations:

| Error text | What it means | What to do |
|---|---|---|
| `X is not a valid member of Y` | **the name is wrong** | fix the name |
| `The current thread cannot access X (lacking capability PluginSecurity)` | the name is right, the caller is not allowed | record the limit, or raise the security level |

## What it cost

In one stage, this shape produced two false platform facts that reached a user
guide, a plan document, a lesson file and five stored evidence rows:

1. *"`VirtualInput` exposes no `Send*` methods at this security level."* The
   probe used four invented names (`SendMouseButtonEvent`, `SendMouseMoveEvent`,
   `SendKeyEvent`, `SendTextInputEvent`). The real, documented surface is
   `SendKey`, `SendMouseButton`, `SendMouseDelta`, `SendMousePosition`,
   `SendPointerAction`, `SendTextInput` — all present and callable.
2. *"`StudioDeviceSimulatorService` has no stop, clear or reset member."* The
   probe asked for `StopDeviceAsync`, `ResetDeviceAsync`, `ClearDeviceAsync` and
   `GetCurrentDeviceAsync`. The real name is **`StopSimulationAsync`**, and the
   service also exposes `GetDeviceAsync`, `GetResolutionAsync`,
   `GetPixelDensityAsync`, `GetOrientationAsync` and `GetScalingModeAsync`.

Both survived a live run, because a wrong name and a real refusal look identical
through a boolean — and both were caught only by a fresh-context review that
checked the names against first-party documentation.

## The shape to use

```lua
local function probeMethod(instance, member)
    local ok, value = pcall(function() return instance[member] end)
    if ok then
        return { state = if type(value) == "function" then "present" else "notAFunction",
                 type = typeof(value) }
    end
    local err = tostring(value)
    local state = if string.find(err, "is not a valid member", 1, true) ~= nil then "absent"
        elseif string.find(err, "lacking capability", 1, true) ~= nil then "blocked"
        else "error"
    return { state = state, error = err }
end
```

Keep the raw error text in the record. `absent` is a bug in your code;
`blocked` is a fact about the environment; and an artifact that says which one
it saw can be argued with.

## The general rule

**Before recording that a platform cannot do something, check the name against
first-party documentation.** "The API refused me" is a claim about Roblox;
"I typed it wrong" is a claim about you, and only one of them belongs in a
document other people will act on.
