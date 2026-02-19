# Sentry Setup Runbook (macOS/iOS Swift Apps)

Reusable checklist for adding Sentry error monitoring to any Apple platform project. Goal: automate everything except the browser-only steps.

---

## 1. Account & Project Creation (Browser)

1. Go to [sentry.io](https://sentry.io) and create org (or use existing)
2. Create project: select platform (e.g., "Apple — macOS")
3. **Gotcha**: Sentry auto-names the project slug based on the platform selection, NOT your project name. A macOS project becomes `apple-macos`, an iOS project becomes `apple-ios`. You can rename it after creation in Settings → Projects → [project] → General Settings → Name/Slug.

**Record these values:**
```bash
SENTRY_ORG="your-org-slug"
SENTRY_PROJECT="apple-macos"  # Check actual slug!
SENTRY_DSN="https://xxx@yyy.ingest.us.sentry.io/zzz"
```

## 2. SDK Integration (Swift)

### Add SPM dependency

In Xcode: File → Add Package Dependencies → `https://github.com/getsentry/sentry-cocoa`

Or in Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),
],
targets: [
    .executableTarget(
        name: "YourApp",
        dependencies: [
            .product(name: "Sentry", package: "sentry-cocoa"),
        ]
    ),
]
```

### Initialize in app entry point

```swift
import Sentry

// In your App init or AppDelegate
SentrySDK.start { options in
    options.dsn = "YOUR_DSN_HERE"
    options.tracesSampleRate = 1.0  // Adjust for production
    options.debug = false           // true during setup only
    options.enableAutoSessionTracking = true
}
```

### Generic pattern (any platform)

The core pattern is always:
1. Add SDK package/dependency for your platform
2. Call `SentrySDK.start` (or equivalent) as early as possible in app lifecycle
3. Pass DSN + sample rate + any environment config

## 3. GitHub Integration (Browser Only)

1. Sentry → Settings → Integrations → GitHub → Install
2. Select your GitHub org/account
3. Grant access to specific repos (or all)
4. This enables: commit tracking, suspect commits, "Create GitHub Issue" alert action

**Cannot be automated**: GitHub OAuth flow requires browser interaction.

## 4. API Token Creation (Browser)

**Correct path** (as of 2026):
1. Sentry → Settings → Developer Settings → Personal Tokens → Create New Token
2. **NOT** the old "Auth Tokens" path (which still exists but is deprecated)

**Required scopes:**
- Project: Read & Write
- Organization: Read & Write
- Alerts: Read & Write
- Release: Read & Write (for CI release tracking)
- Issue & Event: Read & Write

```bash
SENTRY_AUTH_TOKEN="sntrys_xxx"
```

**Scope limitation**: Personal tokens CANNOT access `/organizations/{org}/integrations/` (requires `org:integrations` scope, which is only available to internal/public integrations, not personal tokens). This means "Create GitHub Issue" alert actions must be configured via browser.

## 5. Alert Rule Creation (API)

### Template: New Issue Alert

```bash
curl -X POST "https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/" \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "New Issue Alert",
    "actionMatch": "any",
    "filterMatch": "all",
    "conditions": [
      {"id": "sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"}
    ],
    "actions": [
      {
        "id": "sentry.mail.actions.NotifyEmailAction",
        "targetType": "IssueOwners",
        "fallthroughType": "ActiveMembers"
      }
    ],
    "frequency": 30
  }'
```

### Template: Regression Alert

```bash
curl -X POST "https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/" \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Regression Alert",
    "actionMatch": "any",
    "filterMatch": "all",
    "conditions": [
      {"id": "sentry.rules.conditions.regression_event.RegressionEventCondition"}
    ],
    "actions": [
      {
        "id": "sentry.mail.actions.NotifyEmailAction",
        "targetType": "IssueOwners",
        "fallthroughType": "ActiveMembers"
      }
    ],
    "frequency": 30
  }'
```

### Template: Error Spike Alert (>10 errors in 1 hour)

```bash
curl -X POST "https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/" \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Error Spike (>10 in 1h)",
    "actionMatch": "any",
    "filterMatch": "all",
    "conditions": [
      {
        "id": "sentry.rules.conditions.event_frequency.EventFrequencyCondition",
        "value": 10,
        "interval": "1h"
      }
    ],
    "actions": [
      {
        "id": "sentry.mail.actions.NotifyEmailAction",
        "targetType": "IssueOwners",
        "fallthroughType": "ActiveMembers"
      }
    ],
    "frequency": 60
  }'
```

### Automation script pattern

```bash
#!/bin/bash
set -euo pipefail

SENTRY_ORG="${1:?Usage: $0 <org> <project>}"
SENTRY_PROJECT="${2:?Usage: $0 <org> <project>}"
SENTRY_AUTH_TOKEN="${SENTRY_AUTH_TOKEN:?Set SENTRY_AUTH_TOKEN env var}"
API="https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/"

create_rule() {
  local name="$1" conditions="$2"
  curl -sf -X POST "$API" \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${name}\",
      \"actionMatch\": \"any\",
      \"filterMatch\": \"all\",
      \"conditions\": [${conditions}],
      \"actions\": [{
        \"id\": \"sentry.mail.actions.NotifyEmailAction\",
        \"targetType\": \"IssueOwners\",
        \"fallthroughType\": \"ActiveMembers\"
      }],
      \"frequency\": 30
    }" && echo " -> Created: ${name}" || echo " -> FAILED: ${name}"
}

create_rule "New Issue Alert" \
  '{"id":"sentry.rules.conditions.first_seen_event.FirstSeenEventCondition"}'

create_rule "Regression Alert" \
  '{"id":"sentry.rules.conditions.regression_event.RegressionEventCondition"}'

create_rule "Error Spike (>10 in 1h)" \
  '{"id":"sentry.rules.conditions.event_frequency.EventFrequencyCondition","value":10,"interval":"1h"}'
```

## 6. CI Release Tracking (GitHub Actions)

Add to your existing CI workflow:

```yaml
- name: Sentry Release
  uses: getsentry/action-release@v3
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: your-org-slug
    SENTRY_PROJECT: your-project-slug
  with:
    environment: production
    version: ${{ github.sha }}
```

## 7. GitHub Secret Setup

```bash
# Store token as GitHub Actions secret
gh secret set SENTRY_AUTH_TOKEN --body "sntrys_xxx" --repo owner/repo
```

## 8. What Cannot Be Automated (and Why)

| Step | Reason |
|------|--------|
| GitHub integration install | OAuth browser flow required |
| "Create GitHub Issue" alert action | Requires `org:integrations` scope, unavailable to personal tokens (403) |
| Initial account/org creation | Requires email verification |
| Project creation | No public API for project creation without org-level token |

## 9. Common Gotchas

1. **Project slug != project name**: Sentry derives the slug from the platform selection. "MarkView" project on macOS platform → slug `apple-macos`. Always check the actual slug in project settings or via `GET /api/0/projects/{org}/`.

2. **Personal token scope limitations**: The `/organizations/{org}/integrations/` endpoint returns 403 for personal tokens. This blocks automating alert actions that reference GitHub integrations (like "Create GitHub Issue"). You must configure these in the browser.

3. **Auth token UI path changed**: The correct path is Settings → Developer Settings → Personal Tokens. The old "Auth Tokens" section still exists but creates a different token type.

4. **DSN is not secret**: The DSN can safely be committed to source code. It only allows sending events, not reading them. But the `SENTRY_AUTH_TOKEN` IS secret and must be in environment/secrets only.

5. **Release version must match**: The version string in CI (`getsentry/action-release`) must match what the SDK reports. Using `github.sha` is safest for consistency.

---

*Last updated: 2026-02-17. Based on MarkView (macOS Swift app) setup experience.*
