/// Unicode character utilities for grapheme cluster handling.
///
/// Ported from: ref/text/src/char.ts
///
/// This module provides functions for working with Unicode grapheme clusters,
/// which represent user-perceived characters. A grapheme cluster may consist
/// of multiple code points (e.g., emoji with skin tone modifiers, flag emoji).
///
/// Note: The TypeScript implementation uses a manual grapheme break algorithm
/// with a compressed Unicode table. This Dart port uses the official `characters`
/// package which implements UAX #29 (Unicode Text Segmentation).
library;

import 'package:characters/characters.dart';

/// Returns the next grapheme cluster break after (not equal to) `pos`,
/// if `forward` is true, or before otherwise.
///
/// Returns `pos` itself if no further cluster break is available.
/// Moves across surrogate pairs, extending characters, characters joined
/// with zero-width joiners, and flag emoji.
///
/// [str] The string to search in.
/// [pos] The position to start from (code unit index).
/// [forward] Direction to search (default: true for forward).
int findClusterBreak(String str, int pos, [bool forward = true]) {
  if (forward) {
    return _nextClusterBreak(str, pos);
  } else {
    return _prevClusterBreak(str, pos);
  }
}

/// Find the next grapheme cluster break after pos.
int _nextClusterBreak(String str, int pos) {
  if (pos >= str.length) return str.length;
  
  // Normalize position to start of a grapheme cluster
  pos = _normalizePosition(str, pos);
  
  // Use Characters API to find the next cluster break
  final range = CharacterRange.at(str, pos);
  if (!range.moveNext()) return str.length;
  
  // The end of the current grapheme is after the range
  return range.stringBeforeLength + range.current.length;
}

/// Find the previous grapheme cluster break before pos.
int _prevClusterBreak(String str, int pos) {
  if (pos <= 0) return 0;
  
  // Use Characters API - position range at pos with empty span, then move back
  final range = CharacterRange.at(str, pos, pos);
  if (!range.moveBack()) return 0;
  
  return range.stringBeforeLength;
}

/// Normalize a position that may be in the middle of a surrogate pair
/// to the start of that surrogate pair.
int _normalizePosition(String str, int pos) {
  if (pos > 0 && pos < str.length) {
    final code = str.codeUnitAt(pos);
    // If we're at a low surrogate, back up to the high surrogate
    if (code >= 0xDC00 && code <= 0xDFFF) {
      final prev = str.codeUnitAt(pos - 1);
      if (prev >= 0xD800 && prev <= 0xDBFF) {
        return pos - 1;
      }
    }
  }
  return pos;
}

/// Get the code point at the given position in a string.
///
/// Handles surrogate pairs, returning the full Unicode code point.
/// Equivalent to JavaScript's `String.prototype.codePointAt()`.
int codePointAt(String str, int pos) {
  final code0 = str.codeUnitAt(pos);
  if (!_isHighSurrogate(code0) || pos + 1 == str.length) return code0;
  
  final code1 = str.codeUnitAt(pos + 1);
  if (!_isLowSurrogate(code1)) return code0;
  
  return ((code0 - 0xD800) << 10) + (code1 - 0xDC00) + 0x10000;
}

/// Convert a Unicode code point to a string.
///
/// Equivalent to JavaScript's `String.fromCodePoint()`.
String fromCodePoint(int code) {
  if (code <= 0xFFFF) return String.fromCharCode(code);
  code -= 0x10000;
  return String.fromCharCodes([
    (code >> 10) + 0xD800,
    (code & 0x3FF) + 0xDC00,
  ]);
}

/// Returns 1 for BMP code points, 2 for supplementary plane code points.
///
/// Useful to determine how many string indices a code point occupies.
int codePointSize(int code) => code < 0x10000 ? 1 : 2;

bool _isHighSurrogate(int code) => code >= 0xD800 && code < 0xDC00;
bool _isLowSurrogate(int code) => code >= 0xDC00 && code < 0xE000;
