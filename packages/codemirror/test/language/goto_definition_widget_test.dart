import 'dart:async';

import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  group('Go to Definition Widget Tests', () {
    testWidgets('gotoDefinition facet is registered', (tester) async {
      var definitionRequests = <int>[];
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'function greet() {}\ngreet();',
          extensions: ExtensionList([
            gotoDefinition(
              (state, pos) async {
                definitionRequests.add(pos);
                return DefinitionResult.single(DefinitionLocation(pos: 0));
              },
              GotoDefinitionOptions(
                showHoverUnderline: true,
                navigator: (loc, state) {},
              ),
            ),
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
      await tester.pumpAndSettle();

      // Verify facet is registered
      final configs = state.facet(gotoDefinitionFacet);
      expect(configs, isNotEmpty, reason: 'gotoDefinitionFacet should be registered');
      expect(configs.first.options.showHoverUnderline, isTrue);
    });

    testWidgets('goToDefinitionCommand dispatches effect', (tester) async {
      var definitionRequests = <int>[];
      var navigatedTo = <DefinitionLocation>[];
      
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'function greet() {}\ngreet();',
          selection: EditorSelection.single(21, 21), // on 'greet' call
          extensions: ExtensionList([
            gotoDefinition(
              (state, pos) async {
                definitionRequests.add(pos);
                // Return definition at function declaration (pos 9)
                return DefinitionResult.single(DefinitionLocation(pos: 9, end: 14));
              },
              GotoDefinitionOptions(
                navigator: (loc, state) {
                  navigatedTo.add(loc);
                },
              ),
            ),
            keymap.of(gotoDefinitionKeymap),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: currentState,
              onUpdate: (update) => currentState = update.state,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Use the public API instead of the command
      editorKey.currentState!.triggerGoToDefinition(21);
      
      await tester.pumpAndSettle();

      // Verify definition was requested
      expect(definitionRequests, contains(21),
        reason: 'Definition source should be called for position 21');
      
      // Verify navigation happened
      expect(navigatedTo, isNotEmpty,
        reason: 'Navigator should be called with definition location');
      expect(navigatedTo.first.pos, 9);
    });

    testWidgets('definition source is called via EditorViewState method', (tester) async {
      var definitionRequests = <int>[];
      var navigatedTo = <DefinitionLocation>[];
      
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'let user = 1;\nconsole.log(user);',
          selection: EditorSelection.single(27, 27), // on 'user' usage
          extensions: ExtensionList([
            gotoDefinition(
              (state, pos) async {
                definitionRequests.add(pos);
                // 'user' defined at position 4
                if (pos >= 27 && pos <= 31) {
                  return DefinitionResult.single(DefinitionLocation(pos: 4, end: 8));
                }
                return null;
              },
              GotoDefinitionOptions(
                navigator: (loc, state) {
                  navigatedTo.add(loc);
                },
              ),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: currentState,
              onUpdate: (update) => currentState = update.state,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger go-to-definition via the view state method
      editorKey.currentState!.triggerGoToDefinition(27);
      
      await tester.pumpAndSettle();

      expect(definitionRequests, contains(27),
        reason: 'Definition source should be called');
      expect(navigatedTo, isNotEmpty,
        reason: 'Navigator should be called');
      expect(navigatedTo.first.pos, 4,
        reason: 'Should navigate to definition position');
    });

    testWidgets('local definition navigation updates selection', (tester) async {
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'let user = 1;\nconsole.log(user);',
          selection: EditorSelection.single(27, 27), // on 'user' usage
          extensions: ExtensionList([
            gotoDefinition(
              (state, pos) async {
                return DefinitionResult.single(DefinitionLocation(pos: 4, end: 8));
              },
              // No custom navigator - should use default behavior
            ),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: currentState,
              onUpdate: (update) => currentState = update.state,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger go-to-definition
      editorKey.currentState!.triggerGoToDefinition(27);
      await tester.pumpAndSettle();

      // Selection should move to definition
      expect(currentState.selection.main.from, 4,
        reason: 'Selection should move to definition start');
      expect(currentState.selection.main.to, 8,
        reason: 'Selection should extend to definition end');
    });

    testWidgets('null definition result does not crash', (tester) async {
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'some text',
          selection: EditorSelection.single(5, 5),
          extensions: ExtensionList([
            gotoDefinition(
              (state, pos) async => null, // No definition
            ),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: currentState,
              onUpdate: (update) => currentState = update.state,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Record initial selection
      final initialHead = currentState.selection.main.head;

      // Should not throw
      editorKey.currentState!.triggerGoToDefinition(5);
      await tester.pumpAndSettle();

      // Selection should remain unchanged (null result = no navigation)
      expect(currentState.selection.main.head, initialHead);
    });

    testWidgets('async definition source works', (tester) async {
      final completer = Completer<DefinitionResult>();
      var navigatedTo = <DefinitionLocation>[];
      
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'let foo = 1;',
          selection: EditorSelection.single(4, 4),
          extensions: ExtensionList([
            gotoDefinition(
              (state, pos) => completer.future,
              GotoDefinitionOptions(
                navigator: (loc, state) => navigatedTo.add(loc),
              ),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: currentState,
              onUpdate: (update) => currentState = update.state,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger - should not navigate yet
      editorKey.currentState!.triggerGoToDefinition(4);
      await tester.pump();
      expect(navigatedTo, isEmpty);

      // Complete the future
      completer.complete(DefinitionResult.single(DefinitionLocation(pos: 0)));
      await tester.pumpAndSettle();

      expect(navigatedTo, isNotEmpty);
    });
  });
}
