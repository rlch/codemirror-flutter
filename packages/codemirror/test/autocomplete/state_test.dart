// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';

import '../../lib/src/autocomplete/completion.dart';
import '../../lib/src/autocomplete/config.dart';
import '../../lib/src/autocomplete/state.dart';
import '../../lib/src/state/change.dart';
import '../../lib/src/state/selection.dart';
import '../../lib/src/state/state.dart';
import '../../lib/src/state/transaction.dart';
import '../../lib/src/view/tooltip.dart' show Tooltip;

CompletionResult? _testSource(CompletionContext context) {
  return CompletionResult(
    from: 0,
    options: [const Completion(label: 'test')],
  );
}

CompletionResult? _nullSource(CompletionContext _) => null;

void main() {
  ensureStateInitialized();

  group('UpdateType constants', () {
    test('none is 0', () {
      expect(UpdateType.none, 0);
    });

    test('typing is 1', () {
      expect(UpdateType.typing, 1);
    });

    test('backspacing is 2', () {
      expect(UpdateType.backspacing, 2);
    });

    test('simpleInteraction is typing | backspacing', () {
      expect(UpdateType.simpleInteraction, UpdateType.typing | UpdateType.backspacing);
      expect(UpdateType.simpleInteraction, 3);
    });

    test('activate is 4', () {
      expect(UpdateType.activate, 4);
    });

    test('reset is 8', () {
      expect(UpdateType.reset, 8);
    });

    test('resetIfTouching is 16', () {
      expect(UpdateType.resetIfTouching, 16);
    });
  });

  group('ActiveSource', () {
    test('creates with source and state', () {
      final source = ActiveSource(source: _testSource, state: State.inactive);
      expect(source.source, _testSource);
      expect(source.state, State.inactive);
      expect(source.explicit, false);
    });

    test('creates with explicit flag', () {
      final source = ActiveSource(
        source: _testSource,
        state: State.pending,
        explicit: true,
      );
      expect(source.explicit, true);
    });

    test('hasResult() returns false', () {
      final source = ActiveSource(source: _testSource, state: State.inactive);
      expect(source.hasResult(), false);
    });

    test('isPending returns true when state is pending', () {
      final pending = ActiveSource(source: _testSource, state: State.pending);
      expect(pending.isPending, true);
    });

    test('isPending returns false when state is inactive', () {
      final inactive = ActiveSource(source: _testSource, state: State.inactive);
      expect(inactive.isPending, false);
    });

    test('isPending returns false when state is result', () {
      final result = ActiveSource(source: _testSource, state: State.result);
      expect(result.isPending, false);
    });

    test('map() returns same instance for base class', () {
      final source = ActiveSource(source: _testSource, state: State.inactive);
      final changes = ChangeSet.emptySet(10);
      final mapped = source.map(changes);
      expect(identical(mapped, source), true);
    });

    test('touches() checks if changes affect cursor position', () {
      final state = EditorState.create(
        EditorStateConfig(doc: 'hello world', selection: EditorSelection.cursor(5)),
      );
      final source = ActiveSource(source: _testSource, state: State.inactive);
      final tr = state.update([
        const TransactionSpec(changes: {'from': 0, 'to': 3, 'insert': 'x'}),
      ]);
      expect(source.touches(tr), true);
    });

    test('touches() returns false for non-affecting changes', () {
      final state = EditorState.create(
        EditorStateConfig(doc: 'hello world', selection: EditorSelection.cursor(0)),
      );
      final source = ActiveSource(source: _testSource, state: State.inactive);
      final tr = state.update([
        const TransactionSpec(changes: {'from': 6, 'to': 11, 'insert': 'x'}),
      ]);
      expect(source.touches(tr), false);
    });
  });

  group('ActiveResult', () {
    test('creates with all fields', () {
      final result = CompletionResult(
        from: 0,
        options: [const Completion(label: 'test')],
      );
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: true,
        limit: 0,
        result: result,
        from: 0,
        to: 4,
      );
      expect(activeResult.source, _testSource);
      expect(activeResult.explicit, true);
      expect(activeResult.limit, 0);
      expect(activeResult.result, result);
      expect(activeResult.from, 0);
      expect(activeResult.to, 4);
      expect(activeResult.state, State.result);
    });

    test('hasResult() returns true', () {
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(from: 0, options: []),
        from: 0,
        to: 4,
      );
      expect(activeResult.hasResult(), true);
    });

    test('isPending returns false', () {
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(from: 0, options: []),
        from: 0,
        to: 4,
      );
      expect(activeResult.isPending, false);
    });

    test('map() through empty changes returns same positions', () {
      final result = CompletionResult(from: 0, options: []);
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 2,
        result: result,
        from: 2,
        to: 6,
      );
      final changes = ChangeSet.emptySet(10);
      final mapped = activeResult.map(changes);
      expect(mapped, activeResult);
    });

    test('map() through changes updates positions', () {
      final result = CompletionResult(from: 0, options: []);
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 2,
        result: result,
        from: 2,
        to: 6,
      );
      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 10, null);
      final mapped = activeResult.map(changes) as ActiveResult;
      expect(mapped.from, 5);
      expect(mapped.to, 9);
      expect(mapped.limit, 5);
    });

    test('map() returns inactive source when result.map returns null', () {
      final result = CompletionResult(
        from: 0,
        options: [],
        map: (_, __) => null,
      );
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 2,
        result: result,
        from: 2,
        to: 6,
      );
      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 10, null);
      final mapped = activeResult.map(changes);
      expect(mapped is ActiveResult, false);
      expect(mapped.state, State.inactive);
    });

    test('touches() with range', () {
      final state = EditorState.create(
        EditorStateConfig(doc: 'hello world', selection: EditorSelection.cursor(5)),
      );
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(from: 0, options: []),
        from: 0,
        to: 5,
      );
      final tr = state.update([
        const TransactionSpec(changes: {'from': 3, 'to': 4, 'insert': 'x'}),
      ]);
      expect(activeResult.touches(tr), true);
    });

    test('touches() returns false when range not affected', () {
      final state = EditorState.create(
        EditorStateConfig(doc: 'hello world', selection: EditorSelection.cursor(0)),
      );
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(from: 0, options: []),
        from: 0,
        to: 3,
      );
      final tr = state.update([
        const TransactionSpec(changes: {'from': 6, 'to': 11, 'insert': 'x'}),
      ]);
      expect(activeResult.touches(tr), false);
    });
  });

  group('CompletionState', () {
    test('start() creates initial state', () {
      final completionState = CompletionState.start();
      expect(completionState.active, isEmpty);
      expect(completionState.id.startsWith('cm-ac-'), true);
      expect(completionState.open, isNull);
    });

    test('start() generates unique ids', () {
      final state1 = CompletionState.start();
      final state2 = CompletionState.start();
      expect(state1.id != state2.id, true);
    });

    test('tooltip getter returns null when open is null', () {
      final completionState = CompletionState.start();
      expect(completionState.tooltip, isNull);
    });

    test('attrs getter returns empty map when no active sources', () {
      final completionState = CompletionState(
        active: const [],
        id: 'test-id',
      );
      expect(completionState.attrs, isEmpty);
    });

    test('attrs getter returns base attrs when active sources exist', () {
      final completionState = CompletionState(
        active: [ActiveSource(source: _testSource, state: State.pending)],
        id: 'test-id',
      );
      expect(completionState.attrs['aria-autocomplete'], 'list');
    });
  });

  group('CompletionDialog', () {
    test('setSelected changes selection', () {
      final dialog = CompletionDialog(
        options: [
          Option(
            completion: const Completion(label: 'a'),
            source: _nullSource,
            match: [],
            score: 100,
          ),
          Option(
            completion: const Completion(label: 'b'),
            source: _nullSource,
            match: [],
            score: 90,
          ),
        ],
        attrs: makeAttrs('test-id', 0),
        tooltip: Tooltip(pos: 0, create: (_) => throw UnimplementedError()),
        timestamp: 12345,
        selected: 0,
        disabled: false,
      );

      final newDialog = dialog.setSelected(1, 'test-id');
      expect(newDialog.selected, 1);
      expect(newDialog.attrs['aria-activedescendant'], 'test-id-1');
    });

    test('setSelected returns same instance if index unchanged', () {
      final dialog = CompletionDialog(
        options: [
          Option(
            completion: const Completion(label: 'a'),
            source: _nullSource,
            match: [],
            score: 100,
          ),
        ],
        attrs: makeAttrs('test-id', 0),
        tooltip: Tooltip(pos: 0, create: (_) => throw UnimplementedError()),
        timestamp: 12345,
        selected: 0,
        disabled: false,
      );

      final newDialog = dialog.setSelected(0, 'test-id');
      expect(identical(newDialog, dialog), true);
    });

    test('setSelected returns same instance if index out of range', () {
      final dialog = CompletionDialog(
        options: [
          Option(
            completion: const Completion(label: 'a'),
            source: _nullSource,
            match: [],
            score: 100,
          ),
        ],
        attrs: makeAttrs('test-id', 0),
        tooltip: Tooltip(pos: 0, create: (_) => throw UnimplementedError()),
        timestamp: 12345,
        selected: 0,
        disabled: false,
      );

      final newDialog = dialog.setSelected(5, 'test-id');
      expect(identical(newDialog, dialog), true);
    });

    test('setDisabled returns disabled copy', () {
      final dialog = CompletionDialog(
        options: [],
        attrs: {},
        tooltip: Tooltip(pos: 0, create: (_) => throw UnimplementedError()),
        timestamp: 12345,
        selected: 0,
        disabled: false,
      );

      final disabledDialog = dialog.setDisabled();
      expect(disabledDialog.disabled, true);
      expect(dialog.disabled, false);
    });

    test('map() through changes updates tooltip position', () {
      final dialog = CompletionDialog(
        options: [],
        attrs: {},
        tooltip: Tooltip(pos: 5, create: (_) => throw UnimplementedError()),
        timestamp: 12345,
        selected: 0,
        disabled: false,
      );

      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 10, null);

      final mappedDialog = dialog.map(changes);
      expect(mappedDialog.tooltip.pos, 8);
    });
  });

  group('sortOptions', () {
    test('sorts by score descending', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'ab'));
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(
          from: 0,
          options: [
            const Completion(label: 'abc', boost: 0),
            const Completion(label: 'abd', boost: 10),
            const Completion(label: 'abe', boost: 5),
          ],
        ),
        from: 0,
        to: 2,
      );

      final options = sortOptions([activeResult], state);
      expect(options[0].completion.label, 'abd');
      expect(options[1].completion.label, 'abe');
      expect(options[2].completion.label, 'abc');
    });

    test('applies section ordering', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'a'));
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(
          from: 0,
          options: [
            const Completion(label: 'abc', section: CompletionSection(name: 'B', rank: 2)),
            const Completion(label: 'abd', section: CompletionSection(name: 'A', rank: 1)),
          ],
        ),
        from: 0,
        to: 1,
      );

      final options = sortOptions([activeResult], state);
      expect(options[0].completion.section, isA<CompletionSection>());
      expect((options[0].completion.section as CompletionSection).name, 'A');
    });

    test('deduplicates completions with same label', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'a'));
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(
          from: 0,
          options: [
            const Completion(label: 'abc'),
            const Completion(label: 'abc'),
          ],
        ),
        from: 0,
        to: 1,
      );

      final options = sortOptions([activeResult], state);
      expect(options.length, 1);
    });

    test('keeps different completions with same label but different type', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'a'));
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: CompletionResult(
          from: 0,
          options: [
            const Completion(label: 'abc', type: 'function'),
            const Completion(label: 'abc', type: 'variable'),
          ],
        ),
        from: 0,
        to: 1,
      );

      final options = sortOptions([activeResult], state);
      expect(options.length, 2);
    });
  });

  group('getUpdateType', () {
    test('returns typing for input.type', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello',
          extensions: completionConfig.of(const CompletionConfig(activateOnTyping: true)),
        ),
      );
      final tr = state.update([
        const TransactionSpec(
          changes: {'from': 5, 'insert': 'x'},
          userEvent: 'input.type',
        ),
      ]);
      final conf = (tr.state as EditorState).facet(completionConfig);
      final type = getUpdateType(tr, conf);
      expect(type & UpdateType.typing, UpdateType.typing);
      expect(type & UpdateType.activate, UpdateType.activate);
    });

    test('returns typing without activate when activateOnTyping is false', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello',
          extensions: completionConfig.of(const CompletionConfig(activateOnTyping: false)),
        ),
      );
      final tr = state.update([
        const TransactionSpec(
          changes: {'from': 5, 'insert': 'x'},
          userEvent: 'input.type',
        ),
      ]);
      final conf = (tr.state as EditorState).facet(completionConfig);
      final type = getUpdateType(tr, conf);
      expect(type, UpdateType.typing);
    });

    test('returns backspacing for delete.backward', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      final tr = state.update([
        const TransactionSpec(
          changes: {'from': 4, 'to': 5},
          userEvent: 'delete.backward',
        ),
      ]);
      final conf = (tr.state as EditorState).facet(completionConfig);
      expect(getUpdateType(tr, conf), UpdateType.backspacing);
    });

    test('returns reset for selection change', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      final tr = state.update([
        const TransactionSpec(anchor: 3),
      ]);
      final conf = (tr.state as EditorState).facet(completionConfig);
      expect(getUpdateType(tr, conf), UpdateType.reset);
    });

    test('returns resetIfTouching for doc change without user event', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      final tr = state.update([
        const TransactionSpec(
          changes: {'from': 0, 'insert': 'x'},
        ),
      ]);
      final conf = (tr.state as EditorState).facet(completionConfig);
      expect(getUpdateType(tr, conf), UpdateType.resetIfTouching);
    });

    test('returns none for no changes', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      final tr = state.update([]);
      final conf = (tr.state as EditorState).facet(completionConfig);
      expect(getUpdateType(tr, conf), UpdateType.none);
    });
  });

  group('checkValid', () {
    test('returns false when validFor is null', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      expect(checkValid(null, state, 0, 5), false);
    });

    test('with RegExp validFor matches text', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      expect(checkValid(RegExp(r'\w+'), state, 0, 5), true);
    });

    test('with RegExp validFor returns false for non-match', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello 123'));
      expect(checkValid(RegExp(r'^\d+$'), state, 0, 5), false);
    });

    test('with predicate validFor', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      bool predicate(String text, int from, int to, EditorState s) {
        return text == 'hello';
      }

      expect(checkValid(predicate, state, 0, 5), true);
    });

    test('with predicate validFor returns false when predicate fails', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      bool predicate(String text, int from, int to, EditorState s) {
        return text == 'world';
      }

      expect(checkValid(predicate, state, 0, 5), false);
    });
  });

  group('makeAttrs', () {
    test('creates aria attributes', () {
      final attrs = makeAttrs('my-id', -1);
      expect(attrs['aria-autocomplete'], 'list');
      expect(attrs['aria-haspopup'], 'listbox');
      expect(attrs['aria-controls'], 'my-id');
      expect(attrs.containsKey('aria-activedescendant'), false);
    });

    test('includes activedescendant when selected >= 0', () {
      final attrs = makeAttrs('my-id', 2);
      expect(attrs['aria-activedescendant'], 'my-id-2');
    });

    test('does not include activedescendant when selected is -1', () {
      final attrs = makeAttrs('my-id', -1);
      expect(attrs.containsKey('aria-activedescendant'), false);
    });
  });

  group('State effects', () {
    test('setActiveEffect.of creates effect', () {
      final sources = [ActiveSource(source: _testSource, state: State.pending)];
      final effect = setActiveEffect.of(sources);
      expect(effect.is_(setActiveEffect), true);
      expect(effect.value, sources);
    });

    test('setActiveEffect maps through changes', () {
      final result = CompletionResult(from: 0, options: []);
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 2,
        result: result,
        from: 2,
        to: 6,
      );
      final sources = <ActiveSource>[activeResult];
      final effect = setActiveEffect.of(sources);

      final changes = ChangeSet.of([
        {'from': 0, 'insert': 'abc'},
      ], 10, null);
      final mapped = effect.map(changes)!;
      expect(mapped.is_(setActiveEffect), true);

      final mappedSources = mapped.value as List<ActiveSource>;
      expect(mappedSources.length, 1);
      final mappedResult = mappedSources[0] as ActiveResult;
      expect(mappedResult.from, 5);
      expect(mappedResult.to, 9);
    });

    test('setSelectedEffect.of creates effect', () {
      final effect = setSelectedEffect.of(5);
      expect(effect.is_(setSelectedEffect), true);
      expect(effect.value, 5);
    });

    test('effects can be added to transaction', () {
      final state = EditorState.create(const EditorStateConfig());
      final sources = [ActiveSource(source: _testSource, state: State.pending)];
      final tr = state.update([
        TransactionSpec(effects: [
          setActiveEffect.of(sources),
          setSelectedEffect.of(2),
        ]),
      ]);

      expect(tr.effects.length, 2);
      expect(tr.effects[0].is_(setActiveEffect), true);
      expect(tr.effects[1].is_(setSelectedEffect), true);
    });
  });

  group('sameResults', () {
    test('returns true for identical lists', () {
      final result = CompletionResult(from: 0, options: []);
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: result,
        from: 0,
        to: 5,
      );
      final list = [activeResult];
      expect(sameResults(list, list), true);
    });

    test('returns true for lists with same results', () {
      final result = CompletionResult(from: 0, options: []);
      final activeResult1 = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: result,
        from: 0,
        to: 5,
      );
      final activeResult2 = ActiveResult(
        source: _testSource,
        explicit: true,
        limit: 0,
        result: result,
        from: 0,
        to: 5,
      );
      expect(sameResults([activeResult1], [activeResult2]), true);
    });

    test('returns false for lists with different results', () {
      final result1 = CompletionResult(from: 0, options: []);
      final result2 = CompletionResult(from: 0, options: []);
      final activeResult1 = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: result1,
        from: 0,
        to: 5,
      );
      final activeResult2 = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: result2,
        from: 0,
        to: 5,
      );
      expect(sameResults([activeResult1], [activeResult2]), false);
    });

    test('skips non-result sources when comparing', () {
      final result = CompletionResult(from: 0, options: []);
      final activeResult = ActiveResult(
        source: _testSource,
        explicit: false,
        limit: 0,
        result: result,
        from: 0,
        to: 5,
      );
      final pendingSource = ActiveSource(source: _testSource, state: State.pending);
      expect(sameResults([pendingSource, activeResult], [activeResult]), true);
    });
  });

  group('completionState StateField', () {
    test('can be added to editor state', () {
      final state = EditorState.create(
        EditorStateConfig(extensions: completionState),
      );
      final cs = state.field(completionState);
      expect(cs, isNotNull);
      expect(cs!.active, isEmpty);
    });

    test('updates on transaction', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello',
          extensions: completionState,
        ),
      );
      final tr = state.update([
        const TransactionSpec(changes: {'from': 5, 'insert': 'x'}),
      ]);
      final cs = (tr.state as EditorState).field(completionState);
      expect(cs, isNotNull);
    });
  });

  group('State enum', () {
    test('has correct values', () {
      expect(State.values.length, 3);
      expect(State.values.contains(State.inactive), true);
      expect(State.values.contains(State.pending), true);
      expect(State.values.contains(State.result), true);
    });
  });
}
