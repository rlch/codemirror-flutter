import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('placeholder widget tests', () {
    testWidgets('editor renders with placeholder extension', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: placeholder('Enter some code...'),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      // Editor should render without errors
      expect(find.byType(EditorView), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('editor renders with content and placeholder extension', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: placeholder('Enter some code...'),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      // Editor should render the content
      expect(find.byType(EditorView), findsOneWidget);
    });

    testWidgets('placeholder extension with widget content', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: placeholder(
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit, size: 16),
                SizedBox(width: 4),
                Text('Start typing...'),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      // Editor should render without errors
      expect(find.byType(EditorView), findsOneWidget);
    });

    testWidgets('placeholder extension allows typing', (tester) async {
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: placeholder('Type here...'),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              onUpdate: (update) {
                state = update.state;
              },
            ),
          ),
        ),
      );

      // Tap to focus and type
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.pump();

      // Text should have been entered
      expect(state.doc.toString(), equals('x'));
    });

    testWidgets('multiple editors with placeholder', (tester) async {
      final state1 = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: placeholder('Editor 1 placeholder'),
        ),
      );
      final state2 = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: placeholder('Editor 2 placeholder'),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: EditorView(state: state1)),
                Expanded(child: EditorView(state: state2)),
              ],
            ),
          ),
        ),
      );

      // Both editors should render
      expect(find.byType(EditorView), findsNWidgets(2));
    });
  });
}
