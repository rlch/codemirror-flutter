# codemirror-flutter

[![pub.dev](https://img.shields.io/pub/v/codemirror.svg)](https://pub.dev/packages/codemirror)
[![CI](https://github.com/rlch/codemirror-flutter/actions/workflows/ci.yaml/badge.svg)](https://github.com/rlch/codemirror-flutter/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A pure Dart/Flutter port of [CodeMirror 6](https://codemirror.net/) — the modern, extensible code editor.

## Features

- 🚀 **Native Dart** — No JavaScript interop, runs anywhere Flutter runs
- 📝 **Full CodeMirror 6 API** — EditorState, transactions, facets, extensions
- 🎨 **Syntax Highlighting** — JavaScript, TypeScript, JSX/TSX via Lezer parser
- ✨ **Language Features** — Autocompletion, bracket matching, folding, indentation
- 🔍 **Search & Replace** — Find, replace, regex support
- 📋 **Multiple Selections** — Multi-cursor editing
- 🎯 **LSP Ready** — Hover tooltips, diagnostics, go-to-definition hooks

## Packages

| Package | Description |
|---------|-------------|
| [codemirror](packages/codemirror) | Main editor widget and state management |
| [lezer](packages/lezer) | Incremental GLR parser system |

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

## Development

```bash
# Install dependencies
task bootstrap

# Run tests
task test

# Analyze code
task analyze

# Format code
task format
```

## License

MIT — see [LICENSE](LICENSE)

## Credits

Based on [CodeMirror 6](https://codemirror.net/) by Marijn Haverbeke and [Lezer](https://lezer.codemirror.net/).
