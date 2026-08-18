# UIShadow + per-corner UICorner — verified engine facts (2026-07-20)

Fresh-context Opus platform research for the Phase 4 engine-styling adoption
(design §17). Sources: create.roblox.com class references (UIShadow, UICorner)
and the "Full Release: New UI Capabilities — Shadows, Individual Corners"
devforum post (§21). Confidence high unless noted.

## UIShadow (GA — beta flag removed)

| Property | Type | Semantics |
|---|---|---|
| BlurRadius | **UDim** | Scale = fraction of the parent's SHORTEST dimension, plus a pixel Offset term; clamped non-negative; softness to ~1000 (numeric bound: medium confidence) |
| Color | Color3 | tint (enables glow) |
| Transparency | number 0..1 | |
| Offset | UDim2 | scale = fraction of parent dimensions |
| Spread | **UDim2** | grow (+) / shrink (−) relative to parent |
| ZIndex | number, **negative only** | shadows always render below the parent |
| Enabled | boolean | |

- Applies to frame-like GuiObjects (not Path2D); on Text* instances the shadow
  renders on the BACKGROUND RECT, not glyphs; multiple UIShadows may share a
  parent; purely visual — never enters layout.
- Guidance: ~100 on-screen shadows max (perf budget); shadows may appear
  jagged with a large corner radius (style-lint warning).

## Per-corner UICorner (GA)

- `TopLeftRadius` / `TopRightRadius` / `BottomLeftRadius` / `BottomRightRadius`
  (each UDim); `CornerRadius` is the alias — setting it writes all four,
  READING it returns TopLeftRadius.
- Mixing the alias with individual corners misbehaves → the framework emits
  EXACTLY ONE form per node (uniform alias OR four per-corner values), never
  both (enforced at modifier build time + style lint).

## Discrepancies vs design §17 wording (encoded in the token schema)

1. §17 says "BlurRadius (percent of the parent's shortest dimension)" — the
   authoritative type is **UDim (scale + pixel offset)**. Facet encodes
   blurRadius as `{ scale, offset }`, not a bare percent.
2. §17 lists Spread without a type — it is **UDim2**. Encoded as
   `{ x = {scale, offset}, y = {scale, offset} }`.

## Headless reality (verified empirically under Lune 0.10.4)

- `Instance.new("UIShadow")` → error ("not a valid class name"); Lune's
  UICorner knows only `CornerRadius`. The headless path therefore represents
  shadow/corner styling as **pure style data** on the node (dumped through the
  adapter's style props); instances are created only by the client adapter
  behind capability detection with a headless/no-op fallback.

## Recommended Studio fidelity probe (for the engine-fidelity fixture)

Create UIShadow under a Frame, set all seven properties, read back (types
round-trip; ZIndex rejects/ignores positive); set four distinct per-corner
radii, assert CornerRadius reads TopLeftRadius, then set CornerRadius and
assert all four overwritten; parent a UIShadow to a TextButton (background
rect, not glyphs); large-corner-radius jagged check drives the lint threshold.
