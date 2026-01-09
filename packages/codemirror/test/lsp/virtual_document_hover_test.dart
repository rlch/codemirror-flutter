/// Widget tests for VirtualDocument integration with hover tooltips.
///
/// These tests verify that when using a VirtualDocument to map between
/// visible content and full document content (with hidden prefix/suffix),
/// hover tooltips show the correct information for the hovered symbol.
///
/// Key scenarios tested:
/// 1. Position mapping accuracy between visible ↔ full document
/// 2. Hover source receives correctly mapped positions
/// 3. Tooltip is anchored at the correct visual position
/// 4. Multi-line prefixes map correctly
import 'package:codemirror/codemirror.dart' hide Text, lessThan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VirtualDocument position mapping for hover', () {
    group('offset ↔ position conversions', () {
      test('offsetToLspPosition handles single line correctly', () {
        const text = 'hello world';
        //            01234567890
        
        expect(text.offsetToLspPosition(0), equals(const LspPosition(line: 0, character: 0)));
        expect(text.offsetToLspPosition(5), equals(const LspPosition(line: 0, character: 5)));
        expect(text.offsetToLspPosition(11), equals(const LspPosition(line: 0, character: 11)));
      });
      
      test('offsetToLspPosition handles multiple lines correctly', () {
        const text = 'line1\nline2\nline3';
        //            012345 678901 23456
        //            line0  line1  line2
        
        // Position 0 = start of line 0
        expect(text.offsetToLspPosition(0), equals(const LspPosition(line: 0, character: 0)));
        // Position 5 = end of "line1" (before \n)
        expect(text.offsetToLspPosition(5), equals(const LspPosition(line: 0, character: 5)));
        // Position 6 = start of line 1 (after \n)
        expect(text.offsetToLspPosition(6), equals(const LspPosition(line: 1, character: 0)));
        // Position 11 = end of "line2" (before \n)
        expect(text.offsetToLspPosition(11), equals(const LspPosition(line: 1, character: 5)));
        // Position 12 = start of line 2
        expect(text.offsetToLspPosition(12), equals(const LspPosition(line: 2, character: 0)));
      });
      
      test('lspPositionToOffset is inverse of offsetToLspPosition', () {
        const text = 'function foo() {\n  return 42;\n}';
        
        for (var offset = 0; offset <= text.length; offset++) {
          final pos = text.offsetToLspPosition(offset);
          final backToOffset = text.lspPositionToOffset(pos);
          expect(backToOffset, equals(offset), 
            reason: 'Round-trip failed for offset $offset -> pos $pos -> $backToOffset');
        }
      });
    });
    
    group('VirtualDocument toFullPosition mapping', () {
      test('maps visible position to full document with single-line prefix', () {
        final doc = VirtualDocument(
          prefix: 'const prefix = 1;\n',  // 1 line prefix (ends with \n)
          body: 'visible content',
          suffix: '',
        );
        
        // Visible line 0, char 0 → Full line 1, char 0
        expect(doc.toFullPosition(const LspPosition(line: 0, character: 0)),
          equals(const LspPosition(line: 1, character: 0)));
        
        // Visible line 0, char 5 → Full line 1, char 5
        expect(doc.toFullPosition(const LspPosition(line: 0, character: 5)),
          equals(const LspPosition(line: 1, character: 5)));
      });
      
      test('maps visible position to full document with multi-line prefix', () {
        final doc = VirtualDocument(
          prefix: 'line0\nline1\nline2\n',  // 3 lines prefix
          body: 'body line 0\nbody line 1',
          suffix: '\nend',
        );
        
        expect(doc.bodyStartLine, equals(3), reason: 'Prefix has 3 newlines so body starts at line 3');
        
        // Visible line 0, char 0 → Full line 3, char 0
        expect(doc.toFullPosition(const LspPosition(line: 0, character: 0)),
          equals(const LspPosition(line: 3, character: 0)));
        
        // Visible line 1, char 5 → Full line 4, char 5
        expect(doc.toFullPosition(const LspPosition(line: 1, character: 5)),
          equals(const LspPosition(line: 4, character: 5)));
      });
      
      test('realistic TypeScript template scenario', () {
        // Simulates the template editor scenario
        final doc = VirtualDocument(
          prefix: '''interface Props { name: string; }

function Template(props: Props) {
''',  // 3 lines (0, 1, 2), body starts at line 3
          body: '''  const greeting = props.name;
  return <div>{greeting}</div>;''',
          suffix: '\n}\n',
        );
        
        expect(doc.bodyStartLine, equals(3));
        
        // If user hovers at visible line 0, char 20 (on "props")
        // It should map to full line 3, char 20
        final visiblePos = const LspPosition(line: 0, character: 20);
        final fullPos = doc.toFullPosition(visiblePos);
        
        expect(fullPos.line, equals(3));
        expect(fullPos.character, equals(20));
        
        // Verify by checking the actual content
        final fullLines = doc.fullContent.split('\n');
        expect(fullLines[3], contains('const greeting'));
      });
    });
    
    group('VirtualDocument toVisiblePosition mapping', () {
      test('maps full document position back to visible', () {
        final doc = VirtualDocument(
          prefix: 'prefix\n',  // 1 line
          body: 'visible',
          suffix: '',
        );
        
        // Full line 1, char 3 → Visible line 0, char 3
        expect(doc.toVisiblePosition(const LspPosition(line: 1, character: 3)),
          equals(const LspPosition(line: 0, character: 3)));
      });
      
      test('returns null for positions in prefix', () {
        final doc = VirtualDocument(
          prefix: 'prefix line 0\nprefix line 1\n',
          body: 'body',
          suffix: '',
        );
        
        // Line 0 is in prefix
        expect(doc.toVisiblePosition(const LspPosition(line: 0, character: 5)), isNull);
        // Line 1 is in prefix  
        expect(doc.toVisiblePosition(const LspPosition(line: 1, character: 5)), isNull);
        // Line 2 is body start
        expect(doc.toVisiblePosition(const LspPosition(line: 2, character: 0)), isNotNull);
      });
      
      test('returns null for positions in suffix', () {
        final doc = VirtualDocument(
          prefix: 'prefix\n',
          body: 'body line 0',  // Single line body
          suffix: '\nsuffix',
        );
        
        // Line 1 is the body (visible line 0)
        expect(doc.toVisiblePosition(const LspPosition(line: 1, character: 0)), isNotNull);
        // Line 2 would be suffix (if body has no newlines, line 2 doesn't exist in visible)
        expect(doc.toVisiblePosition(const LspPosition(line: 2, character: 0)), isNull);
      });
    });
    
    group('round-trip position mapping', () {
      test('visible → full → visible is identity', () {
        final doc = VirtualDocument(
          prefix: 'interface Props {}\n\nfunction Component() {\n',
          body: '  return <div>Hello</div>;\n  const x = 1;',
          suffix: '\n}\n',
        );
        
        // Test several visible positions
        final testPositions = [
          const LspPosition(line: 0, character: 0),
          const LspPosition(line: 0, character: 10),
          const LspPosition(line: 1, character: 5),
        ];
        
        for (final visiblePos in testPositions) {
          final fullPos = doc.toFullPosition(visiblePos);
          final backToVisible = doc.toVisiblePosition(fullPos);
          
          expect(backToVisible, equals(visiblePos),
            reason: 'Round-trip failed: visible $visiblePos -> full $fullPos -> $backToVisible');
        }
      });
    });
  });
  
  group('Hover tooltip with VirtualDocument', () {
    testWidgets('hover source receives correctly mapped position', (tester) async {
      ensureStateInitialized();
      
      // Track what position the hover source receives
      int? receivedPos;
      int? receivedSide;
      
      // Simulated virtual document mapping
      // Prefix: "const x = 1;\n" = 13 chars, 1 line
      // Body: "return x;" (what the editor shows)
      const prefix = 'const x = 1;\n';
      const body = 'return x;';
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        receivedPos = pos;
        receivedSide = side;
        
        // The pos should be an offset in the VISIBLE body (0-8 for "return x;")
        // NOT in the full document (which would be 13-21)
        return createTextTooltip(
          pos: pos,
          content: 'Tooltip for visible offset $pos',
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: body,  // Editor only sees the body
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
      
      // Hover over the editor
      final editorBox = tester.getRect(find.byType(EditorView));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(editorBox.left + 50, editorBox.top + 20));
      await tester.pump();
      await gesture.moveTo(Offset(editorBox.left + 60, editorBox.top + 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      // Verify the hover source was called with a visible offset
      expect(receivedPos, isNotNull, reason: 'Hover source should be called');
      expect(receivedPos, lessThan(body.length), 
        reason: 'Received pos ($receivedPos) should be within visible body length (${body.length})');
      expect(receivedPos, greaterThanOrEqualTo(0));
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('tooltip content reflects correct symbol based on mapped position', (tester) async {
      ensureStateInitialized();
      
      // Simulated scenario: prefix defines a variable, body uses it
      // If mapping is wrong, hover might show wrong symbol info
      
      // Virtual document structure:
      // prefix: "const PREFIX_VAR = 1;\n"
      // body: "const BODY_VAR = PREFIX_VAR;"
      // 
      // When hovering over "BODY_VAR" (visible chars 6-14), the LSP query
      // should ask about position in the full doc that corresponds to BODY_VAR
      
      String? lastTooltipContent;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        // Simulate looking up symbol at position
        final doc = state.doc.toString();
        
        // Find what "word" is at this position
        var wordStart = pos;
        var wordEnd = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        
        final word = doc.substring(wordStart, wordEnd);
        lastTooltipContent = 'Symbol: $word at offset $pos';
        
        return createTextTooltip(
          pos: wordStart,
          end: wordEnd,
          content: lastTooltipContent!,
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'const BODY_VAR = PREFIX_VAR;',
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
      
      // Get view state to find position of "BODY_VAR"
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      
      // "BODY_VAR" starts at offset 6
      final coordsAtBodyVar = viewState.coordsAtPos(8); // middle of BODY_VAR
      expect(coordsAtBodyVar, isNotNull, reason: 'Should get coords for position 8');
      
      // Hover at BODY_VAR position
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: coordsAtBodyVar!);
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtBodyVar.dx + 5, coordsAtBodyVar.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      // Verify tooltip shows info for BODY_VAR, not some other symbol
      expect(lastTooltipContent, isNotNull);
      expect(lastTooltipContent, contains('BODY_VAR'),
        reason: 'Tooltip should show BODY_VAR, got: $lastTooltipContent');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('REGRESSION: hovering text should not show info for different symbol', (tester) async {
      ensureStateInitialized();
      
      // This test specifically checks the bug where hovering "text" shows tooltip for "Padding"
      // The issue is position mapping between visible body and full virtual document
      
      // Simulated code:
      // const text = "hello";
      // return <Padding>{text}</Padding>;
      //
      // If user hovers over "text" on line 2, the tooltip should show "text" info
      // NOT "Padding" info
      
      String? hoveredSymbol;
      int? hoveredOffset;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        final doc = state.doc.toString();
        
        // Find word at position
        var wordStart = pos;
        var wordEnd = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        
        if (wordStart < wordEnd) {
          hoveredSymbol = doc.substring(wordStart, wordEnd);
          hoveredOffset = pos;
        }
        
        return createTextTooltip(
          pos: wordStart,
          content: 'Info for: $hoveredSymbol',
        );
      }
      
      final testCode = '''const text = "hello";
return <Padding>{text}</Padding>;''';
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: testCode,
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
      
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      
      // Find the "text" inside {text} - it's on line 2 (index 1)
      // Line 1: "return <Padding>{text}</Padding>;"
      // The "text" inside braces starts at offset 39 (after the first line + "return <Padding>{")
      final line2Start = testCode.indexOf('\n') + 1;
      final textInBracesStart = testCode.indexOf('{text}') + 1;  // +1 to skip {
      
      expect(testCode.substring(textInBracesStart, textInBracesStart + 4), equals('text'),
        reason: 'Should find "text" at computed offset');
      
      // Get coords for middle of "text"
      final coordsAtText = viewState.coordsAtPos(textInBracesStart + 2);
      expect(coordsAtText, isNotNull);
      
      // Hover at this position
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(coordsAtText!.dx, coordsAtText.dy + 5));
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtText.dx + 3, coordsAtText.dy + 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      // The critical check: hoveredSymbol should be "text", not "Padding" or anything else
      expect(hoveredSymbol, isNotNull, reason: 'Should have hovered over a symbol');
      expect(hoveredSymbol, equals('text'),
        reason: 'Hovering over "text" should identify "text", not "$hoveredSymbol" at offset $hoveredOffset');
      
      // Also verify the tooltip shows correct info
      expect(find.text('Info for: text'), findsOneWidget);
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
  });
  
  group('Template editor position mapping flow', () {
    // These tests simulate the EXACT flow in template_editor.dart:
    // 1. User hovers at visible offset in the body
    // 2. _offsetToPosition converts offset → LspPosition (in visible body)
    // 3. vdoc.toFullPosition maps to full document position
    // 4. LSP query returns info for symbol at that position
    // 5. The result should correspond to the symbol at the original hover position
    
    test('simulated hover flow maps position correctly for simple prefix', () {
      // Template editor scenario:
      // prefix: "interface Props {}\nfunction Template() {\n"  (2 lines)
      // body: "  return <Padding>hello</Padding>;"
      // suffix: "\n}"
      
      const prefix = 'interface Props {}\nfunction Template() {\n';
      const body = '  return <Padding>hello</Padding>;';
      const suffix = '\n}';
      
      final vdoc = VirtualDocument(prefix: prefix, body: body, suffix: suffix);
      
      // User hovers over "Padding" - it starts at offset 10 in the body
      // body: "  return <Padding>hello</Padding>;"
      //        0123456789^
      const hoverOffset = 10;  // Start of "Padding"
      
      // Step 1: Convert offset to position in visible body
      final visiblePos = _offsetToPosition(body, hoverOffset);
      expect(visiblePos.line, equals(0));
      expect(visiblePos.character, equals(10));
      
      // Step 2: Map to full document position
      final fullPos = vdoc.toFullPosition(visiblePos);
      expect(fullPos.line, equals(2));  // prefix has 2 lines (indices 0, 1), body starts at line 2
      expect(fullPos.character, equals(10));
      
      // Step 3: Verify the character at that position in full doc is correct
      final fullContent = vdoc.fullContent;
      final fullOffset = fullContent.lspPositionToOffset(fullPos);
      
      // The character at fullOffset should be 'P' (start of "Padding")
      expect(fullContent[fullOffset], equals('P'));
      
      // And extracting from there should give us "Padding"
      expect(fullContent.substring(fullOffset, fullOffset + 7), equals('Padding'));
    });
    
    test('simulated hover flow for multi-line body', () {
      const prefix = 'const x = 1;\n';  // 1 line
      const body = 'const text = "hello";\nreturn <Padding>{text}</Padding>;';
      const suffix = '';
      
      final vdoc = VirtualDocument(prefix: prefix, body: body, suffix: suffix);
      
      // User hovers over "text" in {text} on line 2 of body
      // Line 0: 'const text = "hello";'
      // Line 1: 'return <Padding>{text}</Padding>;'
      //                           ^-- offset in line 1 = 17
      
      // Find "text" in braces on line 1
      final line1Start = body.indexOf('\n') + 1;
      final textInBracesOffset = body.indexOf('{text}') + 1;  // +1 to skip {
      
      expect(body.substring(textInBracesOffset, textInBracesOffset + 4), equals('text'));
      
      // Convert to visible position
      final visiblePos = _offsetToPosition(body, textInBracesOffset);
      expect(visiblePos.line, equals(1));  // Second line of body
      expect(visiblePos.character, equals(textInBracesOffset - line1Start));
      
      // Map to full position
      final fullPos = vdoc.toFullPosition(visiblePos);
      expect(fullPos.line, equals(2));  // prefix has 1 line ending with \n, body line 1 = full line 2
      
      // Verify in full content
      final fullContent = vdoc.fullContent;
      final fullOffset = fullContent.lspPositionToOffset(fullPos);
      expect(fullContent.substring(fullOffset, fullOffset + 4), equals('text'));
    });
    
    test('CRITICAL: hover at body offset X should query full doc at correct mapped position', () {
      // This is the critical test - simulating the exact bug scenario
      // When hovering over "text", we should NOT accidentally query "Padding"
      
      const prefix = '''interface Props { name: string; }
interface TemplateProps extends Props {}
function Template(props: TemplateProps) {
''';
      const body = '''  const text = props.name;
  return <Padding>{text}</Padding>;''';
      const suffix = '\n}\n';
      
      final vdoc = VirtualDocument(prefix: prefix, body: body, suffix: suffix);
      
      // Verify prefix structure
      final prefixLines = prefix.split('\n');
      expect(prefixLines.length, equals(4));  // 3 lines + trailing empty from \n
      expect(vdoc.bodyStartLine, equals(3));
      
      // Now simulate hovering over different symbols in the body
      
      // Test 1: Hover over "const" at start of body
      {
        const hoverOffset = 2;  // "  const" - the 'c' is at offset 2
        final visiblePos = _offsetToPosition(body, hoverOffset);
        final fullPos = vdoc.toFullPosition(visiblePos);
        final fullOffset = vdoc.fullContent.lspPositionToOffset(fullPos);
        
        expect(vdoc.fullContent.substring(fullOffset, fullOffset + 5), equals('const'),
          reason: 'Hovering at body offset 2 should find "const"');
      }
      
      // Test 2: Hover over "text" variable declaration
      {
        final textDeclOffset = body.indexOf('text');  // First occurrence
        final visiblePos = _offsetToPosition(body, textDeclOffset);
        final fullPos = vdoc.toFullPosition(visiblePos);
        final fullOffset = vdoc.fullContent.lspPositionToOffset(fullPos);
        
        expect(vdoc.fullContent.substring(fullOffset, fullOffset + 4), equals('text'),
          reason: 'Hovering over "text" declaration should find "text"');
      }
      
      // Test 3: Hover over "Padding" 
      {
        final paddingOffset = body.indexOf('Padding');
        final visiblePos = _offsetToPosition(body, paddingOffset);
        final fullPos = vdoc.toFullPosition(visiblePos);
        final fullOffset = vdoc.fullContent.lspPositionToOffset(fullPos);
        
        expect(vdoc.fullContent.substring(fullOffset, fullOffset + 7), equals('Padding'),
          reason: 'Hovering over "Padding" should find "Padding"');
      }
      
      // Test 4: Hover over "text" inside {text}
      {
        final textInBracesOffset = body.indexOf('{text}') + 1;
        final visiblePos = _offsetToPosition(body, textInBracesOffset);
        final fullPos = vdoc.toFullPosition(visiblePos);
        final fullOffset = vdoc.fullContent.lspPositionToOffset(fullPos);
        
        expect(vdoc.fullContent.substring(fullOffset, fullOffset + 4), equals('text'),
          reason: 'Hovering over "text" in braces should find "text", NOT Padding');
      }
    });
    
    test('position mapping is consistent across all body offsets', () {
      const prefix = 'const a = 1;\nconst b = 2;\n';
      const body = 'return a + b;';
      const suffix = '';
      
      final vdoc = VirtualDocument(prefix: prefix, body: body, suffix: suffix);
      
      // For every offset in the body, verify the round-trip mapping
      for (var offset = 0; offset <= body.length; offset++) {
        final visiblePos = _offsetToPosition(body, offset);
        final fullPos = vdoc.toFullPosition(visiblePos);
        final visiblePosBack = vdoc.toVisiblePosition(fullPos);
        
        expect(visiblePosBack, isNotNull, 
          reason: 'Position at offset $offset should map back to visible');
        expect(visiblePosBack, equals(visiblePos),
          reason: 'Round-trip should preserve position for offset $offset');
        
        // Also verify the character at that position matches
        if (offset < body.length) {
          final fullOffset = vdoc.fullContent.lspPositionToOffset(fullPos);
          expect(vdoc.fullContent[fullOffset], equals(body[offset]),
            reason: 'Character at offset $offset should match after mapping');
        }
      }
    });
  });
  
  group('Tooltip positioning with VirtualDocument', () {
    testWidgets('tooltip appears at correct Y position for multi-line content', (tester) async {
      ensureStateInitialized();
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('multiline-test-tooltip'),
              width: 100,
              height: 50,
              color: Colors.blue,
              child: const Text('TEST'),
            ),
          ),
        );
      }
      
      // Multi-line content
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'line 0\nline 1\nline 2\nline 3',
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
      
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      final lineHeight = viewState.lineHeight;
      
      // Hover over line 2
      final line2Start = 'line 0\nline 1\n'.length;
      final coordsAtLine2 = viewState.coordsAtPos(line2Start + 3);
      expect(coordsAtLine2, isNotNull);
      
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(coordsAtLine2!.dx, coordsAtLine2.dy + lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtLine2.dx + 5, coordsAtLine2.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      final tooltipFinder = find.byKey(const Key('multiline-test-tooltip'));
      expect(tooltipFinder, findsOneWidget);
      
      final tooltipBox = tester.getRect(tooltipFinder);
      
      // Tooltip should be below line 2 (not at top of editor)
      // Line 2 is at coordsAtLine2.dy, tooltip should be below that
      expect(tooltipBox.top, greaterThan(coordsAtLine2.dy),
        reason: 'Tooltip top (${tooltipBox.top}) should be below line Y (${coordsAtLine2.dy})');
      
      // But not too far below (within 2 line heights + padding)
      expect(tooltipBox.top, lessThan(coordsAtLine2.dy + lineHeight * 3),
        reason: 'Tooltip should be close to hovered line');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('tooltip X position matches the symbol start position', (tester) async {
      ensureStateInitialized();
      
      int? symbolStart;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        final doc = state.doc.toString();
        
        // Find word start
        var wordStart = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        
        symbolStart = wordStart;
        
        return HoverTooltip(
          pos: wordStart,  // Anchor at word start
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('x-pos-tooltip'),
              width: 100,
              height: 50,
              color: Colors.green,
              child: const Text('TEST'),
            ),
          ),
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'const myVariable = 42;',
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
      
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      
      // Hover over "myVariable" (starts at offset 6)
      final myVarStart = 6;
      final coordsAtMiddle = viewState.coordsAtPos(myVarStart + 5);  // middle of word
      expect(coordsAtMiddle, isNotNull);
      
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: coordsAtMiddle!);
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtMiddle.dx + 5, coordsAtMiddle.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      
      expect(symbolStart, equals(myVarStart), 
        reason: 'Symbol start should be at myVariable start');
      
      final tooltipFinder = find.byKey(const Key('x-pos-tooltip'));
      expect(tooltipFinder, findsOneWidget);
      
      final tooltipBox = tester.getRect(tooltipFinder);
      
      // Get the expected X position (start of "myVariable")
      final coordsAtWordStart = viewState.coordsAtPos(myVarStart);
      expect(coordsAtWordStart, isNotNull);
      
      // Tooltip left should be near the word start position
      // Allow some tolerance for padding
      expect((tooltipBox.left - coordsAtWordStart!.dx).abs(), lessThan(20),
        reason: 'Tooltip left (${tooltipBox.left}) should be near word start X (${coordsAtWordStart.dx})');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
  });
  
  group('REGRESSION: Hover position calculation bugs', () {
    testWidgets('hover calculates correct document position from mouse coords', (tester) async {
      ensureStateInitialized();
      
      // Track what position the hover system calculates
      int? calculatedPos;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        calculatedPos = pos;
        return HoverTooltip(
          pos: pos,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('position-test-tooltip'),
              padding: const EdgeInsets.all(8),
              color: Colors.blue,
              child: Text('Pos: $pos'),
            ),
          ),
        );
      }
      
      // Simple single-line content for easier debugging
      const doc = 'const myVariable = 42;';
      //           0123456789...
      //           "const" starts at 0, "myVariable" starts at 6
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
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
      
      // Get coordinates for specific positions
      final coordsAt0 = viewState.coordsAtPos(0);   // Start of "const"
      final coordsAt6 = viewState.coordsAtPos(6);   // Start of "myVariable"
      final coordsAt10 = viewState.coordsAtPos(10); // Middle of "myVariable"
      
      expect(coordsAt0, isNotNull);
      expect(coordsAt6, isNotNull);
      expect(coordsAt10, isNotNull);
      
      // Debug: print the coordinates
      // ignore: avoid_print
      print('coordsAt0: $coordsAt0');
      // ignore: avoid_print
      print('coordsAt6: $coordsAt6');
      // ignore: avoid_print
      print('coordsAt10: $coordsAt10');
      
      // Hover exactly at position 10 (middle of "myVariable")
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: coordsAt10!);
      await tester.pump();
      await gesture.moveTo(Offset(coordsAt10.dx + 2, coordsAt10.dy + 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      expect(calculatedPos, isNotNull, reason: 'Hover should have calculated a position');
      // ignore: avoid_print
      print('Hovered at coordsAt10, calculated pos: $calculatedPos');
      
      // The calculated position should be close to 10 (within the word "myVariable" which is 6-16)
      expect(calculatedPos, greaterThanOrEqualTo(6), 
        reason: 'Position should be >= 6 (start of myVariable)');
      expect(calculatedPos, lessThanOrEqualTo(16),
        reason: 'Position should be <= 16 (end of myVariable)');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('BUG REPRO: hovering line 3 shows wrong symbol (offset by ~100px)', (tester) async {
      ensureStateInitialized();
      
      // This reproduces the user's bug: hovering "center" on line 3 shows "column" info
      // Suggests the X coordinate calculation is wrong
      
      int? calculatedPos;
      String? symbolAtPos;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        calculatedPos = pos;
        final doc = state.doc.toString();
        
        // Find word at position
        var wordStart = pos;
        var wordEnd = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        
        if (wordStart < wordEnd) {
          symbolAtPos = doc.substring(wordStart, wordEnd);
        }
        
        return HoverTooltip(
          pos: wordStart,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('symbol-tooltip'),
              padding: const EdgeInsets.all(8),
              color: Colors.blue,
              child: Text('Symbol: $symbolAtPos'),
            ),
          ),
        );
      }
      
      // Multi-line content similar to the template editor
      const doc = '''const column = 1;
const row = 2;
const center = 3;
const right = 4;''';
      
      // Line 0: "const column = 1;" (17 chars + newline = 18)
      // Line 1: "const row = 2;" (14 chars + newline = 15)
      // Line 2: "const center = 3;" - "center" starts at offset 18+15+6 = 39
      // Line 3: "const right = 4;"
      
      final centerOffset = doc.indexOf('center');
      expect(doc.substring(centerOffset, centerOffset + 6), equals('center'));
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
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
      final lineHeight = viewState.lineHeight;
      
      // Get coordinates for "center" (middle of the word)
      final coordsAtCenter = viewState.coordsAtPos(centerOffset + 3);
      expect(coordsAtCenter, isNotNull);
      
      // Also get coords for "column" to compare
      final columnOffset = doc.indexOf('column');
      final coordsAtColumn = viewState.coordsAtPos(columnOffset + 3);
      expect(coordsAtColumn, isNotNull);
      
      // Debug output
      // ignore: avoid_print
      print('centerOffset: $centerOffset, coords: $coordsAtCenter');
      // ignore: avoid_print  
      print('columnOffset: $columnOffset, coords: $coordsAtColumn');
      // ignore: avoid_print
      print('lineHeight: $lineHeight');
      
      // The Y coordinates should be different (center is on line 2, column is on line 0)
      expect((coordsAtCenter!.dy - coordsAtColumn!.dy).abs(), greaterThan(lineHeight),
        reason: 'center and column should be on different lines');
      
      // Now hover at the center position
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(coordsAtCenter.dx, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtCenter.dx + 2, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      // ignore: avoid_print
      print('After hovering at center coords:');
      // ignore: avoid_print
      print('  calculatedPos: $calculatedPos');
      // ignore: avoid_print
      print('  symbolAtPos: $symbolAtPos');
      
      // THE BUG: This should be "center" but might incorrectly be "column"
      expect(symbolAtPos, isNotNull, reason: 'Should have found a symbol');
      expect(symbolAtPos, equals('center'),
        reason: 'Hovering over "center" should identify "center", not "$symbolAtPos". '
                'calculatedPos=$calculatedPos, centerOffset=$centerOffset');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('BUG REPRO: hover with line numbers enabled', (tester) async {
      ensureStateInitialized();
      
      // This tests hover when line numbers gutter is present
      // The gutter adds width that might not be accounted for in position calculation
      
      int? calculatedPos;
      String? symbolAtPos;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        calculatedPos = pos;
        final doc = state.doc.toString();
        
        var wordStart = pos;
        var wordEnd = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        
        if (wordStart < wordEnd) {
          symbolAtPos = doc.substring(wordStart, wordEnd);
        }
        
        return HoverTooltip(
          pos: wordStart,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('gutter-test-tooltip'),
              padding: const EdgeInsets.all(8),
              color: Colors.blue,
              child: Text('Symbol: $symbolAtPos'),
            ),
          ),
        );
      }
      
      const doc = '''const column = 1;
const row = 2;
const center = 3;''';
      
      final centerOffset = doc.indexOf('center');
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
          extensions: ExtensionList([
            lineNumbers(), // Add line numbers gutter!
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
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
      final lineHeight = viewState.lineHeight;
      
      // Get coordinates for "center" 
      final coordsAtCenter = viewState.coordsAtPos(centerOffset + 3);
      expect(coordsAtCenter, isNotNull);
      
      // Get coords for "column" to compare X positions
      final columnOffset = doc.indexOf('column');
      final coordsAtColumn = viewState.coordsAtPos(columnOffset + 3);
      
      // ignore: avoid_print
      print('WITH LINE NUMBERS:');
      // ignore: avoid_print
      print('  centerOffset: $centerOffset, coords: $coordsAtCenter');
      // ignore: avoid_print  
      print('  columnOffset: $columnOffset, coords: $coordsAtColumn');
      
      // "center" and "column" have the same X offset within their lines (after "const ")
      // So their X coordinates should be similar
      expect((coordsAtCenter!.dx - coordsAtColumn!.dx).abs(), lessThan(10),
        reason: 'center and column should have similar X coords (both start after "const ")');
      
      // Now hover at the center position
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(coordsAtCenter.dx, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtCenter.dx + 2, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      // ignore: avoid_print
      print('  calculatedPos: $calculatedPos, symbolAtPos: $symbolAtPos');
      
      expect(symbolAtPos, equals('center'),
        reason: 'With line numbers: hovering "center" should identify "center", not "$symbolAtPos"');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('BUG REPRO: verify posAtCoords returns correct position for hover location', (tester) async {
      ensureStateInitialized();
      
      // This test directly verifies posAtCoords accuracy
      // The user's bug: hovering "center" on line 3 shows "column" (line 1)
      // This could happen if posAtCoords is calculating wrong Y -> wrong line
      
      const doc = '''const column = 1;
const row = 2;
const center = 3;
const right = 4;''';
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
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
      final lineHeight = viewState.lineHeight;
      
      // Test posAtCoords accuracy for each symbol
      final symbols = ['column', 'row', 'center', 'right'];
      
      for (final symbol in symbols) {
        final expectedOffset = doc.indexOf(symbol);
        final coords = viewState.coordsAtPos(expectedOffset + 2); // middle of word
        expect(coords, isNotNull, reason: 'Should get coords for $symbol');
        
        // Now use posAtCoords to go back from coords to position
        final calculatedPos = viewState.posAtCoords(coords!);
        expect(calculatedPos, isNotNull, reason: 'posAtCoords should return position for $symbol');
        
        // The calculated position should be within the word
        final symbolStart = doc.indexOf(symbol);
        final symbolEnd = symbolStart + symbol.length;
        
        // ignore: avoid_print
        print('$symbol: expectedOffset=$expectedOffset, coords=$coords, calculatedPos=$calculatedPos, range=[$symbolStart, $symbolEnd]');
        
        expect(calculatedPos, greaterThanOrEqualTo(symbolStart),
          reason: 'posAtCoords for $symbol should be >= $symbolStart, got $calculatedPos');
        expect(calculatedPos, lessThanOrEqualTo(symbolEnd),
          reason: 'posAtCoords for $symbol should be <= $symbolEnd, got $calculatedPos');
        
        // Get the word at calculated position
        var wordStart = calculatedPos!;
        var wordEnd = calculatedPos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        final foundWord = doc.substring(wordStart, wordEnd);
        
        expect(foundWord, equals(symbol),
          reason: 'Word at posAtCoords($coords) should be "$symbol", not "$foundWord"');
      }
    });
    
    testWidgets('BUG REPRO: template editor-like setup with all extensions', (tester) async {
      ensureStateInitialized();
      ensureLanguageInitialized();
      ensureFoldInitialized();
      ensureLintInitialized();
      
      // Mimic template editor setup as closely as possible
      int? calculatedPos;
      String? symbolAtPos;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        calculatedPos = pos;
        final doc = state.doc.toString();
        
        var wordStart = pos;
        var wordEnd = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        
        if (wordStart < wordEnd) {
          symbolAtPos = doc.substring(wordStart, wordEnd);
        }
        
        return HoverTooltip(
          pos: wordStart,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('template-test-tooltip'),
              padding: const EdgeInsets.all(8),
              color: Colors.blue,
              child: Text('Symbol: $symbolAtPos'),
            ),
          ),
        );
      }
      
      // Realistic JSX-like content
      const doc = '''const column = 1;
const row = 2;
const center = 3;
return <Column>{center}</Column>;''';
      
      final centerOffset = doc.indexOf('center');
      final columnOffset = doc.indexOf('column');
      
      // Get JavaScript language support like template editor
      final langSupport = javascript(const JavaScriptConfig(jsx: true));
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
          extensions: ExtensionList([
            // Same extensions as template editor
            langSupport.extension,
            syntaxHighlighting(defaultHighlightStyle),
            lineNumbers(),
            highlightActiveLine(),
            highlightActiveLineGutter(),
            foldGutter(),
            bracketMatching(),
            closeBrackets(),
            search(),
            history(),
            autocompletion(),
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
            lintGutter(),
          ]),
        ),
      );
      
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox.expand( // Match template editor's SizedBox.expand
            child: EditorView(
              state: state,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: ['Monaco', 'Menlo', 'Consolas', 'monospace'],
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      final lineHeight = viewState.lineHeight;
      
      // Get coordinates for "center" and "column"
      final coordsAtCenter = viewState.coordsAtPos(centerOffset + 3);
      final coordsAtColumn = viewState.coordsAtPos(columnOffset + 3);
      
      expect(coordsAtCenter, isNotNull);
      expect(coordsAtColumn, isNotNull);
      
      // ignore: avoid_print
      print('TEMPLATE EDITOR-LIKE SETUP:');
      // ignore: avoid_print
      print('  lineHeight: $lineHeight');
      // ignore: avoid_print
      print('  centerOffset: $centerOffset, coords: $coordsAtCenter');
      // ignore: avoid_print
      print('  columnOffset: $columnOffset, coords: $coordsAtColumn');
      
      // Verify they're on different lines
      expect((coordsAtCenter!.dy - coordsAtColumn!.dy).abs(), greaterThan(lineHeight * 1.5),
        reason: 'center (line 2) and column (line 0) should be at least 2 lines apart');
      
      // Hover at center
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(coordsAtCenter.dx, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtCenter.dx + 2, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      // ignore: avoid_print
      print('  After hovering:');
      // ignore: avoid_print
      print('    calculatedPos: $calculatedPos');
      // ignore: avoid_print
      print('    symbolAtPos: $symbolAtPos');
      
      expect(symbolAtPos, equals('center'),
        reason: 'With template editor extensions: hovering "center" should identify "center", not "$symbolAtPos"');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('BUG REPRO: editor inside nested containers with transforms', (tester) async {
      ensureStateInitialized();
      
      // Test if nested containers with padding/margins cause offset issues
      int? calculatedPos;
      String? symbolAtPos;
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        calculatedPos = pos;
        final doc = state.doc.toString();
        
        var wordStart = pos;
        var wordEnd = pos;
        while (wordStart > 0 && _isIdentifier(doc[wordStart - 1])) wordStart--;
        while (wordEnd < doc.length && _isIdentifier(doc[wordEnd])) wordEnd++;
        
        if (wordStart < wordEnd) {
          symbolAtPos = doc.substring(wordStart, wordEnd);
        }
        
        return HoverTooltip(
          pos: wordStart,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('nested-test-tooltip'),
              padding: const EdgeInsets.all(8),
              color: Colors.blue,
              child: Text('Symbol: $symbolAtPos'),
            ),
          ),
        );
      }
      
      const doc = '''const column = 1;
const row = 2;
const center = 3;''';
      
      final centerOffset = doc.indexOf('center');
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: doc,
          extensions: ExtensionList([
            lineNumbers(),
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
          ]),
        ),
      );
      
      // Simulate nested widget tree like in a real app with sidebars, panels, etc.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              // Sidebar taking some width
              Container(
                width: 200,
                color: Colors.grey,
                child: const Center(child: Text('Sidebar')),
              ),
              // Main content area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        height: 50,
                        color: Colors.blue,
                        child: const Center(child: Text('Header')),
                      ),
                      // Editor
                      Expanded(
                        child: EditorView(state: state),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      
      final viewState = tester.state<EditorViewState>(find.byType(EditorView));
      final lineHeight = viewState.lineHeight;
      
      // Get coordinates for "center"
      final coordsAtCenter = viewState.coordsAtPos(centerOffset + 3);
      expect(coordsAtCenter, isNotNull);
      
      // ignore: avoid_print
      print('NESTED CONTAINERS:');
      // ignore: avoid_print
      print('  centerOffset: $centerOffset, coords: $coordsAtCenter');
      
      // Hover at center position
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset(coordsAtCenter!.dx, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtCenter.dx + 2, coordsAtCenter.dy + lineHeight / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      // ignore: avoid_print
      print('  calculatedPos: $calculatedPos, symbolAtPos: $symbolAtPos');
      
      expect(symbolAtPos, equals('center'),
        reason: 'With nested containers: hovering "center" should identify "center", not "$symbolAtPos"');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
    
    testWidgets('tooltip appears at hover location, not offset by 100px', (tester) async {
      ensureStateInitialized();
      
      HoverTooltip? hoverSource(EditorState state, int pos, int side) {
        return HoverTooltip(
          pos: pos,
          create: (context) => TooltipView(
            widget: Container(
              key: const Key('offset-test-tooltip'),
              width: 80,
              height: 30,
              color: Colors.red,
              child: const Text('TIP'),
            ),
          ),
        );
      }
      
      final state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world test',
          extensions: ExtensionList([
            hoverTooltip(hoverSource, const HoverTooltipOptions(hoverTime: 10)),
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
      
      // Hover at "world" (offset 6)
      final coordsAtWorld = viewState.coordsAtPos(6);
      expect(coordsAtWorld, isNotNull);
      
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: coordsAtWorld!);
      await tester.pump();
      await gesture.moveTo(Offset(coordsAtWorld.dx + 5, coordsAtWorld.dy + 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      
      final tooltipFinder = find.byKey(const Key('offset-test-tooltip'));
      expect(tooltipFinder, findsOneWidget);
      
      final tooltipBox = tester.getRect(tooltipFinder);
      
      // ignore: avoid_print
      print('Hover coords: $coordsAtWorld');
      // ignore: avoid_print
      print('Tooltip box: $tooltipBox');
      
      // The tooltip's left edge should be within 50px of the hover X position
      // (allowing for some positioning adjustments, but NOT 100px off)
      final xDifference = (tooltipBox.left - coordsAtWorld.dx).abs();
      expect(xDifference, lessThan(50),
        reason: 'Tooltip left (${tooltipBox.left}) should be within 50px of hover X (${coordsAtWorld.dx}), '
                'but difference is $xDifference');
      
      await gesture.removePointer();
      await tester.pumpAndSettle();
    });
  });
}

bool _isIdentifier(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||  // A-Z
      (code >= 97 && code <= 122) ||    // a-z
      (code >= 48 && code <= 57) ||     // 0-9
      char == '_' ||
      char == r'$';
}

/// Simulates the template editor's LSP hover flow:
/// 1. User hovers at visible offset
/// 2. Convert offset → visible position (line/char)
/// 3. VirtualDocument maps visible position → full position
/// 4. LSP query at full position
/// 5. Result displayed at original visible offset
///
/// This helper mimics `_offsetToPosition` from template_editor.dart
LspPosition _offsetToPosition(String doc, int offset) {
  var line = 0;
  var character = 0;
  for (var i = 0; i < offset && i < doc.length; i++) {
    if (doc[i] == '\n') {
      line++;
      character = 0;
    } else {
      character++;
    }
  }
  return LspPosition(line: line, character: character);
}

/// Simulates `_positionToOffset` from template_editor.dart
int _positionToOffset(String doc, LspPosition position) {
  var offset = 0;
  var line = 0;
  while (line < position.line && offset < doc.length) {
    if (doc[offset] == '\n') line++;
    offset++;
  }
  return (offset + position.character).clamp(0, doc.length);
}
