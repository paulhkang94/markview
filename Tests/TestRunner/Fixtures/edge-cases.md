# Edge Cases

## Deeply Nested Blockquotes

> Level 1
>
> > Level 2
> >
> > > Level 3
> > >
> > > > Level 4
> > > >
> > > > > Level 5

## Deeply Nested Lists

- Level 1
  - Level 2
    - Level 3
      - Level 4
        - Level 5
      - Level 4b
    - Level 3b
  - Level 2b
- Level 1b

1. First
   1. Nested first
      1. Double nested
         1. Triple nested
         2. Triple second
      2. Double second
   2. Nested second
2. Second

## HTML Entities

Common: &amp; &lt; &gt; &quot;

Numeric: &#169; &#8212; &#x2603;

Copyright &copy; 2026. Arrows: &larr; &rarr;

## Unicode Characters

Chinese: 这是一个测试段落。

Japanese: マークダウンのテストです。

Korean: 마크다운 테스트입니다.

Math: ∑ ∏ ∫ ∂ √ ∞ ≈ ≠ ≤ ≥

Accented: café résumé naïve über Zürich

Currency: $ € £ ¥ ₹ ₿

## Emoji

Standalone: 🚀 🎉 ✅ ❌ ⚠️ 💡 🔧 📝

### 🚀 Emoji in Heading

Emoji in lists:

- ✅ Tests passing
- ❌ Build failing
- ⚠️ Warnings present

| Status | Meaning |
|--------|---------|
| ✅     | Pass    |
| ❌     | Fail    |

## Whitespace Edge Cases

Text before empty lines.



Text after multiple empty lines.

Text with trailing spaces
and a hard line break.

Text with backslash\
line break.

## Very Long Line

This is an extremely long line that exceeds two hundred characters in length and is designed to test how the renderer handles text that does not contain any line breaks and just keeps going and going and going until it becomes quite unwieldy and forces the layout engine to wrap properly.

## Backslash Escapes

\*not italic\*

\*\*not bold\*\*

\# not a heading

\- not a list item

\`not code\`

Literal backslash: \\

## Consecutive Headings

# Heading 1
## Heading 2
### Heading 3
#### Heading 4

No content between them.

## Mixed Content Stress

A paragraph with **bold**, *italic*, ~~strikethrough~~, `code`, and a [link](https://example.com) — all inline.

> Blockquote with **bold**, *italic*, `code`, and a [link](https://example.com).
>
> - List inside blockquote
> - With [links](https://example.com)
>
> > Nested quote with ~~strikethrough~~.

## Setext Headings

Heading Level 1
================

Heading Level 2
----------------

## Thematic Break Variations

---

***

___

## Empty Document Sections

Content before.

Content after.
