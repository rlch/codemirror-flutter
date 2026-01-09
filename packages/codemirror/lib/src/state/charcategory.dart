/// Character categorization for word boundary detection.
///
/// Ported from: ref/state/src/charcategory.ts
///
/// This module provides utilities for categorizing characters as word characters,
/// whitespace, or other. This is used for word-based cursor movement and selection.
///
/// Languages can customize which characters count as "word" characters by providing
/// additional word chars (e.g., `-` for CSS, `$` for PHP/shell).
library;

/// The categories produced by a character categorizer.
///
/// These are used to do things like selecting by word.
enum CharCategory {
  /// Word characters (letters, numbers, language-specific chars).
  word,

  /// Whitespace characters.
  space,

  /// Anything else (punctuation, symbols).
  other,
}

/// A function that categorizes a character (grapheme cluster).
typedef CharCategorizer = CharCategory Function(String char);

/// Regex for non-ASCII single-case word characters.
///
/// Includes: German ß, Armenian ﬓ, Hebrew, Arabic, Japanese Hiragana/Katakana,
/// CJK ideographs, Korean Hangul.
final _nonASCIISingleCaseWordChar = RegExp(
  r'[\u00df\u0587\u0590-\u05f4\u0600-\u06ff\u3040-\u309f\u30a0-\u30ff\u3400-\u4db5\u4e00-\u9fcc\uac00-\ud7af]',
);

/// Regex for Unicode alphabetic and numeric characters.
///
/// Uses Unicode property escapes for proper international support.
final RegExp? _wordCharUnicode = _tryCreateUnicodeRegex();

RegExp? _tryCreateUnicodeRegex() {
  try {
    return RegExp(r'[\p{Alphabetic}\p{Number}_]', unicode: true);
  } catch (_) {
    return null;
  }
}

/// Check if a string contains any word characters.
///
/// Uses Unicode properties when available, falls back to heuristics.
bool hasWordChar(String str) {
  if (_wordCharUnicode != null) {
    return _wordCharUnicode!.hasMatch(str);
  }

  // Fallback for environments without Unicode property support
  for (var i = 0; i < str.length; i++) {
    final ch = str[i];
    // ASCII word chars
    if (RegExp(r'\w').hasMatch(ch)) return true;
    // Non-ASCII: check if it has case or is in special ranges
    if (ch.codeUnitAt(0) > 0x80) {
      if (ch.toUpperCase() != ch.toLowerCase()) return true;
      if (_nonASCIISingleCaseWordChar.hasMatch(ch)) return true;
    }
  }
  return false;
}

/// Check if a character is whitespace.
bool _isWhitespace(String char) {
  if (char.isEmpty) return false;
  return !RegExp(r'\S').hasMatch(char);
}

/// Create a character categorizer with custom word characters.
///
/// The returned function categorizes characters as:
/// - [CharCategory.space] for whitespace
/// - [CharCategory.word] for letters, numbers, or chars in [wordChars]
/// - [CharCategory.other] for everything else
///
/// Example:
/// ```dart
/// // CSS categorizer treats `-` as word char for properties like `background-color`
/// final cssCategorizer = makeCategorizer('-');
/// cssCategorizer('-'); // CharCategory.word
/// cssCategorizer('.'); // CharCategory.other
/// ```
CharCategorizer makeCategorizer(String wordChars) {
  return (String char) {
    if (_isWhitespace(char)) return CharCategory.space;
    if (hasWordChar(char)) return CharCategory.word;
    // Check custom word chars
    for (var i = 0; i < wordChars.length; i++) {
      if (char.contains(wordChars[i])) return CharCategory.word;
    }
    return CharCategory.other;
  };
}

/// Default character categorizer with no extra word characters.
final CharCategorizer defaultCategorizer = makeCategorizer('');
