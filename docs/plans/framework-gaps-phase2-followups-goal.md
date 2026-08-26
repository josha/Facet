# /goal — Facet follow-ups: 16 director questions + the test-system mandate

Controller session. Facet repo: GameStudio/ui/Facet (main, in place); RascalRally
lockstep: games/RascalRally/code. READ FIRST:
`.superpowers/sdd/framework-gaps-phase2/progress.md` (ledger: all process rules, traps,
open threads) and `binding-context.md` beside it. Evidence files named below live in the
UntitledRacingGame root — verify each exists; ask the director for any missing. Extract
.mov frames with ffmpeg before analysis. Iron Law on every bug: root cause, red-first,
review. Remaining punch items (review sweep of FIX-2/3/4, device-owed register, stamps
decision) stay booked in the ledger — do not drop them.

## The 16
1. FIX the PS5 overlap bug — reproduced; headless red case staged in task-fix4-report.md
   (composition.luau lane-budget: top exclusions push vs bottom-anchored group).
2. Default edge padding: WHICH screens break, and are they truly non-functional or just
   shifted? (fix4 casualty table claims 21 real breaks — re-verify each honestly.) Desktop
   wants padding (padding.png: tabs-nested, badge "3" touches content); mobile looks ok.
   Answer per-screen; propose a default the director can approve.
3. desktopScroll.png: desktop scrollbar reserves no pixels, overlaps content. Fix.
4. Gamepad: holding d-pad doesn't repeat/advance selection. Framework should auto-repeat.
5. Handheld (ROG Ally): fonts default too small — likely classed as console/ten-foot by
   input, not by SCREEN SIZE. Size classes must consider physical screen size. Fix.
6. Pixel Quest theme, screen-anchored HUD: top buttons show no labels (IMG_3785.jpeg).
7. Pixel Quest, same HUD: task list overflows its box (IMG_3786.jpeg).
8. Pixel Quest, tabs-nested: tab font has no padding, overlaps edge (IMG_3787.jpeg).
9. Pixel Quest, playlist table edit mode: delete control overlaps row (IMG_3788.jpeg).
   For 6-9: why doesn't the solver/containment system prevent themed overflow? Fix the
   CLASS, not four symptoms — the containment invariant should catch themed geometry.
10. More POPS: cartwheel triangle-tap (cartwheelNarrowPopOverlap.mov), glade tap
    (newpop.mov). Find the GENERAL framework-level fix for the pop class, not per-site
    patches — we keep finding these one at a time.
11. glade-corner.png: some cards carry a partial gray corner stroke. What is it? Fix.
12. OddOverlapNotRound.png + whatisthis.png: "round" control isn't round; double-draw
    (blue-on-gray + white-on-gray, offset). Fix at framework level — circles need a
    better approach than what we have.
13. overlap.png: screen-anchored HUD now overlaps at the bottom ON A PHONE. Same family
    as #1? The framework should make overlap impossible — say why it isn't.
14. Design change: menus/five-triggers "panel" on mobile — sub-menus (e.g. Layering)
    open a second panel; should be ONE panel with a back button on mobile, expand on
    medium/large (shouldHaveSinglePanel.png).
15. wardrobeCrampedCards.png: cards too narrow, second image off-center — framework
    minimum-width issue? Cards shouldn't get that cramped.
16. "Container that carries" showcase renders EMPTY — should it?

## The mandate (answers required, then build it)
The director keeps finding overlap/cutoff/stray-stroke/pop bugs in the STUDIO DEVICE
EMULATOR (reachable via the Studio MCP) that headless tests miss — including themed
(Pixel Quest) breakage. (a) Build device-emulator visual sweeps into the test system:
scripted emulator passes across device presets AND theme packages, screenshot + assert
(GetStyled paint, containment on-glass), so these are found before the director sees
them. (b) Answer: do pop bugs show up headlessly at all? Design the fundamental guard
(e.g. first-paint-equals-settled-layout invariant) so the pop CLASS dies. Ship both as
gates, not one-off scripts.
