#!/usr/bin/env python3
"""microprofiler_aggregate — read a Roblox MicroProfiler HTML dump's aggregate
timer table, and its engine layout diagnostics, without opening a browser.

    python3 tools/microprofiler_aggregate.py <dump.html> [<dump.html> ...]
    python3 tools/microprofiler_aggregate.py --all <dump.html>     every scope, not just LuauUI/*
    python3 tools/microprofiler_aggregate.py --layout <dump.html>  the Relayout/Update/Resize records

WHY THIS EXISTS. Three rounds of device captures were decoded by hand, and the
format was written down each time (`artifacts/performance-stress-places/
device-capture-2026-08-14.md` §2 is the canonical description). Writing the decode
down is not the same as being able to re-run it, and the analysis that follows a
capture is where the mistakes live, not the decode. This is the decode, once.

IT IS A READER, NOT A CHECK. It has no pass/fail and is not wired into any gate,
deliberately: what a capture MEANS is a judgement about workload and tier that a
script cannot make, and a green tick on a dump would invite exactly the reading
this project keeps warning about. It prints numbers; a human writes the artifact.

THE FORMAT. base64 inside a leading HTML comment -> 3-byte `GAK` magic, u32
uncompressed size, u32 compressed size, then a zlib stream. Inside:

    header[0x20]  aggregate frame window (0 means NO AGGREGATE - see below)
    header[0x28]  timer frequency, 1e9 => totals are nanoseconds
    header[0x4c]  record count
    header[0x50]  aggregate timer table offset, 80-byte records
    header[0xc4]  size of the \\0-terminated name blob at the tail
    record        u64 total | u64 worst | u32 id | u32 group | u32 color |
                  u32 count | u32 nameOffset

THE ONE READING THAT INVALIDATES A CAPTURE, and it has now happened four times:
**`header[0x20] == 0` means the aggregate accumulator collected no frames.** The
timer table is present and the names decode perfectly; every count and total is
zero. `tableUnified.html` (2026-08-15) and `hostmove1.html` (2026-08-17) both
failed this way, and both looked like healthy files. This tool prints
`WINDOW=0 - NO AGGREGATE, THIS CAPTURE HAS NO TIMINGS` first and loudly for
exactly that reason.

THE CROSS-CHECK THAT SAYS THE DECODE IS RIGHT rather than plausible: on a healthy
LuauUI capture `LuauUI/tick` reads EXACTLY the frame window, one per frame. This
tool prints it as `tick==window` so the check is on the page instead of in
somebody's memory.

THE LAYOUT RECORDS (`--layout`) are the engine's own accounting and are not in the
timer table at all - they are `Context=... Cause=... Root=... Relayouts=N
Updates=N Resizes=N` strings in the blob. They are how a capture answers "did the
ENGINE do less work", which no `LuauUI/*` scope can: totalling them across
contexts is what showed, on 2026-08-17, that a nested host re-attributes the
descendant relayout rather than removing it.
"""
import re
import sys
import base64
import struct
import zlib


def load(path: str) -> bytes:
    raw = open(path, "rb").read()
    m = re.match(rb"<!--(.*?)-->", raw, re.S)
    if m is None:
        raise SystemExit(f"{path}: no leading HTML comment - not a MicroProfiler dump")
    blob = base64.b64decode(m.group(1), validate=False)
    if blob[:3] != b"GAK":
        raise SystemExit(f"{path}: bad magic {blob[:3]!r}, expected GAK")
    usize = struct.unpack("<I", blob[3:7])[0]
    out = zlib.decompress(blob[11:])
    if len(out) != usize:
        raise SystemExit(f"{path}: size mismatch {len(out)} != {usize}")
    return out


def _u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def _u64(d, o):
    return struct.unpack_from("<Q", d, o)[0]


def parse(path: str) -> dict:
    d = load(path)
    count, tbl, strsize = _u32(d, 0x4C), _u32(d, 0x50), _u32(d, 0xC4)
    strbase = len(d) - strsize

    def name(off):
        end = d.find(b"\0", strbase + off)
        return d[strbase + off : end].decode("utf-8", "replace")

    rows = []
    for i in range(count):
        o = tbl + i * 80
        if o + 80 > len(d):
            break
        rows.append(
            dict(
                total=_u64(d, o),
                worst=_u64(d, o + 8),
                count=_u32(d, o + 28),
                name=name(_u32(d, o + 32)),
            )
        )
    return dict(frames=_u32(d, 0x20), freq=_u64(d, 0x28) or 1_000_000_000, rows=rows, raw=d)


def layout_records(d: bytes):
    out = []
    for m in re.findall(rb"Context=[^\x00]{10,200}", d):
        s = m.decode("utf-8", "replace").strip()
        g = re.match(
            r"Context=(\S+) Cause=(\S+) Root=(\S+) Relayouts=(\d+) Updates=(\d+) Resizes=(\d+)", s
        )
        if g:
            out.append(
                dict(
                    context=g.group(1),
                    cause=g.group(2),
                    root=g.group(3),
                    relayouts=int(g.group(4)),
                    updates=int(g.group(5)),
                    resizes=int(g.group(6)),
                )
            )
    return out


def main(argv):
    show_all = "--all" in argv
    show_layout = "--layout" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        raise SystemExit(__doc__.strip().split("\n\n")[1])
    for p in paths:
        r = parse(p)
        ns, frames = r["freq"], r["frames"]
        print(f"\n=== {p} ===")
        if frames == 0:
            print("  WINDOW=0 - NO AGGREGATE, THIS CAPTURE HAS NO TIMINGS.")
            print("  The timer table and names are present and every count is zero. The")
            print("  MicroProfiler's accumulator had collected no frames when it was dumped.")
        else:
            tick = next((x for x in r["rows"] if x["name"] == "LuauUI/tick"), None)
            ok = tick is not None and tick["count"] == frames
            print(
                f"  window={frames} frames  freq={ns}"
                + (f"  tick=={tick['count']} ({'OK' if ok else 'MISMATCH'})" if tick else "")
            )
        rows = [x for x in r["rows"] if x["count"] > 0 and (show_all or x["name"].startswith("LuauUI/"))]
        rows.sort(key=lambda x: -x["total"])
        if rows:
            print(f"  {'scope':<26}{'occ':>7}{'occ/fr':>8}{'total ms':>11}{'ms/occ':>9}{'ms/frame':>10}{'worst':>9}")
            for x in rows[:30]:
                t = x["total"] / ns * 1000
                print(
                    f"  {x['name']:<26}{x['count']:>7}{x['count']/max(frames,1):>8.2f}{t:>11.2f}"
                    f"{t/x['count']:>9.4f}{t/max(frames,1):>10.3f}{x['worst']/ns*1000:>9.3f}"
                )
        if show_layout:
            recs = layout_records(r["raw"])
            print(f"\n  engine layout records ({len(recs)}):")
            print(f"  {'context':<20}{'cause':<34}{'relayouts':>10}{'updates':>9}{'resizes':>9}")
            tr = tu = tz = 0
            for x in recs:
                print(
                    f"  {x['context']:<20}{x['cause']:<34}{x['relayouts']:>10}{x['updates']:>9}{x['resizes']:>9}"
                )
                tr, tu, tz = tr + x["relayouts"], tu + x["updates"], tz + x["resizes"]
            print(f"  {'TOTAL':<54}{tr:>10}{tu:>9}{tz:>9}")


if __name__ == "__main__":
    main(sys.argv[1:])
