import 'package:codemirror/codemirror.dart' as cm hide Text;
import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();

  group('Search Commands', () {
    group('openSearchPanel', () {
      testWidgets('opens search panel via command and renders UI', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'Hello world, hello universe',
            extensions: ExtensionList([
              cm.search(),
              keymap.of(cm.searchKeymap),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final view = editorKey.currentState;
        expect(view, isNotNull, reason: 'EditorViewState should be accessible via key');

        expect(searchPanelOpen(state), isFalse, reason: 'Panel should start closed');

        final result = openSearchPanel(view!);
        expect(result, isTrue, reason: 'openSearchPanel should return true');

        await tester.pumpAndSettle();

        // Verify the panel is now open in state
        expect(searchPanelOpen(view.state), isTrue,
            reason: 'Panel should be open after command');

        // Verify the search panel UI is rendered
        expect(find.byType(TextField), findsWidgets,
            reason: 'Search panel should have text fields');
      });

      testWidgets('openSearchPanel returns true even when already open', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'Test content',
            extensions: ExtensionList([
              cm.search(),
              keymap.of(cm.searchKeymap),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final view = editorKey.currentState!;

        openSearchPanel(view);
        await tester.pumpAndSettle();

        final result = openSearchPanel(view);
        expect(result, isTrue);
      });
    });

    group('selectSelectionMatches', () {
      testWidgets('selects all matches of selected text', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world, hello universe, hello everyone',
            extensions: ExtensionList([
              cm.search(),
              allowMultipleSelections.of(true),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final view = editorKey.currentState!;

        view.dispatch([
          TransactionSpec(
            selection: EditorSelection.single(0, 5),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(state.selection.main.from, 0);
        expect(state.selection.main.to, 5);
        expect(state.sliceDoc(0, 5), 'hello');

        // Get the updated state after our dispatch
        final currentState = editorKey.currentState!.state;
        
        final result = selectSelectionMatches(
          currentState,
          (tr) => view.update([tr]),
        );

        await tester.pumpAndSettle();

        if (result) {
          final viewState = editorKey.currentState!;
          expect(viewState.state.selection.ranges.length, 3,
              reason: 'Should select all 3 "hello" matches');
        } else {
          fail('selectSelectionMatches returned false');
        }
      });

      testWidgets('returns false when selection is empty', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([cm.search()]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(state.selection.main.empty, isTrue);

        final result = selectSelectionMatches(
          state,
          (tr) => editorKey.currentState!.update([tr]),
        );

        expect(result, isFalse, reason: 'Should return false for empty selection');
      });

      testWidgets('returns false when multiple ranges already selected',
          (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world',
            extensions: ExtensionList([
              cm.search(),
              allowMultipleSelections.of(true),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // First verify the selection can be created correctly
        final testSel = EditorSelection.create([
          EditorSelection.range(0, 2),
          EditorSelection.range(6, 8),
        ]);
        expect(testSel.ranges.length, 2, 
            reason: 'EditorSelection.create should produce 2 ranges');

        final view = editorKey.currentState!;
        view.dispatch([
          TransactionSpec(selection: testSel),
        ]);
        await tester.pumpAndSettle();

        // Use the updated state after our dispatch
        final currentState = editorKey.currentState!.state;
        
        final result = selectSelectionMatches(
          currentState,
          (tr) => view.update([tr]),
        );

        // Note: selectSelectionMatches checks sel.ranges.length > 1 but we have 2 ranges
        // The implementation returns false only when ranges.length > 1 (which it is)
        // Let's verify the state first
        expect(currentState.selection.ranges.length, 2, 
            reason: 'Should have 2 selection ranges');
        expect(result, isFalse, 
            reason: 'Should return false when multiple ranges selected');
      });
    });

    group('closeSearchPanel', () {
      testWidgets('closes an open panel', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'Test content',
            extensions: ExtensionList([
              cm.search(),
              keymap.of(cm.searchKeymap),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final view = editorKey.currentState!;

        openSearchPanel(view);
        await tester.pumpAndSettle();

        final result = closeSearchPanel(view);
        expect(result, isTrue);
        await tester.pumpAndSettle();
      });

      testWidgets('returns false when panel is not open', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'Test content',
            extensions: ExtensionList([
              cm.search(),
            ]),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final view = editorKey.currentState!;
        final result = closeSearchPanel(view);
        expect(result, isFalse);
      });
    });
  });

  group('Search Keymap', () {
    test('searchKeymap contains expected bindings', () {
      final bindings = cm.searchKeymap;
      expect(bindings, isNotEmpty);

      final keys = bindings.map((b) => b.key).whereType<String>().toSet();
      expect(keys, contains('Mod-f'), reason: 'Should have Cmd/Ctrl+F binding');
      expect(keys, contains('F3'), reason: 'Should have F3 binding');
      expect(keys, contains('Mod-g'), reason: 'Should have Cmd/Ctrl+G binding');
      expect(keys, contains('Escape'), reason: 'Should have Escape binding');
    });

    test('search keymap bindings have run functions', () {
      for (final binding in cm.searchKeymap) {
        if (binding.key == 'Mod-f' ||
            binding.key == 'F3' ||
            binding.key == 'Mod-g' ||
            binding.key == 'Escape') {
          expect(binding.run, isNotNull,
              reason: 'Binding ${binding.key} should have a run function');
        }
      }
    });

    test('buildKeymap creates proper keymap structure', () {
      final builtKeymap = buildKeymap(cm.searchKeymap);
      
      expect(builtKeymap, isNotEmpty, reason: 'Keymap should not be empty');
      expect(builtKeymap.containsKey('editor'), isTrue,
          reason: 'Keymap should have editor scope');
      
      final editorScope = builtKeymap['editor']!;
      
      // On Mac, Mod-f becomes Meta-f
      // On non-Mac, Mod-f becomes Ctrl-f
      final hasCmdF = editorScope.containsKey('Meta-f');
      final hasCtrlF = editorScope.containsKey('Ctrl-f');
      expect(hasCmdF || hasCtrlF, isTrue,
          reason: 'Should have Meta-f or Ctrl-f binding. Keys: ${editorScope.keys}');
    });

    test('normalizeKeyName handles Mod- correctly', () {
      // On Mac, Mod- becomes Meta-
      // On other platforms, Mod- becomes Ctrl-
      final normalized = normalizeKeyName('Mod-f', isMac ? 'mac' : 'key');
      if (isMac) {
        expect(normalized, 'Meta-f');
      } else {
        expect(normalized, 'Ctrl-f');
      }
    });

    testWidgets('Mod-f keybinding triggers openSearchPanel', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'Test content',
          extensions: ExtensionList([
            cm.search(),
            keymap.of(cm.searchKeymap),
            keymap.of(standardKeymap),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) {
                state = update.state;
              },
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to focus
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;
      expect(view.hasFocus, isTrue, reason: 'Editor should have focus');

      // Check the keymap
      final km = getKeymap(view.state);
      print('Keymap scopes: ${km.keys}');
      print('Editor scope keys: ${km['editor']?.keys}');
      
      // Test that Meta-f is in the keymap
      final hasMetaF = km['editor']?.containsKey('Meta-f') ?? false;
      final hasCtrlF = km['editor']?.containsKey('Ctrl-f') ?? false;
      print('Has Meta-f: $hasMetaF, Has Ctrl-f: $hasCtrlF');
      
      // On Mac, should have Meta-f
      expect(hasMetaF || hasCtrlF, isTrue, 
          reason: 'Keymap should have Meta-f or Ctrl-f');
      
      // Now test the actual key event handling with a simple key
      // First just test that the keymap runner works with a matching key
      final binding = km['editor']!['Meta-f']!;
      expect(binding.run.isNotEmpty, isTrue, reason: 'Binding should have run functions');
      print('Meta-f binding has ${binding.run.length} run functions');
      
      // Call the binding directly
      final runResult = binding.run[0](view);
      print('Direct binding call result: $runResult');
      
      // Check if panel opened
      await tester.pumpAndSettle();
      expect(searchPanelOpen(view.state), isTrue, 
          reason: 'Search panel should be open after calling binding');
    });
  });

  group('SearchQuery in state', () {
    test('can retrieve search query from state', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello world',
          extensions: ExtensionList([cm.search()]),
        ),
      );

      final query = getSearchQuery(state);
      expect(query, isNotNull);
    });

    test('search query with selection initializes from selected text', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello world',
          selection: EditorSelection.single(0, 5),
          extensions: ExtensionList([cm.search()]),
        ),
      );

      final query = getSearchQuery(state);
      expect(query.search, 'Hello');
    });
  });

  group('Search extension', () {
    test('search() returns an extension', () {
      final ext = cm.search();
      expect(ext, isA<Extension>());
    });

    test('search() accepts configuration', () {
      final ext = cm.search(const SearchConfig(
        top: true,
        caseSensitive: true,
      ));
      expect(ext, isA<Extension>());
    });

    test('searchExtensions is available', () {
      expect(searchExtensions, isA<Extension>());
    });
  });

  group('findNext / findPrevious', () {
    testWidgets('findNext finds and selects first match from cursor', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world hello universe',
          // Start cursor at position 0
          selection: EditorSelection.cursor(0),
          extensions: ExtensionList([
            cm.search(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [setSearchQuery.of(SearchQuery(search: 'hello'))],
        ),
      ]);
      await tester.pumpAndSettle();

      final result = findNext(view);
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'findNext should return true when match found');
      
      // Verify the selection was set to the first "hello" (0-5)
      final sel = view.state.selection.main;
      expect(sel.from, 0, reason: 'Selection should start at first "hello"');
      expect(sel.to, 5, reason: 'Selection should end at 5');
    });

    testWidgets('findNext cycles through all matches', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'he and he and he',
          selection: EditorSelection.cursor(0),
          extensions: ExtensionList([
            cm.search(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [setSearchQuery.of(SearchQuery(search: 'he'))],
        ),
      ]);
      await tester.pumpAndSettle();

      // First findNext should find "he" at 0-2
      findNext(view);
      await tester.pumpAndSettle();
      expect(view.state.selection.main.from, 0, reason: 'First match at 0');
      expect(view.state.selection.main.to, 2);

      // Second findNext should find "he" at 7-9
      findNext(view);
      await tester.pumpAndSettle();
      expect(view.state.selection.main.from, 7, reason: 'Second match at 7');
      expect(view.state.selection.main.to, 9);

      // Third findNext should find "he" at 14-16
      findNext(view);
      await tester.pumpAndSettle();
      expect(view.state.selection.main.from, 14, reason: 'Third match at 14');
      expect(view.state.selection.main.to, 16);

      // Fourth findNext should wrap back to "he" at 0-2
      findNext(view);
      await tester.pumpAndSettle();
      expect(view.state.selection.main.from, 0, reason: 'Should wrap to first match');
      expect(view.state.selection.main.to, 2);
    });

    testWidgets('findNext finds next match', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world hello universe',
          extensions: ExtensionList([
            cm.search(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [setSearchQuery.of(SearchQuery(search: 'hello'))],
        ),
      ]);
      await tester.pumpAndSettle();

      final result = findNext(view);
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'findNext should return true when match found');
    });

    testWidgets('findPrevious finds previous match', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world hello universe',
          selection: EditorSelection.cursor(20),
          extensions: ExtensionList([
            cm.search(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [setSearchQuery.of(SearchQuery(search: 'hello'))],
        ),
      ]);
      await tester.pumpAndSettle();

      final result = findPrevious(view);
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'findPrevious should return true when match found');
    });
  });

  group('Replace operations', () {
    testWidgets('replaceNext replaces current match', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            cm.search(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [
            setSearchQuery.of(SearchQuery(search: 'hello', replace: 'hi')),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(selection: EditorSelection.single(0, 5)),
      ]);
      await tester.pumpAndSettle();

      final result = replaceNext(view);
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'replaceNext should succeed');
    });

    testWidgets('replaceAll replaces all matches', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world hello universe',
          extensions: ExtensionList([
            cm.search(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [
            setSearchQuery.of(SearchQuery(search: 'hello', replace: 'hi')),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      final result = replaceAll(view);
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'replaceAll should succeed');

      final newState = editorKey.currentState!.state;
      expect(newState.doc.toString(), 'hi world hi universe');
    });
  });

  group('Search state field', () {
    test('searchState field can be queried', () {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Test',
          extensions: ExtensionList([cm.search()]),
        ),
      );

      final searchStateValue = state.field(searchState, false);
      expect(searchStateValue, isNotNull, reason: 'searchState field should exist');
    });

    test('setSearchQuery effect updates query', () {
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'Test',
          extensions: ExtensionList([cm.search()]),
        ),
      );

      final tr = state.update([
        TransactionSpec(
          effects: [setSearchQuery.of(SearchQuery(search: 'test'))],
        ),
      ]);

      state = tr.state as EditorState;
      final query = getSearchQuery(state);
      expect(query.search, 'test');
    });
  });
}
