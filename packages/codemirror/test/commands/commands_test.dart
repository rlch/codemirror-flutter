import 'package:codemirror/codemirror.dart';
import 'package:test/test.dart';

void main() {
  group('Commands', () {
    group('cursor movement', () {
      test('cursorCharRight moves cursor one character right', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(0),
          ),
        );

        final result = cursorCharRight((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 1);
      });

      test('cursorCharLeft moves cursor one character left', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(3),
          ),
        );

        final result = cursorCharLeft((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 2);
      });

      test('cursorCharLeft at document start returns false', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(0),
          ),
        );

        final result = cursorCharLeft((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, false);
      });

      test('cursorCharRight at document end returns false', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(5),
          ),
        );

        final result = cursorCharRight((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, false);
      });

      test('cursorLineUp moves to previous line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2',
            selection: EditorSelection.single(8), // middle of line2
          ),
        );

        final result = cursorLineUp((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 2); // position 2 on line1
      });

      test('cursorLineDown moves to next line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2',
            selection: EditorSelection.single(2), // middle of line1
          ),
        );

        final result = cursorLineDown((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 8); // position 2 on line2
      });

      test('cursorLineStart moves to start of line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello\nworld',
            selection: EditorSelection.single(8), // middle of "world"
          ),
        );

        final result = cursorLineStart((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 6);
      });

      test('cursorLineEnd moves to end of line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello\nworld',
            selection: EditorSelection.single(6), // start of "world"
          ),
        );

        final result = cursorLineEnd((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 11);
      });

      test('cursorDocStart moves to document start', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(5),
          ),
        );

        final result = cursorDocStart((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 0);
      });

      test('cursorDocEnd moves to document end', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(0),
          ),
        );

        final result = cursorDocEnd((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 11);
      });
    });

    group('group movement', () {
      test('cursorGroupRight moves by word', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(0),
          ),
        );

        final result = cursorGroupRight((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        // Should move past "hello"
        expect(state.selection.main.head, 5);
      });

      test('cursorGroupLeft moves by word backward', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(11),
          ),
        );

        final result = cursorGroupLeft((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        // Should move to start of "world"
        expect(state.selection.main.head, 6);
      });
    });

    group('selection extension', () {
      test('selectCharRight extends selection', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(2),
          ),
        );

        final result = selectCharRight((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.anchor, 2);
        expect(state.selection.main.head, 3);
      });

      test('selectAll selects entire document', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(5),
          ),
        );

        final result = selectAll((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.anchor, 0);
        expect(state.selection.main.head, 11);
      });

      test('selectLine selects entire line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2\nline3',
            selection: EditorSelection.single(8), // middle of line2
          ),
        );

        final result = selectLine((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.from, 6);
        expect(state.selection.main.to, 12); // includes newline
      });

      test('simplifySelection collapses to cursor', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(1, 4),
          ),
        );

        final result = simplifySelection((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.empty, true);
        expect(state.selection.main.head, 4);
      });
    });

    group('deletion', () {
      test('deleteCharBackward deletes character before cursor', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(3),
          ),
        );

        final result = deleteCharBackward((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'helo');
        expect(state.selection.main.head, 2);
      });

      test('deleteCharForward deletes character after cursor', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(2),
          ),
        );

        final result = deleteCharForward((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'helo');
        expect(state.selection.main.head, 2);
      });

      test('deleteCharBackward deletes selection', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(1, 4),
          ),
        );

        final result = deleteCharBackward((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'ho');
      });

      test('deleteGroupBackward deletes word', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(5),
          ),
        );

        final result = deleteGroupBackward((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), ' world');
      });

      test('deleteGroupForward deletes word', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(6),
          ),
        );

        final result = deleteGroupForward((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hello ');
      });

      test('deleteToLineEnd deletes to end of line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(5),
          ),
        );

        final result = deleteToLineEnd((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hello');
      });

      test('deleteToLineStart deletes to start of line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(6),
          ),
        );

        final result = deleteToLineStart((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'world');
      });

      test('deleteTrailingWhitespace removes trailing spaces', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello   \nworld  ',
            selection: EditorSelection.single(0),
          ),
        );

        final result = deleteTrailingWhitespace((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hello\nworld');
      });
    });

    group('line operations', () {
      test('moveLineUp swaps lines', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2\nline3',
            selection: EditorSelection.single(8), // on line2
          ),
        );

        final result = moveLineUp((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'line2\nline1\nline3');
      });

      test('moveLineDown swaps lines', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2\nline3',
            selection: EditorSelection.single(2), // on line1
          ),
        );

        final result = moveLineDown((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'line2\nline1\nline3');
      });

      test('copyLineUp duplicates line above', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2',
            selection: EditorSelection.single(8), // on line2
          ),
        );

        final result = copyLineUp((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'line1\nline2\nline2');
      });

      test('copyLineDown duplicates line below', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2',
            selection: EditorSelection.single(2), // on line1
          ),
        );

        final result = copyLineDown((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'line1\nline1\nline2');
      });

      test('deleteLine removes current line', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'line1\nline2\nline3',
            selection: EditorSelection.single(8), // on line2
          ),
        );

        final result = deleteLine((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'line1\nline3');
      });
    });

    group('text insertion', () {
      test('insertNewline inserts newline', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.single(5),
          ),
        );

        final result = insertNewline((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hello\n world');
      });

      test('insertNewlineKeepIndent preserves indentation', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: '  hello',
            selection: EditorSelection.single(7),
          ),
        );

        final result = insertNewlineKeepIndent((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), '  hello\n  ');
      });

      test('splitLine splits without moving cursor', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(3),
          ),
        );

        final result = splitLine((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hel\nlo');
        expect(state.selection.main.head, 3);
      });

      test('transposeChars swaps adjacent characters', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(2), // between 'e' and 'l'
          ),
        );

        final result = transposeChars((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hlelo');
      });
    });

    group('indentation', () {
      test('indentMore adds indentation', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(0),
          ),
        );

        final result = indentMore((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), '  hello');
      });

      test('indentLess removes indentation', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: '  hello',
            selection: EditorSelection.single(2),
          ),
        );

        final result = indentLess((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), 'hello');
      });

      test('insertTab inserts indent unit (spaces by default)', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(5),
          ),
        );

        final result = insertTab((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        // Default indent unit is 2 spaces
        expect(state.doc.toString(), 'hello  ');
      });

      test('insertTab with selection indents lines', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(0, 5),
          ),
        );

        final result = insertTab((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.doc.toString(), '  hello');
      });
    });

    group('readOnly state', () {
      test('delete commands respect readOnly', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(3),
            extensions: readOnly.of(true),
          ),
        );

        final result = deleteCharBackward((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, false);
        expect(state.doc.toString(), 'hello'); // unchanged
      });

      test('movement commands work when readOnly', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(0),
            extensions: readOnly.of(true),
          ),
        );

        final result = cursorCharRight((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(result, true);
        expect(state.selection.main.head, 1);
      });
    });

    group('keymaps', () {
      test('standardKeymap contains expected bindings', () {
        expect(standardKeymap.length, greaterThan(10));

        // Check for common key bindings
        final keys = standardKeymap.map((b) => b.key ?? b.mac).toList();
        expect(keys, contains('ArrowLeft'));
        expect(keys, contains('ArrowRight'));
        expect(keys, contains('ArrowUp'));
        expect(keys, contains('ArrowDown'));
        expect(keys, contains('Backspace'));
        expect(keys, contains('Delete'));
        expect(keys, contains('Home'));
        expect(keys, contains('End'));
        expect(keys, contains('Mod-a'));
      });

      test('defaultKeymap includes standardKeymap bindings', () {
        expect(defaultKeymap.length, greaterThan(standardKeymap.length));
      });

      test('emacsStyleKeymap has expected bindings', () {
        final keys = emacsStyleKeymap.map((b) => b.key).toList();
        expect(keys, contains('Ctrl-a'));
        expect(keys, contains('Ctrl-e'));
        expect(keys, contains('Ctrl-f'));
        expect(keys, contains('Ctrl-b'));
        expect(keys, contains('Ctrl-n'));
        expect(keys, contains('Ctrl-p'));
      });

      test('indentWithTab binding exists', () {
        expect(indentWithTab.key, 'Tab');
        expect(indentWithTab.shift, isNotNull);
      });
    });

    group('indentation facet', () {
      test('getIndentUnit returns default value', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'hello'),
        );
        expect(getIndentUnit(state), 2);
      });

      test('getIndentUnit respects custom value', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: indentUnit.of('    '),
          ),
        );
        expect(getIndentUnit(state), 4);
      });

      test('indentString creates correct indentation', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'hello'),
        );
        expect(indentString(state, 4), '    ');
        expect(indentString(state, 2), '  ');
      });

      test('countColumn handles tabs', () {
        expect(countColumn('\t', 4), 4);
        expect(countColumn('  \t', 4), 4);
        expect(countColumn('\t\t', 4), 8);
        expect(countColumn('    ', 4), 4);
      });
    });
  });
}
