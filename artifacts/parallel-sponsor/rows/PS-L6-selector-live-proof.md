# PS-L6 (partial) — selector exclusivity, live Studio proof

**Date:** 2026-07-30 · Play Solo, bench `TrackLayout=debug`, source verified
synced (rojo serve; LuauUISponsor/rig/hook/selector all present in the
DataModel before play). Suite at proof time: **2513 passed** (RR), stylua
clean, 11/11 legacy checksums OK, sanctioned changes stamped in
`baseline/sanctioned-changes-post-abc.txt`.

## Run 1 — flag absent (the shipped default)

`UseLuauUISponsor=nil` → after `("role","sponsor")`:
`legacySponsorGui=true, luauuiDev=false`. Legacy path intact; nothing
LuauUISponsor-related loads (require sits inside the branch).

## Run 2 — flag true

`UseLuauUISponsor=true` → after `("role","sponsor")`:
`legacyCount=0, devCount=1, devName=LuauUI_SponsorDev,
chip="LuauUI Sponsor [dev] · build 0.7.0 · presenter=luauui",
role=sponsor, pillAlive=true` — exactly one presenter mounted, legacy NEVER
constructed, sibling consumer (ShowrunnerPillGui via `sponsor:phase()` /
`mapMax()`) alive. Capture: `baseline/studio/PS-L6-selector-on-devchip.png`.

## Rig canary (same Run 2 session)

`RascalSponsorScenarioAPI` from the Server VM:
`select("results-sponsor")` → steps `economy, story, storyBlocked, rollcall,
skipToIntermission`, stamp `rascal-sponsor-scenario/1:results-sponsor`;
`holdPhase("results")` → `RoundPhase == "results"` at +3 s AND +11 s (held —
the live bench otherwise auto-advances in ~7 s); `report()` exported the full
fixture attribute snapshot (hand `tailwind,bubble,raincloud`, drama 210,
charge 85, FlowPhase RESULTS); `release()` clean. Note: API Invoke() returns
JSON STRINGS (decode before use — same convention as LuauUIScenarioAPI).

## Still owed on PS-L6 (by later layers)

- duplicate-command trace across fixtures counting `SponsorCmd` + `WatchFocus`
  + `WatchPark` with an interactive LuauUI surface actually issuing intents;
- teardown-before-remount under live selector churn (headless churn spec
  passes; live churn row runs with the first interactive layer);
- live pcall-fallback exercise: covered headlessly + by code identity with the
  racer-list precedent (a DataModel sabotage fight with rojo sync isn't worth
  the risk); recorded here as an accepted evidence substitution.

Flags and `TrackLayout=firstSmile` restored after the session.
