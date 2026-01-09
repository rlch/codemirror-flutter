/// Range set - efficient storage for ranges with values.
///
/// This module provides [RangeSet] for storing and manipulating collections
/// of ranges associated with values, such as decorations.
library;

import 'package:meta/meta.dart';
import 'change.dart';

/// Large constant for "far away" positions.
const int _far = 1000000000;

/// Maximum ranges per chunk.
const int _chunkSize = 250;

/// Each range is associated with a value, which must inherit from this class.
abstract class RangeValue {
  /// Compare this value with another value. Used when comparing
  /// rangesets. The default implementation compares by identity.
  /// Unless you are only creating a fixed number of unique instances
  /// of your value type, it is a good idea to implement this properly.
  bool eq(RangeValue other) => this == other;

  /// The bias value at the start of the range. Determines how the
  /// range is positioned relative to other ranges starting at this
  /// position. Defaults to 0.
  int get startSide => 0;

  /// The bias value at the end of the range. Defaults to 0.
  int get endSide => 0;

  /// The mode with which the location of the range should be mapped
  /// when its `from` and `to` are the same, to decide whether a
  /// change deletes the range. Defaults to `MapMode.trackDel`.
  MapMode get mapMode => MapMode.trackDel;

  /// Determines whether this value marks a point range. Regular
  /// ranges affect the part of the document they cover, and are
  /// meaningless when empty. Point ranges have a meaning on their
  /// own. When non-empty, a point range is treated as atomic and
  /// shadows any ranges contained in it.
  bool get point => false;

  /// Create a [Range] with this value.
  Range<RangeValue> range(int from, [int? to]) {
    return Range._(from, to ?? from, this);
  }
}

/// A range associates a value with a range of positions.
class Range<T extends RangeValue> {
  /// The range's start position.
  final int from;

  /// Its end position.
  final int to;

  /// The value associated with this range.
  final T value;

  Range._(this.from, this.to, this.value);

  /// Create a range.
  @internal
  static Range<T> create<T extends RangeValue>(int from, int to, T value) {
    return Range._(from, to, value);
  }
}

int _cmpRange<T extends RangeValue>(Range<T> a, Range<T> b) {
  return a.from - b.from != 0
      ? a.from - b.from
      : a.value.startSide - b.value.startSide;
}

/// Collection of methods used when comparing range sets.
abstract interface class RangeComparator<T extends RangeValue> {
  /// Notifies the comparator that a range (in positions in the new
  /// document) has the given sets of values associated with it, which
  /// are different in the old (A) and new (B) sets.
  void compareRange(int from, int to, List<T> activeA, List<T> activeB);

  /// Notification for a changed (or inserted, or deleted) point range.
  void comparePoint(int from, int to, T? pointA, T? pointB);

  /// Notification for a changed boundary between ranges.
  void boundChange(int pos) {}
}

/// Methods used when iterating over the spans created by a set of ranges.
abstract interface class SpanIterator<T extends RangeValue> {
  /// Called for any ranges not covered by point decorations. `active`
  /// holds the values that the range is marked with (and may be empty).
  /// `openStart` indicates how many of those ranges are open (continued)
  /// at the start of the span.
  void span(int from, int to, List<T> active, int openStart);

  /// Called when going over a point decoration.
  void point(
    int from,
    int to,
    T value,
    List<T> active,
    int openStart,
    int index,
  );
}

/// Internal chunk storage for range sets.
@internal
class Chunk<T extends RangeValue> {
  final List<int> from;
  final List<int> to;
  final List<T> value;

  /// Chunks are marked with the largest point that occurs in them
  /// (or -1 for no points), so that scans that are only interested
  /// in points can skip range-only chunks.
  final int maxPoint;

  Chunk(this.from, this.to, this.value, this.maxPoint);

  int get length => to.isEmpty ? 0 : to[to.length - 1];

  /// Find the index of the given position and side.
  int findIndex(int pos, int side, bool end, [int startAt = 0]) {
    final arr = end ? to : from;
    var lo = startAt;
    var hi = arr.length;
    while (lo < hi) {
      if (lo == hi) return lo;
      final mid = (lo + hi) >> 1;
      final diff = arr[mid] - pos != 0
          ? arr[mid] - pos
          : (end ? value[mid].endSide : value[mid].startSide) - side;
      if (mid == lo) return diff >= 0 ? lo : hi;
      if (diff >= 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Iterate over ranges in this chunk that touch [from, to].
  bool between(
    int offset,
    int from,
    int to,
    bool Function(int from, int to, T value) f,
  ) {
    final i0 = findIndex(from, -_far, true);
    final e = findIndex(to, _far, false, i0);
    for (var i = i0; i < e; i++) {
      if (f(this.from[i] + offset, this.to[i] + offset, value[i]) == false) {
        return false;
      }
    }
    return true;
  }

  /// Map this chunk through changes.
  ({Chunk<T>? mapped, int pos}) map(int offset, ChangeDesc changes) {
    final newValue = <T>[];
    final newFrom = <int>[];
    final newTo = <int>[];
    var newPos = -1;
    var maxPoint = -1;

    for (var i = 0; i < value.length; i++) {
      final val = value[i];
      final curFrom = from[i] + offset;
      final curTo = to[i] + offset;
      int newFromPos;
      int newToPos;

      if (curFrom == curTo) {
        final mapped = changes.mapPos(curFrom, val.startSide, val.mapMode);
        if (mapped == null) continue;
        newFromPos = newToPos = mapped;
        if (val.startSide != val.endSide) {
          final mappedEnd = changes.mapPos(curFrom, val.endSide);
          if (mappedEnd == null || mappedEnd < newFromPos) continue;
          newToPos = mappedEnd;
        }
      } else {
        newFromPos = changes.mapPos(curFrom, val.startSide)!;
        newToPos = changes.mapPos(curTo, val.endSide)!;
        if (newFromPos > newToPos ||
            (newFromPos == newToPos &&
                val.startSide > 0 &&
                val.endSide <= 0)) {
          continue;
        }
      }

      if ((newToPos - newFromPos != 0
              ? newToPos - newFromPos
              : val.endSide - val.startSide) <
          0) {
        continue;
      }

      if (newPos < 0) newPos = newFromPos;
      if (val.point) maxPoint = maxPoint > newToPos - newFromPos
          ? maxPoint
          : newToPos - newFromPos;
      newValue.add(val);
      newFrom.add(newFromPos - newPos);
      newTo.add(newToPos - newPos);
    }

    return (
      mapped: newValue.isNotEmpty
          ? Chunk(newFrom, newTo, newValue, maxPoint)
          : null,
      pos: newPos,
    );
  }
}

/// A range cursor is an object that moves to the next range every
/// time you call `next` on it.
abstract interface class RangeCursor<T extends RangeValue> {
  /// Move the iterator forward.
  void next();

  /// The next range's value. Holds `null` when the cursor has reached its end.
  T? get value;

  /// The next range's start position.
  int get from;

  /// The next end position.
  int get to;
}

/// Internal interface for range cursors with additional methods for SpanCursor.
abstract interface class _RangeCursorInternal<T extends RangeValue>
    implements RangeCursor<T> {
  int get _rank;
  int get _startSide;
  void forward(int pos, int side);
  _RangeCursorInternal<T> goto(int pos, [int side]);
}

/// Options for updating a range set.
class RangeSetUpdate<T extends RangeValue> {
  /// An array of ranges to add.
  final List<Range<T>> add;

  /// Indicates whether the library should sort the ranges in `add`.
  final bool sort;

  /// Filter the ranges already in the set.
  final bool Function(int from, int to, T value)? filter;

  /// The start position to apply the filter to.
  final int filterFrom;

  /// The end position to apply the filter to.
  final int? filterTo;

  RangeSetUpdate({
    this.add = const [],
    this.sort = false,
    this.filter,
    this.filterFrom = 0,
    this.filterTo,
  });
}

/// A range set stores a collection of [Range]s in a way that makes them
/// efficient to [map] and [update]. This is an immutable data structure.
class RangeSet<T extends RangeValue> {
  @internal
  final List<int> chunkPos;

  @internal
  final List<Chunk<T>> chunk;

  @internal
  RangeSet<T> get nextLayer => _nextLayer!;
  final RangeSet<T>? _nextLayer;

  @internal
  final int maxPoint;

  RangeSet._(this.chunkPos, this.chunk, RangeSet<T>? nextLayer, this.maxPoint)
      : _nextLayer = nextLayer;

  /// Create a range set.
  @internal
  static RangeSet<T> create<T extends RangeValue>(
    List<int> chunkPos,
    List<Chunk<T>> chunk,
    RangeSet<T> nextLayer,
    int maxPoint,
  ) {
    return RangeSet._(chunkPos, chunk, nextLayer, maxPoint);
  }

  /// The length of the document this set applies to.
  int get length {
    final last = chunk.length - 1;
    return last < 0 ? 0 : _chunkEnd(last) > nextLayer.length
        ? _chunkEnd(last)
        : nextLayer.length;
  }

  /// The number of ranges in the set.
  int get size {
    if (isEmpty) return 0;
    var result = nextLayer.size;
    for (final c in chunk) {
      result += c.value.length;
    }
    return result;
  }

  int _chunkEnd(int index) {
    return chunkPos[index] + chunk[index].length;
  }

  /// Update the range set, optionally adding new ranges or filtering out existing ones.
  RangeSet<T> update(RangeSetUpdate<T> updateSpec) {
    var add = updateSpec.add;
    final sort = updateSpec.sort;
    final filterFrom = updateSpec.filterFrom;
    final filterTo = updateSpec.filterTo ?? length;
    final filter = updateSpec.filter;

    if (add.isEmpty && filter == null) return this;
    if (sort) {
      add = List.of(add)..sort(_cmpRange);
    }
    if (isEmpty) return add.isNotEmpty ? RangeSet.of(add) : this;

    final cur = _LayerCursor<T>(this, null, -1).goto(0);
    var i = 0;
    final spill = <Range<T>>[];
    final builder = RangeSetBuilder<T>();

    while (cur.value != null || i < add.length) {
      if (i < add.length &&
          (cur.from - add[i].from != 0
                  ? cur.from - add[i].from
                  : cur._startSide - add[i].value.startSide) >=
              0) {
        final range = add[i++];
        if (!builder._addInner(range.from, range.to, range.value)) {
          spill.add(range);
        }
      } else if (cur._rangeIndex == 1 &&
          cur._chunkIndex < chunk.length &&
          (i == add.length || _chunkEnd(cur._chunkIndex) < add[i].from) &&
          (filter == null ||
              filterFrom > _chunkEnd(cur._chunkIndex) ||
              filterTo < chunkPos[cur._chunkIndex]) &&
          builder._addChunk(chunkPos[cur._chunkIndex], chunk[cur._chunkIndex])) {
        cur._nextChunk();
      } else {
        if (filter == null ||
            filterFrom > cur.to ||
            filterTo < cur.from ||
            filter(cur.from, cur.to, cur.value as T)) {
          if (!builder._addInner(cur.from, cur.to, cur.value as T)) {
            spill.add(Range.create(cur.from, cur.to, cur.value as T));
          }
        }
        cur.next();
      }
    }

    return builder._finishInner(
      nextLayer.isEmpty && spill.isEmpty
          ? RangeSet.empty<T>()
          : nextLayer.update(RangeSetUpdate<T>(
              add: spill,
              filter: filter,
              filterFrom: filterFrom,
              filterTo: filterTo,
            )),
    );
  }

  /// Map this range set through a set of changes, return the new set.
  RangeSet<T> map(ChangeDesc changes) {
    if (changes.empty || isEmpty) return this;

    final chunks = <Chunk<T>>[];
    final positions = <int>[];
    var maxPt = -1;

    for (var i = 0; i < chunk.length; i++) {
      final start = chunkPos[i];
      final c = chunk[i];
      final touch = changes.touchesRange(start, start + c.length);
      if (touch == false) {
        maxPt = maxPt > c.maxPoint ? maxPt : c.maxPoint;
        chunks.add(c);
        positions.add(changes.mapPos(start)!);
      } else if (touch == true) {
        final result = c.map(start, changes);
        if (result.mapped != null) {
          maxPt = maxPt > result.mapped!.maxPoint ? maxPt : result.mapped!.maxPoint;
          chunks.add(result.mapped!);
          positions.add(result.pos);
        }
      }
    }

    final next = nextLayer.map(changes);
    return chunks.isEmpty
        ? next
        : RangeSet._(positions, chunks, next, maxPt);
  }

  /// Iterate over the ranges that touch the region `from` to `to`,
  /// calling `f` for each. There is no guarantee that the ranges will
  /// be reported in any specific order. When the callback returns
  /// `false`, iteration stops.
  void between(int from, int to, bool Function(int from, int to, T value) f) {
    if (isEmpty) return;
    for (var i = 0; i < chunk.length; i++) {
      final start = chunkPos[i];
      final c = chunk[i];
      if (to >= start && from <= start + c.length) {
        if (!c.between(start, from - start, to - start, f)) return;
      }
    }
    nextLayer.between(from, to, f);
  }

  /// Iterate over the ranges in this set, in order, including all
  /// ranges that end at or after `from`.
  RangeCursor<T> iter([int from = 0]) {
    final cursor = _HeapCursor.create<T>([this]);
    if (cursor is _HeapCursor<T>) {
      return cursor.goto(from);
    } else {
      return (cursor as _LayerCursor<T>).goto(from);
    }
  }

  /// Whether this set is empty.
  bool get isEmpty => nextLayer == this;

  /// Iterate over the ranges in a collection of sets, in order,
  /// starting from `from`.
  static RangeCursor<T> iterSets<T extends RangeValue>(
    List<RangeSet<T>> sets, [
    int from = 0,
  ]) {
    final cursor = _HeapCursor.create<T>(sets);
    if (cursor is _HeapCursor<T>) {
      return cursor.goto(from);
    } else {
      return (cursor as _LayerCursor<T>).goto(from);
    }
  }

  /// Compare two groups of sets, calling methods on `comparator`
  /// to notify it of possible differences.
  static void compare<T extends RangeValue>(
    List<RangeSet<T>> oldSets,
    List<RangeSet<T>> newSets, {
    required ChangeDesc textDiff,
    required RangeComparator<T> comparator,
    int minPointSize = -1,
  }) {
    final a = oldSets
        .where((set) => set.maxPoint > 0 || (!set.isEmpty && set.maxPoint >= minPointSize))
        .toList();
    final b = newSets
        .where((set) => set.maxPoint > 0 || (!set.isEmpty && set.maxPoint >= minPointSize))
        .toList();
    final sharedChunks = _findSharedChunks(a, b, textDiff);

    final sideA = _SpanCursor(a, sharedChunks, minPointSize);
    final sideB = _SpanCursor(b, sharedChunks, minPointSize);

    textDiff.iterGaps((fromA, fromB, length) {
      _compare(sideA, fromA, sideB, fromB, length, comparator);
    });
    if (textDiff.empty && textDiff.length == 0) {
      _compare(sideA, 0, sideB, 0, 0, comparator);
    }
  }

  /// Compare the contents of two groups of range sets, returning true
  /// if they are equivalent in the given range.
  static bool eq<T extends RangeValue>(
    List<RangeSet<T>> oldSets,
    List<RangeSet<T>> newSets, [
    int from = 0,
    int? to,
  ]) {
    to ??= _far - 1;
    final a = oldSets.where((set) => !set.isEmpty && !newSets.contains(set)).toList();
    final b = newSets.where((set) => !set.isEmpty && !oldSets.contains(set)).toList();
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;

    final sharedChunks = _findSharedChunks(a, b, null);
    // Use -1 to include all ranges (including non-point ranges with maxPoint=-1)
    final sideA = _SpanCursor(a, sharedChunks, -1).goto(from);
    final sideB = _SpanCursor(b, sharedChunks, -1).goto(from);

    for (;;) {
      if (sideA._to != sideB._to ||
          !_sameValues(sideA._active, sideB._active) ||
          (sideA._point != null &&
              (sideB._point == null || !sideA._point!.eq(sideB._point!)))) {
        return false;
      }
      if (sideA._to > to) return true;
      sideA.next();
      sideB.next();
    }
  }

  /// Iterate over a group of range sets at the same time, notifying
  /// the iterator about the ranges covering every given piece of content.
  static int spans<T extends RangeValue>(
    List<RangeSet<T>> sets,
    int from,
    int to,
    SpanIterator<T> iterator, [
    int minPointSize = -1,
  ]) {
    final cursor = _SpanCursor(sets, null, minPointSize).goto(from);
    var pos = from;
    var openRanges = cursor._openStart;

    for (;;) {
      final curTo = cursor._to < to ? cursor._to : to;
      if (cursor._point != null) {
        final active = cursor._activeForPoint(cursor._to);
        final openCount = cursor._pointFrom < from
            ? active.length + 1
            : cursor._point!.startSide < 0
                ? active.length
                : (active.length < openRanges ? active.length : openRanges);
        iterator.point(
          pos,
          curTo,
          cursor._point as T,
          active,
          openCount,
          cursor._pointRank,
        );
        openRanges = cursor._openEnd(curTo) < active.length
            ? cursor._openEnd(curTo)
            : active.length;
      } else if (curTo > pos) {
        iterator.span(pos, curTo, cursor._active, openRanges);
        openRanges = cursor._openEnd(curTo);
      }
      if (cursor._to > to) {
        return openRanges + (cursor._point != null && cursor._to > to ? 1 : 0);
      }
      pos = cursor._to;
      cursor.next();
    }
  }

  /// Create a range set for the given range or array of ranges.
  static RangeSet<T> of<T extends RangeValue>(
    List<Range<T>> ranges, [
    bool sort = false,
  ]) {
    final builder = RangeSetBuilder<T>();
    final sorted = sort ? (List.of(ranges)..sort(_cmpRange)) : ranges;
    for (final range in sorted) {
      builder.add(range.from, range.to, range.value);
    }
    return builder.finish();
  }

  /// Join an array of range sets into a single set.
  static RangeSet<T> join<T extends RangeValue>(List<RangeSet<T>> sets) {
    if (sets.isEmpty) return empty<T>();
    var result = sets[sets.length - 1];
    for (var i = sets.length - 2; i >= 0; i--) {
      for (var layer = sets[i]; !layer.isEmpty; layer = layer.nextLayer) {
        result = RangeSet._(
          layer.chunkPos,
          layer.chunk,
          result,
          layer.maxPoint > result.maxPoint ? layer.maxPoint : result.maxPoint,
        );
      }
    }
    return result;
  }

  /// The empty set of ranges.
  static RangeSet<T> empty<T extends RangeValue>() =>
      _EmptyRangeSet._instance.cast<T>();
}

/// Special empty range set implementation with self-referential nextLayer.
class _EmptyRangeSet<T extends RangeValue> extends RangeSet<T> {
  static final _EmptyRangeSet<Never> _instance = _EmptyRangeSet._();

  _EmptyRangeSet._() : super._([], [], null, -1);

  @override
  RangeSet<T> get nextLayer => this;

  @override
  bool get isEmpty => true;

  /// Cast this empty set to any RangeValue type.
  RangeSet<U> cast<U extends RangeValue>() => _EmptyRangeSetCast<U>();
}

class _EmptyRangeSetCast<T extends RangeValue> extends RangeSet<T> {
  _EmptyRangeSetCast() : super._([], [], null, -1);

  @override
  RangeSet<T> get nextLayer => this;

  @override
  bool get isEmpty => true;
}

/// A range set builder helps build up a [RangeSet] directly.
class RangeSetBuilder<T extends RangeValue> {
  final List<Chunk<T>> _chunks = [];
  final List<int> _chunkPos = [];
  int _chunkStart = -1;
  T? _last;
  int _lastFrom = -_far;
  int _lastTo = -_far;
  List<int> _from = [];
  List<int> _to = [];
  List<T> _value = [];
  int _maxPoint = -1;
  int _setMaxPoint = -1;
  RangeSetBuilder<T>? _nextLayer;

  void _finishChunk(bool newArrays) {
    _chunks.add(Chunk(_from, _to, _value, _maxPoint));
    _chunkPos.add(_chunkStart);
    _chunkStart = -1;
    _setMaxPoint = _setMaxPoint > _maxPoint ? _setMaxPoint : _maxPoint;
    _maxPoint = -1;
    if (newArrays) {
      _from = [];
      _to = [];
      _value = [];
    }
  }

  /// Add a range. Ranges should be added in sorted order.
  void add(int from, int to, T value) {
    if (!_addInner(from, to, value)) {
      (_nextLayer ??= RangeSetBuilder<T>()).add(from, to, value);
    }
  }

  bool _addInner(int from, int to, T value) {
    final diff = from - _lastTo != 0
        ? from - _lastTo
        : value.startSide - (_last?.endSide ?? 0);
    if (diff <= 0 &&
        (from - _lastFrom != 0
                ? from - _lastFrom
                : value.startSide - (_last?.startSide ?? 0)) <
            0) {
      throw ArgumentError(
        'Ranges must be added sorted by `from` position and `startSide`',
      );
    }
    if (diff < 0) return false;
    if (_from.length == _chunkSize) _finishChunk(true);
    if (_chunkStart < 0) _chunkStart = from;
    _from.add(from - _chunkStart);
    _to.add(to - _chunkStart);
    _last = value;
    _lastFrom = from;
    _lastTo = to;
    _value.add(value);
    if (value.point) {
      _maxPoint = _maxPoint > to - from ? _maxPoint : to - from;
    }
    return true;
  }

  bool _addChunk(int from, Chunk<T> chunk) {
    if ((from - _lastTo != 0
            ? from - _lastTo
            : chunk.value[0].startSide - (_last?.endSide ?? 0)) <
        0) {
      return false;
    }
    if (_from.isNotEmpty) _finishChunk(true);
    _setMaxPoint = _setMaxPoint > chunk.maxPoint ? _setMaxPoint : chunk.maxPoint;
    _chunks.add(chunk);
    _chunkPos.add(from);
    final last = chunk.value.length - 1;
    _last = chunk.value[last];
    _lastFrom = chunk.from[last] + from;
    _lastTo = chunk.to[last] + from;
    return true;
  }

  /// Finish the range set. Returns the new set.
  RangeSet<T> finish() => _finishInner(RangeSet.empty<T>());

  RangeSet<T> _finishInner(RangeSet<T> next) {
    if (_from.isNotEmpty) _finishChunk(false);
    if (_chunks.isEmpty) return next;
    final result = RangeSet.create(
      _chunkPos,
      _chunks,
      _nextLayer != null ? _nextLayer!._finishInner(next) : next,
      _setMaxPoint,
    );
    return result;
  }
}

Set<Chunk<RangeValue>>? _findSharedChunks<T extends RangeValue>(
  List<RangeSet<T>> a,
  List<RangeSet<T>> b,
  ChangeDesc? textDiff,
) {
  final inA = <Chunk<RangeValue>, int>{};
  for (final set in a) {
    for (var i = 0; i < set.chunk.length; i++) {
      if (set.chunk[i].maxPoint <= 0) {
        inA[set.chunk[i]] = set.chunkPos[i];
      }
    }
  }

  final shared = <Chunk<RangeValue>>{};
  for (final set in b) {
    for (var i = 0; i < set.chunk.length; i++) {
      final known = inA[set.chunk[i]];
      if (known != null) {
        final mappedPos = textDiff?.mapPos(known) ?? known;
        if (mappedPos == set.chunkPos[i]) {
          final touches = textDiff?.touchesRange(known, known + set.chunk[i].length);
          if (touches != true) {
            shared.add(set.chunk[i]);
          }
        }
      }
    }
  }

  return shared.isEmpty ? null : shared;
}

class _LayerCursor<T extends RangeValue> implements _RangeCursorInternal<T> {
  final RangeSet<T> _layer;
  final Set<Chunk<RangeValue>>? _skip;
  final int _minPoint;
  final int _rank;

  @override
  int from = 0;
  @override
  int to = 0;
  @override
  T? value;

  int _chunkIndex = 0;
  int _rangeIndex = 0;

  _LayerCursor(this._layer, this._skip, this._minPoint, [this._rank = 0]);

  int get _startSide => value?.startSide ?? 0;
  int get _endSide => value?.endSide ?? 0;

  _LayerCursor<T> goto(int pos, [int side = -_far]) {
    _chunkIndex = _rangeIndex = 0;
    _gotoInner(pos, side, false);
    return this;
  }

  void _gotoInner(int pos, int side, bool forward) {
    while (_chunkIndex < _layer.chunk.length) {
      final nextChunk = _layer.chunk[_chunkIndex];
      if (!(_skip != null && _skip!.contains(nextChunk) ||
          _layer._chunkEnd(_chunkIndex) < pos ||
          nextChunk.maxPoint < _minPoint)) {
        break;
      }
      _chunkIndex++;
      forward = false;
    }
    if (_chunkIndex < _layer.chunk.length) {
      final rangeIndex = _layer.chunk[_chunkIndex]
          .findIndex(pos - _layer.chunkPos[_chunkIndex], side, true);
      if (!forward || _rangeIndex < rangeIndex) _setRangeIndex(rangeIndex);
    }
    next();
  }

  void forward(int pos, int side) {
    if ((to - pos != 0 ? to - pos : _endSide - side) < 0) {
      _gotoInner(pos, side, true);
    }
  }

  @override
  void next() {
    for (;;) {
      if (_chunkIndex == _layer.chunk.length) {
        from = to = _far;
        value = null;
        break;
      } else {
        final chunkPos = _layer.chunkPos[_chunkIndex];
        final chunk = _layer.chunk[_chunkIndex];
        from = chunkPos + chunk.from[_rangeIndex];
        to = chunkPos + chunk.to[_rangeIndex];
        value = chunk.value[_rangeIndex];
        _setRangeIndex(_rangeIndex + 1);
        if (_minPoint < 0 || (value!.point && to - from >= _minPoint)) break;
      }
    }
  }

  void _setRangeIndex(int index) {
    if (index == _layer.chunk[_chunkIndex].value.length) {
      _chunkIndex++;
      if (_skip != null) {
        while (_chunkIndex < _layer.chunk.length &&
            _skip!.contains(_layer.chunk[_chunkIndex])) {
          _chunkIndex++;
        }
      }
      _rangeIndex = 0;
    } else {
      _rangeIndex = index;
    }
  }

  void _nextChunk() {
    _chunkIndex++;
    _rangeIndex = 0;
    next();
  }

  int compareTo(_LayerCursor<T> other) {
    var diff = from - other.from;
    if (diff != 0) return diff;
    diff = _startSide - other._startSide;
    if (diff != 0) return diff;
    diff = _rank - other._rank;
    if (diff != 0) return diff;
    diff = to - other.to;
    if (diff != 0) return diff;
    return _endSide - other._endSide;
  }
}

class _HeapCursor<T extends RangeValue> implements _RangeCursorInternal<T> {
  final List<_LayerCursor<T>> _heap;

  @override
  int from = 0;
  @override
  int to = 0;
  @override
  T? value;
  int _rank = 0;

  _HeapCursor(this._heap);

  static RangeCursor<T> create<T extends RangeValue>(
    List<RangeSet<T>> sets, [
    Set<Chunk<RangeValue>>? skip,
    int minPoint = -1,
  ]) {
    final heap = <_LayerCursor<T>>[];
    for (var i = 0; i < sets.length; i++) {
      for (var cur = sets[i]; !cur.isEmpty; cur = cur.nextLayer) {
        if (cur.maxPoint >= minPoint) {
          heap.add(_LayerCursor(cur, skip, minPoint, i));
        }
      }
    }
    return heap.length == 1 ? heap[0] : _HeapCursor(heap);
  }

  int get _startSide => value?.startSide ?? 0;

  _HeapCursor<T> goto(int pos, [int side = -_far]) {
    for (final cur in _heap) {
      cur.goto(pos, side);
    }
    if (_heap.isNotEmpty) {
      for (var i = _heap.length >> 1; i >= 0; i--) {
        _heapBubble(i);
      }
    }
    next();
    return this;
  }

  void forward(int pos, int side) {
    for (final cur in _heap) {
      cur.forward(pos, side);
    }
    for (var i = _heap.length >> 1; i >= 0; i--) {
      _heapBubble(i);
    }
    if ((to - pos != 0 ? to - pos : value!.endSide - side) < 0) next();
  }

  @override
  void next() {
    if (_heap.isEmpty) {
      from = to = _far;
      value = null;
      _rank = -1;
    } else {
      final top = _heap[0];
      from = top.from;
      to = top.to;
      value = top.value;
      _rank = top._rank;
      if (top.value != null) top.next();
      _heapBubble(0);
    }
  }

  void _heapBubble(int index) {
    final cur = _heap[index];
    for (;;) {
      var childIndex = (index << 1) + 1;
      if (childIndex >= _heap.length) break;
      var child = _heap[childIndex];
      if (childIndex + 1 < _heap.length &&
          child.compareTo(_heap[childIndex + 1]) >= 0) {
        child = _heap[childIndex + 1];
        childIndex++;
      }
      if (cur.compareTo(child) < 0) break;
      _heap[childIndex] = cur;
      _heap[index] = child;
      index = childIndex;
    }
  }
}

class _SpanCursor<T extends RangeValue> {
  final _RangeCursorInternal<T> _cursor;
  final int _minPoint;

  final List<T> _active = [];
  final List<int> _activeTo = [];
  final List<int> _activeRank = [];
  int _minActive = -1;

  T? _point;
  int _pointFrom = 0;
  int _pointRank = 0;

  int _to = -_far;
  int _endSide = 0;
  int _openStart = -1;

  _SpanCursor(
    List<RangeSet<T>> sets,
    Set<Chunk<RangeValue>>? skip,
    this._minPoint,
  ) : _cursor = _createCursor(sets, skip, _minPoint);

  static _RangeCursorInternal<T> _createCursor<T extends RangeValue>(
    List<RangeSet<T>> sets,
    Set<Chunk<RangeValue>>? skip,
    int minPoint,
  ) {
    final cursor = _HeapCursor.create<T>(sets, skip, minPoint);
    if (cursor is _HeapCursor<T>) {
      return cursor;
    }
    return cursor as _LayerCursor<T>;
  }

  _SpanCursor<T> goto(int pos, [int side = -_far]) {
    _cursor.goto(pos, side);
    _active.clear();
    _activeTo.clear();
    _activeRank.clear();
    _minActive = -1;
    _to = pos;
    _endSide = side;
    _openStart = -1;
    next();
    return this;
  }

  void _forward(int pos, int side) {
    while (_minActive > -1 &&
        (_activeTo[_minActive] - pos != 0
                ? _activeTo[_minActive] - pos
                : _active[_minActive].endSide - side) <
            0) {
      _removeActive(_minActive);
    }
    _cursor.forward(pos, side);
  }

  void _removeActive(int index) {
    _remove(_active, index);
    _remove(_activeTo, index);
    _remove(_activeRank, index);
    _minActive = _findMinIndex(_active, _activeTo);
  }

  void _addActive(List<int>? trackOpen) {
    var i = 0;
    final value = _cursor.value!;
    final to = _cursor.to;
    final rank = _cursor._rank;

    while (i < _activeRank.length &&
        (rank - _activeRank[i] != 0
                ? rank - _activeRank[i]
                : to - _activeTo[i]) >
            0) {
      i++;
    }
    _insert(_active, i, value as T);
    _insert(_activeTo, i, to);
    _insert(_activeRank, i, rank);
    if (trackOpen != null) _insert(trackOpen, i, _cursor.from);
    _minActive = _findMinIndex(_active, _activeTo);
  }

  void next() {
    final from = _to;
    final wasPoint = _point;
    _point = null;
    final trackOpen = _openStart < 0 ? <int>[] : null;

    for (;;) {
      final a = _minActive;
      if (a > -1 &&
          (_activeTo[a] - _cursor.from != 0
                  ? _activeTo[a] - _cursor.from
                  : _active[a].endSide - _cursor._startSide) <
              0) {
        if (_activeTo[a] > from) {
          _to = _activeTo[a];
          _endSide = _active[a].endSide;
          break;
        }
        _removeActive(a);
        if (trackOpen != null) _remove(trackOpen, a);
      } else if (_cursor.value == null) {
        _to = _endSide = _far;
        break;
      } else if (_cursor.from > from) {
        _to = _cursor.from;
        _endSide = _cursor._startSide;
        break;
      } else {
        final nextVal = _cursor.value!;
        if (!nextVal.point) {
          _addActive(trackOpen);
          _cursor.next();
        } else if (wasPoint != null &&
            _cursor.to == _to &&
            _cursor.from < _cursor.to) {
          _cursor.next();
        } else {
          _point = nextVal as T;
          _pointFrom = _cursor.from;
          _pointRank = _cursor._rank;
          _to = _cursor.to;
          _endSide = nextVal.endSide;
          _cursor.next();
          _forward(_to, _endSide);
          break;
        }
      }
    }

    if (trackOpen != null) {
      _openStart = 0;
      for (var i = trackOpen.length - 1; i >= 0 && trackOpen[i] < from; i--) {
        _openStart++;
      }
    }
  }

  List<T> _activeForPoint(int to) {
    if (_active.isEmpty) return _active;
    final active = <T>[];
    for (var i = _active.length - 1; i >= 0; i--) {
      if (_activeRank[i] < _pointRank) break;
      if (_activeTo[i] > to ||
          (_activeTo[i] == to && _active[i].endSide >= _point!.endSide)) {
        active.add(_active[i]);
      }
    }
    return active.reversed.toList();
  }

  int _openEnd(int to) {
    var open = 0;
    for (var i = _activeTo.length - 1; i >= 0 && _activeTo[i] > to; i--) {
      open++;
    }
    return open;
  }
}

void _compare<T extends RangeValue>(
  _SpanCursor<T> a,
  int startA,
  _SpanCursor<T> b,
  int startB,
  int length,
  RangeComparator<T> comparator,
) {
  a.goto(startA);
  b.goto(startB);
  final endB = startB + length;
  var pos = startB;
  final dPos = startB - startA;

  for (;;) {
    final dEnd = (a._to + dPos) - b._to;
    final diff = dEnd != 0 ? dEnd : a._endSide - b._endSide;
    final end = diff < 0 ? a._to + dPos : b._to;
    final clipEnd = end < endB ? end : endB;

    if (a._point != null || b._point != null) {
      if (!(a._point != null &&
          b._point != null &&
          (a._point == b._point || a._point!.eq(b._point!)) &&
          _sameValues(a._activeForPoint(a._to), b._activeForPoint(b._to)))) {
        comparator.comparePoint(pos, clipEnd, a._point, b._point);
      }
    } else {
      if (clipEnd > pos && !_sameValues(a._active, b._active)) {
        comparator.compareRange(pos, clipEnd, a._active, b._active);
      }
    }

    if (end > endB) break;
    if ((dEnd != 0 || a._openEnd(end) != b._openEnd(end))) {
      comparator.boundChange(end);
    }
    pos = end;
    if (diff <= 0) a.next();
    if (diff >= 0) b.next();
  }
}

bool _sameValues<T extends RangeValue>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i] && !a[i].eq(b[i])) return false;
  }
  return true;
}

void _remove<E>(List<E> array, int index) {
  for (var i = index; i < array.length - 1; i++) {
    array[i] = array[i + 1];
  }
  array.removeLast();
}

void _insert<E>(List<E> array, int index, E value) {
  array.add(value);
  for (var i = array.length - 1; i > index; i--) {
    array[i] = array[i - 1];
  }
  array[index] = value;
}

int _findMinIndex<T extends RangeValue>(List<T> value, List<int> array) {
  var found = -1;
  var foundPos = _far;
  for (var i = 0; i < array.length; i++) {
    final cmp = array[i] - foundPos != 0
        ? array[i] - foundPos
        : value[i].endSide - (found >= 0 ? value[found].endSide : 0);
    if (cmp < 0) {
      found = i;
      foundPos = array[i];
    }
  }
  return found;
}
