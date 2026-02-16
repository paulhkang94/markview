# Ethical Principles

**Status:** Living document. Last reviewed: 2026-02-16.

This project is governed by the following ethical principles. They apply to all code, features, integrations, and contributions. These principles are non-negotiable and take precedence over feature requests, performance optimizations, or convenience.

## Core Principles

These principles are shared across all projects in this ecosystem.

### 1. Serve Humanity's Good

Software must contribute positively to the world. Features, integrations, and design decisions must not enable harm to individuals, communities, or society at large. When in doubt, err on the side of caution.

### 2. Respect Individuals

- **Privacy by default.** Never collect, transmit, or store user data without explicit informed consent. Local-first processing is preferred over cloud-dependent workflows.
- **No dark patterns.** The software must not deceive, manipulate, or coerce users into actions they did not intend.
- **Accessibility.** Design for the widest possible range of users, including those with disabilities.

### 3. Transparency

- The software is open source (MIT). Users can inspect, audit, and verify every line of code.
- AI-assisted development is disclosed openly (see README and launch communications).
- Security vulnerabilities are disclosed responsibly and patched promptly.

### 4. User Data Sovereignty

- Users own their data. The software processes files locally and does not phone home.
- No telemetry, analytics, or usage tracking is included or planned.
- Export formats use open standards (HTML, PDF, Markdown) to prevent vendor lock-in.

### 5. Do No Harm

The software must not be designed, modified, or extended to:
- Surveil, track, or profile users without consent
- Exfiltrate, leak, or expose user content to third parties
- Facilitate harassment, discrimination, or abuse
- Undermine security, privacy, or civil liberties

## MarkView-Specific Principles

### MCP Server and AI Integration

The MCP server enables AI assistants to preview markdown in MarkView. This integration must:

- **Process content locally only.** Markdown content received via MCP stays on the user's machine. It is written to a temporary file and opened in the local app. No content is transmitted externally.
- **Operate with minimal permissions.** The MCP server reads stdin/stdout only. It does not access the network, read arbitrary files, or modify system state beyond creating temporary preview files.
- **Fail safely.** Invalid or malicious input is rejected with clear error messages. Path traversal, injection, and oversized payloads are blocked.
- **Respect user intent.** The server only acts when explicitly invoked by the AI assistant at the user's direction. It does not run background tasks, collect data, or persist state between invocations.

### Content Rendering

- **Sanitize all input.** The HTML sanitizer strips scripts, event handlers, and XSS vectors before rendering. Security is not optional.
- **No remote resource loading.** Preview rendering does not fetch external images, scripts, or stylesheets unless the user's markdown explicitly references them.

## Governance

### Review Process

- These principles are reviewed when new features are planned (especially AI integrations, network features, or data handling changes).
- Any contributor can raise an ethics concern via a GitHub issue with the `ethics` label.
- The maintainer is responsible for ensuring compliance and updating this document.

### Amendments

This is a living document. Changes are made via pull request with a clear rationale. The core principles (1-5) should only change in extraordinary circumstances. Domain-specific principles evolve with the software.

## Attribution

Inspired by the [ACM Code of Ethics](https://www.acm.org/code-of-ethics), the [Contributor Covenant](https://www.contributor-covenant.org/), and the principle that software should serve people, not the other way around.
