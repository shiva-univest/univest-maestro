#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SUITE="${1:-test-suites/smoke.yaml}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

cd "$PROJECT_DIR"
mkdir -p artifacts

maestro test \
  --debug-output "./artifacts/$TIMESTAMP" \
  "$SUITE"

echo ""
echo "Logs & screenshots saved to: artifacts/$TIMESTAMP"
