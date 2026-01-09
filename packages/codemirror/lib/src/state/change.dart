/// Change description and change set for document modifications.
///
/// This module provides [ChangeDesc] and [ChangeSet] for describing and
/// applying changes to documents.
library;

import 'package:meta/meta.dart';
import '../text/text.dart';

/// Default regex for splitting text into lines.
final RegExp defaultSplit = RegExp(r'\r\n?|\n');

/// Distinguishes different ways in which positions can be mapped.
enum MapMode {
  /// Map a position to a valid new position, even when its context was deleted.
  simple,

  /// Return null if deletion happens across the position.
  trackDel,

  /// Return null if the character _before_ the position is deleted.
  trackBefore,

  /// Return null if the character _after_ the position is deleted.
  trackAfter,
}

/// A change description is a variant of [ChangeSet] that doesn't store
/// the inserted text. As such, it can't be applied, but is cheaper to
/// store and manipulate.
///
/// Sections are encoded as pairs of integers. The first is the length in
/// the current document, and the second is -1 for unaffected sections,
/// and the length of the replacement content otherwise. So an insertion
/// would be (0, n>0), a deletion (n>0, 0), and a replacement two positive
/// numbers.
@immutable
class ChangeDesc {
  /// The sections describing the change.
  @internal
  final List<int> sections;

  /// Create a change description from sections.
  const ChangeDesc(this.sections);

  /// The length of the document before the change.
  int get length {
    var result = 0;
    for (var i = 0; i < sections.length; i += 2) {
      result += sections[i];
    }
    return result;
  }

  /// The length of the document after the change.
  int get newLength {
    var result = 0;
    for (var i = 0; i < sections.length; i += 2) {
      final ins = sections[i + 1];
      result += ins < 0 ? sections[i] : ins;
    }
    return result;
  }

  /// False when there are actual changes in this set.
  bool get empty =>
      sections.isEmpty || (sections.length == 2 && sections[1] < 0);

  /// Iterate over the unchanged parts left by these changes.
  ///
  /// [f] receives posA (position in old doc), posB (position in new doc),
  /// and length of the unchanged region.
  void iterGaps(void Function(int posA, int posB, int length) f) {
    var posA = 0, posB = 0;
    for (var i = 0; i < sections.length;) {
      final len = sections[i++];
      final ins = sections[i++];
      if (ins < 0) {
        f(posA, posB, len);
        posB += len;
      } else {
        posB += ins;
      }
      posA += len;
    }
  }

  /// Iterate over the ranges changed by these changes.
  ///
  /// [f] receives fromA/toA (extent in starting document) and
  /// fromB/toB (extent in changed document).
  ///
  /// When [individual] is true, adjacent changes are reported separately.
  void iterChangedRanges(
    void Function(int fromA, int toA, int fromB, int toB) f, [
    bool individual = false,
  ]) {
    _iterChanges(this, null, (fromA, toA, fromB, toB, _) {
      f(fromA, toA, fromB, toB);
    }, individual);
  }

  /// Get a description of the inverted form of these changes.
  ChangeDesc get invertedDesc {
    final result = <int>[];
    for (var i = 0; i < sections.length;) {
      final len = sections[i++];
      final ins = sections[i++];
      if (ins < 0) {
        result.addAll([len, ins]);
      } else {
        result.addAll([ins, len]);
      }
    }
    return ChangeDesc(result);
  }

  /// Compute the combined effect of applying another set of changes after this one.
  ///
  /// The length of the document after this set should match the length before [other].
  ChangeDesc composeDesc(ChangeDesc other) {
    return empty ? other : other.empty ? this : _composeSets(this, other);
  }

  /// Map this description, which should start with the same document as [other],
  /// over another set of changes.
  ///
  /// When [before] is true, map as if the changes in `this` happened before
  /// the ones in `other`.
  ChangeDesc mapDesc(ChangeDesc other, [bool before = false]) {
    return other.empty ? this : _mapSet(this, other, before);
  }

  /// Map a given position through these changes.
  ///
  /// [assoc] indicates which side the position should be associated with.
  /// When negative, keeps position close to character before; when zero or
  /// positive, associated with character after.
  ///
  /// [mode] determines whether deletions should be reported.
  int? mapPos(int pos, [int assoc = -1, MapMode mode = MapMode.simple]) {
    var posA = 0, posB = 0;
    for (var i = 0; i < sections.length;) {
      final len = sections[i++];
      final ins = sections[i++];
      final endA = posA + len;
      if (ins < 0) {
        if (endA > pos) return posB + (pos - posA);
        posB += len;
      } else {
        if (mode != MapMode.simple &&
            endA >= pos &&
            (mode == MapMode.trackDel && posA < pos && endA > pos ||
                mode == MapMode.trackBefore && posA < pos ||
                mode == MapMode.trackAfter && endA > pos)) {
          return null;
        }
        if (endA > pos || (endA == pos && assoc < 0 && len == 0)) {
          return pos == posA || assoc < 0 ? posB : posB + ins;
        }
        posB += ins;
      }
      posA = endA;
    }
    if (pos > posA) {
      throw RangeError('Position $pos is out of range for changeset of length $posA');
    }
    return posB;
  }

  /// Check whether these changes touch a given range.
  ///
  /// Returns "cover" if one of the changes entirely covers the range,
  /// true if it touches, false otherwise.
  dynamic touchesRange(int from, [int? to]) {
    to ??= from;
    for (var i = 0, pos = 0; i < sections.length && pos <= to;) {
      final len = sections[i++];
      final ins = sections[i++];
      final end = pos + len;
      if (ins >= 0 && pos <= to && end >= from) {
        return pos < from && end > to ? 'cover' : true;
      }
      pos = end;
    }
    return false;
  }

  @override
  String toString() {
    final result = StringBuffer();
    for (var i = 0; i < sections.length;) {
      final len = sections[i++];
      final ins = sections[i++];
      if (result.isNotEmpty) result.write(' ');
      result.write(len);
      if (ins >= 0) result.write(':$ins');
    }
    return result.toString();
  }

  /// Serialize this change desc to a JSON-representable value.
  List<int> toJson() => sections;

  /// Create a change desc from its JSON representation.
  static ChangeDesc fromJson(dynamic json) {
    if (json is! List ||
        json.length % 2 != 0 ||
        json.any((a) => a is! int)) {
      throw RangeError('Invalid JSON representation of ChangeDesc');
    }
    return ChangeDesc(List<int>.from(json));
  }

  /// Internal factory.
  @internal
  static ChangeDesc create(List<int> sections) => ChangeDesc(sections);
}

/// Represents a single change specification.
class ChangeSpec {
  final int from;
  final int? to;
  final Object? insert; // String or Text

  const ChangeSpec({required this.from, this.to, this.insert});
}

/// A change set represents a group of modifications to a document.
///
/// It stores the document length, and can only be applied to documents
/// with exactly that length.
@immutable
class ChangeSet extends ChangeDesc {
  /// The inserted text segments.
  @internal
  final List<Text> inserted;

  /// Create a change set from sections and inserted text.
  const ChangeSet(super.sections, this.inserted);

  /// Apply the changes to a document, returning the modified document.
  Text apply(Text doc) {
    if (length != doc.length) {
      throw RangeError('Applying change set to a document with the wrong length');
    }
    var result = doc;
    _iterChanges(this, inserted, (fromA, toA, fromB, _, text) {
      result = result.replace(fromB, fromB + (toA - fromA), text);
    }, false);
    return result;
  }

  @override
  ChangeSet mapDesc(ChangeDesc other, [bool before = false]) {
    return _mapSet(this, other, before, mkSet: true) as ChangeSet;
  }

  /// Given the document as it existed _before_ the changes, return a change set
  /// that represents the inverse of this set.
  ChangeSet invert(Text doc) {
    final newSections = sections.toList();
    final newInserted = <Text>[];
    for (var i = 0, pos = 0; i < newSections.length; i += 2) {
      final len = newSections[i];
      final ins = newSections[i + 1];
      if (ins >= 0) {
        newSections[i] = ins;
        newSections[i + 1] = len;
        final index = i >> 1;
        while (newInserted.length < index) {
          newInserted.add(Text.empty);
        }
        newInserted.add(len > 0 ? doc.slice(pos, pos + len) : Text.empty);
      }
      pos += len;
    }
    return ChangeSet(newSections, newInserted);
  }

  /// Combine two subsequent change sets into a single set.
  ///
  /// [other] must start in the document produced by `this`.
  ChangeSet compose(ChangeSet other) {
    if (empty) return other;
    if (other.empty) return this;
    return _composeSets(this, other, mkSet: true) as ChangeSet;
  }

  /// Whether this change set is empty (no actual changes).
  @override
  bool get empty => super.empty;

  /// Given another change set starting in the same document, maps this
  /// change set over the other.
  ///
  /// When [before] is true, order changes as if `this` comes before [other].
  ChangeSet map(ChangeDesc other, [bool before = false]) {
    return other.empty ? this : _mapSet(this, other, before, mkSet: true) as ChangeSet;
  }

  /// Iterate over the changed ranges in the document.
  ///
  /// [f] receives fromA/toA (range in original), fromB/toB (range in new),
  /// and the inserted text.
  void iterChanges(
    void Function(int fromA, int toA, int fromB, int toB, Text inserted) f, [
    bool individual = false,
  ]) {
    _iterChanges(this, inserted, f, individual);
  }

  /// Get a [ChangeDesc] for this change set.
  ChangeDesc get desc => ChangeDesc.create(sections);

  /// Filter this changeset so that only the ranges in [ranges] are kept.
  /// 
  /// The [ranges] list contains pairs of [start, end] positions that should
  /// be kept (not filtered out). Returns a record with:
  /// - `changes`: The filtered ChangeSet
  /// - `filtered`: A ChangeDesc describing what was filtered
  ({ChangeSet changes, ChangeDesc filtered}) filter(List<int> ranges) {
    final resultSections = <int>[];
    final resultInserted = <Text>[];
    final filteredSections = <int>[];
    final iter = _SectionIter(this);
    
    var i = 0;
    var pos = 0;
    
    done:
    while (true) {
      final next = i == ranges.length ? 1000000000 : ranges[i++];
      while (pos < next || (pos == next && iter.len == 0)) {
        if (iter.done) break done;
        final len = iter.len < (next - pos) ? iter.len : (next - pos);
        _addSection(filteredSections, len, -1);
        final ins = iter.ins == -1 ? -1 : (iter.off == 0 ? iter.ins : 0);
        _addSection(resultSections, len, ins);
        if (ins > 0) _addInsert(resultInserted, resultSections, iter.text);
        iter.forward(len);
        pos += len;
      }
      if (i >= ranges.length) break;
      final end = ranges[i++];
      while (pos < end) {
        if (iter.done) break done;
        final len = iter.len < (end - pos) ? iter.len : (end - pos);
        _addSection(resultSections, len, -1);
        _addSection(filteredSections, len, iter.ins == -1 ? -1 : (iter.off == 0 ? iter.ins : 0));
        iter.forward(len);
        pos += len;
      }
    }
    
    return (
      changes: ChangeSet(resultSections, resultInserted),
      filtered: ChangeDesc.create(filteredSections),
    );
  }

  /// Serialize this change set to a JSON-representable value.
  List<dynamic> toChangeSetJson() {
    final parts = <dynamic>[];
    for (var i = 0; i < sections.length; i += 2) {
      final len = sections[i];
      final ins = sections[i + 1];
      if (ins < 0) {
        parts.add(len);
      } else if (ins == 0) {
        parts.add([len]);
      } else {
        parts.add([len, ...inserted[i >> 1].toJson()]);
      }
    }
    return parts;
  }

  /// Create a change set for the given changes.
  static ChangeSet of(List<dynamic> changes, int length, [String? lineSep]) {
    final sections = <int>[];
    final inserted = <Text>[];
    var pos = 0;
    ChangeSet? total;

    void flush([bool force = false]) {
      if (!force && sections.isEmpty) return;
      if (pos < length) _addSection(sections, length - pos, -1);
      final set = ChangeSet(List.unmodifiable(sections), List.unmodifiable(inserted));
      total = total != null ? total!.compose(set.map(total!)) : set;
      sections.clear();
      inserted.clear();
      pos = 0;
    }

    void process(dynamic spec) {
      if (spec is List) {
        for (final sub in spec) {
          process(sub);
        }
      } else if (spec is ChangeSet) {
        if (spec.length != length) {
          throw RangeError(
              'Mismatched change set length (got ${spec.length}, expected $length)');
        }
        flush();
        total = total != null ? total!.compose(spec.map(total!)) : spec;
      } else if (spec is ChangeSpec) {
        final from = spec.from;
        final to = spec.to ?? from;
        final insert = spec.insert;
        if (from > to || from < 0 || to > length) {
          throw RangeError('Invalid change range $from to $to (in doc of length $length)');
        }
        Text insText;
        if (insert == null) {
          insText = Text.empty;
        } else if (insert is String) {
          insText = Text.of(insert.split(lineSep != null ? RegExp(lineSep) : defaultSplit));
        } else {
          insText = insert as Text;
        }
        final insLen = insText.length;
        if (from == to && insLen == 0) return;
        if (from < pos) flush();
        if (from > pos) _addSection(sections, from - pos, -1);
        _addSection(sections, to - from, insLen);
        _addInsert(inserted, sections, insText);
        pos = to;
      } else if (spec is Map<String, dynamic>) {
        // Handle map-style specs: {from: int, to?: int, insert?: String|Text}
        final from = spec['from'] as int;
        final to = (spec['to'] as int?) ?? from;
        final insert = spec['insert'];
        process(ChangeSpec(from: from, to: to, insert: insert));
      }
    }

    for (final change in changes) {
      process(change);
    }
    flush(total == null);
    return total!;
  }

  /// Create an empty changeset of the given length.
  static ChangeSet emptySet(int length) {
    return ChangeSet(length > 0 ? [length, -1] : [], const []);
  }

  /// Create a changeset from its JSON representation.
  static ChangeSet fromJson(dynamic json) {
    if (json is! List) {
      throw RangeError('Invalid JSON representation of ChangeSet');
    }
    final sections = <int>[];
    final inserted = <Text>[];
    for (var i = 0; i < json.length; i++) {
      final part = json[i];
      if (part is int) {
        sections.addAll([part, -1]);
      } else if (part is! List ||
          part.isEmpty ||
          part[0] is! int ||
          part.skip(1).any((e) => e is! String)) {
        throw RangeError('Invalid JSON representation of ChangeSet');
      } else if (part.length == 1) {
        sections.addAll([part[0] as int, 0]);
      } else {
        while (inserted.length < i) {
          inserted.add(Text.empty);
        }
        inserted.add(Text.of(part.skip(1).cast<String>().toList()));
        sections.addAll([part[0] as int, inserted[i].length]);
      }
    }
    return ChangeSet(sections, inserted);
  }

  /// Internal factory.
  @internal
  static ChangeSet createSet(List<int> sections, List<Text> inserted) {
    return ChangeSet(sections, inserted);
  }
}

// Helper to add a section, merging with previous if possible
void _addSection(List<int> sections, int len, int ins, [bool forceJoin = false]) {
  if (len == 0 && ins <= 0) return;
  final last = sections.length - 2;
  if (last >= 0 && ins <= 0 && ins == sections[last + 1]) {
    sections[last] += len;
  } else if (last >= 0 && len == 0 && sections[last] == 0) {
    sections[last + 1] += ins;
  } else if (forceJoin && last >= 0) {
    sections[last] += len;
    sections[last + 1] += ins;
  } else {
    sections.addAll([len, ins]);
  }
}

// Helper to add inserted text
void _addInsert(List<Text> values, List<int> sections, Text value) {
  if (value.isEmpty) return;
  final index = (sections.length - 2) >> 1;
  if (index < values.length) {
    values[values.length - 1] = values[values.length - 1].append(value);
  } else {
    while (values.length < index) {
      values.add(Text.empty);
    }
    values.add(value);
  }
}

// Iterate over changes
void _iterChanges(
  ChangeDesc desc,
  List<Text>? inserted,
  void Function(int fromA, int toA, int fromB, int toB, Text text) f,
  bool individual,
) {
  for (var posA = 0, posB = 0, i = 0; i < desc.sections.length;) {
    var len = desc.sections[i++];
    var ins = desc.sections[i++];
    if (ins < 0) {
      posA += len;
      posB += len;
    } else {
      var endA = posA, endB = posB;
      var text = Text.empty;
      for (;;) {
        endA += len;
        endB += ins;
        if (ins > 0 && inserted != null) {
          text = text.append(inserted[(i - 2) >> 1]);
        }
        if (individual || i == desc.sections.length || desc.sections[i + 1] < 0) {
          break;
        }
        len = desc.sections[i++];
        ins = desc.sections[i++];
      }
      f(posA, endA, posB, endB, text);
      posA = endA;
      posB = endB;
    }
  }
}

/// Section iterator for composing and mapping change sets.
class _SectionIter {
  final ChangeDesc set;
  int i = 0;
  int len = 0;
  int off = 0;
  int ins = 0;

  _SectionIter(this.set) {
    next();
  }

  void next() {
    if (i < set.sections.length) {
      len = set.sections[i++];
      ins = set.sections[i++];
    } else {
      len = 0;
      ins = -2;
    }
    off = 0;
  }

  bool get done => ins == -2;

  int get len2 => ins < 0 ? len : ins;

  Text get text {
    if (set is! ChangeSet) return Text.empty;
    final cs = set as ChangeSet;
    final index = (i - 2) >> 1;
    return index >= cs.inserted.length ? Text.empty : cs.inserted[index];
  }

  Text textBit([int? len]) {
    if (set is! ChangeSet) return Text.empty;
    final cs = set as ChangeSet;
    final index = (i - 2) >> 1;
    if (index >= cs.inserted.length && (len == null || len == 0)) {
      return Text.empty;
    }
    return cs.inserted[index].slice(off, len == null ? null : off + len);
  }

  void forward(int length) {
    if (length == len) {
      next();
    } else {
      len -= length;
      off += length;
    }
  }

  void forward2(int length) {
    if (ins == -1) {
      forward(length);
    } else if (length == ins) {
      next();
    } else {
      ins -= length;
      off += length;
    }
  }
}

// Map a change set over another
ChangeDesc _mapSet(
  ChangeDesc setA,
  ChangeDesc setB,
  bool before, {
  bool mkSet = false,
}) {
  final sections = <int>[];
  final insert = mkSet ? <Text>[] : null;
  final a = _SectionIter(setA);
  final b = _SectionIter(setB);
  var inserted = -1;

  while (true) {
    if (a.done && b.len > 0 || b.done && a.len > 0) {
      throw StateError('Mismatched change set lengths');
    } else if (a.ins == -1 && b.ins == -1) {
      // Move across ranges skipped by both sets
      final len = a.len < b.len ? a.len : b.len;
      _addSection(sections, len, -1);
      a.forward(len);
      b.forward(len);
    } else if (b.ins >= 0 &&
        (a.ins < 0 ||
            inserted == a.i ||
            a.off == 0 && (b.len < a.len || b.len == a.len && !before))) {
      // Change in B comes before next change in A
      var len = b.len;
      _addSection(sections, b.ins, -1);
      while (len > 0) {
        final piece = a.len < len ? a.len : len;
        if (a.ins >= 0 && inserted < a.i && a.len <= piece) {
          _addSection(sections, 0, a.ins);
          if (insert != null) _addInsert(insert, sections, a.text);
          inserted = a.i;
        }
        a.forward(piece);
        len -= piece;
      }
      b.next();
    } else if (a.ins >= 0) {
      // Process change in A
      var len = 0, left = a.len;
      while (left > 0) {
        if (b.ins == -1) {
          final piece = left < b.len ? left : b.len;
          len += piece;
          left -= piece;
          b.forward(piece);
        } else if (b.ins == 0 && b.len < left) {
          left -= b.len;
          b.next();
        } else {
          break;
        }
      }
      _addSection(sections, len, inserted < a.i ? a.ins : 0);
      if (insert != null && inserted < a.i) {
        _addInsert(insert, sections, a.text);
      }
      inserted = a.i;
      a.forward(a.len - left);
    } else if (a.done && b.done) {
      return insert != null
          ? ChangeSet.createSet(sections, insert)
          : ChangeDesc.create(sections);
    } else {
      throw StateError('Mismatched change set lengths');
    }
  }
}

// Compose two change sets
ChangeDesc _composeSets(
  ChangeDesc setA,
  ChangeDesc setB, {
  bool mkSet = false,
}) {
  final sections = <int>[];
  final insert = mkSet ? <Text>[] : null;
  final a = _SectionIter(setA);
  final b = _SectionIter(setB);
  var open = false;

  while (true) {
    if (a.done && b.done) {
      return insert != null
          ? ChangeSet.createSet(sections, insert)
          : ChangeDesc.create(sections);
    } else if (a.ins == 0) {
      // Deletion in A
      _addSection(sections, a.len, 0, open);
      a.next();
    } else if (b.len == 0 && !b.done) {
      // Insertion in B
      _addSection(sections, 0, b.ins, open);
      if (insert != null) _addInsert(insert, sections, b.text);
      b.next();
    } else if (a.done || b.done) {
      throw StateError('Mismatched change set lengths');
    } else {
      final len = a.len2 < b.len ? a.len2 : b.len;
      final sectionLen = sections.length;
      if (a.ins == -1) {
        final insB = b.ins == -1 ? -1 : (b.off != 0 ? 0 : b.ins);
        _addSection(sections, len, insB, open);
        if (insert != null && insB > 0) _addInsert(insert, sections, b.text);
      } else if (b.ins == -1) {
        _addSection(sections, a.off != 0 ? 0 : a.len, len, open);
        if (insert != null) _addInsert(insert, sections, a.textBit(len));
      } else {
        _addSection(sections, a.off != 0 ? 0 : a.len, b.off != 0 ? 0 : b.ins, open);
        if (insert != null && b.off == 0) _addInsert(insert, sections, b.text);
      }
      open = (a.ins > len || b.ins >= 0 && b.len > len) &&
          (open || sections.length > sectionLen);
      a.forward2(len);
      b.forward(len);
    }
  }
}
