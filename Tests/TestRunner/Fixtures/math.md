# Math Rendering

Inline math via `\(...\)` — raw HTML block preserves delimiters for KaTeX:

<p>\(E = mc^2\)</p>

Display math via `$$...$$`:

$$\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$

Another display formula via `$$...$$`:

$$a^2 + b^2 = c^2$$

Block math via `\[...\]` — raw HTML block preserves delimiters for KaTeX:

<p>\[\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}\]</p>

Dollar signs in financial prose must not be treated as math delimiters:

The coverage limit is $10,000 and the deductible is $500.
