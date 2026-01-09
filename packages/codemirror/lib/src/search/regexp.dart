/// Regular expression search cursor.
///
/// This module provides [RegExpCursor], which iterates through a document
/// finding matches for a regular expression pattern.
library;

import '../text/text.dart';

/// Empty match result used as initial value.
final _empty = (from: -1, to: -1, match: RegExp(r'.*').firstMatch('')!);

/// Options for creating a RegExpCursor.
class RegExpCursorOptions {
  /// Whether to ignore case when matching.
  final bool ignoreCase;

  /// Optional test function to filter matches.
  final bool Function(int from, int to, RegExpMatch match)? test;

  const RegExpCursorOptions({
    this.ignoreCase = false,
    this.test,
  });
}

/// A search cursor for regular expression patterns.
///
/// Similar to [SearchCursor] but searches for a regular expression pattern
/// instead of a plain string.
class RegExpCursor implements Iterator<({int from, int to, RegExpMatch match})> {
  final Text _text;
  final RegExp _re;
  final bool Function(int from, int to, RegExpMatch match)? _test;
  final int _to;

  String _curLine = '';
  int _curLineStart = 0;
  int _matchPos = 0;

  /// Whether the end of the search range has been reached.
  bool done = false;

  /// The current match value.
  ({int from, int to, RegExpMatch match}) value = _empty;

  /// Create a cursor that will search the given range in the given document.
  ///
  /// The [query] should be the raw pattern (as you'd pass to `new RegExp`).
  RegExpCursor(
    this._text,
    String query, {
    RegExpCursorOptions? options,
    int from = 0,
    int? to,
  })  : _to = to ?? _text.length,
        _re = RegExp(
          query,
          multiLine: true,
          caseSensitive: !(options?.ignoreCase ?? false),
        ),
        _test = options?.test {
    final startLine = _text.lineAt(from);
    _curLineStart = startLine.from;
    _matchPos = _toCharEnd(_text, from);
    _getLine(_curLineStart);
  }

  void _getLine(int skip) {
    final line = _text.lineAt(skip);
    _curLine = line.text;
    _curLineStart = line.from;
    if (_curLineStart + _curLine.length > _to) {
      _curLine = _curLine.substring(0, _to - _curLineStart);
    }
  }

  void _nextLine() {
    _curLineStart = _curLineStart + _curLine.length + 1;
    if (_curLineStart > _to) {
      _curLine = '';
    } else {
      _getLine(_curLineStart);
    }
  }

  @override
  ({int from, int to, RegExpMatch match}) get current => value;

  @override
  bool moveNext() {
    return _next();
  }

  /// Move to the next match, if there is one.
  bool _next() {
    var off = _matchPos - _curLineStart;

    while (true) {
      // Find next match on current line
      final matches = _re.allMatches(_curLine, _max(0, off));
      RegExpMatch? match;
      for (final m in matches) {
        if (m.start >= off) {
          match = m;
          break;
        }
      }

      if (match != null && _matchPos <= _to) {
        final from = _curLineStart + match.start;
        final to = _curLineStart + match.end;
        _matchPos = _toCharEnd(_text, to + (from == to ? 1 : 0));

        if (from == _curLineStart + _curLine.length) _nextLine();

        if ((from < to || from > value.to) &&
            (_test == null || _test(from, to, match))) {
          value = (from: from, to: to, match: match);
          return true;
        }
        off = _matchPos - _curLineStart;
      } else if (_curLineStart + _curLine.length < _to) {
        _nextLine();
        off = 0;
      } else {
        done = true;
        return false;
      }
    }
  }

  /// Get next match or null.
  ({int from, int to, RegExpMatch match})? next() {
    if (_next()) return value;
    return null;
  }
}

/// Check if a regular expression source is valid.
bool validRegExp(String source) {
  try {
    RegExp(source, multiLine: true);
    return true;
  } catch (_) {
    return false;
  }
}

/// Move position to the end of a character (handles surrogate pairs).
int _toCharEnd(Text text, int pos) {
  if (pos >= text.length) return pos;
  final line = text.lineAt(pos);
  int next;
  while (pos < line.to &&
      (next = line.text.codeUnitAt(pos - line.from)) >= 0xDC00 &&
      next < 0xE000) {
    pos++;
  }
  return pos;
}

int _max(int a, int b) => a > b ? a : b;
