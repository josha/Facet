#!/usr/bin/env python3


import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_ROOT = os.path.join(os.path.dirname(REPO), "Facet-private-archive")

MANIFEST_NAME = "MANIFEST.json"
SUMS_NAME = "SHA256SUMS"
SCHEMA = "facet-private-archive/1"


BOOKKEEPING = {MANIFEST_NAME, SUMS_NAME}


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def head_commit(source):
    result = subprocess.run(
        ["git", "-C", source, "rev-parse", "HEAD"], capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def load_manifest(root):
    path = os.path.join(root, MANIFEST_NAME)
    if not os.path.exists(path):
        return {"schema": SCHEMA, "files": []}
    with open(path) as handle:
        data = json.load(handle)
    data.setdefault("schema", SCHEMA)
    data.setdefault("files", [])
    return data


def write_manifest(root, data):
    data["files"] = sorted(data["files"], key=lambda e: e["path"])
    with open(os.path.join(root, MANIFEST_NAME), "w") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")



    with open(os.path.join(root, SUMS_NAME), "w") as handle:
        for entry in data["files"]:
            handle.write(f"{entry['sha256']}  {entry['path']}\n")


def files_under(source, rel):

    absolute = os.path.join(source, rel)
    if os.path.isfile(absolute):
        return [rel]
    if not os.path.isdir(absolute):
        return []
    found = []
    for base, dirs, names in os.walk(absolute):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        for name in sorted(names):
            full = os.path.join(base, name)
            found.append(os.path.relpath(full, source))
    return sorted(found)


def archive(paths, root=DEFAULT_ROOT, source=REPO, quiet=False):
    os.makedirs(root, exist_ok=True)
    data = load_manifest(root)
    by_path = {entry["path"]: entry for entry in data["files"]}
    commit = head_commit(source)
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

    missing, copied = [], 0
    for requested in paths:
        rel = os.path.relpath(os.path.normpath(requested)).replace(os.sep, "/")
        if rel.startswith("../"):
            missing.append(requested)
            continue
        members = files_under(source, rel)
        if not members:
            missing.append(requested)
            continue
        for member in members:
            src = os.path.join(source, member)
            dst = os.path.join(root, member)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            by_path[member] = {
                "path": member,
                "sha256": sha256_of(dst),
                "bytes": os.path.getsize(dst),
                "originCommit": commit,
                "archivedAt": stamp,
            }
            copied += 1
            if not quiet:
                print(f"  archived  {member}  ({by_path[member]['bytes']} bytes)")

    data["files"] = list(by_path.values())
    write_manifest(root, data)
    if missing:
        for path in missing:
            print(f"archive_private: NOT FOUND in {source}: {path}", file=sys.stderr)
        return 1, copied
    if not quiet:
        print(f"archive_private: {copied} file(s) archived into {root} (manifest holds {len(data['files'])})")
    return 0, copied


def verify(root=DEFAULT_ROOT, quiet=False):
    if not os.path.isdir(root):
        print(f"archive_private: no archive at {root}", file=sys.stderr)
        return 1
    data = load_manifest(root)
    problems = []
    for entry in data["files"]:
        path = os.path.join(root, entry["path"])
        if not os.path.isfile(path):
            problems.append(f"MISSING   {entry['path']}")
            continue
        size = os.path.getsize(path)
        if size != entry["bytes"]:
            problems.append(f"SIZE      {entry['path']}: manifest {entry['bytes']}, on disk {size}")
        digest = sha256_of(path)
        if digest != entry["sha256"]:
            problems.append(f"CHECKSUM  {entry['path']}: manifest {entry['sha256'][:16]}…, on disk {digest[:16]}…")


    sums_path = os.path.join(root, SUMS_NAME)
    if not os.path.isfile(sums_path):
        problems.append(f"MISSING   {SUMS_NAME}")
    else:
        sums = {}
        with open(sums_path) as handle:
            for line in handle:
                line = line.rstrip("\n")
                if not line:
                    continue
                digest, _, name = line.partition("  ")
                sums[name] = digest
        expected = {entry["path"]: entry["sha256"] for entry in data["files"]}
        for name in sorted(set(expected) | set(sums)):
            if expected.get(name) != sums.get(name):
                problems.append(f"SUMS      {name}: MANIFEST.json and {SUMS_NAME} disagree")








    recorded = {entry["path"] for entry in data["files"]}
    unrecorded = 0
    for base, dirs, names in os.walk(root):
        dirs[:] = sorted(dirs)
        for name in sorted(names):
            rel = os.path.relpath(os.path.join(base, name), root).replace(os.sep, "/")
            if rel not in BOOKKEEPING and rel not in recorded:
                unrecorded += 1

    if problems:
        print(f"archive_private: verify FAILED — {len(problems)} problem(s) in {root}")
        for problem in problems:
            print(f"  {problem}")
        return 1
    if not quiet:
        total = sum(entry["bytes"] for entry in data["files"])
        print(f"archive_private: verify OK — {len(data['files'])} file(s), {total} bytes, {root}")
        if unrecorded:
            print(f"  note: {unrecorded} other file(s) in this archive root are not in this manifest")
    return 0


def show(root=DEFAULT_ROOT):
    data = load_manifest(root)
    for entry in data["files"]:
        print(f"{entry['sha256']}  {entry['bytes']:>9}  {entry['originCommit'][:9]}  {entry['path']}")
    print(f"archive_private: {len(data['files'])} file(s) in {root}")
    return 0







def selftest():
    work = tempfile.mkdtemp(prefix="facet-archive-selftest-")
    ok = True
    try:
        source = os.path.join(work, "repo")
        root = os.path.join(work, "archive")
        os.makedirs(os.path.join(source, "vendor", "Thing"))
        os.makedirs(os.path.join(source, "docs"))
        with open(os.path.join(source, "vendor", "Thing", "init.luau"), "w") as handle:
            handle.write("return {}\n")
        with open(os.path.join(source, "vendor", "Thing", "NOTES.md"), "w") as handle:
            handle.write("notes\n")
        with open(os.path.join(source, "docs", "one.md"), "w") as handle:
            handle.write("one\n")

        code, copied = archive(["vendor", "docs/one.md"], root=root, source=source, quiet=True)
        good = code == 0 and copied == 3
        print(f"  [{'OK' if good else 'WRONG'}] archive copied 3 files (got {copied}, exit {code})")
        ok = ok and good

        good = verify(root=root, quiet=True) == 0
        print(f"  [{'OK' if good else 'WRONG'}] a clean archive verifies")
        ok = ok and good


        archive(["vendor", "docs/one.md"], root=root, source=source, quiet=True)
        entries = len(load_manifest(root)["files"])
        good = entries == 3
        print(f"  [{'OK' if good else 'WRONG'}] re-archiving is idempotent (manifest holds {entries})")
        ok = ok and good

        planted = os.path.join(root, "vendor", "Thing", "init.luau")
        with open(planted, "a") as handle:
            handle.write("-- tampered\n")
        good = verify(root=root, quiet=True) != 0
        print(f"  [{'BITES' if good else 'WRONG'}] a planted checksum mismatch fails verify")
        ok = ok and good
        with open(planted, "w") as handle:
            handle.write("return {}\n")
        assert verify(root=root, quiet=True) == 0, "restore failed"

        os.remove(os.path.join(root, "docs", "one.md"))
        good = verify(root=root, quiet=True) != 0
        print(f"  [{'BITES' if good else 'WRONG'}] a deleted archived file fails verify")
        ok = ok and good

        code, _ = archive(["no/such/path"], root=root, source=source, quiet=True)
        good = code != 0
        print(f"  [{'BITES' if good else 'WRONG'}] archiving a path that does not exist fails")
        ok = ok and good
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return ok


def main():
    parser = argparse.ArgumentParser(description="the private archive for material that leaves the public tree")
    parser.add_argument("command", nargs="?", choices=("archive", "verify", "list"))
    parser.add_argument("paths", nargs="*", help="repo-relative files or directories to archive")
    parser.add_argument("--root", default=DEFAULT_ROOT, help=f"archive root (default {DEFAULT_ROOT})")
    parser.add_argument("--source", default=REPO, help="repository root the paths are relative to")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        print("archive_private --selftest")
        raise SystemExit(0 if selftest() else 1)
    if args.command == "archive":
        if not args.paths:
            raise SystemExit("archive_private: archive needs at least one path")
        code, _ = archive(args.paths, root=args.root, source=args.source)
        raise SystemExit(code)
    if args.command == "verify":
        raise SystemExit(verify(root=args.root))
    if args.command == "list":
        raise SystemExit(show(root=args.root))
    parser.print_help()
    raise SystemExit(2)


if __name__ == "__main__":
    main()
