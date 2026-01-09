# CodeMirror Flutter

Pure Dart/Flutter port of CodeMirror 6 text editor.

## Commands

| Command | Purpose |
|---------|---------|
| `melos bootstrap` | Install dependencies and link packages |
| `melos run analyze` | Run static analysis |
| `melos run test` | Run all tests |
| `melos run format` | Format all code |

## Structure

```
packages/
├── codemirror/   # Main editor (text, state, view, commands, language)
└── lezer/        # Parser system (incremental parsing, grammars)
```

## Patterns

- `EditorState.create(EditorStateConfig(...))` not named params
- `state.update([TransactionSpec(...)])` for transactions
- Reference JS implementation in `ref/` directories
