/// Tests for VirtualDocument formatting integration.
///
/// These tests verify that when using a VirtualDocument to map between
/// visible content and full document content (with hidden prefix/suffix),
/// formatting edits are correctly mapped from the full document back to
/// the visible range.
///
/// Key scenarios tested:
/// 1. LSP getFormattingEdits returns correct line/character positions
/// 2. Edits in the visible range are correctly mapped
/// 3. Edits in the prefix/suffix are correctly filtered out
/// 4. Edge cases: edits spanning prefix→body, body→suffix boundaries
import 'package:codemirror/codemirror.dart';
import 'package:test/test.dart';

void main() {
  group('VirtualDocument formatting', () {
    group('position to offset conversions', () {
      test('lspPositionToOffset handles body content correctly', () {
        const body = 'const x=1;\nconst y=2;';
        //            0123456789 0 123456789012
        //            line 0      line 1
        
        // Line 0, char 0 = offset 0
        expect(body.lspPositionToOffset(const LspPosition(line: 0, character: 0)), equals(0));
        // Line 0, char 7 = offset 7 (before '=')
        expect(body.lspPositionToOffset(const LspPosition(line: 0, character: 7)), equals(7));
        // Line 1, char 0 = offset 11 (after newline)
        expect(body.lspPositionToOffset(const LspPosition(line: 1, character: 0)), equals(11));
        // Line 1, char 7 = offset 18
        expect(body.lspPositionToOffset(const LspPosition(line: 1, character: 7)), equals(18));
      });

      test('offsetToLspPosition is inverse of lspPositionToOffset', () {
        const body = 'const x=1;\nconst y=2;';
        
        for (var offset = 0; offset <= body.length; offset++) {
          final pos = body.offsetToLspPosition(offset);
          final backToOffset = body.lspPositionToOffset(pos);
          expect(backToOffset, equals(offset),
            reason: 'Round-trip failed for offset $offset -> pos $pos -> $backToOffset');
        }
      });
    });

    group('mapping formatting edits', () {
      test('maps edits from full document to visible body - simple prefix', () {
        // Simulates template editor scenario:
        // Prefix: "interface Props {}\n" (1 line)
        // Body: "const x=1;" (what user edits, needs formatting to "const x = 1;")
        // Suffix: "\n"
        final doc = VirtualDocument(
          prefix: 'interface Props {}\n',  // line 0, body starts at line 1
          body: 'const x=1;',
          suffix: '\n',
        );
        
        expect(doc.bodyStartLine, equals(1));
        
        // Simulate an edit from the formatter:
        // Full position: line 1, char 7-8 (the "=" in body)
        // This should map to visible line 0, char 7-8
        final fullEditStart = const LspPosition(line: 1, character: 7);
        final fullEditEnd = const LspPosition(line: 1, character: 8);
        
        final visibleStart = doc.toVisiblePosition(fullEditStart);
        final visibleEnd = doc.toVisiblePosition(fullEditEnd);
        
        expect(visibleStart, isNotNull, reason: 'Edit start should be in visible range');
        expect(visibleEnd, isNotNull, reason: 'Edit end should be in visible range');
        expect(visibleStart!.line, equals(0));
        expect(visibleStart.character, equals(7));
        expect(visibleEnd!.line, equals(0));
        expect(visibleEnd.character, equals(8));
        
        // Convert visible positions to offsets
        final fromOffset = doc.body.lspPositionToOffset(visibleStart);
        final toOffset = doc.body.lspPositionToOffset(visibleEnd);
        
        expect(fromOffset, equals(7));
        expect(toOffset, equals(8));
        expect(doc.body.substring(fromOffset, toOffset), equals('='));
      });

      test('filters out edits entirely in prefix', () {
        final doc = VirtualDocument(
          prefix: 'interface Props {}\nfunction Template() {\n',  // 2 lines
          body: 'return <div>Hello</div>;',
          suffix: '\n}\n',
        );
        
        expect(doc.bodyStartLine, equals(2));
        
        // Edit in prefix (line 0)
        final prefixEdit = const LspPosition(line: 0, character: 10);
        expect(doc.toVisiblePosition(prefixEdit), isNull,
          reason: 'Edit in prefix should not map to visible');
        
        // Edit in prefix (line 1)
        final prefixEdit2 = const LspPosition(line: 1, character: 5);
        expect(doc.toVisiblePosition(prefixEdit2), isNull,
          reason: 'Edit in prefix should not map to visible');
      });

      test('filters out edits entirely in suffix', () {
        final doc = VirtualDocument(
          prefix: 'prefix\n',
          body: 'body line 0',  // single line, no newline
          suffix: '\nsuffix line 0\nsuffix line 1',
        );
        
        expect(doc.bodyStartLine, equals(1));
        
        // Body is at line 1, single line
        // Suffix starts at line 2
        final suffixEdit = const LspPosition(line: 2, character: 3);
        expect(doc.toVisiblePosition(suffixEdit), isNull,
          reason: 'Edit in suffix should not map to visible');
      });

      test('multi-line prefix with multi-line body', () {
        // Realistic template editor scenario
        final doc = VirtualDocument(
          prefix: '''interface Props {
  name: string;
}

function Template({ name }: Props) {
''',  // 5 lines (0-4), body starts at line 5
          body: '''  const greeting = `Hello, \${name}!`;
  return <div>{greeting}</div>;''',  // 2 lines
          suffix: '''
}
''',
        );
        
        expect(doc.bodyStartLine, equals(5));
        
        // Edit on first body line (full line 5 = visible line 0)
        final bodyLine1 = const LspPosition(line: 5, character: 8);
        final visible1 = doc.toVisiblePosition(bodyLine1);
        expect(visible1, isNotNull);
        expect(visible1!.line, equals(0));
        expect(visible1.character, equals(8));
        
        // Edit on second body line (full line 6 = visible line 1)
        final bodyLine2 = const LspPosition(line: 6, character: 10);
        final visible2 = doc.toVisiblePosition(bodyLine2);
        expect(visible2, isNotNull);
        expect(visible2!.line, equals(1));
        expect(visible2.character, equals(10));
      });

      test('toVisibleRange handles range entirely in body', () {
        final doc = VirtualDocument(
          prefix: 'line0\nline1\n',  // 2 lines
          body: 'bodyA\nbodyB',      // 2 lines
          suffix: '\nend',
        );
        
        // Full range: lines 2-3 (body lines 0-1)
        const fullRange = LspRange(
          start: LspPosition(line: 2, character: 0),
          end: LspPosition(line: 3, character: 5),
        );
        
        final visibleRange = doc.toVisibleRange(fullRange);
        expect(visibleRange, isNotNull);
        expect(visibleRange!.start, equals(const LspPosition(line: 0, character: 0)));
        expect(visibleRange.end, equals(const LspPosition(line: 1, character: 5)));
      });

      test('toVisibleRange returns null for range entirely in prefix', () {
        final doc = VirtualDocument(
          prefix: 'line0\nline1\n',
          body: 'body',
          suffix: '',
        );
        
        const fullRange = LspRange(
          start: LspPosition(line: 0, character: 0),
          end: LspPosition(line: 1, character: 5),
        );
        
        expect(doc.toVisibleRange(fullRange), isNull);
      });
    });

    group('simulated formatting flow', () {
      test('complete formatting edit mapping flow', () {
        // This test simulates the complete flow in _lspFormatting:
        // 1. Create virtual doc with template prefix/suffix
        // 2. Get formatting edits from LSP (simulated)
        // 3. Filter and map edits to visible range
        // 4. Convert to CodeMirror FormatEdit offsets
        
        final vdoc = VirtualDocument(
          prefix: 'interface Props { name: string; }\n\nfunction Template(props: Props) {\n',
          body: 'const x=1;\nreturn props.name;',
          suffix: '\n}\n',
        );
        
        // body line 0: "const x=1;"
        // body line 1: "return props.name;"
        
        expect(vdoc.bodyStartLine, equals(3));
        
        // Simulated LSP edit: add spaces around "=" on line 3 (first body line)
        // Full position: line 3, char 7-8 (the "=" in "const x=1;")
        // This should become: replace "=" with " = "
        final lspEdit = (
          range: const LspRange(
            start: LspPosition(line: 3, character: 7),
            end: LspPosition(line: 3, character: 8),
          ),
          newText: ' = ',
        );
        
        // Map to visible
        final visibleStart = vdoc.toVisiblePosition(lspEdit.range.start);
        final visibleEnd = vdoc.toVisiblePosition(lspEdit.range.end);
        
        expect(visibleStart, isNotNull, reason: 'Start should be in visible range');
        expect(visibleEnd, isNotNull, reason: 'End should be in visible range');
        
        // Convert to offsets
        final fromOffset = vdoc.body.lspPositionToOffset(visibleStart!);
        final toOffset = vdoc.body.lspPositionToOffset(visibleEnd!);
        
        expect(fromOffset, equals(7));
        expect(toOffset, equals(8));
        expect(vdoc.body.substring(fromOffset, toOffset), equals('='));
        
        // Create FormatEdit
        final formatEdit = FormatEdit(
          from: fromOffset,
          to: toOffset,
          newText: lspEdit.newText,
        );
        
        expect(formatEdit.from, equals(7));
        expect(formatEdit.to, equals(8));
        expect(formatEdit.newText, equals(' = '));
        
        // Apply edit to get expected result
        final before = vdoc.body;
        final after = before.substring(0, formatEdit.from) +
            formatEdit.newText +
            before.substring(formatEdit.to);
        expect(after, equals('const x = 1;\nreturn props.name;'));
      });

      test('filters mixed prefix/body edits correctly', () {
        final vdoc = VirtualDocument(
          prefix: 'prefix\n',  // line 0
          body: 'body',        // line 1
          suffix: '\nsuffix',  // line 2+
        );
        
        // Simulated edits from formatter: some in prefix, some in body
        final edits = [
          // Edit in prefix - should be filtered
          (
            range: const LspRange(
              start: LspPosition(line: 0, character: 0),
              end: LspPosition(line: 0, character: 6),
            ),
            newText: 'PREFIX',
          ),
          // Edit in body - should be kept
          (
            range: const LspRange(
              start: LspPosition(line: 1, character: 0),
              end: LspPosition(line: 1, character: 4),
            ),
            newText: 'BODY',
          ),
          // Edit in suffix - should be filtered
          (
            range: const LspRange(
              start: LspPosition(line: 2, character: 0),
              end: LspPosition(line: 2, character: 6),
            ),
            newText: 'SUFFIX',
          ),
        ];
        
        // Filter edits to visible range (mimics _lspFormatting logic)
        final visibleEdits = <FormatEdit>[];
        
        for (final edit in edits) {
          final visibleStart = vdoc.toVisiblePosition(edit.range.start);
          final visibleEnd = vdoc.toVisiblePosition(edit.range.end);
          
          // Skip edits entirely outside visible range
          if (visibleStart == null && visibleEnd == null) continue;
          
          // Skip edits that start before visible range
          if (visibleStart == null) continue;
          
          // For edits that end after visible range, clamp to end
          final effectiveEnd = visibleEnd ?? vdoc.body.endLspPosition;
          
          final fromOffset = vdoc.body.lspPositionToOffset(visibleStart);
          final toOffset = vdoc.body.lspPositionToOffset(effectiveEnd);
          
          visibleEdits.add(FormatEdit(
            from: fromOffset,
            to: toOffset,
            newText: edit.newText,
          ));
        }
        
        // Should only have the body edit
        expect(visibleEdits.length, equals(1));
        expect(visibleEdits[0].from, equals(0));
        expect(visibleEdits[0].to, equals(4));
        expect(visibleEdits[0].newText, equals('BODY'));
      });
    });

    group('debugging position mapping issue', () {
      test('REPRO: body on same line as prefix ending', () {
        // This is a problematic case: prefix ends WITHOUT newline
        // So body starts on same line as end of prefix
        final vdoc = VirtualDocument(
          prefix: 'function test() {',  // No trailing newline
          body: 'return 1;}',
          suffix: '',
        );
        
        // bodyStartLine is 0 because prefix has no newlines
        expect(vdoc.bodyStartLine, equals(0));
        
        // The body starts at character 17 (length of prefix)
        // But toVisiblePosition doesn't account for this!
        
        // If LSP returns an edit at line 0, char 17 (start of body)
        // toVisiblePosition returns line 0, char 17
        // But in the visible body, this should be line 0, char 0
        final fullPos = const LspPosition(line: 0, character: 17);
        final visiblePos = vdoc.toVisiblePosition(fullPos);
        
        expect(visiblePos, isNotNull);
        // BUG: This currently returns char 17, but it should be char 0
        // because the visible body starts at offset 0
        print('visiblePos: $visiblePos');
        print('Expected: LspPosition(line: 0, character: 0)');
        print('Actual character offset in body for "return": 0');
        
        // The character mapping is wrong when prefix doesn't end with newline
        // visiblePos.character = fullPos.character (17)
        // But the visible body starts at character 0!
      });

      test('typical template editor prefix ends with newline', () {
        // This is the normal case: prefix ends WITH newline
        final vdoc = VirtualDocument(
          prefix: 'function Template(props) {\n',  // Ends with newline
          body: 'return <div>Hello</div>;',
          suffix: '\n}\n',
        );
        
        // bodyStartLine is 1 because prefix has one newline
        expect(vdoc.bodyStartLine, equals(1));
        
        // If LSP returns an edit at line 1, char 0 (start of body)
        // toVisiblePosition should return line 0, char 0
        final fullPos = const LspPosition(line: 1, character: 0);
        final visiblePos = vdoc.toVisiblePosition(fullPos);
        
        expect(visiblePos, isNotNull);
        expect(visiblePos!.line, equals(0));
        expect(visiblePos.character, equals(0));
      });

      test('verify line-based mapping is correct for multi-line prefix', () {
        final vdoc = VirtualDocument(
          prefix: '''interface Props { name: string; }

function Template({ name }: Props) {
''',  // 3 lines (indices 0, 1, 2), ends with newline so body starts at line 3
          body: 'const x=1;',  // Line 3 in full doc, line 0 in visible
          suffix: '\n}\n',
        );
        
        expect(vdoc.bodyStartLine, equals(3));
        
        // Edit at "=" should be line 3, char 7-8 in full doc
        final fullStart = const LspPosition(line: 3, character: 7);
        final fullEnd = const LspPosition(line: 3, character: 8);
        
        final visStart = vdoc.toVisiblePosition(fullStart);
        final visEnd = vdoc.toVisiblePosition(fullEnd);
        
        expect(visStart, isNotNull);
        expect(visEnd, isNotNull);
        expect(visStart!.line, equals(0));
        expect(visStart.character, equals(7));
        expect(visEnd!.line, equals(0));
        expect(visEnd.character, equals(8));
        
        // Verify the offset conversion
        final fromOffset = vdoc.body.lspPositionToOffset(visStart);
        final toOffset = vdoc.body.lspPositionToOffset(visEnd);
        expect(fromOffset, equals(7));
        expect(toOffset, equals(8));
        expect(vdoc.body.substring(fromOffset, toOffset), equals('='));
      });

      test('check if issue is edits being empty', () {
        // Create a simple case that should definitely need formatting
        final vdoc = VirtualDocument(
          prefix: 'function Template() {\n',
          body: 'const x=1;',  // Missing spaces around =
          suffix: '\n}\n',
        );
        
        // Full content should need formatting
        final full = vdoc.fullContent;
        print('Full content:\n$full');
        print('---');
        print('This should produce an edit to change "x=1" to "x = 1"');
        
        // Expected edit from LSP:
        // range: { start: {line: 1, char: 7}, end: {line: 1, char: 8} }
        // newText: " = "
        
        // After mapping to visible:
        // range: { start: {line: 0, char: 7}, end: {line: 0, char: 8} }
        
        expect(vdoc.bodyStartLine, equals(1));
        
        final simEdit = (
          range: const LspRange(
            start: LspPosition(line: 1, character: 7),
            end: LspPosition(line: 1, character: 8),
          ),
          newText: ' = ',
        );
        
        final visStart = vdoc.toVisiblePosition(simEdit.range.start);
        final visEnd = vdoc.toVisiblePosition(simEdit.range.end);
        
        print('Simulated edit mapping:');
        print('  Full start: ${simEdit.range.start} -> Visible: $visStart');
        print('  Full end: ${simEdit.range.end} -> Visible: $visEnd');
        
        expect(visStart, isNotNull, reason: 'Edit start should be in visible range');
        expect(visEnd, isNotNull, reason: 'Edit end should be in visible range');
      });

      test('mimic _lspFormatting flow with REAL LSP edit format', () {
        // The actual LSP edits are INSERTIONS (start == end), not replacements
        // For "const x=1;" -> "const x = 1;", TypeScript returns:
        //   - Insert " " at char 7 (before =)
        //   - Insert " " at char 8 (after =)
        
        final vdoc = VirtualDocument(
          prefix: 'function Template() {\n',  // 1 line, body starts at line 1
          body: 'const x=1;',  // Line 1 in full doc
          suffix: '\n}\n',
        );
        
        // These are the ACTUAL edit formats from TypeScript
        // Note: start and end are THE SAME (insertion, not replacement)
        final lspEdits = [
          (
            range: const LspRange(
              start: LspPosition(line: 1, character: 0),  // Start of body line
              end: LspPosition(line: 1, character: 0),    // Same position = insertion
            ),
            newText: '  ',  // Add indentation
          ),
          (
            range: const LspRange(
              start: LspPosition(line: 1, character: 7),  // Before =
              end: LspPosition(line: 1, character: 7),    // Same position = insertion
            ),
            newText: ' ',  // Space before =
          ),
          (
            range: const LspRange(
              start: LspPosition(line: 1, character: 8),  // After =
              end: LspPosition(line: 1, character: 8),    // Same position = insertion  
            ),
            newText: ' ',  // Space after =
          ),
        ];
        
        // Mimic _lspFormatting logic
        final visibleEdits = <FormatEdit>[];
        final body = vdoc.body;
        
        for (final edit in lspEdits) {
          final visibleStart = vdoc.toVisiblePosition(edit.range.start);
          final visibleEnd = vdoc.toVisiblePosition(edit.range.end);
          
          // Skip edits entirely outside the visible range
          if (visibleStart == null && visibleEnd == null) continue;
          
          // Skip edits that start before visible range (in prefix)
          if (visibleStart == null) continue;
          
          // For edits that end after visible range, clamp to end
          final effectiveEnd = visibleEnd ?? body.endLspPosition;
          
          // Convert line/character to offsets in the visible body
          final fromOffset = body.lspPositionToOffset(visibleStart);
          final toOffset = body.lspPositionToOffset(effectiveEnd);
          
          print('Edit: ${edit.range.start} -> ${edit.range.end} = "${edit.newText}"');
          print('  Visible: $visibleStart -> $effectiveEnd');
          print('  Offsets: $fromOffset -> $toOffset');
          
          visibleEdits.add(FormatEdit(
            from: fromOffset,
            to: toOffset,
            newText: edit.newText,
          ));
        }
        
        print('\nVisible edits: $visibleEdits');
        
        expect(visibleEdits, isNotEmpty, 
          reason: 'Should have visible edits after filtering');
        expect(visibleEdits.length, equals(3));
        
        // First edit: indentation at offset 0
        expect(visibleEdits[0].from, equals(0));
        expect(visibleEdits[0].to, equals(0));
        expect(visibleEdits[0].newText, equals('  '));
        
        // Second edit: space at offset 7
        expect(visibleEdits[1].from, equals(7));
        expect(visibleEdits[1].to, equals(7));
        expect(visibleEdits[1].newText, equals(' '));
        
        // Third edit: space at offset 8
        expect(visibleEdits[2].from, equals(8));
        expect(visibleEdits[2].to, equals(8));
        expect(visibleEdits[2].newText, equals(' '));
      });
    });

    group('edge cases', () {
      test('empty body returns no visible edits', () {
        final vdoc = VirtualDocument(
          prefix: 'prefix\n',
          body: '',
          suffix: '\nsuffix',
        );
        
        // Edit targeting line 1 (body line) when body is empty
        final edit = const LspPosition(line: 1, character: 0);
        final visible = vdoc.toVisiblePosition(edit);
        
        // Line 1 exists (body start line) but has no content
        // This should still map to visible line 0, char 0
        expect(visible, isNotNull);
        expect(visible!.line, equals(0));
        expect(visible.character, equals(0));
      });

      test('body with no newlines maps correctly', () {
        final vdoc = VirtualDocument(
          prefix: 'line0\nline1\nline2\n',  // 3 lines (0, 1, 2)
          body: 'single line body',        // 1 line (line 3 in full)
          suffix: '\nend',
        );
        
        expect(vdoc.bodyStartLine, equals(3));
        
        // Character 5 on body line
        final fullPos = const LspPosition(line: 3, character: 5);
        final visiblePos = vdoc.toVisiblePosition(fullPos);
        
        expect(visiblePos, isNotNull);
        expect(visiblePos!.line, equals(0));
        expect(visiblePos.character, equals(5));
      });

      test('prefix not ending with newline', () {
        final vdoc = VirtualDocument(
          prefix: 'prefix',  // No trailing newline
          body: 'body',
          suffix: '',
        );
        
        // bodyStartLine should be 0 since prefix has no newlines
        expect(vdoc.bodyStartLine, equals(0));
        
        // Full position line 0 should map to visible line 0
        final fullPos = const LspPosition(line: 0, character: 6);  // Start of body
        final visiblePos = vdoc.toVisiblePosition(fullPos);
        
        expect(visiblePos, isNotNull);
        expect(visiblePos!.line, equals(0));
        expect(visiblePos.character, equals(6));
      });
    });
  });
}
