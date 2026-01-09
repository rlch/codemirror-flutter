/// Editor commands for cursor movement, selection, deletion, and text editing.
///
/// This module provides the standard editing commands for a code editor,
/// including cursor movement (by character, word, line), selection extension,
/// deletion operations, and line manipulation.
library;

import 'dart:math' as math;

import 'package:lezer/lezer.dart';

import '../language/indent.dart' show IndentContext, IndentContextOptions, getIndentation;
import '../language/language.dart' show syntaxTree;
import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/selection.dart';
import '../state/state.dart' show EditorState, ChangeByRangeResult;
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../text/text.dart';
import '../view/cursor.dart';
import '../view/keymap.dart';

// Re-export history module items
export 'history.dart';

// ============================================================================
// Command Types
// ============================================================================

/// A command target provides access to state and dispatch function.
///
/// This is the minimal interface needed to execute state commands.
/// For view-aware commands, use [ViewCommandTarget].
typedef StateCommandTarget = ({
  EditorState state,
  void Function(txn.Transaction) dispatch
});

/// A view-aware command target.
///
/// Some commands need access to the view for visual operations like
/// line wrapping, viewport scrolling, or visual cursor movement.
typedef ViewCommandTarget = ({
  EditorState state,
  void Function(txn.Transaction) dispatch,
  dynamic view,
});

/// A state command - operates on state without needing view information.
typedef StateCommand = bool Function(StateCommandTarget);

/// A view command - may need view information for visual operations.
typedef ViewCommand = bool Function(ViewCommandTarget);

// ============================================================================
// Helper Functions
// ============================================================================

/// Update a selection by mapping each range through a function.
EditorSelection _updateSel(
  EditorSelection sel,
  SelectionRange Function(SelectionRange range) by,
) {
  return EditorSelection.create(sel.ranges.map(by).toList(), sel.mainIndex);
}

/// Create a transaction that sets the selection.
txn.Transaction _setSel(
  EditorState state,
  EditorSelection selection, {
  bool scrollIntoView = true,
  String userEvent = 'select',
}) {
  return state.update([
    TransactionSpec(
      selection: selection,
      scrollIntoView: scrollIntoView,
      userEvent: userEvent,
    ),
  ]);
}

/// Move the selection using the provided function.
bool _moveSel(
  StateCommandTarget target,
  SelectionRange Function(SelectionRange range) how,
) {
  final selection = _updateSel(target.state.selection, how);
  if (selection.eq(target.state.selection, true)) return false;
  target.dispatch(_setSel(target.state, selection));
  return true;
}

/// Get the cursor at the end of a range (collapsing a non-empty selection).
SelectionRange _rangeEnd(SelectionRange range, bool forward) {
  return EditorSelection.cursor(forward ? range.to : range.from);
}

// ============================================================================
// Character Movement Commands
// ============================================================================

/// Move the selection by one character.
bool _cursorByChar(StateCommandTarget target, bool forward) {
  return _moveSel(target, (range) {
    if (!range.empty) return _rangeEnd(range, forward);
    return moveByChar(target.state, range, forward);
  });
}

/// Move the selection one character to the left.
///
/// For right-to-left text, this moves forward visually but backward logically.
bool cursorCharLeft(StateCommandTarget target) => _cursorByChar(target, false);

/// Move the selection one character to the right.
bool cursorCharRight(StateCommandTarget target) => _cursorByChar(target, true);

/// Move the selection one character forward (in logical order).
bool cursorCharForward(StateCommandTarget target) => _cursorByChar(target, true);

/// Move the selection one character backward (in logical order).
bool cursorCharBackward(StateCommandTarget target) => _cursorByChar(target, false);

// ============================================================================
// Group/Word Movement Commands
// ============================================================================

/// Move the selection by one word/group.
bool _cursorByGroup(StateCommandTarget target, bool forward) {
  return _moveSel(target, (range) {
    if (!range.empty) return _rangeEnd(range, forward);
    return moveByChar(
      target.state,
      range,
      forward,
      by: (start) => byGroup(target.state, range.head, start),
    );
  });
}

/// Move the selection one group to the left.
bool cursorGroupLeft(StateCommandTarget target) => _cursorByGroup(target, false);

/// Move the selection one group to the right.
bool cursorGroupRight(StateCommandTarget target) => _cursorByGroup(target, true);

/// Move the selection one group forward.
bool cursorGroupForward(StateCommandTarget target) => _cursorByGroup(target, true);

/// Move the selection one group backward.
bool cursorGroupBackward(StateCommandTarget target) => _cursorByGroup(target, false);

// ============================================================================
// Line Movement Commands
// ============================================================================

/// Move the selection by one line.
bool _cursorByLine(StateCommandTarget target, bool forward) {
  return _moveSel(target, (range) {
    if (!range.empty) return _rangeEnd(range, forward);
    return moveVertically(target.state, range, forward);
  });
}

/// Move the selection one line up.
bool cursorLineUp(StateCommandTarget target) => _cursorByLine(target, false);

/// Move the selection one line down.
bool cursorLineDown(StateCommandTarget target) => _cursorByLine(target, true);

/// Move the selection to the start of the line.
bool cursorLineStart(StateCommandTarget target) {
  return _moveSel(target, (range) {
    final line = target.state.doc.lineAt(range.head);
    return EditorSelection.cursor(line.from, assoc: 1);
  });
}

/// Move the selection to the end of the line.
bool cursorLineEnd(StateCommandTarget target) {
  return _moveSel(target, (range) {
    final line = target.state.doc.lineAt(range.head);
    return EditorSelection.cursor(line.to, assoc: -1);
  });
}

/// Move to line boundary (start or end, respecting wrapping).
bool _cursorLineBoundary(StateCommandTarget target, bool forward) {
  return _moveSel(target, (range) {
    var moved = moveToLineBoundary(target.state, range, forward);
    final line = target.state.doc.lineAt(range.head);

    // Smart home: if not at start of content, go to first non-whitespace
    if (!forward && moved.head == line.from && line.length > 0) {
      final match = RegExp(r'^\s*').firstMatch(
        target.state.doc.sliceString(
          line.from,
          math.min(line.from + 100, line.to),
        ),
      );
      final space = match?.group(0)?.length ?? 0;
      if (space > 0 && range.head != line.from + space) {
        moved = EditorSelection.cursor(line.from + space);
      }
    }
    return moved;
  });
}

/// Move the selection to the next line boundary.
bool cursorLineBoundaryForward(StateCommandTarget target) =>
    _cursorLineBoundary(target, true);

/// Move the selection to the previous line boundary.
bool cursorLineBoundaryBackward(StateCommandTarget target) =>
    _cursorLineBoundary(target, false);

// ============================================================================
// Document Boundary Commands
// ============================================================================

/// Move the selection to the start of the document.
bool cursorDocStart(StateCommandTarget target) {
  target.dispatch(_setSel(target.state, EditorSelection.single(0)));
  return true;
}

/// Move the selection to the end of the document.
bool cursorDocEnd(StateCommandTarget target) {
  target.dispatch(_setSel(
    target.state,
    EditorSelection.single(target.state.doc.length),
  ));
  return true;
}

// ============================================================================
// Selection Extension Commands
// ============================================================================

/// Extend the selection using the provided function.
bool _extendSel(
  StateCommandTarget target,
  SelectionRange Function(SelectionRange range) how,
) {
  final selection = _updateSel(target.state.selection, (range) {
    final head = how(range);
    return EditorSelection.range(
      range.anchor,
      head.head,
      goalColumn: head.goalColumn,
      bidiLevel: head.bidiLevel,
    );
  });
  if (selection.eq(target.state.selection)) return false;
  target.dispatch(_setSel(target.state, selection));
  return true;
}

/// Extend selection by one character.
bool _selectByChar(StateCommandTarget target, bool forward) {
  return _extendSel(target, (range) => moveByChar(target.state, range, forward));
}

/// Extend selection one character to the left.
bool selectCharLeft(StateCommandTarget target) => _selectByChar(target, false);

/// Extend selection one character to the right.
bool selectCharRight(StateCommandTarget target) => _selectByChar(target, true);

/// Extend selection one character forward.
bool selectCharForward(StateCommandTarget target) => _selectByChar(target, true);

/// Extend selection one character backward.
bool selectCharBackward(StateCommandTarget target) => _selectByChar(target, false);

/// Extend selection by one group.
bool _selectByGroup(StateCommandTarget target, bool forward) {
  return _extendSel(target, (range) {
    return moveByChar(
      target.state,
      range,
      forward,
      by: (start) => byGroup(target.state, range.head, start),
    );
  });
}

/// Extend selection one group to the left.
bool selectGroupLeft(StateCommandTarget target) => _selectByGroup(target, false);

/// Extend selection one group to the right.
bool selectGroupRight(StateCommandTarget target) => _selectByGroup(target, true);

/// Extend selection one group forward.
bool selectGroupForward(StateCommandTarget target) => _selectByGroup(target, true);

/// Extend selection one group backward.
bool selectGroupBackward(StateCommandTarget target) => _selectByGroup(target, false);

/// Extend selection by one line.
bool _selectByLine(StateCommandTarget target, bool forward) {
  return _extendSel(target, (range) => moveVertically(target.state, range, forward));
}

/// Extend selection one line up.
bool selectLineUp(StateCommandTarget target) => _selectByLine(target, false);

/// Extend selection one line down.
bool selectLineDown(StateCommandTarget target) => _selectByLine(target, true);

/// Extend selection to line start.
bool selectLineStart(StateCommandTarget target) {
  return _extendSel(target, (range) {
    return EditorSelection.cursor(target.state.doc.lineAt(range.head).from);
  });
}

/// Extend selection to line end.
bool selectLineEnd(StateCommandTarget target) {
  return _extendSel(target, (range) {
    return EditorSelection.cursor(target.state.doc.lineAt(range.head).to);
  });
}

/// Extend selection to line boundary.
bool _selectLineBoundary(StateCommandTarget target, bool forward) {
  return _extendSel(target, (range) {
    var moved = moveToLineBoundary(target.state, range, forward);
    final line = target.state.doc.lineAt(range.head);

    if (!forward && moved.head == line.from && line.length > 0) {
      final match = RegExp(r'^\s*').firstMatch(
        target.state.doc.sliceString(line.from, math.min(line.from + 100, line.to)),
      );
      final space = match?.group(0)?.length ?? 0;
      if (space > 0 && range.head != line.from + space) {
        moved = EditorSelection.cursor(line.from + space);
      }
    }
    return moved;
  });
}

/// Extend selection to the next line boundary.
bool selectLineBoundaryForward(StateCommandTarget target) =>
    _selectLineBoundary(target, true);

/// Extend selection to the previous line boundary.
bool selectLineBoundaryBackward(StateCommandTarget target) =>
    _selectLineBoundary(target, false);

/// Extend selection to document start.
bool selectDocStart(StateCommandTarget target) {
  target.dispatch(_setSel(
    target.state,
    EditorSelection.single(target.state.selection.main.anchor, 0),
  ));
  return true;
}

/// Extend selection to document end.
bool selectDocEnd(StateCommandTarget target) {
  target.dispatch(_setSel(
    target.state,
    EditorSelection.single(
      target.state.selection.main.anchor,
      target.state.doc.length,
    ),
  ));
  return true;
}

/// Select the entire document.
bool selectAll(StateCommandTarget target) {
  target.dispatch(target.state.update([
    TransactionSpec(
      selection: EditorSelection.single(0, target.state.doc.length),
      userEvent: 'select',
    ),
  ]));
  return true;
}

/// Expand selection to cover entire lines.
bool selectLine(StateCommandTarget target) {
  final state = target.state;
  final blocks = _selectedLineBlocks(state);
  final ranges = blocks.map((block) {
    return EditorSelection.range(
      block.from,
      math.min(block.to + 1, state.doc.length),
    );
  }).toList();

  target.dispatch(state.update([
    TransactionSpec(
      selection: EditorSelection.create(ranges),
      userEvent: 'select',
    ),
  ]));
  return true;
}

/// Simplify the current selection.
///
/// When multiple ranges are selected, reduce to the main range.
/// When a single non-empty range is selected, collapse to cursor.
bool simplifySelection(StateCommandTarget target) {
  final cur = target.state.selection;
  EditorSelection? selection;

  if (cur.ranges.length > 1) {
    selection = EditorSelection.create([cur.main]);
  } else if (!cur.main.empty) {
    selection = EditorSelection.create([EditorSelection.cursor(cur.main.head)]);
  }

  if (selection == null) return false;
  target.dispatch(_setSel(target.state, selection));
  return true;
}

// ============================================================================
// Delete Commands
// ============================================================================

/// Delete using the provided target function.
bool _deleteBy(
  StateCommandTarget target,
  int Function(SelectionRange range) by,
) {
  if (target.state.isReadOnly) return false;

  var eventType = 'delete.selection';
  final state = target.state;
  
  final changeResult = state.changeByRange((range) {
    var from = range.from;
    var to = range.to;

    if (from == to) {
      final towards = by(range);
      if (towards < from) {
        eventType = 'delete.backward';
        from = towards;
      } else if (towards > to) {
        eventType = 'delete.forward';
        to = towards;
      }
    }

    if (from == to) {
      return ChangeByRangeResult(range: range);
    }

    return ChangeByRangeResult(
      range: EditorSelection.cursor(from, assoc: from < range.head ? -1 : 1),
      changes: [ChangeSpec(from: from, to: to)],
    );
  });

  final changes = changeResult.changes;
  if (changes is ChangeSet && changes.empty) return false;

  target.dispatch(state.update([
    TransactionSpec(
      changes: changeResult.changes,
      selection: changeResult.selection,
      scrollIntoView: true,
      userEvent: eventType,
    ),
  ]));
  return true;
}

/// Delete the selection or character before the cursor.
bool deleteCharBackward(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final line = target.state.doc.lineAt(range.head);
    final linePos = range.head - line.from;

    if (linePos <= 0) {
      // At start of line - delete newline before
      return math.max(0, range.head - 1);
    }

    // Find previous cluster break
    return line.from + findClusterBreak(line.text, linePos, false);
  });
}

/// Delete the selection or character after the cursor.
bool deleteCharForward(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final line = target.state.doc.lineAt(range.head);
    final linePos = range.head - line.from;

    if (linePos >= line.length) {
      // At end of line - delete newline after
      return math.min(target.state.doc.length, range.head + 1);
    }

    // Find next cluster break
    return line.from + findClusterBreak(line.text, linePos, true);
  });
}

/// Delete the selection or group before the cursor.
bool deleteGroupBackward(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final state = target.state;
    final line = state.doc.lineAt(range.head);
    final categorize = state.charCategorizer(range.head);
    CharCategory? cat;

    var pos = range.head;
    while (true) {
      if (pos == line.from) {
        // At start of line
        if (pos == range.head && line.number > 1) {
          pos--;
        }
        break;
      }

      final prev = findClusterBreak(line.text, pos - line.from, false);
      final prevChar = line.text.substring(prev, pos - line.from);
      final prevCat = categorize(prevChar);

      if (cat != null && prevCat != cat) break;
      if (prevChar != ' ' || pos != range.head) cat = prevCat;
      pos = line.from + prev;
    }

    return pos;
  });
}

/// Delete the selection or group after the cursor.
bool deleteGroupForward(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final state = target.state;
    final line = state.doc.lineAt(range.head);
    final categorize = state.charCategorizer(range.head);
    CharCategory? cat;

    var pos = range.head;
    while (true) {
      if (pos == line.to) {
        if (pos == range.head && line.number < state.doc.lines) {
          pos++;
        }
        break;
      }

      final next = findClusterBreak(line.text, pos - line.from, true);
      final nextChar = line.text.substring(pos - line.from, next);
      final nextCat = categorize(nextChar);

      if (cat != null && nextCat != cat) break;
      if (nextChar != ' ' || pos != range.head) cat = nextCat;
      pos = line.from + next;
    }

    return pos;
  });
}

/// Delete to the end of the line.
bool deleteToLineEnd(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final lineEnd = target.state.doc.lineAt(range.head).to;
    return range.head < lineEnd
        ? lineEnd
        : math.min(target.state.doc.length, range.head + 1);
  });
}

/// Delete to the start of the line.
bool deleteToLineStart(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final lineStart = target.state.doc.lineAt(range.head).from;
    return range.head > lineStart ? lineStart : math.max(0, range.head - 1);
  });
}

/// Delete to line boundary backward.
bool deleteLineBoundaryBackward(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final lineStart = moveToLineBoundary(target.state, range, false).head;
    return range.head > lineStart ? lineStart : math.max(0, range.head - 1);
  });
}

/// Delete to line boundary forward.
bool deleteLineBoundaryForward(StateCommandTarget target) {
  return _deleteBy(target, (range) {
    final lineEnd = moveToLineBoundary(target.state, range, true).head;
    return range.head < lineEnd
        ? lineEnd
        : math.min(target.state.doc.length, range.head + 1);
  });
}

/// Delete all whitespace directly before line ends.
bool deleteTrailingWhitespace(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final changes = <ChangeSpec>[];

  for (var lineNum = 1; lineNum <= state.doc.lines; lineNum++) {
    final line = state.doc.line(lineNum);
    final match = RegExp(r'\s+$').firstMatch(line.text);
    if (match != null) {
      changes.add(ChangeSpec(
        from: line.from + match.start,
        to: line.to,
      ));
    }
  }

  if (changes.isEmpty) return false;

  target.dispatch(state.update([
    TransactionSpec(changes: changes, userEvent: 'delete'),
  ]));
  return true;
}

// ============================================================================
// Line Operations
// ============================================================================

/// Get blocks of selected lines.
List<({int from, int to, List<SelectionRange> ranges})> _selectedLineBlocks(
  EditorState state,
) {
  final blocks = <({int from, int to, List<SelectionRange> ranges})>[];
  var upto = -1;

  for (final range in state.selection.ranges) {
    final startLine = state.doc.lineAt(range.from);
    var endLine = state.doc.lineAt(range.to);

    if (!range.empty && range.to == endLine.from) {
      endLine = state.doc.lineAt(range.to - 1);
    }

    if (upto >= startLine.number) {
      // Merge with previous block
      final prev = blocks.last;
      blocks[blocks.length - 1] = (
        from: prev.from,
        to: endLine.to,
        ranges: [...prev.ranges, range],
      );
    } else {
      blocks.add((
        from: startLine.from,
        to: endLine.to,
        ranges: [range],
      ));
    }
    upto = endLine.number + 1;
  }

  return blocks;
}

/// Move selected lines up or down.
bool _moveLine(StateCommandTarget target, bool forward) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final changes = <ChangeSpec>[];
  final ranges = <SelectionRange>[];

  for (final block in _selectedLineBlocks(state)) {
    if (forward ? block.to == state.doc.length : block.from == 0) {
      continue;
    }

    final nextLine = state.doc.lineAt(forward ? block.to + 1 : block.from - 1);
    final size = nextLine.length + 1;

    if (forward) {
      changes.add(ChangeSpec(from: block.to, to: nextLine.to));
      changes.add(ChangeSpec(
        from: block.from,
        insert: '${nextLine.text}${state.lineBreak}',
      ));
      for (final r in block.ranges) {
        ranges.add(EditorSelection.range(
          math.min(state.doc.length, r.anchor + size),
          math.min(state.doc.length, r.head + size),
        ));
      }
    } else {
      changes.add(ChangeSpec(from: nextLine.from, to: block.from));
      changes.add(ChangeSpec(
        from: block.to,
        insert: '${state.lineBreak}${nextLine.text}',
      ));
      for (final r in block.ranges) {
        ranges.add(EditorSelection.range(r.anchor - size, r.head - size));
      }
    }
  }

  if (changes.isEmpty) return false;

  target.dispatch(state.update([
    TransactionSpec(
      changes: changes,
      scrollIntoView: true,
      selection: EditorSelection.create(ranges, state.selection.mainIndex),
      userEvent: 'move.line',
    ),
  ]));
  return true;
}

/// Move selected lines up.
bool moveLineUp(StateCommandTarget target) => _moveLine(target, false);

/// Move selected lines down.
bool moveLineDown(StateCommandTarget target) => _moveLine(target, true);

/// Copy selected lines up or down.
bool _copyLine(StateCommandTarget target, bool forward) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final changes = <ChangeSpec>[];

  for (final block in _selectedLineBlocks(state)) {
    final text = state.doc.sliceString(block.from, block.to);
    if (forward) {
      changes.add(ChangeSpec(from: block.from, insert: '$text${state.lineBreak}'));
    } else {
      changes.add(ChangeSpec(from: block.to, insert: '${state.lineBreak}$text'));
    }
  }

  target.dispatch(state.update([
    TransactionSpec(
      changes: changes,
      scrollIntoView: true,
      userEvent: 'input.copyline',
    ),
  ]));
  return true;
}

/// Copy selected lines up (keeping selection in the original lines).
bool copyLineUp(StateCommandTarget target) => _copyLine(target, false);

/// Copy selected lines down (keeping selection in the original lines).
bool copyLineDown(StateCommandTarget target) => _copyLine(target, true);

/// Delete selected lines.
bool deleteLine(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final blocks = _selectedLineBlocks(state);
  final changeSpecs = blocks.map((block) {
    var from = block.from;
    var to = block.to;
    if (from > 0) {
      from--;
    } else if (to < state.doc.length) {
      to++;
    }
    return ChangeSpec(from: from, to: to);
  }).toList();

  final changes = state.changes(changeSpecs);

  // Update selection to stay on reasonable lines
  final selection = _updateSel(state.selection, (range) {
    return moveVertically(state, range, true);
  }).map(changes);

  target.dispatch(state.update([
    TransactionSpec(
      changes: changes,
      selection: selection,
      scrollIntoView: true,
      userEvent: 'delete.line',
    ),
  ]));
  return true;
}

// ============================================================================
// Text Insertion Commands
// ============================================================================

/// Replace the selection with a newline.
bool insertNewline(StateCommandTarget target) {
  final state = target.state;
  final result = state.replaceSelection(state.lineBreak);
  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'input',
    ),
  ]));
  return true;
}

/// Replace the selection with a newline and keep the same indentation.
bool insertNewlineKeepIndent(StateCommandTarget target) {
  final state = target.state;

  final result = state.changeByRange((range) {
    final line = state.doc.lineAt(range.from);
    final match = RegExp(r'^\s*').firstMatch(line.text);
    final indent = match?.group(0) ?? '';

    return ChangeByRangeResult(
      changes: [ChangeSpec(from: range.from, to: range.to, insert: '${state.lineBreak}$indent')],
      range: EditorSelection.cursor(range.from + indent.length + 1),
    );
  });

  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'input',
    ),
  ]));
  return true;
}

/// Check if cursor is between matching brackets.
({int from, int to})? _isBetweenBrackets(EditorState state, int pos) {
  // Quick check for adjacent brackets
  if (pos > 0 && pos < state.doc.length) {
    final pair = state.sliceDoc(pos - 1, pos + 1);
    if (RegExp(r'\(\)|\[\]|\{\}').hasMatch(pair)) {
      return (from: pos, to: pos);
    }
  }
  
  // Check syntax tree for bracket nodes
  final tree = syntaxTree(state);
  final context = tree.resolveInner(pos);
  final before = context.childBefore(pos);
  final after = context.childAfter(pos);
  
  if (before != null && after != null && before.to <= pos && after.from >= pos) {
    final closedBy = before.type.prop(NodeProp.closedBy);
    if (closedBy != null && closedBy.contains(after.name)) {
      // Check they're on the same line and only whitespace between
      if (state.doc.lineAt(before.to).from == state.doc.lineAt(after.from).from &&
          !RegExp(r'\S').hasMatch(state.sliceDoc(before.to, after.from))) {
        return (from: before.to, to: after.from);
      }
    }
  }
  return null;
}

/// Replace the selection with a newline and compute smart indentation.
/// 
/// If the current line consists only of whitespace, this will also delete 
/// that whitespace. When the cursor is between matching brackets, an 
/// additional newline will be inserted after the cursor.
bool insertNewlineAndIndent(StateCommandTarget target) {
  print('insertNewlineAndIndent called! pos=${target.state.selection.main.head}');
  if (target.state.isReadOnly) return false;
  
  final state = target.state;
  
  final result = state.changeByRange((range) {
    var from = range.from;
    var to = range.to;
    final line = state.doc.lineAt(from);
    
    // Check if cursor is between brackets like { | } or ( | )
    final explode = from == to ? _isBetweenBrackets(state, from) : null;
    
    // Create indent context with simulated break
    final cx = IndentContext(
      state,
      options: IndentContextOptions(
        simulateBreak: from,
        simulateDoubleBreak: explode != null,
      ),
    );
    
    // Get smart indentation
    var indent = getIndentation(cx, from);
    if (indent == null) {
      // Fall back to current line's indentation
      final lineIndentMatch = RegExp(r'^\s*').firstMatch(line.text);
      indent = countColumn(lineIndentMatch?.group(0) ?? '', state.tabSize);
    }
    
    // Delete trailing whitespace on current line (with bounds check)
    while (to < line.to && (to - line.from) < line.text.length) {
      final char = line.text[to - line.from];
      if (char != ' ' && char != '\t') break;
      to++;
    }
    
    // If cursor is in explosion zone, use that range
    if (explode != null) {
      from = explode.from;
      to = explode.to;
    } else if (from > line.from && from < line.from + 100 && (from - line.from) <= line.text.length) {
      // Delete leading whitespace on whitespace-only lines
      final beforeCursor = line.text.substring(0, from - line.from);
      if (!RegExp(r'\S').hasMatch(beforeCursor)) {
        from = line.from;
      }
    }
    
    // Build the insert text
    final indentStr = indentString(state, indent);
    String insertText;
    int cursorPos;
    
    if (explode != null) {
      // Between brackets: add two newlines with proper indentation
      int outerIndentCol;
      try {
        final cx = IndentContext(state);
        outerIndentCol = cx.lineIndent(line.from, -1);
      } catch (_) {
        outerIndentCol = 0;
      }
      final outerIndent = indentString(state, outerIndentCol);
      insertText = '${state.lineBreak}$indentStr${state.lineBreak}$outerIndent';
      cursorPos = from + 1 + indentStr.length;
    } else {
      insertText = '${state.lineBreak}$indentStr';
      cursorPos = from + 1 + indentStr.length;
    }
    
    return ChangeByRangeResult(
      changes: [ChangeSpec(from: from, to: to, insert: insertText)],
      range: EditorSelection.cursor(cursorPos),
    );
  });
  
  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'input',
    ),
  ]));
  return true;
}

/// Create a blank, indented line below the current line.
bool insertBlankLine(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;
  
  final state = target.state;
  
  final result = state.changeByRange((range) {
    var to = range.to;
    final line = state.doc.lineAt(to);
    
    // Move to end of line
    to = line.to;
    
    // Create indent context
    final cx = IndentContext(
      state,
      options: IndentContextOptions(simulateBreak: to),
    );
    
    // Get indentation
    var indent = getIndentation(cx, to);
    if (indent == null) {
      final lineIndent = RegExp(r'^\s*').firstMatch(line.text);
      indent = countColumn(lineIndent?.group(0) ?? '', state.tabSize);
    }
    
    final indentStr = indentString(state, indent);
    final insertText = '${state.lineBreak}$indentStr';
    
    return ChangeByRangeResult(
      changes: [ChangeSpec(from: to, insert: insertText)],
      range: EditorSelection.cursor(to + insertText.length),
    );
  });
  
  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'input',
    ),
  ]));
  return true;
}

/// Split line at cursor, leaving cursor on line before break.
bool splitLine(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final result = state.changeByRange((range) {
    return ChangeByRangeResult(
      changes: [ChangeSpec(from: range.from, to: range.to, insert: state.lineBreak)],
      range: EditorSelection.cursor(range.from),
    );
  });

  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'input',
    ),
  ]));
  return true;
}

/// Transpose (swap) the characters before and after the cursor.
bool transposeChars(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final result = state.changeByRange((range) {
    if (!range.empty || range.from == 0 || range.from == state.doc.length) {
      return ChangeByRangeResult(range: range);
    }

    final pos = range.from;
    final line = state.doc.lineAt(pos);

    final from = pos == line.from
        ? pos - 1
        : line.from + findClusterBreak(line.text, pos - line.from, false);
    final to = pos == line.to
        ? pos + 1
        : line.from + findClusterBreak(line.text, pos - line.from, true);

    final before = state.doc.sliceString(from, pos);
    final after = state.doc.sliceString(pos, to);

    return ChangeByRangeResult(
      changes: [ChangeSpec(from: from, to: to, insert: '$after$before')],
      range: EditorSelection.cursor(to),
    );
  });

  final changes = result.changes;
  if (changes is ChangeSet && changes.empty) return false;

  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'move.character',
    ),
  ]));
  return true;
}

// ============================================================================
// Indentation Commands
// ============================================================================

/// Facet for the indentation unit (string of spaces or a tab).
final indentUnit = Facet.define<String, String>(
  FacetConfig(
    combine: (values) => values.isNotEmpty ? values.first : '  ',
  ),
);

/// Get the indent unit size (number of columns).
int getIndentUnit(EditorState state) {
  final unit = state.facet(indentUnit);
  if (unit.isEmpty) return 2;
  return unit.codeUnitAt(0) == 9 ? state.tabSize : unit.length;
}

/// Create an indentation string for the given number of columns.
String indentString(EditorState state, int cols) {
  final unit = state.facet(indentUnit);
  if (unit.isEmpty || unit.codeUnitAt(0) == 9) {
    // Use tabs
    final tabs = cols ~/ state.tabSize;
    final spaces = cols % state.tabSize;
    return '\t' * tabs + ' ' * spaces;
  } else {
    // Use spaces
    return ' ' * cols;
  }
}



/// Helper to apply a change to each selected line.
ChangeByRangeResult _changeBySelectedLine(
  EditorState state,
  void Function(Line line, List<ChangeSpec> changes, SelectionRange range) f,
) {
  var atLine = -1;
  return state.changeByRange((range) {
    final changes = <ChangeSpec>[];
    for (var pos = range.from; pos <= range.to;) {
      final line = state.doc.lineAt(pos);
      if (line.number > atLine && (range.empty || range.to > line.from)) {
        f(line, changes, range);
        atLine = line.number;
      }
      pos = line.to + 1;
    }
    final changeSet = state.changes(changes);
    return ChangeByRangeResult(
      changes: changes,
      range: EditorSelection.range(
        changeSet.mapPos(range.anchor, 1) ?? range.anchor,
        changeSet.mapPos(range.head, 1) ?? range.head,
      ),
    );
  });
}

/// Add a unit of indentation to all selected lines.
bool indentMore(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;

  final state = target.state;
  final unit = state.facet(indentUnit);

  target.dispatch(state.update([
    TransactionSpec(
      changes: _changeBySelectedLine(state, (line, changes, range) {
        changes.add(ChangeSpec(from: line.from, insert: unit));
      }).changes,
      userEvent: 'input.indent',
    ),
  ]));
  return true;
}

/// Remove a unit of indentation from all selected lines.
bool indentLess(StateCommandTarget target) {
  if (target.state.isReadOnly) return false;

  final state = target.state;

  target.dispatch(state.update([
    TransactionSpec(
      changes: _changeBySelectedLine(state, (line, changes, range) {
        final match = RegExp(r'^\s*').firstMatch(line.text);
        final space = match?.group(0) ?? '';
        if (space.isEmpty) return;

        final col = countColumn(space, state.tabSize);
        var keep = 0;
        final insertCols = math.max(0, col - getIndentUnit(state));
        final insert = indentString(state, insertCols);

        while (keep < space.length &&
            keep < insert.length &&
            space.codeUnitAt(keep) == insert.codeUnitAt(keep)) {
          keep++;
        }

        changes.add(ChangeSpec(
          from: line.from + keep,
          to: line.from + space.length,
          insert: insert.substring(keep),
        ));
      }).changes,
      userEvent: 'delete.dedent',
    ),
  ]));
  return true;
}

/// Insert a tab character or indent the selection.
/// 
/// When the selection is empty (cursor), inserts the indent unit at cursor.
/// When there's a selection, indents all selected lines.
bool insertTab(StateCommandTarget target) {
  if (target.state.selection.ranges.any((r) => !r.empty)) {
    return indentMore(target);
  }

  final state = target.state;
  final unit = state.facet(indentUnit);
  final result = state.replaceSelection(unit);
  target.dispatch(state.update([
    TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      scrollIntoView: true,
      userEvent: 'input',
    ),
  ]));
  return true;
}

// ============================================================================
// Standard Key Bindings
// ============================================================================

/// Convert a StateCommand to a keymap run function.
Command _stateCmd(StateCommand cmd) {
  return (view) {
    final state = (view as dynamic).state as EditorState;
    void dispatch(txn.Transaction tr) => (view as dynamic).dispatchTransaction(tr);
    return cmd((state: state, dispatch: dispatch));
  };
}

/// Emacs-style keybindings available on macOS by default.
///
/// - Ctrl-b: cursorCharLeft (selectCharLeft with Shift)
/// - Ctrl-f: cursorCharRight (selectCharRight with Shift)
/// - Ctrl-p: cursorLineUp (selectLineUp with Shift)
/// - Ctrl-n: cursorLineDown (selectLineDown with Shift)
/// - Ctrl-a: cursorLineStart (selectLineStart with Shift)
/// - Ctrl-e: cursorLineEnd (selectLineEnd with Shift)
/// - Ctrl-d: deleteCharForward
/// - Ctrl-h: deleteCharBackward
/// - Ctrl-k: deleteToLineEnd
/// - Ctrl-Alt-h: deleteGroupBackward
/// - Ctrl-o: splitLine
/// - Ctrl-t: transposeChars
final List<KeyBinding> emacsStyleKeymap = [
  KeyBinding(
    key: 'Ctrl-b',
    run: _stateCmd(cursorCharLeft),
    shift: _stateCmd(selectCharLeft),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Ctrl-f',
    run: _stateCmd(cursorCharRight),
    shift: _stateCmd(selectCharRight),
  ),
  KeyBinding(
    key: 'Ctrl-p',
    run: _stateCmd(cursorLineUp),
    shift: _stateCmd(selectLineUp),
  ),
  KeyBinding(
    key: 'Ctrl-n',
    run: _stateCmd(cursorLineDown),
    shift: _stateCmd(selectLineDown),
  ),
  KeyBinding(
    key: 'Ctrl-a',
    run: _stateCmd(cursorLineStart),
    shift: _stateCmd(selectLineStart),
  ),
  KeyBinding(
    key: 'Ctrl-e',
    run: _stateCmd(cursorLineEnd),
    shift: _stateCmd(selectLineEnd),
  ),
  KeyBinding(key: 'Ctrl-d', run: _stateCmd(deleteCharForward)),
  KeyBinding(key: 'Ctrl-h', run: _stateCmd(deleteCharBackward)),
  KeyBinding(key: 'Ctrl-k', run: _stateCmd(deleteToLineEnd)),
  KeyBinding(key: 'Ctrl-Alt-h', run: _stateCmd(deleteGroupBackward)),
  KeyBinding(key: 'Ctrl-o', run: _stateCmd(splitLine)),
  KeyBinding(key: 'Ctrl-t', run: _stateCmd(transposeChars)),
];

/// Standard platform keybindings.
///
/// - ArrowLeft: cursorCharLeft (selectCharLeft with Shift)
/// - ArrowRight: cursorCharRight (selectCharRight with Shift)
/// - Ctrl-ArrowLeft (Alt on Mac): cursorGroupLeft (selectGroupLeft with Shift)
/// - Ctrl-ArrowRight (Alt on Mac): cursorGroupRight (selectGroupRight with Shift)
/// - ArrowUp: cursorLineUp (selectLineUp with Shift)
/// - ArrowDown: cursorLineDown (selectLineDown with Shift)
/// - Home: cursorLineBoundaryBackward (selectLineBoundaryBackward with Shift)
/// - End: cursorLineBoundaryForward (selectLineBoundaryForward with Shift)
/// - Mod-Home: cursorDocStart (selectDocStart with Shift)
/// - Mod-End: cursorDocEnd (selectDocEnd with Shift)
/// - Mod-a: selectAll
/// - Backspace: deleteCharBackward
/// - Delete: deleteCharForward
/// - Mod-Backspace (Alt on Mac): deleteGroupBackward
/// - Mod-Delete (Alt on Mac): deleteGroupForward
/// - Enter: insertNewlineAndIndent (smart indentation)
final List<KeyBinding> standardKeymap = [
  // Character movement
  KeyBinding(
    key: 'ArrowLeft',
    run: _stateCmd(cursorCharLeft),
    shift: _stateCmd(selectCharLeft),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'ArrowRight',
    run: _stateCmd(cursorCharRight),
    shift: _stateCmd(selectCharRight),
    preventDefault: true,
  ),

  // Group/word movement
  KeyBinding(
    key: 'Mod-ArrowLeft',
    mac: 'Alt-ArrowLeft',
    run: _stateCmd(cursorGroupLeft),
    shift: _stateCmd(selectGroupLeft),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Mod-ArrowRight',
    mac: 'Alt-ArrowRight',
    run: _stateCmd(cursorGroupRight),
    shift: _stateCmd(selectGroupRight),
    preventDefault: true,
  ),

  // Mac: Cmd-Arrow for line boundaries
  KeyBinding(
    mac: 'Cmd-ArrowLeft',
    run: _stateCmd(cursorLineBoundaryBackward),
    shift: _stateCmd(selectLineBoundaryBackward),
    preventDefault: true,
  ),
  KeyBinding(
    mac: 'Cmd-ArrowRight',
    run: _stateCmd(cursorLineBoundaryForward),
    shift: _stateCmd(selectLineBoundaryForward),
    preventDefault: true,
  ),

  // Line movement
  KeyBinding(
    key: 'ArrowUp',
    run: _stateCmd(cursorLineUp),
    shift: _stateCmd(selectLineUp),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'ArrowDown',
    run: _stateCmd(cursorLineDown),
    shift: _stateCmd(selectLineDown),
    preventDefault: true,
  ),

  // Mac: Cmd-Up/Down for document boundaries
  KeyBinding(
    mac: 'Cmd-ArrowUp',
    run: _stateCmd(cursorDocStart),
    shift: _stateCmd(selectDocStart),
  ),
  KeyBinding(
    mac: 'Cmd-ArrowDown',
    run: _stateCmd(cursorDocEnd),
    shift: _stateCmd(selectDocEnd),
  ),

  // Home/End
  KeyBinding(
    key: 'Home',
    run: _stateCmd(cursorLineBoundaryBackward),
    shift: _stateCmd(selectLineBoundaryBackward),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'End',
    run: _stateCmd(cursorLineBoundaryForward),
    shift: _stateCmd(selectLineBoundaryForward),
    preventDefault: true,
  ),

  // Mod-Home/End for document boundaries
  KeyBinding(
    key: 'Mod-Home',
    run: _stateCmd(cursorDocStart),
    shift: _stateCmd(selectDocStart),
  ),
  KeyBinding(
    key: 'Mod-End',
    run: _stateCmd(cursorDocEnd),
    shift: _stateCmd(selectDocEnd),
  ),

  // Enter - use smart indentation
  KeyBinding(
    key: 'Enter',
    run: _stateCmd(insertNewlineAndIndent),
    shift: _stateCmd(insertNewlineAndIndent),
  ),

  // Select all
  KeyBinding(key: 'Mod-a', run: _stateCmd(selectAll)),

  // Delete
  KeyBinding(
    key: 'Backspace',
    run: _stateCmd(deleteCharBackward),
    shift: _stateCmd(deleteCharBackward),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Delete',
    run: _stateCmd(deleteCharForward),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Mod-Backspace',
    mac: 'Alt-Backspace',
    run: _stateCmd(deleteGroupBackward),
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Mod-Delete',
    mac: 'Alt-Delete',
    run: _stateCmd(deleteGroupForward),
    preventDefault: true,
  ),
  
  // Mac: Cmd-Backspace/Delete for line boundary deletion
  KeyBinding(
    mac: 'Mod-Backspace',
    run: _stateCmd(deleteLineBoundaryBackward),
    preventDefault: true,
  ),
  KeyBinding(
    mac: 'Mod-Delete',
    run: _stateCmd(deleteLineBoundaryForward),
    preventDefault: true,
  ),

  // Emacs bindings for Mac
  ...emacsStyleKeymap.map((b) => KeyBinding(
        mac: b.key,
        run: b.run,
        shift: b.shift,
      )),
];

/// Default keymap with additional editing commands.
///
/// Includes all of [standardKeymap] plus:
/// - Alt-ArrowUp: moveLineUp
/// - Alt-ArrowDown: moveLineDown
/// - Shift-Alt-ArrowUp: copyLineUp
/// - Shift-Alt-ArrowDown: copyLineDown
/// - Escape: simplifySelection
/// - Mod-Enter: create blank line below
/// - Alt-l (Ctrl-l on Mac): selectLine
/// - Mod-[: indentLess
/// - Mod-]: indentMore
/// - Shift-Mod-k: deleteLine
final List<KeyBinding> defaultKeymap = [
  // Line movement
  KeyBinding(key: 'Alt-ArrowUp', run: _stateCmd(moveLineUp)),
  KeyBinding(key: 'Alt-ArrowDown', run: _stateCmd(moveLineDown)),
  
  // Line copying
  KeyBinding(key: 'Shift-Alt-ArrowUp', run: _stateCmd(copyLineUp)),
  KeyBinding(key: 'Shift-Alt-ArrowDown', run: _stateCmd(copyLineDown)),

  // Simplify selection
  KeyBinding(key: 'Escape', run: _stateCmd(simplifySelection)),

  // Blank line
  KeyBinding(key: 'Mod-Enter', run: _stateCmd((target) {
    if (target.state.isReadOnly) return false;
    final state = target.state;
    final line = state.doc.lineAt(state.selection.main.head);
    target.dispatch(state.update([
      TransactionSpec(
        changes: ChangeSpec(from: line.to, insert: state.lineBreak),
        selection: EditorSelection.single(line.to + 1),
        scrollIntoView: true,
        userEvent: 'input',
      ),
    ]));
    return true;
  })),

  // Select line
  KeyBinding(key: 'Alt-l', mac: 'Ctrl-l', run: _stateCmd(selectLine)),

  // Indentation
  KeyBinding(key: 'Mod-[', run: _stateCmd(indentLess)),
  KeyBinding(key: 'Mod-]', run: _stateCmd(indentMore)),

  // Delete line
  KeyBinding(key: 'Shift-Mod-k', run: _stateCmd(deleteLine)),

  // Include all standard bindings
  ...standardKeymap,
];

/// Tab/Shift-Tab for indentation.
///
/// Use with caution - this captures Tab which may interfere with
/// accessibility (keyboard navigation).
final KeyBinding indentWithTab = KeyBinding(
  key: 'Tab',
  run: _stateCmd(insertTab),
  shift: _stateCmd(indentLess),
);
