import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart' hide Text;

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureLanguageInitialized();
    ensureFoldInitialized();
  });

  group('Fold Gutter Widget Tests', () {
    final sampleJS = '''function test() {
  const obj = {
    a: 1,
    b: 2
  };
  return obj;
}
''';

    testWidgets('foldGutter extension registers correctly', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            foldGutter(),
          ]),
        ),
      );

      final gutterConfigs = state.facet(activeGutters);
      expect(gutterConfigs, isNotEmpty);
      expect(
        gutterConfigs.any((c) => c.className == 'cm-foldGutter'),
        isTrue,
        reason: 'Should have fold gutter config',
      );
    });

    testWidgets('foldGutter renders fold markers', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            syntaxHighlighting(defaultHighlightStyle),
            foldGutter(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorView(state: state, onUpdate: (_) {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Look for fold markers (open text "⌄")
      expect(find.text('⌄'), findsWidgets,
          reason: 'Should find fold markers for foldable lines');
    });

    testWidgets('foldState field is created with codeFolding', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            codeFolding(),
          ]),
        ),
      );

      final field = state.field(foldState, false);
      expect(field, isNotNull, reason: 'foldState field should be present');
      expect(field!.isEmpty, isTrue, reason: 'Should start with no folds');
    });

    testWidgets('folding a range creates decoration', (tester) async {
      var state = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            codeFolding(),
          ]),
        ),
      );

      // Find a foldable range for the first line (function declaration)
      final line1 = state.doc.line(1);
      final range = foldable(state, line1.from, line1.to);
      expect(range, isNotNull, reason: 'Function block should be foldable');

      // Apply the fold
      final tr = state.update([
        TransactionSpec(effects: [foldEffect.of(range!)]),
      ]);
      state = tr.state as EditorState;

      // Check fold state
      final folded = state.field(foldState, false);
      expect(folded?.isEmpty, isFalse, reason: 'Should have one fold');
    });

    testWidgets('clicking fold marker dispatches fold effect', (tester) async {
      late EditorState currentState;
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            syntaxHighlighting(defaultHighlightStyle),
            foldGutter(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return EditorView(
                    state: currentState,
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
        ),
      );

      await tester.pumpAndSettle();

      // Initially should have no folds
      final initialFoldState = currentState.field(foldState, false);
      expect(initialFoldState == null || initialFoldState.isEmpty, isTrue,
          reason: 'Should start with no folds');

      // Find and tap the first fold marker
      final foldMarkers = find.text('⌄');
      expect(foldMarkers, findsWidgets, reason: 'Should have fold markers');

      // Tap the first fold marker
      await tester.tap(foldMarkers.first);
      await tester.pumpAndSettle();

      // Should now have a fold
      final afterFoldState = currentState.field(foldState, false);
      expect(afterFoldState, isNotNull, reason: 'Fold state should be present');
      expect(afterFoldState!.isEmpty, isFalse,
          reason: 'Should have one fold after clicking');
    });

    testWidgets('clicking unfold marker removes fold', (tester) async {
      late EditorState currentState;
      
      // Create state with a fold already applied
      var initialState = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            syntaxHighlighting(defaultHighlightStyle),
            foldGutter(),
          ]),
        ),
      );

      // Apply a fold manually
      final line1 = initialState.doc.line(1);
      final range = foldable(initialState, line1.from, line1.to);
      expect(range, isNotNull);
      
      final tr = initialState.update([
        TransactionSpec(effects: [foldEffect.of(range!)]),
      ]);
      currentState = tr.state as EditorState;

      // Verify fold is present
      expect(currentState.field(foldState, false)?.isEmpty, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return EditorView(
                    state: currentState,
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
        ),
      );

      await tester.pumpAndSettle();

      // Find the unfold marker (closed text "›")
      final unfoldMarkers = find.text('›');
      expect(unfoldMarkers, findsWidgets, reason: 'Should have unfold marker');

      // Tap the unfold marker
      await tester.tap(unfoldMarkers.first);
      await tester.pumpAndSettle();

      // Fold should be removed
      final afterUnfold = currentState.field(foldState, false);
      expect(afterUnfold == null || afterUnfold.isEmpty, isTrue,
          reason: 'Fold should be removed after clicking unfold marker');
    });

    testWidgets('foldable detects JavaScript function blocks', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
          ]),
        ),
      );

      // Line 1: function test() { - should be foldable
      final line1 = state.doc.line(1);
      final range1 = foldable(state, line1.from, line1.to);
      expect(range1, isNotNull, reason: 'Function should be foldable');

      // Line 2: const obj = { - should be foldable (object literal)
      final line2 = state.doc.line(2);
      final range2 = foldable(state, line2.from, line2.to);
      expect(range2, isNotNull, reason: 'Object literal should be foldable');

      // Line 3: a: 1, - not foldable
      final line3 = state.doc.line(3);
      final range3 = foldable(state, line3.from, line3.to);
      expect(range3, isNull, reason: 'Property line should not be foldable');
    });

    testWidgets('FoldGutterConfig stores custom text', (tester) async {
      // Note: Due to singleton state field initialization, custom configs
      // are captured by the first foldGutter() call. This test verifies
      // the config object itself stores values correctly.
      const customConfig = FoldGutterConfig(
        openText: '[+]',
        closedText: '[-]',
      );

      expect(customConfig.openText, '[+]');
      expect(customConfig.closedText, '[-]');
      
      const defaultConfig = FoldGutterConfig();
      expect(defaultConfig.openText, '⌄');
      expect(defaultConfig.closedText, '›');
    });

    testWidgets('foldable returns null for non-foldable content', (tester) async {
      // Test that foldable() correctly returns null for simple statements
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'const x = 1;',
          extensions: ExtensionList([
            javascript(),
          ]),
        ),
      );

      final line1 = state.doc.line(1);
      final range = foldable(state, line1.from, line1.to);
      expect(range, isNull, reason: 'Simple statement should not be foldable');
    });

    testWidgets('foldedRanges helper returns current folds', (tester) async {
      var state = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            codeFolding(),
          ]),
        ),
      );

      expect(foldedRanges(state).isEmpty, isTrue);

      // Apply fold
      final line1 = state.doc.line(1);
      final range = foldable(state, line1.from, line1.to)!;
      final tr = state.update([
        TransactionSpec(effects: [foldEffect.of(range)]),
      ]);
      state = tr.state as EditorState;

      final folded = foldedRanges(state);
      expect(folded.isEmpty, isFalse);
    });
  });

  group('Fold Decoration Rendering', () {
    testWidgets('fold decoration does not crash editor render', (tester) async {
      final sampleJS = '''function outer() {
  return 42;
}
''';
      late EditorState currentState;
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            syntaxHighlighting(defaultHighlightStyle),
            codeFolding(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return EditorView(
                    state: currentState,
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
        ),
      );

      await tester.pumpAndSettle();

      // Apply fold programmatically
      final line1 = currentState.doc.line(1);
      final range = foldable(currentState, line1.from, line1.to);
      expect(range, isNotNull, reason: 'Function should be foldable');

      final tr = currentState.update([
        TransactionSpec(effects: [foldEffect.of(range!)]),
      ]);
      currentState = tr.state as EditorState;

      // This should not throw
      await tester.pumpAndSettle();

      // Editor should still render without errors
      expect(find.byType(EditorView), findsOneWidget);
      
      // Verify fold is in state
      final folded = currentState.field(foldState, false);
      expect(folded?.isEmpty, isFalse, reason: 'Fold should be present');
    });

    testWidgets('clicking fold marker in foldGutter triggers fold via view dispatch', (tester) async {
      final sampleJS = '''function test() {
  const obj = {
    a: 1,
    b: 2
  };
  return obj;
}
''';
      late EditorState currentState;
      var foldTriggered = false;
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: sampleJS,
          extensions: ExtensionList([
            javascript(),
            syntaxHighlighting(defaultHighlightStyle),
            foldGutter(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return EditorView(
                    state: currentState,
                    onUpdate: (update) {
                      // Check if fold effect was in this update
                      for (final tr in update.transactions) {
                        for (final e in tr.effects) {
                          if (e.is_(foldEffect)) {
                            foldTriggered = true;
                          }
                        }
                      }
                      setState(() {
                        currentState = update.state;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find fold markers
      final foldMarkers = find.text('⌄');
      expect(foldMarkers, findsWidgets, reason: 'Should have fold markers');
      
      // Tap the first fold marker
      await tester.tap(foldMarkers.first);
      await tester.pumpAndSettle();

      // Fold should have been triggered
      expect(foldTriggered, isTrue, reason: 'Fold effect should have been dispatched');
      
      // State should have fold
      final foldedState = currentState.field(foldState, false);
      expect(foldedState?.isEmpty, isFalse, reason: 'State should have fold after click');
    });
  });

  group('Fold Commands', () {
    final sampleCode = '''function outer() {
  function inner() {
    return 42;
  }
  return inner();
}
''';

    testWidgets('foldCode command folds at cursor', (tester) async {
      late EditorState currentState;
      late EditorViewState viewState;
      final key = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: sampleCode,
          selection: EditorSelection.single(0), // Cursor at start
          extensions: ExtensionList([
            javascript(),
            codeFolding(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return EditorView(
                    key: key,
                    state: currentState,
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
        ),
      );

      await tester.pumpAndSettle();
      viewState = key.currentState!;

      // Initially no folds
      expect(currentState.field(foldState, false)?.isEmpty ?? true, isTrue);

      // Execute fold command
      final target = (
        state: viewState.state,
        dispatch: (tr) => viewState.dispatchTransaction(tr),
      );
      final result = foldCode(target);
      expect(result, isTrue, reason: 'foldCode should succeed');

      await tester.pumpAndSettle();

      // Should now have a fold
      expect(currentState.field(foldState, false)?.isEmpty ?? true, isFalse,
          reason: 'Should have fold after command');
    });

    testWidgets('unfoldCode command removes fold at cursor', (tester) async {
      late EditorState currentState;
      late EditorViewState viewState;
      final key = GlobalKey<EditorViewState>();
      
      // Start with a folded state
      var initialState = EditorState.create(
        EditorStateConfig(
          doc: sampleCode,
          selection: EditorSelection.single(0),
          extensions: ExtensionList([
            javascript(),
            codeFolding(),
          ]),
        ),
      );

      // Apply fold
      final line1 = initialState.doc.line(1);
      final range = foldable(initialState, line1.from, line1.to)!;
      final tr = initialState.update([
        TransactionSpec(effects: [foldEffect.of(range)]),
      ]);
      currentState = tr.state as EditorState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return EditorView(
                    key: key,
                    state: currentState,
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
        ),
      );

      await tester.pumpAndSettle();
      viewState = key.currentState!;

      // Should have fold
      expect(currentState.field(foldState, false)?.isEmpty, isFalse);

      // Execute unfold command
      final target = (
        state: viewState.state,
        dispatch: (tr) => viewState.dispatchTransaction(tr),
      );
      final result = unfoldCode(target);
      expect(result, isTrue, reason: 'unfoldCode should succeed');

      await tester.pumpAndSettle();

      // Should have no folds
      expect(currentState.field(foldState, false)?.isEmpty ?? true, isTrue,
          reason: 'Should have no folds after unfold');
    });
  });
}
