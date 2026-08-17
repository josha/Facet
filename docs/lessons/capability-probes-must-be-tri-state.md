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

## It happened again, to a diagnostic instrument (2026-08-16)

The HUD's paint probe compared the framework's model against the engine's own paint
bit and reported the disagreement. Its per-path engine verdict was a boolean, and it
opened:

```lua
local geo = if ctx.geometry ~= nil then ctx.geometry(PROBE_QUERY) else nil
local function enginePaints(path: string): (boolean, string?)
    if geo == nil then
        return true, nil          -- "could not measure" published as "measured yes"
    end
```

**The same collapse, one layer up.** A `false` that means "the name is wrong" and a
`false` that means "I was not allowed to look" are the 2026-07-26 pair; a `true` that
means "I saw it paint" and a `true` that means "there was nothing to see with" are this
one. The instrument printed `13 of 13 painting` on a phone that was visibly missing six
things, and the director acted on the number.

Two extra teeth this instance grew, both worth copying:

1. **A seam that answered NOTHING is not a screen with nothing wrong.** The host reads
   `adapter.getInstance`; an adapter without it returns `{}` — forty paths asked, zero
   answered. `geo ~= nil` was true and every row would have been called LOST, which is
   the same false verdict pointing the other way. The condition is `answered > 0`.
2. **A count is a claim.** When the measurement is unavailable the readout now *replaces*
   the count with `ENGINE SIDE UNAVAILABLE — MODEL ONLY` rather than annotating it. A
   reader who skims and finds a number has been told a fact, and a caveat beside it is
   not a retraction. Three states — `painting`, `LOST`, `UNMEASURED` — are reported
   separately, and the count cannot print while either of the other two is non-empty.

And the same shape hides in a *denominator*: a row the probe could not hold the engine
to was `continue`d out of the total entirely, so `13 of 13` was really 13 of 14 with
nothing said. **An unmeasurable row must be named, never omitted** — the totals now read
`11 of 14 rows wanted / skipped: ScoreHome · TimerRing · ScoreAway`.

## The general rule

**Before recording that a platform cannot do something, check the name against
first-party documentation.** "The API refused me" is a claim about Roblox;
"I typed it wrong" is a claim about you, and only one of them belongs in a
document other people will act on.
