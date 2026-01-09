import 'package:codemirror/codemirror.dart' hide Text, lessThan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hover tooltip', () {
    test('hoverTooltip extension registers config in facet', () {
      ensureStateInitialized();
      
      // Create a simple hover source
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return createTextTooltip(
          pos: pos,
          end: pos + 1,
          content: 'Test tooltip',
        );
      }
      
      // Create state with hover tooltip
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello, World!',
          extensions: ExtensionList([
            hoverTooltip(hoverSource),
          ]),
        ),
      );
      
      // Query the facet
      final configs = state.facet(hoverTooltipFacet);
      
      print('Number of hover configs: ${configs.length}');
      expect(configs.length, equals(1), reason: 'Expected one hover config');
      expect(configs.first.source, equals(hoverSource));
    });
    
    test('hoverTooltip source is called and returns tooltip', () {
      ensureStateInitialized();
      
      var called = false;
      int? calledPos;
      int? calledSide;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        called = true;
        calledPos = pos;
        calledSide = side;
        return createTextTooltip(
          pos: pos,
          end: pos + 5,
          content: 'Info about word at $pos',
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello, World!',
          extensions: ExtensionList([
            hoverTooltip(hoverSource),
          ]),
        ),
      );
      
      final configs = state.facet(hoverTooltipFacet);
      expect(configs.length, equals(1));
      
      // Simulate calling the source
      final result = configs.first.source(state, 5, 1);
      
      expect(called, isTrue);
      expect(calledPos, equals(5));
      expect(calledSide, equals(1));
      expect(result, isA<HoverTooltip>());
      
      final tooltip = result as HoverTooltip;
      expect(tooltip.pos, equals(5));
      expect(tooltip.end, equals(10));
    });
    
    test('multiple hover sources are collected', () {
      ensureStateInitialized();
      
      HoverTooltip? source1(EditorState state, int pos, int side) {
        return createTextTooltip(pos: pos, content: 'Source 1');
      }
      
      HoverTooltip? source2(EditorState state, int pos, int side) {
        return createTextTooltip(pos: pos, content: 'Source 2');
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Test',
          extensions: ExtensionList([
            hoverTooltip(source1),
            hoverTooltip(source2),
          ]),
        ),
      );
      
      final configs = state.facet(hoverTooltipFacet);
      expect(configs.length, equals(2));
    });
    
    testWidgets('hover over text triggers tooltip source', (tester) async {
      ensureStateInitialized();
      
      var sourceCallCount = 0;
      int? lastPos;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        sourceCallCount++;
        lastPos = pos;
        return createTextTooltip(
          pos: pos,
          content: 'Tooltip for position $pos',
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World Test',
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(
              state: state,
              onUpdate: (_) {},
            ),
          ),
        ),
      ));
      
      // Let the editor render
      await tester.pumpAndSettle();
      
      // Find the editor
      final editorFinder = find.byType(EditorView);
      expect(editorFinder, findsOneWidget);
      
      // Get the position of the editor
      final editorBox = tester.getRect(editorFinder);
      
      // Create a test pointer for hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      
      // Move to a position in the text area
      await gesture.addPointer(location: Offset(
        editorBox.left + 50,
        editorBox.top + 20,
      ));
      await tester.pump();
      
      // Move pointer to trigger hover
      await gesture.moveTo(Offset(
        editorBox.left + 60,
        editorBox.top + 20,
      ));
      await tester.pump();
      
      // Wait for hover delay (default 300ms + timer execution)
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(); // Let the async source complete
      await tester.pump(); // Let the tooltip render
      
      // Verify the source was called
      expect(sourceCallCount, greaterThan(0), 
        reason: 'Hover source should be called when hovering over text');
      expect(lastPos, isNotNull);
      
      // Verify the tooltip is shown (look for the tooltip text)
      expect(find.text('Tooltip for position $lastPos'), findsOneWidget);
      
      // Clean up gesture
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('tooltip appears in overlay after hover delay', (tester) async {
      ensureStateInitialized();
      
      var tooltipCreated = false;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        tooltipCreated = true;
        return HoverTooltip(
          pos: pos,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('test-tooltip'),
              padding: const EdgeInsets.all(8),
              color: Colors.yellow,
              child: const Text('HOVER TOOLTIP VISIBLE'),
            ),
          ),
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World Test',
          extensions: ExtensionList([
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
      
      // Initially no tooltip
      expect(find.byKey(const Key('test-tooltip')), findsNothing);
      expect(find.text('HOVER TOOLTIP VISIBLE'), findsNothing);
      
      // Hover over text
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 50, editorBox.top + 20));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 60, editorBox.top + 20));
      await tester.pump();
      
      // Wait for hover delay
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      expect(tooltipCreated, isTrue, reason: 'Tooltip source should be called');
      
      // Check overlay contains tooltip
      expect(find.byKey(const Key('test-tooltip')), findsOneWidget);
      expect(find.text('HOVER TOOLTIP VISIBLE'), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('diagnostic tooltip still works', (tester) async {
      ensureStateInitialized();
      ensureLintInitialized();
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World',
          extensions: ExtensionList([
            linter(null),
          ]),
        ),
      );
      
      // Add a diagnostic
      final stateWithDiag = state.update([
        setDiagnostics(state, [
          Diagnostic(
            from: 0,
            to: 5,
            severity: Severity.error,
            message: 'TEST ERROR MESSAGE',
          ),
        ]),
      ]).state as EditorState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(state: stateWithDiag),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      // No tooltip initially
      expect(find.text('TEST ERROR MESSAGE'), findsNothing);
      
      // Hover over the diagnostic range
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 20, editorBox.top + 15));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 30, editorBox.top + 15));
      await tester.pump();
      
      // Wait for hover delay
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      // Diagnostic tooltip should appear
      expect(find.text('TEST ERROR MESSAGE'), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('both diagnostic and hover tooltip show together', (tester) async {
      ensureStateInitialized();
      ensureLintInitialized();
      
      var hoverSourceCalled = false;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        hoverSourceCalled = true;
        return createTextTooltip(pos: pos, content: 'HOVER INFO');
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World',
          extensions: ExtensionList([
            linter(null),
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );
      
      // Add diagnostic
      final stateWithDiag = state.update([
        setDiagnostics(state, [
          Diagnostic(from: 0, to: 5, severity: Severity.error, message: 'DIAG ERROR'),
        ]),
      ]).state as EditorState;
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(state: stateWithDiag),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      // Hover over diagnostic range
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 20, editorBox.top + 15));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 30, editorBox.top + 15));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      // Both should be visible
      expect(hoverSourceCalled, isTrue);
      expect(find.text('DIAG ERROR'), findsOneWidget);
      expect(find.text('HOVER INFO'), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('async hover source with delay works', (tester) async {
      ensureStateInitialized();
      
      var sourceCalled = false;
      
      // Async hover source like the demo uses
      Future<HoverTooltip?> asyncHoverSource(EditorState state, int pos, int side) async {
        // Simulate network delay like LSP
        await Future.delayed(const Duration(milliseconds: 50));
        sourceCalled = true;
        return createTextTooltip(pos: pos, content: 'ASYNC TOOLTIP');
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'function greet() {}',
          extensions: ExtensionList([
            hoverTooltip(asyncHoverSource, const HoverTooltipOptions(hoverTime: 100)),
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
      
      // Hover over text
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 50, editorBox.top + 20));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 60, editorBox.top + 20));
      await tester.pump();
      
      // Wait for hover delay (300ms default) + async delay (50ms) + buffer
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      expect(sourceCalled, isTrue, reason: 'Async source should be called');
      expect(find.text('ASYNC TOOLTIP'), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('markdown tooltip renders correctly', (tester) async {
      ensureStateInitialized();
      
      var sourceCalled = false;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        sourceCalled = true;
        return createMarkdownTooltip(
          pos: pos,
          content: '**Bold** and _italic_',
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Test content',
          extensions: ExtensionList([
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
      
      // Hover
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 50, editorBox.top + 20));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 60, editorBox.top + 20));
      await tester.pump();
      // Wait for hover delay (300ms default)
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      // Source should be called and HoverTooltipWidget should be present
      expect(sourceCalled, isTrue);
      expect(find.byType(HoverTooltipWidget), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('hover tooltip shows with ClipRRect wrapper (like demo)', (tester) async {
      ensureStateInitialized();
      
      var sourceCalled = false;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        sourceCalled = true;
        return createTextTooltip(pos: pos, content: 'CLIPPED TOOLTIP');
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World',
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );
      
      // Build with ClipRRect like the demo
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 800,
                height: 600,
                child: EditorView(state: state),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      // Hover
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 50, editorBox.top + 20));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 60, editorBox.top + 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      expect(sourceCalled, isTrue);
      // Tooltip should be visible in the overlay (not clipped)
      expect(find.text('CLIPPED TOOLTIP'), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('hover works after state updates (like demo)', (tester) async {
      ensureStateInitialized();
      
      var sourceCalled = false;
      
      Future<HoverTooltip?> hoverSource(EditorState state, int pos, int side) async {
        await Future.delayed(const Duration(milliseconds: 10));
        sourceCalled = true;
        return createTextTooltip(pos: pos, content: 'DEMO TOOLTIP');
      }
      
      EditorState currentState = EditorState.create(
        EditorStateConfig(
          doc: 'Hello World Test',
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
          ]),
        ),
      );
      
      // Verify facet is registered
      var configs = currentState.facet(hoverTooltipFacet);
      expect(configs.length, equals(1));
      
      // Build widget with onUpdate that updates state (like the demo)
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 800,
                height: 600,
                child: EditorView(
                  state: currentState,
                  onUpdate: (update) {
                    setState(() {
                      currentState = update.state;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      // Check configs in view state
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      configs = viewState.state.facet(hoverTooltipFacet);
      expect(configs.length, equals(1));
      
      // Type something to trigger a state update
      await tester.tap(find.byType(EditorView));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'Hello World Test!');
      await tester.pump();
      
      // Check configs still exist after state update
      configs = viewState.state.facet(hoverTooltipFacet);
      
      // Now hover
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 50, editorBox.top + 20));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 60, editorBox.top + 20));
      await tester.pump();
      
      // Wait for hover delay
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      expect(sourceCalled, isTrue, reason: 'Hover source should be called after state updates');

      await gesture.removePointer();
      await tester.pumpAndSettle();
      });
      
      group('Tooltip Positioning', () {
      testWidgets('tooltip appears below the hovered text position', (tester) async {
        ensureStateInitialized();
        
        HoverTooltip? hoverSource(EditorState state, int pos, int side) {
          return HoverTooltip(
            pos: pos,
            create: (context) => TooltipView(
              widget: Container(
                key: const Key('position-test-tooltip'),
                padding: const EdgeInsets.all(8),
                color: Colors.blue,
                child: const Text('POSITION TEST'),
              ),
            ),
          );
        }
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'Hello World Test',
            extensions: ExtensionList([
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
        
        // Get editor position
        final editorBox = tester.getRect(find.byType(EditorView));
        
        // Hover at a specific position in the editor
        final hoverX = editorBox.left + 50;
        final hoverY = editorBox.top + 20;
        
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset(hoverX, hoverY));
        await tester.pump();
        await gesture.moveTo(Offset(hoverX + 5, hoverY));
        await tester.pump();
        
        // Wait for hover delay
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        
        // Verify tooltip appeared
        final tooltipFinder = find.byKey(const Key('position-test-tooltip'));
        expect(tooltipFinder, findsOneWidget, reason: 'Tooltip should appear');
        
        // Get tooltip position
        final tooltipBox = tester.getRect(tooltipFinder);
        
        // Tooltip should be positioned BELOW the hover position (y should be greater)
        expect(tooltipBox.top, greaterThan(hoverY),
          reason: 'Tooltip top ($tooltipBox.top) should be below hover Y ($hoverY)');
        
        // Tooltip should be near horizontally to hover position (within reasonable range)
        expect(tooltipBox.left, greaterThanOrEqualTo(0),
          reason: 'Tooltip should not overflow left edge');
        expect(tooltipBox.left, lessThan(editorBox.right),
          reason: 'Tooltip should be within editor bounds');
        
        await gesture.removePointer();
        await tester.pumpAndSettle();
      });
      
      testWidgets('tooltip x position is near the anchor text position', (tester) async {
        ensureStateInitialized();
        
        HoverTooltip? hoverSource(EditorState state, int pos, int side) {
          return HoverTooltip(
            pos: pos,
            create: (context) => TooltipView(
              widget: Container(
                key: const Key('x-position-tooltip'),
                width: 100,
                height: 50,
                color: Colors.green,
                child: const Text('X POS'),
              ),
            ),
          );
        }
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'Hello World Test Content',
            extensions: ExtensionList([
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
        
        final editorBox = tester.getRect(find.byType(EditorView));
        
        // Hover at a position further into the text
        final hoverX = editorBox.left + 100;
        final hoverY = editorBox.top + 20;
        
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset(hoverX, hoverY));
        await tester.pump();
        await gesture.moveTo(Offset(hoverX + 5, hoverY));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        
        final tooltipFinder = find.byKey(const Key('x-position-tooltip'));
        expect(tooltipFinder, findsOneWidget);
        
        final tooltipBox = tester.getRect(tooltipFinder);
        
        // Tooltip X should be somewhere near the hover X (within 100px tolerance for char alignment)
        // The anchor is computed from the character position, not exact hover point
        expect((tooltipBox.left - hoverX).abs(), lessThan(100),
          reason: 'Tooltip X (${tooltipBox.left}) should be near hover X ($hoverX) within 100px');
        
        await gesture.removePointer();
        await tester.pumpAndSettle();
      });
      
      testWidgets('tooltip for text at different lines appears at correct Y', (tester) async {
        ensureStateInitialized();
        
        HoverTooltip? hoverSource(EditorState state, int pos, int side) {
          return HoverTooltip(
            pos: pos,
            create: (context) => TooltipView(
              widget: Container(
                key: const Key('multiline-tooltip'),
                padding: const EdgeInsets.all(8),
                color: Colors.orange,
                child: const Text('LINE TEST'),
              ),
            ),
          );
        }
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5',
            extensions: ExtensionList([
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
        
        final editorBox = tester.getRect(find.byType(EditorView));
        
        // Get the EditorViewState to access lineHeight
        final viewState = tester.state<EditorViewState>(find.byType(EditorView));
        final lineHeight = viewState.lineHeight;
        
        // Hover over line 3 (approximately 2 * lineHeight from top, plus padding)
        final hoverX = editorBox.left + 30;
        final hoverY = editorBox.top + 8 + (2 * lineHeight) + (lineHeight / 2); // middle of line 3
        
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset(hoverX, hoverY));
        await tester.pump();
        await gesture.moveTo(Offset(hoverX + 5, hoverY));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        
        final tooltipFinder = find.byKey(const Key('multiline-tooltip'));
        expect(tooltipFinder, findsOneWidget, reason: 'Tooltip should appear');
        
        final tooltipBox = tester.getRect(tooltipFinder);
        
        // Tooltip should be below the hovered line
        expect(tooltipBox.top, greaterThan(hoverY),
          reason: 'Tooltip should appear below the hovered line');
        
        // Tooltip should be reasonably close to the hover Y (not at top of editor)
        expect(tooltipBox.top, lessThan(hoverY + lineHeight * 2),
          reason: 'Tooltip should be within 2 line heights below hover position');
        
        await gesture.removePointer();
        await tester.pumpAndSettle();
      });
      
      testWidgets('diagnostic tooltip appears at diagnostic from position', (tester) async {
        ensureStateInitialized();
        ensureLintInitialized();
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'hello world test',
            extensions: ExtensionList([
              linter(null),
            ]),
          ),
        );
        
        // Set diagnostic on "world" (positions 6-11)
        final stateWithDiag = state.update([
          setDiagnostics(state, [
            const Diagnostic(
              from: 6,
              to: 11,
              severity: Severity.error,
              message: 'DIAGNOSTIC AT WORLD',
            ),
          ]),
        ]).state as EditorState;
        
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: EditorView(state: stateWithDiag),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        
        final viewState = tester.state<EditorViewState>(find.byType(EditorView));
        
        // Get exact coords of position 8 (middle of "world")
        final coordsAt8 = viewState.coordsAtPos(8);
        expect(coordsAt8, isNotNull, reason: 'Should get coords for position 8');
        
        // Hover exactly at position 8 (inside "world" diagnostic range 6-11)
        final hoverX = coordsAt8!.dx;
        final hoverY = coordsAt8.dy + viewState.lineHeight / 2;
        
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset(hoverX, hoverY));
        await tester.pump();
        await gesture.moveTo(Offset(hoverX + 2, hoverY));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        
        // Tooltip should appear
        expect(find.text('DIAGNOSTIC AT WORLD'), findsOneWidget);
        
        final tooltipFinder = find.byType(DiagnosticTooltip);
        expect(tooltipFinder, findsOneWidget);
        
        final tooltipBox = tester.getRect(tooltipFinder);
        
        // Get the expected anchor position (position 6 = start of "world")
        final coordsAtFrom = viewState.coordsAtPos(6);
        expect(coordsAtFrom, isNotNull, reason: 'Should get coords for diagnostic from position');
        
        // Tooltip left should be near the diagnostic's from position
        // The anchor is at diagnostic.from, so tooltip X should be near that
        expect((tooltipBox.left - coordsAtFrom!.dx).abs(), lessThan(50),
          reason: 'Tooltip left (${tooltipBox.left}) should be near anchor X (${coordsAtFrom.dx})');
        
        await gesture.removePointer();
        await tester.pumpAndSettle();
      });
      
      testWidgets('tooltip does not overflow screen bounds', (tester) async {
        ensureStateInitialized();
        
        HoverTooltip? hoverSource(EditorState state, int pos, int side) {
          return HoverTooltip(
            pos: pos,
            create: (context) => TooltipView(
              widget: Container(
                key: const Key('overflow-tooltip'),
                width: 300,
                height: 100,
                color: Colors.red,
                child: const Text('OVERFLOW TEST'),
              ),
            ),
          );
        }
        
        final state = EditorState.create(
          EditorStateConfig(
            doc: 'A'.padRight(200, 'A'), // Long line
            extensions: ExtensionList([
              hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 50)),
            ]),
          ),
        );
        
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400, // Narrow editor
              height: 200,
              child: EditorView(state: state),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        
        final editorBox = tester.getRect(find.byType(EditorView));
        
        // Hover near right edge
        final hoverX = editorBox.right - 20;
        final hoverY = editorBox.top + 20;
        
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset(hoverX, hoverY));
        await tester.pump();
        await gesture.moveTo(Offset(hoverX - 5, hoverY));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        
        final tooltipFinder = find.byKey(const Key('overflow-tooltip'));
        expect(tooltipFinder, findsOneWidget);
        
        final tooltipBox = tester.getRect(tooltipFinder);
        final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
        
        // Tooltip should not overflow left
        expect(tooltipBox.left, greaterThanOrEqualTo(0),
          reason: 'Tooltip should not overflow left edge');
        
        // Check that tooltip is visible (top is positive)
        expect(tooltipBox.top, greaterThanOrEqualTo(0),
          reason: 'Tooltip should not overflow top edge');
        
        await gesture.removePointer();
        await tester.pumpAndSettle();
      });
    });
  });
}
