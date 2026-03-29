# Univest Maestro E2E Tests

Production-grade Maestro end-to-end testing framework for the Univest Flutter app (Android + iOS).

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Maestro | Latest | `curl -Ls "https://get.maestro.mobile.dev" \| bash` |
| Flutter | 3.24+ | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| Android SDK | 30+ | Via Android Studio |
| gcloud CLI | Latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| Java | 17 | `brew install openjdk@17` |

## Quick Start

```bash
# 1. Clone and setup
git clone <repo-url> && cd univest-maestro
cp .env.example .env  # Edit with your values

# 2. Install Maestro
curl -Ls "https://get.maestro.mobile.dev" | bash

# 3. Start Android emulator
emulator -avd <avd_name> &

# 4. Run smoke tests
maestro test test-suites/smoke.yaml
```

## Project Structure

```
univest-maestro/
├── config.yaml                     # Maestro global config
├── .env.example                    # Environment template
├── CLAUDE.md                       # AI assistant context
│
├── flows/
│   ├── common/
│   │   └── launch.yaml             # App launch (reusable)
│   ├── auth/
│   │   └── login.yaml              # Login with OTP
│   └── dashboard/
│       └── home.yaml               # Dashboard validation
│
├── test-suites/
│   ├── smoke.yaml                  # Critical path: login + home
│   └── regression.yaml             # Full regression (expandable)
│
├── scripts/
│   └── run_maestro_firebase.sh     # Build + test runner
│
├── .github/workflows/
│   └── maestro-firebase.yml        # CI pipeline
│
└── artifacts/                      # Screenshots & logs (gitignored)
```

## Running Tests

### Local (Emulator/Device)

```bash
# Smoke suite (reads env from config.yaml)
maestro test test-suites/smoke.yaml

# Regression suite
maestro test test-suites/regression.yaml

# Single flow
maestro test flows/auth/login.yaml

# Override env variables inline
maestro test -e contact_number=9876543210 -e otp=0000 test-suites/smoke.yaml

# Via automation script (skip build if not building Flutter app)
./scripts/run_maestro_firebase.sh --local --skip-build
```

### Automation Script (`run_maestro_firebase.sh`)

The script auto-loads `.env` so you don't need to pass flags for project, APK, or device config.

```bash
# Local run
./scripts/run_maestro_firebase.sh --local --skip-build

# Firebase Test Lab (uses .env for project, APK path, device config)
./scripts/run_maestro_firebase.sh --firebase --skip-build

# Override .env values via flags
./scripts/run_maestro_firebase.sh --firebase --skip-build --apk /path/to/app.apk --project my-project-id

# Custom suite
./scripts/run_maestro_firebase.sh --firebase --skip-build --suite test-suites/regression.yaml
```

#### Script Options

| Flag | Description |
|------|-------------|
| `--local` | Run on connected device/emulator |
| `--firebase` | Run on Firebase Test Lab |
| `--skip-build` | Skip Flutter APK build step |
| `--suite <path>` | Test suite to run (default: `smoke.yaml`) |
| `--apk <path>` | Path to pre-built APK (overrides `.env`) |
| `--project <id>` | Firebase project ID (overrides `.env`) |
| `-h, --help` | Show help |

> **Note:** All flags are optional if the corresponding values are set in `.env`.

## Environment Configuration

Copy `.env.example` to `.env` and update values:

```bash
cp .env.example .env
```

Environment variables are defined in `config.yaml` under the `env:` key:

```yaml
env:
  contact_number: "9876543210"
  otp: "0000"
```

Referenced in flows as `${contact_number}` and `${otp}`. You can override them inline:

```bash
maestro test -e contact_number=1234567890 -e otp=1111 test-suites/smoke.yaml
```

## Firebase Test Lab Setup

### 1. Enable Test Lab

```bash
gcloud auth login
gcloud config set project <YOUR_PROJECT_ID>
gcloud services enable testing.googleapis.com
```

### 2. Create Service Account (for CI)

```bash
# Create service account
gcloud iam service-accounts create maestro-test-lab \
  --display-name="Maestro Test Lab"

# Grant permissions
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:maestro-test-lab@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/cloudtestservice.testAdmin"

gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:maestro-test-lab@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Download key
gcloud iam service-accounts keys create gcp-key.json \
  --iam-account=maestro-test-lab@<PROJECT_ID>.iam.gserviceaccount.com
```

### 3. Manual Test Lab Run

```bash
# List available devices
gcloud firebase test android models list

# Run on Test Lab with pre-built APK
gcloud firebase test android run \
  --type=game-loop \
  --app=./univest-build/your-app.apk \
  --device=model=MediumPhone.arm,version=30,locale=en,orientation=portrait \
  --timeout=15m
```

## CI/CD (GitHub Actions)

The pipeline at `.github/workflows/maestro-firebase.yml` runs on push to `main` and manual dispatch.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `GCP_SERVICE_ACCOUNT_KEY` | JSON key for the GCP service account |
| `FIREBASE_PROJECT_ID` | Firebase project ID |
| `FLUTTER_REPO_TOKEN` | PAT with access to Flutter app repo (if private) |

### Required GitHub Variables

| Variable | Description |
|----------|-------------|
| `FLUTTER_REPO` | Flutter app repository (e.g., `org/univest-app`) |

### Manual Trigger

Go to **Actions** > **Maestro E2E Tests** > **Run workflow** and select the test suite (smoke/regression).

## Writing New Flows

### 1. Create the flow

```yaml
# flows/portfolio/overview.yaml
appId: com.univest.capp.uat
tags:
  - portfolio
---
- runFlow: ../common/launch.yaml

- waitFor:
    text: "Portfolio"
    timeout: 10000

- assertVisible:
    text: "Total Investment"

- takeScreenshot: portfolio_overview
```

### 2. Add to test suite

```yaml
# In test-suites/regression.yaml, uncomment or add:
- runFlow: ../flows/portfolio/overview.yaml
```

### 3. Add env variables (if needed)

```yaml
new_variable: "value"
```

### Flutter Selector Strategy

| Priority | Selector | Flutter Mapping | Example |
|----------|----------|-----------------|---------|
| 1 | `id` | `ValueKey('name')` | `- tapOn: { id: "login_btn" }` |
| 2 | `text` | Visible text | `- tapOn: { text: "Submit" }` |
| 3 | `semanticsLabel` | `Semantics(label: '...')` | `- tapOn: { label: "Close" }` |
| 4 | Index | Position in tree | `- tapOn: { index: 0 }` (avoid) |

### Best Practices

- Use `runFlow` for reusable steps (launch, login)
- Use `waitFor` with element selectors, never `wait: <ms>`
- Use `waitForAnimationToEnd` after navigation/transitions
- Add `takeScreenshot` at key checkpoints
- Keep flows focused on a single user journey
- Use `tags` in frontmatter for filtering

## Debugging

### Maestro Studio

```bash
maestro studio
```

Opens a browser UI to:
- Inspect the live view hierarchy
- Find element IDs, text, and semantic labels
- Execute commands interactively
- Take screenshots

### Verbose Logs

```bash
# Debug output for a flow
maestro test flows/auth/login.yaml --debug-output artifacts/debug

# Maestro system logs
cat ~/.maestro/logs/maestro.log
```

### Screenshots

Auto-captured on flow completion (via `config.yaml`). Manual capture:

```yaml
- takeScreenshot: step_name
```

Output: `~/.maestro/tests/` or `--output` directory.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Element not found | Run `maestro studio` to inspect selectors. Verify Flutter `Key`/`Semantics` widgets exist |
| Flaky tests | Replace `wait` with `waitFor` on a specific element. Add `waitForAnimationToEnd` after navigations |
| App won't launch | Check `appId` matches `applicationId` in `build.gradle`. Run `adb devices` to verify connection |
| Timeout errors | Increase `timeout` in `waitFor`. Check if the app is actually reaching that screen |
| iOS testing | Use `bundleId` instead of `appId`. Run on a booted iOS simulator |
| Firebase auth error | Re-run `gcloud auth login`. Verify service account has `cloudtestservice.testAdmin` role |
| Invalid model error | Run `gcloud firebase test android models list` to see available device models |
| APK not found | Check `FLUTTER_PROJECT_DIR` path in `.env`. Ensure the APK file exists |

## License

Internal use only.
