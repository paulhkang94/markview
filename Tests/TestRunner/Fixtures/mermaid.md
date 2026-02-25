# Mermaid Diagram Test Fixture

This file tests Mermaid diagram rendering. Each fenced code block with the `mermaid` language tag should render as a visual diagram.

## Flowchart

```mermaid
flowchart TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Great!]
    B -->|No| D[Debug]
    D --> B
    C --> E[End]
```

## Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant MarkView
    participant Renderer
    User->>MarkView: Open markdown file
    MarkView->>Renderer: renderHTML(markdown)
    Renderer-->>MarkView: HTML body
    MarkView-->>User: Rendered preview
```

## Class Diagram

```mermaid
classDiagram
    class MarkdownRenderer {
        +renderHTML(markdown: String) String
        +wrapInTemplate(bodyHTML: String) String
        +postProcessForAccessibility(html: String) String
    }
    class MarkdownLinter {
        +lint(markdown: String) [Diagnostic]
    }
    MarkdownRenderer --> MarkdownLinter : uses
```

## Pie Chart

```mermaid
pie title Rendering Pipeline
    "Parse" : 30
    "Render" : 50
    "Template" : 20
```

## Git Graph

```mermaid
gitGraph
   commit id: "Initial"
   branch feature
   checkout feature
   commit id: "Add Mermaid"
   commit id: "Add tests"
   checkout main
   merge feature
   commit id: "Release"
```

## State Diagram

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Loading : Open file
    Loading --> Rendering : File read
    Rendering --> Preview : Render complete
    Preview --> Rendering : File changed
    Preview --> Idle : File closed
    Loading --> Error : Read failed
    Error --> Idle : Dismiss
```

## Mixed Content

Regular markdown mixed with mermaid:

Here is a paragraph before a diagram.

```mermaid
flowchart LR
    A --> B --> C
```

And a paragraph after, plus some inline `code` and a table:

| Feature | Supported |
|---------|-----------|
| Flowchart | ✅ |
| Sequence | ✅ |
| Class | ✅ |
