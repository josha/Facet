#!/usr/bin/env python3
"""Distribution spike, step 1: create the THROWAWAY Model asset via Open Cloud.

Creates "Facet-Spike-DeleteMe" (private, clearly labeled, archived at the end of
the spike) from the already-built build/Facet.rbxm, polls the operation until
Roblox finishes processing, and writes the raw responses to
artifacts/distribution-readiness/spike/create-response.json.

Reads ROBLOX_API_KEY from the environment, falling back to
GameStudio/tools/API_KEYS.txt. The key is never printed and never written.

Run from the Facet repository root:
    python3 artifacts/distribution-readiness/spike/spike_create.py
"""
import json
import os
import pathlib
import time
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[3]
os.chdir(ROOT)

key = os.environ.get("ROBLOX_API_KEY", "")
if not key:
    keys = ROOT.parents[1] / "tools" / "API_KEYS.txt"
    if keys.exists():
        for line in keys.read_text().splitlines():
            if line.strip().startswith("ROBLOX_API_KEY="):
                key = line.split("=", 1)[1].strip()
                break
if not key:
    raise SystemExit("ROBLOX_API_KEY not found in the environment or GameStudio/tools/API_KEYS.txt")

rbxm = pathlib.Path("build/Facet.rbxm").read_bytes()
request_json = json.dumps(
    {
        "assetType": "Model",
        "displayName": "Facet-Spike-DeleteMe",
        "description": "Throwaway distribution spike; will be archived. Not the real Facet package.",
        "creationContext": {"creator": {"userId": "1364639953"}},
    }
)
boundary = uuid.uuid4().hex
body = (
    f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n'
    f"Content-Type: application/json\r\n\r\n{request_json}\r\n"
).encode()
body += (
    f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
    f'filename="Facet.rbxm"\r\nContent-Type: model/x-rbxm\r\n\r\n'
).encode() + rbxm + b"\r\n"
body += f"--{boundary}--\r\n".encode()

req = urllib.request.Request(
    "https://apis.roblox.com/assets/v1/assets",
    data=body,
    method="POST",
    headers={"x-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"},
)
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        op = json.loads(resp.read().decode())
except urllib.error.HTTPError as e:
    raise SystemExit(f"CREATE HTTP {e.code}: {e.read().decode()[:400]}")
print("operation:", json.dumps(op))

path = op.get("path") or (f"operations/{op['operationId']}" if op.get("operationId") else None)
if not path:
    raise SystemExit(f"no operation path in: {op}")

final = None
for i in range(40):
    time.sleep(5)
    poll = urllib.request.Request(
        f"https://apis.roblox.com/assets/v1/{path}", headers={"x-api-key": key}
    )
    try:
        with urllib.request.urlopen(poll, timeout=60) as resp:
            state = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print("poll HTTP", e.code, e.read().decode()[:200])
        continue
    if state.get("done"):
        final = state
        break
    if i % 6 == 0:
        print("  …still processing")

out = pathlib.Path("artifacts/distribution-readiness/spike/create-response.json")
out.write_text(json.dumps({"operation": op, "final": final}, indent=1))
if final:
    print("FINAL:", json.dumps(final, indent=1)[:1200])
    asset_id = (final.get("response") or {}).get("assetId")
    print("\nASSET ID:", asset_id)
else:
    print(f"TIMED OUT while processing — poll later; operation path: {path}")
print("raw responses saved to", out)
