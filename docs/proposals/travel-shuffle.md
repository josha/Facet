# Rack shuffle

The player shuffles seven rack items. The game changes their slots. Travel
keeps the same visuals and moves them in place. A second shuffle can change
the slots before the first motion ends.

Add stagger as a zero-based ripple index, or a function that returns that
index at each slot change. Multiply it by motion.durations.travelStagger.
Add lift as an opt-in native scale envelope. Its peak uses
motion.scales.travelLift. Arc uses the existing travelArc token. Each active
carrier has a distinct flight depth above resting items. Restore scale and
depth on landing. onStarted reports the actual start after the delay;
onLanded reports arrival. The game owns sounds and the permutation.

Roblox UIScale.Scale scales the whole visual. GuiObject.ZIndex and native
Sibling stacking order the carriers. TweenInfo.DelayTime can delay a tween,
but cannot preserve the shared spring's velocity on retarget. Compose's
host.frames.onFrame, createSpringState and stepSpring already supply the
shared clock and spring state. Extend the Travel engine's policy for the
delay. Do not add a per-item clock or an instance per shuffle.

The delay applies only to an idle item. An interrupted item retargets at
once from its current position and lift. Reduced motion ignores delay and
lands at once. Pan and input contracts do not change.

Sample seven simultaneous moves, start order, unique flight depth, lift,
arc, final slots and an interrupted second permutation. Check instance
counts. Add a shuffle a row variant to the existing Travel Lab page. Native
text, stacking and the feel of the ripple need a phone check.
