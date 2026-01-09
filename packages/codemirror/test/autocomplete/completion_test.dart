// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';

import '../../lib/src/autocomplete/completion.dart';
import '../../lib/src/state/state.dart';
import '../../lib/src/state/selection.dart';
import '../../lib/src/state/transaction.dart';

void main() {
  ensureStateInitialized();

  group('Completion', () {
    test('creates with required label', () {
      const completion = Completion(label: 'test');
      expect(completion.label, 'test');
      expect(completion.displayLabel, isNull);
      expect(completion.detail, isNull);
      expect(completion.type, isNull);
      expect(completion.boost, isNull);
    });

    test('creates with all optional fields', () {
      const completion = Completion(
        label: 'myFunction',
        displayLabel: 'myFunction()',
        sortText: 'zzz',
        detail: 'A helper function',
        info: 'Extended documentation',
        type: 'function',
        commitCharacters: ['(', '.'],
        boost: 10,
        section: 'Functions',
      );
      expect(completion.label, 'myFunction');
      expect(completion.displayLabel, 'myFunction()');
      expect(completion.sortText, 'zzz');
      expect(completion.detail, 'A helper function');
      expect(completion.info, 'Extended documentation');
      expect(completion.type, 'function');
      expect(completion.commitCharacters, ['(', '.']);
      expect(completion.boost, 10);
      expect(completion.section, 'Functions');
    });
  });

  group('CompletionContext', () {
    test('matchBefore with matching regex', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello world'),
      );
      final context = CompletionContext(
        state: state,
        pos: 11,
        explicit: false,
      );

      final match = context.matchBefore(RegExp(r'\w+'));
      expect(match, isNotNull);
      expect(match!.from, 6);
      expect(match.to, 11);
      expect(match.text, 'world');
    });

    test('matchBefore with non-matching regex', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello world'),
      );
      final context = CompletionContext(
        state: state,
        pos: 11,
        explicit: false,
      );

      final match = context.matchBefore(RegExp(r'\d+'));
      expect(match, isNull);
    });

    test('matchBefore at line start', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'first\nsecond'),
      );
      final context = CompletionContext(
        state: state,
        pos: 6,
        explicit: false,
      );

      final match = context.matchBefore(RegExp(r'\w*'));
      expect(match, isNotNull);
      expect(match!.from, 6);
      expect(match.to, 6);
      expect(match.text, '');
    });

    test('matchBefore partial word', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello worl'),
      );
      final context = CompletionContext(
        state: state,
        pos: 10,
        explicit: false,
      );

      final match = context.matchBefore(RegExp(r'\w+'));
      expect(match, isNotNull);
      expect(match!.from, 6);
      expect(match.to, 10);
      expect(match.text, 'worl');
    });

    test('aborted state is initially false', () {
      final state = EditorState.create(const EditorStateConfig());
      final context = CompletionContext(
        state: state,
        pos: 0,
        explicit: false,
      );

      expect(context.aborted, false);
    });

    test('addEventListener registers abort listener', () {
      final state = EditorState.create(const EditorStateConfig());
      final context = CompletionContext(
        state: state,
        pos: 0,
        explicit: false,
      );

      var called = false;
      context.addEventListener('abort', () {
        called = true;
      });

      expect(called, false);
      context.abort();
      expect(called, true);
    });

    test('abort() calls all listeners', () {
      final state = EditorState.create(const EditorStateConfig());
      final context = CompletionContext(
        state: state,
        pos: 0,
        explicit: false,
      );

      var count = 0;
      context.addEventListener('abort', () => count++);
      context.addEventListener('abort', () => count++);
      context.addEventListener('abort', () => count++);

      context.abort();
      expect(count, 3);
      expect(context.aborted, true);
    });

    test('abort() sets aborted state to true', () {
      final state = EditorState.create(const EditorStateConfig());
      final context = CompletionContext(
        state: state,
        pos: 0,
        explicit: false,
      );

      expect(context.aborted, false);
      context.abort();
      expect(context.aborted, true);
    });

    test('addEventListener with onDocChange sets abortOnDocChange', () {
      final state = EditorState.create(const EditorStateConfig());
      final context = CompletionContext(
        state: state,
        pos: 0,
        explicit: false,
      );

      expect(context.abortOnDocChange, false);
      context.addEventListener('abort', () {}, onDocChange: true);
      expect(context.abortOnDocChange, true);
    });

    test('addEventListener ignores non-abort types', () {
      final state = EditorState.create(const EditorStateConfig());
      final context = CompletionContext(
        state: state,
        pos: 0,
        explicit: false,
      );

      var called = false;
      context.addEventListener('other', () {
        called = true;
      });

      context.abort();
      expect(called, false);
    });
  });

  group('CompletionResult', () {
    test('creates with required fields', () {
      final result = CompletionResult(
        from: 5,
        options: [const Completion(label: 'test')],
      );
      expect(result.from, 5);
      expect(result.to, isNull);
      expect(result.options.length, 1);
      expect(result.validFor, isNull);
      expect(result.filter, isNull);
    });

    test('creates with all fields', () {
      final result = CompletionResult(
        from: 5,
        to: 10,
        options: [const Completion(label: 'test')],
        validFor: RegExp(r'\w+'),
        filter: false,
        commitCharacters: ['.', '('],
      );
      expect(result.from, 5);
      expect(result.to, 10);
      expect(result.options.length, 1);
      expect(result.validFor, isA<RegExp>());
      expect(result.filter, false);
      expect(result.commitCharacters, ['.', '(']);
    });

    test('copyWith preserves values when not overridden', () {
      final original = CompletionResult(
        from: 5,
        to: 10,
        options: [const Completion(label: 'test')],
        filter: true,
      );

      final copied = original.copyWith();
      expect(copied.from, 5);
      expect(copied.to, 10);
      expect(copied.options.length, 1);
      expect(copied.filter, true);
    });

    test('copyWith overrides specified values', () {
      final original = CompletionResult(
        from: 5,
        to: 10,
        options: [const Completion(label: 'test')],
      );

      final copied = original.copyWith(
        from: 0,
        options: [
          const Completion(label: 'a'),
          const Completion(label: 'b'),
        ],
      );
      expect(copied.from, 0);
      expect(copied.to, 10);
      expect(copied.options.length, 2);
    });
  });

  group('ensureAnchor', () {
    test('adds ^ at start when needed', () {
      final expr = RegExp(r'\w+');
      final anchored = ensureAnchor(expr, true);
      expect(anchored.pattern, r'^(?:\w+)$');
    });

    test(r'adds $ at end when needed', () {
      final expr = RegExp(r'\w+');
      final anchored = ensureAnchor(expr, false);
      expect(anchored.pattern, r'(?:\w+)$');
    });

    test('preserves caseSensitive flag', () {
      final expr = RegExp(r'\w+', caseSensitive: false);
      final anchored = ensureAnchor(expr, true);
      expect(anchored.isCaseSensitive, false);
    });

    test('preserves multiLine flag', () {
      final expr = RegExp(r'\w+', multiLine: true);
      final anchored = ensureAnchor(expr, true);
      expect(anchored.isMultiLine, true);
    });

    test('preserves unicode flag', () {
      final expr = RegExp(r'\w+', unicode: true);
      final anchored = ensureAnchor(expr, true);
      expect(anchored.isUnicode, true);
    });

    test('preserves dotAll flag', () {
      final expr = RegExp(r'.*', dotAll: true);
      final anchored = ensureAnchor(expr, true);
      expect(anchored.isDotAll, true);
    });

    test('does not modify already anchored regex at start', () {
      final expr = RegExp(r'^test$');
      final anchored = ensureAnchor(expr, true);
      expect(anchored.pattern, r'^test$');
      expect(identical(anchored, expr), true);
    });

    test('does not add end anchor when already present', () {
      final expr = RegExp(r'test$');
      final anchored = ensureAnchor(expr, false);
      expect(anchored.pattern, r'test$');
      expect(identical(anchored, expr), true);
    });

    test('adds start anchor only when start=true and missing', () {
      final expr = RegExp(r'test$');
      final anchored = ensureAnchor(expr, true);
      expect(anchored.pattern, r'^(?:test$)');
    });
  });

  group('completeFromList', () {
    test('with string list', () {
      final source = completeFromList(['apple', 'banana', 'cherry']);
      final state = EditorState.create(
        const EditorStateConfig(doc: 'app'),
      );
      final context = CompletionContext(
        state: state,
        pos: 3,
        explicit: false,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNotNull);
      expect(result!.options.length, 3);
      expect(result.options[0].label, 'apple');
      expect(result.options[1].label, 'banana');
      expect(result.options[2].label, 'cherry');
    });

    test('with Completion list', () {
      final source = completeFromList([
        const Completion(label: 'func', type: 'function'),
        const Completion(label: 'var', type: 'variable'),
      ]);
      final state = EditorState.create(
        const EditorStateConfig(doc: 'f'),
      );
      final context = CompletionContext(
        state: state,
        pos: 1,
        explicit: false,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNotNull);
      expect(result!.options.length, 2);
      expect(result.options[0].type, 'function');
      expect(result.options[1].type, 'variable');
    });

    test('returns correct from position', () {
      final source = completeFromList(['hello', 'world']);
      final state = EditorState.create(
        const EditorStateConfig(doc: 'say hel'),
      );
      final context = CompletionContext(
        state: state,
        pos: 7,
        explicit: false,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNotNull);
      expect(result!.from, 4);
    });

    test('returns correct validFor regex for word-only completions', () {
      final source = completeFromList(['abc', 'def', 'ghi']);
      final state = EditorState.create(
        const EditorStateConfig(doc: 'ab'),
      );
      final context = CompletionContext(
        state: state,
        pos: 2,
        explicit: false,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNotNull);
      expect(result!.validFor, isA<RegExp>());
      final validFor = result.validFor as RegExp;
      expect(validFor.pattern, r'\w*$');
    });

    test('returns null when no token and not explicit', () {
      final source = completeFromList(['hello', 'world']);
      final state = EditorState.create(
        const EditorStateConfig(doc: '   '),
      );
      final context = CompletionContext(
        state: state,
        pos: 3,
        explicit: false,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNull);
    });

    test('returns result when explicit even without token', () {
      final source = completeFromList(['hello', 'world']);
      final state = EditorState.create(
        const EditorStateConfig(doc: '   '),
      );
      final context = CompletionContext(
        state: state,
        pos: 3,
        explicit: true,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNotNull);
      expect(result!.from, 3);
    });

    test('handles mixed string and Completion list', () {
      final source = completeFromList([
        'simple',
        const Completion(label: 'complex', detail: 'with detail'),
      ]);
      final state = EditorState.create(
        const EditorStateConfig(doc: 's'),
      );
      final context = CompletionContext(
        state: state,
        pos: 1,
        explicit: false,
      );

      final result = source(context) as CompletionResult?;
      expect(result, isNotNull);
      expect(result!.options.length, 2);
      expect(result.options[0].label, 'simple');
      expect(result.options[0].detail, isNull);
      expect(result.options[1].label, 'complex');
      expect(result.options[1].detail, 'with detail');
    });
  });

  group('insertCompletionText', () {
    test('inserts text at position', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hel world',
          selection: EditorSelection.cursor(3),
        ),
      );

      final spec = insertCompletionText(state, 'hello', 0, 3);
      final newState = state.update([spec]).state as EditorState;

      expect(newState.doc.toString(), 'hello world');
    });

    test('updates selection correctly', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hel world',
          selection: EditorSelection.cursor(3),
        ),
      );

      final spec = insertCompletionText(state, 'hello', 0, 3);
      final newState = state.update([spec]).state as EditorState;

      expect(newState.selection.main.from, 5);
      expect(newState.selection.main.to, 5);
    });

    test('works with single cursor', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'foo',
          selection: EditorSelection.cursor(3),
        ),
      );

      final spec = insertCompletionText(state, 'foobar', 0, 3);
      final newState = state.update([spec]).state as EditorState;

      expect(newState.doc.toString(), 'foobar');
      expect(newState.selection.main.from, 6);
    });

    test('replaces text range', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          selection: EditorSelection.cursor(5),
        ),
      );

      final spec = insertCompletionText(state, 'HELLO', 0, 5);
      final newState = state.update([spec]).state as EditorState;

      expect(newState.doc.toString(), 'HELLO world');
      expect(newState.selection.main.from, 5);
    });

    test('has scrollIntoView set to true', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'test',
          selection: EditorSelection.cursor(4),
        ),
      );

      final spec = insertCompletionText(state, 'testing', 0, 4);
      expect(spec.scrollIntoView, true);
    });

    test('has userEvent set to input.complete', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'test',
          selection: EditorSelection.cursor(4),
        ),
      );

      final spec = insertCompletionText(state, 'testing', 0, 4);
      expect(spec.userEvent, 'input.complete');
    });
  });

  group('cur function', () {
    test('returns main selection from position', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello world'),
      ).update([const TransactionSpec(anchor: 5)]).state as EditorState;

      expect(cur(state), 5);
    });

    test('returns from of range selection', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello world'),
      ).update([
        TransactionSpec(
          selection: EditorSelection.create([EditorSelection.range(2, 7)]),
        ),
      ]).state as EditorState;

      expect(cur(state), 2);
    });

    test('returns from of inverted range', () {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'hello world'),
      ).update([
        TransactionSpec(
          selection: EditorSelection.create([EditorSelection.range(7, 2)]),
        ),
      ]).state as EditorState;

      expect(cur(state), 2);
    });
  });

  group('State effects', () {
    test('startCompletionEffect.of(true)', () {
      final effect = startCompletionEffect.of(true);
      expect(effect.is_(startCompletionEffect), true);
      expect(effect.value, true);
    });

    test('startCompletionEffect.of(false)', () {
      final effect = startCompletionEffect.of(false);
      expect(effect.is_(startCompletionEffect), true);
      expect(effect.value, false);
    });

    test('closeCompletionEffect.of(null)', () {
      final effect = closeCompletionEffect.of(null);
      expect(effect.is_(closeCompletionEffect), true);
    });

    test('effects can be added to transaction', () {
      final state = EditorState.create(const EditorStateConfig());
      final tr = state.update([
        TransactionSpec(effects: [
          startCompletionEffect.of(true),
          closeCompletionEffect.of(null),
        ]),
      ]);

      expect(tr.effects.length, 2);
      expect(tr.effects[0].is_(startCompletionEffect), true);
      expect(tr.effects[1].is_(closeCompletionEffect), true);
    });
  });

  group('CompletionSection', () {
    test('creates with required name', () {
      const section = CompletionSection(name: 'Variables');
      expect(section.name, 'Variables');
      expect(section.header, isNull);
      expect(section.rank, isNull);
    });

    test('creates with all fields', () {
      final section = CompletionSection(
        name: 'Functions',
        rank: 1,
      );
      expect(section.name, 'Functions');
      expect(section.rank, 1);
    });
  });

  group('Option', () {
    test('creates with required fields', () {
      const completion = Completion(label: 'test');
      CompletionResult? nullSource(CompletionContext _) => null;
      final option = Option(
        completion: completion,
        source: nullSource,
        match: [0, 1, 2],
        score: 100,
      );
      expect(option.completion, completion);
      expect(option.source, nullSource);
      expect(option.match, [0, 1, 2]);
      expect(option.score, 100);
    });

    test('score is mutable', () {
      const completion = Completion(label: 'test');
      final option = Option(
        completion: completion,
        source: (_) => null,
        match: [],
        score: 50,
      );
      expect(option.score, 50);
      option.score = 100;
      expect(option.score, 100);
    });
  });

  group('pickedCompletion annotation', () {
    test('can be used in transaction', () {
      const completion = Completion(label: 'picked');
      final state = EditorState.create(const EditorStateConfig());
      final tr = state.update([
        TransactionSpec(annotations: [pickedCompletion.of(completion)]),
      ]);

      final picked = tr.annotation(pickedCompletion);
      expect(picked, isNotNull);
      expect(picked!.label, 'picked');
    });
  });
}
