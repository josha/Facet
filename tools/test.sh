#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 0 ]; then
  echo "usage: tools/test.sh (full native verification); use tools/verify.sh fast for the working tier" >&2
  exit 2
fi
exec tools/verify.sh full
