# The sync server's file list is frozen at startup — a long-lived server silently serves an incomplete tree

**Found:** 2026-07-27, sponsor-framework-gaps preflight.

`tools/lune/studio_sync.luau` recomputes the manifest **stamp** per request (an
earlier lesson), but the **file list** is walked once at server start. A server
left running from a previous session served 124 of 146 files — the missing 22
were the entire Step 5 module set (`src/motion/`, the new `src/input/` modules,
new specs' fixtures). An inject against it would have produced a place that
looks current (fresh stamp format, most sources patched) with whole new
subsystems absent, and every "missing module" error would have read as a
framework defect.

The tell: the fresh process logged `manifest 146 nodes` while the surviving
listener answered `files: 124`, and the stamps disagreed.

**Rule:** before any Studio evidence session, compare the served manifest's
**file count and stamp** against a freshly computed one (start a new server or
diff `curl /manifest` against the repo walk). `Address already in use` on
startup is not a convenience — it is the warning that an old list is still
serving. Kill the listener on :8642 and restart; then require the inject
result's `nodes` to equal the fresh count.
