/// Test for hover tooltip Y positioning bug.
///
/// Bug: When hovering over text on a line far into the document with JSX-like
/// content (e.g., ButtonStyle.secondary on line 16), the hover tooltip appears
/// at a completely wrong Y position (about 10-15 lines upward from the actual
/// hover location).
///
/// This test verifies that the tooltip Y position is correctly anchored near
/// the hovered line, not offset by a large amount.
///
/// The bug reproduces specifically with:
/// - JSX-like content with nested brackets and tags
/// - Hovering over text on lines 15+
/// 
/// The bug does NOT reproduce with:
/// - Simple single-line variable declarations
/// - Text near the top of the document
import 'package:codemirror/codemirror.dart' hide Text, lessThan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    ensureStateInitialized();
  });

  group('Hover tooltip Y position', () {
    testWidgets(
        'tooltip Y is near hovered line for ButtonStyle.secondary on line 20+',
        (tester) async {
      // Simplified template content that fits in default 800x600 viewport
      // ButtonStyle.secondary should be on approximately line 18
      const code = '''const [showAnswer, setShowAnswer] = useState(false);

return (
  <Padding>
    <Column>
      <Expanded>
        <Center>
          <Column>
            <Text.h2>{question}</Text.h2>
          </Column>
        </Center>
      </Expanded>
      <SizedBox height={24} />
      <Row mainAxisAlignment="spaceEvenly">
        <Button style={ButtonStyle.destructive()}>Again</Button>
        <Button style={ButtonStyle.secondary()}>Good</Button>
        <Button style={ButtonStyle.primary()}>Easy</Button>
      </Row>
    </Column>
  </Padding>
);''';

      // Find "ButtonStyle.secondary" - specifically the 'd' at the end of 'secondary'
      final secondaryIndex = code.indexOf('ButtonStyle.secondary');
      expect(secondaryIndex, greaterThan(0),
          reason: 'Code should contain ButtonStyle.secondary');

      // Position of the 'd' at the end of 'secondary'
      final dPosition = secondaryIndex + 'ButtonStyle.secondary'.length - 1;

      // Find what line number this is on
      final linesBeforeSecondary = code.substring(0, secondaryIndex).split('\n');
      final lineNumber = linesBeforeSecondary.length;
      // ignore: avoid_print
      print('ButtonStyle.secondary is on line $lineNumber');
      // ignore: avoid_print
      print('Position of "d" in secondary: $dPosition');

      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (_) => TooltipView(
            widget: Container(
              key: const Key('hover-tooltip'),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ButtonStyle.secondary: Creates a secondary button style',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      }

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
          ]),
        ),
      );

      final editorKey = GlobalKey<EditorViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
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

      final viewState = editorKey.currentState!;
      final lineHeight = viewState.lineHeight;

      // Get coordinates for the 'd' in 'secondary'
      final coordsAtD = viewState.coordsAtPos(dPosition);
      expect(coordsAtD, isNotNull,
          reason: 'Should get coords for position $dPosition');

      // Verify the coordinates are within the visible viewport
      final editorBox = tester.getRect(find.byType(EditorView));
      // ignore: avoid_print
      print('Editor box: $editorBox');
      // ignore: avoid_print
      print('Coords at "d" in secondary: $coordsAtD');
      // ignore: avoid_print
      print('Line height: $lineHeight');

      expect(coordsAtD!.dy, greaterThanOrEqualTo(editorBox.top),
          reason: 'Target should be within viewport (not above)');
      expect(coordsAtD.dy, lessThan(editorBox.bottom),
          reason: 'Target should be within viewport (not below)');

      // DEBUG: Let's trace the coordinate calculation
      // The hover source returns pos = hoverPos (the position in the document)
      // Then coordsAtPos(pos) is called to get the anchor coordinates
      // Let's verify what position is being used
      
      // Get the actual anchor position that would be used
      final anchorPos = dPosition; // This is what the hover source returns as tooltip.pos
      final anchorCoords = viewState.coordsAtPos(anchorPos);
      
      // ignore: avoid_print
      print('=== DEBUG: Coordinate calculation ===');
      // ignore: avoid_print
      print('Document position (anchorPos): $anchorPos');
      // ignore: avoid_print
      print('coordsAtPos($anchorPos) = $anchorCoords');
      // ignore: avoid_print
      print('Expected Y based on line $lineNumber: ${(lineNumber - 1) * lineHeight}');
      
      // Check what the overlay offset would be
      final overlay = Overlay.of(viewState.context);
      final overlayRenderBox = overlay.context.findRenderObject() as RenderBox?;
      final overlayOffset = overlayRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
      // ignore: avoid_print
      print('Overlay offset: $overlayOffset');
      // ignore: avoid_print
      print('Anchor after overlay adjustment: ${anchorCoords! - overlayOffset}');
      
      // The positioning formula is:
      // top = anchor.dy + lineHeight + anchorGap (4.0)
      // So expected top = (328 - overlayOffset.dy) + 20 + 4 = ?
      final expectedTop = (anchorCoords.dy - overlayOffset.dy) + lineHeight + 4.0;
      // ignore: avoid_print
      print('Expected tooltip top (anchor.dy + lineHeight + gap): $expectedTop');
      
      // Hover at the 'd' position
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
          location: Offset(coordsAtD.dx, coordsAtD.dy + lineHeight / 2));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
          Offset(coordsAtD.dx + 2, coordsAtD.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Tooltip should appear
      final tooltipFinder = find.byKey(const Key('hover-tooltip'));
      expect(tooltipFinder, findsOneWidget,
          reason: 'Hover tooltip should appear');

      // Get tooltip position
      final tooltipBox = tester.getRect(tooltipFinder);
      
      // Also check the parent ConstrainedBox
      final constrainedBoxFinder = find.ancestor(
        of: tooltipFinder,
        matching: find.byType(ConstrainedBox),
      );
      if (constrainedBoxFinder.evaluate().isNotEmpty) {
        final constrainedBox = tester.getRect(constrainedBoxFinder.first);
        // ignore: avoid_print
        print('ConstrainedBox rect: $constrainedBox');
        // ignore: avoid_print
        print('ConstrainedBox height: ${constrainedBox.height}');
      }
      
      // Also check the Positioned widget
      final positionedFinder = find.ancestor(
        of: tooltipFinder,
        matching: find.byType(Positioned),
      );
      if (positionedFinder.evaluate().isNotEmpty) {
        final positioned = tester.widget<Positioned>(positionedFinder.first);
        // ignore: avoid_print
        print('Positioned top: ${positioned.top}, left: ${positioned.left}');
      }

      // ignore: avoid_print
      print('Hover position Y: ${coordsAtD.dy}');
      // ignore: avoid_print
      print('Tooltip box: $tooltipBox');
      // ignore: avoid_print  
      print('Tooltip actual height: ${tooltipBox.height}');
      // ignore: avoid_print
      print('Tooltip actual width: ${tooltipBox.width}');
      
      // ANALYSIS: The positioning logic uses maxHeight=300 for calculations,
      // but the actual tooltip might be much smaller. This causes premature
      // flip-above behavior when the tooltip would actually fit below.

      // BUG CHECK: The tooltip should be BELOW the hovered line (not 10 lines above)
      // Expected: tooltip.top >= coordsAtD.dy (tooltip appears below the text)
      // Bug symptom: tooltip.top is way above coordsAtD.dy

      // The tooltip top should be close to the hover Y position + lineHeight
      // Allow for the tooltip to appear either above or below, but should be
      // within ~3 line heights of the actual position (below) or ~6 above
      // (since tooltip might flip above when near bottom of viewport)
      final yDifference = (tooltipBox.top - coordsAtD.dy).abs();
      
      // If tooltip is above the hover position, allow for tooltip height + spacing
      // If below, should be within ~2 line heights
      double maxAllowedDifference;
      if (tooltipBox.top < coordsAtD.dy) {
        // Tooltip is above - allow for tooltip height (estimate 100px) + some spacing
        maxAllowedDifference = 150.0;
      } else {
        // Tooltip is below - should be very close (within 2-3 line heights)
        maxAllowedDifference = lineHeight * 3;
      }

      // ignore: avoid_print
      print('Y difference: $yDifference');
      // ignore: avoid_print
      print('Max allowed difference: $maxAllowedDifference');

      expect(
        yDifference,
        lessThan(maxAllowedDifference),
        reason: 'Tooltip Y (${tooltipBox.top}) should be within '
            '$maxAllowedDifference pixels of hover Y (${coordsAtD.dy}), '
            'but difference is $yDifference. '
            'If this is ~10 line heights off, there is a Y positioning bug.',
      );

      // Also verify the tooltip is reasonably positioned (below the hovered text,
      // OR above if there's not enough room below)
      final expectedMinY = coordsAtD.dy - maxAllowedDifference;
      final expectedMaxY = coordsAtD.dy + lineHeight + maxAllowedDifference;

      expect(
        tooltipBox.top,
        greaterThan(expectedMinY),
        reason: 'Tooltip should not be way above the hovered line',
      );
      expect(
        tooltipBox.top,
        lessThan(expectedMaxY),
        reason: 'Tooltip should not be way below the hovered line',
      );
    });

    testWidgets(
        'tooltip Y is correct after scrolling down',
        (tester) async {
      // Generate content with 60 lines, target on line 35
      // At 20px line height, line 35 is at doc Y = 34 * 20 = 680px
      // Viewport is 600px, so after scrolling 200px, lines 10-40 are visible
      // Line 35 should appear at screen Y = 680 - 200 = 480px (visible)
      final lines = List.generate(60, (i) => 'const line$i = $i;');
      lines[34] = 'const target = ButtonStyle.secondary({ radius: 8 });';
      final code = lines.join('\n');

      final targetIndex = code.indexOf('ButtonStyle.secondary');
      expect(targetIndex, greaterThan(0));

      final hoverPos = targetIndex + 'ButtonStyle.sec'.length;

      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (_) => TooltipView(
            widget: Container(
              key: const Key('scroll-tooltip'),
              width: 200,
              height: 40,
              color: Colors.blue,
              child: const Text('Tooltip after scroll'),
            ),
          ),
        );
      }

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
          ]),
        ),
      );

      final editorKey = GlobalKey<EditorViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
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

      final viewState = editorKey.currentState!;
      final lineHeight = viewState.lineHeight;
      final editorBox = tester.getRect(find.byType(EditorView));

      // Scroll down 200px to bring line 35 into middle of viewport
      const scrollPixels = 200.0;
      await tester.drag(find.byType(EditorView), const Offset(0, -scrollPixels));
      await tester.pumpAndSettle();

      // Get coordinates for the target position (after scrolling)
      final coords = viewState.coordsAtPos(hoverPos);
      expect(coords, isNotNull,
          reason: 'Should get coords for position after scroll');

      // ignore: avoid_print
      print('=== SCROLL TEST DEBUG ===');
      // ignore: avoid_print
      print('Scroll pixels: $scrollPixels');
      // ignore: avoid_print
      print('Editor box: $editorBox');
      // ignore: avoid_print
      print('Line height: $lineHeight');
      // ignore: avoid_print
      print('Target line: 35, doc Y: ${34 * lineHeight}');
      // ignore: avoid_print
      print('Expected screen Y after scroll: ${34 * lineHeight - scrollPixels}');
      // ignore: avoid_print
      print('Actual coordsAtPos($hoverPos): $coords');

      // Verify coords are usable (within or near viewport)
      // The BUG causes coords.dy to be incorrect after scrolling
      // If coords are way off, hovering won't work correctly
      final expectedScreenY = 34 * lineHeight - scrollPixels;
      final coordsDiff = (coords!.dy - expectedScreenY).abs();
      // ignore: avoid_print
      print('Expected screen Y: $expectedScreenY, actual: ${coords.dy}, diff: $coordsDiff');

      // Use the coords we got (even if buggy) to hover
      // The tooltip should appear near where we hover
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
          location: Offset(coords.dx, coords.dy + lineHeight / 2));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
          Offset(coords.dx + 2, coords.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final tooltipFinder = find.byKey(const Key('scroll-tooltip'));
      expect(tooltipFinder, findsOneWidget,
          reason: 'Hover tooltip should appear after scrolling');

      final tooltipBox = tester.getRect(tooltipFinder);

      // ignore: avoid_print
      print('Hover Y (from coords): ${coords.dy}');
      // ignore: avoid_print
      print('Tooltip box: $tooltipBox');

      // KEY ASSERTION: The tooltip Y should be near the hover Y
      // If there's a scroll offset bug, the tooltip will appear at wrong position
      final yDifference = (tooltipBox.top - coords.dy).abs();
      final maxAllowedDifference = lineHeight * 5; // 100px tolerance

      // ignore: avoid_print
      print('Y difference (tooltip.top vs coords.dy): $yDifference');
      // ignore: avoid_print
      print('Max allowed: $maxAllowedDifference');

      // Also log the coordsAtPos bug separately
      // ignore: avoid_print
      print('=== COORDS BUG CHECK ===');
      // ignore: avoid_print
      print('coordsAtPos diff from expected: $coordsDiff');
      if (coordsDiff > lineHeight * 2) {
        // ignore: avoid_print
        print('WARNING: coordsAtPos appears to have scroll offset bug!');
      }

      expect(
        yDifference,
        lessThan(maxAllowedDifference),
        reason: 'BUG: Tooltip Y (${tooltipBox.top}) is far from hover Y (${coords.dy}). '
            'Difference: $yDifference pixels. '
            'This suggests scroll offset is not being handled correctly in tooltip positioning.',
      );

      // Additional check: tooltip should be within viewport
      expect(
        tooltipBox.top,
        greaterThanOrEqualTo(editorBox.top - 10),
        reason: 'Tooltip should be within or near viewport top',
      );
      expect(
        tooltipBox.bottom,
        lessThanOrEqualTo(editorBox.bottom + 10),
        reason: 'Tooltip should be within or near viewport bottom',
      );
    });

    testWidgets(
        'tooltip Y is correct for text on line 15 in content',
        (tester) async {
      // Generate content with 20 lines - line 15 should be visible in 600px viewport
      final lines = List.generate(20, (i) => 'const line$i = $i;');
      // Insert our target on line 15
      lines[14] = 'const target = ButtonStyle.secondary({ radius: 8 });';
      final code = lines.join('\n');

      final targetIndex = code.indexOf('ButtonStyle.secondary');
      expect(targetIndex, greaterThan(0));

      // Position in the middle of 'secondary'
      final hoverPos = targetIndex + 'ButtonStyle.sec'.length;

      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (_) => TooltipView(
            widget: Container(
              key: const Key('line15-tooltip'),
              width: 200,
              height: 40,
              color: Colors.blue,
              child: const Text('Tooltip'),
            ),
          ),
        );
      }

      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: code,
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
          ]),
        ),
      );

      final editorKey = GlobalKey<EditorViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
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

      final viewState = editorKey.currentState!;
      final lineHeight = viewState.lineHeight;

      // Get coordinates for the target
      final coords = viewState.coordsAtPos(hoverPos);
      expect(coords, isNotNull,
          reason: 'Should get coords for line 15 position');

      // Verify the coords are within the visible viewport
      final editorBox = tester.getRect(find.byType(EditorView));
      // ignore: avoid_print
      print('Editor box: $editorBox');
      // ignore: avoid_print
      print('Coords at hover pos: $coords');
      
      expect(coords!.dy, greaterThanOrEqualTo(editorBox.top),
          reason: 'Line 15 should be within viewport (not above)');
      expect(coords.dy, lessThan(editorBox.bottom),
          reason: 'Line 15 should be within viewport (not below)');

      // Hover at the position
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
          location: Offset(coords.dx, coords.dy + lineHeight / 2));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
          Offset(coords.dx + 2, coords.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final tooltipFinder = find.byKey(const Key('line15-tooltip'));
      expect(tooltipFinder, findsOneWidget);

      final tooltipBox = tester.getRect(tooltipFinder);

      // ignore: avoid_print
      print('Hover Y: ${coords.dy}, tooltip top: ${tooltipBox.top}');

      // The tooltip should be near the hover position
      final yDifference = (tooltipBox.top - coords.dy).abs();
      final maxAllowedDifference = lineHeight * 5;

      expect(
        yDifference,
        lessThan(maxAllowedDifference),
        reason: 'Tooltip Y (${tooltipBox.top}) should be within '
            '$maxAllowedDifference pixels of hover Y (${coords.dy}), '
            'but difference is $yDifference. '
            'This could indicate a Y positioning bug.',
      );
    });
  });
}
