/// Selection handling for the editor.
///
/// This module provides [EditorSelection] and [SelectionRange] for managing
/// cursor positions and text selections within the document.
library;

import 'package:meta/meta.dart';

// Forward declaration for ChangeDesc - will be imported when available
// For now we have a stub interface
import 'change.dart';

/// Flags for range properties encoded in a single integer.
///
/// The flags field is used like this:
/// - 3 bits for bidi level (7 means unset) (only meaningful for cursors)
/// - 2 bits to indicate the side the cursor is associated with (only for cursors)
/// - 1 bit to indicate whether the range is inverted (head before anchor)
/// - Any further bits hold the goal column (only for ranges produced by vertical motion)
class _RangeFlag {
  _RangeFlag._();

  static const int bidiLevelMask = 7;
  static const int assocBefore = 8;
  static const int assocAfter = 16;
  static const int inverted = 32;
  static const int goalColumnOffset = 6;
  static const int noGoalColumn = 0xffffff;
}

/// A single selection range.
///
/// When [EditorState.allowMultipleSelections] is enabled, a selection may hold
/// multiple ranges. By default, selections hold exactly one range.
@immutable
class SelectionRange {
  /// The lower boundary of the range.
  final int from;

  /// The upper boundary of the range.
  final int to;

  final int _flags;

  const SelectionRange._(this.from, this.to, this._flags);

  /// The anchor of the range—the side that doesn't move when you extend it.
  int get anchor => (_flags & _RangeFlag.inverted) != 0 ? to : from;

  /// The head of the range, which is moved when the range is extended.
  int get head => (_flags & _RangeFlag.inverted) != 0 ? from : to;

  /// True when [anchor] and [head] are at the same position.
  bool get empty => from == to;

  /// If this is a cursor that is explicitly associated with the character
  /// on one of its sides, this returns the side.
  ///
  /// -1 means the character before its position, 1 the character after,
  /// and 0 means no association.
  int get assoc {
    if ((_flags & _RangeFlag.assocBefore) != 0) return -1;
    if ((_flags & _RangeFlag.assocAfter) != 0) return 1;
    return 0;
  }

  /// The bidirectional text level associated with this cursor, if any.
  int? get bidiLevel {
    final level = _flags & _RangeFlag.bidiLevelMask;
    return level == 7 ? null : level;
  }

  /// The goal column (stored vertical offset) associated with a cursor.
  ///
  /// This is used to preserve the vertical position when moving across
  /// lines of different length.
  int? get goalColumn {
    final value = _flags >> _RangeFlag.goalColumnOffset;
    return value == _RangeFlag.noGoalColumn ? null : value;
  }

  /// Map this range through a change, producing a valid range in the
  /// updated document.
  SelectionRange map(ChangeDesc change, [int assoc = -1]) {
    int newFrom, newTo;
    if (empty) {
      newFrom = newTo = change.mapPos(from, assoc) ?? from;
    } else {
      newFrom = change.mapPos(from, 1) ?? from;
      newTo = change.mapPos(to, -1) ?? to;
    }
    return newFrom == from && newTo == to
        ? this
        : SelectionRange._(newFrom, newTo, _flags);
  }

  /// Extend this range to cover at least [from] to [to].
  SelectionRange extend(int from, [int? to]) {
    to ??= from;
    if (from <= anchor && to >= anchor) {
      return EditorSelection.range(from, to);
    }
    final head = (from - anchor).abs() > (to - anchor).abs() ? from : to;
    return EditorSelection.range(anchor, head);
  }

  /// Compare this range to another range.
  ///
  /// When [includeAssoc] is true, cursor ranges must also have the same
  /// [assoc] value.
  bool eq(SelectionRange other, [bool includeAssoc = false]) {
    return anchor == other.anchor &&
        head == other.head &&
        (!includeAssoc || !empty || assoc == other.assoc);
  }

  /// Return a JSON-serializable object representing the range.
  Map<String, dynamic> toJson() => {'anchor': anchor, 'head': head};

  /// Convert a JSON representation of a range to a [SelectionRange] instance.
  static SelectionRange fromJson(Map<String, dynamic> json) {
    if (json['anchor'] is! int || json['head'] is! int) {
      throw RangeError('Invalid JSON representation for SelectionRange');
    }
    return EditorSelection.range(json['anchor'] as int, json['head'] as int);
  }

  /// Factory for creating ranges.
  static SelectionRange create(int from, int to, int flags) {
    return SelectionRange._(from, to, flags);
  }

  @override
  String toString() => 'SelectionRange($anchor/$head)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionRange && from == other.from && to == other.to && _flags == other._flags;

  @override
  int get hashCode => Object.hash(from, to, _flags);
}

/// An editor selection holds one or more selection ranges.
@immutable
class EditorSelection {
  /// The ranges in the selection, sorted by position.
  ///
  /// Ranges cannot overlap (but they may touch, if they aren't empty).
  final List<SelectionRange> ranges;

  /// The index of the _main_ range in the selection.
  ///
  /// This is usually the range that was added last.
  final int mainIndex;

  const EditorSelection._(this.ranges, this.mainIndex);

  /// Map a selection through a change. Used to adjust the selection
  /// position for changes.
  EditorSelection map(ChangeDesc change, [int assoc = -1]) {
    if (change.empty) return this;
    return EditorSelection.create(
      ranges.map((r) => r.map(change, assoc)).toList(),
      mainIndex,
    );
  }

  /// Compare this selection to another selection.
  ///
  /// By default, ranges are compared only by position. When [includeAssoc]
  /// is true, cursor ranges must also have the same [assoc] value.
  bool eq(EditorSelection other, [bool includeAssoc = false]) {
    if (ranges.length != other.ranges.length || mainIndex != other.mainIndex) {
      return false;
    }
    for (var i = 0; i < ranges.length; i++) {
      if (!ranges[i].eq(other.ranges[i], includeAssoc)) return false;
    }
    return true;
  }

  /// Get the primary selection range.
  ///
  /// Usually, you should make sure your code applies to _all_ ranges,
  /// by using methods like [EditorState.changeByRange].
  SelectionRange get main => ranges[mainIndex];

  /// Make sure the selection only has one range.
  ///
  /// Returns a selection holding only the main range from this selection.
  EditorSelection asSingle() {
    return ranges.length == 1 ? this : EditorSelection._([main], 0);
  }

  /// Extend this selection with an extra range.
  EditorSelection addRange(SelectionRange range, [bool main = true]) {
    return EditorSelection.create(
      [range, ...ranges],
      main ? 0 : mainIndex + 1,
    );
  }

  /// Replace a given range with another range, and then normalize the
  /// selection to merge and sort ranges if necessary.
  EditorSelection replaceRange(SelectionRange range, [int? which]) {
    which ??= mainIndex;
    final newRanges = ranges.toList();
    newRanges[which] = range;
    return EditorSelection.create(newRanges, mainIndex);
  }

  /// Convert this selection to an object that can be serialized to JSON.
  Map<String, dynamic> toJson() {
    return {
      'ranges': ranges.map((r) => r.toJson()).toList(),
      'main': mainIndex,
    };
  }

  /// Create a selection from a JSON representation.
  static EditorSelection fromJson(Map<String, dynamic> json) {
    final rangesJson = json['ranges'];
    final main = json['main'];
    if (rangesJson is! List || main is! int || main >= rangesJson.length) {
      throw RangeError('Invalid JSON representation for EditorSelection');
    }
    return EditorSelection._(
      rangesJson.map((r) => SelectionRange.fromJson(r as Map<String, dynamic>)).toList(),
      main,
    );
  }

  /// Create a selection holding a single range.
  static EditorSelection single(int anchor, [int? head]) {
    head ??= anchor;
    return EditorSelection._([EditorSelection.range(anchor, head)], 0);
  }

  /// Sort and merge the given set of ranges, creating a valid selection.
  static EditorSelection create(List<SelectionRange> ranges, [int mainIndex = 0]) {
    if (ranges.isEmpty) {
      throw RangeError('A selection needs at least one range');
    }
    // Check if already normalized
    var pos = 0;
    for (var i = 0; i < ranges.length; i++) {
      final range = ranges[i];
      if (range.empty ? range.from <= pos : range.from < pos) {
        return EditorSelection._normalized(ranges.toList(), mainIndex);
      }
      pos = range.to;
    }
    return EditorSelection._(List.unmodifiable(ranges), mainIndex);
  }

  /// Create a cursor selection range at the given position.
  ///
  /// You can safely ignore the optional arguments in most situations.
  static SelectionRange cursor(
    int pos, {
    int assoc = 0,
    int? bidiLevel,
    int? goalColumn,
  }) {
    return SelectionRange.create(
      pos,
      pos,
      (assoc == 0 ? 0 : assoc < 0 ? _RangeFlag.assocBefore : _RangeFlag.assocAfter) |
          (bidiLevel ?? 7) |
          ((goalColumn ?? _RangeFlag.noGoalColumn) << _RangeFlag.goalColumnOffset),
    );
  }

  /// Create a selection range.
  static SelectionRange range(int anchor, int head, {int? goalColumn, int? bidiLevel}) {
    final flags = ((goalColumn ?? _RangeFlag.noGoalColumn) << _RangeFlag.goalColumnOffset) |
        (bidiLevel ?? 7);
    return head < anchor
        ? SelectionRange.create(
            head, anchor, _RangeFlag.inverted | _RangeFlag.assocAfter | flags)
        : SelectionRange.create(
            anchor, head, (head > anchor ? _RangeFlag.assocBefore : 0) | flags);
  }

  /// Normalize ranges by sorting and merging overlapping ones.
  static EditorSelection _normalized(List<SelectionRange> ranges, [int mainIndex = 0]) {
    final main = ranges[mainIndex];
    ranges.sort((a, b) => a.from - b.from);
    mainIndex = ranges.indexOf(main);

    var i = 1;
    while (i < ranges.length) {
      final range = ranges[i];
      final prev = ranges[i - 1];
      if (range.empty ? range.from <= prev.to : range.from < prev.to) {
        final from = prev.from;
        final to = range.to > prev.to ? range.to : prev.to;
        if (i <= mainIndex) mainIndex--;
        ranges.removeAt(i - 1);
        ranges.removeAt(i - 1);
        final merged = range.anchor > range.head
            ? EditorSelection.range(to, from)
            : EditorSelection.range(from, to);
        ranges.insert(i - 1, merged);
      } else {
        i++;
      }
    }
    return EditorSelection._(List.unmodifiable(ranges), mainIndex);
  }

  @override
  String toString() => 'EditorSelection(${ranges.map((r) => '${r.anchor}/${r.head}').join(', ')})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorSelection &&
          mainIndex == other.mainIndex &&
          ranges.length == other.ranges.length &&
          eq(other);

  @override
  int get hashCode => Object.hash(mainIndex, Object.hashAll(ranges));
}

/// Check that a selection is valid for a document of the given length.
void checkSelection(EditorSelection selection, int docLength) {
  for (final range in selection.ranges) {
    if (range.to > docLength) {
      throw RangeError('Selection points outside of document');
    }
  }
}
