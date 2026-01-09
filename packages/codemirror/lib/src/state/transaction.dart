/// Transaction handling for editor state changes.
///
/// This module provides [Transaction], [Annotation], and [StateEffect] for
/// representing and applying changes to the editor state.
library;

import 'package:meta/meta.dart';

import '../text/text.dart';
import 'change.dart';
import 'selection.dart';
import 'facet.dart' as facet_module show Transaction;

// Forward reference to EditorState
// Import lazily to avoid circular dependency
typedef EditorStateRef = Object;

/// Annotations are tagged values that are used to add metadata to
/// transactions in an extensible way.
///
/// They should be used to model things that affect the entire transaction
/// (such as its [Transaction.time] or information about its
/// [Transaction.userEvent]). For effects that happen _alongside_ the other
/// changes made by the transaction, [StateEffect] is more appropriate.
@immutable
class Annotation<T> {
  /// The annotation type.
  final AnnotationType<T> type;

  /// The value of this annotation.
  final T value;

  /// @internal
  const Annotation(this.type, this.value);

  /// Define a new type of annotation.
  static AnnotationType<T> define<T>() => AnnotationType<T>();
}

/// Marker that identifies a type of [Annotation].
class AnnotationType<T> {
  /// Create an instance of this annotation.
  Annotation<T> of(T value) => Annotation<T>(this, value);
}

/// Specification for how to map [StateEffect] values through position changes.
typedef StateEffectMapFn<Value> = Value? Function(Value value, ChangeDesc mapping);

/// Representation of a type of state effect.
///
/// Defined with [StateEffect.define].
class StateEffectType<Value> {
  /// @internal
  final StateEffectMapFn<Value> _map;

  /// @internal
  const StateEffectType(this._map);

  /// Create a [StateEffect] instance of this type.
  StateEffect<Value> of(Value value) => StateEffect<Value>._(this, value);
}

/// State effects can be used to represent additional effects
/// associated with a [Transaction].
///
/// They are often useful to model changes to custom state fields,
/// when those changes aren't implicit in document or selection changes.
@immutable
class StateEffect<Value> {
  /// @internal
  final StateEffectType<Value> type;

  /// The value of this effect.
  final Value value;

  const StateEffect._(this.type, this.value);

  /// Map this effect through a position mapping.
  ///
  /// Returns `null` when that ends up deleting the effect.
  StateEffect<Value>? map(ChangeDesc mapping) {
    final mapped = type._map(value, mapping);
    if (mapped == null) return null;
    return identical(mapped, value) ? this : StateEffect._(type, mapped);
  }

  /// Tells you whether this effect object is of a given [type].
  bool is_<T>(StateEffectType<T> type) => this.type == type;

  /// Define a new effect type.
  ///
  /// The type parameter indicates the type of values that this effect holds.
  /// It should be a type that doesn't include `null`, since that is used in
  /// [map] to indicate that an effect is removed.
  static StateEffectType<Value> define<Value>({
    StateEffectMapFn<Value>? map,
  }) {
    return StateEffectType<Value>(map ?? ((v, _) => v));
  }

  /// Map an array of effects through a change set.
  static List<StateEffect<dynamic>> mapEffects(
    List<StateEffect<dynamic>> effects,
    ChangeDesc mapping,
  ) {
    if (effects.isEmpty) return effects;
    final result = <StateEffect<dynamic>>[];
    for (final effect in effects) {
      final mapped = effect.map(mapping);
      if (mapped != null) result.add(mapped);
    }
    return result;
  }

  /// This effect can be used to reconfigure the root extensions of the editor.
  ///
  /// Doing this will discard any extensions appended, but does not reset
  /// the content of reconfigured compartments.
  static final StateEffectType<dynamic> reconfigure = StateEffect.define<dynamic>();

  /// Append extensions to the top-level configuration of the editor.
  static final StateEffectType<dynamic> appendConfig = StateEffect.define<dynamic>();
}

/// Describes a [Transaction] when calling `EditorState.update`.
class TransactionSpec {
  /// The changes to the document made by this transaction.
  final dynamic changes;

  /// When set, this transaction explicitly updates the selection.
  ///
  /// Offsets in this selection should refer to the document as it is
  /// _after_ the transaction.
  final EditorSelection? selection;

  /// The anchor position for cursor-style selection.
  ///
  /// Used as a shorthand when [selection] is not specified.
  final int? anchor;

  /// The head position for cursor-style selection.
  ///
  /// Only meaningful when [anchor] is also specified.
  final int? head;

  /// Attach [StateEffect]s to this transaction.
  ///
  /// When they contain positions and this same spec makes changes,
  /// those positions should refer to positions in the updated document.
  final List<StateEffect<dynamic>>? effects;

  /// Set [Annotation]s for this transaction.
  final List<Annotation<dynamic>>? annotations;

  /// Shorthand for `annotations: [Transaction.userEvent.of(...)]`.
  final String? userEvent;

  /// When set to `true`, the transaction is marked as needing to
  /// scroll the current selection into view.
  final bool scrollIntoView;

  /// By default, transactions can be modified by change filters and
  /// transaction filters. Set this to `false` to disable that.
  ///
  /// This can be necessary for transactions that include annotations
  /// that must be kept consistent with their changes.
  final bool filter;

  /// Normally, when multiple specs are combined, the positions in
  /// [changes] refer to the document positions in the initial document.
  ///
  /// When a spec has [sequential] set to true, its positions refer to
  /// the document created by the specs before it instead.
  final bool sequential;

  const TransactionSpec({
    this.changes,
    this.selection,
    this.anchor,
    this.head,
    this.effects,
    this.annotations,
    this.userEvent,
    this.scrollIntoView = false,
    this.filter = true,
    this.sequential = false,
  });
}

/// Internal representation of a resolved transaction spec.
@internal
class ResolvedSpec {
  final ChangeSet changes;
  final EditorSelection? selection;
  final List<StateEffect<dynamic>> effects;
  final List<Annotation<dynamic>> annotations;
  final bool scrollIntoView;

  const ResolvedSpec({
    required this.changes,
    this.selection,
    required this.effects,
    required this.annotations,
    required this.scrollIntoView,
  });
}

/// Changes to the editor state are grouped into transactions.
///
/// Typically, a user action creates a single transaction, which may
/// contain any number of document changes, may change the selection,
/// or have other effects. Create a transaction by calling
/// `EditorState.update`, or immediately dispatch one by calling
/// `EditorView.dispatch`.
class Transaction implements ResolvedSpec, facet_module.Transaction {
  /// Cached new document. @internal
  @internal
  Text? docValue;

  /// Cached new state. @internal
  @internal
  EditorStateRef? stateValue;

  /// The state from which the transaction starts.
  final EditorStateRef startState;

  /// The document changes made by this transaction.
  @override
  final ChangeSet changes;

  /// The selection set by this transaction, or null if it doesn't
  /// explicitly set a selection.
  @override
  final EditorSelection? selection;

  /// The effects added to the transaction.
  @override
  final List<StateEffect<dynamic>> effects;

  /// @internal
  @override
  final List<Annotation<dynamic>> annotations;

  /// Whether the selection should be scrolled into view after this
  /// transaction is dispatched.
  @override
  final bool scrollIntoView;

  Transaction._({
    required this.startState,
    required this.changes,
    this.selection,
    required this.effects,
    required List<Annotation<dynamic>> annotations,
    required this.scrollIntoView,
  }) : annotations = _ensureTimeAnnotation(annotations) {
    if (selection != null) checkSelection(selection!, changes.newLength);
  }

  static List<Annotation<dynamic>> _ensureTimeAnnotation(
    List<Annotation<dynamic>> annotations,
  ) {
    if (annotations.any((a) => a.type == Transaction.time)) {
      return annotations;
    }
    return [
      ...annotations,
      Transaction.time.of(DateTime.now().millisecondsSinceEpoch),
    ];
  }

  /// @internal
  static Transaction create({
    required EditorStateRef startState,
    required ChangeSet changes,
    EditorSelection? selection,
    required List<StateEffect<dynamic>> effects,
    required List<Annotation<dynamic>> annotations,
    required bool scrollIntoView,
  }) {
    return Transaction._(
      startState: startState,
      changes: changes,
      selection: selection,
      effects: List.unmodifiable(effects),
      annotations: annotations.toList(), // Mutable to allow time annotation
      scrollIntoView: scrollIntoView,
    );
  }

  /// The new document produced by the transaction.
  ///
  /// Contrary to `.state.doc`, accessing this won't force the entire
  /// new state to be computed right away, so it is recommended that
  /// transaction filters use this getter when they need to look at
  /// the new document.
  Text get newDoc {
    return docValue ??= _computeNewDoc();
  }

  Text _computeNewDoc() {
    // The startState must have a 'doc' property - we use dynamic access
    // to avoid the circular import issue
    final dynamic state = startState;
    final Text startDoc = state.doc as Text;
    return changes.apply(startDoc);
  }

  /// The new selection produced by the transaction.
  ///
  /// If [selection] is null, this will map the start state's current
  /// selection through the changes made by the transaction.
  EditorSelection get newSelection {
    if (selection != null) return selection!;
    // The startState must have a 'selection' property
    final dynamic state = startState;
    final EditorSelection startSel = state.selection as EditorSelection;
    return startSel.map(changes);
  }

  /// The new state created by the transaction.
  ///
  /// Computed on demand (but retained for subsequent access), so it is
  /// recommended not to access it in transaction filters when possible.
  EditorStateRef get state {
    if (stateValue == null) {
      // The startState must have an 'applyTransaction' method
      final dynamic state = startState;
      state.applyTransaction(this);
    }
    return stateValue!;
  }

  /// Get the value of the given annotation type, if any.
  T? annotation<T>(AnnotationType<T> type) {
    for (final ann in annotations) {
      if (ann.type == type) return ann.value as T;
    }
    return null;
  }

  /// Indicates whether the transaction changed the document.
  @override
  bool get docChanged => !changes.empty;

  /// Indicates whether this transaction reconfigures the state.
  ///
  /// This happens through a configuration compartment or with a top-level
  /// configuration [StateEffect.reconfigure].
  bool get reconfigured {
    // TODO: Implement when EditorState is available
    // return startState.config != state.config;
    return effects.any((e) => e.is_(StateEffect.reconfigure));
  }

  /// Returns true if the transaction has a user event annotation
  /// that is equal to or more specific than [event].
  ///
  /// For example, if the transaction has `"select.pointer"` as user event,
  /// `"select"` and `"select.pointer"` will match it.
  bool isUserEvent(String event) {
    final e = annotation(Transaction.userEvent);
    if (e == null) return false;
    return e == event ||
        (e.length > event.length &&
            e.substring(0, event.length) == event &&
            e[event.length] == '.');
  }

  /// Annotation used to store transaction timestamps.
  ///
  /// Automatically added to every transaction, holding `Date.now()`.
  static final time = Annotation.define<int>();

  /// Annotation used to associate a transaction with a user interface event.
  ///
  /// Holds a string identifying the event, using a dot-separated format
  /// to support attaching more specific information. The events used by
  /// the core libraries are:
  ///
  /// - `"input"` when content is entered
  ///   - `"input.type"` for typed input
  ///     - `"input.type.compose"` for composition
  ///   - `"input.paste"` for pasted input
  ///   - `"input.drop"` when adding content with drag-and-drop
  ///   - `"input.complete"` when autocompleting
  /// - `"delete"` when the user deletes content
  ///   - `"delete.selection"` when deleting the selection
  ///   - `"delete.forward"` when deleting forward from the selection
  ///   - `"delete.backward"` when deleting backward from the selection
  ///   - `"delete.cut"` when cutting to the clipboard
  /// - `"move"` when content is moved
  ///   - `"move.drop"` when content is moved through drag-and-drop
  /// - `"select"` when explicitly changing the selection
  ///   - `"select.pointer"` when selecting with a mouse or other device
  /// - `"undo"` and `"redo"` for history actions
  ///
  /// Use [isUserEvent] to check whether the annotation matches a given event.
  static final userEvent = Annotation.define<String>();

  /// Annotation indicating whether a transaction should be added to
  /// the undo history or not.
  static final addToHistory = Annotation.define<bool>();

  /// Annotation indicating (when present and true) that a transaction
  /// represents a change made by some other actor, not the user.
  ///
  /// This is used, for example, to tag other people's changes in
  /// collaborative editing.
  static final remote = Annotation.define<bool>();
}

/// Join ranges from two sorted arrays, merging adjacent or overlapping ranges.
@internal
List<int> joinRanges(List<int> a, List<int> b) {
  final result = <int>[];
  var iA = 0, iB = 0;
  while (true) {
    int from, to;
    if (iA < a.length && (iB >= b.length || b[iB] >= a[iA])) {
      from = a[iA++];
      to = a[iA++];
    } else if (iB < b.length) {
      from = b[iB++];
      to = b[iB++];
    } else {
      return result;
    }
    if (result.isEmpty || result[result.length - 1] < from) {
      result.add(from);
      result.add(to);
    } else if (result[result.length - 1] < to) {
      result[result.length - 1] = to;
    }
  }
}

/// Merge two resolved transaction specs.
@internal
ResolvedSpec mergeTransaction(
  ResolvedSpec a,
  ResolvedSpec b,
  bool sequential,
) {
  ChangeDesc mapForA;
  ChangeDesc mapForB;
  ChangeSet changes;

  if (sequential) {
    mapForA = b.changes;
    mapForB = ChangeSet.emptySet(b.changes.length);
    changes = a.changes.compose(b.changes);
  } else {
    // b.changes.map(a.changes) returns a ChangeSet when b.changes is a ChangeSet
    final mappedB = b.changes.map(a.changes);
    mapForA = mappedB;
    mapForB = a.changes.mapDesc(b.changes, true);
    changes = a.changes.compose(mappedB);
  }

  EditorSelection? selection;
  if (b.selection != null) {
    selection = b.selection!.map(mapForB);
  } else if (a.selection != null) {
    selection = a.selection!.map(mapForA);
  }

  return ResolvedSpec(
    changes: changes,
    selection: selection,
    effects: [
      ...StateEffect.mapEffects(a.effects, mapForA),
      ...StateEffect.mapEffects(b.effects, mapForB),
    ],
    annotations: a.annotations.isNotEmpty
        ? [...a.annotations, ...b.annotations]
        : b.annotations,
    scrollIntoView: a.scrollIntoView || b.scrollIntoView,
  );
}

/// Resolve a transaction spec to its internal representation.
@internal
ResolvedSpec resolveTransactionInner(
  EditorStateRef state,
  TransactionSpec spec,
  int docSize,
  String? lineSep,
) {
  // Build selection from spec
  EditorSelection? sel;
  if (spec.selection != null) {
    sel = spec.selection;
  } else if (spec.anchor != null) {
    sel = EditorSelection.single(spec.anchor!, spec.head);
  }

  // Build annotations list
  var annotations = spec.annotations?.toList() ?? <Annotation<dynamic>>[];
  if (spec.userEvent != null) {
    annotations = [...annotations, Transaction.userEvent.of(spec.userEvent!)];
  }

  // Build changes
  ChangeSet changes;
  if (spec.changes is ChangeSet) {
    changes = spec.changes as ChangeSet;
  } else if (spec.changes != null) {
    changes = ChangeSet.of(
      spec.changes is List ? spec.changes as List : [spec.changes],
      docSize,
      lineSep,
    );
  } else {
    changes = ChangeSet.emptySet(docSize);
  }

  return ResolvedSpec(
    changes: changes,
    selection: sel,
    effects: spec.effects ?? const [],
    annotations: annotations,
    scrollIntoView: spec.scrollIntoView,
  );
}

/// Resolve multiple transaction specs into a single transaction.
///
/// This is called by `EditorState.update` to create a transaction from
/// one or more specs.
@internal
Transaction resolveTransaction(
  EditorStateRef state,
  List<TransactionSpec> specs,
  int docLength,
  String? lineSep, {
  bool filter = true,
}) {
  var s = resolveTransactionInner(
    state,
    specs.isNotEmpty ? specs[0] : const TransactionSpec(),
    docLength,
    lineSep,
  );

  if (specs.isNotEmpty && !specs[0].filter) filter = false;

  for (var i = 1; i < specs.length; i++) {
    if (!specs[i].filter) filter = false;
    final seq = specs[i].sequential;
    s = mergeTransaction(
      s,
      resolveTransactionInner(
        state,
        specs[i],
        seq ? s.changes.newLength : docLength,
        lineSep,
      ),
      seq,
    );
  }

  final tr = Transaction.create(
    startState: state,
    changes: s.changes,
    selection: s.selection,
    effects: s.effects,
    annotations: s.annotations,
    scrollIntoView: s.scrollIntoView,
  );

  // TODO: Apply filters when EditorState facets are available
  // return extendTransaction(filter ? filterTransaction(tr) : tr);
  return tr;
}

/// Convert a value that may be a single item or a list into a list.
@internal
List<T> asArray<T>(dynamic value) {
  if (value == null) return const [];
  if (value is List<T>) return value;
  if (value is List) return value.cast<T>();
  return [value as T];
}

// TODO: Implement filterTransaction when facets are available
// This applies change filters and transaction filters from the state.

// TODO: Implement extendTransaction when facets are available
// This applies transaction extenders from the state.
