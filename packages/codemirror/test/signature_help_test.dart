import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Signature Help', () {
    setUpAll(() {
      ensureStateInitialized();
      ensureLanguageInitialized();
    });

    test('signatureHelpFacet is registered when using signatureHelp extension', () {
      var sourceCalled = false;
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'console.log(',
          extensions: ExtensionList([
            signatureHelp(
              (EditorState state, int pos) {
                sourceCalled = true;
                return SignatureResult(
                  signatures: [
                    SignatureInfo(
                      label: 'log(message: any): void',
                      parameters: [ParameterInfo(label: 'message: any')],
                    ),
                  ],
                  triggerPos: pos,
                );
              },
              const SignatureHelpOptions(
                triggerCharacters: ['(', ','],
              ),
            ),
          ]),
        ),
      );

      // Check facet is registered
      final configs = state.facet(signatureHelpFacet);
      expect(configs, isNotEmpty, reason: 'signatureHelpFacet should have configs');
      expect(configs.length, 1);
      expect(configs.first.options.triggerCharacters, contains('('));
      
      // Trigger the source
      configs.first.source(state, 12);
      expect(sourceCalled, true, reason: 'Source should have been called');
    });

    testWidgets('signature help triggers on ( character', (tester) async {
      ensureStateInitialized();
      ensureLanguageInitialized();
      
      var signatureRequested = false;
      int? requestedPos;
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'console.log',
          extensions: ExtensionList([
            signatureHelp(
              (EditorState state, int pos) async {
                signatureRequested = true;
                requestedPos = pos;
                return SignatureResult(
                  signatures: [
                    SignatureInfo(
                      label: 'log(message: any): void',
                      parameters: [ParameterInfo(label: 'message: any')],
                    ),
                  ],
                  triggerPos: pos,
                );
              },
              const SignatureHelpOptions(
                triggerCharacters: ['(', ','],
              ),
            ),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(
              state: state,
              autofocus: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      // Focus and place cursor at end
      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();
      
      // Type '(' 
      await tester.enterText(find.byType(EditableText), 'console.log(');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      
      expect(signatureRequested, true, reason: 'Signature help should have been requested');
      expect(requestedPos, 12, reason: 'Position should be after the (');
    });
  });
}
