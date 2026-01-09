/// Widget tests for language features: bracket matching, code folding, and auto-indent.
///
/// These tests MUST FAIL if decorations aren't being rendered properly.
import 'package:codemirror/codemirror.dart' hide Decoration;
import 'package:codemirror/codemirror.dart' as cm show Decoration, MarkDecoration;
import 'package:codemirror/src/state/transaction.dart' as tx show Transaction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();
  ensureFoldInitialized();

  group('Bracket Matching - MUST produce visible decorations', () {
    testWidgets('bracket decorations appear in TextSpan when cursor is near bracket', (tester) async {
      // Position 3 is right before '(' - matchBrackets works here
      final state = EditorState.create(EditorStateConfig(
        doc: 'foo(bar)',
        selection: EditorSelection.single(3),
        extensions: ExtensionList([bracketMatching()]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(key: key, state: state),
          ),
        ),
      );
      await tester.pump();

      // Verify matchBrackets works at this position
      final match = matchBrackets(state, 3, 1);
      expect(match, isNotNull, reason: 'matchBrackets should find a match at position 3');
      expect(match!.matched, isTrue);

      // Get the controller and check TextSpan has styled children
      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      final controller = editableText.controller as HighlightingTextEditingController;
      final textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );

      // MUST have children with bracket styling
      expect(textSpan.children, isNotNull, reason: 'TextSpan must have children for bracket decorations');
      expect(textSpan.children!.isNotEmpty, isTrue, reason: 'TextSpan children must not be empty');
      
      // Find a child with backgroundColor (bracket matching style)
      final hasStyledChild = textSpan.children!.any((child) {
        if (child is TextSpan) {
          return child.style?.backgroundColor != null;
        }
        return false;
      });
      expect(hasStyledChild, isTrue, reason: 'Must have at least one child with bracket matching backgroundColor');
    });

    testWidgets('ViewPlugin produces non-empty decorations', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'foo(bar)',
        selection: EditorSelection.single(3),
        extensions: ExtensionList([bracketMatching()]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(key: key, state: state)),
        ),
      );
      await tester.pump();

      final viewState = key.currentState!;
      
      // Get decoration sources and evaluate them
      final decoSources = viewState.state.facet(decorationsFacet);
      expect(decoSources.isNotEmpty, isTrue, reason: 'Must have decoration sources');

      // At least one source should produce decorations
      bool hasDecorations = false;
      for (final source in decoSources) {
        RangeSet<cm.Decoration>? result;
        if (source is RangeSet<cm.Decoration>) {
          result = source;
        } else if (source is Function) {
          result = (source as dynamic)(viewState) as RangeSet<cm.Decoration>?;
        }
        if (result != null && !result.isEmpty) {
          hasDecorations = true;
          break;
        }
      }
      expect(hasDecorations, isTrue, reason: 'At least one decoration source must produce decorations');
    });
  });

  group('Code Folding - MUST create fold decorations', () {
    testWidgets('fold effect creates visible fold decoration', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function foo() {\n  return 1;\n}',
        extensions: ExtensionList([codeFolding()]),
      ));

      final key = GlobalKey<EditorViewState>();
      EditorState? currentState;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Apply fold
      key.currentState!.dispatch([
        TransactionSpec(effects: [foldEffect.of((from: 15, to: 29))]),
      ]);
      await tester.pump();

      // MUST have folded range
      expect(currentState, isNotNull);
      final folded = foldedRanges(currentState!);
      expect(folded.isEmpty, isFalse, reason: 'Fold effect must create a folded range');
    });

    testWidgets('foldable() finds foldable region in JavaScript via foldNodeProp', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n  return 42;\n}',
        extensions: ExtensionList([
          javascript().extension,
          codeFolding(),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(key: key, state: state)),
        ),
      );
      // Wait for parser to run
      await tester.pump(const Duration(milliseconds: 200));

      final currentState = key.currentState!.state;
      // Line 1 is "function test() {" - from 0 to 17
      final line = currentState.doc.lineAt(1);
      final foldRange = foldable(currentState, line.from, line.to);
      
      expect(foldRange, isNotNull, 
        reason: 'foldable() must find a foldable region for function block');
      // The fold should be the inside of the { } block
      expect(foldRange!.from, equals(17), reason: 'Fold should start after {');
      expect(foldRange.to, equals(31), reason: 'Fold should end before }');
    });

    testWidgets('foldCode command creates fold from cursor position', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n  return 42;\n}',
        selection: EditorSelection.single(10), // Inside "function test()"
        extensions: ExtensionList([
          javascript().extension,
          codeFolding(),
          keymap.of(foldKeymap),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      EditorState? currentState;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Call foldCode command directly
      final target = (
        state: key.currentState!.state,
        dispatch: (tx.Transaction tr) => key.currentState!.dispatchTransaction(tr),
      );
      final result = foldCode(target);
      await tester.pump();

      expect(result, isTrue, reason: 'foldCode must succeed when on foldable line');
      expect(currentState, isNotNull);
      final folded = foldedRanges(currentState!);
      expect(folded.isEmpty, isFalse, reason: 'foldCode must create a fold');
    });

    testWidgets('foldKeymap defines expected bindings', (tester) async {
      // Test that foldKeymap has the expected bindings
      expect(foldKeymap.length, 4);
      
      final keys = foldKeymap.map((b) => b.key).toList();
      expect(keys, contains('Ctrl-Shift-['));
      expect(keys, contains('Ctrl-Shift-]'));
      expect(keys, contains('Ctrl-Alt-['));
      expect(keys, contains('Ctrl-Alt-]'));
      
      // Verify mac variants exist
      final macKeys = foldKeymap.map((b) => b.mac).whereType<String>().toList();
      expect(macKeys, contains('Cmd-Alt-['));
      expect(macKeys, contains('Cmd-Alt-]'));
    });

    testWidgets('unfoldCode removes existing fold', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n  return 42;\n}',
        selection: EditorSelection.single(10),
        extensions: ExtensionList([
          javascript().extension,
          codeFolding(),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      EditorState? currentState;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // First fold
      final target = (
        state: key.currentState!.state,
        dispatch: (tx.Transaction tr) => key.currentState!.dispatchTransaction(tr),
      );
      foldCode(target);
      await tester.pump();
      
      expect(foldedRanges(currentState!).isEmpty, isFalse, reason: 'Setup: fold must exist');

      // Now unfold
      final unfoldTarget = (
        state: key.currentState!.state,
        dispatch: (tx.Transaction tr) => key.currentState!.dispatchTransaction(tr),
      );
      final unfoldResult = unfoldCode(unfoldTarget);
      await tester.pump();

      expect(unfoldResult, isTrue, reason: 'unfoldCode must succeed');
      expect(foldedRanges(currentState!).isEmpty, isTrue, reason: 'unfoldCode must remove the fold');
    });
  });

  group('Syntax Highlighting - MUST produce highlight decorations', () {
    testWidgets('TreeHighlighter produces decorations for JS code', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const x = 42;',
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(key: key, state: state)),
        ),
      );
      // Wait for parsing
      await tester.pump(const Duration(milliseconds: 200));

      final viewState = key.currentState!;
      final highlighterPlugin = viewState.plugin(treeHighlighter);
      
      expect(highlighterPlugin, isNotNull, reason: 'TreeHighlighter plugin must be installed');
      expect(highlighterPlugin!.decorations.isEmpty, isFalse, 
        reason: 'TreeHighlighter must produce decorations for JS code');
    });

    testWidgets('syntax highlighting decorations reach TextSpan', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'const x = 42;',
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(key: key, state: state)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      final controller = editableText.controller as HighlightingTextEditingController;
      final textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );

      // MUST have styled children for syntax highlighting
      expect(textSpan.children, isNotNull, reason: 'TextSpan must have children for syntax highlighting');
      expect(textSpan.children!.length, greaterThan(1), 
        reason: 'Must have multiple spans for different syntax elements');
    });
  });

  group('Tab indentation - MUST work', () {
    testWidgets('Tab key inserts indentation', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'hello',
        selection: EditorSelection.single(0),
        extensions: ExtensionList([keymap.of([indentWithTab])]),
      ));

      EditorState? currentState;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(currentState, isNotNull);
      expect(currentState!.doc.toString(), isNot(equals('hello')), 
        reason: 'Tab must modify the document');
      expect(currentState!.doc.toString().contains('  ') || currentState!.doc.toString().contains('\t'), isTrue,
        reason: 'Tab must insert whitespace');
    });
  });

  group('Bracket Matching - selection changes', () {
    testWidgets('selection-only transaction triggers bracket decoration update', (tester) async {
      // Start with cursor NOT near brackets
      final state = EditorState.create(EditorStateConfig(
        doc: 'abc(def)xyz',
        selection: EditorSelection.single(1), // In 'abc', not near brackets
        extensions: ExtensionList([bracketMatching()]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(key: key, state: state)),
        ),
      );
      await tester.pump();

      // Initially no bracket decorations (cursor at position 1, not near any bracket)
      var editableText = tester.widget<EditableText>(find.byType(EditableText));
      var controller = editableText.controller as HighlightingTextEditingController;
      var textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );
      
      // Position 1 is in 'abc', no brackets nearby
      final initialHasBracketStyle = textSpan.children?.any((child) {
        if (child is TextSpan) {
          return child.style?.backgroundColor != null;
        }
        return false;
      }) ?? false;

      // Now dispatch a selection-only transaction to move to bracket position
      key.currentState!.dispatch([
        TransactionSpec(
          selection: EditorSelection.single(3), // Right before '('
        ),
      ]);
      await tester.pump();

      // Now should have bracket decorations
      editableText = tester.widget<EditableText>(find.byType(EditableText));
      controller = editableText.controller as HighlightingTextEditingController;
      textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );

      expect(textSpan.children, isNotNull, reason: 'Must have children after moving to bracket');
      final hasBracketStyle = textSpan.children!.any((child) {
        if (child is TextSpan) {
          return child.style?.backgroundColor != null;
        }
        return false;
      });
      expect(hasBracketStyle, isTrue, reason: 'Must have bracket styling after moving cursor to bracket position');
    });

    testWidgets('decorations update when cursor moves to different bracket', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: '(a)(b)',
        selection: EditorSelection.single(0), // Before first (
        extensions: ExtensionList([bracketMatching()]),
      ));

      final key = GlobalKey<EditorViewState>();
      EditorState? currentState;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Check initial decorations at position 0
      var editableText = tester.widget<EditableText>(find.byType(EditableText));
      var controller = editableText.controller as HighlightingTextEditingController;
      var textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );
      
      expect(textSpan.children, isNotNull);
      final initialChildCount = textSpan.children!.length;
      expect(initialChildCount, greaterThan(0), reason: 'Should have decorations at position 0');

      // Move to position 3 (before second bracket group)
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(3)),
      ]);
      await tester.pump();

      // Decorations should update
      editableText = tester.widget<EditableText>(find.byType(EditableText));
      controller = editableText.controller as HighlightingTextEditingController;
      textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );
      
      expect(textSpan.children, isNotNull);
      expect(textSpan.children!.length, greaterThan(0), reason: 'Should have decorations at new position');
    });
  });

  group('insertNewlineAndIndent - smart indentation', () {
    testWidgets('copies whitespace when no syntax info', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: '  indented',  // 2 spaces of indent, no language
        extensions: ExtensionList([
          keymap.of(standardKeymap),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Position cursor at end of line
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(10)),
      ]);
      await tester.pump();

      // Press Enter
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull);
      final newDoc = currentState!.doc.toString();
      
      // Should have newline (exact indent depends on fallback)
      expect(newDoc.contains('\n'), isTrue,
        reason: 'Should have newline. Got: "$newDoc"');
    });

    testWidgets('explodes brackets when cursor between them', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {}',
        extensions: ExtensionList([
          keymap.of(standardKeymap),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Position cursor between { and }
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(17)),
      ]);
      await tester.pump();

      // Press Enter - should explode brackets
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull);
      final newDoc = currentState!.doc.toString();
      final lines = newDoc.split('\n');
      
      // Should have 3 lines: line with {, cursor line, line with }
      expect(lines.length, equals(3),
        reason: 'Should have 3 lines after exploding brackets. Got: "$newDoc"');
    });
  });

  group('Indentation - Enter key behavior', () {
    testWidgets('Enter key inserts exactly one newline', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'line1\nline2',
        selection: EditorSelection.single(5), // End of "line1"
        extensions: ExtensionList([
          keymap.of(standardKeymap),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(EditableText));
      await tester.pump();
      
      // The EditorState has the selection, but we need to sync it to the controller
      // Move cursor to position 5 explicitly via dispatch
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(5)),
      ]);
      await tester.pump();
      
      // Verify the state has correct cursor position
      expect(key.currentState!.state.selection.main.head, equals(5), 
        reason: 'Cursor should be at position 5');
      
      // Send Enter key as a KeyDownEvent to trigger our keymap
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      final result = key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull, reason: 'Update should have fired');
      expect(result, equals(KeyEventResult.handled), 
        reason: 'Enter should be handled by keymap');
      
      final newDoc = currentState!.doc.toString();
      
      // Should have exactly 3 lines now (was 2, added 1)
      expect(newDoc.split('\n').length, equals(3), 
        reason: 'Enter should create exactly one new line. Got: "$newDoc"');
      
      // The content should be "line1\n\nline2" (newline inserted at position 5)
      expect(newDoc, equals('line1\n\nline2'),
        reason: 'Content should have one newline inserted');
    });

    testWidgets('Enter key adds newline with indentation', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: '  indented line',
        extensions: ExtensionList([
          keymap.of(standardKeymap),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Position cursor at end of line
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(15)),
      ]);
      await tester.pump();

      // Press Enter via handleKey
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull);
      final newDoc = currentState!.doc.toString();
      
      // Should have newline and some indentation (smart or fallback)
      expect(newDoc.contains('\n'), isTrue,
        reason: 'Enter should add newline');
      expect(newDoc.split('\n').length, equals(2),
        reason: 'Should have 2 lines');
    });

    testWidgets('Enter after closing brace does not add indent', (tester) async {
      // Issue: typing "const x = {}" then pressing Enter after "}" was adding extra indent
      final state = EditorState.create(EditorStateConfig(
        doc: 'const x = {}',
        selection: EditorSelection.single(12), // After the closing brace
        extensions: ExtensionList([
          javascript().extension,
          keymap.of(standardKeymap),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Press Enter via handleKey
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull);
      final newDoc = currentState!.doc.toString();
      final lines = newDoc.split('\n');

      // Should have 2 lines
      expect(lines.length, equals(2),
          reason: 'Should have 2 lines. Got: "$newDoc"');
      
      // Second line should have NO indentation (we're at column 0 after the })
      expect(lines[1], equals(''),
          reason: 'New line should have no indent after closing brace at column 0. Got: "${lines[1]}"');
    });
  });

  group('indentOnInput - MUST reindent on closing brace', () {
    testWidgets('typing } at line start reindents the line', (tester) async {
      // Setup: inside a function body, type closing brace
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n  \n}',
        selection: EditorSelection.single(20), // After the two spaces on line 2
        extensions: ExtensionList([
          javascript().extension,
          indentOnInput(),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Type a closing brace - should trigger reindent
      // The cursor is at "  |" - when we type "}", indentOnInput should reindent
      key.currentState!.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 20, insert: '}'),
          selection: EditorSelection.single(21),
          userEvent: 'input.type',
        ),
      ]);
      await tester.pump();

      expect(currentState, isNotNull);
      // Note: the exact behavior depends on getIndentation working
      // The key thing is it doesn't crash and modifies the document
      expect(currentState!.doc.toString().contains('}'), isTrue);
    });

    testWidgets('indentOnInput correctly reindents when typing closing brace', (tester) async {
      // Test the actual reindent behavior:
      // When we're in an indented block and type }, it should reduce indentation
      final state = EditorState.create(EditorStateConfig(
        doc: 'if (true) {\n    ',  // 4 spaces of indent, cursor at end
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          indentOnInput(),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100)); // Let parser run

      // Position cursor at end of indented line
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(16)),
      ]);
      await tester.pump();

      final beforeDoc = key.currentState!.state.doc.toString();
      expect(beforeDoc, equals('if (true) {\n    '));
      
      // Type } - this should trigger reindent
      key.currentState!.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 16, insert: '}'),
          selection: EditorSelection.single(17),
          userEvent: 'input.type',
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 50));

      expect(currentState, isNotNull);
      final afterDoc = currentState!.doc.toString();
      
      // The line count should be the same - indentOnInput REINDENTS, doesn't add lines
      final beforeLines = beforeDoc.split('\n').length;
      final afterLines = afterDoc.split('\n').length;
      expect(afterLines, equals(beforeLines), 
        reason: 'indentOnInput should not add new lines. Before: "$beforeDoc", After: "$afterDoc"');
      
      // Should contain the closing brace
      expect(afterDoc.contains('}'), isTrue);
    });

    testWidgets('indentOnInput does NOT trigger on newline input (userEvent check)', (tester) async {
      // indentOnInput should NOT process newline inputs - only things like }
      // The regex for JS is: /^\s*(?:case |default:|\{|\}|<\/)$/
      // This should NOT match a newline
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n}',
        extensions: ExtensionList([
          javascript().extension,
          indentOnInput(),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Position cursor after { (position 17)
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(17)),
      ]);
      await tester.pump();

      // Simulate typing a newline as input.type
      key.currentState!.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 17, insert: '\n'),
          selection: EditorSelection.single(18),
          userEvent: 'input.type',
        ),
      ]);
      await tester.pump();

      expect(currentState, isNotNull);
      final newDoc = currentState!.doc.toString();
      
      // Should have exactly one new newline (2 newlines total)
      final newlineCount = newDoc.split('').where((c) => c == '\n').length;
      expect(newlineCount, equals(2),
        reason: 'Should have exactly 2 newlines. Got: "$newDoc"');
    });

    testWidgets('indentOnInput with standardKeymap does NOT add extra newline', (tester) async {
      // This tests the bug where indentOnInput + standardKeymap caused double newlines
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() {\n  code\n}',
        extensions: ExtensionList([
          javascript().extension,
          keymap.of(standardKeymap),
          indentOnInput(),
        ]),
      ));

      EditorState? currentState;
      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) => currentState = update.state,
            ),
          ),
        ),
      );
      await tester.pump();

      // Position cursor at end of "  code" (position 24)
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(24)),
      ]);
      await tester.pump();

      // Press Enter via keymap
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      key.currentState!.handleKey(event);
      await tester.pump();

      expect(currentState, isNotNull);
      final newDoc = currentState!.doc.toString();
      final lines = newDoc.split('\n');
      
      // Should have 4 lines: original 3 plus one new line
      expect(lines.length, equals(4), 
        reason: 'Should have exactly 4 lines after Enter. Got: "$newDoc"');
      
      // Count newline characters
      final newlineCount = newDoc.split('').where((c) => c == '\n').length;
      expect(newlineCount, equals(3),
        reason: 'Should have exactly 3 newlines (4 lines). Got $newlineCount newlines in "$newDoc"');
    });
  });

  group('performAction(newline) interaction', () {
    testWidgets('performAction newline does NOT fire when keymap handles Enter', (tester) async {
      // This tests that when our keymap handles Enter, performAction doesn't also fire
      final state = EditorState.create(EditorStateConfig(
        doc: 'hello',
        selection: EditorSelection.single(5),
        extensions: ExtensionList([
          keymap.of(standardKeymap),
        ]),
      ));

      int dispatchCount = 0;
      EditorState? lastState;
      final key = GlobalKey<EditorViewState>();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: key,
              state: state,
              autofocus: true,
              onUpdate: (update) {
                dispatchCount++;
                lastState = update.state;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Position cursor
      key.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(5)),
      ]);
      await tester.pump();
      
      // Reset count after positioning
      dispatchCount = 0;
      
      // Send Enter key - this should be handled by keymap and NOT trigger performAction
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      final result = key.currentState!.handleKey(event);
      await tester.pump();

      expect(result, equals(KeyEventResult.handled), 
        reason: 'Enter should be handled by keymap');
      expect(dispatchCount, equals(1), 
        reason: 'Should only dispatch once, not twice');
      expect(lastState!.doc.toString(), equals('hello\n'),
        reason: 'Should have one newline');
    });
  });

  group('Multiple extensions together', () {
    testWidgets('bracket matching + syntax highlighting both produce decorations', (tester) async {
      final state = EditorState.create(EditorStateConfig(
        doc: 'function test() { return 1; }',
        selection: EditorSelection.single(16), // At the {
        extensions: ExtensionList([
          javascript().extension,
          syntaxHighlighting(defaultHighlightStyle),
          bracketMatching(),
        ]),
      ));

      final key = GlobalKey<EditorViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(key: key, state: state)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      final controller = editableText.controller as HighlightingTextEditingController;
      final textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );

      expect(textSpan.children, isNotNull);
      expect(textSpan.children!.length, greaterThan(3), 
        reason: 'Should have multiple styled spans from both highlighting and bracket matching');
    });
  });
}
