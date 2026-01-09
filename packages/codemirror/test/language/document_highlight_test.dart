import 'dart:async';

import 'package:codemirror/codemirror.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Document Highlight Unit Tests', () {
    group('HighlightKind', () {
      test('has all expected values', () {
        expect(HighlightKind.values.length, 3);
        expect(HighlightKind.text.name, 'text');
        expect(HighlightKind.read.name, 'read');
        expect(HighlightKind.write.name, 'write');
      });

      test('has correct indices', () {
        expect(HighlightKind.text.index, 0);
        expect(HighlightKind.read.index, 1);
        expect(HighlightKind.write.index, 2);
      });
    });

    group('DocumentHighlight', () {
      test('can create with defaults', () {
        const highlight = DocumentHighlight(from: 0, to: 5);
        expect(highlight.from, 0);
        expect(highlight.to, 5);
        expect(highlight.kind, HighlightKind.text);
      });

      test('can create with specific kind', () {
        const highlight = DocumentHighlight(
          from: 10,
          to: 20,
          kind: HighlightKind.write,
        );
        expect(highlight.from, 10);
        expect(highlight.to, 20);
        expect(highlight.kind, HighlightKind.write);
      });

      test('toString shows range and kind', () {
        const highlight = DocumentHighlight(
          from: 5,
          to: 10,
          kind: HighlightKind.read,
        );
        expect(highlight.toString(), 'DocumentHighlight(5-10, HighlightKind.read)');
      });
    });

    group('DocumentHighlightResult', () {
      test('empty result has no highlights', () {
        expect(DocumentHighlightResult.empty.isEmpty, isTrue);
        expect(DocumentHighlightResult.empty.isNotEmpty, isFalse);
        expect(DocumentHighlightResult.empty.highlights, isEmpty);
      });

      test('can create with highlights', () {
        final result = DocumentHighlightResult(const [
          DocumentHighlight(from: 0, to: 5),
          DocumentHighlight(from: 10, to: 15, kind: HighlightKind.read),
          DocumentHighlight(from: 20, to: 25, kind: HighlightKind.write),
        ]);
        expect(result.isEmpty, isFalse);
        expect(result.isNotEmpty, isTrue);
        expect(result.highlights.length, 3);
      });
    });

    group('DocumentHighlightOptions', () {
      test('has sensible defaults', () {
        const options = DocumentHighlightOptions();
        expect(options.delay, 150);
        expect(options.textColor, isNull);
        expect(options.readColor, isNull);
        expect(options.writeColor, isNull);
        expect(options.highlightCursor, isTrue);
      });

      test('can customize delay', () {
        const options = DocumentHighlightOptions(delay: 300);
        expect(options.delay, 300);
      });

      test('can set custom colors', () {
        const options = DocumentHighlightOptions(
          textColor: Color(0xFF000000),
          readColor: Color(0xFF0000FF),
          writeColor: Color(0xFFFF0000),
        );
        expect(options.textColor, const Color(0xFF000000));
        expect(options.readColor, const Color(0xFF0000FF));
        expect(options.writeColor, const Color(0xFFFF0000));
      });

      test('can disable cursor highlighting', () {
        const options = DocumentHighlightOptions(highlightCursor: false);
        expect(options.highlightCursor, isFalse);
      });

      test('colorForKind returns default colors in dark mode', () {
        const options = DocumentHighlightOptions();

        final textColor = options.colorForKind(HighlightKind.text, isDark: true);
        final readColor = options.colorForKind(HighlightKind.read, isDark: true);
        final writeColor = options.colorForKind(HighlightKind.write, isDark: true);

        expect(textColor, isNotNull);
        expect(readColor, isNotNull);
        expect(writeColor, isNotNull);
        // Verify they're different
        expect(textColor, isNot(equals(readColor)));
        expect(readColor, isNot(equals(writeColor)));
      });

      test('colorForKind returns default colors in light mode', () {
        const options = DocumentHighlightOptions();

        final textColor = options.colorForKind(HighlightKind.text, isDark: false);
        final readColor = options.colorForKind(HighlightKind.read, isDark: false);
        final writeColor = options.colorForKind(HighlightKind.write, isDark: false);

        expect(textColor, isNotNull);
        expect(readColor, isNotNull);
        expect(writeColor, isNotNull);
      });

      test('colorForKind uses custom colors when set', () {
        const customText = Color(0xFF111111);
        const customRead = Color(0xFF222222);
        const customWrite = Color(0xFF333333);

        const options = DocumentHighlightOptions(
          textColor: customText,
          readColor: customRead,
          writeColor: customWrite,
        );

        expect(options.colorForKind(HighlightKind.text, isDark: true), customText);
        expect(options.colorForKind(HighlightKind.read, isDark: true), customRead);
        expect(options.colorForKind(HighlightKind.write, isDark: true), customWrite);
      });
    });

    group('documentHighlightFacet', () {
      test('can register document highlight source', () {
        ensureDocumentHighlightInitialized();

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5; y = x;',
            extensions: ExtensionList([
              documentHighlight((state, pos) {
                return DocumentHighlightResult(const [
                  DocumentHighlight(from: 4, to: 5),
                  DocumentHighlight(from: 15, to: 16, kind: HighlightKind.read),
                ]);
              }),
            ]),
          ),
        );

        final configs = state.facet(documentHighlightFacet);
        expect(configs.length, 1);
        expect(configs[0].source, isNotNull);
      });

      test('can register with custom options', () {
        ensureDocumentHighlightInitialized();

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              documentHighlight(
                (state, pos) => DocumentHighlightResult.empty,
                const DocumentHighlightOptions(
                  delay: 200,
                  highlightCursor: false,
                ),
              ),
            ]),
          ),
        );

        final configs = state.facet(documentHighlightFacet);
        expect(configs[0].options.delay, 200);
        expect(configs[0].options.highlightCursor, isFalse);
      });

      test('can register multiple sources', () {
        ensureDocumentHighlightInitialized();

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code',
            extensions: ExtensionList([
              documentHighlight((state, pos) => DocumentHighlightResult.empty),
              documentHighlight((state, pos) => DocumentHighlightResult.empty),
            ]),
          ),
        );

        final configs = state.facet(documentHighlightFacet);
        expect(configs.length, 2);
      });
    });

    group('State Effects', () {
      test('setHighlightsEffect is defined', () {
        expect(setHighlightsEffect, isNotNull);
      });

      test('clearHighlightsEffect is defined', () {
        expect(clearHighlightsEffect, isNotNull);
      });

      test('can create setDocumentHighlights transaction spec', () {
        final spec = setDocumentHighlights(const [
          DocumentHighlight(from: 0, to: 5),
          DocumentHighlight(from: 10, to: 15),
        ]);

        expect(spec.effects, isNotEmpty);
        expect(spec.effects!.any((e) => e.is_(setHighlightsEffect)), isTrue);
      });

      test('can create clearDocumentHighlights transaction spec', () {
        final spec = clearDocumentHighlights();

        expect(spec.effects, isNotEmpty);
        expect(spec.effects!.any((e) => e.is_(clearHighlightsEffect)), isTrue);
      });
    });

    group('DocumentHighlightState', () {
      test('empty state has no highlights', () {
        final empty = DocumentHighlightState.empty;
        expect(empty.pos, isNull);
        expect(empty.highlights, isEmpty);
        expect(empty.decorations.isEmpty, isTrue);
      });
    });

    group('Async Sources', () {
      test('async document highlight source works', () async {
        ensureDocumentHighlightInitialized();

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5; y = x;',
            extensions: ExtensionList([
              documentHighlight((state, pos) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return DocumentHighlightResult(const [
                  DocumentHighlight(from: 4, to: 5),
                  DocumentHighlight(from: 15, to: 16),
                ]);
              }),
            ]),
          ),
        );

        final configs = state.facet(documentHighlightFacet);
        final result = await configs[0].source(state, 4);

        expect(result?.highlights.length, 2);
      });
    });

    group('Integration scenarios', () {
      test('highlight all occurrences of variable', () {
        final highlights = const [
          DocumentHighlight(from: 4, to: 5), // definition
          DocumentHighlight(from: 15, to: 16, kind: HighlightKind.read), // usage
          DocumentHighlight(from: 25, to: 26, kind: HighlightKind.write), // write
        ];

        final result = DocumentHighlightResult(highlights);

        expect(result.highlights.length, 3);
        expect(
          result.highlights.where((h) => h.kind == HighlightKind.text).length,
          1,
        );
        expect(
          result.highlights.where((h) => h.kind == HighlightKind.read).length,
          1,
        );
        expect(
          result.highlights.where((h) => h.kind == HighlightKind.write).length,
          1,
        );
      });

      test('different highlight kinds for different usages', () {
        // Simulate LSP DocumentHighlightKind values
        const lspText = 1;
        const lspRead = 2;
        const lspWrite = 3;

        HighlightKind fromLsp(int kind) {
          switch (kind) {
            case lspRead:
              return HighlightKind.read;
            case lspWrite:
              return HighlightKind.write;
            default:
              return HighlightKind.text;
          }
        }

        expect(fromLsp(lspText), HighlightKind.text);
        expect(fromLsp(lspRead), HighlightKind.read);
        expect(fromLsp(lspWrite), HighlightKind.write);
      });
    });

    group('State field behavior', () {
      test('highlightStateField is accessible', () {
        ensureDocumentHighlightInitialized();
        expect(highlightStateField, isNotNull);
      });

      test('highlights cleared on document change', () {
        ensureDocumentHighlightInitialized();

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5;',
            extensions: ExtensionList([
              documentHighlight((state, pos) {
                return DocumentHighlightResult(const [
                  DocumentHighlight(from: 4, to: 5),
                ]);
              }),
            ]),
          ),
        );

        // Set highlights via effect
        final tr1 = state.update([
          setDocumentHighlights(const [
            DocumentHighlight(from: 4, to: 5),
          ]),
        ]);
        final state2 = tr1.state as EditorState;

        // Verify highlights are set
        final fieldValue = state2.field(highlightStateField, false);
        expect(fieldValue?.highlights, isNotEmpty);

        // Now make a document change
        final tr2 = state2.update([
          TransactionSpec(
            changes: ChangeSpec(from: 0, to: 0, insert: 'a'),
          ),
        ]);
        final state3 = tr2.state as EditorState;

        // Highlights should be cleared
        final fieldValue2 = state3.field(highlightStateField, false);
        expect(fieldValue2?.highlights, isEmpty);
      });
    });
  });
}
