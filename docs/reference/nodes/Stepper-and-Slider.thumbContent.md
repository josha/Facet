# Stepper-and-Slider.thumbContent

Stepper-and-Slider.thumbContent option values and behavior.

- The track is at least 44 pixels long. A cell that fits its content keeps a
  track that you can drag.
- Each knob travels inside the rail by half of its own art size. At the
  minimum, the left edge of the knob art is at the start of the rail. At the
  maximum, the right edge is at the end of the rail. A vertical knob stops on
  the bottom and the top of the rail. The control measures each knob
  separately, so two custom knobs of different sizes both stop flush. For
  `thumbContent`, the art is the first GuiObject that the function returns.
  The fill ends at the centre of the knob. A press or a drag reads the value
  from the same inset travel. With `thumb = "none"`, the travel is the full
  rail.


Losing the input class during a drag (a change of `PreferredInput`) restores
the value, or the whole pair, from the start of the drag. The later move and
release commit nothing.
