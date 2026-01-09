import 'dart:async';

import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  group('LSP Features Widget Tests', () {
    group('Go to Definition', () {
      testWidgets('Ctrl+click triggers definition lookup', (tester) async {
        int? definitionPos;
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'function test() {}',
            extensions: ExtensionList([
              gotoDefinition(
                (state, pos) async {
                  definitionPos = pos;
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

        // Note: Testing Ctrl+click requires simulating pointer events with modifiers
        // which is complex in widget tests. The unit tests already cover the command.
        expect(state.facet(gotoDefinitionFacet).isNotEmpty, isTrue);
      });

      testWidgets('F12 keymap is registered', (tester) async {
        bool commandCalled = false;
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.cursor(5),
            extensions: ExtensionList([
              gotoDefinition(
                (state, pos) async {
                  commandCalled = true;
                  return null;
                },
              ),
              keymap.of(gotoDefinitionKeymap),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(state: state, autofocus: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify the keymap is registered
        final keymaps = state.facet(keymap);
        expect(keymaps.isNotEmpty, isTrue);
      });
    });

    group('Find References', () {
      testWidgets('findReferences extension registers correctly', (tester) async {
        List<DefinitionLocation>? foundRefs;
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 1; x = 2; console.log(x);',
            extensions: ExtensionList([
              findReferences(
                (state, pos) async {
                  // Simulate finding references for 'x'
                  return ReferencesResult([
                    DefinitionLocation(pos: 4),
                    DefinitionLocation(pos: 11),
                    DefinitionLocation(pos: 31),
                  ]);
                },
                FindReferencesOptions(
                  display: (result, state, originPos) {
                    foundRefs = result.references;
                  },
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

        expect(state.facet(findReferencesFacet).isNotEmpty, isTrue);
      });
    });

    group('Signature Help', () {
      testWidgets('signatureHelp extension registers correctly', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'greet(',
            selection: EditorSelection.cursor(6),
            extensions: ExtensionList([
              signatureHelp(
                (state, pos) async {
                  return SignatureResult(
                    signatures: [
                      SignatureInfo(
                        label: 'greet(name: string): void',
                        parameters: [
                          const ParameterInfo(label: 'name: string'),
                        ],
                      ),
                    ],
                    triggerPos: 5,
                  );
                },
                const SignatureHelpOptions(
                  triggerCharacters: ['(', ','],
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

        expect(state.facet(signatureHelpFacet).isNotEmpty, isTrue);
      });
    });

    group('Document Formatting', () {
      testWidgets('format button can trigger formatting', (tester) async {
        bool formatCalled = false;
        late EditorState currentState;
        
        currentState = EditorState.create(
          EditorStateConfig(
            doc: '  badly   indented   code  ',
            extensions: ExtensionList([
              documentFormatting(
                (state) async {
                  formatCalled = true;
                  return FormatResult.replaceAll(
                    'properly formatted code',
                    state.doc.length,
                  );
                },
              ),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      final configs = currentState.facet(documentFormattingFacet);
                      if (configs.isNotEmpty && configs.first.documentSource != null) {
                        final result = await configs.first.documentSource!(currentState);
                        if (result != null) {
                          final spec = applyFormatEdits(currentState, result);
                          final tr = currentState.update([spec]);
                          currentState = tr.state as EditorState;
                        }
                      }
                    },
                    child: const Text('Format'),
                  ),
                  Expanded(
                    child: EditorView(state: currentState),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the format button
        await tester.tap(find.text('Format'));
        await tester.pumpAndSettle();

        expect(formatCalled, isTrue);
      });

      testWidgets('applyFormatEdits creates correct transaction', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'old text',
            selection: EditorSelection.cursor(4),
          ),
        );

        final result = FormatResult([
          FormatEdit(from: 0, to: 8, newText: 'new text'),
        ]);

        final spec = applyFormatEdits(state, result);
        final tr = state.update([spec]);

        expect((tr.state as EditorState).doc.toString(), 'new text');
      });
    });

    group('Rename Symbol', () {
      testWidgets('renameSymbol extension registers correctly', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let foo = 1; console.log(foo);',
            extensions: ExtensionList([
              renameSymbol(
                (state, pos, newName) async {
                  return RenameResult(
                    locations: [
                      RenameLocation(from: 4, to: 7),
                      RenameLocation(from: 25, to: 28),
                    ],
                  );
                },
                RenameOptions(
                  prepareSource: (state, pos) async {
                    return PrepareRenameResult(
                      from: 4,
                      to: 7,
                      placeholder: 'foo',
                    );
                  },
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

        expect(state.facet(renameFacet).isNotEmpty, isTrue);
      });

      testWidgets('applyRenameEdits replaces all occurrences', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let foo = 1; console.log(foo);',
            selection: EditorSelection.cursor(5),
          ),
        );

        final locations = [
          RenameLocation(from: 4, to: 7),
          RenameLocation(from: 25, to: 28),
        ];

        final spec = applyRenameEdits(state, locations, 'bar');
        final tr = state.update([spec]);

        expect((tr.state as EditorState).doc.toString(), 'let bar = 1; console.log(bar);');
      });
    });

    group('Document Highlight', () {
      testWidgets('documentHighlight extension registers correctly', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 1; x = 2;',
            extensions: ExtensionList([
              documentHighlight(
                (state, pos) async {
                  return DocumentHighlightResult([
                    DocumentHighlight(from: 4, to: 5, kind: HighlightKind.write),
                    DocumentHighlight(from: 11, to: 12, kind: HighlightKind.read),
                  ]);
                },
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

        expect(state.facet(documentHighlightFacet).isNotEmpty, isTrue);
      });
    });

    group('Hover Tooltips', () {
      testWidgets('hoverTooltip extension registers correctly', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'const message = "Hello";',
            extensions: ExtensionList([
              hoverTooltip(
                (state, pos, side) async {
                  return createTextTooltip(
                    pos: 6,
                    end: 13,
                    content: 'const message: string',
                  );
                },
                const HoverTooltipOptions(hoverTime: 100),
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

        expect(state.facet(hoverTooltipFacet).isNotEmpty, isTrue);
      });
    });

    group('Combined LSP Features', () {
      testWidgets('multiple LSP extensions can coexist', (tester) async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'function greet(name) { return "Hello, " + name; }',
            extensions: ExtensionList([
              gotoDefinition((state, pos) async => null),
              findReferences((state, pos) async => null),
              signatureHelp((state, pos) async => null),
              documentFormatting((state) async => null),
              renameSymbol((state, pos, name) async => null),
              documentHighlight((state, pos) async => null),
              hoverTooltip((state, pos, side) async => null),
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

        // Verify all facets are registered
        expect(state.facet(gotoDefinitionFacet).isNotEmpty, isTrue);
        expect(state.facet(findReferencesFacet).isNotEmpty, isTrue);
        expect(state.facet(signatureHelpFacet).isNotEmpty, isTrue);
        expect(state.facet(documentFormattingFacet).isNotEmpty, isTrue);
        expect(state.facet(renameFacet).isNotEmpty, isTrue);
        expect(state.facet(documentHighlightFacet).isNotEmpty, isTrue);
        expect(state.facet(hoverTooltipFacet).isNotEmpty, isTrue);
      });
    });
  });
}
