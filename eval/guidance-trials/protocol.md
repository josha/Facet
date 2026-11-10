# Run a guidance trial

A guidance trial compares what fresh authors build from two versions of the
consumer kit. It tests the guidance and the library together. It is cheaper
and narrower than [the run](../README.md): one screen, one author for each
arm, and a blind review of captures.

## Before the trial

1. Build each kit from its commit: `skills/`, `docs/` and `examples/themes`.
   Freeze it and record its hash in [kits.json](kits.json). Do not edit a
   frozen kit. A change makes a new kit.
2. Choose a task from the `unseen` list in [tasks.json](tasks.json), or write
   one in a family that the set has not used. State the player task and its
   limits. Do not name a control, unless the control is the subject of the
   test. Move the task to `used` when the first run starts.
3. Install the library of the candidate commit in the Studio place. Both arms
   use the same place and the same library.
4. Disable every other script in the place, set the device preview to the
   desktop and stop Play.

## The author

Use one fresh author for each arm, with the same model and effort, and with
no earlier context. Run the authors one after the other when they share one
Studio. Give each author this brief and nothing else. Replace the three
fields.

```text
You are building a UI in Roblox Studio with Facet, a Roblox UI library. This
is an unaided first-pass trial with a fresh agent and no earlier context:
make every design decision yourself and deliver without asking anyone for
feedback or approval.

The user's request: "{REQUEST}"

Studio: the place "{PLACE}" is connected. Facet is installed at
ReplicatedStorage.Packages.Facet.

Guidance: the consumer kit is at {KIT}. Start with
skills/use-facet/SKILL.md and follow it and the guidance it links. Reference
nodes are in docs/reference/nodes.

Where your code goes: one LocalScript named {RUN} in
StarterPlayer.StarterPlayerScripts. Child ModuleScripts are fine. Do not read,
enable or change the other scripts in the place. Do not change the Facet
package.

Files: keep a copy of your final source and of the art files that you make
in {RUN FOLDER}. You may upload original images that you make.

Off limits: other runs, other kits, earlier evaluations.

Finish: stop Play, restore the desktop preview and leave your LocalScript
enabled. Then report what you built, the visual direction, what you tested
and how, known gaps, each native use that remains and its reason, and any
guidance or API friction that cost you time.
```

State these conditions in the brief when they apply, and give both arms the
same conditions:

- Whether an image model is available, the command and the limit on images.
- Whether the author can start other agents. An author that cannot start a
  reviewer delivers a first pass only.

Record the minutes, the tokens and the number of generated images for each
author. Do not coach an author. Keep an operational fix, such as a restarted
tool, separate from design feedback, and record it.

## Captures

After the author stops, capture the result yourself. Do not use the author's
captures.

- Desktop: device `hd_1080`.
- Phone portrait and phone landscape: device `iphone_14`.
- The same states for each arm: the start state and one state after a
  commitment, when the task has one.

Set the device with `StudioDeviceSimulatorService` as the use-facet skill
shows. Run `Facet.review.screen().text` at each size and keep its text with
the captures.

## Blind review

Copy the captures to a new folder. Name each build with a letter, in a
shuffled order, and keep the key outside the folder. Give a fresh reviewer
only the user's request and the folder. Do not give it the kits, the
authors' reports, the arm names or another review.

```text
You are a strict art director for Roblox games. You have not seen this work
before. The request was: "{REQUEST}". The folder holds captures of {N} builds
of that screen, named by letter, each at desktop, phone portrait and phone
landscape. View every image at its full size.

Score each build from 1 to 5 on: identity (does it belong to this product),
craft (finish of the art and type at twice its size), lead (is the subject
the largest and clearest thing), and the fit at desktop, portrait and
landscape. Use one scale for all the builds. A 5 is work that you would ship
with no change.

Then rank the builds, say which one you would ship as it is, if any, and
list for each build every fault that stops a 5, most important first. Write
each fault so that a person can act on it without your other notes.
```

Use one reviewer and one scale for a comparison of craft. Scores from two
reviewers differ by about one point for the same build, so do not compare a
score from one review with a score from another.

## A repair round

A repair round measures what one independent review adds to a first pass.

1. Give a fresh reviewer the request and the captures of one build. Ask for
   the scores and the ordered fault list of the review brief.
2. Give a fresh author the kit, the earlier author's source and art, and the
   fault list. Tell it to repair the list in order, at the cause, on a copy
   of the script, and to keep what works.
3. Capture the copy and review the first pass and the repaired build
   together, blind.

Record the round as its own run, with the run that it repairs. Report a first
pass and a repaired build as different stages. Do not report a repaired build
as unaided work.

## After the trial

Add the runs to [runs.json](runs.json), the reviews to
[reviews.json](reviews.json) and 480-pixel previews to `previews/`. A preview
is for browsing. Score from the original capture.

When a result changes the guidance, mark its task as development material in
[tasks.json](tasks.json). Test the changed guidance on a task from the
`unseen` list.

The reviewer briefs of the first trials were not kept word for word. The
brief above states what those reviewers were asked.
