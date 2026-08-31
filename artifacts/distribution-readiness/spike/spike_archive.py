#!/usr/bin/env python3
"""Distribution spike, final step: archive the throwaway asset 83627005624999.
Reads ROBLOX_API_KEY from env or GameStudio/tools/API_KEYS.txt; never prints it.
Run from the Facet repository root."""
import json, os, pathlib, urllib.error, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[3]; os.chdir(ROOT)
key = os.environ.get("ROBLOX_API_KEY", "")
if not key:
    for line in (ROOT.parents[1] / "tools" / "API_KEYS.txt").read_text().splitlines():
        if line.strip().startswith("ROBLOX_API_KEY="):
            key = line.split("=", 1)[1].strip(); break
if not key:
    raise SystemExit("ROBLOX_API_KEY not found")
req = urllib.request.Request(
    "https://apis.roblox.com/assets/v1/assets/83627005624999:archive",
    data=b"", method="POST", headers={"x-api-key": key})
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = json.loads(resp.read().decode())
except urllib.error.HTTPError as e:
    raise SystemExit(f"archive HTTP {e.code}: {e.read().decode()[:300]}")
pathlib.Path("artifacts/distribution-readiness/spike/archive-response.json").write_text(json.dumps(body, indent=1))
print("archived:", body.get("state"), "| saved to spike/archive-response.json")
