import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/src/autocomplete/snippet.dart';
import 'package:codemirror/src/commands/commands.dart' show indentUnit;
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/selection.dart';
import 'package:codemirror/src/state/change.dart';
import 'package:codemirror/src/state/transaction.dart' hide EditorStateRef, Transaction;

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureSnippetInitialized();
  });

  group('Snippet.parse', () {
    test('parses simple placeholder', () {
      final snippet = Snippet.parse('hello \${}');
      expect(snippet.lines, ['hello ']);
      expect(snippet.fieldPositions.length, 1);
      expect(snippet.fieldPositions[0].from, 6);
      expect(snippet.fieldPositions[0].to, 6);
    });

    test('parses named placeholder', () {
      final snippet = Snippet.parse('hello \${name}');
      expect(snippet.lines, ['hello name']);
      expect(snippet.fieldPositions.length, 1);
      expect(snippet.fieldPositions[0].from, 6);
      expect(snippet.fieldPositions[0].to, 10);
    });

    test('parses numbered placeholder', () {
      final snippet = Snippet.parse('hello \${1}');
      expect(snippet.lines, ['hello ']);
      expect(snippet.fieldPositions.length, 1);
      expect(snippet.fieldPositions[0].field, 0);
    });

    test('parses numbered placeholder with default', () {
      final snippet = Snippet.parse('hello \${1:world}');
      expect(snippet.lines, ['hello world']);
      expect(snippet.fieldPositions.length, 1);
      expect(snippet.fieldPositions[0].from, 6);
      expect(snippet.fieldPositions[0].to, 11);
    });

    test('parses multiple placeholders on same line', () {
      final snippet = Snippet.parse('\${1:first} and \${2:second}');
      expect(snippet.lines, ['first and second']);
      expect(snippet.fieldPositions.length, 2);
      expect(snippet.fieldPositions[0].from, 0);
      expect(snippet.fieldPositions[0].to, 5);
      expect(snippet.fieldPositions[1].from, 10);
      expect(snippet.fieldPositions[1].to, 16);
    });

    test('parses placeholders across multiple lines', () {
      final snippet = Snippet.parse('line1 \${1:a}\nline2 \${2:b}');
      expect(snippet.lines, ['line1 a', 'line2 b']);
      expect(snippet.fieldPositions.length, 2);
      expect(snippet.fieldPositions[0].line, 0);
      expect(snippet.fieldPositions[1].line, 1);
    });

    test('parses escaped braces', () {
      final snippet = Snippet.parse('hello \\{world\\}');
      expect(snippet.lines, ['hello {world}']);
    });

    test('parses hash syntax', () {
      final snippet = Snippet.parse('hello #{name}');
      expect(snippet.lines, ['hello name']);
      expect(snippet.fieldPositions.length, 1);
    });

    test('links same numbered placeholders', () {
      final snippet = Snippet.parse('\${1:first} and \${1}');
      expect(snippet.fieldPositions.length, 2);
      expect(snippet.fieldPositions[0].field, snippet.fieldPositions[1].field);
    });

    test('orders numbered before unnumbered', () {
      final snippet = Snippet.parse('\${1:one} \${} \${2:two} \${}');
      expect(snippet.fieldPositions.length, 4);
      final fields = snippet.fieldPositions.map((p) => p.field).toList();
      expect(fields.toSet().length, 4);
    });

    test('orders numbered placeholders correctly', () {
      final snippet = Snippet.parse('\${3:third} \${1:first} \${2:second}');
      expect(snippet.fieldPositions.length, 3);
      final thirdPos = snippet.fieldPositions.firstWhere((p) => p.from == 0);
      final firstPos = snippet.fieldPositions.firstWhere((p) => p.from == 6);
      final secondPos = snippet.fieldPositions.firstWhere((p) => p.from == 12);
      expect(firstPos.field, lessThan(secondPos.field));
      expect(secondPos.field, lessThan(thirdPos.field));
    });
  });

  group('Snippet.instantiate', () {
    test('instantiates single line snippet', () {
      final snippet = Snippet.parse('hello \${name}');
      final state = EditorState.create(EditorStateConfig(doc: 'prefix'));
      final result = snippet.instantiate(state, 6);
      expect(result.text, ['hello name']);
      expect(result.ranges.length, 1);
      expect(result.ranges[0].from, 12);
      expect(result.ranges[0].to, 16);
    });

    test('instantiates multi-line snippet with indentation', () {
      final snippet = Snippet.parse('if (\${1}) {\n\t\${2}\n}');
      final state = EditorState.create(EditorStateConfig(
        doc: '  ',
        extensions: indentUnit.of('  '),
      ));
      final result = snippet.instantiate(state, 2);
      expect(result.text.length, 3);
      expect(result.text[0], 'if () {');
      expect(result.text[1], '    ');
      expect(result.text[2], '  }');
    });

    test('expands tabs based on indentUnit', () {
      final snippet = Snippet.parse('line1\n\tline2\n\t\tline3');
      final state = EditorState.create(EditorStateConfig(
        doc: '',
        extensions: indentUnit.of('    '),
      ));
      final result = snippet.instantiate(state, 0);
      expect(result.text[1], '    line2');
      expect(result.text[2], '        line3');
    });

    test('preserves base indentation', () {
      final snippet = Snippet.parse('one\ntwo');
      final state = EditorState.create(EditorStateConfig(doc: '    prefix'));
      final result = snippet.instantiate(state, 10);
      expect(result.text[0], 'one');
      expect(result.text[1], '    two');
    });

    test('returns correct text and ranges', () {
      final snippet = Snippet.parse('\${1:foo} \${2:bar}');
      final state = EditorState.create(EditorStateConfig(doc: ''));
      final result = snippet.instantiate(state, 0);
      expect(result.text, ['foo bar']);
      expect(result.ranges.length, 2);
      expect(result.ranges[0].field, 0);
      expect(result.ranges[1].field, 1);
    });
  });

  group('FieldRange', () {
    test('maps positions through ChangeDesc', () {
      final range = FieldRange(0, 5, 10);
      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'}
      ], 20, null);
      final mapped = range.map(changes);
      expect(mapped, isNotNull);
      expect(mapped!.from, 8);
      expect(mapped.to, 13);
      expect(mapped.field, 0);
    });

    test('returns null when range is deleted', () {
      final range = FieldRange(0, 5, 10);
      final changes = ChangeSet.of([
        {'from': 4, 'to': 12}
      ], 20, null);
      final mapped = range.map(changes);
      expect(mapped, isNull);
    });

    test('preserves field index on map', () {
      final range = FieldRange(3, 10, 20);
      final changes = ChangeSet.of([
        {'from': 25, 'insert': 'x'}
      ], 30, null);
      final mapped = range.map(changes);
      expect(mapped!.field, 3);
    });
  });

  group('ActiveSnippet', () {
    test('tracks active field', () {
      final ranges = [
        FieldRange(0, 0, 5),
        FieldRange(1, 10, 15),
      ];
      final active = ActiveSnippet(ranges, 0);
      expect(active.active, 0);
      expect(active.ranges.length, 2);
    });

    test('creates decorations for ranges', () {
      final ranges = [
        FieldRange(0, 0, 5),
        FieldRange(0, 10, 10),
      ];
      final active = ActiveSnippet(ranges, 0);
      expect(active.deco, isNotNull);
    });

    test('maps through changes', () {
      final ranges = [
        FieldRange(0, 5, 10),
        FieldRange(1, 15, 20),
      ];
      final active = ActiveSnippet(ranges, 0);
      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'}
      ], 25, null);
      final mapped = active.map(changes);
      expect(mapped, isNotNull);
      expect(mapped!.ranges[0].from, 8);
      expect(mapped.ranges[0].to, 13);
      expect(mapped.active, 0);
    });

    test('map returns null when range deleted', () {
      final ranges = [
        FieldRange(0, 5, 10),
      ];
      final active = ActiveSnippet(ranges, 0);
      final changes = ChangeSet.of([
        {'from': 4, 'to': 12}
      ], 20, null);
      final mapped = active.map(changes);
      expect(mapped, isNull);
    });

    test('selectionInsideField returns true for contained selection', () {
      final ranges = [
        FieldRange(0, 5, 10),
        FieldRange(1, 15, 20),
      ];
      final active = ActiveSnippet(ranges, 0);
      final sel = EditorSelection.create([EditorSelection.range(6, 8)]);
      expect(active.selectionInsideField(sel), true);
    });

    test('selectionInsideField returns false for outside selection', () {
      final ranges = [
        FieldRange(0, 5, 10),
        FieldRange(1, 15, 20),
      ];
      final active = ActiveSnippet(ranges, 0);
      final sel = EditorSelection.create([EditorSelection.cursor(12)]);
      expect(active.selectionInsideField(sel), false);
    });

    test('selectionInsideField checks active field only', () {
      final ranges = [
        FieldRange(0, 5, 10),
        FieldRange(1, 15, 20),
      ];
      final active = ActiveSnippet(ranges, 0);
      final sel = EditorSelection.create([EditorSelection.range(16, 18)]);
      expect(active.selectionInsideField(sel), false);
    });
  });

  group('snippet function', () {
    test('returns apply function', () {
      final apply = snippet('hello \${name}');
      expect(apply, isA<SnippetApplyFn>());
    });

    test('apply function inserts text', () {
      final apply = snippet('hello world');
      var state = EditorState.create(EditorStateConfig(
        doc: 'prefix',
        selection: EditorSelection.single(6),
      ));

      apply(
        (
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ),
        null,
        6,
        6,
      );

      expect(state.doc.toString(), 'prefixhello world');
    });

    test('apply function replaces from-to range', () {
      final apply = snippet('replacement');
      var state = EditorState.create(EditorStateConfig(
        doc: 'hello world',
        selection: EditorSelection.single(6, 11),
      ));

      apply(
        (
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ),
        null,
        6,
        11,
      );

      expect(state.doc.toString(), 'hello replacement');
    });

    test('apply function sets up field navigation', () {
      final apply = snippet('\${1:first} \${2:second}');
      var state = EditorState.create(EditorStateConfig(doc: ''));

      apply(
        (
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ),
        null,
        0,
        0,
      );

      expect(state.doc.toString(), 'first second');
      expect(state.selection.main.from, 0);
      expect(state.selection.main.to, 5);
    });
  });

  group('field navigation', () {
    EditorState setupSnippetState() {
      final apply = snippet('\${1:one} \${2:two} \${3:three}');
      var state = EditorState.create(EditorStateConfig(doc: ''));
      apply(
        (
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ),
        null,
        0,
        0,
      );
      return state;
    }

    test('nextSnippetField moves to next field', () {
      var state = setupSnippetState();
      expect(state.selection.main.from, 0);
      expect(state.selection.main.to, 3);

      final result = nextSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));

      expect(result, true);
      expect(state.selection.main.from, 4);
      expect(state.selection.main.to, 7);
    });

    test('prevSnippetField moves to previous field', () {
      var state = setupSnippetState();
      nextSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));
      expect(state.selection.main.from, 4);

      final result = prevSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));

      expect(result, true);
      expect(state.selection.main.from, 0);
      expect(state.selection.main.to, 3);
    });

    test('prevSnippetField returns false at first field', () {
      var state = setupSnippetState();
      expect(state.selection.main.from, 0);

      final result = prevSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));

      expect(result, false);
    });

    test('clearSnippet clears snippet state', () {
      var state = setupSnippetState();
      expect(state.field(snippetState, false), isNotNull);

      final result = clearSnippet((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));

      expect(result, true);
      expect(state.field(snippetState, false), isNull);
    });

    test('clearSnippet returns false when no snippet', () {
      var state = EditorState.create(EditorStateConfig(doc: 'hello'));

      final result = clearSnippet((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));

      expect(result, false);
    });

    test('hasNextSnippetField returns true when has next', () {
      var state = setupSnippetState();
      expect(hasNextSnippetField(state), true);
    });

    test('hasNextSnippetField returns false at last field', () {
      var state = setupSnippetState();
      nextSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));
      nextSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));
      expect(hasNextSnippetField(state), false);
    });

    test('hasPrevSnippetField returns true when has prev', () {
      var state = setupSnippetState();
      nextSnippetField((
        state: state,
        dispatch: (tr) => state = tr.state as EditorState,
      ));
      expect(hasPrevSnippetField(state), true);
    });

    test('hasPrevSnippetField returns false at first field', () {
      var state = setupSnippetState();
      expect(hasPrevSnippetField(state), false);
    });

    test('hasNextSnippetField returns false when no snippet', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      expect(hasNextSnippetField(state), false);
    });

    test('hasPrevSnippetField returns false when no snippet', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      expect(hasPrevSnippetField(state), false);
    });
  });

  group('snippetCompletion', () {
    test('creates completion record', () {
      final completion = snippetCompletion(
        'for (\${1:i} = 0; \${1}; \${1}++) {\n\t\${2}\n}',
        'for',
        detail: 'For loop',
        info: 'A basic for loop',
      );

      expect(completion.label, 'for');
      expect(completion.detail, 'For loop');
      expect(completion.info, 'A basic for loop');
      expect(completion.apply, isA<SnippetApplyFn>());
    });

    test('creates completion without optional fields', () {
      final completion = snippetCompletion('console.log(\${})', 'log');

      expect(completion.label, 'log');
      expect(completion.detail, isNull);
      expect(completion.info, isNull);
    });
  });

  group('snippet edge cases', () {
    test('handles empty template', () {
      final snippet = Snippet.parse('');
      expect(snippet.lines, ['']);
      expect(snippet.fieldPositions, isEmpty);
    });

    test('handles template with only placeholder', () {
      final snippet = Snippet.parse('\${}');
      expect(snippet.lines, ['']);
      expect(snippet.fieldPositions.length, 1);
    });

    test('handles multiple same-named placeholders', () {
      final snippet = Snippet.parse('\${name} loves \${name}');
      expect(snippet.lines, ['name loves name']);
      expect(snippet.fieldPositions.length, 2);
      expect(snippet.fieldPositions[0].field, snippet.fieldPositions[1].field);
    });

    test('handles complex nested template', () {
      final snippet = Snippet.parse('function \${1:name}(\${2:params}) {\n\t\${3:body}\n}');
      expect(snippet.lines.length, 3);
      expect(snippet.fieldPositions.length, 3);
    });

    test('handles CRLF line endings', () {
      final snippet = Snippet.parse('line1\r\nline2');
      expect(snippet.lines, ['line1', 'line2']);
    });

    test('handles CR line endings', () {
      final snippet = Snippet.parse('line1\rline2');
      expect(snippet.lines, ['line1', 'line2']);
    });

    test('snippet clears on selection outside field', () {
      final apply = snippet('\${1:one} \${2:two}');
      var state = EditorState.create(EditorStateConfig(doc: ''));
      apply(
        (
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ),
        null,
        0,
        0,
      );
      expect(state.field(snippetState, false), isNotNull);

      state = state.update([
        TransactionSpec(selection: EditorSelection.single(state.doc.length)),
      ]).state as EditorState;

      expect(state.field(snippetState, false), isNull);
    });
  });
}
