# MarkView 1.7.1 hang triage - 2026-08-12

## Scope

Live Sentry review of the three 1.7.1 issue groups named in `mar-046`:
`APPLE-MACOS-2Z`, `APPLE-MACOS-31`, and `APPLE-MACOS-3Q`.
Evidence was refreshed with `scripts/sentry_check.py` on 2026-08-12 EDT.

## Dispositions

| Issue | Latest sample | Evidence | Disposition |
|---|---:|---|---|
| `APPLE-MACOS-2Z` | 2026-08-12 14:03 UTC | 72 events. The in-app stack contains only `main`, `MarkViewApp.$main`, and Sentry's hang monitor. It does not identify an app operation below the entry point. | Monitor. Do not make a speculative code change from this grouping alone. Revisit when a sample contains an actionable app frame. |
| `APPLE-MACOS-31` | 2026-08-07 11:49 UTC | 8 events. The stack is `WebPreviewView.makeNSView` line 38 into `WKWebView.init`. WebKit construction is framework-required and already occurs through SwiftUI's `makeNSView` lifecycle. | Monitor. A reuse or pooling rewrite would add lifecycle risk without evidence that MarkView is constructing duplicate views. |
| `APPLE-MACOS-3Q` | 2026-07-29 14:13 UTC | 1 event. The full app path reaches synchronous `MarkdownLinter.countOccurrences` from `PreviewViewModel.runLint` while the model is main-actor isolated. | Fixed. Lint computation now runs in a detached task, publishes only the newest generation on the main actor, and cancels stale/debounced publications. |

## Fix verification

The regression test injects a deterministic 400 ms lint operation, starts the
normal 300 ms debounced lint path, and verifies that a 350 ms main-actor
heartbeat is not delayed. It fails against the synchronous implementation and
passes with the detached computation. `LintDiagnostic` and its severity are
`Sendable` so results can safely cross back to the main actor.

Focused result on 2026-08-12: `MarkViewTestRunner` - 382 passed, 0 failed.

## Reusable telemetry improvement

`scripts/sentry_check.py --issue [SHORT_ID] [--json]` now returns the latest
event timestamp, release, and normalized in-app frames. This replaces repeated
Keychain lookup, API calls, and ad hoc event-payload parsing during hang triage.
It deliberately avoids printing the raw event payload.

## Release follow-up

- Ship the lint change in the next release after normal verification.
- Watch all three issue groups against that release.
- Treat a new `APPLE-MACOS-3Q` event on the fixed release as a regression.
- Keep `APPLE-MACOS-2Z` and `APPLE-MACOS-31` open or muted according to alert-noise policy until a sample supplies a more actionable stack.
