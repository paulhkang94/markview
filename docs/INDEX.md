# MarkView Documentation Index

> Reference guide for MarkView architecture, launch planning, and technical decisions.
> **Last updated:** 2026-04-11

## Status & Living Docs
- **[PLATFORMS.md](PLATFORMS.md)** - Cross-platform executive summary: feature matrix, iOS/Android gaps, release sequence, shared code architecture
- **[STATUS.md](STATUS.md)** - macOS release state, feature set, test pyramid, distribution channels, adoption metrics
- **[MOBILE.md](MOBILE.md)** - iOS + Android prototype state, App Store blockers, release plan (mobile SSOT)

### Per-platform SSOTs
| Platform | Submission doc | Notes |
|----------|---------------|-------|
| macOS | [STATUS.md](STATUS.md) | v1.4.2 shipping |
| iOS | [markview-ios/docs/RELEASE.md](../../markview-ios/docs/RELEASE.md) | In submission |
| Android | [markview-android/docs/RELEASE.md](../../markview-android/docs/RELEASE.md) | Blocked on identity verification |

## Launch & Planning
- **[LAUNCH.md](personal/LAUNCH.md)** - Consolidated launch strategy and timeline

## Architecture & Design
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture, QuickLook extension, webview sandbox, rendering pipeline
- **[MARKET-ANALYSIS.md](MARKET-ANALYSIS.md)** - Competitive positioning and user segment analysis

## Operations & Maintenance
- **[GOTCHAS.md](GOTCHAS.md)** - Known issues, workarounds, and debugging guidance
- **[FAILURES.md](FAILURES.md)** - Post-mortems and failure analysis
- **[sentry-setup-runbook.md](sentry-setup-runbook.md)** - Error monitoring and alerting setup
- **[mcp-setup.md](mcp-setup.md)** - MCP server configuration and registration

## Research & Strategy
- **[research/](research/)** - Research docs (e2e testing, competitive positioning, QuickLook extension, adoption strategy, dev loop, MCP feasibility, performance, editor bugs)
- **[personal/](personal/)** - Strategy docs (growth, monetization, registry, distribution, retros, mobile plans)
