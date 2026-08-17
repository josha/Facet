#!/usr/bin/env python3
"""Commit ONLY your own hunks, through a private index, in one uninterrupted step.

    tools/commit_isolated.py -m <message-file> <spec> [<spec> ...]
    tools/commit_isolated.py -m <message-file> --dry-run <spec> ...

    <spec> = path                    the whole file (you verified it is all yours)
             path:marker[,marker...] only hunks whose text contains a marker

    tools/commit_isolated.py --repair <path> [<path> ...]
             no commit: just make the shared index agree with HEAD for those
             paths (the repair for phantom staged deletions — see REPAIR below)

WHY THIS EXISTS
---------------
`docs/lessons/staging-by-name-is-not-isolation.md` records four rounds of the
same accident in one week: with N agents in one working tree, every git command
that names a path (`add`, `commit -- <path>`, `diff --cached`) reports on a
LOCATION, and location is not ownership. The rules that grew out of those rounds
are a lock protocol implemented in etiquette, and the third occurrence proved
etiquette does not hold: the focus-graph agent ran `git diff --cached --stat`,
read back only its own eleven files, and still committed three that belonged to
someone else. The check did not fail — the CHECK -> COMMIT interval did, and that
interval is filled by exactly what a careful agent does (composing a message,
re-reading a diff). The more conscientious the agent, the wider its window.

This script removes the interval instead of asking anyone to be quicker. It:

  * stages into a PRIVATE index (`GIT_INDEX_FILE`) seeded from HEAD, so
    `.git/index` — the shared mutable everyone else is also writing — is never
    touched for staging, and another agent's staged work can neither be swept
    into your commit nor destroyed by it;
  * filters your diff to the HUNKS that mention your markers, which is the only
    granularity that is actually scoped to your changes rather than to a file;
  * writes the tree, commits it with `commit-tree`, and advances the branch with
    a COMPARE-AND-SWAP on the HEAD you read, so a commit landing underneath you
    fails loudly instead of being clobbered;
  * REPUBLISHES the committed paths into the shared index (see below), which is
    not optional.

Nothing here resets, checks out, stashes, or `add -A`s. Your working tree is
never modified.

REPUBLISH — the part that is easy to leave out and must not be
-------------------------------------------------------------
A commit made this way moves HEAD without updating `.git/index`, so the shared
index is left holding pre-commit blobs for your paths. That is not cosmetic.
MEASURED, in a scratch repo: with the index stale, another agent's ordinary
`git commit` writes the index as a tree and SILENTLY REVERTS your committed
content — their commit lands with your file back at its old contents, green
tests and all. It also makes their `git diff --cached` show phantom DELETIONS of
your new files, which is how a concurrent agent nearly reverted three files of
this framework the day this script was written.

So after the commit lands, each committed path's index entry is set to its blob
in the new commit, with `git update-index --cacheinfo`. That touches the shared
index for your paths only, reads no working-tree bytes (so it cannot sweep
anyone's in-flight edits), and is the surgical form of the `git reset <path>` the
standing rules forbid.

WHAT IT REFUSES
---------------
  * a named path with no change against HEAD                        -> exit 2
  * a BINARY path is staged WHOLE (there are no hunks to filter), and a
    marker filter on one is refused rather than silently ignored
  * a marker that matches no hunk (it will not commit nothing)      -> exit 2
  * HEAD moved between the read and the update-ref (a real race)    -> exit 3
    Re-run it. Your working tree is untouched, so a re-run is free.
  * it does NOT run pre-commit/commit-msg hooks (`commit-tree` bypasses them).
    This repo has none; if yours does, run them yourself first.

READING THE OUTPUT
------------------
  NEW    <path>                 untracked file, hashed whole into the commit
  KEEP   <path>  @@ -a,b +c,d @@   this hunk IS in the commit
  drop   <path>  @@ -a,b +c,d @@   this hunk is NOT (another agent's, or a later
                                   commit of your own)
  patch: <file>                 the exact bytes committed, kept for audit
  commit <sha> on <ref>
  index: republished N path(s)  the shared index now agrees with HEAD

Read the drop lines. They are the claim you are making about what is not yours.

THE HOLE THAT IS STILL OPEN
---------------------------
Hunk granularity. `git diff` merges nearby edits into one hunk, so if another
agent's change lands within the context window of yours, a marker match takes
BOTH and this script cannot tell. It diffs at `-U1` to make that window as
narrow as git allows (one line of context instead of three), but it does not
close it. When two agents are genuinely inside the same few lines, nothing short
of a separate worktree separates them — and the `patch:` file is there so the
claim is auditable after the fact rather than merely trusted.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import time

CONTEXT = "1"  # narrowest context git will apply cleanly; see "THE HOLE" above


def run(args, **kw):
    return subprocess.run(["git", *args], text=True, capture_output=True, **kw)


def die(msg, code):
    print(f"commit_isolated: {msg}", file=sys.stderr)
    sys.exit(code)


def git(args, **kw):
    r = run(args, **kw)
    if r.returncode != 0:
        sys.exit(f"commit_isolated: `git {' '.join(args)}` failed:\n{r.stderr.strip()}")
    return r.stdout


def tracked(path):
    return run(["ls-files", "--error-unmatch", path]).returncode == 0


def split_hunks(diff):
    lines = diff.splitlines(keepends=True)
    start = next((i for i, l in enumerate(lines) if l.startswith("@@")), None)
    if start is None:
        return None, []
    header, hunks, cur = lines[:start], [], None
    for l in lines[start:]:
        if l.startswith("@@"):
            cur = [l]
            hunks.append(cur)
        else:
            cur.append(l)
    return header, hunks


def index_blob(path):
    parts = run(["ls-files", "-s", "--", path]).stdout.split()
    return parts[1] if len(parts) > 2 else None


def republish(paths, commit, was=None):
    """Make the SHARED index agree with `commit` for these paths. Never reads the
    working tree, so it cannot sweep another agent's in-flight edits.

    `was` maps path -> its blob before this commit. When the index holds neither
    that blob nor the new one, ANOTHER AGENT had staged something there and this
    call resets it to unstaged. Their file on disk is untouched — but it is their
    staging, so it is reported rather than done quietly."""
    done = 0
    for p in paths:
        entry = run(["ls-tree", commit, "--", p]).stdout.split()
        if len(entry) < 3:
            continue  # deleted by this commit; nothing to point at
        mode, blob = entry[0], entry[2]
        if was is not None:
            current = index_blob(p)
            if current is not None and current not in (was.get(p), blob):
                print(
                    f"  NOTE  {p} had ANOTHER AGENT'S staged content in the shared index;\n"
                    f"        republishing resets it to unstaged. Their working-tree file is\n"
                    f"        untouched — they re-stage it. (Left alone, their `git commit`\n"
                    f"        would have reverted this commit instead.)",
                    file=sys.stderr,
                )
        for attempt in range(6):
            r = run(["update-index", "--add", "--cacheinfo", f"{mode},{blob},{p}"])
            if r.returncode == 0:
                done += 1
                break
            if "index.lock" not in r.stderr:
                print(f"  WARN  could not republish {p}: {r.stderr.strip()}", file=sys.stderr)
                break
            time.sleep(0.25 * (attempt + 1))
        else:
            print(
                f"  WARN  {p} left STALE in the shared index (lock contention).\n"
                f"        Another agent's plain `git commit` may revert it. Repair with:\n"
                f"        tools/commit_isolated.py --repair {p}",
                file=sys.stderr,
            )
    return done


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("-m", "--message-file")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--repair", action="store_true")
    ap.add_argument("-h", "--help", action="store_true")
    ap.add_argument("specs", nargs="*")
    a = ap.parse_args()
    if a.help or not a.specs:
        print(__doc__)
        return 0 if a.help else 2

    if a.repair:
        n = republish(a.specs, "HEAD")
        print(f"index: republished {n} path(s) from HEAD")
        return 0

    if not a.message_file:
        sys.exit("commit_isolated: -m <message-file> is required (write the message FIRST)")

    old_head = git(["rev-parse", "HEAD"]).strip()
    index = tempfile.mktemp(suffix=".commit_isolated.index")
    env = dict(os.environ, GIT_INDEX_FILE=index)
    git(["read-tree", old_head], env=env)

    kept_patch, paths, was = [], [], {}
    for spec in a.specs:
        path, _, markers = spec.partition(":")
        paths.append(path)
        head_entry = run(["ls-tree", old_head, "--", path]).stdout.split()
        was[path] = head_entry[2] if len(head_entry) > 2 else None
        if not tracked(path):
            blob = git(["hash-object", "-w", path]).strip()
            git(["update-index", "--add", "--cacheinfo", f"100644,{blob},{path}"], env=env)
            print(f"  NEW    {path}")
            continue
        diff = git(["diff", f"-U{CONTEXT}", "--binary", old_head, "--", path])
        header, hunks = split_hunks(diff)
        if not hunks:
            # A BINARY PATH HAS NO HUNKS AND IS NOT UNCHANGED, and conflating the two
            # refused a real commit. Found 2026-08-17 committing a rebuilt
            # `examples/places/*.rbxl`: `git diff --stat` reported
            # `Bin 2433909 -> 2455473 bytes` and 430,205 bytes of binary patch, while
            # this branch said "no change against HEAD" and exited 2 — because
            # `split_hunks` looks for `@@` and a binary diff has none.
            #
            # There is nothing to FILTER in a binary file: hunk-level isolation is
            # the whole point of this script and a binary path cannot offer it, so
            # the honest handling is the one the untracked branch above already
            # uses — hash the working-tree bytes and stage that blob whole. Naming a
            # binary path here is therefore the same assertion as naming any whole
            # file: you have verified the file is yours. A marker filter cannot mean
            # anything on one, so asking for both is refused rather than silently
            # ignored.
            # A MODE-ONLY CHANGE HAS NO HUNKS EITHER, and it is the same mistake
            # one step smaller: `chmod +x` on a tracked script produces
            # `old mode 100644 / new mode 100755` and not a single `@@`. Found
            # 2026-08-17 on `tools/microprofiler_aggregate.py`, minutes after the
            # binary case, and it matters here for a recorded reason — this script
            # lands NEW files at 100644, so an executable tool can pass `test -x`
            # locally while a fresh clone gets permission denied, and the ONLY way
            # to correct that afterwards is a mode-only commit.
            if "old mode " in diff and "new mode " in diff:
                if markers:
                    die(f"{path} is a MODE-ONLY change and markers cannot select inside one — refusing", 2)
                blob = git(["hash-object", "-w", path]).strip()
                mode = re.search(r"new mode (\d+)", diff).group(1)
                git(["update-index", "--add", "--cacheinfo", f"{mode},{blob},{path}"], env=env)
                print(f"  MODE   {path}  ({mode})")
                continue
            if "GIT binary patch" in diff or "Binary files" in diff:
                if markers:
                    die(f"{path} is BINARY and markers cannot select inside one — refusing", 2)
                blob = git(["hash-object", "-w", path]).strip()
                git(["update-index", "--add", "--cacheinfo", f"100644,{blob},{path}"], env=env)
                print(f"  BINARY {path}  (whole file, {len(diff)} bytes of patch)")
                continue
            die(f"{path} has no change against HEAD — refusing", 2)
        if markers:
            want = markers.split(",")
            keep = [h for h in hunks if any(m in "".join(h) for m in want)]
            if not keep:
                die(f"no hunk of {path} contains any of {want} — refusing", 2)
        else:
            keep = hunks
        for h in hunks:
            tag = "KEEP" if h in keep else "drop"
            print(f"  {tag}   {path}  {h[0].rstrip()}")
        kept_patch.append("".join(header) + "".join("".join(h) for h in keep))

    if kept_patch:
        fd, patch_file = tempfile.mkstemp(suffix=".commit_isolated.patch")
        with os.fdopen(fd, "w") as f:
            f.write("".join(kept_patch))
        git(["apply", "--cached", "--recount", "--whitespace=nowarn", patch_file], env=env)
        print(f"  patch: {patch_file}")

    if a.dry_run:
        print("commit_isolated: --dry-run, nothing committed")
        return 0

    tree = git(["write-tree"], env=env).strip()
    message = open(a.message_file).read()
    sha = subprocess.run(
        ["git", "commit-tree", tree, "-p", old_head], input=message, text=True, capture_output=True, check=True
    ).stdout.strip()
    ref = git(["symbolic-ref", "HEAD"]).strip()
    cas = run(["update-ref", ref, sha, old_head])
    if cas.returncode != 0:
        os.unlink(index)
        die(
            f"HEAD moved under you — nothing committed.\n"
            f"  {cas.stderr.strip()}\n"
            f"  Your working tree is untouched. Re-run this exact command.",
            3,
        )
    os.unlink(index)
    print(f"commit_isolated: {sha[:9]} on {ref}")
    print(f"index: republished {republish(paths, sha, was)} path(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
