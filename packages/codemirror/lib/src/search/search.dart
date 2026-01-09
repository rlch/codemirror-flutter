/// Search and replace functionality.
///
/// This module provides search/replace functionality including:
/// - [SearchQuery] for defining search parameters
/// - [searchState] field for tracking search state
/// - Commands like [findNext], [findPrevious], [replaceNext], [replaceAll]
/// - Search panel UI via Flutter widgets
library;

import 'package:flutter/material.dart' hide Decoration;
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../text/text.dart' as text_lib show Text;
import '../text/char.dart' show findClusterBreak;
import '../view/cursor.dart';
import '../view/decoration.dart';
import '../view/editor_view.dart';
import '../view/keymap.dart';
import '../view/panel.dart' show Panel, PanelConstructor, PanelTheme, PanelThemeProvider, showPanel;
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import '../view/viewport.dart';

import 'cursor.dart';
import 'regexp.dart';

export 'cursor.dart';
export 'regexp.dart';
export 'selection_match.dart';
export 'goto_line.dart';

// ============================================================================
// Search Configuration
// ============================================================================

/// Configuration options for the search extension.
class SearchConfig {
  /// Whether to position the search panel at the top of the editor.
  /// Defaults to false (bottom).
  final bool top;

  /// Whether to enable case sensitivity by default.
  final bool caseSensitive;

  /// Whether to treat string searches literally by default.
  final bool literal;

  /// Controls whether the default query has by-word matching enabled.
  final bool wholeWord;

  /// Whether to enable regular expression search by default.
  final bool regexp;

  /// Custom panel constructor.
  final Panel Function(EditorViewState view)? createPanel;

  /// Custom scroll-to-match effect.
  final StateEffect<ScrollTarget> Function(SelectionRange range, EditorViewState view)?
      scrollToMatch;

  const SearchConfig({
    this.top = false,
    this.caseSensitive = false,
    this.literal = false,
    this.wholeWord = false,
    this.regexp = false,
    this.createPanel,
    this.scrollToMatch,
  });

  /// Create a default config with any overrides.
  SearchConfig copyWith({
    bool? top,
    bool? caseSensitive,
    bool? literal,
    bool? wholeWord,
    bool? regexp,
    Panel Function(EditorViewState view)? createPanel,
    StateEffect<ScrollTarget> Function(SelectionRange range, EditorViewState view)?
        scrollToMatch,
  }) {
    return SearchConfig(
      top: top ?? this.top,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      literal: literal ?? this.literal,
      wholeWord: wholeWord ?? this.wholeWord,
      regexp: regexp ?? this.regexp,
      createPanel: createPanel ?? this.createPanel,
      scrollToMatch: scrollToMatch ?? this.scrollToMatch,
    );
  }
}

/// Default search configuration.
const _defaultSearchConfig = SearchConfig();

/// Facet for search configuration.
final Facet<SearchConfig, SearchConfig> searchConfigFacet = Facet.define(
  FacetConfig(
    combine: (configs) => configs.isEmpty ? _defaultSearchConfig : configs.first,
  ),
);

// ============================================================================
// Search Query
// ============================================================================

/// A search query defining what to search for.
class SearchQuery {
  /// The search string (or regular expression pattern).
  final String search;

  /// Whether the search is case-sensitive.
  final bool caseSensitive;

  /// When true, escape sequences like \n are treated literally.
  final bool literal;

  /// When true, interpret the search string as a regular expression.
  final bool regexp;

  /// The replacement text.
  final String replace;

  /// Whether to only match whole words.
  final bool wholeWord;

  /// Whether this query is valid and non-empty.
  final bool valid;

  /// The unquoted search string (with escape sequences processed).
  final String unquoted;

  /// Create a search query.
  SearchQuery({
    required this.search,
    this.caseSensitive = false,
    this.literal = false,
    this.regexp = false,
    this.replace = '',
    this.wholeWord = false,
  })  : valid = search.isNotEmpty && (!regexp || validRegExp(search)),
        unquoted = literal
            ? search
            : search.replaceAllMapped(
                RegExp(r'\\([nrt\\])'),
                (m) => m[1] == 'n'
                    ? '\n'
                    : m[1] == 'r'
                        ? '\r'
                        : m[1] == 't'
                            ? '\t'
                            : '\\',
              );

  /// Compare this query with another.
  bool eq(SearchQuery other) {
    return search == other.search &&
        replace == other.replace &&
        caseSensitive == other.caseSensitive &&
        regexp == other.regexp &&
        wholeWord == other.wholeWord;
  }

  /// Create a query type for this query.
  @internal
  QueryType create() => regexp ? RegExpQuery(this) : StringQuery(this);

  /// Get a search cursor for this query.
  ///
  /// Returns a SearchCursor for string queries or RegExpCursor for regexp queries.
  dynamic getCursor(
    Object stateOrText, {
    int from = 0,
    int? to,
  }) {
    text_lib.Text doc;
    EditorState? state;
    if (stateOrText is EditorState) {
      state = stateOrText;
      doc = state.doc;
    } else {
      doc = stateOrText as text_lib.Text;
    }
    to ??= doc.length;

    if (regexp) {
      return _regexpCursor(this, doc, from, to, state);
    } else {
      return _stringCursor(this, doc, from, to, state);
    }
  }

  /// Process replacement text to handle escape sequences.
  String unquote(String text) {
    if (literal) return text;
    return text.replaceAllMapped(
      RegExp(r'\\([nrt\\])'),
      (m) => m[1] == 'n'
          ? '\n'
          : m[1] == 'r'
              ? '\r'
              : m[1] == 't'
                  ? '\t'
                  : '\\',
    );
  }
}

// ============================================================================
// Query Types
// ============================================================================

/// Abstract base for query implementations.
@internal
abstract class QueryType<Result> {
  final SearchQuery spec;
  QueryType(this.spec);

  /// Find the next match after the current selection.
  Result? nextMatch(EditorState state, int curFrom, int curTo);

  /// Find the previous match before the current selection.
  Result? prevMatch(EditorState state, int curFrom, int curTo);

  /// Get the replacement text for a match.
  String getReplacement(Result result);

  /// Find all matches in the document (up to limit).
  List<Result>? matchAll(EditorState state, int limit);

  /// Highlight matches in a range.
  void highlight(
    EditorState state,
    int from,
    int to,
    void Function(int from, int to) add,
  );
}

/// String-based query implementation.
class StringQuery extends QueryType<({int from, int to})> {
  StringQuery(super.spec);

  @override
  ({int from, int to})? nextMatch(EditorState state, int curFrom, int curTo) {
    final cursor = _stringCursor(spec, state.doc, curTo, state.doc.length, state);
    var match = cursor.next();
    if (match == null) {
      final end = (curFrom + spec.unquoted.length).clamp(0, state.doc.length);
      final wrapCursor = _stringCursor(spec, state.doc, 0, end, state);
      match = wrapCursor.nextOverlapping();
    }
    if (match == null ||
        (match.from == curFrom && match.to == curTo)) {
      return null;
    }
    return match;
  }

  ({int from, int to})? _prevMatchInRange(EditorState state, int from, int to) {
    const chunkSize = 10000;
    for (var pos = to;;) {
      final start = (pos - chunkSize - spec.unquoted.length).clamp(from, pos);
      final cursor = _stringCursor(spec, state.doc, start, pos, state);
      ({int from, int to})? range;
      while (true) {
        final match = cursor.nextOverlapping();
        if (match == null) break;
        range = match;
      }
      if (range != null) return range;
      if (start == from) return null;
      pos -= chunkSize;
    }
  }

  @override
  ({int from, int to})? prevMatch(EditorState state, int curFrom, int curTo) {
    var found = _prevMatchInRange(state, 0, curFrom);
    if (found == null) {
      final start = (curTo - spec.unquoted.length).clamp(0, state.doc.length);
      found = _prevMatchInRange(state, start, state.doc.length);
    }
    return found != null && (found.from != curFrom || found.to != curTo)
        ? found
        : null;
  }

  @override
  String getReplacement(({int from, int to}) result) => spec.unquote(spec.replace);

  @override
  List<({int from, int to})>? matchAll(EditorState state, int limit) {
    final cursor = _stringCursor(spec, state.doc, 0, state.doc.length, state);
    final ranges = <({int from, int to})>[];
    while (true) {
      final match = cursor.next();
      if (match == null) break;
      if (ranges.length >= limit) return null;
      ranges.add(match);
    }
    return ranges;
  }

  @override
  void highlight(
    EditorState state,
    int from,
    int to,
    void Function(int from, int to) add,
  ) {
    final cursor = _stringCursor(
      spec,
      state.doc,
      (from - spec.unquoted.length).clamp(0, state.doc.length),
      (to + spec.unquoted.length).clamp(0, state.doc.length),
      state,
    );
    while (true) {
      final match = cursor.next();
      if (match == null) break;
      add(match.from, match.to);
    }
  }
}

/// Regular expression query implementation.
class RegExpQuery extends QueryType<({int from, int to, RegExpMatch match})> {
  RegExpQuery(super.spec);

  @override
  ({int from, int to, RegExpMatch match})? nextMatch(
    EditorState state,
    int curFrom,
    int curTo,
  ) {
    final cursor = _regexpCursor(spec, state.doc, curTo, state.doc.length, state);
    var match = cursor.next();
    if (match == null) {
      final wrapCursor = _regexpCursor(spec, state.doc, 0, curFrom, state);
      match = wrapCursor.next();
    }
    return match;
  }

  ({int from, int to, RegExpMatch match})? _prevMatchInRange(
    EditorState state,
    int from,
    int to,
  ) {
    const chunkSize = 10000;
    for (var size = 1;; size++) {
      final start = (to - size * chunkSize).clamp(from, to);
      final cursor = _regexpCursor(spec, state.doc, start, to, state);
      ({int from, int to, RegExpMatch match})? range;
      while (true) {
        final match = cursor.next();
        if (match == null) break;
        range = match;
      }
      if (range != null && (start == from || range.from > start + 10)) {
        return range;
      }
      if (start == from) return null;
    }
  }

  @override
  ({int from, int to, RegExpMatch match})? prevMatch(
    EditorState state,
    int curFrom,
    int curTo,
  ) {
    return _prevMatchInRange(state, 0, curFrom) ??
        _prevMatchInRange(state, curTo, state.doc.length);
  }

  @override
  String getReplacement(({int from, int to, RegExpMatch match}) result) {
    return spec.unquote(spec.replace).replaceAllMapped(
      RegExp(r'\$([$&]|\d+)'),
      (m) {
        final i = m[1]!;
        if (i == '&') return result.match[0]!;
        if (i == r'$') return r'$';
        // Handle numbered capture groups
        for (var len = i.length; len > 0; len--) {
          final n = int.tryParse(i.substring(0, len));
          if (n != null && n > 0 && n < result.match.groupCount + 1) {
            return (result.match[n] ?? '') + i.substring(len);
          }
        }
        return m[0]!;
      },
    );
  }

  @override
  List<({int from, int to, RegExpMatch match})>? matchAll(
    EditorState state,
    int limit,
  ) {
    final cursor = _regexpCursor(spec, state.doc, 0, state.doc.length, state);
    final ranges = <({int from, int to, RegExpMatch match})>[];
    while (true) {
      final match = cursor.next();
      if (match == null) break;
      if (ranges.length >= limit) return null;
      ranges.add(match);
    }
    return ranges;
  }

  @override
  void highlight(
    EditorState state,
    int from,
    int to,
    void Function(int from, int to) add,
  ) {
    const highlightMargin = 250;
    final cursor = _regexpCursor(
      spec,
      state.doc,
      (from - highlightMargin).clamp(0, state.doc.length),
      (to + highlightMargin).clamp(0, state.doc.length),
      state,
    );
    while (true) {
      final match = cursor.next();
      if (match == null) break;
      add(match.from, match.to);
    }
  }
}

// ============================================================================
// Cursor Factories
// ============================================================================

SearchCursor _stringCursor(
  SearchQuery spec,
  text_lib.Text doc,
  int from,
  int to,
  EditorState? state,
) {
  return SearchCursor(
    doc,
    spec.unquoted,
    from: from,
    to: to,
    normalize: spec.caseSensitive ? null : (x) => x.toLowerCase(),
    test: spec.wholeWord && state != null
        ? _stringWordTest(doc, state.charCategorizer(state.selection.main.head))
        : null,
  );
}

bool Function(int, int, String, int)? _stringWordTest(
  text_lib.Text doc,
  CharCategory Function(String) categorizer,
) {
  return (int from, int to, String buf, int bufPos) {
    if (bufPos > from || bufPos + buf.length < to) {
      bufPos = (from - 2).clamp(0, from);
      buf = doc.sliceString(bufPos, (to + 2).clamp(to, doc.length));
    }
    return (categorizer(_charBefore(buf, from - bufPos)) != CharCategory.word ||
            categorizer(_charAfter(buf, from - bufPos)) != CharCategory.word) &&
        (categorizer(_charAfter(buf, to - bufPos)) != CharCategory.word ||
            categorizer(_charBefore(buf, to - bufPos)) != CharCategory.word);
  };
}

RegExpCursor _regexpCursor(
  SearchQuery spec,
  text_lib.Text doc,
  int from,
  int to,
  EditorState? state,
) {
  return RegExpCursor(
    doc,
    spec.search,
    options: RegExpCursorOptions(
      ignoreCase: !spec.caseSensitive,
      test: spec.wholeWord && state != null
          ? _regexpWordTest(state.charCategorizer(state.selection.main.head))
          : null,
    ),
    from: from,
    to: to,
  );
}

bool Function(int, int, RegExpMatch)? _regexpWordTest(
  CharCategory Function(String) categorizer,
) {
  return (int from, int to, RegExpMatch match) {
    final input = match.input;
    final index = match.start;
    final end = match.end;
    return match[0]!.isEmpty ||
        ((categorizer(_charBefore(input, index)) != CharCategory.word ||
                categorizer(_charAfter(input, index)) != CharCategory.word) &&
            (categorizer(_charAfter(input, end)) != CharCategory.word ||
                categorizer(_charBefore(input, end)) != CharCategory.word));
  };
}

String _charBefore(String str, int index) {
  if (index <= 0) return '';
  final start = findClusterBreak(str, index, false);
  return str.substring(start, index);
}

String _charAfter(String str, int index) {
  if (index >= str.length) return '';
  final end = findClusterBreak(str, index, true);
  return str.substring(index, end);
}

// ============================================================================
// State Effects
// ============================================================================

/// State effect to update the search query.
final StateEffectType<SearchQuery> setSearchQuery = StateEffect.define<SearchQuery>();

/// Internal effect to toggle the search panel.
final StateEffectType<bool> _togglePanel = StateEffect.define<bool>();

// ============================================================================
// Search State
// ============================================================================

/// Internal search state.
class _SearchState {
  final QueryType query;
  final PanelConstructor? panel;

  _SearchState(this.query, this.panel);
}

/// State field tracking search state.
final StateField<_SearchState> searchState = StateField.define(
  StateFieldConfig(
    create: (state) => _SearchState(_defaultQuery(state as EditorState).create(), null),
    update: (value, tr) {
      for (final effect in tr.effects) {
        if (effect.is_(setSearchQuery)) {
          value = _SearchState(
            (effect.value as SearchQuery).create(),
            value.panel,
          );
        } else if (effect.is_(_togglePanel)) {
          value = _SearchState(
            value.query,
            effect.value as bool ? _createSearchPanelWrapper : null,
          );
        }
      }
      return value;
    },
    provide: (f) => showPanel.from(f, (val) => val.panel),
  ),
);

/// Wrapper to match PanelConstructor signature.
Panel _createSearchPanelWrapper(EditorState state) {
  // We need access to the view, but PanelConstructor only gets state.
  // This is a limitation - we'll create a placeholder that gets replaced.
  return _PlaceholderSearchPanel(state);
}

/// Placeholder panel that gets replaced when the actual view is available.
class _PlaceholderSearchPanel extends Panel {
  final EditorState state;
  SearchPanel? _actualPanel;
  
  _PlaceholderSearchPanel(this.state);

  @override
  bool get top => state.facet(searchConfigFacet).top;

  @override
  Widget build(BuildContext context) {
    // Find the view from context - this is a workaround
    final viewState = context.findAncestorStateOfType<EditorViewState>();
    if (viewState != null) {
      // Create the actual panel once and reuse it
      _actualPanel ??= _createActualPanel(viewState);
      return _actualPanel!.build(context);
    }
    return const SizedBox.shrink();
  }
  
  SearchPanel _createActualPanel(EditorViewState viewState) {
    final config = state.facet(searchConfigFacet);
    final customPanel = config.createPanel?.call(viewState);
    if (customPanel is SearchPanel) return customPanel;
    return SearchPanel(viewState);
  }
  
  @override
  void update(ViewUpdate update) {
    _actualPanel?.update(update);
  }
  
  @override
  void destroy() {
    _actualPanel?.destroy();
  }
}

/// Get the current search query from the state.
SearchQuery getSearchQuery(EditorState state) {
  final cur = state.field(searchState, false);
  return cur?.query.spec ?? _defaultQuery(state);
}

/// Check if the search panel is open.
bool searchPanelOpen(EditorState state) {
  return state.field(searchState, false)?.panel != null;
}

SearchQuery _defaultQuery(EditorState state, [SearchQuery? fallback]) {
  final sel = state.selection.main;
  var selText =
      sel.empty || sel.to > sel.from + 100 ? '' : state.sliceDoc(sel.from, sel.to);
  if (fallback != null && selText.isEmpty) return fallback;

  final config = state.facet(searchConfigFacet);
  return SearchQuery(
    search: (fallback?.literal ?? config.literal)
        ? selText
        : selText.replaceAll('\n', r'\n'),
    caseSensitive: fallback?.caseSensitive ?? config.caseSensitive,
    literal: fallback?.literal ?? config.literal,
    regexp: fallback?.regexp ?? config.regexp,
    wholeWord: fallback?.wholeWord ?? config.wholeWord,
  );
}

// ============================================================================
// Search Highlighting
// ============================================================================

final _matchMark = Decoration.mark(
  MarkDecorationSpec(className: 'cm-searchMatch'),
);

final _selectedMatchMark = Decoration.mark(
  MarkDecorationSpec(className: 'cm-searchMatch cm-searchMatch-selected'),
);

/// View plugin for highlighting search matches.
class _SearchHighlighter extends PluginValue {
  RangeSet<Decoration> decorations = Decoration.none;
  final EditorViewState _view;

  _SearchHighlighter(EditorViewState view) : _view = view {
    decorations = _highlight(view);
  }

  @override
  void update(ViewUpdate update) {
    final state = update.state.field(searchState, false);
    final startState = update.startState.field(searchState, false);
    if (state != startState ||
        update.docChanged ||
        update.selectionSet ||
        update.viewportChanged) {
      decorations = _highlight(_view);
    }
  }

  RangeSet<Decoration> _highlight(EditorViewState view) {
    final state = view.state.field(searchState, false);
    if (state == null || state.panel == null || !state.query.spec.valid) {
      return Decoration.none;
    }

    final builder = RangeSetBuilder<Decoration>();
    final ranges = view.visibleRanges;

    for (var i = 0; i < ranges.length; i++) {
      var from = ranges[i].from;
      var to = ranges[i].to;

      // Merge adjacent ranges
      while (i < ranges.length - 1 && to > ranges[i + 1].from - 500) {
        to = ranges[++i].to;
      }

      state.query.highlight(view.state, from, to, (matchFrom, matchTo) {
        final selected = view.state.selection.ranges.any(
          (r) => r.from == matchFrom && r.to == matchTo,
        );
        builder.add(
          matchFrom,
          matchTo,
          selected ? _selectedMatchMark : _matchMark,
        );
      });
    }

    return builder.finish();
  }
}

final _searchHighlighter = ViewPlugin.define<_SearchHighlighter>(
  (view) => _SearchHighlighter(view),
  ViewPluginSpec(decorations: (v) => v.decorations),
);

// ============================================================================
// Search Commands
// ============================================================================

/// Helper to create search commands.
bool _searchCommand(
  EditorViewState view,
  bool Function(EditorViewState view, _SearchState state) action,
) {
  final state = view.state.field(searchState, false);
  if (state != null && state.query.spec.valid) {
    return action(view, state);
  }
  return openSearchPanel(view);
}

/// Open the search panel if it isn't already open, and move to the next match.
bool findNext(EditorViewState view) {
  return _searchCommand(view, (v, state) {
    final to = v.state.selection.main.to;
    final next = state.query.nextMatch(v.state, to, to);
    if (next == null) return false;

    final selection = EditorSelection.single(next.from, next.to);
    final config = v.state.facet(searchConfigFacet);
    final scrollEffect = config.scrollToMatch?.call(selection.main, v) ??
        EditorView.scrollIntoView.of(ScrollTarget(selection));

    v.dispatch([
      TransactionSpec(
        selection: selection,
        effects: [scrollEffect],
        userEvent: 'select.search',
      ),
    ]);
    return true;
  });
}

/// Move to the previous match.
bool findPrevious(EditorViewState view) {
  return _searchCommand(view, (v, state) {
    final from = v.state.selection.main.from;
    final prev = state.query.prevMatch(v.state, from, from);
    if (prev == null) return false;

    final selection = EditorSelection.single(prev.from, prev.to);
    final config = v.state.facet(searchConfigFacet);
    final scrollEffect = config.scrollToMatch?.call(selection.main, v) ??
        EditorView.scrollIntoView.of(ScrollTarget(selection));

    v.dispatch([
      TransactionSpec(
        selection: selection,
        effects: [scrollEffect],
        userEvent: 'select.search',
      ),
    ]);
    return true;
  });
}

/// Select all instances of the search query.
bool selectMatches(EditorViewState view) {
  return _searchCommand(view, (v, state) {
    final ranges = state.query.matchAll(v.state, 1000);
    if (ranges == null || ranges.isEmpty) return false;

    v.dispatch([
      TransactionSpec(
        selection: EditorSelection.create(
          ranges.map((r) => EditorSelection.range(r.from, r.to)).toList(),
        ),
        userEvent: 'select.search.matches',
      ),
    ]);
    return true;
  });
}

/// Select all instances of the currently selected text.
bool selectSelectionMatches(
  EditorState state,
  void Function(txn.Transaction) dispatch,
) {
  final sel = state.selection;
  if (sel.ranges.length > 1 || sel.main.empty) return false;

  final from = sel.main.from;
  final to = sel.main.to;
  final searchText = state.sliceDoc(from, to);

  final ranges = <SelectionRange>[];
  var main = 0;

  final cursor = SearchCursor(state.doc, searchText);
  while (true) {
    final match = cursor.next();
    if (match == null) break;
    if (ranges.length > 1000) return false;
    if (match.from == from) main = ranges.length;
    ranges.add(EditorSelection.range(match.from, match.to));
  }

  dispatch(state.update([
    TransactionSpec(
      selection: EditorSelection.create(ranges, main),
      userEvent: 'select.search.matches',
    ),
  ]));
  return true;
}

/// Replace the current match with the replacement text.
bool replaceNext(EditorViewState view) {
  return _searchCommand(view, (v, state) {
    if (v.state.isReadOnly) return false;

    final from = v.state.selection.main.from;
    final to = v.state.selection.main.to;
    var match = state.query.nextMatch(v.state, from, from);
    if (match == null) return false;

    final changes = <Object>[];
    EditorSelection? selection;
    final effects = <StateEffect<dynamic>>[];

    if (match.from == from && match.to == to) {
      final replacement = state.query.getReplacement(match);
      changes.add(ChangeSpec(from: match.from, to: match.to, insert: replacement));
      match = state.query.nextMatch(v.state, match.from, match.to);
    }

    if (match != null) {
      final changeSet = v.state.changes(changes);
      selection = EditorSelection.single(match.from, match.to).map(changeSet);
      final config = v.state.facet(searchConfigFacet);
      final scrollEffect = config.scrollToMatch?.call(selection.main, v) ??
          EditorView.scrollIntoView.of(ScrollTarget(selection));
      effects.add(scrollEffect);
    }

    v.dispatch([
      TransactionSpec(
        changes: changes.isEmpty ? null : changes,
        selection: selection,
        effects: effects.isEmpty ? null : effects,
        userEvent: 'input.replace',
      ),
    ]);
    return true;
  });
}

/// Replace all matches with the replacement text.
bool replaceAll(EditorViewState view) {
  return _searchCommand(view, (v, state) {
    if (v.state.isReadOnly) return false;

    final matches = state.query.matchAll(v.state, 1000000000);
    if (matches == null || matches.isEmpty) return false;

    final changes = matches.map((match) {
      return ChangeSpec(
        from: match.from,
        to: match.to,
        insert: state.query.getReplacement(match),
      );
    }).toList();

    v.dispatch([
      TransactionSpec(
        changes: changes,
        userEvent: 'input.replace.all',
      ),
    ]);
    return true;
  });
}

// ============================================================================
// Panel Commands
// ============================================================================

/// Open the search panel.
bool openSearchPanel(EditorViewState view) {
  final state = view.state.field(searchState, false);
  if (state != null && state.panel != null) {
    // Panel already open - just focus it
    return true;
  }

  final effects = <StateEffect<dynamic>>[_togglePanel.of(true)];
  if (state == null) {
    effects.add(StateEffect.appendConfig.of(searchExtensions));
  }

  view.dispatch([TransactionSpec(effects: effects)]);
  return true;
}

/// Close the search panel.
bool closeSearchPanel(EditorViewState view) {
  final state = view.state.field(searchState, false);
  if (state == null || state.panel == null) return false;

  view.dispatch([
    TransactionSpec(effects: [_togglePanel.of(false)]),
  ]);
  return true;
}

// ============================================================================
// Search Panel Widget
// ============================================================================

/// Default search panel implementation.
class SearchPanel extends Panel {
  final EditorViewState view;
  late SearchQuery query;

  SearchPanel(this.view) {
    final state = view.state.field(searchState, false);
    query = state?.query.spec ?? _defaultQuery(view.state);
  }

  @override
  bool get top => view.state.facet(searchConfigFacet).top;

  @override
  Widget build(BuildContext context) {
    return _SearchPanelWidget(panel: this);
  }

  @override
  void update(ViewUpdate update) {
    for (final tr in update.transactions) {
      for (final effect in tr.effects) {
        if (effect.is_(setSearchQuery)) {
          query = effect.value as SearchQuery;
        }
      }
    }
  }

  void setQuery(SearchQuery newQuery) {
    if (!newQuery.eq(query)) {
      query = newQuery;
      view.dispatch([
        TransactionSpec(effects: [setSearchQuery.of(newQuery)]),
      ]);
    }
  }
}

class _SearchPanelWidget extends StatefulWidget {
  final SearchPanel panel;

  const _SearchPanelWidget({required this.panel});

  @override
  State<_SearchPanelWidget> createState() => _SearchPanelWidgetState();
}

class _SearchPanelWidgetState extends State<_SearchPanelWidget> {
  late TextEditingController _searchController;
  late TextEditingController _replaceController;
  late FocusNode _searchFocus;
  late FocusNode _replaceFocus;
  late bool _caseSensitive;
  late bool _regexp;
  late bool _wholeWord;

  @override
  void initState() {
    super.initState();
    final query = widget.panel.query;
    _searchController = TextEditingController(text: query.search);
    _replaceController = TextEditingController(text: query.replace);
    _searchFocus = FocusNode(onKeyEvent: _handleKeyEvent);
    _replaceFocus = FocusNode(onKeyEvent: _handleKeyEvent);
    _caseSensitive = query.caseSensitive;
    _regexp = query.regexp;
    _wholeWord = query.wholeWord;
    
    // Autofocus the search field after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _replaceController.dispose();
    _searchFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  void _commit() {
    widget.panel.setQuery(SearchQuery(
      search: _searchController.text,
      caseSensitive: _caseSensitive,
      regexp: _regexp,
      wholeWord: _wholeWord,
      replace: _replaceController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = widget.panel.view.state.isReadOnly;
    final theme = PanelThemeProvider.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Find',
                    hintStyle: TextStyle(color: theme.toggleInactiveColor),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    filled: true,
                    fillColor: theme.inputBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: theme.inputBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: theme.inputBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: theme.toggleActiveColor),
                    ),
                  ),
                  style: TextStyle(fontSize: 13, color: theme.textColor),
                  cursorColor: theme.toggleActiveColor,
                  onChanged: (_) => _commit(),
                  onSubmitted: (_) => findNext(widget.panel.view),
                ),
              ),
              const SizedBox(width: 4),
              _IconButton(
                icon: Icons.keyboard_arrow_up,
                tooltip: 'Previous (Shift+Enter)',
                onPressed: () => findPrevious(widget.panel.view),
                theme: theme,
              ),
              _IconButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Next (Enter)',
                onPressed: () => findNext(widget.panel.view),
                theme: theme,
              ),
              _IconButton(
                icon: Icons.select_all,
                tooltip: 'Select all matches',
                onPressed: () => selectMatches(widget.panel.view),
                theme: theme,
              ),
              const SizedBox(width: 8),
              _ToggleButton(
                label: 'Aa',
                tooltip: 'Match case',
                value: _caseSensitive,
                onChanged: (v) {
                  setState(() => _caseSensitive = v);
                  _commit();
                },
                theme: theme,
              ),
              _ToggleButton(
                label: '.*',
                tooltip: 'Regular expression',
                value: _regexp,
                onChanged: (v) {
                  setState(() => _regexp = v);
                  _commit();
                },
                theme: theme,
              ),
              _ToggleButton(
                label: 'W',
                tooltip: 'Whole word',
                value: _wholeWord,
                onChanged: (v) {
                  setState(() => _wholeWord = v);
                  _commit();
                },
                theme: theme,
              ),
              const SizedBox(width: 8),
              _IconButton(
                icon: Icons.close,
                tooltip: 'Close',
                onPressed: () => closeSearchPanel(widget.panel.view),
                theme: theme,
              ),
            ],
          ),
          // Replace row (if not read-only)
          if (!isReadOnly) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceController,
                    focusNode: _replaceFocus,
                    decoration: InputDecoration(
                      hintText: 'Replace',
                      hintStyle: TextStyle(color: theme.toggleInactiveColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: theme.inputBackgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: theme.inputBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: theme.inputBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: theme.toggleActiveColor),
                      ),
                    ),
                    style: TextStyle(fontSize: 13, color: theme.textColor),
                    cursorColor: theme.toggleActiveColor,
                    onChanged: (_) => _commit(),
                    onSubmitted: (_) => replaceNext(widget.panel.view),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => replaceNext(widget.panel.view),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.buttonTextColor,
                    backgroundColor: theme.buttonBackgroundColor,
                  ),
                  child: const Text('Replace'),
                ),
                TextButton(
                  onPressed: () => replaceAll(widget.panel.view),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.buttonTextColor,
                    backgroundColor: theme.buttonBackgroundColor,
                  ),
                  child: const Text('All'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    final isTab = event.logicalKey == LogicalKeyboardKey.tab;
    if (!isTab) return KeyEventResult.ignored;
    
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isReadOnly = widget.panel.view.state.isReadOnly;
    
    if (isReadOnly) {
      // No replace field, keep focus on search
      return KeyEventResult.handled;
    }
    
    if (node == _searchFocus && !isShift) {
      // Tab from search -> replace
      _replaceFocus.requestFocus();
      return KeyEventResult.handled;
    } else if (node == _replaceFocus && isShift) {
      // Shift+Tab from replace -> search
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    } else if (node == _replaceFocus && !isShift) {
      // Tab from replace -> wrap to search
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    } else if (node == _searchFocus && isShift) {
      // Shift+Tab from search -> wrap to replace
      _replaceFocus.requestFocus();
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final PanelTheme theme;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: theme.textColor),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool value;
  final ValueChanged<bool> onChanged;
  final PanelTheme theme;

  const _ToggleButton({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: value
                ? theme.toggleActiveColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value ? theme.toggleActiveColor : theme.toggleInactiveColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: value ? theme.toggleActiveColor : theme.toggleInactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Search Keymap
// ============================================================================

/// Default search keybindings.
List<KeyBinding> get searchKeymap => [
      KeyBinding(
        key: 'Mod-f',
        run: (view) {
          if (view is! EditorViewState) return false;
          return openSearchPanel(view);
        },
        scope: 'editor search-panel',
      ),
      KeyBinding(
        key: 'F3',
        run: (view) {
          if (view is! EditorViewState) return false;
          return findNext(view);
        },
        shift: (view) {
          if (view is! EditorViewState) return false;
          return findPrevious(view);
        },
        scope: 'editor search-panel',
        preventDefault: true,
      ),
      KeyBinding(
        key: 'Mod-g',
        run: (view) {
          if (view is! EditorViewState) return false;
          return findNext(view);
        },
        shift: (view) {
          if (view is! EditorViewState) return false;
          return findPrevious(view);
        },
        scope: 'editor search-panel',
        preventDefault: true,
      ),
      KeyBinding(
        key: 'Escape',
        run: (view) {
          if (view is! EditorViewState) return false;
          return closeSearchPanel(view);
        },
        scope: 'editor search-panel',
      ),
      KeyBinding(
        key: 'Mod-Shift-l',
        run: (view) {
          if (view is! EditorViewState) return false;
          return selectSelectionMatches(
            view.state,
            (tr) {
              // The callback receives a Transaction, we just dispatch it directly
              view.update([tr]);
            },
          );
        },
      ),
    ];

// ============================================================================
// Search Extension
// ============================================================================

/// Add search functionality to the editor.
Extension search([SearchConfig? config]) {
  return config != null
      ? ExtensionList([searchConfigFacet.of(config), searchExtensions])
      : searchExtensions;
}

/// Core search extensions.
final Extension searchExtensions = ExtensionList([
  searchState,
  Prec.low(_searchHighlighter.extension),
]);
