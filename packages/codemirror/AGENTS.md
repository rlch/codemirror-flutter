# CodeMirror Dart Port

Pure Dart/Flutter port of CodeMirror 6. Reference JS in `ref/`.

## Commands
- `flutter test` - Run all tests

## Structure
```
lib/src/{text,state,view,commands,language}/
```
Lezer package: `../lezer/`

## Patterns
- `EditorState.create(EditorStateConfig(...))` not named params
- `state.update([TransactionSpec(...)])` for transactions
- Hide `EditorState`/`Transaction` from facet.dart imports
- Call `ensureLanguageInitialized()` before language features

## Skip
- Browser/DOM code, CSS, stream-parser (CM5 compat)