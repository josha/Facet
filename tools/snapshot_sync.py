import argparse
import hashlib
import io
import json
from pathlib import Path
import posixpath
import re
import subprocess
import tarfile
import tempfile

COMMIT = re.compile("\\A[0-9a-f]{40}\\Z")
REPOSITORY = re.compile(
    "\\Ahttps://github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:\\.git)?\\Z"
)


class SnapshotSync:

    def __init__(
        self,
        name,
        root,
        destination,
        docs_source,
        docs_destination,
        paths,
        strip_prefix="",
        relocate_docs=False,
    ):
        self.name = name
        self.root = root
        self.dest = root / destination
        self.pin_path = self.dest / "UPSTREAM.lock"
        self.docs_source = docs_source
        self.docs_dest = root / docs_destination
        self.paths = paths
        self.strip_prefix = strip_prefix
        self.relocate_docs = relocate_docs
        self.help = f"Materialize the exact {name} snapshot. The snapshot is tracked, generated and read-only."

    def checked_pin(self, pin):
        commit = pin.get("commit")
        repository = pin.get("repository")
        if not isinstance(commit, str) or not COMMIT.match(commit):
            raise SystemExit(
                f"{self.name}: {self.pin_path.relative_to(self.root)} records commit {commit!r}, which is not a full 40-character lowercase-hex object name. Refusing to pass it to git."
            )
        if not isinstance(repository, str) or not REPOSITORY.match(repository):
            raise SystemExit(
                f"{self.name}: {self.pin_path.relative_to(self.root)} records repository {repository!r}, which is not an https://github.com/<owner>/<name> URL. Refusing to fetch from it."
            )
        return (repository, commit)

    def git(self, repository, *args):
        return subprocess.check_output(["git", "-C", str(repository), *args])

    def safe_member_name(self, name):
        probe = name.replace("\\", "/")
        if probe.startswith("/") or ":" in probe.split("/")[0]:
            raise SystemExit(
                f"{self.name}: archive member {name!r} is an absolute path; refusing"
            )
        if ".." in posixpath.normpath(probe).split("/"):
            raise SystemExit(
                f"{self.name}: archive member {name!r} escapes the snapshot root; refusing"
            )
        return name

    def materialize(self, repository, pin):
        (_url, pinned) = self.checked_pin(pin)
        commit = self.git(
            repository,
            "rev-parse",
            "--verify",
            "--end-of-options",
            pinned + "^{commit}",
        )
        commit = commit.decode().strip()
        if commit != pinned:
            raise ValueError(f"{self.name} pin must be a full commit identity")
        archive = self.git(
            repository, "archive", commit, "--", *self.paths, self.docs_source
        )
        (files, docs) = ({}, {})
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            for entry in source:
                if not entry.isfile():
                    continue
                name = self.safe_member_name(entry.name)
                data = source.extractfile(entry).read()
                if name.startswith(self.docs_source + "/"):
                    docs[name.removeprefix(self.docs_source + "/")] = (
                        self.relocate_guide(data, name, pin)
                        if self.relocate_docs and name.endswith(".md")
                        else data
                    )
                else:
                    files[name.removeprefix(self.strip_prefix)] = data
        files["license.luau"] = (
            b"--!strict\nreturn [=[\n" + files["LICENSE"] + b"\n]=]\n"
        )
        return (files, docs)

    def relocate_guide(self, data, name, pin):
        def relocate(match):
            target = match.group(1)
            if ":" in target or target.startswith("#"):
                return match.group(0)
            path = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
            if path.startswith(self.docs_source + "/"):
                return match.group(0)
            return (
                "]("
                + pin["repository"].removesuffix(".git")
                + "/blob/"
                + pin["commit"]
                + "/"
                + path
                + ")"
            )

        return re.sub(r"\]\(([^)]+)\)", relocate, data.decode()).encode()

    def verify(self, pin):
        generated = {
            path.relative_to(self.dest).as_posix(): path
            for path in self.dest.rglob("*")
            if path.is_file()
            and path not in (self.pin_path, self.dest / "README.md")
            and not path.is_relative_to(self.docs_dest)
        }
        docs = {
            path.relative_to(self.docs_dest).as_posix(): path
            for path in self.docs_dest.rglob("*")
            if path.is_file()
        }
        for paths, hashes in ((generated, pin["sha256"]), (docs, pin["docs"])):
            if set(paths) != set(hashes) or any(
                hashlib.sha256(path.read_bytes()).hexdigest() != hashes[name]
                for name, path in paths.items()
            ):
                return False
        expected_dirs = {
            parent.as_posix()
            for name in generated
            for parent in Path(name).parents
            if parent != Path(".")
        }
        expected_dirs.update(
            (
                parent.relative_to(self.dest).as_posix()
                for name in pin["docs"]
                for parent in (self.docs_dest / name).parents
                if parent != self.dest and parent.is_relative_to(self.dest)
            )
        )
        actual_dirs = {
            path.relative_to(self.dest).as_posix()
            for path in self.dest.rglob("*")
            if path.is_dir()
        }
        if actual_dirs != expected_dirs:
            return False
        return True

    def fetch_repository(self, source, scratch, url, commit):
        if source is not None:
            return source
        repository = Path(scratch) / "repository"
        subprocess.run(["git", "init", "--quiet", "--", str(repository)], check=True)
        self.git(repository, "fetch", "--depth=1", "--", url, commit)
        return repository

    def write_snapshot(self, files, docs):
        for root, entries in ((self.dest, files), (self.docs_dest, docs)):
            for path in root.rglob("*"):
                if (
                    path.is_file()
                    and path not in (self.pin_path, self.dest / "README.md")
                    and (
                        root == self.docs_dest
                        or not path.is_relative_to(self.docs_dest)
                    )
                    and path.relative_to(root).as_posix() not in entries
                ):
                    path.unlink()
            for name, data in entries.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        for directory in sorted(
            (p for p in self.dest.rglob("*") if p.is_dir()),
            key=lambda p: len(p.parts),
            reverse=True,
        ):
            if not any(directory.iterdir()):
                directory.rmdir()

    def inventory(self, entries):
        return {
            name: hashlib.sha256(data).hexdigest() for (name, data) in entries.items()
        }

    def main(self):
        parser = argparse.ArgumentParser(description=self.help)
        parser.add_argument(
            "--source",
            type=Path,
            help="local Git repository containing the pinned commit",
        )
        parser.add_argument("--check", action="store_true")
        parser.add_argument(
            "--bump",
            metavar="COMMIT",
            help="move the pin to this full commit and re-materialize",
        )
        args = parser.parse_args()
        pin = json.loads(self.pin_path.read_text())
        if args.bump is not None:
            if args.check:
                raise SystemExit(
                    f"{self.name}: --bump and --check are different requests"
                )
            pin["commit"] = args.bump
        url, commit = self.checked_pin(pin)
        if args.bump is None and self.verify(pin):
            print(f"{self.name}: pinned dependency verified {commit}")
            return
        if args.check:
            raise SystemExit(
                f"{self.name}: missing or modified dependency; run python3 tools/sync_{self.name.lower()}.py"
            )
        with tempfile.TemporaryDirectory(
            prefix=f"facet-{self.name.lower()}-"
        ) as scratch:
            files, docs = self.materialize(
                self.fetch_repository(args.source, scratch, url, commit), pin
            )
        hashes, guides = self.inventory(files), self.inventory(docs)
        if args.bump is not None:
            pin["sha256"], pin["docs"] = hashes, guides
        elif hashes != pin["sha256"] or guides != pin["docs"]:
            raise SystemExit(
                f"{self.name}: archive does not match pinned integrity inventory"
            )
        self.write_snapshot(files, docs)
        if args.bump is not None:
            self.pin_path.write_text(json.dumps(pin, indent=2) + "\n")
        assert self.verify(pin), f"{self.name} materialization did not match its pin"
        print(f"{self.name}: materialized {commit}")
