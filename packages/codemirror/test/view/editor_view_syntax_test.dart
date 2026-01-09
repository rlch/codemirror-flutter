/// Tests for EditorView with syntax highlighting.
import 'package:codemirror/codemirror.dart';
import 'package:codemirror/src/language/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureLanguageInitialized();
  });

  group('EditorView syntax highlighting', () {
    final testCode = '''// Test comment
function greet(name) {
  const message = "Hello";
  return message;
}
''';

    testWidgets('creates state with full syntax tree', (tester) async {
      final langSupport = javascript();
      final state = EditorState.create(
        EditorStateConfig(
          doc: testCode,
          extensions: ExtensionList([
            langSupport.extension,
            syntaxHighlighting(defaultHighlightStyle),
          ]),
        ),
      );

      // Verify state has language field
      final langState = state.field(Language.state, false);
      expect(langState, isNotNull);
      
      // Verify tree
      final tree = syntaxTree(state);
      print('Tree before widget: type=${tree.type.name}, length=${tree.length}');
      
      var nodeCount = 0;
      final cursor = tree.cursor();
      do {
        nodeCount++;
        if (nodeCount <= 30) {
          print('  Node: ${cursor.type.name} [${cursor.from}-${cursor.to}]');
        }
      } while (cursor.next() && nodeCount < 200);
      print('  Total nodes before widget: $nodeCount');
      
      expect(nodeCount, greaterThan(10));
      
      // Now create the widget
      late EditorState widgetState;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              onUpdate: (update) {
                widgetState = update.state;
              },
            ),
          ),
        ),
      );
      
      await tester.pump();
      
      // After widget creation, check the state
      final finder = find.byType(EditorView);
      expect(finder, findsOneWidget);
      
      // Get the EditorViewState
      final viewState = tester.state<EditorViewState>(finder);
      final viewTree = syntaxTree(viewState.state);
      
      print('Tree after widget: type=${viewTree.type.name}, length=${viewTree.length}');
      
      var viewNodeCount = 0;
      final viewCursor = viewTree.cursor();
      do {
        viewNodeCount++;
        if (viewNodeCount <= 30) {
          print('  Node: ${viewCursor.type.name} [${viewCursor.from}-${viewCursor.to}]');
        }
      } while (viewCursor.next() && viewNodeCount < 200);
      print('  Total nodes after widget: $viewNodeCount');
      
      expect(viewNodeCount, greaterThan(10), reason: 'Widget state should have full tree');
    });
  });
}
