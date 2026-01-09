# CodeMirror for Flutter

[![pub.dev](https://img.shields.io/pub/v/codemirror.svg)](https://pub.dev/packages/codemirror)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/rlch/codemirror-flutter/blob/main/LICENSE)

A **pure Dart/Flutter port** of [CodeMirror 6](https://codemirror.net/) — the modern, extensible code editor.

## Features

- 🚀 **Native Dart** — No JavaScript interop, runs anywhere Flutter runs
- 📝 **Full CodeMirror 6 API** — EditorState, transactions, facets, extensions
- 🎨 **Syntax Highlighting** — JavaScript, TypeScript, JSX/TSX via Lezer parser
- ✨ **Language Features** — Autocompletion, bracket matching, folding, indentation
- 🔍 **Search & Replace** — Find, replace, regex support
- 📋 **Multiple Selections** — Multi-cursor editing
- 🎯 **LSP Ready** — Hover tooltips, diagnostics, go-to-definition hooks

## Installation

```yaml
dependencies:
  codemirror: ^0.0.1
```

## Quick Start

```dart
import 'package:codemirror/codemirror.dart';

// Initialize (call once at app startup)
void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();
  runApp(MyApp());
}

// Create editor state
final state = EditorState.create(EditorStateConfig(
  doc: 'const greeting = "Hello, world!";',
  extensions: ExtensionList([
    lineNumbers(),
    javascript(),
    autocompletion(),
  ]),
));

// Use in Flutter
EditorView(
  state: state,
  onUpdate: (update) {
    print('Document changed: ${update.state.doc}');
  },
)
```

## Architecture

The editor is organized into three main layers:

### Text Layer (`lib/src/text/`)
B-tree based immutable document storage with O(log n) operations.

### State Layer (`lib/src/state/`)
Immutable editor state with transaction-based updates:
- `EditorState` — Immutable state container
- `Transaction` — Describes state changes
- `Facet` — Extension aggregation points
- `StateField` — Persistent state slots

### View Layer (`lib/src/view/`)
Flutter widgets and rendering:
- `EditorView` — Main editor widget
- Syntax highlighting via `HighlightingTextEditingController`
- Gutter, tooltips, panels

## Related Packages

- [lezer](https://pub.dev/packages/lezer) — Incremental GLR parser (used for syntax highlighting)

## License

MIT — see [LICENSE](https://github.com/rlch/codemirror-flutter/blob/main/LICENSE)

## Credits

Based on [CodeMirror 6](https://codemirror.net/) by Marijn Haverbeke.
