import 'dart:async';

import 'package:codemirror/codemirror.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Signature Help Unit Tests', () {
    group('ParameterInfo', () {
      test('can create with just label', () {
        const param = ParameterInfo(label: 'int count');
        expect(param.label, 'int count');
        expect(param.documentation, isNull);
      });

      test('can create with documentation', () {
        const param = ParameterInfo(
          label: 'String name',
          documentation: 'The name to use',
        );
        expect(param.label, 'String name');
        expect(param.documentation, 'The name to use');
      });

      test('toString returns label', () {
        const param = ParameterInfo(label: 'bool flag');
        expect(param.toString(), 'ParameterInfo(bool flag)');
      });
    });

    group('SignatureInfo', () {
      test('can create with just label', () {
        const sig = SignatureInfo(label: 'void foo()');
        expect(sig.label, 'void foo()');
        expect(sig.documentation, isNull);
        expect(sig.parameters, isEmpty);
        expect(sig.activeParameter, 0);
      });

      test('can create with all fields', () {
        const sig = SignatureInfo(
          label: 'void bar(int a, String b)',
          documentation: 'A test function',
          parameters: [
            ParameterInfo(label: 'int a', documentation: 'First param'),
            ParameterInfo(label: 'String b', documentation: 'Second param'),
          ],
          activeParameter: 1,
        );

        expect(sig.label, 'void bar(int a, String b)');
        expect(sig.documentation, 'A test function');
        expect(sig.parameters.length, 2);
        expect(sig.activeParameter, 1);
      });

      test('withActiveParameter creates copy', () {
        const sig = SignatureInfo(
          label: 'void test(int a, int b, int c)',
          parameters: [
            ParameterInfo(label: 'int a'),
            ParameterInfo(label: 'int b'),
            ParameterInfo(label: 'int c'),
          ],
          activeParameter: 0,
        );

        final sig2 = sig.withActiveParameter(2);
        expect(sig2.activeParameter, 2);
        expect(sig.activeParameter, 0); // original unchanged
        expect(sig2.label, sig.label);
        expect(sig2.parameters.length, sig.parameters.length);
      });

      test('withActiveParameter clamps to valid range', () {
        const sig = SignatureInfo(
          label: 'void foo(int a)',
          parameters: [ParameterInfo(label: 'int a')],
        );

        expect(sig.withActiveParameter(-5).activeParameter, -1);
        expect(sig.withActiveParameter(100).activeParameter, 0);
      });

      test('toString shows label and active', () {
        const sig = SignatureInfo(
          label: 'test()',
          activeParameter: 2,
        );
        expect(sig.toString(), 'SignatureInfo(test(), active: 2)');
      });
    });

    group('SignatureResult', () {
      test('empty result has no signatures', () {
        expect(SignatureResult.empty.isEmpty, isTrue);
        expect(SignatureResult.empty.isNotEmpty, isFalse);
        expect(SignatureResult.empty.signatures, isEmpty);
        expect(SignatureResult.empty.active, isNull);
      });

      test('can create with signatures', () {
        final result = SignatureResult(
          signatures: const [
            SignatureInfo(label: 'foo(int a)'),
            SignatureInfo(label: 'foo(int a, int b)'),
          ],
          triggerPos: 10,
        );

        expect(result.isEmpty, isFalse);
        expect(result.isNotEmpty, isTrue);
        expect(result.signatures.length, 2);
        expect(result.activeSignature, 0);
        expect(result.triggerPos, 10);
      });

      test('active returns correct signature', () {
        final result = SignatureResult(
          signatures: const [
            SignatureInfo(label: 'first'),
            SignatureInfo(label: 'second'),
          ],
          activeSignature: 1,
          triggerPos: 0,
        );

        expect(result.active?.label, 'second');
      });

      test('active returns null for invalid index', () {
        final result = SignatureResult(
          signatures: const [SignatureInfo(label: 'only')],
          activeSignature: 5, // out of range
          triggerPos: 0,
        );

        expect(result.active, isNull);
      });

      test('withActiveSignature creates copy', () {
        final result = SignatureResult(
          signatures: const [
            SignatureInfo(label: 'a'),
            SignatureInfo(label: 'b'),
            SignatureInfo(label: 'c'),
          ],
          activeSignature: 0,
          triggerPos: 5,
        );

        final result2 = result.withActiveSignature(2);
        expect(result2.activeSignature, 2);
        expect(result.activeSignature, 0); // original unchanged
        expect(result2.triggerPos, 5);
      });

      test('toString shows count and active', () {
        final result = SignatureResult(
          signatures: const [
            SignatureInfo(label: 'a'),
            SignatureInfo(label: 'b'),
          ],
          activeSignature: 1,
          triggerPos: 0,
        );
        expect(result.toString(), 'SignatureResult(2 signatures, active: 1)');
      });
    });

    group('SignatureHelpOptions', () {
      test('has sensible defaults', () {
        const options = SignatureHelpOptions();
        expect(options.triggerCharacters, ['(', ',']);
        expect(options.retriggerCharacters, [')']);
        expect(options.updater, isNull);
        expect(options.autoTrigger, isTrue);
        expect(options.delay, 0);
      });

      test('can customize trigger characters', () {
        const options = SignatureHelpOptions(
          triggerCharacters: ['<', '('],
          retriggerCharacters: ['>', ')'],
        );
        expect(options.triggerCharacters, ['<', '(']);
        expect(options.retriggerCharacters, ['>', ')']);
      });

      test('can set updater', () {
        final options = SignatureHelpOptions(
          updater: (state, result, pos) => result,
        );
        expect(options.updater, isNotNull);
      });

      test('can disable auto trigger', () {
        const options = SignatureHelpOptions(autoTrigger: false);
        expect(options.autoTrigger, isFalse);
      });

      test('can set delay', () {
        const options = SignatureHelpOptions(delay: 100);
        expect(options.delay, 100);
      });
    });

    group('signatureHelpFacet', () {
      test('can register signature source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'print(',
            extensions: ExtensionList([
              signatureHelp((state, pos) {
                return SignatureResult(
                  signatures: const [
                    SignatureInfo(label: 'print(Object? object)'),
                  ],
                  triggerPos: pos,
                );
              }),
            ]),
          ),
        );

        final configs = state.facet(signatureHelpFacet);
        expect(configs.length, 1);
        expect(configs[0].source, isNotNull);
      });

      test('can register with custom options', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'test<',
            extensions: ExtensionList([
              signatureHelp(
                (state, pos) => SignatureResult.empty,
                const SignatureHelpOptions(
                  triggerCharacters: ['<'],
                  delay: 50,
                ),
              ),
            ]),
          ),
        );

        final configs = state.facet(signatureHelpFacet);
        expect(configs[0].options.triggerCharacters, ['<']);
        expect(configs[0].options.delay, 50);
      });
    });

    group('Commands and Effects', () {
      test('triggerSignatureHelpCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'foo(',
            selection: EditorSelection.cursor(4),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = triggerSignatureHelpCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerSignatureEffect)),
          isTrue,
        );
      });

      test('dismissSignatureHelpCommand triggers dismiss effect', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'foo()'),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = dismissSignatureHelpCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(dismissSignatureEffect)),
          isTrue,
        );
      });
    });

    group('Keymap', () {
      test('signatureHelpKeymap contains Ctrl-Shift-Space', () {
        expect(
          signatureHelpKeymap.any((k) => k.key == 'Ctrl-Shift-Space'),
          isTrue,
        );
      });

      test('signatureHelpKeymap contains Cmd-Shift-Space for Mac', () {
        expect(
          signatureHelpKeymap.any((k) => k.mac == 'Cmd-Shift-Space'),
          isTrue,
        );
      });
    });

    group('detectActiveParameter', () {
      // Note: triggerPos should be right after the '(' character
      // So for 'foo(' the trigger pos would be 4 (length of 'foo(')
      
      test('returns 0 for first parameter', () {
        // "foo(|" - cursor right after opening paren, triggerPos at '('
        expect(detectActiveParameter('foo(', 4, 4), 0);
      });

      test('returns 0 when cursor at trigger', () {
        expect(detectActiveParameter('foo(abc', 4, 4), 0);
      });

      test('returns 0 when cursor before trigger', () {
        expect(detectActiveParameter('foo(abc', 4, 2), 0);
      });

      test('counts commas for parameter index', () {
        // "foo(a, |" - triggerPos=4 (after '('), cursor at 7
        expect(detectActiveParameter('foo(a, b', 4, 7), 1);
        // "foo(a, b, |" - triggerPos=4, cursor at 10
        expect(detectActiveParameter('foo(a, b, c', 4, 10), 2);
      });

      test('ignores commas in nested parens', () {
        // "foo(bar(x, y), |" - triggerPos=4
        final text = 'foo(bar(x, y), z)';
        expect(detectActiveParameter(text, 4, 15), 1);
      });

      test('ignores commas in nested brackets', () {
        // "foo([a, b], |" - triggerPos=4
        final text = 'foo([a, b], c)';
        expect(detectActiveParameter(text, 4, 12), 1);
      });

      test('ignores commas in nested braces', () {
        // "foo({a, b}, |" - triggerPos=4
        final text = 'foo({a, b}, c)';
        expect(detectActiveParameter(text, 4, 12), 1);
      });

      test('ignores commas in strings', () {
        // 'foo("a, b", |' - triggerPos=4
        final text = 'foo("a, b", c)';
        expect(detectActiveParameter(text, 4, 12), 1);
      });

      test('ignores commas in single-quoted strings', () {
        final text = "foo('a, b', c)";
        expect(detectActiveParameter(text, 4, 12), 1);
      });

      test('handles escaped quotes in strings', () {
        final text = r'foo("a\"b", c)';
        expect(detectActiveParameter(text, 4, 13), 1);
      });

      test('returns -1 when outside function call', () {
        // "foo(a)|" - after closing paren, triggerPos=4
        expect(detectActiveParameter('foo(a) extra', 4, 6), -1);
      });

      test('handles deeply nested calls', () {
        final text = 'foo(bar(baz(x, y), z), w)';
        // At the 'w' parameter - triggerPos=4
        expect(detectActiveParameter(text, 4, 23), 1);
      });
    });

    group('isWithinFunctionCall', () {
      // Note: triggerPos should be right after the '(' character
      
      test('returns true when inside parens', () {
        expect(isWithinFunctionCall('foo(abc', 4, 7), isTrue);
      });

      test('returns false when before trigger', () {
        expect(isWithinFunctionCall('foo(abc', 4, 2), isFalse);
      });

      test('returns false when after closing paren', () {
        // triggerPos=4 (after '('), cursorPos=6 (after ')')
        expect(isWithinFunctionCall('foo(a)', 4, 6), isFalse);
      });

      test('returns true with nested parens still open', () {
        final text = 'foo(bar(x, y)';
        expect(isWithinFunctionCall(text, 4, text.length), isTrue);
      });

      test('handles string literals', () {
        final text = 'foo("(")';
        // Inside the outer call, after the string with a paren
        expect(isWithinFunctionCall(text, 4, 7), isTrue);
      });
    });

    group('Async Sources', () {
      test('async signature source works', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'print(',
            extensions: ExtensionList([
              signatureHelp((state, pos) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return SignatureResult(
                  signatures: const [
                    SignatureInfo(
                      label: 'print(Object? object)',
                      parameters: [
                        ParameterInfo(label: 'Object? object'),
                      ],
                    ),
                  ],
                  triggerPos: pos,
                );
              }),
            ]),
          ),
        );

        final configs = state.facet(signatureHelpFacet);
        final result = await configs[0].source(state, 6);

        expect(result?.signatures.length, 1);
        expect(result?.active?.label, 'print(Object? object)');
        expect(result?.triggerPos, 6);
      });
    });

    group('Extension Helpers', () {
      test('signatureHelpKeymapExt creates keymap extension', () {
        final ext = signatureHelpKeymapExt();
        expect(ext, isNotNull);

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ext,
          ),
        );

        final keymaps = state.facet(keymap);
        expect(keymaps, isNotEmpty);
      });
    });
  });
}
