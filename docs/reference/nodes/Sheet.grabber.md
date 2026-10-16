# Sheet.grabber

The grabber is also a selectable button. A tap or click closes the sheet
(with `interactiveDismissDisabled` it grows the sheet instead). The engine
gives a press on the grabber to its drag detector and never fires the button's
`Activated`, so a grip drag that ends within 4 pixels of where it started is
the tap. Return or the
gamepad A button grows the sheet to the next taller detent, and its accessible
label reads `Resize: Medium`, or `Resize: Fit` for `hug`. At the tallest
detent, and with one detent, Return or A closes the sheet, and its label reads
`Close sheet`. The grabber's own drag detector
takes a press-drag that starts on the pill, and a release after a drag is not
also a click. The pointer shows a resize cursor over the grabber and a closed
hand while it drags (`SizeNS`, or `SizeEW` on a side sheet, and
`ClosedHand`). Return and the gamepad A button activate it. A bottom
sheet slides up from the bottom and slides down when it closes. The sheet
stays off screen until its room, width, text and height are the same for two
frames, and then it starts to move. Thus the text has its final size and wrap
before the sheet shows, and the height does not change during the slide. With
reduced motion the sheet appears at rest after the same wait. See
[Motion](Motion.md).
