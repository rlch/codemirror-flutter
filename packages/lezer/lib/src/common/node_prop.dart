/// Node properties for associating metadata with syntax nodes.
///
/// This module provides [NodeProp] for typed metadata on node types or trees.
library;

import 'package:meta/meta.dart';

import 'node_type.dart';
import 'tree.dart';

/// Global ID counter for node props.
int _nextPropID = 0;

/// Each [NodeType] or individual [Tree] can have metadata associated
/// with it in props. Instances of this class represent prop names.
class NodeProp<T> {
  /// Unique identifier for this prop.
  @internal
  final int id;

  /// Whether this prop is stored per [NodeType] or per [Tree] node.
  final bool perNode;

  /// Deserialize a value of this prop from a string.
  ///
  /// Used when providing props directly from a grammar file.
  final T Function(String str) deserialize;

  /// Combine function for when multiple values are assigned.
  @internal
  final T Function(T a, T b)? combine;

  /// Create a new node prop type.
  NodeProp({
    T Function(String str)? deserialize,
    T Function(T a, T b)? combine,
    bool perNode = false,
  })  : id = _nextPropID++,
        perNode = perNode,
        deserialize = deserialize ??
            ((_) => throw StateError(
                "This node type doesn't define a deserialize function")),
        combine = combine;

  /// Create a [NodePropSource] that adds this prop to node types
  /// matching the given predicate or match object.
  ///
  /// Takes a [match] object mapping node names/groups to values, or a
  /// function that returns undefined if the node type doesn't get this
  /// prop, and the prop's value if it does.
  NodePropSource add(
      Object /* Map<String, T> | T? Function(NodeType) */ match) {
    if (perNode) {
      throw RangeError("Can't add per-node props to node types");
    }

    final T? Function(NodeType) fn;
    if (match is Map<String, T>) {
      fn = NodeType.match(match);
    } else if (match is T? Function(NodeType)) {
      fn = match;
    } else {
      throw ArgumentError('match must be a Map<String, T> or Function');
    }

    return (type) {
      final result = fn(type);
      return result == null ? null : (this, result);
    };
  }

  /// Prop that describes matching delimiters.
  ///
  /// For opening delimiters, this holds a list of node names for the
  /// node types of closing delimiters that match it.
  static final closedBy = NodeProp<List<String>>(
    deserialize: (str) => str.split(' '),
  );

  /// The inverse of [closedBy].
  ///
  /// Attached to closing delimiters, holding a list of node names of
  /// types of matching opening delimiters.
  static final openedBy = NodeProp<List<String>>(
    deserialize: (str) => str.split(' '),
  );

  /// Used to assign node types to groups.
  ///
  /// For example, all node types that represent an expression could be
  /// tagged with an `"Expression"` group.
  static final group = NodeProp<List<String>>(
    deserialize: (str) => str.split(' '),
  );

  /// Attached to nodes to indicate they should be displayed in a
  /// bidirectional text isolate.
  ///
  /// Generally used for nodes containing arbitrary text, like strings
  /// and comments. Values can be `"rtl"`, `"ltr"`, or `"auto"`.
  static final isolate = NodeProp<String>(
    deserialize: (value) {
      if (value.isNotEmpty &&
          value != 'rtl' &&
          value != 'ltr' &&
          value != 'auto') {
        throw RangeError('Invalid value for isolate: $value');
      }
      return value.isEmpty ? 'auto' : value;
    },
  );

  /// The hash of the context that the node was parsed in, if any.
  ///
  /// Used to limit reuse of contextual nodes.
  static final contextHash = NodeProp<int>(perNode: true);

  /// The distance beyond the end of the node that the tokenizer
  /// looked ahead for any of the tokens inside the node.
  ///
  /// The LR parser only stores this when it is larger than 25.
  static final lookAhead = NodeProp<int>(perNode: true);

  /// Per-node prop used to replace a given node, or part of a node,
  /// with another tree.
  ///
  /// Used to include trees from different languages in mixed-language parsers.
  static final mounted = NodeProp<MountedTree>(perNode: true);

  /// Get a node prop by name.
  ///
  /// Returns null if the name doesn't match any known prop.
  static NodeProp<Object?>? byName(String name) {
    switch (name) {
      case 'closedBy':
        return closedBy;
      case 'openedBy':
        return openedBy;
      case 'group':
        return group;
      case 'isolate':
        return isolate;
      case 'contextHash':
        return contextHash;
      case 'lookAhead':
        return lookAhead;
      case 'mounted':
        return mounted;
      default:
        return null;
    }
  }
}

/// A mounted tree, which can be stored on a tree node to indicate that
/// parts of its content are represented by another tree.
class MountedTree {
  /// The inner tree.
  final Tree tree;

  /// If null, this tree replaces the entire node.
  ///
  /// If not, only the given ranges are considered to be covered by this
  /// tree. This is used for trees that are mixed in a way that isn't
  /// strictly hierarchical.
  final List<({int from, int to})>? overlay;

  /// The parser used to create this subtree.
  final Object parser; // Parser type - forward reference

  const MountedTree(this.tree, this.overlay, this.parser);

  /// Get the mounted tree from a Tree, if any.
  @internal
  static MountedTree? get(Tree? tree) {
    return tree?.props?[NodeProp.mounted.id] as MountedTree?;
  }
}

/// Type returned by [NodeProp.add].
///
/// Describes whether a prop should be added to a given node type in a
/// node set, and what value it should have.
typedef NodePropSource = (NodeProp<Object?>, Object?)? Function(NodeType type);
