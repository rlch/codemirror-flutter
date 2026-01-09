import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart';

/// Test Enter key behavior at every position in the user's template
void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  const templateContent = '''const x = 2

return (
  <Padding padding={EdgeInsetsGeometry.all({ value: 24 })}>
    <Center>
      <Column mainAxisAlignment="center" crossAxisAlignment="center">
        <Text.h1>New Template</Text.h1>
        <SizedBox height={16} />
        <Text>
          Add properties in the sidebar, then use them here like {"{propertyName}"}
        </Text>
      </Column>
    </Center>
  </Padding>
);''';

  group('Enter key comprehensive tests with user template', () {
    test('document structure is correct', () {
      final lines = templateContent.split('\n');
      print('Template has ${lines.length} lines:');
      for (var i = 0; i < lines.length; i++) {
        print('Line ${i + 1}: "${lines[i]}"');
      }
      expect(lines.length, equals(15));
    });

    test('Enter at end of each line', () {
      final lines = templateContent.split('\n');
      final failures = <String>[];
      
      for (var lineIdx = 0; lineIdx < lines.length - 1; lineIdx++) {
        final lineNum = lineIdx + 1;
        
        // Calculate position at end of this line
        var pos = 0;
        for (var i = 0; i <= lineIdx; i++) {
          pos += lines[i].length;
          if (i < lineIdx) pos += 1; // newline
        }
        
        print('\n=== Testing Enter at end of line $lineNum ===');
        print('Line content: "${lines[lineIdx]}"');
        print('Position: $pos');
        
        // Create fresh state for each test - use JSX mode for JSX content
        final state = EditorState.create(EditorStateConfig(
          doc: templateContent,
          extensions: ExtensionList([
            javascript(const JavaScriptConfig(jsx: true)).extension,
            keymap.of(standardKeymap),
          ]),
        ));
        
        // Position cursor at end of line
        final stateWithCursor = state.update([
          TransactionSpec(selection: EditorSelection.single(pos)),
        ]).state as EditorState;
        
        // Verify cursor position
        final cursorLine = stateWithCursor.doc.lineAt(pos);
        print('Cursor on line: ${cursorLine.number} (expected: $lineNum)');
        
        // Press Enter using record syntax
        Transaction? result;
        final target = (
          state: stateWithCursor,
          dispatch: (Transaction tr) {
            result = tr;
          },
        );
        final handled = insertNewlineAndIndent(target);
        
        if (!handled || result == null) {
          failures.add('Line $lineNum: Enter not handled');
          continue;
        }
        
        final newDoc = result!.newDoc;
        final newSelection = result!.newSelection;
        final newCursorPos = newSelection.main.head;
        final newCursorLine = newDoc.lineAt(newCursorPos);
        
        print('After Enter:');
        print('  New cursor position: $newCursorPos');
        print('  New cursor line: ${newCursorLine.number}');
        print('  Expected line: ${lineNum + 1}');
        
        // Check what indent was computed
        final computedIndent = getIndentation(stateWithCursor, pos);
        print('  Computed indent at pos $pos: $computedIndent');
        
        // Print context around cursor
        final newLines = newDoc.toString().split('\n');
        print('  Lines around cursor:');
        for (var i = (newCursorLine.number - 2).clamp(0, newLines.length - 1); 
             i <= (newCursorLine.number).clamp(0, newLines.length - 1); i++) {
          final marker = i == newCursorLine.number - 1 ? ' <-- cursor' : '';
          print('    Line ${i + 1}: "${newLines[i]}"$marker');
        }
        
        // The new line should have proper indentation
        final newLineContent = newLines[newCursorLine.number - 1];
        final cursorOffsetInLine = newCursorPos - newCursorLine.from;
        print('  New line content: "$newLineContent"');
        print('  Cursor offset in new line: $cursorOffsetInLine');
        
        // Cursor should be on the NEXT line
        if (newCursorLine.number != lineNum + 1) {
          failures.add(
            'Line $lineNum: After Enter, cursor should be on line ${lineNum + 1}, '
            'but was on line ${newCursorLine.number}'
          );
        }
        
        // If computed indent was non-null, cursor should be at that indent
        if (computedIndent != null && computedIndent > 0 && cursorOffsetInLine == 0) {
          failures.add(
            'Line $lineNum: Cursor has no indent but computed indent was $computedIndent'
          );
        }
      }
      
      if (failures.isNotEmpty) {
        print('\n\n=== FAILURES ===');
        for (final f in failures) {
          print('  - $f');
        }
        fail('${failures.length} lines failed:\n${failures.join('\n')}');
      }
    });

    test('Enter at end of line 6 (Padding line) - specific repro', () {
      // Line 6 is: "      <Column ...>"
      final state = EditorState.create(EditorStateConfig(
        doc: templateContent,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
          keymap.of(standardKeymap),
        ]),
      ));
      
      final lines = templateContent.split('\n');
      print('Line 6: "${lines[5]}"');
      
      // Calculate position at end of line 6
      var pos = 0;
      for (var i = 0; i < 6; i++) {
        pos += lines[i].length;
        if (i < 5) pos += 1; // newline between lines
      }
      print('End of line 6 position: $pos');
      print('Char before: "${templateContent[pos - 1]}"');
      
      final stateWithCursor = state.update([
        TransactionSpec(selection: EditorSelection.single(pos)),
      ]).state as EditorState;
      
      // Press Enter
      Transaction? result;
      final target = (
        state: stateWithCursor,
        dispatch: (Transaction tr) {
          result = tr;
        },
      );
      insertNewlineAndIndent(target);
      
      final newDoc = result!.newDoc;
      final newSelection = result!.newSelection;
      final newCursorPos = newSelection.main.head;
      final newCursorLine = newDoc.lineAt(newCursorPos);
      
      print('After Enter:');
      print('  Cursor position: $newCursorPos');
      print('  Cursor line number: ${newCursorLine.number}');
      
      // Print the document
      final newLines = newDoc.toString().split('\n');
      print('\nNew document:');
      for (var i = 0; i < newLines.length; i++) {
        final marker = i == newCursorLine.number - 1 ? ' <-- CURSOR HERE' : '';
        print('  ${i + 1}: "${newLines[i]}"$marker');
      }
      
      // CRITICAL: Cursor should be on line 7, not line 8
      expect(newCursorLine.number, equals(7),
          reason: 'After Enter at end of line 6, cursor should be on line 7');
    });

    test('Enter at end of line 4 (return line) - inside parens', () {
      final state = EditorState.create(EditorStateConfig(
        doc: templateContent,
        extensions: ExtensionList([
          javascript(const JavaScriptConfig(jsx: true)).extension,
          keymap.of(standardKeymap),
        ]),
      ));
      
      final lines = templateContent.split('\n');
      print('Line 4: "${lines[3]}"'); // "return ("
      
      // Calculate position at end of line 4
      var pos = 0;
      for (var i = 0; i < 4; i++) {
        pos += lines[i].length;
        if (i < 3) pos += 1;
      }
      
      final stateWithCursor = state.update([
        TransactionSpec(selection: EditorSelection.single(pos)),
      ]).state as EditorState;
      
      Transaction? result;
      final target = (
        state: stateWithCursor,
        dispatch: (Transaction tr) {
          result = tr;
        },
      );
      insertNewlineAndIndent(target);
      
      final newDoc = result!.newDoc;
      final newSelection = result!.newSelection;
      final newCursorPos = newSelection.main.head;
      final newCursorLine = newDoc.lineAt(newCursorPos);
      
      print('After Enter at end of "return (":');
      print('  Cursor line: ${newCursorLine.number}');
      
      expect(newCursorLine.number, equals(5),
          reason: 'Cursor should be on line 5 after Enter at end of line 4');
    });
  });
}
