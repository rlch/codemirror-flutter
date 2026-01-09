/// Integration test for diagnostics popover on hover in EditorView.
///
/// Tests that hovering over code with diagnostics (e.g., `color:`) correctly
/// displays the diagnostics popover aligned to the hover position.
///
/// NOTE: These tests are for the base EditorView widget, NOT for VirtualDocument.
/// VirtualDocument-specific tests are in test/lsp/virtual_document_hover_test.dart.
import 'package:codemirror/codemirror.dart' hide Text, lessThan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureLintInitialized();
  });

  group('Diagnostics hover popover', () {
    testWidgets('shows diagnostics popover when hovering over color: at start of code', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();

      // Code starting with color: so diagnostic is at position 0
      const code = 'color: "#6B7280";\nfontWeight: "bold";';

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
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

      // Add a diagnostic on "color:" at the start (position 0 to 6)
      view.dispatch([
        setDiagnostics(state, [
          const Diagnostic(
            from: 0,
            to: 6, // "color:" is 6 characters
            severity: Severity.error,
            message: 'Invalid color property: expected a valid color value',
            source: 'tsx-linter',
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

      // Find the diagnostic tooltip
      final tooltipFinder = find.byType(DiagnosticTooltip);
      expect(tooltipFinder, findsOneWidget, reason: 'Diagnostics popover should appear on hover');

      // Get tooltip position
      final tooltipBox = tester.getRect(tooltipFinder);

      // Verify tooltip positioning is reasonable (below the hover point)
      expect(tooltipBox.top, greaterThan(hoverPosition.dy),
          reason: 'Tooltip should be positioned below the cursor');

      // Tooltip should contain the error message
      expect(find.text('Invalid color property: expected a valid color value'), findsOneWidget);

      // Tooltip should be within screen bounds
      expect(tooltipBox.left, greaterThanOrEqualTo(0),
          reason: 'Tooltip should not overflow left edge');
      expect(tooltipBox.right, lessThanOrEqualTo(600),
          reason: 'Tooltip should not overflow right edge');

      // Key test: Verify tooltip X position is aligned near the diagnostic start
      final xDiff = (tooltipBox.left - hoverPosition.dx).abs();
      expect(xDiff, lessThan(80),
          reason: 'Tooltip left (${tooltipBox.left}) should be aligned near hover X (${hoverPosition.dx}). '
              'Actual difference: $xDiff. If this is large, there may be an alignment bug.');
    });

    testWidgets('shows diagnostics popover on first color: in TSX-like template content', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();

      // Full TSX-like content from the user's example
      const code = '''const [showAnswer, setShowAnswer] = useState(false);

  const handleReveal = () => {
    setShowAnswer(true);
  };

  return (
    <Card>
      <Column spacing={16}>
        {/* Front side - always visible */}
        <Column spacing={8}>
          <Text.h1 style={TextStyle({ color: Color('#6B7280'), fontWeight: 'bold' })}>
            QUESTION
          </Text.h1>
          <Text.h3>
            {front}
          </Text.h3>
        </Column>

        {/* Answer section */}
        {showAnswer ? (
          <Column spacing={8}>
            <Text.small style={TextStyle({ color: Color('#6B7280'), fontWeight: 'bold' })}>
              ANSWER
            </Text.small>
            <Text>
              {back}
            </Text>
          </Column>
        ) : (
          <Button onPress={handleReveal}>
            Reveal Answer
          </Button>
        )}
      </Column>
    </Card>
  );''';

      // Find position of first "color:" in the code
      final colorIndex = code.indexOf('color:');
      expect(colorIndex, greaterThan(0), reason: 'Code should contain "color:"');

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
          extensions: ExtensionList([
            linter(null),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 800, // Large enough to show all lines
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

      // Add a diagnostic on the first "color:" occurrence
      view.dispatch([
        setDiagnostics(state, [
          Diagnostic(
            from: colorIndex,
            to: colorIndex + 6,
            severity: Severity.error,
            message: 'Invalid color property',
            source: 'tsx-linter',
          ),
        ]),
      ]);
      await tester.pump();

      // Use coordsAtPos to get accurate position for the diagnostic
      final coords = view.coordsAtPos(colorIndex);
      expect(coords, isNotNull, reason: 'Should be able to get coords for color: position');

      // Hover over the diagnostic at its actual position
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: coords!);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(coords);
      await tester.pump(const Duration(milliseconds: 400));

      // Find the diagnostic tooltip
      final tooltipFinder = find.byType(DiagnosticTooltip);
      expect(tooltipFinder, findsOneWidget,
          reason: 'Diagnostics popover should appear when hovering over first color: in template');

      // Verify the tooltip content
      expect(find.text('Invalid color property'), findsOneWidget);

      // Verify tooltip is positioned correctly (not offset by gutter or other elements)
      final tooltipBox = tester.getRect(tooltipFinder);
      final xDiff = (tooltipBox.left - coords.dx).abs();

      // Tooltip should be within reasonable distance of the hover position.
      // Allow up to 150px difference for wide editors with long lines.
      expect(xDiff, lessThan(150),
          reason: 'Tooltip should be aligned with hover position. '
              'Tooltip left: ${tooltipBox.left}, Coords X: ${coords.dx}, '
              'Difference: $xDiff');
    });

    testWidgets('diagnostics popover shows correct alignment with line numbers gutter', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();

      const code = 'const x = { color: "#FF0000" };';
      final colorIndex = code.indexOf('color:');

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
          extensions: ExtensionList([
            lineNumbers(),
            linter(null),
            lintGutter(),
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

      // Add diagnostic on color:
      view.dispatch([
        setDiagnostics(state, [
          Diagnostic(
            from: colorIndex,
            to: colorIndex + 6,
            severity: Severity.warning,
            message: 'Consider using a CSS variable for colors',
          ),
        ]),
      ]);
      await tester.pump();

      // Get coordinates at the diagnostic position
      final coords = view.coordsAtPos(colorIndex);
      expect(coords, isNotNull);

      // Hover over the diagnostic
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);

      await gesture.addPointer(location: coords!);
      await tester.pump();
      await gesture.moveTo(coords + const Offset(5, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Tooltip should appear
      final tooltipFinder = find.byType(DiagnosticTooltip);
      expect(tooltipFinder, findsOneWidget);

      final tooltipBox = tester.getRect(tooltipFinder);
      final editorBox = tester.getRect(find.byType(EditorView));

      // Key test: tooltip should NOT be offset far to the right due to gutter
      // The tooltip should be near the actual text position, not shifted by gutter width
      final tooltipRelativeX = tooltipBox.left - editorBox.left;
      final coordsRelativeX = coords.dx - editorBox.left;

      // Tooltip left should be within reasonable distance of hover position
      // (accounting for text alignment, but NOT a 100px gutter offset)
      final xDiff = tooltipRelativeX - coordsRelativeX;
      expect(xDiff.abs(), lessThan(80),
          reason: 'Tooltip should be aligned with hover position. '
              'Tooltip relative X: $tooltipRelativeX, Coords relative X: $coordsRelativeX, '
              'Difference: $xDiff. If this is ~100px, there\'s a gutter offset bug.');
    });

    testWidgets('diagnostics popover hides when mouse moves away', (tester) async {
      final editorKey = GlobalKey<EditorViewState>();

      const code = 'const style = { color: "red" };';
      final colorIndex = code.indexOf('color:');

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
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

      view.dispatch([
        setDiagnostics(state, [
          Diagnostic(
            from: colorIndex,
            to: colorIndex + 6,
            severity: Severity.error,
            message: 'Test error',
          ),
        ]),
      ]);
      await tester.pump();

      final coords = view.coordsAtPos(colorIndex + 3);
      expect(coords, isNotNull);

      // Hover to show tooltip
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);

      await gesture.addPointer(location: coords!);
      await tester.pump();
      await gesture.moveTo(coords + const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DiagnosticTooltip), findsOneWidget);

      // Move mouse away from the editor
      await gesture.moveTo(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tooltip should hide
      expect(find.byType(DiagnosticTooltip), findsNothing);
    });
  });
}
