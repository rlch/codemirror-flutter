import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Template Editor Signature Help Integration', () {
    setUpAll(() {
      ensureStateInitialized();
      ensureLanguageInitialized();
      ensureFoldInitialized();
      ensureLintInitialized();
    });

    testWidgets('signature help triggers when typing ( after method call', (tester) async {
      final triggeredAt = <int>[];
      var signatureSourceCalled = false;
      
      Future<SignatureResult?> signatureSource(EditorState state, int pos) async {
        signatureSourceCalled = true;
        triggeredAt.add(pos);
        print('Signature help triggered at pos: $pos');
        print('  Doc: ${state.doc}');
        return SignatureResult(
          signatures: [
            SignatureInfo(
              label: 'submitReview(id: string): void',
              parameters: [ParameterInfo(label: 'id: string')],
              activeParameter: 0,
            ),
          ],
          triggerPos: pos,
        );
      }
      
      final langSupport = javascript(const JavaScriptConfig(jsx: true));

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'controller.submitReview',
          extensions: ExtensionList([
            langSupport.extension,
            syntaxHighlighting(defaultHighlightStyle),
            lineNumbers(),
            highlightActiveLine(),
            highlightActiveLineGutter(),
            foldGutter(),
            bracketMatching(),
            closeBrackets(),
            search(),
            history(),
            autocompletion(),
            signatureHelp(
              signatureSource,
              const SignatureHelpOptions(
                triggerCharacters: ['(', ','],
                retriggerCharacters: [')'],
              ),
            ),
            lintGutter(),
          ]),
        ),
      );
      
      final configs = state.facet(signatureHelpFacet);
      expect(configs, isNotEmpty, reason: 'signatureHelpFacet should be registered');
      print('Facet configs: ${configs.length}');
      print('Trigger chars: ${configs.first.options.triggerCharacters}');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(
              state: state,
              autofocus: true,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: ['Monaco', 'Menlo', 'Consolas', 'monospace'],
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      print('Before typing: doc = controller.submitReview');
      
      await tester.enterText(find.byType(EditableText), 'controller.submitReview(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      print('After typing: signatureSourceCalled = $signatureSourceCalled');
      print('Triggered at positions: $triggeredAt');
      
      expect(signatureSourceCalled, isTrue, 
          reason: 'Signature help should trigger when typing (');
      expect(triggeredAt, contains(24), 
          reason: 'Should trigger at position 24 (after the open paren)');
    });

    testWidgets('signature help triggers with minimal extensions', (tester) async {
      final triggeredAt = <int>[];
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'fn',
          extensions: ExtensionList([
            signatureHelp(
              (state, pos) {
                triggeredAt.add(pos);
                print('Minimal test: triggered at $pos');
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

      await tester.enterText(find.byType(EditableText), 'fn(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      print('Minimal test - triggered at: $triggeredAt');
      expect(triggeredAt, isNotEmpty, reason: 'Signature help should trigger');
    });

    testWidgets('signature help with closeBrackets + autocompletion', (tester) async {
      final triggeredAt = <int>[];
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'test',
          extensions: ExtensionList([
            closeBrackets(),
            autocompletion(),
            signatureHelp(
              (state, pos) {
                triggeredAt.add(pos);
                print('With closeBrackets: triggered at $pos, doc="${state.doc}"');
                return SignatureResult(
                  signatures: [SignatureInfo(label: 'test()', parameters: [])],
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
      await tester.pump(const Duration(milliseconds: 100));

      print('closeBrackets test - triggered at: $triggeredAt');
      expect(triggeredAt, isNotEmpty, 
          reason: 'Signature help should trigger even with closeBrackets');
    });

    testWidgets('signature help with async LSP source returning null', (tester) async {
      var sourceCallCount = 0;
      
      Future<SignatureResult?> signatureSource(EditorState state, int pos) async {
        sourceCallCount++;
        print('LSP-like source called: count=$sourceCallCount, pos=$pos');
        await Future.delayed(const Duration(milliseconds: 10));
        return null;
      }
      
      final langSupport = javascript(const JavaScriptConfig(jsx: true));

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'controller.submitReview',
          extensions: ExtensionList([
            langSupport.extension,
            closeBrackets(),
            autocompletion(),
            signatureHelp(
              signatureSource,
              const SignatureHelpOptions(
                triggerCharacters: ['(', ','],
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

      await tester.enterText(find.byType(EditableText), 'controller.submitReview(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      print('LSP null test - source called $sourceCallCount times');
      expect(sourceCallCount, greaterThan(0), 
          reason: 'Signature source should be called even if it returns null');
    });

    testWidgets('full template editor setup - exact mirror', (tester) async {
      final triggeredAt = <int>[];
      var signatureSourceCalled = false;
      
      Future<SignatureResult?> signatureSource(EditorState state, int pos) async {
        signatureSourceCalled = true;
        triggeredAt.add(pos);
        print('FULL SETUP: Signature help triggered at pos: $pos');
        print('  Doc: "${state.doc}"');
        return SignatureResult(
          signatures: [
            SignatureInfo(
              label: 'submitReview(id: string): void',
              parameters: [ParameterInfo(label: 'id: string')],
              activeParameter: 0,
            ),
          ],
          triggerPos: pos,
        );
      }
      
      final langSupport = javascript(const JavaScriptConfig(jsx: true));

      final extensions = <Extension>[
        langSupport.extension,
        syntaxHighlighting(defaultHighlightStyle),
        lineNumbers(),
        highlightActiveLine(),
        highlightActiveLineGutter(),
        foldGutter(),
        bracketMatching(),
        closeBrackets(),
        search(),
        keymap.of(searchKeymap),
        keymap.of(foldKeymap),
        keymap.of(closeBracketsKeymap),
        history(),
        keymap.of(historyKeymap),
        keymap.of(standardKeymap),
        keymap.of([indentWithTab]),
        autocompletion(),
        signatureHelp(
          signatureSource,
          const SignatureHelpOptions(
            triggerCharacters: ['(', ','],
            retriggerCharacters: [')'],
          ),
        ),
        lintGutter(),
      ];

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'controller.submitReview',
          extensions: ExtensionList(extensions),
        ),
      );
      
      final configs = state.facet(signatureHelpFacet);
      expect(configs, isNotEmpty, reason: 'signatureHelpFacet should be registered');
      print('FULL SETUP: ${configs.length} facet configs');
      print('FULL SETUP: trigger chars = ${configs.first.options.triggerCharacters}');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorView(
              state: state,
              autofocus: true,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: ['Monaco', 'Menlo', 'Consolas', 'monospace'],
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(EditorView));
      await tester.pumpAndSettle();

      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      print('FULL SETUP: Initial doc = "${viewState.state.doc}"');
      print('FULL SETUP: Initial cursor = ${viewState.state.selection.main.head}');
      
      await tester.enterText(find.byType(EditableText), 'controller.submitReview(');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      print('FULL SETUP: After typing doc = "${viewState.state.doc}"');
      print('FULL SETUP: signatureSourceCalled = $signatureSourceCalled');
      print('FULL SETUP: triggered at: $triggeredAt');
      
      expect(signatureSourceCalled, isTrue, 
          reason: 'Signature help should trigger when typing (');
    });
  });
}
