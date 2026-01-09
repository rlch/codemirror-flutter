/// Test that tooltip positioning correctly accounts for gutters.
///
/// This test verifies that when an editor has gutters (line numbers, etc.),
/// the tooltip X position is computed correctly relative to the text content,
/// not offset by the gutter width.
import 'package:codemirror/codemirror.dart' hide Text, lessThan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tooltip positioning with gutters', () {
    testWidgets('tooltip X position accounts for gutter width', (tester) async {
      ensureStateInitialized();

      // Track the anchor position computed by the tooltip
      Offset? computedAnchor;

      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('gutter-test-tooltip'),
              width: 150,
              height: 50,
              color: Colors.blue,
              child: Text('POS: $pos'),
            ),
          ),
        );
      }

      // Add multiple gutters like the real app uses
      ensureLintInitialized();
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World\nLine Two\nLine Three',
          extensions: ExtensionList([
            // Add line numbers gutter
            lineNumbers(),
            // Add lint gutter (for diagnostics)
            linter(null),
            // Add hover tooltip
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(state: state),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Get the EditorViewState to access coordsAtPos
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));

      // Get the computed coords for position 0 (start of "Hello")
      final coordsAt0 = viewState.coordsAtPos(0);
      expect(coordsAt0, isNotNull, reason: 'coordsAtPos(0) should return valid coords');

      // The coordinates should be in the text area, not at the very left of the editor
      // With gutters, the text content starts after the gutter width
      final editorBox = tester.getRect(find.byType(EditorView));

      // Position 0 should NOT be at the left edge of the editor (that's where the gutter is)
      // It should be offset by gutter width + padding
      print('Editor left: ${editorBox.left}');
      print('coordsAt0: $coordsAt0');

      // Now hover over position 5 ("o" in "Hello")
      final coordsAt5 = viewState.coordsAtPos(5);
      expect(coordsAt5, isNotNull, reason: 'coordsAtPos(5) should return valid coords');

      print('coordsAt5: $coordsAt5');

      // Hover at the computed position
      final hoverX = coordsAt5!.dx;
      final hoverY = coordsAt5.dy + viewState.lineHeight / 2;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(hoverX, hoverY));
      await tester.pump();
      await gesture.moveTo(Offset(hoverX + 2, hoverY));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Tooltip should appear
      final tooltipFinder = find.byKey(const Key('gutter-test-tooltip'));
      expect(tooltipFinder, findsOneWidget, reason: 'Tooltip should appear');

      final tooltipBox = tester.getRect(tooltipFinder);

      print('Tooltip box: $tooltipBox');
      print('Hover position: ($hoverX, $hoverY)');
      print('Expected anchor X: $hoverX');
      print('Actual tooltip left: ${tooltipBox.left}');

      // Key assertion: tooltip left should be close to the hover X position
      // If there's a ~100px offset bug, the tooltip.left would be much higher than hoverX
      final xDifference = (tooltipBox.left - hoverX).abs();
      expect(
        xDifference,
        lessThan(50), // Tooltip should be within 50px of hover position
        reason:
            'Tooltip X (${tooltipBox.left}) should be near hover X ($hoverX). '
            'Difference: $xDifference. '
            'This may indicate the gutter width is being double-counted.',
      );

      await gesture.removePointer();
      await tester.pumpAndSettle();
    });

    testWidgets('hover position detection is accurate with gutters', (tester) async {
      ensureStateInitialized();

      int? detectedPos;

      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        detectedPos = pos;
        return createTextTooltip(pos: pos, content: 'Position: $pos');
      }

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'ABCDEFGHIJ', // 10 chars on line 1
          extensions: ExtensionList([
            lineNumbers(),
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(state: state),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final viewState = tester.state<EditorViewState>(find.byType(EditorView));

      // Get coords for position 5 (letter 'F')
      final coordsAt5 = viewState.coordsAtPos(5);
      expect(coordsAt5, isNotNull);

      // Hover exactly at position 5
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
          location: Offset(coordsAt5!.dx, coordsAt5.dy + viewState.lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(
          Offset(coordsAt5.dx + 2, coordsAt5.dy + viewState.lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // The detected position should be around 5 (could be 4-6 depending on exact hit)
      expect(detectedPos, isNotNull);
      expect(detectedPos, inInclusiveRange(4, 6),
          reason:
              'Hovering at coordsAtPos(5) should detect position 4-6, got $detectedPos');

      await gesture.removePointer();
      await tester.pumpAndSettle();
    });

    testWidgets('coordsAtPos returns correct global coords with gutters', (tester) async {
      ensureStateInitialized();

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello',
          extensions: ExtensionList([
            lineNumbers(),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(state: state),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      final editorBox = tester.getRect(find.byType(EditorView));

      // Get coords for position 0
      final coordsAt0 = viewState.coordsAtPos(0);
      expect(coordsAt0, isNotNull);

      print('Editor box: $editorBox');
      print('coordsAt0: $coordsAt0');

      // The X coordinate for position 0 should be:
      // - Greater than editor left (because of gutter)
      // - But less than middle of editor (text starts in left portion)
      expect(coordsAt0!.dx, greaterThan(editorBox.left),
          reason: 'Position 0 should be after gutter');
      expect(coordsAt0.dx, lessThan(editorBox.left + 200),
          reason: 'Position 0 should be in the left portion of editor (gutter width ~50-100px)');

      // The Y coordinate should be within the editor's vertical bounds
      expect(coordsAt0.dy, greaterThanOrEqualTo(editorBox.top));
      expect(coordsAt0.dy, lessThan(editorBox.bottom));
    });

    testWidgets('tooltip alignment matches anchor position from coordsAtPos',
        (tester) async {
      ensureStateInitialized();

      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('alignment-test-tooltip'),
              width: 100,
              height: 40,
              color: Colors.green,
              child: const Text('TEST'),
            ),
          ),
        );
      }

      final state = EditorState.create(
        EditorStateConfig(
          doc: 'const x = 42;',
          extensions: ExtensionList([
            lineNumbers(),
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(state: state),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final viewState = tester.state<EditorViewState>(find.byType(EditorView));

      // Hover at position 6 (the 'x')
      final coordsAt6 = viewState.coordsAtPos(6);
      expect(coordsAt6, isNotNull);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(
          location: Offset(coordsAt6!.dx, coordsAt6.dy + viewState.lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(
          Offset(coordsAt6.dx + 2, coordsAt6.dy + viewState.lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final tooltipFinder = find.byKey(const Key('alignment-test-tooltip'));
      expect(tooltipFinder, findsOneWidget);

      final tooltipBox = tester.getRect(tooltipFinder);

      // The tooltip's left edge should align with (or be near) the anchor X
      // It uses left alignment (Alignment.bottomLeft -> Alignment.topLeft)
      print('Anchor X (coordsAt6.dx): ${coordsAt6.dx}');
      print('Tooltip left: ${tooltipBox.left}');

      // The tooltip should be positioned with its LEFT edge near the anchor X
      expect(
        (tooltipBox.left - coordsAt6.dx).abs(),
        lessThan(20),
        reason: 'Tooltip left (${tooltipBox.left}) should be near anchor X (${coordsAt6.dx})',
      );

      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
  });
}
