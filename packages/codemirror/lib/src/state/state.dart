/// Editor state - the core immutable state representation.
///
/// This module provides [EditorState], the persistent data structure
/// representing the complete state of an editor instance.
library;

import 'package:meta/meta.dart';

import '../text/text.dart';
import 'change.dart';
import 'charcategory.dart';
import 'selection.dart';
import 'transaction.dart';
import 'facet.dart' hide Transaction;
import 'facet.dart'
    as facet_module
    show
        Configuration,
        DynamicSlot,
        ensureAddr,
        getAddr,
        Compartment,
        CompartmentReconfigure,
        EditorState,
        Transaction;

// ============================================================================
// Extension Facets (ported from extension.ts)
// ============================================================================

/// Facet for language data providers.
///
/// Returns a list of objects mapping property names to language data values.
final Facet<
  List<Map<String, dynamic>> Function(EditorState state, int pos, int side),
  List<
    List<Map<String, dynamic>> Function(EditorState state, int pos, int side)
  >
>
languageData = Facet.define();

/// A facet that, when enabled, causes the editor to allow multiple
/// ranges to be selected.
///
/// Be careful though, because by default the editor relies on the native
/// DOM selection, which cannot handle multiple selections. An extension
/// like `drawSelection` can be used to make secondary selections visible
/// to the user.
final Facet<bool, bool> allowMultipleSelections = Facet.define(
  FacetConfig(combine: (values) => values.any((v) => v), isStatic: true),
);

/// Facet for the line separator.
///
/// When configured, only the specified separator will be used, allowing
/// documents to be round-tripped through the editor without normalizing
/// line separators.
final Facet<String, String?> lineSeparator = Facet.define(
  FacetConfig(
    combine: (values) => values.isNotEmpty ? values[0] : null,
    isStatic: true,
  ),
);

/// Facet used to register change filters, which are called for each
/// transaction (unless explicitly disabled), and can suppress part of
/// the transaction's changes.
///
/// Such a function can return `true` to indicate that it doesn't want to
/// do anything, `false` to completely stop the changes in the transaction,
/// or a set of ranges in which changes should be suppressed. Such ranges
/// are represented as a list of integers, with each pair of two numbers
/// indicating the start and end of a range.
final Facet<
  dynamic Function(Transaction tr),
  List<dynamic Function(Transaction tr)>
>
changeFilter = Facet.define();

/// Facet used to register a hook that gets a chance to update or replace
/// transaction specs before they are applied.
///
/// This will only be applied for transactions that don't have `filter`
/// set to `false`. You can either return a single transaction spec
/// (possibly the input transaction), or a list of specs.
///
/// When possible, it is recommended to avoid accessing `Transaction.state`
/// in a filter, since it will force creation of a state that will then be
/// discarded again, if the transaction is actually filtered.
final Facet<
  dynamic Function(Transaction tr),
  List<dynamic Function(Transaction tr)>
>
transactionFilter = Facet.define();

/// This is a more limited form of [transactionFilter], which can only add
/// annotations and effects.
///
/// But, this type of filter runs even if the transaction has disabled
/// regular filtering, making it suitable for effects that don't need to
/// touch the changes or selection, but do want to process every transaction.
///
/// Extenders run _after_ filters, when both are present.
final Facet<
  TransactionSpec? Function(Transaction tr),
  List<TransactionSpec? Function(Transaction tr)>
>
transactionExtender = Facet.define();

/// This facet controls the value of the [EditorState.readOnly] getter.
///
/// Commands and extensions that implement editing functionality consult
/// this to determine whether they should apply. It defaults to false,
/// but when its highest-precedence value is `true`, such functionality
/// disables itself.
///
/// Not to be confused with `EditorView.editable`, which controls whether
/// the editor's DOM is set to be editable (and thus focusable).
final Facet<bool, bool> readOnly = Facet.define(
  FacetConfig(combine: (values) => values.isNotEmpty ? values[0] : false),
);

// ============================================================================
// EditorStateConfig
// ============================================================================

/// Options passed when creating an editor state.
class EditorStateConfig {
  /// The initial document.
  ///
  /// Can be provided either as a plain string (which will be split into
  /// lines according to the value of the [lineSeparator] facet), or an
  /// instance of the [Text] class.
  final Object? doc;

  /// The starting selection.
  ///
  /// Defaults to a cursor at the very start of the document.
  final Object? selection;

  /// Extensions to associate with this state.
  final Extension? extensions;

  const EditorStateConfig({this.doc, this.selection, this.extensions});
}

// ============================================================================
// EditorState
// ============================================================================

/// The editor state class is a persistent (immutable) data structure.
///
/// To update a state, you create a [Transaction], which produces a _new_
/// state instance, without modifying the original object.
///
/// As such, _never_ mutate properties of a state directly. That'll just
/// break things.
class EditorState implements facet_module.EditorState {
  /// The configuration for this state.
  @override
  final facet_module.Configuration config;

  /// The current document.
  final Text doc;

  /// The current selection.
  final EditorSelection selection;

  /// Internal values array.
  @internal
  @override
  final List<dynamic> values;

  /// Internal status array for slot resolution.
  @internal
  @override
  final List<int> status;

  /// Internal slot computation function.
  @internal
  @override
  int Function(facet_module.EditorState, facet_module.DynamicSlot)? computeSlot;

  EditorState._({
    required this.config,
    required this.doc,
    required this.selection,
    required this.values,
    required this.computeSlot,
    Transaction? tr,
  }) : status = config.statusTemplate.toList() {
    // Fill in the computed state immediately, so that further queries
    // for it made during the update return this state
    tr?.stateValue = this;
    for (var i = 0; i < config.dynamicSlots.length; i++) {
      facet_module.ensureAddr(this, i << 1);
    }
    computeSlot = null;
  }

  /// Retrieve the value of a [StateField].
  ///
  /// Throws an error when the state doesn't have that field, unless you
  /// pass `false` as second parameter.
  @override
  T? field<T>(StateField<T> field, [bool require = true]) {
    final addr = config.address[field.id];
    if (addr == null) {
      if (require) {
        throw RangeError('Field is not present in this state');
      }
      return null;
    }
    facet_module.ensureAddr(this, addr);
    return facet_module.getAddr(this, addr) as T;
  }

  /// Create a [Transaction] that updates this state.
  ///
  /// Any number of [TransactionSpec]s can be passed. Unless `sequential`
  /// is set, the changes (if any) of each spec are assumed to start in
  /// the _current_ document (not the document produced by previous specs),
  /// and its selection and effects are assumed to refer to the document
  /// created by its _own_ changes. The resulting transaction contains
  /// the combined effect of all the different specs.
  Transaction update([List<TransactionSpec> specs = const []]) {
    return _resolveTransaction(this, specs, true);
  }

  /// Internal: apply a transaction to create a new state.
  @internal
  void applyTransaction(Transaction tr) {
    facet_module.Configuration? conf = config;
    var base = conf.base;
    var compartments = conf.compartments;

    for (final effect in tr.effects) {
      final reconfigureEffect = facet_module.Compartment.reconfigureEffect;
      if (reconfigureEffect != null && effect.is_(reconfigureEffect)) {
        final value = effect.value as facet_module.CompartmentReconfigure;
        conf = null;
        compartments = Map.of(compartments);
        compartments[value.compartment] = value.extension;
      } else if (effect.is_(StateEffect.reconfigure)) {
        conf = null;
        base = effect.value as Extension;
      } else if (effect.is_(StateEffect.appendConfig)) {
        conf = null;
        base = ExtensionList([
          if (base is ExtensionList) ...base.extensions else base,
          effect.value as Extension,
        ]);
      }
    }

    List<dynamic> startValues;
    if (conf == null) {
      conf = facet_module.Configuration.resolve(base, compartments, this);
      final intermediateState = EditorState._(
        config: conf,
        doc: doc,
        selection: selection,
        values: List<dynamic>.filled(conf.dynamicSlots.length, null),
        computeSlot: (state, slot) => slot.reconfigure(state, this),
        tr: null,
      );
      startValues = intermediateState.values;
    } else {
      startValues = (tr.startState as EditorState).values.toList();
    }

    final newSelection =
        (tr.startState as EditorState).facet(
          EditorState.allowMultipleSelections_,
        )
        ? tr.newSelection
        : tr.newSelection.asSingle();

    EditorState._(
      config: conf,
      doc: tr.newDoc,
      selection: newSelection,
      values: startValues,
      computeSlot: (state, slot) =>
          slot.update(state, tr as facet_module.Transaction),
      tr: tr,
    );
  }

  /// Create a [TransactionSpec] that replaces every selection range with
  /// the given content.
  TransactionSpec replaceSelection(Object text) {
    final t = text is String ? toText(text) : text as Text;
    final result = changeByRange(
      (range) => ChangeByRangeResult(
        changes: ChangeSpec(from: range.from, to: range.to, insert: t),
        range: EditorSelection.cursor(range.from + t.length),
      ),
    );
    return TransactionSpec(
      changes: result.changes,
      selection: result.selection,
      effects: result.effects,
      scrollIntoView: true,
    );
  }

  /// Create a set of changes and a new selection by running the given
  /// function for each range in the active selection.
  ///
  /// The function can return an optional set of changes (in the coordinate
  /// space of the start document), plus an updated range (in the coordinate
  /// space of the document produced by the call's own changes). This method
  /// will merge all the changes and ranges into a single changeset and
  /// selection, and return it as a [TransactionSpec].
  ChangeByRangeResult changeByRange(
    ChangeByRangeResult Function(SelectionRange range) f,
  ) {
    final sel = selection;
    final result1 = f(sel.ranges[0]);
    var changes = this.changes(result1.changes);
    final ranges = [result1.range];
    var effects = _asArray<StateEffect<dynamic>>(result1.effects);

    for (var i = 1; i < sel.ranges.length; i++) {
      final result = f(sel.ranges[i]);
      final newChanges = this.changes(result.changes);
      final newMapped = newChanges.map(changes);

      for (var j = 0; j < i; j++) {
        ranges[j] = ranges[j].map(newMapped);
      }

      final mapBy = changes.mapDesc(newChanges, true);
      ranges.add(result.range.map(mapBy));
      changes = changes.compose(newMapped);
      effects = [
        ...StateEffect.mapEffects(effects, newMapped),
        ...StateEffect.mapEffects(
          _asArray<StateEffect<dynamic>>(result.effects),
          mapBy,
        ),
      ];
    }

    return ChangeByRangeResult(
      changes: changes,
      selection: EditorSelection.create(ranges, sel.mainIndex),
      effects: effects,
      range: ranges[sel.mainIndex],
    );
  }

  /// Create a [ChangeSet] from the given change description, taking the
  /// state's document length and line separator into account.
  ChangeSet changes([dynamic spec]) {
    if (spec is ChangeSet) return spec;
    return ChangeSet.of(
      spec is List ? spec : (spec != null ? [spec] : []),
      doc.length,
      facet(lineSeparator),
    );
  }

  /// Using the state's line separator, create a [Text] instance from the
  /// given string.
  Text toText(String string) {
    final sep = facet(lineSeparator);
    return Text.of(string.split(sep != null ? RegExp(sep) : defaultSplit));
  }

  /// Return the given range of the document as a string.
  String sliceDoc([int from = 0, int? to]) {
    return doc.sliceString(from, to ?? doc.length, lineBreak);
  }

  /// Get the value of a state facet.
  @override
  T facet<T>(FacetReader<T> facet) {
    final addr = config.address[facet.id];
    if (addr == null) return facet.defaultValue;
    facet_module.ensureAddr(this, addr);
    return facet_module.getAddr(this, addr) as T;
  }

  /// Convert this state to a JSON-serializable object.
  ///
  /// When custom fields should be serialized, you can pass them in as a
  /// map mapping property names (which should not use `doc` or `selection`)
  /// to fields.
  Map<String, dynamic> toJson([Map<String, StateField<dynamic>>? fields]) {
    final result = <String, dynamic>{
      'doc': sliceDoc(),
      'selection': selection.toJson(),
    };
    if (fields != null) {
      for (final entry in fields.entries) {
        final value = entry.value;
        if (config.address[value.id] != null) {
          final toJsonFn = value.spec.toJson;
          if (toJsonFn != null) {
            result[entry.key] = toJsonFn(field(value), this);
          }
        }
      }
    }
    return result;
  }

  /// Deserialize a state from its JSON representation.
  ///
  /// When custom fields should be deserialized, pass the same object you
  /// passed to [toJson] when serializing as third argument.
  static EditorState fromJson(
    Map<String, dynamic> json, [
    EditorStateConfig config = const EditorStateConfig(),
    Map<String, StateField<dynamic>>? fields,
  ]) {
    if (json['doc'] is! String) {
      throw RangeError('Invalid JSON representation for EditorState');
    }

    final fieldInit = <Extension>[];
    if (fields != null) {
      for (final entry in fields.entries) {
        if (json.containsKey(entry.key)) {
          final field = entry.value;
          final value = json[entry.key];
          final fromJsonFn = field.spec.fromJson;
          if (fromJsonFn != null) {
            // Use a helper to properly type the initialization
            fieldInit.add(_initFieldFromJson(field, fromJsonFn, value));
          }
        }
      }
    }

    return EditorState.create(
      EditorStateConfig(
        doc: json['doc'] as String,
        selection: EditorSelection.fromJson(
          json['selection'] as Map<String, dynamic>,
        ),
        extensions: config.extensions != null
            ? ExtensionList([...fieldInit, config.extensions!])
            : (fieldInit.isNotEmpty ? ExtensionList(fieldInit) : null),
      ),
    );
  }

  /// Create a new state.
  ///
  /// You'll usually only need this when initializing an editor—updated
  /// states are created by applying transactions.
  static EditorState create([
    EditorStateConfig config = const EditorStateConfig(),
  ]) {
    final configuration = facet_module.Configuration.resolve(
      config.extensions ?? const ExtensionList([]),
      const {},
    );

    final docValue = config.doc;
    Text doc;
    if (docValue is Text) {
      doc = docValue;
    } else {
      final sep = configuration.staticFacet(EditorState.lineSeparator_);
      doc = Text.of(
        (docValue as String? ?? '').split(
          sep != null ? RegExp(sep) : defaultSplit,
        ),
      );
    }

    EditorSelection selection;
    final selValue = config.selection;
    if (selValue == null) {
      selection = EditorSelection.single(0);
    } else if (selValue is EditorSelection) {
      selection = selValue;
    } else if (selValue is Map<String, dynamic>) {
      selection = EditorSelection.single(
        selValue['anchor'] as int,
        selValue['head'] as int?,
      );
    } else {
      selection = EditorSelection.single(0);
    }

    checkSelection(selection, doc.length);
    if (!configuration.staticFacet(EditorState.allowMultipleSelections_)) {
      selection = selection.asSingle();
    }

    return EditorState._(
      config: configuration,
      doc: doc,
      selection: selection,
      values: List<dynamic>.filled(configuration.dynamicSlots.length, null),
      computeSlot: (state, slot) => slot.create(state),
      tr: null,
    );
  }

  // ============================================================================
  // Static facets
  // ============================================================================

  /// A facet that, when enabled, causes the editor to allow multiple
  /// ranges to be selected.
  static Facet<bool, bool> get allowMultipleSelections_ =>
      allowMultipleSelections;

  /// Configures the tab size to use in this state.
  ///
  /// The first (highest-precedence) value of the facet is used. If no
  /// value is given, this defaults to 4.
  static final Facet<int, int> tabSize_ = Facet.define(
    FacetConfig(combine: (values) => values.isNotEmpty ? values[0] : 4),
  );

  /// The line separator to use.
  ///
  /// By default, any of `"\n"`, `"\r\n"` and `"\r"` is treated as a
  /// separator when splitting lines, and lines are joined with `"\n"`.
  ///
  /// When you configure a value here, only that precise separator will
  /// be used, allowing you to round-trip documents through the editor
  /// without normalizing line separators.
  static Facet<String, String?> get lineSeparator_ => lineSeparator;

  /// This facet controls the value of the [isReadOnly] getter.
  ///
  /// Commands and extensions that implement editing functionality
  /// consult this to determine whether they should apply.
  static Facet<bool, bool> get readOnly_ => readOnly;

  /// Registers translation phrases.
  ///
  /// The [phrase] method will look through all objects registered with
  /// this facet to find translations for its argument.
  static final Facet<Map<String, String>, List<Map<String, String>>> phrases =
      Facet.define(
        FacetConfig(
          compare: (a, b) {
            final keysA = a.map((m) => m.keys).expand((k) => k).toList();
            final keysB = b.map((m) => m.keys).expand((k) => k).toList();
            if (keysA.length != keysB.length) return false;
            for (var i = 0; i < keysA.length; i++) {
              if (keysA[i] != keysB[i]) return false;
            }
            return true;
          },
        ),
      );

  /// Facet used to register change filters.
  static Facet<
    dynamic Function(Transaction tr),
    List<dynamic Function(Transaction tr)>
  >
  get changeFilter_ => changeFilter;

  /// Facet used to register transaction filters.
  static Facet<
    dynamic Function(Transaction tr),
    List<dynamic Function(Transaction tr)>
  >
  get transactionFilter_ => transactionFilter;

  /// Facet used to register transaction extenders.
  static Facet<
    TransactionSpec? Function(Transaction tr),
    List<TransactionSpec? Function(Transaction tr)>
  >
  get transactionExtender_ => transactionExtender;

  /// A facet used to register language data providers.
  static Facet<
    List<Map<String, dynamic>> Function(EditorState state, int pos, int side),
    List<
      List<Map<String, dynamic>> Function(EditorState state, int pos, int side)
    >
  >
  get languageData_ => languageData;

  // ============================================================================
  // Property getters
  // ============================================================================

  /// The size (in columns) of a tab in the document, determined by the
  /// [tabSize_] facet.
  int get tabSize => facet(EditorState.tabSize_);

  /// Get the proper line-break string for this state.
  String get lineBreak => facet(EditorState.lineSeparator_) ?? '\n';

  /// Returns true when the editor is configured to be read-only.
  bool get isReadOnly => facet(EditorState.readOnly_);

  // ============================================================================
  // Additional methods
  // ============================================================================

  /// Look up a translation for the given phrase (via the [phrases] facet),
  /// or return the original string if no translation is found.
  ///
  /// If additional arguments are passed, they will be inserted in place of
  /// markers like `$1` (for the first value) and `$2`, etc. A single `$`
  /// is equivalent to `$1`, and `$$` will produce a literal dollar sign.
  String phrase(String phrase, [List<dynamic>? insert]) {
    for (final map in facet(EditorState.phrases)) {
      if (map.containsKey(phrase)) {
        phrase = map[phrase]!;
        break;
      }
    }
    if (insert != null && insert.isNotEmpty) {
      phrase = phrase.replaceAllMapped(RegExp(r'\$(\$|\d*)'), (m) {
        final i = m.group(1)!;
        if (i == r'$') return r'$';
        final n = int.tryParse(i) ?? 1;
        if (n == 0 || n > insert.length) return m.group(0)!;
        return insert[n - 1].toString();
      });
    }
    return phrase;
  }

  /// Find the values for a given language data field, provided by the
  /// [languageData] facet.
  List<T> languageDataAt<T>(String name, int pos, [int side = -1]) {
    final values = <T>[];
    for (final provider in facet(languageData)) {
      for (final result in provider(this, pos, side)) {
        if (result.containsKey(name)) {
          values.add(result[name] as T);
        }
      }
    }
    return values;
  }

  /// Get a character categorizer for the given position.
  ///
  /// This reads the `"wordChars"` language data to determine which
  /// additional characters should be considered word characters
  /// (e.g., `-` in CSS for `background-color`).
  CharCategorizer charCategorizer(int at) {
    return makeCategorizer(languageDataAt<String>('wordChars', at).join(''));
  }

  /// Return the word at the given position, meaning the range containing
  /// all word characters around it.
  ///
  /// If no word characters are adjacent to the position, this returns null.
  SelectionRange? wordAt(int pos) {
    final line = doc.lineAt(pos);
    final text = line.text;
    final wordChars = languageDataAt<String>('wordChars', pos).join('');

    var start = pos - line.from;
    var end = pos - line.from;

    bool isWordChar(String char) {
      if (char.isEmpty) return false;
      final code = char.codeUnitAt(0);
      // Basic alphanumeric check
      if ((code >= 48 && code <= 57) || // 0-9
          (code >= 65 && code <= 90) || // A-Z
          (code >= 97 && code <= 122) || // a-z
          code == 95) {
        // underscore
        return true;
      }
      return wordChars.contains(char);
    }

    // Find word boundaries
    while (start > 0 && isWordChar(text[start - 1])) {
      start--;
    }
    while (end < text.length && isWordChar(text[end])) {
      end++;
    }

    if (start == end) return null;
    return EditorSelection.range(start + line.from, end + line.from);
  }
}

// ============================================================================
// Helper types
// ============================================================================

/// Result of [EditorState.changeByRange].
class ChangeByRangeResult {
  /// The changes to apply.
  final dynamic changes;

  /// The updated selection range.
  final SelectionRange range;

  /// The selection (when multiple ranges are combined).
  final EditorSelection? selection;

  /// Any effects to apply.
  final List<StateEffect<dynamic>>? effects;

  const ChangeByRangeResult({
    this.changes,
    required this.range,
    this.selection,
    this.effects,
  });
}

// ============================================================================
// Transaction resolution (internal)
// ============================================================================

/// Helper to initialize a field from JSON.
/// This avoids type issues when the field's type parameter is dynamic.
Extension _initFieldFromJson(StateField<dynamic> field, Function fromJsonFn, dynamic value) {
  return field.init((state) => fromJsonFn(value, state));
}

/// Convert a value that may be a single item or a list into a list.
List<T> _asArray<T>(dynamic value) {
  if (value == null) return [];
  if (value is List<T>) return value;
  if (value is List) return value.cast<T>();
  return [value as T];
}

/// Resolve a mixed list of Transactions and TransactionSpecs.
/// 
/// When the first item is a Transaction, we use it as the base and only 
/// process subsequent specs (merging their changes). This matches the JS
/// behavior where `[tr, {changes, sequential: true}]` keeps the original
/// transaction and adds new changes on top.
Transaction _resolveTransactionFromMixed(
  EditorState state,
  List<dynamic> items,
  Transaction originalTr,
) {
  if (items.isEmpty) return originalTr;
  
  final lineSep = state.facet(lineSeparator);
  
  // If the first item is a Transaction, use it as the base resolved spec
  _ResolvedSpec s;
  int startIndex;
  
  if (items[0] is Transaction) {
    final baseTr = items[0] as Transaction;
    s = _ResolvedSpec(
      changes: baseTr.changes,
      selection: baseTr.selection,
      effects: baseTr.effects,
      annotations: baseTr.annotations,
      scrollIntoView: baseTr.scrollIntoView,
    );
    startIndex = 1;
  } else if (items[0] is TransactionSpec) {
    s = _resolveTransactionInner(state, items[0] as TransactionSpec, state.doc.length, lineSep);
    startIndex = 1;
  } else {
    return originalTr;
  }
  
  // Process remaining items
  for (var i = startIndex; i < items.length; i++) {
    final item = items[i];
    if (item is TransactionSpec) {
      final seq = item.sequential;
      s = _mergeTransaction(
        s,
        _resolveTransactionInner(
          state,
          item,
          seq ? s.changes.newLength : state.doc.length,
          lineSep,
        ),
        seq,
      );
    }
  }
  
  return Transaction.create(
    startState: state,
    changes: s.changes,
    selection: s.selection,
    effects: s.effects,
    annotations: s.annotations,
    scrollIntoView: s.scrollIntoView,
  );
}

/// Resolve multiple transaction specs into a single transaction.
Transaction _resolveTransaction(
  EditorState state,
  List<TransactionSpec> specs,
  bool filter,
) {
  final lineSep = state.facet(lineSeparator);
  var s = _resolveTransactionInner(
    state,
    specs.isNotEmpty ? specs[0] : const TransactionSpec(),
    state.doc.length,
    lineSep,
  );

  if (specs.isNotEmpty && !specs[0].filter) filter = false;

  for (var i = 1; i < specs.length; i++) {
    if (!specs[i].filter) filter = false;
    final seq = specs[i].sequential;
    s = _mergeTransaction(
      s,
      _resolveTransactionInner(
        state,
        specs[i],
        seq ? s.changes.newLength : state.doc.length,
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

  return _extendTransaction(filter ? _filterTransaction(tr) : tr);
}

/// Resolve a transaction spec to its internal representation.
_ResolvedSpec _resolveTransactionInner(
  EditorState state,
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

  return _ResolvedSpec(
    changes: changes,
    selection: sel,
    effects: spec.effects ?? const [],
    annotations: annotations,
    scrollIntoView: spec.scrollIntoView,
  );
}

/// Internal representation of a resolved transaction spec.
class _ResolvedSpec {
  final ChangeSet changes;
  final EditorSelection? selection;
  final List<StateEffect<dynamic>> effects;
  final List<Annotation<dynamic>> annotations;
  final bool scrollIntoView;

  const _ResolvedSpec({
    required this.changes,
    this.selection,
    required this.effects,
    required this.annotations,
    required this.scrollIntoView,
  });
}

/// Merge two resolved transaction specs.
_ResolvedSpec _mergeTransaction(
  _ResolvedSpec a,
  _ResolvedSpec b,
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

  return _ResolvedSpec(
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

/// Join two range arrays (pairs of from/to positions).
/// Returns merged and sorted ranges.
List<int> _joinRanges(List<int> a, List<int> b) {
  final result = <int>[];
  var iA = 0, iB = 0;
  while (true) {
    int from, to;
    if (iA < a.length && (iB == b.length || b[iB] >= a[iA])) {
      from = a[iA++];
      to = a[iA++];
    } else if (iB < b.length) {
      from = b[iB++];
      to = b[iB++];
    } else {
      return result;
    }
    if (result.isEmpty || result[result.length - 1] < from) {
      result.addAll([from, to]);
    } else if (result[result.length - 1] < to) {
      result[result.length - 1] = to;
    }
  }
}

/// Apply change filters and transaction filters.
Transaction _filterTransaction(Transaction tr) {
  final state = tr.startState as EditorState;

  // Apply change filters - collect the result
  dynamic result = true;
  final changeFilters = state.facet(changeFilter);
  for (final filter in changeFilters) {
    final value = filter(tr);
    if (value == false) {
      result = false;
      break;
    }
    if (value is List<int>) {
      result = result == true ? value : _joinRanges(result as List<int>, value);
    }
    // value == true means no filtering, continue
  }

  // If changes were filtered, create a new transaction
  if (result != true) {
    ChangeSet changes;
    ChangeDesc back;
    if (result == false) {
      back = tr.changes.invertedDesc;
      changes = ChangeSet.emptySet(state.doc.length);
    } else {
      final filtered = tr.changes.filter(result as List<int>);
      changes = filtered.changes;
      back = filtered.filtered.mapDesc(filtered.changes).invertedDesc;
    }
    tr = Transaction.create(
      startState: state,
      changes: changes,
      selection: tr.selection?.map(back),
      effects: StateEffect.mapEffects(tr.effects, back),
      annotations: tr.annotations,
      scrollIntoView: tr.scrollIntoView,
    );
  }

  // Apply transaction filters
  final txFilters = state.facet(transactionFilter);
  for (var i = txFilters.length - 1; i >= 0; i--) {
    final filtered = txFilters[i](tr);
    if (filtered is Transaction) {
      tr = filtered;
    } else if (filtered is List && filtered.length == 1 && filtered[0] is Transaction) {
      tr = filtered[0] as Transaction;
    } else if (filtered != null) {
      // Convert to a list and resolve
      final items = _asArray<dynamic>(filtered);
      tr = _resolveTransactionFromMixed(state, items, tr);
    }
  }

  return tr;
}

/// Apply transaction extenders.
Transaction _extendTransaction(Transaction tr) {
  final state = tr.startState as EditorState;
  final extenders = state.facet(transactionExtender);
  _ResolvedSpec spec = _ResolvedSpec(
    changes: tr.changes,
    selection: tr.selection,
    effects: tr.effects,
    annotations: tr.annotations,
    scrollIntoView: tr.scrollIntoView,
  );
  
  // Iterate in reverse order like TypeScript implementation
  final lineSep = state.facet(lineSeparator);
  for (var i = extenders.length - 1; i >= 0; i--) {
    final extension = extenders[i](tr);
    if (extension != null && _hasContent(extension)) {
      spec = _mergeTransaction(
        spec,
        _resolveTransactionInner(state, extension, tr.changes.newLength, lineSep),
        true, // sequential
      );
    }
  }
  
  // Only create a new transaction if something changed
  if (spec.effects != tr.effects || spec.annotations != tr.annotations) {
    return Transaction.create(
      startState: state,
      changes: tr.changes,
      selection: tr.selection,
      effects: spec.effects,
      annotations: spec.annotations,
      scrollIntoView: spec.scrollIntoView,
    );
  }
  
  return tr;
}

/// Check if a TransactionSpec has any content (annotations, effects, etc.)
bool _hasContent(TransactionSpec spec) {
  return (spec.annotations != null && spec.annotations!.isNotEmpty) ||
      (spec.effects != null && spec.effects!.isNotEmpty) ||
      spec.scrollIntoView;
}

// ============================================================================
// Initialize Compartment._reconfigure
// ============================================================================

/// Initialize the Compartment reconfigure effect.
///
/// This must be called to set up the circular dependency between
/// Compartment and StateEffect.
void _initCompartmentReconfigure() {
  facet_module.Compartment.initReconfigure(
    StateEffect.define<facet_module.CompartmentReconfigure>(),
  );
}

// Run initialization
final bool _stateInitialized = () {
  _initCompartmentReconfigure();
  return true;
}();

/// Ensure state module is initialized.
///
/// This is a no-op but ensures the initialization code runs.
void ensureStateInitialized() {
  // ignore: unnecessary_statements
  _stateInitialized;
}
