#!/usr/bin/env python3
"""The Input Action System owns semantic action routing: no NEW legacy binder may appear.

WHAT THE ROW CLAIMS (release-candidate review, `ias-owns-semantic-input`).
`InputContext`/`InputAction`/`InputBinding` own semantic routing and lifetime. Every legacy
call that survives has a CURRENT impossibility proof, one allowlisted adapter that owns it,
and a removal trigger. This check is the drift half: it refuses a NEW direct
`ContextActionService` use, and a NEW `InputBegan`/`InputEnded`/`InputChanged` subscription,
anywhere outside the files the inventory already classified and excused.

THE ALLOWLIST IS BUILT FROM THE INVENTORY, NOT FROM THE TREE. Every entry below names its
inventory class (2 environment/capability · 3 raw pointer/keyboard geometry · 4 engine
interoperability/diagnosis · 5 test-only injection), the inventory's own stated reason, and
the concrete event that RETIRES it. Class-1 rows — semantic action routing — are absent by
construction: after wave R3 the two migratable ones are gone (Rascal Rally's deprecated
`InputAction:Fire` sites and its hand-staged touch buttons), and the six that cannot migrate
are recorded in `NO_IAS_SURFACE` with the platform text that makes them impossible today.
`artifacts/release-candidate-review/input/ias-inventory.md` is the source; this file is that
document made executable.

BOTH DIRECTIONS BITE, which is the only reason a drift check is worth a gate row:

  * a file with a flagged site that is NOT allowlisted            -> FAIL (new drift)
  * an allowlisted file that no longer HAS a flagged site         -> FAIL (stale exemption;
      its removal trigger fired, so the entry must go, not linger as a standing permit)
  * a `NO_IAS_SURFACE` verb whose witness has vanished            -> FAIL (the verb migrated
      or was renamed; the impossibility ledger is fiction until someone re-reads it)

That second rule is the one that keeps this honest over time. `src/client/InputBridge.luau`
in the consumer carried two flagged sites until 2026-08-18; the `UIButton` migration removed
them, and an allowlist that still excused it would have handed the next author a free pass
on a file that no longer needs one.

WHAT IT READS. Luau source with COMMENTS STRIPPED, through the real lexer in
`tools/check_no_screen_key_bindings.py` (long comments at arbitrary bracket level, long
strings, quoted and interpolated strings). String CONTENTS stay visible on purpose: the most
plausible bypass is `game:GetService("ContextActionService")`, and it lives inside a string.

WHAT IT CANNOT SEE, stated so the next agent does not assume otherwise:
  * a computed service name (`game:GetService(NAMES[i])`, concatenation, `loadstring`);
  * a helper OUTSIDE the scanned trees binding on a module's behalf — the require graph in
    `tools/lune/check_boundary.luau` is the instrument for that class, not this one;
  * whether an ALLOWLISTED file's use is still the one the inventory excused. The entry
    pins the file and the reason, not the line.

Run: `python3 tools/check_input_authority.py`            from the Facet root; exit 0 = clean
     `python3 tools/check_input_authority.py --selftest`  planted-drift proof, hermetic
"""

import os
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_no_screen_key_bindings import strip_luau_comments  # noqa: E402

# ── the trees this check owns ────────────────────────────────────────────────
# The consumer tree is scanned when it is present (it is, in the multi-repo
# checkout the gate runs from) and reported as skipped when it is not, never
# silently dropped — "found nothing" must never read as "passed".
FACET_TREES = ("src", "examples")
CONSUMER_TREE = "../../../games/RascalRally/code/src"

# ── the two flagged classes ─────────────────────────────────────────────────
PATTERNS = {
    # Any direct reach into ContextActionService. Facet's own rule (ADR-0004) is
    # that it never re-implements or reaches into arbitration; the one module
    # that does is a DIAGNOSTIC, and it is allowlisted as such.
    "ContextActionService": re.compile(r"ContextActionService"),
    # Any subscription to the raw input stream, on ANY receiver. Deliberately not
    # narrowed to a variable literally named `UserInputService`: an alias would
    # walk straight through that, and the per-node `GuiObject.InputBegan` form is
    # the same class — it is what the consumer's hand-staged touch buttons used.
    "Input*:Connect": re.compile(r"\.Input(?:Began|Ended|Changed)\b"),
}

# ── the allowlist: file -> (classes, why the inventory excused it, what retires it) ──
ALLOWLIST = {
    "src/client/gamepad_contention.luau": (
        "4",
        "INPUT-20..23. Workspace.PlayerScriptsUseInputActionSystem is NOT SCRIPTABLE on any "
        "build (re-probed 0.734.0.7340915, 2026-08-15), so every detector of the legacy "
        "stack must be BEHAVIOURAL — it reads CAS's own bound-action table because there is "
        "nothing else to read. And CAS priority is not the same arbitration space as "
        "InputContext.Priority (measured live 2026-08-14: a CAS Sink at 100 beat an "
        "InputContext at 10000 with Sink=true), so with the flag OFF there is no "
        "in-framework remedy at all and the diagnosis has to exist.",
        "IAS rollout Phase 3 (mid-2027, per the release announcement) removes the property "
        "and puts every place on the IAS player scripts; there is then no legacy stack for "
        "these probes to find. Partially retired already: disableLegacyControls() is inert "
        "wherever iasPlayerScriptsActive() answers true (DF-9, 2026-08-18).",
    ),
    "src/client/screen_pointer.luau": (
        "3 (+1: the wheel)",
        "INPUT-29/30/32. Research A.4: 'Pointer position/geometry: Not addressed as a "
        "general capability... no mention of hit-testing, screen-to-world conversion, or "
        "geometry helpers.' Drag capture is per-node geometry against solved rects. The "
        "wheel is worse than a gap: A.2's binding sources are KeyCode / UIButton / "
        "PointerIndex and the action types are Bool / Direction1D / Direction2D / "
        "Direction3D / ViewportPosition — NO wheel input source is documented anywhere in "
        "IAS, and ViewportPosition delivers a position, not a delta.",
        "IAS documents a pointer-geometry/hit-test surface AND a wheel binding source. "
        "Either one alone retires only half of this entry.",
    ),
    "src/client/screen_target.luau": (
        "3 + class-1-cannot-migrate",
        "INPUT-35/36/37/39. Four distinct documented gaps: no per-node secondary-pointer "
        "source (A.2 lists only KeyCode/UIButton/PointerIndex, and IAS carries no per-node "
        "targeting at all); 'Touch gesture recognition (swipe/pinch/etc.): Not mentioned'; "
        "'Text entry: Not mentioned anywhere on the overview page or the three class "
        "references' — TextBox.FocusLost(enterPressed, input) is the only surface that "
        "reports WHY editing ended; and the disclosure long-press needs InputObject identity "
        "plus a 12px slop, which IAS never exposes.",
        "IAS gains a gesture surface, a text-entry surface, and an InputObject payload on "
        "Pressed. Each closes a different row here; the entry shrinks as they land.",
    ),
    "examples/gallery/scenarios/runner.luau": (
        "5 (+4)",
        "INPUT-65..67. The raw gameProcessed SECOND OPINION has no IAS equivalent — IAS "
        "exposes no input trace — and it is the instrument that tells a scenario whether a "
        "key was eaten before any action saw it. The CAS unbind of RbxCameraKeypress is the "
        "keyboardFirst arm's only route: engine truth 5 says no InputContext priority "
        "outranks it.",
        "Test/tool-only and never shipped in src/. Retires when the scenarios stop needing a "
        "keyboard-first arm, or when IAS exposes an input trace of its own.",
    ),
    "../../../games/RascalRally/code/src/client/InputIdentity.luau": (
        "2",
        "INPUT-100/101. Research A.4: 'Device-change observation: Not exposed as its own "
        "event... The docs do not document a way to explicitly subscribe to device-change "
        "events within IAS itself.' The module's own header explains why even "
        "GetLastInputType() is unusable on a gamepad+touch handheld — deadzone drift flaps "
        "it several times a second — so the classifier reads the raw stream and requires a "
        "DELIBERATE act (past a 0.25 deadzone) before identity changes.",
        "IAS documents a device-change event carrying the deliberate-act distinction.",
    ),
    "../../../games/RascalRally/code/src/client/SponsorGesture.luau": (
        "3",
        "INPUT-107. Card-drag geometry: mouse move deltas and the press-candidate promotion "
        "that separates a drag from a tap. Same A.4 pointer-geometry gap as screen_pointer.",
        "IAS documents a pointer-geometry surface. Until then this belongs behind the "
        "game's own drag adapter, and the inventory records that the InputObject.Changed "
        "idiom (not the UIS-identity match) is the one that survived a device round.",
    ),
    "../../../games/RascalRally/code/src/client/SponsorGui.luau": (
        "3",
        "INPUT-114. Card-slot press-candidate: the same drag-vs-tap discrimination, on the "
        "legacy Sponsor surface that stays shipped as the rollback path.",
        "IAS documents a pointer-geometry surface, or the legacy Sponsor rollback is retired.",
    ),
    "../../../games/RascalRally/code/src/client/SponsorFtue.luau": (
        "3",
        "INPUT-115. Slot press advances the FTUE step — a per-node press on a specific "
        "instance, which is geometry, not a semantic verb with a binding.",
        "IAS documents a pointer-geometry surface.",
    ),
}

# ── the impossibility ledger: verbs with NO IAS surface at all ───────────────
# Six class-1 verbs the inventory records as unmigratable. Three of them route
# through a flagged surface and are covered by an ALLOWLIST entry above; three do
# not, and would otherwise be invisible here. Each carries a WITNESS — a token
# that must still be present in its owner — so the ledger cannot quietly become
# fiction: if a verb genuinely moves onto IAS, its witness disappears and this
# check says so instead of leaving a stale paragraph behind.
NO_IAS_SURFACE = (
    (
        "mouse-wheel scroll delta (INPUT-32)",
        "src/client/screen_pointer.luau",
        "MouseWheel",
        "A.2: no wheel input source is documented anywhere in IAS; ViewportPosition delivers "
        "a position, not a delta.",
    ),
    (
        "secondary-pointer context menu, per node (INPUT-35)",
        "src/client/screen_target.luau",
        "MouseButton2",
        "A.2: the only pointer-ish binding sources are KeyCode/UIButton/PointerIndex, and "
        "IAS carries no per-node targeting; this verb is per node.",
    ),
    (
        "the six touch gestures (INPUT-36)",
        "src/client/screen_target.luau",
        "TouchLongPress",
        "A.4: 'Touch gesture recognition (swipe/pinch/etc.): Not mentioned.'",
    ),
    (
        "text entry begin/commit/cancel + OSK return (INPUT-37)",
        "src/client/screen_target.luau",
        "ReturnPressedFromOnScreenKeyboard",
        "A.4: 'Text entry: Not mentioned anywhere on the overview page or the three class "
        "references.'",
    ),
    (
        "full-value disclosure long-press (INPUT-39)",
        "src/client/screen_target.luau",
        "enableDisclosure",
        "A.4 gesture gap, plus the one-finger identity match needs InputObject identity, "
        "which IAS never exposes.",
    ),
    (
        "consumer menu/HUD button taps, 22 sites (INPUT-116)",
        "../../../games/RascalRally/code/src/client/SponsorGui.luau",
        "Activated:Connect",
        "Expressible in principle via UIButton, but each tap would need its own InputAction "
        "and InputContext placement for a one-off, non-contended, pointer-only affordance; "
        "IAS delivers only a boolean and the payload is the point. Recorded as knowingly "
        "kept, not as a gap.",
    ),
)


def fail(message: str) -> "NoReturn":  # noqa: F821
    sys.stderr.write(message.rstrip() + "\n")
    raise SystemExit(1)


def luau_files(root: str) -> list:
    found = []
    for base, _, names in os.walk(root):
        found += [os.path.join(base, f) for f in names if f.endswith(".luau")]
    return sorted(found)


def flagged_sites(path: str) -> dict:
    """{pattern name: count} for one file, on comment-stripped source."""
    with open(path, encoding="utf-8") as handle:
        code = strip_luau_comments(handle.read())
    return {name: len(pat.findall(code)) for name, pat in PATTERNS.items() if pat.search(code)}


def scan(trees: list, allowlist: dict) -> tuple:
    """(offences, stale, scanned) — the whole rule, over the given roots.

    `trees` are (reported name, path on disk) pairs so the selftest can point the
    identical rule at a scratch copy without rewriting any of it.
    """
    offences, stale, scanned = [], [], []
    hit_files = {}
    for label, root in trees:
        if not os.path.isdir(root):
            continue
        scanned.append(label)
        for path in luau_files(root):
            sites = flagged_sites(path)
            if not sites:
                continue
            key = path if label == root else os.path.join(label, os.path.relpath(path, root))
            hit_files[key] = sites
            if key not in allowlist:
                detail = ", ".join(f"{n}×{c}" for n, c in sorted(sites.items()))
                offences.append(f"  {key}: {detail}")
    for key in sorted(allowlist):
        # only judge staleness for entries whose tree was actually scanned
        root_scanned = any(key.startswith(label) for label in scanned)
        if root_scanned and key not in hit_files:
            stale.append(f"  {key}")
    return offences, stale, scanned


def ledger_offences() -> list:
    bad = []
    for verb, owner, witness, _why in NO_IAS_SURFACE:
        if not os.path.isfile(owner):
            bad.append(f"  {verb}: owner {owner} is gone")
            continue
        with open(owner, encoding="utf-8") as handle:
            code = strip_luau_comments(handle.read())
        if witness not in code:
            bad.append(f"  {verb}: witness `{witness}` no longer present in {owner}")
    return bad


def real_trees() -> list:
    trees = [(t, t) for t in FACET_TREES]
    trees.append((CONSUMER_TREE, CONSUMER_TREE))
    return trees


def main() -> None:
    if not os.path.isdir("src") or not os.path.isdir("tools"):
        fail("missing src/ or tools/ — run this from the Facet root")
    offences, stale, scanned = scan(real_trees(), ALLOWLIST)
    if offences:
        fail(
            "INPUT AUTHORITY VIOLATED — a file outside the allowlisted adapters reaches for\n"
            "ContextActionService or subscribes to the raw input stream. Semantic action\n"
            "routing belongs on InputContext/InputAction/InputBinding; if this genuinely\n"
            "cannot be expressed today, add it to ALLOWLIST with its inventory class, the\n"
            "platform text that makes it impossible, and the event that retires it:\n" + "\n".join(offences)
        )
    if stale:
        fail(
            "STALE EXEMPTION — an allowlisted file no longer has a flagged site, so its\n"
            "removal trigger has fired. Delete the entry rather than leaving a standing\n"
            "permit on a file that no longer needs one:\n" + "\n".join(stale)
        )
    ledger = ledger_offences()
    if ledger:
        fail(
            "IMPOSSIBILITY LEDGER OUT OF DATE — a verb recorded as having NO IAS surface has\n"
            "lost its witness. Either it migrated (delete the entry and celebrate) or it was\n"
            "renamed (re-read it and move the witness):\n" + "\n".join(ledger)
        )
    consumer = "scanned" if CONSUMER_TREE in scanned else "NOT PRESENT (skipped)"
    print(
        f"input authority: clean. trees {', '.join(FACET_TREES)} scanned; consumer {consumer}. "
        f"{len(ALLOWLIST)} allowlisted adapters, {len(NO_IAS_SURFACE)} ledger verbs, 0 new binders."
    )


# --------------------------------------------------------------------------
# THE SELFTEST. A drift check that cannot be shown to BITE is decoration, and
# this repo has shipped that mistake before (`docs/lessons/`). Both planted
# defects the row names are reproduced here against a scratch COPY of the real
# tree — hermetic, so a concurrent reader of the working tree never sees a
# planted file, and so a crash mid-selftest cannot leave one behind.
# --------------------------------------------------------------------------
PLANT_CAS = """--!strict
local ContextActionService = game:GetService("ContextActionService")
ContextActionService:BindAction("MyVerb", function() end, false, Enum.KeyCode.E)
return {}
"""

PLANT_SUB = """--!strict
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input)
\tif input.KeyCode == Enum.KeyCode.E then
\t\tprint("interact")
\tend
end)
return {}
"""


def selftest() -> None:
    bad = []
    scratch = tempfile.mkdtemp(prefix="input-authority-selftest-")
    try:
        copy = os.path.join(scratch, "src")
        shutil.copytree("src", copy)
        trees = [("src", copy)]

        clean, stale, _ = scan(trees, ALLOWLIST)
        if clean:
            bad.append(f"  the unplanted copy already reports drift: {clean}")

        planted = os.path.join(copy, "client", "_drift_probe.luau")
        for name, source in (("a CAS bind", PLANT_CAS), ("a UserInputService.InputBegan bind", PLANT_SUB)):
            with open(planted, "w", encoding="utf-8") as handle:
                handle.write(source)
            offences, _, _ = scan(trees, ALLOWLIST)
            if len(offences) != 1 or "_drift_probe.luau" not in offences[0]:
                bad.append(f"  planting {name} did NOT redden the check (got {offences})")
        os.remove(planted)

        restored, _, _ = scan(trees, ALLOWLIST)
        if restored:
            bad.append(f"  the RESTORED tree does not pass: {restored}")

        # the comment exemption still holds — prose naming a service is not a bind
        with open(planted, "w", encoding="utf-8") as handle:
            handle.write("--[[ ContextActionService priority is not InputContext.Priority ]]\nreturn {}\n")
        commented, _, _ = scan(trees, ALLOWLIST)
        if commented:
            bad.append(f"  a BLOCK COMMENT naming the service reddened the check: {commented}")
        os.remove(planted)

        # …and a string literal is NOT exempt: GetService("...") is the bypass
        with open(planted, "w", encoding="utf-8") as handle:
            handle.write('local s = game:GetService("ContextActionService")\nreturn s\n')
        stringy, _, _ = scan(trees, ALLOWLIST)
        if len(stringy) != 1:
            bad.append(f"  a service name inside a STRING was not seen: {stringy}")
        os.remove(planted)

        # THE EXIT CODE, not just the rule. `scan` returning offences is useless
        # if `main` does not turn them into a non-zero exit — that is the half a
        # gate `run` string actually reads. Proved by pointing the real entry
        # point at the scratch copy rather than by planting in the live tree,
        # which a concurrent reader would see.
        global FACET_TREES, CONSUMER_TREE  # noqa: PLW0603
        with open(planted, "w", encoding="utf-8") as handle:
            handle.write(PLANT_CAS)
        saved_facet, saved_consumer, saved_cwd = FACET_TREES, CONSUMER_TREE, os.getcwd()
        saved_err, exited = sys.stderr, None
        try:
            FACET_TREES, CONSUMER_TREE = ("src",), "no-such-consumer-tree"
            os.chdir(scratch)
            os.makedirs("tools", exist_ok=True)
            # the failure it prints is the EXPECTED one; swallow it so a green
            # selftest does not read like a violation report to whoever runs it
            sys.stderr = open(os.devnull, "w", encoding="utf-8")
            try:
                main()
            except SystemExit as stop:
                exited = stop.code
        finally:
            sys.stderr.close()
            sys.stderr = saved_err
            os.chdir(saved_cwd)
            FACET_TREES, CONSUMER_TREE = saved_facet, saved_consumer
        if exited != 1:
            bad.append(f"  main() exited {exited} over a planted bind; a gate run string would stay green")
        os.remove(planted)

        # the staleness rule bites: an entry for a file with no flagged site
        _, stale_now, _ = scan(trees, dict(ALLOWLIST, **{"src/init.luau": ("0", "invented", "invented")}))
        if "  src/init.luau" not in stale_now:
            bad.append(f"  a stale allowlist entry was not reported: {stale_now}")

        # and the real tree, judged by the real rule, is clean in every dimension
        offences, stale_real, scanned = scan(real_trees(), ALLOWLIST)
        if offences or stale_real:
            bad.append(f"  the REAL trees are not clean: offences={offences} stale={stale_real}")
        if CONSUMER_TREE not in scanned:
            bad.append("  the consumer tree was not scanned — this run proves nothing about it")
        if ledger_offences():
            bad.append(f"  the impossibility ledger is out of date: {ledger_offences()}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if bad:
        fail("selftest FAILED:\n" + "\n".join(bad))
    print(
        "selftest: 8 cases green (planted CAS, planted InputBegan, restore, comment, string, "
        "non-zero exit, stale entry, real tree)"
    )


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        selftest()
    else:
        main()
