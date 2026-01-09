import 'package:codemirror/codemirror.dart';
import 'package:codemirror/src/view/view_update.dart';
import 'package:test/test.dart';

void main() {
  // Ensure state module is initialized
  ensureStateInitialized();

  group('ChangedRange', () {
    test('creates a changed range', () {
      final range = ChangedRange(0, 5, 0, 10);
      expect(range.fromA, 0);
      expect(range.toA, 5);
      expect(range.fromB, 0);
      expect(range.toB, 10);
    });

    test('addToSet adds non-overlapping range', () {
      final ranges = <ChangedRange>[];
      ChangedRange(0, 5, 0, 5).addToSet(ranges);
      ChangedRange(10, 15, 10, 15).addToSet(ranges);

      expect(ranges.length, 2);
      expect(ranges[0].fromA, 0);
      expect(ranges[0].toA, 5);
      expect(ranges[1].fromA, 10);
      expect(ranges[1].toA, 15);
    });

    test('addToSet merges overlapping ranges', () {
      final ranges = <ChangedRange>[];
      ChangedRange(0, 10, 0, 10).addToSet(ranges);
      ChangedRange(5, 15, 5, 15).addToSet(ranges);

      expect(ranges.length, 1);
      expect(ranges[0].fromA, 0);
      expect(ranges[0].toA, 15);
    });

    test('addToSet inserts in sorted order', () {
      final ranges = <ChangedRange>[];
      ChangedRange(10, 15, 10, 15).addToSet(ranges);
      ChangedRange(0, 5, 0, 5).addToSet(ranges);

      expect(ranges.length, 2);
      expect(ranges[0].fromA, 0);
      expect(ranges[1].fromA, 10);
    });
  });

  group('UpdateFlag', () {
    test('has correct flag values', () {
      expect(UpdateFlag.viewport, 1);
      expect(UpdateFlag.viewportMoved, 2);
      expect(UpdateFlag.height, 4);
      expect(UpdateFlag.geometry, 8);
      expect(UpdateFlag.focus, 16);
    });

    test('flags can be combined', () {
      const flags = UpdateFlag.viewport | UpdateFlag.height;
      expect(flags & UpdateFlag.viewport, UpdateFlag.viewport);
      expect(flags & UpdateFlag.height, UpdateFlag.height);
      expect(flags & UpdateFlag.focus, 0);
    });
  });

  group('ViewUpdate', () {
    late EditorState state;

    setUp(() {
      state = EditorState.create(
        const EditorStateConfig(doc: 'Hello, World!'),
      );
    });

    test('creates empty update', () {
      final update = ViewUpdate.create(state, []);
      expect(update.state, state);
      expect(update.transactions, isEmpty);
      expect(update.empty, true);
      expect(update.docChanged, false);
    });

    test('tracks document changes', () {
      final tr = state.update([
        TransactionSpec(
          changes: ChangeSpec(from: 0, to: 5, insert: 'Hi'),
        ),
      ]);

      final update = ViewUpdate.create(tr.state as EditorState, [tr]);
      expect(update.docChanged, true);
      expect(update.empty, false);
      expect(update.state.doc.toString(), 'Hi, World!');
    });

    test('tracks selection changes', () {
      final tr = state.update([
        TransactionSpec(
          selection: EditorSelection.single(5),
        ),
      ]);

      final update = ViewUpdate.create(tr.state as EditorState, [tr]);
      expect(update.selectionSet, true);
    });

    test('computes changed ranges', () {
      final tr = state.update([
        TransactionSpec(
          changes: ChangeSpec(from: 0, to: 5, insert: 'Hi'),
        ),
      ]);

      final update = ViewUpdate.create(tr.state as EditorState, [tr]);
      final ranges = update.changedRanges;
      expect(ranges, isNotEmpty);
      expect(ranges[0].fromA, 0);
      expect(ranges[0].toA, 5);
      expect(ranges[0].fromB, 0);
      expect(ranges[0].toB, 2);
    });

    test('isUserEvent checks transaction events', () {
      final tr = state.update([
        TransactionSpec(
          changes: ChangeSpec(from: 0, insert: 'x'),
          userEvent: 'input.type',
        ),
      ]);

      final update = ViewUpdate.create(tr.state as EditorState, [tr]);
      expect(update.isUserEvent('input'), true);
      expect(update.isUserEvent('input.type'), true);
      expect(update.isUserEvent('delete'), false);
    });

    test('flags can be set and checked', () {
      final update = ViewUpdate.create(state, []);
      update.flags = UpdateFlag.viewport | UpdateFlag.height;

      expect(update.viewportChanged, true);
      expect(update.heightChanged, true);
      expect(update.geometryChanged, false);
      expect(update.focusChanged, false);
    });
  });
}
