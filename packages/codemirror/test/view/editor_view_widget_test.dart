import 'package:codemirror/codemirror.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Initialize state module
  ensureStateInitialized();

  group('EditorView Widget', () {
    testWidgets('displays initial document content', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Hello, World!'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      // Find the editable text
      expect(find.text('Hello, World!'), findsOneWidget);
    });

    testWidgets('can receive focus on tap', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Test content'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      // Tap on the editor
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      // Check that EditableText received focus
      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.focusNode.hasFocus, isTrue);
    });

    testWidgets('can type text', (tester) async {
      EditorState? updatedState;
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Hello'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              onUpdate: (update) {
                updatedState = update.state;
              },
            ),
          ),
        ),
      );

      // Tap to focus
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      // Type some text
      await tester.enterText(find.byType(EditableText), 'Hello World');
      await tester.pump();

      // Verify the text was entered
      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('autofocus works', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Auto focus test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              autofocus: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Check that EditableText has focus
      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.autofocus, isTrue);
    });

    testWidgets('read-only mode uses readOnly EditableText', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Read only content'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              readOnly: true,
            ),
          ),
        ),
      );

      // Should use EditableText with readOnly property
      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.readOnly, isTrue);
      expect(find.text('Read only content'), findsOneWidget);
    });

    testWidgets('custom style is applied', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Styled text'),
      );

      const customStyle = TextStyle(
        fontFamily: 'Courier',
        fontSize: 18,
        color: Colors.red,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              style: customStyle,
            ),
          ),
        ),
      );

      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.style.fontFamily, 'Courier');
      expect(editableText.style.fontSize, 18);
      expect(editableText.style.color, Colors.red);
    });

    testWidgets('custom cursor color is applied', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Cursor test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              cursorColor: Colors.green,
            ),
          ),
        ),
      );

      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      expect(editableText.cursorColor, Colors.green);
    });

    testWidgets('background color is applied', (tester) async {
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Background test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              backgroundColor: Colors.yellow,
            ),
          ),
        ),
      );

      // Find the Container with background color
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Container),
        ).first,
      );
      expect((container.decoration as BoxDecoration?)?.color ?? container.color, Colors.yellow);
    });

    testWidgets('onUpdate callback is called on text change', (tester) async {
      int updateCount = 0;
      final state = EditorState.create(
        const EditorStateConfig(doc: 'Initial'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              onUpdate: (update) {
                updateCount++;
              },
            ),
          ),
        ),
      );

      // Tap to focus
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      // Enter new text
      await tester.enterText(find.byType(EditableText), 'Changed');
      await tester.pump();

      expect(updateCount, greaterThan(0));
    });
  });
}
