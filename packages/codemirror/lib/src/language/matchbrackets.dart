/// Bracket matching for CodeMirror.
///
/// This module provides bracket matching functionality that highlights
/// matching brackets when the cursor is positioned near them.
library;

import 'package:lezer/lezer.dart' hide Range;

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/range_set.dart';
import '../state/transaction.dart' as tx show Transaction;
import '../view/decoration.dart';
import '../view/view_plugin.dart';
import '../view/view_update.dart';
import '../view/editor_view.dart';
import 'language.dart';

// ============================================================================
// Configuration
// ============================================================================

/// Configuration options for bracket matching.
class BracketMatchingConfig {
  /// Whether the bracket matching should look at the character after
  /// the cursor when matching (if the one before isn't a bracket).
  /// Defaults to true.
  final bool afterCursor;

  /// The bracket characters to match, as a string of pairs.
  /// Defaults to `"()[]{}"`.
  ///
  /// Note that these are only used as fallback when there is no matching
  /// information in the syntax tree.
  final String brackets;

  /// The maximum distance to scan for matching brackets.
  /// This is only relevant for brackets not encoded in the syntax tree.
  /// Defaults to 10000.
  final int maxScanDistance;

  /// Custom function to render match decorations.
  final List<Range<Decoration>> Function(MatchResult match, EditorState state)? renderMatch;

  const BracketMatchingConfig({
    this.afterCursor = true,
    this.brackets = '()[]{}',
    this.maxScanDistance = 10000,
    this.renderMatch,
  });
}

const _defaultScanDist = 10000;
const _defaultBrackets = '()[]{}';

/// Combine bracket matching configs.
BracketMatchingConfig _combineConfigs(List<BracketMatchingConfig> configs) {
  if (configs.isEmpty) {
    return const BracketMatchingConfig();
  }

  var afterCursor = true;
  var brackets = _defaultBrackets;
  var maxScanDistance = _defaultScanDist;
  List<Range<Decoration>> Function(MatchResult, EditorState)? renderMatch;

  for (final config in configs) {
    afterCursor = config.afterCursor;
    brackets = config.brackets;
    maxScanDistance = config.maxScanDistance;
    renderMatch = config.renderMatch;
  }

  return BracketMatchingConfig(
    afterCursor: afterCursor,
    brackets: brackets,
    maxScanDistance: maxScanDistance,
    renderMatch: renderMatch,
  );
}

// ============================================================================
// Match Result
// ============================================================================

/// The result returned from [matchBrackets].
class MatchResult {
  /// The extent of the bracket token found.
  final ({int from, int to}) start;

  /// The extent of the matched token, if any was found.
  final ({int from, int to})? end;

  /// Whether the tokens match.
  ///
  /// This can be false even when [end] has a value, if that token
  /// doesn't match the opening token.
  final bool matched;

  const MatchResult({
    required this.start,
    this.end,
    required this.matched,
  });
}

// ============================================================================
// Bracket Matching Handle
// ============================================================================

/// When larger syntax nodes, such as HTML tags, are marked as
/// opening/closing, it can be a bit messy to treat the whole node as
/// a matchable bracket.
///
/// This node prop allows you to define, for such a node, a 'handle'—the
/// part of the node that is highlighted, and that the cursor must be on
/// to activate highlighting in the first place.
final NodeProp<SyntaxNode? Function(SyntaxNode node)> bracketMatchingHandle =
    NodeProp<SyntaxNode? Function(SyntaxNode node)>(
  deserialize: (_) => throw UnsupportedError('Cannot deserialize bracketMatchingHandle'),
);

// ============================================================================
// Facet and State Field
// ============================================================================

final Facet<BracketMatchingConfig, BracketMatchingConfig> _bracketMatchingConfig = Facet.define(
  FacetConfig(
    combine: _combineConfigs,
  ),
);

final MarkDecoration _matchingMark = Decoration.mark(
  const MarkDecorationSpec(className: 'cm-matchingBracket'),
);

final MarkDecoration _nonmatchingMark = Decoration.mark(
  const MarkDecorationSpec(className: 'cm-nonmatchingBracket'),
);

List<Range<Decoration>> _defaultRenderMatch(MatchResult match, EditorState state) {
  final decorations = <Range<Decoration>>[];
  final mark = match.matched ? _matchingMark : _nonmatchingMark;
  decorations.add(mark.range(match.start.from, match.start.to));
  if (match.end != null) {
    decorations.add(mark.range(match.end!.from, match.end!.to));
  }
  return decorations;
}

final StateField<RangeSet<Decoration>> _bracketMatchingState = StateField.define(
  StateFieldConfig(
    create: (state) => _computeBracketDecorations(state as EditorState),
    update: (deco, tr) {
      final transaction = tr as tx.Transaction;
      if (!transaction.docChanged && transaction.selection == null) return deco;
      return _computeBracketDecorations(transaction.state as EditorState);
    },
  ),
);

/// Compute bracket matching decorations for the given state.
RangeSet<Decoration> _computeBracketDecorations(EditorState state) {
  final config = state.facet(_bracketMatchingConfig);
  final decorations = <Range<Decoration>>[];

  for (final range in state.selection.ranges) {
    if (!range.empty) continue;

    var match = matchBrackets(state, range.head, -1, config);
    match ??= range.head > 0 ? matchBrackets(state, range.head - 1, 1, config) : null;

    if (match == null && config.afterCursor) {
      match = matchBrackets(state, range.head, 1, config);
      match ??= range.head < state.doc.length
          ? matchBrackets(state, range.head + 1, -1, config)
          : null;
    }

    if (match != null) {
      final render = config.renderMatch ?? _defaultRenderMatch;
      decorations.addAll(render(match, state));
    }
  }

  return RangeSet.of(decorations, true);
}

// ============================================================================
// bracketMatching Extension
// ============================================================================

/// Create an extension that enables bracket matching.
///
/// Whenever the cursor is next to a bracket, that bracket and the one
/// it matches are highlighted. Or, when no matching bracket is found,
/// another highlighting style is used to indicate this.
///
/// ## Example
///
/// ```dart
/// EditorState.create(
///   extensions: [
///     bracketMatching(),
///   ],
/// );
/// ```
Extension bracketMatching([BracketMatchingConfig config = const BracketMatchingConfig()]) {
  return ExtensionList([
    _bracketMatchingConfig.of(config),
    _bracketMatchingState,
    _bracketMatchingDecorations.extension, // Use .extension to include viewPlugin registration
  ]);
}

/// Plugin that provides bracket matching decorations.
final ViewPlugin<_BracketMatchingPlugin> _bracketMatchingDecorations = ViewPlugin.define(
  (view) => _BracketMatchingPlugin(view),
  ViewPluginSpec(
    decorations: (plugin) => plugin.decorations,
  ),
);

class _BracketMatchingPlugin extends PluginValue {
  RangeSet<Decoration> decorations;

  _BracketMatchingPlugin(dynamic view)
      : decorations = (view as EditorViewState).state.field(_bracketMatchingState, false) ?? RangeSet.empty();

  @override
  void update(ViewUpdate update) {
    decorations = update.state.field(_bracketMatchingState, false) ?? RangeSet.empty();
  }
}

// ============================================================================
// matchBrackets Function
// ============================================================================

/// Find the matching bracket for the token at [pos], scanning direction [dir].
///
/// Only the [brackets] and [maxScanDistance] properties are used from
/// [config], if given. Returns null if no bracket was found at [pos],
/// or a [MatchResult] otherwise.
MatchResult? matchBrackets(
  EditorState state,
  int pos,
  int dir, [
  BracketMatchingConfig config = const BracketMatchingConfig(),
]) {
  final maxScanDistance = config.maxScanDistance;
  final brackets = config.brackets;
  final tree = syntaxTree(state);
  final node = tree.resolveInner(pos, dir);

  for (SyntaxNode? cur = node; cur != null; cur = cur.parent) {
    final matches = _matchingNodes(cur.type, dir, brackets);
    if (matches != null && cur.from < cur.to) {
      final handle = _findHandle(cur);
      if (handle != null) {
        final handleFrom = handle.from;
        final handleTo = handle.to;
        if (dir > 0 ? pos >= handleFrom && pos < handleTo : pos > handleFrom && pos <= handleTo) {
          return _matchMarkedBrackets(state, pos, dir, cur, handle, matches, brackets);
        }
      }
    }
  }

  return _matchPlainBrackets(state, pos, dir, tree, node.type, maxScanDistance, brackets);
}

List<String>? _matchingNodes(NodeType type, int dir, String brackets) {
  final byProp = type.prop(dir < 0 ? NodeProp.openedBy : NodeProp.closedBy);
  if (byProp != null) return byProp;

  if (type.name.length == 1) {
    final index = brackets.indexOf(type.name);
    if (index > -1 && index % 2 == (dir < 0 ? 1 : 0)) {
      return [brackets[index + dir]];
    }
  }
  return null;
}

SyntaxNode? _findHandle(SyntaxNode node) {
  final hasHandle = node.type.prop(bracketMatchingHandle);
  if (hasHandle != null) return hasHandle(node);
  return node;
}

MatchResult? _matchMarkedBrackets(
  EditorState state,
  int pos,
  int dir,
  SyntaxNode token,
  SyntaxNode handle,
  List<String> matching,
  String brackets,
) {
  final parent = token.parent;
  final firstToken = (from: handle.from, to: handle.to);
  var depth = 0;
  final cursor = parent?.cursor();

  if (cursor != null && (dir < 0 ? cursor.childBefore(token.from) : cursor.childAfter(token.to))) {
    do {
      if (dir < 0 ? cursor.to <= token.from : cursor.from >= token.to) {
        if (depth == 0 && matching.contains(cursor.type.name) && cursor.from < cursor.to) {
          final endHandle = _findHandle(cursor.node);
          return MatchResult(
            start: firstToken,
            end: endHandle != null ? (from: endHandle.from, to: endHandle.to) : null,
            matched: true,
          );
        } else if (_matchingNodes(cursor.type, dir, brackets) != null) {
          depth++;
        } else if (_matchingNodes(cursor.type, -dir, brackets) != null) {
          if (depth == 0) {
            final endHandle = _findHandle(cursor.node);
            return MatchResult(
              start: firstToken,
              end: endHandle != null && endHandle.from < endHandle.to
                  ? (from: endHandle.from, to: endHandle.to)
                  : null,
              matched: false,
            );
          }
          depth--;
        }
      }
    } while (dir < 0 ? cursor.prevSibling() : cursor.nextSibling());
  }

  return MatchResult(start: firstToken, matched: false);
}

MatchResult? _matchPlainBrackets(
  EditorState state,
  int pos,
  int dir,
  Tree tree,
  NodeType tokenType,
  int maxScanDistance,
  String brackets,
) {
  final startCh = dir < 0 ? state.sliceDoc(pos - 1, pos) : state.sliceDoc(pos, pos + 1);
  final bracket = brackets.indexOf(startCh);
  if (bracket < 0 || (bracket % 2 == 0) != (dir > 0)) return null;

  final startToken = (from: dir < 0 ? pos - 1 : pos, to: dir > 0 ? pos + 1 : pos);
  final iter = state.doc.iterRange(pos, dir > 0 ? state.doc.length : 0);
  var depth = 0;
  var distance = 0;

  while (!iter.done && distance <= maxScanDistance) {
    iter.next();
    final text = iter.value;
    if (dir < 0) distance += text.length;
    final basePos = pos + distance * dir;

    final start = dir > 0 ? 0 : text.length - 1;
    final end = dir > 0 ? text.length : -1;

    for (var i = start; i != end; i += dir) {
      final found = brackets.indexOf(text[i]);
      if (found < 0 || tree.resolveInner(basePos + i, 1).type != tokenType) continue;

      if ((found % 2 == 0) == (dir > 0)) {
        depth++;
      } else if (depth == 1) {
        return MatchResult(
          start: startToken,
          end: (from: basePos + i, to: basePos + i + 1),
          matched: (found >> 1) == (bracket >> 1),
        );
      } else {
        depth--;
      }
    }

    if (dir > 0) distance += text.length;
  }

  return iter.done ? MatchResult(start: startToken, matched: false) : null;
}
