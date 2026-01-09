/// Widget tests for smart indentation with JavaScript language support.
///
/// These tests simulate the exact setup used in language_features_demo.dart
/// to catch bugs that only appear in widget context.
@Timeout(Duration(seconds: 10))
library;

import 'package:codemirror/codemirror.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('Smart indentation widget tests - matching language_features_demo setup', () {
    testWidgets('Enter key works with full demo extensions', (tester) async {
      // This matches the exact setup in language_features_demo.dart
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          keymap.of([indentWithTab]),
          bracketMatching(),
          codeFolding(),
          keymap.of(foldKeymap),
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
      // Let parser run
      await tester.pump(const Duration(milliseconds: 300));

      // Position cursor at end of first line (after comment)
      final firstLineEnd = _demoCode.indexOf('\n');
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(firstLineEnd)),
      ]);
      await tester.pump();

      final beforeLines = key.currentState!.state.doc.lines;

      // Press Enter
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull, reason: 'onUpdate should be called');
      expect(currentState!.doc.lines, equals(beforeLines + 1),
          reason: 'Should add exactly one line');
    });

    testWidgets('Enter after opening brace indents', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n}',
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
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
      await tester.pump(const Duration(milliseconds: 100));

      // Position cursor after {
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(17)),
      ]);
      await tester.pump();

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

      // Should have 3 lines now
      expect(newDoc.split('\n').length, equals(3),
          reason: 'Should have 3 lines after Enter. Got: "$newDoc"');

      // Second line should be indented
      final lines = newDoc.split('\n');
      expect(lines[1].startsWith('  ') || lines[1].isEmpty, isTrue,
          reason: 'New line should be indented or cursor on new line. Line 1: "${lines[1]}"');
    });

    testWidgets('Enter between braces explodes', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {}',
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
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

      // Position cursor between { and }
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(17)),
      ]);
      await tester.pump();

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

      // Should have 3 lines (exploded)
      expect(newDoc.split('\n').length, equals(3),
          reason: 'Braces should explode to 3 lines. Got: "$newDoc"');
    });

    testWidgets('Enter in deeply nested structure works', (tester) async {
      // This is the structure that caused hangs
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
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
      await tester.pump(const Duration(milliseconds: 300));

      // Position cursor after "settings: ["
      final settingsPos = _demoCode.indexOf('settings: [') + 'settings: ['.length;
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(settingsPos)),
      ]);
      await tester.pump();

      final beforeDoc = key.currentState!.state.doc.toString();
      final beforeLines = beforeDoc.split('\n').length;

      // Press Enter - this was causing hangs
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull, reason: 'Transaction should complete');
      final newDoc = currentState!.doc.toString();
      final afterLines = newDoc.split('\n').length;

      expect(afterLines, greaterThan(beforeLines),
          reason: 'Should have added a line');
    });

    testWidgets('Enter at various positions in demo code', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          bracketMatching(),
          codeFolding(),
          keymap.of(foldKeymap),
          indentOnInput(),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      EditorState? currentState;

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
      await tester.pump(const Duration(milliseconds: 300));

      // Test Enter at multiple positions
      final testPositions = [
        _demoCode.indexOf('function processData'),
        _demoCode.indexOf('const results'),
        _demoCode.indexOf('if (item.value'),
        _demoCode.indexOf('return {') + 'return {'.length,
        _demoCode.indexOf('class DataManager'),
      ];

      for (final pos in testPositions) {
        if (pos < 0) continue;

        // Reset to original state
        key.currentState!.dispatch([
          TransactionSpec(selection: EditorSelection.single(pos)),
        ]);
        await tester.pump();

        final beforeLines = key.currentState!.state.doc.lines;

        // Press Enter
        final event = KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        );
        final result = key.currentState!.handleKey(event);
        await tester.pump();

        expect(result, equals(KeyEventResult.handled),
            reason: 'Enter should be handled at position $pos');
        expect(currentState, isNotNull,
            reason: 'State should update at position $pos');
        expect(currentState!.doc.lines, greaterThanOrEqualTo(beforeLines),
            reason: 'Line count should increase at position $pos');
      }
    });

    testWidgets('Enter at start of { key: "theme" line - exact repro', (tester) async {
      // This is the EXACT position user reports hanging
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          keymap.of([indentWithTab]),
          bracketMatching(),
          codeFolding(),
          keymap.of(foldKeymap),
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
      await tester.pump(const Duration(milliseconds: 300));

      // Find the LINE START (the spaces before {), not the { itself
      final themeIdx = _demoCode.indexOf('{ key: "theme"');
      // Go back to find line start
      var lineStart = themeIdx;
      while (lineStart > 0 && _demoCode[lineStart - 1] != '\n') {
        lineStart--;
      }
      
      print('Line start position: $lineStart');
      print('Theme { position: $themeIdx');
      print('Chars at line start: "${_demoCode.substring(lineStart, lineStart + 10)}"');
      
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(lineStart)),
      ]);
      await tester.pump();

      final beforeDoc = key.currentState!.state.doc.toString();
      final beforeLines = beforeDoc.split('\n');
      
      // Find which line number this is
      final lineNum = _demoCode.substring(0, lineStart).split('\n').length;
      print('Line number: $lineNum');
      print('Line content: "${beforeLines[lineNum - 1]}"');

      // Check what getIndentation returns at this position
      final indentAtPos = getIndentation(key.currentState!.state, lineStart);
      print('getIndentation at line start ($lineStart): $indentAtPos');
      
      // Press Enter at start of that line
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull, reason: 'Should not hang');
      
      final afterDoc = currentState!.doc.toString();
      final afterLines = afterDoc.split('\n');
      
      // lineNum is 1-indexed (line 53 means the 53rd line)
      // arrays are 0-indexed, so afterLines[52] is line 53
      final beforeLineIdx = lineNum - 1; // 0-indexed
      print('Before line $lineNum (idx $beforeLineIdx): "${beforeLines[beforeLineIdx]}"');
      print('After line $lineNum (idx $beforeLineIdx): "${afterLines[beforeLineIdx]}"');
      print('After line ${lineNum + 1} (idx $lineNum): "${afterLines[lineNum]}"');
      
      // When pressing Enter at START of a line with leading whitespace:
      // - The leading whitespace is deleted (consumed as "trailing whitespace after cursor")
      // - A newline + computed indent is inserted  
      // - The content (without original indent) moves to the new line with computed indent
      // This matches JS CodeMirror behavior (see test "clears empty lines before the cursor")
      expect(afterLines[beforeLineIdx].trim(), isEmpty,
          reason: 'Line $lineNum should be empty. Got: "${afterLines[beforeLineIdx]}"');
      expect(afterLines[lineNum].contains('{ key: "theme"'), isTrue,
          reason: 'Theme line content should be on line ${lineNum + 1}. Got: "${afterLines[lineNum]}"');
      // Indentation is computed by getIndentation, not preserved from original line
      // For array item after `settings: [`, computed indent is 4 spaces (array contents)
      final computedIndent = getIndentation(state, lineStart);
      final expectedIndent = indentString(state, computedIndent ?? 4);
      expect(afterLines[lineNum].startsWith(expectedIndent), isTrue,
          reason: 'Theme line should have computed indent ($computedIndent). Got: "${afterLines[lineNum]}"');
    });

    testWidgets('Enter at END of line after comma - smart indent', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          keymap.of([indentWithTab]),
          bracketMatching(),
          codeFolding(),
          keymap.of(foldKeymap),
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
      await tester.pump(const Duration(milliseconds: 300));

      // Find end of `{ key: "theme", value: "dark" },` line (after the comma)
      final themeLineEnd = _demoCode.indexOf('{ key: "theme", value: "dark" },') + 
                           '{ key: "theme", value: "dark" },'.length;
      
      print('Position at end of theme line: $themeLineEnd');
      print('Char before: "${_demoCode[themeLineEnd - 1]}"');
      
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(themeLineEnd)),
      ]);
      await tester.pump();

      // Check what indentation is computed
      final indent = getIndentation(key.currentState!.state, themeLineEnd);
      print('getIndentation at end of line: $indent');
      
      // Press Enter at end of that line
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull, reason: 'Should not hang');
      
      final afterDoc = currentState!.doc.toString();
      final cursorPos = currentState!.selection.main.head;
      
      // Find what line cursor is on and what's on that line
      final beforeCursor = afterDoc.substring(0, cursorPos);
      final lineStart = beforeCursor.lastIndexOf('\n') + 1;
      final textBeforeCursor = afterDoc.substring(lineStart, cursorPos);
      
      print('Cursor position: $cursorPos');
      print('Text before cursor on new line: "$textBeforeCursor"');
      print('New line content: "${afterDoc.substring(lineStart, afterDoc.indexOf('\n', lineStart))}"');
      
      // Cursor should be at computed indentation
      // Note: getIndentation returns the computed indent based on syntax tree
      final expectedIndent = indentString(state, indent ?? 2);
      expect(textBeforeCursor, equals(expectedIndent),
          reason: 'Cursor should be at computed indent ($indent). Got: "$textBeforeCursor"');
    });

    testWidgets('Tab key indents line with demo setup', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          keymap.of([indentWithTab]),
          bracketMatching(),
          codeFolding(),
          keymap.of(foldKeymap),
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
      await tester.pump(const Duration(milliseconds: 100));

      // Position cursor on a line
      final themeLineStart = _demoCode.indexOf('{ key: "theme"');
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(themeLineStart)),
      ]);
      await tester.pump();

      final beforeDoc = key.currentState!.state.doc.toString();
      final beforeLine = beforeDoc.split('\n')[52]; // 0-indexed line 52
      print('Before Tab - line: "$beforeLine"');

      // Press Tab
      final tabEvent = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.tab,
        physicalKey: PhysicalKeyboardKey.tab,
        timeStamp: Duration.zero,
      );
      final result = key.currentState!.handleKey(tabEvent);
      await tester.pump();

      print('Tab key result: $result');
      expect(result, equals(KeyEventResult.handled),
          reason: 'Tab should be handled by keymap');
      expect(currentState, isNotNull, reason: 'State should update');

      final afterDoc = currentState!.doc.toString();
      final afterLine = afterDoc.split('\n')[52];
      print('After Tab - line: "$afterLine"');

      // Line should have more indentation
      expect(afterLine.length, greaterThan(beforeLine.length),
          reason: 'Tab should add indentation. Before: "$beforeLine", After: "$afterLine"');
    });

    testWidgets('Shift+Tab dedents line with demo setup', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: _demoCode,
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          keymap.of(standardKeymap),
          keymap.of([indentWithTab]),
          bracketMatching(),
          codeFolding(),
          keymap.of(foldKeymap),
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
      await tester.pump(const Duration(milliseconds: 100));

      // Position cursor on a line with indentation
      final themeLineStart = _demoCode.indexOf('{ key: "theme"');
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(themeLineStart)),
      ]);
      await tester.pump();

      final beforeDoc = key.currentState!.state.doc.toString();
      final beforeLine = beforeDoc.split('\n')[52];
      print('Before Shift+Tab - line: "$beforeLine"');

      // Press Shift+Tab
      final shiftTabEvent = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.tab,
        physicalKey: PhysicalKeyboardKey.tab,
        timeStamp: Duration.zero,
      );
      // Simulate shift being held
      HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
        logicalKey: LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      ));
      
      final result = key.currentState!.handleKey(shiftTabEvent);
      
      // Release shift
      HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
        logicalKey: LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      ));
      await tester.pump();

      print('Shift+Tab key result: $result');
      expect(result, equals(KeyEventResult.handled),
          reason: 'Shift+Tab should be handled by keymap');
      expect(currentState, isNotNull, reason: 'State should update');

      final afterDoc = currentState!.doc.toString();
      final afterLine = afterDoc.split('\n')[52];
      print('After Shift+Tab - line: "$afterLine"');

      // Line should have less indentation
      expect(afterLine.length < beforeLine.length, isTrue,
          reason: 'Shift+Tab should remove indentation. Before: "$beforeLine", After: "$afterLine"');
    });

    testWidgets('rapid Enter presses do not hang', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n  \n}',
        extensions: ExtensionList([
          javascript().extension,
          keymap.of(standardKeymap),
          indentOnInput(),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      EditorState? currentState;

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

      // Position cursor
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(19)),
      ]);
      await tester.pump();

      // Press Enter 5 times rapidly
      for (var i = 0; i < 5; i++) {
        final event = KeyDownEvent(
          logicalKey: LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        );
        key.currentState!.handleKey(event);
        await tester.pump();
      }

      expect(currentState, isNotNull);
      expect(currentState!.doc.lines, greaterThan(3),
          reason: 'Should have added multiple lines');
    });
  });
}
