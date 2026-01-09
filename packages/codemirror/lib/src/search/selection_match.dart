/// Highlight text that matches the selection.
///
/// This module provides [highlightSelectionMatches], which highlights
/// text matching the current selection throughout the visible document.
library;

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../view/cursor.dart';
import '../view/decoration.dart';
import '../view/editor_view.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import '../view/viewport.dart';

import 'cursor.dart';

// ============================================================================
// Configuration
// ============================================================================

/// Options for [highlightSelectionMatches].
class HighlightSelectionMatchesConfig {
  /// Whether to highlight the word around the cursor when nothing is selected.
  /// Defaults to false.
  final bool highlightWordAroundCursor;

  /// Minimum length of selection before it is highlighted.
  /// Defaults to 1 (always highlight non-cursor selections).
  final int minSelectionLength;

  /// Maximum number of matches to highlight.
  /// Defaults to 100.
  final int maxMatches;

  /// Whether to only highlight whole words.
  final bool wholeWords;

  const HighlightSelectionMatchesConfig({
    this.highlightWordAroundCursor = false,
    this.minSelectionLength = 1,
    this.maxMatches = 100,
    this.wholeWords = false,
  });
}

const _defaultConfig = HighlightSelectionMatchesConfig();

final Facet<HighlightSelectionMatchesConfig, HighlightSelectionMatchesConfig>
    _highlightConfig = Facet.define(
  FacetConfig(
    combine: (configs) {
      if (configs.isEmpty) return _defaultConfig;
      // Combine: use first config's word cursor, take min of limits
      return HighlightSelectionMatchesConfig(
        highlightWordAroundCursor:
            configs.any((c) => c.highlightWordAroundCursor),
        minSelectionLength:
            configs.map((c) => c.minSelectionLength).reduce((a, b) => a < b ? a : b),
        maxMatches: configs.map((c) => c.maxMatches).reduce((a, b) => a < b ? a : b),
        wholeWords: configs.any((c) => c.wholeWords),
      );
    },
  ),
);

// ============================================================================
// Decorations
// ============================================================================

final _matchDeco = Decoration.mark(
  MarkDecorationSpec(className: 'cm-selectionMatch'),
);

final _mainMatchDeco = Decoration.mark(
  MarkDecorationSpec(className: 'cm-selectionMatch cm-selectionMatch-main'),
);

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if there are no word characters at the boundaries of the range.
bool _insideWordBoundaries(
  CharCategory Function(String) check,
  EditorState state,
  int from,
  int to,
) {
  return (from == 0 ||
          check(state.sliceDoc(from - 1, from)) != CharCategory.word) &&
      (to == state.doc.length ||
          check(state.sliceDoc(to, to + 1)) != CharCategory.word);
}

/// Check if the characters at the boundaries are word characters.
bool _insideWord(
  CharCategory Function(String) check,
  EditorState state,
  int from,
  int to,
) {
  return check(state.sliceDoc(from, from + 1)) == CharCategory.word &&
      check(state.sliceDoc(to - 1, to)) == CharCategory.word;
}

// ============================================================================
// View Plugin
// ============================================================================

class _MatchHighlighter extends PluginValue {
  RangeSet<Decoration> decorations = Decoration.none;
  final EditorViewState _view;

  _MatchHighlighter(EditorViewState view) : _view = view {
    decorations = _getDeco(view);
  }

  @override
  void update(ViewUpdate update) {
    if (update.selectionSet || update.docChanged || update.viewportChanged) {
      decorations = _getDeco(_view);
    }
  }

  RangeSet<Decoration> _getDeco(EditorViewState view) {
    final config = view.state.facet(_highlightConfig);
    final state = view.state;
    final sel = state.selection;

    // Only highlight when there's a single selection
    if (sel.ranges.length > 1) return Decoration.none;

    final range = sel.main;
    String query;
    CharCategory Function(String)? check;

    if (range.empty) {
      if (!config.highlightWordAroundCursor) return Decoration.none;
      final word = state.wordAt(range.head);
      if (word == null) return Decoration.none;
      check = state.charCategorizer(range.head);
      query = state.sliceDoc(word.from, word.to);
    } else {
      final len = range.to - range.from;
      if (len < config.minSelectionLength || len > 200) return Decoration.none;
      if (config.wholeWords) {
        query = state.sliceDoc(range.from, range.to);
        check = state.charCategorizer(range.head);
        if (!(_insideWordBoundaries(check, state, range.from, range.to) &&
            _insideWord(check, state, range.from, range.to))) {
          return Decoration.none;
        }
      } else {
        query = state.sliceDoc(range.from, range.to);
        if (query.isEmpty) return Decoration.none;
      }
    }

    final deco = <Range<Decoration>>[];
    for (final part in view.visibleRanges) {
      final cursor = SearchCursor(state.doc, query, from: part.from, to: part.to);
      while (true) {
        final match = cursor.next();
        if (match == null) break;
        final from = match.from;
        final to = match.to;

        if (check == null || _insideWordBoundaries(check, state, from, to)) {
          if (range.empty && from <= range.from && to >= range.to) {
            deco.add(_mainMatchDeco.range(from, to));
          } else if (from >= range.to || to <= range.from) {
            deco.add(_matchDeco.range(from, to));
          }
          if (deco.length > config.maxMatches) return Decoration.none;
        }
      }
    }

    return Decoration.createSet(deco, sort: true);
  }
}

final _matchHighlighter = ViewPlugin.define<_MatchHighlighter>(
  (view) => _MatchHighlighter(view),
  ViewPluginSpec(decorations: (v) => v.decorations),
);

// ============================================================================
// Extension
// ============================================================================

/// Highlight text that matches the current selection.
///
/// Uses the `cm-selectionMatch` CSS class for highlighting. When
/// [HighlightSelectionMatchesConfig.highlightWordAroundCursor] is enabled,
/// the word at the cursor will be highlighted with `cm-selectionMatch-main`.
Extension highlightSelectionMatches([HighlightSelectionMatchesConfig? options]) {
  return ExtensionList([
    _matchHighlighter.extension,
    if (options != null) _highlightConfig.of(options),
  ]);
}

// ============================================================================
// Select Next Occurrence
// ============================================================================

/// Select the word around the cursor.
bool _selectWord(EditorState state, void Function(dynamic) dispatch) {
  final selection = state.selection;
  final newSel = EditorSelection.create(
    selection.ranges.map((range) {
      return state.wordAt(range.head) ?? EditorSelection.cursor(range.head);
    }).toList(),
    selection.mainIndex,
  );
  if (newSel.eq(selection)) return false;
  dispatch(state.update([TransactionSpec(selection: newSel)]));
  return true;
}

/// Find the next occurrence of a query after the last cursor.
({int from, int to})? _findNextOccurrence(EditorState state, String query) {
  final main = state.selection.main;
  final ranges = state.selection.ranges;
  final word = state.wordAt(main.head);
  final fullWord =
      word != null && word.from == main.from && word.to == main.to;

  var cursor = SearchCursor(state.doc, query, from: ranges.last.to);
  var cycled = false;

  while (true) {
    final match = cursor.next();
    if (match == null) {
      if (cycled) return null;
      cursor = SearchCursor(
        state.doc,
        query,
        from: 0,
        to: (ranges.last.from - 1).clamp(0, state.doc.length),
      );
      cycled = true;
      continue;
    }

    if (cycled && ranges.any((r) => r.from == match.from)) {
      continue;
    }

    if (fullWord) {
      final matchWord = state.wordAt(match.from);
      if (matchWord == null ||
          matchWord.from != match.from ||
          matchWord.to != match.to) {
        continue;
      }
    }

    return match;
  }
}

/// Select the next occurrence of the current selection.
///
/// If the selection is empty, expands to select the word around the cursor.
bool selectNextOccurrence(EditorState state, void Function(dynamic) dispatch) {
  final ranges = state.selection.ranges;
  if (ranges.any((sel) => sel.from == sel.to)) {
    return _selectWord(state, dispatch);
  }

  final searchedText = state.sliceDoc(ranges[0].from, ranges[0].to);
  if (state.selection.ranges.any(
    (r) => state.sliceDoc(r.from, r.to) != searchedText,
  )) {
    return false;
  }

  final range = _findNextOccurrence(state, searchedText);
  if (range == null) return false;

  dispatch(state.update([
    TransactionSpec(
      selection:
          state.selection.addRange(EditorSelection.range(range.from, range.to)),
      effects: [EditorView.scrollIntoView.of(ScrollTarget.fromPos(range.to))],
    ),
  ]));
  return true;
}
