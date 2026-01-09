import 'package:codemirror/codemirror.dart';
import 'package:test/test.dart';

void main() {
  group('History', () {
    group('basic undo/redo', () {
      test('can undo a change', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        // Make a change
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' world'),
              ),
            ])
            .state as EditorState;
        expect(state.doc.toString(), 'hello world');

        // Undo it
        final undone = undo((
          state: state,
          dispatch: (tr) {
            state = tr.state as EditorState;
          },
        ));

        expect(undone, true);
        expect(state.doc.toString(), 'hello');
      });

      test('can redo an undone change', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        // Make a change
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' world'),
              ),
            ])
            .state as EditorState;

        // Undo it
        undo((
          state: state,
          dispatch: (tr) {
            state = tr.state as EditorState;
          },
        ));
        expect(state.doc.toString(), 'hello');

        // Redo it
        final redone = redo((
          state: state,
          dispatch: (tr) {
            state = tr.state as EditorState;
          },
        ));

        expect(redone, true);
        expect(state.doc.toString(), 'hello world');
      });

      test('undo returns false when nothing to undo', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        final undone = undo((
          state: state,
          dispatch: (_) {},
        ));

        expect(undone, false);
      });

      test('redo returns false when nothing to redo', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        final redone = redo((
          state: state,
          dispatch: (_) {},
        ));

        expect(redone, false);
      });
    });

    group('undoDepth/redoDepth', () {
      test('starts at 0', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        expect(undoDepth(state), 0);
        expect(redoDepth(state), 0);
      });

      test('increments with changes', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' world'),
              ),
            ])
            .state as EditorState;

        expect(undoDepth(state), 1);
        expect(redoDepth(state), 0);
      });

      test('tracks undo/redo correctly', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        // Make two changes
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' world'),
                annotations: [isolateHistory.of('full')],
              ),
            ])
            .state as EditorState;

        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 11, insert: '!'),
              ),
            ])
            .state as EditorState;

        expect(undoDepth(state), 2);
        expect(redoDepth(state), 0);

        // Undo one
        undo((
          state: state,
          dispatch: (tr) {
            state = tr.state as EditorState;
          },
        ));

        expect(undoDepth(state), 1);
        expect(redoDepth(state), 1);
      });
    });

    group('addToHistory annotation', () {
      test('respects addToHistory: false', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' world'),
                annotations: [Transaction.addToHistory.of(false)],
              ),
            ])
            .state as EditorState;

        expect(state.doc.toString(), 'hello world');
        expect(undoDepth(state), 0);
      });
    });

    group('isolateHistory annotation', () {
      test('isolateHistory prevents merging', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: history(),
          ),
        );

        // First change
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' '),
              ),
            ])
            .state as EditorState;

        // Second change with isolation
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 6, insert: 'world'),
                annotations: [isolateHistory.of('before')],
              ),
            ])
            .state as EditorState;

        expect(undoDepth(state), 2);
      });
    });

    group('multiple changes', () {
      test('can undo multiple changes in sequence', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'a',
            extensions: history(),
          ),
        );

        // Make 3 isolated changes
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 1, insert: 'b'),
                annotations: [isolateHistory.of('full')],
              ),
            ])
            .state as EditorState;
        expect(state.doc.toString(), 'ab');

        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 2, insert: 'c'),
                annotations: [isolateHistory.of('full')],
              ),
            ])
            .state as EditorState;
        expect(state.doc.toString(), 'abc');

        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 3, insert: 'd'),
                annotations: [isolateHistory.of('full')],
              ),
            ])
            .state as EditorState;
        expect(state.doc.toString(), 'abcd');

        // Undo all 3
        undo((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));
        expect(state.doc.toString(), 'abc');

        undo((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));
        expect(state.doc.toString(), 'ab');

        undo((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));
        expect(state.doc.toString(), 'a');
      });
    });

    group('selection history', () {
      test('undo restores selection from before change', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            selection: EditorSelection.single(3), // Start with cursor at position 3
            extensions: history(),
          ),
        );

        expect(state.selection.main.head, 3);

        // Make a text change (which records the selection before the change)
        state = state
            .update([
              TransactionSpec(
                changes: ChangeSpec(from: 5, insert: ' world'),
              ),
            ])
            .state as EditorState;

        expect(state.doc.toString(), 'hello world');

        // Move cursor to different position
        state = state
            .update([
              TransactionSpec(
                selection: EditorSelection.single(11),
              ),
            ])
            .state as EditorState;
        expect(state.selection.main.head, 11);

        // Undo the text change - should restore the selection from before the change
        undo((
          state: state,
          dispatch: (tr) => state = tr.state as EditorState,
        ));

        expect(state.doc.toString(), 'hello');
        expect(state.selection.main.head, 3);
      });
    });

    group('HistoryConfig', () {
      test('respects minDepth', () {
        var state = EditorState.create(
          EditorStateConfig(
            doc: '',
            extensions: history(const HistoryConfig(minDepth: 3)),
          ),
        );

        // Make 5 changes
        for (var i = 0; i < 5; i++) {
          state = state
              .update([
                TransactionSpec(
                  changes: ChangeSpec(from: state.doc.length, insert: '$i'),
                  annotations: [isolateHistory.of('full')],
                ),
              ])
              .state as EditorState;
        }

        expect(state.doc.toString(), '01234');
        // Should be able to undo all 5 (minDepth is minimum, not maximum)
        expect(undoDepth(state), 5);
      });
    });

    group('historyKeymap', () {
      test('defines standard key bindings', () {
        expect(historyKeymap.length, 4);
        expect(historyKeymap[0].key, 'Mod-z');
        expect(historyKeymap[1].key, 'Mod-y');
        expect(historyKeymap[1].mac, 'Mod-Shift-z');
        expect(historyKeymap[2].key, 'Mod-u');
        expect(historyKeymap[3].key, 'Alt-u');
        expect(historyKeymap[3].mac, 'Mod-Shift-u');
      });
    });
  });
}
