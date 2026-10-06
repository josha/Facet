import os
from pathlib import Path
import signal
import subprocess
import sys

name, output, timeout = sys.argv[1:4]
tier = sys.argv[4] if len(sys.argv) > 4 else "one"
environment = dict(os.environ, FACET_SUITE_JSON=output)
process = subprocess.Popen([os.environ.get("LUNE", "lune"), "run", "tests/run_one", name, tier], env=environment, start_new_session=True)
try:
    code = process.wait(timeout=float(timeout))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    Path(output).unlink(missing_ok=True)
    print(f"worker {name} and its process group stopped after {timeout}s", file=sys.stderr)
    code = 124
sys.exit(code)
