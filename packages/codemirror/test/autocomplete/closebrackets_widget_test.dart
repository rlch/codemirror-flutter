import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart' hide Text;

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureLanguageInitialized();
  });

  group('closeBrackets widget tests', () {
    testWidgets('typing ( inserts () and positions cursor between', (tester) async {
      EditorState? currentState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorView(
            state: EditorState.create(EditorStateConfig(
              doc: '',
              extensions: ExtensionList([
                closeBrackets(),
              ]),
            )),
            onUpdate: (update) {
              currentState = update.state;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Debug: Print initial state
      print('Initial doc: "${currentState?.doc.toString()}"');
      print('Initial selection: ${currentState?.selection.main}');

      // Simulate typing '('
      await tester.enterText(find.byType(EditableText), '(');
      await tester.pumpAndSettle();

      print('After typing (: "${currentState?.doc.toString()}"');
      print('Selection after: ${currentState?.selection.main}');

      expect(currentState?.doc.toString(), '()');
      expect(currentState?.selection.main.head, 1);
    });
    
    testWidgets('can type additional text after bracket auto-close', (tester) async {
      EditorState? currentState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorView(
            state: EditorState.create(EditorStateConfig(
              doc: '',
              extensions: ExtensionList([
                closeBrackets(),
              ]),
            )),
            onUpdate: (update) {
              currentState = update.state;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Type ( - should become ()
      await tester.enterText(find.byType(EditableText), '(');
      await tester.pumpAndSettle();
      
      print('After (: doc="${currentState?.doc.toString()}", cursor=${currentState?.selection.main.head}');
      expect(currentState?.doc.toString(), '()');
      expect(currentState?.selection.main.head, 1, reason: 'cursor should be between brackets');
      
      // Now type 'x' inside the brackets
      // The controller should have "()" with cursor at 1
      // After typing 'x', it should become "(x)" with cursor at 2
      await tester.enterText(find.byType(EditableText), '(x)');
      await tester.pumpAndSettle();
      
      print('After x: doc="${currentState?.doc.toString()}", cursor=${currentState?.selection.main.head}');
      expect(currentState?.doc.toString(), '(x)', reason: 'should have x inside brackets');
      expect(currentState?.selection.main.head, 2, reason: 'cursor should be after x');
    });

    testWidgets('typing [ inserts []', (tester) async {
      EditorState? currentState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorView(
            state: EditorState.create(EditorStateConfig(
              doc: '',
              extensions: ExtensionList([
                closeBrackets(),
              ]),
            )),
            onUpdate: (update) {
              currentState = update.state;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), '[');
      await tester.pumpAndSettle();

      print('After typing [: "${currentState?.doc.toString()}"');

      expect(currentState?.doc.toString(), '[]');
    });

    testWidgets('debug: check if input handler is called', (tester) async {
      var inputHandlerCalled = false;
      EditorState? currentState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorView(
            state: EditorState.create(EditorStateConfig(
              doc: '',
              extensions: ExtensionList([
                closeBrackets(),
                // Debug input handler
                EditorView.inputHandler.of((view, from, to, text) {
                  print('Input handler called: from=$from, to=$to, text="$text"');
                  inputHandlerCalled = true;
                  return false; // Don't consume, let closeBrackets handle it
                }),
              ]),
            )),
            onUpdate: (update) {
              currentState = update.state;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Try sending text via channel
      tester.testTextInput.enterText('(');
      await tester.pumpAndSettle();

      print('inputHandlerCalled: $inputHandlerCalled');
      print('Final doc: "${currentState?.doc.toString()}"');

      // Check if anything was inserted at all
      expect(currentState?.doc.toString().isNotEmpty, true, reason: 'Document should not be empty after typing');
    });

    testWidgets('debug: check TextEditingDelta path', (tester) async {
      EditorState? currentState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorView(
            state: EditorState.create(EditorStateConfig(
              doc: 'hello',
              extensions: ExtensionList([
                closeBrackets(),
              ]),
            )),
            onUpdate: (update) {
              currentState = update.state;
              print('State updated: doc="${update.state.doc.toString()}"');
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Get the EditableText and simulate typing
      final editableText = find.byType(EditableText);
      await tester.tap(editableText);
      await tester.pumpAndSettle();

      // Try different methods of entering text
      print('--- Method 1: enterText ---');
      await tester.enterText(editableText, 'hello(');
      await tester.pumpAndSettle();
      print('Doc after enterText: "${currentState?.doc.toString()}"');

      // Reset
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorView(
            state: EditorState.create(EditorStateConfig(
              doc: '',
              extensions: ExtensionList([
                closeBrackets(),
              ]),
            )),
            onUpdate: (update) {
              currentState = update.state;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      print('--- Method 2: testTextInput ---');
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();
      
      tester.testTextInput.enterText('(');
      await tester.pumpAndSettle();
      print('Doc after testTextInput: "${currentState?.doc.toString()}"');
    });
  });
}
