# Look, then repair

This page holds the full form of the checks in
[step 4 of the skill](../SKILL.md#4-look-then-repair). Read it when a check
there needs its detail, when you run an independent review, or when a
finding of `Facet.review` needs its meaning.

View each capture at its real size. A text report does not show the screen.
Check these in order and stop at the first failure.

1. **Fit.** Nothing is clipped, overlapped or unreachable at any size. The
   ground reaches every edge, with no band of the game world beside it. The
   main action is inside the thumb's reach on a phone. Every part of the
   desktop screen is present at every size under the same label: a part can
   move or shrink, but it does not vanish or change its name. List the parts
   and labels of the desktop capture and find each one in the other captures.
   A part stays with its group at every size, and an action that discards
   work does not sit beside the main action. The furniture of the place stays
   where it is when the state changes. On a phone, a row of controls keeps a
   margin of 16 pixels or more at each side.
2. **Lead.** The subject or the content is the largest and clearest thing on
   the screen, at every size. On a desktop its objects and markings span most
   of the width. Play that sits in a centre column under half the width is too
   small: scale the lead from the measured room.
3. **Identity.** With the title hidden, the screen still belongs to this
   product. For an expressive game, these are signs of an unfinished direction:
   a flat neutral ground; one font family at nearly one size; choices that are
   equal rectangles with different labels; a main action that looks like every
   other button; a small subject beside a large empty area. Put the capture
   beside the chosen sketch: the place, the lead and the objects of the
   sketch are all in the capture.
4. **States.** Selected, focused, pressed and disabled paint belong to the
   theme, and selection stays clear when focus moves to a peer. In a still
   capture, a person who has not used the screen can name the selected choice.
5. **Response.** Commit with real input. The response on the card happens, and
   the action stays in place.
6. **Craft.** Crop the capture to each kind of object and view it at twice its
   size. The objects of the lead have the most detail on the screen, with the
   parts that a player expects on the real thing. No image is soft, stretched
   or flat where its material has grain. Nothing is a placeholder: no dash
   for a missing value, no empty outline, no hint glyph that looks like debug
   text. All numerals use one family. Art that shows a value shows the real
   one. A disabled control is drawn in the same family as the enabled one.
   Parts of one group share a baseline, also after an animation ends. A label
   on a piece of art lies inside the painted shape, with a margin, and
   contrasts with the paint behind it. No object is stretched away from its
   drawn proportions. [Art](art.md#spend-the-detail-where-the-player-looks)
   has the standard.

For an expressive game, an independent review is the largest gain in finish
that is available after the first build. Your own check of your own screen
misses faults that a fresh viewer sees at once. When you can start a separate
agent, give it only the user's request and the captures of every size. Ask it
to act as a strict art director who has not seen the work: to score identity,
craft, hierarchy and the fit at each size from 1 to 5, and to list every
fault that stops a 5, most important first, each specific enough to act on
without its other notes. Repair the list in order, at the cause, and keep
what works. Capture again and repeat with a new reviewer. Two rounds are
usual. Stop when the list is small polish, and do not ask a reviewer to
approve the result. When you cannot start an agent, tell the user that the
screen has had no independent review.

Repair the two largest gaps at their cause, then capture again. Enlarge the
lead or the type before you add panels; fix the theme before you paint one
control. A quiet tool passes the identity check with a plain ground and one
family; judge its hierarchy, rhythm, density and states.

Run `Facet.review.screen().text` in the Client data model on each changed
screen, at each size that you capture and in each state that has its own
message, such as the empty state and the result. A collision at one size does
not show at another. Fix `empty-screen`, `build-failed`, `runtime-error` and
each `high` finding before building the next screen. `overlapping-text` is
high: two texts collide at this size. `covered-text` names a label that is
under a plate from another part at this size, and `escaped-text` names a
label that runs past its backing or that a clip cuts; repair them unless the
effect is deliberate. `native-text` names labels that were built outside
Facet; rebuild them with `UI.Text`. Treat other findings as prompts to look,
not as verdicts. For an image, the review uses the painted bounds, which it
reads from the pixels in Studio, so a label that runs over the edge of the
paint is found. It does not find a label that is mostly on the transparent
margin, on a soft shadow or over a hole in the paint, and it uses the
