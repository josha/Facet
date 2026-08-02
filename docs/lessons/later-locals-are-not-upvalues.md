# A local declared LATER in the file is NOT an upvalue — it silently binds a nil global

**Hit four times as of 2026-07-25.** The fourth instance shipped a boot crash the
entire 1313-spec suite could not see.

## The trap

```lua
local function focusColor(): Color3
	return focusTreatment.color or COLOR.accent  -- COLOR is declared BELOW
end

local COLOR = { accent = ... }
```

Luau resolves names lexically at function-definition time. `COLOR` is not in
scope yet, so the function captures the **global** `COLOR` — which is `nil` —
and the file still parses, type-checks under `--!strict` in practice (the
global reads as `any`), and loads without a warning. The failure is deferred to
the first CALL: `attempt to index nil with 'accent'`.

## Why the suite stays green

The fourth hit was in `src/client/screen_target.luau` — the ENGINE adapter.
Headless specs run against `fake_target`; no Lune spec ever executes the real
adapter's body, so the only place this class of bug can surface is a real
Studio boot. This is exactly what the live-drive step of the verification
contract exists for: `present()` crashed on frame one of the first Play
session and the suite had just passed at 1313.

## The rule

When adding a function to a large existing file, CHECK THE DECLARATION ORDER of
every local it references — grep for `local <Name>` and confirm the line number
is ABOVE the new function. Module-scope tables (`COLOR`, `TAGS`, config tables)
declared mid-file are the usual victims because the file reads as if they were
"always there".

If the reference cycle is genuinely two-way, use the forward-declaration
pattern the same file already uses for functions:

```lua
local refreshFocusVisuals: () -> ()   -- declared early
...
function refreshFocusVisuals()        -- assigned later
```

## Prior hits

1. Step 2 native-stylesheets round — a rule-builder referencing a later
   selector table.
2. Step 3.5 build — a controller helper referencing a later-declared
   `dangerPair` local (found headlessly because that one WAS pure).
3. Step 3.5 review-fix round — same class inside `sheet_model`.
4. 2026-07-25 director fix round — `focusColor()`/`COLOR` above; engine-only,
   caught live.
