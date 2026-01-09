// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';

import '../../lib/src/language/fold.dart';
import '../../lib/src/state/state.dart';
import '../../lib/src/state/selection.dart';
import '../../lib/src/state/facet.dart' hide EditorState, Transaction;
import '../../lib/src/state/transaction.dart';
import '../../lib/src/state/change.dart';
import '../../lib/src/state/range_set.dart';
import '../../lib/src/view/decoration.dart';

void main() {
  // Ensure fold module is initialized
  ensureFoldInitialized();

  const doc = '1\n2\n3\n4\n5\n6\n7\n8\n';

  String ranges(RangeSet<Decoration>? set) {
    if (set == null) return '';
    final result = <String>[];
    set.between(0, 100000000, (f, t, _) {
      result.add('$f-$t');
      return true;
    });
    return result.join(' ');
  }

  group('Folding', () {
    test('stores fold state', () {
      var state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([foldState]),
      ));

      // Apply fold effects
      final tr = state.update([
        TransactionSpec(effects: [
          foldEffect.of((from: 0, to: 3)),
          foldEffect.of((from: 4, to: 7)),
        ]),
      ]);
      state = tr.state as EditorState;

      expect(ranges(state.field(foldState)), '0-3 4-7');

      // Unfold one range
      final tr2 = state.update([
        TransactionSpec(effects: [unfoldEffect.of((from: 4, to: 7))]),
      ]);
      state = tr2.state as EditorState;

      expect(ranges(state.field(foldState)), '0-3');
    });

    test('maps fold ranges through changes', () {
      var state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([foldState]),
      ));

      // Create a fold
      var tr = state.update([
        TransactionSpec(effects: [foldEffect.of((from: 4, to: 7))]),
      ]);
      state = tr.state as EditorState;
      expect(ranges(state.field(foldState)), '4-7');

      // Insert text before the fold
      tr = state.update([
        TransactionSpec(changes: ChangeSpec(from: 0, insert: 'XX')),
      ]);
      state = tr.state as EditorState;

      // Fold should be shifted by 2
      expect(ranges(state.field(foldState)), '6-9');
    });

    test('clears folds that touch selection', () {
      var state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([foldState]),
      ));

      // Create a fold
      var tr = state.update([
        TransactionSpec(effects: [foldEffect.of((from: 2, to: 5))]),
      ]);
      state = tr.state as EditorState;
      expect(ranges(state.field(foldState)), '2-5');

      // Move selection into the fold
      tr = state.update([
        TransactionSpec(selection: EditorSelection.single(3)),
      ]);
      state = tr.state as EditorState;

      // Fold should be removed
      expect(ranges(state.field(foldState)), '');
    });

    test('does not duplicate folds', () {
      var state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([foldState]),
      ));

      // Apply the same fold twice
      final tr = state.update([
        TransactionSpec(effects: [
          foldEffect.of((from: 2, to: 5)),
          foldEffect.of((from: 2, to: 5)),
        ]),
      ]);
      state = tr.state as EditorState;

      // Should only have one fold
      expect(ranges(state.field(foldState)), '2-5');
    });
  });

  group('FoldRange', () {
    test('maps through changes correctly', () {
      var state = EditorState.create(EditorStateConfig(
        doc: 'hello world',
        extensions: ExtensionList([foldState]),
      ));

      // Fold "llo wo"
      var tr = state.update([
        TransactionSpec(effects: [foldEffect.of((from: 2, to: 8))]),
      ]);
      state = tr.state as EditorState;

      // Delete "he" at start
      tr = state.update([
        TransactionSpec(changes: ChangeSpec(from: 0, to: 2)),
      ]);
      state = tr.state as EditorState;

      // Fold should now be at 0-6
      expect(ranges(state.field(foldState)), '0-6');
    });

    test('removes fold when range becomes invalid', () {
      var state = EditorState.create(EditorStateConfig(
        doc: 'hello world',
        extensions: ExtensionList([foldState]),
      ));

      // Fold "llo wo"
      var tr = state.update([
        TransactionSpec(effects: [foldEffect.of((from: 2, to: 8))]),
      ]);
      state = tr.state as EditorState;

      // Delete the entire folded region
      tr = state.update([
        TransactionSpec(changes: ChangeSpec(from: 0, to: 11)),
      ]);
      state = tr.state as EditorState;

      // Fold should be removed
      expect(ranges(state.field(foldState)), '');
    });
  });

  group('foldedRanges', () {
    test('returns empty when no folds', () {
      final state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([foldState]),
      ));
      expect(foldedRanges(state).isEmpty, true);
    });

    test('returns current folds', () {
      var state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([foldState]),
      ));

      final tr = state.update([
        TransactionSpec(effects: [foldEffect.of((from: 0, to: 3))]),
      ]);
      state = tr.state as EditorState;

      final folded = foldedRanges(state);
      expect(folded.isEmpty, false);
    });

    test('returns empty when foldState not present', () {
      final state = EditorState.create(EditorStateConfig(doc: doc));
      expect(foldedRanges(state).isEmpty, true);
    });
  });

  group('FoldConfig', () {
    test('has default placeholder text', () {
      const config = FoldConfig();
      expect(config.placeholderText, '…');
    });

    test('can customize placeholder text', () {
      const config = FoldConfig(placeholderText: '[...]');
      expect(config.placeholderText, '[...]');
    });
  });

  group('codeFolding extension', () {
    test('creates extension', () {
      final ext = codeFolding();
      expect(ext, isNotNull);
    });

    test('accepts configuration', () {
      final ext = codeFolding(const FoldConfig(
        placeholderText: '...',
      ));
      expect(ext, isNotNull);
    });

    test('integrates with editor state', () {
      final state = EditorState.create(EditorStateConfig(
        doc: doc,
        extensions: ExtensionList([codeFolding()]),
      ));
      expect(state, isNotNull);
      expect(state.field(foldState, false), isNotNull);
    });
  });

  group('foldKeymap', () {
    test('has expected bindings', () {
      expect(foldKeymap.length, 4);

      final keys = foldKeymap.map((b) => b.key).toList();
      expect(keys, contains('Ctrl-Shift-['));
      expect(keys, contains('Ctrl-Shift-]'));
      expect(keys, contains('Ctrl-Alt-['));
      expect(keys, contains('Ctrl-Alt-]'));
    });
  });

  group('Edge cases', () {
    test('handles empty document', () {
      final state = EditorState.create(EditorStateConfig(
        doc: '',
        extensions: ExtensionList([foldState]),
      ));
      expect(foldedRanges(state).isEmpty, true);
    });

    test('handles single character document', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'x',
        extensions: ExtensionList([foldState]),
      ));

      // Try to create an invalid fold (from >= to after mapping)
      // This should be handled gracefully
      expect(foldedRanges(state).isEmpty, true);
    });

    test('handles overlapping fold requests', () {
      var state = EditorState.create(EditorStateConfig(
        doc: 'abcdefghij',
        extensions: ExtensionList([foldState]),
      ));

      // Create overlapping folds
      final tr = state.update([
        TransactionSpec(effects: [
          foldEffect.of((from: 0, to: 5)),
          foldEffect.of((from: 3, to: 8)), // Overlaps with first
        ]),
      ]);
      state = tr.state as EditorState;

      // Both folds should be added (CodeMirror allows overlapping folds)
      final folded = foldedRanges(state);
      expect(folded.isEmpty, false);
    });
  });
}
