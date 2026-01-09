import 'package:codemirror/codemirror.dart' hide Text, lessThan, greaterThan;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    ensureStateInitialized();
    ensureLanguageInitialized();
    ensureLintInitialized();
  });

  group('Line number alignment (off-by-one issue)', () {
    testWidgets('line number 1 aligns with first content line', (tester) async {
      // JSX-like content similar to the screenshot showing the issue
      const doc = '''return (
  <Padding
  padding={EdgeInsetsGeometry.all({
    <Center>
      <Column mainAxisAlignment="c
crossAxisAlignment="center">
        <Text.h1>New Template</Tex
        <SizedBox height={16} />
      <Text>
        Add properties in the si
them here like "{propertyName}"
      </Text>
    </Column>
  </Center>
</Padding>
);''';

      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
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

      // Find line number 1 and check its alignment with content
      final lineNum1 = find.text('1');
      expect(lineNum1, findsOneWidget, reason: 'Should find line number 1');

      final gutterRect1 = tester.getRect(lineNum1);

      // Get the EditableText to find actual content position
      final editableTextFinder = find.byType(EditableText);
      expect(editableTextFinder, findsOneWidget);

      final editableState = tester.state<EditableTextState>(editableTextFinder);
      final renderEditable = editableState.renderEditable;

      // Get position of first character
      final textPos = const TextPosition(offset: 0);
      final caretRect = renderEditable.getLocalRectForCaret(textPos);

      // Convert to global coordinates
      final renderBox = editableState.context.findRenderObject() as RenderBox;
      final contentGlobalY = renderBox.localToGlobal(Offset(0, caretRect.top)).dy;

      // The line number "1" should be at the same Y position as the first line of content
      final drift = gutterRect1.top - contentGlobalY;

      print('Line 1 gutter Y: ${gutterRect1.top}');
      print('Line 1 content Y: $contentGlobalY');
      print('Drift: $drift');

      // Should be within 2 pixels
      expect(drift.abs(), lessThan(2.0),
          reason: 'Line number 1 (${gutterRect1.top}) should align with content ($contentGlobalY), drift: $drift');
    });

    testWidgets('line numbers are not offset by one line', (tester) async {
      // Create a simple document where we can verify line numbers match content
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'LINE_A\nLINE_B\nLINE_C\nLINE_D\nLINE_E',
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

      // Find each line number
      for (var i = 1; i <= 5; i++) {
        final lineNumFinder = find.text('$i');
        expect(lineNumFinder, findsOneWidget, reason: 'Should find line number $i');

        final gutterRect = tester.getRect(lineNumFinder);

        // Calculate expected position based on the document model
        final line = state.doc.line(i);
        print('Line $i: from=${line.from}, text="${line.text}"');

        // Get content position for this line's start
        final editableTextFinder = find.byType(EditableText);
        final editableState = tester.state<EditableTextState>(editableTextFinder);
        final renderEditable = editableState.renderEditable;

        final textPos = TextPosition(offset: line.from);
        final caretRect = renderEditable.getLocalRectForCaret(textPos);

        final renderBox = editableState.context.findRenderObject() as RenderBox;
        final contentGlobalY = renderBox.localToGlobal(Offset(0, caretRect.top)).dy;

        final drift = gutterRect.top - contentGlobalY;

        print('  Gutter Y: ${gutterRect.top}, Content Y: $contentGlobalY, Drift: $drift');

        expect(drift.abs(), lessThan(3.0),
            reason: 'Line $i gutter (${gutterRect.top}) should align with content ($contentGlobalY), drift: $drift');
      }
    });

    testWidgets('gutter line spacing matches content line spacing', (tester) async {
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

      // Get gutter line heights
      final gutterHeights = <double>[];
      for (var i = 1; i <= 4; i++) {
        final line1 = tester.getRect(find.text('$i'));
        final line2 = tester.getRect(find.text('${i + 1}'));
        gutterHeights.add(line2.top - line1.top);
      }

      // Get content line heights from EditableText
      final editableTextFinder = find.byType(EditableText);
      final editableState = tester.state<EditableTextState>(editableTextFinder);
      final renderEditable = editableState.renderEditable;
      final renderBox = editableState.context.findRenderObject() as RenderBox;

      final contentHeights = <double>[];
      for (var i = 1; i <= 4; i++) {
        final line1 = state.doc.line(i);
        final line2 = state.doc.line(i + 1);

        final pos1 = TextPosition(offset: line1.from);
        final pos2 = TextPosition(offset: line2.from);

        final rect1 = renderEditable.getLocalRectForCaret(pos1);
        final rect2 = renderEditable.getLocalRectForCaret(pos2);

        final y1 = renderBox.localToGlobal(Offset(0, rect1.top)).dy;
        final y2 = renderBox.localToGlobal(Offset(0, rect2.top)).dy;

        contentHeights.add(y2 - y1);
      }

      print('Gutter line heights: $gutterHeights');
      print('Content line heights: $contentHeights');

      // All heights should match between gutter and content
      for (var i = 0; i < gutterHeights.length; i++) {
        expect(gutterHeights[i], closeTo(contentHeights[i], 1.0),
            reason: 'Gutter height ${gutterHeights[i]} should match content height ${contentHeights[i]} for line ${i + 1}');
      }
    });

    testWidgets('first line number starts at correct Y position with padding', (tester) async {
      const padding = EdgeInsets.all(16.0);
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
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
                padding: padding,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find line number 1
      final lineNum1 = find.text('1');
      expect(lineNum1, findsOneWidget);

      final gutterRect = tester.getRect(lineNum1);

      // Get content position
      final editableTextFinder = find.byType(EditableText);
      final editableState = tester.state<EditableTextState>(editableTextFinder);
      final renderEditable = editableState.renderEditable;
      final renderBox = editableState.context.findRenderObject() as RenderBox;

      final textPos = const TextPosition(offset: 0);
      final caretRect = renderEditable.getLocalRectForCaret(textPos);
      final contentGlobalY = renderBox.localToGlobal(Offset(0, caretRect.top)).dy;

      final drift = gutterRect.top - contentGlobalY;

      print('With padding=${padding.top}:');
      print('  Line 1 gutter Y: ${gutterRect.top}');
      print('  Line 1 content Y: $contentGlobalY');
      print('  Drift: $drift');

      expect(drift.abs(), lessThan(2.0),
          reason: 'Line number 1 should align with content even with padding');
    });

    testWidgets('lint gutter maintains width even without diagnostics', (tester) async {
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: ExtensionList([
            lineNumbers(),
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
                state: state,
                onUpdate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the GutterView widgets
      final gutterViews = find.byType(GutterView);
      expect(gutterViews, findsNWidgets(2), reason: 'Should have line numbers and lint gutters');

      // Get widths of both gutters
      final gutterRects = <Rect>[];
      for (var i = 0; i < 2; i++) {
        gutterRects.add(tester.getRect(gutterViews.at(i)));
      }

      print('Gutter widths: ${gutterRects.map((r) => r.width).toList()}');

      // The lint gutter should have non-zero width (from spacer)
      // Find which one is the lint gutter (it should be ~14-16px wide)
      final lintGutterWidth = gutterRects.map((r) => r.width).where((w) => w < 30).firstOrNull;
      expect(lintGutterWidth, isNotNull, reason: 'Should find lint gutter');
      expect(lintGutterWidth, greaterThanOrEqualTo(14.0),
          reason: 'Lint gutter should maintain minimum width from spacer');
    });

    testWidgets('lint marker vertically aligns with line number on same line', (tester) async {
      var state = EditorState.create(
        EditorStateConfig(
          doc: 'Line 1\nLine 2\nLine 3',
          extensions: ExtensionList([
            lineNumbers(),
            lintGutter(),
          ]),
        ),
      );

      // Add a diagnostic on line 2
      final tr = state.update([
        setDiagnostics(state, [
          Diagnostic(from: 7, to: 13, message: 'Test error', severity: Severity.error),
        ]),
      ]);
      state = tr.state as EditorState;

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

      // Find line number "2"
      final lineNum2 = find.text('2');
      expect(lineNum2, findsOneWidget, reason: 'Should find line number 2');
      final lineNumRect = tester.getRect(lineNum2);

      // Find the lint marker (the X icon) - it uses a nerd font character
      // Look for visible Text widgets with the error icon (exclude the hidden spacer)
      final lintMarkerFinder = find.byWidgetPredicate((widget) {
        if (widget is Text) {
          final text = widget.data ?? (widget.textSpan as TextSpan?)?.text;
          if (text == '\uf00d') {
            // Check if it's inside an Opacity widget with opacity 0 (the spacer)
            return true;
          }
        }
        return false;
      });
      
      // Find all matches and get the visible one (not inside Opacity(0))
      final allMatches = tester.widgetList<Text>(lintMarkerFinder).toList();
      print('Found ${allMatches.length} lint markers');
      
      // Get rects and find the one that's actually visible (has color)
      Rect? lintRect;
      for (final match in lintMarkerFinder.evaluate()) {
        final widget = match.widget as Text;
        final style = widget.style;
        if (style?.color != null && style!.color!.alpha > 0) {
          lintRect = tester.getRect(find.byWidget(widget));
          break;
        }
      }
      expect(lintRect, isNotNull, reason: 'Should find visible lint marker');

      print('Line number 2 rect: $lineNumRect (height: ${lineNumRect.height})');
      print('Lint marker rect: $lintRect (height: ${lintRect!.height})');
      print('Line number top Y: ${lineNumRect.top}');
      print('Lint marker top Y: ${lintRect.top}');
      print('Line number center Y: ${lineNumRect.center.dy}');
      print('Lint marker center Y: ${lintRect.center.dy}');

      // The lint marker should be vertically centered at the same position as the line number
      final centerYDrift = (lintRect.center.dy - lineNumRect.center.dy).abs();
      final topYDrift = (lintRect.top - lineNumRect.top).abs();
      print('Center Y drift: $centerYDrift');
      print('Top Y drift: $topYDrift');

      // Centers should align (both markers centered within the line)
      expect(centerYDrift, lessThan(2.0),
          reason: 'Lint marker center (${lintRect.center.dy}) should align with line number center (${lineNumRect.center.dy})');
    });

    testWidgets('content position stays same with or without lint gutter markers', (tester) async {
      // First, create editor with lint gutter but no diagnostics
      var state = EditorState.create(
        EditorStateConfig(
          doc: 'const x = 1;',
          extensions: ExtensionList([
            lineNumbers(),
            lintGutter(),
          ]),
        ),
      );

      late EditorState currentState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: EditorView(
                state: state,
                onUpdate: (update) => currentState = update.state,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      currentState = state;

      // Get content position without diagnostics
      final editableTextFinder = find.byType(EditableText);
      final editableState = tester.state<EditableTextState>(editableTextFinder);
      final renderBox = editableState.context.findRenderObject() as RenderBox;
      final contentXWithoutDiagnostics = renderBox.localToGlobal(Offset.zero).dx;

      print('Content X without diagnostics: $contentXWithoutDiagnostics');

      // Now add diagnostics via transaction
      final tr = currentState.update([
        setDiagnostics(currentState, [
          Diagnostic(from: 0, to: 5, message: 'Test error', severity: Severity.error),
        ]),
      ]);
      state = tr.state as EditorState;

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

      // Get content position with diagnostics
      final editableTextFinder2 = find.byType(EditableText);
      final editableState2 = tester.state<EditableTextState>(editableTextFinder2);
      final renderBox2 = editableState2.context.findRenderObject() as RenderBox;
      final contentXWithDiagnostics = renderBox2.localToGlobal(Offset.zero).dx;

      print('Content X with diagnostics: $contentXWithDiagnostics');

      // Content should be at the same X position regardless of diagnostics
      expect(contentXWithDiagnostics, equals(contentXWithoutDiagnostics),
          reason: 'Content X position should not change when diagnostics are added');
    });
  });
}
