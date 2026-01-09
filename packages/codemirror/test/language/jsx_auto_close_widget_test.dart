import 'package:codemirror/codemirror.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JSX auto-close tags widget tests', () {
    testWidgets('typing > after <div inserts </div>', (tester) async {
      EditorState? currentState;
      
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final initialState = EditorState.create(EditorStateConfig(
        doc: '<div',
        selection: EditorSelection.single(4), // cursor after "v"
        extensions: ExtensionList([
          lang.extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));
      currentState = initialState;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return EditorView(
                  state: currentState!,
                  onUpdate: (update) {
                    setState(() {
                      currentState = update.state;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      print('Initial doc: "${currentState!.doc}"');
      print('Initial cursor: ${currentState!.selection.main.head}');
      
      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();
      
      // Type ">"
      await tester.enterText(find.byType(EditableText), '<div>');
      await tester.pumpAndSettle();
      
      print('After typing >: "${currentState!.doc}"');
      print('Cursor after: ${currentState!.selection.main.head}');
      
      // Check if auto-close happened
      // Expected: "<div></div>" with cursor at position 5 (after >)
      expect(currentState!.doc.toString(), equals('<div></div>'),
        reason: 'Should auto-close with </div>');
    });
    
    testWidgets('JSX extension is included in language support', (tester) async {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      
      // Check that jsxAutoCloseTags is in the support extensions
      print('Language support extension type: ${lang.extension.runtimeType}');
      print('Language support: ${lang.support.runtimeType}');
      
      // The extension should be an ExtensionList containing the language + support
      expect(lang.support, isNotNull);
    });
    
    testWidgets('debug: check input handler registration', (tester) async {
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final state = EditorState.create(EditorStateConfig(
        doc: '<div',
        extensions: ExtensionList([
          lang.extension,
        ]),
      ));
      
      // Check facet for input handlers
      final handlers = state.facet(EditorView.inputHandler);
      print('Number of input handlers: ${handlers.length}');
      for (var i = 0; i < handlers.length; i++) {
        print('  Handler $i: ${handlers[i].runtimeType}');
      }
      
      expect(handlers.length, greaterThan(0),
        reason: 'Should have at least one input handler (jsxAutoCloseTags)');
    });
    
    testWidgets('typing > in nested JSX inserts close tag', (tester) async {
      EditorState? currentState;
      
      final lang = javascript(const JavaScriptConfig(jsx: true));
      // Start with nested structure: <Center>\n  <Column
      final initialState = EditorState.create(EditorStateConfig(
        doc: '<Center>\n  <Column',
        selection: EditorSelection.single(18), // cursor after "Column"
        extensions: ExtensionList([
          lang.extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));
      currentState = initialState;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return EditorView(
                  state: currentState!,
                  onUpdate: (update) {
                    setState(() {
                      currentState = update.state;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      print('Initial doc: "${currentState!.doc}"');
      print('Initial cursor: ${currentState!.selection.main.head}');
      
      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();
      
      // Type ">"
      await tester.enterText(find.byType(EditableText), '<Center>\n  <Column>');
      await tester.pumpAndSettle();
      
      print('After typing >: "${currentState!.doc}"');
      print('Cursor after: ${currentState!.selection.main.head}');
      
      // Check if auto-close happened
      expect(currentState!.doc.toString(), equals('<Center>\n  <Column></Column>'),
        reason: 'Should auto-close nested <Column> with </Column>');
    });
    
    testWidgets('typing > for JSXMemberExpression inserts close tag', (tester) async {
      EditorState? currentState;
      
      final lang = javascript(const JavaScriptConfig(jsx: true));
      final initialState = EditorState.create(EditorStateConfig(
        doc: '<Text.h1',
        selection: EditorSelection.single(8), // cursor after "h1"
        extensions: ExtensionList([
          lang.extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));
      currentState = initialState;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return EditorView(
                  state: currentState!,
                  onUpdate: (update) {
                    setState(() {
                      currentState = update.state;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      print('Initial doc: "${currentState!.doc}"');
      print('Initial cursor: ${currentState!.selection.main.head}');
      
      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();
      
      // Type ">"
      await tester.enterText(find.byType(EditableText), '<Text.h1>');
      await tester.pumpAndSettle();
      
      print('After typing >: "${currentState!.doc}"');
      print('Cursor after: ${currentState!.selection.main.head}');
      
      // Check if auto-close happened
      expect(currentState!.doc.toString(), equals('<Text.h1></Text.h1>'),
        reason: 'Should auto-close <Text.h1> with </Text.h1>');
    });
  });
}
