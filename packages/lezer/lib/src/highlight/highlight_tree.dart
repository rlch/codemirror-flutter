/// Tree highlighting functionality.
///
/// This module provides [highlightTree] for applying syntax highlighting
/// to a syntax tree.
library;

import '../common/node_prop.dart';
import '../common/syntax_node.dart';
import '../common/tree.dart';
import '../common/tree_cursor.dart';
import 'highlighter.dart';
import 'style_tags.dart';
import 'tag.dart';

/// Highlight the given tree with the given highlighter.
///
/// Often, the higher-level [highlightCode] function is easier to use.
void highlightTree(
  Tree tree,
  Object /* Highlighter | List<Highlighter> */ highlighter,
  void Function(int from, int to, String classes) putStyle, {
  int from = 0,
  int? to,
}) {
  final toPos = to ?? tree.length;
  final highlighters =
      highlighter is List<Highlighter> ? highlighter : [highlighter as Highlighter];

  final builder = _HighlightBuilder(from, highlighters, putStyle);
  builder.highlightRange(tree.cursor(), from, toPos, '', highlighters);
  builder.flush(toPos);
}

/// Highlight code and call putText for every piece of text.
void highlightCode(
  String code,
  Tree tree,
  Object /* Highlighter | List<Highlighter> */ highlighter,
  void Function(String code, String classes) putText,
  void Function() putBreak, {
  int from = 0,
  int? to,
}) {
  final toPos = to ?? code.length;
  var pos = from;

  void writeTo(int p, String classes) {
    if (p <= pos) return;
    final text = code.substring(pos, p);
    var i = 0;
    while (true) {
      final nextBreak = text.indexOf('\n', i);
      final upto = nextBreak < 0 ? text.length : nextBreak;
      if (upto > i) putText(text.substring(i, upto), classes);
      if (nextBreak < 0) break;
      putBreak();
      i = nextBreak + 1;
    }
    pos = p;
  }

  highlightTree(tree, highlighter, (from, to, classes) {
    writeTo(from, '');
    writeTo(to, classes);
  }, from: from, to: toPos);
  writeTo(toPos, '');
}

/// Helper class for building highlighted spans.
class _HighlightBuilder {
  String _class = '';
  int at;
  final List<Highlighter> highlighters;
  final void Function(int from, int to, String cls) span;

  _HighlightBuilder(this.at, this.highlighters, this.span);

  void startSpan(int at, String cls) {
    if (cls != _class) {
      flush(at);
      if (at > this.at) this.at = at;
      _class = cls;
    }
  }

  void flush(int to) {
    if (to > at && _class.isNotEmpty) span(at, to, _class);
  }

  void highlightRange(
    TreeCursor cursor,
    int from,
    int to,
    String inheritedClass,
    List<Highlighter> highlighters,
  ) {
    final type = cursor.type;
    final start = cursor.from;
    final end = cursor.to;

    if (start >= to || end <= from) return;

    // Filter highlighters by scope for top nodes
    if (type.isTop) {
      highlighters =
          highlighters.where((h) => h.scope == null || h.scope!(type)).toList();
    }

    var cls = inheritedClass;
    final rule = _getStyleTags(cursor);
    if (rule != null) {
      final tagCls = _highlightTags(highlighters, rule.tags);
      if (tagCls != null) {
        if (cls.isNotEmpty) cls += ' ';
        cls += tagCls;
        if (rule.inherit) {
          inheritedClass += (inheritedClass.isNotEmpty ? ' ' : '') + tagCls;
        }
      }
    }

    startSpan(from > start ? from : start, cls);
    if (rule?.opaque == true) return;

    // Handle mounted trees with overlays
    final mounted = cursor.tree != null ? MountedTree.get(cursor.tree!) : null;
    if (mounted != null && mounted.overlay != null) {
      _highlightMounted(cursor, mounted, from, to, inheritedClass, highlighters, cls);
    } else if (cursor.firstChild()) {
      if (mounted != null) inheritedClass = '';
      do {
        if (cursor.to <= from) continue;
        if (cursor.from >= to) break;
        highlightRange(cursor, from, to, inheritedClass, highlighters);
        startSpan(to < cursor.to ? to : cursor.to, cls);
      } while (cursor.nextSibling());
      cursor.parent();
    }
  }

  void _highlightMounted(
    TreeCursor cursor,
    MountedTree mounted,
    int from,
    int to,
    String inheritedClass,
    List<Highlighter> highlighters,
    String cls,
  ) {
    final start = cursor.from;
    final end = cursor.to;
    final inner = cursor.node.enter(mounted.overlay![0].from + start, 1);
    if (inner == null) return;

    final innerHighlighters =
        highlighters.where((h) => h.scope == null || h.scope!(mounted.tree.type)).toList();
    final hasChild = cursor.firstChild();

    for (var i = 0, pos = start;;) {
      final next = i < mounted.overlay!.length ? mounted.overlay![i] : null;
      final nextPos = next != null ? next.from + start : end;
      final rangeFrom = from > pos ? from : pos;
      final rangeTo = to < nextPos ? to : nextPos;

      if (rangeFrom < rangeTo && hasChild) {
        while (cursor.from < rangeTo) {
          highlightRange(cursor, rangeFrom, rangeTo, inheritedClass, highlighters);
          startSpan(rangeTo < cursor.to ? rangeTo : cursor.to, cls);
          if (cursor.to >= nextPos || !cursor.nextSibling()) break;
        }
      }

      if (next == null || nextPos > to) break;
      pos = next.to + start;
      if (pos > from) {
        final innerCursor = TreeCursor.fromNode(inner as TreeNode);
        final innerFrom = from > next.from + start ? from : next.from + start;
        final innerTo = to < pos ? to : pos;
        highlightRange(innerCursor, innerFrom, innerTo, '', innerHighlighters);
        startSpan(to < pos ? to : pos, cls);
      }
      i++;
    }

    if (hasChild) cursor.parent();
  }
}

/// Get style tags from a cursor position.
Rule? _getStyleTags(TreeCursor cursor) {
  var rule = cursor.type.prop(ruleNodeProp);
  while (rule != null && rule.context != null && !cursor.matchContext(rule.context!)) {
    rule = rule.next;
  }
  return rule;
}

/// Highlight tags with the given highlighters.
String? _highlightTags(List<Highlighter> highlighters, List<Tag> tags) {
  String? result;
  for (final highlighter in highlighters) {
    final value = highlighter.style(tags);
    if (value != null) {
      result = result != null ? '$result $value' : value;
    }
  }
  return result;
}
