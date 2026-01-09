import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('History Keymap Widget Tests', () {
    testWidgets('Cmd-Z (Mod-z) triggers undo and reverts changes',
        (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      EditorState? currentState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
                onUpdate: (update) {
                  currentState = update.state;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Type text via transaction
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 5, insert: ' world'),
        ),
      ]);
      await tester.pump();

      expect(currentState?.doc.toString(), 'hello world');

      // Send Cmd-Z (Meta-Z on macOS)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      // Verify text was undone
      expect(currentState?.doc.toString(), 'hello');
    });

    testWidgets('Cmd-Shift-Z (Mod-Shift-z on mac) triggers redo',
        (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      EditorState? currentState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
                onUpdate: (update) {
                  currentState = update.state;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Make a change
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 5, insert: ' world'),
        ),
      ]);
      await tester.pump();
      expect(currentState?.doc.toString(), 'hello world');

      // Undo with Cmd-Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(currentState?.doc.toString(), 'hello');

      // Redo with Cmd-Shift-Z (using simulateKeyDownEvent for proper modifier state)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      // Verify text was redone
      expect(currentState?.doc.toString(), 'hello world');
    });

    testWidgets(
        'CodeMirror keymap intercepts undo shortcuts before Flutter handles them',
        (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'test',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      EditorState? currentState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
                onUpdate: (update) {
                  currentState = update.state;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Make a change
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 4, insert: ' change'),
        ),
      ]);
      await tester.pump();
      expect(currentState?.doc.toString(), 'test change');

      // Send Cmd-Z - this should be intercepted by CodeMirror's keymap
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      // Verify CodeMirror's undo was triggered
      expect(currentState?.doc.toString(), 'test');
    });

    testWidgets('Multiple undo/redo cycles work correctly', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'a',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      EditorState? currentState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
                onUpdate: (update) {
                  currentState = update.state;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      final viewState = tester.state<EditorViewState>(find.byType(EditorView));

      // Make 3 isolated changes
      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 1, insert: 'b'),
          annotations: [isolateHistory.of('full')],
        ),
      ]);
      await tester.pump();
      expect(currentState?.doc.toString(), 'ab');

      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 2, insert: 'c'),
          annotations: [isolateHistory.of('full')],
        ),
      ]);
      await tester.pump();
      expect(currentState?.doc.toString(), 'abc');

      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 3, insert: 'd'),
          annotations: [isolateHistory.of('full')],
        ),
      ]);
      await tester.pump();
      expect(currentState?.doc.toString(), 'abcd');

      // Helper to send Cmd-Z
      Future<void> sendUndo() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
        await tester.pumpAndSettle();
      }

      // Helper to send Cmd-Shift-Z
      Future<void> sendRedo() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
        await tester.pumpAndSettle();
      }

      // Undo all 3 changes
      await sendUndo();
      expect(currentState?.doc.toString(), 'abc');

      await sendUndo();
      expect(currentState?.doc.toString(), 'ab');

      await sendUndo();
      expect(currentState?.doc.toString(), 'a');

      // Redo all 3 changes
      await sendRedo();
      expect(currentState?.doc.toString(), 'ab');

      await sendRedo();
      expect(currentState?.doc.toString(), 'abc');

      await sendRedo();
      expect(currentState?.doc.toString(), 'abcd');

      // Undo 2, redo 1, undo 1
      await sendUndo();
      await sendUndo();
      expect(currentState?.doc.toString(), 'ab');

      await sendRedo();
      expect(currentState?.doc.toString(), 'abc');

      await sendUndo();
      expect(currentState?.doc.toString(), 'ab');
    });

    testWidgets('Keybindings work when focus is on the editor', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'initial',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      EditorState? currentState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
                onUpdate: (update) {
                  currentState = update.state;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewState = tester.state<EditorViewState>(find.byType(EditorView));

      // Make a change
      viewState.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 7, insert: ' text'),
        ),
      ]);
      await tester.pump();
      expect(currentState?.doc.toString(), 'initial text');

      // Tap on editor to ensure focus
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Now undo should work
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(currentState?.doc.toString(), 'initial');
    });

    testWidgets('Undo does nothing when nothing to undo', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'unchanged',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Get initial undoDepth
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      expect(undoDepth(viewState.state), 0);

      // Try undo when nothing to undo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      // Document should be unchanged
      expect(viewState.state.doc.toString(), 'unchanged');
    });

    testWidgets('Redo does nothing when nothing to redo', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'unchanged',
          extensions: ExtensionList([
            history(),
            keymap.of(historyKeymap),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorView(
                state: state,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Get initial redoDepth
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      expect(redoDepth(viewState.state), 0);

      // Try redo when nothing to redo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      // Document should be unchanged
      expect(viewState.state.doc.toString(), 'unchanged');
    });

    testWidgets('History keymap defines correct key bindings', (tester) async {
      // Verify historyKeymap has the expected bindings
      expect(historyKeymap.length, 4);

      // Mod-z for undo
      expect(historyKeymap[0].key, 'Mod-z');

      // Mod-y (Windows/Linux redo) with Mod-Shift-z (Mac redo)
      expect(historyKeymap[1].key, 'Mod-y');
      expect(historyKeymap[1].mac, 'Mod-Shift-z');

      // Mod-u for undoSelection
      expect(historyKeymap[2].key, 'Mod-u');

      // Alt-u (Windows/Linux) / Mod-Shift-u (Mac) for redoSelection
      expect(historyKeymap[3].key, 'Alt-u');
      expect(historyKeymap[3].mac, 'Mod-Shift-u');
    });
  });
}
