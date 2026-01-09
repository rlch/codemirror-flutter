import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart';

const _demoCode = '''// JavaScript Example with nested structures
function processData(items) {
  const results = items.map((item) => {
    if (item.value > 10) {
      return {
        id: item.id,
        processed: true,
        data: {
          original: item.value,
          doubled: item.value * 2,
          metadata: {
            timestamp: Date.now(),
            source: "processor"
          }
        }
      };
    }
    return { id: item.id, processed: false };
  });
  
  return results.filter((r) => r.processed);
}

class DataManager {
  constructor(config) {
    this.config = config;
    this.cache = new Map();
  }

  async fetchAll(ids) {
    const promises = ids.map((id) => {
      if (this.cache.has(id)) {
        return Promise.resolve(this.cache.get(id));
      }
      return this.fetch(id);
    });
    return Promise.all(promises);
  }

  fetch(id) {
    return fetch(`/api/data/` + id)
      .then((response) => response.json())
      .then((data) => {
        this.cache.set(id, data);
        return data;
      });
  }
}

// Array with nested brackets
const config = {
  settings: [
    { key: "theme", value: "dark" },
    { key: "fontSize", value: 14 },
    { key: "tabSize", value: 2 }
  ],
  features: {
    autoSave: true,
    linting: ["eslint", "prettier"]
  }
};
''';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  testWidgets('insertNewlineAndIndent in EditorView with FULL demo code', (tester) async {
    final state = EditorState.create(EditorStateConfig(
      doc: _demoCode,
      extensions: ExtensionList([
        javascript().extension,
        keymap.of(standardKeymap),
        indentOnInput(),
      ]),
    ));

    EditorState? currentState;
    final key = GlobalKey<EditorViewState>();
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorView(
            key: key,
            state: state,
            autofocus: true,
            onUpdate: (update) => currentState = update.state,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200)); // Let parser run

    // Find "settings: [" and position after it
    final settingsPos = _demoCode.indexOf('settings: [') + 'settings: ['.length;
    print('Positioning cursor at $settingsPos');
    
    key.currentState!.dispatch([
      TransactionSpec(selection: EditorSelection.single(settingsPos)),
    ]);
    await tester.pump();

    print('Pressing Enter...');
    // Press Enter
    final event = KeyDownEvent(
      logicalKey: LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );
    key.currentState!.handleKey(event);
    await tester.pump();

    print('Done, checking result');
    expect(currentState, isNotNull);
    final newDoc = currentState!.doc.toString();
    expect(newDoc.length, greaterThan(_demoCode.length));
  });

  test('insertNewlineAndIndent with FULL demo code after settings: [', () {
    final state = EditorState.create(EditorStateConfig(
      doc: _demoCode,
      extensions: ExtensionList([
        javascript().extension,
      ]),
    ));

    // Find "settings: [" and position after it
    final settingsPos = _demoCode.indexOf('settings: [') + 'settings: ['.length;
    print('Position: $settingsPos, char before: "${_demoCode[settingsPos-1]}"');
    
    final stateWithSelection = state.update([
      TransactionSpec(selection: EditorSelection.single(settingsPos)),
    ]).state as EditorState;

    Transaction? result;
    final target = (
      state: stateWithSelection,
      dispatch: (Transaction tr) {
        result = tr;
        print('Dispatched transaction');
      },
    );
    
    print('Calling insertNewlineAndIndent...');
    final handled = insertNewlineAndIndent(target);
    print('Done: handled=$handled');
    
    expect(handled, isTrue);
    expect(result, isNotNull);
  });

  test('insertNewlineAndIndent after [ does not hang', () {
    final state = EditorState.create(EditorStateConfig(
      doc: '''const config = {
  settings: [
    { key: "theme", value: "dark" },
  ],
};''',
      selection: EditorSelection.single(29), // After the [
      extensions: ExtensionList([
        javascript().extension,
      ]),
    ));

    Transaction? result;
    final target = (
      state: state,
      dispatch: (Transaction tr) {
        result = tr;
      },
    );
    
    // This should complete quickly, not hang
    final handled = insertNewlineAndIndent(target);
    
    expect(handled, isTrue);
    expect(result, isNotNull);
    expect(result!.newDoc.length, greaterThan(state.doc.length));
  });

  test('getIndentation does not hang', () {
    final state = EditorState.create(EditorStateConfig(
      doc: '''const config = {
  settings: [
    { key: "theme", value: "dark" },
  ],
};''',
      extensions: ExtensionList([
        javascript().extension,
      ]),
    ));

    // Test getIndentation at position 29 (after [)
    final indent = getIndentation(state, 29);
    print('Indent at 29: $indent');
    // Should complete without hanging
  });

  testWidgets('Enter key in EditorView with standardKeymap does not hang', (tester) async {
    final state = EditorState.create(EditorStateConfig(
      doc: '''const config = {
  settings: [
    { key: "theme", value: "dark" },
  ],
};''',
      extensions: ExtensionList([
        javascript().extension,
        keymap.of(standardKeymap),
      ]),
    ));

    EditorState? currentState;
    final key = GlobalKey<EditorViewState>();
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorView(
            key: key,
            state: state,
            autofocus: true,
            onUpdate: (update) => currentState = update.state,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Find the actual position after [
    final doc = state.doc.toString();
    final bracketPos = doc.indexOf('settings: [') + 'settings: ['.length;
    print('Bracket position: $bracketPos, char before: "${doc[bracketPos-1]}", char at: "${bracketPos < doc.length ? doc[bracketPos] : "EOF"}"');
    
    // Position cursor after [
    key.currentState!.dispatch([
      TransactionSpec(selection: EditorSelection.single(bracketPos)),
    ]);
    await tester.pump();
    
    print('Cursor at: ${key.currentState!.state.selection.main.head}');

    // Press Enter
    final event = KeyDownEvent(
      logicalKey: LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );
    key.currentState!.handleKey(event);
    await tester.pump();

    expect(currentState, isNotNull);
    final newDoc = currentState!.doc.toString();
    print('New doc:\n$newDoc');
    
    // Should have added a newline
    expect(newDoc.split('\n').length, greaterThan(5));
  });
}
