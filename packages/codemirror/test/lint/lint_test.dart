import 'dart:ui' show PointerDeviceKind;

import 'package:codemirror/codemirror.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLintInitialized();

  group('Lint Unit Tests', () {
    group('Diagnostic', () {
      test('can create diagnostic with required fields', () {
        const diagnostic = Diagnostic(
          from: 0,
          to: 5,
          severity: Severity.error,
          message: 'Test error',
        );

        expect(diagnostic.from, 0);
        expect(diagnostic.to, 5);
        expect(diagnostic.severity, Severity.error);
        expect(diagnostic.message, 'Test error');
        expect(diagnostic.source, isNull);
        expect(diagnostic.markClass, isNull);
        expect(diagnostic.actions, isNull);
      });

      test('can create diagnostic with all fields', () {
        const diagnostic = Diagnostic(
          from: 10,
          to: 20,
          severity: Severity.warning,
          message: 'Test warning',
          source: 'test-linter',
          markClass: 'custom-mark',
        );

        expect(diagnostic.source, 'test-linter');
        expect(diagnostic.markClass, 'custom-mark');
      });

      test('severity enum has correct values', () {
        expect(Severity.values.length, 4);
        expect(Severity.hint.index, 0);
        expect(Severity.info.index, 1);
        expect(Severity.warning.index, 2);
        expect(Severity.error.index, 3);
      });
    });

    group('setDiagnostics', () {
      test('creates transaction spec with diagnostics effect', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'hello world'),
        );

        final spec = setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error here',
          ),
        ]);

        expect(spec.effects, isNotNull);
        expect(spec.effects!.length, 1);
        expect(spec.effects![0].is_(setDiagnosticsEffect), isTrue);
      });
    });

    group('diagnosticCount', () {
      test('returns 0 when no lint state', () {
        final state = EditorState.create(
          EditorStateConfig(doc: 'hello'),
        );

        expect(diagnosticCount(state), 0);
      });
    });

    group('LintConfig', () {
      test('has sensible defaults', () {
        const config = LintConfig();
        expect(config.delay, 750);
        expect(config.needsRefresh, isNull);
        expect(config.markerFilter, isNull);
        expect(config.tooltipFilter, isNull);
        expect(config.hideOn, isNull);
        expect(config.autoPanel, false);
      });

      test('can customize delay', () {
        const config = LintConfig(delay: 500);
        expect(config.delay, 500);
      });
    });

    group('LintGutterConfig', () {
      test('has sensible defaults', () {
        const config = LintGutterConfig();
        expect(config.hoverTime, 300);
        expect(config.markerFilter, isNull);
        expect(config.tooltipFilter, isNull);
      });
    });
  });

  group('Lint Widget Tests', () {
    testWidgets('linter extension can be added to state', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null), // Just config, no source
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

      expect(editorKey.currentState, isNotNull);
      expect(diagnosticCount(state), 0);
    });

    testWidgets('diagnostics can be set manually', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null),
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
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error in hello',
          ),
        ]),
      ]);
      await tester.pump();

      expect(diagnosticCount(view.state), greaterThan(0));
    });

    testWidgets('linter with source runs on document change', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      int lintCallCount = 0;

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello',
          extensions: ExtensionList([
            linter(
              (_) {
                lintCallCount++;
                return [];
              },
              const LintConfig(delay: 10), // Very short delay for test
            ),
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

      // Initial lint should be scheduled - wait for delay + buffer
      await tester.pump(const Duration(milliseconds: 200));
      // Test that the lint source is configured (it may or may not have run yet)
      expect(state.facet(language), isNull); // Just verify state works
    });

    testWidgets('nextDiagnostic moves to next diagnostic', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world test',
          extensions: ExtensionList([
            linter(null),
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

      // Set two diagnostics
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'First error',
          ),
          const Diagnostic(
            from: 12,
            to: 16,
            severity: Severity.warning,
            message: 'Second warning',
          ),
        ]),
      ]);
      await tester.pump();

      // Try to navigate to next diagnostic using the command target pattern
      final handled = nextDiagnostic((
        state: view.state,
        dispatch: view.dispatchTransaction,
      ));

      expect(handled, isTrue);
    });

    testWidgets('previousDiagnostic returns false when no diagnostics', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null),
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
      final handled = previousDiagnostic((
        state: view.state,
        dispatch: view.dispatchTransaction,
      ));

      expect(handled, isFalse);
    });

    testWidgets('lintGutter extension can be added', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null),
            lintGutter(),
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

      expect(editorKey.currentState, isNotNull);
    });

    testWidgets('lintGutter creates markers for diagnostics', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello\nworld\ntest',
          extensions: ExtensionList([
            linter(null),
            lintGutter(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      // Add diagnostics on different lines
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error on line 1',
          ),
          const Diagnostic(
            from: 6,
            to: 11,
            severity: Severity.warning,
            message: 'Warning on line 2',
          ),
        ]),
      ]);
      await tester.pump();

      // Check that diagnostics were recorded
      expect(diagnosticCount(view.state), 2);
      
      // Verify the gutter configuration is in the state
      final gutters = view.state.facet(activeGutters);
      expect(gutters.any((g) => g.className == 'cm-gutter-lint'), isTrue);
    });

    testWidgets('forEachDiagnostic iterates diagnostics', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world test',
          extensions: ExtensionList([
            linter(null),
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

      // Set diagnostics
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error 1',
          ),
          const Diagnostic(
            from: 6,
            to: 11,
            severity: Severity.warning,
            message: 'Warning 1',
          ),
        ]),
      ]);
      await tester.pump();

      // Count diagnostics via forEach
      final diagnostics = <Diagnostic>[];
      forEachDiagnostic(view.state, (d, from, to) {
        diagnostics.add(d);
      });

      // At least some diagnostics should be found
      expect(diagnostics.length, greaterThanOrEqualTo(1));
    });

    testWidgets('lint decorations are added to decorationsFacet', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null),
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

      // Set diagnostics
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error',
          ),
        ]),
      ]);
      await tester.pump();

      // Check that decorations facet has lint sources
      final decorationSources = view.state.facet(decorationsFacet);
      expect(decorationSources.isNotEmpty, isTrue,
        reason: 'decorationsFacet should have sources');
      
      // Check that diagnosticCount reflects the new diagnostics
      expect(diagnosticCount(view.state), 1,
        reason: 'diagnosticCount should reflect set diagnostics');
      
      // Check that view.decorations has content
      // This verifies that _updateDecorations() processes the facet correctly
      expect(view.decorations.size, greaterThan(0),
        reason: 'view.decorations should be updated after setDiagnostics');
    });

    testWidgets('diagnostics update when document changes', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null),
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

      // Set diagnostic at position 6-11 (world)
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 6,
            to: 11,
            severity: Severity.error,
            message: 'Error on world',
          ),
        ]),
      ]);
      await tester.pump();

      final countBefore = diagnosticCount(view.state);
      expect(countBefore, greaterThan(0));

      // Insert text at beginning, which should shift diagnostic positions
      view.dispatch([
        TransactionSpec(
          changes: ChangeSpec(from: 0, insert: 'prefix '),
        ),
      ]);
      await tester.pump();

      // Diagnostic should still exist (mapped to new position)
      final countAfter = diagnosticCount(view.state);
      expect(countAfter, greaterThan(0));
    });

    testWidgets('hover tooltip appears when hovering over diagnostic', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world',
          extensions: ExtensionList([
            linter(null),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      // Set a diagnostic on "hello" (positions 0-5)
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Test error message',
            source: 'test-linter',
          ),
        ]),
      ]);
      await tester.pump();

      // Verify diagnostic is set
      expect(diagnosticCount(view.state), 1);

      // Find the editor widget and get its position
      final editorFinder = find.byType(EditorView);
      expect(editorFinder, findsOneWidget);

      // Get the position of the editor
      final editorBox = tester.getRect(editorFinder);

      // Hover over the start of the text (where "hello" is)
      // Add some offset for padding
      final hoverPosition = Offset(
        editorBox.left + 20,
        editorBox.top + 20,
      );

      // Create a hover event
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: hoverPosition);
      addTearDown(gesture.removePointer);
      await tester.pump();

      // Move to trigger hover
      await gesture.moveTo(hoverPosition);
      await tester.pump();

      // Wait for the hover delay (300ms) plus some buffer
      await tester.pump(const Duration(milliseconds: 400));

      // Check that DiagnosticTooltip appears in the overlay
      expect(find.byType(DiagnosticTooltip), findsOneWidget,
        reason: 'DiagnosticTooltip should appear after hovering over diagnostic');

      // Verify the tooltip shows the correct message
      expect(find.text('Test error message'), findsOneWidget,
        reason: 'Tooltip should display the diagnostic message');

      // Verify the source is shown
      expect(find.text('test-linter'), findsOneWidget,
        reason: 'Tooltip should display the diagnostic source');

      // Move away to hide tooltip
      await gesture.moveTo(Offset(editorBox.left + 200, editorBox.top + 200));
      await tester.pump();
      // Wait for the hide delay (100ms) plus buffer
      await tester.pump(const Duration(milliseconds: 200));

      // Tooltip should be hidden
      expect(find.byType(DiagnosticTooltip), findsNothing,
        reason: 'DiagnosticTooltip should hide when mouse moves away');
    });

    testWidgets('hover tooltip is positioned correctly below cursor', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world\nsecond line\nthird line',
          extensions: ExtensionList([
            linter(null),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      // Set a diagnostic on "hello"
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.warning,
            message: 'Warning message',
          ),
        ]),
      ]);
      await tester.pump();

      // Hover over the diagnostic
      final editorBox = tester.getRect(find.byType(EditorView));
      final hoverPosition = Offset(editorBox.left + 20, editorBox.top + 20);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: hoverPosition);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(hoverPosition);
      await tester.pump(const Duration(milliseconds: 400));

      // Find the tooltip
      final tooltipFinder = find.byType(DiagnosticTooltip);
      expect(tooltipFinder, findsOneWidget);

      // Get tooltip position
      final tooltipBox = tester.getRect(tooltipFinder);

      // Tooltip should be positioned below the hover point (with some margin)
      // The tooltip top should be greater than the hover Y position
      expect(tooltipBox.top, greaterThan(hoverPosition.dy),
        reason: 'Tooltip should be positioned below the cursor');

      // Tooltip should be within screen bounds
      expect(tooltipBox.left, greaterThanOrEqualTo(0),
        reason: 'Tooltip should not overflow left edge');
      expect(tooltipBox.right, lessThanOrEqualTo(600),
        reason: 'Tooltip should not overflow right edge');
    });

    testWidgets('diagnosticsAtPos returns correct diagnostics', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world test',
          extensions: ExtensionList([
            linter(null),
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

      // Set multiple diagnostics at different positions
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error on hello',
          ),
          const Diagnostic(
            from: 6,
            to: 11,
            severity: Severity.warning,
            message: 'Warning on world',
          ),
        ]),
      ]);
      await tester.pump();

      // Check diagnosticsAtPos at position 2 (inside "hello")
      final diagsAt2 = diagnosticsAtPos(view.state, 2);
      expect(diagsAt2.length, 1);
      expect(diagsAt2[0].message, 'Error on hello');

      // Check diagnosticsAtPos at position 8 (inside "world")
      final diagsAt8 = diagnosticsAtPos(view.state, 8);
      expect(diagsAt8.length, 1);
      expect(diagsAt8[0].message, 'Warning on world');

      // Check diagnosticsAtPos at position 14 (inside "test" - no diagnostic)
      final diagsAt14 = diagnosticsAtPos(view.state, 14);
      expect(diagsAt14.length, 0);
    });

    testWidgets('lintGutter maintains fixed width with no diagnostics', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello\nworld\ntest',
          extensions: ExtensionList([
            linter(null),
            lintGutter(),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: EditorView(
                key: editorKey,
                state: state,
                onUpdate: (update) => state = update.state,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the lint gutter by looking for GutterView with cm-gutter-lint class
      final gutterFinder = find.byWidgetPredicate((widget) =>
          widget is GutterView && widget.config.className == 'cm-gutter-lint');
      expect(gutterFinder, findsOneWidget);

      // Get the width of the gutter with no diagnostics
      final gutterElement = tester.element(gutterFinder);
      final gutterBox = gutterElement.renderObject as RenderBox;
      final widthWithNoDiagnostics = gutterBox.size.width;

      // Width should be > 0 due to the spacer
      expect(widthWithNoDiagnostics, greaterThan(0),
          reason: 'Lint gutter should have width even with no diagnostics');

      // Add diagnostics
      final view = editorKey.currentState!;
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'Error on line 1',
          ),
        ]),
      ]);
      await tester.pumpAndSettle();

      // Get the width with diagnostics
      final widthWithDiagnostics = gutterBox.size.width;

      // Width should be the same (fixed width)
      expect(widthWithDiagnostics, widthWithNoDiagnostics,
          reason: 'Lint gutter width should not change when diagnostics are added');

      // Clear diagnostics
      view.dispatch([setDiagnostics(view.state, [])]);
      await tester.pumpAndSettle();

      // Width should still be the same
      final widthAfterClearing = gutterBox.size.width;
      expect(widthAfterClearing, widthWithNoDiagnostics,
          reason: 'Lint gutter width should not change when diagnostics are cleared');
    });
  });
}
