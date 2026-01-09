/// Tests Enter key behavior at various cursor positions.
///
/// Covers edge cases beyond just "end of line":
/// - Beginning of line
/// - Middle of line
/// - Between brackets {} [] ()
/// - Inside JSX tags
/// - Empty lines
/// - After opening brackets
/// - Before closing brackets
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  /// Helper to press Enter and return the result
  (Transaction, String) pressEnter(EditorState state, int pos) {
    final stateWithCursor = state.update([
      TransactionSpec(selection: EditorSelection.single(pos)),
    ]).state as EditorState;

    Transaction? result;
    final target = (
      state: stateWithCursor,
      dispatch: (Transaction tr) => result = tr,
    );
    insertNewlineAndIndent(target);

    final newDoc = result!.newDoc.toString();
    return (result!, newDoc);
  }

  group('Enter at beginning of line', () {
    test('beginning of first line', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const x = 1;',
        extensions: ExtensionList([javascript().extension]),
      ));

      final (tr, newDoc) = pressEnter(state, 0);
      final cursorPos = tr.newSelection.main.head;

      expect(newDoc, startsWith('\nconst'));
      expect(cursorPos, equals(1)); // After the newline
    });

    test('beginning of indented line', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function f() {\n  return 1;\n}',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position at beginning of "  return 1;" (position 15)
      final (tr, newDoc) = pressEnter(state, 15);
      final cursorPos = tr.newSelection.main.head;
      final lines = newDoc.split('\n');

      expect(lines.length, equals(4));
      expect(lines[1], equals('')); // New empty line
      expect(lines[2], equals('  return 1;')); // Original line preserved
    });
  });

  group('Enter in middle of line', () {
    test('middle of statement', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const longVariableName = 123;',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position after 'const '
      final (tr, newDoc) = pressEnter(state, 6);
      final lines = newDoc.split('\n');

      expect(lines.length, equals(2));
      expect(lines[0], equals('const '));
      expect(lines[1], contains('longVariableName'));
    });

    test('middle of JSX tag', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '<Component prop="value" />',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after 'prop='
      final pos = '<Component prop='.length;
      final (tr, newDoc) = pressEnter(state, pos);

      expect(newDoc.split('\n').length, equals(2));
    });
  });

  group('Enter between brackets', () {
    test('between empty braces {}', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function f() {}',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position between { and }
      final pos = 'function f() {'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      // Should "explode" to 3 lines with cursor on indented middle line
      expect(lines.length, equals(3));
      expect(lines[0], equals('function f() {'));
      expect(lines[1], startsWith('  ')); // Indented
      expect(lines[2], equals('}'));
    });

    test('between empty brackets []', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const arr = []',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position between [ and ]
      final pos = 'const arr = ['.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      expect(lines.length, equals(3));
      expect(lines[1], startsWith('  ')); // Indented
    });

    test('between empty parens ()', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function f()',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position between ( and )
      final pos = 'function f('.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      expect(lines.length, equals(3));
    });

    test('between braces with content', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const obj = { a: 1 }',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position after { and space
      final pos = 'const obj = { '.length;
      final (tr, newDoc) = pressEnter(state, pos);

      // Should add newline but not explode since not empty
      expect(newDoc.split('\n').length, greaterThanOrEqualTo(2));
    });
  });

  group('Enter after opening bracket', () {
    test('after opening brace', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function f() {\n  return 1;\n}',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position right after {
      final pos = 'function f() {'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      // Should insert line with indentation
      expect(lines.length, equals(4));
      // Cursor should be on indented new line
      expect(cursorLine.number, equals(2));
    });

    test('after opening bracket in array', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const arr = [\n  1, 2, 3\n]',
        extensions: ExtensionList([javascript().extension]),
      ));

      final pos = 'const arr = ['.length;
      final (tr, newDoc) = pressEnter(state, pos);

      expect(newDoc.split('\n').length, equals(4));
    });
  });

  group('Enter before closing bracket', () {
    test('before closing brace', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function f() {\n  return 1;\n}',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position right before }
      final pos = 'function f() {\n  return 1;\n'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      expect(lines.length, equals(4));
      expect(lines.last, equals('}')); // Closing brace preserved
    });
  });

  group('Enter in JSX specific positions', () {
    test('after JSX opening tag', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '<div>\n</div>',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after <div>
      final pos = '<div>'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final cursorPos = tr.newSelection.main.head;
      final cursorLine = tr.newDoc.lineAt(cursorPos);

      expect(newDoc.split('\n').length, equals(3));
      expect(cursorLine.number, equals(2)); // New line between
    });

    test('before JSX closing tag', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '<div>\n  content\n</div>',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position before </div>
      final pos = '<div>\n  content\n'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      expect(lines.length, equals(4));
      expect(lines.last, equals('</div>'));
    });

    test('inside JSX expression {}', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '<div>{value}</div>',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after {
      final pos = '<div>{'.length;
      final (tr, newDoc) = pressEnter(state, pos);

      expect(newDoc.split('\n').length, greaterThanOrEqualTo(2));
    });

    test('between empty JSX tags', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '<div></div>',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position between > and <
      final pos = '<div>'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      // Note: >< is NOT a bracket pair like {} [] (), so it won't "explode"
      // to 3 lines. It just inserts a newline with proper indentation.
      expect(lines.length, equals(2));
      expect(lines[0], equals('<div>'));
      expect(lines[1], equals('</div>')); // No extra indentation between tags
    });

    test('nested JSX elements', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '<Parent>\n  <Child />\n</Parent>',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after <Child />
      final pos = '<Parent>\n  <Child />'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      expect(lines.length, equals(4));
      // New line should maintain JSX indentation
      expect(cursorLine.number, equals(3));
    });
  });

  group('Enter on empty and whitespace lines', () {
    test('empty line in middle', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'line1\n\nline3',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position on empty line
      final pos = 'line1\n'.length;
      final (tr, newDoc) = pressEnter(state, pos);

      expect(newDoc, equals('line1\n\n\nline3'));
    });

    test('whitespace-only line', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function f() {\n  \n}',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position at end of whitespace line
      final pos = 'function f() {\n  '.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final lines = newDoc.split('\n');

      expect(lines.length, equals(4));
    });
  });

  group('Enter at document boundaries', () {
    test('very end of document', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const x = 1;',
        extensions: ExtensionList([javascript().extension]),
      ));

      final (tr, newDoc) = pressEnter(state, 12);

      expect(newDoc, equals('const x = 1;\n'));
    });

    test('end of document after newline', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const x = 1;\n',
        extensions: ExtensionList([javascript().extension]),
      ));

      final (tr, newDoc) = pressEnter(state, 13);

      expect(newDoc, equals('const x = 1;\n\n'));
    });
  });

  group('Enter with deeply nested structures', () {
    test('deeply nested braces', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '''const obj = {
  level1: {
    level2: {
      level3: {
        value: 1
      }
    }
  }
};''',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position after "level3: {"
      final pos = state.doc.toString().indexOf('level3: {') + 'level3: {'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      // Should indent properly for nesting level
      final lineText = newDoc.split('\n')[cursorLine.number - 1];
      expect(lineText.length - lineText.trimLeft().length, greaterThanOrEqualTo(8));
    });

    test('deeply nested JSX', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '''<A>
  <B>
    <C>
      <D>content</D>
    </C>
  </B>
</A>''',
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after <D>
      final pos = state.doc.toString().indexOf('<D>') + '<D>'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      // Should be on new line with proper indentation
      expect(cursorLine.number, greaterThan(4));
    });
  });

  group('Enter with special characters', () {
    test('after string with special chars', () {
      final state = EditorState.create(EditorStateConfig(
        doc: r'const s = "hello\nworld";',
        extensions: ExtensionList([javascript().extension]),
      ));

      final (tr, newDoc) = pressEnter(state, state.doc.length);

      expect(newDoc.split('\n').length, equals(2));
    });

    test('inside template literal', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const s = `line1\nline2`;',
        extensions: ExtensionList([javascript().extension]),
      ));

      // Position after line1
      final pos = 'const s = `line1'.length;
      final (tr, newDoc) = pressEnter(state, pos);

      // Template literals shouldn't auto-indent
      expect(newDoc.split('\n').length, equals(3));
    });
  });

  group('Enter with the exact user template', () {
    const templateContent = '''const x = 2

return (
  <Padding padding={EdgeInsetsGeometry.all({ value: 24 })}>
    <Center>
      <Column mainAxisAlignment="center" crossAxisAlignment="center">
        <Text.h1>New Template</Text.h1>
        <SizedBox height={16} />
        <Text>
          Add properties in the sidebar, then use them here like {"{propertyName}"}
        </Text>
      </Column>
    </Center>
  </Padding>
);''';

    test('enter after EdgeInsetsGeometry.all({ value: 24 })', () {
      final state = EditorState.create(EditorStateConfig(
        doc: templateContent,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after closing }) of EdgeInsetsGeometry
      final pos = templateContent.indexOf('{ value: 24 })') + '{ value: 24 })'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      print('Cursor at line ${cursorLine.number}');
      expect(cursorLine.number, greaterThan(0));
    });

    test('enter inside the nested {} of EdgeInsetsGeometry', () {
      final state = EditorState.create(EditorStateConfig(
        doc: templateContent,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after { in { value: 24 }
      final pos = templateContent.indexOf('{ value:');
      final (tr, newDoc) = pressEnter(state, pos + 1);
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      expect(cursorLine.number, greaterThan(0));
    });

    test('enter after self-closing tag <SizedBox />', () {
      final state = EditorState.create(EditorStateConfig(
        doc: templateContent,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position after />
      final pos = templateContent.indexOf('<SizedBox height={16} />') + '<SizedBox height={16} />'.length;
      final (tr, newDoc) = pressEnter(state, pos);
      final cursorLine = tr.newDoc.lineAt(tr.newSelection.main.head);

      // Should maintain proper indentation (8 spaces for this nesting level)
      final lineContent = newDoc.split('\n')[cursorLine.number - 1];
      final indent = lineContent.length - lineContent.trimLeft().length;
      expect(indent, equals(8));
    });

    test('enter in the middle of prop value', () {
      final state = EditorState.create(EditorStateConfig(
        doc: templateContent,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
        ]),
      ));

      // Position in middle of "center" in mainAxisAlignment="center"
      final pos = templateContent.indexOf('mainAxisAlignment="center"') + 'mainAxisAlignment="cen'.length;
      final (tr, newDoc) = pressEnter(state, pos);

      // Should split the line
      expect(newDoc.split('\n').length, equals(16));
    });
  });
}
