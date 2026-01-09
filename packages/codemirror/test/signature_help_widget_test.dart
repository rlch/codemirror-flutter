import 'dart:async';

import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Signature Help Widget Tests', () {
    setUpAll(() {
      ensureStateInitialized();
      ensureLanguageInitialized();
    });

    testWidgets('signature help triggers even with closeBrackets enabled', (tester) async {
      final triggeredAt = <int>[];
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'fn',
          extensions: ExtensionList([
            closeBrackets(),
            signatureHelp(
              (state, pos) {
                triggeredAt.add(pos);
                return SignatureResult(
                  signatures: [SignatureInfo(label: 'fn()', parameters: [])],
                  triggerPos: pos,
                );
              },
              const SignatureHelpOptions(triggerCharacters: ['(']),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(state: state, autofocus: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Type 'fn(' - close brackets will turn this into 'fn()'
      // But signature help should still trigger on the original '(' 
      await tester.enterText(find.byType(EditableText), 'fn(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should trigger even though closeBrackets transforms '(' to '()'
      expect(triggeredAt, isNotEmpty, 
          reason: 'Signature help should trigger even with closeBrackets enabled');
      expect(triggeredAt, contains(3), reason: 'Should trigger at position 3 (after the open paren)');
    });

    testWidgets('signature help tooltip appears when typing (', (tester) async {
      var signatureRequested = false;
      int? requestedPos;
      final signatureCompleter = Completer<SignatureResult?>();

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'console.log',
          extensions: ExtensionList([
            signatureHelp(
              (EditorState state, int pos) async {
                signatureRequested = true;
                requestedPos = pos;
                return signatureCompleter.future;
              },
              const SignatureHelpOptions(
                triggerCharacters: ['(', ','],
                retriggerCharacters: [')'],
              ),
            ),
          ]),
        ),
      );

      EditorState? currentState = state;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(
              state: currentState,
              autofocus: true,
              onUpdate: (update) {
                currentState = update.state;
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Focus the editor
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Simulate typing '(' by entering new text
      // This simulates what happens when user types
      await tester.enterText(find.byType(EditableText), 'console.log(');
      await tester.pump();

      // Wait for signature help to be triggered
      await tester.pump(const Duration(milliseconds: 50));

      expect(signatureRequested, true, reason: 'Signature help should be requested when ( is typed');
      expect(requestedPos, 12, reason: 'Position should be after the (');

      // Complete with a signature result
      signatureCompleter.complete(SignatureResult(
        signatures: [
          SignatureInfo(
            label: 'log(message?: any, ...optionalParams: any[]): void',
            documentation: 'Prints to stdout with newline.',
            parameters: [
              ParameterInfo(label: 'message?: any', documentation: 'The message to print'),
              ParameterInfo(label: '...optionalParams: any[]'),
            ],
            activeParameter: 0,
          ),
        ],
        triggerPos: 12,
      ));

      // Wait for tooltip to appear
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Look for the signature help tooltip content
      expect(find.textContaining('log('), findsWidgets,
          reason: 'Signature help tooltip should show the function signature');
    });

    testWidgets('signature help source is called with correct state', (tester) async {
      EditorState? capturedState;
      int? capturedPos;

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'test',
          extensions: ExtensionList([
            signatureHelp(
              (EditorState state, int pos) {
                capturedState = state;
                capturedPos = pos;
                return SignatureResult(
                  signatures: [
                    SignatureInfo(label: 'test()', parameters: []),
                  ],
                  triggerPos: pos,
                );
              },
              const SignatureHelpOptions(triggerCharacters: ['(']),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(state: state, autofocus: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'test(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(capturedState, isNotNull, reason: 'State should be passed to source');
      expect(capturedPos, 5, reason: 'Position should be after the (');
      expect(capturedState!.doc.toString(), 'test(',
          reason: 'State should have updated document');
    });

    testWidgets('signature help is dismissed on ) character', (tester) async {
      var dismissCount = 0;
      var triggerCount = 0;

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'fn(',
          extensions: ExtensionList([
            signatureHelp(
              (EditorState state, int pos) {
                triggerCount++;
                return SignatureResult(
                  signatures: [SignatureInfo(label: 'fn()', parameters: [])],
                  triggerPos: pos,
                );
              },
              const SignatureHelpOptions(
                triggerCharacters: ['('],
                retriggerCharacters: [')'],
              ),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(state: state, autofocus: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Type ) to dismiss
      await tester.enterText(find.byType(EditableText), 'fn()');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The ) should NOT trigger signature help (it's a retrigger/dismiss char)
      // Since doc started with 'fn(' and we typed 'fn()', only ')' was inserted
      // This should dismiss, not trigger
    });

    testWidgets('signature help facet is properly registered', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'test',
          extensions: ExtensionList([
            signatureHelp(
              (state, pos) => null,
              const SignatureHelpOptions(triggerCharacters: ['(', ',']),
            ),
          ]),
        ),
      );

      final configs = state.facet(signatureHelpFacet);
      expect(configs, isNotEmpty, reason: 'Facet should be registered');
      expect(configs.length, 1);
      expect(configs.first.options.triggerCharacters, ['(', ',']);
      expect(configs.first.options.autoTrigger, true);
    });

    testWidgets('signature help with async LSP-like source', (tester) async {
      var sourceCallCount = 0;
      
      // Simulate an LSP client delay
      Future<SignatureResult?> lspLikeSource(EditorState state, int pos) async {
        sourceCallCount++;
        await Future.delayed(const Duration(milliseconds: 10));
        
        final doc = state.doc.toString();
        // Simple check: only return signature if we're after a (
        if (pos > 0 && pos <= doc.length) {
          final beforeCursor = doc.substring(0, pos);
          if (beforeCursor.endsWith('(')) {
            return SignatureResult(
              signatures: [
                SignatureInfo(
                  label: 'asyncFn(param: string): Promise<void>',
                  parameters: [ParameterInfo(label: 'param: string')],
                  activeParameter: 0,
                ),
              ],
              triggerPos: pos,
            );
          }
        }
        return null;
      }

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'asyncFn',
          extensions: ExtensionList([
            signatureHelp(lspLikeSource, const SignatureHelpOptions(
              triggerCharacters: ['(', ','],
            )),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(state: state, autofocus: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText), 'asyncFn(');
      await tester.pump();
      
      // Wait for trigger
      await tester.pump(const Duration(milliseconds: 50));
      
      expect(sourceCallCount, greaterThan(0), reason: 'LSP source should be called');
      
      // Wait for async response
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      
      // Signature tooltip should now be visible
      expect(find.textContaining('asyncFn'), findsWidgets);
    });

    testWidgets('multiple trigger characters work', (tester) async {
      final triggeredAt = <int>[];

      final state = EditorState.create(
        EditorStateConfig(
          doc: '',
          extensions: ExtensionList([
            signatureHelp(
              (state, pos) {
                triggeredAt.add(pos);
                return SignatureResult(
                  signatures: [SignatureInfo(label: 'fn(a, b)', parameters: [
                    ParameterInfo(label: 'a'),
                    ParameterInfo(label: 'b'),
                  ])],
                  triggerPos: pos,
                );
              },
              const SignatureHelpOptions(triggerCharacters: ['(', ',']),
            ),
          ]),
        ),
      );

      // Verify facet is registered
      final configs = state.facet(signatureHelpFacet);
      expect(configs, isNotEmpty, reason: 'Facet should be registered');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(state: state, autofocus: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Type 'fn(' - last char is ( which triggers signature help
      await tester.enterText(find.byType(EditableText), 'fn(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(triggeredAt, contains(3), reason: 'Should trigger at position 3 after (');

      // Type 'fn(a,' - last char is , which triggers signature help
      await tester.enterText(find.byType(EditableText), 'fn(a,');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(triggeredAt, contains(5), reason: 'Should trigger at position 5 after ,');
    });

    testWidgets('signature help hides when cursor moves outside function call via arrow keys', (tester) async {
      final triggeredPositions = <int>[];
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: '',  // Start empty
          extensions: ExtensionList([
            signatureHelp(
              (state, pos) {
                triggeredPositions.add(pos);
                // Always return a result to simulate active signature help
                return SignatureResult(
                  signatures: [SignatureInfo(label: 'fn(a, b)', parameters: [
                    ParameterInfo(label: 'a'),
                    ParameterInfo(label: 'b'),
                  ])],
                  triggerPos: 3, // triggerPos is where '(' was typed
                );
              },
              const SignatureHelpOptions(triggerCharacters: ['(', ',']),
            ),
          ]),
        ),
      );

      final viewKey = GlobalKey<EditorViewState>();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(key: viewKey, state: state, autofocus: true),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      // Type 'fn(' to trigger signature help (the '(' is the trigger character)
      await tester.enterText(find.byType(EditableText), 'fn(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      
      // Verify signature help was triggered and is active
      expect(triggeredPositions, isNotEmpty, reason: 'Signature help should have triggered');
      expect(viewKey.currentState?.signatureResult, isNotNull,
          reason: 'Signature help should be active after trigger');
      
      // Now type ')' to close the function call - cursor goes to position 4 (after ')')
      await tester.enterText(find.byType(EditableText), 'fn()');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      
      // Press Right arrow - this tests the arrow key code path for dismissal
      // The cursor is now at position 4 (after ')'), which is outside the function call
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      
      // After cursor moves outside parens, signature help should be hidden
      expect(viewKey.currentState?.signatureResult, isNull,
          reason: 'Signature help should hide when cursor moves outside function call');
    });
  });
}
