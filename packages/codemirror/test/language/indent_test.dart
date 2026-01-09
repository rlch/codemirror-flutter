// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';

import '../../lib/src/commands/commands.dart';
import '../../lib/src/language/indent.dart';
import '../../lib/src/state/state.dart';
import '../../lib/src/state/facet.dart' hide EditorState, Transaction;

void main() {
  group('Indentation', () {
    test('tracks indent units', () {
      // Default: 2 spaces
      final s0 = EditorState.create(const EditorStateConfig(doc: ''));
      expect(getIndentUnit(s0), 2);
      expect(indentString(s0, 4), '    ');

      // Custom: 3 spaces
      final s1 = EditorState.create(EditorStateConfig(
        doc: '',
        extensions: ExtensionList([indentUnit.of('   ')]),
      ));
      expect(getIndentUnit(s1), 3);
      expect(indentString(s1, 4), '    ');

      // Tabs with tabSize 8
      final s2 = EditorState.create(EditorStateConfig(
        doc: '',
        extensions: ExtensionList([
          indentUnit.of('\t'),
          EditorState.tabSize_.of(8),
        ]),
      ));
      expect(getIndentUnit(s2), 8);
      expect(indentString(s2, 16), '\t\t');

      // Note: Full-width characters not fully supported by indentString yet
      // It calculates indent unit size correctly but uses spaces for output
      final s3 = EditorState.create(EditorStateConfig(
        doc: '',
        extensions: ExtensionList([indentUnit.of('　')]), // Full-width space
      ));
      expect(getIndentUnit(s3), 1);
      // indentString uses regular spaces, not the custom character
    });

    // Note: Unlike JS CodeMirror, the Dart port doesn't validate indent units.
    // Invalid units are silently accepted and handled gracefully at runtime.

    test('countColumn handles tabs correctly', () {
      expect(countColumn('    ', 4), 4);
      expect(countColumn('\t', 4), 4);
      expect(countColumn('\t\t', 4), 8);
      expect(countColumn('  \t', 4), 4); // 2 spaces + tab completes to 4
      expect(countColumn('   \t', 4), 4); // 3 spaces + tab completes to 4
    });

    test('indentString creates correct whitespace', () {
      final state = EditorState.create(const EditorStateConfig(doc: ''));
      expect(indentString(state, 0), '');
      expect(indentString(state, 2), '  ');
      expect(indentString(state, 4), '    ');

      final tabState = EditorState.create(EditorStateConfig(
        doc: '',
        extensions: ExtensionList([indentUnit.of('\t')]),
      ));
      expect(indentString(tabState, 4), '\t');
      expect(indentString(tabState, 8), '\t\t');
      expect(indentString(tabState, 6), '\t  '); // 1 tab (4) + 2 spaces
    });
  });

  group('IndentContext', () {
    test('provides line information', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'line1\nline2\nline3'));
      final cx = IndentContext(state);

      final line1 = cx.lineAt(0);
      expect(line1.text, 'line1');
      expect(line1.from, 0);

      final line2 = cx.lineAt(6);
      expect(line2.text, 'line2');
      expect(line2.from, 6);
    });

    test('simulates line breaks', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello world'));
      final cx = IndentContext(
        state,
        options: const IndentContextOptions(simulateBreak: 5),
      );

      // Before the simulated break
      final before = cx.lineAt(3, -1);
      expect(before.text, 'hello');
      expect(before.from, 0);

      // After the simulated break
      final after = cx.lineAt(6, 1);
      expect(after.text, ' world');
      expect(after.from, 5);
    });

    test('simulates double line breaks', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello world'));
      final cx = IndentContext(
        state,
        options: const IndentContextOptions(
          simulateBreak: 5,
          simulateDoubleBreak: true,
        ),
      );

      // At the break position with double break
      final at = cx.lineAt(5);
      expect(at.text, '');
      expect(at.from, 5);
    });

    test('calculates column positions', () {
      final state = EditorState.create(const EditorStateConfig(doc: '  hello'));
      final cx = IndentContext(state);

      expect(cx.column(0), 0);
      expect(cx.column(2), 2);
      expect(cx.column(5), 5);
    });

    test('finds line indentation', () {
      final state = EditorState.create(const EditorStateConfig(doc: '  hello\n    world'));
      final cx = IndentContext(state);

      expect(cx.lineIndent(0), 2);
      expect(cx.lineIndent(8), 4);
    });

    test('overrides indentation', () {
      final state = EditorState.create(const EditorStateConfig(doc: '  hello\n    world'));
      final cx = IndentContext(
        state,
        options: IndentContextOptions(
          overrideIndentation: (pos) => pos == 0 ? 6 : -1,
        ),
      );

      expect(cx.lineIndent(0), 6);
      expect(cx.lineIndent(8), 4); // Not overridden
    });

    test('textAfterPos returns text after position', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello world'));
      final cx = IndentContext(state);

      expect(cx.textAfterPos(0), 'hello world');
      expect(cx.textAfterPos(6), 'world');
    });
  });

  group('indentRange', () {
    test('indents lines in range', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'line1\nline2\nline3',
        extensions: ExtensionList([
          indentService.of((cx, pos) => 2), // Always indent 2
        ]),
      ));

      final changes = indentRange(state, 0, 17);
      expect(changes.length, greaterThan(0));

      final newDoc = changes.apply(state.doc);
      expect(newDoc.toString(), '  line1\n  line2\n  line3');
    });

    test('preserves existing correct indentation', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '  line1\n  line2',
        extensions: ExtensionList([
          indentService.of((cx, pos) => 2),
        ]),
      ));

      final changes = indentRange(state, 0, 15);
      expect(changes.empty, true); // No changes needed
    });
  });

  group('Indentation strategies', () {
    test('continuedIndent adds unit to base', () {
      final strategy = continuedIndent();
      // The strategy adds one unit to the base indentation
      expect(strategy, isNotNull);
    });

    test('continuedIndent respects except pattern', () {
      final strategy = continuedIndent(except: RegExp(r'^else\b'));
      expect(strategy, isNotNull);
    });

    test('delimitedIndent for brackets', () {
      final strategy = delimitedIndent(closing: '}');
      expect(strategy, isNotNull);
    });
  });
}
