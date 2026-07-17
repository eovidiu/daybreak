#!/bin/bash
# Harness init.sh for Daybreak (web: Cloudflare Worker + vanilla JS, tests via vitest)
# Usage: .harness/init.sh [smoke_test|full_test]   default: full_test
#
# smoke_test — fast Node syntax check of Worker + browser sources (<15s).
# full_test  — vitest suite (unit + route tests) with coverage.
#
# Note: iOS (SwiftUI) tests run separately via xcodebuild on a simulator/device
# and are NOT part of this automated gate — they need Xcode and a booted device.

set -e

TARGET=${1:-full_test}
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Harness ${TARGET} (daybreak / node) ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

if [ "$TARGET" = "smoke_test" ]; then
    echo "--- Node syntax check ---"
    FAIL=0
    while IFS= read -r f; do
        node --check "$f" || FAIL=1
    done < <(find src public/app -name '*.js' -not -path '*/node_modules/*' 2>/dev/null)
    if [ "$FAIL" -ne 0 ]; then
        echo "Syntax errors found."
        exit 1
    fi
    echo "Syntax OK."
else
    echo "--- Install (only if node_modules missing) ---"
    [ -d node_modules ] || npm ci 2>&1 | tail -5
    echo ""
    echo "--- Vitest (unit + routes) with coverage ---"
    npx vitest run --coverage 2>&1 | tail -25
fi

echo ""
echo "=== ${TARGET} Complete ==="
