# Studio author workflow

Use this workflow within the supplied tool boundary. It does not change the
product requirements. Make persistent
changes in Edit and test them in Play. Keep supplied libraries and documents
unchanged.

Plan the brief as connected player routes. Identify each route's entry, shared
state, accepted game effect, cancellation or failure, and return. Track the
required routes that remain incomplete. The first working route is a checkpoint
toward the complete brief.

1. Read the required guidance and the task chapters for the first route. Resolve
   unfamiliar library options from their public contracts. Check unfamiliar
   native constructors, datatype operations and members with a small native
   probe in the intended data model before using them in shared code.
2. Build a small complete route before expanding features: enter from gameplay,
   use normal player input, observe the actual game effect and accepted result,
   and return. Include the server behavior that makes the result real. An open
   page, a changed label or a successful tool call does not prove this route.
3. Start Play after the first persistent implementation. Check Client and Server
   errors and the current camera's `ViewportSize`. If the camera stays absent or
   at 1 by 1, report unavailable native rendering separately from game failures.
   Request a capture when rendering is ready. Inspect the returned image at its actual size.
   A text response, object bounds or an image from an earlier state does not
   verify the current appearance. Test a short or narrow supported layout before
   copying a layout pattern. Keep a coherent visual language across the world
   and UI, with a composition suited to each task. Check the main subject, next
   action, readable terms and gameplay clearance. Revise weak composition before
   adding decorative detail.
4. Fix the persistent source, restart Play and repeat the affected route. Check
   normal completion, cancellation and return, including input and focus. Add
   features in small groups and verify their real effects after each group.
   Check choices and progression in the later tasks that consume them. Repeat
   representative routes with each required input and layout, including a live
   viewport change. Keep decisions, consequences and exits usable.
   Keep the place working after each group of changes.
5. If a tool times out, its action may still have occurred. Inspect state before
   repeating an action. If capture remains unavailable, do not claim visual
   review or spend the remaining attempt on identical retries. Continue useful
   functional checks and repairs with available tools. Report the missing visual
   evidence; do not assume access to tools outside the supplied boundary.
6. Stop only when every requirement in the brief works or no useful work can
   proceed with the available tools. Before finishing, check the persistent
   result in a fresh Play session. State which routes you actually operated,
   what failed, and what remains untested or incomplete. Keep implementation,
   functional testing and visual review distinct. A normal author exit is not
   proof that the game meets the brief.
