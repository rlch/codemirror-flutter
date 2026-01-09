/// Code folding for CodeMirror.
///
/// This module provides infrastructure for folding (collapsing) regions
/// of code in the editor.
library;

import 'package:flutter/widgets.dart' show Widget, Text, Container, EdgeInsets, BoxDecoration, Border, BorderRadius, Radius, TextStyle, Color, BuildContext, FontWeight, TextDecoration;
import 'package:lezer/lezer.dart' hide Range;

import '../commands/commands.dart' show StateCommandTarget;
import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as tx show Transaction;
import '../state/range_set.dart';
import '../text/text.dart' show Line;
import '../view/decoration.dart';
import '../view/gutter.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import '../view/editor_view.dart';
import '../view/keymap.dart';
import 'language.dart';

typedef Transaction = tx.Transaction;

// ============================================================================
// Fold Service Facet
// ============================================================================

/// A facet that registers a code folding service.
///
/// When called with the extent of a line, such a function should return
/// a foldable range that starts on that line (but continues beyond it),
/// if one can be found.
final Facet<
    ({int from, int to})? Function(EditorState state, int lineStart, int lineEnd),
    List<({int from, int to})? Function(EditorState state, int lineStart, int lineEnd)>> foldService = Facet.define(
  FacetConfig(
    combine: (values) => values.toList(),
  ),
);

// ============================================================================
// Fold Node Prop
// ============================================================================

/// This node prop is used to associate folding information with syntax
/// node types.
///
/// Given a syntax node, it should check whether that tree is foldable
/// and return the range that can be collapsed when it is.
final NodeProp<({int from, int to})? Function(SyntaxNode node, EditorState state)> foldNodeProp =
    NodeProp<({int from, int to})? Function(SyntaxNode node, EditorState state)>(
  deserialize: (_) => throw UnsupportedError('Cannot deserialize foldNodeProp'),
);

// ============================================================================
// foldInside Helper
// ============================================================================

/// Fold function that folds everything but the first and the last child
/// of a syntax node.
///
/// Useful for nodes that start and end with delimiters.
({int from, int to})? foldInside(SyntaxNode node) {
  final first = node.firstChild;
  final last = node.lastChild;
  if (first != null && last != null && first.to < last.from) {
    return (from: first.to, to: last.type.isError ? node.to : last.from);
  }
  return null;
}

// ============================================================================
// Syntax Folding
// ============================================================================

({int from, int to})? _syntaxFolding(EditorState state, int start, int end) {
  final tree = syntaxTree(state);
  if (tree.length < end) return null;

  ({int from, int to})? found;

  // Walk up from the innermost node at end position
  for (SyntaxNode? cur = tree.resolveInner(end, 1); cur != null; cur = cur.parent) {
    if (cur.to <= end || cur.from > end) continue;
    if (found != null && cur.from < start) break;

    final prop = cur.type.prop(foldNodeProp);
    if (prop != null && (cur.to < tree.length - 50 || tree.length == state.doc.length || !_isUnfinished(cur))) {
      final value = prop(cur, state);
      if (value != null && value.from <= end && value.from >= start && value.to > end) {
        found = value;
      }
    }
  }

  return found;
}

bool _isUnfinished(SyntaxNode node) {
  final ch = node.lastChild;
  return ch != null && ch.to == node.to && ch.type.isError;
}

// ============================================================================
// foldable Function
// ============================================================================

/// Check whether the given line is foldable.
///
/// First asks any fold services registered through [foldService], and if
/// none of them return a result, tries to query the [foldNodeProp] of
/// syntax nodes that cover the end of the line.
({int from, int to})? foldable(EditorState state, int lineStart, int lineEnd) {
  for (final service in state.facet(foldService)) {
    final result = service(state, lineStart, lineEnd);
    if (result != null) return result;
  }
  return _syntaxFolding(state, lineStart, lineEnd);
}

// ============================================================================
// State Effects
// ============================================================================

/// A document range for folding operations.
typedef FoldRange = ({int from, int to});

FoldRange? _mapRange(FoldRange range, ChangeDesc mapping) {
  final from = mapping.mapPos(range.from, 1);
  final to = mapping.mapPos(range.to, -1);
  if (from == null || to == null || from >= to) return null;
  return (from: from, to: to);
}

/// State effect that can be attached to a transaction to fold the
/// given range.
///
/// You probably only need this in exceptional circumstances—usually
/// you'll just want to let [foldCode] and the fold gutter create
/// the transactions.
final StateEffectType<FoldRange> foldEffect = StateEffect.define<FoldRange>(
  map: _mapRange,
);

/// State effect that unfolds the given range (if it was folded).
final StateEffectType<FoldRange> unfoldEffect = StateEffect.define<FoldRange>(
  map: _mapRange,
);

// ============================================================================
// Fold Configuration
// ============================================================================

/// Configuration for code folding.
class FoldConfig {
  /// Text to use as placeholder for folded text.
  /// Defaults to `"…"`.
  final String placeholderText;

  const FoldConfig({
    this.placeholderText = '…',
  });
}

const _defaultFoldConfig = FoldConfig();

final Facet<FoldConfig, FoldConfig> _foldConfig = Facet.define(
  FacetConfig(
    combine: (values) => values.isNotEmpty ? values.last : _defaultFoldConfig,
  ),
);

// ============================================================================
// Fold Widget
// ============================================================================

/// Widget that displays the fold placeholder.
class _FoldPlaceholderWidget extends WidgetType {
  final String text;

  const _FoldPlaceholderWidget(this.text);

  @override
  Widget toWidget(dynamic view) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        border: Border.all(color: const Color(0xFFDDDDDD)),
        borderRadius: const BorderRadius.all(Radius.circular(3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  bool eq(WidgetType other) {
    return other is _FoldPlaceholderWidget && other.text == text;
  }
}

// ============================================================================
// Fold State Field
// ============================================================================

/// The state field that stores the folded ranges (as a decoration set).
///
/// Can be passed to [EditorState.toJSON] and [EditorState.fromJSON] to
/// serialize the fold state.
late final StateField<RangeSet<Decoration>> foldState;

void _initFoldState() {
  foldState = StateField.define(
    StateFieldConfig(
      create: (_) => RangeSet.empty(),
      update: (folded, tr) {
        final transaction = tr as tx.Transaction;

        // Handle delete events by clearing touched folds
        if (transaction.isUserEvent('delete')) {
          transaction.changes.iterChangedRanges((fromA, toA, fromB, toB) {
            folded = _clearTouchedFolds(folded, fromA, toA);
          });
        }

        folded = folded.map(transaction.changes);

        for (final e in transaction.effects) {
          if (e.is_(foldEffect)) {
            final range = e.value as FoldRange;
            if (!_foldExists(folded, range.from, range.to)) {
              final config = (transaction.state as EditorState).facet(_foldConfig);
              final widget = Decoration.replace(
                ReplaceDecorationSpec(widget: _FoldPlaceholderWidget(config.placeholderText)),
              );
              folded = folded.update(RangeSetUpdate(add: [widget.range(range.from, range.to)]));
            }
          } else if (e.is_(unfoldEffect)) {
            final range = e.value as FoldRange;
            folded = folded.update(RangeSetUpdate(
              filter: (from, to, _) => range.from != from || range.to != to,
              filterFrom: range.from,
              filterTo: range.to,
            ));
          }
        }

        // Clear folded ranges that cover the selection head
        if (transaction.selection != null) {
          folded = _clearTouchedFolds(folded, transaction.selection!.main.head);
        }

        return folded;
      },
    ),
  );
}

// Run initialization
final bool _foldInitialized = () {
  _initFoldState();
  return true;
}();

/// Ensure fold module is initialized.
void ensureFoldInitialized() {
  // ignore: unnecessary_statements
  _foldInitialized;
}

RangeSet<Decoration> _clearTouchedFolds(RangeSet<Decoration> folded, int from, [int? to]) {
  to ??= from;
  var touched = false;
  folded.between(from, to, (a, b, _) {
    if (a < to! && b > from) touched = true;
    return true;
  });
  if (!touched) return folded;
  return folded.update(RangeSetUpdate(
    filterFrom: from,
    filterTo: to,
    filter: (a, b, _) => a >= to! || b <= from,
  ));
}

bool _foldExists(RangeSet<Decoration> folded, int from, int to) {
  var found = false;
  folded.between(from, from, (a, b, _) {
    if (a == from && b == to) found = true;
    return !found;
  });
  return found;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get a range set containing the folded ranges in the given state.
RangeSet<Decoration> foldedRanges(EditorState state) {
  ensureFoldInitialized();
  return state.field(foldState, false) ?? RangeSet.empty();
}

({int from, int to})? _findFold(EditorState state, int from, int to) {
  ({int from, int to})? found;
  state.field(foldState, false)?.between(from, to, (fFrom, fTo, _) {
    if (found == null || found!.from > fFrom) found = (from: fFrom, to: fTo);
    return true;
  });
  return found;
}

List<StateEffect<dynamic>> _maybeEnable(EditorState state, List<StateEffect<dynamic>> other) {
  ensureFoldInitialized();
  if (state.field(foldState, false) != null) return other;
  return [...other, StateEffect.appendConfig.of(codeFolding())];
}

// ============================================================================
// Commands
// ============================================================================

/// Fold the lines that are selected, if possible.
bool foldCode(StateCommandTarget target) {
  final view = target;
  for (final line in _selectedLines(view)) {
    final range = foldable(view.state, line.from, line.to);
    if (range != null) {
      view.dispatch(view.state.update([
        TransactionSpec(effects: _maybeEnable(view.state, [foldEffect.of(range)])),
      ]));
      return true;
    }
  }
  return false;
}

/// Unfold folded ranges on selected lines.
bool unfoldCode(StateCommandTarget target) {
  ensureFoldInitialized();
  final view = target;
  if (view.state.field(foldState, false) == null) return false;

  final effects = <StateEffect<dynamic>>[];
  for (final line in _selectedLines(view)) {
    final folded = _findFold(view.state, line.from, line.to);
    if (folded != null) {
      effects.add(unfoldEffect.of(folded));
    }
  }

  if (effects.isNotEmpty) {
    view.dispatch(view.state.update([TransactionSpec(effects: effects)]));
  }
  return effects.isNotEmpty;
}

/// Fold all top-level foldable ranges.
///
/// Note that, in most cases, folding information will depend on the
/// syntax tree, and folding everything may not work reliably when the
/// document hasn't been fully parsed (either because the editor state
/// was only just initialized, or because the document is so big that
/// the parser decided not to parse it entirely).
bool foldAll(StateCommandTarget target) {
  final view = target;
  final state = view.state;
  final effects = <StateEffect<dynamic>>[];

  var pos = 0;
  while (pos < state.doc.length) {
    final line = state.doc.lineAt(pos);
    final range = foldable(state, line.from, line.to);
    if (range != null) {
      effects.add(foldEffect.of(range));
      pos = state.doc.lineAt(range.to).to + 1;
    } else {
      pos = line.to + 1;
    }
  }

  if (effects.isNotEmpty) {
    view.dispatch(view.state.update([
      TransactionSpec(effects: _maybeEnable(state, effects)),
    ]));
  }
  return effects.isNotEmpty;
}

/// Unfold all folded code.
bool unfoldAll(StateCommandTarget target) {
  ensureFoldInitialized();
  final view = target;
  final field = view.state.field(foldState, false);
  if (field == null || field.isEmpty) return false;

  final effects = <StateEffect<dynamic>>[];
  field.between(0, view.state.doc.length, (from, to, _) {
    effects.add(unfoldEffect.of((from: from, to: to)));
    return true;
  });

  view.dispatch(view.state.update([TransactionSpec(effects: effects)]));
  return true;
}

/// Toggle folding at cursors.
///
/// Unfolds if there is an existing fold starting in that line, tries
/// to find a foldable range around it otherwise.
bool toggleFold(StateCommandTarget target) {
  final view = target;
  final effects = <StateEffect<dynamic>>[];

  for (final line in _selectedLines(view)) {
    final folded = _findFold(view.state, line.from, line.to);
    if (folded != null) {
      effects.add(unfoldEffect.of(folded));
    } else {
      final foldRange = _foldableContainer(view, line);
      if (foldRange != null) {
        effects.add(foldEffect.of(foldRange));
      }
    }
  }

  if (effects.isNotEmpty) {
    view.dispatch(view.state.update([
      TransactionSpec(effects: _maybeEnable(view.state, effects)),
    ]));
  }
  return effects.isNotEmpty;
}

/// Find the foldable region containing the given line, if one exists.
({int from, int to})? _foldableContainer(StateCommandTarget view, _LineInfo line) {
  for (var currentLine = line;;) {
    final foldableRegion = foldable(view.state, currentLine.from, currentLine.to);
    if (foldableRegion != null && foldableRegion.to > line.from) return foldableRegion;
    if (currentLine.from == 0) return null;
    currentLine = _lineInfoAt(view.state.doc.lineAt(currentLine.from - 1));
  }
}

// ============================================================================
// Line Selection Helper
// ============================================================================

typedef _LineInfo = ({int from, int to});

_LineInfo _lineInfoAt(Line line) => (from: line.from, to: line.to);

List<_LineInfo> _selectedLines(StateCommandTarget view) {
  final lines = <_LineInfo>[];
  for (final range in view.state.selection.ranges) {
    final head = range.head;
    if (lines.any((l) => l.from <= head && l.to >= head)) continue;
    final line = view.state.doc.lineAt(head);
    lines.add(_lineInfoAt(line));
  }
  return lines;
}

// ============================================================================
// Fold Keymap
// ============================================================================

/// Default fold-related key bindings.
///
/// - Ctrl-Shift-[ (Cmd-Alt-[ on macOS): [foldCode]
/// - Ctrl-Shift-] (Cmd-Alt-] on macOS): [unfoldCode]
/// - Ctrl-Alt-[: [foldAll]
/// - Ctrl-Alt-]: [unfoldAll]
final List<KeyBinding> foldKeymap = [
  KeyBinding(key: 'Ctrl-Shift-[', mac: 'Cmd-Alt-[', run: _foldCodeCmd),
  KeyBinding(key: 'Ctrl-Shift-]', mac: 'Cmd-Alt-]', run: _unfoldCodeCmd),
  KeyBinding(key: 'Ctrl-Alt-[', run: _foldAllCmd),
  KeyBinding(key: 'Ctrl-Alt-]', run: _unfoldAllCmd),
];

bool _foldCodeCmd(dynamic view) {
  final v = view as EditorViewState;
  return foldCode((state: v.state, dispatch: (tr) => v.dispatchTransaction(tr)));
}

bool _unfoldCodeCmd(dynamic view) {
  final v = view as EditorViewState;
  return unfoldCode((state: v.state, dispatch: (tr) => v.dispatchTransaction(tr)));
}

bool _foldAllCmd(dynamic view) {
  final v = view as EditorViewState;
  return foldAll((state: v.state, dispatch: (tr) => v.dispatchTransaction(tr)));
}

bool _unfoldAllCmd(dynamic view) {
  final v = view as EditorViewState;
  return unfoldAll((state: v.state, dispatch: (tr) => v.dispatchTransaction(tr)));
}

// ============================================================================
// codeFolding Extension
// ============================================================================

/// Create an extension that configures code folding.
///
/// ## Example
///
/// ```dart
/// EditorState.create(
///   extensions: [
///     codeFolding(),
///     keymap.of(foldKeymap),
///   ],
/// );
/// ```
Extension codeFolding([FoldConfig? config]) {
  ensureFoldInitialized();
  final result = <Extension>[
    foldState,
    _foldDecorations.extension, // Use .extension to include viewPlugin registration
  ];
  if (config != null) {
    result.add(_foldConfig.of(config));
  }
  return ExtensionList(result);
}

/// Plugin that provides fold decorations.
final ViewPlugin<_FoldPlugin> _foldDecorations = ViewPlugin.define(
  (view) => _FoldPlugin(view),
  ViewPluginSpec(
    decorations: (plugin) => plugin.decorations,
  ),
);

class _FoldPlugin extends PluginValue {
  RangeSet<Decoration> decorations;

  _FoldPlugin(EditorViewState view)
      : decorations = view.state.field(foldState, false) ?? RangeSet.empty();

  @override
  void update(ViewUpdate update) {
    decorations = update.state.field(foldState, false) ?? RangeSet.empty();
  }
}

// ============================================================================
// Fold Gutter
// ============================================================================

/// Configuration for the fold gutter.
class FoldGutterConfig {
  /// Text used to indicate that a given line can be folded.
  /// Defaults to `"⌄"`.
  final String openText;

  /// Text used to indicate that a given line is folded.
  /// Defaults to `"›"`.
  final String closedText;

  /// When given, if this returns true for a given view update,
  /// recompute the fold markers.
  final bool Function(ViewUpdate update)? foldingChanged;

  const FoldGutterConfig({
    this.openText = '⌄',
    this.closedText = '›',
    this.foldingChanged,
  });
}

/// Gutter marker for fold indicators.
class _FoldMarker extends GutterMarker {
  final FoldGutterConfig config;
  final bool open;

  _FoldMarker(this.config, this.open);

  @override
  bool markerEq(GutterMarker other) =>
      other is _FoldMarker && other.open == open;

  /// Fixed line height matching EditorViewState.fixedLineHeight
  static const double _lineHeight = 20.0;
  
  @override
  Widget? toWidget(BuildContext context) {
    return Text(
      open ? config.openText : config.closedText,
      style: const TextStyle(
        fontFamily: 'JetBrainsMono',
        package: 'codemirror',
        fontSize: 14,
        height: _lineHeight / 14,
        fontWeight: FontWeight.normal,
        decoration: TextDecoration.none,
        color: Color(0xFF808080),
      ),
    );
  }

  @override
  String get elementClass => 'cm-foldGutter-marker';
}

/// Create an extension that registers a fold gutter, which shows a
/// fold status indicator before foldable lines (which can be clicked
/// to fold or unfold the line).
Extension foldGutter([FoldGutterConfig config = const FoldGutterConfig()]) {
  ensureFoldInitialized();
  
  final canFold = _FoldMarker(config, true);
  final canUnfold = _FoldMarker(config, false);

  return ExtensionList([
    _foldGutterMarkers(config, canFold, canUnfold),
    gutter(GutterConfig(
      className: 'cm-foldGutter',
      markers: (state) => state.field(_foldGutterMarkersField, false) ?? RangeSet.empty<GutterMarker>(),
      eventHandlers: {
        'click': (context, line, event) {
          final state = _getFoldGutterState(context);
          if (state == null) return false;
          
          final folded = _findFold(state, line.from, line.to);
          if (folded != null) {
            final view = _getFoldGutterView(context);
            if (view != null) {
              view.dispatch([
                TransactionSpec(effects: [unfoldEffect.of(folded)]),
              ]);
            }
            return true;
          }
          
          final range = foldable(state, line.from, line.to);
          if (range != null) {
            final view = _getFoldGutterView(context);
            if (view != null) {
              view.dispatch([
                TransactionSpec(effects: _maybeEnable(state, [foldEffect.of(range)])),
              ]);
            }
            return true;
          }
          return false;
        },
      },
    )),
    codeFolding(),
  ]);
}

// State field for fold gutter markers
late final StateField<RangeSet<GutterMarker>> _foldGutterMarkersField;
bool _foldGutterInitialized = false;

Extension _foldGutterMarkers(FoldGutterConfig config, _FoldMarker canFold, _FoldMarker canUnfold) {
  if (!_foldGutterInitialized) {
    _foldGutterInitialized = true;
    _foldGutterMarkersField = StateField.define(StateFieldConfig(
      create: (state) => _buildFoldMarkers(state as EditorState, canFold, canUnfold),
      update: (markers, tr) {
        final transaction = tr as tx.Transaction;
        final newState = transaction.state as EditorState;
        final oldState = transaction.startState as EditorState;
        
        // Rebuild if doc changed, fold state changed, or syntax tree changed
        if (transaction.docChanged ||
            oldState.field(foldState, false) != newState.field(foldState, false)) {
          return _buildFoldMarkers(newState, canFold, canUnfold);
        }
        
        return markers.map(transaction.changes);
      },
    ));
  }
  return _foldGutterMarkersField;
}

RangeSet<GutterMarker> _buildFoldMarkers(EditorState state, _FoldMarker canFold, _FoldMarker canUnfold) {
  final builder = RangeSetBuilder<GutterMarker>();
  final doc = state.doc;
  
  for (var i = 1; i <= doc.lines; i++) {
    final line = doc.line(i);
    final folded = _findFold(state, line.from, line.to);
    final marker = folded != null
        ? canUnfold
        : foldable(state, line.from, line.to) != null
            ? canFold
            : null;
    if (marker != null) {
      builder.add(line.from, line.from, marker);
    }
  }
  
  return builder.finish();
}

// Helper to get EditorState from gutter context
EditorState? _getFoldGutterState(BuildContext context) {
  // Walk up to find EditorView and get its state
  final editorState = context.findAncestorStateOfType<EditorViewState>();
  return editorState?.state;
}

// Helper to get EditorViewState from gutter context  
EditorViewState? _getFoldGutterView(BuildContext context) {
  return context.findAncestorStateOfType<EditorViewState>();
}
