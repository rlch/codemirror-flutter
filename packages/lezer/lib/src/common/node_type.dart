/// Node types for syntax tree nodes.
///
/// This module provides [NodeType] which represents the type of a syntax node.
library;

import 'package:meta/meta.dart';

import 'node_prop.dart';

/// Node type flags.
@internal
class NodeFlag {
  NodeFlag._();

  static const int top = 1;
  static const int skipped = 2;
  static const int error = 4;
  static const int anonymous = 8;
}

/// Empty props map.
final Map<int, Object?> _noProps = const {};

/// Each node in a syntax tree has a node type associated with it.
class NodeType {
  /// The name of the node type.
  ///
  /// Not necessarily unique, but if the grammar was written properly,
  /// different node types with the same name within a node set should
  /// play the same semantic role.
  final String name;

  /// The props on this node type, keyed by prop ID.
  @internal
  final Map<int, Object?> props;

  /// The id of this node in its set.
  ///
  /// Corresponds to the term ids used in the parser.
  final int id;

  /// Internal flags.
  @internal
  final int flags;

  /// @internal
  const NodeType(this.name, this.props, this.id, [this.flags = 0]);

  /// Define a node type.
  static NodeType define({
    required int id,
    String? name,
    List<Object>? props,
    bool top = false,
    bool error = false,
    bool skipped = false,
  }) {
    final Map<int, Object?> propsMap =
        props != null && props.isNotEmpty ? {} : _noProps;
    final flags = (top ? NodeFlag.top : 0) |
        (skipped ? NodeFlag.skipped : 0) |
        (error ? NodeFlag.error : 0) |
        (name == null ? NodeFlag.anonymous : 0);

    final type = NodeType(name ?? '', propsMap, id, flags);

    if (props != null) {
      for (final src in props) {
        final (NodeProp<Object?>, Object?)? pair;
        if (src is (NodeProp<Object?>, Object?)) {
          pair = src;
        } else if (src is NodePropSource) {
          pair = src(type);
        } else {
          throw ArgumentError('Invalid prop source: $src');
        }
        if (pair != null) {
          final (prop, value) = pair;
          if (prop.perNode) {
            throw RangeError("Can't store a per-node prop on a node type");
          }
          propsMap[prop.id] = value;
        }
      }
    }

    return type;
  }

  /// Retrieves a node prop for this type.
  ///
  /// Returns `null` if the prop isn't present on this node.
  T? prop<T>(NodeProp<T> prop) => props[prop.id] as T?;

  /// True when this is the top node of a grammar.
  bool get isTop => (flags & NodeFlag.top) > 0;

  /// True when this node is produced by a skip rule.
  bool get isSkipped => (flags & NodeFlag.skipped) > 0;

  /// Indicates whether this is an error node.
  bool get isError => (flags & NodeFlag.error) > 0;

  /// When true, this node type doesn't correspond to a user-declared
  /// named node, for example because it is used to cache repetition.
  bool get isAnonymous => (flags & NodeFlag.anonymous) > 0;

  /// Returns true when this node's name or one of its groups matches
  /// the given string or id.
  bool is_(Object /* String | int */ nameOrId) {
    if (nameOrId is String) {
      if (name == nameOrId) return true;
      final group = prop(NodeProp.group);
      return group != null && group.contains(nameOrId);
    }
    return id == nameOrId;
  }

  /// An empty dummy node type to use when no actual type is available.
  static final none = NodeType('', const {}, 0, NodeFlag.anonymous);

  /// Create a function from node types to arbitrary values by
  /// specifying an object whose property names are node or group names.
  ///
  /// You can put multiple names, separated by spaces, in a single
  /// property name to map multiple node names to a single value.
  static T? Function(NodeType) match<T>(Map<String, T> map) {
    final direct = <String, T>{};
    for (final entry in map.entries) {
      for (final name in entry.key.split(' ')) {
        direct[name] = entry.value;
      }
    }
    return (node) {
      final groups = node.prop(NodeProp.group);
      for (var i = -1; i < (groups?.length ?? 0); i++) {
        final found = direct[i < 0 ? node.name : groups![i]];
        if (found != null) return found;
      }
      return null;
    };
  }

  @override
  String toString() => name.isEmpty ? 'NodeType.none' : 'NodeType($name)';
}
