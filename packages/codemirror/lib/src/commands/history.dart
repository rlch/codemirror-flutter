/// Undo/redo history for the editor.
///
/// This module provides undo/redo functionality through a transaction-based
/// history system. History events are grouped by time and user event type,
/// and the system supports both change and selection undo.
library;

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../view/keymap.dart';

// ============================================================================
// Branch enum - done vs undone
// ============================================================================

/// Which branch of the history to operate on.
enum _BranchName {
  /// The "done" branch - things that can be undone.
  done,

  /// The "undone" branch - things that can be redone.
  undone,
}

// ============================================================================
// Annotations
// ============================================================================

/// Internal annotation for history operations.
final _fromHistory = Annotation.define<({_BranchName side, List<_HistEvent> rest})>();

/// Transaction annotation that will prevent that transaction from
/// being combined with other transactions in the undo history.
///
/// Given `"before"`, it'll prevent merging with previous transactions.
/// With `"after"`, subsequent transactions won't be combined with this
/// one. With `"full"`, the transaction is isolated on both sides.
final isolateHistory = Annotation.define<String>();

// ============================================================================
// Facets
// ============================================================================

/// This facet provides a way to register functions that, given a
/// transaction, provide a set of effects that the history should
/// store when inverting the transaction.
///
/// This can be used to integrate some kinds of effects in the history,
/// so that they can be undone (and redone again).
final invertedEffects = Facet.define<
    List<StateEffect<dynamic>> Function(txn.Transaction),
    List<List<StateEffect<dynamic>> Function(txn.Transaction)>>(
  FacetConfig(
    combine: (values) => values.toList(),
  ),
);

/// Configuration for the history extension.
class HistoryConfig {
  /// The minimum depth (amount of events) to store. Defaults to 100.
  final int minDepth;

  /// The maximum time (in milliseconds) that adjacent events can be
  /// apart and still be grouped together. Defaults to 500.
  final int newGroupDelay;

  const HistoryConfig({
    this.minDepth = 100,
    this.newGroupDelay = 500,
  });
}

/// Facet for history configuration.
final _historyConfig = Facet.define<HistoryConfig, HistoryConfig>(
  FacetConfig(
    combine: (configs) {
      if (configs.isEmpty) {
        return const HistoryConfig();
      }
      // Combine: use max minDepth, min newGroupDelay
      var minDepth = configs.first.minDepth;
      var newGroupDelay = configs.first.newGroupDelay;
      for (final config in configs.skip(1)) {
        if (config.minDepth > minDepth) minDepth = config.minDepth;
        if (config.newGroupDelay < newGroupDelay) {
          newGroupDelay = config.newGroupDelay;
        }
      }
      return HistoryConfig(minDepth: minDepth, newGroupDelay: newGroupDelay);
    },
  ),
);

// ============================================================================
// Helper functions
// ============================================================================

/// Get the end position of changes.
int _changeEnd(ChangeDesc changes) {
  var end = 0;
  changes.iterChangedRanges((fromA, toA, fromB, toB) {
    end = toA;
  });
  return end;
}

/// Concatenate two lists, avoiding allocation when possible.
List<T> _conc<T>(List<T> a, List<T> b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return [...a, ...b];
}

/// Check if two change descriptions are adjacent (touching or overlapping).
bool _isAdjacent(ChangeDesc a, ChangeDesc b) {
  final ranges = <int>[];
  var isAdj = false;

  a.iterChangedRanges((fromA, toA, fromB, toB) {
    ranges.add(fromA);
    ranges.add(toA);
  });

  b.iterChangedRanges((fromA, toA, fromB, toB) {
    for (var i = 0; i < ranges.length; i += 2) {
      final from = ranges[i];
      final to = ranges[i + 1];
      if (toB >= from && fromB <= to) {
        isAdj = true;
      }
    }
  });

  return isAdj;
}

/// Check if two selections have the same shape (same number of ranges,
/// same empty/non-empty pattern).
bool _eqSelectionShape(EditorSelection a, EditorSelection b) {
  if (a.ranges.length != b.ranges.length) return false;
  for (var i = 0; i < a.ranges.length; i++) {
    if (a.ranges[i].empty != b.ranges[i].empty) return false;
  }
  return true;
}

/// Pattern for user events that can be joined.
final _joinableUserEvent = RegExp(r'^(input\.type|delete)($|\.)');

/// Maximum selections to store per event.
const _maxSelectionsPerEvent = 200;

// ============================================================================
// HistEvent - A single history event
// ============================================================================

/// A history event storing changes, effects, and selections.
class _HistEvent {
  /// The changes in this event (null for selection-only events).
  final ChangeSet? changes;

  /// The effects associated with this event.
  final List<StateEffect<dynamic>> effects;

  /// Mapping accumulated from subsequent changes.
  final ChangeDesc? mapped;

  /// The selection before this event.
  final EditorSelection? startSelection;

  /// Selection changes after this event.
  final List<EditorSelection> selectionsAfter;

  const _HistEvent({
    this.changes,
    this.effects = const [],
    this.mapped,
    this.startSelection,
    this.selectionsAfter = const [],
  });

  /// Create a copy with different selectionsAfter.
  _HistEvent setSelAfter(List<EditorSelection> after) {
    return _HistEvent(
      changes: changes,
      effects: effects,
      mapped: mapped,
      startSelection: startSelection,
      selectionsAfter: after,
    );
  }

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() {
    return {
      if (changes != null) 'changes': changes!.toJson(),
      if (mapped != null) 'mapped': mapped!.toJson(),
      if (startSelection != null) 'startSelection': startSelection!.toJson(),
      'selectionsAfter': selectionsAfter.map((s) => s.toJson()).toList(),
    };
  }

  /// Create from JSON.
  static _HistEvent fromJson(Map<String, dynamic> json) {
    return _HistEvent(
      changes: json['changes'] != null
          ? ChangeSet.fromJson(json['changes'] as List<dynamic>)
          : null,
      effects: const [],
      mapped: json['mapped'] != null
          ? ChangeDesc.fromJson(json['mapped'] as List<dynamic>)
          : null,
      startSelection: json['startSelection'] != null
          ? EditorSelection.fromJson(
              json['startSelection'] as Map<String, dynamic>)
          : null,
      selectionsAfter: (json['selectionsAfter'] as List<dynamic>)
          .map((s) => EditorSelection.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Create from a transaction.
  ///
  /// Returns null if the transaction has no changes or effects to store.
  static _HistEvent? fromTransaction(
    txn.Transaction transaction, [
    EditorSelection? selection,
  ]) {
    List<StateEffect<dynamic>> effects = [];

    // Get inverted effects from registered providers
    final state = transaction.startState as EditorState;
    for (final invert in state.facet(invertedEffects)) {
      final result = invert(transaction);
      if (result.isNotEmpty) {
        effects = [...effects, ...result];
      }
    }

    if (effects.isEmpty && transaction.changes.empty) return null;

    return _HistEvent(
      changes: transaction.changes.invert(state.doc),
      effects: effects,
      startSelection: selection ?? state.selection,
    );
  }

  /// Create a selection-only event.
  static _HistEvent selection(List<EditorSelection> selections) {
    return _HistEvent(selectionsAfter: selections);
  }
}

// ============================================================================
// Branch operations
// ============================================================================

/// Update a branch, trimming if it exceeds maxLen.
List<_HistEvent> _updateBranch(
  List<_HistEvent> branch,
  int to,
  int maxLen,
  _HistEvent newEvent,
) {
  final start = to + 1 > maxLen + 20 ? to - maxLen - 1 : 0;
  final newBranch = branch.sublist(start, to).toList();
  newBranch.add(newEvent);
  return newBranch;
}

/// Add a selection to a branch.
List<_HistEvent> _addSelection(
    List<_HistEvent> branch, EditorSelection selection) {
  if (branch.isEmpty) {
    return [_HistEvent.selection([selection])];
  } else {
    final lastEvent = branch.last;
    var sels = lastEvent.selectionsAfter.length > _maxSelectionsPerEvent
        ? lastEvent.selectionsAfter
            .sublist(lastEvent.selectionsAfter.length - _maxSelectionsPerEvent)
            .toList()
        : lastEvent.selectionsAfter.toList();

    if (sels.isNotEmpty && sels.last.eq(selection)) return branch;

    sels.add(selection);
    return _updateBranch(
        branch, branch.length - 1, 1000000000, lastEvent.setSelAfter(sels));
  }
}

/// Pop a selection from a branch.
List<_HistEvent> _popSelection(List<_HistEvent> branch) {
  final last = branch.last;
  final newBranch = branch.toList();
  newBranch[branch.length - 1] = last.setSelAfter(
    last.selectionsAfter.sublist(0, last.selectionsAfter.length - 1),
  );
  return newBranch;
}

/// Add a mapping to all events in a branch.
List<_HistEvent> _addMappingToBranch(
    List<_HistEvent> branch, ChangeDesc mapping) {
  if (branch.isEmpty) return branch;

  var length = branch.length;
  List<EditorSelection> selections = [];

  while (length > 0) {
    final event = _mapEvent(branch[length - 1], mapping, selections);
    if (event.changes != null && !event.changes!.empty ||
        event.effects.isNotEmpty) {
      // Event survived mapping
      final result = branch.sublist(0, length).toList();
      result[length - 1] = event;
      return result;
    } else {
      // Drop this event
      mapping = event.mapped!;
      length--;
      selections = event.selectionsAfter;
    }
  }

  return selections.isNotEmpty ? [_HistEvent.selection(selections)] : [];
}

/// Map an event through a change description.
_HistEvent _mapEvent(
  _HistEvent event,
  ChangeDesc mapping,
  List<EditorSelection> extraSelections,
) {
  final selections = _conc(
    event.selectionsAfter.isNotEmpty
        ? event.selectionsAfter.map((s) => s.map(mapping)).toList()
        : <EditorSelection>[],
    extraSelections,
  );

  // Selection-only events don't store mappings
  if (event.changes == null) {
    return _HistEvent.selection(selections);
  }

  final mappedChanges = event.changes!.map(mapping);
  final before = mapping.mapDesc(event.changes!, true);
  final fullMapping =
      event.mapped != null ? event.mapped!.composeDesc(before) : before;

  return _HistEvent(
    changes: mappedChanges,
    effects: StateEffect.mapEffects(event.effects, mapping),
    mapped: fullMapping,
    startSelection: event.startSelection!.map(before),
    selectionsAfter: selections,
  );
}

// ============================================================================
// HistoryState - The complete history state
// ============================================================================

/// The state of the undo/redo history.
class _HistoryState {
  /// Events that can be undone.
  final List<_HistEvent> done;

  /// Events that can be redone.
  final List<_HistEvent> undone;

  /// Time of the previous event.
  final int _prevTime;

  /// User event of the previous transaction.
  final String? _prevUserEvent;

  const _HistoryState(
    this.done,
    this.undone, [
    this._prevTime = 0,
    this._prevUserEvent,
  ]);

  /// Empty history state.
  static const empty = _HistoryState([], []);

  /// Isolate the history (prevent merging with subsequent events).
  _HistoryState isolate() {
    return _prevTime != 0 ? _HistoryState(done, undone) : this;
  }

  /// Add changes to the history.
  _HistoryState addChanges(
    _HistEvent event,
    int time,
    String? userEvent,
    int newGroupDelay,
    int maxLen,
  ) {
    var newDone = done;
    final lastEvent = done.isNotEmpty ? done.last : null;

    if (lastEvent != null &&
        lastEvent.changes != null &&
        !lastEvent.changes!.empty &&
        event.changes != null &&
        (userEvent == null || _joinableUserEvent.hasMatch(userEvent)) &&
        ((lastEvent.selectionsAfter.isEmpty &&
                time - _prevTime < newGroupDelay &&
                _isAdjacent(lastEvent.changes!, event.changes!)) ||
            userEvent == 'input.type.compose')) {
      // Join with previous event
      newDone = _updateBranch(
        done,
        done.length - 1,
        maxLen,
        _HistEvent(
          changes: event.changes!.compose(lastEvent.changes!),
          effects: _conc(event.effects, lastEvent.effects),
          mapped: lastEvent.mapped,
          startSelection: lastEvent.startSelection,
        ),
      );
    } else {
      newDone = _updateBranch(done, done.length, maxLen, event);
    }

    return _HistoryState(newDone, [], time, userEvent);
  }

  /// Add a selection change to the history.
  _HistoryState addSelection(
    EditorSelection selection,
    int time,
    String? userEvent,
    int newGroupDelay,
  ) {
    final last =
        done.isNotEmpty ? done.last.selectionsAfter : <EditorSelection>[];

    if (last.isNotEmpty &&
        time - _prevTime < newGroupDelay &&
        userEvent == _prevUserEvent &&
        userEvent != null &&
        RegExp(r'^select($|\.)').hasMatch(userEvent) &&
        _eqSelectionShape(last.last, selection)) {
      return this;
    }

    return _HistoryState(
      _addSelection(done, selection),
      undone,
      time,
      userEvent,
    );
  }

  /// Add a mapping to both branches.
  _HistoryState addMapping(ChangeDesc mapping) {
    return _HistoryState(
      _addMappingToBranch(done, mapping),
      _addMappingToBranch(undone, mapping),
      _prevTime,
      _prevUserEvent,
    );
  }

  /// Pop an event from the history.
  txn.Transaction? pop(
      _BranchName side, EditorState state, bool includeSelection) {
    final branch = side == _BranchName.done ? done : undone;
    if (branch.isEmpty) return null;

    final event = branch.last;

    if (includeSelection && event.selectionsAfter.isNotEmpty) {
      return state.update([
        TransactionSpec(
          selection: event.selectionsAfter.last,
          annotations: [
            _fromHistory.of((side: side, rest: _popSelection(branch))),
          ],
          userEvent: side == _BranchName.done ? 'select.undo' : 'select.redo',
          scrollIntoView: true,
        ),
      ]);
    } else if (event.changes == null) {
      return null;
    } else {
      var rest = branch.length == 1
          ? <_HistEvent>[]
          : branch.sublist(0, branch.length - 1);
      if (event.mapped != null) {
        rest = _addMappingToBranch(rest, event.mapped!);
      }

      return state.update([
        TransactionSpec(
          changes: event.changes,
          selection: event.startSelection,
          effects: event.effects,
          annotations: [
            _fromHistory.of((side: side, rest: rest)),
          ],
          filter: false,
          userEvent: side == _BranchName.done ? 'undo' : 'redo',
          scrollIntoView: true,
        ),
      ]);
    }
  }
}

// ============================================================================
// StateField for history
// ============================================================================

/// The state field that stores history data.
final historyField = StateField.define<_HistoryState>(
  StateFieldConfig(
    create: (_) => _HistoryState.empty,
    update: (histState, transaction) {
      final trans = transaction as txn.Transaction;
      final state = trans.state as EditorState;
      final config = state.facet(_historyConfig);

      // Check if this is a history operation
      final fromHist = trans.annotation(_fromHistory);
      if (fromHist != null) {
        final selection = trans.docChanged
            ? EditorSelection.single(_changeEnd(trans.changes))
            : null;
        final item = _HistEvent.fromTransaction(trans, selection);
        final from = fromHist.side;
        var other = from == _BranchName.done ? histState.undone : histState.done;

        if (item != null) {
          other = _updateBranch(other, other.length, config.minDepth, item);
        } else {
          other = _addSelection(
              other, (trans.startState as EditorState).selection);
        }

        return _HistoryState(
          from == _BranchName.done ? fromHist.rest : other,
          from == _BranchName.done ? other : fromHist.rest,
        );
      }

      // Check for isolation
      final isolate = trans.annotation(isolateHistory);
      var newState = histState;
      if (isolate == 'full' || isolate == 'before') {
        newState = newState.isolate();
      }

      // Check if this should be added to history
      if (trans.annotation(txn.Transaction.addToHistory) == false) {
        return !trans.changes.empty ? newState.addMapping(trans.changes.desc) : newState;
      }

      // Add the event to history
      final event = _HistEvent.fromTransaction(trans);
      final time = trans.annotation(txn.Transaction.time) ?? 0;
      final userEvent = trans.annotation(txn.Transaction.userEvent);

      if (event != null) {
        newState = newState.addChanges(
          event,
          time,
          userEvent,
          config.newGroupDelay,
          config.minDepth,
        );
      } else if (trans.selection != null) {
        newState = newState.addSelection(
          (trans.startState as EditorState).selection,
          time,
          userEvent,
          config.newGroupDelay,
        );
      }

      if (isolate == 'full' || isolate == 'after') {
        newState = newState.isolate();
      }

      return newState;
    },
    toJson: (value) => {
      'done': value.done.map((e) => e.toJson()).toList(),
      'undone': value.undone.map((e) => e.toJson()).toList(),
    },
    fromJson: (json, state) {
      final done = (json['done'] as List<dynamic>)
          .map((e) => _HistEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      final undone = (json['undone'] as List<dynamic>)
          .map((e) => _HistEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      return _HistoryState(done, undone);
    },
  ),
);

// ============================================================================
// Commands
// ============================================================================

/// Command target interface for history commands.
///
/// A command target has access to the editor state and a dispatch function
/// to apply transactions.
typedef CommandTarget = ({EditorState state, void Function(txn.Transaction) dispatch});

/// Create a history command.
bool Function(CommandTarget) _cmd(_BranchName side, bool selection) {
  return (target) {
    final state = target.state;
    if (!selection && state.isReadOnly) return false;

    final histState = state.field(historyField);
    if (histState == null) return false;

    final transaction = histState.pop(side, state, selection);
    if (transaction == null) return false;

    target.dispatch(transaction);
    return true;
  };
}

/// Undo a single group of history events.
///
/// Returns false if no group was available.
bool undo(CommandTarget target) => _cmd(_BranchName.done, false)(target);

/// Redo a group of history events.
///
/// Returns false if no group was available.
bool redo(CommandTarget target) => _cmd(_BranchName.undone, false)(target);

/// Undo a change or selection change.
bool undoSelection(CommandTarget target) => _cmd(_BranchName.done, true)(target);

/// Redo a change or selection change.
bool redoSelection(CommandTarget target) => _cmd(_BranchName.undone, true)(target);

/// Get the depth of undoable events.
int undoDepth(EditorState state) {
  final histState = state.field(historyField);
  if (histState == null) return 0;
  final branch = histState.done;
  return branch.length - (branch.isNotEmpty && branch.first.changes == null ? 1 : 0);
}

/// Get the depth of redoable events.
int redoDepth(EditorState state) {
  final histState = state.field(historyField);
  if (histState == null) return 0;
  final branch = histState.undone;
  return branch.length - (branch.isNotEmpty && branch.first.changes == null ? 1 : 0);
}

// ============================================================================
// Extension factory
// ============================================================================

/// Create a history extension with the given configuration.
///
/// Example:
/// ```dart
/// EditorState.create(
///   EditorStateConfig(
///     doc: 'Hello, World!',
///     extensions: ExtensionList([
///       history(const HistoryConfig(minDepth: 200)),
///     ]),
///   ),
/// )
/// ```
Extension history([HistoryConfig config = const HistoryConfig()]) {
  return ExtensionList([
    historyField,
    _historyConfig.of(config),
  ]);
}

/// Default key bindings for the undo history.
///
/// - Mod-z: [undo]
/// - Mod-y (Mod-Shift-z on macOS): [redo]
/// - Mod-u: [undoSelection]
/// - Alt-u (Mod-Shift-u on macOS): [redoSelection]
final List<KeyBinding> historyKeymap = [
  KeyBinding(
    key: 'Mod-z',
    run: (view) {
      final state = (view as dynamic).state as EditorState;
      final dispatchTransaction =
          (view as dynamic).dispatchTransaction as void Function(txn.Transaction);
      return undo((state: state, dispatch: dispatchTransaction));
    },
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Mod-y',
    mac: 'Mod-Shift-z',
    run: (view) {
      final state = (view as dynamic).state as EditorState;
      final dispatchTransaction =
          (view as dynamic).dispatchTransaction as void Function(txn.Transaction);
      return redo((state: state, dispatch: dispatchTransaction));
    },
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Mod-u',
    run: (view) {
      final state = (view as dynamic).state as EditorState;
      final dispatchTransaction =
          (view as dynamic).dispatchTransaction as void Function(txn.Transaction);
      return undoSelection((state: state, dispatch: dispatchTransaction));
    },
    preventDefault: true,
  ),
  KeyBinding(
    key: 'Alt-u',
    mac: 'Mod-Shift-u',
    run: (view) {
      final state = (view as dynamic).state as EditorState;
      final dispatchTransaction =
          (view as dynamic).dispatchTransaction as void Function(txn.Transaction);
      return redoSelection((state: state, dispatch: dispatchTransaction));
    },
    preventDefault: true,
  ),
];
