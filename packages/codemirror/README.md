# CodeMirror for Flutter

A **native Dart/Flutter port** of [CodeMirror 6](https://codemirror.net/) - the versatile code editor.

> ⚠️ **Work in Progress**: This is an early-stage port. See [PORT.md](PORT.md) for implementation status.

## Overview

This package is a ground-up reimplementation of CodeMirror 6 in Dart, following Flutter's architecture and idioms. It is NOT a web wrapper - it's pure Dart/Flutter using `EditableText` and custom render objects.

### Goals

- **Native performance** - No JavaScript bridge, pure Dart
- **Flutter-idiomatic** - Uses Flutter's widget and rendering patterns
- **Full feature parity** - Eventually match CodeMirror 6's capabilities
- **Extensible** - Same Facet-based extension system

## Architecture

The editor is organized into three main layers:

### 1. Text Layer (`lib/src/text/`)
B-tree based immutable document storage with O(log n) operations.

### 2. State Layer (`lib/src/state/`)
Immutable editor state with transaction-based updates:
- `EditorState` - Immutable state container
- `Transaction` - Describes state changes
- `Facet` - Extension aggregation points
- `StateField` - Persistent state slots

### 3. View Layer (`lib/src/view/`)
Flutter widgets for rendering and input:
- `EditorView` - Main editor widget
- Uses `EditableText` as base for text input
- Custom rendering for decorations and gutters

## Development

### Reference Implementation

The original CodeMirror 6 source is cloned into `ref/` for reference during porting:

```bash
# Already done, but for reference:
git clone --depth 1 https://github.com/codemirror/state.git ref/state
git clone --depth 1 https://github.com/codemirror/view.git ref/view
git clone --depth 1 https://github.com/codemirror/text.git ref/text
git clone --depth 1 https://github.com/codemirror/commands.git ref/commands
```

### Porting Strategy

We port file-by-file from TypeScript to idiomatic Dart:
1. Read the JS file completely
2. Identify types and interfaces  
3. Create equivalent Dart classes with proper null safety
4. Replace DOM APIs with Flutter equivalents
5. Write tests alongside implementation

See [AGENTS.md](AGENTS.md) for detailed porting guidelines and [PORT.md](PORT.md) for implementation phases.

## License

MIT - same as CodeMirror 6
