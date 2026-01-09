/// Bidirectional text support.
///
/// This module provides utilities for handling bidirectional (BiDi) text,
/// implementing a subset of the Unicode Bidirectional Algorithm (UBA).
/// It's used for correct cursor movement and text rendering in mixed
/// left-to-right and right-to-left text.
library;

import '../state/selection.dart';
import '../text/text.dart';

// ============================================================================
// Direction - Text direction enum
// ============================================================================

/// Text direction for bidirectional text support.
///
/// These values match the base levels in the Unicode Bidirectional Algorithm.
enum Direction {
  /// Left-to-right text direction (base level 0).
  ltr,

  /// Right-to-left text direction (base level 1).
  rtl;

  /// Get the numeric level for this direction.
  int get level => this == ltr ? 0 : 1;
}

// ============================================================================
// Character Types - For BiDi classification
// ============================================================================

/// Character types used in the bidirectional algorithm.
class _CharType {
  static const int l = 1; // Left-to-Right
  static const int r = 2; // Right-to-Left
  static const int al = 4; // Right-to-Left Arabic
  static const int en = 8; // European Number
  static const int an = 16; // Arabic Number
  static const int et = 64; // European Number Terminator
  static const int cs = 128; // Common Number Separator
  static const int ni = 256; // Neutral or Isolate (BN, N, WS)
  static const int nsm = 512; // Non-spacing Mark
  static const int strong = l | r | al;
  static const int num = en | an;
}

/// Decode a string with each type encoded as log2(type).
List<int> _decodeTypes(String str) {
  return str.codeUnits.map((c) => 1 << (c - 48)).toList();
}

/// Character types for codepoints 0 to 0xf8.
final List<int> _lowTypes = _decodeTypes(
  '88888888888888888888888888888888888666888888787833333333337888888'
  '000000000000000000000000008888880000000000000000000000000088888888'
  '888888888888888888888888888887866668888088888663380888308888800000'
  '0000000000000000008000000000000000000000000000000008',
);

/// Character types for codepoints 0x600 to 0x6f9.
final List<int> _arabicTypes = _decodeTypes(
  '4444448826627288999999999992222222222222222222222222222222222222222'
  '222222222229999999999999999999994444444444644222822222222222222222'
  '222222222222222222222222222222222222222222222222222222222222222222'
  '22222222222222999999949999999229989999223333333333',
);

/// Get the character type for a codepoint.
int _charType(int ch) {
  if (ch <= 0xf7) return _lowTypes[ch];
  if (ch >= 0x590 && ch <= 0x5f4) return _CharType.r;
  if (ch >= 0x600 && ch <= 0x6f9) return _arabicTypes[ch - 0x600];
  if (ch >= 0x6ee && ch <= 0x8ac) return _CharType.al;
  if (ch >= 0x2000 && ch <= 0x200c) return _CharType.ni;
  if (ch >= 0xfb50 && ch <= 0xfdff) return _CharType.al;
  return _CharType.l;
}

/// RegExp to detect RTL text.
final RegExp _bidiRE = RegExp(r'[\u0590-\u05f4\u0600-\u06ff\u0700-\u08ac\ufb50-\ufdff]');

/// Check if a string contains any RTL characters.
bool hasRtlText(String text) => _bidiRE.hasMatch(text);

// ============================================================================
// BidiSpan - A contiguous span with single direction
// ============================================================================

/// Represents a contiguous range of text that has a single direction.
///
/// Bidi spans are the result of applying the Unicode Bidirectional Algorithm
/// to a line of text. Each span has a from/to range (relative to line start)
/// and a bidi level that determines direction.
class BidiSpan {
  /// The start of the span (relative to line start).
  final int from;

  /// The end of the span.
  final int to;

  /// The bidi level of the span.
  ///
  /// Level 0 = LTR, level 1 = RTL, level 2 = LTR embedded in RTL, etc.
  final int level;

  const BidiSpan(this.from, this.to, this.level);

  /// Get the direction of this span.
  Direction get dir => level.isOdd ? Direction.rtl : Direction.ltr;

  /// Get the position on a given side of the span.
  ///
  /// [end] - true for end side, false for start side
  /// [dir] - the base direction
  int side(bool end, Direction dir) {
    return (this.dir == dir) == end ? to : from;
  }

  /// Check if movement in the given direction is forward in this span.
  bool forward(bool isForward, Direction dir) {
    return isForward == (this.dir == dir);
  }

  /// Find a span containing the given index.
  ///
  /// Returns the index of the span in the order list.
  static int find(
    List<BidiSpan> order,
    int index,
    int level,
    int assoc,
  ) {
    var maybe = -1;

    for (var i = 0; i < order.length; i++) {
      final span = order[i];

      if (span.from <= index && span.to >= index) {
        if (span.level == level) return i;

        // When multiple spans match, prefer the one that covers the
        // assoc side, or the one with minimum level.
        if (maybe < 0 ||
            (assoc != 0
                ? (assoc < 0 ? span.from < index : span.to > index)
                : order[maybe].level > span.level)) {
          maybe = i;
        }
      }
    }

    if (maybe < 0) {
      throw RangeError('Index out of range');
    }
    return maybe;
  }

  @override
  String toString() => 'BidiSpan($from-$to, level=$level)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BidiSpan &&
          from == other.from &&
          to == other.to &&
          level == other.level;

  @override
  int get hashCode => Object.hash(from, to, level);
}

// ============================================================================
// Isolate - For handling isolated ranges
// ============================================================================

/// An isolated bidirectional range.
///
/// Isolates are ranges that should be processed independently in the
/// bidirectional algorithm, like inline elements with dir="auto".
class Isolate {
  /// Start position.
  final int from;

  /// End position.
  final int to;

  /// The direction of this isolate.
  final Direction direction;

  /// Nested isolates within this one.
  final List<Isolate> inner;

  const Isolate({
    required this.from,
    required this.to,
    required this.direction,
    this.inner = const [],
  });
}

/// Check if two lists of isolates are equal.
bool isolatesEq(List<Isolate> a, List<Isolate> b) {
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i++) {
    final iA = a[i];
    final iB = b[i];

    if (iA.from != iB.from ||
        iA.to != iB.to ||
        iA.direction != iB.direction ||
        !isolatesEq(iA.inner, iB.inner)) {
      return false;
    }
  }

  return true;
}

// ============================================================================
// BiDi Algorithm Implementation
// ============================================================================

/// Reusable array of character types.
final List<int> _types = [];

/// Compute the bidi order for a line of text.
///
/// Returns a list of [BidiSpan]s representing the visual order of the text.
/// For simple LTR text with no RTL characters, returns a trivial order.
///
/// ```dart
/// final order = computeOrder('Hello World', Direction.ltr, []);
/// // Returns [BidiSpan(0, 11, 0)]
///
/// final mixedOrder = computeOrder('Hello שלום World', Direction.ltr, []);
/// // Returns spans for the mixed content
/// ```
List<BidiSpan> computeOrder(
  String line,
  Direction direction, [
  List<Isolate> isolates = const [],
]) {
  if (line.isEmpty) {
    return [BidiSpan(0, 0, direction == Direction.rtl ? 1 : 0)];
  }

  // Fast path for simple LTR text
  if (direction == Direction.ltr && isolates.isEmpty && !hasRtlText(line)) {
    return trivialOrder(line.length);
  }

  // Ensure types array is large enough
  while (_types.length < line.length) {
    _types.add(_CharType.ni);
  }

  final order = <BidiSpan>[];
  final level = direction == Direction.ltr ? 0 : 1;

  _computeSectionOrder(line, level, level, isolates, 0, line.length, order);

  return order;
}

/// Create a trivial (all LTR) order for the given length.
List<BidiSpan> trivialOrder(int length) {
  return [BidiSpan(0, length, 0)];
}

/// Compute character types and apply W normalization rules.
void _computeCharTypes(
  String line,
  int rFrom,
  int rTo,
  List<Isolate> isolates,
  int outerType,
) {
  for (var iI = 0; iI <= isolates.length; iI++) {
    final from = iI > 0 ? isolates[iI - 1].to : rFrom;
    final to = iI < isolates.length ? isolates[iI].from : rTo;
    var prevType = iI > 0 ? _CharType.ni : outerType;

    // W1-W3: Handle NSM, EN after AL, convert AL to R
    var prev = prevType;
    var prevStrong = prevType;

    for (var i = from; i < to; i++) {
      var type = _charType(line.codeUnitAt(i));

      if (type == _CharType.nsm) {
        type = prev;
      } else if (type == _CharType.en && prevStrong == _CharType.al) {
        type = _CharType.an;
      }

      _types[i] = type == _CharType.al ? _CharType.r : type;

      if (type & _CharType.strong != 0) {
        prevStrong = type;
      }
      prev = type;
    }

    // W5-W7: Handle ET, CS, and EN after L
    prev = prevType;
    prevStrong = prevType;

    for (var i = from; i < to; i++) {
      var type = _types[i];

      if (type == _CharType.cs) {
        if (i < to - 1 && prev == _types[i + 1] && (prev & _CharType.num != 0)) {
          type = _types[i] = prev;
        } else {
          _types[i] = _CharType.ni;
        }
      } else if (type == _CharType.et) {
        var end = i + 1;
        while (end < to && _types[end] == _CharType.et) {
          end++;
        }

        final replace = ((i > from && prev == _CharType.en) ||
                (end < rTo && _types[end] == _CharType.en))
            ? (prevStrong == _CharType.l ? _CharType.l : _CharType.en)
            : _CharType.ni;

        for (var j = i; j < end; j++) {
          _types[j] = replace;
        }
        i = end - 1;
      } else if (type == _CharType.en && prevStrong == _CharType.l) {
        _types[i] = _CharType.l;
      }

      prev = type;
      if (type & _CharType.strong != 0) {
        prevStrong = type;
      }
    }
  }
}

/// Process neutrals (N1, N2 rules).
void _processNeutrals(
  int rFrom,
  int rTo,
  List<Isolate> isolates,
  int outerType,
) {
  var prev = outerType;

  for (var iI = 0; iI <= isolates.length; iI++) {
    final from = iI > 0 ? isolates[iI - 1].to : rFrom;
    var to = iI < isolates.length ? isolates[iI].from : rTo;

    for (var i = from; i < to;) {
      final type = _types[i];

      if (type == _CharType.ni) {
        var end = i + 1;
        var currentII = iI;
        var currentTo = to;

        while (true) {
          if (end == currentTo) {
            if (currentII == isolates.length) break;
            end = isolates[currentII++].to;
            currentTo = currentII < isolates.length
                ? isolates[currentII].from
                : rTo;
          } else if (_types[end] == _CharType.ni) {
            end++;
          } else {
            break;
          }
        }

        final beforeL = prev == _CharType.l;
        final afterL =
            (end < rTo ? _types[end] : outerType) == _CharType.l;
        final replace = beforeL == afterL
            ? (beforeL ? _CharType.l : _CharType.r)
            : outerType;

        // Fill backwards
        for (var j = end - 1; j >= i; j--) {
          // Skip isolate ranges
          var inIsolate = false;
          for (var k = currentII - 1; k >= 0; k--) {
            if (j >= isolates[k].from && j < isolates[k].to) {
              inIsolate = true;
              j = isolates[k].from;
              break;
            }
          }
          if (!inIsolate) {
            _types[j] = replace;
          }
        }
        i = end;
      } else {
        prev = type;
        i++;
      }
    }
  }
}

/// Emit spans for a section of text.
void _emitSpans(
  String line,
  int from,
  int to,
  int level,
  int baseLevel,
  List<Isolate> isolates,
  List<BidiSpan> order,
) {
  final ourType = level.isOdd ? _CharType.r : _CharType.l;

  if (level % 2 == baseLevel % 2) {
    // Same direction as base, don't flip
    var iCh = from;
    var iI = 0;

    while (iCh < to) {
      var sameDir = true;
      var isNum = false;

      if (iI == isolates.length || iCh < isolates[iI].from) {
        final next = _types[iCh];
        if (next != ourType) {
          sameDir = false;
          isNum = next == _CharType.an;
        }
      }

      final localLevel = sameDir ? level : level + 1;
      var iScan = iCh;

      scanLoop:
      while (true) {
        if (iI < isolates.length && iScan == isolates[iI].from) {
          if (isNum) break scanLoop;

          final iso = isolates[iI];
          iI++;

          if (iso.from > iCh) {
            order.add(BidiSpan(iCh, iso.from, localLevel));
          }

          final dirSwap = (iso.direction == Direction.ltr) != (localLevel.isEven);
          _computeSectionOrder(
            line,
            dirSwap ? level + 1 : level,
            baseLevel,
            iso.inner,
            iso.from,
            iso.to,
            order,
          );
          iCh = iso.to;
          iScan = iso.to;
        } else if (iScan == to ||
            (sameDir
                ? _types[iScan] != ourType
                : _types[iScan] == ourType)) {
          break;
        } else {
          iScan++;
        }
      }

      if (iCh < iScan) {
        order.add(BidiSpan(iCh, iScan, localLevel));
      }
      iCh = iScan;
    }
  } else {
    // Opposite direction, iterate in reverse
    var iCh = to;
    var iI = isolates.length;

    while (iCh > from) {
      var sameDir = true;
      var isNum = false;

      if (iI == 0 || iCh > isolates[iI - 1].to) {
        final next = _types[iCh - 1];
        if (next != ourType) {
          sameDir = false;
          isNum = next == _CharType.an;
        }
      }

      final localLevel = sameDir ? level : level + 1;
      var iScan = iCh;

      scanLoop:
      while (true) {
        if (iI > 0 && iScan == isolates[iI - 1].to) {
          if (isNum) break scanLoop;

          final iso = isolates[--iI];

          if (iso.to < iCh) {
            order.add(BidiSpan(iso.to, iCh, localLevel));
          }

          final dirSwap = (iso.direction == Direction.ltr) != (localLevel.isEven);
          _computeSectionOrder(
            line,
            dirSwap ? level + 1 : level,
            baseLevel,
            iso.inner,
            iso.from,
            iso.to,
            order,
          );
          iCh = iso.from;
          iScan = iso.from;
        } else if (iScan == from ||
            (sameDir
                ? _types[iScan - 1] != ourType
                : _types[iScan - 1] == ourType)) {
          break;
        } else {
          iScan--;
        }
      }

      if (iScan < iCh) {
        order.add(BidiSpan(iScan, iCh, localLevel));
      }
      iCh = iScan;
    }
  }
}

/// Compute order for a section of text.
void _computeSectionOrder(
  String line,
  int level,
  int baseLevel,
  List<Isolate> isolates,
  int from,
  int to,
  List<BidiSpan> order,
) {
  final outerType = level.isOdd ? _CharType.r : _CharType.l;

  _computeCharTypes(line, from, to, isolates, outerType);
  _processNeutrals(from, to, isolates, outerType);
  _emitSpans(line, from, to, level, baseLevel, isolates, order);
}

// ============================================================================
// Visual Movement
// ============================================================================

/// Track what text was moved over for debugging.
String movedOver = '';

/// Move visually (not logically) through text.
///
/// Returns a new cursor position after moving in the given direction,
/// or null if at the start/end of the line.
SelectionRange? moveVisually(
  Line line,
  List<BidiSpan> order,
  Direction dir,
  SelectionRange start,
  bool forward,
) {
  var startIndex = start.head - line.from;
  var spanI = BidiSpan.find(order, startIndex, start.bidiLevel ?? -1, start.assoc);
  var span = order[spanI];
  var spanEnd = span.side(forward, dir);

  // At end of span?
  if (startIndex == spanEnd) {
    final nextI = spanI + (forward ? 1 : -1);
    if (nextI < 0 || nextI >= order.length) return null;

    span = order[spanI = nextI];
    startIndex = span.side(!forward, dir);
    spanEnd = span.side(forward, dir);
  }

  // Find next cluster break
  var nextIndex = _findClusterBreak(line.text, startIndex, span.forward(forward, dir));
  if (nextIndex < span.from || nextIndex > span.to) {
    nextIndex = spanEnd;
  }

  movedOver = line.text.substring(
    startIndex < nextIndex ? startIndex : nextIndex,
    startIndex < nextIndex ? nextIndex : startIndex,
  );

  // Check if we're crossing into a span with a different level
  final nextSpan = spanI == (forward ? order.length - 1 : 0)
      ? null
      : order[spanI + (forward ? 1 : -1)];

  if (nextSpan != null &&
      nextIndex == spanEnd &&
      nextSpan.level + (forward ? 0 : 1) < span.level) {
    return EditorSelection.cursor(
      nextSpan.side(!forward, dir) + line.from,
      assoc: nextSpan.forward(forward, dir) ? 1 : -1,
      bidiLevel: nextSpan.level,
    );
  }

  return EditorSelection.cursor(
    nextIndex + line.from,
    assoc: span.forward(forward, dir) ? -1 : 1,
    bidiLevel: span.level,
  );
}

/// Wrapper for findClusterBreak that uses findClusterBreak from char.dart.
int _findClusterBreak(String text, int pos, bool forward) {
  return findClusterBreak(text, pos, forward);
}

/// Determine the direction of text from its first strong character.
///
/// Returns [Direction.ltr] if no strong character is found.
Direction autoDirection(String text, int from, int to) {
  for (var i = from; i < to; i++) {
    final type = _charType(text.codeUnitAt(i));
    if (type == _CharType.l) return Direction.ltr;
    if (type == _CharType.r || type == _CharType.al) return Direction.rtl;
  }
  return Direction.ltr;
}
