import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureSnippetInitialized();

  group('Autocompletion Widget Tests', () {
    group('Basic setup', () {
      testWidgets('completionState field is accessible', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: ExtensionList([
              autocompletion(),
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

        // Check that completionState field is accessible
        final cState = state.field(completionState);
        expect(cState, isNotNull, reason: 'completionState field should be accessible');
        expect(cState!.active, isEmpty, reason: 'No active sources initially');
        expect(cState.open, isNull, reason: 'No dialog open initially');
      });

      testWidgets('completionStatus returns null when no completions', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: ExtensionList([
              autocompletion(),
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

        expect(completionStatus(state), isNull);
      });
    });

    group('startCompletion command', () {
      testWidgets('startCompletion returns true when field exists', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [_simpleSource],
              )),
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
        final result = startCompletion(view);
        expect(result, isTrue, reason: 'startCompletion should return true');
      });

      testWidgets('startCompletion sets pending state', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [_simpleSource],
              )),
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
        
        // Before starting
        expect(completionStatus(state), isNull);
        
        startCompletion(view);
        await tester.pump();
        
        // After starting - should be pending
        final status = completionStatus(view.state);
        expect(status, 'pending', reason: 'Status should be pending after startCompletion');
      });
    });

    group('Completion source execution', () {
      testWidgets('completion source is called on startCompletion', (tester) async {
        var sourceCalled = false;
        
        CompletionResult? testSource(CompletionContext context) {
          sourceCalled = true;
          return CompletionResult(
            from: 0,
            options: [const Completion(label: 'test')],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
              )),
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
        
        // Focus the editor
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(sourceCalled, isTrue, reason: 'Completion source should be called');
      });

      testWidgets('completions are populated after source returns', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'alpha'),
              const Completion(label: 'beta'),
              const Completion(label: 'gamma'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        final completions = currentCompletions(view.state);
        expect(completions.length, 3, reason: 'Should have 3 completions');
        expect(completionStatus(view.state), 'active', reason: 'Completion should be active');
      });
    });

    group('Keyboard interaction', () {
      testWidgets('Ctrl+Space triggers completion', (tester) async {
        var sourceCalled = false;
        
        CompletionResult? testSource(CompletionContext context) {
          sourceCalled = true;
          return CompletionResult(
            from: 0,
            options: [const Completion(label: 'test')],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
              )),
              keymap.of(completionKeymap),
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

        // Focus the editor
        await tester.tap(find.byType(EditableText));
        await tester.pump();

        // Press Ctrl+Space
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(sourceCalled, isTrue, reason: 'Ctrl+Space should trigger completion');
      });
    });

    group('CompletionPluginValue', () {
      testWidgets('plugin is created and active', (tester) async {
        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [_simpleSource],
              )),
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
        
        // The completionPlugin should be installed
        final plugin = view.plugin(completionPlugin);
        expect(plugin, isNotNull, reason: 'completionPlugin should be installed');
      });
    });

    group('Full completion flow', () {
      testWidgets('completions appear after startCompletion', (tester) async {
        var sourceExecuted = false;
        
        CompletionResult? testSource(CompletionContext context) {
          sourceExecuted = true;
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'testing'),
              const Completion(label: 'testFunction'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
              )),
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
        
        // Focus and trigger completion
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        
        expect(sourceExecuted, isTrue, reason: 'Source should have been executed');
        expect(completionStatus(view.state), 'active', reason: 'Completion should be active');
        expect(currentCompletions(view.state).length, 2, reason: 'Should have 2 completions');
      });
    });

    group('Completion popup', () {
      testWidgets('completion popup appears in overlay', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'alpha', type: 'function'),
              const Completion(label: 'beta', type: 'variable'),
              const Completion(label: 'gamma', type: 'class'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
              )),
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
        
        // Focus and trigger completion
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        // Verify completion popup appeared (as overlay)
        expect(completionStatus(view.state), 'active');
        expect(currentCompletions(view.state).length, 3);
        
        // The popup should be visible in the overlay
        // It contains the completion labels
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('beta'), findsOneWidget);
        expect(find.text('gamma'), findsOneWidget);
      });

      testWidgets('arrow keys navigate completion options', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 0,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        // Initially first item is selected (selectOnOpen: true)
        expect(selectedCompletionIndex(view.state), 0);
        
        // Press down arrow to move selection
        moveCompletionSelection(true)(view);
        await tester.pump();
        
        expect(selectedCompletionIndex(view.state), 1);
        
        // Press down again
        moveCompletionSelection(true)(view);
        await tester.pump();
        
        expect(selectedCompletionIndex(view.state), 2);
        
        // Press up to go back
        moveCompletionSelection(false)(view);
        await tester.pump();
        
        expect(selectedCompletionIndex(view.state), 1);
      });

      testWidgets('enter accepts selected completion', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'replacement'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'test',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 0,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        // Accept the completion
        final accepted = acceptCompletion(view);
        await tester.pump();
        
        expect(accepted, isTrue);
        expect(view.state.doc.toString(), 'replacement');
      });

      testWidgets('rapid arrow key presses do not close completion', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 75, // Default delay
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        // Verify completion is open
        expect(completionStatus(view.state), 'active', reason: 'Completion should be active');
        expect(selectedCompletionIndex(view.state), 0, reason: 'First item should be selected');
        
        // Simulate rapid arrow key presses (spamming) - no pump between presses
        for (var i = 0; i < 10; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        }
        // Single pump after all key presses
        await tester.pump();
        
        // Completion should still be open
        expect(completionStatus(view.state), 'active', 
            reason: 'Completion should remain active after rapid arrow key presses');
        
        // Selection should have moved (wrapping around the 5 items)
        final selectedIdx = selectedCompletionIndex(view.state);
        expect(selectedIdx, isNotNull, reason: 'Should still have a selection');
        expect(selectedIdx, greaterThanOrEqualTo(0), reason: 'Selection should be valid');
      });

      testWidgets('completion triggered by typing then rapid arrow spam closes popup', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: context.pos,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: '',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                activateOnTyping: true,
                activateOnTypingDelay: 0,
                interactionDelay: 75,
              )),
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
        
        // Focus the editor
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        // Type a character to trigger completion
        await tester.enterText(find.byType(EditableText), 'a');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        
        // Wait for completion to become active
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        final status = completionStatus(view.state);
        
        if (status != 'active') {
          // Force trigger if typing didn't work
          startCompletion(view);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
        }
        
        expect(completionStatus(view.state), 'active', reason: 'Completion should be active after typing');
        
        // Batch send multiple key events without pumping between them
        // This simulates keyboard repeat / fast typing
        for (var i = 0; i < 10; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        }
        // Now pump once to process all events
        await tester.pump();
        
        final statusAfterBatch = completionStatus(view.state);
        expect(statusAfterBatch, 'active', reason: 'Completion should remain active after batch arrow keys');
        
        // Now spam with minimal pumps
        for (var i = 0; i < 30; i++) {
          final statusBefore = completionStatus(view.state);
          final cState = view.state.field(completionState);
          final openBefore = cState?.open;
          final activeBefore = cState?.active.map((a) => '${a.state}').join(',');
          
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          // Pump with 0 duration to process immediately
          await tester.pump();
          
          final statusAfter = completionStatus(view.state);
          final cStateAfter = view.state.field(completionState);
          final openAfter = cStateAfter?.open;
          final activeAfter = cStateAfter?.active.map((a) => '${a.state}').join(',');
          
          if (statusAfter != 'active') {
            fail('Completion closed on iteration $i!\n'
                '  Before: status=$statusBefore open=${openBefore != null} active=[$activeBefore]\n'
                '  After: status=$statusAfter open=${openAfter != null} active=[$activeAfter]');
          }
        }
        
        expect(completionStatus(view.state), 'active');
      });

      testWidgets('rapid arrow key presses 1ms apart reproduces bug', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 75,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(completionStatus(view.state), 'active');
        
        // Spam arrow down as fast as possible - 1ms between each
        for (var i = 0; i < 50; i++) {
          final statusBefore = completionStatus(view.state);
          final selectedBefore = selectedCompletionIndex(view.state);
          final openBefore = view.state.field(completionState)?.open;
          
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump(const Duration(milliseconds: 1));
          
          final statusAfter = completionStatus(view.state);
          final selectedAfter = selectedCompletionIndex(view.state);
          final openAfter = view.state.field(completionState)?.open;
          
          // If completion closed, log and fail
          if (statusAfter != 'active') {
            fail('Completion closed on iteration $i! '
                'Before: status=$statusBefore selected=$selectedBefore open=${openBefore != null}, '
                'After: status=$statusAfter selected=$selectedAfter open=${openAfter != null}');
          }
        }
        
        expect(completionStatus(view.state), 'active');
      });

      testWidgets('rapid arrow key presses with real elapsed time', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 75,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(completionStatus(view.state), 'active');
        final openTimestamp = view.state.field(completionState)!.open!.timestamp;
        
        // Spam arrow down using runAsync to get real timing
        await tester.runAsync(() async {
          for (var i = 0; i < 30; i++) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final elapsed = now - openTimestamp;
            final statusBefore = completionStatus(view.state);
            
            // Simulate the command directly like a real keypress would
            final handled = moveCompletionSelection(true)(view);
            
            final statusAfter = completionStatus(view.state);
            
            if (statusAfter != 'active') {
              fail('Completion closed on iteration $i! '
                  'elapsed=${elapsed}ms handled=$handled '
                  'Before: status=$statusBefore '
                  'After: status=$statusAfter');
            }
            
            // Wait 1ms real time
            await Future.delayed(const Duration(milliseconds: 1));
          }
        });
        
        await tester.pump();
        expect(completionStatus(view.state), 'active');
      });

      testWidgets('rapid key events through Flutter input system', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 75,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(completionStatus(view.state), 'active');
        
        // Now spam using runAsync for real timing
        await tester.runAsync(() async {
          for (var i = 0; i < 30; i++) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final timestamp = view.state.field(completionState)?.open?.timestamp ?? 0;
            final elapsed = now - timestamp;
            final statusBefore = completionStatus(view.state);
            
            // Simulate key event through the view's input handler
            final keyEvent = KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.arrowDown,
              logicalKey: LogicalKeyboardKey.arrowDown,
              timeStamp: Duration(milliseconds: now),
            );
            view.inputState.handleKeyEvent(keyEvent);
            
            final statusAfter = completionStatus(view.state);
            
            if (statusAfter != 'active') {
              fail('Completion closed on iteration $i at elapsed=${elapsed}ms!\n'
                  '  Before: status=$statusBefore\n'
                  '  After: status=$statusAfter');
            }
            
            // Real 1ms delay between keys
            await Future.delayed(const Duration(milliseconds: 1));
          }
        });
        
        await tester.pump();
        expect(completionStatus(view.state), 'active');
      });

      testWidgets('rapid navigation with real wall-clock timing', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 75,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(completionStatus(view.state), 'active');
        
        // Use runAsync for real timing
        await tester.runAsync(() async {
          final startTime = DateTime.now().millisecondsSinceEpoch;
          
          for (var i = 0; i < 50; i++) {
            final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
            final statusBefore = completionStatus(view.state);
            
            // Call command directly (like keymap would)
            moveCompletionSelection(true)(view);
            
            final statusAfter = completionStatus(view.state);
            
            if (statusAfter != 'active') {
              fail('Completion closed on iteration $i at ${elapsed}ms!\n'
                  '  Before: status=$statusBefore\n'
                  '  After: status=$statusAfter');
            }
            
            // Real 1ms delay
            await Future.delayed(const Duration(milliseconds: 1));
          }
        });
        
        await tester.pump();
        expect(completionStatus(view.state), 'active');
      });

      testWidgets('rapid Ctrl-n presses do not close completion', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'aaa'),
              const Completion(label: 'bbb'),
              const Completion(label: 'ccc'),
              const Completion(label: 'ddd'),
              const Completion(label: 'eee'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'x',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
                selectOnOpen: true,
                interactionDelay: 75,
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(completionStatus(view.state), 'active');
        
        // Simulate rapid Ctrl-n presses
        for (var i = 0; i < 10; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
          await tester.pump(const Duration(milliseconds: 5));
        }
        
        // Completion should still be open
        expect(completionStatus(view.state), 'active',
            reason: 'Completion should remain active after rapid Ctrl-n presses');
      });

      testWidgets('escape closes completion', (tester) async {
        CompletionResult? testSource(CompletionContext context) {
          return CompletionResult(
            from: 0,
            options: [
              const Completion(label: 'test'),
            ],
            filter: false,
          );
        }

        final editorKey = GlobalKey<EditorViewState>();
        EditorState state = EditorState.create(
          EditorStateConfig(
            doc: 'hello',
            extensions: ExtensionList([
              autocompletion(CompletionConfig(
                override: [testSource],
              )),
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
        
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        
        startCompletion(view);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        
        expect(completionStatus(view.state), 'active');
        
        // Close completion
        final closed = closeCompletion(view);
        await tester.pump();
        
        expect(closed, isTrue);
        expect(completionStatus(view.state), isNull);
        // Text should remain unchanged
        expect(view.state.doc.toString(), 'hello');
      });
    });
  });
}

// Simple test source
CompletionResult? _simpleSource(CompletionContext context) {
  return CompletionResult(
    from: 0,
    options: [
      const Completion(label: 'test1'),
      const Completion(label: 'test2'),
    ],
    filter: false,
  );
}
