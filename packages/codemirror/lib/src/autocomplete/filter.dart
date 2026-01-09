library;

class Penalty {
  Penalty._();

  static const int gap = -1100;
  static const int notStart = -700;
  static const int caseFold = -200;
  static const int byWord = -100;
  static const int notFull = -100;
}

enum _Tp { nonWord, upper, lower }

class FuzzyMatcher {
  final String pattern;
  final List<int> chars = [];
  final List<int> folded = [];
  final bool astral;

  List<int> _any = [];
  List<int> _precise = [];
  List<int> _byWord = [];

  int score = 0;
  List<int> matched = const [];

  FuzzyMatcher(this.pattern) : astral = _hasAstral(pattern) {
    for (int p = 0; p < pattern.length;) {
      final char = pattern.codeUnitAt(p);
      int codePoint;
      int size;
      if (char >= 0xD800 && char <= 0xDBFF && p + 1 < pattern.length) {
        final next = pattern.codeUnitAt(p + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          codePoint = 0x10000 + ((char - 0xD800) << 10) + (next - 0xDC00);
          size = 2;
        } else {
          codePoint = char;
          size = 1;
        }
      } else {
        codePoint = char;
        size = 1;
      }
      chars.add(codePoint);
      final part = pattern.substring(p, p + size);
      final upper = part.toUpperCase();
      final foldedPart = upper == part ? part.toLowerCase() : upper;
      folded.add(foldedPart.isNotEmpty ? foldedPart.codeUnitAt(0) : codePoint);
      p += size;
    }
  }

  static bool _hasAstral(String s) {
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDBFF) return true;
    }
    return false;
  }

  ({int score, List<int> matched})? _ret(int score, List<int> matched) {
    this.score = score;
    this.matched = matched;
    return (score: score, matched: matched);
  }

  ({int score, List<int> matched})? match(String word) {
    if (pattern.isEmpty) return _ret(Penalty.notFull, []);
    if (word.length < pattern.length) return null;

    if (chars.length == 1) {
      final (first, firstSize) = _codePointAt(word, 0);
      var score = firstSize == word.length ? 0 : Penalty.notFull;
      if (first == chars[0]) {
      } else if (first == folded[0]) {
        score += Penalty.caseFold;
      } else {
        return null;
      }
      return _ret(score, [0, firstSize]);
    }

    final direct = word.indexOf(pattern);
    if (direct == 0) {
      return _ret(
        word.length == pattern.length ? 0 : Penalty.notFull,
        [0, pattern.length],
      );
    }

    final len = chars.length;
    var anyTo = 0;

    _any = List.filled(len, 0);
    _precise = List.filled(len, 0);
    _byWord = List.filled(len, 0);

    if (direct < 0) {
      final e = word.length < 200 ? word.length : 200;
      for (int i = 0; i < e && anyTo < len;) {
        final (next, size) = _codePointAt(word, i);
        if (next == chars[anyTo] || next == folded[anyTo]) {
          _any[anyTo++] = i;
        }
        i += size;
      }
      if (anyTo < len) return null;
    }

    var preciseTo = 0;
    var byWordTo = 0;
    var byWordFolded = false;
    var adjacentTo = 0;
    var adjacentStart = -1;
    var adjacentEnd = -1;
    final hasLower = RegExp(r'[a-z]').hasMatch(word);
    var wordAdjacent = true;
    var prevType = _Tp.nonWord;

    final e = word.length < 200 ? word.length : 200;
    for (int i = 0; i < e && byWordTo < len;) {
      final (next, size) = _codePointAt(word, i);

      if (direct < 0) {
        if (preciseTo < len && next == chars[preciseTo]) {
          _precise[preciseTo++] = i;
        }
        if (adjacentTo < len) {
          if (next == chars[adjacentTo] || next == folded[adjacentTo]) {
            if (adjacentTo == 0) adjacentStart = i;
            adjacentEnd = i + 1;
            adjacentTo++;
          } else {
            adjacentTo = 0;
          }
        }
      }

      _Tp type;
      if (next < 0xff) {
        type = (next >= 48 && next <= 57 || next >= 97 && next <= 122)
            ? _Tp.lower
            : (next >= 65 && next <= 90)
                ? _Tp.upper
                : _Tp.nonWord;
      } else {
        final ch = String.fromCharCode(next);
        type = ch != ch.toLowerCase()
            ? _Tp.upper
            : ch != ch.toUpperCase()
                ? _Tp.lower
                : _Tp.nonWord;
      }

      if (i == 0 || type == _Tp.upper && hasLower || prevType == _Tp.nonWord && type != _Tp.nonWord) {
        if (chars[byWordTo] == next || (folded[byWordTo] == next && (byWordFolded = true))) {
          _byWord[byWordTo++] = i;
        } else if (_byWord.isNotEmpty && byWordTo > 0) {
          wordAdjacent = false;
        }
      }

      prevType = type;
      i += size;
    }

    if (byWordTo == len && _byWord[0] == 0 && wordAdjacent) {
      return _result(
        Penalty.byWord + (byWordFolded ? Penalty.caseFold : 0),
        _byWord.sublist(0, byWordTo),
        word,
      );
    }
    if (adjacentTo == len && adjacentStart == 0) {
      return _ret(
        Penalty.caseFold - word.length + (adjacentEnd == word.length ? 0 : Penalty.notFull),
        [0, adjacentEnd],
      );
    }
    if (direct > -1) {
      return _ret(
        Penalty.notStart - word.length,
        [direct, direct + pattern.length],
      );
    }
    if (adjacentTo == len) {
      return _ret(
        Penalty.caseFold + Penalty.notStart - word.length,
        [adjacentStart, adjacentEnd],
      );
    }
    if (byWordTo == len) {
      return _result(
        Penalty.byWord +
            (byWordFolded ? Penalty.caseFold : 0) +
            Penalty.notStart +
            (wordAdjacent ? 0 : Penalty.gap),
        _byWord.sublist(0, byWordTo),
        word,
      );
    }

    return chars.length == 2
        ? null
        : _result(
            (_any[0] != 0 ? Penalty.notStart : 0) + Penalty.caseFold + Penalty.gap,
            _any.sublist(0, anyTo),
            word,
          );
  }

  ({int score, List<int> matched})? _result(int score, List<int> positions, String word) {
    final result = <int>[];
    var i = 0;
    for (final pos in positions) {
      final to = pos + (astral ? _codePointSize(word, pos) : 1);
      if (i > 0 && result[i - 1] == pos) {
        result[i - 1] = to;
      } else {
        result.add(pos);
        result.add(to);
        i += 2;
      }
    }
    return _ret(score - word.length, result);
  }

  static (int, int) _codePointAt(String s, int i) {
    final char = s.codeUnitAt(i);
    if (char >= 0xD800 && char <= 0xDBFF && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return (0x10000 + ((char - 0xD800) << 10) + (next - 0xDC00), 2);
      }
    }
    return (char, 1);
  }

  static int _codePointSize(String s, int i) {
    final char = s.codeUnitAt(i);
    if (char >= 0xD800 && char <= 0xDBFF && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) return 2;
    }
    return 1;
  }
}

class StrictMatcher {
  final String pattern;
  final String folded;

  List<int> matched = const [];
  int score = 0;

  StrictMatcher(this.pattern) : folded = pattern.toLowerCase();

  ({int score, List<int> matched})? match(String word) {
    if (word.length < pattern.length) return null;
    final start = word.substring(0, pattern.length);
    int? matchScore;
    if (start == pattern) {
      matchScore = 0;
    } else if (start.toLowerCase() == folded) {
      matchScore = Penalty.caseFold;
    }
    if (matchScore == null) return null;
    matched = [0, start.length];
    score = matchScore + (word.length == pattern.length ? 0 : Penalty.notFull);
    return (score: score, matched: matched);
  }
}
