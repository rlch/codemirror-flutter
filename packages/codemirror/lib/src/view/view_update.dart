/// View update - describes a view update event.
///
/// This module provides [ViewUpdate], which is passed to view plugins and
/// update listeners to describe what changed during an update.
library;

import 'package:meta/meta.dart';

import '../state/change.dart';
import '../state/state.dart';
import '../state/transaction.dart';

// ============================================================================
// UpdateFlag - Bit flags for update types
// ============================================================================

/// Bit flags indicating what changed in an update.
abstract final class UpdateFlag {
  /// The viewport changed.
  static const int viewport = 1;

  /// The viewport moved (but may not have changed size).
  static const int viewportMoved = 2;

  /// Height information changed.
  static const int height = 4;

  /// Geometry (width, padding) changed.
  static const int geometry = 8;

  /// Focus changed.
  static const int focus = 16;
}

// ============================================================================
// ChangedRange - Tracks changed document ranges
// ============================================================================

/// Represents a range that changed in the document.
///
/// The `fromA`/`toA` positions are in the old document, while
/// `fromB`/`toB` are in the new document.
@immutable
class ChangedRange {
  /// Start position in the old document.
  final int fromA;

  /// End position in the old document.
  final int toA;

  /// Start position in the new document.
  final int fromB;

  /// End position in the new document.
  final int toB;

  const ChangedRange(this.fromA, this.toA, this.fromB, this.toB);

  /// Create a changed range from a single position change.
  factory ChangedRange.single(int from, int to, int length) {
    return ChangedRange(from, to, from, from + length);
  }

  /// Add this range to a set of ranges, merging if overlapping.
  List<ChangedRange> addToSet(List<ChangedRange> set) {
    var i = set.length;
    var me = this;

    for (; i > 0; i--) {
      final range = set[i - 1];
      if (range.fromA > toA || range.toA < fromA) continue;

      // Ranges overlap, merge them
      final unionFromA = range.fromA < me.fromA ? range.fromA : me.fromA;
      final unionToA = range.toA > me.toA ? range.toA : me.toA;
      final unionFromB = range.fromB < me.fromB ? range.fromB : me.fromB;
      final unionToB = range.toB > me.toB ? range.toB : me.toB;

      me = ChangedRange(unionFromA, unionToA, unionFromB, unionToB);
      set.removeAt(i - 1);
    }

    // Find correct position to insert
    var insertAt = 0;
    for (; insertAt < set.length; insertAt++) {
      if (set[insertAt].fromA >= me.fromA) break;
    }

    set.insert(insertAt, me);
    return set;
  }

  /// Extend a set of changed ranges with additional ranges.
  static List<ChangedRange> extendWithRanges(
    List<ChangedRange> changes,
    List<int> ranges,
  ) {
    if (ranges.isEmpty) return changes;

    final result = <ChangedRange>[];
    var changesI = 0;
    var rangesI = 0;
    var posA = 0;
    var posB = 0;

    while (changesI < changes.length || rangesI < ranges.length) {
      ChangedRange? change;

      if (changesI < changes.length) {
        change = changes[changesI];
      }

      int? rangeFrom, rangeTo;
      if (rangesI < ranges.length) {
        rangeFrom = ranges[rangesI];
        rangeTo = ranges[rangesI + 1];
      }

      // Decide which to process next
      if (change != null &&
          (rangeFrom == null ||
              change.fromA + posA <= rangeFrom + posB)) {
        // Process the change
        result.add(ChangedRange(
          change.fromA + posA,
          change.toA + posA,
          change.fromB + posB,
          change.toB + posB,
        ));
        posA += change.toA - change.fromA;
        posB += change.toB - change.fromB;
        changesI++;
      } else if (rangeFrom != null && rangeTo != null) {
        // Process the range
        final from = rangeFrom + posB;
        final to = rangeTo + posB;
        if (result.isNotEmpty && result.last.toB >= from) {
          // Merge with previous
          final last = result.removeLast();
          result.add(ChangedRange(
            last.fromA,
            last.toA + (to - last.toB),
            last.fromB,
            to,
          ));
        } else {
          result.add(ChangedRange(from, from, from, to));
        }
        rangesI += 2;
      } else {
        break;
      }
    }

    return result;
  }

  @override
  String toString() => 'ChangedRange($fromA-$toA -> $fromB-$toB)';
}

// ============================================================================
// ViewUpdate - The main update object passed to plugins
// ============================================================================

/// An update to the editor view.
///
/// This is passed to view plugins and update listeners to inform them
/// about what happened during an update. It provides access to the old
/// and new state, the transactions that caused the change, and various
/// flags indicating what aspects changed.
class ViewUpdate {
  /// The new editor state after the update.
  final EditorState state;

  /// The transactions that caused this update.
  final List<Transaction> transactions;

  /// Bit flags indicating what changed.
  int flags;

  /// The state before the update.
  final EditorState startState;

  /// The combined changes from all transactions.
  ChangeSet? _changes;

  ViewUpdate._({
    required this.state,
    required this.transactions,
    required this.flags,
    required this.startState,
  });

  /// Create a new ViewUpdate.
  factory ViewUpdate.create(
    EditorState state,
    List<Transaction> transactions, {
    int flags = 0,
  }) {
    final startState =
        transactions.isNotEmpty ? transactions.first.startState : state;
    return ViewUpdate._(
      state: state,
      transactions: transactions,
      flags: flags,
      startState: startState as EditorState,
    );
  }

  /// The changes made to the document by all transactions.
  ChangeSet get changes {
    if (_changes != null) return _changes!;

    if (transactions.isEmpty) {
      _changes = ChangeSet.emptySet(state.doc.length);
    } else {
      _changes = transactions.first.changes;
      for (var i = 1; i < transactions.length; i++) {
        _changes = _changes!.compose(transactions[i].changes);
      }
    }
    return _changes!;
  }

  /// The ranges in the document that were changed.
  List<ChangedRange> get changedRanges {
    final result = <ChangedRange>[];
    changes.iterChangedRanges((fromA, toA, fromB, toB) {
      result.add(ChangedRange(fromA, toA, fromB, toB));
    });
    return result;
  }

  /// Whether any changes were made to the document.
  bool get docChanged => !changes.empty;

  /// Whether the selection was explicitly set.
  bool get selectionSet {
    return transactions.any((tr) => tr.selection != null);
  }

  /// Whether this update is empty (no changes, no effects).
  bool get empty {
    return transactions.isEmpty ||
        (transactions.length == 1 &&
            transactions[0].changes.empty &&
            transactions[0].effects.isEmpty);
  }

  /// Whether the viewport changed.
  bool get viewportChanged => (flags & UpdateFlag.viewport) != 0;

  /// Whether heights may have changed.
  bool get heightChanged => (flags & UpdateFlag.height) != 0;

  /// Whether geometry (widths, padding) changed.
  bool get geometryChanged => (flags & UpdateFlag.geometry) != 0;

  /// Whether focus changed.
  bool get focusChanged => (flags & UpdateFlag.focus) != 0;

  /// Check if this is a user event of the given type.
  ///
  /// See [Transaction.isUserEvent] for the event type format.
  bool isUserEvent(String event) {
    for (final tr in transactions) {
      if (tr.isUserEvent(event)) return true;
    }
    return false;
  }
}
