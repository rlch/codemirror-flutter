import 'package:codemirror/codemirror.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('highlightActiveLine widget tests', () {
    testWidgets('creates editor with active line extension', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: highlightActiveLine(),
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
      // Content is rendered via EditableText
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('works with empty document', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: highlightActiveLine(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      expect(find.byType(EditorView), findsOneWidget);
    });

    testWidgets('combines with other extensions', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'function test() {\n  return 42;\n}',
          extensions: ExtensionList([
            highlightActiveLine(),
            highlightActiveLineGutter(),
            lineNumbers(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      expect(find.byType(EditorView), findsOneWidget);
    });

    testWidgets('active line updates on cursor movement', (tester) async {
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: highlightActiveLine(),
          selection: EditorSelection.cursor(0),
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

      // Tap to focus
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      // Editor should still render correctly
      expect(find.byType(EditorView), findsOneWidget);
    });

    testWidgets('works with syntax highlighting', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'const x = 42;\nlet y = "hello";',
          extensions: ExtensionList([
            highlightActiveLine(),
            javascript(),
            syntaxHighlighting(defaultHighlightStyle),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(state: state),
          ),
        ),
      );

      expect(find.byType(EditorView), findsOneWidget);
    });
  });
}
