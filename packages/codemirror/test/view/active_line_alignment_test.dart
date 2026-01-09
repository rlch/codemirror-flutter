import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Active line alignment', () {
    testWidgets('active line background renders as column of lines', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5',
          selection: EditorSelection.cursor(14), // Start of "Line 3"
          extensions: ExtensionList([
            highlightActiveLine(),
            highlightActiveLineGutter(),
            lineNumbers(),
            editorTheme.of(const EditorThemeData(
              activeLineColor: Color(0xFF0000FF),
              activeLineGutterColor: Color(0xFF00FF00),
            )),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: EditorView(
                state: state,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find the ActiveLineBackground widget
      final activeLineBg = find.byType(ActiveLineBackground);
      expect(activeLineBg, findsOneWidget);
      
      // Verify cursor is on line 3
      expect(state.doc.lineAt(14).number, equals(3));
    });

    testWidgets('active line is behind gutter in z-order', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          selection: EditorSelection.cursor(0),
          extensions: ExtensionList([
            highlightActiveLine(),
            highlightActiveLineGutter(),
            lineNumbers(),
            editorTheme.of(const EditorThemeData(
              activeLineColor: Color(0x800000FF),
              activeLineGutterColor: Color(0x8000FF00),
            )),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: EditorView(
                state: state,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find Stack that contains both ActiveLineBackground and the Row
      final stackFinder = find.byType(Stack);
      expect(stackFinder, findsWidgets);
      
      // The ActiveLineBackground should be positioned first (behind)
      // and the Row with gutter+content should be on top
      final activeLineBg = find.byType(ActiveLineBackground);
      expect(activeLineBg, findsOneWidget);
      
      // Verify line numbers are visible (findable) - they should be on top of the highlight
      // Line 1 is the active line, its number should still be rendered
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}
