/// Column position utilities for handling tab expansion.
///
/// Ported from: ref/text/src/column.ts
///
/// This module provides functions for converting between character offsets
/// and visual column positions, accounting for tab characters that expand
/// to multiple columns.
library;

import 'char.dart';

/// Count the column position at the given offset into the string.
///
/// Takes extending characters (grapheme clusters) and tab size into account.
/// Each grapheme cluster counts as one column, except tabs which expand
/// to align to the next tab stop.
///
/// [string] The string to measure.
/// [tabSize] The number of columns per tab stop.
/// [to] The character offset to measure to (defaults to end of string).
int countColumn(String string, int tabSize, [int? to]) {
  to ??= string.length;
  var col = 0;
  var i = 0;
  
  while (i < to) {
    if (string.codeUnitAt(i) == 0x09) {
      // Tab - align to next tab stop
      col += tabSize - (col % tabSize);
      i++;
    } else {
      // Regular character - move by grapheme cluster
      col++;
      i = findClusterBreak(string, i, true);
    }
  }
  
  return col;
}

/// Find the offset that corresponds to the given column position.
///
/// Takes extending characters (grapheme clusters) and tab size into account.
/// By default, returns the string length when the string is too short to
/// reach the column. Pass `strict: true` to return -1 in that situation.
///
/// [string] The string to search in.
/// [col] The target visual column position.
/// [tabSize] The number of columns per tab stop.
/// [strict] If true, return -1 when column is past end of string.
int findColumn(String string, int col, int tabSize, {bool strict = false}) {
  var i = 0;
  var n = 0;
  
  while (true) {
    if (n >= col) return i;
    if (i == string.length) break;
    
    n += string.codeUnitAt(i) == 0x09 
        ? tabSize - (n % tabSize) 
        : 1;
    i = findClusterBreak(string, i, true);
  }
  
  return strict ? -1 : string.length;
}
