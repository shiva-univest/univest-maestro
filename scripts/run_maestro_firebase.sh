#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Maestro + Firebase Test Lab Runner
# Usage:
#   ./scripts/run_maestro_firebase.sh --local
#   ./scripts/run_maestro_firebase.sh --firebase
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_PROJECT_DIR="${FLUTTER_PROJECT_DIR:-../univest}"  # path to Flutter project
APK_PATH="${APK_PATH:-$FLUTTER_PROJECT_DIR/build/app/outputs/flutter-apk/app-uat-debug.apk}"
ARTIFACTS_DIR="$HOME/.maestro/tests"
TEST_SUITE="$PROJECT_DIR/test-suites/smoke.yaml"
FIREBASE_PROJECT="${FIREBASE_PROJECT:-}"
DEVICE_MODEL="${DEVICE_MODEL:-Pixel2}"
DEVICE_VERSION="${DEVICE_VERSION:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    echo "Usage: $0 [--local | --firebase] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --local              Run Maestro tests locally on connected device/emulator"
    echo "  --firebase           Run tests on Firebase Test Lab"
    echo "  --skip-build         Skip APK build step"
    echo "  --suite <path>       Test suite to run (default: smoke.yaml)"
    echo "  --apk <path>         Path to pre-built APK"
    echo "  --project <id>       Firebase project ID"
    echo "  -h, --help           Show this help"
    exit 0
}

# --- Parse arguments ---
MODE=""
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)    MODE="local"; shift ;;
        --firebase) MODE="firebase"; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --suite)    TEST_SUITE="$2"; shift 2 ;;
        --apk)      APK_PATH="$2"; shift 2 ;;
        --project)  FIREBASE_PROJECT="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *)          error "Unknown option: $1" ;;
    esac
done

[[ -z "$MODE" ]] && error "Specify --local or --firebase"

# --- Check dependencies ---
check_dependencies() {
    if ! command -v maestro &>/dev/null; then
        warn "Maestro not found. Installing..."
        curl -Ls "https://get.maestro.mobile.dev" | bash
        export PATH="$HOME/.maestro/bin:$PATH"
    fi
    log "Maestro version: $(maestro --version)"
}

# --- Build APK ---
build_apk() {
    if [[ "$SKIP_BUILD" == true ]]; then
        log "Skipping APK build"
        return
    fi

    log "Building Flutter APK..."
    cd "$FLUTTER_PROJECT_DIR"
    flutter build apk --debug --flavor uat -t lib/main_uat.dart
    cd "$PROJECT_DIR"

    [[ -f "$APK_PATH" ]] || error "APK not found at $APK_PATH"
    log "APK built: $APK_PATH"
}

# --- Run locally ---
run_local() {
    log "Running Maestro tests locally..."
    maestro test \
        --debug-output "$ARTIFACTS_DIR/$TIMESTAMP" \
        "$TEST_SUITE"

    log "Results saved to: $ARTIFACTS_DIR/$TIMESTAMP"
}

# --- Run on Firebase Test Lab ---
run_firebase() {
    [[ -z "$FIREBASE_PROJECT" ]] && error "Set --project or FIREBASE_PROJECT env var"

    if ! command -v gcloud &>/dev/null; then
        error "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
    fi

    log "Uploading APK to Firebase Test Lab..."
    mkdir -p "$ARTIFACTS_DIR/$TIMESTAMP"

    # Run instrumentation test with Maestro sharding
    gcloud firebase test android run \
        --project="$FIREBASE_PROJECT" \
        --type=game-loop \
        --app="$APK_PATH" \
        --device="model=$DEVICE_MODEL,version=$DEVICE_VERSION,locale=en,orientation=portrait" \
        --timeout=15m \
        --results-dir="maestro-$TIMESTAMP" \
        2>&1 | tee "$ARTIFACTS_DIR/$TIMESTAMP/firebase_output.log"

    # Download results
    RESULTS_BUCKET=$(gcloud firebase test android run \
        --project="$FIREBASE_PROJECT" \
        --format="value(resultStorage.gcsPath)" 2>/dev/null || true)

    if [[ -n "$RESULTS_BUCKET" ]]; then
        gsutil -m cp -r "$RESULTS_BUCKET/*" "$ARTIFACTS_DIR/$TIMESTAMP/" 2>/dev/null || true
    fi

    log "Firebase Test Lab run complete"
    log "Results saved to: $ARTIFACTS_DIR/$TIMESTAMP"
}

# --- Main ---
log "Maestro Firebase Test Runner"
log "Mode: $MODE"
log "Suite: $TEST_SUITE"

check_dependencies
build_apk

case $MODE in
    local)    run_local ;;
    firebase) run_firebase ;;
esac

log "Done!"
