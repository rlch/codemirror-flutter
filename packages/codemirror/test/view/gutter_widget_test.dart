import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/codemirror.dart' hide Text;

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureLanguageInitialized();
  });

  group('Gutter Widget Tests', () {
    testWidgets('lineNumbers extension adds gutter config', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: lineNumbers(),
        ),
      );

      // Check that activeGutters facet has config
      final gutterConfigs = state.facet(activeGutters);
      expect(gutterConfigs, isNotEmpty, reason: 'activeGutters should have configs');
      expect(gutterConfigs.length, 1);
      expect(gutterConfigs.first.className, 'cm-lineNumbers');
    });

    testWidgets('GutterView renders line numbers', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: lineNumbers(),
        ),
      );

      final gutterConfigs = state.facet(activeGutters);
      expect(gutterConfigs, isNotEmpty);
      
      final config = gutterConfigs.first;
      
      // Create line blocks manually
      final lineBlocks = <BlockInfo>[];
      var top = 0.0;
      const lineHeight = 20.0;
      for (var i = 1; i <= state.doc.lines; i++) {
        final line = state.doc.line(i);
        lineBlocks.add(BlockInfo(line.from, line.length, top, lineHeight));
        top += lineHeight;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GutterView(
              config: config,
              state: state,
              lineBlocks: lineBlocks,
              contentHeight: top,
            ),
          ),
        ),
      );

      // Should render line numbers
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('EditorView renders gutters when lineNumbers is configured', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello\nWorld\nTest',
          extensions: lineNumbers(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: EditorView(
                state: state,
                onUpdate: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Debug: print widget tree
      debugDumpApp();

      // Check that line numbers are rendered
      expect(find.text('1'), findsOneWidget, reason: 'Should find line number 1');
      expect(find.text('2'), findsOneWidget, reason: 'Should find line number 2');
      expect(find.text('3'), findsOneWidget, reason: 'Should find line number 3');
    });

    testWidgets('activeGutters facet is properly populated', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Test',
          extensions: ExtensionList([
            lineNumbers(),
          ]),
        ),
      );

      final configs = state.facet(activeGutters);
      print('Number of gutter configs: ${configs.length}');
      for (final config in configs) {
        print('  - className: ${config.className}');
        print('  - side: ${config.side}');
      }
      
      expect(configs, isNotEmpty);
    });

    testWidgets('custom gutter with markers renders', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: gutter(GutterConfig(
            className: 'test-gutter',
            lineMarker: (state, line, others) {
              return _TestMarker('*');
            },
          )),
        ),
      );

      final gutterConfigs = state.facet(activeGutters);
      expect(gutterConfigs, isNotEmpty);

      final config = gutterConfigs.first;
      
      // Create line blocks
      final lineBlocks = <BlockInfo>[];
      var top = 0.0;
      const lineHeight = 20.0;
      for (var i = 1; i <= state.doc.lines; i++) {
        final line = state.doc.line(i);
        lineBlocks.add(BlockInfo(line.from, line.length, top, lineHeight));
        top += lineHeight;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GutterView(
              config: config,
              state: state,
              lineBlocks: lineBlocks,
              contentHeight: top,
            ),
          ),
        ),
      );

      // Should render markers on each line
      expect(find.text('*'), findsNWidgets(3));
    });

    testWidgets('GutterView with empty lineBlocks renders nothing', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Test',
          extensions: lineNumbers(),
        ),
      );

      final config = state.facet(activeGutters).first;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GutterView(
              config: config,
              state: state,
              lineBlocks: const [], // Empty!
              contentHeight: 100,
            ),
          ),
        ),
      );

      // Should not crash, should render empty container
      expect(find.byType(GutterView), findsOneWidget);
      expect(find.text('1'), findsNothing); // No line numbers since no blocks
    });

    testWidgets('gutter line numbers have consistent spacing', (tester) async {
      // Create editor with multiple lines
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5',
          extensions: lineNumbers(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorView(
                state: state,
                onUpdate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the line number widgets
      final lineNum1 = find.text('1');
      final lineNum2 = find.text('2');
      final lineNum3 = find.text('3');
      final lineNum4 = find.text('4');
      final lineNum5 = find.text('5');

      expect(lineNum1, findsOneWidget, reason: 'Should find line number 1');
      expect(lineNum2, findsOneWidget, reason: 'Should find line number 2');
      expect(lineNum3, findsOneWidget, reason: 'Should find line number 3');
      expect(lineNum4, findsOneWidget, reason: 'Should find line number 4');
      expect(lineNum5, findsOneWidget, reason: 'Should find line number 5');

      // Get the Y positions of each line number
      final rect1 = tester.getRect(lineNum1);
      final rect2 = tester.getRect(lineNum2);
      final rect3 = tester.getRect(lineNum3);
      final rect4 = tester.getRect(lineNum4);
      final rect5 = tester.getRect(lineNum5);

      // Calculate the height between consecutive line numbers
      final height1to2 = rect2.top - rect1.top;
      final height2to3 = rect3.top - rect2.top;
      final height3to4 = rect4.top - rect3.top;
      final height4to5 = rect5.top - rect4.top;

      print('Line heights in gutter:');
      print('  1->2: $height1to2');
      print('  2->3: $height2to3');
      print('  3->4: $height3to4');
      print('  4->5: $height4to5');

      // All heights should be equal (within a small tolerance)
      const tolerance = 1.0;
      expect(height1to2, closeTo(height2to3, tolerance),
          reason: 'Height between lines 1-2 ($height1to2) and 2-3 ($height2to3) should be equal');
      expect(height2to3, closeTo(height3to4, tolerance),
          reason: 'Height between lines 2-3 ($height2to3) and 3-4 ($height3to4) should be equal');
      expect(height3to4, closeTo(height4to5, tolerance),
          reason: 'Height between lines 3-4 ($height3to4) and 4-5 ($height4to5) should be equal');

      // Expected line height: fontSize(14) * height(1.4) = 19.6
      const expectedLineHeight = 14.0 * 1.4;
      print('Expected line height: $expectedLineHeight');
      print('Actual line height: $height1to2');
      
      expect(height1to2, closeTo(expectedLineHeight, 2.0),
          reason: 'Line height ($height1to2) should be close to expected ($expectedLineHeight)');
    });

    testWidgets('gutter lines are evenly spaced', (tester) async {
      // Create editor with 25 lines
      final lines = List.generate(25, (i) => 'Line ${i + 1}').join('\n');
      final state = EditorState.create(
        EditorStateConfig(
          doc: lines,
          extensions: lineNumbers(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 800, // Tall enough to show all lines
              child: EditorView(
                state: state,
                onUpdate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find line number 1 and 20
      final lineNum1 = find.text('1');
      final lineNum2 = find.text('2');
      final lineNum20 = find.text('20');

      expect(lineNum1, findsOneWidget, reason: 'Should find line number 1');
      expect(lineNum2, findsOneWidget, reason: 'Should find line number 2');
      expect(lineNum20, findsOneWidget, reason: 'Should find line number 20');

      // Get positions
      final rect1 = tester.getRect(lineNum1);
      final rect2 = tester.getRect(lineNum2);
      final rect20 = tester.getRect(lineNum20);

      // Calculate actual line height from first two lines
      final actualLineHeight = rect2.top - rect1.top;
      final expectedOffset = 19 * actualLineHeight;
      final actualOffset = rect20.top - rect1.top;

      print('Line 1 top: ${rect1.top}');
      print('Line 20 top: ${rect20.top}');
      print('Actual line height: $actualLineHeight');
      print('Expected offset (19 * $actualLineHeight): $expectedOffset');
      print('Actual offset: $actualOffset');
      print('Drift: ${actualOffset - expectedOffset}');

      // Lines should be evenly spaced - line 20 should be at 19 * lineHeight
      expect(actualOffset, closeTo(expectedOffset, 2.0),
          reason: 'Line 20 position ($actualOffset) should match expected ($expectedOffset)');
    });

    testWidgets('gutter line numbers align with actual content lines', (tester) async {
      // Create editor with distinct content on each line so we can find them
      final lines = List.generate(25, (i) => 'CONTENT_LINE_${i + 1}_END').join('\n');
      final state = EditorState.create(
        EditorStateConfig(
          doc: lines,
          extensions: lineNumbers(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 800, // Tall enough to show all lines
              child: EditorView(
                state: state,
                onUpdate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Compare gutter line number position to content position for several lines
      for (final lineNum in [1, 5, 10, 15, 20]) {
        final gutterFinder = find.text('$lineNum');
        
        // The content is rendered by EditableText, so we need to find the RenderEditable
        // and query the position of specific text
        expect(gutterFinder, findsOneWidget, reason: 'Should find gutter line number $lineNum');
        
        final gutterRect = tester.getRect(gutterFinder);
        
        // Get the EditableText's render object to query text positions
        final editableTextFinder = find.byType(EditableText);
        expect(editableTextFinder, findsOneWidget);
        
        final editableState = tester.state<EditableTextState>(editableTextFinder);
        final renderEditable = editableState.renderEditable;
        
        // Calculate position of line start in document
        // Line 1 starts at 0, line 2 starts after "CONTENT_LINE_1_END\n", etc.
        final lineLength = 'CONTENT_LINE_XX_END\n'.length; // ~20 chars per line
        final docPos = (lineNum - 1) * lineLength;
        
        // Get the local rect for this position
        final textPos = TextPosition(offset: docPos.clamp(0, state.doc.length));
        final caretRect = renderEditable.getLocalRectForCaret(textPos);
        
        // Convert to global coordinates
        final renderBox = editableState.context.findRenderObject() as RenderBox;
        final contentGlobalY = renderBox.localToGlobal(Offset(0, caretRect.top)).dy;
        
        final drift = gutterRect.top - contentGlobalY;
        
        print('Line $lineNum: gutter top=${gutterRect.top.toStringAsFixed(1)}, '
            'content top=${contentGlobalY.toStringAsFixed(1)}, drift=${drift.toStringAsFixed(1)}');
        
        // Gutter and content should be aligned within 5 pixels
        expect(drift.abs() < 5.0, isTrue,
            reason: 'Line $lineNum gutter (${gutterRect.top}) should align with content ($contentGlobalY), drift: $drift');
      }
    });
  });
}


class _TestMarker extends GutterMarker {
  final String text;
  _TestMarker(this.text);

  @override
  Widget? toWidget(BuildContext context) => Text(text);

  @override
  bool markerEq(GutterMarker other) =>
      other is _TestMarker && other.text == text;
}
