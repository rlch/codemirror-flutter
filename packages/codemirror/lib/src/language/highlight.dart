/// Syntax highlighting for the editor.
///
/// This module provides [HighlightStyle] and [syntaxHighlighting] for
/// applying syntax highlighting to editor content using Lezer's
/// highlighting infrastructure.
library;

import 'package:lezer/lezer.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/range_set.dart';
import '../view/decoration.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import '../view/editor_view.dart';
import 'language.dart';

// ============================================================================
// HighlightStyle
// ============================================================================

/// A highlight style associates CSS styles with highlighting tags.
///
/// Create one using [HighlightStyle.define] and then use it with
/// [syntaxHighlighting] to apply it to an editor.
class HighlightStyle implements Highlighter {
  /// The tag styles used to create this highlight style.
  final List<TagStyle> specs;

  /// Theme type this style is for (dark/light), or null for any.
  final String? themeType;

  final Highlighter _highlighter;

  @override
  final bool Function(NodeType)? scope;

  HighlightStyle._({
    required this.specs,
    required Highlighter highlighter,
    this.scope,
    this.themeType,
  }) : _highlighter = highlighter;

  /// Create a highlighter style that associates the given styles to
  /// the given tags.
  ///
  /// The specs must be [TagStyle] objects that hold a style tag or list of
  /// tags and a CSS class name.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final myStyle = HighlightStyle.define([
  ///   TagStyle(tag: Tags.keyword, className: 'cm-keyword'),
  ///   TagStyle(tag: Tags.comment, className: 'cm-comment'),
  ///   TagStyle(tag: [Tags.string, Tags.regexp], className: 'cm-string'),
  /// ]);
  /// ```
  static HighlightStyle define(
    List<TagStyle> specs, {
    /// By default, highlighters apply to the entire document. You can
    /// scope them to a single language by providing the language
    /// object or a language's top node type here.
    Object? /* Language | NodeType */ scope,
    /// Add a style to _all_ content. Probably only useful in
    /// combination with [scope].
    String? all,
    /// Specify that this highlight style should only be active then
    /// the theme is dark or light. By default, it is active
    /// regardless of theme.
    String? themeType,
  }) {
    final bool Function(NodeType)? scopeFn;
    if (scope is Language) {
      scopeFn = (type) => type.prop(languageDataProp) == scope.data;
    } else if (scope is NodeType) {
      scopeFn = (type) => type == scope;
    } else {
      scopeFn = null;
    }

    final highlighter = tagHighlighter(
      specs,
      scope: scopeFn,
      all: all,
    );

    return HighlightStyle._(
      specs: specs,
      highlighter: highlighter,
      scope: scopeFn,
      themeType: themeType,
    );
  }

  @override
  String? style(List<Tag> tags) => _highlighter.style(tags);
}

// ============================================================================
// TagStyle (re-export from lezer for convenience)
// ============================================================================

// TagStyle is already exported from lezer/highlighter.dart

// ============================================================================
// Highlighting Facets
// ============================================================================

/// Facet for storing highlighters.
final Facet<Highlighter, List<Highlighter>> _highlighterFacet = Facet.define(
  FacetConfig(
    combine: (values) => values.toList(),
  ),
);

/// Facet for the fallback highlighter (used when no others are registered).
final Facet<Highlighter, List<Highlighter>?> _fallbackHighlighter = Facet.define(
  FacetConfig(
    combine: (values) => values.isNotEmpty ? [values[0]] : null,
  ),
);

/// Get the active highlighters for a state.
List<Highlighter>? getHighlighters(EditorState state) {
  final main = state.facet(_highlighterFacet);
  return main.isNotEmpty ? main : state.facet(_fallbackHighlighter);
}

// ============================================================================
// syntaxHighlighting
// ============================================================================

/// Wrap a highlighter in an editor extension that uses it to apply
/// syntax highlighting to the editor content.
///
/// When multiple (non-fallback) styles are provided, the styling
/// applied is the union of the classes they emit.
///
/// ## Example
///
/// ```dart
/// EditorState.create(
///   extensions: [
///     someLanguage(),
///     syntaxHighlighting(myHighlightStyle),
///   ],
/// );
/// ```
Extension syntaxHighlighting(
  Highlighter highlighter, {
  /// When enabled, this marks the highlighter as a fallback, which
  /// only takes effect if no other highlighters are registered.
  bool fallback = false,
}) {
  final ext = <Extension>[
    // Install the tree highlighter plugin and its decoration provider
    treeHighlighter.extension,
  ];

  String? themeType;
  if (highlighter is HighlightStyle) {
    themeType = highlighter.themeType;
  }

  if (fallback) {
    ext.add(_fallbackHighlighter.of(highlighter));
  } else if (themeType != null) {
    // For theme-specific highlighters, we'd need computeN with darkTheme facet
    // For now, just add it directly
    ext.add(_highlighterFacet.of(highlighter));
  } else {
    ext.add(_highlighterFacet.of(highlighter));
  }

  return ExtensionList(ext);
}

// ============================================================================
// highlightingFor
// ============================================================================

/// Returns the CSS classes (if any) that the highlighters active in
/// the state would assign to the given style tags and (optional) language
/// scope.
String? highlightingFor(
  EditorState state,
  List<Tag> tags, [
  NodeType? scope,
]) {
  final highlighters = getHighlighters(state);
  String? result;
  if (highlighters != null) {
    for (final highlighter in highlighters) {
      if (highlighter.scope == null || (scope != null && highlighter.scope!(scope))) {
        final cls = highlighter.style(tags);
        if (cls != null) {
          result = result != null ? '$result $cls' : cls;
        }
      }
    }
  }
  return result;
}

// ============================================================================
// TreeHighlighter
// ============================================================================

/// View plugin that applies syntax highlighting decorations.
class TreeHighlighter extends PluginValue {
  RangeSet<Decoration> decorations;
  int decoratedTo;
  Tree tree;
  final Map<String, Decoration> _markCache = {};
  final EditorViewState _view;

  TreeHighlighter(EditorViewState view)
      : _view = view,
        tree = syntaxTree(view.state),
        decoratedTo = 0,
        decorations = RangeSet.empty() {
    final highlighters = getHighlighters(view.state);
    decorations = _buildDeco(view, highlighters);
    decoratedTo = view.viewState.viewport.to;
  }

  @override
  void update(ViewUpdate update) {
    final newTree = syntaxTree(update.state);
    final highlighters = getHighlighters(update.state);
    final styleChange = highlighters != getHighlighters(update.startState);
    final viewport = _view.viewState.viewport;
    
    // Clamp decoratedTo to the old document length before mapping
    final oldLen = update.changes.length;
    final safeDecoratedTo = decoratedTo.clamp(0, oldLen);
    final decoratedToMapped = update.changes.mapPos(safeDecoratedTo, 1) ?? safeDecoratedTo;

    if (newTree.length < viewport.to &&
        !styleChange &&
        newTree.type == tree.type &&
        decoratedToMapped >= viewport.to) {
      decorations = decorations.map(update.changes);
      decoratedTo = decoratedToMapped;
    } else if (!identical(newTree, tree) || update.viewportChanged || styleChange) {
      tree = newTree;
      decorations = _buildDeco(_view, highlighters);
      decoratedTo = viewport.to;
    }
  }

  RangeSet<Decoration> _buildDeco(
    EditorViewState view,
    List<Highlighter>? highlighters,
  ) {
    if (highlighters == null || highlighters.isEmpty || tree.length == 0) {
      return RangeSet.empty();
    }

    final builder = RangeSetBuilder<Decoration>();
    
    // Build decorations for the entire parsed tree, not just visible ranges.
    // This ensures decorations outside the viewport aren't lost when the tree
    // is rebuilt. The visibleRanges optimization is a performance feature for
    // large documents in browsers, but in Flutter we can afford to decorate
    // the full document since documents are typically smaller and we don't
    // have the same DOM overhead.
    highlightTree(
      tree,
      highlighters,
      (from, to, classes) {
        final mark = _markCache[classes] ??
            (_markCache[classes] = Decoration.mark(
              MarkDecorationSpec(className: classes),
            ));
        builder.add(from, to, mark);
      },
      from: 0,
      to: tree.length,
    );

    return builder.finish();
  }
}

/// The tree highlighter plugin.
final ViewPlugin<TreeHighlighter> treeHighlighter = ViewPlugin.define(
  (view) => TreeHighlighter(view),
  ViewPluginSpec(
    decorations: (plugin) => plugin.decorations,
  ),
);

// ============================================================================
// Default Highlight Styles
// ============================================================================

/// A default highlight style (works well with light themes).
final HighlightStyle defaultHighlightStyle = HighlightStyle.define([
  TagStyle(tag: Tags.meta, className: 'cm-meta'),
  TagStyle(tag: Tags.link, className: 'cm-link'),
  TagStyle(tag: Tags.heading, className: 'cm-heading'),
  TagStyle(tag: Tags.emphasis, className: 'cm-emphasis'),
  TagStyle(tag: Tags.strong, className: 'cm-strong'),
  TagStyle(tag: Tags.strikethrough, className: 'cm-strikethrough'),
  TagStyle(tag: Tags.keyword, className: 'cm-keyword'),
  TagStyle(tag: [Tags.atom, Tags.bool_, Tags.url, Tags.contentSeparator, Tags.labelName], className: 'cm-atom'),
  TagStyle(tag: [Tags.literal, Tags.inserted], className: 'cm-literal'),
  TagStyle(tag: [Tags.string, Tags.deleted], className: 'cm-string'),
  TagStyle(tag: [Tags.regexp, Tags.escape, Tags.special(Tags.string)], className: 'cm-string2'),
  TagStyle(tag: Tags.definition(Tags.variableName), className: 'cm-def'),
  TagStyle(tag: Tags.local(Tags.variableName), className: 'cm-variable-2'),
  TagStyle(tag: [Tags.typeName, Tags.namespace], className: 'cm-type'),
  TagStyle(tag: Tags.className, className: 'cm-class'),
  TagStyle(tag: [Tags.special(Tags.variableName), Tags.macroName], className: 'cm-variable-3'),
  TagStyle(tag: Tags.definition(Tags.propertyName), className: 'cm-property'),
  TagStyle(tag: Tags.comment, className: 'cm-comment'),
  TagStyle(tag: Tags.invalid, className: 'cm-invalid'),
  // Function calls
  TagStyle(tag: Tags.function(Tags.variableName), className: 'cm-function'),
  TagStyle(tag: Tags.function(Tags.propertyName), className: 'cm-function'),
  // Numbers
  TagStyle(tag: Tags.number, className: 'cm-number'),
  // Operators and punctuation
  TagStyle(tag: Tags.operator, className: 'cm-operator'),
  TagStyle(tag: Tags.punctuation, className: 'cm-punctuation'),
  TagStyle(tag: Tags.paren, className: 'cm-paren'),
  TagStyle(tag: Tags.squareBracket, className: 'cm-squareBracket'),
  TagStyle(tag: Tags.brace, className: 'cm-brace'),
  TagStyle(tag: Tags.separator, className: 'cm-separator'),
  // Properties
  TagStyle(tag: Tags.propertyName, className: 'cm-propertyName'),
  // Variables
  TagStyle(tag: Tags.variableName, className: 'cm-variableName'),
  // JSX/HTML tags
  TagStyle(tag: Tags.tagName, className: 'cm-tagName'),
  TagStyle(tag: Tags.angleBracket, className: 'cm-angleBracket'),
  TagStyle(tag: Tags.attributeName, className: 'cm-attributeName'),
  TagStyle(tag: Tags.attributeValue, className: 'cm-attributeValue'),
  TagStyle(tag: Tags.content, className: 'cm-content'),
]);

/// A highlight style for dark themes.
final HighlightStyle darkHighlightStyle = HighlightStyle.define([
  TagStyle(tag: Tags.meta, className: 'cm-meta'),
  TagStyle(tag: Tags.link, className: 'cm-link'),
  TagStyle(tag: Tags.heading, className: 'cm-heading'),
  TagStyle(tag: Tags.emphasis, className: 'cm-emphasis'),
  TagStyle(tag: Tags.strong, className: 'cm-strong'),
  TagStyle(tag: Tags.strikethrough, className: 'cm-strikethrough'),
  TagStyle(tag: Tags.keyword, className: 'cm-keyword'),
  TagStyle(tag: [Tags.atom, Tags.bool_, Tags.url, Tags.contentSeparator, Tags.labelName], className: 'cm-atom'),
  TagStyle(tag: [Tags.literal, Tags.inserted], className: 'cm-literal'),
  TagStyle(tag: [Tags.string, Tags.deleted], className: 'cm-string'),
  TagStyle(tag: [Tags.regexp, Tags.escape, Tags.special(Tags.string)], className: 'cm-string2'),
  TagStyle(tag: Tags.definition(Tags.variableName), className: 'cm-def'),
  TagStyle(tag: Tags.local(Tags.variableName), className: 'cm-variable-2'),
  TagStyle(tag: [Tags.typeName, Tags.namespace], className: 'cm-type'),
  TagStyle(tag: Tags.className, className: 'cm-class'),
  TagStyle(tag: [Tags.special(Tags.variableName), Tags.macroName], className: 'cm-variable-3'),
  TagStyle(tag: Tags.definition(Tags.propertyName), className: 'cm-property'),
  TagStyle(tag: Tags.comment, className: 'cm-comment'),
  TagStyle(tag: Tags.invalid, className: 'cm-invalid'),
  // Function calls
  TagStyle(tag: Tags.function(Tags.variableName), className: 'cm-function'),
  TagStyle(tag: Tags.function(Tags.propertyName), className: 'cm-function'),
  // Numbers
  TagStyle(tag: Tags.number, className: 'cm-number'),
  // Operators and punctuation
  TagStyle(tag: Tags.operator, className: 'cm-operator'),
  TagStyle(tag: Tags.punctuation, className: 'cm-punctuation'),
  TagStyle(tag: Tags.paren, className: 'cm-paren'),
  TagStyle(tag: Tags.squareBracket, className: 'cm-squareBracket'),
  TagStyle(tag: Tags.brace, className: 'cm-brace'),
  TagStyle(tag: Tags.separator, className: 'cm-separator'),
  // Properties
  TagStyle(tag: Tags.propertyName, className: 'cm-propertyName'),
  // Variables
  TagStyle(tag: Tags.variableName, className: 'cm-variableName'),
  // JSX/HTML tags
  TagStyle(tag: Tags.tagName, className: 'cm-tagName'),
  TagStyle(tag: Tags.angleBracket, className: 'cm-angleBracket'),
  TagStyle(tag: Tags.attributeName, className: 'cm-attributeName'),
  TagStyle(tag: Tags.attributeValue, className: 'cm-attributeValue'),
  TagStyle(tag: Tags.content, className: 'cm-content'),
], themeType: 'dark');
