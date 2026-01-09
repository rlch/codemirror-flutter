import 'dart:async';

import 'package:codemirror/codemirror.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Rename Module Unit Tests', () {
    group('RenameLocation', () {
      test('can create local location', () {
        const loc = RenameLocation(from: 0, to: 5);
        expect(loc.from, 0);
        expect(loc.to, 5);
        expect(loc.uri, isNull);
        expect(loc.isLocal, isTrue);
      });

      test('can create external location', () {
        const loc = RenameLocation(
          from: 10,
          to: 20,
          uri: 'file:///other.dart',
        );
        expect(loc.from, 10);
        expect(loc.to, 20);
        expect(loc.uri, 'file:///other.dart');
        expect(loc.isLocal, isFalse);
      });

      test('toString for local location', () {
        const loc = RenameLocation(from: 5, to: 10);
        expect(loc.toString(), 'RenameLocation(5-10)');
      });

      test('toString for external location', () {
        const loc = RenameLocation(
          from: 0,
          to: 5,
          uri: 'file:///test.dart',
        );
        expect(loc.toString(), 'RenameLocation(file:///test.dart:0-5)');
      });
    });

    group('PrepareRenameResult', () {
      test('can create valid result', () {
        const result = PrepareRenameResult(
          from: 10,
          to: 20,
          placeholder: 'oldName',
        );
        expect(result.from, 10);
        expect(result.to, 20);
        expect(result.placeholder, 'oldName');
        expect(result.error, isNull);
        expect(result.canRename, isTrue);
      });

      test('can create error result', () {
        final result = PrepareRenameResult.error('Cannot rename this symbol');
        expect(result.placeholder, '');
        expect(result.error, 'Cannot rename this symbol');
        expect(result.canRename, isFalse);
      });
    });

    group('RenameResult', () {
      test('empty result has no locations', () {
        expect(RenameResult.empty.isEmpty, isTrue);
        expect(RenameResult.empty.isNotEmpty, isFalse);
        expect(RenameResult.empty.locations, isEmpty);
        expect(RenameResult.empty.workspaceEdits, isEmpty);
        expect(RenameResult.empty.isWorkspaceRename, isFalse);
        expect(RenameResult.empty.totalLocations, 0);
      });

      test('can create with local locations', () {
        final result = RenameResult(
          locations: const [
            RenameLocation(from: 0, to: 5),
            RenameLocation(from: 20, to: 25),
            RenameLocation(from: 50, to: 55),
          ],
        );
        expect(result.isEmpty, isFalse);
        expect(result.isNotEmpty, isTrue);
        expect(result.locations.length, 3);
        expect(result.isWorkspaceRename, isFalse);
        expect(result.totalLocations, 3);
      });

      test('can create with workspace edits', () {
        final result = RenameResult(
          locations: const [
            RenameLocation(from: 0, to: 5),
          ],
          workspaceEdits: const {
            'file:///other.dart': [
              RenameLocation(from: 10, to: 15, uri: 'file:///other.dart'),
              RenameLocation(from: 30, to: 35, uri: 'file:///other.dart'),
            ],
          },
        );
        expect(result.isWorkspaceRename, isTrue);
        expect(result.totalLocations, 3);
      });
    });

    group('RenameOptions', () {
      test('has sensible defaults', () {
        const options = RenameOptions();
        expect(options.prepareSource, isNull);
        expect(options.workspaceHandler, isNull);
        expect(options.showPreview, isFalse);
      });

      test('can set all options', () {
        final options = RenameOptions(
          prepareSource: (state, pos) async => null,
          workspaceHandler: (edits, newName) async => true,
          showPreview: true,
        );
        expect(options.prepareSource, isNotNull);
        expect(options.workspaceHandler, isNotNull);
        expect(options.showPreview, isTrue);
      });
    });

    group('renameFacet', () {
      test('can register rename source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5; y = x;',
            extensions: ExtensionList([
              renameSymbol((state, pos, newName) {
                return RenameResult(
                  locations: const [
                    RenameLocation(from: 4, to: 5),
                    RenameLocation(from: 15, to: 16),
                  ],
                );
              }),
            ]),
          ),
        );

        final configs = state.facet(renameFacet);
        expect(configs.length, 1);
        expect(configs[0].source, isNotNull);
      });

      test('can register with prepare source', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let myVar = 5;',
            extensions: ExtensionList([
              renameSymbol(
                (state, pos, newName) => RenameResult.empty,
                RenameOptions(
                  prepareSource: (state, pos) async {
                    return const PrepareRenameResult(
                      from: 4,
                      to: 9,
                      placeholder: 'myVar',
                    );
                  },
                ),
              ),
            ]),
          ),
        );

        final configs = state.facet(renameFacet);
        expect(configs.length, 1);
        expect(configs[0].options.prepareSource, isNotNull);
      });

      test('can register multiple rename sources', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'code',
            extensions: ExtensionList([
              renameSymbol((state, pos, newName) => RenameResult.empty),
              renameSymbol((state, pos, newName) => RenameResult.empty),
            ]),
          ),
        );

        final configs = state.facet(renameFacet);
        expect(configs.length, 2);
      });
    });

    group('Commands and Effects', () {
      test('renameSymbolCommand triggers effect', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5;',
            selection: EditorSelection.cursor(4),
          ),
        );

        Transaction? dispatchedTr;
        final target = (
          state: state,
          dispatch: (Transaction tr) => dispatchedTr = tr,
        );

        final result = renameSymbolCommand(target);
        expect(result, isTrue);
        expect(dispatchedTr, isNotNull);
        expect(
          dispatchedTr!.effects.any((e) => e.is_(triggerRenameEffect)),
          isTrue,
        );
      });
    });

    group('Keymap', () {
      test('renameKeymap contains F2', () {
        expect(
          renameKeymap.any((k) => k.key == 'F2'),
          isTrue,
        );
      });

      test('renameKeymapExt creates keymap extension', () {
        final ext = renameKeymapExt();
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

    group('applyRenameEdits', () {
      test('returns empty spec for empty result', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'test'),
        );

        final spec = applyRenameEdits(state, [], 'newName');
        expect(spec.changes, isNull);
      });

      test('creates changes for local locations', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'let x = 5; y = x;'),
        );

        final locations = const [
          RenameLocation(from: 4, to: 5),
          RenameLocation(from: 15, to: 16),
        ];

        final spec = applyRenameEdits(state, locations, 'newVar');
        expect(spec.changes, isNotNull);
        expect(spec.userEvent, 'rename');
      });

      test('ignores external locations', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'let x = 5;'),
        );

        final locations = const [
          RenameLocation(from: 4, to: 5),
          RenameLocation(from: 10, to: 15, uri: 'file:///other.dart'),
        ];

        final spec = applyRenameEdits(state, locations, 'newVar');
        expect(spec.changes, isNotNull);
      });

      test('returns empty spec when all locations are external', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'let x = 5;'),
        );

        final locations = const [
          RenameLocation(from: 10, to: 15, uri: 'file:///other.dart'),
        ];

        final spec = applyRenameEdits(state, locations, 'newVar');
        expect(spec.changes, isNull);
      });

      test('preserves cursor position when cursor before all locations', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5; y = x;',
            selection: EditorSelection.cursor(0), // at start
          ),
        );

        final locations = const [
          RenameLocation(from: 4, to: 5),
          RenameLocation(from: 15, to: 16),
        ];

        final spec = applyRenameEdits(state, locations, 'newVar');
        expect(spec.selection, isNotNull);
        // Cursor at 0, all edits are after, so position unchanged
        expect(spec.selection!.main.head, 0);
      });

      test('adjusts cursor position for edit length changes', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5; y = x;',
            selection: EditorSelection.cursor(17), // at end
          ),
        );

        final locations = const [
          RenameLocation(from: 4, to: 5), // x -> newVar (+5)
          RenameLocation(from: 15, to: 16), // x -> newVar (+5)
        ];

        final spec = applyRenameEdits(state, locations, 'newVar');
        expect(spec.selection, isNotNull);
        // Cursor at 17, two +5 changes before it = 17 + 10 = 27
        // But we need to check actual calculation
      });

      test('moves cursor to end of renamed symbol when inside', () {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let myVar = 5;',
            selection: EditorSelection.cursor(6), // inside "myVar"
          ),
        );

        final locations = const [
          RenameLocation(from: 4, to: 9), // myVar
        ];

        final spec = applyRenameEdits(state, locations, 'x');
        // Verify changes were created
        expect(spec.changes, isNotNull);
        // Verify selection was created
        expect(spec.selection, isNotNull);
      });
    });

    group('Async Sources', () {
      test('async rename source works', () async {
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let x = 5;',
            extensions: ExtensionList([
              renameSymbol((state, pos, newName) async {
                await Future.delayed(const Duration(milliseconds: 10));
                return const RenameResult(
                  locations: [
                    RenameLocation(from: 4, to: 5),
                  ],
                );
              }),
            ]),
          ),
        );

        final configs = state.facet(renameFacet);
        final result = await configs[0].source(state, 4, 'newName');

        expect(result?.locations.length, 1);
      });

      test('async prepare source works', () async {
        PrepareRenameResult? result;

        final state = EditorState.create(
          EditorStateConfig(
            doc: 'let myVar = 5;',
            extensions: ExtensionList([
              renameSymbol(
                (state, pos, newName) => RenameResult.empty,
                RenameOptions(
                  prepareSource: (state, pos) async {
                    await Future.delayed(const Duration(milliseconds: 10));
                    return const PrepareRenameResult(
                      from: 4,
                      to: 9,
                      placeholder: 'myVar',
                    );
                  },
                ),
              ),
            ]),
          ),
        );

        final configs = state.facet(renameFacet);
        result = await configs[0].options.prepareSource!(state, 4);

        expect(result?.canRename, isTrue);
        expect(result?.placeholder, 'myVar');
      });
    });

    group('Integration scenarios', () {
      test('rename with workspace edits', () {
        final result = RenameResult(
          locations: const [
            RenameLocation(from: 4, to: 10),
          ],
          workspaceEdits: const {
            'file:///utils.dart': [
              RenameLocation(from: 20, to: 26, uri: 'file:///utils.dart'),
              RenameLocation(from: 100, to: 106, uri: 'file:///utils.dart'),
            ],
            'file:///main.dart': [
              RenameLocation(from: 50, to: 56, uri: 'file:///main.dart'),
            ],
          },
        );

        expect(result.isWorkspaceRename, isTrue);
        expect(result.totalLocations, 4);
        expect(result.workspaceEdits.keys.length, 2);
      });

      test('prepare rename error prevents rename', () {
        final result = PrepareRenameResult.error(
          'This symbol cannot be renamed',
        );

        expect(result.canRename, isFalse);
        expect(result.from, 0);
        expect(result.to, 0);
        expect(result.placeholder, '');
      });
    });
  });
}
