# Changelog

## v1.4.3

- Fix linter false positive: `**` inside backtick code spans (e.g., `` `src/**/*.swift` ``) no longer triggers an "unclosed bold formatting" warning. The same fix applies to `__` and `~~` inside backticks.
- Fix FileWatcher: file descriptor captured by value in cancel handler, preventing silent watcher death after atomic saves (VS Code, Vim)
- Fix ToC: links rebuild correctly after innerHTML swap — clicking headings no longer scrolls to top
- Fix: Close File action added — previously no way to return to the home screen without quitting
- Add recent files screen with auto-reopen and Open Recent menu
- New app icon: hybrid SF Mono M design

## v1.4.2

- Fix KaTeX: remove `$...$` inline math delimiter to prevent false positives on financial prose
- Fix npm binary extraction path

## v1.4.0 / v1.4.1

- MCP server: add `lint_content`, `get_word_count`, `outline` tools (9 MCP tools total)
- Fix dark mode: CSS custom properties for reliable rendering across all renderers
- Fix dark mode: add missing `color-scheme` meta tag
- New app icon: SF Pro Bold M design

## v1.3.0

- Fix dark mode: inject CSS explicitly instead of relying on WKWebView media query
- Add dark mode regression tests

## v1.1.1

- Fix dark mode: inject CSS explicitly instead of relying on WKWebView media query
- Add dark mode regression tests to prevent invisible text bugs
- Default window size to 80% of screen instead of fixed 1000x700
- Fix README placeholder and outdated test counts
- Add screenshots to README

## v1.1.0

- Add versioning infrastructure (Info.plist, release script, build numbers)
- Add accessibility: ARIA landmarks, lang attributes, RTL CSS support
- Add internationalization: all user-facing strings in Strings.swift
- Add visual regression tester (19 tests with WCAG contrast validation)
- Add dark mode inline code fix + CSS auto-coverage tests
- Extract dark mode CSS to shared constant + golden drift check
- Match GitHub Primer CSS for tables + configurable preview width
- Add keyboard shortcuts (Cmd+E toggle editor, Cmd+O open, Cmd+Shift+E/P export)
- Fix mdpreview CLI to use `open` command instead of bare binary

## v1.0.0

- Initial release
- GitHub Flavored Markdown rendering via swift-cmark
- Live preview with split-pane editor
- Syntax highlighting for 18 languages via Prism.js
- Markdown linting with 9 built-in rules
- File watching with DispatchSource
- Multi-format plugins (Markdown, CSV, HTML)
- HTML sanitizer for XSS prevention
- Auto-suggestions for code fences, emoji, headings, links
- Export to HTML and PDF
- Dark mode with system/light/dark theme options
- 17 configurable settings
- 133 standalone tests + fuzz testing + differential testing
- App bundle with Finder "Open With" support
