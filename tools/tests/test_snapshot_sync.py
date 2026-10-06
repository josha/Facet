import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from snapshot_sync import SnapshotSync


class SnapshotSyncTests(unittest.TestCase):
    def test_tracked_snapshots_need_no_upstream_history(self):
        for nested in (False, True):
            with self.subTest(
                nested=nested
            ), tempfile.TemporaryDirectory() as directory:
                sync = SnapshotSync(
                    "Fixture",
                    Path(directory),
                    "vendor",
                    "guide",
                    "vendor/guide" if nested else "guide",
                    (),
                )
                files, docs = {"src/init.luau": b"return {}"}, {
                    "SKILL.md": b"Use the public API."
                }
                sync.write_snapshot(files, docs)
                pin = {
                    "repository": "https://github.com/voidmeld/deleted-history",
                    "commit": "a" * 40,
                    "sha256": sync.inventory(files),
                    "docs": sync.inventory(docs),
                }
                sync.pin_path.write_text(json.dumps(pin))
                with patch(
                    "snapshot_sync.subprocess.check_output",
                    side_effect=AssertionError("upstream history is unavailable"),
                ), patch(
                    "snapshot_sync.subprocess.run",
                    side_effect=AssertionError("network is unavailable"),
                ):
                    for arguments in (["sync", "--check"], ["sync"]):
                        with patch.object(sys, "argv", arguments):
                            sync.main()
                (sync.dest / "src/init.luau").write_bytes(b"modified")
                self.assertFalse(sync.verify(pin))
                with patch.object(sys, "argv", ["sync", "--check"]), self.assertRaises(
                    SystemExit
                ):
                    sync.main()
                sync.write_snapshot(files, docs)
                (sync.docs_dest / "extra.md").write_text("unexpected")
                self.assertFalse(sync.verify(pin))
                sync.write_snapshot(files, docs)
                (sync.dest / "empty").mkdir()
                self.assertFalse(sync.verify(pin))

    def test_bump_and_repair_materialize_the_same_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            sync = SnapshotSync(
                "Fixture", Path(directory), "vendor", "guide", "guide", ()
            )
            sync.dest.mkdir()
            pin = {
                "repository": "https://github.com/voidmeld/verify",
                "commit": "a" * 40,
                "sha256": {},
                "docs": {},
            }
            sync.pin_path.write_text(json.dumps(pin))
            files, docs = {"src/init.luau": b"return {}"}, {"SKILL.md": b"Public API"}
            with patch.object(
                sync, "fetch_repository", return_value=Path(directory)
            ), patch.object(sync, "materialize", return_value=(files, docs)):
                with patch.object(sys, "argv", ["sync", "--bump", "b" * 40]):
                    sync.main()
                recorded = json.loads(sync.pin_path.read_text())
                self.assertEqual(recorded["commit"], "b" * 40)
                self.assertTrue(sync.verify(recorded))
                (sync.dest / "src/init.luau").write_bytes(b"damaged")
                with patch.object(sys, "argv", ["sync"]):
                    sync.main()
                self.assertEqual(
                    (sync.dest / "src/init.luau").read_bytes(), files["src/init.luau"]
                )
                self.assertEqual(json.loads(sync.pin_path.read_text()), recorded)
                with patch.object(
                    sync,
                    "materialize",
                    return_value=({"src/init.luau": b"wrong archive"}, docs),
                ), patch.object(sys, "argv", ["sync"]):
                    (sync.dest / "src/init.luau").unlink()
                    with self.assertRaises(SystemExit):
                        sync.main()

    def test_relocates_only_links_outside_the_copied_guide(self):
        sync = SnapshotSync(
            "Compose", Path("/tmp"), "vendor", ".agents/skills/compose", "guide", ()
        )
        pin = {
            "repository": "https://github.com/voidmeld/compose.git",
            "commit": "a" * 40,
        }
        guide = b"[API](../../../docs/api.md#runtime) [peer](references/ownership.md#owner) [web](https://example.com) [here](#here)"
        expected = (
            "[API](https://github.com/voidmeld/compose/blob/"
            + pin["commit"]
            + "/docs/api.md#runtime) [peer](references/ownership.md#owner) [web](https://example.com) [here](#here)"
        ).encode()
        self.assertEqual(
            sync.relocate_guide(guide, ".agents/skills/compose/SKILL.md", pin), expected
        )

    def test_rejects_unsafe_commit_and_archive_paths(self):
        sync = SnapshotSync("Fixture", Path("/tmp"), "vendor", "guide", "guide", ())
        for value in ("main", "--upload-pack=bad", "a" * 39):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                sync.checked_pin(
                    {
                        "commit": value,
                        "repository": "https://github.com/voidmeld/verify",
                    }
                )
        for value in ("../escape", "/absolute", "C:\\escape"):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                sync.safe_member_name(value)


if __name__ == "__main__":
    unittest.main()
