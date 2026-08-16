# Declarative reactive world objects on Roblox — platform research

Bounded research for the "declarative fine-grained-reactive system for Parts and Models" architecture decision.
Sourced from create.roblox.com first, devforum second, framework docs third. Researched 2026-08-13.
Every claim is tagged **[OFFICIAL]** (create.roblox.com or a framework's own docs), **[FORUM]** (devforum / GitHub),
or **[INFERRED]** (reasoning from cited facts). Anything unverified is marked **UNCONFIRMED**.

## 1. Transform model

- **Confirmed: BaseParts carry only world-space CFrames.** `PVInstance:PivotTo()` is documented as
  "Transforms the PVInstance along with all of its descendant PVInstances such that the pivot is now located at the
  specified CFrame", and crucially: "BaseParts are moved in this way by having their **CFrame transformed by the
  necessary offset**. Models are moved in this way by having their `Model.WorldPivot` transformed by the necessary
  offset." There is no parent-relative transform stored on a BasePart. [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/PVInstance
- **PivotTo does move all descendant parts**, and it is *not* free — it writes every descendant BasePart's CFrame.
  It does have a real optimization: "When calling PivotTo on Models, the offsets of the descendant parts and models
  are **cached**, such that subsequent calls to PivotTo on the same model do not accumulate floating point drift."
  Also: "`Object.Changed` events are not fired for Position and Orientation of BaseParts moved in this way; they are
  only fired for CFrame." [OFFICIAL] same URL
- `Model.PrimaryPart` is "the physical reference that specifies which BasePart the pivot point and bounding box
  should move with"; without one, transforms happen from the centre of the model's bounding box. `Model.WorldPivot`
  is the model's own world-space pivot (a Model has no CFrame property). [OFFICIAL]
  https://create.roblox.com/docs/parts/models
- **Attachments are the one genuine parent-relative transform primitive.** `Attachment.CFrame` is "The CFrame offset
  of the attachment"; `Attachment.WorldCFrame` is "the exact CFrame of the attachment in world space… equivalent to
  multiplying the CFrame of the attachment's parent by its own CFrame"; `Position` is "expressed in the local
  coordinate space". Attachments define transforms "relative to an ancestor PVInstance, Bone, or another
  Attachment" — i.e. attachments can nest, giving a real (if narrow) local hierarchy. [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/Attachment
- **Joints group parts into assemblies, they do not create a scene graph.** "An assembly is one or more parts welded
  by a rigid WeldConstraint or connected through movable joints, like Motor6Ds." "Every assembly has a root part
  indicated by its `AssemblyRootPart` property." When one part is anchored it becomes the root; "if more than one
  part is anchored, the assembly will split" and welds between anchored assemblies deactivate. [OFFICIAL]
  https://create.roblox.com/docs/physics/assemblies
  → For **anchored decorative** hierarchies (our likely case), welds are inert and offer no transform propagation. [INFERRED]
- `RigidConstraint` "creates a rigid connection between two Attachments or Bones" and "ensures they stay in the same
  relative position/orientation"; it exists mainly for accessory/rig attachment beyond WeldConstraint. Whether it
  works usefully on anchored parts is **UNCONFIRMED** from docs. [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/RigidConstraint
- **`WorldRoot:BulkMoveTo` current guidance is an explicit anti-recommendation.** "This function moves a table of
  BaseParts to a table of CFrames without necessarily firing the default property Changed events." Modes:
  `FireAllEvents` (default; Position, Orientation and CFrame Changed fire) and `FireCFrameChanged` (only CFrame).
  The doc then says: "**You should only use this function if you're sure that part movement is a bottleneck in your
  code. Simply setting the CFrame property of individual parts and welded models is fast enough in the majority of
  cases.**" [OFFICIAL] https://create.roblox.com/docs/reference/engine/classes/WorldRoot
  A community benchmark puts the crossover around ~30 parts (~9% win at 50 parts); no staff reply. [FORUM]
  https://devforum.roblox.com/t/bulkmoveto-vs-normal-cframe-ing/1278502
- **No new first-party scene-graph / local-transform feature shipped 2025–2026.** Searched create.roblox.com,
  devforum announcements, 2026 weekly recaps and the Creator Roadmap 2026 Spring Update; nothing adds parent-relative
  part transforms. The 2026 world-building shipments are elsewhere: Procedural Models (see §6f), Solid Modeling on
  Meshes, mesh/texture streaming, SLIM LOD. [OFFICIAL]
  https://devforum.roblox.com/t/creator-roadmap-2026-spring-update/4625473 ,
  https://create.roblox.com/updates
- `EditableMesh` is geometry, not hierarchy: it operates "in the mesh's local object space", is gated behind
  age/ID verification ("using EditableMesh fails by default for published games"), and caps at 60,000 vertices /
  20,000 triangles with strict client memory budgets. Not a scene-graph feature. [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/EditableMesh

## 2. Streaming

- **Stream-out parents to nil; it is not a Destroy.** "When an instance streams out, it is parented to `nil` so that
  any existing Luau state will reconnect if the instance streams back in. As a result, removal signals such as
  `ChildRemoved` or `DescendantRemoving` fire on its **parent** or **ancestor**, but the instance itself is not
  destroyed in the same sense as an `Instance:Destroy()` call." [OFFICIAL]
  https://create.roblox.com/docs/workspace/streaming
  → `AncestryChanged` fires (parent → nil); `Destroying` does **not** fire on stream-out. [FORUM]
  https://devforum.roblox.com/t/what-happens-to-objects-that-are-streamed-out-streamingenabled/2527597
- **Client-set properties are NOT preserved across a stream cycle.** "Local-only changes to instance properties
  (changes that exist on a client and have not been replicated to the server) can be lost if the instances streams
  out and later streams back in." [OFFICIAL] streaming
- **ModelStreamingMode** (`Enum.ModelStreamingMode`) [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/enums/ModelStreamingMode :
  - `Default` (0) — "Default behavior (subject to change)."
  - `Atomic` (1) — model + all initial descendants stream as a unit; streams in when any descendant BasePart is
    eligible, streams out only when all are. `WaitForChild` on the model, not on its descendants.
  - `Persistent` (2) — "sent as a complete atomic unit soon after the player joins and before the
    `Workspace.PersistentLoaded` event fires"; never streams out. Docs say use it "only if it must remain available
    and accessible to scripts at all times."
  - `PersistentPerPlayer` (3) — Persistent for players added via `Model:AddPersistentPlayer()`, Atomic for everyone
    else; revert with `RemovePersistentPlayer()`.
  - `Nonatomic` (4) — default in practice; "descendants are also sent, except for part descendants"; behaviour also
    depends on `Workspace.ModelStreamingBehavior` (`Legacy` vs `Improved`).
- **Officially recommended client pattern is CollectionService, not held references.** "Assign a logical
  CollectionService tag to all of the affected objects using `AddTag()` or the Tags section" and detect stream in/out
  through "`GetInstanceAddedSignal()` and `GetInstanceRemovedSignal()`". [OFFICIAL]
  https://create.roblox.com/docs/workspace/streaming/techniques
  - Same page's pitfall list: "ChildAdded/ChildRemoved and CollectionService signals also fire on stream in/out,
    **indistinguishable from real spawns**"; use an attribute like `Spawned` to tell first spawn from re-stream.
  - "If the script cannot make progress without an instance, wait for it with `WaitForChild()`… this can yield
    indefinitely if the instance never streams in, so consider adding a timeout as the second parameter."
  - "Sending a part/model reference from server to client through a RemoteEvent or RemoteFunction requires that the
    instance is replicated to the receiving client." → the same constraint applies to ObjectValue-carried references;
    a specific ObjectValue-under-streaming caveat is **UNCONFIRMED** in current docs.
  - Client-side `Raycast()`, `GetPartBoundsInBox()` and `Model:GetBoundingBox()` "reflect only streamed-in content";
    `Touched`, ProximityPrompts, DragDetectors and ClickDetectors "do not operate" for un-streamed parts.
  - Once streamed out, "Instance property updates are no longer replicated to that client."
- `Player:RequestStreamAroundAsync(position, timeOut?)` yields and pre-fetches around a point, but "**there are no
  guarantees of what will be streamed in around the specified location**"; the effect is temporary and low client
  memory abandons all requests. [OFFICIAL] https://create.roblox.com/docs/reference/engine/classes/Player
- `Model.LevelOfDetail` (`Enum.ModelLevelOfDetail`): `Automatic` (0) = "currently equivalent to Disabled";
  `StreamingMesh` (1) = coarse untextured imposter outside the streaming radius; `Disabled` (2) = nothing renders;
  `SLIM` (4) = progressively lower-resolution composite, better quality than StreamingMesh. Imposter/composite
  renders have no physics, collision or raycast. [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/enums/ModelLevelOfDetail

## 3. Replication + authority

- **What replicates:** "Replication is the process of the server synchronizing the state of your place with all
  connected clients." Workspace and ReplicatedStorage replicate; ServerStorage/ServerScriptService never do;
  ReplicatedFirst replicates "to all clients (but not back to the server) first". [OFFICIAL]
  https://create.roblox.com/docs/projects/data-model
- **Client changes stay local and the server can stomp them.** "Any changes that occur on the client persist but
  won't be replicated to the server. **The server can overwrite changes on the client to maintain consistency.**"
  [OFFICIAL] data-model. The ReplicatedStorage reference repeats it: "Any changes that are made on the client persist
  but aren't replicated to the server. **Client changes may be overwritten if the server does something that
  overwrites those changes.**" [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/ReplicatedStorage
  → This is the *entire* documented promise. There is no doc guaranteeing that a later server write re-establishes a
  client-overridden property; only that it *may*. In practice a server write to property P re-replicates P and wins;
  properties the server never touches again keep the client's value. [INFERRED]
- **Ordering: no guarantee across kinds.** "The Roblox Engine doesn't guarantee the order in which objects (and
  changes to objects) are replicated from the server to the client" — which is why `WaitForChild` is required.
  RemoteEvents "might not be consistently ordered with property and attribute updates over the network", while
  changes of the same type (e.g. two attribute changes) generally do arrive in order. [OFFICIAL]
  https://create.roblox.com/docs/scripting/attributes
  → **No documented replication rate or hz** for property/CFrame updates. UNCONFIRMED.
- **Network ownership:** "the server **always** owns anchored BaseParts and you cannot manually change their
  ownership." Unanchored parts near a character may be auto-assigned to that client; `SetNetworkOwner()` should be
  used "conservatively since it may result in jittery physics interactions". [OFFICIAL]
  https://create.roblox.com/docs/physics/network-ownership
  → For anchored decorative world objects, the server is unconditionally authoritative. [INFERRED]
- **Client-local structural edits to server instances are unsupported.** A client reparenting a server-replicated
  part out of Workspace was classified "expected behavior" by Roblox staff (Khanovich, Aug 2025): client-local
  structural changes cause desync, and physics updates require the object to stay in Workspace. Direct server
  property writes still replicated in that repro; physics-driven CFrame/Velocity did not. [FORUM]
  https://devforum.roblox.com/t/physics-does-not-replicate-to-parts-locally-moved-to-replicatedstorage/3867656
- **Server Authority / next-gen replication.** `Workspace.AuthorityMode = Server` requires all of:
  `NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`, `SignalBehavior = Deferred`, `UseFixedSimulation`
  and **`StreamingEnabled`**. It makes the server "the single source of truth for the entire game state."
  [OFFICIAL] https://create.roblox.com/docs/projects/server-authority
  - Properties carrying the **Simulation Access** label (`BasePart.CFrame` among them) "will be predicted by the
    server authority system. Additionally, **only properties and methods with this label can be accessed inside
    functions bound with `RunService:BindToSimulation()`**." [OFFICIAL] same URL
  - **Attribute limits** (under "Attribute limits", following "Only write to attributes on predicted instances from
    within functions bound through `BindToSimulation()`"): "In order to be replicated, an attribute must meet all of
    the following criteria: It is among the first 64 attributes on its Instance. Its name contains at most 50
    characters. If a string type attribute, its value contains at most 50 characters." [OFFICIAL] same URL
    Developers have filed feature requests arguing these limits punish attribute-as-state architectures; no staff
    resolution. [FORUM]
    https://devforum.roblox.com/t/nextgenerationreplications-attribute-limits-punish-games-using-attributes-for-non-simulation-state/4647479
  - **Instance stitching by deterministic GUID** — the sharpest constraint on a reconciler: "Instance stitching works
    by generating the same deterministic GUID on both the client and the server. The GUID is derived from four inputs:
    the type of the Instance being created, the source's identity, **the current simulation frame, and a per-script
    call counter that resets each frame**." `Instance.new()`'s source is "the script itself"; `Instance:Clone()` —
    "Each cloned instance uses the source instance's GUID as the context seed." Applies to instances created inside a
    `BindToSimulation()` callback. [OFFICIAL]
    https://create.roblox.com/docs/projects/server-authority/techniques
    → A reconciler that reorders, batches, or conditionally skips instantiations inside simulation code breaks
    stitching; cloning a replicated template is the identity-stable path. [INFERRED]
  - **What Server Authority changes for NON-predicted anchored decorative instances is UNCONFIRMED** — the docs do
    not describe a separate path for them beyond the shared `NextGenerationReplication` stream. Note the practical
    corollary that server authority *forces StreamingEnabled on*, so a world framework targeting a server-authority
    place cannot assume non-streaming. [OFFICIAL/INFERRED] server-authority

## 4. Reactive property write costs + native mechanisms

- **No official numeric cost for an Instance property read/write exists.** UNCONFIRMED. The only official guidance is
  behavioural: "Don't call the same method every time you need a value. Call the method once, store the value, and
  then overwrite it later as necessary." [OFFICIAL]
  https://create.roblox.com/docs/performance-optimization/design
  Studio's Script Profiler does treat property accesses as first-class attributable cost units ("can record all types
  of function calls, including Luau functions, method calls, and property accesses"). [OFFICIAL]
  https://create.roblox.com/docs/studio/optimization/scriptprofiler
  A community measurement of the Luau↔engine bridge called the gap "very miniscule, basically deep within
  micro-optimization territory" (~300–900 µs over 100,000 accesses), largely erased by `--!optimize 2`; self-labelled
  outdated, not staff. [FORUM] https://devforum.roblox.com/t/narrowing-the-luabridge-overhead/3516622
- **Geometry-affecting writes are a much worse cost class than transform writes:** "Size/scale changes cause
  FastCluster to be rebuilt… other property changes might also cause FastCluster to be rebuilt, so in general reduce
  these changes as much as possible." [OFFICIAL] https://create.roblox.com/docs/performance-optimization/improve
- **`--!native` will not rescue a property-write-bound layer.** It targets scripts "that have a lot of numerical
  computation without using too many heavy Luau library or Roblox API calls"; Roblox APIs "remain supported"
  (supported ≠ accelerated); only script functions compile; there is a game-wide cap after which "native compilation
  stops and the remaining code is run non-natively", plus server startup compile time and extra memory. [OFFICIAL]
  https://create.roblox.com/docs/luau/native-code-gen → net-negative for us. [INFERRED]
- **Server-side per-frame writes are called out by name.** "If TweenService is used to tween an object server side,
  the tweened property is replicated to each client **every frame**." "**Tween objects on the client rather than the
  server.**" "Server-side TweenService" is listed as a common networking problem causing jitter. Also listed as a
  named mistake: "Replicating data every frame that does not need to be replicated," and "Limit unnecessary instance
  replication, especially in cases where the server doesn't need to have knowledge of the instances being created…
  the clients can create visuals locally." [OFFICIAL] improve
- "Whenever possible, write **event-driven** code rather than per-frame calculations. At 60 FPS, the total budget for
  each frame is 16.67 milliseconds." "Invoke code on RunService events sparingly." [OFFICIAL] design, improve
- **Replication rate / interpolation for anchored-part CFrame is UNCONFIRMED.** No documented hz, throttle threshold
  or client-side interpolation guarantee. `Enum.InterpolationThrottlingMode` exists but its doc page has no
  descriptive text. https://create.roblox.com/docs/reference/engine/enums/InterpolationThrottlingMode
- **Constraints vs CFrame: there is no official head-to-head recommendation.** UNCONFIRMED. What docs do say:
  `AlignPosition` is a "Constraint which applies force to move two attachments together, or to move one attachment to
  a goal position" [OFFICIAL] https://create.roblox.com/docs/reference/engine/classes/AlignPosition ; and constraints
  are not free — "Where possible, minimize the number of physics constraints or joints in an assembly." [OFFICIAL]
  improve. Anchored parts are unaffected by forces and cannot hold network ownership, so mover constraints are
  irrelevant to anchored decor and CFrame/`PivotTo` is the only lever there. [INFERRED]
- **Prefer engine-side animated properties for effects.** ParticleEmitter animates Size/Color/Transparency engine-side
  across particle lifetime via NumberSequence/ColorSequence; the documented costs are GPU-side (fill-rate, overdraw,
  "keep the particle rate as low as possible"). [OFFICIAL] https://create.roblox.com/docs/effects/particle-emitters
  Scripted mutation is expensive: "property changes to ParticleEmitters can have a dramatic impact on performance."
  [OFFICIAL] improve. `Beam.TextureSpeed` scrolls the texture engine-side with no script. [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/Beam . Light-property animation guidance: UNCONFIRMED.

## 5. Templates + identity

- **`Instance.new()` vs `:Clone()` — no official perf statement exists.** UNCONFIRMED. Official Clone semantics only:
  copies the instance "and all of its descendants, ignoring all instances that are not Archivable", returned with
  `Parent` nil. [OFFICIAL] https://create.roblox.com/docs/reference/engine/classes/Instance
  Adjacent official guidance favours templates for a *replication* reason: keep clonable objects in ServerStorage and
  "Chunk up complex instance trees like maps", because runtime creation/removal of complex trees is network-intensive.
  [OFFICIAL] improve, data-model. Community consensus: `Instance.new` wins for trivial objects, `Clone` wins once many
  properties/descendants are involved. [FORUM]
  https://devforum.roblox.com/t/clone-is-actually-slower-than-creating-a-new-instance-directly-how-come/746934
- **PackageLink is edit-time.** Packages "allow you to reuse single assets or asset hierarchies across games";
  "Do not delete or move the PackageLink object!"; auto-update "will take place when a place is opened in Studio."
  No documented runtime role. [OFFICIAL] https://create.roblox.com/docs/projects/assets/packages → not a runtime
  template or identity mechanism. [INFERRED]
- **CollectionService tags replicate and are streaming-aware.** Tags "replicate from the server to the client" and are
  "serialized when places are saved". `GetInstanceAddedSignal(tag)` fires both on tag assignment and when an
  already-tagged instance becomes a descendant of the DataModel; `GetTagged` returns tagged DataModel descendants.
  **Trap:** "An instance's tags that were added client-side will be dropped if the server later adds or removes a tag
  on that instance because the server replicates all tags together and overwrites previous tags." [OFFICIAL]
  https://create.roblox.com/docs/reference/engine/classes/CollectionService
- **Attributes** support string, boolean, number, UDim, UDim2, BrickColor, Color3, Vector2, Vector3, CFrame,
  NumberSequence, ColorSequence, NumberRange, Rect, Font; they replicate ("replicated so that clients can access them
  immediately") and persist with the place. [OFFICIAL] https://create.roblox.com/docs/studio/properties
  Names must be alphanumeric plus `. - / _`, "Strings must be 100 characters or less", and may not start with `RBX`.
  [OFFICIAL] https://create.roblox.com/docs/reference/engine/classes/Instance
  Reactivity hooks: `Instance.AttributeChanged` and `Instance:GetAttributeChangedSignal()`. [OFFICIAL]
  https://create.roblox.com/docs/scripting/attributes
  **There is no documented cap on attribute count or value size in the general (non-server-authority) case**
  — UNCONFIRMED; but see §3, where server authority imposes 64 attributes / 50-char name / 50-char string value.
- **Instancing rewards template-clone architectures.** "A draw call is a set of instructions from the engine to the
  GPU… Draw calls have significant overhead." The engine "utilizes a process called *instancing* to collapse
  identical meshes with the same texture characteristics into a single draw call", and: "If you ensure all identical
  meshes to have the same underlying asset IDs, the engine can recognize and render them in a single draw call. Make
  sure to only upload each mesh in a map once and then duplicate them in Studio for reuse." Decals, textures and
  particles "don't batch well and introduce additional draw calls." [OFFICIAL] improve, design
  → One MeshId per visual kind + clone is directly rewarded by the renderer; per-object mesh variation is punished.
  [INFERRED]

## 6. Landscape

### a. Fusion (elttob / dphfox)

- **Instance-generic: yes.** `New` takes any class name; the official tutorial's own examples include `Part` alongside `TextLabel`, with no GUI restriction. [OFFICIAL] https://elttob.uk/Fusion/0.3/tutorials/roblox/new-instances/
- **Version 0.3, released 2024-08-29**; last `main` commit 2026-02-02; 790 stars — ~2 years without a release, low-volume maintenance only. 0.4 docs are published but banner-marked "for a future version of Fusion." [OFFICIAL] https://github.com/dphfox/Fusion/releases , https://elttob.uk/Fusion/0.4/
- Parenting via `[Children]`: "accepts instances, arrays of children, and state objects containing children or `nil`", nesting to any depth. Cleanup via `scoped()`/`innerScope()`/`doCleanup()`; scopes are arrays destroyed in reverse creation order; use-after-cleanup is a hard error. [OFFICIAL] https://elttob.uk/Fusion/0.3/tutorials/roblox/parenting/ , https://elttob.uk/Fusion/0.3/tutorials/fundamentals/scopes/
- **The guarantee we most need was removed.** Fusion 0.2's `[Cleanup]` promised "Fusion's `[Cleanup]` will work regardless of how your instances were destroyed"; `[Cleanup]` is absent from the 0.3 API-reference member list (Attribute, AttributeChange, AttributeOut, Child, Children, Hydrate, New, OnChange, OnEvent, Out). [OFFICIAL] https://elttob.uk/Fusion/0.2/tutorials/instances/cleanup/ , https://elttob.uk/Fusion/0.3/api-reference/ (removal inferred from the member list — see UNCONFIRMED)
- `Hydrate` is one-directional and flagged for replacement ("`Hydrate` itself will be replaced by other primitives in the near future"); there is no mechanism to observe external property changes. [OFFICIAL] https://elttob.uk/Fusion/0.3/tutorials/roblox/hydration/
- **What it does NOT handle:** no mention anywhere in Fusion's docs of StreamingEnabled, replication, server/client topology, or what happens when external code destroys or reparents a Fusion-owned instance. [OFFICIAL by absence] The author has written about exactly this class of problem — Roblox's sandbox disables `__gc`, so "quite literally the only way you can detect an object has been cleaned up is by polling a weak table." [FORUM/author] https://fluff.blog/2022/11/12/destruction-problems-in-fusion.html
- Real lifetime failure in the wild: `useAfterDestroy` when a reactive value is destroyed before its bound instance; parent scopes must strictly outlive children. [FORUM] https://devforum.roblox.com/t/fusion-sometimes-throwing-useafterdestroy-error-on-a-reactive-recursive-node-tree/4284287

### b. Vide (centau)

- **Instance-generic by signature:** `create(class: string)` and `create(instance: Instance)` accept any class. [OFFICIAL] https://centau.github.io/vide/api/creation.html — but it is branded and documented as UI-only ("A reactive UI library for Luau"), with no 3D/Parts/world/streaming content anywhere on the docs site. [OFFICIAL] https://centau.github.io/vide/
- Scopes: *stable* (`root()`) vs *reactive* (`effect()`); "A reactive scope cannot be created within another reactive scope, only within a stable scope"; destroying a parent cascades. **Lifetime is GC-based, not Destroy-based** — destroying an effect scope "will remove this reference, allowing the instance to be garbage collected", i.e. Vide drops references rather than owning Instance destruction. [OFFICIAL] https://centau.github.io/vide/tut/crash-course/6-scope.html
- Most actively released of the three: v0.4.1 on 2026-07-11 (pre-release), v0.4.0 on 2026-01-17. Streaming / external destruction: no documentation at all. [OFFICIAL / by absence] https://github.com/centau/vide/releases

### c. react-lua / Roact

- Roact 1.x is deprecated: "Roact is no longer maintained and should not be used for new work"; superseded by
  react-lua (Roact 17). [OFFICIAL] https://roblox.github.io/roact-alignment/
- react-lua is actively maintained by Roblox (commits through 2026-07-30). [OFFICIAL]
  https://github.com/Roblox/react-lua/commits/main
- **No supported 3D host.** ReactRoblox is "a Roblox-opinionated renderer, intended to stand in for native renderers
  like react-dom"; every documented example renders into `ScreenGui`/`PlayerGui`. The reconciler commits to "the
  Roblox Instance hierarchy" generically, so Parts would probably work as host components, but no Part/3D host is
  documented or shipped. [OFFICIAL/INFERRED] https://github.com/Roblox/react-luau
  Whether `createRoot` accepts `Workspace`/`Model` as a container is **UNCONFIRMED** (docs host unreachable).

### d. Dedicated declarative WORLD/scene frameworks

**The niche is empty.** Across ~8 distinct query formulations ("declarative workspace", "declarative parts",
"scene graph roblox luau", "reactive world roblox", "roblox retained mode world", "react-three-fiber for Roblox"),
every declarative Roblox framework found is UI-scoped: Rex (12 likes, v0.2.2-beta) [FORUM]
https://devforum.roblox.com/t/rex-modern-reactive-ui-framework-for-roblox/3778193 ; Fluid (38 stars, GUI)
https://github.com/ffrostfall/fluid ; Pract, Flux, Fragment, Vinum, OnyxUI, Toned — all UI. Charm (littensy) is
atomic state + server→client atom sync with no Instance rendering. https://github.com/littensy/charm
No dedicated world/scene declarative framework surfaced. [INFERRED — negative result]

### e. The ECS school

- **jecs (Ukendio)**: 456 stars, v0.11.0 (March), steady cadence. [OFFICIAL] https://github.com/Ukendio/jecs
- Its flagship devforum thread — "Jecs - Optimizing declarative scene graphs with ECS", posted 2024-11-17, **124 likes**, replies running to 2026-06-21 — is the most active world-architecture thread found. But "scene graph" there means **ECS-internal hierarchy** via `pair(ChildOf, parent)`: the OP never mentions Roblox Instances, Parts, Models, rendering, or streaming. [FORUM] https://devforum.roblox.com/t/jecs-optimizing-declarative-scene-graphs-with-ecs/3263203
- **Matter is effectively dead**: `evaera/matter` unmaintained; the `matter-ecs/matter` fork's latest release is still v0.8.5 from 2023-12-09. [OFFICIAL] https://github.com/matter-ecs/matter/releases
- **Neither ECS library solves entity→Instance sync.** Matter: "Replication is not built into Matter, but it's easy to implement yourself" — it lists a `Model` component but never explains how the client creates or destroys Instances from components. [OFFICIAL] https://matter-ecs.github.io/matter/docs/Guides/Replication/ . jecs docs have no Instance-component/rendering-system chapter and no streaming guidance. [OFFICIAL by absence] Replication is a separate third-party layer (Replecs, v0.2.3-test1). https://github.com/PepeElToro41/replecs
- **There is no "ECS vs fine-grained reactivity" debate in the Roblox community — the two communities do not intersect.** The jecs thread never mentions Fusion/Vide/React; the UI frameworks never mention ECS. The conventional framing is ECS vs OOP. [FORUM/INFERRED] https://devforum.roblox.com/t/ecs-in-roblox-studio-why-is-it-better-than-oop-and-how-to-cook-it/3962745
- jecs production-adoption claims (Fisch, Horse Valley, Dead Rails, Volleyball Legends) are one forum user's unsourced claim, challenged in-thread and never substantiated — treat as anecdote. [FORUM, unverified]

### f. Roblox first-party

- **`Roblox/signals` is the decisive first-party datapoint.** An official Roblox library: "Scalable and minimal reactive programming framework for Luau", providing "fine-grained reactivity through a minimal set of primitives that automatically track dependencies and efficiently propagate updates" via `createSignal`/`createComputed`/`createEffect`. 44 stars, activity through mid-2026. **It is state-only: no rendering, no Instance creation, no world objects.** [OFFICIAL] https://github.com/Roblox/signals → Roblox shipped the reactive *core* and left the renderer to developers. [INFERRED] (`Roblox/otter` is a companion official "declarative animation library for Luau". https://github.com/Roblox/otter)
- **No first-party declarative system for world instances exists or is roadmapped.** The Creator Roadmap 2026 Spring Update (2026-05-08, 52 shipped + 21 new) contains nothing on declarative scene authoring, reactive instances, scene-graph APIs, or runtime DataModel APIs; the UI-adjacent items are StyleQueries and UI shadows/glows. RDC 2025's headline announcements (AI/4D generation, MCP in Studio Assistant, server authority closed beta, matchmaking, avatars, DevEx) likewise contained nothing declarative-world. [OFFICIAL] https://devforum.roblox.com/t/creator-roadmap-2026-spring-update/4625473 , https://devforum.roblox.com/t/rdc25-what-we-announced/3920245
- **The closest first-party thing is ProceduralModel — and it *is* runtime.** "ProceduralModels are a type of parameter-driven Model that let you build and generate 3D objects using code… When those attributes change, or when the model is resized, the generator automatically runs to update the model," and explicitly: "**Generate content both at edit time and at runtime, using the same system in Studio and in-game.**" API: `Generator` (a ModuleScript exposing `OnGenerate(params, targetContainer)` plus an `Attributes` default map), `GenerationError`, `Size` as an *input*, `ForceGeneration()`, `WaitForGenerationAsync()`, and a `Generated` folder overwritten each run. "Generation is not supported within `Actor` instances." Fully released 2026-05-18. [OFFICIAL] https://create.roblox.com/docs/parts/procedural-models , https://create.roblox.com/docs/reference/engine/classes/ProceduralModel , https://devforum.roblox.com/t/full-release-procedural-models-build-parametrized-3d-models-with-code-or-ai/4642542
  → This is attribute→geometry regeneration: coarse-grained and whole-subtree, not fine-grained reactive diffing, and it does not address streaming, replication, or client-side ownership. Whether generated content replicates is **UNCONFIRMED**. [INFERRED]
- **Open Cloud Engine Instance API is edit-time and script-only** — Beta; "You can only read and update Script, LocalScript, and ModuleScript objects"; requires a collaborative session; cannot update scripts open in Studio or in a package; 200 KB bodies. Confirmed 2026-08-13. [OFFICIAL] https://create.roblox.com/docs/cloud/guides/instance

## 7. Streaming × client decoration

This is the sharpest platform hazard for a client-side declarative world layer.

- **Official rule:** "Instances which are **created** or **cloned** by client-side scripts are exempted from streaming
  out **unless they are parented under a server-created instance**." [OFFICIAL]
  https://create.roblox.com/docs/workspace/streaming
  → A client-created decoration parented to a server-streamed part is therefore *inside* the streaming system; a
  client-created decoration parented to a client-created root (e.g. a folder the client made in Workspace) is not.
  [INFERRED]
- **Adornment-style effects degrade silently rather than erroring:** "In-game UI objects like BillboardGui or
  SurfaceGui as well as visual effects like Beams or Highlights whose adornee or attachment streams out simply stop
  rendering." [OFFICIAL] https://create.roblox.com/docs/workspace/streaming/techniques
- **The community record on what happens to client-created children is contradictory, and Roblox has declined to
  define it.**
  - Older accepted answer: "When object streams out, it **does not** keep what is locally created" — recreate
    client-side effects on stream-in. [FORUM]
    https://devforum.roblox.com/t/streamingenabled-destroying-client-created-objects/1927180
  - Newer bug report (28 Aug 2025): client-created instances parented to a replicated part **persist** under it across
    a stream-out/stream-in cycle, i.e. they are *not* cleaned up. Roblox staff replied that they "do not consider this
    a bug, and have no plans to alter this behavior at present." [FORUM]
    https://devforum.roblox.com/t/parts-created-on-client-do-not-get-cleaned-up-correctly-when-streaming-enabled-is-on/3905567
  → Treat the lifetime of client-created children of streamed instances as **undefined and version-dependent**.
    A correct framework must be idempotent on re-attach (reconcile, never blindly re-create) and must not leak if the
    children survive. [INFERRED]
- **Recommended reattachment pattern (composed from official guidance):** tag the server-side anchor instances; drive
  attach/detach from `CollectionService:GetInstanceAddedSignal` / `GetInstanceRemovedSignal`; treat every add as
  possibly a re-stream rather than a first spawn (use an attribute flag, per the official `Spawned` example); never
  hold a bare reference across a stream boundary; `WaitForChild` only with a timeout. [OFFICIAL]
  https://create.roblox.com/docs/workspace/streaming/techniques
- **Do not solve this by pinning:** `Persistent` models never stream out, but the docs say to use it "only if it must
  remain available and accessible to scripts at all times" and reserve it for "rare circumstances". [OFFICIAL]
  https://create.roblox.com/docs/workspace/streaming

## Sources

Every URL is cited inline at the point of use above. Index:

**create.roblox.com** — `/docs/parts/models` · `/docs/parts/procedural-models` · `/docs/reference/engine/classes/{PVInstance, WorldRoot, Attachment, RigidConstraint, EditableMesh, Player, ReplicatedStorage, AlignPosition, Beam, Instance, CollectionService, ProceduralModel}` · `/docs/reference/engine/enums/{ModelStreamingMode, ModelLevelOfDetail, InterpolationThrottlingMode}` · `/docs/physics/{assemblies, network-ownership}` · `/docs/workspace/streaming` · `/docs/workspace/streaming/techniques` · `/docs/projects/{data-model, client-server, server-authority, server-authority/techniques, assets/packages}` · `/docs/scripting/attributes` · `/docs/performance-optimization/{design, improve}` · `/docs/luau/native-code-gen` · `/docs/studio/{properties, optimization/scriptprofiler}` · `/docs/effects/particle-emitters` · `/docs/cloud/guides/instance` · `/updates`

**Framework & first-party repos** — github.com/Roblox/{signals, otter, react-luau} · roblox.github.io/roact-alignment · elttob.uk/Fusion/{0.2,0.3,0.4} · github.com/dphfox/Fusion/releases · centau.github.io/vide · github.com/centau/vide/releases · github.com/Ukendio/jecs · github.com/matter-ecs/matter/releases · matter-ecs.github.io/matter/docs/Guides/Replication · github.com/{littensy/charm, ffrostfall/fluid, PepeElToro41/replecs} · fluff.blog/2022/11/12/destruction-problems-in-fusion.html

**devforum.roblox.com/t/** — creator-roadmap-2026-spring-update/4625473 · full-release-procedural-models…/4642542 · rdc25-what-we-announced/3920245 · what-happens-to-objects-that-are-streamed-out-streamingenabled/2527597 · streamingenabled-destroying-client-created-objects/1927180 · parts-created-on-client-do-not-get-cleaned-up-correctly-when-streaming-enabled-is-on/3905567 · physics-does-not-replicate-to-parts-locally-moved-to-replicatedstorage/3867656 · nextgenerationreplications-attribute-limits…/4647479 · bulkmoveto-vs-normal-cframe-ing/1278502 · narrowing-the-luabridge-overhead/3516622 · clone-is-actually-slower-than-creating-a-new-instance-directly-how-come/746934 · jecs-optimizing-declarative-scene-graphs-with-ecs/3263203 · rex-modern-reactive-ui-framework-for-roblox/3778193 · fusion-sometimes-throwing-useafterdestroy-error…/4284287 · ecs-in-roblox-studio-why-is-it-better-than-oop-and-how-to-cook-it/3962745

## UNCONFIRMED items

1. Any official numeric cost (ns/µs) for a single Instance property read or write.
2. Whether `--!native` specifically accelerates Instance property access (only the "numerical computation, not heavy
   Roblox API calls" scoping is official).
3. Official replication rate / hz / throttle threshold for server→client CFrame updates on anchored parts, and whether
   clients interpolate them; `Enum.InterpolationThrottlingMode` has no documented semantics.
4. Any official head-to-head "use constraints instead of writing CFrame" recommendation.
5. Official `Instance.new()` vs `:Clone()` performance comparison.
6. Any documented cap on attribute count or attribute value size **outside** the server-authority path.
7. What Server Authority / NextGenerationReplication changes for non-predicted anchored decorative instances.
8. A current-docs ObjectValue-specific streaming caveat (only the general "reference must be replicated to the
   receiving client" rule is official).
9. Whether ProceduralModel-generated content replicates server→client, and whether generation runs client-side in a
   live experience.
10. Whether RigidConstraint is useful on anchored parts.
11. Whether ReactRoblox `createRoot` accepts non-GUI containers (`Workspace`, `Model`) — docs host unreachable.
12. Whether Fusion or Vide mention StreamingEnabled anywhere (no mention found across ~10 targeted queries and direct
    page reads, but no site-wide text search was possible).
13. Whether Fusion 0.3 formally documents the removal of `[Cleanup]` (inferred from the API-reference member list).
14. jecs production-game adoption claims — one unsourced forum comment, challenged in-thread.

## Facts most likely to change the architecture decision

- Roblox parts have no parent-relative transform at all — every hierarchical placement must be recomputed by us and
  written out as world CFrames, and nothing shipped in 2025–2026 changes that. (§1)
- Streaming parents instances to nil rather than destroying them, and the docs say client-set properties "can be lost"
  across a stream-out/stream-in cycle, so any client-side reactive layer must re-apply its own state on stream-in. (§2)
- Roblox's own recommended handle for streamable world objects is CollectionService tags plus
  `GetInstanceAddedSignal`/`GetInstanceRemovedSignal`, and the docs warn those fire on streaming
  "indistinguishable from real spawns". (§2)
- The lifetime of client-created children of a server-streamed part is genuinely undefined — an accepted forum answer
  says they are lost, a 2025 bug report says they survive, and Roblox replied "we do not consider this a bug" — so the
  framework must be idempotent on reattach and must not leak either way. (§7)
- The engine explicitly does not guarantee the order in which property, attribute and instance changes replicate, and
  no replication rate for property or CFrame updates is documented anywhere. (§3)
- Official performance docs name server-side per-frame property writes as a mistake — server TweenService "is
  replicated to each client every frame" and the instruction is "tween objects on the client rather than the
  server". (§4)
- Server Authority forces StreamingEnabled on; for PREDICTED instances only Simulation-Access properties (e.g.
  `BasePart.CFrame`) may be touched inside `BindToSimulation()`, and predicted instances are matched by a GUID derived
  partly from per-script creation *order within a frame* — so a reconciler that reorders or conditionally skips
  creation breaks client/server stitching. What SA changes for NON-predicted decorative instances is undocumented
  (UNCONFIRMED #7). (§3)
- The renderer collapses identical meshes with the same asset ID into a single draw call, which directly rewards a
  one-MeshId-per-visual-kind template-clone architecture and punishes per-object mesh variation. (§5)
- `BulkMoveTo` is officially an anti-recommendation — "simply setting the CFrame property of individual parts and
  welded models is fast enough in the majority of cases" — so batched-write plumbing is not the win it looks like. (§1)
- Nobody has built this: Fusion and Vide are instance-generic but have zero streaming, replication or
  external-destruction awareness; jecs and Matter leave entity→Instance sync entirely to you; and Roblox itself shipped
  a state-only fine-grained reactive core (`Roblox/signals`) plus runtime-but-coarse ProceduralModel regeneration, and
  no declarative world renderer. (§6)
