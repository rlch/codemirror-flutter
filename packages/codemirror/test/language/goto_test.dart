import 'dart:async';

import 'package:codemirror/codemirror.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Goto Module Unit Tests', () {
    group('DefinitionKind', () {
      test('has all expected values', () {
        expect(DefinitionKind.values.length, 4);
        expect(DefinitionKind.definition.name, 'definition');
        expect(DefinitionKind.declaration.name, 'declaration');
        expect(DefinitionKind.typeDefinition.name, 'typeDefinition');
        expect(DefinitionKind.implementation.name, 'implementation');
      });
    });

    group('DefinitionLocation', () {
      test('can create local location', () {
        const loc = DefinitionLocation(pos: 10);
        expect(loc.pos, 10);
        expect(loc.uri, isNull);
        expect(loc.isLocal, isTrue);
        expect(loc.end, isNull);
        expect(loc.line, isNull);
        expect(loc.column, isNull);
      });

      test('can create local location with range', () {
        final loc = DefinitionLocation.local(10, end: 20);
        expect(loc.pos, 10);
        expect(loc.end, 20);
        expect(loc.isLocal, isTrue);
      });

      test('can create external location', () {
        final loc = DefinitionLocation.external(
          uri: 'file:///path/to/file.dart',
          line: 5,
          column: 10,
        );
        expect(loc.uri, 'file:///path/to/file.dart');
        expect(loc.pos, 0); // default when not specified
        expect(loc.line, 5);
        expect(loc.column, 10);
        expect(loc.isLocal, isFalse);
      });

      test('can create external location with pos', () {
        final loc = DefinitionLocation.external(
          uri: 'file:///other.dart',
          pos: 100,
          line: 10,
          column: 5,
        );
        expect(loc.uri, 'file:///other.dart');
        expect(loc.pos, 100);
        expect(loc.isLocal, isFalse);
      });

      test('toString for local location', () {
        const loc = DefinitionLocation(pos: 42);
        expect(loc.toString(), 'DefinitionLocation(pos: 42)');
      });

      test('toString for local location with range', () {
        final loc = DefinitionLocation.local(10, end: 20);
        expect(loc.toString(), 'DefinitionLocation(pos: 10-20)');
      });

      test('toString for external location', () {
        final loc = DefinitionLocation.external(
          uri: 'file:///test.dart',
          line: 5,
          column: 10,
        );
        expect(loc.toString(), 'DefinitionLocation(file:///test.dart:5:10)');
      });
    });

    group('DefinitionResult', () {
      test('can create empty result', () {
        expect(DefinitionResult.empty.isEmpty, isTrue);
        expect(DefinitionResult.empty.isNotEmpty, isFalse);
        expect(DefinitionResult.empty.primary, isNull);
        expect(DefinitionResult.empty.definitions, isEmpty);
      });

      test('can create single result', () {
        final loc = DefinitionLocation.local(42);
        final result = DefinitionResult.single(loc);
        
        expect(result.isEmpty, isFalse);
        expect(result.isNotEmpty, isTrue);
        expect(result.primary, equals(loc));
        expect(result.definitions.length, 1);
      });

      test('can create multi-definition result', () {
        final result = DefinitionResult([
          DefinitionLocation.local(10),
          DefinitionLocation.local(20),
          DefinitionLocation.external(uri: 'file:///other.dart'),
        ]);
        
        expect(result.definitions.length, 3);
        expect(result.primary?.pos, 10);
      });
    });

    group('ReferencesResult', () {
      test('can create empty result', () {
        expect(ReferencesResult.empty.isEmpty, isTrue);
        expect(ReferencesResult.empty.isNotEmpty, isFalse);
        expect(ReferencesResult.empty.length, 0);
      });

      test('can create result with references', () {
        final result = ReferencesResult([
          DefinitionLocation.local(10),
          DefinitionLocation.local(50),
          DefinitionLocation.local(100),
        ]);
        
        expect(result.isEmpty, isFalse);
        expect(result.isNotEmpty, isTrue);
        expect(result.length, 3);
        expect(result.references[0].pos, 10);
      });
    });

    group('GotoDefinitionOptions', () {
      test('has sensible defaults', () {
        const options = GotoDefinitionOptions();
        expect(options.navigator, isNull);
        expect(options.showHoverUnderline, isTrue);
        expect(options.clickModifier, isNull);
      });

      test('isClickModifierActive uses default on non-Mac', () {
        const options = GotoDefinitionOptions();
        // Default is Ctrl on non-Mac
        if (!isMac) {
          expect(
            options.isClickModifierActive(
              ctrl: true,
              meta: false,
              alt: false,
              shift: false,
            ),
            isTrue,
          );
          expect(
            options.isClickModifierActive(
              ctrl: false,
              meta: true,
              alt: false,
              shift: false,
            ),
            isFalse,
          );
        }
      });

      test('custom clickModifier is respected', () {
        final options = GotoDefinitionOptions(
          clickModifier: (ctrl, meta, alt, shift) => alt && shift,
        );
        
        expect(
          options.isClickModifierActive(
            ctrl: false,
            meta: false,
            alt: true,
            shift: true,
          ),
          isTrue,
        );
        expect(
          options.isClickModifierActive(
            ctrl: true,
            meta: false,
            alt: false,
            shift: false,
          ),
          isFalse,
        );
      });
    });

    group('gotoDefinitionFacet', () {
      test('can register definition source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              gotoDefinition((state, pos) {
                return DefinitionResult.single(DefinitionLocation.local(0));
              }),
            ]),
          ),
        );

        final configs = state.facet(gotoDefinitionFacet);
        expect(configs.length, 1);
        expect(configs[0].source, isNotNull);
      });

      test('can register multiple definition sources', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              gotoDefinition((state, pos) => DefinitionResult.empty),
              gotoDefinition((state, pos) => DefinitionResult.empty),
            ]),
          ),
        );

        final configs = state.facet(gotoDefinitionFacet);
        expect(configs.length, 2);
      });
    });

    group('gotoDeclarationFacet', () {
      test('can register declaration source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              gotoDeclaration((state, pos) {
                return DefinitionResult.single(DefinitionLocation.local(0));
              }),
            ]),
          ),
        );

        final configs = state.facet(gotoDeclarationFacet);
        expect(configs.length, 1);
      });
    });

    group('gotoTypeDefinitionFacet', () {
      test('can register type definition source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'int x = 5;',
            extensions: ExtensionList([
              gotoTypeDefinition((state, pos) {
                // Would return the 'int' type location
                return DefinitionResult.single(DefinitionLocation.local(0));
              }),
            ]),
          ),
        );

        final configs = state.facet(gotoTypeDefinitionFacet);
        expect(configs.length, 1);
      });
    });

    group('gotoImplementationFacet', () {
      test('can register implementation source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'abstract class Foo {}',
            extensions: ExtensionList([
              gotoImplementation((state, pos) {
                // Would return implementations of Foo
                return DefinitionResult([
                  DefinitionLocation.local(100),
                  DefinitionLocation.local(200),
                ]);
              }),
            ]),
          ),
        );

        final configs = state.facet(gotoImplementationFacet);
        expect(configs.length, 1);
      });
    });

    group('findReferencesFacet', () {
      test('can register references source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              findReferences((state, pos) {
                return ReferencesResult([
                  DefinitionLocation.local(0),
                  DefinitionLocation.local(10),
                ]);
              }),
            ]),
          ),
        );

        final configs = state.facet(findReferencesFacet);
        expect(configs.length, 1);
      });

      test('FindReferencesOptions can set display callback', () {
        ReferencesResult? receivedResult;
        int? receivedPos;

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              findReferences(
                (state, pos) => ReferencesResult([DefinitionLocation.local(pos)]),
                FindReferencesOptions(
                  display: (result, state, pos) {
                    receivedResult = result;
                    receivedPos = pos;
                  },
                ),
              ),
            ]),
          ),
        );

        final configs = state.facet(findReferencesFacet);
        expect(configs[0].options.display, isNotNull);

        // Manually invoke to test the callback works
        configs[0].options.display!(
          ReferencesResult([DefinitionLocation.local(42)]),
          state,
          42,
        );
        expect(receivedResult?.length, 1);
        expect(receivedPos, 42);
      });
    });

    group('Commands and Effects', () {
      test('goToDefinitionCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.cursor(5),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = goToDefinitionCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerDefinitionEffect)),
          isTrue,
        );
      });

      test('goToDeclarationCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            selection: EditorSelection.cursor(3),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = goToDeclarationCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerDeclarationEffect)),
          isTrue,
        );
      });

      test('goToTypeDefinitionCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'int x = 5;',
            selection: EditorSelection.cursor(4),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = goToTypeDefinitionCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerTypeDefinitionEffect)),
          isTrue,
        );
      });

      test('goToImplementationCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'abstract class Foo {}',
            selection: EditorSelection.cursor(15),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = goToImplementationCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerImplementationEffect)),
          isTrue,
        );
      });

      test('findReferencesCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5; y = x;',
            selection: EditorSelection.cursor(4),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = findReferencesCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerReferencesEffect)),
          isTrue,
        );
      });
    });

    group('Keymaps', () {
      test('gotoDefinitionKeymap contains F12 and Mod-b', () {
        expect(
          gotoDefinitionKeymap.any((k) => k.key == 'F12'),
          isTrue,
        );
        expect(
          gotoDefinitionKeymap.any((k) => k.key == 'Mod-b'),
          isTrue,
        );
      });

      test('gotoTypeDefinitionKeymap contains Mod-F12', () {
        expect(
          gotoTypeDefinitionKeymap.any((k) => k.key == 'Mod-F12'),
          isTrue,
        );
      });

      test('gotoImplementationKeymap contains Ctrl-F12', () {
        expect(
          gotoImplementationKeymap.any((k) => k.key == 'Ctrl-F12'),
          isTrue,
        );
      });

      test('findReferencesKeymap contains Shift-F12', () {
        expect(
          findReferencesKeymap.any((k) => k.key == 'Shift-F12'),
          isTrue,
        );
      });

      test('allDefinitionKeymap contains all bindings', () {
        expect(allDefinitionKeymap.length, greaterThanOrEqualTo(5));
        expect(
          allDefinitionKeymap.any((k) => k.key == 'F12'),
          isTrue,
        );
        expect(
          allDefinitionKeymap.any((k) => k.key == 'Mod-F12'),
          isTrue,
        );
        expect(
          allDefinitionKeymap.any((k) => k.key == 'Shift-F12'),
          isTrue,
        );
      });
    });

    group('Async Sources', () {
      test('async definition source works', () async {
        DefinitionResult? result;
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              gotoDefinition((state, pos) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return DefinitionResult.single(DefinitionLocation.local(pos * 2));
              }),
            ]),
          ),
        );

        final configs = state.facet(gotoDefinitionFacet);
        result = await configs[0].source(state, 5);
        
        expect(result?.primary?.pos, 10);
      });

      test('async references source works', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'x = 1; y = x; z = x;',
            extensions: ExtensionList([
              findReferences((state, pos) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return ReferencesResult([
                  DefinitionLocation.local(0),
                  DefinitionLocation.local(11),
                  DefinitionLocation.local(18),
                ]);
              }),
            ]),
          ),
        );

        final configs = state.facet(findReferencesFacet);
        final result = await configs[0].source(state, 0);
        
        expect(result?.length, 3);
      });
    });

    group('Extension Helpers', () {
      test('gotoDefinitionKeymapExt creates keymap extension', () {
        final ext = gotoDefinitionKeymapExt();
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

      test('allDefinitionKeymapExt creates combined keymap extension', () {
        final ext = allDefinitionKeymapExt();
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
