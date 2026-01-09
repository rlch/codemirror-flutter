/// Cursor movement and positioning utilities.
///
/// This module provides functions for cursor navigation including
/// character-by-character movement, word boundaries, and line navigation.
library;

import '../state/charcategory.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../text/text.dart';

// Re-export CharCategory for backwards compatibility
export '../state/charcategory.dart' show CharCategory, CharCategorizer, makeCategorizer, defaultCategorizer;

// ============================================================================
// Group Selection (Word Boundaries)
// ============================================================================

/// Get a selection range covering the word/group at the given position.
///
/// This is used for double-click word selection and similar operations.
/// The [bias] parameter indicates the preferred direction when at a boundary
/// (-1 = prefer left, 1 = prefer right).
SelectionRange groupAt(EditorState state, int pos, [int bias = 1]) {
  final categorize = state.charCategorizer(pos);
  final line = state.doc.lineAt(pos);
  final linePos = pos - line.from;

  if (line.length == 0) {
    return EditorSelection.cursor(pos);
  }

  // Adjust bias at line boundaries
  int adjustedBias = bias;
  if (linePos == 0) {
    adjustedBias = 1;
  } else if (linePos == line.length) {
    adjustedBias = -1;
  }

  // Find the starting character
  var from = linePos;
  var to = linePos;

  if (adjustedBias < 0) {
    from = findClusterBreak(line.text, linePos, false);
  } else {
    to = findClusterBreak(line.text, linePos, true);
  }

  // Categorize the character we're on
  final cat = categorize(line.text.substring(from, to));

  // Extend backward while same category
  while (from > 0) {
    final prev = findClusterBreak(line.text, from, false);
    if (categorize(line.text.substring(prev, from)) != cat) break;
    from = prev;
  }

  // Extend forward while same category
  while (to < line.length) {
    final next = findClusterBreak(line.text, to, true);
    if (categorize(line.text.substring(to, next)) != cat) break;
    to = next;
  }

  return EditorSelection.range(from + line.from, to + line.from);
}

/// Create a function that checks if a character belongs to the same
/// group as the starting character.
///
/// This is used for word-wise cursor movement.
bool Function(String) byGroup(EditorState state, int pos, String start) {
  final categorize = state.charCategorizer(pos);
  var cat = categorize(start);

  return (String next) {
    final nextCat = categorize(next);
    // If started on whitespace, transition to the next category
    if (cat == CharCategory.space) cat = nextCat;
    return cat == nextCat;
  };
}

// ============================================================================
// Cursor Movement
// ============================================================================

/// Move the cursor by one character.
///
/// This is the base character movement function. The [by] parameter can
/// be used to extend movement to word boundaries.
SelectionRange moveByChar(
  EditorState state,
  SelectionRange start,
  bool forward, {
  bool Function(String) Function(String)? by,
}) {
  var line = state.doc.lineAt(start.head);

  SelectionRange cur = start;
  bool Function(String)? check;

  while (true) {
    final next = _moveVisually(state, line, cur, forward);
    final char = _lastMovedOver;

    if (next == null) {
      // At document boundary - try to move to next/previous line
      if (line.number == (forward ? state.doc.lines : 1)) {
        return cur;
      }

      line = state.doc.line(line.number + (forward ? 1 : -1));
      final nextPos = forward ? line.from : line.to;
      cur = EditorSelection.cursor(nextPos);
      
      // If we're checking for word boundaries, reset on newline
      if (check != null && !check('\n')) {
        return cur;
      }
      continue;
    }

    if (check == null) {
      if (by == null) return next;
      check = by(char);
    } else if (!check(char)) {
      return cur;
    }
    cur = next;
  }
}

/// Track the last character moved over for word boundary detection.
String _lastMovedOver = '';

/// Visual movement within a line.
SelectionRange? _moveVisually(
  EditorState state,
  Line line,
  SelectionRange pos,
  bool forward,
) {
  final linePos = pos.head - line.from;

  if (forward) {
    if (linePos >= line.length) {
      _lastMovedOver = '\n';
      return null;
    }
    final next = findClusterBreak(line.text, linePos, true);
    _lastMovedOver = line.text.substring(linePos, next);
    return EditorSelection.cursor(line.from + next, assoc: forward ? -1 : 1);
  } else {
    if (linePos <= 0) {
      _lastMovedOver = '\n';
      return null;
    }
    final prev = findClusterBreak(line.text, linePos, false);
    _lastMovedOver = line.text.substring(prev, linePos);
    return EditorSelection.cursor(line.from + prev, assoc: forward ? -1 : 1);
  }
}

/// Move to the start or end of a line.
///
/// When [includeWrap] is true and the editor has line wrapping enabled,
/// this moves to the visual line boundary instead of the logical line.
SelectionRange moveToLineBoundary(
  EditorState state,
  SelectionRange start,
  bool forward, {
  bool includeWrap = false,
}) {
  final line = state.doc.lineAt(start.head);

  // For now, we just move to logical line boundaries
  // Visual line boundaries require view/layout information
  return EditorSelection.cursor(
    forward ? line.to : line.from,
    assoc: forward ? -1 : 1,
  );
}

/// Move vertically by one line.
///
/// The [distance] parameter can specify a custom vertical distance,
/// otherwise the default line height is used.
SelectionRange moveVertically(
  EditorState state,
  SelectionRange start,
  bool forward, {
  int? distance,
  int? goalColumn,
}) {
  final startPos = start.head;

  // At document boundary?
  if (startPos == (forward ? state.doc.length : 0)) {
    return EditorSelection.cursor(startPos, assoc: start.assoc);
  }

  final line = state.doc.lineAt(startPos);
  final goal = goalColumn ?? start.goalColumn ?? (startPos - line.from);

  // Find target line
  final targetLineNum = line.number + (forward ? 1 : -1);
  if (targetLineNum < 1 || targetLineNum > state.doc.lines) {
    // Stay on current line but move to end
    return EditorSelection.cursor(
      forward ? line.to : line.from,
      assoc: forward ? -1 : 1,
    );
  }

  final targetLine = state.doc.line(targetLineNum);
  final targetPos = targetLine.from + goal.clamp(0, targetLine.length);

  return EditorSelection.cursor(
    targetPos,
    assoc: forward ? -1 : 1,
    goalColumn: goal,
  );
}

// ============================================================================
// Atomic Ranges
// ============================================================================

/// Facet for defining atomic ranges that cursor movement should skip.
///
/// Atomic ranges are treated as single units for cursor movement - the
/// cursor will jump over them rather than stopping inside them.
final Facet<RangeSet<RangeValue> Function(dynamic view), List<RangeSet<RangeValue> Function(dynamic view)>>
    atomicRanges = Facet.define();

/// Skip atomic ranges starting from [pos] in the given direction.
///
/// Returns the position after skipping any atomic ranges.
int skipAtomicRanges(List<RangeSet<RangeValue>> atoms, int pos, int bias) {
  while (true) {
    var moved = 0;

    for (final set in atoms) {
      set.between(pos - 1, pos + 1, (from, to, value) {
        if (pos > from && pos < to) {
          final side = moved != 0 ? moved : (bias != 0 ? bias : (pos - from < to - pos ? -1 : 1));
          pos = side < 0 ? from : to;
          moved = side;
        }
        return true;
      });
    }

    if (moved == 0) return pos;
  }
}

/// Adjust a selection to skip atomic ranges.
EditorSelection skipAtomsForSelection(
  List<RangeSet<RangeValue>> atoms,
  EditorSelection sel,
) {
  List<SelectionRange>? ranges;

  for (var i = 0; i < sel.ranges.length; i++) {
    final range = sel.ranges[i];
    SelectionRange? updated;

    if (range.empty) {
      final pos = skipAtomicRanges(atoms, range.from, 0);
      if (pos != range.from) {
        updated = EditorSelection.cursor(pos, assoc: -1);
      }
    } else {
      final from = skipAtomicRanges(atoms, range.from, -1);
      final to = skipAtomicRanges(atoms, range.to, 1);
      if (from != range.from || to != range.to) {
        updated = EditorSelection.range(
          range.from == range.anchor ? from : to,
          range.from == range.head ? from : to,
        );
      }
    }

    if (updated != null) {
      ranges ??= sel.ranges.toList();
      ranges[i] = updated;
    }
  }

  return ranges != null
      ? EditorSelection.create(ranges, sel.mainIndex)
      : sel;
}

/// Skip atomic ranges for a single position movement.
SelectionRange skipAtoms(
  dynamic view,
  SelectionRange oldPos,
  SelectionRange pos,
) {
  final state = view.state as EditorState;
  final atoms = state.facet(atomicRanges).map((f) => f(view)).toList();
  final newPos = skipAtomicRanges(atoms, pos.from, oldPos.head > pos.from ? -1 : 1);
  return newPos == pos.from ? pos : EditorSelection.cursor(newPos, assoc: newPos < pos.from ? 1 : -1);
}


