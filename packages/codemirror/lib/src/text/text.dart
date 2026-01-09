/// Text data structure - B-tree based immutable document storage.
///
/// This module provides O(log n) access to document content by position
/// or line number. The [Text] class is immutable - modifications return
/// new instances.
library;

export 'char.dart';
export 'column.dart';

import 'dart:collection';

import 'package:meta/meta.dart';

/// Branch factor constants for the B-tree structure.
class _Tree {
  _Tree._();
  
  /// The branch factor as an exponent of 2.
  static const int branchShift = 5;
  
  /// The approximate branch factor (~32 lines per leaf).
  static const int branch = 1 << branchShift;
}

/// Flags passed to decompose method.
class _Open {
  _Open._();
  static const int from = 1;
  static const int to = 2;
}

/// A text iterator iterates over a sequence of strings.
/// 
/// When iterating over a [Text] document, result values will either be 
/// lines or line breaks.
abstract class TextIterator implements Iterator<String> {
  /// Retrieve the next string. Optionally skip a given number of
  /// positions after the current position.
  TextIterator next([int skip = 0]);
  
  /// The current string. Will be the empty string when the cursor is
  /// at its end or [next] hasn't been called on it yet.
  String get value;
  
  /// Whether the end of the iteration has been reached.
  bool get done;
  
  /// Whether the current string represents a line break.
  bool get lineBreak;
  
  @override
  String get current => value;
  
  @override
  bool moveNext() {
    next();
    return !done;
  }
}

/// Describes a line in the document.
/// 
/// Created on-demand when lines are queried via [Text.lineAt] or [Text.line].
@immutable
class Line {
  /// The position of the start of the line.
  final int from;
  
  /// The position at the end of the line (before the line break,
  /// or at the end of document for the last line).
  final int to;
  
  /// This line's line number (1-based).
  final int number;
  
  /// The line's content.
  final String text;
  
  /// Creates a new line descriptor.
  const Line(this.from, this.to, this.number, this.text);
  
  /// The length of the line (not including any line break after it).
  int get length => to - from;
  
  @override
  String toString() => 'Line($number: "$text")';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Line &&
          from == other.from &&
          to == other.to &&
          number == other.number &&
          text == other.text;
  
  @override
  int get hashCode => Object.hash(from, to, number, text);
}

/// The data structure for documents.
/// 
/// This is an immutable B-tree based structure that provides O(log n)
/// access by position or line number. Documents are made up of lines
/// with line breaks between them.
/// 
/// To create a document, use [Text.of]:
/// ```dart
/// final doc = Text.of(['Hello', 'World']);
/// ```
@immutable
abstract class Text with IterableMixin<String> {
  /// Protected constructor.
  const Text._();
  
  /// The length of the string (total character count).
  @override
  int get length;
  
  /// The number of lines in the string (always >= 1).
  int get lines;
  
  /// If this is a branch node, holds the child [Text] objects.
  /// For leaf nodes, this is null.
  List<Text>? get children;
  
  /// Get the line description around the given position.
  /// 
  /// [pos] must be between 0 and [length] (inclusive).
  Line lineAt(int pos) {
    if (pos < 0 || pos > length) {
      throw RangeError('Invalid position $pos in document of length $length');
    }
    return lineInner(pos, false, 1, 0);
  }
  
  /// Get the description for the given (1-based) line number.
  /// 
  /// [n] must be between 1 and [lines] (inclusive).
  Line line(int n) {
    if (n < 1 || n > lines) {
      throw RangeError('Invalid line number $n in $lines-line document');
    }
    return lineInner(n, true, 1, 0);
  }
  
  /// Internal method for line lookup.
  @internal
  Line lineInner(int target, bool isLine, int line, int offset);
  
  /// Replace a range of the text with the given content.
  /// 
  /// Returns a new [Text] with positions [from] to [to] replaced by [text].
  Text replace(int from, int to, Text text) {
    final parts = <Text>[];
    decompose(0, from, parts, _Open.to);
    if (text.isNotEmpty) {
      text.decompose(0, text.length, parts, _Open.from | _Open.to);
    }
    decompose(to, length, parts, _Open.from);
    return TextNode.from(parts, length - (to - from) + text.length);
  }
  
  /// Append another document to this one.
  Text append(Text other) {
    return replace(length, length, other);
  }
  
  /// Retrieve the text between the given points.
  /// 
  /// [to] defaults to [length] if not specified.
  Text slice(int from, [int? to]) {
    to ??= length;
    final parts = <Text>[];
    decompose(from, to, parts, 0);
    return TextNode.from(parts, to - from);
  }
  
  /// Retrieve a part of the document as a string.
  /// 
  /// [to] defaults to [length]. [lineSep] is used as the line separator
  /// (defaults to '\n').
  String sliceString(int from, [int? to, String lineSep = '\n']);
  
  /// Internal: flatten the text into a list of line strings.
  @internal
  void flatten(List<String> target);
  
  /// Internal: scan for identical content in a direction.
  @internal
  int scanIdentical(Text other, int dir);
  
  /// Test whether this text is equal to another instance.
  bool eq(Text other) {
    if (identical(this, other)) return true;
    if (other.length != length || other.lines != lines) return false;
    
    final start = scanIdentical(other, 1);
    final end = length - scanIdentical(other, -1);
    
    final a = RawTextCursor(this);
    final b = RawTextCursor(other);
    
    for (int skip = start, pos = start;;) {
      a.next(skip);
      b.next(skip);
      skip = 0;
      if (a.lineBreak != b.lineBreak || a.done != b.done || a.value != b.value) {
        return false;
      }
      pos += a.value.length;
      if (a.done || pos >= end) return true;
    }
  }
  
  /// Iterate over the text.
  /// 
  /// When [dir] is -1, iteration happens from end to start.
  /// This will return lines and the breaks between them as separate strings.
  TextIterator iter([int dir = 1]) => RawTextCursor(this, dir);
  
  /// Iterate over a range of the text.
  /// 
  /// When [from] > [to], the iterator will run in reverse.
  TextIterator iterRange(int from, [int? to]) {
    return PartialTextCursor(this, from, to ?? length);
  }
  
  /// Return a cursor that iterates over the given range of lines,
  /// without returning the line breaks between.
  /// 
  /// [from] and [to] should be 1-based line numbers if provided.
  TextIterator iterLines([int? from, int? to]) {
    TextIterator inner;
    if (from == null) {
      inner = iter();
    } else {
      to ??= lines + 1;
      final start = line(from).from;
      final endPos = to == lines + 1
          ? length
          : to <= 1
              ? 0
              : line(to - 1).to;
      inner = iterRange(start, start > endPos ? start : endPos);
    }
    return LineCursor(inner);
  }
  
  /// Internal: decompose the text for tree operations.
  @internal
  void decompose(int from, int to, List<Text> target, int open);
  
  @override
  String toString() => sliceString(0);
  
  /// Convert the document to a list of lines.
  /// 
  /// Can be deserialized via [Text.of].
  List<String> toJson() {
    final lines = <String>[];
    flatten(lines);
    return lines;
  }
  
  @override
  Iterator<String> get iterator => iter();
  
  /// Create a [Text] instance for the given list of lines.
  /// 
  /// The list must not be empty.
  static Text of(List<String> text) {
    if (text.isEmpty) {
      throw RangeError('A document must have at least one line');
    }
    if (text.length == 1 && text[0].isEmpty) return empty;
    return text.length <= _Tree.branch
        ? TextLeaf(text)
        : TextNode.from(TextLeaf.split(text, []), null);
  }
  
  /// The empty document.
  static final Text empty = TextLeaf(const [''], 0);
}

/// Leaf node storing an array of line strings.
/// 
/// There are always line breaks between these strings. Leaves are limited
/// in size and contained in [TextNode] instances for bigger documents.
@immutable
class TextLeaf extends Text {
  /// The lines stored in this leaf.
  final List<String> text;
  
  @override
  final int length;
  
  /// Creates a leaf node from lines.
  TextLeaf(List<String> text, [int? length])
      : text = List.unmodifiable(text),
        length = length ?? _textLength(text),
        super._();
  
  @override
  int get lines => text.length;
  
  @override
  List<Text>? get children => null;
  
  @override
  Line lineInner(int target, bool isLine, int line, int offset) {
    for (int i = 0;; i++) {
      final string = text[i];
      final end = offset + string.length;
      if ((isLine ? line : end) >= target) {
        return Line(offset, end, line, string);
      }
      offset = end + 1;
      line++;
    }
  }
  
  @override
  void decompose(int from, int to, List<Text> target, int open) {
    final sliced = from <= 0 && to >= length
        ? this
        : TextLeaf(
            _sliceText(text, from, to),
            (to < length ? to : length) - (from > 0 ? from : 0),
          );
    
    if ((open & _Open.from) != 0) {
      final prev = target.removeLast() as TextLeaf;
      final joined = _appendText(sliced.text, prev.text.toList(), 0, sliced.length);
      if (joined.length <= _Tree.branch) {
        target.add(TextLeaf(joined, prev.length + sliced.length));
      } else {
        final mid = joined.length >> 1;
        target.add(TextLeaf(joined.sublist(0, mid)));
        target.add(TextLeaf(joined.sublist(mid)));
      }
    } else {
      target.add(sliced);
    }
  }
  
  @override
  Text replace(int from, int to, Text text) {
    if (text is! TextLeaf) return super.replace(from, to, text);
    
    final lines = _appendText(
      this.text,
      _appendText(text.text, _sliceText(this.text, 0, from), 0, null),
      to,
      null,
    );
    final newLen = length + text.length - (to - from);
    
    if (lines.length <= _Tree.branch) return TextLeaf(lines, newLen);
    return TextNode.from(TextLeaf.split(lines, []), newLen);
  }
  
  @override
  String sliceString(int from, [int? to, String lineSep = '\n']) {
    to ??= length;
    final result = StringBuffer();
    for (int pos = 0, i = 0; pos <= to && i < text.length; i++) {
      final line = text[i];
      final end = pos + line.length;
      if (pos > from && i > 0) result.write(lineSep);
      if (from < end && to > pos) {
        final sliceStart = from - pos > 0 ? from - pos : 0;
        final sliceEnd = to - pos;
        result.write(line.substring(sliceStart, sliceEnd < line.length ? sliceEnd : line.length));
      }
      pos = end + 1;
    }
    return result.toString();
  }
  
  @override
  void flatten(List<String> target) {
    target.addAll(text);
  }
  
  @override
  int scanIdentical(Text other, int dir) => 0;
  
  /// Split a list of lines into leaf nodes.
  static List<Text> split(List<String> text, List<Text> target) {
    final part = <String>[];
    var len = -1;
    for (final line in text) {
      part.add(line);
      len += line.length + 1;
      if (part.length == _Tree.branch) {
        target.add(TextLeaf(part.toList(), len));
        part.clear();
        len = -1;
      }
    }
    if (len > -1) target.add(TextLeaf(part.toList(), len));
    return target;
  }
}

/// Branch node providing tree structure for the [Text] type.
/// 
/// Stores other nodes or leaves, balancing themselves on changes.
/// There are implied line breaks between children.
@immutable
class TextNode extends Text {
  @override
  final List<Text> children;
  
  @override
  final int length;
  
  @override
  final int lines;
  
  /// Creates a branch node from children.
  TextNode(List<Text> children, this.length)
      : children = List.unmodifiable(children),
        lines = children.fold(0, (sum, child) => sum + child.lines),
        super._();
  
  @override
  Line lineInner(int target, bool isLine, int line, int offset) {
    for (int i = 0;; i++) {
      final child = children[i];
      final end = offset + child.length;
      final endLine = line + child.lines - 1;
      if ((isLine ? endLine : end) >= target) {
        return child.lineInner(target, isLine, line, offset);
      }
      offset = end + 1;
      line = endLine + 1;
    }
  }
  
  @override
  void decompose(int from, int to, List<Text> target, int open) {
    for (int i = 0, pos = 0; pos <= to && i < children.length; i++) {
      final child = children[i];
      final end = pos + child.length;
      if (from <= end && to >= pos) {
        final childOpen = open &
            ((pos <= from ? _Open.from : 0) | (end >= to ? _Open.to : 0));
        if (pos >= from && end <= to && childOpen == 0) {
          target.add(child);
        } else {
          child.decompose(from - pos, to - pos, target, childOpen);
        }
      }
      pos = end + 1;
    }
  }
  
  @override
  Text replace(int from, int to, Text text) {
    if (text.lines < lines) {
      for (int i = 0, pos = 0; i < children.length; i++) {
        final child = children[i];
        final end = pos + child.length;
        
        // Fast path: only affects one child and size remains acceptable
        if (from >= pos && to <= end) {
          final updated = child.replace(from - pos, to - pos, text);
          final totalLines = lines - child.lines + updated.lines;
          if (updated.lines < (totalLines >> (_Tree.branchShift - 1)) &&
              updated.lines > (totalLines >> (_Tree.branchShift + 1))) {
            final copy = children.toList();
            copy[i] = updated;
            return TextNode(copy, length - (to - from) + text.length);
          }
          return super.replace(pos, end, updated);
        }
        pos = end + 1;
      }
    }
    return super.replace(from, to, text);
  }
  
  @override
  String sliceString(int from, [int? to, String lineSep = '\n']) {
    to ??= length;
    final result = StringBuffer();
    for (int i = 0, pos = 0; i < children.length && pos <= to; i++) {
      final child = children[i];
      final end = pos + child.length;
      if (pos > from && i > 0) result.write(lineSep);
      if (from < end && to > pos) {
        result.write(child.sliceString(from - pos, to - pos, lineSep));
      }
      pos = end + 1;
    }
    return result.toString();
  }
  
  @override
  void flatten(List<String> target) {
    for (final child in children) {
      child.flatten(target);
    }
  }
  
  @override
  int scanIdentical(Text other, int dir) {
    if (other is! TextNode) return 0;
    
    var scanLength = 0;
    int iA, iB, eA, eB;
    
    if (dir > 0) {
      iA = 0;
      iB = 0;
      eA = children.length;
      eB = other.children.length;
    } else {
      iA = children.length - 1;
      iB = other.children.length - 1;
      eA = -1;
      eB = -1;
    }
    
    while (true) {
      if (iA == eA || iB == eB) return scanLength;
      final chA = children[iA];
      final chB = other.children[iB];
      if (!identical(chA, chB)) {
        return scanLength + chA.scanIdentical(chB, dir);
      }
      scanLength += chA.length + 1;
      iA += dir;
      iB += dir;
    }
  }
  
  /// Create a balanced tree from children nodes.
  static Text from(List<Text> children, [int? len]) {
    var length = len ?? children.fold<int>(-1, (sum, ch) => sum + ch.length + 1);
    
    var lineCount = 0;
    for (final ch in children) {
      lineCount += ch.lines;
    }
    
    if (lineCount < _Tree.branch) {
      final flat = <String>[];
      for (final ch in children) {
        ch.flatten(flat);
      }
      return TextLeaf(flat, length);
    }
    
    final chunk = lineCount >> _Tree.branchShift > _Tree.branch
        ? lineCount >> _Tree.branchShift
        : _Tree.branch;
    final maxChunk = chunk << 1;
    final minChunk = chunk >> 1;
    
    final chunked = <Text>[];
    var currentLines = 0;
    var currentLen = -1;
    final currentChunk = <Text>[];
    
    void flush() {
      if (currentLines == 0) return;
      chunked.add(currentChunk.length == 1
          ? currentChunk[0]
          : TextNode.from(currentChunk.toList(), currentLen));
      currentLen = -1;
      currentLines = 0;
      currentChunk.clear();
    }
    
    void add(Text child) {
      if (child.lines > maxChunk && child is TextNode) {
        for (final node in child.children) {
          add(node);
        }
      } else if (child.lines > minChunk && (currentLines > minChunk || currentLines == 0)) {
        flush();
        chunked.add(child);
      } else if (child is TextLeaf &&
          currentLines > 0 &&
          currentChunk.isNotEmpty &&
          currentChunk.last is TextLeaf &&
          child.lines + (currentChunk.last as TextLeaf).lines <= _Tree.branch) {
        final last = currentChunk.last as TextLeaf;
        currentLines += child.lines;
        currentLen += child.length + 1;
        currentChunk[currentChunk.length - 1] = TextLeaf(
          [...last.text, ...child.text],
          last.length + 1 + child.length,
        );
      } else {
        if (currentLines + child.lines > chunk) flush();
        currentLines += child.lines;
        currentLen += child.length + 1;
        currentChunk.add(child);
      }
    }
    
    for (final child in children) {
      add(child);
    }
    flush();
    
    return chunked.length == 1 ? chunked[0] : TextNode(chunked, length);
  }
}

// Helper functions

int _textLength(List<String> text) {
  var length = -1;
  for (final line in text) {
    length += line.length + 1;
  }
  return length;
}

List<String> _appendText(
  List<String> text,
  List<String> target, [
  int from = 0,
  int? to,
]) {
  to ??= 1000000000; // Large default
  var first = true;
  for (int pos = 0, i = 0; i < text.length && pos <= to; i++) {
    var line = text[i];
    final end = pos + line.length;
    if (end >= from) {
      if (end > to) line = line.substring(0, to - pos);
      if (pos < from) line = line.substring(from - pos);
      if (first) {
        target[target.length - 1] += line;
        first = false;
      } else {
        target.add(line);
      }
    }
    pos = end + 1;
  }
  return target;
}

List<String> _sliceText(List<String> text, [int? from, int? to]) {
  return _appendText(text, [''], from ?? 0, to);
}

/// Raw cursor for iterating through text.
class RawTextCursor extends TextIterator {
  final int dir;
  final List<Text> _nodes;
  final List<int> _offsets;
  
  @override
  bool done = false;
  
  @override
  bool lineBreak = false;
  
  @override
  String value = '';
  
  /// Creates a raw cursor over the given text.
  RawTextCursor(Text text, [this.dir = 1])
      : _nodes = [text],
        _offsets = [
          dir > 0
              ? 1
              : (text is TextLeaf ? text.text.length : text.children!.length) << 1
        ];
  
  TextIterator _nextInner(int skip, int dir) {
    done = lineBreak = false;
    
    while (true) {
      final last = _nodes.length - 1;
      final top = _nodes[last];
      final offsetValue = _offsets[last];
      final offset = offsetValue >> 1;
      final size = top is TextLeaf ? top.text.length : top.children!.length;
      
      if (offset == (dir > 0 ? size : 0)) {
        if (last == 0) {
          done = true;
          value = '';
          return this;
        }
        if (dir > 0) _offsets[last - 1]++;
        _nodes.removeLast();
        _offsets.removeLast();
      } else if ((offsetValue & 1) == (dir > 0 ? 0 : 1)) {
        _offsets[last] += dir;
        if (skip == 0) {
          lineBreak = true;
          value = '\n';
          return this;
        }
        skip--;
      } else if (top is TextLeaf) {
        final nextStr = top.text[offset + (dir < 0 ? -1 : 0)];
        _offsets[last] += dir;
        if (nextStr.length > (skip > 0 ? skip : 0)) {
          value = skip == 0
              ? nextStr
              : dir > 0
                  ? nextStr.substring(skip)
                  : nextStr.substring(0, nextStr.length - skip);
          return this;
        }
        skip -= nextStr.length;
      } else {
        final nextNode = top.children![offset + (dir < 0 ? -1 : 0)];
        if (skip > nextNode.length) {
          skip -= nextNode.length;
          _offsets[last] += dir;
        } else {
          if (dir < 0) _offsets[last]--;
          _nodes.add(nextNode);
          _offsets.add(dir > 0
              ? 1
              : (nextNode is TextLeaf
                      ? nextNode.text.length
                      : nextNode.children!.length) <<
                  1);
        }
      }
    }
  }
  
  @override
  TextIterator next([int skip = 0]) {
    if (skip < 0) {
      _nextInner(-skip, -dir);
      skip = value.length;
    }
    return _nextInner(skip, dir);
  }
}

/// Partial cursor for iterating a range of text.
class PartialTextCursor extends TextIterator {
  final RawTextCursor _cursor;
  int _pos;
  final int from;
  final int to;
  
  @override
  String value = '';
  
  @override
  bool done = false;
  
  /// Creates a partial cursor over a range.
  PartialTextCursor(Text text, int start, int end)
      : _cursor = RawTextCursor(text, start > end ? -1 : 1),
        _pos = start > end ? text.length : 0,
        from = start < end ? start : end,
        to = start > end ? start : end;
  
  TextIterator _nextInner(int skip, int dir) {
    if (dir < 0 ? _pos <= from : _pos >= to) {
      value = '';
      done = true;
      return this;
    }
    
    skip += dir < 0
        ? (_pos - to > 0 ? _pos - to : 0)
        : (from - _pos > 0 ? from - _pos : 0);
    
    var limit = dir < 0 ? _pos - from : to - _pos;
    if (skip > limit) skip = limit;
    limit -= skip;
    
    final result = _cursor.next(skip);
    _pos += (result.value.length + skip) * dir;
    
    value = result.value.length <= limit
        ? result.value
        : dir < 0
            ? result.value.substring(result.value.length - limit)
            : result.value.substring(0, limit);
    
    done = value.isEmpty;
    return this;
  }
  
  @override
  TextIterator next([int skip = 0]) {
    if (skip < 0) {
      skip = from - _pos > skip ? from - _pos : skip;
    } else if (skip > 0) {
      skip = to - _pos < skip ? to - _pos : skip;
    }
    return _nextInner(skip, _cursor.dir);
  }
  
  @override
  bool get lineBreak => _cursor.lineBreak && value.isNotEmpty;
}

/// Cursor that iterates lines without line breaks.
class LineCursor extends TextIterator {
  final TextIterator _inner;
  bool _afterBreak = true;
  
  @override
  String value = '';
  
  @override
  bool done = false;
  
  /// Creates a line cursor wrapping another iterator.
  LineCursor(this._inner);
  
  @override
  TextIterator next([int skip = 0]) {
    final result = _inner.next(skip);
    
    if (result.done) {
      done = true;
      value = '';
    } else if (result.lineBreak) {
      if (_afterBreak) {
        value = '';
      } else {
        _afterBreak = true;
        next();
      }
    } else {
      value = result.value;
      _afterBreak = false;
    }
    return this;
  }
  
  @override
  bool get lineBreak => false;
}