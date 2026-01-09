import 'dart:async';

import 'package:codemirror/codemirror.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Format Module Unit Tests', () {
    group('FormatEdit', () {
      test('can create basic edit', () {
        const edit = FormatEdit(from: 0, to: 5, newText: 'hello');
        expect(edit.from, 0);
        expect(edit.to, 5);
        expect(edit.newText, 'hello');
      });

      test('can create insert edit', () {
        final edit = FormatEdit.insert(10, 'new text');
        expect(edit.from, 10);
        expect(edit.to, 10);
        expect(edit.newText, 'new text');
      });

      test('can create delete edit', () {
        final edit = FormatEdit.delete(5, 15);
        expect(edit.from, 5);
        expect(edit.to, 15);
        expect(edit.newText, '');
      });

      test('can create replace edit', () {
        final edit = FormatEdit.replace(0, 10, 'replacement');
        expect(edit.from, 0);
        expect(edit.to, 10);
        expect(edit.newText, 'replacement');
      });

      test('toString shows range and text', () {
        const edit = FormatEdit(from: 5, to: 10, newText: 'test');
        expect(edit.toString(), 'FormatEdit(5-10: "test")');
      });
    });

    group('FormatResult', () {
      test('empty result has no edits', () {
        expect(FormatResult.empty.isEmpty, isTrue);
        expect(FormatResult.empty.isNotEmpty, isFalse);
        expect(FormatResult.empty.edits, isEmpty);
      });

      test('can create with edits', () {
        final result = FormatResult([
          FormatEdit.insert(0, 'a'),
          FormatEdit.delete(5, 10),
        ]);
        expect(result.isEmpty, isFalse);
        expect(result.isNotEmpty, isTrue);
        expect(result.edits.length, 2);
      });

      test('replaceAll creates single edit for entire document', () {
        final result = FormatResult.replaceAll('formatted', 100);
        expect(result.edits.length, 1);
        expect(result.edits[0].from, 0);
        expect(result.edits[0].to, 100);
        expect(result.edits[0].newText, 'formatted');
      });
    });

    group('DocumentFormattingOptions', () {
      test('has sensible defaults', () {
        const options = DocumentFormattingOptions();
        expect(options.formatOnSave, isFalse);
        expect(options.tabSize, 2);
        expect(options.insertSpaces, isTrue);
        expect(options.options, isEmpty);
      });

      test('can customize all options', () {
        const options = DocumentFormattingOptions(
          formatOnSave: true,
          tabSize: 4,
          insertSpaces: false,
          options: {'foo': 'bar'},
        );
        expect(options.formatOnSave, isTrue);
        expect(options.tabSize, 4);
        expect(options.insertSpaces, isFalse);
        expect(options.options['foo'], 'bar');
      });
    });

    group('OnTypeFormattingOptions', () {
      test('has empty trigger characters by default', () {
        const options = OnTypeFormattingOptions();
        expect(options.triggerCharacters, isEmpty);
      });

      test('can set trigger characters', () {
        const options = OnTypeFormattingOptions(
          triggerCharacters: [';', '}', '\n'],
        );
        expect(options.triggerCharacters.length, 3);
        expect(options.triggerCharacters.contains(';'), isTrue);
        expect(options.triggerCharacters.contains('}'), isTrue);
      });
    });

    group('documentFormattingFacet', () {
      test('can register document formatter', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'unformatted code',
            extensions: ExtensionList([
              documentFormatting((state) {
                return FormatResult.replaceAll(
                  'formatted code',
                  state.doc.length,
                );
              }),
            ]),
          ),
        );

        final configs = state.facet(documentFormattingFacet);
        expect(configs.length, 1);
        expect(configs[0].documentSource, isNotNull);
      });

      test('can register range formatter', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'some code',
            extensions: ExtensionList([
              rangeFormatting((state, from, to) {
                return FormatResult([
                  FormatEdit(from: from, to: to, newText: 'formatted'),
                ]);
              }),
            ]),
          ),
        );

        final configs = state.facet(documentFormattingFacet);
        expect(configs.length, 1);
        expect(configs[0].rangeSource, isNotNull);
      });

      test('can register on-type formatter', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code;',
            extensions: ExtensionList([
              onTypeFormatting(
                (state, pos, char) {
                  if (char == ';') {
                    return FormatResult([FormatEdit.insert(pos, ' ')]);
                  }
                  return null;
                },
                const OnTypeFormattingOptions(triggerCharacters: [';']),
              ),
            ]),
          ),
        );

        final configs = state.facet(documentFormattingFacet);
        expect(configs.length, 1);
        expect(configs[0].onTypeSource, isNotNull);
        expect(configs[0].onTypeOptions.triggerCharacters, [';']);
      });

      test('can register multiple formatters', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code',
            extensions: ExtensionList([
              documentFormatting((state) => FormatResult.empty),
              rangeFormatting((state, from, to) => FormatResult.empty),
              onTypeFormatting((state, pos, char) => null),
            ]),
          ),
        );

        final configs = state.facet(documentFormattingFacet);
        expect(configs.length, 3);
      });
    });

    group('Commands and Effects', () {
      test('formatDocumentCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'test code'),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = formatDocumentCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(formatDocumentEffect)),
          isTrue,
        );
      });

      test('formatSelectionCommand triggers effect with selection range', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'line one\nline two\nline three',
            selection: EditorSelection.range(10, 18), // "line two"
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = formatSelectionCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(formatRangeEffect)),
          isTrue,
        );
      });

      test('formatSelectionCommand with no selection formats current line', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'line one\nline two\nline three',
            selection: EditorSelection.cursor(12), // middle of "line two"
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = formatSelectionCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(formatRangeEffect)),
          isTrue,
        );
      });
    });

    group('Keymap', () {
      test('documentFormattingKeymap contains Shift-Alt-f', () {
        expect(
          documentFormattingKeymap.any((k) => k.key == 'Shift-Alt-f'),
          isTrue,
        );
      });

      test('documentFormattingKeymap contains alternative Ctrl-Shift-i', () {
        expect(
          documentFormattingKeymap.any((k) => k.key == 'Ctrl-Shift-i'),
          isTrue,
        );
      });

      test('documentFormattingKeymapExt creates keymap extension', () {
        final ext = documentFormattingKeymapExt();
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

    group('applyFormatEdits', () {
      test('returns empty spec for empty result', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'test'),
        );

        final spec = applyFormatEdits(state, FormatResult.empty);
        expect(spec.changes, isNull);
      });

      test('creates change spec for single edit', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'hello world'),
        );

        final result = FormatResult([
          FormatEdit.replace(0, 5, 'HELLO'),
        ]);

        final spec = applyFormatEdits(state, result);
        expect(spec.changes, isNotNull);
        expect(spec.userEvent, 'format');
      });

      test('preserves cursor position for edit before cursor', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.cursor(10), // before 'd'
          ),
        );

        // Replace "hello" with "hi" (shorter)
        final result = FormatResult([
          FormatEdit.replace(0, 5, 'hi'),
        ]);

        final spec = applyFormatEdits(state, result);
        // Verify selection is computed
        expect(spec.selection, isNotNull);
      });

      test('preserves cursor position for edit after cursor', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.cursor(2), // in "hello"
          ),
        );

        // Replace "world" with "WORLD!!!" (longer)
        final result = FormatResult([
          FormatEdit.replace(6, 11, 'WORLD!!!'),
        ]);

        final spec = applyFormatEdits(state, result);
        // Verify selection is computed
        expect(spec.selection, isNotNull);
      });

      test('handles multiple edits in correct order', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'aaa bbb ccc'),
        );

        final result = FormatResult([
          FormatEdit.replace(0, 3, 'AAA'),
          FormatEdit.replace(4, 7, 'BBB'),
          FormatEdit.replace(8, 11, 'CCC'),
        ]);

        final spec = applyFormatEdits(state, result);
        expect(spec.changes, isNotNull);
      });
    });

    group('formatDocument utility', () {
      test('calls document source and returns spec', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'unformatted',
            extensions: ExtensionList([
              documentFormatting((state) {
                return FormatResult.replaceAll('FORMATTED', state.doc.length);
              }),
            ]),
          ),
        );

        final spec = await formatDocument(state);
        expect(spec, isNotNull);
        expect(spec!.changes, isNotNull);
      });

      test('returns null when no formatter registered', () async {
        final state = EditorState.create(
          EditorStateConfig(doc: 'test'),
        );

        final spec = await formatDocument(state);
        expect(spec, isNull);
      });

      test('returns null when formatter returns empty result', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              documentFormatting((state) => FormatResult.empty),
            ]),
          ),
        );

        final spec = await formatDocument(state);
        expect(spec, isNull);
      });
    });

    group('formatRange utility', () {
      test('calls range source with correct range', () async {
        int? receivedFrom;
        int? receivedTo;

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              rangeFormatting((state, from, to) {
                receivedFrom = from;
                receivedTo = to;
                return FormatResult([
                  FormatEdit(from: from, to: to, newText: 'RANGE'),
                ]);
              }),
            ]),
          ),
        );

        final spec = await formatRange(state, 0, 5);
        expect(spec, isNotNull);
        expect(receivedFrom, 0);
        expect(receivedTo, 5);
      });

      test('falls back to document formatting when no range formatter', () async {
        var documentFormatterCalled = false;

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              documentFormatting((state) {
                documentFormatterCalled = true;
                return FormatResult.replaceAll('FORMATTED', state.doc.length);
              }),
            ]),
          ),
        );

        final spec = await formatRange(state, 0, 2);
        expect(spec, isNotNull);
        expect(documentFormatterCalled, isTrue);
      });
    });

    group('checkOnTypeFormatting', () {
      test('triggers for matching character', () async {
        var triggered = false;

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code;',
            extensions: ExtensionList([
              onTypeFormatting(
                (state, pos, char) {
                  triggered = true;
                  return FormatResult([FormatEdit.insert(pos + 1, ' ')]);
                },
                const OnTypeFormattingOptions(triggerCharacters: [';']),
              ),
            ]),
          ),
        );

        final spec = await checkOnTypeFormatting(state, 4, ';');
        expect(spec, isNotNull);
        expect(triggered, isTrue);
      });

      test('does not trigger for non-matching character', () async {
        var triggered = false;

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code.',
            extensions: ExtensionList([
              onTypeFormatting(
                (state, pos, char) {
                  triggered = true;
                  return FormatResult([FormatEdit.insert(pos + 1, ' ')]);
                },
                const OnTypeFormattingOptions(triggerCharacters: [';']),
              ),
            ]),
          ),
        );

        final spec = await checkOnTypeFormatting(state, 4, '.');
        expect(spec, isNull);
        expect(triggered, isFalse);
      });

      test('returns null when source returns null', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code;',
            extensions: ExtensionList([
              onTypeFormatting(
                (state, pos, char) => null,
                const OnTypeFormattingOptions(triggerCharacters: [';']),
              ),
            ]),
          ),
        );

        final spec = await checkOnTypeFormatting(state, 4, ';');
        expect(spec, isNull);
      });
    });

    group('Async Sources', () {
      test('async document formatter works', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'unformatted',
            extensions: ExtensionList([
              documentFormatting((state) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return FormatResult.replaceAll('ASYNC FORMATTED', state.doc.length);
              }),
            ]),
          ),
        );

        final spec = await formatDocument(state);
        expect(spec, isNotNull);
      });

      test('async range formatter works', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              rangeFormatting((state, from, to) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return FormatResult([
                  FormatEdit(from: from, to: to, newText: 'ASYNC'),
                ]);
              }),
            ]),
          ),
        );

        final spec = await formatRange(state, 0, 5);
        expect(spec, isNotNull);
      });

      test('async on-type formatter works', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code;',
            extensions: ExtensionList([
              onTypeFormatting(
                (state, pos, char) async {
                  await Future.delayed(const Duration(milliseconds: 10));
                  return FormatResult([FormatEdit.insert(pos + 1, '\n')]);
                },
                const OnTypeFormattingOptions(triggerCharacters: [';']),
              ),
            ]),
          ),
        );

        final spec = await checkOnTypeFormatting(state, 4, ';');
        expect(spec, isNotNull);
      });
    });
  });
}
