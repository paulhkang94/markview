# Code Blocks

## Python

```python
def fibonacci(n: int) -> list[int]:
    fib = [0, 1]
    for i in range(2, n):
        fib.append(fib[-1] + fib[-2])
    return fib[:n]

if __name__ == "__main__":
    print(fibonacci(10))
```

## JavaScript

```javascript
const debounce = (fn, ms) => {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
};
```

## Swift

```swift
struct MarkdownRenderer {
    func render(_ markdown: String) -> AttributedString {
        let parser = Parser(markdown)
        return parser.parse().map { node in
            node.attributedString
        }.joined()
    }
}
```

## Rust

```rust
fn main() {
    let numbers: Vec<i32> = (1..=10).collect();
    let sum: i32 = numbers.iter().sum();
    println!("Sum: {sum}");
}
```

## Go

```go
func handler(w http.ResponseWriter, r *http.Request) {
    data := map[string]string{"status": "ok"}
    json.NewEncoder(w).Encode(data)
}
```

## Bash

```bash
#!/bin/bash
set -euo pipefail
for f in *.md; do
    echo "Processing $f"
    wc -l "$f"
done
```

## JSON

```json
{
  "name": "markview",
  "version": "1.0.0",
  "dependencies": {
    "cmark-gfm": "^0.4.0"
  }
}
```

## YAML

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: swift test
```

## HTML

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Preview</title>
</head>
<body>
    <div id="content"></div>
</body>
</html>
```

## CSS

```css
.markdown-body {
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    font-size: 16px;
    line-height: 1.5;
    max-width: 900px;
    margin: 0 auto;
}
```

## SQL

```sql
SELECT u.name, COUNT(p.id) AS post_count
FROM users u
LEFT JOIN posts p ON p.author_id = u.id
WHERE u.active = true
GROUP BY u.id
ORDER BY post_count DESC
LIMIT 10;
```

## TypeScript

```typescript
interface Config {
    theme: 'light' | 'dark';
    fontSize: number;
    extensions: string[];
}

const defaultConfig: Config = {
    theme: 'light',
    fontSize: 14,
    extensions: ['table', 'strikethrough'],
};
```

## Indented Code Block

    This is an indented code block.
    It uses 4 spaces of indentation.
    No language hint is available.

## Inline Code

Use `git status` to check the working tree. The `--short` flag gives compact output.

Run `npm install` then `npm start`.

## Nested Backticks

Use `` `backticks` `` inside inline code by doubling the outer backticks.

## Code Block with No Language

```
Plain code block
No syntax highlighting
Just monospace text
```

## Empty Code Block

```
```
