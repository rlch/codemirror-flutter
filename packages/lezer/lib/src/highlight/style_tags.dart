/// Style tags for associating highlighting tags with syntax nodes.
///
/// This module provides [styleTags] for mapping node selectors to tags.
library;

import '../common/node_prop.dart';
import 'tag.dart';

/// Style rule modes.
enum RuleMode {
  /// Normal mode - only applies to this node.
  normal,

  /// Opaque mode (!) - stops further matching for child nodes.
  opaque,

  /// Inherit mode (...) - applies to all child nodes.
  inherit,
}

/// A style rule for a node type.
class Rule {
  /// The tags to apply.
  final List<Tag> tags;

  /// The mode of this rule.
  final RuleMode mode;

  /// Context path (parent node names).
  final List<String>? context;

  /// Next rule in chain.
  Rule? next;

  Rule(this.tags, this.mode, this.context);

  /// Whether this rule is opaque.
  bool get opaque => mode == RuleMode.opaque;

  /// Whether this rule inherits to children.
  bool get inherit => mode == RuleMode.inherit;

  /// The depth (context path length) of this rule.
  int get depth => context?.length ?? 0;

  /// Sort rules by depth.
  Rule sort(Rule? other) {
    if (other == null || other.depth < depth) {
      next = other;
      return this;
    }
    other.next = sort(other.next);
    return other;
  }

  /// An empty rule.
  static final empty = Rule([], RuleMode.normal, null);
}

/// The node prop that stores style rules.
final ruleNodeProp = NodeProp<Rule>(
  combine: (a, b) {
    Rule? cur;
    Rule? root;
    Rule? take;
    Rule? aRule = a;
    Rule? bRule = b;

    while (aRule != null || bRule != null) {
      if (aRule == null || (bRule != null && aRule.depth >= bRule.depth)) {
        take = bRule;
        bRule = bRule?.next;
      } else {
        take = aRule;
        aRule = aRule.next;
      }
      if (cur != null &&
          cur.mode == take!.mode &&
          take.context == null &&
          cur.context == null) {
        continue;
      }
      final copy = Rule(take!.tags, take.mode, take.context);
      if (cur != null) {
        cur.next = copy;
      } else {
        root = copy;
      }
      cur = copy;
    }
    return root!;
  },
);

/// Add a set of tags to a language syntax via [NodeSet.extend] or
/// [LRParser.configure].
///
/// The argument object maps node selectors to highlighting tags or arrays
/// of tags.
///
/// Node selectors may hold one or more (space-separated) node paths. Such
/// a path can be a node name, or multiple node names (or `*` wildcards)
/// separated by slash characters, as in `"Block/Declaration/VariableName"`.
///
/// A path can be ended with `/...` to indicate that the tag should also
/// apply to all child nodes. When a path ends in `!`, no further matching
/// happens for the node's child nodes.
///
/// For example:
/// ```dart
/// styleTags({
///   // Style Number and BigNumber nodes
///   'Number BigNumber': tags.number,
///   // Style Escape nodes whose parent is String
///   'String/Escape': tags.escape,
///   // Style anything inside Attributes nodes
///   'Attributes!': tags.meta,
///   // Add a style to all content inside Italic nodes
///   'Italic/...': tags.emphasis,
/// });
/// ```
NodePropSource styleTags(Map<String, Object /* Tag | List<Tag> */> spec) {
  final byName = <String, Rule>{};

  for (final entry in spec.entries) {
    var tagValue = entry.value;
    final List<Tag> tagList;
    if (tagValue is List<Tag>) {
      tagList = tagValue;
    } else {
      tagList = [tagValue as Tag];
    }

    for (final part in entry.key.split(' ')) {
      if (part.isEmpty) continue;

      final pieces = <String>[];
      var mode = RuleMode.normal;
      var rest = part;

      for (var pos = 0;;) {
        if (rest == '...' && pos > 0 && pos + 3 == part.length) {
          mode = RuleMode.inherit;
          break;
        }

        final m = RegExp(r'^"(?:[^"\\]|\\.)*?"|[^\/!]+').firstMatch(rest);
        if (m == null) {
          throw RangeError('Invalid path: $part');
        }

        final match = m.group(0)!;
        if (match == '*') {
          pieces.add('');
        } else if (match.startsWith('"')) {
          // Parse JSON string
          pieces.add(match.substring(1, match.length - 1));
        } else {
          pieces.add(match);
        }

        pos += match.length;
        if (pos == part.length) break;

        final next = part[pos++];
        if (pos == part.length && next == '!') {
          mode = RuleMode.opaque;
          break;
        }
        if (next != '/') {
          throw RangeError('Invalid path: $part');
        }
        rest = part.substring(pos);
      }

      final last = pieces.length - 1;
      final inner = pieces[last];
      if (inner.isEmpty) {
        throw RangeError('Invalid path: $part');
      }

      final rule = Rule(
        tagList,
        mode,
        last > 0 ? pieces.sublist(0, last) : null,
      );

      byName[inner] = rule.sort(byName[inner]);
    }
  }

  return ruleNodeProp.add(byName);
}

/// Match a syntax node's highlight rules.
///
/// If there's a match, return its set of tags, and whether it is opaque
/// or applies to all child nodes.
({List<Tag> tags, bool opaque, bool inherit})? getStyleTags(
  Object /* SyntaxNodeRef */ node,
) {
  // Note: This is a simplified implementation. The full implementation
  // would need the SyntaxNodeRef interface.
  // For now, we return null - the actual implementation will be in
  // highlight_tree.dart
  return null;
}
