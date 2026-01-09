/// Search cursor for iterating over text matches.
///
/// This module provides [SearchCursor], which iterates through a document
/// finding matches for a plain string query.
library;

import '../text/text.dart';

/// Normalize a string using NFKD form (compatibility decomposition).
String _basicNormalize(String s) => s;

String Function(String) _makeNormalizer(String Function(String)? normalize) {
  if (normalize == null) return _basicNormalize;
  return (String x) => normalize(_basicNormalize(x));
}

String _normalizeQuery(String query, String Function(String)? normalize) {
  if (normalize == null) return _basicNormalize(query);
  return normalize(_basicNormalize(query));
}

/// A search cursor provides an iterator over text matches in a document.
class SearchCursor implements Iterator<({int from, int to})> {
  final TextIterator _iter;
  final String Function(String) _normalize;
  final String _query;
  final bool Function(int from, int to, String buffer, int bufferPos)? _test;

  ({int from, int to}) _value = (from: 0, to: 0);
  bool _done = false;

  final List<int> _matches = [];
  String _buffer = '';
  int _bufferPos = 0;
  int _bufferStart;

  /// Create a text cursor.
  ///
  /// The [query] is the search string, [from] to [to] provides the region.
  /// When [normalize] is given, it will be called on both the query and
  /// content before comparing.
  SearchCursor(
    Text text,
    String query, {
    int from = 0,
    int? to,
    String Function(String)? normalize,
    bool Function(int from, int to, String buffer, int bufferPos)? test,
  })  : _iter = text.iterRange(from, to ?? text.length),
        _bufferStart = from,
        _normalize = _makeNormalizer(normalize),
        _query = _normalizeQuery(query, normalize),
        _test = test;

  /// The current match value.
  ({int from, int to}) get value => _value;

  /// Whether iteration is complete.
  bool get done => _done;

  @override
  ({int from, int to}) get current => _value;

  @override
  bool moveNext() {
    _matches.clear();
    return _nextOverlapping();
  }

  bool _nextOverlapping() {
    while (true) {
      final next = _peek();
      if (next < 0) {
        _done = true;
        return false;
      }

      final str = String.fromCharCode(next);
      final start = _bufferStart + _bufferPos;
      _bufferPos += _charSize(next);

      final norm = _normalize(str);
      if (norm.isNotEmpty) {
        for (var i = 0, pos = start;; i++) {
          final code = norm.codeUnitAt(i);
          final match = _match(code, pos, _bufferPos + _bufferStart);
          if (i == norm.length - 1) {
            if (match != null) {
              _value = match;
              return true;
            }
            break;
          }
          if (pos == start && i < str.length && str.codeUnitAt(i) == code) {
            pos++;
          }
        }
      }
    }
  }

  /// Look for the next match, ignoring overlapping matches.
  ({int from, int to})? next() {
    _matches.clear();
    return nextOverlapping();
  }

  /// Get the next match, including overlapping matches.
  ({int from, int to})? nextOverlapping() {
    if (_nextOverlapping()) {
      return _value;
    }
    return null;
  }

  int _peek() {
    if (_bufferPos == _buffer.length) {
      _bufferStart += _buffer.length;
      _iter.moveNext();
      if (_iter.done) return -1;
      _bufferPos = 0;
      _buffer = _iter.current;
    }
    return _codePointAt(_buffer, _bufferPos);
  }

  ({int from, int to})? _match(int code, int pos, int end) {
    // Empty query never matches
    if (_query.isEmpty) return null;
    
    ({int from, int to})? match;

    for (var i = 0; i < _matches.length; i += 2) {
      var index = _matches[i];
      var keep = false;

      if (_query.codeUnitAt(index) == code) {
        if (index == _query.length - 1) {
          match = (from: _matches[i + 1], to: end);
        } else {
          _matches[i]++;
          keep = true;
        }
      }

      if (!keep) {
        _matches.removeRange(i, i + 2);
        i -= 2;
      }
    }

    if (_query.codeUnitAt(0) == code) {
      if (_query.length == 1) {
        match = (from: pos, to: end);
      } else {
        _matches.addAll([1, pos]);
      }
    }

    if (match != null && _test != null && !_test(match.from, match.to, _buffer, _bufferStart)) {
      match = null;
    }

    return match;
  }
}

int _codePointAt(String str, int pos) {
  if (pos >= str.length) return -1;
  final code = str.codeUnitAt(pos);
  if (code >= 0xD800 && code < 0xDC00 && pos + 1 < str.length) {
    final next = str.codeUnitAt(pos + 1);
    if (next >= 0xDC00 && next < 0xE000) {
      return (code - 0xD800) * 0x400 + (next - 0xDC00) + 0x10000;
    }
  }
  return code;
}

int _charSize(int codePoint) {
  return codePoint >= 0x10000 ? 2 : 1;
}
