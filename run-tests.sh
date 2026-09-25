#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  --fast) exec tools/verify.sh fast ;;
  "") exec tools/verify.sh full ;;
  *) echo "usage: ./run-tests.sh [--fast]" >&2; exit 2 ;;
esac
