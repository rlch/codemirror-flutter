import 'dart:async';

import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  group('Document Highlight Widget Tests', () {
    testWidgets('tap on symbol triggers highlight (replicates LSP demo)', (tester) async {
      // Replicate the exact LSP demo setup
      const sampleCode = '''let user = 1;
console.log(user);''';
      // 'user' at positions 4-8 (definition) and line 2 (usage)
      
      final highlightRequests = <int>[];
      var highlightsApplied = false;
      
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: sampleCode,
          selection: EditorSelection.single(0, 0), // Start at beginning
          extensions: ExtensionList([
            documentHighlight(
              (state, pos) async {
                highlightRequests.add(pos);
                // Simulate LSP: return highlights for 'user' variable
                // 'user' spans 4-8 in first line
                if (pos >= 4 && pos <= 8) {
                  return DocumentHighlightResult(const [
                    DocumentHighlight(from: 4, to: 8, kind: HighlightKind.write),
                    DocumentHighlight(from: 26, to: 30, kind: HighlightKind.read),
                  ]);
                }
                return null;
              },
              const DocumentHighlightOptions(delay: 10),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorView(
                key: editorKey,
                state: currentState,
                onUpdate: (update) {
                  currentState = update.state;
                  final hs = currentState.field(highlightStateField, false);
                  if (hs != null && hs.highlights.isNotEmpty) {
                    highlightsApplied = true;
                  }
                },
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dispatch a selection change to position 5 (on 'user')
      // This simulates what happens after clicking resolves to a position
      editorKey.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(5, 5)),
      ]);
      
      // Wait for debounce (10ms) + processing
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Verify highlight source was called
      expect(highlightRequests, contains(5),
        reason: 'Highlight source should be called after selection change');
      
      // Verify highlights were applied
      expect(highlightsApplied, isTrue,
        reason: 'Highlights should be applied to state field');
      
      final highlightState = currentState.field(highlightStateField, false);
      expect(highlightState?.highlights, hasLength(2),
        reason: 'Should have 2 highlights for user variable');
    });

    testWidgets('highlight source is called on selection change via dispatch', (tester) async {
      final requestedPositions = <int>[];
      
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'let x = 1; x = 2;',
          selection: EditorSelection.single(0, 0), // Start at beginning
          extensions: ExtensionList([
            documentHighlight(
              (state, pos) {
                requestedPositions.add(pos);
                return DocumentHighlightResult(const [
                  DocumentHighlight(from: 4, to: 5, kind: HighlightKind.write),
                  DocumentHighlight(from: 11, to: 12, kind: HighlightKind.read),
                ]);
              },
              const DocumentHighlightOptions(delay: 10),
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
              onUpdate: (update) {
                currentState = update.state;
              },
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Dispatch a selection change via the view
      editorKey.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(4, 4)),
      ]);
      
      // Wait for debounce delay
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(requestedPositions, contains(4), reason: 'Highlight source should be called for position 4');
    });

    testWidgets('setDocumentHighlights effect updates state field', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'let x = 1;',
          extensions: ExtensionList([
            documentHighlight((state, pos) async => null),
          ]),
        ),
      );

      final tr = state.update([
        setDocumentHighlights(const [
          DocumentHighlight(from: 4, to: 5, kind: HighlightKind.write),
        ]),
      ]);
      final newState = tr.state as EditorState;

      final highlightState = newState.field(highlightStateField, false);
      expect(highlightState, isNotNull);
      expect(highlightState!.highlights, hasLength(1));
      expect(highlightState.highlights.first.kind, HighlightKind.write);
    });

    testWidgets('clearDocumentHighlights effect clears state field', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'let x = 1;',
          extensions: ExtensionList([
            documentHighlight((state, pos) async => null),
          ]),
        ),
      );

      final tr1 = state.update([
        setDocumentHighlights(const [DocumentHighlight(from: 4, to: 5)]),
      ]);
      final state2 = tr1.state as EditorState;
      expect(state2.field(highlightStateField, false)?.highlights, isNotEmpty);

      final tr2 = state2.update([clearDocumentHighlights()]);
      final state3 = tr2.state as EditorState;
      expect(state3.field(highlightStateField, false)?.highlights ?? [], isEmpty);
    });

    testWidgets('highlights cleared when cursor moves to whitespace', (tester) async {
      late EditorState currentState;
      final editorKey = GlobalKey<EditorViewState>();
      
      // Use doc with clear whitespace: "x   y" - positions: x=0, space=1,2,3, y=4
      currentState = EditorState.create(
        EditorStateConfig(
          doc: 'x   y',
          selection: EditorSelection.single(0, 0), // on 'x'
          extensions: ExtensionList([
            documentHighlight(
              (state, pos) async {
                // Only return highlights when on 'x' or 'y'
                if (pos == 0) {
                  return DocumentHighlightResult(const [
                    DocumentHighlight(from: 0, to: 1),
                  ]);
                }
                if (pos == 4) {
                  return DocumentHighlightResult(const [
                    DocumentHighlight(from: 4, to: 5),
                  ]);
                }
                return null;
              },
              const DocumentHighlightOptions(delay: 10),
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
      
      // First trigger highlight on 'x'
      editorKey.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(0, 0)),
      ]);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      
      // Should have highlight on 'x'
      var hs = currentState.field(highlightStateField, false);
      expect(hs?.highlights, isNotEmpty, reason: 'Should have highlight on x');

      // Move cursor to whitespace at position 2 (middle of spaces)
      editorKey.currentState!.dispatch([
        TransactionSpec(selection: EditorSelection.single(2, 2)),
      ]);
      
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Highlights should be cleared (wordAt returns null for whitespace)
      hs = currentState.field(highlightStateField, false);
      expect(hs?.highlights ?? [], isEmpty,
        reason: 'No highlights when cursor is on whitespace');
    });

    testWidgets('highlights cleared on document change', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'let x = 1;',
          extensions: ExtensionList([
            documentHighlight((state, pos) async => null),
          ]),
        ),
      );

      final tr1 = state.update([
        setDocumentHighlights(const [DocumentHighlight(from: 4, to: 5)]),
      ]);
      final state2 = tr1.state as EditorState;
      expect(state2.field(highlightStateField, false)?.highlights, isNotEmpty);

      final tr2 = state2.update([
        TransactionSpec(changes: ChangeSpec(from: 0, to: 0, insert: 'a')),
      ]);
      final state3 = tr2.state as EditorState;
      expect(state3.field(highlightStateField, false)?.highlights ?? [], isEmpty);
    });

    testWidgets('highlight styles exist in themes', (tester) async {
      // Verify light theme has document highlight styles
      final lightTheme = HighlightTheme.light;
      expect(lightTheme.getStyle('cm-documentHighlight'), isNotNull,
        reason: 'Light theme should have cm-documentHighlight style');
      expect(lightTheme.getStyle('cm-documentHighlight-read'), isNotNull,
        reason: 'Light theme should have cm-documentHighlight-read style');
      expect(lightTheme.getStyle('cm-documentHighlight-write'), isNotNull,
        reason: 'Light theme should have cm-documentHighlight-write style');
      
      // Verify dark theme has document highlight styles
      final darkTheme = HighlightTheme.dark;
      expect(darkTheme.getStyle('cm-documentHighlight'), isNotNull,
        reason: 'Dark theme should have cm-documentHighlight style');
      expect(darkTheme.getStyle('cm-documentHighlight-read'), isNotNull,
        reason: 'Dark theme should have cm-documentHighlight-read style');
      expect(darkTheme.getStyle('cm-documentHighlight-write'), isNotNull,
        reason: 'Dark theme should have cm-documentHighlight-write style');
      
      // Verify styles have background colors
      final lightWrite = lightTheme.getStyle('cm-documentHighlight-write');
      expect(lightWrite?.backgroundColor, isNotNull,
        reason: 'Write highlight should have background color');
    });
  });
}
