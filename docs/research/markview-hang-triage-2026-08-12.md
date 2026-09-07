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
The summary path deliberately avoids printing the raw event payload.

> **Amended 2026-09-07.** That is still true of the default `--issue` output, but
> it is no longer the only mode. Triaging `APPLE-MACOS-4J` needed thread state,
> `contexts`, tags, and breadcrumbs, none of which survive the summary, so
> `--issue [SHORT_ID] --raw` was added as an opt-in full dump of the untouched
> event.
>
> **`--raw` output is not redacted.** A Sentry macOS event can carry the
> reporter's IP address (`user.ip_address`), device name and model
> (`contexts.device`), tags, and absolute filesystem paths in breadcrumbs and
> stack frames. Read it in the terminal. Never paste it into a tracked file, an
> issue, or a pull request body - this repository is public.

## Follow-on: APPLE-MACOS-4J (1.7.2)

`APPLE-MACOS-3Q` above moved *linting* off the main actor. The next member of the
same family, `APPLE-MACOS-4J`, was triaged on 2026-09-07 and showed the
*rendering* half still running synchronously on the MainActor
(`finishLoadContent` -> `renderImmediate` -> `MarkdownRenderer.renderHTML` ->
cmark), reproduced above 2000 ms on two realistic document shapes.

Fixed in #76 (mar-049), unreleased as of 1.7.2: `PreviewViewModel.scheduleRender`
renders in a detached task and publishes behind a `renderGeneration` guard, the
same shape as `scheduleLint`. The `isLoaded` flag now flips when the first render
publishes rather than when the file is read, so the preview is never revealed
over empty HTML on a cold open; the contract is documented on the property and
pinned by the `mar-049:` tests. Full triage evidence stays untracked in
`docs/personal/hang-4j-triage-2026-09-07.md`; a summary lives in `docs/STATUS.md`.

## Release follow-up

- Ship the lint change in the next release after normal verification.
- Watch all three issue groups against that release.
- Treat a new `APPLE-MACOS-3Q` event on the fixed release as a regression.
- Keep `APPLE-MACOS-2Z` and `APPLE-MACOS-31` open or muted according to alert-noise policy until a sample supplies a more actionable stack.
