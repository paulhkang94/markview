# Contributing to MarkView

Thanks for your interest in contributing. This guide covers how to get started, run tests, and submit changes.

## Prerequisites

- macOS 13+ (Ventura or later)
- Swift 6.1+ (install via Xcode Command Line Tools: `xcode-select --install`)
- Git

## Getting Started

```bash
git clone https://github.com/paulhkang94/markview.git
cd markview
swift build                 # Build all targets
swift run MarkView          # Launch the app
swift run MarkView test.md  # Open a specific file
```

## Running Tests

```bash
# Core test suite (178 tests)
swift run MarkViewTestRunner

# Full verification (build + core tests)
bash verify.sh

# Extended testing (fuzz + differential + visual + golden)
bash verify.sh --extended

# Individual test suites
swift run MarkViewFuzzTester    # 10K random input crash tests
swift run MarkViewDiffTester    # Compare output vs cmark-gfm CLI
swift run MarkViewVisualTester  # Visual regression + WCAG contrast
```

Before submitting a PR, run `bash verify.sh --extended` to ensure all tests pass.

## Submitting Issues

### Bug Reports

Include:
- macOS version (e.g., macOS 14.5)
- Steps to reproduce
- Expected behavior vs actual behavior
- Error messages or screenshots if applicable

### Feature Requests

Describe the use case and how it improves the user experience. Link to prior art if relevant.

## Submitting Pull Requests

1. **Fork** the repo and create a branch from `main`
2. **Make changes** — follow existing code patterns (no specific linter enforced)
3. **Add tests** — if you fix a bug, add a test that catches it; if you add a feature, cover the happy path
4. **Run tests** — `bash verify.sh --extended` must pass
5. **Commit** with a clear message (see git log for examples)
6. **Push** to your fork and submit a PR against `main`
7. **Respond to review** — address feedback promptly

## Code Style

- Follow existing Swift conventions (use SwiftLint rules as guidance)
- Keep functions focused — if it's over 50 lines, consider refactoring
- Prefer pure functions in MarkViewCore (no UI dependencies for testability)
- Comment non-obvious logic, especially in the renderer and sanitizer

## Areas Where Contributions Are Welcome

- **More plugins** — add support for ReStructuredText, AsciiDoc, Org-mode, etc.
- **More linter rules** — extend MarkdownLinter with additional checks
- **Performance** — profile and optimize hot paths (renderer, file watcher)
- **Accessibility** — improve VoiceOver support, keyboard navigation
- **Internationalization** — add translations for non-English locales
- **Documentation** — expand docs/ARCHITECTURE.md, add inline docs

## Questions?

Open an issue with the `question` label or ping `@paulhkang94` in the PR.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
