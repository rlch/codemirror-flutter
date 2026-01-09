/// Example: Column utilities for tab-aware cursor positioning
///
/// The core problem: In a text editor, character offset ≠ visual column position
/// because tabs expand to multiple columns.
///
/// Example line: "a\tb" with tabSize=4
/// - Character offsets: a=0, \t=1, b=2  (3 characters)
/// - Visual columns:    a=0, \t=1-3, b=4 (5 columns wide visually)
///
/// countColumn: Given an offset, what visual column is it?
/// findColumn: Given a visual column, what offset is it?

import 'package:codemirror/src/text/column.dart';

void main() {
  const tabSize = 4;

  // Example 1: Simple tab expansion
  print('=== Example 1: Tab expansion ===');
  const line1 = 'a\tb';
  print('Line: "a\\tb" (a, tab, b)');
  print('Character offsets: a=0, tab=1, b=2');
  print('');

  // What visual column is each character at?
  print('countColumn results:');
  print('  offset 0 → column ${countColumn(line1, tabSize, 0)}'); // 0
  print('  offset 1 → column ${countColumn(line1, tabSize, 1)}'); // 1
  print('  offset 2 → column ${countColumn(line1, tabSize, 2)}'); // 4 (tab expands to col 4)
  print('  offset 3 → column ${countColumn(line1, tabSize, 3)}'); // 5
  print('');

  // What offset is each visual column at?
  print('findColumn results:');
  print('  column 0 → offset ${findColumn(line1, 0, tabSize)}'); // 0
  print('  column 1 → offset ${findColumn(line1, 1, tabSize)}'); // 1
  print('  column 2 → offset ${findColumn(line1, 2, tabSize)}'); // 1 (still in tab)
  print('  column 3 → offset ${findColumn(line1, 3, tabSize)}'); // 1 (still in tab)
  print('  column 4 → offset ${findColumn(line1, 4, tabSize)}'); // 2 (at "b")
  print('');

  // Example 2: Code indentation
  print('=== Example 2: Code indentation ===');
  const line2 = '\t\treturn x;';
  print('Line: "\\t\\treturn x;" (2 tabs + code)');
  print('');

  final codeStart = countColumn(line2, tabSize, 2); // After 2 tabs
  print('Visual column where code starts: $codeStart'); // 8

  // If user clicks at visual column 10, where in the string is that?
  final clickOffset = findColumn(line2, 10, tabSize);
  print('Click at column 10 → offset $clickOffset'); // 4 (in "return")
  print('Character there: "${line2[clickOffset]}"');
  print('');

  // Example 3: Emoji handling
  print('=== Example 3: Emoji (grapheme clusters) ===');
  const line3 = '👨‍👩‍👧 family';
  print('Line: "👨‍👩‍👧 family"');
  print('String length (code units): ${line3.length}');
  print('Visual columns: ${countColumn(line3, tabSize)}'); // Family emoji = 1 col
  print('');

  // The family emoji is ONE visual column despite being many code units
  print('After emoji:');
  final afterEmoji = findColumn(line3, 1, tabSize);
  print('  column 1 → offset $afterEmoji');
  print('  character: "${line3.substring(afterEmoji, afterEmoji + 1)}"'); // space
}
